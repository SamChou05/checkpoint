import copy
import json
import unittest
from unittest.mock import Mock

from complete_question_solution import build_solver_prompt
from lambda_test_support import FakeBedrockClient, _complete_solution, _raw_question
from question_generation import ProviderCallBudget, _generate_sanitized_questions
from question_verification import verify_questions
from request_contract import _normalize_request
from verification_policy import meets_verification_policy


class DisplayedSolverTests(unittest.TestCase):
    def setUp(self):
        self.raw = _raw_question("Each blue token scores 3 points. What do 4 blue tokens score?")
        self.raw.update(choices=["12", "4", "7", "0"], expectedAnswer="12", topic="Scoring",
                        explanation="Each of four tokens scores three points, giving 4 times 3 = 12.")
        self.request = _normalize_request({
            "goal": {"title": "Hidden title", "contentTopics": ["Scoring"],
                     "questionDirective": "Hidden intended interpretation"},
            "sourceDocuments": [{"name": "Hidden reference", "text": "Hidden rule: blue tokens score 3 points."}],
            "targetCount": 1, "minimumDifficulty": 1,
        })

    def verdict(self):
        return {"index": 0, "valid": True, "answer": "12", "difficulty": 2,
                "explanation": self.raw["explanation"],
                "choiceExplanations": {c: "The stated rule yields twelve points in total." for c in self.raw["choices"]}}

    def test_display_contract_has_only_exact_learner_visible_fields(self):
        item = {**self.raw, "index": 0, "objective": "Hidden objective premise",
                "skillID": "hidden-skill", "objectiveID": "hidden-objective"}
        item["prompt"] = 'Read the literal lines:\n  x = "a  b"\n  print(x)'
        original = copy.deepcopy(item)
        _, text = build_solver_prompt([item], self.request, displayed_only=True)
        data = json.loads(text.split("\n", 1)[1].rsplit("\n", 1)[0])
        self.assertEqual(data, {"items": [{k: item[k] for k in ("index", "prompt", "choices", "topic")}]})
        self.assertNotIn("Hidden", text)
        self.assertEqual(item, original)
        # Historical source-context experiments remain explicit and unchanged.
        _, historical = build_solver_prompt([item], self.request)
        self.assertIn("Hidden reference", historical)
        self.assertIn("Hidden objective premise", historical)

    def test_runtime_author_and_reviewer_keep_sources_but_solver_cannot_use_them(self):
        client = FakeBedrockClient.returning_questions(self.raw)
        result = _generate_sanitized_questions(self.request, client, ProviderCallBudget(3))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["verificationPolicyRevision"], 4)
        def prompt(call):
            return call["messages"][0]["content"][0]["text"]
        self.assertIn("Hidden reference", prompt(client.calls[0]))
        self.assertIn("Hidden reference", prompt(client.review_calls[0]))
        solver_data = json.loads(prompt(client.solution_calls[0]).split("\n", 1)[1].rsplit("\n", 1)[0])
        self.assertEqual(set(solver_data), {"items"})
        self.assertEqual(set(solver_data["items"][0]), {"index", "prompt", "choices", "topic"})
        self.assertNotIn("Hidden", prompt(client.solution_calls[0]))

    def test_hidden_reference_cannot_rescue_declared_missing_premises(self):
        question = {**self.raw, "prompt": "A Luma player earns 4 blue tokens. How many points are earned?"}
        review = Mock(return_value=json.dumps({"reviews": [self.verdict()]}))
        def solve(_, prompt):
            self.assertNotIn("Hidden", prompt)
            item = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])["items"][0]
            return json.dumps({"solutions": [{"index": 0, "choices": [
                {"choice": c, "judgment": "uncertain", "reason": "The scoring rule is absent from the question."}
                for c in item["choices"]
            ]}]})
        self.assertEqual(verify_questions([question], self.request, review, solve=solve,
                                         solver_contract="complete_choices", solver_context="displayed"), [])
        review.assert_not_called()

    def test_historical_full_context_gate_cannot_issue_current_provenance(self):
        def solve(_, prompt):
            item = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])["items"][0]
            return json.dumps({"solutions": [_complete_solution(item, "12")]})
        result = verify_questions([self.raw], self.request,
                                  lambda *_: json.dumps({"reviews": [self.verdict()]}),
                                  solve=solve, solver_contract="complete_choices")
        self.assertEqual(result[0]["verificationPolicyRevision"], 2)
        self.assertFalse(meets_verification_policy(result[0], 4))
        for old in [0, 1, 2, 3]:
            self.assertFalse(meets_verification_policy({"verificationVersion": 1, "verificationPolicyRevision": old}, 4))

    def test_displayed_context_requires_the_complete_choice_contract(self):
        for kwargs in [{"solver_context": "other"}, {"solver_context": "displayed"}]:
            with self.assertRaises(ValueError):
                verify_questions([self.raw], self.request, Mock(), **kwargs)
