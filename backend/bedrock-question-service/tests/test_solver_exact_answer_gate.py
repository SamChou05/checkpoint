"""Literal disagreement only; this gate does not interpret impossible prose."""

import copy
import json
import unittest
from unittest.mock import Mock

from question_verification import verify_questions


class SolverExactAnswerGateTests(unittest.TestCase):
    def setUp(self):
        self.question = {
            "prompt": "What is 2 + 2?",
            "expectedAnswer": "4",
            "choices": ["3", "4", "5", "6"],
            "topic": "Arithmetic",
            "difficulty": 1,
            "format": "Multiple Choice",
            "explanation": "Adding two and two gives four.",
        }
        self.request = {
            "goal": {"title": "Add whole numbers"},
            "minimumDifficulty": 1,
            "sourceDocuments": [],
        }

    def verify(self, answer):
        solver = Mock(
            return_value=json.dumps(
                {
                    "solutions": [
                        {
                            "index": 0,
                            "outcome": "resolved",
                            "answer": answer,
                            "limitations": "",
                            "assumptionsRequired": [],
                        }
                    ]
                }
            )
        )
        # This callback approves the author's key regardless of the solver.
        reviewer = Mock(
            return_value=json.dumps(
                {
                    "reviews": [
                        {
                            "index": 0,
                            "valid": True,
                            "answer": "4",
                            "difficulty": 1,
                            "explanation": "Adding two and two gives four.",
                            "choiceExplanations": {
                                "3": "Three is one less than the required sum.",
                                "4": "Four is the sum of two and two.",
                                "5": "Five is one more than the required sum.",
                                "6": "Six is two more than the required sum.",
                            },
                        }
                    ]
                }
            )
        )
        original = copy.deepcopy(self.question)
        metrics = {}
        accepted = verify_questions(
            [self.question], self.request, reviewer, metrics, solve=solver
        )
        self.assertEqual(self.question, original)
        solver.assert_called_once()
        payload = json.loads(
            solver.call_args.args[1].split("\n", 1)[1].rsplit("\n", 1)[0]
        )
        for field in ("choices", "expectedAnswer", "explanation"):
            self.assertNotIn(field, payload["items"][0])
        return accepted, reviewer, metrics

    def test_exact_different_offered_answer_blocks_before_approving_review(self):
        for answer in ("3", "5", "6"):
            with self.subTest(answer=answer):
                accepted, reviewer, metrics = self.verify(answer)
                self.assertEqual(accepted, [])
                reviewer.assert_not_called()
                self.assertEqual(
                    metrics["QuestionQuality"]["review"],
                    {"answer_disagreement": 1},
                )

    def test_exact_authored_answer_keeps_the_current_review_route(self):
        accepted, reviewer, metrics = self.verify("4")
        reviewer.assert_called_once()
        self.assertEqual([item["expectedAnswer"] for item in accepted], ["4"])
        self.assertEqual(metrics["QuestionQuality"]["review"], {"accepted": 1})

    def test_ordinary_nonexact_summary_is_not_required_to_equal_an_option(self):
        accepted, reviewer, metrics = self.verify(
            "Adding two and two gives four because there are two pairs."
        )
        reviewer.assert_called_once()
        self.assertEqual([item["expectedAnswer"] for item in accepted], ["4"])
        self.assertEqual(metrics["QuestionQuality"]["review"], {"accepted": 1})


if __name__ == "__main__":
    unittest.main()
