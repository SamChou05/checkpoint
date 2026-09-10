#!/usr/bin/env python3
"""Six frozen author-only calls comparing main-explanation guidance.

Dry by default. Reuses runtime request construction and the existing isolated
caller. Capture never parses, repairs, sanitizes, reviews or admits an item.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_runtime_qualification as runtime  # noqa: E402
from request_contract import _normalize_request  # noqa: E402

caller, shared = runtime.caller, runtime.shared
_hash, _same = runtime._hash, runtime._same
EXPERIMENT = "fresh-author-main-capacity-v1"
ARMS = ("main_320", "main_900")
MAX_CALLS, MAX_INPUT_BYTES, WORKER_SECONDS = 6, 32 * 1024, 90
INSTRUCTION = "explanation at most 320"
SETTINGS = {
    **runtime.SETTINGS,
    "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
    "CHECKPOINT_PROMPT_VARIANT": "balanced",
    "GENERATION_ATTEMPTS": "1",
    "MAX_PROVIDER_CALLS_PER_REQUEST": "1",
}


def author_response(response):
    """Retain empty final text and usage as an invalid response observation."""
    projected = runtime.recorded._response(response)
    if type(projected["text"]) is str and not projected["text"].strip():
        projected["content_valid"] = False
    return projected


def author_worker(connection, request, settings, cli_credentials, deadline):
    # The inherited caller passes legacy settings; this experiment freezes its
    # own read75/connect3 client settings without mutating that shared module.
    caller._worker(connection, request, SETTINGS, cli_credentials, deadline,
                   response_projector=author_response)


def _input_bytes(request):
    size = len(shared.canonical(request).encode("utf-8"))
    if size > MAX_INPUT_BYTES:
        raise ValueError("Whole request exceeds the input allowance.")
    return size


def make_plan(packet, *, source_revision=None):
    cases = packet.get("cases") if type(packet) is dict else None
    if (
        type(packet) is not dict or packet.get("experiment") != EXPERIMENT
        or type(cases) is not list or len(cases) != 3
        or any(type(c) is not dict or type(c.get("case_id")) is not str
               or not c["case_id"].strip() for c in cases)
        or len({c["case_id"] for c in cases}) != 3
    ):
        raise ValueError("Exactly three distinct fresh goal cases are required.")
    snapshot = runtime._source_snapshot(source_revision)
    snapshot["source_sha256"]["evals/checkpoint_main_capacity_trial.py"] = hashlib.sha256(
        Path(__file__).read_bytes()
    ).hexdigest()
    jobs = []
    with patch.dict(os.environ, SETTINGS):
        for index, case in enumerate(cases):
            payload = case.get("payload")
            if (
                type(payload) is not dict
                or set(payload) != {"goal", "sourceDocuments", "targetCount", "minimumDifficulty"}
                or type(payload["targetCount"]) is not int or payload["targetCount"] != 2
                or type(payload["minimumDifficulty"]) is not int or payload["minimumDifficulty"] != 3
                or type(payload["sourceDocuments"]) is not list
            ):
                raise ValueError("Each payload supplies only a goal, sources, count two and difficulty three.")
            normalized = _normalize_request(copy.deepcopy(payload))
            # Metadata outside payload never enters the request. Preserve the
            # exact supplied reference wording and its partial-source marker.
            fields = ("name", "text", "truncated")
            original = [{k: d.get(k, False if k == "truncated" else None) for k in fields}
                        for d in payload["sourceDocuments"]]
            actual = [{k: d.get(k, False if k == "truncated" else None) for k in fields}
                      for d in normalized["sourceDocuments"]]
            if original != actual:
                raise ValueError("Source text or completeness changed during normalization.")
            request = runtime._first_request(normalized, settings=SETTINGS)
            system = request["system"][0]["text"]
            if system.count(INSTRUCTION) != 1:
                raise ValueError("The single exact main-budget instruction is required.")
            for arm in ARMS if index % 2 == 0 else ARMS[::-1]:
                authored = copy.deepcopy(request)
                if arm == "main_900":
                    authored["system"][0]["text"] = system.replace(INSTRUCTION, "explanation at most 900")
                jobs.append({
                    "case_index": index, "case_id": case["case_id"], "arm": arm,
                    "normalized_request": copy.deepcopy(normalized),
                    "normalized_request_sha256": _hash(normalized),
                    "request": authored, "request_sha256": _hash(authored),
                    "input_utf8_bytes": _input_bytes(authored),
                })
    return {
        "experiment": EXPERIMENT, "fixture": copy.deepcopy(packet), "fixture_sha256": _hash(packet),
        **snapshot, "settings": copy.deepcopy(SETTINGS), "jobs": jobs,
        "maximum_calls": MAX_CALLS, "maximum_calls_per_job": 1,
        "requested_items_per_job": 2, "requested_minimum_difficulty": 3,
        "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": MAX_CALLS * MAX_INPUT_BYTES,
        "planned_input_utf8_bytes": sum(j["input_utf8_bytes"] for j in jobs),
        "worker_timeout_seconds": WORKER_SECONDS, "sdk_read_timeout_seconds": 75,
        "sdk_connect_timeout_seconds": 3, "sdk_total_max_attempts": 1,
        "maximum_worker_capture_bytes": caller.MAX_CAPTURE_BYTES,
        "failure_policy": "Operational, unfinished response, cleanup or persistence failure stops later jobs. No retry, repair, fallback, top-up, replacement or resume. Completed malformed author text is retained and does not stop later jobs.",
        "scope": "Author-only paired guidance of 320 versus 900 characters; all raw items require independent post-run assessment before virtual 420/900 main-length observations. No parsing, semantic validation, production admission, source acquisition or deployment in this runner.",
        "timing_scope": "Six serial local workers, each at most 90 seconds plus bounded cleanup; SDK read timeout 75, connect timeout 3, and one attempt. Parent persistence is not hard real-time. Local termination does not establish remote cancellation or zero billing.",
    }


def load_plan(path, approved_hash, *, plan_builder=make_plan):
    plan = json.loads(Path(path).read_text())
    if _hash(plan) != approved_hash or not _same(
        plan, plan_builder(plan["fixture"], source_revision=plan.get("source_revision"))
    ):
        raise ValueError("Exact frozen source, fixture, requests, settings and dependencies required.")
    return plan


def run(plan, directory, *, cli_credentials=False, transport=caller.observe_request,
        plan_builder=make_plan):
    if not _same(plan, plan_builder(plan["fixture"], source_revision=plan.get("source_revision"))):
        raise ValueError("Plan no longer matches current sources.")
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    report = {"plan": copy.deepcopy(plan), "plan_sha256": _hash(plan),
              "status": "running", "calls": []}

    def persist():
        shared.write_json(directory / "capture.json", report)

    persist()
    try:
        for job_index, job in enumerate(plan["jobs"]):
            request = copy.deepcopy(job["request"])
            call = {"job_index": job_index, "case_index": job["case_index"],
                    "case_id": job["case_id"], "arm": job["arm"], "request": request,
                    "request_sha256": _hash(request), "input_utf8_bytes": _input_bytes(request),
                    "worker_timeout_seconds": WORKER_SECONDS, "status": "launch_intent"}
            report["calls"].append(call)
            persist()  # No worker exists before its exact request is durable.

            def progress(state):
                call["observation"] = copy.deepcopy(state)
                persist()

            call["observation"] = transport(
                request, cli_credentials=cli_credentials, on_progress=progress,
                worker=author_worker, timeout=WORKER_SECONDS,
            )
            call["status"] = "observed"
            persist()  # Preserve every returned response before any disposition.
            if not runtime._usable_observation(call["observation"]):
                report["status"] = "operational_failure"
                break
        else:
            report["status"] = "completed"
    except Exception as error:
        report.update(status="operational_failure", error_type=type(error).__name__)
    finally:
        persist()
    return report


def replay_capture(report, *, plan_builder=make_plan):
    """Replay terminal captures through the same runner with no provider client."""
    if (
        type(report) is not dict or report.get("status") not in {"completed", "operational_failure"}
        or report.get("plan_sha256") != _hash(report.get("plan"))
        or type(report.get("calls")) is not list
        or any(type(c) is not dict or "observation" not in c for c in report["calls"])
    ):
        raise ValueError("A terminal complete observation capture is required.")
    calls = iter(report["calls"])

    def transport(request, **kwargs):
        call = next(calls)
        if (not _same(call["request"], request) or call["request_sha256"] != _hash(request)
                or call["worker_timeout_seconds"] != kwargs["timeout"]):
            raise ValueError("Recorded request or timeout mismatch.")
        return copy.deepcopy(call["observation"])

    with tempfile.TemporaryDirectory() as directory:
        derived = run(report["plan"], Path(directory) / "replay", transport=transport,
                      plan_builder=plan_builder)
    if not _same(derived, report):
        raise ValueError("Replay differs; incomplete persistence captures cannot be promoted.")
    return derived


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--execute", metavar="CANONICAL_PLAN_SHA256")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    if args.execute:
        if args.fixture is not None or args.output is None:
            parser.error("Execute needs an existing frozen plan and fresh output directory.")
        report = run(load_plan(args.plan, args.execute), args.output,
                     cli_credentials=args.aws_cli_credentials)
        return 0 if report["status"] == "completed" else 1
    if args.fixture is None or args.output is not None or args.aws_cli_credentials:
        parser.error("Dry preparation needs only fixture and new plan path.")
    if args.plan.exists():
        parser.error("Plan path already exists.")
    plan = make_plan(json.loads(args.fixture.read_text()))
    shared.write_json(args.plan, plan)
    print(json.dumps({"plan_sha256": _hash(plan), "maximum_calls": MAX_CALLS, "execute": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
