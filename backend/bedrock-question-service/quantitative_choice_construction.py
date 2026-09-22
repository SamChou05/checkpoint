"""Derive four numerical options from a closed task, never a proposed key.

This pure constructor owns no routing, approval or learner prose. The existing
compiler validates all mathematical bounds and renders the final five fields.
"""

import copy
from fractions import Fraction
import hashlib
import json
from math import gcd

import quantitative_task_compiler as compiler


class QuantitativeConstructionError(ValueError):
    """A task cannot supply four defensible options within the closed subset."""

    def __init__(self, code):
        self.code = code
        super().__init__(code)


def _calculation(op, left, right):
    if left is None or right is None:
        return None
    try:
        return compiler._calculate(op, left, right)
    except compiler.QuantitativeTaskError:
        # A hypothetical mistake may divide by zero or overflow. It cannot
        # become an offered number. Errors in the actual task are not caught.
        return None


def _local_mistakes(op, left, right):
    """At most six fixed local mechanisms, with fraction procedures first.

The IES fractions practice guide describes independent numerator/denominator
operations and misapplied inversion (Recommendation 3). The priorities here
are pedagogical hypotheses, not measured novice response probabilities:
https://ies.ed.gov/ncee/wwc/docs/practiceguide/fractions_pg_093010.pdf
"""
    fractional = left.denominator != 1 or right.denominator != 1
    if fractional:
        a, b = Fraction(left.numerator), Fraction(left.denominator)
        c, d = Fraction(right.numerator), Fraction(right.denominator)
        if op in {"add", "sub"}:
            numerator = _calculation(op, a, c)
            common = _calculation("mul", b / gcd(left.denominator, right.denominator), d)
            return [
                _calculation("div", numerator, _calculation(op, b, d)),
                _calculation("div", numerator, common),
                left,  # Stop at the left intermediate result.
                _calculation("sub" if op == "add" else "add", left, right),
                right,
                _calculation("mul", left, right),
            ]
        if op == "div":
            return [
                _calculation("mul", left, right),  # Invert neither operand.
                _calculation("div", right, left),  # Invert the dividend only.
                _calculation("div", Fraction(1), _calculation("mul", left, right)),
                left, right, _calculation("add", left, right),
            ]
        if left.denominator != 1 and right.denominator != 1:
            numerator = _calculation("mul", a, c)
            return [
                _calculation("div", numerator, b),  # Retain only one denominator.
                _calculation("div", numerator, d),
                _calculation("div", left, right),
                left, _calculation("add", left, right), _calculation("sub", left, right),
            ]
        fraction, whole = (left, right) if left.denominator != 1 else (right, left)
        # Zero and signed identity factors do not need a special fraction
        # procedure; keep their original operation/omission pool.
        if abs(whole) > 1:
            numerator, denominator = Fraction(fraction.numerator), Fraction(fraction.denominator)
            return [
                _calculation("div", whole, denominator),  # Omit the numerator.
                _calculation("mul", numerator, whole),  # Omit the denominator.
                _calculation("div", numerator, _calculation("mul", denominator, whole)),
                left, right, _calculation("add", left, right),
            ]
    proposed = [_calculation(other, left, right)
                for other in compiler.OPERATORS if other != op]
    proposed.extend((left, right))
    if op in {"sub", "div"}:
        proposed.append(_calculation(op, right, left))
    return proposed


def _mistakes(expression):
    """Values from exactly one mistaken step in this validated subtree.

At most six local candidates per binary node: fraction-procedure mistakes,
operator substitutions, omissions or reversal. Child mistakes propagate through
otherwise unchanged ancestors. No erroneous intermediate becomes a new task.
The compiler's 31-node tree bound permits at most 90 candidate values.
"""
    if expression[0] == "constant":
        return []
    op, left_tree, right_tree = expression
    left, right = compiler._evaluate(left_tree), compiler._evaluate(right_tree)
    proposed = _local_mistakes(op, left, right)
    proposed.extend(_calculation(op, value, right) for value in _mistakes(left_tree))
    proposed.extend(_calculation(op, left, value) for value in _mistakes(right_tree))
    # Preserve the fixed mechanism order; aliases consume no pool positions.
    return list(dict.fromkeys(value for value in proposed if value is not None))


