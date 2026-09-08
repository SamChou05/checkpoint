#!/usr/bin/env python3
"""Prepare and replay artifact observations; no model or native execution here."""

from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
from pathlib import Path
import sys

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_artifact_authoring_eval as author  # noqa: E402
from evals import checkpoint_execution_evidence_eval as managed  # noqa: E402
from evals import observe_html_artifact as html_transport  # noqa: E402
from evals.html_artifact_question import (  # noqa: E402
    HTMLArtifactError,
    bind_html_observation,
    prepare_html_artifact,
)
from evals.python_artifact_question import (  # noqa: E402
    ArtifactQuestionError,
    bind_python_artifact_question,
    prepare_python_artifact_question,
)
from execution_evidence import (  # noqa: E402
    _reject_constant,
    _unique_object,
    parse_execution_observation,
)
from question_quality import _extract_json_object  # noqa: E402

EXPERIMENT = "artifact-first-observation-v1"
RUNTIME = {"implementation": "cpython", "version": "3.12.13"}
LIMITS = managed.Limits(
    maximum_sessions=2,
    maximum_invokes=2,
    run_timeout_seconds=90,
    case_timeout_seconds=30,
    cleanup_reserve_seconds=5,
)
SOURCES = (
    *author.ADAPTER_SOURCES,
    "execution_evidence.py",
    "evals/checkpoint_execution_evidence_eval.py",
    "evals/checkpoint_artifact_observation_eval.py",
    "evals/observe_html_artifact.py",
)
canonical, digest = author.shared.canonical, author.shared.digest


def _require(condition, reason):
    if not condition:
        raise ValueError(reason)


def _same_json(left, right):
    # Python equality would conflate true/1 and false/0 in frozen JSON records.
    return canonical(left) == canonical(right)


def _read(path):
    raw = Path(path).read_bytes()
    return raw, json.loads(
        raw, object_pairs_hook=_unique_object, parse_constant=_reject_constant
    )


def _source_hashes():
    return {
        **author.source_hashes(),
        **{
            name: hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
            for name in SOURCES
        },
    }


def _author_capture(path):
    raw, capture = _read(path)
    plan = capture["plan"]
    _require(capture["plan_sha256"] == digest(canonical(plan)), "author_plan_hash")
    _require(plan["experiment"] == author.EXPERIMENT, "author_experiment")
    _require(
        plan["fixture_canonical_sha256"] == digest(canonical(plan["fixture"])),
        "author_fixture_hash",
    )
    _require(
        capture["status"] == "completed" and capture["stopped_early"] is False,
        "author_not_completed",
    )
    _require(
        len(capture["calls"]) == len(capture["results"]) == len(plan["jobs"]) == 2,
        "two_author_calls_required",
    )
    current = _source_hashes()
    for name in author.ADAPTER_SOURCES:
        _require(
            plan["source_sha256"].get(name) == current[name],
            "author_adapter_source_changed:" + name,
        )
    _require(len(plan["fixture"]["cases"]) == 2, "two_author_fixtures_required")
    for i, (job, call, result, case) in enumerate(
        zip(
            plan["jobs"],
            capture["calls"],
            capture["results"],
            plan["fixture"]["cases"],
            strict=True,
        )
    ):
        user = (
            "<artifact_authoring_json>\n"
            + json.dumps(case["user_data"], ensure_ascii=False, allow_nan=False)
            + "\n</artifact_authoring_json>"
        )
        expected = author.shared.converse_request(case["system_prompt"], user)
        _require(
            _same_json(job["requests"], {"author": expected})
            and _same_json(call["request"], expected),
            "author_request_join",
        )
        _require(
            type(call["case_index"]) is int
            and call["case_index"] == i
            and call["role"] == "author"
            and call["case_id"]
            == job["case_id"]
            == result["case_id"]
            == case["case_id"],
            "author_identity_join",
        )
        _require(
            job["family"] == result["family"] == case["family"] == author.FAMILIES[i]
            and type(job["fixture_case_index"]) is int
            and job["fixture_case_index"] == i,
            "author_family_join",
        )
        _require(
            job["user_data_canonical_sha256"] == digest(canonical(case["user_data"])),
            "author_context_hash",
        )
        _require(
            call["status"] == "response_received"
            and call["response"]["stopReason"] == "end_turn"
            and result["status"] == "completed"
            and type(result["provider_calls"]) is int
            and result["provider_calls"] == 1,
            "author_completion_join",
        )
        text = call["response"]["text"]
        _require(
            type(text) is list and text and all(type(v) is str for v in text),
            "author_text",
        )
        parsed = author.validate_author(_extract_json_object("\n".join(text)))
        _require(
            _same_json(result["stage_outputs"], {"author": parsed}),
            "author_raw_parsed_join",
        )
    return hashlib.sha256(raw).hexdigest(), capture, current


