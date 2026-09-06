"""Bounded truth-table checks for AI-translated conditional reasoning items.

This checks entailment, not whether the model faithfully translated English.
Translation remains subject to the answer-blind reviewer and live evaluation.
"""

import itertools
import re


def requires_logic_proof(question, request):
    context = str(request.get("goal", {})).lower()
    return ("lsat" in context or "conditional logic" in context) and bool(
        re.search(
            r"properly inferred|must follow|necessarily true|must be true",
            question["prompt"],
            re.IGNORECASE,
        )
    )


def proves_unique_answer(proof, choices, expected_answer):
    if not isinstance(proof, dict):
        return False
    atoms = proof.get("atoms")
    premises = proof.get("premises")
    claims = proof.get("choiceClaims")
    if (
        not isinstance(atoms, dict)
        or not 1 <= len(atoms) <= 6
        or any(
            not isinstance(key, str)
            or not re.fullmatch(r"[A-Z]", key)
            or not isinstance(value, str)
            or not 1 <= len(value) <= 180
            for key, value in atoms.items()
        )
        or not isinstance(premises, list)
        or not 1 <= len(premises) <= 12
        or not isinstance(claims, dict)
        or set(claims) != set(choices)
    ):
        return False

    def valid(expression, depth=0):
        if depth > 8:
            return False
        if isinstance(expression, str):
            return expression in atoms
        if not isinstance(expression, list) or not expression:
            return False
        if len(expression) == 1 and isinstance(expression[0], str):
            return expression[0] in atoms
        operator = expression[0]
        arity = {"not": 1, "and": 2, "or": 2, "implies": 2}.get(str(operator))
        return (
            arity is not None
            and len(expression) == arity + 1
            and all(valid(child, depth + 1) for child in expression[1:])
        )

    if not all(valid(expression) for expression in premises + list(claims.values())):
        return False

    def evaluate(expression, assignment):
        if isinstance(expression, str):
            return assignment[expression]
        if len(expression) == 1:
            return assignment[expression[0]]
        operator, *children = expression
        values = [evaluate(child, assignment) for child in children]
        if operator == "not":
            return not values[0]
        if operator == "and":
            return values[0] and values[1]
        if operator == "or":
            return values[0] or values[1]
        return not values[0] or values[1]

    worlds = [
        dict(zip(atoms, values))
        for values in itertools.product([False, True], repeat=len(atoms))
    ]
    possible = [
        world
        for world in worlds
        if all(evaluate(premise, world) for premise in premises)
    ]
    if not possible:
        return False
    entailed = [
        choice
        for choice, claim in claims.items()
        if all(evaluate(claim, world) for world in possible)
    ]
    return entailed == [expected_answer]
