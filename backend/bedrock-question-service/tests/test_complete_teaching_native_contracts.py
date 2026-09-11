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
    native_prompt,
)
from question_generation import ProviderCallBudget, _generate_with_bedrock
from service_errors import ProviderError


AUTHOR = "question_author_complete_v1"
REVIEWER = "complete_teaching_reviewer_v1"


def author_payload():
    choices = ['print(" a  b ")', 'print("a b")', "cafe\u0301", "x != y"]
    return {"questions": [{
        "prompt": 'Read the literal exactly:\n    value = " a  b "\nWhich expression preserves it?',
        "explanation": '  The literal preserves leading, internal, and trailing spaces.\n',
        "expectedAnswer": choices[0],
        "choices": choices,
        "choiceFeedback": [
            {"choice": choice, "explanation": f'  Exact feedback for {choice}: Ω.\n'}
            for choice in reversed(choices)
        ],
        "topic": "Quoted whitespace", "difficulty": 3, "format": "Multiple Choice",
        "skillID": " original skill ", "objectiveID": " original objective ",
        "objective": " Preserve the original objective label. ",
    }]}


def review_payload():
    choices = author_payload()["questions"][0]["choices"]
    return {"reviews": [{
        "index": 0, "valid": True, "answer": choices[0], "difficulty": 3,
        "explanationSupport": "supported",
        "choiceFeedbackSupport": [
            {"choice": choice, "feedbackSupport": "supported", "displaySupport": "supported"}
            for choice in choices
        ],
        "issues": [],
    }]}


class Client:
    def __init__(self, payload):
        self.payload = payload
        self.calls = []

    def converse(self, **request):
        self.calls.append(request)
        return {"stopReason": "end_turn", "output": {"message": {"content": [
            {"text": json.dumps(self.payload, ensure_ascii=False)},
        ]}}}


