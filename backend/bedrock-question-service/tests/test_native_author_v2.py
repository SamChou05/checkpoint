"""Fixed native author slots constrain counts and key membership, not truth."""

import copy
import hashlib
import itertools
import json
import os
import unittest
from unittest.mock import patch

from jsonschema import Draft202012Validator

from lambda_test_support import _raw_question, _request_payload
from native_output_contracts import (
    adapt_native_response,
    contract_metadata,
    native_output_config,
    native_prompt,
)
from question_generation import ProviderCallBudget, _generate_provider_payload, _generate_with_bedrock
from question_quality import _sanitize_questions
from request_contract import _normalize_request
from service_errors import ProviderError


CONTRACT = "question_author_v2"
SLOTS = ("a", "b", "c", "d")


def question():
    value = _raw_question("Which assumption connects the stated evidence to its conclusion?")
    value.pop("expectedAnswer")
    value["choices"] = dict(zip(SLOTS, value["choices"], strict=True))
    value["correctChoice"] = "a"
    return value


def raw(*questions):
    return json.dumps({"questions": list(questions)}, ensure_ascii=False)


def adapt(*questions):
    return json.loads(adapt_native_response(raw(*questions), CONTRACT))


class Client:
    def __init__(self, text):
        self.text = text
        self.calls = []

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return {
            "stopReason": "end_turn",
            "output": {"message": {"content": [{"text": self.text}]}},
            "usage": {"inputTokens": 11, "outputTokens": 7},
        }


