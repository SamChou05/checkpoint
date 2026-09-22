"""Exact independent oracles for fraction-error candidates, not novice efficacy."""

import copy
from fractions import Fraction
import hashlib
import itertools
import json
import unittest

from quantitative_choice_construction import (
    QuantitativeConstructionError,
    _local_mistakes,
    _mistakes,
    construct_quantitative_spec,
)
from quantitative_task_compiler import _expression
import test_quantitative_choice_construction as construction_oracle
from test_quantitative_choice_construction import (
    evaluate,
    exact,
    literal,
    operation,
)


class FractionDistractorTests(unittest.TestCase):
    def check_exact(self, tree):
        # The older suite's independent AST/procedure oracle checks that every
        # offered wrong value is a permitted one-step error, not arbitrary filler.
        return construction_oracle.QuantitativeChoiceConstructionTests().assert_exact(exact(tree))

    def test_fraction_procedures_precede_unrelated_root_swaps(self):
        cases = (
            ("add", "2/3", "4/7", {"3/5", "2/7", "2/3"}),
            ("sub", "7/10", "1/6", {"3/2", "1/5", "7/10"}),
            ("div", "7/3", "14/9", {"98/27", "2/3", "27/98"}),
            ("mul", "4/7", "21", {"3", "84", "4/147"}),
            ("mul", "21", "4/7", {"3", "84", "4/147"}),
            ("mul", "2/3", "4/7", {"8/3", "8/7", "7/6"}),
        )
        for op, left, right, expected_wrong in cases:
            with self.subTest(op=op, left=left, right=right):
                tree = operation(op, literal(left), literal(right))
                full = self.check_exact(tree)
                self.assertEqual(set(full["choices"]) - {str(evaluate(tree))}, expected_wrong)

    def test_aliases_cancellation_and_signed_identity_factors(self):
        for op in ("add", "sub", "mul", "div"):
            a = self.check_exact(operation(op, literal("2/6"), literal("2/4")))
            b = self.check_exact(operation(op, literal("1/3"), literal("0.5")))
            self.assertEqual(set(a["choices"]), set(b["choices"]))
        for value in ("3/5", "-3/5"):
            self.check_exact(operation("sub", literal(value), literal(value)))
            self.check_exact(operation("div", literal(value), literal(value)))
        for factor, expected in (("1", {"1/2", "3/2", "-1/2", "1"}),
                                 ("-1", {"-1/2", "3/2", "1/2", "-1"})):
            full = self.check_exact(operation("mul", literal("1/2"), literal(factor)))
            self.assertEqual(set(full["choices"]), expected)
        for op in ("mul", "div"):
            with self.assertRaises(QuantitativeConstructionError) as caught:
                construct_quantitative_spec(exact(operation(op, literal(0), literal("3/5"))))
            self.assertEqual(caught.exception.code, "insufficient_distractors")

    def test_signed_rational_grid_keeps_exact_key_bounds_and_independent_order(self):
        values = sorted({Fraction(n, d) for n in (-7, -1, 0, 1, 7) for d in (1, 2, 3, 7)})
        admitted = defined = 0
        key_positions = set()
        for op, left, right in itertools.product(("add", "sub", "mul", "div"), values, values):
            if op == "div" and right == 0:
                continue
            defined += 1
            tree = operation(op, literal(left), literal(right))
            with self.subTest(op=op, left=left, right=right):
                try:
                    full = self.check_exact(tree)
                except QuantitativeConstructionError as error:
                    self.assertEqual(error.code, "insufficient_distractors")
                    continue
                admitted += 1
                spec = exact(tree)
                seed = json.dumps(spec, sort_keys=True, ensure_ascii=True, allow_nan=False,
                                  separators=(",", ":")).encode()
                expected_order = sorted(full["choices"], key=lambda value: (
                    hashlib.sha256(seed + b"\0" + value.encode()).digest(), value))
                self.assertEqual(full["choices"], expected_order)
                key_positions.add(full["choices"].index(str(evaluate(tree))))
        self.assertEqual(defined, 885)
        self.assertGreater(admitted, defined * 0.8)
        self.assertEqual(key_positions, {0, 1, 2, 3})

    def test_nested_errors_change_only_one_step(self):
        admitted = defined = 0
        for outer, inner, left, right, side in itertools.product(
                ("add", "sub", "mul", "div"), ("add", "sub", "mul", "div"),
                ("-3/5", "2/3", "4"), ("-1/2", "3/7", "2"), ("left", "right")):
            child = operation(inner, literal(left), literal(right))
            tree = operation(outer, child, literal("5/6")) if side == "left" else (
                operation(outer, literal("5/6"), child))
            try:
                evaluate(tree)
            except ZeroDivisionError:
                continue
            defined += 1
            with self.subTest(outer=outer, inner=inner, left=left, right=right, side=side):
                try:
                    self.check_exact(tree)
                    admitted += 1
                except QuantitativeConstructionError as error:
                    self.assertEqual(error.code, "insufficient_distractors")
        self.assertEqual(defined, 288)
        self.assertGreater(admitted, 280)

    def test_six_local_mechanisms_and_ninety_total_candidates_remain_hard_bounds(self):
        for op, left, right in itertools.product(
                ("add", "sub", "mul", "div"),
                (Fraction(-7, 3), Fraction(0), Fraction(1), Fraction(2, 5)),
                (Fraction(-5, 2), Fraction(0), Fraction(1), Fraction(7))):
            self.assertLessEqual(len(_local_mistakes(op, left, right)), 6)
        tree = literal("2/7")
        for index in range(4):
            tree = operation("add" if index % 2 == 0 else "mul", tree, copy.deepcopy(tree))
        ir, _ = _expression(tree, [0], allow_variable=False)
        candidates = _mistakes(ir)
        self.assertLessEqual(len(candidates), 90)
        self.assertEqual(len(set(candidates)), len(candidates))
        for value in candidates:
            self.assertIs(type(value), Fraction)
            self.assertLessEqual(value.numerator.bit_length(), 96)
            self.assertLessEqual(value.denominator.bit_length(), 96)

    def test_hypothetical_zero_denominators_and_overflow_do_not_escape(self):
        # Equal denominators make the componentwise subtraction error undefined;
        # the real subtraction remains valid. The invalid hypothesis is omitted.
        self.check_exact(operation("sub", literal("5/7"), literal("2/7")))
        # Such intermediate values can arise in bounded nested expressions;
        # the correct ratio is one while the hypothetical product exceeds96bits.
        value = Fraction(2**94 + 1, 2**94 - 1)
        self.assertIsNone(_local_mistakes("div", value, value)[0])
        for candidate in _local_mistakes("div", value, value):
            if candidate is not None:
                self.assertLessEqual(candidate.numerator.bit_length(), 96)
                self.assertLessEqual(candidate.denominator.bit_length(), 96)


if __name__ == "__main__":
    unittest.main()
