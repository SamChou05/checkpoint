import copy
import json
import os
import unittest
import uuid
from unittest import mock

import lambda_function
import question_bank


SECRET = "unit-test-question-bank-secret-at-least-32-characters"
INSTALL_ID = "install-123"


class FakeQueue:
    def __init__(self):
        self.messages = []

    def send_message(self, **kwargs):
        self.messages.append(kwargs)
        return {"MessageId": "message-1"}


class ConditionalFailure(RuntimeError):
    response = {"Error": {"Code": "ConditionalCheckFailedException"}}


class OutboxDynamo:
    def __init__(self, job, *, failed_marks=0):
        self.job = job
        self.failed_marks = failed_marks
        self.mark_attempts = 0

    def get_item(self, **kwargs):
        return {"Item": self.job}

    def update_item(self, **kwargs):
        self.mark_attempts += 1
        if self.failed_marks:
            self.failed_marks -= 1
            raise RuntimeError("simulated crash after SQS accepted the message")
        if self.job["status"]["S"] != "queued" or self.job["enqueueStatus"]["S"] == "sent":
            raise ConditionalFailure()
        self.job["enqueueStatus"] = kwargs["ExpressionAttributeValues"][":sent"]
        return {}


class ClaimDynamo:
    def __init__(self, meta, pointer, questions):
        self.meta = meta
        self.pointer = pointer
        self.questions = list(questions)
        self.claims = {}
        self.transactions = []

    def get_item(self, **kwargs):
        key = kwargs["Key"]
        pk = key["pk"]["S"]
        sk = key["sk"]["S"]
        if sk == "META":
            return {"Item": self.meta}
        if pk.startswith("OWNER#"):
            return {"Item": self.pointer}
        if sk.startswith("CLAIM#") and sk in self.claims:
            return {"Item": self.claims[sk]}
        return {}

    def query(self, **kwargs):
        return {"Items": self.questions[: kwargs.get("Limit", len(self.questions))]}

    def transact_write_items(self, **kwargs):
        self.transactions.append(kwargs)
        for operation in kwargs["TransactItems"]:
            if "Delete" in operation:
                sk = operation["Delete"]["Key"]["sk"]["S"]
                self.questions = [item for item in self.questions if item["sk"]["S"] != sk]
            elif "Update" in operation:
                update = operation["Update"]
                sk = update["Key"]["sk"]["S"]
                values = update["ExpressionAttributeValues"]
                if sk == "META" and ":after" in values:
                    self.meta["readyCount"] = values[":after"]
                    self.meta["state"] = values[":state"]
                elif sk.startswith("QUESTION#"):
                    for item in self.questions:
                        if item["sk"]["S"] == sk:
                            item["state"] = values[":claimed"]
            elif "Put" in operation:
                item = operation["Put"]["Item"]
                if item["sk"]["S"].startswith("CLAIM#"):
                    self.claims[item["sk"]["S"]] = item
        return {}


