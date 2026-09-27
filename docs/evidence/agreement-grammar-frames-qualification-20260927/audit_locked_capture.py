"""Reproduce the post-lock slot, answer, proof, feedback and review join offline."""

from fractions import Fraction
import hashlib
import itertools
import json
from pathlib import Path
import re

from agreement_task_constructor import (
    _select_novel_task,
    compile_question as compile_agreement,
)
from quantitative_task_compiler import compile_question as compile_numeric


HERE = Path(__file__).resolve().parent
EXPECTED_HASHES = {
    "plan.json": "23c3c0bca2ecfc185ca5998812c3c32bd89e1bec5a939260f6877e449664e742",
    "capture.json": "de6c6c160fbf36772e78317f060062f8955433f0d850f384f879482f3536dc4f",
    "official-worksheet.json": "92a3be8c3a9508866ce0114111adf5083f61aa1806fc66619f1923fe84607ad0",
    "official-RUBRIC.md": "0ab4d3c62d3a0212fea5bf80c2d64a31ad4281e235af17b2b5b56ab35aacebd2",
    "blind-private-returned_output.json": "3381d47820035f066b0f9dda3b189f3420ae5ecd30ea71108ede8a65ddfcf739",
    "blind-review-a.json": "13e10433e5a94ae09854aeb4d2b435a150b34550591a35b4c0aeeb2e34c9534a",
    "blind-review-b.json": "da3d43136d149009c0b2d71487f9e58ba5ceeb815e00892baa5874eaf974e22e",
}
LEARNER_FIELDS = ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations")
PAIRS = {"-".join(pair) for pair in itertools.combinations("ABCD", 2)}
LABEL_REFERENCE = re.compile(r"\b(?:choice|option|answer)\s+[ABCD]\b", re.IGNORECASE)


def checked(name):
    raw = (HERE / name).read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXPECTED_HASHES[name]:
        raise ValueError(f"Locked {name} hash changed.")
    return json.loads(raw) if name.endswith(".json") else raw.decode()


def review_pairs(item, reviewer):
    rows = item["choice_pairs"]
    if reviewer == "a":
        if (type(rows) is not list or len(rows) != 6
                or {row["pair"] for row in rows} != PAIRS
                or any(row["meaningfully_distinct"] is not True for row in rows)):
            raise ValueError("Reviewer A did not find all six pairs distinct.")
    elif (type(rows) is not dict or set(rows) != PAIRS
          or any(not value.startswith("meaningfully_distinct") for value in rows.values())):
        raise ValueError("Reviewer B did not find all six pairs distinct.")
    return 6


def independently_solve_numeric(spec):
    def value(node):
        if "value" in node:
            return Fraction(node["value"])
        left, right = value(node["left"]), value(node["right"])
        return {
            "add": lambda: left + right,
            "sub": lambda: left - right,
            "mul": lambda: left * right,
            "div": lambda: left / right,
        }[node["op"]]()

    if spec["kind"] == "exact_value":
        return str(value(spec["expression"]))
    if spec["kind"] == "scalar_condition":
        condition = spec["condition"]

        def at(node, x):
            if "variable" in node:
                if node["variable"] != "x":
                    raise ValueError("Unexpected variable.")
                return Fraction(x)
            if "value" in node:
                return Fraction(node["value"])
            left, right = at(node["left"], x), at(node["right"], x)
            return {"add": lambda: left + right, "sub": lambda: left - right,
                    "mul": lambda: left * right, "div": lambda: left / right}[node["op"]]()

        if condition["relation"] != "gt" or spec["selection"] != "minimum":
            raise ValueError("Unexpected numeric selection or comparison.")
        satisfying = [x for x in range(spec["domain"]["lower"], spec["domain"]["upper"] + 1)
                      if at(condition["left"], x) > at(condition["right"], x)]
        return str(min(satisfying))
    raise ValueError("Unsupported numeric spec in locked capture.")


