#!/usr/bin/env python3
"""Eval-only, bounded direct AgentCore transport. No model or production path.

Requests are durable before dispatch. Each SDK operation runs in a disposable
local subprocess so a blocked socket or event stream cannot extend its caller
deadline indefinitely. Killing that subprocess cancels local waiting, not remote
execution; finally-stop and the absolute service TTL are separate safeguards.
"""

from __future__ import annotations

import argparse
import copy
from dataclasses import asdict, dataclass
from datetime import date, datetime
import hashlib
import json
import multiprocessing
import os
import re
import selectors
import socket
from pathlib import Path
import sys
import tempfile
import time
import uuid

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

INTERPRETER_ID = "aws.codeinterpreter.v1"
SESSION_TTL_SECONDS = 60
HARD_MAX_SESSIONS = 16
HARD_MAX_INVOKES = 16
MAX_HARNESS_BYTES = 64 * 1024


@dataclass(frozen=True)
class Limits:
    maximum_sessions: int = 6
    maximum_invokes: int = 6
    run_timeout_seconds: float = 180
    case_timeout_seconds: float = 20
    cleanup_reserve_seconds: float = 5
    max_events: int = 16
    max_capture_bytes: int = 32 * 1024

    def validate(self):
        for value, ceiling in (
            (self.maximum_sessions, HARD_MAX_SESSIONS),
            (self.maximum_invokes, HARD_MAX_INVOKES),
            (self.max_events, 128),
            (self.max_capture_bytes, 1024 * 1024),
        ):
            if type(value) is not int or not 1 <= value <= ceiling:
                raise ValueError("Integer limit is outside the evaluation ceiling.")
        if not (
            0 < self.cleanup_reserve_seconds < self.case_timeout_seconds <= 60
            and self.case_timeout_seconds <= self.run_timeout_seconds <= 1200
        ):
            raise ValueError("Invalid case, run, or cleanup deadline.")


