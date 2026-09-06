"""Real author regression: empty call/tuple syntax is not an answer list."""

import ast
import json
from pathlib import Path
import unittest

from lambda_test_support import _request_payload
from question_quality import (
    _prompt_contains_embedded_options,
    _prompt_without_trailing_choice_echo,
    _sanitize_questions,
)
from request_contract import _normalize_request

FIXTURES = json.loads(
    (Path(__file__).parent / "fixtures/embedded_options_contract.json").read_text()
)


class EmbeddedOptionsTests(unittest.TestCase):
    def test_real_python_question_and_empty_syntax_variants_survive(self):
        request = _normalize_request(_request_payload(target_count=1))
        for question in FIXTURES["valid_questions"]:
            with self.subTest(prompt=question["prompt"]):
                self.assertFalse(_prompt_contains_embedded_options(question["prompt"]))
                accepted = _sanitize_questions([question], request)
                self.assertEqual(len(accepted), 1)
                self.assertEqual(accepted[0]["prompt"], question["prompt"])

    def test_captured_answer_matches_the_actual_python_operations(self):
        # Run the fixed, inspected operations from this regression, not arbitrary
        # provider code. Parse only the literal answer for comparison.
        value = "a  b  c"
        text = value.replace("  ", "|", 1).strip()
        self.assertEqual(
            text.split(),
            ast.literal_eval(FIXTURES["valid_questions"][0]["expectedAnswer"]),
        )
        self.assertEqual(len(()) + len(()), 0)

    def test_explicit_choice_lists_still_fail_structural_validation(self):
        request = _normalize_request(_request_payload(target_count=1))
        for prompt in FIXTURES["embedded_choice_prompts"]:
            self.assertTrue(_prompt_contains_embedded_options(prompt))
            question = {**FIXTURES["valid_questions"][0], "prompt": prompt}
            self.assertEqual(_sanitize_questions([question], request), [])

    def test_exact_choice_echoes_are_removed_without_erasing_call_parentheses(self):
        question = FIXTURES["valid_questions"][0]
        for labeled in (False, True):
            echo = "\n".join(
                (f"{chr(65 + index)}. " if labeled else "") + choice
                for index, choice in enumerate(question["choices"])
            )
            echoed = {**question, "prompt": question["prompt"] + "\n\n" + echo}
            self.assertEqual(
                _prompt_without_trailing_choice_echo(
                    echoed["prompt"], question["choices"]
                ),
                question["prompt"],
            )
            request = _normalize_request(_request_payload(target_count=1))
            accepted = _sanitize_questions([echoed], request)
            self.assertEqual(len(accepted), 1)
            self.assertEqual(accepted[0]["prompt"], question["prompt"])
