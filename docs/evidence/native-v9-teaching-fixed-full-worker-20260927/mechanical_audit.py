"""Offline proof and provenance audit for the single captured 3:2 worker run."""

import hashlib
import json
from fractions import Fraction
from itertools import combinations
from pathlib import Path

HERE = Path(__file__).resolve().parent
CAPTURE_SHA256 = "a880fcf748b75f2c9ebcd7170edeb412b4f83712602ee3becdee7de929bf874a"
PLAN_SHA256 = "5a6b2a1e6eb63c5803ceb8e155fe29d486bea0dc7c5ac2d5081a030fe8858003"
FIELDS = ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def value(node, x=None):
    if "value" in node:
        return Fraction(node["value"])
    if node.get("variable") == "x":
        if x is None:
            raise ValueError("Missing variable assignment")
        return Fraction(x)
    left, right = value(node["left"], x), value(node["right"], x)
    return {"add": lambda: left + right, "sub": lambda: left - right,
            "mul": lambda: left * right, "div": lambda: left / right}[node["op"]]()


def condition(spec, x):
    test = spec["condition"]
    left, right = value(test["left"], x), value(test["right"], x)
    return {"eq": lambda: left == right, "ne": lambda: left != right,
            "lt": lambda: left < right, "le": lambda: left <= right,
            "gt": lambda: left > right, "ge": lambda: left >= right}[test["relation"]]()


def numeric_proof(spec, question):
    key = Fraction(question["expectedAnswer"])
    choices = [Fraction(choice) for choice in question["choices"]]
    if len(set(choices)) != 4:
        raise ValueError("Numeric choices are semantically duplicated")
    if spec["kind"] == "exact_value":
        answer = value(spec["expression"])
        if key != answer or choices.count(answer) != 1:
            raise ValueError("Exact numeric answer mismatch")
        return {"kind": "exact_value", "independent_answer": str(answer)}
    domain = spec["domain"]
    full = [x for x in range(domain["lower"], domain["upper"] + 1) if condition(spec, x)]
    if not full:
        raise ValueError("No satisfying domain value")
    selected = {"minimum": min, "maximum": max}.get(spec["selection"])
    if selected is None:
        offered_true = [int(choice) for choice in choices if condition(spec, int(choice))]
        if offered_true != [int(key)] or int(key) not in full:
            raise ValueError("Offered condition has no unique correct answer")
    elif key != selected(full) or choices.count(key) != 1:
        raise ValueError("Domain extremum or offered key mismatch")
    return {"kind": "scalar_condition", "selection": spec["selection"],
            "satisfying_domain_values": full,
            "offered_truth": {str(choice): condition(spec, int(choice)) for choice in choices},
            "independent_answer": str(key)}


def audit():
    capture_path, plan_path = HERE / "capture.json", HERE / "plan.json"
    if sha(capture_path) != CAPTURE_SHA256 or sha(plan_path) != PLAN_SHA256:
        raise ValueError("Frozen capture or plan changed")
    capture, plan = json.loads(capture_path.read_text()), json.loads(plan_path.read_text())
    if capture["plan"] != plan or capture["plan_sha256"] != PLAN_SHA256:
        raise ValueError("Capture is detached from the frozen plan")
    if capture["summary"]["returned_questions"] != 5 or len(capture["calls"]) != 3:
        raise ValueError("Official call or return counts changed")
    job = capture["jobs"][0]
    if job["returned_slot_ordinals"] != [0, 1, 2, 3, 4]:
        raise ValueError("Original slot identities changed")
    if [slot["status"] for slot in capture["original_jobs"][0]["slots"]] != [
        "returned", "returned", "returned", "returned", "returned"
    ]:
        raise ValueError("Unfilled original slot was lost")
    sanitized = job["passes"][0]["sanitized"]
    if len(sanitized) != 5:
        raise ValueError("Sanitizer did not receive five original candidates")
    rows = []
    for ordinal, entry in enumerate(sanitized):
        question = entry["question"]
        if entry["original_slot_ordinals"] != [ordinal]:
            raise ValueError("Candidate source slot changed")
        source = entry.get("compiled_source") or entry.get("agreement_source")
        if any(question[field] != source["learner"][field] for field in FIELDS):
            raise ValueError("Code-owned learner content changed")
        choices = question["choices"]
        if (len(choices) != 4 or len({choice.casefold().strip() for choice in choices}) != 4
                or choices.count(question["expectedAnswer"]) != 1
                or len(list(combinations(choices, 2))) != 6):
            raise ValueError("A candidate has missing, repeated or unkeyed choices")
        row = {"original_slot": ordinal, "status": capture["original_jobs"][0]["slots"][ordinal]["status"],
               "provenance_fields_match": True, "literal_choice_pairs_distinct": 6,
               "key_occurrences": 1}
        if entry.get("compiled_source"):
            row["numeric_proof"] = numeric_proof(entry["compiled_source"]["spec"], question)
        else:
            row["english_proof_type"] = "code_owned_agreement_task"
        rows.append(row)
    if any(job["returned"][i][field] != sanitized[ordinal]["question"][field]
           for i, ordinal in enumerate(job["returned_slot_ordinals"]) for field in FIELDS):
        raise ValueError("Released learner content differs from sanitized source")
    return {"capture_sha256": CAPTURE_SHA256, "plan_sha256": PLAN_SHA256,
            "original_slots": 5, "sanitized_candidates": 5, "returned_original_slots": [0, 1, 2, 3, 4],
            "unfilled_original_slots": [], "provider_calls": 3,
            "all_25_candidate_learner_fields_match_provenance": True,
            "literal_choice_pairs_checked": 30, "numeric_semantic_choice_pairs_checked": 18,
            "english_linguistic_review": "separate_locked_blind_reviews",
            "authored_teaching_review": "pending_manual_post_lock",
            "rows": rows}


if __name__ == "__main__":
    result = audit()
    path = HERE / "mechanical-audit.json"
    with path.open("x") as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps({key: value for key, value in result.items() if key != "rows"}, indent=2))
