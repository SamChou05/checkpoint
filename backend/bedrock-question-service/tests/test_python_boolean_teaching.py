"""Fail-closed regression for two observed false universal teaching claims."""

import unittest

from lambda_test_support import _request_payload
from python_boolean_teaching import has_incomplete_python_boolean_rule
from question_quality import _sanitize_questions
from question_teaching import AuthoredTeachingFormatError, freeze_authored_question
from request_contract import _normalize_request


PYTHON_PROMPT = "In Python 3.12, what value does 0 or 'go' return?"
PYTHON_TOPIC = "Python 3 Boolean expressions"
FALSE_OR = (
    '`or` returns the first truthy operand without evaluating the rest. '
    '"go" is truthy, so the expression short-circuits and returns "go".'
)
FALSE_AND = (
    '`and` returns the first falsy operand. 5 is truthy, so evaluation continues. '
    '0 is falsy, so `and` returns 0 immediately.'
)


def question(prompt=PYTHON_PROMPT, explanation=FALSE_OR):
    return {
        "prompt": prompt, "choices": ['"go"', "0", "None", "False"],
        "expectedAnswer": '"go"', "explanation": explanation,
        "topic": PYTHON_TOPIC, "difficulty": 3, "format": "Multiple Choice",
    }


class PythonBooleanTeachingTests(unittest.TestCase):
    def test_observed_unqualified_rules_are_rejected_even_with_correct_local_result(self):
        observed = (
            '`or` evaluates left to right and returns the first truthy operand '
            'without evaluating the rest. "ready" is a non-empty string and '
            'therefore truthy, so it is returned immediately.',
            '`or` returns the first truthy operand without evaluating the rest. '
            '"go" is truthy, so the expression short-circuits and returns "go"; '
            '`10 // 0` is never executed.',
            FALSE_AND,
        )
        for explanation in observed:
            with self.subTest(explanation=explanation):
                self.assertTrue(has_incomplete_python_boolean_rule(
                    PYTHON_PROMPT, PYTHON_TOPIC, explanation
                ))
                with self.assertRaisesRegex(AuthoredTeachingFormatError, "Incomplete Python"):
                    freeze_authored_question(question(explanation=explanation))

    def test_complete_or_and_rules_and_local_only_explanations_survive(self):
        valid = (
            '`or` returns the first truthy operand, or the last operand when all are falsy. '
            'Here "go" is truthy and is returned.',
            '`and` evaluates left to right and returns the first falsy operand, '
            'or the last operand if all are truthy. Here 0 is the first falsy one.',
            '`or` returns the first truthy operand if one exists. Otherwise it '
            'returns the last operand. Here "go" is truthy.',
            '`and` returns the first falsy operand when one exists. Here 0 is '
            'falsy, so evaluation stops at 0.',
            'In this expression, `or` returns the first truthy operand, "go". '
            'The preceding 0 is falsy.',
            '`or` returns the first truthy operand in this expression, "go", '
            'after checking the preceding 0.',
            'The claim that `or` returns the first truthy operand is incomplete: '
            'if none is truthy, it returns the last operand.',
        )
        for explanation in valid:
            with self.subTest(explanation=explanation):
                self.assertFalse(has_incomplete_python_boolean_rule(
                    PYTHON_PROMPT, PYTHON_TOPIC, explanation
                ))
                self.assertEqual(freeze_authored_question(question(explanation=explanation))[
                    "explanation"
                ], explanation)

    def test_other_languages_and_non_rule_prose_are_untouched(self):
        for prompt, topic, explanation in (
            ("What does this Ruby expression return?", "Ruby", FALSE_OR),
            ("What does this logic circuit output?", "Digital logic", FALSE_AND),
            (PYTHON_PROMPT, PYTHON_TOPIC, '"go" is the first truthy value here and is returned.'),
        ):
            with self.subTest(topic=topic, explanation=explanation):
                self.assertFalse(has_incomplete_python_boolean_rule(prompt, topic, explanation))

    def test_sanitizer_skips_bad_authored_row_and_retains_good_surplus(self):
        request = _normalize_request(_request_payload(target_count=1))
        good = question(
            prompt="In Python 3.12, what value does False or 'go' return?",
            explanation='In this expression, `or` returns the first truthy operand, "go". '
                        'False is falsy, so it is skipped.',
        )
        metrics = {}
        admitted = _sanitize_questions(
            [question(), good], request, metrics, preserve_authored_explanation=True
        )
        self.assertEqual([row["prompt"] for row in admitted], [good["prompt"]])
        self.assertEqual(metrics["QuestionQuality"]["sanitize"]["invalid_content"], 1)


if __name__ == "__main__":
    unittest.main()