class QuestionBankTests(unittest.TestCase):
    def setUp(self):
        os.environ.update(
            {
                "ALLOW_UNAUTHENTICATED_BACKEND": "true",
                "QUESTION_BANK_TABLE_NAME": "question-banks",
                "QUESTION_BANK_QUEUE_URL": "https://sqs.example/question-banks",
                "QUOTA_HASH_SECRET": SECRET,
            }
        )

    def tearDown(self):
        for key in [
            "ALLOW_UNAUTHENTICATED_BACKEND",
            "QUESTION_BANK_TABLE_NAME",
            "QUESTION_BANK_QUEUE_URL",
            "QUESTION_BANK_TTL_SECONDS",
            "QUESTION_BANK_FAILURE_COOLDOWN_SECONDS",
            "QUESTION_BANK_GENERATION_CHUNK_SIZE",
            "QUESTION_BANK_MAX_RECEIVE_COUNT",
            "QUOTA_HASH_SECRET",
        ]:
            os.environ.pop(key, None)

    def test_ensure_bank_identity_uses_owner_goal_and_explicit_revision(self):
        payload = _ensure_payload()
        normalized = _normalized_request()
        dynamo = object()
        queue = object()
        captured_bank_keys = []

        def update_configuration(
            _client,
            _table,
            bank_key,
            context_revision,
            _normalized,
            desired,
            low,
            _now,
        ):
            captured_bank_keys.append(bank_key["pk"]["S"])
            return _meta(
                bank_key["pk"]["S"],
                bank_key["pk"]["S"].split("#")[2],
                context_revision,
                desired=desired,
                low=low,
                ready=desired,
            )

        with (
            mock.patch.object(question_bank, "_activate_goal_version", return_value=""),
            mock.patch.object(question_bank, "_require_current_bank"),
            mock.patch.object(
                question_bank,
                "_update_bank_configuration",
                side_effect=update_configuration,
            ),
        ):
            first = question_bank.ensure_bank(
                payload,
                _event(),
                lambda _: normalized,
                dynamodb_client=dynamo,
                sqs_client=queue,
            )
            changed_poll = dict(payload)
            changed_poll["existingPrompts"] = ["A newly answered prompt"]
            second = question_bank.ensure_bank(
                changed_poll,
                _event(),
                lambda _: normalized,
                dynamodb_client=dynamo,
                sqs_client=queue,
            )

        self.assertEqual(first["bankID"], second["bankID"])
        self.assertEqual(captured_bank_keys[0], captured_bank_keys[1])
        self.assertNotIn(INSTALL_ID, captured_bank_keys[0])
        changed_revision = dict(payload)
        changed_revision["contextRevision"] = "fedcba9876543210"
        with (
            mock.patch.object(question_bank, "_activate_goal_version", return_value=""),
            mock.patch.object(question_bank, "_require_current_bank"),
            mock.patch.object(
                question_bank,
                "_update_bank_configuration",
                side_effect=update_configuration,
            ),
        ):
            third = question_bank.ensure_bank(
                changed_revision,
                _event(),
                lambda _: normalized,
                dynamodb_client=dynamo,
                sqs_client=queue,
            )
        self.assertNotEqual(first["bankID"], third["bankID"])

    def test_ensure_requires_context_revision_and_caps_server_target(self):
        missing = _ensure_payload()
        missing.pop("contextRevision")
        with self.assertRaises(question_bank.QuestionBankError) as raised:
            question_bank.ensure_bank(
                missing,
                _event(),
                lambda _: _normalized_request(),
                dynamodb_client=object(),
                sqs_client=object(),
            )
        self.assertEqual(raised.exception.status_code, 400)

    def test_generation_chunks_default_to_one_session_and_cap_at_claim_limit(self):
        self.assertEqual(question_bank._generation_chunk_count(), 5)  # noqa: SLF001
        os.environ["QUESTION_BANK_GENERATION_CHUNK_SIZE"] = "12"
        self.assertEqual(question_bank._generation_chunk_count(), 12)  # noqa: SLF001
        os.environ["QUESTION_BANK_GENERATION_CHUNK_SIZE"] = "100"
        self.assertEqual(question_bank._generation_chunk_count(), 20)  # noqa: SLF001

    def test_bank_configuration_condition_locks_weight_map_to_revision(self):
        first_skill = "11111111-1111-4111-8111-111111111111"
        second_skill = "22222222-2222-4222-8222-222222222222"
        normalized = {
            **_normalized_request(),
            "skillMap": {
                "version": 1,
                "skills": [
                    {"id": first_skill, "name": "Core", "objectives": []},
                    {"id": second_skill, "name": "Review", "objectives": []},
                ],
            },
            "desiredSkillAllocation": {first_skill: 9, second_skill: 1},
        }
        client = mock.Mock()
        client.update_item.return_value = {"Attributes": {}}

        question_bank._update_bank_configuration(  # noqa: SLF001
            client,
            "question-banks",
            {"pk": {"S": "BANK#owner#bank"}, "sk": {"S": "META"}},
            "revision-1",
            normalized,
            40,
            10,
            1_700_000_000,
        )

        update = client.update_item.call_args.kwargs
        self.assertIn("skillAllocationKey = :allocation", update["ConditionExpression"])
        self.assertEqual(
            update["ExpressionAttributeValues"][":allocation"],
            {"S": question_bank._skill_allocation_key(normalized)},  # noqa: SLF001
        )

    def test_superseded_revision_can_be_reactivated_after_goal_revert(self):
        client = mock.Mock()
        bank_id = "a" * 64
        bank_key = {"pk": {"S": f"BANK#{'b' * 64}#{bank_id}"}, "sk": {"S": "META"}}
        pointer_key = {"pk": {"S": f"OWNER#{'b' * 64}"}, "sk": {"S": "GOAL#goal"}}
        reusable_meta = {
            **bank_key,
            "state": {"S": "superseded"},
            "contextRevision": {"S": "0123456789abcdef"},
        }
        pointer = {
            **pointer_key,
            "currentBankID": {"S": "c" * 64},
            "contextRevision": {"S": "fedcba9876543210"},
        }

        with mock.patch.object(
            question_bank,
            "_get_item",
            side_effect=[reusable_meta, pointer],
        ):
            previous = question_bank._activate_goal_version(  # noqa: SLF001
                client,
                "question-banks",
                bank_key,
                pointer_key,
                bank_id,
                "0123456789abcdef",
                "goal",
                _normalized_request(),
                40,
                0,
                1_700_000_000,
            )

        self.assertEqual(previous, "c" * 64)
        update = client.update_item.call_args.kwargs
        self.assertEqual(update["ExpressionAttributeValues"][":bank"], {"S": bank_id})
        self.assertNotIn("tombstonedAt", update["UpdateExpression"])

        oversized = _ensure_payload()
        oversized["desiredCount"] = 101
        with self.assertRaises(question_bank.QuestionBankError) as raised:
            question_bank.ensure_bank(
                oversized,
                _event(),
                lambda _: _normalized_request(),
                dynamodb_client=object(),
                sqs_client=object(),
            )
        self.assertEqual(raised.exception.status_code, 400)

    def test_claim_is_owner_bound_atomic_and_idempotent(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["generatedCount"] = meta["desiredCount"]
        meta["initialFillComplete"] = {"BOOL": True}
        dynamo = ClaimDynamo(meta, pointer, [question])
        queue = FakeQueue()
        payload = {"bankID": bank_id, "claimID": "claim-1", "limit": 5}

        first = question_bank.claim_questions(
            payload,
            _event(),
            dynamodb_client=dynamo,
            sqs_client=queue,
        )
        second = question_bank.claim_questions(
            payload,
            _event(),
            dynamodb_client=dynamo,
            sqs_client=queue,
        )

        self.assertEqual(first, second)
        self.assertEqual(len(first["questions"]), 1)
        self.assertEqual(first["questions"][0]["remoteID"], str(uuid.UUID(int=1)))
        self.assertEqual(len(dynamo.transactions), 1)
        self.assertEqual(queue.messages, [])

    def test_claim_treats_legacy_question_without_state_as_ready(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["generatedCount"] = meta["desiredCount"]
        meta["initialFillComplete"] = {"BOOL": True}
        question.pop("state")
        dynamo = ClaimDynamo(meta, pointer, [question])

        response = question_bank.claim_questions(
            {"bankID": bank_id, "claimID": "legacy-claim", "limit": 1},
            _event(),
            dynamodb_client=dynamo,
            sqs_client=FakeQueue(),
        )

        self.assertEqual(len(response["questions"]), 1)
        question_update = next(
            item["Update"]
            for item in dynamo.transactions[0]["TransactItems"]
            if "Update" in item
            and item["Update"]["Key"]["sk"]["S"].startswith("QUESTION#")
        )
        self.assertEqual(
            question_update["ConditionExpression"],
            "attribute_not_exists(#state) OR #state = :ready",
        )

    def test_retrying_queued_idempotent_claim_recovers_refill_scheduling(self):
        bank_id, meta, pointer, question = _claim_records(low=1)
        dynamo = ClaimDynamo(meta, pointer, [question])
        payload = {"bankID": bank_id, "claimID": "recover-refill", "limit": 1}

        with (
            mock.patch.object(
                question_bank,
                "_ensure_refill",
                side_effect=RuntimeError("temporary DynamoDB failure"),
            ),
            mock.patch.object(question_bank.LOGGER, "exception"),
        ):
            first = question_bank.claim_questions(
                payload,
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )

        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            second = question_bank.claim_questions(
                payload,
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )

        self.assertEqual(first, second)
        self.assertEqual(second["status"], "queued")
        self.assertEqual(len(dynamo.transactions), 1)
        refill.assert_called_once()

    def test_claim_rejects_meta_owned_by_a_different_principal(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["ownerHash"] = {"S": "0" * 64}
        dynamo = ClaimDynamo(meta, pointer, [question])
        with self.assertRaises(question_bank.QuestionBankError) as raised:
            question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "claim-1", "limit": 5},
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )
        self.assertEqual(raised.exception.status_code, 404)
        self.assertEqual(dynamo.transactions, [])

    def test_claim_reconciles_meta_count_after_question_ttl_expiry(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["readyCount"] = {"N": "5"}
        meta["generatedCount"] = {"N": "5"}
        dynamo = ClaimDynamo(meta, pointer, [question])

        response = question_bank.claim_questions(
            {"bankID": bank_id, "claimID": "ttl-reconcile", "limit": 2},
            _event(),
            dynamodb_client=dynamo,
            sqs_client=FakeQueue(),
        )

        self.assertEqual(len(response["questions"]), 1)
        self.assertEqual(response["readyCount"], 0)
        self.assertEqual(dynamo.meta["readyCount"], {"N": "0"})
        meta_update = next(
            item["Update"]
            for item in dynamo.transactions[0]["TransactItems"]
            if "Update" in item and item["Update"]["Key"]["sk"]["S"] == "META"
        )
        self.assertEqual(
            meta_update["ExpressionAttributeValues"][":observed"],
            {"N": "5"},
        )

    def test_claim_from_safety_blocked_context_does_not_schedule_refill(self):
        bank_id, meta, pointer, question = _claim_records(low=1)
        meta["generationBlockedReason"] = {"S": "safety_intervention"}
        dynamo = ClaimDynamo(meta, pointer, [question])

        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            response = question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "blocked-claim", "limit": 1},
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )

        self.assertEqual(response["status"], "empty")
        refill.assert_not_called()
        meta_update = next(
            item["Update"]
            for item in dynamo.transactions[0]["TransactItems"]
            if "Update" in item and item["Update"]["Key"]["sk"]["S"] == "META"
        )
        self.assertIn(
            "generationBlockedReason = :blockedReason",
            meta_update["ConditionExpression"],
        )

    def test_zero_watermark_is_finite_but_positive_watermark_refills(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["generatedCount"] = meta["desiredCount"]
        meta["initialFillComplete"] = {"BOOL": True}
        finite = ClaimDynamo(meta, pointer, [question])
        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "finite-claim", "limit": 1},
                _event(),
                dynamodb_client=finite,
                sqs_client=FakeQueue(),
            )
        refill.assert_not_called()

        bank_id, meta, pointer, question = _claim_records(low=0)
        partial_finite = ClaimDynamo(meta, pointer, [question])
        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            response = question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "partial-finite-claim", "limit": 1},
                _event(),
                dynamodb_client=partial_finite,
                sqs_client=FakeQueue(),
            )
        self.assertEqual(response["status"], "queued")
        refill.assert_called_once()

        bank_id, meta, pointer, question = _claim_records(low=1)
        replenishing = ClaimDynamo(meta, pointer, [question])
        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            response = question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "member-claim", "limit": 1},
                _event(),
                dynamodb_client=replenishing,
                sqs_client=FakeQueue(),
            )
        self.assertEqual(response["status"], "queued")
        refill.assert_called_once()

    def test_finite_bank_claim_then_ensure_never_exceeds_initial_generated_target(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["desiredCount"] = {"N": "3"}
        meta["readyCount"] = {"N": "3"}
        meta["generatedCount"] = {"N": "3"}
        meta["initialFillComplete"] = {"BOOL": True}
        questions = []
        for integer in range(1, 4):
            item = copy.deepcopy(question)
            remote_id = str(uuid.UUID(int=integer))
            item["sk"] = {"S": f"QUESTION#{remote_id}"}
            stored = json.loads(item["questionJSON"]["S"])
            stored["remoteID"] = remote_id
            item["remoteID"] = {"S": remote_id}
            item["questionJSON"] = {
                "S": json.dumps(stored, separators=(",", ":"))
            }
            questions.append(item)
        dynamo = ClaimDynamo(meta, pointer, questions)

        claimed = question_bank.claim_questions(
            {"bankID": bank_id, "claimID": "after-initial-fill", "limit": 1},
            _event(),
            dynamodb_client=dynamo,
            sqs_client=FakeQueue(),
        )
        self.assertEqual(claimed["readyCount"], 2)
        self.assertEqual(dynamo.meta["generatedCount"]["N"], "3")

        ensure_payload = _ensure_payload()
        ensure_payload["desiredCount"] = 3
        with (
            mock.patch.object(question_bank, "_activate_goal_version", return_value=bank_id),
            mock.patch.object(question_bank, "_require_current_bank"),
            mock.patch.object(
                question_bank,
                "_update_bank_configuration",
                return_value=dynamo.meta,
            ),
            mock.patch.object(question_bank, "_ensure_refill") as refill,
        ):
            ensured = question_bank.ensure_bank(
                ensure_payload,
                _event(),
                lambda _: _normalized_request(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )
        self.assertEqual(ensured["readyCount"], 2)
        refill.assert_not_called()

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
                object(),
                generator,
                client,
                FakeQueue(),
            )

        generator.assert_not_called()
        refill.assert_called_once()

    def test_safety_intervention_blocks_only_the_current_bank_context(self):
        client = mock.Mock()
        client.update_item.return_value = {
            "Attributes": {"generationPass": {"N": "0"}}
        }
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
            mock.patch.object(question_bank, "_query_question_history", return_value=[]),
            mock.patch.object(question_bank, "_consume_worker_quota"),
            mock.patch.object(question_bank, "_reserve_provider_attempt", return_value=True),
            mock.patch.object(question_bank, "_reset_job_for_retry", reset),
        ):
            question_bank._process_job(  # noqa: SLF001
                {
                    "bankPK": bank_pk,
                    "jobID": "job-1",
                    "contextRevision": revision,
                },
                object(),
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
        self.assertIn("REMOVE activeJobID, refillAfter", meta_update["UpdateExpression"])

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
            "Item": {"providerAttemptCount": {"N": "2"}}
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
        self.assertEqual(queue.messages[0]["MessageBody"], queue.messages[1]["MessageBody"])
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
        self.assertEqual(job_update["ExpressionAttributeValues"][":failed"], {"S": "failed"})
        self.assertEqual(job_update["ExpressionAttributeValues"][":receives"], {"N": "5"})
        self.assertIn("REMOVE activeJobID", meta_update["UpdateExpression"])
        self.assertEqual(meta_update["ExpressionAttributeValues"][":retry"], {"N": "1700000600"})

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

    def test_bank_response_distinguishes_retry_cooldown_from_finite_exhaustion(self):
        retrying = {
            "bankID": {"S": "a" * 64},
            "desiredCount": {"N": "40"},
            "readyCount": {"N": "0"},
            "state": {"S": "failed"},
            "refillAfter": {"N": str(int(question_bank.time.time()) + 60)},
        }
        exhausted = {
            **retrying,
            "state": {"S": "empty"},
            "initialFillComplete": {"BOOL": True},
        }

        self.assertEqual(question_bank._bank_response(retrying)["status"], "queued")  # noqa: SLF001
        self.assertEqual(question_bank._bank_response(exhausted)["status"], "empty")  # noqa: SLF001

    def test_prepared_question_ids_are_stable_uuid_and_deduplicated(self):
        raw = {
            "prompt": "Which statement follows?",
            "expectedAnswer": "The supported statement.",
            "choices": ["The supported statement.", "B", "C", "D"],
            "explanation": "The facts support it.",
            "topic": "Reasoning",
            "difficulty": 3,
            "format": "Multiple Choice",
        }
        first = question_bank._prepare_questions("a" * 64, [raw, raw], [])  # noqa: SLF001
        second = question_bank._prepare_questions("a" * 64, [raw], [])  # noqa: SLF001
        self.assertEqual(len(first), 1)
        self.assertEqual(first, second)
        uuid.UUID(first[0]["remoteID"])

        claimed_history = [
            {
                "remoteID": {"S": first[0]["remoteID"]},
                "state": {"S": "claimed"},
            }
        ]
        regenerated = question_bank._prepare_questions(  # noqa: SLF001
            "a" * 64,
            [raw],
            claimed_history,
        )
        self.assertEqual(regenerated, [])

    def test_worker_skill_allocation_honors_targets_with_batch_breadth(self):
        first_skill = "11111111-1111-4111-8111-111111111111"
        second_skill = "22222222-2222-4222-8222-222222222222"
        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {"id": first_skill, "name": "Reasoning", "objectives": []},
                    {"id": second_skill, "name": "Evidence", "objectives": []},
                ],
            },
            "desiredSkillAllocation": {first_skill: 6, second_skill: 2},
        }

        allocation = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [],
            desired_count=8,
            low_watermark=0,
            target_count=4,
        )

        self.assertEqual(allocation, {first_skill: 3, second_skill: 1})

    def test_worker_skill_allocation_does_not_starve_sixth_skill_across_chunks(self):
        skill_ids = [
            f"{index:08d}-1111-4111-8111-111111111111"
            for index in range(1, 7)
        ]
        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {"id": skill_id, "name": f"Skill {index}", "objectives": []}
                    for index, skill_id in enumerate(skill_ids, start=1)
                ],
            },
            "desiredSkillAllocation": {skill_id: 1 for skill_id in skill_ids},
        }

        first = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [],
            desired_count=40,
            low_watermark=0,
            target_count=5,
        )
        first_items = [
            {
                "state": {"S": "ready"},
                "questionJSON": {"S": json.dumps({"skillID": skill_id})},
            }
            for skill_id, count in first.items()
            for _ in range(count)
        ]
        second = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            first_items,
            desired_count=40,
            low_watermark=0,
            target_count=5,
        )

        self.assertEqual(sum(first.values()), 5)
        self.assertEqual(sum(second.values()), 5)
        self.assertNotIn(skill_ids[-1], first)
        self.assertEqual(second[skill_ids[-1]], 1)

    def test_worker_skill_allocation_counts_claimed_history_only_for_finite_bank(self):
        first_skill = "11111111-1111-4111-8111-111111111111"
        second_skill = "22222222-2222-4222-8222-222222222222"
        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {"id": first_skill, "name": "Reasoning", "objectives": []},
                    {"id": second_skill, "name": "Evidence", "objectives": []},
                ],
            },
            "desiredSkillAllocation": {},
        }
        claimed = {
            "state": {"S": "claimed"},
            "questionJSON": {"S": json.dumps({"skillID": first_skill})},
        }

        finite = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [claimed],
            desired_count=4,
            low_watermark=0,
            target_count=3,
        )
        replenishing = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [claimed],
            desired_count=4,
            low_watermark=1,
            target_count=3,
        )

        self.assertEqual(finite, {first_skill: 1, second_skill: 2})
        self.assertEqual(replenishing, {first_skill: 2, second_skill: 1})

    def test_imbalanced_stable_weights_keep_minor_skill_through_refill(self):
        major_skill = "11111111-1111-4111-8111-111111111111"
        maintenance_skill = "22222222-2222-4222-8222-222222222222"
        request = {
            "skillMap": {
                "version": 3,
                "skills": [
                    {"id": major_skill, "name": "Core", "objectives": []},
                    {
                        "id": maintenance_skill,
                        "name": "Maintenance",
                        "objectives": [],
                    },
                ],
            },
            "desiredSkillAllocation": {major_skill: 99, maintenance_skill: 1},
        }

        targets = question_bank._apportion_skill_counts(  # noqa: SLF001
            [major_skill, maintenance_skill],
            request["desiredSkillAllocation"],
            40,
        )
        initial_batch = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [],
            desired_count=40,
            low_watermark=10,
            target_count=5,
        )
        ready_major = [
            {
                "state": {"S": "ready"},
                "questionJSON": {"S": json.dumps({"skillID": major_skill})},
            }
            for _ in range(9)
        ]
        claimed_maintenance = {
            "state": {"S": "claimed"},
            "questionJSON": {
                "S": json.dumps({"skillID": maintenance_skill})
            },
        }
        refill_batch = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            ready_major + [claimed_maintenance],
            desired_count=40,
            low_watermark=10,
            target_count=5,
        )

        self.assertEqual(targets, {major_skill: 39, maintenance_skill: 1})
        self.assertEqual(initial_batch, {major_skill: 4, maintenance_skill: 1})
        self.assertEqual(refill_batch, {major_skill: 4, maintenance_skill: 1})

    def test_durable_weight_map_requires_room_and_stays_fixed_per_revision(self):
        first_skill = "11111111-1111-4111-8111-111111111111"
        second_skill = "22222222-2222-4222-8222-222222222222"
        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {"id": first_skill, "name": "Core", "objectives": []},
                    {"id": second_skill, "name": "Review", "objectives": []},
                ],
            },
            "desiredSkillAllocation": {first_skill: 99, second_skill: 1},
        }

        with self.assertRaises(question_bank.QuestionBankError) as raised:
            question_bank._validate_durable_skill_allocation(request, 1)  # noqa: SLF001
        changed = copy.deepcopy(request)
        changed["desiredSkillAllocation"] = {first_skill: 1, second_skill: 99}

        self.assertEqual(raised.exception.status_code, 400)
        self.assertNotEqual(
            question_bank._skill_allocation_key(request),  # noqa: SLF001
            question_bank._skill_allocation_key(changed),  # noqa: SLF001
        )

    def test_prepared_questions_retain_skill_and_objective_tags(self):
        question = {
            "prompt": "Which conclusion follows?",
            "expectedAnswer": "The supported conclusion.",
            "choices": ["The supported conclusion.", "B", "C", "D"],
            "explanation": "The evidence supports it.",
            "topic": "Reasoning",
            "skillID": "11111111-1111-4111-8111-111111111111",
            "objectiveID": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "objective": "Draw supported conclusions",
            "difficulty": 3,
            "format": "Multiple Choice",
        }

        prepared = question_bank._prepare_questions(  # noqa: SLF001
            "a" * 64,
            [question],
            [],
        )

        self.assertEqual(prepared[0]["skillID"], question["skillID"])
        self.assertEqual(prepared[0]["objectiveID"], question["objectiveID"])
        self.assertEqual(prepared[0]["objective"], question["objective"])

    def test_worker_reports_only_failed_sqs_records(self):
        event = {
            "Records": [
                {"messageId": "ok", "body": "{}"},
                {"messageId": "failed", "body": "{}"},
            ]
        }
        with (
            mock.patch.object(
                question_bank,
                "_process_job",
                side_effect=[None, RuntimeError("provider unavailable")],
            ),
            mock.patch.object(question_bank.LOGGER, "exception"),
        ):
            result = question_bank.handle_worker_event(
                event,
                object(),
                lambda _: [],
                dynamodb_client=object(),
                sqs_client=object(),
            )
        self.assertEqual(result, {"batchItemFailures": [{"itemIdentifier": "failed"}]})

    def test_http_routes_ensure_without_synchronous_generation_or_quota(self):
        event = _event()
        event["rawPath"] = "/v1/question-banks/ensure"
        event["requestContext"]["stage"] = "prod"
        event["body"] = json.dumps(_ensure_payload())
        with (
            mock.patch.object(
                lambda_function.question_bank,
                "ensure_bank",
                return_value={
                    "bankID": "a" * 64,
                    "status": "queued",
                    "readyCount": 0,
                    "targetCount": 40,
                },
            ) as ensure,
            mock.patch.object(lambda_function, "_check_rate_limits") as quota,
            mock.patch.object(lambda_function, "_generate_sanitized_questions") as generation,
        ):
            response = lambda_function.handle_http_request(event)

        self.assertEqual(response["statusCode"], 202)
        ensure.assert_called_once()
        quota.assert_not_called()
        generation.assert_not_called()


