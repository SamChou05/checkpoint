"""Exact native reviewer identity and real survivor-count routing."""

import copy
import json
from pathlib import Path
import unittest

from botocore.session import get_session
from botocore.validate import validate_parameters
from jsonschema import Draft202012Validator

import question_generation as generation
import test_native_pipeline as pipeline
from native_output_contracts import (
    MAX_REVIEW_BATCH_COUNT, ReviewerSlotContract, adapt_native_response,
    contract_metadata, native_output_config, native_prompt,
)
from question_verification import COMPLETE_REVIEW_SYSTEM_PROMPT
from service_errors import ProviderError, ServiceConfigurationError
from test_native_pipeline import (
    AUTHOR, REVIEWER, ScriptedNativeClient,
    author_payload, review, review_map, solver_map, solver_record, task_data,
)

EVIDENCE = Path(__file__).resolve().parents[3] / "docs/evidence/reviewer-identity-20260922"


def payload(count):
    return {"reviews": {str(index): {
        "valid": True, "answer": "cafe\u0301  exact", "difficulty": 3,
        "explanation": "  Preserve this teaching.\n",
        "choiceFeedback": [{"choice": "cafe\u0301  exact", "explanation": " Exact bytes.\n"}],
    } for index in range(count)}}


class ReviewerSlotContractTests(unittest.TestCase):
    def test_all_supported_counts_enforce_closed_identity_and_validate_sdk_shape(self):
        shape = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        for count in range(1, MAX_REVIEW_BATCH_COUNT + 1):
            with self.subTest(count=count):
                contract = ReviewerSlotContract(count)
                config = native_output_config(contract)
                schema = json.loads(config["textFormat"]["structure"]["jsonSchema"]["schema"])
                Draft202012Validator.check_schema(schema)
                raw = payload(count)
                raw["reviews"] = dict(reversed(list(raw["reviews"].items())))
                Draft202012Validator(schema).validate(raw)
                decoded = json.loads(adapt_native_response(json.dumps(raw), contract))
                self.assertEqual([row["index"] for row in decoded["reviews"]], list(range(count)))
                validate_parameters({"modelId": "us.anthropic.claude-sonnet-4-6",
                                     "messages": [{"role": "user", "content": [{"text": "synthetic"}]}],
                                     "outputConfig": config}, shape)
                config["textFormat"]["structure"]["jsonSchema"]["schema"] = "changed"
                self.assertNotEqual(config, native_output_config(contract))

    def test_invalid_counts_fail_before_any_request_can_be_built(self):
        for count in (False, True, 0, -1, 41, 5.0, "5", None):
            with self.subTest(count=count), self.assertRaises(ServiceConfigurationError):
                ReviewerSlotContract(count)

    def test_unknown_missing_duplicate_or_embedded_identities_are_never_repaired(self):
        bad = []
        for key in ("-1", "5", "01", "1.0", "true", "x"):
            raw = payload(5)
            raw["reviews"][key] = copy.deepcopy(raw["reviews"]["0"])
            bad.append(json.dumps(raw))
        for key in map(str, range(5)):
            raw = payload(5)
            del raw["reviews"][key]
            bad.append(json.dumps(raw))
        raw = payload(5)
        raw["reviews"]["0"]["index"] = 0
        bad.append(json.dumps(raw))
        bad.extend(['{"reviews":{"0":{},"0":{}}}', '{"reviews":{},"reviews":{}}',
                    json.dumps(payload(5)).replace('"valid": true', '"valid": false,"valid": true')])
        for raw in bad:
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                adapt_native_response(raw, ReviewerSlotContract(5))

    def test_field_types_closed_shapes_and_nonfinite_numbers_remain_strict(self):
        bad = ['[]', '{}', '{"reviews":[]}', '```json\n{}\n```']
        for update in ({"valid": 1}, {"difficulty": True}, {"answer": None},
                       {"choiceFeedback": {}}, {"unknown": "text"}):
            raw = payload(1)
            raw["reviews"]["0"].update(update)
            bad.append(json.dumps(raw))
        for field in payload(1)["reviews"]["0"]:
            raw = payload(1)
            del raw["reviews"]["0"][field]
            bad.append(json.dumps(raw))
        for number in ("NaN", "Infinity", "1e309"):
            bad.append(json.dumps(payload(1)).replace('"difficulty": 3', '"difficulty": ' + number))
        for raw in bad:
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                adapt_native_response(raw, ReviewerSlotContract(1))

    def test_positive_bytes_and_negative_verdicts_preserve_existing_admission(self):
        raw = payload(2)
        raw["reviews"]["1"]["valid"] = False
        result = json.loads(adapt_native_response(json.dumps(raw), ReviewerSlotContract(2)))["reviews"]
        self.assertEqual(result[0]["answer"], raw["reviews"]["0"]["answer"])
        self.assertEqual(result[0]["explanation"], raw["reviews"]["0"]["explanation"])
        self.assertEqual(result[0]["choiceExplanations"], {"cafe\u0301  exact": " Exact bytes.\n"})
        self.assertEqual(result[1], {"index": 1, "valid": False})
        raw["reviews"]["0"]["choiceFeedback"] *= 2
        with self.assertRaises(ProviderError):
            adapt_native_response(json.dumps(raw), ReviewerSlotContract(2))

    def test_live_count_five_schema_prompt_and_response_bytes_match_qualified_candidate(self):
        capture = json.loads((EVIDENCE / "capture.json").read_text())
        plan = json.loads((EVIDENCE / "plan.json").read_text())
        configured = native_output_config(ReviewerSlotContract(5))["textFormat"]["structure"]["jsonSchema"]
        for planned, call in zip(plan["calls"], capture["calls"], strict=True):
            request = planned["provider_request"]
            self.assertEqual(configured["schema"], request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
            self.assertEqual(native_prompt(COMPLETE_REVIEW_SYSTEM_PROMPT, ReviewerSlotContract(5)), request["system"][0]["text"])
            raw = "\n".join(block["text"] for block in call["response"]["output"]["message"]["content"] if "text" in block)
            original = json.loads(raw)["reviews"]
            decoded = json.loads(adapt_native_response(raw, ReviewerSlotContract(5)))["reviews"]
            for index, row in enumerate(decoded):
                source = original[str(index)]
                self.assertEqual(row["index"], index)
                self.assertEqual(row["valid"], source["valid"])
                if row["valid"]:
                    self.assertEqual(row["answer"], source["answer"])
                    self.assertEqual(row["explanation"], source["explanation"])
                    self.assertEqual(row["choiceExplanations"], {r["choice"]: r["explanation"] for r in source["choiceFeedback"]})
        self.assertEqual(contract_metadata(ReviewerSlotContract(5))["version"], "3")
        self.assertEqual(contract_metadata("default_reviewer_v1")["sha256"],
                         "77c15c631555d0d83bfaa2e0ba1c19478c51d2573586220cce2ce94684bfe2fe")


class ReviewerSurvivorRoutingTests(unittest.TestCase):
    setUp = pipeline.NativePipelineTests.setUp

    def test_contract_count_comes_from_dense_solver_survivors_not_requested_count(self):
        rejected = {**self.question, "prompt": "Which second conclusion follows from these conditions?"}
        def solve(request):
            records = []
            for item in task_data(request, "question_solution_json")["items"]:
                record = solver_record(item, self.question["expectedAnswer"])
                if item["prompt"] == rejected["prompt"]:
                    for value in record["choices"].values():
                        value["judgment"] = "uncertain"
                records.append(record)
            return solver_map(*records)

        def reviewer(request):
            items = task_data(request, "question_review_json")["items"]
            self.assertEqual([(item["index"], item["prompt"]) for item in items], [(0, self.question["prompt"])])
            return review_map(review(self.question))

        client = ScriptedNativeClient((AUTHOR, author_payload(rejected, self.question)),
                                      ("complete_choice_solver_v5_n2", solve), (REVIEWER, reviewer))
        request = {**self.request, "targetCount": 2}
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        accepted = generation._generate_sanitized_questions(request, client, generation.ProviderCallBudget(3), metrics)
        self.assertEqual([q["prompt"] for q in accepted], [self.question["prompt"]])
        self.assertEqual(metrics["ProviderObservations"][-1]["structuredOutput"]["name"], "default_reviewer_v3_n1")
        self.assertEqual(len(client.calls), 3)


if __name__ == "__main__":
    unittest.main()
