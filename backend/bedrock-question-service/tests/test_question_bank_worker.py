import json
import os
import unittest
import uuid
from unittest import mock

import lambda_function
import question_bank
from question_bank_test_support import (
    ConditionalFailure,
    FakeQueue,
    OutboxDynamo,
    QuestionBankTestCase,
    _normalized_request,
    _pending_job,
    _stream_job_event,
)


class QuestionBankWorkerTests(QuestionBankTestCase):
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
            mock.patch.object(question_bank, "_consume_worker_quota"),
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
        client.get_item.return_value = {"Item": {"providerAttemptCount": {"N": "2"}}}
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
        terminal.assert_called_once_with(mock.ANY, message, 2)
        terminal_notice.assert_called_once_with("provider_attempt_limit")

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


if __name__ == "__main__":
    unittest.main()
