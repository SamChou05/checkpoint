"""A schema-valid rejection must not discard independently valid review peers."""

import copy
import json
import os
import unittest
from pathlib import Path
from unittest.mock import patch

from native_output_contracts import adapt_native_response
from question_generation import ProviderCallBudget, _generate_with_bedrock
from question_verification import verify_questions
from service_errors import ProviderError


ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / "docs/evidence/choice-reliability-20260921"


def question(prompt, answer, choices):
    return {"prompt": prompt, "expectedAnswer": answer, "choices": choices,
            "topic": "Arithmetic", "difficulty": 1, "explanation": "Private fixture teaching."}


def review(item, index, *, valid=True):
    return {
        "index": index, "valid": valid, "answer": item["expectedAnswer"], "difficulty": 1,
        "explanation": "  The stated calculation establishes this answer.\n    Keep these bytes.  ",
        "choiceFeedback": [{"choice": choice, "explanation": "  Exact choice feedback.\n  "}
                           for choice in reversed(item["choices"])],
    }


class NativeRejectedRowsTests(unittest.TestCase):
    def setUp(self):
        self.valid = question("What is 2 + 2?", "4", ["4", "5", "6", "7"])
        self.invalid = question("What is 1 + 1?", "2", ["2", "3", "3.0", "4"])
        self.positive = review(self.valid, 0)
        self.negative = review(self.invalid, 1, valid=False)

    def adapt_and_verify(self, rows):
        adapted = adapt_native_response(json.dumps({"reviews": rows}), "default_reviewer_v1")
        metrics = {}
        accepted = verify_questions(
            [self.valid, self.invalid], {"minimumDifficulty": 1}, lambda *_: adapted,
            metrics, preserve_reviewed_text=True,
        )
        return json.loads(adapted)["reviews"], accepted, metrics

    def test_rejected_feedback_is_discarded_while_positive_feedback_stays_exact(self):
        for reverse in (False, True):
            rows = [self.positive, self.negative]
            if reverse:
                rows.reverse()
            before = copy.deepcopy(rows)
            adapted, accepted, metrics = self.adapt_and_verify(rows)
            self.assertEqual(rows, before)
            rejected = next(row for row in adapted if row["valid"] is False)
            self.assertEqual(rejected, {"index": 1, "valid": False})
            self.assertEqual([q["prompt"] for q in accepted], [self.valid["prompt"]])
            self.assertEqual(accepted[0]["explanation"].encode(), self.positive["explanation"].encode())
            self.assertEqual(accepted[0]["choiceExplanations"], {
                row["choice"]: row["explanation"] for row in self.positive["choiceFeedback"]
            })
            self.assertEqual(metrics["QuestionQuality"]["review"]["rejected_by_model"], 1)

    def test_exact_failed_live_capture_retains_only_three_valid_controls(self):
        capture = json.loads((EVIDENCE / "native-reviewer-capture.json").read_text())
        plan = json.loads((EVIDENCE / "native-reviewer-plan.json").read_text())
        raw = capture["calls"][2]["provider_raw"]
        self.assertFalse(capture["calls"][2]["native_stage_valid"])

        class CapturedClient:
            calls = 0

            def converse(self, **_request):
                self.calls += 1
                return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": raw}]}}}

        client = CapturedClient()
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native"}):
            adapted = _generate_with_bedrock(
                {}, client, "us.anthropic.claude-sonnet-4-6", user_prompt="Offline capture replay",
                system_prompt="Review the unchanged synthetic controls.",
                contract="default_reviewer_v1", call_budget=ProviderCallBudget(1),
            )
        rows = json.loads(adapted)["reviews"]
        self.assertEqual(rows[2], {"index": 2, "valid": False})
        self.assertEqual(client.calls, 1)
        questions = [question(case["prompt"], case["expectedAnswer"], case["choices"])
                     for case in plan["expected_cases"]]
        metrics = {}
        accepted = verify_questions(questions, {"minimumDifficulty": 1}, lambda *_: adapted,
                                    metrics, preserve_reviewed_text=True)
        admitted = [case["id"] for case in plan["expected_cases"]
                    if any(q["prompt"] == case["prompt"] and q["choices"] == case["choices"] for q in accepted)]
        self.assertEqual(admitted, ["valid_arithmetic", "case_sensitive_valid", "operator_sensitive_valid"])
        self.assertEqual(metrics["QuestionQuality"]["review"]["rejected_by_model"], 5)

    def test_negative_rows_still_require_complete_schema_valid_types_and_fields(self):
        mutations = [
            {**self.negative, "valid": "false"}, {**self.negative, "valid": 0},
            {**self.negative, "index": True}, {**self.negative, "answer": None},
            {**self.negative, "difficulty": "1"}, {**self.negative, "explanation": []},
            {**self.negative, "choiceFeedback": {}},
            {**self.negative, "choiceFeedback": [{"choice": "2", "explanation": 3}]},
            {**self.negative, "choiceFeedback": [{"choice": "2", "explanation": "why", "repair": "other"}]},
            {**self.negative, "repair": "Replace the question."},
        ]
        mutations.extend({key: value for key, value in self.negative.items() if key != missing}
                         for missing in self.negative)
        for bad in mutations:
            with self.subTest(row=bad), self.assertRaises(ProviderError):
                self.adapt_and_verify([self.positive, bad])

    def test_negative_verdict_never_bypasses_strict_json(self):
        for raw in (
            '{"reviews":[],"reviews":[]}',
            '{"reviews":[],"repair":"other"}',
            '{"reviews":[{"index":1,"valid":true,"valid":false}]}',
            '{"reviews":[{"index":1,"valid":false,"difficulty":NaN}]}',
            '{"reviews":[{"index":1,"valid":false,"difficulty":1e309}]}',
            '{"reviews":[{"index":1,"valid":false,"choiceFeedback":[{"choice":"a","choice":"b"}]}]}',
            '```json\n{"reviews":[]}\n```',
        ):
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                adapt_native_response(raw, "default_reviewer_v1")

    def test_negative_index_is_preserved_for_batch_correlation_rejection(self):
        for index in (-1, 0, 2):
            with self.subTest(index=index):
                rows, accepted, metrics = self.adapt_and_verify([
                    self.positive, {**self.negative, "index": index},
                ])
                self.assertEqual(rows[1], {"index": index, "valid": False})
                self.assertEqual(accepted, [])
                self.assertEqual(metrics["QuestionQuality"]["review"]["invalid_index"], 2)

    def test_accepted_rows_keep_duplicate_feedback_and_answer_coverage_checks(self):
        malformed = {**self.positive, "choiceFeedback": [self.positive["choiceFeedback"][0]] * 2}
        with self.assertRaises(ProviderError):
            self.adapt_and_verify([malformed, self.negative])
        for positive in (
            {**self.positive, "answer": "5"},
            {**self.positive, "choiceFeedback": self.positive["choiceFeedback"][:3]},
        ):
            with self.subTest(positive=positive):
                _, accepted, _ = self.adapt_and_verify([positive, self.negative])
                self.assertEqual(accepted, [])


if __name__ == "__main__":
    unittest.main()
