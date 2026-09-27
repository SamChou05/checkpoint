"""Offline, closed worked-evaluation MCQs; not wired to production authoring.

The model may select only a curated scene. Code owns the expression, exact
arithmetic, four derivations, literal answer key, and position-free teaching.
This prototype needs blind learner review and live qualification before use.
"""

from dataclasses import dataclass
from fractions import Fraction


TASK_KIND = "rational_worked_evaluation_v1"
LEARNER_FIELDS = ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations")


class MathReasoningTaskError(ValueError):
    """A task or constructed question violates the closed prototype contract."""


@dataclass(frozen=True)
class _Scene:
    operation: str
    base: Fraction
    left: Fraction
    right: Fraction


# Curated operand sets keep every result compact. These are data, not model
# values; each scene is checked again when compiled because equal error results
# would make two worked choices indistinguishable as numerical outcomes.
SCENES = {
    "multiply_a": _Scene("multiply", Fraction(3, 4), Fraction(2, 3), Fraction(3, 5)),
    "multiply_b": _Scene("multiply", Fraction(1, 2), Fraction(1, 3), Fraction(3, 4)),
    "multiply_c": _Scene("multiply", Fraction(2, 5), Fraction(3, 4), Fraction(2, 3)),
    "divide_a": _Scene("divide", Fraction(1, 2), Fraction(1, 3), Fraction(2, 3)),
    "divide_b": _Scene("divide", Fraction(3, 5), Fraction(2, 3), Fraction(4, 5)),
    "divide_c": _Scene("divide", Fraction(2, 3), Fraction(3, 4), Fraction(2, 5)),
}


def task_schema() -> dict:
    """A standalone schema for a model's scene selection; not production-wired."""
    return {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "kind": {"type": "string", "const": TASK_KIND},
            "scene": {"type": "string", "enum": list(SCENES)},
        },
        "required": ["kind", "scene"],
    }


def _checked_task(task: object, ordinal: int) -> _Scene:
    if (type(task) is not dict or set(task) != {"kind", "scene"}
            or type(task["kind"]) is not str or task["kind"] != TASK_KIND
            or type(task["scene"]) is not str or task["scene"] not in SCENES
            or type(ordinal) is not int or ordinal < 0):
        raise MathReasoningTaskError("Unsupported or model-extended math task.")
    scene = SCENES[task["scene"]]
    if (scene.operation not in {"multiply", "divide"}
            or any(type(value) is not Fraction or value <= 0 or value >= 1
                   for value in (scene.base, scene.left, scene.right))):
        raise MathReasoningTaskError("Math scene has unsupported operands.")
    return scene


def _worked_choices(scene: _Scene) -> tuple[tuple[str, str, str, str], tuple[Fraction, ...]]:
    base, left, right = scene.base, scene.left, scene.right
    multiply = scene.operation == "multiply"
    symbol = "×" if multiply else "÷"
    intermediate = left * right if multiply else left / right
    correct = base + intermediate
    early_sum = base + left
    early_result = early_sum * right if multiply else early_sum / right
    crossed_sum = Fraction(base.numerator + intermediate.numerator,
                           base.denominator + intermediate.denominator)
    false_inner_numerator = left.numerator * right.numerator
    false_inner_denominator = (left.denominator + right.denominator if multiply
                               else left.denominator * right.denominator)
    false_inner = Fraction(false_inner_numerator, false_inner_denominator)
    false_inner_result = base + false_inner

    outcomes = (correct, early_result, crossed_sum, false_inner_result)
    if len(set(outcomes)) != 4 or false_inner == intermediate:
        raise MathReasoningTaskError("A flawed derivation collides with another result.")

    choices = (
        f"{left} {symbol} {right} = {intermediate}; "
        f"{base} + {intermediate} = {correct}.",
        f"{base} + {left} = {early_sum}; "
        f"{early_sum} {symbol} {right} = {early_result}.",
        f"{left} {symbol} {right} = {intermediate}; "
        f"({base.numerator}+{intermediate.numerator})/"
        f"({base.denominator}+{intermediate.denominator}) = {crossed_sum}.",
        (f"{left} {symbol} {right} = "
         f"{false_inner_numerator}/{false_inner_denominator}; "
         f"{base} + {false_inner} = {false_inner_result}." if multiply else
         f"{left} {symbol} {right} = {false_inner}; "
         f"{base} + {false_inner} = {false_inner_result}."),
    )
    return choices, outcomes


def compile_question(task: object, *, ordinal: int = 0) -> dict:
    """Return one exact, four-choice worked-evaluation question."""
    scene = _checked_task(task, ordinal)
    choices, outcomes = _worked_choices(scene)
    base, left, right = scene.base, scene.left, scene.right
    multiply = scene.operation == "multiply"
    symbol = "×" if multiply else "÷"
    verb = "multiplication" if multiply else "division"
    intermediate = left * right if multiply else left / right
    answer = choices[0]
    prompt = (f"Which worked evaluation correctly computes "
              f"{base} + {left} {symbol} {right}?")
    explanation = (
        f"Do {verb} before addition: {left} {symbol} {right} = {intermediate}, "
        f"then {base} + {intermediate} = {outcomes[0]}. Adding {base} and "
        f"{left} first changes the order of operations. Adding numerators and "
        f"denominators separately does not add fractions. "
        + ("Multiplying fractions requires multiplying their denominators."
           if multiply else "Dividing fractions requires the reciprocal of the divisor.")
    )
    feedback = (
        f"Correct. {verb.capitalize()} comes before addition, so the intermediate "
        f"value is {intermediate} and the result is {outcomes[0]}.",
        f"Incorrect. This adds {base} and {left} before {verb}; that changes "
        f"the expression. Do {left} {symbol} {right} first.",
        f"Incorrect. This adds the numerators and denominators separately. "
        f"The exact intermediate is {intermediate}; add {base} to it using a common denominator.",
        (f"Incorrect. The denominator of {left} × {right} is the product of "
         f"their denominators, not their sum. The exact product is {intermediate}."
         if multiply else
         f"Incorrect. This multiplies by {right} instead of dividing by it. "
         f"Use its reciprocal; {left} ÷ {right} = {intermediate}."),
    )
    offset = ordinal % 4
    ordered_choices = choices[offset:] + choices[:offset]
    feedback_by_choice = dict(zip(choices, feedback, strict=True))
    result = {
        "prompt": prompt,
        "choices": list(ordered_choices),
        "expectedAnswer": answer,
        "explanation": explanation,
        "choiceExplanations": {choice: feedback_by_choice[choice] for choice in ordered_choices},
    }
    if (set(result) != set(LEARNER_FIELDS) or len(set(choices)) != 4
            or ordered_choices.count(answer) != 1
            or set(result["choiceExplanations"]) != set(choices)
            or not 12 <= len(prompt) <= 320
            or any(not 1 <= len(choice) <= 140 or choice[:3] in {"A. ", "B. ", "C. ", "D. "}
                   for choice in choices)
            or not 12 <= len(explanation) <= 420
            or any(not 1 <= len(note) <= 280 for note in feedback)):
        raise MathReasoningTaskError("Worked-evaluation content exceeds answer limits.")
    return result
