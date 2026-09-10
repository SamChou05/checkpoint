import copy
import hashlib
import json
import os
import unittest
from unittest.mock import patch

from native_output_contracts import (
    adapt_native_response,
    contract_metadata,
    native_output_config,
)
from question_generation import ProviderCallBudget, _generate_with_bedrock
from service_errors import ProviderError, ServiceConfigurationError


class Client:
    def __init__(self, payload, stop_reason="end_turn"):
        self.payload = payload
        self.stop_reason = stop_reason
        self.calls = []

    def converse(self, **request):
        self.calls.append(request)
        return {"stopReason": self.stop_reason, "output": {"message": {"content": [
            {"text": json.dumps(self.payload, ensure_ascii=False)}
        ]}}}


class NativeOutputContractTests(unittest.TestCase):
    def test_every_contract_has_stable_independent_closed_schema(self):
        names = [
            "question_author_v1", "skill_map_inference_v1", "skill_map_evolution_v1",
            "complete_choice_solver_v1", "default_reviewer_v1",
            "authored_solution_reviewer_v1",
        ]
        for name in names:
            first = native_output_config(name)
            second = native_output_config(name)
            self.assertEqual(first, second)
            self.assertIsNot(first, second)
            schema = json.loads(first["textFormat"]["structure"]["jsonSchema"]["schema"])
            self.assertFalse(schema["additionalProperties"])
            first["textFormat"]["structure"]["jsonSchema"]["name"] = "mutated"
            self.assertEqual(second["textFormat"]["structure"]["jsonSchema"]["name"], name)

    def test_native_author_request_sends_named_schema_and_matching_prompt(self):
        client = Client({"questions": []})
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native"}, clear=False):
            raw = _generate_with_bedrock(
                {}, client, "us.anthropic.claude-sonnet-4-6-v1:0",
                system_prompt="author rules", user_prompt="task",
                contract="question_author_v1", call_budget=ProviderCallBudget(1),
            )
        self.assertEqual(json.loads(raw), {"questions": []})
        request = client.calls[0]
        self.assertEqual(
            request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"],
            "question_author_v1",
        )
        self.assertIn("question_author_v1", request["system"][0]["text"])

    def test_packaged_botocore_service_model_accepts_exact_native_request(self):
        from botocore.session import get_session
        from botocore.validate import validate_parameters

        request = {
            "modelId": "us.anthropic.claude-sonnet-4-6-v1:0",
            "messages": [{"role": "user", "content": [{"text": "task"}]}],
            "system": [{"text": "rules"}],
            "inferenceConfig": {"maxTokens": 6000, "temperature": 0.2},
            "outputConfig": native_output_config("question_author_v1"),
        }
        shape = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        validate_parameters(request, shape)

    def test_legacy_mode_preserves_request_shape(self):
        client = Client({"questions": []})
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"}, clear=False):
            _generate_with_bedrock(
                {}, client, "amazon.nova-lite-v1:0", user_prompt="task",
                system_prompt="rules", contract="question_author_v1",
            )
        self.assertNotIn("outputConfig", client.calls[0])

    def test_native_mode_fails_before_call_for_missing_contract_or_unsupported_model(self):
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native"}, clear=False):
            for contract, model in [(None, "us.anthropic.claude-sonnet-4-6-v1:0"),
                                    ("question_author_v1", "amazon.nova-lite-v1:0")]:
                client = Client({"questions": []})
                with self.assertRaises(ServiceConfigurationError):
                    _generate_with_bedrock(
                        {}, client, model, user_prompt="task", system_prompt="rules",
                        contract=contract,
                    )
                self.assertEqual(client.calls, [])

    def test_reviewer_adapter_preserves_exact_bytes_and_rejects_duplicates(self):
        choice = "cafe\u0301"
        raw = json.dumps({"reviews": [{
            "index": 0, "valid": True, "answer": choice, "difficulty": 3,
            "explanation": "exact", "choiceFeedback": [
                {"choice": choice, "explanation": "combining bytes retained"},
                {"choice": "B", "explanation": "b"},
            ],
        }]}, ensure_ascii=False)
        adapted = json.loads(adapt_native_response(raw, "default_reviewer_v1"))
        self.assertEqual(list(adapted["reviews"][0]["choiceExplanations"])[0], choice)
        duplicate = raw.replace(
            '{"choice": "B", "explanation": "b"}',
            json.dumps({"choice": choice, "explanation": "again"}, ensure_ascii=False),
        )
        with self.assertRaises(ProviderError):
            adapt_native_response(duplicate, "default_reviewer_v1")

    def test_native_validation_rejects_extra_missing_wrong_enum_and_nonfinite(self):
        bad = [
            '{"solutions":[],"extra":true}',
            '{}',
            '{"solutions":[{"index":0,"choices":[{"choice":"A","judgment":"yes","reason":"x"}]}]}',
            '{"solutions":[{"index":NaN,"choices":[]}]}',
        ]
        for raw in bad:
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                adapt_native_response(raw, "complete_choice_solver_v1")

    def test_rejected_native_review_cannot_smuggle_answer_or_feedback(self):
        raw = json.dumps({"reviews": [{
            "index": 0, "valid": False, "answer": "A", "difficulty": 3,
            "explanation": "no", "choiceFeedback": [],
        }]})
        with self.assertRaises(ProviderError):
            adapt_native_response(raw, "default_reviewer_v1")

    def test_native_refusal_is_not_parsed_or_retried_unconstrained(self):
        client = Client({"questions": []}, stop_reason="content_filtered")
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native"}, clear=False):
            with self.assertRaises(ProviderError):
                _generate_with_bedrock(
                    {}, client, "us.anthropic.claude-sonnet-4-6-v1:0",
                    user_prompt="task", system_prompt="rules",
                    contract="question_author_v1", request_metrics=metrics,
                )
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(metrics["ProviderCalls"], 1)


    def test_each_stage_accepts_its_positive_fixture_and_rejects_shape_mutations(self):
        from jsonschema import Draft202012Validator

        fixtures = {
            "question_author_v1": {"questions": [{
                "prompt": "What follows from the stated conditions?", "choices": ["yes", "no", "zero", "unknown"],
                "expectedAnswer": "yes", "explanation": "The stated conditions establish the result.",
                "topic": "Reasoning", "difficulty": 3, "format": "Multiple Choice",
            }]},
            "skill_map_inference_v1": {"skills": [{
                "name": "Reasoning", "objectives": [{"name": "Assess evidence"}],
            }]},
            "skill_map_evolution_v1": {"changes": [{
                "action": "advance", "predecessorSkillID": "task-owned-id",
                "successor": {"name": "Advanced reasoning", "objectives": [{"name": "Weigh alternatives"}]},
            }]},
            "complete_choice_solver_v1": {"solutions": [{"index": 0, "choices": [
                {"choice": "yes", "judgment": "supported", "reason": "The evidence establishes this result."},
                {"choice": "no", "judgment": "uncertain", "reason": "A required premise is unstated."},
                {"choice": "zero", "judgment": "refuted", "reason": "The premise contradicts this result."},
            ]}]},
            "default_reviewer_v1": {"reviews": [{
                "index": 0, "valid": True, "answer": "yes", "difficulty": 3,
                "explanation": "The evidence establishes this result.",
                "choiceFeedback": [{"choice": "yes", "explanation": "This follows from the evidence."}],
            }]},
            "authored_solution_reviewer_v1": {"reviews": [{
                "index": 0, "valid": True, "answer": "yes", "difficulty": 3,
                "explanationSupport": "supported", "issues": [],
            }]},
        }
        for contract, payload in fixtures.items():
            with self.subTest(contract=contract):
                declaration = native_output_config(contract)["textFormat"]["structure"]["jsonSchema"]
                schema = json.loads(declaration["schema"])
                Draft202012Validator.check_schema(schema)
                Draft202012Validator(schema).validate(payload)
                self.assertIsInstance(json.loads(adapt_native_response(json.dumps(payload), contract)), dict)
                self.assertNotIn("task-owned-id", declaration["schema"])
                self.assertEqual(contract_metadata(contract)["sha256"], hashlib.sha256(declaration["schema"].encode()).hexdigest())
                envelope = next(iter(payload))
                mutations = []
                for field in payload[envelope][0]:
                    missing = copy.deepcopy(payload)
                    del missing[envelope][0][field]
                    mutations.append((f"missing {field}", missing))
                    wrong_type = copy.deepcopy(payload)
                    wrong_type[envelope][0][field] = None
                    mutations.append((f"null {field}", wrong_type))
                mutations.extend([
                    ("root array", []),
                    ("missing envelope", {}),
                    ("non-array collection", {envelope: {}}),
                    ("unknown root field", {**payload, "verdict": "invalid"}),
                    ("unknown item field", {envelope: [{**payload[envelope][0], "verdict": "invalid"}]}),
                ])
                for name, bad in mutations:
                    with self.subTest(mutation=name), self.assertRaises(ProviderError):
                        adapt_native_response(json.dumps(bad), contract)

    def test_nested_fields_and_enums_reject_unknown_or_wrong_types(self):
        invalid = [
            ("question_author_v1", {"questions": [{"prompt": "A complete question?", "choices": [1],
                "expectedAnswer": "A", "explanation": "Because of the stated condition.", "topic": "Logic",
                "difficulty": True, "format": "Free Response"}]}),
            ("skill_map_inference_v1", {"skills": [{"name": "Logic", "objectives": [{"name": "Infer", "id": "provider-id"}]}]}),
            ("skill_map_evolution_v1", {"changes": [{"action": "retain", "predecessorSkillID": "id",
                "successor": {"name": "Logic", "objectives": [{"name": "Infer"}]}}]}),
            ("skill_map_evolution_v1", {"changes": [{"action": "advance", "predecessorSkillID": "id",
                "successor": {"name": "Logic", "objectives": ["Infer"]}}]}),
            ("complete_choice_solver_v1", {"solutions": [{"index": True, "choices": []}]}),
            ("complete_choice_solver_v1", {"solutions": [{"index": 0, "choices": [{"choice": "A", "judgment": "supported", "reason": "Because", "answer": "A"}]}]}),
            ("default_reviewer_v1", {"reviews": [{"index": 0, "valid": "true", "answer": "A", "difficulty": 3, "explanation": "Because", "choiceFeedback": []}]}),
            ("default_reviewer_v1", {"reviews": [{"index": 0, "valid": True, "answer": "A", "difficulty": 3, "explanation": "Because", "choiceFeedback": [{"choice": "A", "explanation": "Because", "issues": []}]}]}),
            ("authored_solution_reviewer_v1", {"reviews": [{"index": 0, "valid": True, "answer": "A", "difficulty": 3, "explanationSupport": "yes", "issues": []}]}),
            ("authored_solution_reviewer_v1", {"reviews": [{"index": 0, "valid": True, "answer": "A", "difficulty": 3, "explanationSupport": "supported", "issues": [False]}]}),
        ]
        for contract, payload in invalid:
            with self.subTest(contract=contract, payload=payload), self.assertRaises(ProviderError):
                adapt_native_response(json.dumps(payload), contract)

    def test_native_contracts_express_empty_and_negative_results_without_forcing_acceptance(self):
        for contract, key in (("question_author_v1", "questions"), ("skill_map_inference_v1", "skills"),
                              ("skill_map_evolution_v1", "changes"), ("complete_choice_solver_v1", "solutions")):
            raw = json.dumps({key: []})
            self.assertEqual(adapt_native_response(raw, contract), raw)
        rejected = {"reviews": [{"index": 0, "valid": False, "answer": "", "difficulty": 3,
                                 "explanation": "", "choiceFeedback": []}]}
        adapted = json.loads(adapt_native_response(json.dumps(rejected), "default_reviewer_v1"))
        self.assertEqual(adapted["reviews"][0]["choiceExplanations"], {})
        for support in ("supported", "unsupported", "uncertain"):
            payload = {"reviews": [{"index": 0, "valid": False, "answer": "", "difficulty": 3,
                                    "explanationSupport": support, "issues": ["The evidence is insufficient."]}]}
            raw = json.dumps(payload)
            self.assertEqual(adapt_native_response(raw, "authored_solution_reviewer_v1"), raw)

    def test_native_strict_json_rejects_duplicate_nested_keys_and_overflowing_numbers(self):
        for raw in ('{"questions":[],"questions":[]}',
                    '{"questions":[{"difficulty":3,"difficulty":4}]}',
                    '{"questions":[{"difficulty":1e309}]}',
                    '{"questions":[{"difficulty":Infinity}]}',
                    '{"questions":[{"difficulty":-Infinity}]}'):
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                adapt_native_response(raw, "question_author_v1")

    def test_native_feedback_adapter_preserves_newlines_indentation_and_unicode(self):
        choices = ["cafe\u0301", "print(\"one\")\n    return 1", "漢字", "no"]
        explanation = "  A line of teaching.\r\n    Its indentation is meaningful.  "
        payload = {"reviews": [{"index": 0, "valid": True, "answer": choices[0], "difficulty": 3,
                                "explanation": explanation, "choiceFeedback": [
                                    {"choice": c, "explanation": explanation} for c in reversed(choices)]}]}
        result = json.loads(adapt_native_response(json.dumps(payload, ensure_ascii=False), "default_reviewer_v1"))["reviews"][0]
        self.assertEqual(result["explanation"].encode(), explanation.encode())
        self.assertEqual(list(result["choiceExplanations"]), list(reversed(choices)))
        for key, value in result["choiceExplanations"].items():
            self.assertIn(key.encode(), [c.encode() for c in choices])
            self.assertEqual(value.encode(), explanation.encode())

    def test_native_incomplete_stops_and_sdk_errors_consume_one_accounted_attempt(self):
        from botocore.exceptions import ParamValidationError

        for stop in ("max_tokens", "content_filtered", "tool_use", None):
            with self.subTest(stop=stop):
                client = Client({"questions": []}, stop_reason=stop)
                metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
                budget = ProviderCallBudget(2)
                with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native"}):
                    with self.assertRaises(ProviderError):
                        _generate_with_bedrock({}, client, "us.anthropic.claude-sonnet-4-6",
                            user_prompt="task", system_prompt="rules", contract="question_author_v1",
                            request_metrics=metrics, call_budget=budget)
                self.assertEqual(len(client.calls), 1)
                self.assertEqual(metrics["ProviderCalls"], 1)
                self.assertEqual(budget.calls, 1)
        class UnsupportedSDK:
            def converse(self, **_request):
                raise ParamValidationError(report="Unknown parameter outputConfig")
        budget = ProviderCallBudget(2)
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native"}):
            with self.assertRaises(ServiceConfigurationError):
                _generate_with_bedrock({}, UnsupportedSDK(), "us.anthropic.claude-sonnet-4-6",
                    user_prompt="task", system_prompt="rules", contract="question_author_v1", call_budget=budget)
        self.assertEqual(budget.calls, 1)


if __name__ == "__main__":
    unittest.main()