def _number_choices(answer, candidates):
    compiler._number(str(answer))
    choices = [answer]
    for value in candidates:
        if value in choices:
            continue
        try:
            compiler._number(str(value))
        except compiler.QuantitativeTaskError:
            continue
        choices.append(value)
        if len(choices) == 4:
            return [str(value) for value in choices]
    raise QuantitativeConstructionError("insufficient_distractors")


def _construct(spec):
    if type(spec) is not dict or type(spec.get("kind")) is not str:
        raise QuantitativeConstructionError("invalid_task")
    kind = spec["kind"]
    if kind == "exact_value":
        compiler._fields(spec, ("kind", "unit", "expression"))
    elif kind == "scalar_condition":
        compiler._fields(spec, ("kind", "unit", "condition", "selection", "domain"))
    else:
        raise QuantitativeConstructionError("invalid_task")
    if type(spec["unit"]) is not str or spec["unit"] not in compiler.UNITS:
        raise QuantitativeConstructionError("invalid_unit")

    if kind == "exact_value":
        expression, _ = compiler._expression(spec["expression"], [0], allow_variable=False)
        answer = compiler._evaluate(expression)
        choices = _number_choices(answer, _mistakes(expression))
    else:
        condition = spec["condition"]
        compiler._fields(condition, ("left", "relation", "right"))
        relation, selection = condition["relation"], spec["selection"]
        if type(relation) is not str or relation not in compiler.RELATIONS:
            raise QuantitativeConstructionError("invalid_relation")
        if type(selection) is not str or selection not in compiler.SELECTIONS:
            raise QuantitativeConstructionError("invalid_selection")
        domain_spec = spec["domain"]
        if type(domain_spec) is not dict or domain_spec.get("kind") != "integer_interval":
            raise QuantitativeConstructionError("unsupported_domain")
        domain, _, _ = compiler._domain(domain_spec, ())
        budget = [0]
        left, _ = compiler._expression(condition["left"], budget, allow_variable=True)
        right, _ = compiler._expression(condition["right"], budget, allow_variable=True)
        # Evaluate the *entire* stated domain. Undefined unoffered points cannot
        # disappear through option selection, and no monotonicity is assumed.
        feasible = [value for value in domain
                    if compiler._holds(compiler._evaluate(left, value), relation,
                                       compiler._evaluate(right, value))]
        if not feasible:
            raise QuantitativeConstructionError("no_answer")
        answer = feasible[-1] if selection == "maximum" else feasible[0]
        if selection == "any_satisfying":
            candidates = [value for value in domain if value not in feasible]
        else:
            # A second satisfying number is wrong only under the explicitly
            # requested extremum. All options stay inside the stated domain.
            candidates = [value for value in domain if value != answer]
        candidates.sort(key=lambda value: (abs(value - answer), value))
        choices = _number_choices(answer, candidates)

    # The hash orders every final option identically, regardless of which is
    # correct; no native key, preferred slot or caller ordering is accepted.
    seed = json.dumps(spec, sort_keys=True, ensure_ascii=True, allow_nan=False,
                      separators=(",", ":")).encode()
    choices.sort(key=lambda value: (hashlib.sha256(seed + b"\0" + value.encode()).digest(), value))
    full = {**copy.deepcopy(spec), "choices": choices}
    compiler.compile_question(full)
    return full


def construct_quantitative_spec(spec_without_choices: dict) -> dict:
    """Return an independent full compiler spec, or fail without modifying input.

Only exact-value arithmetic and explicit bounded integer scalar domains are
supported. Three numerical mistakes/competitors must survive exact deduplication;
there is no random filler or fallback from malformed input. Final compiler text
bounds remain fail-closed. No pedagogical or verification stamp is returned.
"""
    try:
        return _construct(spec_without_choices)
    except compiler.QuantitativeTaskError as error:
        raise QuantitativeConstructionError(error.code) from error
