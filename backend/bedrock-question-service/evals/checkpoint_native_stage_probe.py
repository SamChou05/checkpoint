#!/usr/bin/env python3
"""Fixed historical-input native-format diagnostic; dry by default.

Ten single-attempt requests cover all seven archived formatting failures, with
one exact repeat per downstream schema. Repeats are not cold/warm measurements.
There is no repair, fresh generation, delivery claim or correctness score.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from unittest.mock import patch

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_author_latency_probe as caller  # noqa: E402
from evals import checkpoint_runtime_qualification as runtime  # noqa: E402
from complete_question_solution import validate_batch, CompleteSolutionFormatError  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_generation as generation  # noqa: E402
from question_quality import _strict_json_object  # noqa: E402
from question_teaching import validate_authored_reviews, AuthoredTeachingFormatError  # noqa: E402
from service_errors import ProviderError  # noqa: E402

shared, recorded = caller.shared, caller.recorded
_hash, _same = recorded._hash, recorded._same
EXPERIMENT = "native-downstream-historical-format-probe-v1"
ORIGIN = SERVICE_DIR.parents[1] / "docs/evidence/delivery-feedback-20260909/capture.json"
ORIGIN_SHA256 = "b2b4d385fcde8143d8d43ea34cb17d6e4963fb816793cb5feed9a776c02b3049"
CALL_INDEXES = (7, 14, 16, 18, 20, 7, 5, 5, 28, 28)
CONTRACTS = {"solver": "complete_choice_solver_v1", "reviewer": "default_reviewer_v1",
             "teaching_auditor": "authored_solution_reviewer_v1"}
MAX_CALLS, MAX_INPUT_BYTES, WORKER_SECONDS = 10, 32 * 1024, 240
REQUIRED_SDK = {"boto3": "1.43.91", "botocore": "1.43.91"}
SETTINGS = {**runtime.SETTINGS, "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
            "MAX_QUESTIONS_PER_BATCH": "5"}


class _Captured(BaseException):
    pass


def _source_snapshot(revision=None):
    dependencies = shared.dependencies()
    if any(dependencies.get(package) != version for package, version in REQUIRED_SDK.items()):
        raise ValueError("The packaged boto3 and botocore 1.43.91 runtime is required.")
    revision = shared.source_revision() if revision is None else revision
    if type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("A full committed source revision is required.")
    check = subprocess.run(["git", "cat-file", "-e", revision + "^{commit}"],
                           cwd=SERVICE_DIR, capture_output=True)
    if check.returncode:
        raise ValueError("Source revision must resolve to a commit.")
    paths = sorted(SERVICE_DIR.glob("*.py")) + sorted((SERVICE_DIR / "evals").glob("*.py"))
    paths.append(SERVICE_DIR / "requirements.txt")
    sources = {}
    for path in paths:
        name = path.relative_to(SERVICE_DIR).as_posix()
        committed = subprocess.run(
            ["git", "show", f"{revision}:backend/bedrock-question-service/{name}"],
            cwd=SERVICE_DIR, capture_output=True,
        )
        raw = path.read_bytes()
        if committed.returncode or raw != committed.stdout:
            raise ValueError("All runtime and probe sources must match the committed revision.")
        sources[name] = hashlib.sha256(raw).hexdigest()
    return {"source_revision": revision, "source_sha256": sources,
            "dependencies": dependencies}


def _subject(request, role):
    tag = "question_solution_json" if role == "solver" else "question_review_json"
    text = request["messages"][0]["content"][0]["text"]
    prefix, suffix = f"<{tag}>\n", f"\n</{tag}>"
    if not text.startswith(prefix) or not text.endswith(suffix):
        raise ValueError("Exact archived stage subject required.")
    return json.loads(text[len(prefix):-len(suffix)])


def _invoke(job, client):
    with patch.dict(os.environ, SETTINGS):
        return generation._generate_with_bedrock(
            copy.deepcopy(job["normalized_operation_request"]), client,
            job["archived_request"]["modelId"],
            job["archived_request"]["messages"][0]["content"][0]["text"],
            job["archived_request"]["system"][0]["text"],
            contract=job["contract"],
        )


def _native_request(job):
    requests = []

    class Client:
        def converse(self, **request):
            requests.append(copy.deepcopy(request))
            raise _Captured()

    try:
        _invoke(job, Client())
    except _Captured:
        pass
    if len(requests) != 1:
        raise ValueError("Exactly one production request must be captured.")
    expected = copy.deepcopy(job["archived_request"])
    expected["system"] = [{"text": native.native_prompt(expected["system"][0]["text"], job["contract"])}]
    expected["outputConfig"] = native.native_output_config(job["contract"])
    if not _same(requests[0], expected):
        raise ValueError("Only native system instructions and outputConfig may change.")
    if len(shared.canonical(expected).encode()) > MAX_INPUT_BYTES:
        raise ValueError("Native request exceeds the fixed input allowance.")
    return requests[0]


def make_plan(*, source_revision=None):
    raw = ORIGIN.read_bytes()
    if hashlib.sha256(raw).hexdigest() != ORIGIN_SHA256:
        raise ValueError("Exact archived capture bytes required.")
    origin = json.loads(raw)
    if origin["plan_sha256"] != _hash(origin["plan"]):
        raise ValueError("Archived plan binding changed.")
    snapshot = _source_snapshot(source_revision)
    jobs = []
    for position, index in enumerate(CALL_INDEXES):
        prior = origin["calls"][index]
        request = prior["request"]
        operation = origin["plan"]["operations"][prior["operation_index"]]
        with patch.dict(os.environ, {**operation["settings"], "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"}):
            role = runtime._guard_request(request, operation["settings"])
        if (role not in CONTRACTS or prior["role"] != role
                or request["modelId"] != "us.anthropic.claude-sonnet-4-6"
                or prior["request_sha256"] != _hash(request)
                or not runtime._usable_observation(prior["observation"])):
            raise ValueError("Archived request must be an exact completed downstream call.")
        try:
            _strict_json_object(prior["observation"]["response"]["text"])
        except ProviderError:
            pass
        else:
            raise ValueError("Selected archive must exhibit strict JSON failure.")
        job = {"position": position, "archived_call_index": index,
               "archived_operation_index": prior["operation_index"], "role": role,
               "contract": CONTRACTS[role], "archived_request": copy.deepcopy(request),
               "normalized_operation_request": copy.deepcopy(operation["request"]),
               "subject": _subject(request, role)}
        job["request"] = _native_request(job)
        job["request_sha256"] = _hash(job["request"])
        job["input_utf8_bytes"] = len(shared.canonical(job["request"]).encode())
        job["contract_metadata"] = native.contract_metadata(job["contract"])
        jobs.append(job)
    if len(jobs) != MAX_CALLS:
        raise ValueError("Fixed ten-call diagnostic required.")
    return {"experiment": EXPERIMENT, **snapshot,
            "origin": {"capture_file_sha256": ORIGIN_SHA256,
                       "capture_canonical_sha256": _hash(origin),
                       "prior_plan_sha256": origin["plan_sha256"]},
            "jobs": jobs, "settings": copy.deepcopy(SETTINGS), "maximum_calls": MAX_CALLS,
            "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
            "maximum_input_utf8_bytes_total": MAX_CALLS * MAX_INPUT_BYTES,
            "planned_input_utf8_bytes": sum(j["input_utf8_bytes"] for j in jobs),
            "per_worker_deadline_seconds": WORKER_SECONDS, "sdk_total_max_attempts": 1,
            "maximum_worker_capture_bytes": caller.MAX_CAPTURE_BYTES,
            "scope": "Historical-input downstream transport diagnostic. Exact repeated requests are not cache-state or independent-quality measurements. No author calls, retries, repairs, fallback, resume, full production review, question delivery, or correctness certification.",
            "failure_policy": "Stop on provider, unfinished response, cleanup, observation or persistence failure. Completed schema/adaptation/correlation rejection is content evidence and does not trigger repairs or stop later fixed jobs.",
            "timing_scope": "Ten serial local workers, each at most 240 seconds before bounded cleanup; socket read75/connect3/SDK1. Parent persistence is not hard real-time. No response leaves remote completion and usage unknown. No first-schema compilation success is presumed."}


def load_frozen_plan(path, approved_hash):
    plan = json.loads(path.read_text())
    if _hash(plan) != approved_hash or not _same(
        plan, make_plan(source_revision=plan.get("source_revision")),
    ):
        raise ValueError("Exact frozen plan, committed source, dependencies and origins required.")
    return plan


def _default_correlation(adapted, items):
    """Only index/choice coverage; deliberately not the full production review."""
    reviews = json.loads(adapted)["reviews"]
    offered = {item["index"]: item["choices"] for item in items}
    indexes = [review["index"] for review in reviews]
    if len(indexes) != len(offered) or set(indexes) != set(offered):
        raise ValueError("Reviewer index coverage failed.")
    for review in reviews:
        if review["valid"] and (review["answer"] not in offered[review["index"]]
                or set(review["choiceExplanations"]) != set(offered[review["index"]])):
            raise ValueError("Reviewer choice coverage failed.")
    return reviews


def content_observation(job, state):
    result = {"raw_schema_validation": "unavailable", "adaptation": "unavailable",
              "stage_validation": "unavailable", "semantic_assessment": "unassessed",
              "full_production_acceptance": "not_run"}
    if not runtime._usable_observation(state):
        return result
    raw = state["response"]["text"]
    try:
        parsed = json.loads(raw, object_pairs_hook=native._reject_duplicate_pairs,
                            parse_constant=native._reject_constant)
        schema = json.loads(job["request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
        native._validate_schema_value(parsed, schema)
    except (TypeError, ValueError):
        result["raw_schema_validation"] = "rejected"
        return result
    result["raw_schema_validation"] = "passed"

    class RecordedClient:
        def converse(self, **request):
            if not _same(request, job["request"]):
                raise ValueError("Offline runtime response binding changed.")
            return runtime._provider_response(state)

    try:
        adapted = _invoke(job, RecordedClient())
    except ProviderError:
        result["adaptation"] = "rejected"
        return result
    result["adaptation"] = "passed"
    try:
        items = job["subject"]["items"]
        if job["role"] == "solver":
            validated = validate_batch(adapted, items)
        elif job["role"] == "teaching_auditor":
            validated = validate_authored_reviews(adapted, items)
        else:
            validated = _default_correlation(adapted, items)
    except (CompleteSolutionFormatError, AuthoredTeachingFormatError, ValueError):
        result["stage_validation"] = "rejected"
        return result
    result.update(stage_validation="passed", validated_item_count=len(validated),
                  stage_validation_scope=("default_reviewer_index_and_choice_coverage_only"
                                          if job["role"] == "reviewer" else "production_stage_validator"))
    return result


def run_probe(plan_path, approved_hash, directory, *, cli_credentials=False, observer=None):
    plan = load_frozen_plan(plan_path, approved_hash)
    return run_frozen_jobs(plan, directory, cli_credentials=cli_credentials, observer=observer)


def run_frozen_jobs(plan, directory, *, cli_credentials=False, observer=None, content_observer=None):
    """Run an already validated fixed plan using the bounded downstream observer.

    Callers own frozen-plan validation. This helper neither chooses extra jobs
    nor retries content failures, and preserves the existing native admission.
    """
    approved_hash = _hash(plan)
    directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    report = {"plan": plan, "plan_sha256": approved_hash, "status": "running", "calls": [],
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
            active_position = None
            call = {"position": job["position"], "archived_call_index": job["archived_call_index"],
                    "request_sha256": job["request_sha256"], "status": "launch_intent",
                    "provider_dispatch_attempted": None, "usage_known": False, "lifecycle": []}
            report["calls"].append(call)
            active_position = job["position"]
            persist()  # No worker may exist before the exact planned request is durable.

            def progress(state):
                call["observation"] = copy.deepcopy(state)
                call.update(provider_dispatch_attempted=state.get("provider_dispatch_attempted"),
                            usage_known=state.get("usage_known", False))
                call["lifecycle"].append({"status": state.get("status"),
                                          "provider_dispatch_attempted": state.get("provider_dispatch_attempted"),
                                          "local_process_group_id": state.get("local_process_group_id")})
                persist()  # Existing observer admits a ready worker only after this returns.

            with patch.object(caller, "SETTINGS", SETTINGS):
                state = (observer or caller.observe_request)(
                    job["request"], cli_credentials=cli_credentials,
                    on_progress=progress, timeout=WORKER_SECONDS,
                )
            call["observation"] = state
            call.update(provider_dispatch_attempted=state.get("provider_dispatch_attempted"),
                        usage_known=state.get("usage_known", False))
            usable = runtime._usable_observation(state)
            call["status"] = "completed" if usable else "operational_failure"
            report["results"][job["position"]] = {
                "position": job["position"], "status": call["status"],
                **(content_observer or content_observation)(job, state),
            }
            persist()
            if not usable or persistence_failed:
                report["status"] = "operational_failure"
                break
        else:
            report["status"] = "completed"
    except Exception as error:
        report.update(status="operational_failure", error_type=type(error).__name__)
        if active_position is not None:
            call = report["calls"][-1]
            if call["status"] == "launch_intent":
                call["status"] = "operational_failure"
            report["results"][active_position] = {
                "position": active_position, "status": "operational_failure",
                "error_type": type(error).__name__, "semantic_assessment": "unavailable",
            }
    finally:
        persist()
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--plan-sha256")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    if args.execute:
        if args.plan is None or args.plan_sha256 is None:
            parser.error("Execution requires --plan and --plan-sha256.")
        report = run_probe(args.plan, args.plan_sha256, args.directory,
                           cli_credentials=args.aws_cli_credentials)
        return 0 if report["status"] == "completed" else 1
    if args.plan is not None or args.plan_sha256 is not None or args.aws_cli_credentials:
        parser.error("Dry preparation accepts only a new --directory.")
    plan = make_plan()
    args.directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    shared.write_json(args.directory / "plan.json", plan)
    print(json.dumps({"plan_sha256": _hash(plan), "maximum_calls": MAX_CALLS, "execute": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
