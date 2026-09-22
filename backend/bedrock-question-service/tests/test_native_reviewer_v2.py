"""A negative verdict cannot carry learner feedback in the v2 transport."""

import copy
import json
import os
import unittest
from unittest.mock import patch

from jsonschema import Draft202012Validator

from lambda_test_support import FakeBedrockClient, _complete_solution, _raw_question, _request_payload
from native_output_contracts import (
    _validate_schema_value,
    adapt_native_response,
    contract_metadata,
    native_output_config,
)
from question_generation import ProviderCallBudget, _generate_sanitized_questions, _generate_with_bedrock
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import ProviderError
from test_native_output_contracts import Client
from test_native_pipeline import AUTHOR, REVIEWER, SOLVER, ScriptedNativeClient, review, task_data


# Exact rejected row from native-reviewer-capture.json, call 3, item 2. Its
# negative semantic judgment was well-formed under v1's schema, but its retained
# answer/feedback violated the separately enforced rejection representation.
CAPTURED_NEGATIVE = {
    "answer": "Two",
    "choiceFeedback": [
        {"choice": "Two", "explanation": "The word 'Two' names the number two, satisfying the fictional rule exactly."},
        {"choice": "Three", "explanation": "Three names the number three, not two."},
        {"choice": "The number three", "explanation": "This phrase also denotes three, not two; it duplicates 'Three' as a wrong answer."},
        {"choice": "Four", "explanation": "Four names the number four, not two."},
    ],
    "difficulty": 2,
    "explanation": "The stem defines the allowed answer as exactly two; only 'Two' satisfies that. 'Three' and 'The number three' are duplicates of each other as wrong answers, making this item defective.",
    "index": 2,
    "valid": False,
}


def schema(contract):
    return json.loads(native_output_config(contract)["textFormat"]["structure"]["jsonSchema"]["schema"])


