"""Independent arithmetic and contract tests for the offline math prototype."""

from fractions import Fraction
from unittest.mock import patch
import re
import unittest

import math_reasoning_task_constructor as constructor


# These results were calculated from the printed expressions, separately from
# the constructor's derivation code. Tuple order is correct, precedence error,
# false fraction addition, and false multiplication/division.
EXPECTED = {
    "multiply_a": ("3/4 + 2/3 × 3/5", ("23/20", "17/20", "5/9", "3/2")),
    "multiply_b": ("1/2 + 1/3 × 3/4", ("3/4", "5/8", "1/3", "13/14")),
    "multiply_c": ("2/5 + 3/4 × 2/3", ("9/10", "23/30", "3/7", "44/35")),
    "divide_a": ("1/2 + 1/3 ÷ 2/3", ("1", "5/4", "1/2", "13/18")),
    "divide_b": ("3/5 + 2/3 ÷ 4/5", ("43/30", "19/12", "8/11", "17/15")),
    "divide_c": ("2/3 + 3/4 ÷ 2/5", ("61/24", "85/24", "17/11", "29/30")),
}


def task(scene: str) -> dict:
    return {"kind": constructor.TASK_KIND, "scene": scene}


def result_of(choice: str) -> Fraction:
    match = re.search(r"= (-?\d+(?:/\d+)?)\.$", choice)
    if match is None:
        raise AssertionError(f"Choice has no exact final value: {choice}")
    return Fraction(match.group(1))


class MathReasoningTaskConstructorTests(unittest.TestCase):
    def test_closed_task_rejects_model_prose_and_invalid_types(self):
        schema = constructor.task_schema()
        self.assertIs(schema["additionalProperties"], False)
        self.assertEqual(set(schema["properties"]["scene"]["enum"]), set(EXPECTED))
        invalid = (
            None, [], "multiply_a", {},
            {"kind": constructor.TASK_KIND},
            {**task("multiply_a"), "answer": "A"},
            {**task("multiply_a"), "kind": "exact_value"},
            {**task("multiply_a"), "scene": "invented"},
            {**task("multiply_a"), "scene": True},
        )
        for raw in invalid:
            with self.subTest(raw=raw), self.assertRaises(constructor.MathReasoningTaskError):
                constructor.compile_question(raw)
        for ordinal in (-1, 0.25, True, "1"):
            with self.subTest(ordinal=ordinal), self.assertRaises(constructor.MathReasoningTaskError):
                constructor.compile_question(task("multiply_a"), ordinal=ordinal)

    def test_all_scenes_have_four_different_exact_results_and_one_truth(self):
        self.assertEqual(set(constructor.SCENES), set(EXPECTED))
        prompts = set()
        for scene, (expression, expected) in EXPECTED.items():
            with self.subTest(scene=scene):
                question = constructor.compile_question(task(scene))
                self.assertEqual(set(question), set(constructor.LEARNER_FIELDS))
                self.assertEqual(question["prompt"],
                                 f"Which worked evaluation correctly computes {expression}?")
                prompts.add(question["prompt"])
                choices = question["choices"]
                self.assertEqual(len(choices), 4)
                self.assertEqual(len(set(choices)), 4)
                self.assertEqual(tuple(str(result_of(choice)) for choice in choices), expected)
                self.assertTrue(all(not choice.startswith(("Multiply first:", "Divide first:",
                                                           "Add first:", "Multiply instead of divide:"))
                                    for choice in choices))
                self.assertEqual(len({result_of(choice) for choice in choices}), 4)
                self.assertEqual(question["expectedAnswer"], choices[0])
                self.assertEqual(sum(result_of(choice) == Fraction(expected[0])
                                     for choice in choices), 1)
                self.assertEqual(set(question["choiceExplanations"]), set(choices))
                self.assertEqual(list(question["choiceExplanations"]), choices)
                self.assertEqual(sum(note.startswith("Correct.") for note in
                                     question["choiceExplanations"].values()), 1)
                self.assertEqual(sum(note.startswith("Incorrect.") for note in
                                     question["choiceExplanations"].values()), 3)
                self.assertIn("before addition", question["explanation"])
                self.assertIn("common denominator", question["choiceExplanations"][choices[2]])
                if scene.startswith("multiply"):
                    self.assertIn("denominators, not their sum",
                                  question["choiceExplanations"][choices[3]])
                else:
                    self.assertIn("reciprocal", question["choiceExplanations"][choices[3]])
        self.assertEqual(len(prompts), len(EXPECTED))

    def test_answer_and_feedback_follow_literal_choices_after_rotation(self):
        for scene in EXPECTED:
            first = constructor.compile_question(task(scene))
            for ordinal in range(1, 8):
                with self.subTest(scene=scene, ordinal=ordinal):
                    rotated = constructor.compile_question(task(scene), ordinal=ordinal)
                    self.assertEqual(rotated["choices"],
                                     first["choices"][ordinal % 4:] + first["choices"][:ordinal % 4])
                    self.assertEqual(rotated["expectedAnswer"], first["expectedAnswer"])
                    self.assertEqual(rotated["explanation"], first["explanation"])
                    self.assertEqual(rotated["choiceExplanations"], first["choiceExplanations"])
                    self.assertEqual(list(rotated["choiceExplanations"]), rotated["choices"])
                    self.assertEqual(rotated["choices"].count(rotated["expectedAnswer"]), 1)
                    self.assertEqual(rotated["choices"].index(rotated["expectedAnswer"]),
                                     (-ordinal) % 4)

    def test_all_variants_fit_content_limits_and_have_no_letter_key(self):
        for scene in EXPECTED:
            question = constructor.compile_question(task(scene))
            self.assertTrue(12 <= len(question["prompt"]) <= 320)
            self.assertTrue(all(1 <= len(choice) <= 140 for choice in question["choices"]))
            self.assertTrue(12 <= len(question["explanation"]) <= 420)
            self.assertTrue(all(1 <= len(note) <= 280 for note in
                                question["choiceExplanations"].values()))
            self.assertTrue(all(not re.match(r"^[A-D][.)] ", choice)
                                for choice in question["choices"]))
            self.assertNotRegex(question["explanation"], r"\b[A-D][.)] ")

    def test_colliding_wrong_result_fails_closed(self):
        # 1/2 + 1/2 × 1/2: adding product denominators yields 3/4,
        # accidentally the true value. A new scene with this trap must fail.
        trapped = constructor._Scene("multiply", Fraction(1, 2),
                                     Fraction(1, 2), Fraction(1, 2))
        with patch.dict(constructor.SCENES, {"collision": trapped}):
            with self.assertRaisesRegex(constructor.MathReasoningTaskError,
                                        "collides"):
                constructor.compile_question(task("collision"))


if __name__ == "__main__":
    unittest.main()
