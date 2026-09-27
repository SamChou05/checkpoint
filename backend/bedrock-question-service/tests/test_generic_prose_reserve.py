"""The opt-in generic reserve keeps surplus candidates behind existing gates."""

import json
import os
import unittest
from unittest.mock import Mock, patch

import question_generation as generation
from lambda_test_support import FakeLambdaContext, _raw_question, _request_payload
from request_contract import _normalize_request
from service_errors import ProviderCallBudgetExceededError, ProviderDeadlineExceededError
from test_native_pipeline import (
    MODEL, ScriptedNativeClient, author_payload, authored_issue_flags,
    solver_map, solver_record, task_data,
)


class GenericProseReserveTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
            "QUESTION_AUTHOR_MODE": "prose",
            "QUESTION_AUTHOR_CARDINALITY_CONTRACT": "count_bound",
            "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
            "QUESTION_GENERIC_PROSE_RESERVE_7": "enabled",
            "BEDROCK_MODEL_ID": MODEL,
            "BEDROCK_VERIFICATION_MODEL_ID": MODEL,
            "BEDROCK_FALLBACK_MODEL_ID": "",
            "BEDROCK_CLAUDE_THINKING": "disabled",
            "GENERATION_ATTEMPTS": "5",
        }))
        self.questions = []
        for index in range(7):
            question = _raw_question(
                f"Scenario {index} states a separate assumption and conclusion. Which inference follows?",
                explanation=f"  Worked reason {index}: the stated assumption establishes this conclusion.  ",
            )
            question["choices"] = question["choices"][index % 4:] + question["choices"][:index % 4]
            self.questions.append(question)
        self.request = _normalize_request(_request_payload(target_count=5))

    def client(self, *, authored_count=7, solver_rejected=(), review_rejected=()):
        originals = {question["prompt"]: question for question in self.questions[:authored_count]}
        solver_rejected = set(solver_rejected)
        review_rejected = set(review_rejected)

        def solve(request):
            items = task_data(request, "question_solution_json")["items"]
            self.assertEqual(len(items), authored_count)
            rows = []
            for item in items:
                self.assertNotIn("expectedAnswer", item)
                self.assertNotIn("explanation", item)
                row = solver_record(item, originals[item["prompt"]]["expectedAnswer"])
                if item["index"] in solver_rejected:
                    for choice in row["choices"].values():
                        choice["judgment"] = "refuted"
                rows.append(row)
            return solver_map(*rows)

        def review(request):
            items = task_data(request, "question_review_json")["items"]
            self.assertEqual(len(items), authored_count - len(solver_rejected))
            rows = {}
            for item in items:
                original = originals[item["prompt"]]
                self.assertEqual(item["explanation"], original["explanation"])
                self.assertNotIn("expectedAnswer", item)
                self.assertNotIn("difficulty", item)
                rows[str(item["index"])] = {
                    "valid": item["index"] not in review_rejected,
                    "answer": original["expectedAnswer"],
                    "difficulty": 3,
                    "explanationSupport": "supported",
                    "issueFlags": authored_issue_flags(),
                }
            return {"reviews": rows}

        survivor_count = authored_count - len(solver_rejected)
        return ScriptedNativeClient(
            (f"question_author_v4_n{authored_count}", author_payload(*self.questions[:authored_count])),
            (f"complete_choice_solver_v5_n{authored_count}", solve),
            (f"authored_solution_reviewer_v3_n{survivor_count}", review),
        )

    def test_seven_authored_and_verified_rows_return_only_five_unchanged(self):
        client = self.client()
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        result = generation._generate_sanitized_questions(self.request, client, budget)
        self.assertEqual(len(client.calls), 3)
        self.assertEqual((budget.calls, reserve.call_count), (3, 3))
        self.assertEqual(task_data(client.calls[0], "generation_request_json")["targetCount"], 7)
        self.assertEqual(self.request["targetCount"], 5)
        author_schema = json.loads(client.calls[0]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
        self.assertEqual(set(author_schema["properties"]["questions"]["properties"]),
                         set(map(str, range(7))))
        self.assertEqual(set(author_schema["properties"]["questions"]["required"]),
                         set(map(str, range(7))))
        self.assertIn('"6"', client.calls[0]["system"][0]["text"])
        self.assertEqual([row["prompt"] for row in result], [q["prompt"] for q in self.questions[:5]])
        for result_row, authored in zip(result, self.questions[:5], strict=True):
            self.assertEqual(result_row["expectedAnswer"], authored["expectedAnswer"])
            self.assertEqual(result_row["explanation"], authored["explanation"])
            self.assertCountEqual(result_row["choices"], authored["choices"])
            self.assertEqual(result_row["choices"].count(authored["expectedAnswer"]), 1)
            self.assertEqual(result_row["choiceExplanations"], {})

    def test_six_five_and_four_review_survivors_keep_source_identity(self):
        for rejected in ({1}, {1, 4}, {0, 2, 4}):
            with self.subTest(rejected=rejected):
                client = self.client(review_rejected=rejected)
                result = generation._generate_sanitized_questions(
                    self.request, client, generation.ProviderCallBudget(6),
                )
                surviving = [q for index, q in enumerate(self.questions) if index not in rejected][:5]
                if len(surviving) < 5:
                    self.assertEqual(result, [])
                else:
                    self.assertEqual([q["prompt"] for q in result], [q["prompt"] for q in surviving])
                    self.assertEqual([q["expectedAnswer"] for q in result],
                                     [q["expectedAnswer"] for q in surviving])
                    self.assertEqual([q["explanation"] for q in result],
                                     [q["explanation"] for q in surviving])
                self.assertEqual(len(client.calls), 3)

    def test_solver_rejection_uses_dense_review_count_and_original_key(self):
        client = self.client(solver_rejected={2})
        result = generation._generate_sanitized_questions(
            self.request, client, generation.ProviderCallBudget(3),
        )
        self.assertEqual([q["prompt"] for q in result],
                         [self.questions[i]["prompt"] for i in (0, 1, 3, 4, 5)])
        self.assertEqual(client.calls[2]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"],
                         "authored_solution_reviewer_v3_n6")

    def test_budget_and_deadline_refuse_before_provider_call(self):
        for budget, error in (
            (generation.ProviderCallBudget(2), ProviderCallBudgetExceededError),
            (generation.ProviderCallBudget(3, context=FakeLambdaContext(0)),
             ProviderDeadlineExceededError),
        ):
            with self.subTest(error=error):
                client = self.client()
                with self.assertRaises(error):
                    generation._generate_sanitized_questions(self.request, client, budget)
                self.assertEqual(client.calls, [])

        context = FakeLambdaContext(300_000)
        client = self.client()
        authored = client.steps[0][1]

        def author_then_expire(_request):
            context.remaining_milliseconds = 0
            return authored

        client.steps[0] = (client.steps[0][0], author_then_expire)
        with self.assertRaises(ProviderDeadlineExceededError):
            generation._generate_sanitized_questions(
                self.request, client, generation.ProviderCallBudget(3, context=context),
            )
        self.assertEqual(len(client.calls), 1)

    def test_flag_is_off_by_default_and_excludes_mapped_or_source_requests(self):
        with patch.dict(os.environ, {"QUESTION_GENERIC_PROSE_RESERVE_7": "disabled"}):
            client = self.client(authored_count=5)
            result = generation._generate_sanitized_questions(
                self.request, client, generation.ProviderCallBudget(3),
            )
            self.assertEqual(len(result), 5)
            self.assertEqual(task_data(client.calls[0], "generation_request_json")["targetCount"], 5)
        for change in (
            {"skillMap": {"skills": []}},
            {"requestedSkillAllocation": {"skill": 5}},
            {"requestedObjectiveAllocation": [{"skillID": "s", "objectiveID": "o", "count": 5}]},
            {"sourceDocuments": [{"text": "Source scope"}]},
            {"adaptiveSkillPlans": [{"skillID": "s", "targetDifficulty": 3}]},
        ):
            with self.subTest(change=change):
                self.assertFalse(generation._generic_prose_reserve_enabled(
                    {**self.request, **change}, "prose", "count_bound", "authored_solution",
                ))
        sourced = _request_payload(target_count=5)
        sourced["sourceDocuments"] = [{"name": "Scope", "text": "A source statement."}]
        self.assertFalse(generation._generic_prose_reserve_enabled(
            _normalize_request(sourced), "prose", "count_bound", "authored_solution",
        ))
