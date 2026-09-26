"""Count-bound native author transport, without provider calls."""

import copy
import json
import os
import unittest
from unittest.mock import patch

from botocore.session import get_session
from botocore.validate import validate_parameters
from jsonschema import Draft202012Validator

import question_generation as generation
from lambda_test_support import _request_payload
from native_output_contracts import (
    AuthorSlotContract, _contract_schema, _validate_schema_value,
    adapt_native_response, contract_metadata, native_output_config, native_prompt,
)
from request_contract import _normalize_request
from service_errors import ProviderError, ServiceConfigurationError
from test_native_pipeline import ScriptedNativeClient


HISTORICAL_HASHES = {
    "question_author_v1": "25c2c85d94ae1543ef4a46a3f97e845c37739cec5b77aacbf219d935a13df1a9",
    "question_author_v2": "abc583c2eecbd461b3c4852170aeadabf5437ff46b65257f14325488b34dd813",
    "question_author_v3": "94ab5d7cb7661085e66e2c8d7c860cd2378f8d9ef8f133326c49ddcffb7bfcd9",
    "question_author_mixed_v1": "b04914293b719243a6139b5090d5c5d6117da8a5e0c7bd51c4637b6c233edc6c",
    "question_author_constructed_v1": "a6bcb84b4ca15b1a5b3b789b92f65f12e5d3caa81658ae805b7c06413bc20ac8",
}
MODES = ("prose", "mixed_quantitative", "constructed_quantitative")


def prose(index):
    return {
        "prompt": f"Which statement follows from case {index}?",
        "choices": {"a": f"Correct {index}", "b": f"Wrong B {index}",
                    "c": f"Wrong C {index}", "d": f"Wrong D {index}"},
        "explanation": f"The supplied conditions establish case {index}.",
        "correctChoice": "a", "topic": "Logic", "difficulty": 2,
        "format": "Multiple Choice",
    }


def row(mode, index):
    question = prose(index)
    return question if mode == "prose" else {"kind": "prose", "question": question}


def payload(mode, count):
    return {"questions": {str(index): row(mode, index) for index in range(count)}}


def expand(value, definitions):
    if isinstance(value, list):
        return [expand(item, definitions) for item in value]
    if isinstance(value, dict):
        if "$ref" in value:
            assert set(value) == {"$ref"}
            assert value["$ref"].startswith("#/$defs/")
            return expand(definitions[value["$ref"][8:]], definitions)
        return {key: expand(item, definitions) for key, item in value.items() if key != "$defs"}
    return value