class NativeAuthorV2Tests(unittest.TestCase):
    def setUp(self):
        self.declaration = native_output_config(CONTRACT)["textFormat"]["structure"]["jsonSchema"]
        self.schema = json.loads(self.declaration["schema"])

    def test_closed_slots_and_answer_enum_require_exactly_four_positions(self):
        Draft202012Validator.check_schema(self.schema)
        item = self.schema["properties"]["questions"]["items"]
        choices = item["properties"]["choices"]
        self.assertEqual(choices["type"], "object")
        self.assertFalse(choices["additionalProperties"])
        self.assertEqual(choices["required"], list(SLOTS))
        self.assertEqual(choices["properties"], dict.fromkeys(SLOTS, {"type": "string"}))
        self.assertEqual(item["properties"]["correctChoice"], {"type": "string", "enum": list(SLOTS)})
        self.assertNotIn("expectedAnswer", item["properties"])
        self.assertFalse(item["additionalProperties"])
        self.assertFalse(self.schema["additionalProperties"])
        self.assertNotIn("minItems", self.declaration["schema"])
        self.assertNotIn("maxItems", self.declaration["schema"])

    def test_each_key_and_every_object_order_maps_to_exact_slot_text(self):
        texts = ['  "e\u0301"\t ', '"a  b"', "−1", "None\r\n"]
        slots = dict(zip(SLOTS, texts, strict=True))
        for order in itertools.permutations(SLOTS):
            for selected in SLOTS:
                with self.subTest(order=order, selected=selected):
                    source = {
                        **question(), "choices": {key: slots[key] for key in order},
                        "correctChoice": selected,
                        "explanation": "The explanation deliberately mentions another answer.",
                    }
                    before = copy.deepcopy(source)
                    result = adapt(source)["questions"][0]
                    self.assertEqual(result["choices"], texts)
                    self.assertEqual(result["expectedAnswer"].encode(), slots[selected].encode())
                    self.assertEqual(result["explanation"], source["explanation"])
                    self.assertNotIn("correctChoice", result)
                    self.assertEqual(set(result), (set(source) - {"correctChoice"}) | {"expectedAnswer"})
                    self.assertEqual(source, before)

    def test_batch_order_and_optional_metadata_are_preserved_without_defaults(self):
        first = {**question(), "skillID": "  skill\t", "objectiveID": "", "objective": "cafe\u0301"}
        second = {**question(), "prompt": "A distinct complete question follows here.", "correctChoice": "d"}
        originals = copy.deepcopy([first, second])
        result = adapt(first, second)["questions"]
        self.assertEqual([row["prompt"] for row in result], [first["prompt"], second["prompt"]])
        for key in ("skillID", "objectiveID", "objective"):
            self.assertEqual(result[0][key].encode(), first[key].encode())
            self.assertNotIn(key, result[1])
        self.assertEqual([first, second], originals)
        self.assertEqual(adapt(), {"questions": []})

    def test_missing_extra_and_legacy_array_slots_fail_both_validators(self):
        base = question()
        mutations = [
            {**base, "choices": list(base["choices"].values())},
            {**base, "choices": {**base["choices"], "e": "Fifth option"}},
            {**base, "choices": {"A": "one", "b": "two", "c": "three", "d": "four"}},
        ]
        for slot in SLOTS:
            mutations.append({**base, "choices": {key: value for key, value in base["choices"].items() if key != slot}})
        for changed in mutations:
            with self.subTest(choices=changed["choices"]):
                self.assertFalse(Draft202012Validator(self.schema).is_valid({"questions": [changed]}))
                with self.assertRaises(ProviderError):
                    adapt(changed)

    def test_choice_and_selected_slot_types_and_enums_are_strict(self):
        base = question()
        for slot in SLOTS:
            for value in (None, True, False, 1, 1.0, [], {}):
                with self.subTest(slot=slot, value=value), self.assertRaises(ProviderError):
                    adapt({**base, "choices": {**base["choices"], slot: value}})
        for value in (None, True, False, 0, 1, 1.0, [], {}, "", "A", "e", "a ", base["choices"]["a"]):
            with self.subTest(correctChoice=value), self.assertRaises(ProviderError):
                adapt({**base, "correctChoice": value})

    def test_required_fields_unknown_fields_and_optional_null_rules_stay_strict(self):
        base = question()
        for key in base:
            with self.subTest(missing=key), self.assertRaises(ProviderError):
                adapt({name: value for name, value in base.items() if name != key})
            with self.subTest(null=key), self.assertRaises(ProviderError):
                adapt({**base, key: None})
        for key in ("skillID", "objectiveID", "objective"):
            for value in (None, True, 1, [], {}):
                with self.subTest(optional=key, value=value), self.assertRaises(ProviderError):
                    adapt({**base, key: value})
        for key, value in (
            ("expectedAnswer", base["choices"]["a"]), ("choiceExplanations", {}),
            ("verificationVersion", 1), ("verificationPolicyRevision", 99),
            ("repair", "other"), ("difficulty", True), ("difficulty", "3"),
            ("difficulty", 3.0), ("format", "multiple choice"),
        ):
            with self.subTest(key=key, value=value), self.assertRaises(ProviderError):
                adapt({**base, key: value})
        for payload in ({}, [], {"questions": {}}, {"questions": [], "answer": "a"}):
            with self.subTest(payload=payload), self.assertRaises(ProviderError):
                adapt_native_response(json.dumps(payload), CONTRACT)

    def test_strict_json_rejects_duplicate_slots_discriminators_and_nonfinite(self):
        valid = raw(question())
        for value in (
            valid.replace('"correctChoice": "a"', '"correctChoice": "a", "correctChoice": "b"'),
            valid.replace('"choices": {', '"choices": {"a": "Injected duplicate", ', 1),
            valid.replace('"difficulty": 3', '"difficulty": NaN'),
            valid.replace('"difficulty": 3', '"difficulty": Infinity'),
            valid.replace('"difficulty": 3', '"difficulty": 1e309'),
            '{"questions":[],"questions":[]}', '```json\n' + valid + '\n```',
            "Prose before " + valid, valid + " trailing prose",
        ):
            with self.subTest(raw=value), self.assertRaises(ProviderError):
                adapt_native_response(value, CONTRACT)

    def test_duplicate_choices_are_preserved_then_rejected_by_existing_admission(self):
        source = question()
        source["choices"]["d"] = source["choices"]["a"]
        adapted = adapt(source)["questions"]
        self.assertEqual(len(adapted[0]["choices"]), 4)
        self.assertEqual(adapted[0]["choices"][0], adapted[0]["choices"][3])
        self.assertEqual(adapted[0]["expectedAnswer"], adapted[0]["choices"][0])
        Draft202012Validator(self.schema).validate({"questions": [source]})
        metrics = {}
        request = _normalize_request(_request_payload(target_count=1))
        self.assertEqual(_sanitize_questions(adapted, request, metrics), [])
        self.assertEqual(metrics["QuestionQuality"]["sanitize"], {"invalid_choices": 1})

    def test_existing_admission_keeps_choice_and_prompt_bounds(self):
        request = _normalize_request(_request_payload(target_count=1))
        self.assertEqual(len(_sanitize_questions(adapt(question())["questions"], request)), 1)
        for source in (
            {**question(), "choices": {**question()["choices"], "d": "x" * 141}},
            {**question(), "choices": {**question()["choices"], "d": ""}},
            {**question(), "prompt": "x" * 321},
        ):
            with self.subTest(source=source):
                # The transport does not introduce unsupported length bounds
                # or silently repair content; existing admission still vetoes.
                adapted = adapt(source)["questions"]
                self.assertEqual(_sanitize_questions(adapted, request), [])

    def test_v1_hash_response_and_prompt_are_unchanged(self):
        self.assertEqual(contract_metadata("question_author_v1"), {
            "name": "question_author_v1", "version": "1",
            "sha256": "25c2c85d94ae1543ef4a46a3f97e845c37739cec5b77aacbf219d935a13df1a9",
        })
        text = raw(_raw_question("Which conclusion follows from the supplied evidence?"))
        self.assertEqual(adapt_native_response(text, "question_author_v1"), text)
        self.assertEqual(native_prompt("rules", "question_author_v1"),
                         "rules\n\nNATIVE TRANSPORT: Return only the JSON shape constrained by question_author_v1.")
        metadata = contract_metadata(CONTRACT)
        self.assertEqual(metadata["name"], CONTRACT)
        self.assertEqual(metadata["version"], "2")
        self.assertEqual(metadata["sha256"], hashlib.sha256(self.declaration["schema"].encode()).hexdigest())

    def test_explicit_native_request_uses_v2_then_adapts_to_public_shape(self):
        source = question()
        source["correctChoice"] = "c"
        client = Client(raw(source))
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        budget = ProviderCallBudget(1)
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native"}):
            result = _generate_with_bedrock(
                {}, client, "us.anthropic.claude-sonnet-4-6", system_prompt="Original author rules",
                user_prompt="Synthetic question task", call_budget=budget,
                request_metrics=metrics, contract=CONTRACT,
            )
        self.assertEqual(json.loads(result), adapt(source))
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(budget.calls, 1)
        request = client.calls[0]
        self.assertEqual(request["outputConfig"], native_output_config(CONTRACT))
        self.assertEqual(request["system"][0]["text"], native_prompt("Original author rules", CONTRACT))
        self.assertIn("Do not return expectedAnswer", request["system"][0]["text"])
        self.assertEqual(metrics["ProviderObservations"][0]["structuredOutput"],
                         {"mode": "native", **contract_metadata(CONTRACT)})
        from botocore.session import get_session
        from botocore.validate import validate_parameters
        shape = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        validate_parameters(request, shape)

    def test_legacy_author_orchestration_keeps_v1_identity(self):
        source = _raw_question("Which conclusion follows from the supplied evidence?")
        client = Client(raw(source))
        request = _normalize_request(_request_payload(target_count=1))
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy",
            "BEDROCK_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
            "BEDROCK_FALLBACK_MODEL_ID": "",
        }):
            result = _generate_provider_payload(request, client, ProviderCallBudget(1), metrics)
        self.assertEqual(result, {"questions": [source]})
        self.assertNotIn("outputConfig", client.calls[0])
        self.assertEqual(metrics["ProviderObservations"][0]["structuredOutput"],
                         {"mode": "legacy", **contract_metadata("question_author_v1")})


if __name__ == "__main__":
    unittest.main()
