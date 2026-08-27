import copy
import json
import os
import unittest
import uuid
from unittest import mock

import question_bank
from question_bank_test_support import (
    INSTALL_ID,
    ClaimDynamo,
    FakeQueue,
    QuestionBankTestCase,
    _claim_records,
    _ensure_payload,
    _event,
    _meta,
    _normalized_request,
)


class QuestionBankInventoryTests(QuestionBankTestCase):
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
            item["questionJSON"] = {"S": json.dumps(stored, separators=(",", ":"))}
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
            mock.patch.object(
                question_bank, "_activate_goal_version", return_value=bank_id
            ),
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


if __name__ == "__main__":
    unittest.main()
