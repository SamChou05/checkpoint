"""Derive four numerical options from a closed task, never a proposed key.

This pure constructor owns no routing, approval or learner prose. The existing
compiler validates all mathematical bounds and renders the final five fields.
"""

import copy
import hashlib
import json

import quantitative_task_compiler as compiler


class QuantitativeConstructionError(ValueError):
    """A task cannot supply four defensible options within the closed subset."""

    def __init__(self, code):
        self.code = code
        super().__init__(code)


def _calculation(op, left, right):
    try:
        return compiler._calculate(op, left, right)
    except compiler.QuantitativeTaskError:
        # A hypothetical mistake may divide by zero or overflow. It cannot
        # become an offered number. Errors in the actual task are not caught.
        return None


def _mistakes(expression):
    """Values from exactly one changed operation in this validated subtree.

At most six local changes per binary node: substitute another arithmetic
operator, omit that operation and keep either operand, or reverse a subtraction
or division. Child mistakes propagate through otherwise unchanged ancestors.
The compiler's 31-node tree bound permits at most 90 candidate values.
"""
    if expression[0] == "constant":
        return []
    op, left_tree, right_tree = expression
    left, right = compiler._evaluate(left_tree), compiler._evaluate(right_tree)
    proposed = [_calculation(other, left, right)
                for other in compiler.OPERATORS if other != op]
    proposed.extend((left, right))
    if op in {"sub", "div"}:
        proposed.append(_calculation(op, right, left))
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