def prepare_observation_plan(author_capture_path):
    """Bind four ordered author occurrences without repairs or a Git-HEAD check."""
    capture_hash, capture, sources = _author_capture(author_capture_path)
    slots, python_jobs = [], []
    for i, result in enumerate(capture["results"]):
        family = result["family"]
        context = capture["plan"]["fixture"]["cases"][i]["user_data"]
        for j, spec in enumerate(result["stage_outputs"]["author"]["candidates"]):
            slot = {
                "slot_id": f"{family}-{j + 1}",
                "family": family,
                "author_case_index": i,
                "candidate_index": j,
                "candidate_sha256": digest(canonical(spec)),
                "goal": copy.deepcopy(context["goal"]),
                "sourceDocuments": copy.deepcopy(context.get("sourceDocuments", [])),
                "status": "prepared",
                "reason": None,
                "prepared": None,
            }
            try:
                if family == "python":
                    prepared = prepare_python_artifact_question(
                        spec, case_id=slot["slot_id"], runtime=RUNTIME
                    )
                    python_jobs.append(prepared["job"])
                    if not prepared["job"]["eligible"]:
                        slot.update(
                            status="unsupported",
                            reason=prepared["job"]["unsupported_reason"],
                        )
                else:
                    prepared = prepare_html_artifact(spec)
                slot["prepared"] = prepared
            except (ArtifactQuestionError, HTMLArtifactError) as error:
                slot.update(status="unsupported", reason=str(error))
            slots.append(slot)
    python_plan = managed.prepare_plan(python_jobs, LIMITS) if python_jobs else None
    return {
        "experiment": EXPERIMENT,
        "author_capture_sha256": capture_hash,
        "author_plan_sha256": capture["plan_sha256"],
        "source_sha256": sources,
        "runtime": copy.deepcopy(RUNTIME),
        "slots": slots,
        "python_plan": python_plan,
        "python_plan_sha256": managed.digest(managed._json(python_plan))
        if python_plan
        else None,
        "scope": "Four fixed author slots; no repair, retry, replacement, feedback rewrite, semantic certification or production admission. Native routes execute separately only after this plan is frozen. Hashes are correlation checks, not authenticity signatures.",
    }


def validate_observation_plan(plan, author_capture_path):
    _require(
        _same_json(plan, prepare_observation_plan(author_capture_path)),
        "observation_plan_changed",
    )
    return plan


def blind_packet(plan):
    """No family, status, key, feedback, difficulty, or author metadata export."""
    items = []
    for index, slot in enumerate(plan["slots"]):
        prepared = slot["prepared"]
        display = (
            prepared["draft"] if prepared and slot["family"] == "python" else prepared
        )
        items.append(
            {
                "id": f"item-{index + 1}",
                "goal": copy.deepcopy(slot["goal"]),
                "sourceDocuments": copy.deepcopy(slot["sourceDocuments"]),
                "prompt": display["prompt"] if display else None,
                "choices": copy.deepcopy(display["choices"]) if display else [],
            }
        )
    return {"items": items}