def _event():
    return {
        "requestContext": {"http": {"method": "POST", "sourceIp": "198.51.100.1"}},
        "headers": {"X-Checkpoint-Install-ID": INSTALL_ID},
        "body": "{}",
    }


def _ensure_payload():
    return {
        "goal": {"id": "goal-123", "title": "Study logic"},
        "contextRevision": "0123456789abcdef",
        "desiredCount": 40,
        "lowWatermark": 0,
        "targetCount": 20,
        "minimumDifficulty": 3,
    }


def _normalized_request():
    return {
        "goal": {"title": "Study logic"},
        "competencies": [],
        "existingPrompts": [],
        "existingQuestionCoverage": [],
        "reportedPrompts": [],
        "sourceDocuments": [],
        "targetCount": 20,
        "minimumDifficulty": 3,
        "difficultyGuidance": "Medium application",
    }


def _pending_job():
    return {
        "pk": {"S": "BANK#owner#bank"},
        "sk": {"S": "JOB#job-1"},
        "itemType": {"S": "job"},
        "jobID": {"S": "job-1"},
        "contextRevision": {"S": "revision-1"},
        "status": {"S": "queued"},
        "enqueueStatus": {"S": "pending"},
    }


def _stream_job_event(job, *, sequence_number="1"):
    return {
        "Records": [
            {
                "eventID": f"event-{sequence_number}",
                "eventName": "INSERT",
                "dynamodb": {
                    "SequenceNumber": sequence_number,
                    "NewImage": copy.deepcopy(job),
                },
            }
        ]
    }


