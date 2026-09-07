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
from question_verification import verify_questions
from request_contract import _normalize_request

FIXTURES = json.loads(
    (Path(__file__).parent / "fixtures/embedded_options_contract.json").read_text()
)
REVIEWED_STEM = json.loads(
    (Path(__file__).parent / "fixtures/reviewed_stem_contract.json").read_text()
)


class EmbeddedOptionsTests(unittest.TestCase):
    def test_reordered_reviewed_choices_do_not_make_the_stimulus_disposable(self):
        # Synthetic integrity contract shared with the iOS admission test. The
        # fixed model replies isolate transport behavior, not model accuracy.
        raw = REVIEWED_STEM["raw_author_question"]
        request = _normalize_request(REVIEWED_STEM["request"])
        sanitized = _sanitize_questions([raw], request)
        self.assertEqual(sanitized, [REVIEWED_STEM["sanitized_question"]])
        self.assertEqual(sanitized[0]["prompt"], raw["prompt"])
        self.assertNotEqual(sanitized[0]["choices"], raw["choices"])
        script_lines = raw["prompt"].split("\n")[1:]
        self.assertEqual(script_lines, sanitized[0]["choices"])
        self.assertEqual(script_lines[0], raw["expectedAnswer"])
        self.assertEqual(len(ast.parse("\n".join(script_lines)).body), 4)
        seen_stages = []

        def response(stage, prompt, result_key):
            data = json.loads(
                prompt.split(f"<question_{stage}_json>\n", 1)[1].split(
                    f"\n</question_{stage}_json>", 1
                )[0]
            )
            self.assertEqual(data["items"][0]["prompt"], raw["prompt"])
            seen_stages.append(stage)
            return json.dumps(REVIEWED_STEM[result_key])

        verified = verify_questions(
            sanitized,
            request,
            lambda _, prompt: response("review", prompt, "fixed_reviewer_response"),
            solve=lambda _, prompt: response("solution", prompt, "fixed_solver_response"),
        )
        self.assertEqual(seen_stages, ["solution", "review"])
        self.assertEqual(
            json.loads(json.dumps(verified)), [REVIEWED_STEM["verified_response"]]
        )

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
