"""Reproduce the post-lock key, slot, proof and difficulty join offline."""

from fractions import Fraction
import hashlib
import itertools
import json
from pathlib import Path
import re

from agreement_task_constructor import compile_question as compile_agreement
from quantitative_task_compiler import compile_question as compile_numeric

HERE = Path(__file__).resolve().parent
EXPECTED_HASHES = {
    "plan.json": "d7f257343300ac5765d3389104260ac62c2f42f8349c4201af751f230d753dd6",
    "capture.json": "f8a912da0c29df783303d9afca5f0af0b559408f80ff6b37eae7755a285ff145",
    "official-worksheet.json": "e0896bdcf33c763fa9f27b4f0bee79aa364d8a51d91cc9464ae6f86114e62721",
    "official-RUBRIC.md": "0ab4d3c62d3a0212fea5bf80c2d64a31ad4281e235af17b2b5b56ab35aacebd2",
    "blind-private-returned_output.json": "02dcea50fb61141daafe6a8c5e428e7f36ffe6b23e97ca8f0dec1501b8594509",
    "blind-review-a.json": "2424af66093316eecd26ceaf17fdc76f56e90956a3785adb6b494b815ac9b86a",
    "blind-review-b.json": "1350cf9288cc5f603ae474fbb834c8221cd5b771513c4295c34fcb7c0a0cdf16",
}
LEARNER_FIELDS = ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations")
PAIRS = {"".join(pair) for pair in itertools.combinations("ABCD", 2)}
LABEL_REFERENCE = re.compile(r"\b(?:choice|option|answer)\s+[ABCD]\b", re.IGNORECASE)


def load_checked(name):
    raw = (HERE / name).read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXPECTED_HASHES[name]:
        raise ValueError(f"Locked {name} hash changed.")
    return json.loads(raw) if name.endswith(".json") else raw.decode()


def review_pairs(item, reviewer):
    if reviewer == "a":
        pairs = {"".join(row["choices"]): row for row in item["six_choice_pairs"]}
    else:
        pairs = {row["pair"]: row for row in item["choice_pairs"]}
    if (set(pairs) != PAIRS or any(row["equivalent"] is not False
                                    or row["meaningfully_distinct"] is not True
                                    for row in pairs.values())):
        raise ValueError("A reviewer did not pass all six distinct choice pairs.")
    return len(pairs)


