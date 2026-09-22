"""Independent arithmetic/selection oracles for the opt-in pure constructor."""

import copy
from fractions import Fraction
import itertools
from math import lcm
import unittest

from quantitative_choice_construction import (
    QuantitativeConstructionError, construct_quantitative_spec,
)
from quantitative_task_compiler import compile_question


def literal(value):
    return {"value": str(value)}


def operation(op, left, right):
    return {"op": op, "left": left, "right": right}


def exact(expression, unit="unitless"):
    return {"kind": "exact_value", "unit": unit, "expression": expression}


def scalar(left, relation, right, selection="any_satisfying", lower=-5, upper=5):
    return {"kind": "scalar_condition", "unit": "unitless",
            "condition": {"left": left, "relation": relation, "right": right},
            "selection": selection,
            "domain": {"kind": "integer_interval", "lower": lower, "upper": upper}}


def evaluate(tree, x=None):
    if "value" in tree:
        return Fraction(tree["value"])
    if "variable" in tree:
        return Fraction(x)
    left, right = evaluate(tree["left"], x), evaluate(tree["right"], x)
    if tree["op"] == "add":
        return left + right
    if tree["op"] == "sub":
        return left - right
    if tree["op"] == "mul":
        return left * right
    return left / right


def holds(spec, x):
    condition = spec["condition"]
    left, right = evaluate(condition["left"], x), evaluate(condition["right"], x)
    return {"lt": left < right, "le": left <= right, "gt": left > right,
            "ge": left >= right, "eq": left == right, "ne": left != right}[condition["relation"]]


def mutated_trees(tree):
    """Independent syntax oracle: enumerate exactly one permitted AST change."""
    if "op" not in tree:
        return
    for replacement in ("add", "sub", "mul", "div"):
        if replacement != tree["op"]:
            yield {**copy.deepcopy(tree), "op": replacement}
    yield copy.deepcopy(tree["left"])
    yield copy.deepcopy(tree["right"])
    if tree["op"] in {"sub", "div"}:
        yield operation(tree["op"], copy.deepcopy(tree["right"]), copy.deepcopy(tree["left"]))
    for side in ("left", "right"):
        for child in mutated_trees(tree[side]):
            candidate = copy.deepcopy(tree)
            candidate[side] = child
            yield candidate


def fraction_procedure_trees(tree):
    """Independent error oracle: replace one step, keep every ancestor intact.

This includes the fraction-error families without sharing the constructor's
priority, branch selection or helpers. The ordinary AST mutation oracle above
also remains available; membership alone does not assert pedagogical quality.
"""
    if "op" not in tree:
        return
    left, right = evaluate(tree["left"]), evaluate(tree["right"])
    if left.denominator != 1 or right.denominator != 1:
        a, b, c, d = left.numerator, left.denominator, right.numerator, right.denominator
        procedures = []
        if tree["op"] in {"add", "sub"}:
            sign = 1 if tree["op"] == "add" else -1
            procedures += [lambda: Fraction(a + sign * c, b + sign * d),
                           lambda: Fraction(a + sign * c, lcm(b, d))]
        elif tree["op"] == "div":
            procedures += [lambda: 1 / (left * right)]
        else:
            procedures += [lambda: Fraction(a * c, b), lambda: Fraction(a * c, d)]
            for fraction, whole in ((left, right), (right, left)):
                if whole.denominator == 1:
                    procedures += [lambda f=fraction, w=whole: w / f.denominator,
                                   lambda f=fraction, w=whole: f.numerator * w,
                                   lambda f=fraction, w=whole: f.numerator / (f.denominator * w)]
        for procedure in procedures:
            try:
                yield literal(procedure())
            except ZeroDivisionError:
                pass
    for side in ("left", "right"):
        for child in fraction_procedure_trees(tree[side]):
            candidate = copy.deepcopy(tree)
            candidate[side] = child
            yield candidate