class NativeReviewerV2Tests(unittest.TestCase):
    def setUp(self):
        self.question = _raw_question("Which conclusion follows from these stated conditions?")
        self.other = _raw_question("Which alternative follows from the different stated conditions?")
        self.request = _normalize_request(_request_payload(target_count=2))
        self.accepted = review(self.question)
        self.rejected = {"index": 1, "valid": False}

    def test_version_metadata_changes_without_rewriting_the_v1_schema(self):
        self.assertEqual(contract_metadata("default_reviewer_v1"), {
            "name": "default_reviewer_v1", "version": "1",
            "sha256": "77c15c631555d0d83bfaa2e0ba1c19478c51d2573586220cce2ce94684bfe2fe",
        })
        metadata = contract_metadata("default_reviewer_v2")
        self.assertEqual(metadata["version"], "2")
        self.assertNotEqual(metadata["sha256"], contract_metadata("default_reviewer_v1")["sha256"])
        Draft202012Validator.check_schema(schema("default_reviewer_v2"))

    def test_actual_captured_negative_is_schema_valid_v1_but_invalid_v2(self):
        payload = {"reviews": [CAPTURED_NEGATIVE]}
        Draft202012Validator(schema("default_reviewer_v1")).validate(payload)
        self.assertFalse(Draft202012Validator(schema("default_reviewer_v2")).is_valid(payload))
        for contract in ("default_reviewer_v1", "default_reviewer_v2"):
            with self.subTest(contract=contract), self.assertRaises(ProviderError):
                adapt_native_response(json.dumps(payload), contract)

    def test_minimal_negative_and_mixed_batch_preserve_only_approved_feedback(self):
        explanation = "  Exact explanation.\r\n    Preserve indentation and cafe\u0301.  "
        self.accepted["explanation"] = explanation
        self.accepted["choiceFeedback"][0]["explanation"] = explanation
        for rows in ([self.rejected], [self.accepted, self.rejected]):
            with self.subTest(rows=len(rows)):
                payload = {"reviews": rows}
                before = copy.deepcopy(payload)
                Draft202012Validator(schema("default_reviewer_v2")).validate(payload)
                adapted = json.loads(adapt_native_response(json.dumps(payload), "default_reviewer_v2"))
                self.assertEqual(adapted["reviews"][-1], self.rejected)
                self.assertEqual(payload, before)
                if len(rows) == 2:
                    self.assertEqual(adapted["reviews"][0]["explanation"].encode(), explanation.encode())
                    self.assertEqual(adapted["reviews"][0]["choiceExplanations"], {
                        item["choice"]: item["explanation"] for item in self.accepted["choiceFeedback"]
                    })

    def test_malformed_union_members_cannot_fall_through_to_acceptance(self):
        bad = [
            {**self.accepted, "valid": False},
            {**self.rejected, "answer": ""},
            {**self.rejected, "choiceFeedback": []},
            {**self.rejected, "explanation": ""},
            {**self.rejected, "difficulty": 0},
            {**self.rejected, "repair": "Use another question"},
            {**self.rejected, "valid": True},
            {**self.rejected, "valid": 0},
            {**self.accepted, "valid": 1},
            {**self.rejected, "valid": "false"},
            {**self.rejected, "index": True},
            {"index": 1}, {"valid": False},
            {**self.accepted, "choiceFeedback": [{"choice": "A", "explanation": "B", "unknown": True}]},
            {**self.accepted, "choiceFeedback": [self.accepted["choiceFeedback"][0]] * 2},
        ]
        for row in bad:
            with self.subTest(row=row), self.assertRaises(ProviderError):
                adapt_native_response(json.dumps({"reviews": [row]}), "default_reviewer_v2")

    def test_strict_json_rejects_duplicate_discriminators_nested_keys_and_unknown_envelopes(self):
        for raw in (
            '{"reviews":[{"index":0,"valid":true,"valid":false}]}',
            '{"reviews":[{"index":0,"index":1,"valid":false}]}',
            '{"reviews":[],"reviews":[]}',
            '{"reviews":[],"answer":"4"}',
            '{"reviews":[{"index":NaN,"valid":false}]}',
            '{"reviews":[{"index":1e309,"valid":false}]}',
            '```json\n{"reviews":[]}\n```',
        ):
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                adapt_native_response(raw, "default_reviewer_v2")

    def test_union_validator_does_not_ignore_siblings_or_invalid_union_definitions(self):
        for union in (
            {"anyOf": []}, {"anyOf": {}}, {"anyOf": [None]},
            {"anyOf": [{"type": "boolean"}], "enum": [True]},
        ):
            with self.subTest(union=union), self.assertRaises(ValueError):
                _validate_schema_value(False, union)

    def test_v1_negative_shape_and_explicit_transport_remain_compatible(self):
        old_negative = {"index": 0, "valid": False, "answer": "", "difficulty": 0,
                        "explanation": "", "choiceFeedback": []}
        client = Client({"reviews": [old_negative]})
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native"}):
            adapted = _generate_with_bedrock(
                {}, client, "us.anthropic.claude-sonnet-4-6", user_prompt="task", system_prompt="rules",
                contract="default_reviewer_v1",
            )
        self.assertEqual(json.loads(adapted)["reviews"][0]["choiceExplanations"], {})
        self.assertEqual(client.calls[0]["outputConfig"], native_output_config("default_reviewer_v1"))
        with self.assertRaises(ProviderError):
            adapt_native_response(json.dumps({"reviews": [self.rejected]}), "default_reviewer_v1")
        with self.assertRaises(ProviderError):
            adapt_native_response(json.dumps({"reviews": [old_negative]}), "default_reviewer_v2")

    def test_production_pipeline_keeps_v1_after_v2_failed_live_qualification(self):
        answers = {q["prompt"]: q["expectedAnswer"] for q in (self.question, self.other)}

        def solve(request):
            items = task_data(request, "question_solution_json")["items"]
            return {"solutions": [_complete_solution(item, answers[item["prompt"]]) for item in items]}

        client = ScriptedNativeClient(
            (AUTHOR, {"questions": [self.question, self.other]}),
            (SOLVER, solve),
            (REVIEWER, {"reviews": [self.accepted, {
                **self.rejected, "answer": "", "difficulty": 0, "explanation": "", "choiceFeedback": [],
            }]}),
        )
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
            "BEDROCK_MODEL_ID": "moonshotai.kimi-k2.5",
            "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
            "QUESTION_FEEDBACK_CONTRACT": "reviewer_written", "GENERATION_ATTEMPTS": "1",
        }):
            accepted = _generate_sanitized_questions(self.request, client, ProviderCallBudget(3), metrics)
        self.assertEqual([q["prompt"] for q in accepted], [self.question["prompt"]])
        self.assertEqual(accepted[0]["choiceExplanations"], {
            row["choice"]: row["explanation"] for row in self.accepted["choiceFeedback"]
        })
        self.assertEqual(metrics["QuestionQuality"]["review"]["rejected_by_model"], 1)
        self.assertEqual(client.calls[-1]["outputConfig"], native_output_config("default_reviewer_v1"))
        self.assertEqual(metrics["ProviderObservations"][-1]["structuredOutput"]["version"], "1")
        self.assertEqual(accepted[0]["verificationPolicyRevision"], 2)

    def test_explicit_v2_stage_adapts_mixed_feedback_without_promoting_rejections(self):
        client = Client({"reviews": [self.accepted, self.rejected]})
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native"}):
            adapted = _generate_with_bedrock(
                {}, client, "us.anthropic.claude-sonnet-4-6", user_prompt="task", system_prompt="rules",
                contract="default_reviewer_v2", request_metrics=metrics,
            )
        self.assertEqual(client.calls[-1]["outputConfig"], native_output_config("default_reviewer_v2"))
        self.assertEqual(metrics["ProviderObservations"][-1]["structuredOutput"]["version"], "2")
        admitted = verify_questions([self.question, self.other], self.request, lambda *_: adapted,
                                    preserve_reviewed_text=True)
        self.assertEqual([q["prompt"] for q in admitted], [self.question["prompt"]])
        self.assertEqual(admitted[0]["choiceExplanations"], {
            row["choice"]: row["explanation"] for row in self.accepted["choiceFeedback"]
        })

    def test_duplicate_indexes_remain_rejected_by_admission(self):
        payload = {"reviews": [self.accepted, {"index": 0, "valid": False}]}
        adapted = adapt_native_response(json.dumps(payload), "default_reviewer_v2")
        metrics = {}
        accepted = verify_questions([self.question, self.other], self.request, lambda *_: adapted, metrics)
        self.assertEqual(accepted, [])
        self.assertEqual(metrics["QuestionQuality"]["review"]["invalid_index"], 2)

    def test_legacy_pipeline_keeps_v1_identity_and_unconstrained_request_shape(self):
        client = FakeBedrockClient.returning_questions(self.question)
        request = _normalize_request(_request_payload(target_count=1))
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy",
            "QUESTION_FEEDBACK_CONTRACT": "reviewer_written", "GENERATION_ATTEMPTS": "1",
        }):
            accepted = _generate_sanitized_questions(request, client, ProviderCallBudget(3), metrics)
        self.assertEqual(len(accepted), 1)
        self.assertTrue(all("outputConfig" not in call
                            for call in client.calls + client.solution_calls + client.review_calls))
        observation = metrics["ProviderObservations"][-1]["structuredOutput"]
        self.assertEqual((observation["mode"], observation["name"], observation["version"]),
                         ("legacy", "default_reviewer_v1", "1"))


if __name__ == "__main__":
    unittest.main()