def _meta(pk, bank_id, revision, *, desired, low, ready):
    owner_hash = pk.split("#")[1]
    goal_key = question_bank._secret_digest("goal", "goal-123")  # noqa: SLF001
    return {
        "pk": {"S": pk},
        "sk": {"S": "META"},
        "bankID": {"S": bank_id},
        "ownerHash": {"S": owner_hash},
        "goalKey": {"S": goal_key},
        "contextRevision": {"S": revision},
        "readyCount": {"N": str(ready)},
        "generatedCount": {"N": str(ready)},
        "desiredCount": {"N": str(desired)},
        "lowWatermark": {"N": str(low)},
        "state": {"S": "ready" if ready else "empty"},
        **(
            {"initialFillComplete": {"BOOL": True}}
            if low == 0 and ready >= desired
            else {}
        ),
    }


def _claim_records(*, low):
    owner_hash = question_bank._secret_digest("owner", INSTALL_ID)  # noqa: SLF001
    goal_key = question_bank._secret_digest("goal", "goal-123")  # noqa: SLF001
    revision = "0123456789abcdef"
    bank_id = question_bank._secret_digest(  # noqa: SLF001
        "bank", f"{owner_hash}:{goal_key}:{revision}"
    )
    pk = f"BANK#{owner_hash}#{bank_id}"
    meta = _meta(pk, bank_id, revision, desired=3, low=low, ready=1)
    pointer = {
        "pk": {"S": f"OWNER#{owner_hash}"},
        "sk": {"S": f"GOAL#{goal_key}"},
        "currentBankID": {"S": bank_id},
        "contextRevision": {"S": revision},
    }
    remote_id = str(uuid.UUID(int=1))
    question = {
        "pk": {"S": pk},
        "sk": {"S": f"QUESTION#{remote_id}"},
        "remoteID": {"S": remote_id},
        "state": {"S": "ready"},
        "questionJSON": {
            "S": json.dumps(
                {
                    "remoteID": remote_id,
                    "prompt": "Which statement follows?",
                    "expectedAnswer": "The supported statement.",
                    "choices": ["The supported statement.", "B", "C", "D"],
                    "explanation": "The facts support it.",
                    "topic": "Reasoning",
                    "difficulty": 3,
                    "format": "Multiple Choice",
                },
                separators=(",", ":"),
            )
        },
    }
    return bank_id, meta, pointer, question


if __name__ == "__main__":
    unittest.main()
