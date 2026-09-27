"""Independent arithmetic checks for the offline comparison constructor."""

from fractions import Fraction
import re
import unittest

from math_comparison_task_constructor import (
    FAMILIES, LEARNER_FIELDS, ORDERS, PAIRS, TASK_KIND,
    MathComparisonTaskError, compile_question, task_schema,
)


EXPRESSION = re.compile(r"^(\d+)/(\d+) ([+×]) (\d+)/(\d+)$")
CHOICE = re.compile(r"^([AB]) is larger than ([AB]) by (\d+(?:/\d+)?)\.$")


def task(family: str, pair: str, order: str = "forward") -> dict:
    return {"kind": TASK_KIND, "family": family, "pair": pair, "order": order}


def read_expression(expression: str) -> tuple[Fraction, Fraction, Fraction, str]:
    match = EXPRESSION.fullmatch(expression)
    if match is None:
        raise AssertionError(f"Unexpected expression: {expression}")
    a, b, operation, c, d = match.groups()
    first, second = Fraction(int(a), int(b)), Fraction(int(c), int(d))
    value = first + second if operation == "+" else first * second
    return value, first, second, operation


def read_prompt(prompt: str) -> tuple[str, str]:
    prefix = "Let A = "
    middle = " and B = "
    suffix = ". Which is larger, and by exactly how much?"
    if not prompt.startswith(prefix) or not prompt.endswith(suffix):
        raise AssertionError(f"Unexpected prompt: {prompt}")
    return prompt[len(prefix):-len(suffix)].split(middle, 1)


