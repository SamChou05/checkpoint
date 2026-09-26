"""Task-only native author may supply math graphs, never learner content."""

import copy
import hashlib
import json
import os
from pathlib import Path
import socket
import unittest
from unittest.mock import Mock, patch

import boto3
from jsonschema import Draft202012Validator

import native_output_contracts as native
import question_generation as generation
from quantitative_authoring import (
    LEARNER_FIELDS, TASK_ONLY_AUTHOR_CONTRACT, prepare_mixed_rows,
)
from quantitative_task_compiler import compile_question
from service_errors import ProviderError, ServiceConfigurationError
from test_constructed_quantitative_pipeline import row, task
from test_native_pipeline import MODEL, ScriptedNativeClient, authored_issue_flags, task_data


ROOT = Path(__file__).resolve().parents[3]
PRIOR_PLAN = ROOT / "docs/evidence/current-source-worker-successor-qualification-20260926/plan.json"


def goal_digest(goal):
    return hashlib.sha256(json.dumps(goal, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=True, allow_nan=False).encode()).hexdigest()


class TaskOnlyAuthorTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "QUESTION_AUTHOR_MODE": "constructed_quantitative",
            "QUESTION_AUTHOR_CARDINALITY_CONTRACT": "array", "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
            "BEDROCK_MODEL_ID": MODEL, "BEDROCK_VERIFICATION_MODEL_ID": MODEL,
            "BEDROCK_FALLBACK_MODEL_ID": "", "BEDROCK_CLAUDE_THINKING": "disabled",
            "GENERATION_ATTEMPTS": "1",
        }))
        for owner, name in ((socket.socket, "connect"), (boto3, "client"), (boto3.session.Session, "client")):
            self.enterContext(patch.object(owner, name, side_effect=AssertionError("No provider access")))
        self.request = copy.deepcopy(json.loads(PRIOR_PLAN.read_text())["jobs"][0]["request"])
        self.request["targetCount"] = 2
        self.goal_hash = goal_digest(self.request["goal"])

    def test_schema_excludes_prose_authored_choices_keys_teaching_and_tags(self):
        local = native._contract_schema(TASK_ONLY_AUTHOR_CONTRACT)
        row_schema = local["properties"]["questions"]["items"]
        self.assertEqual(row_schema["required"], ["kind", "task", "topic", "difficulty"])
        self.assertEqual(set(row_schema["properties"]), set(row_schema["required"]))
        self.assertEqual(row_schema["properties"]["kind"]["enum"], ["quantitative"])
        self.assertNotIn("prose", json.dumps(local))
        for forbidden in ("choices", "correctChoice", "expectedAnswer", "explanation", "choiceFeedback"):
            self.assertNotIn(forbidden, json.dumps(local))
        provider = json.loads(native.native_output_config(TASK_ONLY_AUTHOR_CONTRACT)["textFormat"]["structure"]["jsonSchema"]["schema"])
        Draft202012Validator.check_schema(provider)
        self.assertEqual(set(provider["$defs"]), {"node", "task"})
        self.assertEqual(provider["properties"]["questions"]["items"]["properties"]["kind"]["enum"],
                         ["quantitative"])

    def test_local_adapter_rejects_prose_authored_fields_duplicate_keys_and_constants(self):
        valid = {"questions": [row(task())]}
        self.assertEqual(json.loads(native.adapt_native_response(json.dumps(valid), TASK_ONLY_AUTHOR_CONTRACT)), valid)
        rejected = [
            {"questions": [{"kind": "prose", "question": {}}]},
            {"questions": [{**row(task()), "choices": {"a": "5", "b": "4", "c": "6", "d": "7"}}]},
            {"questions": [{**row(task()), "correctChoice": "a"}]},
            {"questions": [{**row(task()), "explanation": "The answer is five."}]},
            {"questions": [{**row(task()), "skillID": "forged"}]},
            {"questions": [{**row(task()), "task": {**task(), "choices": {}}}]},
        ]
        for payload in rejected:
            with self.subTest(payload=payload), self.assertRaises(ProviderError):
                native.adapt_native_response(json.dumps(payload), TASK_ONLY_AUTHOR_CONTRACT)
        for raw in ('{"questions":[],"questions":[]}', '{"questions":[{"kind":"quantitative","task":NaN}]}'):
            with self.assertRaises(ProviderError):
                native.adapt_native_response(raw, TASK_ONLY_AUTHOR_CONTRACT)

    def test_prompt_has_one_typed_example_and_no_prose_or_answer_request(self):
        prompt = native.native_prompt(generation._system_prompt(), TASK_ONLY_AUTHOR_CONTRACT)
        self.assertIn("question_author_tasks_v1", prompt)
        self.assertIn('"kind":"quantitative"', prompt)
        self.assertNotIn('"kind":"prose"', prompt)
        self.assertNotIn("correctChoice", prompt)
        self.assertNotIn("expectedAnswer", prompt)
        self.assertIn("ignore", prompt.lower())
        with self.assertRaises(ServiceConfigurationError):
            native.native_prompt("unowned prompt", TASK_ONLY_AUTHOR_CONTRACT)

    def test_exact_goal_hash_and_context_preflight(self):
        with patch.dict(os.environ, {"QUESTION_TASK_ONLY_NUMERICAL_GOAL_SHA256": self.goal_hash}):
            self.assertTrue(generation._task_only_numerical_author(self.request, "constructed_quantitative", "array"))
            changed = copy.deepcopy(self.request)
            changed["goal"]["title"] += " changed"
            self.assertFalse(generation._task_only_numerical_author(changed, "constructed_quantitative", "array"))
            for field, value in (("skillMap", {}), ("desiredSkillAllocation", {}),
                                 ("requestedSkillAllocation", {}), ("requestedObjectiveAllocation", []),
                                 ("adaptiveSkillPlans", [{"skillID": "x", "targetDifficulty": 3}]),
                                 ("requiresFullObjectiveCoverage", True), ("sourceDocuments", [{"text": "source"}]),
                                 ("competencies", [{"name": "Math"}])):
                with self.subTest(field=field), self.assertRaises(ServiceConfigurationError):
                    restricted = copy.deepcopy(self.request)
                    restricted[field] = value
                    generation._task_only_numerical_author(restricted, "constructed_quantitative", "array")
            for mode, cardinality in (("prose", "array"), ("constructed_quantitative", "count_bound")):
                with self.assertRaises(ServiceConfigurationError):
                    generation._task_only_numerical_author(self.request, mode, cardinality)
        with patch.dict(os.environ, {"QUESTION_TASK_ONLY_NUMERICAL_GOAL_SHA256": "not-a-hash"}), self.assertRaises(ServiceConfigurationError):
            generation._task_only_numerical_author(self.request, "constructed_quantitative", "array")

    def test_full_pipeline_keeps_compiler_proof_and_never_releases_authored_content(self):
        rows = [row(task(str(value))) for value in (8, 10)]
        prepared, sidecars, failures = prepare_mixed_rows({"questions": rows}, construct_choices=True)
        self.assertEqual(failures, [])
        by_prompt = {question["prompt"]: question for question in prepared}

        def audit(request):
            items = task_data(request, "question_review_json")["items"]
            return {"reviews": {str(item["index"]): {
                "valid": True, "answer": by_prompt[item["prompt"]]["expectedAnswer"], "difficulty": 2,
                "explanationSupport": "supported", "issueFlags": authored_issue_flags(),
            } for item in items}}

        client = ScriptedNativeClient(
            (TASK_ONLY_AUTHOR_CONTRACT, {"questions": rows}),
            ("authored_solution_reviewer_v3_n2", audit),
        )
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        with patch.dict(os.environ, {"QUESTION_TASK_ONLY_NUMERICAL_GOAL_SHA256": self.goal_hash}):
            result = generation._generate_sanitized_questions(self.request, client, budget)
        self.assertEqual((len(result), budget.calls, reserve.call_count), (2, 2, 2))
        self.assertEqual(client.calls[0]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"],
                         TASK_ONLY_AUTHOR_CONTRACT)
        for index, question in enumerate(result):
            expected = compile_question(json.loads(sidecars[index].spec_json))
            self.assertEqual({field: question[field] for field in LEARNER_FIELDS}, expected)
            self.assertEqual(question["verificationPolicyRevision"], 8)

    def test_task_only_three_then_two_uses_four_calls_and_exact_compiler_fields(self):
        batches = [[row(task(str(value))) for value in values] for values in ((8, 10, 12), (14, 16))]
        expected, by_prompt = [], {}
        for batch in batches:
            prepared, sidecars, failures = prepare_mixed_rows({"questions": batch}, construct_choices=True)
            self.assertEqual(failures, [])
            by_prompt.update({question["prompt"]: question for question in prepared})
            expected.extend(compile_question(json.loads(sidecar.spec_json)) for sidecar in sidecars.values())

        def audit(request):
            items = task_data(request, "question_review_json")["items"]
            return {"reviews": {str(item["index"]): {
                "valid": True, "answer": by_prompt[item["prompt"]]["expectedAnswer"], "difficulty": 2,
                "explanationSupport": "supported", "issueFlags": authored_issue_flags(),
            } for item in items}}

        client = ScriptedNativeClient(
            (TASK_ONLY_AUTHOR_CONTRACT, {"questions": batches[0]}),
            ("authored_solution_reviewer_v3_n3", audit),
            (TASK_ONLY_AUTHOR_CONTRACT, {"questions": batches[1]}),
            ("authored_solution_reviewer_v3_n2", audit),
        )
        request = {**self.request, "targetCount": 5}
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        with patch.dict(os.environ, {"QUESTION_TASK_ONLY_NUMERICAL_GOAL_SHA256": self.goal_hash,
                                  "QUESTION_CONSTRUCTED_AUTHOR_BATCH_SIZE": "3", "GENERATION_ATTEMPTS": "3"}):
            result = generation._generate_sanitized_questions(request, client, budget)
        self.assertEqual((len(result), budget.calls, reserve.call_count), (5, 4, 4))
        self.assertEqual([task_data(client.calls[i], "generation_request_json")["targetCount"] for i in (0, 2)], [3, 2])
        self.assertEqual([client.calls[i]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
                          for i in (0, 2)], [TASK_ONLY_AUTHOR_CONTRACT] * 2)
        self.assertEqual([{field: question[field] for field in LEARNER_FIELDS} for question in result], expected)
        self.assertEqual([question["verificationPolicyRevision"] for question in result], [8] * 5)

    def test_task_only_second_author_failure_retains_verified_first_batch(self):
        first = [row(task(str(value))) for value in (8, 10, 12)]
        prepared, _, failures = prepare_mixed_rows({"questions": first}, construct_choices=True)
        self.assertEqual(failures, [])
        by_prompt = {question["prompt"]: question for question in prepared}

        def audit(request):
            items = task_data(request, "question_review_json")["items"]
            return {"reviews": {str(item["index"]): {
                "valid": True, "answer": by_prompt[item["prompt"]]["expectedAnswer"], "difficulty": 2,
                "explanationSupport": "supported", "issueFlags": authored_issue_flags(),
            } for item in items}}

        client = ScriptedNativeClient(
            (TASK_ONLY_AUTHOR_CONTRACT, {"questions": first}),
            ("authored_solution_reviewer_v3_n3", audit),
            (TASK_ONLY_AUTHOR_CONTRACT, ProviderError("synthetic second-author failure")),
        )
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        with patch.dict(os.environ, {"QUESTION_TASK_ONLY_NUMERICAL_GOAL_SHA256": self.goal_hash,
                                  "QUESTION_CONSTRUCTED_AUTHOR_BATCH_SIZE": "3", "GENERATION_ATTEMPTS": "3"}):
            result = generation._generate_sanitized_questions({**self.request, "targetCount": 5}, client, budget)
        self.assertEqual((len(result), budget.calls, reserve.call_count), (3, 3, 3))
        self.assertEqual([question["verificationPolicyRevision"] for question in result], [8] * 3)

    def test_prose_response_fails_closed_before_compiler_or_audit(self):
        client = ScriptedNativeClient((TASK_ONLY_AUTHOR_CONTRACT, {"questions": [
            {"kind": "prose", "question": {"prompt": "invalid"}},
        ]}))
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        with patch.dict(os.environ, {"QUESTION_TASK_ONLY_NUMERICAL_GOAL_SHA256": self.goal_hash}), self.assertRaises(ProviderError):
            generation._generate_sanitized_questions(self.request, client, budget)
        self.assertEqual((len(client.calls), budget.calls, reserve.call_count), (1, 1, 1))


if __name__ == "__main__":
    unittest.main()
