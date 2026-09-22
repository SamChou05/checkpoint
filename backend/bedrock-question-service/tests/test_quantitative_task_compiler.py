import copy
from fractions import Fraction
import itertools
import unittest

from quantitative_task_compiler import (
    MAX_DOMAIN_SIZE,
    QuantitativeTaskError,
    compile_question,
)


def constant(value):
    return {"value": str(value)}


def operation(op, left, right):
    return {"op": op, "left": left, "right": right}


def exact(expression=None, choices=None, unit="unitless"):
    return {"kind": "exact_value", "unit": unit,
            "expression": expression or operation("add", constant(2), constant(2)),
            "choices": choices or ["4", "2", "3", "5"]}


def condition(selection="any_satisfying", *, relation="gt", choices=None, domain=None):
    return {"kind": "scalar_condition", "unit": "rides", "selection": selection,
            "condition": {"left": operation("mul", constant("2.50"), {"variable": "x"}),
                          "relation": relation, "right": constant(60)},
            "domain": domain or {"kind": "integer_interval", "lower": 0, "upper": 40},
            "choices": choices or ["23", "24", "25", "26"]}


def square_condition(*, relation="eq", choices=None, lower=-10, upper=10):
    spec = condition(relation=relation, choices=choices or ["7", "-7", "0", "14"],
                     domain={"kind": "integer_interval", "lower": lower, "upper": upper})
    spec["unit"] = "unitless"
    spec["condition"]["left"] = operation("mul", {"variable": "x"}, {"variable": "x"})
    spec["condition"]["right"] = constant(49)
    return spec


