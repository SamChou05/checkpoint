"""Reproduce the post-lock source, answer, compiler, feedback and review join offline."""

from fractions import Fraction
import hashlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import re
from unittest.mock import patch

from agreement_task_constructor import (
    _select_novel_task as select_agreement_task,
    compile_question as compile_agreement,
)
from mapped_quantitative_families import flat_task, select_novel_task
from quantitative_task_compiler import compile_question as compile_numeric


HERE = Path(__file__).resolve().parent
EXPECTED_HASHES = {
    "plan.json": "4a26cee369744fd7f6aed2e60522608b40faa0d17a99d3f65a6f493e872ad6ce",
    "capture.json": "f9e81f34f19e4829b49587c3919d77bae2595784064e063631d3515b61e009fa",
    "official-worksheet.json": "65ed30beb66ad63c7cbc85fc404d38577df6ac8c0b1f4b2b493a352f5fca33e7",
    "official-RUBRIC.md": "0ab4d3c62d3a0212fea5bf80c2d64a31ad4281e235af17b2b5b56ab35aacebd2",
    "blind-private-returned_output.json": "31ece675a9749505dd1bd42fe020a2a5018fb656d37b78b2795c0f848d623b11",
    "blind-review-a.json": "72639aff8ddacbde1233f000003e91a41e8eddb7f1e5e73a2cd6a7b8f99f3f69",
    "blind-review-b.json": "87b396c1da4e06c0c564f93e779c50031f872a5f103908b15e2c0cf775263adf",
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
    if reviewer == "a":
        rows = item["choice_pairs"]
        if (type(rows) is not list or len(rows) != 6
                or {"-".join(row["choices"]) for row in rows} != PAIRS
                or any(row["meaningfully_distinct"] is not True for row in rows)
                or item["all_six_pairs_meaningfully_distinct"] is not True):
            raise ValueError("Reviewer A did not judge all six pairs distinct.")
    else:
        rows = item["choice_pair_audit"]
        if (type(rows) is not dict or set(rows) != PAIRS
                or any(row["meaningfully_distinct"] is not True for row in rows.values())
                or item["all_six_choice_pairs_meaningfully_distinct"] is not True):
            raise ValueError("Reviewer B did not judge all six pairs distinct.")
    return 6


def independent_numeric_key(slot, family_row):
    a, b = family_row["a"], family_row["b"]
    if slot == 0:
        return str(3 * (Fraction(a, a + 1) + Fraction(b, b + 2)))
    if slot == 1:
        offset = a + 3
        domain = range(0, 16)
        satisfying = [x for x in domain if a * x + offset == a * b + offset]
        if satisfying != [b]:
            raise ValueError("Bounded equation has a changed solution set.")
        return str(b)
    if slot == 2:
        domain = range(b - 3, b + 4)
        threshold = Fraction(b, b + a)
        satisfying = [x for x in domain if Fraction(x, x + a) >= threshold]
        if min(satisfying) != b or any(x < b for x in satisfying):
            raise ValueError("Bounded ratio threshold has a changed minimum.")
        return str(b)
    raise ValueError("Unexpected quantitative original slot.")


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

    spec = importlib.util.spec_from_file_location("frozen_family_probe", HERE / "full_worker_probe.py")
    probe = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(probe)
    probe.check_plan(plan, HERE / "plan.json", EXPECTED_HASHES["plan.json"])
    raw_author = json.loads(capture["calls"][0]["response"]["output"]["message"]["content"][0]["text"])
    with patch.dict(os.environ, probe.ENVIRONMENT, clear=True):
        contract = probe.mapped_contract(plan["jobs"][0]["request"])
        adapted = json.loads(probe.native.adapt_native_response(json.dumps(raw_author), contract))
    if adapted != capture["jobs"][0]["passes"][0]["author_payload"]:
        raise ValueError("Native author adaptation changed from captured accepted payload.")

    ids = {item["id"] for item in worksheet["items"]}
    if len(ids) != 5 or ids != set(private["mapping"]):
        raise ValueError("Worksheet and sealed mapping IDs differ.")
    for label, review in reviews.items():
        if (review["worksheet_sha256"] != EXPECTED_HASHES["official-worksheet.json"]
                or review["rubric_sha256"] != EXPECTED_HASHES["official-RUBRIC.md"]
                or {item["id"] for item in review["items"]} != ids):
            raise ValueError(f"Locked reviewer {label} did not review exact worksheet.")
    job = capture["jobs"][0]
    returned = dict(zip(job["returned_slot_ordinals"], job["returned"], strict=True))
    provenance = dict(zip(job["returned_slot_ordinals"], job["returned_provenance"], strict=True))
    if (sorted(returned) != list(range(5)) or sorted(provenance) != list(range(5))
            or [(item["ordinal"], item["status"]) for item in capture["original_jobs"][0]["slots"]] !=
            [(index, "returned") for index in range(5)]):
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
            family_row = raw_author["questions"][str(slot)]
            authored = flat_task(slot, family_row)
            selected = select_novel_task(slot, authored, existing_prompts=(),
                                         blocked_fingerprints=(), fingerprint_version=1)
            if (source["author_task"] != authored or source["selected_task"] != selected
                    or authored != selected or source["novelty_prompts"] != []
                    or source["blocked_stem_fingerprints"] != []
                    or source["stem_fingerprint_version"] != 1):
                raise ValueError(f"Slot {slot} family selection provenance changed.")
            rebuilt = compile_numeric(source["spec"])
            independent_key = independent_numeric_key(slot, family_row)
        else:
            task, exhausted = select_agreement_task(
                source["author_task"], slot, tuple(source["novelty_prompts"]),
                tuple(source["blocked_variant_identities"]))
            if task != source["task"] or exhausted != source["novelty_exhausted"]:
                raise ValueError(f"Agreement slot {slot} selection provenance changed.")
            rebuilt = compile_agreement(source["task"], ordinal=slot)
            independent_key = {3: "sort; organizes", 4: "prepare; receives"}[slot]
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
                or row["objective"] != assignment[3] or row["topic"] != assignment[2]
                or row["verificationPolicyRevision"] != policy):
            raise ValueError(f"Slot {slot} trusted objective or policy changed.")
        ratings = {}
        for label in "ab":
            review = review_by_id[label][opaque]
            answer = review["best_literal_answer"] if label == "a" else review["best_answer"]
            objective_fit = (review["objective_fit"]["fits_visible_inferred_objective"]
                             if label == "a" else review["visible_objective_fit"])
            if (answer != key or review["stem_self_contained"] is not True
                    or objective_fit is not True):
                raise ValueError(f"Reviewer {label} did not endorse slot {slot} key/stem.")
            review_pairs(review, label)
            ratings[label] = review["difficulty_1_to_5"]
        slots.append({"original_slot": slot, "opaque_id": opaque,
                      "correct_display_label": key, "key": independent_key,
                      "policy_revision": policy, "reviewer_difficulties": ratings,
                      "model_reviewer_difficulty": model_reviews[str(slot)]["difficulty"],
                      "returned_difficulty_metadata": row["difficulty"],
                      "all_five_learner_fields_exactly_recompiled": True,
                      "independent_key_check": True,
                      "feedback_complete_and_position_free": True,
                      "target_objective_assignment_matches": True})
    slots.sort(key=lambda item: item["original_slot"])
    passed = [item["original_slot"] for item in slots
              if all(level >= 2 for level in item["reviewer_difficulties"].values())]
    return {"kind": "locked_post_trial_offline_audit",
            "source_commit": plan["candidate_source_revision"],
            "locked_file_hashes": EXPECTED_HASHES,
            "mechanical_return": "5/5_original_slots",
            "three_expected_converse_calls": True,
            "six_reservation_slots_bounded": True,
            "execute_elapsed_seconds": capture["summary"]["execute_elapsed_seconds"],
            "native_author_response_readapted_exactly": True,
            "all_25_learner_fields_exactly_recompiled": True,
            "five_independently_rechecked_keys": True,
            "both_reviewers_match_all_five_keys": True,
            "both_reviewers_find_all_30_pairs_distinct": True,
            "per_reviewer_minimum_difficulty_2_passed_slots": passed,
            "per_reviewer_minimum_difficulty_2_passed_count": len(passed),
            "prespecified_content_gate": "PASS" if len(passed) == 5 else "FAIL",
            "slots": slots}


if __name__ == "__main__":
    print(json.dumps(audit(), ensure_ascii=False, allow_nan=False, indent=2))
