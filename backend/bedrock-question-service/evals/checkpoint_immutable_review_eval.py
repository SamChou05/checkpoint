#!/usr/bin/env python3
"""Six fixed complete teaching items, one immutable audit each; dry by default.

No generation, solving, repair, deployment or production admission is performed.
Final teaching text is frozen before review and is never written by the auditor.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys
import time

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_solution_compatibility_eval as shared  # noqa: E402
from evals.question_immutable_review import (  # noqa: E402
    freeze_question,
    observe_review,
    review_prompt,
)

EXPERIMENT = "immutable-teaching-audit-v1"
MAX_CALLS, MAX_INPUT_BYTES = 6, 32000


def _hash(value):
    return shared.digest(shared.canonical(value))


def _same(left, right):
    return shared.canonical(left) == shared.canonical(right)


def make_plan(packet):
    cases = packet.get("cases") if type(packet) is dict else None
    if (
        type(packet) is not dict
        or packet.get("experiment") != EXPERIMENT
        or type(cases) is not list
        or len(cases) != MAX_CALLS
        or any(
            type(c) is not dict or type(c.get("case_id")) is not str or not c["case_id"]
            for c in cases
        )
        or len({c["case_id"] for c in cases}) != MAX_CALLS
    ):
        raise ValueError("Exactly six distinct fixed cases are required.")
    jobs = []
    for case in cases:
        question = freeze_question(case["question"])
        context = case["context"]
        if (
            context.get("minimumDifficulty") != 1
            or type(context["minimumDifficulty"]) is not int
        ):
            raise ValueError(
                "This fixed-content test isolates factual support at floor 1."
            )
        request = shared.converse_request(*review_prompt(question, context))
        size = shared.text_bytes(request)
        if size > MAX_INPUT_BYTES:
            raise ValueError("Input-text allowance exceeded.")
        jobs.append(
            {
                "case_id": case["case_id"],
                "question": question,
                "question_canonical_sha256": _hash(question),
                "request": request,
                "request_canonical_sha256": _hash(request),
                "input_utf8_bytes": size,
            }
        )
    sources = shared.source_hashes()
    for name in (
        "evals/question_immutable_review.py",
        "evals/checkpoint_immutable_review_eval.py",
    ):
        sources[name] = hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
    return {
        "experiment": EXPERIMENT,
        "fixture": copy.deepcopy(packet),
        "fixture_canonical_sha256": _hash(packet),
        "source_revision": shared.source_revision(),
        "source_sha256": sources,
        "dependencies": shared.dependencies(),
        "model": shared.MODEL,
        "settings": copy.deepcopy(shared.SETTINGS),
        "jobs": jobs,
        "maximum_calls": MAX_CALLS,
        "maximum_calls_per_case": 1,
        "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": MAX_CALLS * MAX_INPUT_BYTES,
        "planned_input_utf8_bytes": sum(j["input_utf8_bytes"] for j in jobs),
        "sdk_total_max_attempts": 1,
        "failure_policy": "Any provider, malformed-review, persistence or correlation failure stops later calls. No retries, repairs, replacement items or resume.",
        "scope": "Fixed full teaching content only; feedback reveals the intended answer. No author/solver calls or production verification stamps. Successful verdicts do not certify truth, author feasibility, level-3 difficulty, bank fill or learning outcomes.",
        "budget_note": "Input bytes and output tokens are allowances, not a monetary ceiling. A 100-second read timeout is not a whole-trial deadline.",
    }


def _validate_plan(plan, approved_hash):
    if type(approved_hash) is not str or _hash(plan) != approved_hash:
        raise ValueError("Exact frozen canonical plan hash required.")
    if not _same(plan, make_plan(plan["fixture"])):
        raise ValueError("Frozen source, requests, settings or dependencies changed.")
    return copy.deepcopy(plan)


def load_frozen_plan(path, approved_hash):
    return _validate_plan(json.loads(path.read_text()), approved_hash)


def _response(response):
    response = response if type(response) is dict else {}
    output = response.get("output", {})
    message = output.get("message", {}) if type(output) is dict else {}
    message = message if type(message) is dict else {}
    raw_blocks = message.get("content")
    blocks = raw_blocks if type(raw_blocks) is list else []
    valid = message.get("role") == "assistant" and type(raw_blocks) is list
    valid = valid and not any(
        type(b) is not dict or set(b) not in ({"text"}, {"reasoningContent"})
        for b in blocks
    )
    texts = [b["text"] for b in blocks if type(b) is dict and "text" in b]
    text_valid = bool(texts) and all(type(t) is str for t in texts)
    return {
        "text": "\n".join(texts) if text_valid else None,
        "content_valid": valid and text_valid,
        "usage": copy.deepcopy(response.get("usage")),
        "stopReason": response.get("stopReason"),
        "reasoningContentBlockCount": sum(
            type(b) is dict and "reasoningContent" in b for b in blocks
        ),
    }


def _usage_known(response):
    usage = response.get("usage") if type(response) is dict else None
    return type(usage) is dict and all(
        type(usage.get(k)) is int and usage[k] >= 0
        for k in ("inputTokens", "outputTokens")
    )


def _validate_response_record(response):
    if type(response) is not dict or set(response) != {
        "text",
        "content_valid",
        "usage",
        "stopReason",
        "reasoningContentBlockCount",
    }:
        raise ValueError("Malformed captured response.")
    if type(response["content_valid"]) is not bool or (
        response["text"] is not None and type(response["text"]) is not str
    ):
        raise ValueError("Malformed content observation.")
    if response["content_valid"] and not response["text"]:
        raise ValueError("Missing valid final text.")
    count = response["reasoningContentBlockCount"]
    if type(count) is not int or count < 0:
        raise ValueError("Malformed reasoning-block count.")


def _observation(response, question):
    _validate_response_record(response)
    if not response["content_valid"] or response["stopReason"] != "end_turn":
        raise ValueError("Provider did not finish normally.")
    observation = observe_review(response["text"], question, minimum_difficulty=1)
    if observation["reason"] == "invalid_review":
        raise ValueError("Malformed immutable-review contract.")
    return observation


def run_experiment(
    plan_path, approved_hash, directory, client=None, *, cli_credentials=False
):
    plan = load_frozen_plan(plan_path, approved_hash)
    directory.mkdir(parents=True, exist_ok=False)
    report = {
        "plan": plan,
        "plan_sha256": approved_hash,
        "status": "running",
        "calls": [],
        "results": [],
    }

    def persist():
        shared.write_json(directory / "capture.json", report)

    persist()
    phase = "client_setup"
    try:
        client = (
            client
            if client is not None
            else shared.new_client(shared.SETTINGS, cli_credentials)
        )
        for index, job in enumerate(plan["jobs"]):
            # The prevalidated list has exactly six entries; a case is never retried.
            call = {
                "case_index": index,
                "case_id": job["case_id"],
                "request": copy.deepcopy(job["request"]),
                "request_canonical_sha256": job["request_canonical_sha256"],
                "question_canonical_sha256": job["question_canonical_sha256"],
                "provider_dispatch_attempted": False,
                "usage_known": False,
                "status": "prepared",
            }
            report["calls"].append(call)
            started = time.monotonic()
            try:
                phase = "request_persist"
                persist()  # Exact input must be durable before provider dispatch.
                call["provider_dispatch_attempted"] = True
                call["status"] = "dispatch_started"
                phase = "provider_dispatch"
                call["response"] = _response(
                    client.converse(**copy.deepcopy(job["request"]))
                )
                call["usage_known"] = _usage_known(call["response"])
                phase = "response_persist"
                persist()
                phase = "review_parse"
                observation = _observation(call["response"], job["question"])
                report["results"].append(
                    {"case_id": job["case_id"], "observation": observation}
                )
                call["status"] = "completed"
            except Exception as error:
                call.update(
                    status="operational_failure",
                    error_type=type(error).__name__,
                    error_phase=phase,
                )
                raise
            finally:
                call["elapsed_seconds"] = round(time.monotonic() - started, 3)
                prior_phase = phase
                phase = "call_persist"
                persist()
                phase = prior_phase
        report["status"] = "completed"
    except Exception as error:
        report.update(
            status="operational_failure",
            error_type=type(error).__name__,
            error_phase=phase,
        )
    finally:
        persist()
    return report


def replay_capture(report, approved_hash):
    """Check terminal stored results against exact frozen requests; no inference."""
    plan = _validate_plan(report["plan"], approved_hash)
    if report.get("plan_sha256") != approved_hash or report.get("status") not in (
        "completed",
        "operational_failure",
    ):
        raise ValueError("A terminal capture for this plan is required.")
    calls = report["calls"]
    if type(calls) is not list or len(calls) > MAX_CALLS:
        raise ValueError("Invalid call count.")
    rebuilt = []
    failure = False
    for index, call in enumerate(calls):
        job = plan["jobs"][index]
        if failure or any(
            not _same(call.get(k), v)
            for k, v in {
                "case_index": index,
                "case_id": job["case_id"],
                "request": job["request"],
                "request_canonical_sha256": job["request_canonical_sha256"],
                "question_canonical_sha256": job["question_canonical_sha256"],
            }.items()
        ):
            raise ValueError("Capture order or binding changed.")
        if type(call.get("provider_dispatch_attempted")) is not bool:
            raise ValueError("Missing dispatch accounting.")
        if "response" in call:
            _validate_response_record(call["response"])
            if not call["provider_dispatch_attempted"]:
                raise ValueError("Response recorded without provider dispatch.")
        if not _same(call.get("usage_known"), _usage_known(call.get("response"))):
            raise ValueError("Usage accounting differs from captured response.")
        if call["status"] == "operational_failure":
            if type(call.get("error_type")) is not str:
                raise ValueError("Failure evidence missing.")
            failure = True
            continue
        if (
            call["status"] != "completed"
            or call["provider_dispatch_attempted"] is not True
        ):
            raise ValueError("Nonterminal or undispatched successful call.")
        rebuilt.append(
            {
                "case_id": job["case_id"],
                "observation": _observation(call["response"], job["question"]),
            }
        )
    if not _same(rebuilt, report["results"]):
        raise ValueError("Recorded decisions or returned content changed.")
    complete = len(calls) == MAX_CALLS and not failure
    persisted_prefix_failure = (
        report["status"] == "operational_failure"
        and report.get("error_phase") == "call_persist"
        and type(report.get("error_type")) is str
        and bool(calls)
        and not failure
    )
    if (report["status"] == "completed") != (complete and not persisted_prefix_failure):
        raise ValueError("Terminal status does not match completed calls.")
    if (
        not complete
        and not failure
        and not persisted_prefix_failure
        and (calls or type(report.get("error_type")) is not str)
    ):
        raise ValueError("Incomplete capture lacks a terminal failure.")
    return {
        "results": rebuilt,
        "dispatch_intents": len(calls),
        "provider_calls": sum(c["provider_dispatch_attempted"] for c in calls),
        "scope": "Replay verifies bindings, not factual correctness.",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--plan-sha256")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    if args.execute:
        if args.plan is None or args.fixture is not None:
            parser.error("Execution requires --plan and no --fixture.")
        result = run_experiment(
            args.plan,
            args.plan_sha256,
            args.output,
            cli_credentials=args.aws_cli_credentials,
        )
        return int(result["status"] != "completed")
    if args.fixture is None or args.plan is not None:
        parser.error("Preparation requires --fixture and no --plan.")
    plan = make_plan(json.loads(args.fixture.read_text()))
    args.output.mkdir(parents=True, exist_ok=False)
    shared.write_json(args.output / "plan.json", plan)
    print(
        json.dumps(
            {"plan_sha256": _hash(plan), "maximum_calls": MAX_CALLS, "execute": False}
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
