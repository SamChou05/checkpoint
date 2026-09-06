import json
import os
import unittest
import uuid
from unittest import mock

import lambda_function
import question_bank
import question_generation
from question_bank_test_support import (
    ConditionalFailure,
    FakeQueue,
    OutboxDynamo,
    QuestionBankTestCase,
    _normalized_request,
    _pending_job,
    _stream_job_event,
)


class FailureLedgerDynamo:
    """Minimal stateful DynamoDB fake for the bank/job failure transactions."""

    def __init__(self, *, context_revision="revision-1"):
        self.context_revision = context_revision
        self.meta = {
            "contextRevision": {"S": context_revision},
            "bankID": {"S": "bank"},
            "goalKey": {"S": "goal"},
            "readyCount": {"N": "0"},
            "generatedCount": {"N": "0"},
            "desiredCount": {"N": "5"},
            "lowWatermark": {"N": "0"},
            "failedGenerationJobCount": {"N": "0"},
            "state": {"S": "empty"},
        }
        self.jobs = {}
        self.transactions = []

    def activate_job(self, job_id):
        self.meta["activeJobID"] = {"S": job_id}
        self.meta["state"] = {"S": "queued"}
        self.jobs[job_id] = {
            "status": {"S": "queued"},
            "contextRevision": {"S": self.context_revision},
        }

    def get_item(self, **kwargs):
        sort_key = kwargs["Key"]["sk"]["S"]
        if sort_key == "META":
            return {"Item": self.meta}
        if sort_key.startswith("JOB#"):
            job = self.jobs.get(sort_key.removeprefix("JOB#"))
            return {"Item": job} if job else {}
        return {}

    def transact_write_items(self, **kwargs):
        transaction = kwargs["TransactItems"]
        self.transactions.append(transaction)
        if "Put" in transaction[1]:
            self._apply_refill(transaction)
        else:
            self._apply_terminal_failure(transaction)

    def _apply_refill(self, transaction):
        bank_update = transaction[0]["Update"]
        job = transaction[1]["Put"]["Item"]
        values = bank_update["ExpressionAttributeValues"]
        if self.meta.get("activeJobID") or self.meta.get("generationBlockedReason"):
            raise ConditionalFailure()
        if self.meta["contextRevision"] != values[":revision"]:
            raise ConditionalFailure()
        self.meta["activeJobID"] = values[":job"]
        self.meta["state"] = values[":queued"]
        self.meta["updatedAt"] = values[":now"]
        self.meta["expiresAt"] = values[":ttl"]
        self.jobs[job["jobID"]["S"]] = job

    def _apply_terminal_failure(self, transaction):
        job_update = transaction[0]["Update"]
        bank_update = transaction[1]["Update"]
        job_id = job_update["Key"]["sk"]["S"].removeprefix("JOB#")
        job = self.jobs[job_id]
        job_values = job_update["ExpressionAttributeValues"]
        bank_values = bank_update["ExpressionAttributeValues"]
        if job["status"]["S"] not in {"queued", "processing"}:
            raise ConditionalFailure()
        if self.meta.get("activeJobID") != bank_values[":job"]:
            raise ConditionalFailure()
        if self.meta["contextRevision"] != bank_values[":revision"]:
            raise ConditionalFailure()
        observed = int(bank_values[":observedFailedCount"]["N"])
        actual = int(self.meta.get("failedGenerationJobCount", {"N": "0"})["N"])
        if observed != actual or self.meta.get("generationBlockedReason"):
            raise ConditionalFailure()

        job["status"] = job_values[":failed"]
        job["failedAt"] = job_values[":now"]
        job["failureReceiveCount"] = job_values[":receives"]
        self.meta["failedGenerationJobCount"] = bank_values[":failedCount"]
        self.meta["updatedAt"] = bank_values[":now"]
        self.meta.pop("activeJobID", None)
        if ":reason" in bank_values:
            self.meta["state"] = bank_values[":blocked"]
            self.meta["generationBlockedReason"] = bank_values[":reason"]
            self.meta["generationBlockedAt"] = bank_values[":now"]
            self.meta.pop("refillAfter", None)
        else:
            self.meta["state"] = bank_values[":failed"]
            self.meta["refillAfter"] = bank_values[":retry"]


