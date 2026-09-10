#!/usr/bin/env python3
"""Dry-by-default model comparison using the current solver and teaching gates.

No model activation, native capability changes, retries, repair or deployment.
The reviewer request depends on its own fresh solver; bind it durably before
dispatch instead of pretending to know that request when preparing the plan.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
from unittest.mock import patch

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from complete_question_solution import COMPLETE_SOLUTION_SYSTEM_PROMPT  # noqa: E402
from evals import checkpoint_native_stage_probe as native_probe  # noqa: E402
import question_generation as generation  # noqa: E402
from question_quality import _strict_json_object  # noqa: E402
from question_verification import COMPLETE_REVIEW_SYSTEM_PROMPT, verify_questions  # noqa: E402
from service_errors import ProviderError  # noqa: E402

caller, shared, runtime = native_probe.caller, native_probe.shared, native_probe.runtime
_hash, _same, _source_snapshot = native_probe._hash, native_probe._same, native_probe._source_snapshot
ROOT = SERVICE_DIR.parents[1]
FIXTURE = SERVICE_DIR / "evals/fixtures/question_current_model_comparison.json"
PROTOCOL = ROOT / "docs/QUESTION_CURRENT_MODEL_COMPARISON_PROTOCOL.md"
CASE_NOTE = ROOT / "docs/QUESTION_CURRENT_MODEL_COMPARISON_CASES.md"
ASSESSMENT = ROOT / "docs/evidence/current-model-comparison-preparation-20260910/independent-subjects.json"
MODELS = ("us.anthropic.claude-sonnet-4-6", "us.anthropic.claude-opus-5")
EXPERIMENT = "current-complete-choice-model-comparison-v1"
MAX_CALLS, MAX_INPUT_BYTES, WORKER_SECONDS = 32, 32 * 1024, 240
SETTINGS = {
    "AWS_REGION": "us-east-1", "BEDROCK_REGION": "us-east-1",
    "BEDROCK_CLAUDE_THINKING": "adaptive", "BEDROCK_CLAUDE_EFFORT": "high",
    "BEDROCK_THINKING_MAX_TOKENS": "16000", "BEDROCK_MAX_TOKENS": "16000",
    "BEDROCK_READ_TIMEOUT_SECONDS": "100", "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
    "BEDROCK_FALLBACK_MODEL_ID": "", "BEDROCK_GUARDRAIL_IDENTIFIER": "",
    "BEDROCK_GUARDRAIL_VERSION": "", "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy",
}


class _Captured(BaseException):
    pass


class OperationalFailure(RuntimeError):
    pass


def _provider_request(model, system, user):
    if model not in MODELS:
        raise ValueError("Unexpected comparison model.")
    return {
        "modelId": model, "system": [{"text": system}],
        "messages": [{"role": "user", "content": [{"text": user}]}],
        "inferenceConfig": {"maxTokens": 16000},
        "additionalModelRequestFields": {
            "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"},
        },
    }


def _run_job(case, model, exchange, *, expected_solver=None):
    """The same production verifier owns both live execution and offline replay."""
    stages, metrics = [], {}

    def invoke(system, user):
        role = "solver" if not stages else "reviewer"
        expected_system = (COMPLETE_SOLUTION_SYSTEM_PROMPT if role == "solver"
                           else COMPLETE_REVIEW_SYSTEM_PROMPT)
        if len(stages) >= 2 or system != expected_system:
            raise OperationalFailure("Unexpected stage or extra model call.")
        expected = _provider_request(model, system, user)
        if role == "solver" and expected_solver is not None and not _same(expected, expected_solver):
            raise OperationalFailure("Frozen solver request changed.")
        stages.append({"role": role, "request_sha256": _hash(expected)})

        class Client:
            def converse(self, **request):
                if not _same(request, expected):
                    raise OperationalFailure("Production provider settings changed.")
                return exchange(role, request)

        with patch.dict(os.environ, SETTINGS):
            raw = generation._generate_legacy_with_bedrock(
                copy.deepcopy(case["request"]), Client(), model, user, system,
            )
        stages[-1]["text_sha256"] = hashlib.sha256(raw.encode()).hexdigest()
        return raw

    accepted = verify_questions(
        [copy.deepcopy(case["question"])], copy.deepcopy(case["request"]), invoke, metrics,
        solve=invoke, solver_contract="complete_choices", feedback_contract="reviewer_written",
        preserve_reviewed_text=True,
    )
    return {"status": "completed", "stages": stages,
            "quality": metrics.get("QuestionQuality", {}), "accepted": accepted,
            "semantic_assessment": "unassessed"}


def _solver_request(case, model):
    captured = []

    def exchange(role, request):
        if role != "solver":
            raise ValueError("Preparation may reach only the solver.")
        captured.append(copy.deepcopy(request))
        raise _Captured()

    try:
        _run_job(case, model, exchange)
    except _Captured:
        pass
    if len(captured) != 1 or len(shared.canonical(captured[0]).encode()) > MAX_INPUT_BYTES:
        raise ValueError("Each unchanged case must produce one bounded solver request.")
    return captured[0]


def make_plan(*, source_revision=None):
    fixture_bytes = FIXTURE.read_bytes()
    packet = json.loads(fixture_bytes)
    assessment = json.loads(ASSESSMENT.read_text())
    if assessment.get("fixture_sha256") != hashlib.sha256(fixture_bytes).hexdigest():
        raise ValueError("Independent assessment must describe the exact frozen fixture.")
    cases = packet["cases"]
    if len(cases) != 8 or len({c["case_id"] for c in cases}) != 8:
        raise ValueError("Exactly eight distinct frozen subjects are required.")
    for case in cases:
        provenance = case["provenance"]
        if (provenance["request_canonical_sha256"] != _hash(case["request"])
                or provenance["question_canonical_sha256"] != _hash(case["question"])):
            raise ValueError("Question or request differs from its original source identity.")
        source = (ROOT / provenance["source_path"]).resolve()
        if not source.is_relative_to(ROOT.resolve()) or hashlib.sha256(source.read_bytes()).hexdigest() != provenance["source_byte_sha256"]:
            raise ValueError("Subject provenance bytes changed.")
    documents = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in (FIXTURE, PROTOCOL, CASE_NOTE, ASSESSMENT)}
    jobs = []
    for index, case in enumerate(cases):
        for model in (MODELS if index % 2 == 0 else tuple(reversed(MODELS))):
            request = _solver_request(case, model)
            jobs.append({"position": len(jobs), "case_index": index, "case_id": case["case_id"],
                         "model": model, "solver_request": request,
                         "solver_request_sha256": _hash(request)})
    return {
        "experiment": EXPERIMENT, **_source_snapshot(source_revision),
        "fixture": packet, "documents_sha256": documents, "jobs": jobs,
        "settings": copy.deepcopy(SETTINGS), "maximum_calls": MAX_CALLS,
        "maximum_calls_per_job": 2, "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": MAX_CALLS * MAX_INPUT_BYTES,
        "maximum_output_tokens_per_call": 16000, "sdk_total_max_attempts": 1,
        "worker_deadline_seconds": WORKER_SECONDS,
        "reviewer_system": COMPLETE_REVIEW_SYSTEM_PROMPT,
        "reviewer_binding": "Current verify_questions builds this request from the same job's fresh validated solver; exact request and hash must be persisted before dispatch.",
        "scope": "Fixed-subject model diagnostic with equal legacy transport and thinking settings. No fresh authoring, native qualification, production change or general accuracy claim.",
        "assessment": "Freeze independent subject judgments before execution. Score answer support, every explanation and difficulty separately. Format failures and uncertainty are not demonstrated factual catches.",
    }


def load_frozen_plan(path, expected_hash):
    plan = json.loads(path.read_text())
    if _hash(plan) != expected_hash or not _same(plan, make_plan(source_revision=plan.get("source_revision"))):
        raise ValueError("Plan, committed sources, subjects, assessments or settings changed.")
    return plan


def run_trial(plan_path, expected_hash, directory, *, cli_credentials=False, observer=None):
    plan = load_frozen_plan(plan_path, expected_hash)
    # One claim beside the immutable plan prevents silently rerunning it into a
    # new output directory. A failed/uncertain run must be assessed, never resumed.
    claim = plan_path.with_name(plan_path.name + ".execution-claim.json")
    directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    with claim.open("x", encoding="utf-8") as handle:
        handle.write(shared.canonical({"plan_sha256": expected_hash, "directory": str(directory.resolve())}))
        handle.flush()
        os.fsync(handle.fileno())
    descriptor = os.open(claim.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    report = {"plan": plan, "plan_sha256": expected_hash, "status": "running", "calls": [],
              "input_utf8_bytes": 0,
              "results": [{"position": j["position"], "status": "unattempted"} for j in plan["jobs"]]}
    persistence_failed = False
    active_position = None

    def persist():
        nonlocal persistence_failed
        try:
            shared.write_json(directory / "capture.json", report)
        except Exception:
            persistence_failed = True
            raise

    persist()
    try:
        for job in plan["jobs"]:
            active_position = job["position"]
            calls_in_job = []

            def exchange(role, request):
                size = len(shared.canonical(request).encode())
                if (persistence_failed or len(report["calls"]) >= MAX_CALLS or len(calls_in_job) >= 2
                        or size > MAX_INPUT_BYTES
                        or report["input_utf8_bytes"] + size > MAX_CALLS * MAX_INPUT_BYTES):
                    raise OperationalFailure("Call or input allowance exhausted before dispatch.")
                call = {"position": job["position"], "role": role, "request": copy.deepcopy(request),
                        "request_sha256": _hash(request), "input_utf8_bytes": size,
                        "status": "launch_intent", "lifecycle": [], "observation": None}
                calls_in_job.append(call)
                report["calls"].append(call)
                report["input_utf8_bytes"] += size
                persist()

                def progress(state):
                    call["observation"] = copy.deepcopy(state)
                    call["lifecycle"].append({key: state.get(key) for key in (
                        "status", "provider_dispatch_attempted", "local_process_group_id")})
                    persist()

                with patch.object(caller, "SETTINGS", SETTINGS):
                    state = (observer or caller.observe_request)(
                        request, cli_credentials=cli_credentials, on_progress=progress, timeout=WORKER_SECONDS,
                    )
                call["observation"] = copy.deepcopy(state)
                call["observation_sha256"] = _hash(state)
                usable = runtime._usable_observation(state) and state["usage_known"]
                call["status"] = "completed" if usable else "operational_failure"
                persist()
                if not usable or persistence_failed:
                    raise OperationalFailure("Provider, usage, observation or cleanup failed.")
                return runtime._provider_response(state)

            try:
                result = _run_job(plan["fixture"]["cases"][job["case_index"]], job["model"], exchange,
                                  expected_solver=job["solver_request"])
            except ProviderError as error:
                # The production extractor rejects an empty completed text. It
                # is content loss only when every observation is known terminal.
                if (error.__cause__ is not None or persistence_failed or not calls_in_job
                        or any(c["status"] != "completed" for c in calls_in_job)
                        or calls_in_job[-1]["observation"]["response"]["text"].strip()):
                    raise
                result = {"status": "completed_content_failure", "accepted": [],
                          "semantic_assessment": "unavailable", "reason": "provider_text_extraction"}
            report["results"][job["position"]] = {"position": job["position"], **result}
            persist()
        report["status"] = "completed"
    except Exception as error:
        report.update(status="operational_failure", error_type=type(error).__name__)
        if active_position is not None:
            report["results"][active_position] = {"position": active_position,
                                                   "status": "operational_failure",
                                                   "semantic_assessment": "unavailable",
                                                   "error_type": type(error).__name__}
    finally:
        persist()
    return report


def replay_job(plan, job, calls):
    cursor = 0

    def exchange(role, request):
        nonlocal cursor
        if cursor >= len(calls):
            raise ValueError("Replay requires a missing historical response.")
        call = calls[cursor]
        cursor += 1
        if (call["position"] != job["position"] or call["role"] != role
                or call["request_sha256"] != _hash(request) or not _same(call["request"], request)
                or call["status"] != "completed"
                or call["input_utf8_bytes"] != len(shared.canonical(request).encode())
                or call["observation_sha256"] != _hash(call["observation"])
                or not runtime._usable_observation(call["observation"]) or not call["observation"]["usage_known"]):
            raise ValueError("Captured request, model, stage or usable response binding changed.")
        return runtime._provider_response(call["observation"])

    try:
        result = _run_job(plan["fixture"]["cases"][job["case_index"]], job["model"], exchange,
                          expected_solver=job["solver_request"])
    except ProviderError as error:
        # Never interpret a missing/altered call as an empty-text content result.
        if (error.__cause__ is not None or cursor != len(calls) or not calls
                or calls[-1]["observation"]["response"]["text"].strip()):
            raise
        result = {"status": "completed_content_failure", "accepted": [],
                  "semantic_assessment": "unavailable", "reason": "provider_text_extraction"}
    if cursor != len(calls):
        raise ValueError("Replay did not consume every call for this job.")
    return {"position": job["position"], **result}


def export_assessment(report, directory):
    plan = report["plan"]
    if (report["status"] != "completed" or report["plan_sha256"] != _hash(plan)
            or not _same(plan, make_plan(source_revision=plan.get("source_revision")))):
        raise ValueError("A completed capture bound to unchanged source is required.")
    if len(report["results"]) != len(plan["jobs"]):
        raise ValueError("All planned results must be represented.")
    positions = [c["position"] for c in report["calls"]]
    if (positions != sorted(positions) or len(positions) > MAX_CALLS
            or any(not 0 < c["input_utf8_bytes"] <= MAX_INPUT_BYTES for c in report["calls"])
            or report["input_utf8_bytes"] != sum(c["input_utf8_bytes"] for c in report["calls"])):
        raise ValueError("Capture call order or input accounting changed.")
    teaching, solutions, mapping = [], [], []
    # Deterministic masking conceals labels/order, not a claim of perfect human
    # blinding. Every planned job is present, including skipped reviewer slots.
    jobs = sorted(plan["jobs"], key=lambda j: _hash({"mask": EXPERIMENT, "position": j["position"]}))
    consumed = 0
    for ordinal, job in enumerate(jobs):
        calls = [c for c in report["calls"] if c["position"] == job["position"]]
        consumed += len(calls)
        if not _same(replay_job(plan, job, calls), report["results"][job["position"]]):
            raise ValueError("Saved policy result differs from exact offline replay.")
        case = plan["fixture"]["cases"][job["case_index"]]
        actual_subject = native_probe._subject(job["solver_request"], "solver")["items"][0]
        identifier = f"sample-{ordinal + 1:02d}"
        subject = {"sample_id": identifier, "prompt": case["question"]["prompt"],
                   "choices": copy.deepcopy(actual_subject["choices"]),
                   "context": {key: case["request"].get(key) for key in ("goal", "skillMap", "sourceDocuments")}}
        for role, packet in (("solver", solutions), ("reviewer", teaching)):
            observed = next((c for c in calls if c["role"] == role), None)
            raw = observed["observation"]["response"]["text"] if observed else None
            try:
                parsed = _strict_json_object(raw) if raw is not None else None
            except ProviderError:
                parsed = None
            packet.append({**copy.deepcopy(subject), "raw_response": raw, "parsed_response": parsed})
        mapping.append({"sample_id": identifier, "position": job["position"], "model": job["model"],
                        "case_id": job["case_id"]})
    if consumed != len(report["calls"]):
        raise ValueError("Capture contains calls outside the planned jobs.")
    directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    packets = {"solutions.json": solutions, "teaching.json": teaching, "private-mapping.json": mapping}
    for name, value in packets.items():
        shared.write_json(directory / name, value)
    shared.write_json(directory / "binding.json", {
        "capture_canonical_sha256": _hash(report), "plan_sha256": _hash(plan),
        "packet_sha256": {name: hashlib.sha256((directory / name).read_bytes()).hexdigest() for name in packets},
        "scope": "Exact final text, with models and authored keys withheld. Teaching packet omits solver output. Missing reviews remain null; policy returns are not content scores.",
    })


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--plan-sha256")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    parser.add_argument("--export-capture", type=Path)
    args = parser.parse_args(argv)
    if args.export_capture:
        if args.execute or args.plan or args.plan_sha256 or args.aws_cli_credentials:
            parser.error("Export is an offline-only action.")
        export_assessment(json.loads(args.export_capture.read_text()), args.directory)
        return 0
    if args.execute:
        if args.plan is None or args.plan_sha256 is None:
            parser.error("Execution requires the frozen plan and hash.")
        report = run_trial(args.plan, args.plan_sha256, args.directory, cli_credentials=args.aws_cli_credentials)
        return 0 if report["status"] == "completed" else 1
    if args.plan or args.plan_sha256 or args.aws_cli_credentials:
        parser.error("Dry preparation accepts only a new directory.")
    plan = make_plan()
    args.directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    shared.write_json(args.directory / "plan.json", plan)
    print(_hash(plan))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
