"""Socket-free checks for the pinned synthetic 3:2 agreement request and gate."""

import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = HERE / "qualification-spec.json"
REQUEST = HERE / "request.json"
REQUEST_SHA256 = "212cea7d53ddefe17fbe8f2459705b46b871793e62e0e58b56cc11e3626e63ae"
SCHEMA_SHA256 = "a6426dd4d8cdd26a7d6fb03bbd373c8d55ab1dd79c17eab48279e3a3120d201e"
FAILED_BASELINE_SHA256 = "2bcb9b577d165b508debe70cf6d42b2cf749f006c03922650b9d154eab8ca251"


class ProtocolError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ProtocolError(message)


def canonical_hash(value):
    encoded = json.dumps(value, sort_keys=True, ensure_ascii=True,
                         allow_nan=False, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def check_draft(spec, request, *, directory=HERE):
    """Reject drift, already-created launch artifacts and a premature freeze."""
    require(spec["state"] == "draft_waiting_for_candidate", "Draft state changed.")
    require(spec["candidate_source_revision"] is None
            and spec["candidate_source_root"] is None
            and spec["candidate_source_hashes"] is None
            and spec["independent_source_review"] is None,
            "Source cannot be declared ready by this offline draft guard.")
    require(spec["baseline_failed_capture_sha256"] == FAILED_BASELINE_SHA256
            and spec["baseline_result"] == "3/5_original_slots_FAIL",
            "Failed baseline was reinterpreted.")
    require(spec["previous_v7_full_worker_capture_sha256"] ==
            "1ab308db5ea2aeedea0655a7886886c4851fbfa9278b22b5c9413cacaf45af4a"
            and spec["previous_v7_full_worker_result"] == "5/5_single_trial_PASS"
            and spec["previous_v9_author_only_capture_sha256"] ==
            "17575d5a62b1fde235c3d43c7c9bc1d9e40385466e30b973fde1ca9cf1bbc9aa"
            and spec["previous_v9_author_only_result"] ==
            "provider_and_compiler_PASS_probe_bookkeeping_FAILED_no_worker",
            "Recent v7 worker or v9 author-only predecessor was reinterpreted.")
    require(spec["request_file"] == "request.json"
            and spec["request_sha256"] == REQUEST_SHA256
            and canonical_hash(request) == REQUEST_SHA256,
            "Original normalized five-slot request changed.")
    require(request["targetCount"] == 5
            and request["requestedSkillAllocation"] == {
                "11111111-1111-4111-8111-111111111111": 3,
                "22222222-2222-4222-8222-222222222222": 2,
            }, "Original slot allocation changed.")
    contract = spec["expected_current_author_contract"]
    require(contract["native_schema_bytes"] == 2156
            and contract["native_schema_sha256"] == SCHEMA_SHA256
            and contract["name"] ==
            "question_author_constructed_mapped_families_v9_n5_56d4204a9b0238f6"
            and contract["exact_author_wire_sha256"] ==
            "994d50d46bcc75bc5d918b10f6e002ab6be29c643a15f7e120ce45f5ebeaac78",
            "Native author contract drifted.")
    limits = spec["limits"]
    require(limits["original_jobs"] == 1 and limits["original_slots"] == 5
            and limits["calls_per_job"] == 6 and limits["seconds_per_job"] == 240
            and limits["sdk_attempts_per_call"] == 1
            and limits["deadline_origin"] == "execute_capture_start_before_credentials_and_sts"
            and limits["sts_preflight_requests"] == 1
            and limits["sts_execute_requests"] == 1
            and limits["sts_total_requests"] == 2
            and limits["sts_sdk_attempts_per_request"] == 1
            and limits["hard_deadline_enforcement"] == "SIGALRM_ITIMER_REAL_one_shot"
            and limits["one_trial_execution"] is True,
            "Trial budget or cardinality drifted.")
    env = spec["environment"]
    require(env["QUESTION_MAPPED_AGREEMENT_TASKS"] == "enabled"
            and env["QUESTION_MAPPED_QUANTITATIVE_FAMILIES"] == "enabled"
            and env["BEDROCK_STRUCTURED_OUTPUT_MODE"] == "native"
            and env["BEDROCK_MODEL_ID"] == "us.anthropic.claude-sonnet-4-6"
            and env["BEDROCK_VERIFICATION_MODEL_ID"] == env["BEDROCK_MODEL_ID"]
            and env["BEDROCK_FALLBACK_MODEL_ID"] == ""
            and env["BEDROCK_CLAUDE_THINKING"] == "adaptive"
            and env["BEDROCK_CLAUDE_EFFORT"] == "high"
            and env["QUESTION_FEEDBACK_CONTRACT"] == "authored_solution",
            "Provider environment drifted.")
    gate = spec["prespecified_gate"]
    require(gate["original_slot_denominator"] == 5
            and gate["returned_original_slots_required"] == [0, 1, 2, 3, 4]
            and gate["quantitative_policy8_required"] == 3
            and gate["agreement_policy10_required"] == 2
            and gate["agreement_reviewer_difficulty_allowed"] == [2, 3]
            and gate["agreement_reviewer_difficulty_outside_allowed_rejected"] is True
            and gate["provider_calls_max"] == 6
            and gate["elapsed_seconds_max"] == 240
            and gate["execute_elapsed_seconds_max"] == 240
            and gate["whole_execute_deadline_includes_credential_export_and_identity"] is True
            and gate["topup_repair_retry_fallback_resume_allowed"] is False,
            "Prespecified result gate drifted.")
    blind = spec["blind_review"]
    require(blind["reviewers"] == 2 and blind["answer_blind"] is True
            and blind["slot_blind"] is True
            and blind["returned_output_worksheet_only_for_official_gate"] is True
            and blind["unavailable_original_slots_explicit"] is True
            and blind["keys_sources_model_ratings_rejection_reasons_hidden_until_both_reviews_locked"] is True,
            "Blind review procedure drifted.")
    require(not any((directory / name).exists() for name in (
        "plan.json", "review-approval.json", "launch-precheck.json",
        "launch-precheck-attempt.json", "capture.json")),
        "Draft must not contain launch or capture artifacts.")
    return {"state": "draft_waiting_for_candidate", "request_sha256": REQUEST_SHA256,
            "provider_calls": 0, "freeze_allowed": False, "launch_allowed": False}


def official_gate(result):
    """Pure post-run denominator check; actual evidence must derive its fields."""
    return (result.get("returned_original_slots") == [0, 1, 2, 3, 4]
            and result.get("verification_policy_revisions_by_slot") == [8, 8, 8, 10, 10]
            and type(result.get("provider_calls")) is int
            and 0 <= result["provider_calls"] <= 6
            and type(result.get("elapsed_seconds")) in (int, float)
            and 0 <= result["elapsed_seconds"] <= 240
            and result.get("within_execute_deadline") is True
            and result.get("requested_skill_allocation_exact") is True
            and result.get("independent_keys_pass") is True
            and result.get("all_six_choice_pairs_pass") is True
            and result.get("teaching_audit_pass") is True
            and result.get("blind_reviews_locked") is True
            and result.get("blind_reviews_pass") is True
            and type(result.get("unresolved_content_uncertainty")) is int
            and result["unresolved_content_uncertainty"] == 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-draft", action="store_true", required=True)
    parser.parse_args()
    spec = json.loads(SPEC.read_text())
    request = json.loads(REQUEST.read_text())
    print(json.dumps(check_draft(spec, request), sort_keys=True))


if __name__ == "__main__":
    main()
