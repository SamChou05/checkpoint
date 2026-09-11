"""Mentions of intermediate results or distractors are not semantic verdicts."""

import copy
import json
import unittest
from unittest.mock import patch

from lambda_test_support import FakeBedrockClient, _complete_solution, _request_payload
from question_generation import ProviderCallBudget, _generate_sanitized_questions
from question_quality import _sanitize_questions
from request_contract import _normalize_request


QUESTIONS = [
    {
        "prompt": "Compute -(2 - 5). What is the sign of the final result?",
        "expectedAnswer": "positive",
        "choices": ["positive", "negative", "zero", "undefined"],
        "explanation": "The intermediate result is negative: 2 - 5 = -3. Negating -3 gives 3.",
        "topic": "Arithmetic", "difficulty": 2,
    },
    {
        "prompt": "By side-length equality, how is a triangle with side lengths 3, 4 and 5 classified?",
        "expectedAnswer": "Scalene triangle",
        "choices": ["Equilateral triangle", "Isosceles triangle", "Scalene triangle", "Degenerate triangle"],
        "explanation": "Isosceles triangle is incorrect here: the three side lengths are all different.",
        "topic": "Geometry", "difficulty": 2,
    },
    {
        "prompt": "How many centimeters are in a length of 1.5 meters?",
        "expectedAnswer": "150 cm",
        "choices": ["150 cm", "15 cm", "1500 cm", "1.5 cm"],
        "explanation": "The provided choices use centimeters. Multiply 1.5 by 100 to convert meters to centimeters.",
        "topic": "Unit conversion", "difficulty": 2,
    },
]


class ExplanationPrefilterTests(unittest.TestCase):
    def request(self):
        return _normalize_request(_request_payload(target_count=1, minimum_difficulty=1))

    def test_correct_explanations_reach_semantic_checks_in_both_feedback_modes(self):
        self.assertEqual(-(2 - 5), 3)
        self.assertEqual(len({3, 4, 5}), 3)
        self.assertEqual(1.5 * 100, 150)
        for question in QUESTIONS:
            for authored in (False, True):
                with self.subTest(prompt=question["prompt"], authored=authored):
                    actual = _sanitize_questions(
                        [question], self.request(), preserve_authored_explanation=authored
                    )
                    self.assertEqual(len(actual), 1)
                    self.assertEqual(actual[0]["expectedAnswer"], question["expectedAnswer"])
                    self.assertEqual(actual[0]["explanation"], question["explanation"])

    def run_pipeline(self, question, *, supported_answer, authored=False, support="supported"):
        solution = _complete_solution({"index": 0, "choices": question["choices"]}, supported_answer)
        review = {"index": 0, "valid": True, "answer": supported_answer, "difficulty": 2}
        if authored:
            review.update(explanationSupport=support, issues=[])
        else:
            review.update(
                explanation="The final result is 3, which is greater than zero.",
                choiceExplanations={choice: "This choice is assessed against the final value, three."
                                    for choice in question["choices"]},
            )
        client = FakeBedrockClient([
            json.dumps({"questions": [question]}),
            json.dumps({"solutions": [solution]}),
            json.dumps({"reviews": [review]}),
        ], auto_review=False)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict("os.environ", {
            "GENERATION_ATTEMPTS": "1", "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy",
            "QUESTION_FEEDBACK_CONTRACT": "authored_solution" if authored else "reviewer_written",
        }):
            result = _generate_sanitized_questions(self.request(), client, ProviderCallBudget(3), metrics)
        return result, client, metrics

    def test_final_positive_key_survives_both_complete_verification_paths(self):
        for authored in (False, True):
            result, client, _ = self.run_pipeline(QUESTIONS[0], supported_answer="positive", authored=authored)
            self.assertEqual(result[0]["expectedAnswer"], "positive")
            self.assertEqual(result[0]["verificationPolicyRevision"], 3 if authored else 2)
            self.assertEqual(len(client.calls), 3)
            if authored:
                self.assertEqual(result[0]["explanation"], QUESTIONS[0]["explanation"])

    def test_a_wrong_key_is_still_rejected_before_final_review(self):
        wrong = {**QUESTIONS[0], "expectedAnswer": "negative"}
        for authored in (False, True):
            result, client, metrics = self.run_pipeline(wrong, supported_answer="positive", authored=authored)
            self.assertEqual(result, [])
            self.assertEqual(len(client.calls), 2)
            self.assertEqual(metrics["QuestionQuality"]["review"]["answer_disagreement"], 1)

    def test_unsupported_authored_teaching_is_still_rejected_by_its_auditor(self):
        wrong = {**QUESTIONS[0], "explanation": "The final result is negative, because negating -3 gives -3."}
        result, client, metrics = self.run_pipeline(wrong, supported_answer="positive", authored=True, support="unsupported")
        self.assertEqual(result, [])
        self.assertEqual(len(client.calls), 3)
        self.assertEqual(metrics["QuestionQuality"]["review"]["unsupported_authored_explanation"], 1)

    def test_structurally_invalid_content_still_cannot_reach_a_model(self):
        question = copy.deepcopy(QUESTIONS[0])
        question["choices"][1] = question["choices"][0]
        self.assertEqual(_sanitize_questions([question], self.request()), [])
