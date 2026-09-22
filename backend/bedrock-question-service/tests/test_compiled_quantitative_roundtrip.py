"""Compiler-produced learner text survives the existing downstream carriers.

Synthetic trusted metadata exercises storage/claim transport; this test does not
authorize compiler output or qualify a generation/verification route.
"""

import copy
import json
from pathlib import Path
from unittest import mock

import question_bank
import question_bank_store
import question_bank_worker
from quantitative_task_compiler import compile_question
from question_bank_test_support import (
    ClaimDynamo,
    FakeQueue,
    QuestionBankTestCase,
    _claim_records,
    _event,
)


FIXTURE = Path(__file__).parent / "fixtures" / "compiled_quantitative_roundtrip.json"
LEARNER_FIELDS = (
    "prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations",
)


class CompiledQuantitativeRoundtripTests(QuestionBankTestCase):
    def setUp(self):
        super().setUp()
        self.fixture = json.loads(FIXTURE.read_text())

    def assert_learner_preserved(self, actual, expected):
        self.assertEqual({field: actual[field] for field in LEARNER_FIELDS}, expected)
        for field in ("prompt", "expectedAnswer", "explanation"):
            self.assertEqual(actual[field].encode("utf-8"), expected[field].encode("utf-8"))
        self.assertEqual(
            [text.encode("utf-8") for text in actual["choices"]],
            [text.encode("utf-8") for text in expected["choices"]],
        )
        self.assertEqual(
            {key.encode("utf-8"): value.encode("utf-8")
             for key, value in actual["choiceExplanations"].items()},
            {key.encode("utf-8"): value.encode("utf-8")
             for key, value in expected["choiceExplanations"].items()},
        )

    def test_shared_client_fixtures_are_exact_current_compiler_outputs(self):
        self.assertEqual(len(self.fixture["cases"]), 3)
        for case in self.fixture["cases"]:
            with self.subTest(case=case["id"]):
                actual = compile_question(case["spec"])
                self.assertEqual(set(actual), set(LEARNER_FIELDS))
                self.assert_learner_preserved(actual, case["compiled"])

    def test_bank_write_claim_and_idempotent_replay_preserve_all_five_fields(self):
        bank_id, meta, pointer, _ = _claim_records(low=0)
        generated = [
            {**copy.deepcopy(case["compiled"]), **self.fixture["trustedWireMetadata"]}
            for case in self.fixture["cases"]
        ]
        prepared = question_bank_worker._prepare_questions(bank_id, generated, [])
        self.assertEqual(len(prepared), 3)
        self.assertEqual(len({item["remoteID"] for item in prepared}), 3)
        client = mock.Mock()
        question_bank_worker._commit_generated_questions(
            client, "question-banks", {"pk": meta["pk"], "sk": meta["sk"]},
            {"pk": meta["pk"], "sk": {"S": "JOB#compiled-roundtrip"}},
            {"pk": pointer["pk"], "sk": pointer["sk"]},
            bank_id, meta["contextRevision"]["S"], "test-lease", prepared,
            observed_desired_count=3, observed_low_watermark=0,
            observed_ready_count=0, observed_generated_count=0,
        )
        client.transact_write_items.assert_called_once()
        stored = [
            operation["Put"]["Item"]
            for operation in client.transact_write_items.call_args.kwargs["TransactItems"]
            if "Put" in operation
        ]
        self.assertEqual(len(stored), 3)
        for item, case, payload in zip(stored, self.fixture["cases"], prepared, strict=True):
            restored = question_bank_store._question_from_item(item)
            self.assertEqual(restored, payload)
            self.assert_learner_preserved(restored, case["compiled"])

        # The fake applies claim transactions; the real worker serialization
        # above supplies its question rows, with the committed ready counts.
        meta["readyCount"] = meta["generatedCount"] = {"N": "3"}
        meta["initialFillComplete"] = {"BOOL": True}
        dynamo = ClaimDynamo(meta, pointer, stored)
        request = {
            "bankID": bank_id, "claimID": "compiled-roundtrip", "limit": 3,
            "minimumVerificationVersion": 1, "minimumVerificationPolicyRevision": 2,
        }
        with mock.patch.object(question_bank, "_ensure_refill"):
            first = question_bank.claim_questions(
                request, _event(), dynamodb_client=dynamo, sqs_client=FakeQueue(),
            )
            replay = question_bank.claim_questions(
                request, _event(), dynamodb_client=dynamo, sqs_client=FakeQueue(),
            )
        self.assertEqual(first, replay)
        self.assertEqual(len(dynamo.transactions), 1)
        self.assertEqual(first["questions"], prepared)
        for actual, case in zip(first["questions"], self.fixture["cases"], strict=True):
            self.assert_learner_preserved(actual, case["compiled"])
        self.assertTrue(all(item["state"] == {"S": "claimed"} for item in stored))
