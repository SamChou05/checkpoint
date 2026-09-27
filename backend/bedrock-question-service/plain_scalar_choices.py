"""Conservative exact-value collision check for plain numerical answers.

This is a veto, not an answer solver. It deliberately leaves expressions,
units, code output, and representation questions to the existing semantic
review because equal mathematical values need not be interchangeable there.
"""

from fractions import Fraction
import re


_SCALAR = re.compile(r"[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:/[+-]?\d+)?%?\Z")
_WORDS = {
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
    "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
    "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
    "eighteen": 18, "nineteen": 19, "twenty": 20,
}
_TENS = {
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
    "seventy": 70, "eighty": 80, "ninety": 90,
}


def _number_word(value: str) -> int | None:
    normalized = value.casefold()
    if normalized in _WORDS:
        return _WORDS[normalized]
    if normalized in _TENS:
        return _TENS[normalized]
    # Both spellings are common answers to a count question. Parse only a
    # complete tens-and-ones phrase, never words embedded in prose or code.
    parts = re.split(r"[ -]", normalized)
    if len(parts) == 2 and parts[0] in _TENS and parts[1] in _WORDS:
        ones = _WORDS[parts[1]]
        if 1 <= ones <= 9:
            return _TENS[parts[0]] + ones
    return None


_NUMERIC_TASK = re.compile(
    r"\b(?:value|sum|difference|product|quotient|probability|fraction|"
    r"percentage|percent|total|amount|ratio|mean|median|average|count|"
    r"how many|how much)\b", re.I,
)
_BARE_ARITHMETIC = re.compile(
    r"\s*what is\s+[+-]?\d+(?:\.\d+)?(?:\s*[+*/×÷-]\s*[+-]?\d+(?:\.\d+)?)+\s*\?\s*\Z",
    re.I,
)
_REPRESENTATION_TASK = re.compile(
    r"\b(?:written|notation|spelling|syntax|representation|representations|"
    r"literal|literals|string|strings|text|character|characters|digit|digits|"
    r"format|formatting|code|program|python|javascript|printed|printing|"
    r"console|output)\b", re.I,
)


def _plain_scalar(value: str) -> Fraction | None:
    value = value.strip(" \t\n\r\v\f")
    word = _number_word(value)
    if word is not None:
        return Fraction(word)
    if not _SCALAR.fullmatch(value):
        return None
    try:
        if value.endswith("%"):
            return Fraction(value[:-1]) / 100
        if "/" in value:
            numerator, denominator = value.split("/", 1)
            return Fraction(numerator) / Fraction(denominator)
        return Fraction(value)
    except (ValueError, ZeroDivisionError):
        return None


def has_plain_scalar_collision(prompt: str, choices: list[str]) -> bool:
    """Veto exact scalar duplicates only for an explicit numerical-value task.

    False negatives are expected: no inference from mathematical expressions,
    units, or subject-specific equivalence is attempted. A representation cue
    disables the gate so `2` and `two` can be distinct written answers.
    """
    if not isinstance(prompt, str) or not isinstance(choices, list):
        return False
    if _REPRESENTATION_TASK.search(prompt):
        return False
    if not (_NUMERIC_TASK.search(prompt) or _BARE_ARITHMETIC.fullmatch(prompt)):
        return False
    seen = set()
    for choice in choices:
        if not isinstance(choice, str):
            continue
        scalar = _plain_scalar(choice)
        if scalar is None:
            continue
        if scalar in seen:
            return True
        seen.add(scalar)
    return False