def _python_services(plan, report):
    """Verify the recorded managed lifecycle and reconstruct each raw result."""
    native_plan = plan["python_plan"]
    if native_plan is None:
        _require(report is None, "unexpected_python_report")
        return {}
    _require(
        type(report) is dict
        and report.get("outcome") == "completed"
        and report.get("operational_failure") is False,
        "python_not_operationally_complete",
    )
    _require(
        _same_json(report["plan"], native_plan)
        and report["plan_sha256"] == plan["python_plan_sha256"],
        "python_plan_join",
    )
    jobs, calls, results = native_plan["jobs"], report["calls"], report["results"]
    eligible = sum(job["eligible"] for job in jobs)
    _require(
        len(results) == len(jobs)
        and report["unattempted_cases"] == 0
        and len(calls) == eligible * 3
        and report["session_attempts"] == report["invoke_attempts"] == eligible,
        "python_attempt_counts",
    )
    services, sessions, cursor = {}, set(), 0
    for job, result in zip(jobs, results, strict=True):
        _require(result["case_id"] == job["case_id"], "python_result_identity")
        if not job["eligible"]:
            _require(
                result["status"] == "unsupported"
                and result["cleanup"] == "not_started"
                and result["reason"] == job["unsupported_reason"],
                "unsupported_python_result",
            )
            continue
        start, invoke, stop = calls[cursor : cursor + 3]
        cursor += 3
        for record, operation in zip(
            (start, invoke, stop),
            (
                "StartCodeInterpreterSession",
                "InvokeCodeInterpreter",
                "StopCodeInterpreterSession",
            ),
            strict=True,
        ):
            _require(
                record["operation"] == operation
                and record["outcome"] == "completed"
                and record.get("local_worker_stopped") is True,
                "python_operation_failure",
            )
        session = start["response"]["sessionId"]
        _require(
            type(session) is str
            and session
            and session not in sessions
            and result["session_id"] == session
            and result["cleanup"] == "stopped",
            "python_session_or_cleanup",
        )
        sessions.add(session)
        interpreter = managed.INTERPRETER_ID
        _require(
            start["response"]["codeInterpreterIdentifier"] == interpreter
            and stop["response"]["codeInterpreterIdentifier"] == interpreter
            and stop["response"]["sessionId"] == session,
            "python_lifecycle_response",
        )
        start_request, stop_request = start["request"], stop["request"]
        _require(
            set(start_request)
            == {
                "codeInterpreterIdentifier",
                "name",
                "sessionTimeoutSeconds",
                "clientToken",
            }
            and start_request["codeInterpreterIdentifier"] == interpreter
            and start_request["name"] == "checkpoint-objective-evidence"
            and type(start_request["sessionTimeoutSeconds"]) is int
            and start_request["sessionTimeoutSeconds"] == managed.SESSION_TTL_SECONDS
            and type(start_request["clientToken"]) is str
            and start_request["clientToken"],
            "python_start_request",
        )
        _require(
            set(stop_request)
            == {"codeInterpreterIdentifier", "sessionId", "clientToken"}
            and stop_request["codeInterpreterIdentifier"] == interpreter
            and stop_request["sessionId"] == session
            and type(stop_request["clientToken"]) is str
            and stop_request["clientToken"],
            "python_stop_request",
        )
        _require(
            _same_json(
                invoke["request"],
                {
                    "codeInterpreterIdentifier": interpreter,
                    "sessionId": session,
                    "name": "executeCode",
                    "arguments": {
                        "language": "python",
                        "runtime": "python",
                        "code": job["harness_code"],
                    },
                },
            ),
            "python_exact_invoke",
        )
        service = managed._result_from_events(invoke["response"], session)
        observed = parse_execution_observation(job, service)
        _require(
            observed.get("envelope_valid") is True
            and observed.get("operational_failure") is False
            and _same_json(result["evidence"], observed)
            and result["status"] == observed["status"],
            "python_observation_join",
        )
        services[job["case_id"]] = service
    return services


def _html_envelope(job, record):
    """Join the bounded parent process record before trusting its inner tuple."""
    _require(
        type(record) is dict
        and record.get("status") in {"completed", "unsupported"}
        and record.get("reason") == "",
        "html_transport_failure",
    )
    _require(canonical(record["request"]) == canonical(job), "html_request_join")
    stdin = canonical(job) + "\n"
    size = len(stdin.encode("utf-8"))
    _require(
        record["stdin_text"] == stdin
        and record["stdin_sha256"] == digest(stdin)
        and record["stdin_bytes"] == record["stdin_bytes_sent"] == size
        and size <= html_transport.INPUT_BYTES,
        "html_stdin_join",
    )
    _require(
        record["child_started"] is True
        and record["cleanup"]
        == {
            "child_reaped": True,
            "termination_attempted": False,
            "browser_cleanup_confirmed": True,
        }
        and all(type(value) is bool for value in record["cleanup"].values())
        and record["observer_path"] == str(html_transport.OBSERVER)
        and record["process_deadline_seconds"] == html_transport.PROCESS_TIMEOUT_SECONDS
        and record["capture_limit_bytes_per_stream"] == html_transport.CAPTURE_BYTES
        and record["cleanup_grace_seconds"] == html_transport.REAP_GRACE_SECONDS * 3,
        "html_parent_lifecycle",
    )
    for stream in ("stdout", "stderr"):
        raw = base64.b64decode(record[stream + "_base64"], validate=True)
        _require(
            type(record[stream]) is str
            and raw.decode("utf-8") == record[stream]
            and record[stream + "_bytes_seen"]
            == record[stream + "_retained_bytes"]
            == len(raw)
            and len(raw) <= html_transport.CAPTURE_BYTES,
            "html_raw_stream_join",
        )
    envelope = json.loads(
        record["stdout"],
        object_pairs_hook=_unique_object,
        parse_constant=_reject_constant,
    )
    _require(
        canonical(record["envelope"]) == canonical(envelope)
        and html_transport._valid_envelope(envelope, job)
        and envelope["cleanup"] == {"context": "closed", "browser": "closed"}
        and type(record["returncode"]) is int
        and (
            (record["status"], record["returncode"], envelope["status"])
            in {("completed", 0, "observed"), ("unsupported", 1, "unsupported")}
        ),
        "html_parsed_envelope_join",
    )
    return envelope


