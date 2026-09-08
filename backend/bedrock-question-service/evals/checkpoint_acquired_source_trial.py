#!/usr/bin/env python3
"""At most three fresh source-backed items: author then immutable audit.

Dry by default. Uses the existing bounded process caller unchanged, with no
repair, retry, resume, production stamps, source fetching or native execution.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import acquired_source_review as audit  # noqa: E402
from evals import checkpoint_author_latency_probe as caller  # noqa: E402
from evals.question_complete_author import author_prompt, parse_author  # noqa: E402
from evals.question_immutable_review import (  # noqa: E402
    ImmutableReviewContentError,
    ImmutableReviewFormatError,
)

shared, recorded = caller.shared, caller.recorded
_hash, _same = recorded._hash, recorded._same
EXPERIMENT = "acquired-source-fresh-authoring-v1"
MAX_CALLS, MAX_INPUT_BYTES, MAX_TOTAL_INPUT_BYTES = 6, 32000, 192000
AUTHOR_SOURCE_INSTRUCTION = """
The acquiredSources packet is exact server-acquired text, not a model summary.
Use its substantive material while respecting source metadata, extraction limits,
truncation and omitted text. An excerpt does not establish that omitted exceptions
are absent. Keep the task self-contained, preserve every necessary qualification,
and ground all teaching explanations without inventing stronger claims.
""".strip()


def _author_request(case):
    context = case["context"]
    system, user = author_prompt({"goal": context["goal"], "sourceDocuments": []}, 3)
    data = json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])
    data["acquiredSources"] = audit.prepare_sources(case["records"], case["selections"])
    user = (
        "<complete_question_author_json>\n"
        + shared.canonical(data)
        + "\n</complete_question_author_json>"
    )
    return shared.converse_request(system + "\n\n" + AUTHOR_SOURCE_INSTRUCTION, user)


def _guard_request(request):
    if not _same(
        request,
        shared.converse_request(
            request["system"][0]["text"], request["messages"][0]["content"][0]["text"]
        ),
    ):
        raise ValueError("Provider request shape/settings changed.")
    if shared.text_bytes(request) > MAX_INPUT_BYTES:
        raise ValueError("Input allowance exceeded.")


def make_plan(packet, *, source_revision=None):
    revision = shared.source_revision() if source_revision is None else source_revision
    if type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("A full frozen commit identity is required.")
    if subprocess.run(
        ["git", "cat-file", "-e", revision + "^{commit}"],
        cwd=SERVICE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode:
        raise ValueError("Frozen source revision does not resolve to a commit.")
    cases = packet.get("cases") if type(packet) is dict else None
    if (
        type(packet) is not dict
        or packet.get("experiment") != EXPERIMENT
        or type(cases) is not list
        or not 1 <= len(cases) <= 3
        or any(
            type(c) is not dict or type(c.get("case_id")) is not str or not c["case_id"]
            for c in cases
        )
        or len({c["case_id"] for c in cases}) != len(cases)
    ):
        raise ValueError("One to three distinct source-backed goals are required.")
    jobs = []
    for case in cases:
        context = case["context"]
        if (
            type(context.get("minimumDifficulty")) is not int
            or context["minimumDifficulty"] != 3
        ):
            raise ValueError("Every goal must request minimum difficulty three.")
        request = _author_request(case)
        _guard_request(request)
        jobs.append(
            {
                "case_id": case["case_id"],
                "author_request": request,
                "author_request_sha256": _hash(request),
                "source_packet_sha256": _hash(
                    audit.prepare_sources(case["records"], case["selections"])
                ),
            }
        )
    sources = shared.source_hashes()
    for name in (
        "evals/checkpoint_acquired_source_trial.py",
        "evals/acquired_source_review.py",
        "evals/checkpoint_author_latency_probe.py",
        "evals/checkpoint_immutable_review_eval.py",
        "evals/question_complete_author.py",
        "evals/question_immutable_review.py",
    ):
        sources[name] = hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
    return {
        "experiment": EXPERIMENT,
        "fixture": copy.deepcopy(packet),
        "fixture_sha256": _hash(packet),
        "jobs": jobs,
        "source_revision": revision,
        "source_sha256": sources,
        "dependencies": shared.dependencies(),
        "settings": copy.deepcopy(caller.SETTINGS),
        "model": shared.MODEL,
        "maximum_calls": len(cases) * 2,
        "maximum_calls_per_case": 2,
        "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": MAX_TOTAL_INPUT_BYTES,
        "sdk_total_max_attempts": 1,
        "worker_deadline_seconds": caller.DEADLINE_SECONDS,
        "maximum_worker_capture_bytes": caller.MAX_CAPTURE_BYTES,
        "failure_policy": "Provider, unfinished response, binding, cleanup or persistence failure stops all later dispatch. Author/audit content-contract, evidence or difficulty rejection ends its case and proceeds. A derived audit exceeding input budget is a case-level input_budget_rejected, with no call.",
        "scope": "New fresh author and immutable audit use identical selected acquired text. No stem-only solver, model comparison, retries, repairs, source acquisition, native operation, deployment or production admission. Citation fidelity and model declarations do not prove factual truth. Full acquired text/fixtures stay local unless redistribution is permitted.",
        "timing_scope": "Each unchanged observer uses read300/connect3, one SDK attempt and a300-second local worker deadline including bootstrap, plus bounded reaping. Local waiting at most1800 seconds plus reaping for6 calls; parent persistence/preflight is not hard real-time. No response means unknown usage/remote completion, not zero.",
    }


def load_frozen_plan(path, approved_hash):
    plan = json.loads(Path(path).read_text())
    if _hash(plan) != approved_hash or not _same(
        plan, make_plan(plan["fixture"], source_revision=plan.get("source_revision"))
    ):
        raise ValueError(
            "Frozen fixture, sources, dependencies and requests must match."
        )
    return plan


def _call_text(call):
    state = call.get("observation")
    if state is None:
        return None
    if type(state) is not dict:
        raise ValueError("Malformed terminal observer record.")
    response = state.get("response")
    if response is not None:
        recorded._validate_response_record(response)
        if state.get("usage_known") != recorded._usage_known(response):
            raise ValueError("Usage-known binding mismatch.")
    elif state.get("usage_known") is not False:
        raise ValueError("Missing response cannot have known usage.")
    if state.get("status") != "completed":
        return None
    if (
        state.get("provider_dispatch_attempted") is not True
        or state.get("local_worker_reaped") is not True
        or state.get("local_process_group_cleanup_confirmed") is not True
        or type(state.get("worker_exitcode")) is not int
        or state["worker_exitcode"] != 0
        or state.get("termination_attempted") is not False
        or response is None
        or not response["content_valid"]
        or response["stopReason"] != "end_turn"
    ):
        return None
    return response["text"]


def _case_state(case, job, calls):
    result = {
        "case_id": case["case_id"],
        "status": "unattempted",
        "question": None,
        "audit": None,
        "semantic_assessment": "unassessed",
    }
    if not calls:
        return result, ("author", job["author_request"])
    text = _call_text(calls[0])
    if text is None:
        return {
            **result,
            "status": "operational_failure",
            "failed_role": "author",
        }, None
    try:
        question = parse_author(text)
    except (ImmutableReviewContentError, ImmutableReviewFormatError) as error:
        return {
            **result,
            "status": "author_contract_rejected",
            "reason": str(error),
        }, None
    result.update(question=question, question_sha256=_hash(question), status="authored")
    request = shared.converse_request(
        *audit.review_prompt(
            question, case["context"], case["records"], case["selections"]
        )
    )
    if shared.text_bytes(request) > MAX_INPUT_BYTES:
        return {**result, "status": "input_budget_rejected"}, None
    if len(calls) == 1:
        return result, ("auditor", request)
    text = _call_text(calls[1])
    if text is None:
        return {
            **result,
            "status": "operational_failure",
            "failed_role": "auditor",
        }, None
    observed = audit.observe_review(
        text, question, case["context"], case["records"], case["selections"], 3
    )
    return {
        **result,
        "status": "audit_contract_rejected"
        if observed["reason"] in {"invalid_review", "invalid_evidence"}
        else "audited",
        "audit": observed,
    }, None


def _derive(plan, calls):
    if type(calls) is not list or len(calls) > min(MAX_CALLS, plan["maximum_calls"]):
        raise ValueError("Call count exceeded.")
    results = [
        {"case_id": job["case_id"], "status": "unattempted"} for job in plan["jobs"]
    ]
    cursor, total = 0, 0
    for index, (case, job) in enumerate(
        zip(plan["fixture"]["cases"], plan["jobs"], strict=True)
    ):
        owned = []
        while True:
            result, pending = _case_state(case, job, owned)
            results[index] = result
            if pending is None:
                if result["status"] == "operational_failure":
                    if cursor != len(calls):
                        raise ValueError("Dispatch after operational failure.")
                    return {"status": "operational_failure", "results": results}, None
                break
            role, request = pending
            if cursor == len(calls):
                return {"status": "running", "results": results}, (index, role, request)
            call = calls[cursor]
            _guard_request(request)
            total += shared.text_bytes(request)
            if (
                total > MAX_TOTAL_INPUT_BYTES
                or call.get("case_id") != case["case_id"]
                or call.get("role") != role
                or not _same(call.get("request"), request)
                or call.get("request_sha256") != _hash(request)
                or call.get("source_packet_sha256") != job["source_packet_sha256"]
                or call.get("input_utf8_bytes") != shared.text_bytes(request)
            ):
                raise ValueError("Call/source/input binding mismatch.")
            owned.append(call)
            cursor += 1
    if cursor != len(calls):
        raise ValueError("Unexpected repeated or trailing call.")
    return {"status": "completed", "results": results}, None


def replay_capture(capture):
    """Replay captured final text and decisions, without observer/client creation."""
    plan = capture["plan"]
    if capture.get("plan_sha256") != _hash(plan) or not _same(
        plan, make_plan(plan["fixture"], source_revision=plan.get("source_revision"))
    ):
        raise ValueError("Capture plan binding mismatch.")
    derived, _ = _derive(plan, capture["calls"])
    recorded_status = capture.get("status")
    if recorded_status not in {"running", "completed", "operational_failure"}:
        raise ValueError("Unknown capture status.")
    if recorded_status != derived["status"] and not (
        recorded_status == "running"
        or (
            recorded_status == "operational_failure"
            and type(capture.get("error_type")) is str
            and capture["error_type"]
        )
    ):
        raise ValueError("Capture terminal status mismatch.")
    if not _same(capture.get("results"), derived["results"]):
        raise ValueError("Capture result binding mismatch.")
    return {
        **derived,
        "status": recorded_status,
        "derived_status": derived["status"],
        "parent_error_type": capture.get("error_type"),
    }


def run_trial(
    plan_path,
    approved_hash,
    directory,
    *,
    cli_credentials=False,
    observer=caller.observe_request,
):
    plan = load_frozen_plan(plan_path, approved_hash)
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    initial, _ = _derive(plan, [])
    report = {"plan": plan, "plan_sha256": approved_hash, "calls": [], **initial}
    persistence_failed = False

    def persist():
        nonlocal persistence_failed
        try:
            shared.write_json(directory / "capture.json", report)
        except Exception:
            persistence_failed = True
            raise

    persist()
    try:
        while True:
            derived, pending = _derive(plan, report["calls"])
            report.update(derived)
            persist()
            if pending is None:
                break
            index, role, request = pending
            _guard_request(request)
            if len(report["calls"]) >= min(MAX_CALLS, plan["maximum_calls"]):
                raise ValueError("Dispatch cap exceeded.")
            total = sum(
                c["input_utf8_bytes"] for c in report["calls"]
            ) + shared.text_bytes(request)
            if total > MAX_TOTAL_INPUT_BYTES or persistence_failed:
                raise ValueError("Dispatch budget or durability failure.")
            call = {
                "case_id": plan["jobs"][index]["case_id"],
                "role": role,
                "request": copy.deepcopy(request),
                "request_sha256": _hash(request),
                "source_packet_sha256": plan["jobs"][index]["source_packet_sha256"],
                "input_utf8_bytes": shared.text_bytes(request),
                "observation": None,
            }
            report["calls"].append(call)
            persist()  # Exact dynamic request is durable before any worker exists.

            def progress(state):
                call["observation"] = copy.deepcopy(state)
                persist()

            state = observer(
                copy.deepcopy(request),
                cli_credentials=cli_credentials,
                on_progress=progress,
                timeout=caller.DEADLINE_SECONDS,
            )
            call["observation"] = copy.deepcopy(state)
            if persistence_failed:
                raise ValueError(
                    "A progress persistence failure prevents continuation."
                )
            persist()
    except Exception as error:
        # Preserve the last observation, including unknown dispatch/usage after
        # interruption. Reconcile any completed prefix without launching work.
        try:
            derived, _ = _derive(plan, report["calls"])
            report.update(derived)
        except Exception:
            pass
        report.update(status="operational_failure", error_type=type(error).__name__)
    finally:
        persist()
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--plan-sha256")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    if args.execute:
        if args.fixture is not None or args.plan is None or args.plan_sha256 is None:
            parser.error(
                "Execute requires only the frozen plan, exact hash and fresh output."
            )
        report = run_trial(
            args.plan,
            args.plan_sha256,
            args.output,
            cli_credentials=args.aws_cli_credentials,
        )
        return 0 if report["status"] == "completed" else 1
    if (
        args.fixture is None
        or args.plan is not None
        or args.plan_sha256 is not None
        or args.aws_cli_credentials
    ):
        parser.error("Dry preparation requires fixture and fresh output only.")
    plan = make_plan(json.loads(args.fixture.read_text()))
    args.output.mkdir(parents=True, exist_ok=False)
    shared.write_json(args.output / "plan.json", plan)
    print(
        json.dumps(
            {
                "plan_sha256": _hash(plan),
                "maximum_calls": plan["maximum_calls"],
                "execute": False,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
