"""Offline exact-arithmetic comparison prototype; not wired to production.

The model may select only a closed family, operand pair, and presentation order.
Fraction arithmetic owns the answer, all choices, and all teaching text.
"""

from fractions import Fraction


TASK_KIND = "rational_comparison_v1"
FAMILIES = ("crossed_sums", "crossed_products")
ORDERS = ("forward", "reverse")
LEARNER_FIELDS = ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations")

# A pair is a single enum so the native schema cannot admit equal operands or
# a product case where the partial-calculation margin equals the truth. These
# eight pairs have different exact margins across both families, avoiding
# mirrored operands and a cross-family answer collision.
PAIRS = {
    f"{a}_{b}": (a, b)
    for a, b in (
        (2, 3), (2, 4), (2, 5), (5, 3),
        (6, 3), (4, 5), (6, 4), (5, 6),
    )
}


class MathComparisonTaskError(ValueError):
    """The supplied task or its compiled content violates the closed contract."""


def task_schema() -> dict:
    """Return the bounded standalone shape for a possible native author."""
    return {
        "type": "object", "additionalProperties": False,
        "properties": {
            "kind": {"type": "string", "const": TASK_KIND},
            "family": {"type": "string", "enum": list(FAMILIES)},
            "pair": {"type": "string", "enum": list(PAIRS)},
            "order": {"type": "string", "enum": list(ORDERS)},
        },
        "required": ["kind", "family", "pair", "order"],
    }


def _checked_task(task: object, ordinal: int) -> tuple[str, int, int, str]:
    if (type(task) is not dict or set(task) != {"kind", "family", "pair", "order"}
            or type(task["kind"]) is not str or task["kind"] != TASK_KIND
            or type(task["family"]) is not str or task["family"] not in FAMILIES
            or type(task["pair"]) is not str or task["pair"] not in PAIRS
            or type(task["order"]) is not str or task["order"] not in ORDERS
            or type(ordinal) is not int or ordinal < 0):
        raise MathComparisonTaskError("Unsupported or model-extended comparison task.")
    a, b = PAIRS[task["pair"]]
    return task["family"], a, b, task["order"]


def _fraction(value: Fraction) -> str:
    return str(value.numerator) if value.denominator == 1 else str(value)


def _choice(winner: str, loser: str, margin: Fraction) -> str:
    return f"{winner} is larger than {loser} by {_fraction(margin)}."


def compile_question(task: object, *, ordinal: int = 0) -> dict:
    """Compile one exact key, four semantic choices, and literal-keyed feedback."""
    family, a, b, order = _checked_task(task, ordinal)
    x, y = Fraction(a, a + 1), Fraction(b, b + 2)
    u, v = Fraction(a, a + 2), Fraction(b, b + 1)
    sign = "+" if family == "crossed_sums" else "×"
    if family == "crossed_sums":
        first_value, second_value = x + y, u + v
        partial_margin = abs(x - u)
        partial_reason = "subtracting only the first fractions and ignoring the second fractions"
    else:
        first_value, second_value = x * y, u * v
        partial_margin = abs(x - u) * (y if order == "forward" else v)
        partial_reason = "holding the second factor fixed at A's value"
    first_expression = f"{a}/{a + 1} {sign} {b}/{b + 2}"
    second_expression = f"{a}/{a + 2} {sign} {b}/{b + 1}"
    if order == "reverse":
        first_expression, second_expression = second_expression, first_expression
        first_value, second_value = second_value, first_value
    if first_value == second_value:
        raise MathComparisonTaskError("Comparison unexpectedly tied.")
    margin = abs(first_value - second_value)
    if partial_margin in {Fraction(0), margin}:
        raise MathComparisonTaskError("Comparison margins are not distinct.")

    winner, loser = (("A", "B") if first_value > second_value else ("B", "A"))
    claims = (
        (winner, loser, margin),
        (loser, winner, margin),
        (winner, loser, partial_margin),
        (loser, winner, partial_margin),
    )
    offset = ordinal % len(claims)
    choices = [_choice(*claim) for claim in claims[offset:] + claims[:offset]]
    answer = _choice(winner, loser, margin)
    opposite = _choice(loser, winner, margin)
    partial = _choice(winner, loser, partial_margin)
    both_wrong = _choice(loser, winner, partial_margin)
    prompt = (f"Let A = {first_expression} and B = {second_expression}. "
              "Which is larger, and by exactly how much?")
    explanation = (
        f"A = {first_expression} = {_fraction(first_value)}; "
        f"B = {second_expression} = {_fraction(second_value)}. "
        f"Subtracting gives |A − B| = {_fraction(margin)}, so {answer} "
        f"Choices naming {loser} as larger reverse the comparison; "
        f"the margin {_fraction(partial_margin)} comes from {partial_reason}."
    )
    feedback = {
        answer: (f"Correct. A = {_fraction(first_value)} and B = {_fraction(second_value)}; "
                 f"the exact difference is {_fraction(margin)}."),
        opposite: (f"Incorrect: the difference {_fraction(margin)} is right, "
                   f"but {_fraction(first_value)} and {_fraction(second_value)} "
                   f"show that {winner}, not {loser}, is larger."),
        partial: (f"Incorrect: {_fraction(partial_margin)} comes from {partial_reason}. "
                  f"The full expressions differ by {_fraction(margin)}."),
        both_wrong: (f"Incorrect: {loser} is not larger, and {_fraction(partial_margin)} "
                     f"comes from {partial_reason}. The exact margin is {_fraction(margin)}."),
    }
    result = {
        "prompt": prompt, "choices": choices, "expectedAnswer": answer,
        "explanation": explanation,
        "choiceExplanations": {choice: feedback[choice] for choice in choices},
    }
    if (set(result) != set(LEARNER_FIELDS) or len(choices) != 4
            or len(set(choices)) != 4 or choices.count(answer) != 1
            or list(result["choiceExplanations"]) != choices
            or not 12 <= len(prompt) <= 320
            or any(not 1 <= len(choice) <= 140 for choice in choices)
            or not 12 <= len(explanation) <= 420
            or any(not 1 <= len(note) <= 280 for note in feedback.values())):
        raise MathComparisonTaskError("Comparison content exceeded closed answer limits.")
    return result