class MathComparisonConstructorTests(unittest.TestCase):
    def test_closed_schema_and_runtime_reject_extra_or_wrongly_typed_fields(self):
        schema = task_schema()
        self.assertIs(schema["additionalProperties"], False)
        self.assertEqual(schema["properties"]["family"]["enum"], list(FAMILIES))
        self.assertEqual(schema["properties"]["pair"]["enum"], list(PAIRS))
        self.assertEqual(schema["properties"]["order"]["enum"], list(ORDERS))
        valid = task("crossed_sums", "2_3")
        bad = (
            None, [], {}, "2_3", {**valid, "answer": "A"},
            {**valid, "kind": "other"}, {**valid, "kind": True},
            {**valid, "family": "other"}, {**valid, "family": 1},
            {**valid, "pair": "2_2"}, {**valid, "pair": "5_2"},
            {**valid, "pair": "6_2"}, {**valid, "pair": "2_6"},
            {**valid, "pair": 2},
            {**valid, "order": "other"}, {**valid, "order": False},
            {key: value for key, value in valid.items() if key != "order"},
        )
        for raw in bad:
            with self.subTest(raw=raw), self.assertRaises(MathComparisonTaskError):
                compile_question(raw)
        for ordinal in (-1, 1.5, True, "1"):
            with self.subTest(ordinal=ordinal), self.assertRaises(MathComparisonTaskError):
                compile_question(valid, ordinal=ordinal)

    def test_all_bounded_variants_have_independently_recomputed_unique_key(self):
        self.assertEqual(len(PAIRS), 8)
        prompts = set()
        for family in FAMILIES:
            for pair in PAIRS:
                for order in ORDERS:
                    for ordinal in range(4):
                        with self.subTest(family=family, pair=pair,
                                          order=order, ordinal=ordinal):
                            result = compile_question(task(family, pair, order), ordinal=ordinal)
                            self.assertEqual(set(result), set(LEARNER_FIELDS))
                            a_expression, b_expression = read_prompt(result["prompt"])
                            a_value, a_first, a_second, operation = read_expression(a_expression)
                            b_value, b_first, _, b_operation = read_expression(b_expression)
                            self.assertEqual(operation, b_operation)
                            self.assertEqual(operation, "+" if family == "crossed_sums" else "×")
                            self.assertNotEqual(a_value, b_value)
                            difference = abs(a_value - b_value)
                            winner, loser = (("A", "B") if a_value > b_value else ("B", "A"))
                            key = f"{winner} is larger than {loser} by {difference}."
                            self.assertEqual(result["expectedAnswer"], key)
                            self.assertEqual(result["choices"].count(key), 1)
                            self.assertEqual(result["choices"].index(key), (-ordinal) % 4)
                            self.assertEqual(len(result["choices"]), 4)
                            self.assertEqual(len(set(result["choices"])), 4)
                            partial = abs(a_first - b_first)
                            if family == "crossed_products":
                                partial *= a_second
                            self.assertNotEqual(partial, difference)
                            parsed = [CHOICE.fullmatch(choice) for choice in result["choices"]]
                            self.assertTrue(all(parsed))
                            claims = {(match[1], match[2], Fraction(match[3]))
                                      for match in parsed}
                            self.assertEqual(claims, {
                                (winner, loser, difference), (loser, winner, difference),
                                (winner, loser, partial), (loser, winner, partial),
                            })
                            self.assertEqual(list(result["choiceExplanations"]), result["choices"])
                            self.assertEqual(sum(note.startswith("Correct.") for note in
                                                 result["choiceExplanations"].values()), 1)
                            self.assertEqual(sum(note.startswith("Incorrect:") for note in
                                                 result["choiceExplanations"].values()), 3)
                            self.assertLessEqual(len(result["prompt"]), 320)
                            self.assertLessEqual(len(result["explanation"]), 420)
                            self.assertTrue(all(len(choice) <= 140 for choice in result["choices"]))
                            self.assertTrue(all(len(note) <= 280 for note in
                                                result["choiceExplanations"].values()))
                            self.assertNotRegex(result["explanation"], r"\b[A-D][.)] ")
                            if ordinal == 0:
                                self.assertNotIn(result["prompt"], prompts)
                                prompts.add(result["prompt"])
        self.assertEqual(len(prompts), len(FAMILIES) * len(PAIRS) * len(ORDERS))

    def test_hand_computed_sum_and_product_examples(self):
        sum_question = compile_question(task("crossed_sums", "2_4"))
        self.assertEqual(sum_question["expectedAnswer"], "A is larger than B by 1/30.")
        self.assertEqual(sum_question["choices"][2], "A is larger than B by 1/6.")
        product_question = compile_question(task("crossed_products", "5_3"))
        self.assertEqual(product_question["expectedAnswer"], "B is larger than A by 1/28.")
        self.assertEqual(product_question["choices"][2], "B is larger than A by 1/14.")

    def test_rotation_changes_only_choice_order_not_answer_or_feedback(self):
        for family in FAMILIES:
            for pair in PAIRS:
                for order in ORDERS:
                    with self.subTest(family=family, pair=pair, order=order):
                        first = compile_question(task(family, pair, order))
                        for ordinal in range(1, 4):
                            rotated = compile_question(task(family, pair, order), ordinal=ordinal)
                            self.assertEqual(rotated["prompt"], first["prompt"])
                            self.assertEqual(rotated["expectedAnswer"], first["expectedAnswer"])
                            self.assertEqual(rotated["explanation"], first["explanation"])
                            self.assertEqual(rotated["choiceExplanations"],
                                             first["choiceExplanations"])

    def test_curated_pairs_have_distinct_exact_margins_across_both_families(self):
        all_margins = set()
        for family in FAMILIES:
            margins = set()
            for pair in PAIRS:
                question = compile_question(task(family, pair))
                a_expression, b_expression = read_prompt(question["prompt"])
                a_value = read_expression(a_expression)[0]
                b_value = read_expression(b_expression)[0]
                margin = abs(a_value - b_value)
                self.assertNotIn(margin, margins, (family, pair))
                self.assertNotIn(margin, all_margins, (family, pair))
                margins.add(margin)
                all_margins.add(margin)
            self.assertEqual(len(margins), len(PAIRS))
        self.assertEqual(len(all_margins), len(FAMILIES) * len(PAIRS))


if __name__ == "__main__":
    unittest.main()
