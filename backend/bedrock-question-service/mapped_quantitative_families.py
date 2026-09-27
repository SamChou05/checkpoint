"""Closed numerical task families for the pinned mapped 3:2 pilot.

Provider fields choose bounded operands only. This module owns each expression,
domain and operation; the existing quantitative compiler owns all learner text,
choices, answer keys, feedback and the independently rechecked provenance.
"""

from __future__ import annotations

import copy
from collections import Counter
from functools import lru_cache
from typing import Any

from question_bank_common import _normalized_stem_identity, _stem_fingerprint


FAMILIES = ("fraction_evaluation", "bounded_equation", "bounded_ratio_threshold")
# Each slot keeps its original assignment while switching to a different
# mathematical decision on a refill. Operands within one family are examples
# of the same decision, not evidence of bank-level variety.
SLOT_FAMILIES = (
    (FAMILIES[0], "fraction_quotient", "fraction_reciprocal_sum",
     "fraction_product_complement"),
    (FAMILIES[1], "bounded_quadratic_equation", "bounded_rational_equation",
     "bounded_two_root_minimum"),
    (FAMILIES[2], "bounded_quadratic_maximum", "bounded_linear_budget_maximum",
     "bounded_solution_count"),
)
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
            "family": {"type": "string", "enum": list(SLOT_FAMILIES[slot])},
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
            or type(row["family"]) is not str or row["family"] not in SLOT_FAMILIES[slot]
            or type(row["a"]) is not int or row["a"] not in OPERANDS
            or type(row["b"]) is not int
            or row["b"] not in (OPERANDS if slot == 0 else BOUNDARIES)):
        raise MappedQuantitativeFamilyError("Unsupported quantitative family row.")
    a, b, family = row["a"], row["b"], row["family"]
    if family == FAMILIES[0]:
        # (a/(a+1) + b/(b+2)) * 3: two nonintegral operands and two steps.
        return {"kind": "exact_value", "unit": "unitless", "nodes": [
            _literal(a), _literal(a + 1), _binary("div", 0, 1),
            _literal(b), _literal(b + 2), _binary("div", 3, 4),
            _binary("add", 2, 5), _literal(3), _binary("mul", 6, 7),
        ], "root": 8}
    if family == "fraction_quotient":
        # (a/(a+1)) / (b/(b+2)) + 1: dividing exact fractions instead of
        # summing them and scaling the result.
        return {"kind": "exact_value", "unit": "unitless", "nodes": [
            _literal(a), _literal(a + 1), _binary("div", 0, 1),
            _literal(b), _literal(b + 2), _binary("div", 3, 4),
            _binary("div", 2, 5), _literal(1), _binary("add", 6, 7),
        ], "root": 8}
    if family == "fraction_reciprocal_sum":
        # Find the reciprocal of a sum of two nonintegral fractions. Unlike
        # sum-and-scale or quotient-and-add, the final division applies to
        # the entire exact sum, not to either original fraction.
        return {"kind": "exact_value", "unit": "unitless", "nodes": [
            _literal(a), _literal(a + 1), _binary("div", 0, 1),
            _literal(b), _literal(b + 2), _binary("div", 3, 4),
            _binary("add", 2, 5), _literal(1), _binary("div", 7, 6),
        ], "root": 8}
    if family == "fraction_product_complement":
        # Find the complement of a fraction of a fraction. The learner must
        # multiply the two proper fractions, then subtract that share from one;
        # this is neither sum-and-scale, quotient-and-add nor reciprocal-of-sum.
        return {"kind": "exact_value", "unit": "unitless", "nodes": [
            _literal(a), _literal(a + 1), _binary("div", 0, 1),
            _literal(b), _literal(b + 2), _binary("div", 3, 4),
            _binary("mul", 2, 5), _literal(1), _binary("sub", 7, 6),
        ], "root": 8}
    if family == FAMILIES[1]:
        # a(x+2)+(a+3)=(a-1)x+(b+3a+3) reduces to x=b. The variable
        # appears on both sides, so the learner must distribute and collect.
        return {"kind": "scalar_condition", "unit": "unitless", "nodes": [
            _literal(a), {"kind": "variable"}, _literal(2),
            _binary("add", 1, 2), _binary("mul", 0, 3),
            _literal(a + 3), _binary("add", 4, 5),
            _literal(a - 1), _binary("mul", 7, 1),
            _literal(b + 3 * a + 3), _binary("add", 8, 9),
        ], "condition": {"left": 6, "relation": "eq", "right": 10},
            "selection": "any_satisfying",
            "domain": {"kind": "integer_interval", "lower": 0, "upper": 15}}
    if family == "bounded_quadratic_equation":
        # On nonnegative integers (x+a)(x+1) is strictly increasing, so the
        # target product has exactly one solution, x=b, in the stated domain.
        return {"kind": "scalar_condition", "unit": "unitless", "nodes": [
            {"kind": "variable"}, _literal(a), _binary("add", 0, 1),
            _literal(1), _binary("add", 0, 3), _binary("mul", 2, 4),
            _literal((b + a) * (b + 1)),
        ], "condition": {"left": 5, "relation": "eq", "right": 6},
            "selection": "any_satisfying",
            "domain": {"kind": "integer_interval", "lower": 0, "upper": 15}}
    if family == "bounded_rational_equation":
        # (x+a)/(x+1) strictly decreases on nonnegative integers because
        # a > 1. Equality with its value at b therefore has one solution.
        return {"kind": "scalar_condition", "unit": "unitless", "nodes": [
            {"kind": "variable"}, _literal(a), _binary("add", 0, 1),
            _literal(1), _binary("add", 0, 3), _binary("div", 2, 4),
            _literal(b + a), _literal(b + 1), _binary("div", 6, 7),
        ], "condition": {"left": 5, "relation": "eq", "right": 8},
            "selection": "any_satisfying",
            "domain": {"kind": "integer_interval", "lower": 0, "upper": 15}}
    if family == "bounded_two_root_minimum":
        # Exactly two roots lie in the stated domain: b and b+a. Unlike the
        # unique-solution families, the learner must identify both and apply
        # the explicit minimum selection to distinguish the answer.
        return {"kind": "scalar_condition", "unit": "unitless", "nodes": [
            {"kind": "variable"}, _literal(b), _binary("sub", 0, 1),
            _literal(b + a), _binary("sub", 0, 3), _binary("mul", 2, 4),
            _literal(0),
        ], "condition": {"left": 5, "relation": "eq", "right": 6},
            "selection": "minimum",
            "domain": {"kind": "integer_interval", "lower": 0, "upper": b + a + 2}}
    if family == "bounded_quadratic_maximum":
        # x(x+a) is strictly increasing on this nonnegative interval. The
        # greatest integer satisfying its bound is therefore x=b.
        return {"kind": "scalar_condition", "unit": "unitless", "nodes": [
            {"kind": "variable"}, _literal(a), _binary("add", 0, 1),
            _binary("mul", 0, 2), _literal(b * (b + a)),
        ], "condition": {"left": 3, "relation": "le", "right": 4},
            "selection": "maximum",
            "domain": {"kind": "integer_interval", "lower": b - 3, "upper": b + 3}}
    if family == "bounded_linear_budget_maximum":
        # Distribute and collect terms in a(x+2)+x <= a(b+2)+b. Since a+1
        # is positive, b is the unique greatest satisfying integer.
        return {"kind": "scalar_condition", "unit": "unitless", "nodes": [
            _literal(a), {"kind": "variable"}, _literal(2),
            _binary("add", 1, 2), _binary("mul", 0, 3), _binary("add", 4, 1),
            _literal(a * (b + 2) + b),
        ], "condition": {"left": 5, "relation": "le", "right": 6},
            "selection": "maximum",
            "domain": {"kind": "integer_interval", "lower": b - 3, "upper": b + 3}}
    if family == "bounded_solution_count":
        # Distribution reduces a(x+2) - (a-1)x <= b+2a to x <= b. The
        # eight-integer domain straddles b, and its varying left span makes
        # the code-owned count 2..6. The learner counts solutions instead of
        # selecting an extremal x as in the other slot-two families.
        left_span = 1 + a % 5
        return {"kind": "scalar_condition", "unit": "unitless", "nodes": [
            _literal(a), {"kind": "variable"}, _literal(2),
            _binary("add", 1, 2), _binary("mul", 0, 3),
            _literal(a - 1), _binary("mul", 5, 1), _binary("sub", 4, 6),
            _literal(b + 2 * a),
        ], "condition": {"left": 7, "relation": "le", "right": 8},
            "selection": "count_satisfying",
            "domain": {"kind": "integer_interval", "lower": b - left_span,
                       "upper": b + 7 - left_span}}
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


