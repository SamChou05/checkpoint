"""Bounded numerical-meaning vetoes before the fallible model solver."""

import itertools
import unittest

from complete_question_solution import rejection_reason
from lambda_test_support import _request_payload
from plain_scalar_choices import has_plain_scalar_collision
from question_quality import _sanitize_questions
from question_verification import _has_reviewable_choices
from request_contract import _normalize_request


def question(prompt, choices, answer):
    return {
        "prompt": prompt, "choices": choices, "expectedAnswer": answer,
        "explanation": "The shown values follow from the given numerical facts.",
        "topic": "Arithmetic", "difficulty": 3, "format": "Multiple Choice",
    }


class PlainScalarChoiceTests(unittest.TestCase):
    def setUp(self):
        self.request = _normalize_request(_request_payload(target_count=1))

    def test_word_and_digit_duplicate_is_rejected_before_false_model_judgment(self):
        item = question("What is 1 + 1?", ["3", "2", "two", "4"], "3")
        self.assertTrue(has_plain_scalar_collision(item["prompt"], item["choices"]))
        # All pairs marked distinct and one answer marked supported used to pass
        # the declaration gate. The runtime preflight now rejects this item.
        record = {
            "index": 0,
            "choices": [
                {"choice": choice, "judgment": "supported" if choice == "3" else "refuted",
                 "reason": "Model declares this result."}
                for choice in item["choices"]
            ],
            "choicePairs": [
                {"leftChoice": left, "rightChoice": right, "relation": "distinct",
                 "reason": "Model declares them distinct."}
                for left, right in itertools.combinations(item["choices"], 2)
            ],
        }
        self.assertIsNone(rejection_reason(record, item, audit_choice_pairs=True))
        self.assertEqual(_sanitize_questions([item], self.request), [])
        self.assertFalse(_has_reviewable_choices(item))

    def test_fraction_percent_and_decimal_equivalence_is_exact(self):
        prompt = "What is the probability of selecting one red marble from four equally likely marbles?"
        for choices in (["1/4", "25%", "50%", "0"], ["0.25", "1/4", "0.5", "0"]):
            item = question(prompt, choices, choices[0])
            with self.subTest(choices=choices):
                self.assertTrue(has_plain_scalar_collision(prompt, choices))
                self.assertEqual(_sanitize_questions([item], self.request), [])
                self.assertFalse(_has_reviewable_choices(item))
        distinct = question(prompt, ["1/4", "20%", "50%", "0"], "1/4")
        self.assertFalse(has_plain_scalar_collision(prompt, distinct["choices"]))
        self.assertEqual(len(_sanitize_questions([distinct], self.request)), 1)

    def test_compound_number_words_duplicate_digit_counts(self):
        prompt = "How many seats are occupied in the stated row?"
        for digit, word in (("21", "twenty-one"), ("30", "thirty"),
                            ("42", "forty two"), ("99", "Ninety-Nine")):
            item = question(prompt, [digit, word, "12", "15"], digit)
            with self.subTest(word=word):
                self.assertTrue(has_plain_scalar_collision(prompt, item["choices"]))
                self.assertEqual(_sanitize_questions([item], self.request), [])
                self.assertFalse(_has_reviewable_choices(item))

        # Exact phrase parsing must not fold an unrelated word or literal.
        self.assertFalse(has_plain_scalar_collision(prompt,
                                                     ["21", "twenty-onetwo", "12", "15"]))
        self.assertFalse(has_plain_scalar_collision(prompt,
                                                     ["21", "twenty--one", "12", "15"]))

    def test_written_representation_and_code_output_are_not_collapsed(self):
        for item in (
            question("Which written notation uses a percent sign to represent one quarter?",
                     ["25%", "1/4", "0.25", "2/4"], "25%"),
            question("What string is printed by this Python code?",
                     ["2", "two", "3", "4"], "two"),
            question("Which written notation spells out the count of 21?",
                     ["21", "twenty-one", "twenty two", "22"], "twenty-one"),
        ):
            with self.subTest(prompt=item["prompt"]):
                self.assertFalse(has_plain_scalar_collision(item["prompt"], item["choices"]))
                self.assertEqual(len(_sanitize_questions([item], self.request)), 1)
                self.assertTrue(_has_reviewable_choices(item))

    def test_unparsed_units_expressions_and_unmarked_tasks_remain_model_judgments(self):
        self.assertFalse(has_plain_scalar_collision("What is the value of this expression?",
                                                     ["2 cm", "0.02 m", "3 cm", "4 cm"]))
        self.assertFalse(has_plain_scalar_collision("Which object has two handles?",
                                                     ["2", "two", "3", "4"]))
        self.assertFalse(has_plain_scalar_collision("What is the value?",
                                                     ["1/0", "0", "1", "2"]))


if __name__ == "__main__":
    unittest.main()