def audit():
    plan, capture = checked("plan.json"), checked("capture.json")
    worksheet, private = checked("official-worksheet.json"), checked("blind-private-returned_output.json")
    checked("official-RUBRIC.md")
    reviews = {label: checked(f"blind-review-{label}.json") for label in "ab"}
    if (capture["plan"] != plan or capture["plan_sha256"] != EXPECTED_HASHES["plan.json"]
            or private["capture_sha256"] != EXPECTED_HASHES["capture.json"]
            or private["plan_sha256"] != EXPECTED_HASHES["plan.json"]
            or private["worksheet_sha256"] != EXPECTED_HASHES["official-worksheet.json"]
            or capture["status"] != "completed_pending_review"
            or capture["summary"]["returned_questions"] != 5
            or capture["summary"]["within_execute_deadline"] is not True
            or capture["summary"]["attempted_calls"] != 3
            or capture["summary"]["expected_three_call_sequence_satisfied"] is not True
            or len(capture["calls"]) != 3 or len(capture["call_slots"]) != 6
            or [slot["status"] for slot in capture["call_slots"]] !=
            ["completed"] * 3 + ["unattempted"] * 3
            or len(capture["original_jobs"]) != 1 or len(capture["jobs"]) != 1
            or worksheet["requested_slots"] != 5 or len(worksheet["items"]) != 5):
        raise ValueError("Frozen one-pass, three-call or five-slot capture drifted.")
    expected_stages = [plan["initial_author_contract_name"],
                       "complete_choice_solver_v5_n2", "authored_solution_reviewer_v3_n5"]
    if [call["stage"] for call in capture["calls"]] != expected_stages:
        raise ValueError("Expected author/solver/reviewer call order drifted.")
    for path, expected in plan["source_hashes"].items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest() != expected:
            raise ValueError(f"Pinned source path changed: {path}")
    ids = {item["id"] for item in worksheet["items"]}
    if len(ids) != 5 or ids != set(private["mapping"]):
        raise ValueError("Worksheet and sealed mapping IDs differ.")
    for label, review in reviews.items():
        if {item["id"] for item in review["items"]} != ids:
            raise ValueError(f"Locked reviewer {label} did not cover exact worksheet IDs.")
    if reviews["a"]["scope"]["unblinded_material_consulted"] is not False or \
            reviews["b"]["locked_before_answer_map_reveal"] is not True:
        raise ValueError("Reviewers did not attest a keyless lock.")
    job = capture["jobs"][0]
    returned = dict(zip(job["returned_slot_ordinals"], job["returned"], strict=True))
    provenance = dict(zip(job["returned_slot_ordinals"], job["returned_provenance"], strict=True))
    if sorted(returned) != list(range(5)) or sorted(provenance) != list(range(5)) or \
            [(item["ordinal"], item["status"]) for item in capture["original_jobs"][0]["slots"]] != \
            [(index, "returned") for index in range(5)]:
        raise ValueError("Original slots or provenance changed.")
    display_by_id = {item["id"]: item for item in worksheet["items"]}
    review_by_id = {label: {item["id"]: item for item in review["items"]}
                    for label, review in reviews.items()}
    model_text = capture["calls"][2]["response"]["output"]["message"]["content"][0]["text"]
    model_reviews = json.loads(model_text)["reviews"]
    slots = []
    for opaque, binding in private["mapping"].items():
        slot = binding["original_slot"]
        row, source = returned[slot], provenance[slot]
        if slot < 3:
            rebuilt = compile_numeric(source["spec"])
            independent_key = independently_solve_numeric(source["spec"])
        else:
            task, exhausted = _select_novel_task(
                source["author_task"], slot, tuple(source["novelty_prompts"]),
                tuple(source["blocked_variant_identities"]))
            if task != source["task"] or exhausted != source["novelty_exhausted"]:
                raise ValueError(f"Agreement slot {slot} novelty selection proof changed.")
            rebuilt = compile_agreement(source["task"], ordinal=slot)
            independent_key = {3: "checks; practice", 4: "receives; prepare"}[slot]
        if any(row[field] != rebuilt[field] or row[field] != source["learner"][field]
               for field in LEARNER_FIELDS):
            raise ValueError(f"Slot {slot} learner fields diverged from trusted compiler.")
        if (row["expectedAnswer"] != independent_key
                or row["choices"].count(independent_key) != 1
                or set(row["choiceExplanations"]) != set(row["choices"])
                or LABEL_REFERENCE.search(row["explanation"])
                or any(LABEL_REFERENCE.search(text) for text in row["choiceExplanations"].values())):
            raise ValueError(f"Slot {slot} answer or choice-specific teaching failed.")
        indices = binding["display_to_source_index"]
        if sorted(indices) != list(range(4)):
            raise ValueError("Display choice mapping is not a permutation.")
        display = display_by_id[opaque]
        expected_display = {label: row["choices"][index]
                            for label, index in zip("ABCD", indices, strict=True)}
        key = binding["correct_display_label"]
        if (display["stem"] != row["prompt"] or display["choices"] != expected_display
                or expected_display[key] != independent_key):
            raise ValueError(f"Worksheet item {opaque} changed under display permutation.")
        assignment = plan["mapped_assignment"]["assignments"][0 if slot < 3 else 1]
        policy = 8 if slot < 3 else 10
        if (row["skillID"] != assignment[0] or row["objectiveID"] != assignment[1]
                or row["objective"] != assignment[3]
                or row["verificationPolicyRevision"] != policy):
            raise ValueError(f"Slot {slot} trusted objective or policy changed.")
        ratings = {}
        for label in "ab":
            review = review_by_id[label][opaque]
            if review["defensible_answer_letters"] != [key] or \
                    review["stem_self_contained"] is not True:
                raise ValueError(f"Reviewer {label} did not endorse slot {slot} key/stem.")
            review_pairs(review, label)
            ratings[label] = review["difficulty_1_to_5"]
        slots.append({"original_slot": slot, "opaque_id": opaque,
                      "correct_display_label": key, "key": independent_key,
                      "policy_revision": policy,
                      "reviewer_difficulties": ratings,
                      "model_reviewer_difficulty": model_reviews[str(slot)]["difficulty"],
                      "returned_difficulty_metadata": row["difficulty"],
                      "all_five_learner_fields_exactly_recompiled": True,
                      "independent_key_check": True,
                      "feedback_complete_and_position_free": True,
                      "target_objective_assignment_matches": True})
    slots.sort(key=lambda row: row["original_slot"])
    passed_slots = [row["original_slot"] for row in slots
                    if all(level >= 2 for level in row["reviewer_difficulties"].values())]
    return {"kind": "locked_post_trial_offline_audit",
            "source_commit": plan["candidate_source_revision"],
            "locked_file_hashes": EXPECTED_HASHES,
            "mechanical_return": "5/5_original_slots",
            "three_expected_converse_calls": True,
            "six_reservation_slots_bounded": True,
            "execute_elapsed_seconds": capture["summary"]["execute_elapsed_seconds"],
            "all_25_learner_fields_exactly_recompiled": True,
            "five_independently_rechecked_keys": True,
            "both_reviewers_match_all_five_keys": True,
            "both_reviewers_find_all_30_pairs_distinct": True,
            "per_reviewer_minimum_difficulty_2_passed_slots": passed_slots,
            "per_reviewer_minimum_difficulty_2_passed_count": len(passed_slots),
            "prespecified_content_gate": "FAIL" if len(passed_slots) < 5 else "PASS",
            "slots": slots}


if __name__ == "__main__":
    print(json.dumps(audit(), ensure_ascii=False, allow_nan=False, indent=2))