class QuantitativeChoiceConstructionTests(unittest.TestCase):
    def assert_error(self, spec, code):
        with self.assertRaises(QuantitativeConstructionError) as caught:
            construct_quantitative_spec(spec)
        self.assertEqual(caught.exception.code, code)

    def assert_exact(self, spec):
        before = copy.deepcopy(spec)
        full = construct_quantitative_spec(spec)
        self.assertEqual(spec, before)
        self.assertEqual({k: v for k, v in full.items() if k != "choices"}, before)
        numbers = list(map(Fraction, full["choices"]))
        self.assertEqual(len(numbers), 4)
        self.assertEqual(len(set(numbers)), 4)
        answer = evaluate(spec["expression"])
        self.assertEqual(numbers.count(answer), 1)
        permitted = set()
        for mutated in itertools.chain(mutated_trees(spec["expression"]),
                                       fraction_procedure_trees(spec["expression"])):
            try:
                permitted.add(evaluate(mutated))
            except ZeroDivisionError:
                pass
        self.assertTrue(set(numbers) - {answer} <= permitted)
        content = compile_question(full)
        suffix = "" if spec["unit"] == "unitless" else " " + spec["unit"]
        self.assertEqual(content["expectedAnswer"], str(answer) + suffix)
        self.assertEqual(set(content["choiceExplanations"]), set(content["choices"]))
        self.assertLessEqual(len(content["explanation"]), 420)
        return full

    def test_all_operations_and_signed_fraction_nested_mistakes(self):
        count = 0
        for op, left, right in itertools.product(("add", "sub", "mul", "div"),
                                                  ("-7/3", "0", "4/5", "7"),
                                                  ("-5/2", "3/7", "4")):
            tree = operation(op, literal(left), literal(right))
            # Some zero cases still have too few permitted single-step errors.
            possible = set()
            for candidate in itertools.chain(mutated_trees(tree), fraction_procedure_trees(tree)):
                try:
                    possible.add(evaluate(candidate))
                except ZeroDivisionError:
                    pass
            if len(possible - {evaluate(tree)}) < 3:
                self.assert_error(exact(tree), "insufficient_distractors")
            else:
                self.assert_exact(exact(tree))
            count += 1
        self.assertEqual(count, 48)
        nested = operation("div", operation("sub", literal("-7/3"), literal("2/5")),
                           operation("add", literal("-1/2"), literal("3/4")))
        self.assert_exact(exact(nested, "USD"))

    def test_zero_division_mistakes_are_filtered_but_actual_undefined_fails(self):
        tree = operation("add", operation("sub", literal(7), literal(0)), literal(3))
        full = self.assert_exact(exact(tree))
        self.assertNotIn("None", full["choices"])
        self.assert_error(exact(operation("div", literal(7), literal(0))), "undefined_expression")

    def test_pool_exhaustion_has_no_generic_padding(self):
        for tree in (literal(7), operation("add", literal(0), literal(0)),
                     operation("mul", literal(1), literal(1))):
            self.assert_error(exact(tree), "insufficient_distractors")

    def test_seven_observed_missing_answer_task_shapes(self):
        tasks = [
            exact(operation("mul", operation("add", literal("3/4"), literal("2/5")), literal("5/6"))),
            exact(operation("div", operation("sub", literal("1.25"), literal("0.75")), literal("0.4"))),
            exact(operation("mul", operation("sub", literal("2/3"), literal("5/6")), literal("3/4"))),
            exact(operation("div", operation("add", literal("7/8"), literal("2/5")), literal("3/10"))),
            exact(operation("sub", operation("mul", literal("2/3"), literal("5/6")), literal("3/4"))),
        ]
        self.assertEqual([compile_question(self.assert_exact(task))["expectedAnswer"] for task in tasks],
                         ["23/24", "5/4", "-1/8", "17/4", "-7/36"])
        x = {"variable": "x"}
        minimum = scalar(operation("sub", operation("add", operation("mul", x, literal(4)), literal(3)), literal(15)),
                         "le", x, "minimum", 1, 20)
        maximum = scalar(operation("add", operation("sub", operation("mul", x, literal(5)), literal(12)), literal(8)),
                         "ge", x, "maximum", -10, 10)
        self.assertEqual(compile_question(construct_quantitative_spec(minimum))["expectedAnswer"], "1")
        self.assertEqual(compile_question(construct_quantitative_spec(maximum))["expectedAnswer"], "10")

    def test_all_relations_and_selections_against_small_domain_oracle(self):
        checks = admitted = 0
        x = {"variable": "x"}
        for relation, selection, threshold in itertools.product(
                ("lt", "le", "gt", "ge", "eq", "ne"),
                ("any_satisfying", "minimum", "maximum"), (-1, 0, 1, 4, 9, 30)):
            spec = scalar(operation("mul", x, x), relation, literal(threshold), selection)
            domain = list(range(-5, 6))
            feasible = [value for value in domain if holds(spec, value)]
            checks += 1
            if not feasible:
                self.assert_error(spec, "no_answer")
                continue
            if selection == "any_satisfying" and len(domain) - len(feasible) < 3:
                self.assert_error(spec, "insufficient_distractors")
                continue
            full = construct_quantitative_spec(spec)
            offered = list(map(Fraction, full["choices"]))
            self.assertEqual(len(set(offered)), 4)
            self.assertTrue(set(offered) <= set(domain))
            if selection == "any_satisfying":
                supported = [v for v in offered if holds(spec, v)]
            else:
                required = min(feasible) if selection == "minimum" else max(feasible)
                supported = [v for v in offered if v == required]
            self.assertEqual(len(supported), 1)
            self.assertEqual(compile_question(full)["expectedAnswer"], str(supported[0]))
            admitted += 1
        self.assertEqual(checks, 108)
        self.assertGreater(admitted, 50)

    def test_any_satisfying_does_not_invent_a_unique_domain_solution(self):
        spec = scalar({"variable": "x"}, "ge", literal(2), lower=-2, upper=6)
        full = construct_quantitative_spec(spec)
        self.assertEqual(sum(holds(spec, x) for x in range(-2, 7)), 5)
        self.assertEqual(sum(holds(spec, Fraction(x)) for x in full["choices"]), 1)
        self.assertEqual(full["selection"], "any_satisfying")
        self.assertNotIn("minimum", compile_question(full)["prompt"])

    def test_nonmonotonic_extrema_keep_other_satisfying_values_wrong(self):
        x = {"variable": "x"}
        for selection, answer in (("minimum", "-3"), ("maximum", "3")):
            spec = scalar(operation("mul", x, x), "le", literal(9), selection)
            full = construct_quantitative_spec(spec)
            content = compile_question(full)
            self.assertEqual(content["expectedAnswer"], answer)
            self.assertTrue(any(holds(spec, Fraction(v)) and v != answer for v in full["choices"]))
            self.assertTrue(all("maximum" in text or "minimum" in text or "false" in text
                                for text in content["choiceExplanations"].values()))

    def test_scalar_domain_and_pool_limits(self):
        x = {"variable": "x"}
        self.assert_error(scalar(x, "eq", literal(100)), "no_answer")
        self.assert_error(scalar(x, "ge", literal(-10)), "insufficient_distractors")
        self.assert_error(scalar(x, "gt", literal(0), "minimum", 1, 3), "insufficient_distractors")
        for domain in ({"kind": "offered"}, {"kind": "integer_interval", "lower": True, "upper": 5},
                       {"kind": "integer_interval", "lower": 0, "upper": 201},
                       {"kind": "integer_interval", "lower": 0, "upper": 10**1000}):
            spec = scalar(x, "ge", literal(0), "minimum")
            spec["domain"] = domain
            self.assert_error(spec, "unsupported_domain" if domain["kind"] == "offered" else "domain_limit")
        valid = scalar(x, "ge", literal(0), "minimum", -100, 100)
        self.assertEqual(compile_question(construct_quantitative_spec(valid))["expectedAnswer"], "0")

    def test_undefined_unoffered_scalar_values_reject_whole_task(self):
        denominator = operation("sub", {"variable": "x"}, literal(4))
        spec = scalar(operation("div", literal(1), denominator), "gt", literal(0), "minimum", -5, 5)
        self.assert_error(spec, "undefined_expression")

    def test_repeatable_independent_output_and_no_provider_metadata(self):
        spec = exact(operation("add", literal("4/7"), literal("3/5")))
        full = construct_quantitative_spec(spec)
        self.assertEqual(full, construct_quantitative_spec(dict(reversed(list(spec.items())))))
        for _ in range(5):
            self.assertEqual(full, construct_quantitative_spec(copy.deepcopy(spec)))
        full["expression"]["left"]["value"] = "999"
        self.assertEqual(spec["expression"]["left"]["value"], "4/7")
        for field in ("choices", "expectedAnswer", "correctChoice", "explanation", "compiled", "verificationPolicyRevision"):
            poisoned = {**spec, field: "untrusted"}
            self.assert_error(poisoned, "invalid_fields")

    def test_number_expression_and_final_text_bounds(self):
        for value, code in (("9" * 10000, "invalid_number"), ("1000000001", "number_limit"),
                            ("1/0", "number_limit"), (True, "invalid_number"), ("NaN", "invalid_number")):
            self.assert_error(exact(operation("add", {"value": value}, literal(3))), code)
        # Exact arithmetic may fit 96 bits while its answer cannot be a legal
        # 24-character/component-bounded offered number. Do not approximate it.
        self.assert_error(exact(operation("mul", literal(10**9), literal(10**9))), "number_limit")
        huge = operation("mul", operation("mul", literal(10**9), literal(10**9)),
                         operation("mul", literal(10**9), literal(10**9)))
        self.assert_error(exact(huge), "arithmetic_limit")
        deep = literal(2)
        for _ in range(5):
            deep = operation("add", deep, literal(2))
        self.assert_exact(exact(deep))
        self.assert_error(exact(operation("add", deep, literal(2))), "expression_limit")
        full_tree = literal(2)
        for _ in range(4):
            full_tree = operation("add", full_tree, full_tree)
        self.assert_exact(exact(full_tree))
        self.assert_error(exact(operation("add", full_tree, literal(2))), "expression_limit")
        # This valid-size tree produces a worked proof beyond 420 characters.
        tree = literal("2/7")
        for _ in range(4):
            tree = operation("add", tree, tree)
        self.assert_error(exact(tree), "learner_text_limit")

    def test_exact_types_unknown_fields_cycles_and_no_variable(self):
        self.assert_error([], "invalid_task")
        self.assert_error({"kind": "other"}, "invalid_task")
        self.assert_error(exact({"variable": "x"}), "invalid_variable")
        self.assert_error(exact({"value": "1", "extra": "x"}), "invalid_expression")
        bad = scalar({"variable": "x"}, "contains", literal(1))
        self.assert_error(bad, "invalid_relation")
        bad["condition"]["relation"] = "eq"
        bad["selection"] = "most_likely"
        self.assert_error(bad, "invalid_selection")
        self.assert_error(exact(literal(3), "invented"), "invalid_unit")
        cyclic = operation("add", literal(3), literal(2))
        cyclic["left"] = cyclic
        self.assert_error(exact(cyclic), "expression_limit")


if __name__ == "__main__":
    unittest.main()
