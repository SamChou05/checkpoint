"""Inactive, pure compiler for a closed quantitative multiple-choice subset.

The specification is the problem, not evidence about a separate prose problem.
Every learner string comes from this module; no model key, teaching, code, or
free-form scenario is accepted. No provider, routing, or policy dependencies.
"""

from fractions import Fraction
import re


MAX_NUMBER_CHARS = 24
MAX_COMPONENT = 1_000_000_000
MAX_RATIONAL_BITS = 96
MAX_EXPRESSION_NODES = 31
MAX_EXPRESSION_DEPTH = 6
MAX_DOMAIN_SIZE = 201
MAX_DOMAIN_BOUND = 1_000_000
UNITS = frozenset(("unitless", "m", "cm", "s", "kg", "g", "L", "USD", "rides"))
RELATIONS = {"lt": "<", "le": "<=", "gt": ">", "ge": ">=", "eq": "=", "ne": "!="}
OPERATORS = {"add": "+", "sub": "-", "mul": "*", "div": "/"}
SELECTIONS = frozenset(("any_satisfying", "minimum", "maximum"))
_NUMBER = re.compile(r"-?[0-9]+(?:/[0-9]+|\.[0-9]+)?\Z", re.ASCII)


class QuantitativeTaskError(ValueError):
    """A task cannot be compiled within the defined guarantees and limits."""

    def __init__(self, code):
        self.code = code
        super().__init__(code)


def _fail(code):
    raise QuantitativeTaskError(code)


def _fields(value, fields):
    if (type(value) is not dict or len(value) != len(fields)
            or any(type(key) is not str for key in value)
            or set(value) != set(fields)):
        _fail("invalid_fields")


def _bounded(value):
    if (value.numerator.bit_length() > MAX_RATIONAL_BITS
            or value.denominator.bit_length() > MAX_RATIONAL_BITS):
        _fail("arithmetic_limit")
    return value


def _number(value):
    if (type(value) is not str or not 1 <= len(value) <= MAX_NUMBER_CHARS
            or _NUMBER.fullmatch(value) is None):
        _fail("invalid_number")
    if "/" in value:
        numerator, denominator = map(int, value.split("/"))
    elif "." in value:
        integer, decimal = value.split(".")
        numerator = int(integer + decimal)
        denominator = 10 ** len(decimal)
    else:
        numerator, denominator = int(value), 1
    if (abs(numerator) > MAX_COMPONENT or not 1 <= denominator <= MAX_COMPONENT):
        _fail("number_limit")
    return _bounded(Fraction(numerator, denominator))


def _expression(value, budget, *, allow_variable, depth=1):
    budget[0] += 1
    if budget[0] > MAX_EXPRESSION_NODES or depth > MAX_EXPRESSION_DEPTH:
        _fail("expression_limit")
    if type(value) is not dict or len(value) not in (1, 3):
        _fail("invalid_expression")
    if set(value) == {"value"}:
        _fields(value, ("value",))
        number = _number(value["value"])
        # A fraction literal must remain one operand: a / (b/c) is not a/b/c.
        text = str(number) if number.denominator == 1 else f"({number})"
        return ("constant", number), text
    if set(value) == {"variable"}:
        _fields(value, ("variable",))
        if not allow_variable or type(value["variable"]) is not str or value["variable"] != "x":
            _fail("invalid_variable")
        return ("variable",), "x"
    _fields(value, ("op", "left", "right"))
    op = value["op"]
    if type(op) is not str or op not in OPERATORS:
        _fail("invalid_operator")
    left, left_text = _expression(value["left"], budget, allow_variable=allow_variable,
                                  depth=depth + 1)
    right, right_text = _expression(value["right"], budget, allow_variable=allow_variable,
                                    depth=depth + 1)
    return (op, left, right), f"({left_text} {OPERATORS[op]} {right_text})"


def _evaluate(expression, x=None):
    op = expression[0]
    if op == "constant":
        return expression[1]
    if op == "variable":
        return x
    left, right = _evaluate(expression[1], x), _evaluate(expression[2], x)
    if op == "add":
        result = left + right
    elif op == "sub":
        result = left - right
    elif op == "mul":
        result = left * right
    else:
        if right == 0:
            _fail("undefined_expression")
        result = left / right
    return _bounded(result)


def _holds(left, relation, right):
    if relation == "lt":
        return left < right
    if relation == "le":
        return left <= right
    if relation == "gt":
        return left > right
    if relation == "ge":
        return left >= right
    if relation == "eq":
        return left == right
    return left != right


def _quantity(value, unit):
    return str(value) if unit == "unitless" else f"{value} {unit}"


def _domain(raw, choices):
    if type(raw) is not dict or type(raw.get("kind")) is not str:
        _fail("invalid_domain")
    if raw == {"kind": "offered"}:
        _fields(raw, ("kind",))
        return tuple(choices), "the offered values", lambda value: True
    _fields(raw, ("kind", "lower", "upper"))
    lower, upper = raw["lower"], raw["upper"]
    if (raw["kind"] != "integer_interval" or type(lower) is not int or type(upper) is not int
            or lower.bit_length() > 20 or upper.bit_length() > 20
            or abs(lower) > MAX_DOMAIN_BOUND or abs(upper) > MAX_DOMAIN_BOUND
            or not 1 <= upper - lower + 1 <= MAX_DOMAIN_SIZE):
        _fail("domain_limit")
    values = tuple(Fraction(value) for value in range(lower, upper + 1))
    text = f"integers from {lower} through {upper}, inclusive"
    return values, text, lambda value: value.denominator == 1 and lower <= value <= upper


def _unique_answer(supported):
    if not supported:
        _fail("no_answer")
    if len(supported) != 1:
        _fail("multiple_answers")
    return supported[0]


