"""Offline-only integrity check for the unfrozen mixed successor assignment."""

import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ARITHMETIC = ("11111111-1111-4111-8111-111111111111",
              "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")
ENGLISH = ("22222222-2222-4222-8222-222222222222",
           "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(spec, jobs, predecessor):
    """Validate a draft without importing runtime, credential, or network code."""
    require(spec["state"] == "draft_offline_only"
            and spec["candidate_source_revision"] == "397f6a13112d967176b75f972ecbbe48f0aa6ef5"
            and spec["independent_source_review"] == "go"
            and spec["aws_launch_authorized"] is False
            and spec["frozen_plan"] is False,
            "Offline draft source review or launch state changed.")
    require(set(jobs) == {"status", "jobs"} and jobs["status"] == "draft_offline_only"
            and type(jobs["jobs"]) is list and len(jobs["jobs"]) == 1,
            "Mixed-only original assignment changed.")
    job = jobs["jobs"][0]
    prior_mixed = [item for item in predecessor["jobs"] if item["id"] == "mixed"]
    require(len(prior_mixed) == 1 and job == prior_mixed[0],
            "Mixed request differs from the locked predecessor assignment.")
    request = job["request"]
    require(request["targetCount"] == 5 and request["minimumDifficulty"] == 2
            and request["sourceDocuments"] == []
            and request["requestedSkillAllocation"] == {ARITHMETIC[0]: 3, ENGLISH[0]: 2},
            "The five-slot 3:2 assignment changed.")
    skills = request["skillMap"]["skills"]
    require(len(skills) == 2 and
            [(skill["id"], skill["objectives"][0]["id"]) for skill in skills]
            == [ARITHMETIC, ENGLISH]
            and all(len(skill["objectives"]) == 1 for skill in skills),
            "Mapped skills or objectives changed.")
    limits = spec["limits"]
    require(limits == {"original_jobs": 1, "original_slots": 5, "calls_per_job": 6,
                       "seconds_per_job": 240, "sdk_attempts_per_call": 1,
                       "connect_timeout_seconds": 3, "read_timeout_ceiling_seconds": 200,
                       "one_trial_execution": True},
            "The one-shot execution budget changed.")
    gates = spec["gates"]
    require(gates["original_slots_returned"] == 5
            and gates["arithmetic_compiled_policy_8"] == 3
            and gates["english_authored_prose_policy_7"] == 2
            and gates["unresolved_content_uncertainty"] == 0
            and all(value is True for key, value in gates.items() if key not in {
                "original_slots_returned", "arithmetic_compiled_policy_8",
                "english_authored_prose_policy_7", "unresolved_content_uncertainty"}),
            "The full-content success gate changed.")
    source = spec["source_acceptance"]
    require(source["native_author_questions_object_keys"] == [str(i) for i in range(5)]
            and source["mandatory_mapped_fields"] == ["skillID", "objectiveID", "objective"]
            and all(value is True for key, value in source.items() if key not in {
                "native_author_questions_object_keys", "mandatory_mapped_fields"}),
            "The scoped fixed-map source criterion changed.")
    initial = spec["initial_author_pins"]
    require(initial["job_fixture_sha256"] == spec["original_jobs_sha256"]
            and spec["trial_environment"]["QUESTION_MAPPED_FIXED_FIVE_GOAL_SHA256"] == initial["goal_sha256"]
            and spec["trial_environment"]["QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256"] == initial["scope_sha256"]
            and spec["trial_environment"]["QUESTION_AUTHOR_CARDINALITY_CONTRACT"] == "array"
            and initial["native_contract_name"] == spec["author_contract_pins"]["3:2"]["name"]
            and len(spec["source_hashes"]) == 32 and len(spec["author_contract_pins"]) == 11
            and len(spec["harness_artifact_sha256"]) == 7,
            "Exact mapped source, scope or contract pins changed.")
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
    for relative, expected in spec["prior_evidence_sha256"].items():
        require(sha256(ROOT / relative) == expected, "Locked evidence changed: " + relative)
    for relative, expected in spec["source_hashes"].items():
        require(sha256(ROOT / relative) == expected, "Reviewed source changed: " + relative)
    require(sha256(ROOT / "backend/bedrock-question-service/tests/test_mapped_fixed_author.py")
            == spec["source_test_sha256"], "Reviewed source test changed.")
    for relative, expected in spec["harness_artifact_sha256"].items():
        require(sha256(ROOT / relative) == expected, "Reviewed offline harness changed: " + relative)
    prior_path = ROOT / "docs/evidence/task-only-full-worker-qualification-20260926/jobs-draft.json"
    validate(spec, json.loads(jobs_path.read_text()), json.loads(prior_path.read_text()))
    return {"status": "offline_draft_valid", "original_slots": 5, "aws_operations": 0}


if __name__ == "__main__":
    print(json.dumps(check_files(), sort_keys=True))
