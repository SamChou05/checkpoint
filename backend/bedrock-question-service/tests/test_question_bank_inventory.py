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
    ConditionalFailure,
    FakeQueue,
    QuestionBankTestCase,
    _claim_records,
    _ensure_payload,
    _event,
    _meta,
    _normalized_request,
)


class QuestionBankInventoryTests(QuestionBankTestCase):
    def test_verified_claim_discards_old_inventory_and_refills(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["generatedCount"] = meta["desiredCount"] = {"N": "1"}
        meta["initialFillComplete"] = {"BOOL": True}
        dynamo = ClaimDynamo(meta, pointer, [question])
        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            response = question_bank.claim_questions(
                {
                    "bankID": bank_id,
                    "claimID": "verified-only",
                    "limit": 1,
                    "minimumVerificationVersion": 1,
                },
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )
        self.assertEqual(response["questions"], [])
        self.assertEqual(question["state"], {"S": "discarded"})
        self.assertEqual(dynamo.meta["generatedCount"], {"N": "0"})
        refill.assert_called_once()

    def test_verified_claim_preserves_checked_payload_and_replay(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        payload = json.loads(question["questionJSON"]["S"])
        payload["verificationVersion"] = 1
        payload["choiceExplanations"] = {"B": "This reverses the condition."}
        question["questionJSON"]["S"] = json.dumps(payload)
        dynamo = ClaimDynamo(meta, pointer, [question])
        request = {
            "bankID": bank_id,
            "claimID": "checked-replay",
            "limit": 1,
            "minimumVerificationVersion": 1,
        }
        with mock.patch.object(question_bank, "_ensure_refill"):
            first = question_bank.claim_questions(
                request, _event(), dynamodb_client=dynamo, sqs_client=FakeQueue()
            )
            second = question_bank.claim_questions(
                request, _event(), dynamodb_client=dynamo, sqs_client=FakeQueue()
            )
        self.assertEqual(first, second)
        self.assertEqual(first["questions"], [payload])

    def test_legacy_claim_cannot_replay_as_verified(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        dynamo = ClaimDynamo(meta, pointer, [question])
        request = {"bankID": bank_id, "claimID": "old-replay", "limit": 1}
        with mock.patch.object(question_bank, "_ensure_refill"):
            question_bank.claim_questions(
                request, _event(), dynamodb_client=dynamo, sqs_client=FakeQueue()
            )
            with self.assertRaises(question_bank.QuestionBankError) as raised:
                question_bank.claim_questions(
                    {**request, "minimumVerificationVersion": 1},
                    _event(),
                    dynamodb_client=dynamo,
                    sqs_client=FakeQueue(),
                )
        self.assertEqual(raised.exception.code, "claim_conflict")

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

    def test_new_bank_context_starts_a_fresh_failure_ledger(self):
        client = mock.Mock()
        owner_hash = "b" * 64
        bank_id = "a" * 64
        bank_key = {
            "pk": {"S": f"BANK#{owner_hash}#{bank_id}"},
            "sk": {"S": "META"},
        }
        pointer_key = {
            "pk": {"S": f"OWNER#{owner_hash}"},
            "sk": {"S": "GOAL#goal"},
        }
        with mock.patch.object(
            question_bank,
            "_get_item",
            side_effect=[None, None],
        ):
            question_bank._activate_goal_version(  # noqa: SLF001
                client,
                "question-banks",
                bank_key,
                pointer_key,
                bank_id,
                "revision-2",
                "goal",
                _normalized_request(),
                40,
                0,
                1_700_000_000,
            )

        created_meta = client.put_item.call_args.kwargs["Item"]
        self.assertEqual(created_meta["failedGenerationJobCount"], {"N": "0"})

    def test_new_bank_persists_full_objective_coverage_capability(self):
        client = mock.Mock()
        owner_hash = "b" * 64
        bank_id = "a" * 64
        bank_key = {
            "pk": {"S": f"BANK#{owner_hash}#{bank_id}"},
            "sk": {"S": "META"},
        }
        pointer_key = {
            "pk": {"S": f"OWNER#{owner_hash}"},
            "sk": {"S": "GOAL#goal"},
        }
        normalized = {
            **_normalized_request(),
            "requiresFullObjectiveCoverage": True,
        }
        with mock.patch.object(
            question_bank,
            "_get_item",
            side_effect=[None, None],
        ):
            question_bank._activate_goal_version(  # noqa: SLF001
                client,
                "question-banks",
                bank_key,
                pointer_key,
                bank_id,
                "revision-2",
                "goal",
                normalized,
                40,
                0,
                1_700_000_000,
            )

        stored_request = json.loads(
            client.put_item.call_args.kwargs["Item"]["generationRequest"]["S"]
        )
        self.assertTrue(stored_request["requiresFullObjectiveCoverage"])

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
        self.assertIn(
            "attribute_not_exists(desiredCount) OR desiredCount <= :desired",
            update["ConditionExpression"],
        )
        self.assertEqual(
            update["ExpressionAttributeValues"][":allocation"],
            {"S": question_bank._skill_allocation_key(normalized)},  # noqa: SLF001
        )

    def test_bank_configuration_target_is_monotonic_but_watermark_remains_mutable(self):
        class ConfigurationDynamo:
            def __init__(self):
                self.desired_count = 40
                self.low_watermark = 10

            def update_item(self, **kwargs):
                values = kwargs["ExpressionAttributeValues"]
                desired_count = int(values[":desired"]["N"])
                grows_target = "desiredCount = :desired" in kwargs["UpdateExpression"]
                if grows_target:
                    if desired_count < self.desired_count:
                        raise ConditionalFailure()
                    self.desired_count = desired_count
                elif desired_count > self.desired_count:
                    raise ConditionalFailure()
                self.low_watermark = int(values[":low"]["N"])
                return {
                    "Attributes": {
                        "desiredCount": {"N": str(self.desired_count)},
                        "lowWatermark": {"N": str(self.low_watermark)},
                    }
                }

        client = ConfigurationDynamo()
        arguments = (
            client,
            "question-banks",
            {"pk": {"S": "BANK#owner#bank"}, "sk": {"S": "META"}},
            "revision-1",
            _normalized_request(),
        )

        unchanged = question_bank._update_bank_configuration(  # noqa: SLF001
            *arguments,
            40,
            0,
            1_700_000_000,
        )
        increased = question_bank._update_bank_configuration(  # noqa: SLF001
            *arguments,
            60,
            15,
            1_700_000_001,
        )
        reduced = question_bank._update_bank_configuration(  # noqa: SLF001
            *arguments,
            50,
            0,
            1_700_000_002,
        )

        self.assertEqual(unchanged["desiredCount"], {"N": "40"})
        self.assertEqual(unchanged["lowWatermark"], {"N": "0"})
        self.assertEqual(increased["desiredCount"], {"N": "60"})
        self.assertEqual(increased["lowWatermark"], {"N": "15"})
        self.assertEqual(reduced["desiredCount"], {"N": "60"})
        self.assertEqual(reduced["lowWatermark"], {"N": "0"})
        self.assertEqual(client.desired_count, 60)
        self.assertEqual(client.low_watermark, 0)

    def test_smaller_target_fallback_keeps_context_and_allocation_locks(self):
        client = mock.Mock()
        client.update_item.side_effect = [ConditionalFailure(), ConditionalFailure()]

        with self.assertRaises(question_bank.QuestionBankError) as raised:
            question_bank._update_bank_configuration(  # noqa: SLF001
                client,
                "question-banks",
                {"pk": {"S": "BANK#owner#bank"}, "sk": {"S": "META"}},
                "revision-1",
                _normalized_request(),
                40,
                0,
                1_700_000_000,
            )

        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(raised.exception.code, "stale_bank")
        self.assertEqual(client.update_item.call_count, 2)
        fallback = client.update_item.call_args_list[1].kwargs
        self.assertNotIn("desiredCount = :desired", fallback["UpdateExpression"])
        self.assertIn("contextRevision = :revision", fallback["ConditionExpression"])
        self.assertIn(
            "skillAllocationKey = :allocation", fallback["ConditionExpression"]
        )
        self.assertIn("desiredCount >= :desired", fallback["ConditionExpression"])

    def test_smaller_repeat_ensure_refills_to_effective_stored_target(self):
        payload = _ensure_payload()
        meta = _meta(
            f"BANK#{'b' * 64}#{'a' * 64}",
            "a" * 64,
            payload["contextRevision"],
            desired=80,
            low=0,
            ready=50,
        )

        with (
            mock.patch.object(question_bank, "_activate_goal_version", return_value=""),
            mock.patch.object(
                question_bank,
                "_update_bank_configuration",
                return_value=meta,
            ),
            mock.patch.object(question_bank, "_ensure_refill") as ensure_refill,
            mock.patch.object(question_bank, "_get_item", return_value=None),
            mock.patch.object(question_bank, "_require_current_bank"),
        ):
            response = question_bank.ensure_bank(
                payload,
                _event(),
                lambda _: _normalized_request(),
                dynamodb_client=object(),
                sqs_client=object(),
            )

        ensure_refill.assert_called_once()
        self.assertEqual(response["targetCount"], 80)

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

    def test_claim_scans_past_and_discards_legacy_duplicates_without_underfill(self):
        bank_id, meta, pointer, claimed_question = _claim_records(low=0)
        claimed_question["state"] = {"S": "claimed"}
        duplicates = []
        for integer in range(2, 27):
            duplicate = copy.deepcopy(claimed_question)
            duplicate_id = str(uuid.UUID(int=integer))
            duplicate["sk"] = {"S": f"QUESTION#{duplicate_id}"}
            duplicate["remoteID"] = {"S": duplicate_id}
            duplicate["state"] = {"S": "ready"}
            duplicate_payload = json.loads(duplicate["questionJSON"]["S"])
            duplicate_payload["remoteID"] = duplicate_id
            duplicate_payload["explanation"] = (
                f"Changed legacy explanation {integer} for the same stem."
            )
            duplicate["questionJSON"] = {"S": json.dumps(duplicate_payload)}
            duplicates.append(duplicate)

        novel_questions = []
        novel_prompts = []
        for integer in range(27, 29):
            novel = copy.deepcopy(duplicates[-1])
            novel_id = str(uuid.UUID(int=integer))
            novel_prompt = f"Which distinct conclusion number {integer} follows?"
            novel["sk"] = {"S": f"QUESTION#{novel_id}"}
            novel["remoteID"] = {"S": novel_id}
            novel_payload = json.loads(novel["questionJSON"]["S"])
            novel_payload["remoteID"] = novel_id
            novel_payload["prompt"] = novel_prompt
            novel["questionJSON"] = {"S": json.dumps(novel_payload)}
            novel_questions.append(novel)
            novel_prompts.append(novel_prompt)

        meta["readyCount"] = {"N": "27"}
        meta["generatedCount"] = {"N": "28"}
        meta["desiredCount"] = {"N": "28"}
        meta["initialFillComplete"] = {"BOOL": True}
        dynamo = ClaimDynamo(
            meta,
            pointer,
            [claimed_question] + duplicates + novel_questions,
        )

        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            response = question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "deduplicated-claim", "limit": 2},
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )

        self.assertEqual(
            [question["prompt"] for question in response["questions"]],
            novel_prompts,
        )
        self.assertEqual(response["readyCount"], 0)
        self.assertTrue(all(item["state"] == {"S": "discarded"} for item in duplicates))
        self.assertTrue(
            all(item["state"] == {"S": "claimed"} for item in novel_questions)
        )
        self.assertEqual(len(dynamo.transactions), 2)
        cleanup_updates = [
            operation["Update"]
            for operation in dynamo.transactions[0]["TransactItems"]
            if "Update" in operation
            and operation["Update"]["Key"]["sk"]["S"].startswith("QUESTION#")
        ]
        claim_updates = [
            operation["Update"]
            for operation in dynamo.transactions[1]["TransactItems"]
            if "Update" in operation
            and operation["Update"]["Key"]["sk"]["S"].startswith("QUESTION#")
        ]
        self.assertEqual(len(cleanup_updates), 23)
        self.assertEqual(len(claim_updates), 4)
        self.assertEqual(response["status"], "queued")
        self.assertEqual(dynamo.meta["generatedCount"], {"N": "3"})
        refill.assert_called_once()

    def test_claim_cleanup_preserves_one_unserved_canonical_duplicate(self):
        bank_id, meta, pointer, template = _claim_records(low=0)
        duplicate_questions = []
        for integer in range(1, 26):
            duplicate = copy.deepcopy(template)
            duplicate_id = str(uuid.UUID(int=integer))
            duplicate["sk"] = {"S": f"QUESTION#{duplicate_id}"}
            duplicate["remoteID"] = {"S": duplicate_id}
            duplicate_payload = json.loads(duplicate["questionJSON"]["S"])
            duplicate_payload["remoteID"] = duplicate_id
            duplicate_payload["explanation"] = (
                f"Legacy explanation {integer} for the same unserved stem."
            )
            duplicate["questionJSON"] = {"S": json.dumps(duplicate_payload)}
            duplicate_questions.append(duplicate)

        novel_questions = []
        novel_prompts = []
        for integer in range(26, 28):
            novel = copy.deepcopy(template)
            novel_id = str(uuid.UUID(int=integer))
            novel_prompt = f"Which novel conclusion number {integer} follows?"
            novel["sk"] = {"S": f"QUESTION#{novel_id}"}
            novel["remoteID"] = {"S": novel_id}
            novel_payload = json.loads(novel["questionJSON"]["S"])
            novel_payload["remoteID"] = novel_id
            novel_payload["prompt"] = novel_prompt
            novel["questionJSON"] = {"S": json.dumps(novel_payload)}
            novel_questions.append(novel)
            novel_prompts.append(novel_prompt)

        meta["readyCount"] = {"N": "27"}
        meta["generatedCount"] = {"N": "27"}
        meta["desiredCount"] = {"N": "27"}
        meta["initialFillComplete"] = {"BOOL": True}
        dynamo = ClaimDynamo(
            meta,
            pointer,
            duplicate_questions + novel_questions,
        )

        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            response = question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "canonical-claim", "limit": 2},
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )

        self.assertEqual(
            [question["prompt"] for question in response["questions"]],
            [
                "Which statement follows?",
                novel_prompts[0],
            ],
        )
        self.assertEqual(
            sum(item["state"] == {"S": "claimed"} for item in duplicate_questions),
            1,
        )
        self.assertEqual(
            sum(item["state"] == {"S": "discarded"} for item in duplicate_questions),
            24,
        )
        self.assertEqual(dynamo.meta["generatedCount"], {"N": "3"})
        self.assertEqual(response["status"], "queued")
        refill.assert_called_once()
        self.assertTrue(
            all(
                len(transaction["TransactItems"]) <= 25
                for transaction in dynamo.transactions
            )
        )

    def test_finite_bank_replenishes_discarded_duplicate_idempotently(self):
        bank_id, meta, pointer, claimed_question = _claim_records(low=0)
        claimed_question["state"] = {"S": "claimed"}
        duplicate = copy.deepcopy(claimed_question)
        duplicate_id = str(uuid.UUID(int=2))
        duplicate["sk"] = {"S": f"QUESTION#{duplicate_id}"}
        duplicate["remoteID"] = {"S": duplicate_id}
        duplicate["state"] = {"S": "ready"}
        duplicate_payload = json.loads(duplicate["questionJSON"]["S"])
        duplicate_payload["remoteID"] = duplicate_id
        duplicate["questionJSON"] = {"S": json.dumps(duplicate_payload)}
        meta["readyCount"] = {"N": "1"}
        meta["generatedCount"] = {"N": "2"}
        meta["desiredCount"] = {"N": "2"}
        meta["initialFillComplete"] = {"BOOL": True}
        dynamo = ClaimDynamo(meta, pointer, [claimed_question, duplicate])
        payload = {
            "bankID": bank_id,
            "claimID": "finite-discard-replenishment",
            "limit": 1,
        }

        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            first = question_bank.claim_questions(
                payload,
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )
            second = question_bank.claim_questions(
                payload,
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )

        self.assertEqual(first, second)
        self.assertEqual(first["questions"], [])
        self.assertEqual(first["status"], "queued")
        self.assertEqual(duplicate["state"], {"S": "discarded"})
        self.assertEqual(dynamo.meta["generatedCount"], {"N": "1"})
        self.assertEqual(len(dynamo.transactions), 1)
        self.assertEqual(refill.call_count, 2)

    def test_claim_discards_cross_context_blocked_stem_and_refills_finite_bank(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        prompt = json.loads(question["questionJSON"]["S"])["prompt"]
        fingerprint = question_bank._stem_fingerprint(prompt)  # noqa: SLF001
        meta["readyCount"] = {"N": "1"}
        meta["generatedCount"] = {"N": "1"}
        meta["desiredCount"] = {"N": "1"}
        meta["initialFillComplete"] = {"BOOL": True}
        dynamo = ClaimDynamo(meta, pointer, [question])
        payload = {
            "bankID": bank_id,
            "claimID": "cross-context-blocked-stem",
            "limit": 1,
            "blockedStemFingerprints": [fingerprint],
        }

        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            first = question_bank.claim_questions(
                payload,
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )
            retry_payload = {
                **payload,
                "blockedStemFingerprints": ["not-a-fingerprint"],
            }
            second = question_bank.claim_questions(
                retry_payload,
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )

        self.assertEqual(first, second)
        self.assertEqual(first["questions"], [])
        self.assertEqual(first["status"], "queued")
        self.assertEqual(question["state"], {"S": "discarded"})
        self.assertEqual(dynamo.meta["generatedCount"], {"N": "0"})
        self.assertEqual(len(dynamo.transactions), 1)
        self.assertEqual(refill.call_count, 2)

    def test_new_claim_rejects_malformed_or_oversized_stem_fingerprints(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        dynamo = ClaimDynamo(meta, pointer, [question])
        invalid_values = [
            "not-an-array",
            ["A" * 16],
            ["0" * 15],
            ["0" * 16] * 751,
        ]

        for index, invalid in enumerate(invalid_values):
            with self.subTest(index=index):
                with self.assertRaises(question_bank.QuestionBankError) as raised:
                    question_bank.claim_questions(
                        {
                            "bankID": bank_id,
                            "claimID": f"invalid-fingerprints-{index}",
                            "limit": 1,
                            "blockedStemFingerprints": invalid,
                        },
                        _event(),
                        dynamodb_client=dynamo,
                        sqs_client=FakeQueue(),
                    )
                self.assertEqual(raised.exception.status_code, 400)

        self.assertEqual(dynamo.transactions, [])

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
            replay = question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "blocked-claim", "limit": 1},
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )

        self.assertEqual(response["status"], "empty")
        self.assertEqual(
            response["generationBlockedReason"],
            "safety_intervention",
        )
        self.assertEqual(replay, response)
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

    def test_claim_does_not_reset_the_bank_failure_ledger(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["failedGenerationJobCount"] = {"N": "2"}
        dynamo = ClaimDynamo(meta, pointer, [question])

        with mock.patch.object(question_bank, "_ensure_refill"):
            question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "failure-ledger-claim", "limit": 1},
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )

        self.assertEqual(
            dynamo.meta["failedGenerationJobCount"],
            {"N": "2"},
        )
        meta_update = next(
            item["Update"]
            for item in dynamo.transactions[0]["TransactItems"]
            if "Update" in item and item["Update"]["Key"]["sk"]["S"] == "META"
        )
        self.assertNotIn("failedGenerationJobCount", meta_update["UpdateExpression"])

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
