import copy
import json
import unittest
from unittest.mock import Mock

from complete_question_solution import build_solver_prompt, CompleteSolutionFormatError, SOURCE_SOLUTION_SYSTEM_PROMPT
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
        _, text = build_solver_prompt([item], self.request, context="displayed")
        data = json.loads(text.split("\n", 1)[1].rsplit("\n", 1)[0])
        self.assertEqual(data, {"items": [{k: item[k] for k in ("index", "prompt", "choices", "topic")}]})
        self.assertNotIn("Hidden", text)
        self.assertEqual(item, original)
        # Historical source-context experiments remain explicit and unchanged.
        _, historical = build_solver_prompt([item], self.request)
        self.assertIn("Hidden reference", historical)
        self.assertIn("Hidden objective premise", historical)

    def test_runtime_preserves_subject_references_but_hides_authored_item_metadata(self):
        client = FakeBedrockClient.returning_questions(self.raw)
        result = _generate_sanitized_questions(self.request, client, ProviderCallBudget(3))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["verificationPolicyRevision"], 8)
        def prompt(call):
            return call["messages"][0]["content"][0]["text"]
        self.assertIn("Hidden reference", prompt(client.calls[0]))
        self.assertIn("Hidden reference", prompt(client.review_calls[0]))
        solver_data = json.loads(prompt(client.solution_calls[0]).split("\n", 1)[1].rsplit("\n", 1)[0])
        self.assertEqual(set(solver_data), {"items", "sourceDocuments", "goal", "skillMap"})
        self.assertEqual(set(solver_data["items"][0]), {"index", "prompt", "choices", "topic"})
        self.assertEqual(solver_data["sourceDocuments"], self.request["sourceDocuments"])
        self.assertEqual(solver_data["goal"], self.request["goal"])
        self.assertEqual(solver_data["skillMap"], self.request.get("skillMap"))

    def test_historical_displayed_contract_rejects_source_recall(self):
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
        self.assertFalse(meets_verification_policy(result[0], 8))
        for old in range(8):
            self.assertFalse(meets_verification_policy({"verificationVersion": 1, "verificationPolicyRevision": old}, 8))

    def test_displayed_context_requires_the_complete_choice_contract(self):
        for kwargs in [{"solver_context": "other"}, {"solver_context": "displayed"}, {"solver_context": "source"}, {"solver_context": "subject"}]:
            with self.assertRaises(ValueError):
                verify_questions([self.raw], self.request, Mock(), **kwargs)

    def test_source_context_keeps_learned_facts_and_excludes_hidden_intent(self):
        item = {**self.raw, "index": 0, "objective": "Assume all tokens blue",
                "skillID": "blue-only", "objectiveID": "hidden-answer"}
        system, prompt = build_solver_prompt([item], self.request, context="source")
        self.assertEqual(system, SOURCE_SOLUTION_SYSTEM_PROMPT)
        data = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])
        self.assertEqual(data["sourceDocuments"], self.request["sourceDocuments"])
        self.assertEqual(data["items"], [{k: item[k] for k in ("index", "prompt", "choices", "topic")}])
        self.assertEqual(set(data), {"items", "sourceDocuments"})
        with self.assertRaises(CompleteSolutionFormatError):
            build_solver_prompt([item], self.request, context="unknown")

    def test_source_facts_do_not_override_a_solver_declared_missing_case(self):
        question = {**self.raw, "prompt": "Four tokens of unspecified color are earned. How many points?"}
        review = Mock()
        def solve(_, prompt):
            data = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])
            self.assertEqual(data["sourceDocuments"], self.request["sourceDocuments"])
            return json.dumps({"solutions": [{"index": 0, "choices": [
                {"choice": c, "judgment": "uncertain", "reason": "The color of these tokens is unspecified."}
                for c in data["items"][0]["choices"]
            ]}]})
        metrics = {}
        result = verify_questions([question], self.request, review, solve=solve,
                                  solver_contract="complete_choices", solver_context="source",
                                  request_metrics=metrics)
        self.assertEqual(result, [])
        self.assertEqual(metrics["QuestionQuality"]["review"]["solver_uncertain"], 1)
        review.assert_not_called()
