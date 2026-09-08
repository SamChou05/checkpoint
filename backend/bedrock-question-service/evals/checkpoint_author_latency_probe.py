#!/usr/bin/env python3
"""Two author-only transport observations; dry by default, never a resumed trial.

One parent owns durable evidence. Disposable workers send only final text,
sanitized usage and lifecycle signals; they never write captures. A local process
deadline is not evidence of remote cancellation, zero billing or bad content.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import multiprocessing
import os
from pathlib import Path
import selectors
import signal
import socket
import sys
import time

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_immutable_review_eval as recorded  # noqa: E402
from evals import checkpoint_solution_compatibility_eval as shared  # noqa: E402
from evals.question_complete_author import parse_author  # noqa: E402
from evals.question_immutable_review import (  # noqa: E402
    ImmutableReviewContentError,
    ImmutableReviewFormatError,
)

EXPERIMENT = "complete-authoring-latency-observation-v1"
ORIGINS = {
    "plan": "c15d48b270b9c710a96123ba4da334dd25aaf79c28fe05153beba3291bb5626a",
    "capture": "1362b862932ebf7705b1ff7420789ce002f8eb8eb8434bc5cb90a38856ad0e25",
}
CASE_INDEXES = (0, 2)
DEADLINE_SECONDS = 300
MAX_CAPTURE_BYTES = 262144
MAX_INPUT_BYTES = 32000
SETTINGS = {**shared.SETTINGS, "BEDROCK_READ_TIMEOUT_SECONDS": "300"}
_hash, _same = recorded._hash, recorded._same


def make_plan():
    origins = {}
    for name, expected in ORIGINS.items():
        path = SERVICE_DIR.parents[1] / (
            f"docs/evidence/complete-authoring-{name}-20260908.json"
        )
        raw = path.read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError("The exact original evidence files are required.")
        origins[name] = json.loads(raw)
    parent, capture = origins["plan"], origins["capture"]
    if not _same(capture["plan"], parent) or capture["plan_sha256"] != _hash(parent):
        raise ValueError("Original capture and plan do not join.")
    if not _same(SETTINGS, {**parent["settings"], "BEDROCK_READ_TIMEOUT_SECONDS": "300"}):
        raise ValueError("Only the original offline read window may change.")
    jobs = []
    for index in CASE_INDEXES:
        source = parent["jobs"][index]
        request = copy.deepcopy(source["author_request"])
        if (
            request["modelId"] != shared.MODEL
            or request["inferenceConfig"] != {"maxTokens": 16000}
            or request["additionalModelRequestFields"]
            != {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}}
            or shared.text_bytes(request) > MAX_INPUT_BYTES
        ):
            raise ValueError("Original author configuration changed.")
        jobs.append(
            {
                "case_id": source["case_id"],
                "parent_case_index": index,
                "request": request,
                "request_canonical_sha256": _hash(request),
                "input_utf8_bytes": shared.text_bytes(request),
            }
        )
    sources = shared.source_hashes()
    for path in (
        Path(__file__),
        SERVICE_DIR / "evals/checkpoint_immutable_review_eval.py",
        SERVICE_DIR / "evals/question_immutable_review.py",
        SERVICE_DIR / "evals/question_complete_author.py",
    ):
        sources[str(path.relative_to(SERVICE_DIR))] = hashlib.sha256(
            path.read_bytes()
        ).hexdigest()
    return {
        "experiment": EXPERIMENT,
        "origin": {
            "file_sha256": ORIGINS,
            "plan_canonical_sha256": _hash(parent),
            "source_revision": parent["source_revision"],
            "prior_status": capture["status"],
            "description": "New diagnostic: CSS repeats the previously dispatched request; English was preselected from original case 2. Not a resume, replacement result or independent accuracy comparison.",
        },
        "jobs": jobs,
        "settings": SETTINGS,
        "source_revision": shared.source_revision(),
        "source_sha256": sources,
        "dependencies": shared.dependencies(),
        "maximum_calls": 2,
        "maximum_calls_per_case": 1,
        "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": 2 * MAX_INPUT_BYTES,
        "planned_input_utf8_bytes": sum(j["input_utf8_bytes"] for j in jobs),
        "per_worker_deadline_seconds": DEADLINE_SECONDS,
        "maximum_worker_capture_bytes": MAX_CAPTURE_BYTES,
        "maximum_local_reaping_grace_seconds": 0.4,
        "sdk_total_max_attempts": 1,
        "scope": "Author only. Exact original request bodies; only offline socket read window changes from 100 to 300 seconds, with an added process deadline including worker startup and credential resolution. No solver, auditor, streaming, repair, retry, production admission or deployment.",
        "failure_policy": "Provider/transport/cleanup/persistence failure stops later jobs. Completed author text is retained even when incomplete or invalid under content limits; content observations never certify correctness.",
        "timing_scope": "SDK completion interval is distinct from worker lifetime and socket read inactivity. A new response after 100 seconds neither proves a 100-second read timeout would exclude it nor that the old timed-out request would complete. No response leaves content, usage and remote completion unknown. Two serial worker deadlines bound local inference waiting to 600 seconds plus reaping; trusted parent disk/preflight work is not hard real-time.",
    }


def load_frozen_plan(path, approved_hash):
    plan = json.loads(path.read_text())
    if _hash(plan) != approved_hash or not _same(plan, make_plan()):
        raise ValueError("Exact frozen source, origins, requests and dependencies required.")
    return plan


def _send(connection, message):
    encoded = (shared.canonical(message) + "\n").encode("utf-8")
    if len(encoded) > MAX_CAPTURE_BYTES - 2048:
        raise ValueError("WorkerCaptureLimit")
    connection.sendall(encoded)


def _sdk_exchange(connection, request, settings, cli_credentials, *,
                  response_projector=recorded._response):
    """App-owned worker logic; injectable client factory permits offline tests."""
    client, dispatched = None, False
    binding = _hash(request)
    try:
        client = shared.new_client(settings, cli_credentials)
        _send(connection, {"kind": "dispatch", "request_sha256": binding})
        dispatched = True
        started = time.monotonic()
        response = response_projector(client.converse(**request))
        elapsed = time.monotonic() - started
        # The shared projection removes reasoning content. Restrict the remaining
        # provider metadata as well; never serialize headers or exception text.
        usage = response["usage"]
        response["usage"] = (
            {
                k: usage[k]
                for k in (
                    "inputTokens", "outputTokens", "totalTokens",
                    "cacheReadInputTokens", "cacheWriteInputTokens",
                )
                if type(usage.get(k)) is int and usage[k] >= 0
            }
            if type(usage) is dict else None
        )
        if type(response["stopReason"]) is not str:
            response["stopReason"] = None
        _send(connection, {"kind": "response", "request_sha256": binding,
                           "response": response, "sdk_elapsed_seconds": elapsed})
        client.close()
        client = None
        _send(connection, {"kind": "complete", "request_sha256": binding})
    except Exception as error:
        _send(connection, {"kind": "failure", "request_sha256": binding,
                           "error_type": type(error).__name__, "dispatched": dispatched})
    finally:
        if client is not None:
            client.close()


def _worker(connection, request, settings, cli_credentials, deadline, *,
            response_projector=recorded._response):
    # A worker-local alarm backs up the parent's watchdog even if a parent disk
    # write stalls. Its default action terminates this process, not remote work.
    os.setsid()
    signal.signal(signal.SIGALRM, signal.SIG_DFL)
    signal.setitimer(signal.ITIMER_REAL, max(0.001, deadline - time.monotonic()))
    try:
        _send(connection, {"kind": "ready", "request_sha256": _hash(request),
                           "process_group_id": os.getpid()})
        # No client or credential-helper descendant may exist until the parent
        # durably knows which isolated group it owns and permits admission.
        if connection.recv(1) != b"G":
            raise ValueError("Worker admission missing.")
        _sdk_exchange(connection, request, settings, cli_credentials,
                      response_projector=response_projector)
    finally:
        connection.close()


def _group_exists(group_id):
    try:
        os.killpg(group_id, 0)
        return True
    except ProcessLookupError:
        return False


def _cleanup_worker(process, group_id, *, completed, deadline):
    """Clean the confirmed isolated group even after its leader has exited."""
    terminated = False
    if process.pid is None:
        return {"local_worker_reaped": True, "worker_exitcode": None,
                "local_process_group_cleanup_confirmed": True,
                "termination_attempted": False}
    if completed:
        process.join(timeout=min(0.2, max(0, deadline - time.monotonic())))
    try:
        for sig in (signal.SIGTERM, signal.SIGKILL):
            if group_id is not None:
                try:
                    os.killpg(group_id, sig)
                    terminated = True
                except ProcessLookupError:
                    pass
            elif process.is_alive():
                # Before readiness the worker cannot create descendants. Never
                # guess a process group or signal the parent's shared group.
                terminated = True
                try:
                    process.terminate() if sig == signal.SIGTERM else process.kill()
                except ProcessLookupError:
                    pass
            until = time.monotonic() + 0.2
            process.join(timeout=max(0, until - time.monotonic()))
            while group_id is not None and _group_exists(group_id) and time.monotonic() < until:
                time.sleep(min(0.01, max(0, until - time.monotonic())))
            if not process.is_alive() and (group_id is None or not _group_exists(group_id)):
                break
        group_clean = group_id is None or not _group_exists(group_id)
    except OSError:
        # A permissions/OS failure is cleanup uncertainty, never success. A
        # vanished process/group is the normal race handled above.
        group_clean = False
        process.join(timeout=0)
    return {"local_worker_reaped": not process.is_alive(),
            "worker_exitcode": process.exitcode,
            "local_process_group_cleanup_confirmed": group_clean,
            "termination_attempted": terminated}


def observe_request(request, *, cli_credentials=False, on_progress=lambda _: None,
                    worker=_worker, context=None, timeout=DEADLINE_SECONDS):
    """One bounded worker. Only the parent callback may persist observations."""
    receiver, sender = socket.socketpair()
    receiver.setblocking(False)
    context = context or multiprocessing.get_context("spawn")
    started = time.monotonic()
    deadline = started + timeout
    process = context.Process(target=worker, args=(
        sender, copy.deepcopy(request), SETTINGS, cli_credentials, deadline,
    ))
    state = {"status": "running", "error_type": None,
             "provider_dispatch_attempted": None, "usage_known": False}
    buffer, received, stage = bytearray(), 0, "prepared"
    group_id = None
    selector = selectors.DefaultSelector()
    selector.register(receiver, selectors.EVENT_READ)
    try:
        process.start()
        sender.close()
        while time.monotonic() < deadline:
            if not selector.select(max(0, deadline - time.monotonic())):
                break
            chunk = receiver.recv(65536)
            if not chunk:
                state["error_type"] = "WorkerExitedWithoutCompletion"
                break
            received += len(chunk)
            if received > MAX_CAPTURE_BYTES:
                state["error_type"] = "WorkerCaptureLimit"
                break
            buffer.extend(chunk)
            while b"\n" in buffer and time.monotonic() < deadline:
                line, _, buffer = buffer.partition(b"\n")
                message = json.loads(line)
                if type(message) is not dict or message.get("request_sha256") != _hash(request):
                    raise ValueError("Worker request binding mismatch.")
                kind = message.get("kind")
                if kind == "ready" and stage == "prepared":
                    group_id = message.get("process_group_id")
                    if type(group_id) is not int or group_id != process.pid:
                        group_id = None
                        raise ValueError("Worker isolated group binding mismatch.")
                    state["local_process_group_id"] = group_id
                    stage = "ready"
                elif kind == "dispatch" and stage == "ready":
                    stage = "dispatched"
                    state["provider_dispatch_attempted"] = True
                elif kind == "response" and stage == "dispatched":
                    recorded._validate_response_record(message["response"])
                    elapsed = message["sdk_elapsed_seconds"]
                    if type(elapsed) not in (int, float) or not 0 <= elapsed <= timeout:
                        raise ValueError("Invalid SDK interval.")
                    state.update(response=message["response"], sdk_elapsed_seconds=elapsed,
                                 usage_known=recorded._usage_known(message["response"]))
                    stage = "responded"
                elif kind == "complete" and stage == "responded":
                    state.update(status="completed", error_type=None)
                    stage = "complete"
                elif kind == "failure" and stage in ("ready", "dispatched", "responded"):
                    if type(message.get("dispatched")) is not bool or type(message.get("error_type")) is not str:
                        raise ValueError("Malformed worker failure.")
                    if stage != "ready" and not message["dispatched"]:
                        raise ValueError("Worker dispatch accounting mismatch.")
                    state.update(error_type=message["error_type"],
                                 provider_dispatch_attempted=message["dispatched"])
                    stage = "failure"
                else:
                    raise ValueError("Malformed worker message sequence.")
                on_progress(copy.deepcopy(state))
                if stage == "ready" and time.monotonic() < deadline:
                    receiver.sendall(b"G")
                if stage in ("complete", "failure"):
                    break
            if stage in ("complete", "failure"):
                if buffer:
                    raise ValueError("Unexpected trailing worker data.")
                break
    except Exception as error:
        state.update(status="operational_failure", error_type=type(error).__name__)
    finally:
        if state["status"] == "running":
            state.update(status="operational_failure",
                         error_type=state["error_type"] or "ProcessDeadline")
        state.update(_cleanup_worker(process, group_id, completed=stage == "complete", deadline=deadline))
        state.update(process_elapsed_seconds=time.monotonic() - started,
                     remote_completion="unknown" if "response" not in state else "response_observed")
        if state["status"] == "completed" and (state["termination_attempted"] or process.exitcode != 0):
            state.update(status="operational_failure", error_type="WorkerCleanupFailure")
        if not state["local_worker_reaped"] or not state["local_process_group_cleanup_confirmed"]:
            state.update(status="operational_failure", error_type="WorkerCleanupFailure")
        selector.close()
        receiver.close()
        sender.close()
    return state


def content_observation(call):
    """Shape/length only; never supplies a correctness or acceptance verdict."""
    response = call.get("response")
    if response is None:
        return {"status": "unavailable", "semantic_assessment": "unknown"}
    if not response["content_valid"] or response["stopReason"] != "end_turn":
        return {"status": "incomplete_content", "semantic_assessment": "unassessed"}
    try:
        parse_author(response["text"])
        return {"status": "author_contract_valid", "semantic_assessment": "unassessed"}
    except (ImmutableReviewFormatError, ImmutableReviewContentError) as error:
        return {"status": "author_contract_rejected", "reason": str(error),
                "semantic_assessment": "unassessed"}


def run_probe(plan_path, approved_hash, directory, *, cli_credentials=False,
              transport=observe_request):
    plan = load_frozen_plan(plan_path, approved_hash)
    directory.mkdir(parents=True, exist_ok=False)
    report = {"plan": plan, "plan_sha256": approved_hash, "status": "running",
              "calls": [], "results": [{"case_id": j["case_id"], "status": "unattempted"}
                                        for j in plan["jobs"]]}

    def persist():
        shared.write_json(directory / "capture.json", report)

    persist()
    try:
        for index, job in enumerate(plan["jobs"]):
            call = {**copy.deepcopy(job), "status": "launch_intent",
                    "provider_dispatch_attempted": None, "usage_known": False}
            report["calls"].append(call)
            persist()  # No worker exists before this exact request is durable.

            def progress(state):
                call.update(state)
                persist()

            call.update(transport(job["request"], cli_credentials=cli_credentials,
                                  on_progress=progress))
            report["results"][index] = {"case_id": job["case_id"],
                                        **content_observation(call)}
            if "sdk_elapsed_seconds" in call:
                call["completion_window"] = (
                    "within_100_seconds" if call["sdk_elapsed_seconds"] <= 100
                    else "after_100_within_300_seconds"
                )
            persist()
            if call["status"] != "completed":
                report["status"] = "operational_failure"
                break
        else:
            report["status"] = "completed"
    except Exception as error:
        report.update(status="operational_failure", error_type=type(error).__name__)
    finally:
        persist()
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--plan-sha256")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    if args.execute:
        if args.plan is None or args.plan_sha256 is None:
            parser.error("Execution requires the frozen plan and exact canonical hash.")
        report = run_probe(args.plan, args.plan_sha256, args.output,
                           cli_credentials=args.aws_cli_credentials)
        return 0 if report["status"] == "completed" else 1
    if args.plan is not None or args.plan_sha256 is not None or args.aws_cli_credentials:
        parser.error("Dry preparation needs only a new output directory.")
    plan = make_plan()
    args.output.mkdir(parents=True, exist_ok=False)
    shared.write_json(args.output / "plan.json", plan)
    print(json.dumps({"plan_sha256": _hash(plan), "maximum_calls": 2, "execute": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
