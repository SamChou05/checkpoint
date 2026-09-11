"""Different tasks can use the same answer vocabulary without being duplicates."""

import copy
import json
from pathlib import Path
import unittest

from lambda_test_support import FakeBedrockClient, _request_payload
from question_generation import ProviderCallBudget, _generate_sanitized_questions
from question_quality import _sanitize_questions
from request_contract import _normalize_request


CASES = json.loads(
    (Path(__file__).parent / "fixtures/reusable_answer_contract.json").read_text()
)


class ReusableAnswerTests(unittest.TestCase):
    def request(self, count=2, history=()):
        payload = _request_payload(target_count=count, minimum_difficulty=1)
        payload["existingQuestionCoverage"] = list(history)
        return _normalize_request(payload)

    def assert_content(self, actual, expected):
        self.assertEqual(len(actual), len(expected))
        for question, source in zip(actual, expected, strict=True):
            self.assertEqual(question["prompt"], source["prompt"])
            self.assertEqual(question["expectedAnswer"], source["expectedAnswer"])
            self.assertCountEqual(question["choices"], source["choices"])

    def test_different_tasks_keep_their_choices_and_keys_in_one_batch(self):
        for pair in CASES:
            with self.subTest(topic=pair[0]["topic"]):
                self.assert_content(_sanitize_questions(pair, self.request()), pair)

    def test_history_does_not_exhaust_an_answer_vocabulary(self):
        for first, second in CASES:
            with self.subTest(topic=first["topic"]):
                request = self.request(count=1, history=[first])
                self.assert_content(_sanitize_questions([second], request), [second])

    def test_an_exact_stem_still_rejects_even_when_its_key_and_choices_change(self):
        for first, second in CASES:
            repeat = {**second, "prompt": first["prompt"]}
            for request, batch in [
                (self.request(), [first, repeat, second]),
                (self.request(history=[first]), [repeat, second]),
            ]:
                metrics = {}
                result = _sanitize_questions(batch, request, metrics)
                self.assertEqual(result[-1]["prompt"], second["prompt"])
                self.assertEqual(metrics["QuestionQuality"]["sanitize"]["duplicate_stem"], 1)

    def test_within_question_duplicates_and_missing_keys_still_reject(self):
        first = CASES[0][0]
        for malformed in [
            {**first, "choices": ["noun", "noun", "adjective", "adverb"]},
            {**first, "expectedAnswer": "not an offered choice"},
        ]:
            self.assertEqual(_sanitize_questions([malformed], self.request()), [])

    def test_generation_checks_both_questions_in_a_single_complete_pass(self):
        for pair in CASES:
            client = FakeBedrockClient.returning_questions(*copy.deepcopy(pair))
            budget = ProviderCallBudget(3)
            result = _generate_sanitized_questions(self.request(), client, budget)
            self.assert_content(result, pair)
            self.assertEqual(budget.calls, 3)
            self.assertEqual(len(client.solution_calls), 1)
            self.assertEqual(len(client.review_calls), 1)
            self.assertTrue(all(q["verificationPolicyRevision"] == 2 for q in result))
