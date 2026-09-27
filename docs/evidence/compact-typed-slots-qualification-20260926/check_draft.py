"""Offline integrity check for the unfrozen compact mixed trial assignment."""

import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ARITHMETIC = ("11111111-1111-4111-8111-111111111111",
              "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")
ENGLISH = ("22222222-2222-4222-8222-222222222222",
           "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")
SOURCE_REVISION = "5183423ae31508ce0a8ac1eb316070a0230cf5d5"
SCHEMA_SHA256 = "eee8c873b7892a8b96e510777fe9ffbbc8d10cf70846644ea0993946c9c2bb3c"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(spec, jobs, predecessor):
    """Validate plan policy without importing runtime, credentials, or network code."""
    require(spec["state"] == "draft_offline_only"
            and spec["candidate_source_revision"] == SOURCE_REVISION
            and spec["independent_source_review"] == "go"
            and spec["independent_harness_review"] in {"pending", "go"}
            and spec["aws_launch_authorized"] is (spec["independent_harness_review"] == "go")
            and spec["frozen_plan"] is False,
            "Compact source, review, or launch state changed.")
    require(set(jobs) == {"status", "jobs"} and jobs["status"] == "draft_offline_only"
            and type(jobs["jobs"]) is list and len(jobs["jobs"]) == 1,
            "One-job original assignment changed.")
    job = jobs["jobs"][0]
    prior_mixed = [item for item in predecessor["jobs"] if item["id"] == "mixed"]
    require(len(prior_mixed) == 1 and job == prior_mixed[0],
            "Mixed request differs from the locked predecessor assignment.")
    request = job["request"]
    require(request["targetCount"] == 5 and request["minimumDifficulty"] == 2
            and request["sourceDocuments"] == []
            and request["requestedSkillAllocation"] == {ARITHMETIC[0]: 3, ENGLISH[0]: 2},
            "Five-slot 3:2 assignment changed.")
    skills = request["skillMap"]["skills"]
    require(len(skills) == 2 and
            [(skill["id"], skill["objectives"][0]["id"]) for skill in skills]
            == [ARITHMETIC, ENGLISH]
            and all(len(skill["objectives"]) == 1 for skill in skills),
            "Mapped skill or objective order changed.")
    require(spec["limits"] == {
        "original_jobs": 1, "original_slots": 5, "calls_per_job": 6,
        "seconds_per_job": 240, "sdk_attempts_per_call": 1,
        "connect_timeout_seconds": 3, "read_timeout_ceiling_seconds": 200,
        "one_trial_execution": True,
    }, "One-shot execution budget changed.")
    gates = spec["gates"]
    require(gates["original_slots_returned"] == 5
            and gates["arithmetic_compiled_policy_8"] == 3
            and gates["english_authored_prose_policy_7"] == 2
            and gates["unresolved_content_uncertainty"] == 0
            and all(value is True for key, value in gates.items() if key not in {
                "original_slots_returned", "arithmetic_compiled_policy_8",
                "english_authored_prose_policy_7", "unresolved_content_uncertainty"}),
            "Full-content success gate changed.")
    source = spec["source_acceptance"]
    require(source == {
        "scoped_to_exact_full_mapped_request": True,
        "native_author_questions_object_keys": [str(i) for i in range(5)],
        "slot_kinds": ["quantitative"] * 3 + ["prose"] * 2,
        "server_injects_assignment_metadata": True,
        "model_written_assignment_metadata_forbidden": True,
        "one_mapped_author_pass": True,
        "no_mapped_top_up_or_retry": True,
        "python_and_unmapped_numerical_routes_unchanged": True,
        "author_solver_reviewer_roles_unchanged": True,
    }, "Compact source criterion changed.")
    initial = spec["initial_author_pins"]
    require(initial["job_fixture_sha256"] == spec["original_jobs_sha256"]
            and spec["trial_environment"]["QUESTION_MAPPED_FIXED_FIVE_GOAL_SHA256"] == initial["goal_sha256"]
            and spec["trial_environment"]["QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256"] == initial["scope_sha256"]
            and spec["trial_environment"]["QUESTION_AUTHOR_CARDINALITY_CONTRACT"] == "array"
            and spec["trial_environment"]["BEDROCK_FALLBACK_MODEL_ID"] == ""
            and initial["native_contract_name"] == "question_author_constructed_mapped_compact_v1_n5_56d4204a9b0238f6"
            and initial["native_schema_sha256"] == SCHEMA_SHA256
            and initial["native_schema_bytes"] == 2664
            and len(spec["source_hashes"]) >= 32
            and len(spec["harness_artifact_sha256"]) >= 8,
            "Exact compact source, scope, schema, or harness pins changed.")
    require(spec["credential_window_seconds"] == {
        "precheck_exported_snapshot_minimum": 360,
        "remaining_before_freeze_and_execute": 330,
        "execute_snapshot_minimum": 300,
    }, "Credential window changed.")


def check_files():
    spec = json.loads((HERE / "plan-draft.json").read_text())
    jobs_path = ROOT / spec["original_jobs_path"]
    require(jobs_path == HERE / "jobs-draft.json", "Draft fixture path changed.")
    require(sha256(jobs_path) == spec["original_jobs_sha256"], "Draft fixture hash changed.")
    for category in ("prior_evidence_sha256", "source_hashes", "harness_artifact_sha256"):
        for relative, expected in spec[category].items():
            require(sha256(ROOT / relative) == expected,
                    f"Pinned {category} artifact changed: {relative}")
    require(sha256(ROOT / "backend/bedrock-question-service/tests/test_compact_mapped_author.py")
            == spec["source_test_sha256"], "Reviewed compact source test changed.")
    prior_path = ROOT / "docs/evidence/task-only-full-worker-qualification-20260926/jobs-draft.json"
    validate(spec, json.loads(jobs_path.read_text()), json.loads(prior_path.read_text()))
    return {"status": "offline_draft_valid", "original_slots": 5, "aws_operations": 0}


if __name__ == "__main__":
    print(json.dumps(check_files(), sort_keys=True))