@lru_cache(maxsize=3)
def _inventory_rows(slot: int) -> tuple[tuple[str, dict[str, Any], str, str, str], ...]:
    """Compile the finite inventory once, including exact stem and answer."""
    from quantitative_authoring import _constructed_candidate

    return tuple(
        (family, task, learner["prompt"], _normalized_stem_identity(learner["prompt"]),
         learner["expectedAnswer"])
        for family in SLOT_FAMILIES[slot]
        for a in OPERANDS
        for b in (OPERANDS if slot == 0 else BOUNDARIES)
        for task in (flat_task(slot, {"family": family, "a": a, "b": b}),)
        for learner in (_constructed_candidate(task).content(),)
    )


@lru_cache(maxsize=3)
def _inventory(slot: int) -> tuple[tuple[str, dict[str, Any], str, str], ...]:
    """Keep the stable four-field inventory view for existing replay tools."""
    return tuple((family, task, prompt, identity)
                 for family, task, prompt, identity, _ in _inventory_rows(slot))


def canonical_variant_identities() -> frozenset[str]:
    """All code-owned numeric stems that a durable bank can recognize."""
    return frozenset(identity for slot in range(3)
                     for _, _, _, identity in _inventory(slot))


@lru_cache(maxsize=1)
def historical_variant_identity_map() -> dict[str, str]:
    """Map the released one-sided linear frame to its current variant.

    The bounded-equation frame gained distribution on both sides in f48440e.
    Older ready/claimed questions still belong to the same family and operand
    pair even though their exact stems no longer occur in the current inventory.
    Projecting them onto current identities preserves full-bank novelty after
    a source upgrade without admitting arbitrary historical prose as a block.
    """
    from quantitative_authoring import _constructed_candidate

    variants = {}
    for a in OPERANDS:
        for b in BOUNDARIES:
            offset = a + 3
            old_task = {
                "kind": "scalar_condition", "unit": "unitless", "nodes": [
                    _literal(a), {"kind": "variable"}, _binary("mul", 0, 1),
                    _literal(offset), _binary("add", 2, 3),
                    _literal(a * b + offset),
                ],
                "condition": {"left": 4, "relation": "eq", "right": 5},
                "selection": "any_satisfying",
                "domain": {"kind": "integer_interval", "lower": 0, "upper": 15},
            }
            prompt = _constructed_candidate(old_task).content()["prompt"]
            current_task = flat_task(1, {"family": FAMILIES[1], "a": a, "b": b})
            current_prompt = _constructed_candidate(current_task).content()["prompt"]
            variants[_normalized_stem_identity(prompt)] = _normalized_stem_identity(current_prompt)
    return variants