def audit():
    plan = load_checked("plan.json")
    capture = load_checked("capture.json")
    worksheet = load_checked("official-worksheet.json")
    load_checked("official-RUBRIC.md")
    private = load_checked("blind-private-returned_output.json")
    reviews = {label: load_checked(f"blind-review-{label}.json") for label in "ab"}
    if (capture["plan"] != plan or capture["plan_sha256"] != EXPECTED_HASHES["plan.json"]
            or private["capture_sha256"] != EXPECTED_HASHES["capture.json"]
            or private["worksheet_sha256"] != EXPECTED_HASHES["official-worksheet.json"]
            or worksheet["requested_slots"] != 5 or len(worksheet["items"]) != 5
            or capture["summary"]["returned_questions"] != 5
            or capture["summary"]["within_execute_deadline"] is not True):
        raise ValueError("Prespecified five-slot capture or worksheet drifted.")
    ids = {item["id"] for item in worksheet["items"]}
    if ids != set(private["mapping"]):
        raise ValueError("Private map and worksheet IDs differ.")
    for label, review in reviews.items():
        if (review["worksheet_sha256"] != EXPECTED_HASHES["official-worksheet.json"]
                or review["rubric_sha256"] != EXPECTED_HASHES["official-RUBRIC.md"]
                or review["requested_slots"] != 5
                or {item["id"] for item in review["items"]} != ids):
            raise ValueError(f"Review {label} is not the locked five-item worksheet.")
    job = capture["jobs"][0]
    returned = dict(zip(job["returned_slot_ordinals"], job["returned"], strict=True))
    provenance = dict(zip(job["returned_slot_ordinals"], job["returned_provenance"], strict=True))
    if sorted(returned) != list(range(5)) or sorted(provenance) != list(range(5)):
        raise ValueError("Returned slot provenance changed.")
    model_review_text = capture["calls"][2]["response"]["output"]["message"]["content"][0]["text"]
    model_reviews = json.loads(model_review_text)["reviews"]
    by_id = {label: {item["id"]: item for item in review["items"]} for label, review in reviews.items()}
    worksheet_by_id = {item["id"]: item for item in worksheet["items"]}
    slots = []
    for opaque, binding in private["mapping"].items():
        slot = binding["original_slot"]
        row, source = returned[slot], provenance[slot]
        rebuilt = (compile_numeric(source["spec"]) if slot < 3
                   else compile_agreement(source["task"], ordinal=slot))
        field_match = all(row[field] == rebuilt[field] == source["learner"][field]
                          for field in LEARNER_FIELDS)
        if not field_match:
            raise ValueError(f"Slot {slot} learner fields changed from code proof.")
        if (set(row["choiceExplanations"]) != set(row["choices"])
                or row["choices"].count(row["expectedAnswer"]) != 1
                or LABEL_REFERENCE.search(row["explanation"])
                or any(LABEL_REFERENCE.search(text) for text in row["choiceExplanations"].values())):
            raise ValueError(f"Slot {slot} feedback is incomplete or position-bound.")
        display = worksheet_by_id[opaque]
        if display["stem"] != row["prompt"]:
            raise ValueError(f"Slot {slot} worksheet stem changed.")
        choices = {label: row["choices"][index] for label, index in
                   zip("ABCD", binding["display_to_source_index"], strict=True)}
        if display["choices"] != choices:
            raise ValueError(f"Slot {slot} display permutation changed.")
        key = binding["correct_display_label"]
        if choices[key] != row["expectedAnswer"]:
            raise ValueError(f"Slot {slot} sealed key does not match learner key.")
        ratings = {}
        for label in "ab":
            review = by_id[label][opaque]
            if review["answer"] != key or review["stem_self_contained"] is not True:
                raise ValueError(f"Slot {slot} reviewer {label} did not support the key/stem.")
            review_pairs(review, label)
            ratings[label] = review["difficulty_1_to_5"]
        assignment = plan["mapped_assignment"]["assignments"][0 if slot < 3 else 1]
        if row["skillID"] != assignment[0] or row["objectiveID"] != assignment[1]:
            raise ValueError(f"Slot {slot} objective assignment drifted.")
        if slot < 3:
            assert row["verificationPolicyRevision"] == 8
        else:
            assert row["verificationPolicyRevision"] == 10
        slots.append({"original_slot": slot, "opaque_id": opaque,
                      "key": row["expectedAnswer"], "display_key": key,
                      "policy_revision": row["verificationPolicyRevision"],
                      "reviewer_difficulties": ratings,
                      "model_reviewer_difficulty": model_reviews[str(slot)]["difficulty"],
                      "returned_difficulty_metadata": row["difficulty"],
                      "learner_fields_recompiled_exactly": field_match,
                      "choice_feedback_complete_and_position_free": True,
                      "objective_assignment_matches": True})
    slots.sort(key=lambda item: item["original_slot"])
    # Independent arithmetic spot checks make the code-recompile comparison
    # more than a round trip through the same compiler implementation.
    independent_numeric = [str((Fraction(3, 4) + Fraction(5, 6)) * 8),
                           str(Fraction(9, 4) - Fraction(2, 3) + Fraction(1, 2)),
                           str(max(x for x in range(1, 11) if 4 * x - 3 <= 25))]
    if [returned[i]["expectedAnswer"] for i in range(3)] != independent_numeric:
        raise ValueError("Independent arithmetic solutions disagree.")
    level_two_consensus = [item["original_slot"] for item in slots
                           if list(item["reviewer_difficulties"].values()) == [2, 2]]
    return {"kind": "post_lock_offline_audit", "source_commit": plan["candidate_source_revision"],
            "capture_sha256": EXPECTED_HASHES["capture.json"],
            "worksheet_sha256": EXPECTED_HASHES["official-worksheet.json"],
            "review_a_sha256": EXPECTED_HASHES["blind-review-a.json"],
            "review_b_sha256": EXPECTED_HASHES["blind-review-b.json"],
            "mechanical_return": "5/5_original_slots", "provider_calls": len(capture["calls"]),
            "execute_elapsed_seconds": capture["summary"]["execute_elapsed_seconds"],
            "all_25_learner_fields_exactly_recompiled": True,
            "both_reviewers_match_all_five_keys": True,
            "both_reviewers_find_all_30_pairs_distinct": True,
            "blind_level_two_consensus_slots": level_two_consensus,
            "blind_level_two_consensus_count": len(level_two_consensus),
            "prespecified_level_two_content_gate": "FAIL" if len(level_two_consensus) < 5 else "PASS",
            "slots": slots}


if __name__ == "__main__":
    print(json.dumps(audit(), ensure_ascii=False, allow_nan=False, indent=2))