class QuestionBankWorkerTests(QuestionBankTestCase):
    def test_worker_feedback_uses_the_thirty_most_recent_questions(self):
        client = mock.Mock()
        client.update_item.return_value = {"Attributes": {"generationPass": {"N": "0"}}}
        bank_pk = "BANK#owner#bank"
        revision = "revision-1"
        meta = {
            "contextRevision": {"S": revision},
            "goalKey": {"S": "goal"},
            "bankID": {"S": "bank"},
            "readyCount": {"N": "35"},
            "generatedCount": {"N": "35"},
            "desiredCount": {"N": "40"},
            "lowWatermark": {"N": "0"},
            "generationRequest": {"S": json.dumps(_normalized_request())},
            "activeJobID": {"S": "job-1"},
        }
        pointer = {"currentBankID": {"S": "bank"}}
        history = []
        for index in range(1, 36):
            remote_id = str(uuid.UUID(int=index))
            question = {
                "remoteID": remote_id,
                "prompt": f"Historical prompt {index}: what follows?",
                "expectedAnswer": f"Historical answer {index}.",
                "choices": [
                    f"Historical answer {index}.",
                    f"Distractor B {index}",
                    f"Distractor C {index}",
                    f"Distractor D {index}",
                ],
                "explanation": f"Historical explanation {index}.",
                "topic": "Reasoning",
                "difficulty": 3,
                "format": "Multiple Choice",
            }
            history.append(
                {
                    "pk": {"S": bank_pk},
                    "sk": {"S": f"QUESTION#{remote_id}"},
                    "remoteID": {"S": remote_id},
                    "state": {"S": "claimed"},
                    "createdAt": {"N": str(index)},
                    "questionJSON": {"S": json.dumps(question)},
                }
            )
        history.reverse()
        captured_requests = []

        def generate(request, reserve_provider_call):
            captured_requests.append(request)
            reserve_provider_call()
            reserve_provider_call()
            return [
                {
                    "prompt": "A fresh prompt asks what follows?",
                    "expectedAnswer": "The fresh answer.",
                    "choices": ["The fresh answer.", "B", "C", "D"],
                    "explanation": "The new evidence supports it.",
                    "topic": "Reasoning",
                    "difficulty": 3,
                    "format": "Multiple Choice",
                }
            ]

        with (
            mock.patch.object(
                question_bank,
                "_get_item",
                side_effect=[meta, pointer, meta],
            ),
            mock.patch.object(
                question_bank,
                "_query_question_history",
                return_value=history,
            ),
            mock.patch.object(
                question_bank, "_reserve_provider_attempt", return_value=True
            ) as reserve,
            mock.patch.object(question_bank, "_commit_generated_questions"),
            mock.patch.object(question_bank, "_ensure_refill"),
        ):
            question_bank._process_job(  # noqa: SLF001
                {
                    "bankPK": bank_pk,
                    "jobID": "job-1",
                    "contextRevision": revision,
                },
                generate,
                client,
                FakeQueue(),
            )

        self.assertEqual(len(captured_requests), 1)
        request = captured_requests[0]
        self.assertEqual(
            request["existingPrompts"],
            [f"Historical prompt {index}: what follows?" for index in range(6, 36)],
        )
        self.assertEqual(
            [item["prompt"] for item in request["existingQuestionCoverage"]],
            request["existingPrompts"],
        )
        self.assertEqual(reserve.call_count, 2)

    def test_worker_failure_preserves_original_sqs_delivery_boundary(self):
        class CaptureDynamo:
            def __init__(self):
                self.transaction = None

            def transact_write_items(self, **kwargs):
                self.transaction = kwargs["TransactItems"]

        dynamo = CaptureDynamo()
        question_bank._reset_job_for_retry(  # noqa: SLF001
            dynamo,
            "question-banks",
            {"pk": {"S": "BANK#owner#bank"}, "sk": {"S": "META"}},
            {"pk": {"S": "BANK#owner#bank"}, "sk": {"S": "JOB#job-1"}},
            "lease-token",
        )
        job_update = dynamo.transaction[0]["Update"]
        self.assertNotIn("enqueueStatus", job_update["UpdateExpression"])
        self.assertNotIn("enqueueLeaseUntil", job_update["UpdateExpression"])
        self.assertEqual(
            job_update["ExpressionAttributeValues"][":queued"],
            {"S": "queued"},
        )
        bank_update = dynamo.transaction[1]["Update"]
        self.assertNotIn("failedGenerationJobCount", bank_update["UpdateExpression"])

    def test_ensure_does_not_redeliver_a_processing_job_after_lease_expiry(self):
        client = mock.Mock()
        meta = {
            "readyCount": {"N": "0"},
            "generatedCount": {"N": "0"},
            "desiredCount": {"N": "40"},
            "lowWatermark": {"N": "10"},
            "activeJobID": {"S": "job-1"},
        }
        processing = {
            "status": {"S": "processing"},
            "leaseUntil": {"N": "1"},
            "enqueueStatus": {"S": "sent"},
        }
        with (
            mock.patch.object(question_bank, "_get_item", return_value=processing),
            mock.patch.object(question_bank, "_deliver_job") as delivery,
        ):
            scheduled = question_bank._ensure_refill(  # noqa: SLF001
                client,
                FakeQueue(),
                "question-banks",
                "https://sqs.example/question-banks",
                {"pk": {"S": "BANK#owner#bank"}, "sk": {"S": "META"}},
                {"pk": {"S": "OWNER#owner"}, "sk": {"S": "GOAL#goal"}},
                meta,
                100,
            )
        self.assertFalse(scheduled)
        delivery.assert_not_called()
        client.update_item.assert_not_called()

    def test_completed_job_replay_repairs_a_missing_refill_chain(self):
        client = mock.Mock()
        client.update_item.side_effect = ConditionalFailure()
        generator = mock.Mock()
        bank_pk = "BANK#owner#bank"
        revision = "revision-1"
        job = {"status": {"S": "complete"}}
        meta = {
            "contextRevision": {"S": revision},
            "goalKey": {"S": "goal"},
            "bankID": {"S": "bank"},
            "readyCount": {"N": "20"},
            "generatedCount": {"N": "20"},
            "desiredCount": {"N": "40"},
            "lowWatermark": {"N": "0"},
        }
        pointer = {"currentBankID": {"S": "bank"}}

        with (
            mock.patch.object(
                question_bank,
                "_get_item",
                side_effect=[job, meta, pointer],
            ),
            mock.patch.object(question_bank, "_ensure_refill") as refill,
        ):
            question_bank._process_job(  # noqa: SLF001
                {
                    "bankPK": bank_pk,
                    "jobID": "job-1",
                    "contextRevision": revision,
                },
                generator,
                client,
                FakeQueue(),
            )

        generator.assert_not_called()
        refill.assert_called_once()

    def test_safety_intervention_blocks_only_the_current_bank_context(self):
        client = mock.Mock()
        client.update_item.return_value = {"Attributes": {"generationPass": {"N": "0"}}}
        bank_pk = "BANK#owner#bank"
        revision = "revision-1"
        meta = {
            "contextRevision": {"S": revision},
            "goalKey": {"S": "goal"},
            "readyCount": {"N": "0"},
            "generatedCount": {"N": "0"},
            "desiredCount": {"N": "20"},
            "lowWatermark": {"N": "0"},
            "generationRequest": {"S": json.dumps(_normalized_request())},
            "activeJobID": {"S": "job-1"},
        }
        pointer = {"currentBankID": {"S": "bank"}}
        reset = mock.Mock()

        with (
            mock.patch.object(
                question_bank,
                "_get_item",
                side_effect=[meta, pointer],
            ),
            mock.patch.object(
                question_bank, "_query_question_history", return_value=[]
            ),
            mock.patch.object(
                question_bank, "_reserve_provider_attempt", return_value=True
            ),
            mock.patch.object(question_bank, "_reset_job_for_retry", reset),
        ):
            question_bank._process_job(  # noqa: SLF001
                {
                    "bankPK": bank_pk,
                    "jobID": "job-1",
                    "contextRevision": revision,
                },
                mock.Mock(
                    side_effect=question_bank.NonRetryableGenerationError(
                        "safety_intervention"
                    )
                ),
                client,
                FakeQueue(),
            )

        reset.assert_not_called()
        transaction = client.transact_write_items.call_args.kwargs["TransactItems"]
        job_update = transaction[0]["Update"]
        meta_update = transaction[1]["Update"]
        self.assertEqual(
            job_update["ExpressionAttributeValues"][":blocked"],
            {"S": "blocked"},
        )
        self.assertIn("generationBlockedReason", meta_update["UpdateExpression"])
        self.assertIn(
            "REMOVE activeJobID, refillAfter", meta_update["UpdateExpression"]
        )

        blocked_meta = {**meta, "generationBlockedReason": {"S": "safety_intervention"}}
        refill_client = mock.Mock()
        scheduled = question_bank._ensure_refill(  # noqa: SLF001
            refill_client,
            FakeQueue(),
            "question-banks",
            "https://sqs.example/question-banks",
            {"pk": {"S": bank_pk}, "sk": {"S": "META"}},
            {"pk": {"S": "OWNER#owner"}, "sk": {"S": "GOAL#goal"}},
            blocked_meta,
            100,
        )
        self.assertFalse(scheduled)
        self.assertEqual(refill_client.method_calls, [])

    def test_provider_attempt_reservation_caps_duplicate_deliveries(self):
        os.environ["QUESTION_BANK_MAX_RECEIVE_COUNT"] = "2"
        client = mock.Mock()
        client.update_item.side_effect = [{}, {}, ConditionalFailure()]
        client.get_item.return_value = {
            "Item": {
                "providerAttemptCount": {"N": "2"},
                "leaseToken": {"S": "lease-token"},
            }
        }
        job_key = {
            "pk": {"S": "BANK#owner#bank"},
            "sk": {"S": "JOB#job-1"},
        }

        self.assertTrue(
            question_bank._reserve_provider_attempt(  # noqa: SLF001
                client, "question-banks", job_key, "lease-token"
            )
        )
        self.assertTrue(
            question_bank._reserve_provider_attempt(  # noqa: SLF001
                client, "question-banks", job_key, "lease-token"
            )
        )
        self.assertFalse(
            question_bank._reserve_provider_attempt(  # noqa: SLF001
                client, "question-banks", job_key, "lease-token"
            )
        )
        condition = client.update_item.call_args.kwargs["ConditionExpression"]
        self.assertIn("providerAttemptCount < :limit", condition)

    def test_provider_call_reservation_charges_async_daily_quota_atomically(self):
        os.environ["RATE_LIMIT_TABLE_NAME"] = "rate-limits"
        os.environ["MAX_REQUESTS_PER_INSTALL_PER_DAY"] = "40"
        client = mock.Mock()
        job_key = {
            "pk": {"S": "BANK#owner#bank"},
            "sk": {"S": "JOB#job-1"},
        }

        reserved = question_bank._reserve_provider_attempt(  # noqa: SLF001
            client,
            "question-banks",
            job_key,
            "lease-token",
            "owner",
        )

        self.assertTrue(reserved)
        client.update_item.assert_not_called()
        transaction = client.transact_write_items.call_args.kwargs["TransactItems"]
        self.assertEqual(len(transaction), 2)
        provider_update = transaction[0]["Update"]
        quota_update = transaction[1]["Update"]
        self.assertIn("providerAttemptCount", provider_update["UpdateExpression"])
        self.assertEqual(quota_update["TableName"], "rate-limits")
        self.assertIn("ADD #count :one", quota_update["UpdateExpression"])
        self.assertEqual(
            quota_update["ExpressionAttributeValues"][":limit"],
            {"N": "40"},
        )

    def test_provider_call_reservation_reports_exhausted_async_daily_quota(self):
        os.environ["RATE_LIMIT_TABLE_NAME"] = "rate-limits"
        os.environ["MAX_REQUESTS_PER_INSTALL_PER_DAY"] = "2"
        client = mock.Mock()
        client.transact_write_items.side_effect = ConditionalFailure()
        client.get_item.side_effect = [
            {
                "Item": {
                    "providerAttemptCount": {"N": "1"},
                    "leaseToken": {"S": "lease-token"},
                }
            },
            {"Item": {"count": {"N": "2"}}},
        ]

        with self.assertRaises(question_bank.ProviderQuotaLimitError):
            question_bank._reserve_provider_attempt(  # noqa: SLF001
                client,
                "question-banks",
                {
                    "pk": {"S": "BANK#owner#bank"},
                    "sk": {"S": "JOB#job-1"},
                },
                "lease-token",
                "owner",
            )

    def test_provider_budget_reserves_each_converse_invocation(self):
        reservation = mock.Mock(
            side_effect=[None, question_bank.ProviderAttemptLimitError()]
        )
        call_budget = lambda_function.ProviderCallBudget(
            6,
            reserve_call=reservation,
        )
        bedrock = mock.Mock()
        bedrock.converse.return_value = {
            "output": {"message": {"content": [{"text": "{}"}]}},
            "usage": {"inputTokens": 1, "outputTokens": 1},
        }
        metrics = {
            "ProviderCalls": 0,
            "BedrockInputTokens": 0,
            "BedrockOutputTokens": 0,
        }

        result = lambda_function._generate_with_bedrock(  # noqa: SLF001
            {},
            bedrock,
            "amazon.nova-lite-v1:0",
            user_prompt="Generate one question.",
            system_prompt="Return JSON.",
            call_budget=call_budget,
            request_metrics=metrics,
        )
        with self.assertRaises(question_bank.ProviderAttemptLimitError):
            lambda_function._generate_with_bedrock(  # noqa: SLF001
                {},
                bedrock,
                "amazon.nova-lite-v1:0",
                user_prompt="Generate one question.",
                system_prompt="Return JSON.",
                call_budget=call_budget,
                request_metrics=metrics,
            )

        self.assertEqual(result, "{}")
        self.assertEqual(reservation.call_count, 2)
        self.assertEqual(bedrock.converse.call_count, 1)
        self.assertEqual(call_budget.calls, 1)
        self.assertEqual(metrics["ProviderCalls"], 1)

    def test_durable_provider_limit_is_not_hidden_by_partial_topoff(self):
        request = _normalized_request()
        request["targetCount"] = 2
        accepted = {
            "prompt": "A fresh prompt asks which conclusion follows?",
            "expectedAnswer": "The supported conclusion.",
            "choices": ["The supported conclusion.", "B", "C", "D"],
            "explanation": "The stated evidence supports it.",
            "topic": "Reasoning",
            "difficulty": 3,
            "format": "Multiple Choice",
        }

        with (
            mock.patch.object(
                question_generation,
                "_generate_provider_payload",
                side_effect=[
                    {"questions": [accepted]},
                    question_bank.ProviderAttemptLimitError(),
                ],
            ),
            mock.patch.object(
                question_generation,
                "_sanitize_questions",
                return_value=[accepted],
            ),
            mock.patch.object(
                question_generation, "verify_questions", return_value=[accepted]
            ),
        ):
            with self.assertRaises(question_bank.ProviderAttemptLimitError):
                lambda_function._generate_sanitized_questions(  # noqa: SLF001
                    request,
                    mock.Mock(),
                )

    def test_async_quota_exhaustion_delays_bank_without_retrying_job(self):
        client = mock.Mock()
        bank_pk = "BANK#owner#bank"
        revision = "revision-1"
        meta = {
            "contextRevision": {"S": revision},
            "goalKey": {"S": "goal"},
            "bankID": {"S": "bank"},
            "readyCount": {"N": "0"},
            "generatedCount": {"N": "0"},
            "desiredCount": {"N": "5"},
            "lowWatermark": {"N": "0"},
            "generationRequest": {"S": json.dumps(_normalized_request())},
            "activeJobID": {"S": "job-1"},
        }
        pointer = {"currentBankID": {"S": "bank"}}

        with (
            mock.patch.object(
                question_bank,
                "_get_item",
                side_effect=[meta, pointer],
            ),
            mock.patch.object(
                question_bank, "_query_question_history", return_value=[]
            ),
            mock.patch.object(
                question_bank,
                "_reserve_provider_attempt",
                side_effect=question_bank.ProviderQuotaLimitError,
            ),
            mock.patch.object(
                question_bank, "_mark_rate_limited", return_value=True
            ) as mark_rate_limited,
            mock.patch.object(question_bank, "_reset_job_for_retry") as reset,
        ):
            question_bank._process_job(  # noqa: SLF001
                {
                    "bankPK": bank_pk,
                    "jobID": "job-1",
                    "contextRevision": revision,
                },
                lambda _request, reserve_provider_call: reserve_provider_call(),
                client,
                FakeQueue(),
            )

        mark_rate_limited.assert_called_once()
        reset.assert_not_called()

    def test_provider_attempt_exhaustion_terminally_acks_the_message(self):
        os.environ["QUESTION_BANK_MAX_RECEIVE_COUNT"] = "2"
        message = {
            "bankPK": "BANK#owner#bank",
            "jobID": "job-1",
            "contextRevision": "revision-1",
        }
        event = {
            "Records": [
                {
                    "messageId": "duplicate",
                    "body": json.dumps(message),
                    "attributes": {"ApproximateReceiveCount": "1"},
                }
            ]
        }
        terminal_notice = mock.Mock()
        with (
            mock.patch.object(
                question_bank,
                "_process_job",
                side_effect=question_bank.ProviderAttemptLimitError,
            ),
            mock.patch.object(question_bank, "_mark_job_terminal_failure") as terminal,
        ):
            result = question_bank.handle_worker_event(
                event,
                object(),
                lambda _: [],
                dynamodb_client=object(),
                sqs_client=object(),
                on_terminal_failure=terminal_notice,
            )

        self.assertEqual(result, {"batchItemFailures": []})
        terminal.assert_called_once_with(mock.ANY, message, 1)
        terminal_notice.assert_called_once_with("provider_attempt_limit")

    def test_three_exhausted_jobs_block_one_bank_context_without_resetting_on_refill(
        self,
    ):
        os.environ["QUESTION_BANK_MAX_FAILED_GENERATION_JOBS"] = "3"
        os.environ["QUESTION_BANK_FAILURE_COOLDOWN_SECONDS"] = "600"
        dynamo = FailureLedgerDynamo()
        bank_key = {
            "pk": {"S": "BANK#owner#bank"},
            "sk": {"S": "META"},
        }
        pointer_key = {
            "pk": {"S": "OWNER#owner"},
            "sk": {"S": "GOAL#goal"},
        }
        dynamo.activate_job("job-1")

        job_id = "job-1"
        for failure_count in range(1, 4):
            message = {
                "bankPK": "BANK#owner#bank",
                "jobID": job_id,
                "contextRevision": "revision-1",
            }
            now = 1_700_000_000 + failure_count * 1_000
            with mock.patch.object(question_bank.time, "time", return_value=now):
                question_bank._mark_job_terminal_failure(  # noqa: SLF001
                    dynamo,
                    message,
                    5,
                )

            self.assertEqual(
                dynamo.meta["failedGenerationJobCount"],
                {"N": str(failure_count)},
            )

            transaction_count = len(dynamo.transactions)
            question_bank._mark_job_terminal_failure(  # noqa: SLF001
                dynamo,
                message,
                5,
            )
            self.assertEqual(len(dynamo.transactions), transaction_count)
            self.assertEqual(
                dynamo.meta["failedGenerationJobCount"],
                {"N": str(failure_count)},
            )

            if failure_count < 3:
                self.assertEqual(dynamo.meta["state"], {"S": "failed"})
                self.assertNotIn("generationBlockedReason", dynamo.meta)
                with mock.patch.object(question_bank, "_deliver_job"):
                    scheduled = question_bank._ensure_refill(  # noqa: SLF001
                        dynamo,
                        FakeQueue(),
                        "question-banks",
                        "https://sqs.example/question-banks",
                        bank_key,
                        pointer_key,
                        dynamo.meta,
                        now + 600,
                    )
                self.assertTrue(scheduled)
                self.assertEqual(
                    dynamo.meta["failedGenerationJobCount"],
                    {"N": str(failure_count)},
                )
                job_id = dynamo.meta["activeJobID"]["S"]

        self.assertEqual(dynamo.meta["state"], {"S": "blocked"})
        self.assertEqual(
            dynamo.meta["generationBlockedReason"],
            {"S": "provider_failure_limit"},
        )
        self.assertNotIn("activeJobID", dynamo.meta)
        self.assertNotIn("refillAfter", dynamo.meta)
        bank_response = question_bank._bank_response(dynamo.meta)  # noqa: SLF001
        self.assertEqual(bank_response["status"], "empty")
        self.assertEqual(
            bank_response["generationBlockedReason"],
            "provider_failure_limit",
        )
        ordinary_empty_meta = dict(dynamo.meta)
        ordinary_empty_meta.pop("generationBlockedReason")
        self.assertNotIn(
            "generationBlockedReason",
            question_bank._bank_response(ordinary_empty_meta),  # noqa: SLF001
        )

        transaction_count = len(dynamo.transactions)
        scheduled = question_bank._ensure_refill(  # noqa: SLF001
            dynamo,
            FakeQueue(),
            "question-banks",
            "https://sqs.example/question-banks",
            bank_key,
            pointer_key,
            dynamo.meta,
            1_800_000_000,
        )
        self.assertFalse(scheduled)
        self.assertEqual(len(dynamo.transactions), transaction_count)

    def test_terminal_failure_from_a_stale_context_does_not_touch_current_bank(self):
        dynamo = FailureLedgerDynamo(context_revision="revision-2")
        dynamo.activate_job("job-current")

        question_bank._mark_job_terminal_failure(  # noqa: SLF001
            dynamo,
            {
                "bankPK": "BANK#owner#bank",
                "jobID": "job-current",
                "contextRevision": "revision-1",
            },
            5,
        )

        self.assertEqual(dynamo.transactions, [])
        self.assertEqual(dynamo.meta["failedGenerationJobCount"], {"N": "0"})
        self.assertEqual(dynamo.jobs["job-current"]["status"], {"S": "queued"})

    def test_first_failure_migrates_a_legacy_bank_without_a_ledger(self):
        dynamo = FailureLedgerDynamo()
        dynamo.meta.pop("failedGenerationJobCount")
        dynamo.activate_job("job-legacy")

        question_bank._mark_job_terminal_failure(  # noqa: SLF001
            dynamo,
            {
                "bankPK": "BANK#owner#bank",
                "jobID": "job-legacy",
                "contextRevision": "revision-1",
            },
            5,
        )

        self.assertEqual(dynamo.meta["failedGenerationJobCount"], {"N": "1"})
        bank_update = dynamo.transactions[0][1]["Update"]
        self.assertIn(
            "attribute_not_exists(failedGenerationJobCount)",
            bank_update["ConditionExpression"],
        )

    def test_worker_maps_safety_intervention_to_non_retryable_generation(self):
        captured = []

        def run_callback(_event, _context, generate_questions, **_kwargs):
            try:
                generate_questions({"targetCount": 1})
            except Exception as error:  # noqa: BLE001 - asserting callback contract
                captured.append(error)
            return {"batchItemFailures": []}

        with (
            mock.patch.object(
                lambda_function,
                "_generate_sanitized_questions",
                side_effect=lambda_function.SafetyInterventionError,
            ),
            mock.patch.object(
                lambda_function.question_bank,
                "handle_worker_event",
                side_effect=run_callback,
            ),
            mock.patch.object(lambda_function, "_emit_request_metrics") as emit_metrics,
        ):
            result = lambda_function.question_bank_worker_handler({}, object())

        self.assertEqual(result, {"batchItemFailures": []})
        self.assertEqual(len(captured), 1)
        self.assertIsInstance(captured[0], question_bank.NonRetryableGenerationError)
        self.assertEqual(captured[0].code, "safety_intervention")
        self.assertEqual(
            emit_metrics.call_args.args[0]["Outcome"],
            "safety_intervention",
        )

    def test_worker_reports_terminal_provider_attempt_exhaustion_in_metrics(self):
        def run_callback(
            _event,
            _context,
            _generate_questions,
            *,
            on_terminal_failure,
            **_kwargs,
        ):
            on_terminal_failure("provider_attempt_limit")
            return {"batchItemFailures": []}

        with (
            mock.patch.object(
                lambda_function.question_bank,
                "handle_worker_event",
                side_effect=run_callback,
            ),
            mock.patch.object(lambda_function, "_emit_request_metrics") as emit_metrics,
        ):
            result = lambda_function.question_bank_worker_handler({}, object())

        self.assertEqual(result, {"batchItemFailures": []})
        metrics = emit_metrics.call_args.args[0]
        self.assertEqual(metrics["StatusCode"], 502)
        self.assertEqual(metrics["Outcome"], "provider_failure")

    def test_duplicate_outbox_record_is_idempotent_after_delivery_is_marked(self):
        job = _pending_job()
        dynamo = OutboxDynamo(job)
        queue = FakeQueue()
        event = _stream_job_event(job)

        first = question_bank.handle_outbox_event(
            event,
            object(),
            dynamodb_client=dynamo,
            sqs_client=queue,
        )
        second = question_bank.handle_outbox_event(
            event,
            object(),
            dynamodb_client=dynamo,
            sqs_client=queue,
        )

        self.assertEqual(first, {"batchItemFailures": []})
        self.assertEqual(second, {"batchItemFailures": []})
        self.assertEqual(len(queue.messages), 1)
        self.assertEqual(job["enqueueStatus"], {"S": "sent"})

    def test_outbox_retries_after_crash_between_send_and_mark(self):
        job = _pending_job()
        dynamo = OutboxDynamo(job, failed_marks=1)
        queue = FakeQueue()
        event = _stream_job_event(job, sequence_number="42")
        with mock.patch.object(question_bank.LOGGER, "exception"):
            first = question_bank.handle_outbox_event(
                event,
                object(),
                dynamodb_client=dynamo,
                sqs_client=queue,
            )
        second = question_bank.handle_outbox_event(
            event,
            object(),
            dynamodb_client=dynamo,
            sqs_client=queue,
        )

        self.assertEqual(
            first,
            {"batchItemFailures": [{"itemIdentifier": "42"}]},
        )
        self.assertEqual(second, {"batchItemFailures": []})
        self.assertEqual(len(queue.messages), 2)
        self.assertEqual(
            queue.messages[0]["MessageBody"], queue.messages[1]["MessageBody"]
        )
        self.assertEqual(job["enqueueStatus"], {"S": "sent"})

    def test_final_poison_receive_marks_job_failed_and_starts_cooldown(self):
        class CaptureDynamo:
            def __init__(self):
                self.transactions = []
                self.meta = {
                    "contextRevision": {"S": "revision-1"},
                    "activeJobID": {"S": "job-1"},
                    "failedGenerationJobCount": {"N": "0"},
                }

            def get_item(self, **kwargs):
                if kwargs["Key"]["sk"] == {"S": "META"}:
                    return {"Item": self.meta}
                return {}

            def transact_write_items(self, **kwargs):
                self.transactions.append(kwargs["TransactItems"])

        os.environ["QUESTION_BANK_MAX_RECEIVE_COUNT"] = "5"
        os.environ["QUESTION_BANK_FAILURE_COOLDOWN_SECONDS"] = "600"
        dynamo = CaptureDynamo()
        message = {
            "bankPK": "BANK#owner#bank",
            "jobID": "job-1",
            "contextRevision": "revision-1",
        }
        event = {
            "Records": [
                {
                    "messageId": "poison",
                    "body": json.dumps(message),
                    "attributes": {"ApproximateReceiveCount": "5"},
                }
            ]
        }
        with (
            mock.patch.object(
                question_bank,
                "_process_job",
                side_effect=RuntimeError("provider unavailable"),
            ),
            mock.patch.object(question_bank.LOGGER, "exception"),
            mock.patch.object(question_bank.time, "time", return_value=1_700_000_000),
        ):
            result = question_bank.handle_worker_event(
                event,
                object(),
                lambda _: [],
                dynamodb_client=dynamo,
                sqs_client=object(),
            )

        self.assertEqual(result, {"batchItemFailures": [{"itemIdentifier": "poison"}]})
        self.assertEqual(len(dynamo.transactions), 1)
        job_update = dynamo.transactions[0][0]["Update"]
        meta_update = dynamo.transactions[0][1]["Update"]
        self.assertEqual(
            job_update["ExpressionAttributeValues"][":failed"], {"S": "failed"}
        )
        self.assertEqual(
            job_update["ExpressionAttributeValues"][":receives"], {"N": "5"}
        )
        self.assertIn("REMOVE activeJobID", meta_update["UpdateExpression"])
        self.assertEqual(
            meta_update["ExpressionAttributeValues"][":failedCount"],
            {"N": "1"},
        )
        self.assertEqual(
            meta_update["ExpressionAttributeValues"][":retry"], {"N": "1700000600"}
        )

    def test_worker_commit_is_conditioned_against_pro_to_finite_downgrade(self):
        class PolicyDynamo:
            def __init__(self):
                self.transaction = None

            def transact_write_items(self, **kwargs):
                self.transaction = kwargs["TransactItems"]
                meta_update = self.transaction[-3]["Update"]
                values = meta_update["ExpressionAttributeValues"]
                latest_policy = {
                    ":observedDesired": {"N": "40"},
                    ":observedLow": {"N": "0"},
                    ":observedReady": {"N": "35"},
                    ":observedGenerated": {"N": "80"},
                }
                if any(values[name] != value for name, value in latest_policy.items()):
                    raise ConditionalFailure()

        dynamo = PolicyDynamo()
        question = {
            "remoteID": str(uuid.UUID(int=99)),
            "prompt": "Which statement follows?",
        }
        with self.assertRaises(ConditionalFailure):
            question_bank._commit_generated_questions(  # noqa: SLF001
                dynamo,
                "question-banks",
                {"pk": {"S": "BANK#owner#bank"}, "sk": {"S": "META"}},
                {"pk": {"S": "BANK#owner#bank"}, "sk": {"S": "JOB#job-1"}},
                {"pk": {"S": "OWNER#owner"}, "sk": {"S": "GOAL#goal"}},
                "bank",
                "revision-1",
                "lease-token",
                [question],
                observed_desired_count=80,
                observed_low_watermark=20,
                observed_ready_count=35,
                observed_generated_count=80,
            )
        condition = dynamo.transaction[-3]["Update"]["ConditionExpression"]
        self.assertIn("desiredCount = :observedDesired", condition)
        self.assertIn("lowWatermark = :observedLow", condition)
        self.assertIn("readyCount <= :observedReady", condition)
        self.assertIn("generatedCount = :observedGenerated", condition)
        self.assertNotIn(
            "failedGenerationJobCount",
            dynamo.transaction[-3]["Update"]["UpdateExpression"],
        )


if __name__ == "__main__":
    unittest.main()
