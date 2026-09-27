"""Offline contract checks for server-bound 3:2 mapped author slots."""

import copy
import hashlib
import json
import os
import unittest
from unittest.mock import patch

from botocore.session import get_session
from botocore.validate import validate_parameters
from jsonschema import Draft202012Validator

import question_generation as generation
from lambda_test_support import _raw_question, _request_payload
from native_output_contracts import AuthorSlotContract, adapt_native_response, native_output_config, native_prompt
from quantitative_authoring import prepare_mixed_rows
from request_contract import _normalize_request
from service_errors import ProviderError, ServiceConfigurationError
from test_mixed_quantitative_pipeline import prose_row
from test_quantitative_authoring import exact_task


ARITHMETIC = "11111111-1111-4111-8111-111111111111"
ENGLISH = "22222222-2222-4222-8222-222222222222"
EXPRESSION = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
AGREEMENT = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"


class CompactMappedAuthorTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
            "QUESTION_AUTHOR_MODE": "constructed_quantitative",
            "QUESTION_AUTHOR_CARDINALITY_CONTRACT": "array",
            "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
            "BEDROCK_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
            "BEDROCK_FALLBACK_MODEL_ID": "",
        }))
        request = _normalize_request(_request_payload(target_count=5, minimum_difficulty=2))
        request["goal"].update(title="Arithmetic and English application practice",
                               contentTopics=["Exact arithmetic", "Standard written English"])
        request["skillMap"] = {"version": 1, "skills": [
            {"id": ARITHMETIC, "name": "Exact arithmetic", "objectives": [
                {"id": EXPRESSION, "name": "Evaluate exact expressions"}]},
            {"id": ENGLISH, "name": "Standard written English", "objectives": [
                {"id": AGREEMENT, "name": "Apply subject-verb agreement"}]},
        ]}
        request["requestedSkillAllocation"] = {ARITHMETIC: 3, ENGLISH: 2}
        self.request = request
        self.enterContext(patch.dict(os.environ, {
            "QUESTION_MAPPED_FIXED_FIVE_GOAL_SHA256": hashlib.sha256(json.dumps(
                request["goal"], sort_keys=True, separators=(",", ":"),
                ensure_ascii=True, allow_nan=False).encode()).hexdigest(),
            "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256": generation._mapped_author_scope_sha256(request),
        }))
        self.assignments = (
            (ARITHMETIC, EXPRESSION, "Exact arithmetic", "Evaluate exact expressions", 3),
            (ENGLISH, AGREEMENT, "Standard written English", "Apply subject-verb agreement", 2),
        )

    def contract(self):
        assignments = self.assignments
        return AuthorSlotContract(sum(item[4] for item in assignments),
                                  "constructed_quantitative", assignments, ARITHMETIC, 2)

    def raw(self):
        rows = {}
        for index, value in enumerate(("8", "10", "12")):
            task = exact_task(value)
            del task["choices"]
            rows[str(index)] = task
        for index in (3, 4):
            question = prose_row(_raw_question(f"Which sentence {index} has correct agreement?"))["question"]
            for field in ("topic", "skillID", "objectiveID", "objective"):
                question.pop(field, None)
            rows[str(index)] = question
        return {"questions": rows}

    def test_compact_schema_and_server_metadata_injection(self):
        contract = self.contract()
        config = native_output_config(contract)
        serialized = config["textFormat"]["structure"]["jsonSchema"]["schema"]
        schema = json.loads(serialized)
        Draft202012Validator.check_schema(schema)
        raw = self.raw()
        Draft202012Validator(schema).validate(raw)
        self.assertEqual(set(schema["properties"]["questions"]["properties"]),
                         {"0", "1", "2", "3", "4"})
        self.assertLess(len(serialized.encode()), 3000)
        self.assertEqual(serialized.count('"anyOf"'), 2)
        converse = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        validate_parameters({"modelId": "us.anthropic.claude-sonnet-4-6",
                             "messages": [{"role": "user", "content": [{"text": "synthetic"}]}],
                             "outputConfig": config}, converse)
        adapted = json.loads(adapt_native_response(json.dumps(raw), contract))
        self.assertEqual(len(adapted["questions"]), 5)
        for index, row in enumerate(adapted["questions"]):
            tagged = row if index < 3 else row["question"]
            expected = self.assignments[0 if index < 3 else 1]
            self.assertEqual((tagged["skillID"], tagged["objectiveID"],
                              tagged["topic"], tagged["objective"]), expected[:4])
        rows, compiled, failures = prepare_mixed_rows(adapted, construct_choices=True)
        self.assertEqual((len(rows), len(compiled), failures), (5, 3, []))
        self.assertEqual(len({tuple(row["choices"]) for row in rows[:3]}), 3)
        prompt = native_prompt(generation._system_prompt(), contract)
        self.assertIn("Establish the facts and solve the problem.", prompt)
        self.assertIn("Stem at most\n320 characters", prompt)
        self.assertIn("Difficulty rubric:", prompt)
        self.assertIn("The main explanation is the complete worked solution", prompt)
        self.assertIn("For each prose slot:", prompt)
        self.assertNotIn('"expectedAnswer":"..."', prompt)

    def test_wrong_kind_missing_slot_and_model_written_metadata_reject_whole_batch(self):
        contract = self.contract()
        for mutation in ("missing", "extra", "swap", "metadata", "numeric_key", "wrong_kind"):
            with self.subTest(mutation=mutation):
                raw = self.raw()
                if mutation == "missing":
                    del raw["questions"]["4"]
                elif mutation == "extra":
                    raw["questions"]["5"] = copy.deepcopy(raw["questions"]["4"])
                elif mutation == "swap":
                    raw["questions"]["2"], raw["questions"]["3"] = (
                        raw["questions"]["3"], raw["questions"]["2"])
                elif mutation == "metadata":
                    raw["questions"]["0"]["skillID"] = ENGLISH
                elif mutation == "numeric_key":
                    raw["questions"]["0"]["expectedAnswer"] = "16"
                else:
                    raw["questions"]["3"] = copy.deepcopy(raw["questions"]["0"])
                with self.assertRaises(ProviderError):
                    adapt_native_response(json.dumps(raw), contract)
        with self.assertRaises(ServiceConfigurationError):
            AuthorSlotContract(2, "constructed_quantitative", (self.assignments[1],),
                               ARITHMETIC, 2)

    def test_exact_scope_excludes_partial_and_drifted_requests(self):
        self.assertIsNotNone(generation._mapped_fixed_slot_assignments(
            self.request, "constructed_quantitative", "array"))
        altered = copy.deepcopy(self.request)
        altered["skillMap"]["skills"].reverse()
        self.assertIsNone(generation._mapped_fixed_slot_assignments(
            altered, "constructed_quantitative", "array"))
        for field, value in (("existingPrompts", ["Earlier expression stem"]),
                             ("reportedPrompts", ["Already reported"]),
                             ("blockedStemFingerprints", ["deadbeef"]),
                             ("stemFingerprintVersion", 2),
                             ("existingQuestionCoverage", [{"prompt": "Earlier covered item"}])):
            with self.subTest(field=field):
                changed = copy.deepcopy(self.request)
                changed[field] = value
                self.assertIsNone(generation._mapped_fixed_slot_assignments(
                    changed, "constructed_quantitative", "array"))
        partial = copy.deepcopy(self.request)
        partial["targetCount"] = 2
        partial["requestedSkillAllocation"] = {ENGLISH: 2}
        self.assertIsNone(generation._mapped_fixed_slot_assignments(
            partial, "constructed_quantitative", "array"))
        bad = copy.deepcopy(partial)
        bad["skillMap"]["skills"].reverse()
        self.assertIsNone(generation._mapped_fixed_slot_assignments(
            bad, "constructed_quantitative", "array"))
        with patch.object(generation, "_generate_with_bedrock", return_value='{"questions":[]}') as generate:
            self.assertEqual(generation._generate_provider_payload(partial, None), {"questions": []})
        self.assertEqual(generate.call_args.kwargs["contract"], "question_author_constructed_v1")
        with patch.dict(os.environ, {"BEDROCK_FALLBACK_MODEL_ID": "different-model"}):
            with self.assertRaises(ServiceConfigurationError):
                generation._mapped_fixed_slot_assignments(self.request, "constructed_quantitative", "array")
        with patch.dict(os.environ):
            os.environ.pop("BEDROCK_FALLBACK_MODEL_ID")
            with patch.object(generation, "DEFAULT_FALLBACK_MODEL_ID", "different-model"):
                with self.assertRaises(ServiceConfigurationError):
                    generation._mapped_fixed_slot_assignments(self.request, "constructed_quantitative", "array")

    def test_runtime_uses_one_compact_pass_and_preserves_partial_result(self):
        seen = []
        raw = self.raw()

        def author(*_args, **kwargs):
            contract = kwargs["contract"]
            self.assertIsInstance(contract, AuthorSlotContract)
            seen.append((contract, copy.deepcopy(kwargs["normalized_request"])))
            return adapt_native_response(json.dumps(raw), contract)

        sanitized_calls = []

        def sanitize(rows, *_args, **_kwargs):
            sanitized_calls.append(True)
            return rows[:3] if len(sanitized_calls) == 1 else rows

        with (patch.object(generation, "_generate_with_bedrock", side_effect=author),
              patch.object(generation, "_sanitize_questions", side_effect=sanitize),
              patch.object(generation, "verify_questions", side_effect=lambda rows, *_a, **_k: rows)):
            result = generation._generate_sanitized_questions(copy.deepcopy(self.request), None)
        self.assertEqual(len(result), 3)
        self.assertEqual([contract.count for contract, _ in seen], [5])
        self.assertEqual(seen[0][0].mapped_quantitative_skill_id, ARITHMETIC)
        self.assertEqual(seen[0][1]["requestedSkillAllocation"], {ARITHMETIC: 3, ENGLISH: 2})

    def test_invalid_quantitative_task_has_no_prose_fallback(self):
        raw = self.raw()
        raw["questions"]["1"]["root"] = 999
        adapted = json.loads(adapt_native_response(json.dumps(raw), self.contract()))
        rows, compiled, failures = prepare_mixed_rows(adapted, construct_choices=True)
        self.assertIsNone(rows[1])
        self.assertEqual(set(compiled), {0, 2})
        self.assertEqual(failures, ["invalid_spec"])

    def test_compact_route_rejects_short_cap_before_provider_and_does_not_retry_bad_batch(self):
        with (patch.object(generation, "_constructed_author_batch_size", return_value=3),
              patch.object(generation, "_generate_with_bedrock") as generate):
            with self.assertRaises(ServiceConfigurationError):
                generation._generate_sanitized_questions(copy.deepcopy(self.request), None)
            generate.assert_not_called()
        with patch.object(generation, "_generate_with_bedrock",
                          return_value='{"questions":[]}') as generate:
            with self.assertRaises(ProviderError):
                generation._generate_provider_payload(copy.deepcopy(self.request), None)
        self.assertEqual(generate.call_count, 1)


if __name__ == "__main__":
    unittest.main()
