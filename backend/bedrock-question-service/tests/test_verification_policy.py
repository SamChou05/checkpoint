"""Policy provenance and compatible inventory freshness; all services are fake."""

import copy
import json
from unittest import mock

import question_bank
from lambda_test_support import FakeBedrockClient, _raw_question, _request_payload
from question_bank_test_support import (
    ClaimDynamo,
    ConditionalFailure,
    FakeQueue,
    QuestionBankTestCase,
    _claim_records,
    _event,
)
from question_generation import ProviderCallBudget, _generate_sanitized_questions
from question_quality import _sanitize_questions
from question_verification import verify_questions
from request_contract import _normalize_request


class VerificationPolicyTests(QuestionBankTestCase):
    def setUp(self):
        super().setUp()
        self.question = _raw_question(
            "Which conclusion follows from the stated premises?"
        )
        self.request = _normalize_request(_request_payload(target_count=1))

    def review(self, **changes):
        return {
            "index": 0,
            "valid": True,
            "answer": self.question["expectedAnswer"],
            "difficulty": 3,
            "explanation": "The stated premises establish this conclusion.",
            "choiceExplanations": {
                choice: "Evaluate this conclusion against the stated premises."
                for choice in self.question["choices"]
            },
            **changes,
        }

    def solution(self, **changes):
        return {
            "index": 0,
            "outcome": "resolved",
            "answer": "The stated conclusion follows.",
            "limitations": "",
            "assumptionsRequired": [],
            **changes,
        }

    def test_legacy_full_path_owns_revision_one_regardless_of_authored_or_solver_metadata(
        self,
    ):
        for forged in (True, 0, 1, 99, "1"):
            with self.subTest(forged=forged):
                question = {**self.question, "verificationPolicyRevision": forged}
                original = copy.deepcopy(question)
                solver = mock.Mock(
                    return_value=json.dumps(
                        {"solutions": [self.solution(verificationPolicyRevision=99)]}
                    )
                )
                reviewer = mock.Mock(
                    return_value=json.dumps(
                        {"reviews": [self.review()]}
                    )
                )
                accepted = verify_questions(
                    [question], self.request, reviewer, solve=solver
                )
                self.assertEqual(question, original)
                self.assertEqual(len(accepted), 1)
                self.assertEqual(accepted[0]["verificationVersion"], 1)
                self.assertIs(type(accepted[0]["verificationPolicyRevision"]), int)
                self.assertEqual(accepted[0]["verificationPolicyRevision"], 1)
                solver.assert_called_once()
                reviewer.assert_called_once()
                for callback in (solver, reviewer):
                    self.assertNotIn(
                        "verificationPolicyRevision", callback.call_args.args[1]
                    )

    def test_review_only_cannot_mint_or_retain_caller_policy(self):
        for forged in (None, True, 1, 99):
            with self.subTest(forged=forged):
                question = copy.deepcopy(self.question)
                if forged is not None:
                    question["verificationPolicyRevision"] = forged
                reviewer = mock.Mock(
                    return_value=json.dumps(
                        {"reviews": [self.review()]}
                    )
                )
                accepted = verify_questions([question], self.request, reviewer)
                self.assertEqual(len(accepted), 1)
                self.assertEqual(accepted[0]["verificationVersion"], 1)
                self.assertNotIn("verificationPolicyRevision", accepted[0])

    def test_legacy_and_review_only_reject_reviewer_policy_metadata(self):
        question = {**self.question, "verificationPolicyRevision": 99}
        original = copy.deepcopy(question)
        for legacy_solver in (False, True):
            for metadata in (
                {"verificationPolicyRevision": 1},
                {"verificationVersion": 1},
            ):
                with self.subTest(legacy_solver=legacy_solver, metadata=metadata):
                    solver = mock.Mock(return_value=json.dumps({
                        "solutions": [self.solution()],
                    })) if legacy_solver else None
                    reviewer = mock.Mock(return_value=json.dumps({
                        "reviews": [self.review(**metadata)],
                    }))
                    self.assertEqual(
                        verify_questions(
                            [question], self.request, reviewer, solve=solver
                        ),
                        [],
                    )
                    self.assertEqual(question, original)
                    reviewer.assert_called_once()
                    if solver is not None:
                        solver.assert_called_once()

    def test_forged_author_metadata_does_not_survive_sanitization_and_full_generation_stamps_after_three_stages(
        self,
    ):
        self.question["verificationPolicyRevision"] = 99
        sanitized = _sanitize_questions([self.question], self.request)
        self.assertEqual(len(sanitized), 1)
        self.assertNotIn("verificationPolicyRevision", sanitized[0])
        client = FakeBedrockClient.returning_questions(self.question)
        accepted = _generate_sanitized_questions(
            self.request, client, ProviderCallBudget(3)
        )
        self.assertEqual(len(accepted), 1)
        self.assertEqual(accepted[0]["verificationPolicyRevision"], 2)
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(len(client.solution_calls), 1)
        self.assertEqual(len(client.review_calls), 1)

    def test_rejected_or_malformed_solver_and_failed_review_never_return_policy(self):
        self.question["verificationPolicyRevision"] = 1
        for raw in (
            "{}",
            json.dumps({"solutions": [self.solution(outcome="uncertain")]}),
            json.dumps(
                {
                    "solutions": [
                        self.solution(
                            limitations="The result needs an unstated condition."
                        )
                    ]
                }
            ),
        ):
            reviewer = mock.Mock()
            self.assertEqual(
                verify_questions(
                    [self.question], self.request, reviewer, solve=lambda *_: raw
                ),
                [],
            )
            reviewer.assert_not_called()
        self.assertEqual(
            verify_questions(
                [self.question],
                self.request,
                lambda *_: json.dumps({"reviews": [self.review(valid=False)]}),
                solve=lambda *_: json.dumps({"solutions": [self.solution()]}),
            ),
            [],
        )

    def bank(self, *, revision=None, wire=1):
        bank_id, meta, pointer, item = _claim_records(low=0)
        meta["generatedCount"] = meta["desiredCount"] = {"N": "1"}
        meta["initialFillComplete"] = {"BOOL": True}
        question = json.loads(item["questionJSON"]["S"])
        question["verificationVersion"] = wire
        if revision is not None:
            question["verificationPolicyRevision"] = revision
        item["questionJSON"]["S"] = json.dumps(question)
        return bank_id, ClaimDynamo(meta, pointer, [item]), item, question

    def claim(self, bank_id, dynamo, *, minimum=1, claim_id="policy-claim", **changes):
        payload = {
            "bankID": bank_id,
            "claimID": claim_id,
            "limit": 1,
            "minimumVerificationVersion": 1,
            **changes,
        }
        if minimum is not None:
            payload["minimumVerificationPolicyRevision"] = minimum
        return question_bank.claim_questions(
            payload, _event(), dynamodb_client=dynamo, sqs_client=FakeQueue()
        )

    def test_v1_without_revision_one_is_retired_and_refilled_without_relabeling(self):
        for revision in (None, 0, True, False, 1.0, "1", -1):
            with self.subTest(revision=revision):
                bank_id, dynamo, item, _ = self.bank(revision=revision)
                original_json = item["questionJSON"]["S"]
                with mock.patch.object(question_bank, "_ensure_refill") as refill:
                    response = self.claim(bank_id, dynamo)
                self.assertEqual(response["questions"], [])
                self.assertEqual(item["state"], {"S": "discarded"})
                self.assertEqual(item["questionJSON"]["S"], original_json)
                self.assertEqual(dynamo.meta["generatedCount"], {"N": "0"})
                refill.assert_called_once()

    def test_revision_one_survives_compatible_claim_and_idempotent_replay_exactly(self):
        bank_id, dynamo, item, question = self.bank(revision=1)
        original_json = item["questionJSON"]["S"]
        with mock.patch.object(question_bank, "_ensure_refill"):
            first = self.claim(bank_id, dynamo)
            second = self.claim(bank_id, dynamo)
        self.assertEqual(first, second)
        self.assertEqual(first["questions"], [question])
        self.assertEqual(item["questionJSON"]["S"], original_json)

    def test_stale_claim_replay_conflicts_without_mutating_original_response(self):
        bank_id, dynamo, _, question = self.bank()
        with mock.patch.object(question_bank, "_ensure_refill"):
            previous = self.claim(bank_id, dynamo, minimum=None)
            stored = copy.deepcopy(dynamo.claims)
            with self.assertRaises(question_bank.QuestionBankError) as raised:
                self.claim(bank_id, dynamo)
        self.assertEqual(previous["questions"], [question])
        self.assertEqual(raised.exception.code, "claim_conflict")
        self.assertEqual(dynamo.claims, stored)

    def test_omitted_or_zero_minimum_keeps_legacy_v1_claim_and_replay_unchanged(self):
        for minimum in (None, 0):
            with self.subTest(minimum=minimum):
                bank_id, dynamo, _, question = self.bank()
                with mock.patch.object(question_bank, "_ensure_refill"):
                    first = self.claim(bank_id, dynamo, minimum=minimum)
                    second = self.claim(bank_id, dynamo, minimum=minimum)
                self.assertEqual(first, second)
                self.assertEqual(first["questions"], [question])
                self.assertNotIn("verificationPolicyRevision", first["questions"][0])

    def test_racing_stale_claim_replay_also_requires_requested_policy(self):
        bank_id, dynamo, _, _ = self.bank(revision=1)

        def stale_claim_wins(**kwargs):
            claim_item = next(
                operation["Put"]["Item"]
                for operation in kwargs["TransactItems"]
                if "Put" in operation
                and operation["Put"]["Item"]["itemType"] == {"S": "claim"}
            )
            stored = copy.deepcopy(claim_item)
            response = json.loads(stored["responseJSON"]["S"])
            response["questions"][0].pop("verificationPolicyRevision")
            stored["responseJSON"] = {"S": json.dumps(response)}
            dynamo.claims[stored["sk"]["S"]] = stored
            raise ConditionalFailure()

        with mock.patch.object(
            dynamo, "transact_write_items", side_effect=stale_claim_wins
        ):
            with self.assertRaises(question_bank.QuestionBankError) as raised:
                self.claim(bank_id, dynamo)
        self.assertEqual(raised.exception.code, "claim_conflict")

    def test_minimum_policy_is_strict_integer_and_known_request_bound(self):
        for invalid in (True, False, "1", 1.0, -1, 3, None, [], {}):
            with self.subTest(invalid=invalid):
                bank_id, dynamo, _, _ = self.bank(revision=1)
                with mock.patch.object(
                    dynamo,
                    "get_item",
                    side_effect=AssertionError("Invalid input reached storage"),
                ):
                    with self.assertRaises(question_bank.QuestionBankError) as raised:
                        question_bank.claim_questions(
                            {
                                "bankID": bank_id,
                                "claimID": "invalid",
                                "limit": 1,
                                "minimumVerificationPolicyRevision": invalid,
                            },
                            _event(),
                            dynamodb_client=dynamo,
                            sqs_client=FakeQueue(),
                        )
                self.assertEqual(raised.exception.code, "invalid_request")

    def test_revision_two_claim_floor_filters_one_without_relabeling_inventory(self):
        bank_id, dynamo, item, _ = self.bank(revision=1)
        original_json = item["questionJSON"]["S"]
        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            response = self.claim(bank_id, dynamo, minimum=2)
        self.assertEqual(response["questions"], [])
        self.assertEqual(item["state"], {"S": "discarded"})
        self.assertEqual(item["questionJSON"]["S"], original_json)
        self.assertEqual(dynamo.meta["generatedCount"], {"N": "0"})
        refill.assert_called_once()

    def test_revision_one_and_two_respect_compatible_claim_and_replay_floors(self):
        for revision, minimum in ((1, None), (1, 0), (1, 1), (2, None), (2, 0), (2, 1), (2, 2)):
            with self.subTest(revision=revision, minimum=minimum):
                bank_id, dynamo, item, question = self.bank(revision=revision)
                original_json = item["questionJSON"]["S"]
                with mock.patch.object(question_bank, "_ensure_refill"):
                    first = self.claim(bank_id, dynamo, minimum=minimum)
                    stored = copy.deepcopy(dynamo.claims)
                    replay = self.claim(bank_id, dynamo, minimum=minimum)
                self.assertEqual(first, replay)
                self.assertEqual(first["questions"], [question])
                self.assertEqual(item["questionJSON"]["S"], original_json)
                self.assertEqual(dynamo.claims, stored)

    def test_revision_two_refuses_a_stored_revision_one_claim_without_rewriting_it(self):
        bank_id, dynamo, item, question = self.bank(revision=1)
        original_json = item["questionJSON"]["S"]
        with mock.patch.object(question_bank, "_ensure_refill"):
            previous = self.claim(bank_id, dynamo, minimum=1)
            stored = copy.deepcopy(dynamo.claims)
            with self.assertRaises(question_bank.QuestionBankError) as raised:
                self.claim(bank_id, dynamo, minimum=2)
        self.assertEqual(previous["questions"], [question])
        self.assertEqual(raised.exception.code, "claim_conflict")
        self.assertEqual(dynamo.claims, stored)
        self.assertEqual(item["questionJSON"]["S"], original_json)

    def test_revision_two_refuses_a_racing_revision_one_claim_without_rewriting_it(self):
        bank_id, dynamo, _, _ = self.bank(revision=2)
        race_winner = {}

        def legacy_claim_wins(**kwargs):
            claim_item = next(
                operation["Put"]["Item"]
                for operation in kwargs["TransactItems"]
                if "Put" in operation
                and operation["Put"]["Item"]["itemType"] == {"S": "claim"}
            )
            stored = copy.deepcopy(claim_item)
            response = json.loads(stored["responseJSON"]["S"])
            response["questions"][0]["verificationPolicyRevision"] = 1
            stored["responseJSON"] = {"S": json.dumps(response)}
            dynamo.claims[stored["sk"]["S"]] = stored
            race_winner.update(copy.deepcopy(dynamo.claims))
            raise ConditionalFailure()

        with mock.patch.object(dynamo, "transact_write_items", side_effect=legacy_claim_wins):
            with self.assertRaises(question_bank.QuestionBankError) as raised:
                self.claim(bank_id, dynamo, minimum=2)
        self.assertEqual(raised.exception.code, "claim_conflict")
        self.assertEqual(dynamo.claims, race_winner)

    def test_policy_alone_requires_typed_v1_wire_stamp_for_inventory_and_replay(self):
        for wire in (0, True, 1.0, "1", 2):
            with self.subTest(wire=wire):
                bank_id, dynamo, _, question = self.bank(revision=1, wire=wire)
                with mock.patch.object(question_bank, "_ensure_refill"):
                    response = self.claim(bank_id, dynamo, minimumVerificationVersion=0)
                self.assertEqual(response["questions"], [])
                with self.assertRaises(question_bank.QuestionBankError):
                    question_bank._require_claim_verification(
                        {"questions": [question]}, 0, 1
                    )

    def test_policy_replay_rejects_malformed_revision_even_when_python_equality_matches_one(
        self,
    ):
        for revision in (None, True, 1.0, "1", 0):
            with self.subTest(revision=revision):
                _, _, _, question = self.bank(revision=revision)
                with self.assertRaises(question_bank.QuestionBankError) as raised:
                    question_bank._require_claim_verification(
                        {"questions": [question]}, 1, 1
                    )
                self.assertEqual(raised.exception.code, "claim_conflict")
