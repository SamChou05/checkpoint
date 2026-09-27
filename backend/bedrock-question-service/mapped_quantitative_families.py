"""Closed numerical task families for the pinned mapped 3:2 pilot.

Provider fields choose bounded operands only. This module owns each expression,
domain and operation; the existing quantitative compiler owns all learner text,
choices, answer keys, feedback and the independently rechecked provenance.
"""

from __future__ import annotations

from typing import Any

from question_bank_common import _normalized_stem_identity, _stem_fingerprint


FAMILIES = ("fraction_evaluation", "bounded_equation", "bounded_ratio_threshold")
SUPPORTED_TOPIC = "Exact arithmetic"
SUPPORTED_OBJECTIVE = "Evaluate an exact rational expression or explicit bounded condition"
OPERANDS = tuple(range(2, 10))
BOUNDARIES = tuple(range(3, 12))


class MappedQuantitativeFamilyError(ValueError):
    """A model row does not match its trusted original slot."""


def task_schema(slot: int) -> dict[str, Any]:
    """Return a small native shape with no graph, key or learner text."""
    if type(slot) is not int or slot not in (0, 1, 2):
        raise MappedQuantitativeFamilyError("Unsupported quantitative slot.")
    return {
        "type": "object", "additionalProperties": False,
        "properties": {
            "family": {"type": "string", "enum": [FAMILIES[slot]]},
            "a": {"type": "integer", "enum": list(OPERANDS)},
            "b": {"type": "integer", "enum": list(OPERANDS if slot == 0 else BOUNDARIES)},
        },
        "required": ["family", "a", "b"],
    }


def _literal(value: int) -> dict[str, str]:
    return {"kind": "literal", "value": str(value)}


def _binary(op: str, left: int, right: int) -> dict[str, str | int]:
    return {"kind": "binary", "op": op, "left": left, "right": right}


def flat_task(slot: int, row: object) -> dict[str, Any]:
    """Expand only the closed family assigned to this original slot."""
    if (type(slot) is not int or slot not in (0, 1, 2)
            or type(row) is not dict or set(row) != {"family", "a", "b"}
            or type(row["family"]) is not str or row["family"] != FAMILIES[slot]
            or type(row["a"]) is not int or row["a"] not in OPERANDS
            or type(row["b"]) is not int
            or row["b"] not in (OPERANDS if slot == 0 else BOUNDARIES)):
        raise MappedQuantitativeFamilyError("Unsupported quantitative family row.")
    a, b = row["a"], row["b"]
    if slot == 0:
        # (a/(a+1) + b/(b+2)) * 3: two nonintegral operands and two steps.
        return {"kind": "exact_value", "unit": "unitless", "nodes": [
            _literal(a), _literal(a + 1), _binary("div", 0, 1),
            _literal(b), _literal(b + 2), _binary("div", 3, 4),
            _binary("add", 2, 5), _literal(3), _binary("mul", 6, 7),
        ], "root": 8}
    if slot == 1:
        # ax+(a+3)=ab+(a+3) has the unique solution x=b in 0..15.
        offset = a + 3
        return {"kind": "scalar_condition", "unit": "unitless", "nodes": [
            _literal(a), {"kind": "variable"}, _binary("mul", 0, 1),
            _literal(offset), _binary("add", 2, 3),
            _literal(a * b + offset),
        ], "condition": {"left": 4, "relation": "eq", "right": 5},
            "selection": "any_satisfying",
            "domain": {"kind": "integer_interval", "lower": 0, "upper": 15}}
    # The ratio x/(x+a) reaches b/(b+a) first at x=b for positive a.
    # Its entire interval is positive-denominator; the three smaller domain
    # values are all explicitly checked in the compiler's worked teaching.
    return {"kind": "scalar_condition", "unit": "unitless", "nodes": [
        {"kind": "variable"}, _literal(a), _binary("add", 0, 1),
        _binary("div", 0, 2), _literal(b), _literal(b + a),
        _binary("div", 4, 5),
    ], "condition": {"left": 3, "relation": "ge", "right": 6},
        "selection": "minimum",
        "domain": {"kind": "integer_interval", "lower": b - 3, "upper": b + 3}}


def select_novel_task(
    slot: int, source_task: dict, *, existing_prompts: tuple[str, ...],
    blocked_fingerprints: tuple[str, ...], fingerprint_version: int,
) -> dict[str, Any]:
    """Keep fresh model operands; otherwise search this slot's finite family.

    Search starts at the source pair and wraps in fixed parameter order. Every
    candidate is compiled before its stem is compared with the same recent and
    full-bank identities used by sanitization. Exhaustion fails the whole mapped
    pass rather than emitting a known duplicate or changing its assigned family.
    """
    from quantitative_authoring import _constructed_candidate

    if (type(slot) is not int or slot not in (0, 1, 2)
            or type(source_task) is not dict or type(existing_prompts) is not tuple
            or any(type(prompt) is not str for prompt in existing_prompts)
            or type(blocked_fingerprints) is not tuple
            or any(type(value) is not str for value in blocked_fingerprints)):
        raise MappedQuantitativeFamilyError("Invalid quantitative novelty input.")
    try:
        _stem_fingerprint("", version=fingerprint_version)
    except ValueError as error:
        raise MappedQuantitativeFamilyError("Invalid fingerprint version.") from error
    pairs = [(a, b) for a in OPERANDS
             for b in (OPERANDS if slot == 0 else BOUNDARIES)]
    tasks = [flat_task(slot, {"family": FAMILIES[slot], "a": a, "b": b})
             for a, b in pairs]
    try:
        start = tasks.index(source_task)
    except ValueError as error:
        raise MappedQuantitativeFamilyError("Source task is outside its assigned family.") from error
    blocked = {_normalized_stem_identity(prompt) for prompt in existing_prompts}
    fingerprints = set(blocked_fingerprints)
    for offset in range(len(tasks)):
        candidate = tasks[(start + offset) % len(tasks)]
        prompt = _constructed_candidate(candidate).content()["prompt"]
        if (_normalized_stem_identity(prompt) not in blocked
                and _stem_fingerprint(prompt, version=fingerprint_version) not in fingerprints):
            return candidate
    raise MappedQuantitativeFamilyError("Quantitative family inventory exhausted.")
