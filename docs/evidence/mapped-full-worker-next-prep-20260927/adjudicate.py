"""Apply the prespecified five-slot gate after locked blind and teaching review."""

import hashlib
import json
from pathlib import Path

from mechanical_audit import audit as audit_mechanics
from qualification_guard import official_gate
from verify_blind_reviews import verify as verify_blind_reviews

HERE = Path(__file__).resolve().parent
TEACHING_SHA256 = "cc0643dc1dd6588fa06a2220cc737a707a4c1a31d7e704e6e05502d224c9cb51"
QUANT_ID = "11111111-1111-4111-8111-111111111111"
ENGLISH_ID = "22222222-2222-4222-8222-222222222222"


def adjudicate():
    mechanics, blind = audit_mechanics(), verify_blind_reviews()
    teaching_raw = (HERE / "teaching-audit.md").read_bytes()
    if hashlib.sha256(teaching_raw).hexdigest() != TEACHING_SHA256:
        raise ValueError("Post-lock teaching audit changed")
    capture = json.loads((HERE / "capture.json").read_bytes())
    job = capture["jobs"][0]
    returned = job["returned"]
    counts = {QUANT_ID: 0, ENGLISH_ID: 0}
    for question in returned:
        counts[question["skillID"]] += 1
    policies = [question["verificationPolicyRevision"] for question in returned]
    if (mechanics["returned_original_slots"] != [0, 1, 2, 3, 4]
            or blind["both_reviewers_correct_single_keys"] != 5
            or blind["meaningfully_distinct_pairs_per_reviewer"] != 30
            or blind["both_reviewers_self_contained"] != 5):
        raise ValueError("Supporting mechanical or blind audit failed")
    result = {
        "returned_original_slots": job["returned_slot_ordinals"],
        "verification_policy_revisions_by_slot": policies,
        "provider_calls": len(capture["calls"]),
        "elapsed_seconds": capture["summary"]["execute_elapsed_seconds"],
        "within_execute_deadline": capture["summary"]["within_execute_deadline"],
        "requested_skill_allocation_exact": counts == {QUANT_ID: 3, ENGLISH_ID: 2},
        "independent_keys_pass": blind["both_reviewers_correct_single_keys"] == 5,
        "all_six_choice_pairs_pass": blind["meaningfully_distinct_pairs_per_reviewer"] == 30,
        "teaching_audit_pass": True,
        "blind_reviews_locked": True,
        "blind_reviews_pass": blind["both_reviewers_self_contained"] == 5,
        "unresolved_content_uncertainty": 0,
    }
    if policies[3:] != [10, 10] or blind["difficulty_review_a"][3] not in (2, 3):
        raise ValueError("English policy or observed difficulty fell outside the frozen range")
    return {
        "prespecified_gate_result": result,
        "qualified_under_prespecified_single_trial_gate": official_gate(result),
        "capture_status_remains": capture["status"],
        "capture_qualified_field_remains": capture["summary"]["qualified"],
        "manual_teaching_audit_sha256": TEACHING_SHA256,
        "manual_judgment": "Five explanations and 20 literal-choice feedback entries are mathematically/grammatically sound and complete; see teaching-audit.md.",
        "resolved_difficulty_difference": "Blind reviewer A rated original slot 3 level 3 and B level 2; both are in frozen allowed 2–3 range.",
        "known_batch_novelty_limitation": "Both reviewers flagged English slots 3 and 4 as strong near-duplicates in two-blank agreement format, despite different subject structures.",
        "population_reliability_established": False,
        "bank_queue_or_deployment_qualified": False,
    }


if __name__ == "__main__":
    record = adjudicate()
    with (HERE / "post-lock-adjudication.json").open("x") as stream:
        json.dump(record, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps(record, indent=2))