class AuthorSlotContractTests(unittest.TestCase):
    def test_supported_counts_have_closed_keys_shared_rows_and_sdk_shape(self):
        converse = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        for mode in MODES:
            for count in (1, 5, 20, 40):
                with self.subTest(mode=mode, count=count):
                    contract = AuthorSlotContract(count, mode)
                    config = native_output_config(contract)
                    schema = json.loads(config["textFormat"]["structure"]["jsonSchema"]["schema"])
                    Draft202012Validator.check_schema(schema)
                    local = _contract_schema(contract)
                    self.assertEqual(expand(schema, schema["$defs"]), local)
                    ordered_prose = (schema["$defs"]["authorRow"] if mode == "prose"
                                     else schema["$defs"]["proseQuestion"])
                    self.assertEqual(list(ordered_prose["properties"]), [
                        "prompt", "choices", "explanation", "correctChoice", "topic",
                        "difficulty", "format", "skillID", "objectiveID", "objective",
                    ])
                    self.assertEqual(list(schema["properties"]["questions"]["properties"]),
                                     [str(index) for index in range(count)])
                    self.assertLess(len(config["textFormat"]["structure"]["jsonSchema"]["schema"]), 6000)
                    raw = payload(mode, count)
                    Draft202012Validator(schema).validate(raw)
                    _validate_schema_value(raw, local)
                    decoded = json.loads(adapt_native_response(json.dumps(raw), contract))
                    self.assertEqual(len(decoded["questions"]), count)
                    self.assertEqual(contract_metadata(contract)["name"], contract.name)
                    validate_parameters({
                        "modelId": "us.anthropic.claude-sonnet-4-6",
                        "messages": [{"role": "user", "content": [{"text": "synthetic"}]}],
                        "outputConfig": config,
                    }, converse)
                    config["textFormat"]["structure"]["jsonSchema"]["schema"] = "mutated"
                    self.assertNotEqual(config, native_output_config(contract))

    def test_missing_extra_duplicate_and_invalid_rows_fail_before_any_adaptation(self):
        for mode in MODES:
            contract = AuthorSlotContract(5, mode)
            valid = payload(mode, 5)
            bad = []
            for missing in ("0", "4"):
                changed = copy.deepcopy(valid)
                del changed["questions"][missing]
                bad.append(json.dumps(changed))
            for extra in ("5", "01", "-1"):
                changed = copy.deepcopy(valid)
                changed["questions"][extra] = row(mode, 5)
                bad.append(json.dumps(changed))
            changed = copy.deepcopy(valid)
            changed["questions"]["0"] = {}
            bad.append(json.dumps(changed))
            bad.append('{"questions":{"0":{},"0":{}}}')
            bad.append('{"questions":{},"questions":{}}')
            bad.extend(('[]', '{"questions":[]}', '```json\n{}\n```'))
            for raw in bad:
                with self.subTest(mode=mode, raw=raw), self.assertRaises(ProviderError):
                    adapt_native_response(raw, contract)

    def test_dense_keys_restore_source_order_and_derive_exact_prose_answer(self):
        source = payload("prose", 2)
        source["questions"]["0"]["correctChoice"] = "d"
        source["questions"] = dict(reversed(list(source["questions"].items())))
        decoded = json.loads(adapt_native_response(json.dumps(source), AuthorSlotContract(2)))
        self.assertEqual([question["prompt"] for question in decoded["questions"]],
                         [prose(0)["prompt"], prose(1)["prompt"]])
        self.assertEqual(decoded["questions"][0]["expectedAnswer"], "Wrong D 0")
        self.assertNotIn("correctChoice", decoded["questions"][0])

    def test_count_and_mode_are_trusted_configuration_only(self):
        for count in (False, True, 0, -1, 41, 5.0, "5", None):
            with self.subTest(count=count), self.assertRaises(ServiceConfigurationError):
                AuthorSlotContract(count)
        for mode in ("legacy", "", None, [], 2):
            with self.subTest(mode=mode), self.assertRaises(ServiceConfigurationError):
                AuthorSlotContract(1, mode)

    def test_owned_prompt_example_must_be_present_exactly_once(self):
        with self.assertRaises(ServiceConfigurationError):
            native_prompt("No owned example here.", AuthorSlotContract(1))
        existing = generation._system_prompt()
        duplicate = existing + '\n{"questions":[{}]}'
        with self.assertRaises(ServiceConfigurationError):
            native_prompt(duplicate, AuthorSlotContract(1))

    def test_historical_author_schema_bytes_are_unchanged(self):
        for name, digest in HISTORICAL_HASHES.items():
            with self.subTest(name=name):
                self.assertEqual(contract_metadata(name)["sha256"], digest)

    def test_real_fake_dispatch_binds_each_pass_count_and_preserves_prompt_example(self):
        for mode in MODES:
            prompt_lengths = {}
            for count in (1, 5, 20, 40):
                with self.subTest(mode=mode, count=count), patch.dict(os.environ, {
                    "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
                    "QUESTION_AUTHOR_CARDINALITY_CONTRACT": "count_bound",
                    "QUESTION_AUTHOR_MODE": mode,
                    "QUESTION_FEEDBACK_CONTRACT": "authored_solution" if mode == "constructed_quantitative" else "reviewer_written",
                    "MAX_QUESTIONS_PER_BATCH": "40",
                    "BEDROCK_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
                    "BEDROCK_FALLBACK_MODEL_ID": "",
                }):
                    contract = AuthorSlotContract(count, mode)
                    client = ScriptedNativeClient((contract.name, payload(mode, count)))
                    request = _normalize_request(_request_payload(target_count=count))
                    result = generation._generate_provider_payload(request, client, generation.ProviderCallBudget(1))
                    self.assertEqual(len(result["questions"]), count)
                    self.assertEqual(client.calls[0]["outputConfig"], native_output_config(contract))
                    system = client.calls[0]["system"][0]["text"]
                    example_line = next(line for line in system.splitlines() if line.startswith('{"questions":'))
                    example = json.loads(example_line)
                    self.assertEqual(list(example["questions"]), ["0"])
                    self.assertIn("Illustrative single map entry", system)
                    keys = ", ".join(json.dumps(str(index)) for index in range(count))
                    self.assertIn(f"required keys: {keys}.", system)
                    self.assertIn(contract.name, system)
                    self.assertNotIn('Return {"questions":[...]} using exactly', system)
                    prompt_lengths[count] = len(system)
            self.assertLess(prompt_lengths[40] - prompt_lengths[1], 350)

    def test_fallback_keeps_same_count_and_native_schema(self):
        contract = AuthorSlotContract(5)
        client = ScriptedNativeClient((contract.name, RuntimeError("transient")),
                                      (contract.name, payload("prose", 5)))
        with patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "QUESTION_AUTHOR_MODE": "prose",
            "QUESTION_AUTHOR_CARDINALITY_CONTRACT": "count_bound",
            "BEDROCK_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
            "BEDROCK_FALLBACK_MODEL_ID": "moonshotai.kimi-k2.5",
        }):
            request = _normalize_request(_request_payload(target_count=5))
            result = generation._generate_provider_payload(request, client, generation.ProviderCallBudget(2))
        self.assertEqual(len(result["questions"]), 5)
        self.assertEqual([call["outputConfig"] for call in client.calls], [native_output_config(contract)] * 2)

    def test_existing_array_route_remains_default_for_every_native_author_mode(self):
        names = {
            "prose": "question_author_v3",
            "mixed_quantitative": "question_author_mixed_v1",
            "constructed_quantitative": "question_author_constructed_v1",
        }
        for mode in MODES:
            for selection in (None, "array"):
                settings = {
                    "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
                    "QUESTION_AUTHOR_MODE": mode,
                    "QUESTION_FEEDBACK_CONTRACT": (
                        "authored_solution" if mode == "constructed_quantitative" else "reviewer_written"
                    ),
                    "BEDROCK_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
                    "BEDROCK_FALLBACK_MODEL_ID": "",
                }
                if selection is not None:
                    settings["QUESTION_AUTHOR_CARDINALITY_CONTRACT"] = selection
                with self.subTest(mode=mode, selection=selection), patch.dict(os.environ, settings, clear=True):
                    self.assertEqual("QUESTION_AUTHOR_CARDINALITY_CONTRACT" in os.environ,
                                     selection is not None)
                    client = ScriptedNativeClient((names[mode], {"questions": [row(mode, 0)]}))
                    result = generation._generate_provider_payload(
                        _normalize_request(_request_payload(target_count=1)), client,
                        generation.ProviderCallBudget(1),
                    )
                    self.assertEqual(len(result["questions"]), 1)
                    self.assertEqual(client.calls[0]["outputConfig"], native_output_config(names[mode]))

    def test_count_bound_opt_in_rejects_legacy_transport_before_dispatch(self):
        with patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy",
            "QUESTION_AUTHOR_CARDINALITY_CONTRACT": "count_bound",
        }), self.assertRaises(ServiceConfigurationError):
            generation._generate_provider_payload(
                _normalize_request(_request_payload(target_count=1)), object(),
                generation.ProviderCallBudget(1),
            )


if __name__ == "__main__":
    unittest.main()
