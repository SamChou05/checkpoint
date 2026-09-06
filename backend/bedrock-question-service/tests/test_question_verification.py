import copy
import json
import unittest
from unittest import mock

from lambda_test_support import FakeBedrockClient, _raw_question, _request_payload
from question_generation import ProviderCallBudget, _generate_sanitized_questions
from question_generation import _verification_model_id
from question_verification import verify_questions
from question_verification import _claims_unbounded_linear_pair_output
from request_contract import _normalize_request
from service_errors import ProviderCallBudgetExceededError


class QuestionVerificationTests(unittest.TestCase):
    def test_pair_output_guard_rejects_unbounded_enumeration_and_preserves_bounded_variants(
        self,
    ):
        prompt = "Find all pairs in an unsorted array that sum to k. Which approach gives O(n) time?"
        self.assertTrue(_claims_unbounded_linear_pair_output(prompt))
        for bounded in [
            prompt.replace("all pairs", "all unique pairs"),
            prompt.replace("O(n)", "O(n + k)"),
            prompt.replace("all pairs", "whether any pair exists"),
            prompt + " The array has no duplicates.",
        ]:
            self.assertFalse(_claims_unbounded_linear_pair_output(bounded))

    def test_review_uses_its_pinned_model_separately_from_author(self):
        with mock.patch.dict(
            "os.environ",
            {
                "BEDROCK_MODEL_ID": "author-model",
                "BEDROCK_VERIFICATION_MODEL_ID": "review-model",
            },
        ):
            self.assertEqual(_verification_model_id(), "review-model")
        with mock.patch.dict(
            "os.environ",
            {"BEDROCK_MODEL_ID": "author-model", "BEDROCK_VERIFICATION_MODEL_ID": ""},
        ):
            self.assertEqual(_verification_model_id(), "us.anthropic.claude-sonnet-4-6")

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
            {"explanation": "Choice B gives the required conclusion."},
        ]:
            with self.subTest(change=change):
                accepted = verify_questions(
                    [self.question],
                    self.request,
                    lambda *_: json.dumps({"reviews": [self.verdict(**change)]}),
                )
                self.assertEqual(accepted, [])

    def test_long_and_truncated_duplicate_choices_never_reach_review(self):
        for choices in [
            ["x" * 141, "second", "third", "fourth"],
            [
                "A complete explanation with a sufficiently long shared prefix for a choice",
                "A complete explanation with a sufficiently long shared prefix for a choice tail",
                "third",
                "fourth",
            ],
        ]:
            question = {
                **self.question,
                "choices": choices,
                "expectedAnswer": choices[0],
            }
            reviewer = mock.Mock()
            self.assertEqual(verify_questions([question], self.request, reviewer), [])
            reviewer.assert_not_called()

    def test_conditional_inference_requires_a_valid_unique_proof(self):
        question = {
            **self.question,
            "prompt": "Which conclusion must follow from these statements?",
        }
        request = {**self.request, "goal": {"title": "Study for the LSAT"}}
        verdict = self.verdict()
        review = lambda *_: json.dumps({"reviews": [verdict]})  # noqa: E731
        self.assertEqual(verify_questions([question], request, review), [])
        choices = question["choices"]
        verdict["logicProof"] = {
            "atoms": {
                "A": "first property",
                "B": "second property",
                "C": "third property",
            },
            "premises": [["implies", "A", "B"], ["implies", "B", "C"]],
            "choiceClaims": {
                choices[0]: ["implies", "A", "C"],
                choices[1]: ["implies", "B", "A"],
                choices[2]: ["implies", "C", "A"],
                choices[3]: ["implies", "A", ["not", "C"]],
            },
        }
        self.assertEqual(len(verify_questions([question], request, review)), 1)
        verdict["logicProof"]["premises"] = [
            ["implies", "B", "A"],
            ["implies", "B", "C"],
        ]
        self.assertEqual(verify_questions([question], request, review), [])

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

    def test_reviewed_difficulty_replaces_author_label_but_respects_adaptive_target(
        self,
    ):
        def review(*_):
            return json.dumps({"reviews": [self.verdict(difficulty=4)]})

        accepted = verify_questions([self.question], self.request, review)
        self.assertEqual(accepted[0]["difficulty"], 4)
        self.question["skillID"] = "skill-a"
        self.request["adaptiveSkillPlans"] = [
            {"skillID": "skill-a", "targetDifficulty": 3}
        ]
        self.assertEqual(verify_questions([self.question], self.request, review), [])
        self.request["adaptiveSkillPlans"][0]["targetDifficulty"] = 4
        self.assertEqual(
            verify_questions([self.question], self.request, review)[0]["difficulty"], 4
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
