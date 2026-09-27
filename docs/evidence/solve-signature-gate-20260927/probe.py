"""Offline solve-signature experiment for the frozen 20-question worksheet.

This is deliberately not a production selector. It reads only code-owned
constructed numeric graphs and previously locked blind review artifacts.
"""

from __future__ import annotations

from functools import lru_cache
import hashlib
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[3]
BACKEND = ROOT / "backend/bedrock-question-service"
SOURCE = ROOT / "docs/evidence/english-each-contrast-20260927"
sys.path.insert(0, str(BACKEND))

from mapped_quantitative_families import (  # noqa: E402
    BOUNDARIES, OPERANDS, SLOT_FAMILIES, flat_task,
)


def numeric_signature(task: dict) -> str:
    """Describe the solve kernel of one trusted compiled numeric task.

    The graph, not the provider family label or surface wording, supplies the
    operator topology/degree. Selection is omitted deliberately: max versus
    count after finding the same bound was a strong blind-review repetition.
    """
    nodes = task["nodes"]

    @lru_cache(maxsize=None)
    def shape(index: int) -> str:
        node = nodes[index]
        if node["kind"] == "literal":
            return "c"
        if node["kind"] == "variable":
            return "x"
        return f"{node['op']}({shape(node['left'])},{shape(node['right'])})"

    @lru_cache(maxsize=None)
    def algebra(index: int) -> tuple[int, bool]:
        node = nodes[index]
        if node["kind"] == "literal":
            return 0, False
        if node["kind"] == "variable":
            return 1, False
        left_degree, left_rational = algebra(node["left"])
        right_degree, right_rational = algebra(node["right"])
        op = node["op"]
        if op in {"add", "sub"}:
            degree = max(left_degree, right_degree)
        elif op == "mul":
            degree = left_degree + right_degree
        elif op == "div":
            degree = left_degree
        else:
            raise ValueError(f"Unknown graph operation {op!r}")
        return degree, left_rational or right_rational or (op == "div" and right_degree > 0)

    if task["kind"] == "exact_value":
        return "exact:" + shape(task["root"])
    if task["kind"] != "scalar_condition" or task["domain"]["kind"] != "integer_interval":
        raise ValueError("Not a closed mapped scalar condition")
    condition = task["condition"]
    left_degree, left_rational = algebra(condition["left"])
    right_degree, right_rational = algebra(condition["right"])
    kernel = ("rational_variable_denominator" if left_rational or right_rational
              else f"polynomial_degree_{max(left_degree, right_degree)}")
    return f"scalar:integer_interval:{condition['relation']}:{kernel}"


def main() -> None:
    answer_map = json.loads((SOURCE / "post-lock-answer-map.json").read_text())["mapping"]
    review_a = json.loads((SOURCE / "blind-review-a.json").read_text())
    review_b = json.loads((SOURCE / "blind-review-b.json").read_text())
    worksheet_sha = hashlib.sha256((SOURCE / "worksheet.json").read_bytes()).hexdigest()
    if worksheet_sha != review_a["worksheet_sha256"] or worksheet_sha != review_b["source_sha256"]:
        raise AssertionError("Blind reviews do not bind the frozen worksheet")
    signatures = {}
    for question_id, entry in answer_map.items():
        if entry["slot"] < 3:
            signatures[question_id] = numeric_signature(flat_task(entry["slot"], entry["task"]))

    observed_matches = set()
    for review, pairs_field, pair_field, strength_field, target in (
        (review_a, "all_190_cross_item_pairs", "pair", "strength", "strong"),
        (review_b, "all_190_cross_item_pair_reviews", "items", "overlap", "high"),
    ):
        if len(review[pairs_field]) != 190:
            raise AssertionError("Blind review does not cover all 190 pairs")
        top = {tuple(pair[pair_field]) for pair in review[pairs_field]
               if pair[strength_field] == target}
        matches = {tuple(pair[pair_field]) for pair in review[pairs_field]
                   if len(pair[pair_field]) == 2
                   and all(question_id in signatures for question_id in pair[pair_field])
                   and signatures[pair[pair_field][0]] == signatures[pair[pair_field][1]]}
        if matches != top:
            raise AssertionError(f"Signature/reviewer disagreement: {matches=} {top=}")
        observed_matches |= matches

    inventory_signatures = {}
    variants_checked = 0
    for slot in range(3):
        inventory_signatures[str(slot)] = {
            family: numeric_signature(flat_task(slot, {"family": family, "a": OPERANDS[0],
                                                 "b": (OPERANDS if slot == 0 else BOUNDARIES)[0]}))
            for family in SLOT_FAMILIES[slot]
        }
        for family in SLOT_FAMILIES[slot]:
            expected = inventory_signatures[str(slot)][family]
            for a in OPERANDS:
                for b in OPERANDS if slot == 0 else BOUNDARIES:
                    variants_checked += 1
                    if numeric_signature(flat_task(slot, {"family": family, "a": a, "b": b})) != expected:
                        raise AssertionError(f"Operand-dependent mechanism: {slot=} {family=}")
    if variants_checked != 832:
        raise AssertionError("Closed numeric inventory changed")

    used = set()
    batches = []
    first_failure = None
    for batch_number in range(1, 5):
        entries = [(question_id, entry) for question_id, entry in answer_map.items()
                   if entry["batch"] == batch_number]
        if len(entries) != 5 or set(entry["slot"] for _, entry in entries) != set(range(5)):
            raise AssertionError(f"Incomplete frozen batch {batch_number}")
        repeats = sorted(question_id for question_id, _ in entries
                         if question_id in signatures and signatures[question_id] in used)
        batches.append({"batch": batch_number, "numericSolveRepeats": repeats,
                        "admittedByStrictGate": not repeats})
        if repeats and first_failure is None:
            first_failure = {"batch": batch_number, "priorCompleteItems": 5 * (batch_number - 1),
                             "rejectedQuestionIDs": repeats}
        used.update(signatures[question_id] for question_id, _ in entries
                    if question_id in signatures)

    capacities = {slot: len(set(families.values())) for slot, families in inventory_signatures.items()}
    result = {
        "sourceWorksheetSha256": worksheet_sha,
        "numericVariantsChecked": variants_checked,
        "consensusTopPairs": [list(pair) for pair in sorted(observed_matches)],
        "signatureMatchesAmong190": [list(pair) for pair in sorted(observed_matches)],
        "numericMechanismsPerSlot": capacities,
        "inventorySignatures": inventory_signatures,
        "frozenBatches": batches,
        "strictGateFirstFailure": first_failure,
        "completeQuestionCapacityBeforeRepeat": min(capacities.values()) * 5,
        "targetMaximumCompleteItems": {str(target): min(target, 5 * min(capacities.values()))
                                       for target in (20, 40, 80)},
        "targetMinimumUnderfill": {str(target): target - min(target, 5 * min(capacities.values()))
                                   for target in (20, 40, 80)},
        "englishSolveGate": "not_proposed_no_consensus_strong_english_pair",
        "providerCalls": 0,
    }
    output = Path(__file__).with_name("report.json")
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: result[key] for key in (
        "numericVariantsChecked", "consensusTopPairs", "numericMechanismsPerSlot",
        "strictGateFirstFailure", "targetMaximumCompleteItems", "targetMinimumUnderfill")}, indent=2))


if __name__ == "__main__":
    main()