def _finish(prompt, choices, answer, explanation, feedback):
    for text, minimum, maximum in (
        (prompt, 12, 320), (explanation, 12, 420),
        *((text, 1, 140) for text in choices),
        *((text, 12, 280) for text in feedback.values()),
    ):
        if not minimum <= len(text) <= maximum:
            _fail("learner_text_limit")
    return {"prompt": prompt, "choices": choices, "expectedAnswer": answer,
            "explanation": explanation, "choiceExplanations": feedback}


def compile_question(spec):
    """Compile one exact five-field learner payload or raise QuantitativeTaskError.

    Number inputs are bounded decimal/fraction/integer strings, never floats.
    All expressions operate on numerical measures in a single declared unit;
    this subset neither converts units nor infers physical dimensional equations.
    Selection is explicit and rendered. Output contains no verification stamp.
    """
    if type(spec) is not dict or type(spec.get("kind")) is not str:
        _fail("invalid_task")
    kind = spec["kind"]
    if kind == "exact_value":
        _fields(spec, ("kind", "unit", "expression", "choices"))
    elif kind == "scalar_condition":
        _fields(spec, ("kind", "unit", "condition", "selection", "domain", "choices"))
    else:
        _fail("invalid_task")
    unit = spec["unit"]
    if type(unit) is not str or unit not in UNITS:
        _fail("invalid_unit")
    raw_choices = spec["choices"]
    if type(raw_choices) is not list or len(raw_choices) != 4:
        _fail("invalid_choices")
    choices = [_number(value) for value in raw_choices]
    if len(set(choices)) != 4:
        _fail("equivalent_choices")
    rendered = [_quantity(value, unit) for value in choices]
    measure = "a unitless number" if unit == "unitless" else f"a numerical measure in {unit}"
    if kind == "exact_value":
        expression, text = _expression(spec["expression"], [0], allow_variable=False)
        result = _evaluate(expression)
        answer = _unique_answer([value for value in choices if value == result])
        prompt = f"Let q be {measure}, defined by q = {text}. What is its exact value?"
        explanation = f"The expression {text} evaluates exactly to {result}. The answer is {_quantity(answer, unit)}."
        feedback = {
            shown: (f"The expression evaluates exactly to {result}; {shown} is the requested value."
                    if value == answer else
                    f"The expression evaluates exactly to {result}, not {value}. {shown} is not the requested value.")
            for value, shown in zip(choices, rendered, strict=True)
        }
        return _finish(prompt, rendered, _quantity(answer, unit), explanation, feedback)

    condition = spec["condition"]
    _fields(condition, ("left", "relation", "right"))
    relation = condition["relation"]
    selection = spec["selection"]
    if type(relation) is not str or relation not in RELATIONS:
        _fail("invalid_relation")
    if type(selection) is not str or selection not in SELECTIONS:
        _fail("invalid_selection")
    budget = [0]
    left, left_text = _expression(condition["left"], budget, allow_variable=True)
    right, right_text = _expression(condition["right"], budget, allow_variable=True)
    domain, domain_text, in_domain = _domain(spec["domain"], choices)
    # Evaluate every permitted value, including those not offered. Undefined
    # arithmetic anywhere in the declared domain rejects the task, not a choice.
    observations = {value: (_evaluate(left, value), _evaluate(right, value)) for value in domain}
    feasible = [value for value, (a, b) in observations.items() if _holds(a, relation, b)]
    if selection == "any_satisfying":
        supported = [value for value in choices if value in feasible]
        task = "Which offered value of x satisfies the condition?"
    else:
        extremum = (min(feasible) if selection == "minimum" else max(feasible)) if feasible else None
        supported = [value for value in choices if value == extremum]
        task = f"What is the {selection} x in this domain satisfying the condition?"
    answer = _unique_answer(supported)
    formula = f"{left_text} {RELATIONS[relation]} {right_text}"
    prompt = f"Let x be {measure}. Its domain is {domain_text}. Condition: {formula}. {task}"
    selected_text = ("the only offered value satisfying the condition"
                     if selection == "any_satisfying" else
                     f"the {selection} value satisfying the condition in this domain")
    answer_left, answer_right = observations[answer]
    if selection == "any_satisfying":
        proof = "Every other offered value is outside the domain or fails the condition."
    else:
        direction = "smaller" if selection == "minimum" else "larger"
        competitors = [value for value in domain
                       if (value < answer if selection == "minimum" else value > answer)]
        proof = (f"Every {direction} value in the stated domain fails the condition." if competitors
                 else f"No {direction} value exists in the stated domain.")
    explanation = (f"At x = {answer}, {answer_left} {RELATIONS[relation]} {answer_right} is true. "
                   f"{_quantity(answer, unit)} is {selected_text}. {proof}")
    feedback = {}
    for value, shown in zip(choices, rendered, strict=True):
        if not in_domain(value):
            feedback[shown] = f"{shown} is outside the stated domain ({domain_text}); it cannot answer this question."
            continue
        a, b = observations[value]
        holds = _holds(a, relation, b)
        evidence = f"At x = {value}, {a} {RELATIONS[relation]} {b} is {'true' if holds else 'false'}."
        if not holds:
            feedback[shown] = evidence + " This value does not satisfy the condition."
        elif value == answer:
            feedback[shown] = evidence + f" This is {selected_text}."
        else:
            # A satisfying value can be excluded ONLY by the explicit extremum
            # task. Any-satisfying questions with two such choices already fail.
            feedback[shown] = evidence + f" The question asks for the {selection}; that value is {_quantity(answer, unit)}."
    return _finish(prompt, rendered, _quantity(answer, unit), explanation, feedback)
