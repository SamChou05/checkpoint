import copy
import json
import unittest

from lambda_test_support import FakeBedrockClient, _raw_question, _request_payload
from question_generation import ProviderCallBudget, _generate_sanitized_questions
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import ProviderCallBudgetExceededError


class QuestionVerificationTests(unittest.TestCase):
    def setUp(self):
        self.question = _raw_question(
            "Which conclusion is supported by the stated argument?"
        )
        self.request = _normalize_request(_request_payload(target_count=1))

    def verdict(self, **changes):
        return {
            "index": 0,
            "valid": True,
            "answer": self.question["expectedAnswer"],
            "difficulty": 3,
            "explanation": "The premise supports the conclusion through the stated relationship.",
            "choiceExplanations": {
                choice: "This choice can be evaluated against the specific premises."
                for choice in self.question["choices"]
            },
            **changes,
        }

    def test_review_is_blind_to_authored_key_explanation_and_level(self):
        prompts = []

        def reviewer(system, prompt):
            prompts.append((system, prompt))
            data = json.loads(
                prompt.split("<question_review_json>\n")[1].split(
                    "\n</question_review_json>"
                )[0]
            )
            item = data["items"][0]
            self.assertNotIn("expectedAnswer", item)
            self.assertNotIn("explanation", item)
            self.assertNotIn("difficulty", item)
            self.assertEqual(set(item["choices"]), set(self.question["choices"]))
            return json.dumps({"reviews": [self.verdict()]})

        accepted = verify_questions([self.question], self.request, reviewer)
        self.assertEqual(accepted[0]["verificationVersion"], 1)
        self.assertEqual(accepted[0]["explanation"], self.verdict()["explanation"])
        self.assertEqual(len(accepted[0]["choiceExplanations"]), 4)
        self.assertIn("counterexamples", prompts[0][0])

    def test_disagreement_ambiguity_missing_choice_and_wrong_difficulty_fail_closed(
        self,
    ):
        for change in [
            {"valid": False},
            {"answer": "0.017 is absent from the choices"},
            {"answer": self.question["choices"][1]},
            {"difficulty": 1},
            {"valid": "true"},
            {"choiceExplanations": {}},
            {"explanation": "Unclear"},
            {"explanation": "x" * 421},
        ]:
            with self.subTest(change=change):
                accepted = verify_questions(
                    [self.question],
                    self.request,
                    lambda *_: json.dumps({"reviews": [self.verdict(**change)]}),
                )
                self.assertEqual(accepted, [])

    def test_missing_duplicate_or_malformed_review_never_approves(self):
        for payload in [
            "bad JSON",
            "{}",
            '{"reviews":[]}',
            json.dumps({"reviews": [self.verdict(), self.verdict()]}),
            json.dumps({"reviews": [self.verdict(index=True)]}),
        ]:
            with self.subTest(payload=payload):
                self.assertEqual(
                    verify_questions([self.question], self.request, lambda *_: payload),
                    [],
                )

    def test_generation_cannot_return_an_unverified_question_when_budget_runs_out(self):
        client = FakeBedrockClient.returning_questions(self.question)
        budget = ProviderCallBudget(1)
        with self.assertRaises(ProviderCallBudgetExceededError):
            _generate_sanitized_questions(self.request, client, call_budget=budget)
        self.assertEqual(budget.calls, 1)
        self.assertEqual(client.review_calls, [])

    def test_rejected_candidate_is_replaced_and_every_provider_call_is_counted(self):
        replacement = copy.deepcopy(self.question)
        replacement["prompt"] = (
            "Which assumption bridges this different set of evidence to the conclusion?"
        )
        client = FakeBedrockClient(
            [
                json.dumps({"questions": [self.question]}),
                json.dumps({"reviews": [self.verdict(valid=False)]}),
                json.dumps({"questions": [replacement]}),
                json.dumps({"reviews": [self.verdict()]}),
            ],
            auto_review=False,
        )
        budget = ProviderCallBudget(4)
        accepted = _generate_sanitized_questions(
            self.request, client, call_budget=budget
        )
        self.assertEqual([q["prompt"] for q in accepted], [replacement["prompt"]])
        self.assertEqual(budget.calls, 4)
        self.assertEqual(len(client.calls), 4)
        retry_prompt = client.calls[2]["messages"][0]["content"][0]["text"]
        self.assertIn(self.question["prompt"], retry_prompt)
