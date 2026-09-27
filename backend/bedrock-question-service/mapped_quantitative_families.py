"""Closed numerical task families for the pinned mapped 3:2 pilot.

Provider fields choose bounded operands only. This module owns each expression,
domain and operation; the existing quantitative compiler owns all learner text,
choices, answer keys, feedback and the independently rechecked provenance.
"""

from __future__ import annotations

from typing import Any


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
