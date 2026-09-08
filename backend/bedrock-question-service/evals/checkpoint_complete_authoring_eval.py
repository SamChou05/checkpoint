#!/usr/bin/env python3
"""Fresh complete author -> runtime blind solver gate -> immutable audit.

Four fixed learning goals, at most twelve serial calls, dry by default. No
repairs, retries, deployment, native execution or production acceptance stamps.
One state machine derives both live follow-up requests and replayed decisions.
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

from evals import checkpoint_immutable_review_eval as recorded  # noqa: E402
from evals import checkpoint_solution_compatibility_eval as shared  # noqa: E402
from evals.question_complete_author import author_prompt, parse_author  # noqa: E402
from evals.question_immutable_review import (  # noqa: E402
    ImmutableReviewContentError,
    ImmutableReviewFormatError,
    _context,
    observe_review,
    review_prompt,
)
from question_verification import (  # noqa: E402
    SOLUTION_SYSTEM_PROMPT,
    _solver_rejection_reason,
    _validated_solutions,
)

EXPERIMENT = "complete-authoring-immutable-audit-v1"
ROLES = ("author", "solver", "auditor")
MAX_CALLS, MAX_INPUT_BYTES, MAX_TOTAL_INPUT_BYTES = 12, 32000, 384000
_hash, _same = recorded._hash, recorded._same


def make_plan(packet):
    cases = packet.get("cases") if type(packet) is dict else None
    if (
        type(packet) is not dict
        or packet.get("experiment") != EXPERIMENT
        or type(cases) is not list
        or len(cases) != 4
        or any(
            type(c) is not dict or type(c.get("case_id")) is not str or not c["case_id"]
            for c in cases
        )
        or len({c["case_id"] for c in cases}) != 4
    ):
        raise ValueError("Four distinct fresh learning goals are required.")
    jobs = []
    for case in cases:
        context = case["context"]
        if (
            type(context.get("minimumDifficulty")) is not int
            or context["minimumDifficulty"] != 3
        ):
            raise ValueError("Every fresh case requests minimum difficulty three.")
        request = shared.converse_request(*author_prompt(context, minDifficulty=3))
        if shared.text_bytes(request) > MAX_INPUT_BYTES:
            raise ValueError("Initial request exceeds the input allowance.")
        jobs.append({"case_id": case["case_id"], "author_request": request})
    sources = shared.source_hashes()
    for name in (
        "evals/checkpoint_complete_authoring_eval.py",
        "evals/question_complete_author.py",
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
        "maximum_calls_per_case": 3,
        "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": MAX_TOTAL_INPUT_BYTES,
        "sdk_total_max_attempts": 1,
        "dynamic_request_policy": "Derive exact solver/auditor requests from the frozen context and prior unchanged validated author output. Persist exact requests and content hashes before dispatch. Solver output stays out of the auditor prompt; existing solver vetoes run in code.",
        "failure_policy": "Provider, binding or persistence failure stops dispatch. Malformed or oversized model content, a derived request beyond its input allowance, a solver veto, an auditor veto or assessed difficulty below three ends that case; remaining goals continue. No retries, repairs, top-ups, replacement goals or resume.",
        "scope": "Fresh complete teaching items, one sequence per goal. Code eligibility is not factual correctness, calibrated challenge, production admission, throughput or learning efficacy. No retrieval or native execution occurs inside the pipeline; sources are preselected.",
        "budget_note": "Input bytes and output tokens are allowances, not a money cap. Socket read timeout is not a whole-trial deadline. Failed call usage may be unknown.",
    }


def load_frozen_plan(path, approved_hash):
    plan = json.loads(path.read_text())
    if _hash(plan) != approved_hash or not _same(plan, make_plan(plan["fixture"])):
        raise ValueError("Exact frozen plan, source and dependencies required.")
    return plan


def _request(plan, index, role, result):
    context = plan["fixture"]["cases"][index]["context"]
    bindings = {"context_canonical_sha256": _hash(context)}
    if role == "author":
        return copy.deepcopy(plan["jobs"][index]["author_request"]), bindings
    question = result["question"]
    bindings["question_canonical_sha256"] = _hash(question)
    if role == "solver":
        data = _context(context)
        data["items"] = [
            {"index": 0, "prompt": question["prompt"], "topic": question["topic"]}
        ]
        system, user = (
            SOLUTION_SYSTEM_PROMPT,
            (
                "<question_solution_json>\n"
                + json.dumps(data, ensure_ascii=False)
                + "\n</question_solution_json>"
            ),
        )
    else:
        # Prior solver decisions bind the sequence but are not auditor evidence.
        bindings["solution_canonical_sha256"] = _hash(result["solution"])
        system, user = review_prompt(question, context)
    return shared.converse_request(system, user), bindings


def _apply(response, role, result):
    recorded._validate_response_record(response)
    if not response["content_valid"] or response["stopReason"] != "end_turn":
        result.update(
            status="contract_rejected", rejection=f"{role}:incomplete_content"
        )
        return
    raw = response["text"]
    if len(raw) > 24000:
        result.update(status="contract_rejected", rejection=f"{role}:raw_length")
        return
    try:
        if role == "author":
            result["question"] = parse_author(raw)
        elif role == "solver":
            solutions = _validated_solutions(raw, 1)
            if solutions is None:
                raise ImmutableReviewFormatError("solver:invalid_contract")
            result["solution"] = solutions[0]
            reason = _solver_rejection_reason(solutions[0], result["question"])
            if reason:
                result.update(status="solver_rejected", rejection=reason)
        else:
            observation = observe_review(raw, result["question"], minimum_difficulty=3)
            result["observation"] = observation
            result["status"] = (
                "eligible" if observation["eligible"] else "audit_rejected"
            )
            if observation["reason"] == "invalid_review":
                result["status"] = "contract_rejected"
            if not observation["eligible"]:
                result["rejection"] = observation["reason"]
    except (ImmutableReviewFormatError, ImmutableReviewContentError) as error:
        result.update(status="contract_rejected", rejection=f"{role}:{error}")


def derive(plan, calls):
    """Return deterministic case states and the next exact permitted dispatch."""
    if type(calls) is not list or len(calls) > MAX_CALLS:
        raise ValueError("Invalid call list.")
    results = [
        {"case_id": job["case_id"], "status": "unattempted"} for job in plan["jobs"]
    ]
    cursor, total = 0, 0
    for index, result in enumerate(results):
        result["status"] = "running"
        for role in ROLES:
            request, bindings = _request(plan, index, role, result)
            size = shared.text_bytes(request)
            if size > MAX_INPUT_BYTES or total + size > MAX_TOTAL_INPUT_BYTES:
                # No call is authorized for this role. Keep its prior exact
                # output and a replayable budget disposition, without fabricating
                # a model rejection or trying the oversized request again.
                result.update(
                    status="budget_rejected", rejection=f"{role}:input_allowance"
                )
                break
            expected = {
                "case_index": index,
                "case_id": result["case_id"],
                "role": role,
                "request": request,
                "request_canonical_sha256": _hash(request),
                "bindings": bindings,
                "input_utf8_bytes": size,
            }
            if cursor == len(calls):
                if role == "author":
                    result["status"] = "unattempted"
                return results, expected
            call = calls[cursor]
            if type(call) is not dict or any(
                not _same(call.get(k), v) for k, v in expected.items()
            ):
                raise ValueError("Call order, request or object binding changed.")
            if type(call.get("provider_dispatch_attempted")) is not bool or not _same(
                call.get("usage_known"), recorded._usage_known(call.get("response"))
            ):
                raise ValueError("Dispatch or usage accounting changed.")
            if "response" in call:
                recorded._validate_response_record(call["response"])
                if not call["provider_dispatch_attempted"]:
                    raise ValueError("Response without a dispatch.")
            cursor, total = cursor + 1, total + size
            if call["status"] == "operational_failure":
                if cursor != len(calls) or type(call.get("error_type")) is not str:
                    raise ValueError(
                        "Dispatch after failure or missing failure record."
                    )
                result.update(status="operational_failure", failure_role=role)
                return results, None
            if call["status"] != "completed" or not call["provider_dispatch_attempted"]:
                raise ValueError("Nonterminal or undispatched call.")
            _apply(call["response"], role, result)
            if result["status"] != "running":
                break
    if cursor != len(calls):
        raise ValueError("Calls exceed the permitted sequence.")
    return results, None


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
    }

    def persist():
        shared.write_json(directory / "capture.json", report)

    report["results"], pending = derive(plan, [])
    persist()
    phase, call = "client_setup", None
    try:
        client = (
            client
            if client is not None
            else shared.new_client(shared.SETTINGS, cli_credentials)
        )
        while pending is not None:
            call = {
                **pending,
                "status": "prepared",
                "provider_dispatch_attempted": False,
                "usage_known": False,
            }
            report["calls"].append(call)
            started = time.monotonic()
            try:
                phase = "request_persist"
                persist()
                phase = "provider_dispatch"
                call["provider_dispatch_attempted"] = True
                call["response"] = recorded._response(
                    client.converse(**copy.deepcopy(call["request"]))
                )
                call["usage_known"] = recorded._usage_known(call["response"])
                phase = "response_persist"
                persist()
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
            phase = "derive_results"
            report["results"], pending = derive(plan, report["calls"])
            phase = "call_persist"
            persist()
        report["status"] = "completed"
    except Exception as error:
        report.update(
            status="operational_failure",
            error_type=type(error).__name__,
            error_phase=phase,
        )
        report["results"], _ = derive(plan, report["calls"])
    finally:
        persist()
    return report


def replay_capture(report, approved_hash):
    plan = report["plan"]
    if (
        report.get("plan_sha256") != approved_hash
        or _hash(plan) != approved_hash
        or not _same(plan, make_plan(plan["fixture"]))
        or report.get("status") not in ("completed", "operational_failure")
    ):
        raise ValueError("A bound terminal capture from the exact source is required.")
    results, pending = derive(plan, report["calls"])
    if not _same(results, report["results"]):
        raise ValueError("Recorded content or decisions changed.")
    if report["status"] == "completed":
        if pending is not None or any(
            r["status"] in ("unattempted", "running", "operational_failure")
            for r in results
        ):
            raise ValueError("Completed trial has an incomplete or failed sequence.")
    elif type(report.get("error_type")) is not str or report.get("error_phase") not in (
        "client_setup",
        "request_persist",
        "provider_dispatch",
        "response_persist",
        "derive_results",
        "call_persist",
    ):
        raise ValueError("Operational failure lacks evidence.")
    return {
        "results": results,
        "provider_calls": sum(
            c["provider_dispatch_attempted"] for c in report["calls"]
        ),
        "input_utf8_bytes": sum(c["input_utf8_bytes"] for c in report["calls"]),
        "scope": "Replay verifies captured bindings and code decisions, not semantic correctness.",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--plan-sha256")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    if args.execute:
        if args.plan is None or args.fixture is not None:
            parser.error("Execution requires a frozen --plan and no --fixture.")
        report = run_experiment(
            args.plan,
            args.plan_sha256,
            args.output,
            cli_credentials=args.aws_cli_credentials,
        )
        return 0 if report["status"] == "completed" else 1
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