class QuantitativeTaskCompilerTests(unittest.TestCase):
    def assert_rejected(self, spec, code=None):
        with self.assertRaises(QuantitativeTaskError) as caught:
            compile_question(spec)
        if code:
            self.assertEqual(caught.exception.code, code)

    def assert_payload(self, result):
        self.assertEqual(set(result), {"prompt", "choices", "expectedAnswer", "explanation",
                                       "choiceExplanations"})
        self.assertEqual(len(set(result["choices"])), 4)
        self.assertIn(result["expectedAnswer"], result["choices"])
        self.assertEqual(set(result["choiceExplanations"]), set(result["choices"]))
        for text, lower, upper in [
            (result["prompt"], 12, 320), (result["explanation"], 12, 420),
            *((v, 1, 140) for v in result["choices"]),
            *((v, 12, 280) for v in result["choiceExplanations"].values()),
        ]:
            self.assertTrue(lower <= len(text) <= upper, text)

    def test_exact_decimal_arithmetic_has_no_float_rounding(self):
        result = compile_question(exact(operation("add", constant("0.1"), constant("0.2")),
                                        ["0.3", "0.2", "0.4", "0.5"], "m"))
        self.assert_payload(result)
        self.assertEqual(result["expectedAnswer"], "3/10 m")
        self.assertIn("((1/10) + (1/5))", result["prompt"])
        self.assertIn("3/10", result["explanation"])
        self.assertIn("not 1/5", result["choiceExplanations"]["1/5 m"])

    def test_rendered_fraction_operands_preserve_expression_grouping(self):
        result = compile_question(exact(operation("div", constant("1/2"), constant("3/4")),
                                        ["2/3", "1/24", "3/8", "3/2"]))
        self.assertIn("((1/2) / (3/4))", result["prompt"])
        self.assertEqual(result["expectedAnswer"], "2/3")

    def test_subtraction_negative_values_and_noncommutative_division(self):
        expression = operation("div", operation("sub", constant(-1), constant(2)), constant(2))
        result = compile_question(exact(expression, ["-1.5", "1.5", "-0.5", "0.5"], "s"))
        self.assertEqual(result["expectedAnswer"], "-3/2 s")

    def test_any_satisfying_rejects_both_qualifying_bus_values(self):
        self.assert_rejected(condition(), "multiple_answers")

    def test_explicit_minimum_retains_qualifying_nonminimum_as_wrong_for_stated_reason(self):
        result = compile_question(condition("minimum"))
        self.assert_payload(result)
        self.assertEqual(result["expectedAnswer"], "25 rides")
        self.assertIn("minimum x in this domain", result["prompt"])
        self.assertIn("0 through 40, inclusive", result["prompt"])
        self.assertIn("65 > 60 is true", result["choiceExplanations"]["26 rides"])
        self.assertIn("question asks for the minimum", result["choiceExplanations"]["26 rides"])
        self.assertIn("At x = 25, 125/2 > 60 is true", result["explanation"])
        self.assertIn("Every smaller value in the stated domain fails", result["explanation"])

    def test_inclusive_boundary_moves_minimum(self):
        strict = compile_question(condition("minimum"))
        inclusive = compile_question(condition("minimum", relation="ge"))
        self.assertEqual(strict["expectedAnswer"], "25 rides")
        self.assertEqual(inclusive["expectedAnswer"], "24 rides")
        self.assertIn("60 >= 60 is true", inclusive["choiceExplanations"]["24 rides"])

    def test_less_than_boundary_and_maximum(self):
        strict = compile_question(condition("maximum", relation="lt"))
        inclusive = compile_question(condition("maximum", relation="le"))
        self.assertEqual(strict["expectedAnswer"], "23 rides")
        self.assertEqual(inclusive["expectedAnswer"], "24 rides")
        self.assertIn("maximum", inclusive["prompt"])

    def test_equality_rejects_both_offered_signed_roots(self):
        self.assert_rejected(square_condition(), "multiple_answers")

    def test_explicit_nonnegative_domain_keeps_only_positive_root(self):
        result = compile_question(square_condition(lower=0))
        self.assert_payload(result)
        self.assertEqual(result["expectedAnswer"], "7")
        self.assertIn("integers from 0 through 10, inclusive", result["prompt"])
        self.assertIn("(x * x) = 49", result["prompt"])
        self.assertIn("At x = 7, 49 = 49 is true", result["explanation"])
        self.assertIn("outside the stated domain", result["choiceExplanations"]["-7"])
        self.assertNotIn("is false", result["choiceExplanations"]["-7"])

    def test_equality_can_have_an_unoffered_second_root_without_ambiguous_choices(self):
        result = compile_question(square_condition(choices=["7", "0", "1", "2"]))
        self.assertEqual(result["expectedAnswer"], "7")
        self.assertIn("only offered value satisfying", result["explanation"])
        self.assertIn("Every other offered value", result["explanation"])
        self.assertIn("0 = 49 is false", result["choiceExplanations"]["0"])

    def test_equality_with_no_domain_solution_is_rejected(self):
        spec = square_condition()
        spec["condition"]["right"] = constant(-1)
        self.assert_rejected(spec, "no_answer")

    def test_rational_equality_uses_exact_addition_and_literal_equal_sign(self):
        spec = condition(relation="eq", choices=["0.2", "0.3", "0.4", "-0.2"],
                         domain={"kind": "offered"})
        spec["unit"] = "unitless"
        spec["condition"] = {"left": operation("add", {"variable": "x"}, constant("0.1")),
                             "relation": "eq", "right": constant("0.3")}
        result = compile_question(spec)
        self.assertEqual(result["expectedAnswer"], "1/5")
        self.assertIn("(x + (1/10)) = (3/10)", result["prompt"])
        self.assertIn("3/10 = 3/10 is true", result["explanation"])
        self.assertIn("2/5 = 3/10 is false", result["choiceExplanations"]["3/10"])

    def test_not_equal_rejects_multiple_satisfying_values_and_respects_domain(self):
        self.assert_rejected(square_condition(relation="ne", lower=-20, upper=20), "multiple_answers")
        # With 14 outside the explicit domain, 0 is the sole qualifying option.
        result = compile_question(square_condition(relation="ne"))
        self.assertEqual(result["expectedAnswer"], "0")
        self.assertIn("(x * x) != 49", result["prompt"])
        self.assertIn("0 != 49 is true", result["explanation"])
        for root in ("7", "-7"):
            self.assertIn("49 != 49 is false", result["choiceExplanations"][root])
        self.assertIn("outside the stated domain", result["choiceExplanations"]["14"])

    def test_global_domain_minimum_cannot_be_replaced_by_smallest_offered(self):
        spec = condition("minimum", choices=["23", "24", "26", "27"])
        self.assert_rejected(spec, "no_answer")
        spec["domain"] = {"kind": "offered"}
        result = compile_question(spec)
        self.assertEqual(result["expectedAnswer"], "26 rides")
        self.assertIn("domain is the offered values", result["prompt"])

    def test_global_maximum_absent_from_choices_is_rejected(self):
        spec = condition("maximum", choices=["23", "24", "25", "26"])
        self.assert_rejected(spec, "no_answer")
        spec["domain"] = {"kind": "offered"}
        self.assertEqual(compile_question(spec)["expectedAnswer"], "26 rides")

    def test_any_asks_about_offered_values_not_uniqueness_in_whole_domain(self):
        result = compile_question(condition(choices=["21", "22", "24", "26"]))
        self.assertEqual(result["expectedAnswer"], "26 rides")
        self.assertIn("Which offered value", result["prompt"])
        self.assertIn("only offered value", result["explanation"])

    def test_outside_integer_domain_is_refuted_without_claiming_condition_false(self):
        spec = condition("minimum", choices=["24.5", "25", "26", "41"])
        result = compile_question(spec)
        for choice in ("49/2 rides", "41 rides"):
            self.assertIn("outside the stated domain", result["choiceExplanations"][choice])
            self.assertNotIn("is false", result["choiceExplanations"][choice])

    def test_fractional_offered_domain_and_negative_interval(self):
        spec = condition("minimum", choices=["24", "24.5", "25", "25.5"],
                         domain={"kind": "offered"})
        self.assertEqual(compile_question(spec)["expectedAnswer"], "49/2 rides")
        spec = condition("maximum", domain={"kind": "integer_interval", "lower": -4, "upper": -1},
                         choices=["-4", "-3", "-2", "-1"])
        spec["condition"] = {"left": {"variable": "x"}, "relation": "lt", "right": constant(-1)}
        self.assertEqual(compile_question(spec)["expectedAnswer"], "-2 rides")

    def test_nonmonotonic_extrema_explain_exhaustive_domain_evidence(self):
        # (x-1)*(x-3) <= 0 holds at 1,2,3, then stops holding again at 4.
        expression = operation("mul", operation("sub", {"variable": "x"}, constant(1)),
                               operation("sub", {"variable": "x"}, constant(3)))
        spec = condition("minimum", choices=["0", "1", "3", "4"],
                         domain={"kind": "integer_interval", "lower": 0, "upper": 4})
        spec["condition"] = {"left": expression, "relation": "le", "right": constant(0)}
        minimum = compile_question(spec)
        self.assertEqual(minimum["expectedAnswer"], "1 rides")
        self.assertIn("At x = 1, 0 <= 0 is true", minimum["explanation"])
        self.assertIn("Every smaller value in the stated domain fails", minimum["explanation"])
        self.assertIn("3 <= 0 is false", minimum["choiceExplanations"]["4 rides"])
        spec["selection"] = "maximum"
        maximum = compile_question(spec)
        self.assertEqual(maximum["expectedAnswer"], "3 rides")
        self.assertIn("At x = 3, 0 <= 0 is true", maximum["explanation"])
        self.assertIn("Every larger value in the stated domain fails", maximum["explanation"])
        spec["domain"] = {"kind": "offered"}
        self.assertIn("Every larger value in the stated domain fails", compile_question(spec)["explanation"])

    def test_extremum_at_domain_edge_does_not_invent_failed_competitors(self):
        spec = condition("minimum", choices=["25", "26", "27", "28"], domain={"kind": "offered"})
        result = compile_question(spec)
        self.assertIn("No smaller value exists in the stated domain", result["explanation"])
        spec["selection"] = "maximum"
        self.assertIn("No larger value exists in the stated domain", compile_question(spec)["explanation"])

    def test_none_satisfy_and_exact_key_absent_are_rejected(self):
        self.assert_rejected(condition(choices=["20", "21", "22", "23"]), "no_answer")
        self.assert_rejected(exact(choices=["1", "2", "3", "5"]), "no_answer")
        self.assert_rejected(condition("minimum", domain={"kind": "integer_interval", "lower": 0, "upper": 2}),
                             "no_answer")

    def test_equivalent_wrong_choices_and_tied_minimum_are_rejected(self):
        for alias in ("02", "2.0", "4/2"):
            self.assert_rejected(exact(choices=["4", "2", alias, "5"]), "equivalent_choices")
        self.assert_rejected(condition("minimum", choices=["25", "50/2", "24", "26"]),
                             "equivalent_choices")
        self.assert_rejected(exact(choices=["4", "-0", "0.0", "5"]), "equivalent_choices")

    def test_no_key_feedback_or_free_prose_is_accepted_as_input(self):
        for key in ("expectedAnswer", "correctChoice", "prompt", "explanation", "scenario", "code"):
            spec = exact()
            spec[key] = "arbitrary replacement"
            self.assert_rejected(spec, "invalid_fields")

    def test_input_immutability_determinism_and_every_choice_permutation(self):
        spec = condition("minimum")
        before = copy.deepcopy(spec)
        original = compile_question(spec)
        self.assertEqual(spec, before)
        self.assertEqual(original, compile_question(spec))
        for choices in itertools.permutations(spec["choices"]):
            moved = {**spec, "choices": list(choices)}
            actual = compile_question(moved)
            self.assertEqual(actual["expectedAnswer"], original["expectedAnswer"])
            self.assertEqual(actual["prompt"], original["prompt"])
            self.assertEqual(actual["explanation"], original["explanation"])
            self.assertEqual(actual["choiceExplanations"], original["choiceExplanations"])
        original["choices"][0] = "mutated"
        self.assertEqual(spec, before)

    def test_exhaustive_small_linear_conditions_against_independent_integer_oracle(self):
        comparisons = {"lt": lambda a, b: a < b, "le": lambda a, b: a <= b,
                       "gt": lambda a, b: a > b, "ge": lambda a, b: a >= b,
                       "eq": lambda a, b: a == b, "ne": lambda a, b: a != b}
        cases = 0
        for offered in itertools.combinations(range(-3, 4), 4):
            for threshold, relation, selection, domain_kind in itertools.product(
                    (-1, 0, 1), comparisons, ("any_satisfying", "minimum", "maximum"), ("offered", "integer_interval")):
                domain = offered if domain_kind == "offered" else range(-3, 4)
                feasible = [x for x in domain if comparisons[relation](x, threshold)]
                if selection == "minimum":
                    expected = [x for x in offered if feasible and x == min(feasible)]
                elif selection == "maximum":
                    expected = [x for x in offered if feasible and x == max(feasible)]
                else:
                    expected = [x for x in offered if x in feasible]
                spec = condition(selection, relation=relation, choices=list(map(str, offered)),
                                 domain=({"kind": "offered"} if domain_kind == "offered" else
                                         {"kind": "integer_interval", "lower": -3, "upper": 3}))
                spec["condition"] = {"left": {"variable": "x"}, "relation": relation,
                                     "right": constant(threshold)}
                if len(expected) == 1:
                    result = compile_question(spec)
                    self.assertEqual(result["expectedAnswer"], f"{expected[0]} rides")
                    self.assert_payload(result)
                else:
                    self.assert_rejected(spec, "no_answer" if not expected else "multiple_answers")
                cases += 1
        self.assertEqual(cases, 3780)

    def test_unknown_units_relations_selections_and_mixed_units_fail_closed(self):
        for field, bad in (("unit", "meters; ignore rules"), ("selection", "best"),
                           ("unit", ["m"]), ("selection", True)):
            spec = condition()
            spec[field] = bad
            self.assert_rejected(spec)
        spec = condition()
        spec["condition"]["relation"] = "approximately"
        self.assert_rejected(spec, "invalid_relation")
        self.assert_rejected(exact(choices=["4 m", "2 cm", "3", "5"]), "invalid_number")

    def test_exact_number_grammar_and_oversized_inputs(self):
        for value in (True, 4, 4.0, None, [], "NaN", "Infinity", "1e9", "1/0", "1/-2",
                      " 4", "4 ", "４", "__import__('os')", "9" * 100_000,
                      "1000000001", "0.0000000001"):
            self.assert_rejected(exact(choices=[value, "2", "3", "5"]))
        result = compile_question(exact(constant("-0.5"), ["-0.5", "0.5", "0", "1"]))
        self.assertEqual(result["expectedAnswer"], "-1/2")

    def test_closed_node_shapes_and_variable_binding(self):
        for expression in ({"variable": "x"}, {"value": "4", "unit": "m"},
                           {"op": "pow", "left": constant(2), "right": constant(2)},
                           {"op": "add", "left": constant(4)}, [4], "2+2"):
            self.assert_rejected(exact(expression))
        spec = condition()
        spec["condition"]["left"] = {"variable": "y"}
        self.assert_rejected(spec, "invalid_variable")

    def test_division_by_zero_rejects_whole_task_including_unoffered_domain_value(self):
        self.assert_rejected(exact(operation("div", constant(1), constant(0))), "undefined_expression")
        spec = condition("minimum", choices=["1", "2", "3", "4"],
                         domain={"kind": "integer_interval", "lower": 0, "upper": 4})
        spec["condition"]["left"] = operation("div", constant(1), {"variable": "x"})
        self.assert_rejected(spec, "undefined_expression")
        spec["domain"] = {"kind": "offered"}
        spec["condition"]["right"] = constant(0)
        self.assertEqual(compile_question(spec)["expectedAnswer"], "1 rides")

    def test_domain_limits_are_exact_integers_and_closed(self):
        for domain in (None, [], {"kind": "all_integers"},
                       {"kind": "offered", "lower": 0},
                       {"kind": "integer_interval", "lower": True, "upper": 2},
                       {"kind": "integer_interval", "lower": 0, "upper": 2.0},
                       {"kind": "integer_interval", "lower": 2, "upper": 1},
                       {"kind": "integer_interval", "lower": 0, "upper": MAX_DOMAIN_SIZE},
                       {"kind": "integer_interval", "lower": 10**100, "upper": 10**100 + 1}):
            spec = condition()
            spec["domain"] = domain
            self.assert_rejected(spec)

    def test_expression_depth_cycles_node_count_and_intermediate_size_are_bounded(self):
        expression = constant(4)
        for _ in range(6):
            expression = operation("add", expression, constant(0))
        self.assert_rejected(exact(expression), "expression_limit")
        cycle = operation("add", constant(4), constant(0))
        cycle["left"] = cycle
        self.assert_rejected(exact(cycle), "expression_limit")
        expression = constant(0)
        for _ in range(5):
            expression = operation("add", expression, expression)
        self.assert_rejected(exact(expression), "expression_limit")
        square = operation("mul", constant(1_000_000_000), constant(1_000_000_000))
        self.assert_rejected(exact(operation("mul", square, square)), "arithmetic_limit")

    def test_learner_bounds_reject_without_clipping_a_valid_large_expression(self):
        expression = constant("123456789/987654321")
        for _ in range(4):
            expression = operation("sub", expression, expression)
        self.assert_rejected(exact(expression, ["0", "1", "2", "3"]), "learner_text_limit")

    def test_huge_collections_and_non_json_types_are_rejected(self):
        self.assert_rejected({**exact(), **{f"extra{i}": i for i in range(10_000)}}, "invalid_fields")
        self.assert_rejected(exact({f"extra{i}": i for i in range(10_000)}), "invalid_expression")
        spec = exact()
        spec["choices"] = ["4"] * 10_000
        self.assert_rejected(spec, "invalid_choices")
        spec["choices"] = ("4", "2", "3", "5")
        self.assert_rejected(spec, "invalid_choices")
        class StringSubclass(str):
            pass
        spec = condition()
        spec["domain"] = {"kind": StringSubclass("offered")}
        self.assert_rejected(spec, "invalid_domain")
        spec["domain"] = {StringSubclass("kind"): "offered"}
        self.assert_rejected(spec, "invalid_fields")
        self.assert_rejected(exact({StringSubclass("value"): "4"}), "invalid_fields")

    def test_exact_fraction_choice_value_agrees_with_key_for_all_arithmetic_operators(self):
        for op, expected in (("add", Fraction(17, 6)), ("sub", Fraction(-7, 6)),
                             ("mul", Fraction(5, 3)), ("div", Fraction(5, 12))):
            result = compile_question(exact(operation(op, constant("5/6"), constant(2)),
                                            [str(expected), "0", "4", "-4"]))
            self.assertEqual(result["expectedAnswer"], str(expected))


if __name__ == "__main__":
    unittest.main()
