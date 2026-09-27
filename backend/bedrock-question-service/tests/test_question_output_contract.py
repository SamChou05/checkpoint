"""Malformed provider output must fail closed without losing verified work."""

import json
import unittest
from unittest import mock

from lambda_test_support import (
    FakeBedrockClient,
    _complete_solution,
    _raw_question,
    _request_payload,
)
from question_generation import ProviderCallBudget, _generate_sanitized_questions
from question_quality import _extract_json_object
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import ProviderError


class QuestionOutputContractTests(unittest.TestCase):
    def setUp(self):
        self.question = _raw_question(
            "Which conclusion follows from the stated conditions?"
        )
        self.request = _normalize_request(_request_payload(target_count=1))

    def author_payload(self, token):
        return json.dumps({"questions": [self.question]}).replace(
            '"difficulty": 3', '"difficulty": ' + token
        )

    def verdict(self, question=None, index=0):
        question = question or self.question
        return {
            "index": index,
            "valid": True,
            "answer": question["expectedAnswer"],
            "difficulty": 3,
            "explanation": "The stated conditions establish the specified conclusion.",
            "choiceExplanations": {
                choice: "The stated logical relationship determines this choice."
                for choice in question["choices"]
            },
        }

    def complete_review(self, response, questions=None):
        questions = questions or [self.question]
        answers = {question["prompt"]: question["expectedAnswer"] for question in questions}

        def solve(_system, prompt):
            data = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])
            return json.dumps({
                "solutions": [
                    _complete_solution(item, answers[item["prompt"]])
                    for item in data["items"]
                ]
            })

        return verify_questions(
            questions, self.request, lambda *_: json.dumps(response),
            solve=solve, solver_contract="complete_choices",
        )

    def test_author_rejects_nonfinite_constants_and_overflowing_json_numbers(self):
        for token in ("Infinity", "-Infinity", "NaN", "1e309", "-1e309"):
            with self.subTest(token=token):
                with self.assertRaises(ProviderError):
                    _extract_json_object(self.author_payload(token))

    def test_nonfinite_author_difficulty_uses_bounded_json_retry(self):
        client = FakeBedrockClient([
            self.author_payload("1e309"),
            FakeBedrockClient.question_response(self.question),
        ])
        budget = ProviderCallBudget(4)
        accepted = _generate_sanitized_questions(self.request, client, budget)
        self.assertEqual([question["prompt"] for question in accepted], [self.question["prompt"]])
        self.assertEqual(budget.calls, 4)
        self.assertEqual(len(client.calls), 2)
        self.assertEqual(len(client.solution_calls), 1)
        self.assertEqual(len(client.review_calls), 1)
        self.assertEqual(accepted[0]["verificationPolicyRevision"], 2)

    def test_legacy_author_retries_instead_of_salvaging_surrounding_text(self):
        whole = FakeBedrockClient.question_response(self.question)
        malformed = (
            "The stated conditions may not support this answer.\n" + whole,
            whole + "\nA different choice may also be correct.",
            json.dumps([self.question]),
        )
        for first_response in malformed:
            with self.subTest(first_response=first_response), mock.patch.dict(
                "os.environ", {"BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy",
                               "BEDROCK_FALLBACK_MODEL_ID": ""},
            ):
                client = FakeBedrockClient([first_response, whole])
                budget = ProviderCallBudget(4)
                accepted = _generate_sanitized_questions(self.request, client, budget)
                self.assertEqual([item["prompt"] for item in accepted], [self.question["prompt"]])
                self.assertEqual((budget.calls, len(client.calls)), (4, 2))
                self.assertEqual((len(client.solution_calls), len(client.review_calls)), (1, 1))
                retry_prompt = client.calls[1]["messages"][0]["content"][0]["text"]
                self.assertIn("previous response could not be parsed", retry_prompt)

    def test_legacy_author_accepts_sole_json_fence_without_retry(self):
        whole = FakeBedrockClient.question_response(self.question)
        with mock.patch.dict("os.environ", {"BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy",
                                             "BEDROCK_FALLBACK_MODEL_ID": ""}):
            client = FakeBedrockClient("```json\n" + whole + "\n```")
            budget = ProviderCallBudget(3)
            accepted = _generate_sanitized_questions(self.request, client, budget)
        self.assertEqual([item["prompt"] for item in accepted], [self.question["prompt"]])
        self.assertEqual((budget.calls, len(client.calls)), (3, 1))
        self.assertEqual((len(client.solution_calls), len(client.review_calls)), (1, 1))

    def test_malformed_author_top_up_preserves_prior_verified_question(self):
        request = _normalize_request(_request_payload(target_count=2))
        replacement = _raw_question(
            "Which assumption supports this different conclusion?"
        )
        malformed = json.dumps({"questions": [replacement]}).replace(
            '"difficulty": 3', '"difficulty": 1e309'
        )
        client = FakeBedrockClient([
            FakeBedrockClient.question_response(self.question), malformed, malformed,
        ])
        budget = ProviderCallBudget(6)
        with mock.patch.dict("os.environ", {"BEDROCK_FALLBACK_MODEL_ID": ""}):
            accepted = _generate_sanitized_questions(request, client, budget)
        self.assertEqual([question["prompt"] for question in accepted], [self.question["prompt"]])
        self.assertEqual(budget.calls, 5)
        self.assertEqual(len(client.solution_calls), 1)
        self.assertEqual(len(client.review_calls), 1)

    def test_review_rejects_undeclared_envelope_fields(self):
        for extra in ({"rejected": True}, {"issues": ["No offered answer is correct."]}):
            with self.subTest(extra=extra):
                self.assertEqual(
                    self.complete_review({"reviews": [self.verdict()], **extra}), []
                )

    def test_review_rejects_undeclared_verdict_fields(self):
        for extra in (
            {"issues": ["No offered answer is correct."]},
            {"validity": "invalid"},
            {"repairedPrompt": "A different repaired question."},
            {"verificationPolicyRevision": 99},
        ):
            with self.subTest(extra=extra):
                self.assertEqual(
                    self.complete_review({"reviews": [{**self.verdict(), **extra}]}), []
                )

    def test_minimal_negative_review_keeps_other_valid_questions(self):
        rejected = _raw_question("Which assumption supports this alternative conclusion?")
        accepted = self.complete_review(
            {"reviews": [
                self.verdict(),
                {"index": 1, "valid": False, "answer": ""},
            ]},
            [self.question, rejected],
        )
        self.assertEqual([question["prompt"] for question in accepted], [self.question["prompt"]])


if __name__ == "__main__":
    unittest.main()