def bind_observations(
    plan, author_capture_path, *, python_report=None, html_observations=None
):
    """Replay trusted captures only; a failed Python lifecycle blocks HTML."""
    validate_observation_plan(plan, author_capture_path)
    html_observations = {} if html_observations is None else html_observations
    allowed = {
        s["slot_id"]
        for s in plan["slots"]
        if s["family"] == "html" and s["status"] == "prepared"
    }
    _require(
        type(html_observations) is dict and set(html_observations) <= allowed,
        "unexpected_html_slots",
    )
    failure = None
    try:
        services = _python_services(plan, python_report)
    except (KeyError, TypeError, ValueError) as error:
        services, failure = {}, str(error)
    rows = []
    for slot in plan["slots"]:
        row = {
            "slot_id": slot["slot_id"],
            "status": slot["status"],
            "reason": slot["reason"],
            "bundle": None,
        }
        if slot["status"] == "prepared":
            if failure:
                row.update(status="blocked", reason=failure)
            elif slot["family"] == "python":
                bundle = bind_python_artifact_question(
                    slot["prepared"], services[slot["slot_id"]], cleanup_confirmed=True
                )
                row.update(
                    status=bundle["status"], reason=bundle.get("reason"), bundle=bundle
                )
            elif slot["slot_id"] not in html_observations:
                row.update(status="unattempted", reason="html_observation_missing")
            else:
                try:
                    envelope = _html_envelope(
                        slot["prepared"], html_observations[slot["slot_id"]]
                    )
                    if envelope["status"] == "unsupported":
                        row.update(status="unsupported", reason=envelope["reason"])
                    else:
                        bundle = bind_html_observation(slot["prepared"], envelope)
                        row.update(status="bound", bundle=bundle)
                except (HTMLArtifactError, KeyError, TypeError, ValueError) as error:
                    reason = str(error)
                    row.update(
                        status="unmatched"
                        if reason == "observed_answer_not_uniquely_offered"
                        else "inconclusive",
                        reason=reason,
                    )
                    if row["status"] != "unmatched":
                        failure = reason
        rows.append(row)
    return {
        "plan_sha256": digest(canonical(plan)),
        "operational_failure": failure is not None,
        "reason": failure,
        "slots": rows,
        "feedback_assessment": "unassessed",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--author-capture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    plan = prepare_observation_plan(args.author_capture)
    args.output.mkdir(parents=True, exist_ok=False)
    for name, value in (
        ("plan.json", plan),
        ("blinded.json", blind_packet(plan)),
        ("python-plan.json", plan["python_plan"]),
    ):
        if value is not None:
            author.shared.write_json(args.output / name, value)
    for slot in plan["slots"]:
        if slot["family"] == "html" and slot["status"] == "prepared":
            author.shared.write_json(
                args.output / (slot["slot_id"] + "-job.json"), slot["prepared"]
            )
    print(
        json.dumps(
            {
                "plan_sha256": digest(canonical(plan)),
                "python_plan_sha256": plan["python_plan_sha256"],
                "slots": [
                    {"id": s["slot_id"], "status": s["status"], "reason": s["reason"]}
                    for s in plan["slots"]
                ],
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