def _json(value):
    def default(item):
        if isinstance(item, (datetime, date)):
            return item.isoformat()
        raise TypeError("Unsupported capture value.")

    return json.dumps(value, ensure_ascii=False, sort_keys=True, default=default)


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class DurableCapture:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # A previous attempt must never be silently replaced or resumed.
        with self.path.open("x", encoding="utf-8"):
            pass

    def write(self, report):
        data = _json(report) + "\n"
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=self.path.parent, delete=False
            ) as handle:
                temporary = handle.name
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, self.path)
            temporary = None
            directory = os.open(self.path.parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            if temporary is not None:
                os.unlink(temporary)


def _bounded_json(value, byte_limit):
    """Reject oversized capture, including a single decoded SDK event.

    The SDK has already materialized an individual event before this check.
    This bounds retained data, not the service's or decoder's peak allocation.
    """
    encoded = _json(value).encode("utf-8")
    if len(encoded) > byte_limit:
        raise ValueError("capture_limit")
    return json.loads(encoded)


def _client_config(timeout_seconds):
    from botocore.config import Config

    return Config(
        connect_timeout=min(3.0, timeout_seconds / 3),
        read_timeout=max(0.001, timeout_seconds * 2 / 3),
        retries={"total_max_attempts": 1, "mode": "standard"},
    )


def _send_message(connection, message):
    connection.sendall((_json(message) + "\n").encode("utf-8"))


def _sdk_worker(connection, operation, request, region, timeout_seconds, limits):
    """Child sends bounded observations; it never persists credentials/headers."""
    client = None
    stream = None
    try:
        import boto3

        client = boto3.client(
            "bedrock-agentcore",
            region_name=region,
            config=_client_config(timeout_seconds),
        )
        method = {
            "StartCodeInterpreterSession": client.start_code_interpreter_session,
            "InvokeCodeInterpreter": client.invoke_code_interpreter,
            "StopCodeInterpreterSession": client.stop_code_interpreter_session,
        }[operation]
        response = method(**request)
        metadata = response.pop("ResponseMetadata", {})
        request_id = metadata.get("RequestId")
        if operation != "InvokeCodeInterpreter":
            _send_message(
                connection,
                {
                    "kind": "response",
                    "response": _bounded_json(response, limits.max_capture_bytes),
                    "request_id": request_id,
                },
            )
        else:
            stream = response.get("stream")
            if stream is None:
                raise ValueError("missing_stream")
            _send_message(
                connection,
                {
                    "kind": "response",
                    "response": {"sessionId": response.get("sessionId"), "events": []},
                    "request_id": request_id,
                },
            )
            used_bytes = 0
            for index, event in enumerate(stream):
                if index >= limits.max_events:
                    raise ValueError("event_limit")
                event = _bounded_json(event, limits.max_capture_bytes - used_bytes)
                used_bytes += len(_json(event).encode("utf-8"))
                _send_message(connection, {"kind": "event", "event": event})
        _send_message(connection, {"kind": "complete"})
    except Exception as error:
        # Exception strings may contain code, headers, or endpoint details.
        reason = (
            str(error)
            if type(error) is ValueError
            and str(error) in {"capture_limit", "event_limit", "missing_stream"}
            else "provider_error"
        )
        failure = {
            "kind": "failure",
            "reason": reason,
            "error_type": type(error).__name__,
        }
        response = getattr(error, "response", None)
        if isinstance(response, dict):
            code = response.get("Error", {}).get("Code")
            if isinstance(code, str) and re.fullmatch(
                r"[A-Za-z][A-Za-z0-9_]{0,127}", code
            ):
                failure["provider_error_code"] = code
        _send_message(connection, failure)
    finally:
        if stream is not None and hasattr(stream, "close"):
            stream.close()
        if client is not None:
            client.close()
        connection.close()


class SubprocessExecutor:
    """One SDK attempt per call, bounded independently of streaming progress."""

    def __init__(self, region="us-east-1", context=None, worker=_sdk_worker):
        self.region = region
        self.context = context or multiprocessing.get_context("spawn")
        self.worker = worker

    def __call__(self, operation, request, timeout_seconds, limits, on_progress):
        receiver, sender = socket.socketpair()
        receiver.setblocking(False)
        process = self.context.Process(
            target=self.worker,
            args=(sender, operation, request, self.region, timeout_seconds, limits),
            daemon=True,
        )
        result = {"outcome": "inconclusive", "reason": "deadline", "response": None}
        deadline = time.monotonic() + timeout_seconds
        used_bytes = 0
        buffer = bytearray()
        # Own newline-JSON framing keeps reads nonblocking even for partial IPC
        # messages. Connection.poll()+recv() would still block on a partial frame.
        frame_limit = limits.max_capture_bytes + 4096
        selector = selectors.DefaultSelector()
        selector.register(receiver, selectors.EVENT_READ)
        done = False
        try:
            process.start()
            sender.close()
            while not done and time.monotonic() < deadline:
                if not selector.select(max(0, deadline - time.monotonic())):
                    break
                chunk = receiver.recv(min(65536, frame_limit + 1))
                if not chunk:
                    result["reason"] = "worker_exit_without_completion"
                    break
                buffer.extend(chunk)
                while b"\n" in buffer and time.monotonic() < deadline:
                    line, _, remainder = buffer.partition(b"\n")
                    buffer = bytearray(remainder)
                    if len(line) > frame_limit:
                        result["reason"] = "capture_limit"
                        done = True
                        break
                    try:
                        message = json.loads(line)
                    except (ValueError, UnicodeError):
                        result["reason"] = "malformed_worker_message"
                        done = True
                        break
                    kind = message.get("kind") if isinstance(message, dict) else None
                    if kind == "response":
                        result["response"] = message["response"]
                        result["request_id"] = message.get("request_id")
                    elif kind == "event":
                        events = (result.get("response") or {}).get("events")
                        if events is None:
                            result["reason"] = "malformed_stream"
                            done = True
                            break
                        encoded_size = len(_json(message["event"]).encode("utf-8"))
                        if (
                            len(events) >= limits.max_events
                            or used_bytes + encoded_size > limits.max_capture_bytes
                        ):
                            result["reason"] = "capture_limit"
                            done = True
                            break
                        used_bytes += encoded_size
                        events.append(message["event"])
                    elif kind == "complete":
                        result.update(outcome="completed", reason=None)
                        done = True
                        break
                    elif kind == "failure":
                        result.update(
                            reason=message["reason"],
                            error_type=message.get("error_type"),
                            provider_error_code=message.get("provider_error_code"),
                        )
                        done = True
                        break
                    else:
                        result["reason"] = "malformed_worker_message"
                        done = True
                        break
                    on_progress(copy.deepcopy(result))
                if len(buffer) > frame_limit:
                    result["reason"] = "capture_limit"
                    break
        finally:
            # At most 0.4 seconds of local termination/reaping grace. This is
            # not a remote cancellation assertion; Stop is still mandatory.
            if process.pid is not None:
                if process.is_alive():
                    process.terminate()
                process.join(timeout=0.2)
                if process.is_alive():
                    process.kill()
                    process.join(timeout=0.2)
                result["local_worker_stopped"] = not process.is_alive()
            selector.close()
            receiver.close()
            sender.close()
        if result.get("local_worker_stopped") is not True:
            result.update(outcome="inconclusive", reason="local_worker_cleanup_failed")
        return result


def prepare_plan(jobs, limits=None, region="us-east-1"):
    """Prepare data only. Harness construction and evidence parsing stay separate."""
    limits = limits or Limits()
    limits.validate()
    if not isinstance(jobs, list) or not jobs:
        raise ValueError("At least one prepared case is required.")
    ids = [job.get("case_id") for job in jobs]
    if any(not isinstance(identifier, str) or not identifier for identifier in ids):
        raise ValueError("Each case needs a nonempty identifier.")
    if len(set(ids)) != len(ids):
        raise ValueError("Case identifiers must be unique.")
    supported_count = 0
    for job in jobs:
        if job.get("eligible") is False:
            if (
                not isinstance(job.get("unsupported_reason"), str)
                or not job["unsupported_reason"]
            ):
                raise ValueError("Unsupported cases need a reason.")
            continue
        if job.get("eligible") is not True:
            raise ValueError("Each job needs explicit harness eligibility.")
        code = job.get("harness_code")
        if (
            not isinstance(code, str)
            or not 0 < len(code.encode("utf-8")) <= MAX_HARNESS_BYTES
        ):
            raise ValueError("Missing or oversized trusted harness.")
        if job.get("harness_sha256") != digest(code):
            raise ValueError("Trusted harness does not match its recorded hash.")
        supported_count += 1
    if supported_count > min(limits.maximum_sessions, limits.maximum_invokes):
        raise ValueError("Plan exceeds the explicit session or invoke ceiling.")
    return {
        "schema_version": 1,
        "region": region,
        "interpreter_id": INTERPRETER_ID,
        "session_ttl_seconds": SESSION_TTL_SECONDS,
        "sdk_total_max_attempts": 1,
        "limits": asdict(limits),
        "jobs": copy.deepcopy(jobs),
    }


def _result_from_events(response, session_id):
    # Verified against the current API and Botocore 1.43.89 shape:
    # https://docs.aws.amazon.com/bedrock-agentcore/latest/APIReference/API_ToolResultStructuredContent.html
    # Only documented AgentCore stdout/stderr/exitCode are normalized here;
    # stdOut/stdErr below are our parser interface, not additional wire aliases.
    if not isinstance(response, dict) or response.get("sessionId") != session_id:
        raise ValueError("session_mismatch")
    events = response.get("events")
    if not isinstance(events, list) or len(events) != 1:
        raise ValueError("unexpected_result_count")
    event = events[0]
    if not isinstance(event, dict) or set(event) != {"result"}:
        raise ValueError("stream_error_or_unknown_event")
    result = event["result"]
    if not isinstance(result, dict) or result.get("isError") is not False:
        raise ValueError("tool_error_or_missing_success")
    structured = result.get("structuredContent")
    if not isinstance(structured, dict):
        raise ValueError("missing_structured_result")
    # executeCode has no requested async task ID. The matching session and
    # completed synchronous stream are required; optional task metadata cannot
    # report pending/failed work or an uncorrelated empty task identifier.
    task_status = structured.get("taskStatus")
    task_id = structured.get("taskId")
    if task_status not in (None, "completed"):
        raise ValueError("unfinished_task")
    if task_id is not None and (
        not isinstance(task_id, str) or not task_id or task_status != "completed"
    ):
        raise ValueError("invalid_task_metadata")
    if type(structured.get("exitCode")) is not int or structured["exitCode"] != 0:
        raise ValueError("harness_exit_failure")
    stdout = structured.get("stdout")
    if not isinstance(stdout, str) or structured.get("stderr") not in (None, ""):
        raise ValueError("malformed_harness_output")
    return {
        "stdOut": stdout,
        "stdErr": structured.get("stderr") or "",
        "exitCode": structured["exitCode"],
        "isError": result["isError"],
    }


def run_plan(plan, output, parse_evidence, *, executor=None, clock=time.monotonic):
    """Execute a reviewed plan; any provider/cleanup failure stops the run.

    parse_evidence(job, service_result) must validate the harness's artifact-bound record
    and return status observed/unsupported/inconclusive. It must not infer MCQ
    rejection from transport, timeout, or parsing failures.
    """
    limits = Limits(**plan["limits"])
    if prepare_plan(plan["jobs"], limits, plan["region"]) != plan:
        raise ValueError("Plan differs from the supported immutable contract.")
    execute = executor or SubprocessExecutor(plan["region"])
    capture = DurableCapture(output)
    started = clock()
    deadline = started + limits.run_timeout_seconds
    report = {
        "plan": copy.deepcopy(plan),
        "plan_sha256": digest(_json(plan)),
        "calls": [],
        "results": [],
        "session_attempts": 0,
        "invoke_attempts": 0,
        "outcome": "running",
        "operational_failure": False,
        # AgentCore does not provide token or measured CPU/memory billing here.
        "usage": {
            "session_seconds": None,
            "vcpu_seconds": None,
            "memory_gb_seconds": None,
        },
    }
    capture.write(report)

    def persist(*, required=True):
        report["elapsed_seconds"] = round(clock() - started, 6)
        try:
            capture.write(report)
        except Exception as error:
            report["capture_failed"] = True
            report["capture_error_type"] = type(error).__name__
            report["operational_failure"] = True
            report["outcome"] = "failed"
            if report["results"]:
                report["results"][-1].update(
                    status="inconclusive", reason="capture_failed"
                )
            if required:
                raise

    def call(
        operation,
        request,
        call_deadline,
        *,
        on_response=lambda value: None,
        emergency_cleanup=False,
    ):
        remaining = call_deadline - clock()
        if remaining <= 0:
            return {
                "outcome": "inconclusive",
                "reason": "admission_deadline",
                "response": None,
            }
        counter = {
            "StartCodeInterpreterSession": (
                "session_attempts",
                limits.maximum_sessions,
            ),
            "InvokeCodeInterpreter": ("invoke_attempts", limits.maximum_invokes),
        }.get(operation)
        if counter:
            key, maximum = counter
            if report[key] >= maximum:
                return {
                    "outcome": "inconclusive",
                    "reason": "call_cap",
                    "response": None,
                }
            report[key] += 1
        record = {
            "operation": operation,
            "request": copy.deepcopy(request),
            "outcome": "dispatch_pending",
            "timeout_seconds": remaining,
            "attempted_remote_usage": None,
        }
        report["calls"].append(record)
        # Evaluation calls require durable intent. Emergency Stop is the only
        # exception: a broken disk must not strand a known paid session.
        persist(required=not emergency_cleanup)

        def progress(observation):
            record["partial"] = observation
            on_response(observation)  # Adopt a known session before a sink can fail.
            persist(required=not emergency_cleanup)

        try:
            remaining = call_deadline - clock()
            if remaining <= 0:
                outcome = {
                    "outcome": "inconclusive",
                    "reason": "admission_deadline_after_capture",
                    "response": None,
                }
            else:
                outcome = execute(
                    operation, copy.deepcopy(request), remaining, limits, progress
                )
        except Exception as error:
            outcome = {
                "outcome": "inconclusive",
                "reason": "executor_error",
                "error_type": type(error).__name__,
                "response": None,
            }
        if (
            outcome.get("response") is None
            and record.get("partial", {}).get("response") is not None
        ):
            outcome["response"] = copy.deepcopy(record["partial"]["response"])
        on_response(outcome)
        record.update(outcome)
        persist(required=not emergency_cleanup)
        return outcome

    for job in plan["jobs"]:
        result = {
            "case_id": job["case_id"],
            "status": "inconclusive",
            "cleanup": "not_started",
        }
        report["results"].append(result)
        if job.get("eligible") is False:
            result.update(status="unsupported", reason=job["unsupported_reason"])
            persist()
            continue
        if deadline - clock() < limits.case_timeout_seconds:
            result.update(reason="admission_deadline")
            report["operational_failure"] = True
            break
        case_deadline = min(deadline, clock() + limits.case_timeout_seconds)
        work_deadline = case_deadline - limits.cleanup_reserve_seconds
        session_id = None

        def remember_session(observation):
            nonlocal session_id
            response = observation.get("response") or {}
            possible_id = response.get("sessionId")
            if isinstance(possible_id, str) and possible_id:
                session_id = possible_id
                result["session_id"] = session_id

        try:
            start = call(
                "StartCodeInterpreterSession",
                {
                    "codeInterpreterIdentifier": INTERPRETER_ID,
                    "name": "checkpoint-objective-evidence",
                    "sessionTimeoutSeconds": SESSION_TTL_SECONDS,
                    "clientToken": str(uuid.uuid4()),
                },
                work_deadline,
                on_response=remember_session,
            )
            response = start.get("response") or {}
            possible_id = response.get("sessionId")
            if isinstance(possible_id, str) and possible_id:
                session_id = possible_id
                result["session_id"] = session_id
            if start["outcome"] != "completed":
                result["reason"] = start["reason"]
                result["cleanup"] = (
                    "session_id_unknown" if session_id is None else "pending"
                )
                raise ValueError("start_failed")
            if (
                session_id is None
                or response.get("codeInterpreterIdentifier") != INTERPRETER_ID
            ):
                raise ValueError("malformed_start")
            invocation = call(
                "InvokeCodeInterpreter",
                {
                    "codeInterpreterIdentifier": INTERPRETER_ID,
                    "sessionId": session_id,
                    "name": "executeCode",
                    "arguments": {
                        "language": "python",
                        "runtime": "python",
                        "code": job["harness_code"],
                    },
                },
                work_deadline,
            )
            if invocation["outcome"] != "completed":
                result["reason"] = invocation["reason"]
                raise ValueError("invoke_failed")
            service_result = _result_from_events(invocation.get("response"), session_id)
            evidence = parse_evidence(copy.deepcopy(job), service_result)
            if not isinstance(evidence, dict) or evidence.get("status") not in {
                "observed",
                "unsupported",
                "inconclusive",
            }:
                raise ValueError("invalid_evidence_status")
            result.update(status=evidence["status"], evidence=evidence)
            if evidence["status"] == "inconclusive":
                report["operational_failure"] = True
        except Exception as error:
            result.update(status="inconclusive", error_type=type(error).__name__)
            result.setdefault("reason", "invalid_or_failed_observation")
            report["operational_failure"] = True
        finally:
            if session_id is not None:
                stopped = call(
                    "StopCodeInterpreterSession",
                    {
                        "codeInterpreterIdentifier": INTERPRETER_ID,
                        "sessionId": session_id,
                        "clientToken": str(uuid.uuid4()),
                    },
                    case_deadline,
                    emergency_cleanup=True,
                )
                stop_response = stopped.get("response") or {}
                if (
                    stopped["outcome"] == "completed"
                    and stop_response.get("sessionId") == session_id
                    and stop_response.get("codeInterpreterIdentifier") == INTERPRETER_ID
                ):
                    result["cleanup"] = "stopped"
                else:
                    result.update(
                        status="inconclusive",
                        cleanup="failed",
                        cleanup_reason=stopped.get("reason") or "malformed_stop",
                    )
                    report["operational_failure"] = True
            persist(required=False)
        if report["operational_failure"]:
            break
    report["outcome"] = "failed" if report["operational_failure"] else "completed"
    report["unattempted_cases"] = len(plan["jobs"]) - len(report["results"])
    persist(required=False)
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--approved-plan-sha256")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)

    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate plan key")
            result[key] = value
        return result

    try:
        if args.plan.stat().st_size > 2 * 1024 * 1024:
            raise ValueError("Prepared plan exceeds the capture ceiling")
        plan = json.loads(
            args.plan.read_text(encoding="utf-8"), object_pairs_hook=unique_object
        )
        rebuilt = prepare_plan(plan["jobs"], Limits(**plan["limits"]), plan["region"])
        if rebuilt != plan:
            raise ValueError("Plan differs from the supported immutable contract")
        plan_hash = digest(_json(plan))
    except (OSError, ValueError, TypeError, KeyError) as error:
        parser.error("Invalid prepared plan: " + type(error).__name__)
    summary = {
        "plan_sha256": plan_hash,
        "cases": len(plan["jobs"]),
        "eligible_cases": sum(job["eligible"] for job in plan["jobs"]),
        "region": plan["region"],
        "session_ttl_seconds": plan["session_ttl_seconds"],
        "limits": plan["limits"],
        "mode": "execute" if args.execute else "dry_run",
    }
    if not args.execute:
        print(_json(summary))
        return 0
    if args.approved_plan_sha256 != plan_hash:
        parser.error("Execution requires the exact reviewed --approved-plan-sha256")
    if args.output is None or args.output.exists():
        parser.error("Execution requires a new --output file")
    from execution_evidence import parse_execution_observation

    if args.aws_cli_credentials:
        from evals.checkpoint_prompt_ablation import use_aws_cli_credentials

        use_aws_cli_credentials()
    report = run_plan(plan, args.output, parse_execution_observation)
    print(
        _json(
            {
                **summary,
                "outcome": report["outcome"],
                "session_attempts": report["session_attempts"],
                "invoke_attempts": report["invoke_attempts"],
            }
        )
    )
    return 1 if report["operational_failure"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
