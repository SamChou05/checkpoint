"""Pure compiler for a closed quantitative multiple-choice subset.

The specification is the problem, not evidence about a separate prose problem.
Every learner string comes from this module; no model key, teaching, code, or
free-form scenario is accepted. No provider, routing, or policy dependencies.
"""

from fractions import Fraction
from math import lcm
import re


MAX_NUMBER_CHARS = 24
MAX_COMPONENT = 1_000_000_000
MAX_RATIONAL_BITS = 96
MAX_EXPRESSION_NODES = 31
MAX_EXPRESSION_DEPTH = 6
MAX_DOMAIN_SIZE = 201
MAX_DOMAIN_BOUND = 1_000_000
MAX_EXPLICIT_COMPETITORS = 8
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
    return _calculate(op, left, right)


def _calculate(op, left, right):
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


def _operand(value):
    # Preserve unary signs and fraction grouping in every displayed operation.
    return f"({value})" if value < 0 or value.denominator != 1 else str(value)


def _equation(terms):
    # Omit only identical adjacent written terms, never a different calculation.
    return " = ".join(term for i, term in enumerate(terms) if i == 0 or term != terms[i - 1])


def _worked_steps(expression):
    """Evaluate validated constant IR and explain each operation in postorder.

    All displayed fractions are exact; unreduced numerators/denominators expose
    the operation before Fraction's reduction. No trace is clipped to fit.
    """
    op = expression[0]
    if op == "constant":
        return expression[1], []
    left, left_steps = _worked_steps(expression[1])
    right, right_steps = _worked_steps(expression[2])
    result = _calculate(op, left, right)
    terms = [f"{_operand(left)} {OPERATORS[op]} {_operand(right)}"]
    if op in ("add", "sub"):
        denominator = lcm(left.denominator, right.denominator)
        if denominator == 1:
            label = "Add" if op == "add" else "Subtract"
        else:
            label = f"Common denominator {denominator}"
            a = left.numerator * (denominator // left.denominator)
            b = right.numerator * (denominator // right.denominator)
            terms.append(f"({a}/{denominator}) {OPERATORS[op]} ({b}/{denominator})")
            numerator = a + b if op == "add" else a - b
            terms.append(f"{numerator}/{denominator}")
    elif op == "mul":
        label = "Multiply"
        if left.denominator != 1 or right.denominator != 1:
            label = "Multiply numerators and denominators"
            terms.append(f"{left.numerator * right.numerator}/{left.denominator * right.denominator}")
    else:
        # _calculate already rejects zero. Fraction normalizes a negative divisor
        # into a signed numerator with a positive denominator for the reciprocal.
        reciprocal = 1 / right
        label = "Multiply by the reciprocal"
        terms.append(f"{_operand(left)} * {_operand(reciprocal)}")
        terms.append(f"{left.numerator * reciprocal.numerator}/{left.denominator * reciprocal.denominator}")
    terms.append(str(result))
    step = f"{label}: {_equation(terms)}."
    return result, left_steps + right_steps + [step]


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


def _rational_equation_derivation(left, right, domain, answer, *, unit, relation, selection):
    """Show algebra for (x+a)/(x+1) = p/q when its exact proof permits it.

    The generic domain evaluation remains authoritative. Recognize only the
    validated expression tree, and recompute the solution before presenting a
    linear derivation; other scalar tasks retain their substitution teaching.
    """
    if (unit != "unitless" or relation != "eq" or selection != "any_satisfying"
            or left[0] != "div" or right[0] != "div"
            or left[1][0] != "add" or left[2][0] != "add"
            or left[1][1] != ("variable",) or left[2][1] != ("variable",)
            or left[1][2][0] != "constant" or left[2][2] != ("constant", Fraction(1))
            or right[1][0] != "constant" or right[2][0] != "constant"
            or not domain or domain[0] < 0 or answer.denominator != 1):
        return None
    offset = left[1][2][1]
    if offset.denominator != 1 or offset <= 1:
        return None
    target = _evaluate(right)
    numerator, denominator = target.numerator, target.denominator
    coefficient = numerator - denominator
    constant = denominator * offset - numerator
    if (numerator <= denominator or coefficient <= 0 or constant <= 0
            or constant != coefficient * answer):
        return None
    solved_step = (f"so {constant} = x, giving x = {answer}. " if coefficient == 1 else
                   f"so {constant} = {coefficient}x. Divide by {coefficient} to get x = {answer}. ")
    return (
        f"Because x + 1 is nonzero throughout the domain, cross-multiply: "
        f"{denominator}(x + {offset}) = {numerator}(x + 1). "
        f"Expanding gives {denominator}x + {denominator * offset} = "
        f"{numerator}x + {numerator}, {solved_step}"
        "The nonzero x coefficient makes this the only solution in the domain."
    )


def _root_distractor_reasons(expression):
    """Recognize exact values from common mistakes at the final operation.

    These are possible paths to an offered value, not claims about a learner's
    actual reasoning. Earlier-step mistakes receive the final-operation proof
    instead. Preserve the first explanation when two mistakes have one value.
    """
    if expression[0] == "constant":
        return {}
    op, left_tree, right_tree = expression
    left, right = _evaluate(left_tree), _evaluate(right_tree)
    result = _calculate(op, left, right)
    reasons = {}

    def add(value, reason):
        if value is not None and value != result:
            reasons.setdefault(value, reason)

    def calculate(other, a, b):
        if a is None or b is None:
            return None
        try:
            return _calculate(other, a, b)
        except QuantitativeTaskError:
            return None

    if op in ("add", "sub") and (left.denominator != 1 or right.denominator != 1):
        numerator = calculate(op, Fraction(left.numerator), Fraction(right.numerator))
        denominator = calculate(op, Fraction(left.denominator), Fraction(right.denominator))
        add(calculate("div", numerator, denominator),
            "This can come from combining the numerators and denominators separately.")
        add(calculate("div", numerator, Fraction(lcm(left.denominator, right.denominator))),
            "This can come from using a common denominator without scaling the numerators.")
    elif op == "mul" and left.denominator != 1 and right.denominator != 1:
        numerator = calculate("mul", Fraction(left.numerator), Fraction(right.numerator))
        add(calculate("div", numerator, Fraction(left.denominator)),
            f"This can come from leaving out the denominator {right.denominator}.")
        add(calculate("div", numerator, Fraction(right.denominator)),
            f"This can come from leaving out the denominator {left.denominator}.")
    elif op == "mul" and (left.denominator != 1) != (right.denominator != 1):
        fraction, whole = (left, right) if left.denominator != 1 else (right, left)
        if abs(whole) > 1:
            numerator = Fraction(fraction.numerator)
            denominator = Fraction(fraction.denominator)
            add(calculate("div", whole, denominator),
                f"This can come from dropping the numerator {numerator} of {fraction}.")
            add(calculate("mul", numerator, whole),
                f"This can come from dropping the denominator {denominator} of {fraction}.")
            add(calculate("div", numerator, calculate("mul", denominator, whole)),
                f"This can come from multiplying the denominator by {whole} instead of the numerator.")
    elif op == "div" and (left.denominator != 1 or right.denominator != 1):
        add(calculate("mul", left, right),
            f"This can come from multiplying by {right} instead of dividing by it.")
        add(calculate("div", right, left),
            "This can come from reversing the dividend and divisor.")
        product = calculate("mul", left, right)
        add(calculate("div", Fraction(1), product),
            "This can come from taking the reciprocal of the product of both operands.")

    add(left, "This stops at the left operand before the final operation.")
    add(right, "This stops at the right operand before the final operation.")
    for other in OPERATORS:
        if other != op:
            add(calculate(other, left, right),
                f"This can come from using {OPERATORS[other]} at the final step instead of {OPERATORS[op]}.")
    if op in ("sub", "div"):
        add(calculate(op, right, left),
            "This can come from reversing the operands at the final step.")
    return reasons


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
        result, steps = _worked_steps(expression)
        answer = _unique_answer([value for value in choices if value == result])
        prompt = f"Let q be {measure}, defined by q = {text}. What is its exact value?"
        teaching = " ".join(steps) if steps else f"The definition directly gives q = {result}."
        explanation = f"{teaching} The answer is {_quantity(answer, unit)}."
        reasons = _root_distractor_reasons(expression)
        if expression[0] != "constant":
            op, left_tree, right_tree = expression
            left, right = _evaluate(left_tree), _evaluate(right_tree)
            correction = f"{_operand(left)} {OPERATORS[op]} {_operand(right)} = {result}"
        feedback = {}
        for value, shown in zip(choices, rendered, strict=True):
            if value == answer:
                feedback[shown] = f"The expression evaluates exactly to {result}; {shown} is the requested value."
                continue
            if expression[0] == "constant":
                detail = f"{shown}: The definition gives q = {_quantity(result, unit)}, not {shown}."
            else:
                reason = reasons.get(value, "Use the evaluated operands in the final calculation.")
                detail = f"{shown}: {reason} {correction}, not {value}."
            feedback[shown] = (detail if len(detail) <= 280 else
                               f"The expression evaluates exactly to {result}, not {value}. {shown} is not the requested value.")
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
        competitors = sorted(value for value in domain
                             if (value < answer if selection == "minimum" else value > answer))
        proof = (f"Every {direction} value in the stated domain fails the condition." if competitors
                 else f"No {direction} value exists in the stated domain.")
    explanation_start = (f"At x = {answer}, {answer_left} {RELATIONS[relation]} {answer_right} is true. "
                         f"{_quantity(answer, unit)} is {selected_text}. ")
    # Show the whole competing set when it fits; a partial list would not prove
    # a domain-wide minimum or maximum. Never clip learner-facing evidence.
    if selection != "any_satisfying" and 0 < len(competitors) <= MAX_EXPLICIT_COMPETITORS:
        comparisons = "; ".join(
            f"x = {value}: {observations[value][0]} {RELATIONS[relation]} "
            f"{observations[value][1]} is false" for value in competitors
        )
        explicit_proof = f"The {direction} domain values fail: {comparisons}."
        if len(explanation_start) + len(explicit_proof) <= 420:
            proof = explicit_proof
    explanation = (_rational_equation_derivation(
        left, right, domain, answer, unit=unit, relation=relation, selection=selection,
    ) or explanation_start + proof)
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
