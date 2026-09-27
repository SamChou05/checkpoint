"""Socket-free draft and illustrative result-shape checks; never dispatch AWS."""

import argparse
import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
REQUEST_SHA256 = "bcfbc829725c6d568cfc755b82a1210d9d284b1c58d24f81ad01fb63e9ce7d58"
TRIAL_ID = "generic-prose-seven-reserve-probability-20260927-05"
AUTHOR_ORDINALS = list(range(7))
FORBIDDEN_LAUNCH_ARTIFACTS = (
    "plan.json", "review-approval.json", "launch-precheck.json",
    "launch-precheck-attempt.json", "capture.json", "blind-worksheet.json",
)


class ProtocolError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ProtocolError(message)


def strict_json(path):
    def unique_members(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f"Duplicate JSON property in {path.name}.")
            result[key] = value
        return result

    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_members)


def check_draft(protocol, request, *, directory=HERE, request_bytes=None,
                check_artifacts=True):
    """A passing draft check explicitly does not authorize live execution."""
    if request_bytes is None:
        request_bytes = (directory / "request.json").read_bytes()
    require(protocol.get("state") == "draft_waiting_for_candidate"
            and protocol.get("trial_id") == TRIAL_ID,
            "Draft identity or state changed.")
    for field in (
        "candidate_source_commit", "candidate_source_hashes",
        "candidate_author_wire_sha256", "candidate_native_schema_sha256",
        "candidate_native_schema_bytes", "independent_source_review",
    ):
        require(field in protocol and protocol[field] is None,
                f"{field} cannot be frozen by the draft guard.")
    require(protocol.get("request_file") == "request.json"
            and protocol.get("request_sha256") == REQUEST_SHA256
            and hashlib.sha256(request_bytes).hexdigest() == REQUEST_SHA256,
            "The frozen synthetic request changed.")
    require(type(request) is dict and request.get("targetCount") == 5
            and request.get("minimumDifficulty") == 2
            and request.get("goal", {}).get("needsSkillMap") is False
            and request.get("goal", {}).get("contentTopics") == ["Probability"]
            and request.get("sourceDocuments") == []
            and request.get("adaptiveSkillPlans") == []
            and request.get("requiresFullObjectiveCoverage") is False
            and not any(key in request for key in (
                "skillMap", "desiredSkillAllocation", "requestedSkillAllocation",
                "requestedObjectiveAllocation",
            )), "The request no longer selects the unassigned generic route.")
    env = protocol.get("environment", {})
    expected_env = {
        "BEDROCK_REGION": "us-east-1",
        "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
        "QUESTION_AUTHOR_MODE": "prose",
        "QUESTION_AUTHOR_CARDINALITY_CONTRACT": "count_bound",
        "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
        "QUESTION_GENERIC_PROSE_RESERVE_7": "enabled",
        "BEDROCK_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
        "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
        "BEDROCK_FALLBACK_MODEL_ID": "",
        "BEDROCK_CLAUDE_THINKING": "disabled",
        "BEDROCK_CLAUDE_EFFORT": "high",
        "BEDROCK_MAX_TOKENS": "6000",
        "BEDROCK_THINKING_MAX_TOKENS": "16000",
        "BEDROCK_TEMPERATURE": "0.2",
        "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
        "BEDROCK_READ_TIMEOUT_SECONDS": "200",
        "GENERATION_ATTEMPTS": "3",
        "MAX_PROVIDER_CALLS_PER_REQUEST": "6",
    }
    require(env == expected_env,
            "The generic native author environment drifted.")
    limits = protocol.get("limits", {})
    require(limits.get("original_jobs") == 1
            and limits.get("requested_return_count") == 5
            and limits.get("native_author_rows") == 7
            and limits.get("verifier_chunks") == [4, "remaining_1_to_3_sanitized_rows"]
            and limits.get("maximum_verifier_stages") == 4
            and limits.get("successful_stage_order") == [
                "author7", "solver4", "reviewer_up_to4", "solver_n1_to_n3",
                "reviewer_up_to_n3",
            ]
            and limits.get("author_calls") == 1
            and limits.get("maximum_converse_calls") == 6
            and limits.get("successful_converse_calls") == 5
            and limits.get("sdk_attempts_per_call") == 1
            and limits.get("whole_execute_seconds") == 240
            and limits.get("deadline_origin") == "before_credential_export_and_execute_sts"
            and limits.get("connect_timeout_seconds") == 3
            and limits.get("read_timeout_seconds") == 200
            and limits.get("sts_precheck_requests") == 1
            and limits.get("sts_execute_requests") == 1
            and limits.get("sts_sdk_attempts_per_request") == 1
            and limits.get("resume_retry_fallback_topup_bank_queue_deploy") is False,
            "The one-shot transport or budget changed.")
    gate = protocol.get("prespecified_gate", {})
    require(gate.get("returned_question_count") == 5
            and gate.get("authored_source_ordinals") == AUTHOR_ORDINALS
            and gate.get("survivor_source_ordinals_must_be_earliest_five_accepted") is True
            and gate.get("survivor_source_ordinals_unique") is True
            and gate.get("verification_version") == 1
            and gate.get("verification_policy_revision") == 7
            and gate.get("minimum_difficulty") == 2
            and gate.get("blind_reviewer_difficulty_allowed") == [2, 3]
            and gate.get("distinct_choices_per_question") == 4
            and gate.get("one_independently_supported_choice_per_question") is True
            and gate.get("meaningfully_distinct_choice_pairs_per_question") == 6
            and gate.get("meaningfully_distinct_choice_pairs_total") == 30
            and gate.get("all_five_self_contained_and_on_topic") is True
            and gate.get("all_five_main_explanations_sound") is True
            and gate.get("no_strong_cross_question_repeats") is True
            and gate.get("maximum_converse_calls") == 5
            and gate.get("whole_execute_seconds_max") == 240
            and gate.get("no_repair_or_second_job") is True
            and gate.get("ambiguous_or_unavailable_evidence_is_failure") is True,
            "The prespecified five-survivor gate changed.")
    blind = protocol.get("blind_review", {})
    require(blind.get("independent_reviewers") == 2
            and blind.get("answer_blind") is True
            and blind.get("source_ordinal_blind") is True
            and blind.get("worksheet_from_returned_five_only") is True
            and blind.get("hide_model_keys_reviewer_ratings_teaching_rejection_reasons_until_both_locked") is True
            and blind.get("unavailable_original_rows_recorded_explicitly") is True,
            "The blind-review protocol changed.")
    if check_artifacts:
        require(not any((directory / name).exists() for name in FORBIDDEN_LAUNCH_ARTIFACTS),
                "Draft contains a launch or capture artifact.")
    return {"state": "draft_waiting_for_candidate", "request_sha256": REQUEST_SHA256,
            "provider_calls": 0, "launch_allowed": False}