def select_novel_task(
    slot: int, source_task: dict, *, existing_prompts: tuple[str, ...],
    blocked_fingerprints: tuple[str, ...], fingerprint_version: int,
    blocked_variant_identities: tuple[str, ...] = (),
) -> dict[str, Any]:
    """Prefer an unseen solve structure, then a fresh parameterization.

    Prefer the least-used assigned-slot family. Within an equally used family,
    prefer operand pairs and proven answers that have appeared less often across
    the full bank, then prefer the source family. The inventory is compiled,
    and every candidate passes exact-stem and fingerprint checks.
    """

    if (type(slot) is not int or slot not in (0, 1, 2)
            or type(source_task) is not dict or type(existing_prompts) is not tuple
            or any(type(prompt) is not str for prompt in existing_prompts)
            or type(blocked_fingerprints) is not tuple
            or any(type(value) is not str for value in blocked_fingerprints)
            or type(blocked_variant_identities) is not tuple
            or any(type(identity) is not str for identity in blocked_variant_identities)
            or not set(blocked_variant_identities) <= canonical_variant_identities()):
        raise MappedQuantitativeFamilyError("Invalid quantitative novelty input.")
    try:
        _stem_fingerprint("", version=fingerprint_version)
    except ValueError as error:
        raise MappedQuantitativeFamilyError("Invalid fingerprint version.") from error
    inventory = _inventory_rows(slot)
    try:
        source_index = next(index for index, (_, task, _, _, _) in enumerate(inventory)
                            if task == source_task)
    except StopIteration as error:
        raise MappedQuantitativeFamilyError("Source task is outside its assigned family.") from error
    blocked = {_normalized_stem_identity(prompt) for prompt in existing_prompts}
    blocked.update(blocked_variant_identities)
    fingerprints = set(blocked_fingerprints)
    per_family = len(OPERANDS) * (len(OPERANDS) if slot == 0 else len(BOUNDARIES))
    second_values = OPERANDS if slot == 0 else BOUNDARIES

    def operands(index: int) -> tuple[int, int]:
        offset = index % per_family
        return OPERANDS[offset // len(second_values)], second_values[offset % len(second_values)]

    used = [
        (index, family, answer) for index, (family, _, prompt, identity, answer) in enumerate(inventory)
        if identity in blocked
        or _stem_fingerprint(prompt, version=fingerprint_version) in fingerprints
    ]
    family_use_counts = Counter(family for _, family, _ in used)
    pair_use_counts = Counter(operands(index) for index, _, _ in used)
    answer_use_counts = Counter(answer for _, _, answer in used)
    first_use_counts = Counter(operands(index)[0] for index, _, _ in used)
    second_use_counts = Counter(operands(index)[1] for index, _, _ in used)
    source_family = inventory[source_index][0]
    eligible = [
        (index, family, task)
        for index, (family, task, prompt, identity, _) in enumerate(inventory)
        if identity not in blocked
        and _stem_fingerprint(prompt, version=fingerprint_version) not in fingerprints
    ]
    if eligible:
        return copy.deepcopy(min(eligible, key=lambda row: (
            family_use_counts[row[1]],
            # Repeating operands or the same proven answer across
            # different families still makes a bank feel like a reworded quiz.
            # Family balancing stays first; these counts only break ties.
            pair_use_counts[operands(row[0])],
            answer_use_counts[inventory[row[0]][4]],
            second_use_counts[operands(row[0])[1]],
            first_use_counts[operands(row[0])[0]],
            row[1] != source_family,
            (row[0] % per_family - source_index % per_family
             - (1 if row[1] != source_family else 0)) % per_family,
        ))[2])
    raise MappedQuantitativeFamilyError("Quantitative family inventory exhausted.")