class CompleteTeachingNativeContractTests(unittest.TestCase):
    def test_complete_author_extends_original_shape_and_preserves_wire_order(self):
        original = json.loads(native_output_config("question_author_v1")["textFormat"]["structure"]["jsonSchema"]["schema"])
        declaration = native_output_config(AUTHOR)["textFormat"]["structure"]["jsonSchema"]
        complete = json.loads(declaration["schema"])
        item = complete["properties"]["questions"]["items"]
        self.assertEqual(list(item["properties"]), [
            "prompt", "explanation", "expectedAnswer", "choices", "choiceFeedback",
            "topic", "difficulty", "format", "skillID", "objectiveID", "objective",
        ])
        feedback_schema = item["properties"].pop("choiceFeedback")
        item["required"].remove("choiceFeedback")
        self.assertEqual(complete, original)
        self.assertEqual(feedback_schema, {"type": "array", "items": {
            "type": "object", "properties": {"choice": {"type": "string"}, "explanation": {"type": "string"}},
            "required": ["choice", "explanation"], "additionalProperties": False,
        }})
        self.assertEqual(contract_metadata(AUTHOR)["sha256"], hashlib.sha256(declaration["schema"].encode()).hexdigest())

    def test_complete_author_adapter_preserves_all_content_and_property_order(self):
        payload = author_payload()
        original = copy.deepcopy(payload)
        raw = json.dumps(payload, ensure_ascii=False)
        result = json.loads(adapt_native_response(raw, AUTHOR))
        before, after = payload["questions"][0], result["questions"][0]
        self.assertEqual(list(after), ["choiceExplanations" if key == "choiceFeedback" else key for key in before])
        for field, value in before.items():
            if field != "choiceFeedback":
                self.assertEqual(after[field], value)
        self.assertEqual(list(after["choiceExplanations"]), [row["choice"] for row in before["choiceFeedback"]])
        self.assertEqual(after["choiceExplanations"], {row["choice"]: row["explanation"] for row in before["choiceFeedback"]})
        self.assertEqual(payload, original)
        self.assertEqual(raw, json.dumps(original, ensure_ascii=False))

    def test_complete_author_rejects_incomplete_duplicate_extra_and_renamed_choices(self):
        cases = []
        for size in (0, 1, 3, 5):
            payload = author_payload()
            question = payload["questions"][0]
            question["choices"] = [f"choice {index}" for index in range(size)]
            question["choiceFeedback"] = [
                {"choice": choice, "explanation": "Complete enough feedback text."} for choice in question["choices"]
            ]
            cases.append((f"coordinated cardinality {size}", payload))
        for name in ("missing feedback", "extra feedback", "duplicate feedback", "renamed feedback",
                     "normalized Unicode feedback", "duplicate offered choice", "missing offered choice"):
            payload = author_payload()
            question = payload["questions"][0]
            rows = question["choiceFeedback"]
            if name == "missing feedback":
                rows.pop()
            elif name == "extra feedback":
                rows.append({"choice": "unoffered", "explanation": "New feedback text."})
            elif name == "duplicate feedback":
                rows[1] = copy.deepcopy(rows[0])
            elif name == "renamed feedback":
                rows[0]["choice"] = "x == y"
            elif name == "normalized Unicode feedback":
                rows[1]["choice"] = "café"
            elif name == "duplicate offered choice":
                question["choices"][1] = question["choices"][0]
            else:
                question["choices"].pop()
            cases.append((name, payload))
        for name, payload in cases:
            with self.subTest(name=name), self.assertRaises(ProviderError):
                adapt_native_response(json.dumps(payload), AUTHOR)

    def test_complete_author_transport_refuses_maps_and_unknown_replacement_fields(self):
        cases = []
        for field in ("choiceFeedback", "prompt", "choices", "expectedAnswer", "explanation"):
            payload = author_payload()
            del payload["questions"][0][field]
            cases.append(payload)
        for field in ("choiceExplanations", "replacementPrompt", "verificationPolicyRevision"):
            payload = author_payload()
            payload["questions"][0][field] = {} if field == "choiceExplanations" else "unapproved"
            cases.append(payload)
        for field, value in (("choice", None), ("explanation", False), ("replacement", "new text")):
            payload = author_payload()
            payload["questions"][0]["choiceFeedback"][0][field] = value
            cases.append(payload)
        for payload in cases:
            with self.subTest(payload=payload), self.assertRaises(ProviderError):
                adapt_native_response(json.dumps(payload), AUTHOR)

    def test_complete_reviewer_preserves_raw_declarations_for_core_gate(self):
        # Unsupported/uncertain declarations must remain expressible. The
        # immutable teaching gate decides admission after transport validation.
        for state in ("supported", "unsupported", "uncertain"):
            payload = review_payload()
            row = payload["reviews"][0]
            row["explanationSupport"] = state
            row["choiceFeedbackSupport"][0]["feedbackSupport"] = state
            row["choiceFeedbackSupport"][1]["displaySupport"] = state
            row["issues"] = [] if state == "supported" else ["Preserve this unresolved issue exactly.  "]
            row["valid"] = state == "supported"
            if not row["valid"]:
                row["answer"] = ""
            raw = " \n" + json.dumps(payload, ensure_ascii=False, indent=2) + "\n "
            with self.subTest(state=state):
                self.assertEqual(adapt_native_response(raw, REVIEWER), raw)

    def test_complete_reviewer_rejects_rewrites_missing_fields_and_invalid_support(self):
        cases = []
        for field in review_payload()["reviews"][0]:
            payload = review_payload()
            del payload["reviews"][0][field]
            cases.append((f"missing {field}", payload))
        for field in ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations", "choiceFeedback", "replacement"):
            payload = review_payload()
            payload["reviews"][0][field] = "replacement text"
            cases.append((f"forbidden {field}", payload))
        for field in ("feedbackSupport", "displaySupport"):
            for value in ("approved", None, True):
                payload = review_payload()
                payload["reviews"][0]["choiceFeedbackSupport"][0][field] = value
                cases.append((f"invalid {field} {value}", payload))
        for field in ("choice", "feedbackSupport", "displaySupport"):
            payload = review_payload()
            del payload["reviews"][0]["choiceFeedbackSupport"][0][field]
            cases.append((f"missing nested {field}", payload))
        payload = review_payload()
        payload["reviews"][0]["choiceFeedbackSupport"][0]["explanation"] = "replacement teaching"
        cases.append(("nested rewrite", payload))
        for name, payload in cases:
            with self.subTest(name=name), self.assertRaises(ProviderError):
                adapt_native_response(json.dumps(payload), REVIEWER)

    def test_new_contracts_are_closed_valid_schemas_with_no_new_provider_keywords(self):
        from jsonschema import Draft202012Validator

        allowed_keywords = {"type", "properties", "required", "additionalProperties", "items", "enum"}

        def check_shape(schema):
            self.assertLessEqual(set(schema), allowed_keywords)
            if schema["type"] == "object":
                self.assertFalse(schema["additionalProperties"])
                for child in schema["properties"].values():
                    check_shape(child)
            if schema["type"] == "array":
                check_shape(schema["items"])

        for contract, payload in ((AUTHOR, author_payload()), (REVIEWER, review_payload())):
            with self.subTest(contract=contract):
                config = native_output_config(contract)
                declaration = config["textFormat"]["structure"]["jsonSchema"]
                schema = json.loads(declaration["schema"])
                Draft202012Validator.check_schema(schema)
                Draft202012Validator(schema).validate(payload)
                check_shape(schema)
                self.assertEqual(contract_metadata(contract)["sha256"], hashlib.sha256(declaration["schema"].encode()).hexdigest())
                config["textFormat"]["structure"]["jsonSchema"]["schema"] = "mutated"
                self.assertNotEqual(config, native_output_config(contract))

    def test_new_contracts_cross_actual_request_boundary_with_exact_transport(self):
        from botocore.session import get_session
        from botocore.validate import validate_parameters

        shape = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        for contract, payload in ((AUTHOR, author_payload()), (REVIEWER, review_payload())):
            client = Client(payload)
            metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
            with self.subTest(contract=contract), patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native"}):
                raw = _generate_with_bedrock(
                    {}, client, "us.anthropic.claude-sonnet-4-6", user_prompt="exact subject input",
                    system_prompt="original audit rules", contract=contract,
                    call_budget=ProviderCallBudget(1), request_metrics=metrics,
                )
            self.assertEqual(len(client.calls), 1)
            request = client.calls[0]
            self.assertEqual(request["outputConfig"], native_output_config(contract))
            self.assertEqual(request["system"][0]["text"], native_prompt("original audit rules", contract))
            self.assertEqual(request["messages"][0]["content"][0]["text"], "exact subject input")
            validate_parameters(request, shape)
            if contract == AUTHOR:
                self.assertIn("exactly four choiceFeedback rows", request["system"][0]["text"])
                self.assertIn("prompt, explanation, expectedAnswer, choices, then choiceFeedback", request["system"][0]["text"])
                self.assertEqual(json.loads(raw)["questions"][0]["choices"], payload["questions"][0]["choices"])
                self.assertIn("choiceExplanations", json.loads(raw)["questions"][0])
            else:
                self.assertEqual(json.loads(raw), payload)
            self.assertEqual(metrics["ProviderObservations"][0]["structuredOutput"], {
                "mode": "native", **contract_metadata(contract),
            })

    def test_existing_contract_schema_and_prompt_bytes_remain_frozen(self):
        expected = {
            "question_author_v1": (
                "76fcf193d302609a08a116d9a168e0b8dfc9ea662a44fb5287cf7ca46b9294f5",
                "f87e3c4e19fbeef719df6b12de8971bc39388afa70b75483d5ada40bf6c679b4",
            ),
            "skill_map_inference_v1": (
                "593bb052a930a26472f02be9459740da03d7cd4f015fd17284afa797f5eac82a",
                "14557028c65ccbd2124b4d912e18a5b1db1253e45458586c8bba44854b990e6f",
            ),
            "skill_map_evolution_v1": (
                "4929d715823f9b87f0a9add73851cad47a5ef36cc5da03d45aa9834aeabd4ad1",
                "94813d244ee95e8018cc9038b9b90dd7c8b47df41a6fa3adf67e6a86458c2225",
            ),
            "complete_choice_solver_v1": (
                "12ad4fefd897015baa60b400ae9b6f3006aeeda34b57de1dabfb344f5e6c5e61",
                "4e07ac82064570cce6adecc235a8b40915bc1008c24fc00d18f131b8f0efa2c0",
            ),
            "default_reviewer_v1": (
                "77c15c631555d0d83bfaa2e0ba1c19478c51d2573586220cce2ce94684bfe2fe",
                "793335e726fe595f642b322cb7ae9d8b4bcb12e37639eb46c21f76cfc9bcdef2",
            ),
            "authored_solution_reviewer_v1": (
                "d965da2f5a514961f173fcf232368f0b887505774e2982f1ada7ebe565ebc501",
                "54b14768cc0ee7fbb89c8e5720ca7d97412fcb43c875380ecb5b8decaf512a76",
            ),
        }
        for contract, (schema_hash, prompt_hash) in expected.items():
            with self.subTest(contract=contract):
                schema = native_output_config(contract)["textFormat"]["structure"]["jsonSchema"]["schema"]
                self.assertEqual(hashlib.sha256(schema.encode()).hexdigest(), schema_hash)
                self.assertEqual(hashlib.sha256(native_prompt("original audit rules", contract).encode()).hexdigest(), prompt_hash)

    def test_existing_adapters_keep_their_original_coverage_and_raw_byte_behavior(self):
        # Historical author schemas admit partial choice arrays; historical
        # review adapters leave exact four-choice admission to their core gate.
        payload = author_payload()
        question = payload["questions"][0]
        del question["choiceFeedback"]
        question["choices"] = question["choices"][:2]
        raw = " \n" + json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        self.assertEqual(adapt_native_response(raw, "question_author_v1"), raw)
        old_review = {"reviews": [{
            "index": 0, "valid": True, "answer": "exact", "difficulty": 3,
            "explanation": " original teaching  ",
            "choiceFeedback": [{"choice": "exact", "explanation": " original choice teaching  "}],
        }]}
        expected = copy.deepcopy(old_review)
        del expected["reviews"][0]["choiceFeedback"]
        expected["reviews"][0]["choiceExplanations"] = {"exact": " original choice teaching  "}
        self.assertEqual(adapt_native_response(json.dumps(old_review), "default_reviewer_v1"),
                         json.dumps(expected, ensure_ascii=False, allow_nan=False))


if __name__ == "__main__":
    unittest.main()