def illustrative_gate(result):
    """Check a post-run summary shape; only a future source-pinned harness can derive it."""
    if type(result) is not dict:
        return False
    authored = result.get("authored_source_ordinals")
    accepted = result.get("accepted_source_ordinals")
    returned = result.get("returned_source_ordinals")
    if authored != AUTHOR_ORDINALS or type(accepted) is not list or type(returned) is not list:
        return False
    if (any(type(value) is not int or value not in AUTHOR_ORDINALS for value in accepted)
            or len(set(accepted)) != len(accepted)
            or accepted != sorted(accepted)
            or returned != accepted[:5]
            or len(returned) != 5):
        return False
    return (
        result.get("verification_versions") == [1] * 5
        and result.get("verification_policy_revisions") == [7] * 5
        and result.get("offered_choice_counts") == [4] * 5
        and result.get("offered_key_counts") == [1] * 5
        and type(result.get("backend_difficulties")) is list
        and all(type(value) is int and value >= 2
                for value in result["backend_difficulties"])
        and len(result["backend_difficulties"]) == 5
        and result.get("independent_unique_keys") is True
        and result.get("distinct_choice_pair_counts") == [6] * 5
        and result.get("all_self_contained_and_on_topic") is True
        and result.get("all_teaching_sound") is True
        and result.get("no_strong_cross_question_repeats") is True
        and result.get("blind_reviews_locked") is True
        and result.get("blind_review_count") == 2
        and type(result.get("blind_reviewer_difficulties")) is list
        and len(result["blind_reviewer_difficulties"]) == 2
        and all(type(scores) is list and len(scores) == 5
                and all(type(score) is int and score in (2, 3) for score in scores)
                for scores in result["blind_reviewer_difficulties"])
        and result.get("blind_reviews_pass") is True
        and result.get("unresolved_content_uncertainty") == 0
        and type(result.get("converse_calls")) is int
        and result["converse_calls"] == 5
        and type(result.get("whole_execute_seconds")) in (int, float)
        and 0 <= result["whole_execute_seconds"] <= 240
        and result.get("deadline_included_credential_export_and_sts") is True
        and result.get("no_second_job_or_repair") is True
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-draft", action="store_true", required=True)
    parser.parse_args()
    protocol = strict_json(HERE / "protocol.json")
    request = strict_json(HERE / "request.json")
    print(json.dumps(check_draft(protocol, request), sort_keys=True))


if __name__ == "__main__":
    main()
