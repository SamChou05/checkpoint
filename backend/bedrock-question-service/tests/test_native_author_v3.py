"""Native author ordering preserves tested bytes and existing semantic gates."""

import copy
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from jsonschema import Draft202012Validator

from lambda_test_support import _raw_question, _request_payload
from native_output_contracts import adapt_native_response, contract_metadata, native_output_config, native_prompt
from question_generation import ProviderCallBudget, _generate_provider_payload, _generate_sanitized_questions
from request_contract import _normalize_request
from service_errors import ProviderError
from test_native_author_v2 import Client, question, raw
from test_native_pipeline import AUTHOR, SOLVER, ScriptedNativeClient, solver_map, solver_record, task_data


ROOT = Path(__file__).resolve().parents[3]
CONTRACT = "question_author_v3"


class NativeAuthorV3Tests(unittest.TestCase):
    def test_v3_uses_exact_tested_schema_bytes_and_shared_slot_prompt(self):
        plan = json.loads((ROOT / "docs/evidence/native-author-order-20260922/plan.json").read_text())
        tested = next(job for job in plan["jobs"] if job["arm"] == "ordered")
        expected = tested["provider_request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]
        actual = native_output_config(CONTRACT)["textFormat"]["structure"]["jsonSchema"]
        self.assertEqual(actual, {**expected, "name": CONTRACT})
        self.assertEqual(native_prompt("same author rules", CONTRACT),
                         native_prompt("same author rules", "question_author_v2"))
        schema = json.loads(actual["schema"])
        self.assertEqual(list(schema["properties"]["questions"]["items"]["properties"]), [
            "prompt", "choices", "explanation", "correctChoice", "topic", "difficulty",
            "format", "skillID", "objectiveID", "objective",
        ])
        self.assertEqual(contract_metadata(CONTRACT), {
            "name": CONTRACT, "version": "3",
            "sha256": "94ab5d7cb7661085e66e2c8d7c860cd2378f8d9ef8f133326c49ddcffb7bfcd9",
        })
        for contract, digest in (
            ("question_author_v1", "25c2c85d94ae1543ef4a46a3f97e845c37739cec5b77aacbf219d935a13df1a9"),
            ("question_author_v2", "abc583c2eecbd461b3c4852170aeadabf5437ff46b65257f14325488b34dd813"),
        ):
            self.assertEqual(contract_metadata(contract)["sha256"], digest)

    def test_v3_replays_all_saved_author_rows_with_exact_v2_adapter_results(self):
        capture = json.loads((ROOT / "docs/evidence/native-author-order-20260922/capture.json").read_text())
        for call in capture["calls"]:
            provider_raw = "\n".join(block["text"] for block in call["response"]["output"]["message"]["content"] if "text" in block)
            with self.subTest(call=call["index"]):
                self.assertEqual(adapt_native_response(provider_raw, CONTRACT), call["adapted_raw"])

    def test_native_author_route_requests_slots_and_derives_the_selected_key(self):
        source = question()
        source["correctChoice"] = "d"
        source["explanation"] = "This unrelated sentence cannot choose or replace the answer key."
        client = Client(raw(source))
        request = _normalize_request(_request_payload(target_count=1))
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "BEDROCK_MODEL_ID": "moonshotai.kimi-k2.5",
            "BEDROCK_FALLBACK_MODEL_ID": "",
        }):
            result = _generate_provider_payload(request, client, ProviderCallBudget(1), metrics)
        self.assertEqual(result["questions"][0]["choices"], list(source["choices"].values()))
        self.assertEqual(result["questions"][0]["expectedAnswer"], source["choices"]["d"])
        self.assertEqual(client.calls[0]["outputConfig"], native_output_config(CONTRACT))
        instructions = client.calls[0]["system"][0]["text"]
        examples = [json.loads(line) for line in instructions.splitlines() if line.startswith('{"questions":')]
        self.assertEqual(len(examples), 1)
        schema = json.loads(client.calls[0]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
        Draft202012Validator(schema).validate(examples[0])
        self.assertNotIn("expectedAnswer exactly equals", instructions)
        self.assertIn("correctChoice identifies exactly one", instructions)
        self.assertEqual(metrics["ProviderObservations"][0]["structuredOutput"],
                         {"mode": "native", **contract_metadata(CONTRACT)})

    def test_legacy_author_keeps_its_own_matching_output_example(self):
        client = Client(raw(_raw_question("Which statement follows from the given evidence?")))
        request = _normalize_request(_request_payload(target_count=1))
        with patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy", "BEDROCK_MODEL_ID": "moonshotai.kimi-k2.5",
            "BEDROCK_FALLBACK_MODEL_ID": "", "QUESTION_FEEDBACK_CONTRACT": "reviewer_written",
        }):
            _generate_provider_payload(request, client, ProviderCallBudget(1))
        sent = client.calls[0]
        self.assertNotIn("outputConfig", sent)
        instructions = sent["system"][0]["text"]
        example = next(json.loads(line) for line in instructions.splitlines() if line.startswith('{"questions":'))
        schema = json.loads(native_output_config("question_author_v1")["textFormat"]["structure"]["jsonSchema"]["schema"])
        Draft202012Validator(schema).validate(example)
        self.assertIn("expectedAnswer exactly equals one", instructions)
        self.assertNotIn("correctChoice", instructions)

    def test_initial_and_json_repair_share_the_mode_selected_author_contract(self):
        request = _normalize_request(_request_payload(target_count=1))
        for mode, contract in (("legacy", "question_author_v1"), ("native", CONTRACT)):
            with self.subTest(mode=mode), patch.dict(os.environ, {
                "BEDROCK_STRUCTURED_OUTPUT_MODE": mode,
                "BEDROCK_MODEL_ID": "moonshotai.kimi-k2.5", "BEDROCK_FALLBACK_MODEL_ID": "",
            }), patch("question_generation._generate_with_bedrock", side_effect=["invalid JSON", '{"questions":[]}']) as generate:
                self.assertEqual(_generate_provider_payload(request, object()), {"questions": []})
                self.assertEqual([call.kwargs["contract"] for call in generate.call_args_list], [contract, contract])
                self.assertIn("user_prompt", generate.call_args_list[1].kwargs)

    def test_invalid_v3_slots_cannot_bypass_the_same_strict_v2_shape(self):
        for changed in (
            {**question(), "correctChoice": True},
            {**question(), "expectedAnswer": "forged"},
            {**question(), "choices": {**question()["choices"], "e": "fifth"}},
        ):
            with self.subTest(source=changed), self.assertRaises(ProviderError):
                adapt_native_response(raw(changed), CONTRACT)

    def test_captured_semantic_defect_still_faces_the_independent_solver(self):
        capture = json.loads((ROOT / "docs/evidence/native-author-release-20260922/capture.json").read_text())
        raw_text = "\n".join(block["text"] for block in capture["calls"][0]["response"]["output"]["message"]["content"] if "text" in block)
        bad_question = copy.deepcopy(json.loads(raw_text)["questions"][3])
        self.assertEqual(bad_question["choices"][bad_question["correctChoice"]], "25%")

        def solve(request):
            item = task_data(request, "question_solution_json")["items"][0]
            def refute_all(record):
                for row in record["choices"]:
                    row.update(judgment="refuted", reason="Concentrate rises from9 to15liters:66⅔%, which is absent.")
            return solver_map(solver_record(item, "25%", refute_all))

        client = ScriptedNativeClient((AUTHOR, {"questions": [bad_question]}), (SOLVER, solve))
        request = _normalize_request({
            "goal": {"title": "Apply arithmetic to mixture quantities", "needsSkillMap": False},
            "targetCount": 1, "minimumDifficulty": 2,
        })
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "BEDROCK_MODEL_ID": "moonshotai.kimi-k2.5",
            "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
            "BEDROCK_FALLBACK_MODEL_ID": "", "QUESTION_FEEDBACK_CONTRACT": "reviewer_written",
            "GENERATION_ATTEMPTS": "1",
        }):
            accepted = _generate_sanitized_questions(request, client, ProviderCallBudget(3), metrics)
        self.assertEqual(accepted, [])
        self.assertEqual(len(client.calls), 2)
        self.assertEqual(metrics["QuestionQuality"]["review"]["solver_zero_supported"], 1)


if __name__ == "__main__":
    unittest.main()
