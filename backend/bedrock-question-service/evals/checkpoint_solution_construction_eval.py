#!/usr/bin/env python3
"""Dry-by-default answer-first construction trial; no production acceptance.

Three fresh tasks and one fixed task use at most fifteen serial provider calls.
The independent solver's exact concise answer becomes the constructed key;
subsequent stages cannot rewrite it or the task. Replay checks recorded joins,
not the factual truth or authenticity of a provider's saved text.
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
from evals import question_solution_construction as contract  # noqa: E402
from question_quality import _extract_json_object  # noqa: E402

EXPERIMENT = "solution-key-construction-v1"
ROLES = ("author", "solver", "distractor", "reviewer")
MAX_CALLS, MAX_CALLS_PER_CASE = 15, 4
MAX_INPUT_BYTES, MAX_TOTAL_INPUT_BYTES = 32000, 480000


def _same(left, right):
    return shared.canonical(left) == shared.canonical(right)


def _hash(value):
    return shared.digest(shared.canonical(value))


def source_hashes():
    hashes = shared.source_hashes()
    for name in (
        "evals/checkpoint_solution_construction_eval.py",
        "evals/question_solution_construction.py",
    ):
        hashes[name] = hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
    return hashes


def _fixed_task(case):
    if "fixed_task" not in case:
        return None
    return contract.validate_task(shared.canonical({"task": case["fixed_task"]}))


def make_plan(packet):
    if not isinstance(packet, dict) or packet.get("experiment") != EXPERIMENT:
        raise ValueError("Unexpected experiment identifier.")
    cases = packet.get("cases") if isinstance(packet, dict) else None
    if (
        not isinstance(cases, list)
        or len(cases) != 4
        or any(
            not isinstance(c, dict)
            or not isinstance(c.get("case_id"), str)
            or not c["case_id"]
            for c in cases
        )
        or len({c["case_id"] for c in cases}) != 4
        or sum("fixed_task" in c for c in cases) != 1
    ):
        raise ValueError("Exactly three fresh cases and one fixed task are required.")
    jobs = []
    for index, case in enumerate(cases):
        context = case["context"]
        fixed = _fixed_task(case)
        role_order = list(ROLES if fixed is None else ROLES[1:])
        # The contract validates/whitelists context; fixture assessment stays out.
        request = shared.converse_request(
            *contract.prompt_for(role_order[0], context, task=fixed)
        )
        if shared.text_bytes(request) > MAX_INPUT_BYTES:
            raise ValueError("Initial request exceeds the input-text allowance.")
        jobs.append(
            {
                "case_id": case["case_id"],
                "fixture_case_index": index,
                "role_order": role_order,
                "context_canonical_sha256": _hash(context),
                "fixed_task_canonical_sha256": _hash(fixed) if fixed else None,
                "initial_request": request,
            }
        )
    return {
        "experiment": EXPERIMENT,
        "fixture": copy.deepcopy(packet),
        "fixture_canonical_sha256": _hash(packet),
        "source_revision": shared.source_revision(),
        "source_sha256": source_hashes(),
        "dependencies": shared.dependencies(),
        "model": shared.MODEL,
        "settings": copy.deepcopy(shared.SETTINGS),
        "system_prompts": copy.deepcopy(contract.PROMPTS),
        "jobs": jobs,
        "maximum_calls": MAX_CALLS,
        "maximum_calls_per_case": MAX_CALLS_PER_CASE,
        "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": MAX_TOTAL_INPUT_BYTES,
        "sdk_total_max_attempts": 1,
        "dynamic_request_policy": "Rebuild each request from frozen builders and exact validated earlier outputs; persist request and object hashes before dispatch.",
        "failure_policy": "Operational, malformed, correlation or persistence failure stops all dispatch. Unsupported content rejects its case and skips remaining roles; other cases proceed without replacement.",
        "scope": "Single construction sequence per case. Constructed/eligible is a recorded contract result, not factual correctness, educational quality or production admission. No repair, retry, native execution or verification stamp.",
        "input_budget_note": "UTF-8 text and output-token allowances are not a dollar cap. SDK timeout is not a total deadline; failed-call usage can be unknown.",
    }


def _validate_plan(plan, approved_hash):
    if _hash(plan) != approved_hash:
        raise ValueError("The exact canonical frozen-plan hash is required.")
    if not _same(plan, make_plan(plan["fixture"])):
        raise ValueError(
            "Frozen fixture, source, dependencies, prompts or settings changed."
        )
    return plan


def load_frozen_plan(path, approved_hash):
    return _validate_plan(json.loads(path.read_text(encoding="utf-8")), approved_hash)


def _initial_results(plan):
    results = []
    for case in plan["fixture"]["cases"]:
        result = {
            "case_id": case["case_id"],
            "status": "unattempted",
            "stage_outputs": {},
            "correctness_assessment": "unassessed",
            "feedback_assessment": "unassessed",
        }
        fixed = _fixed_task(case)
        if fixed is not None:
            result["task"] = fixed
        results.append(result)
    return results


def _request(plan, index, role, result):
    context = plan["fixture"]["cases"][index]["context"]
    request = shared.converse_request(
        *contract.prompt_for(
            role,
            context,
            task=result.get("task"),
            solution=result.get("solution"),
            question=result.get("question"),
        )
    )
    bindings = {
        f"{name}_canonical_sha256": _hash(result[name])
        for name in ("task", "solution", "question")
        if name in result
    }
    bindings["context_canonical_sha256"] = _hash(context)
    return request, bindings


def _apply_raw(plan, index, role, raw, result):
    try:
        parsed = _extract_json_object(raw)
    except Exception as error:
        raise contract.ConstructionFormatError("Malformed stage JSON.") from error
    result["stage_outputs"][role] = parsed
    try:
        if role == "author":
            result["task"] = contract.validate_task(raw)
        elif role == "solver":
            result["solution"] = contract.validate_solution(raw)
            if not contract.solution_eligible(result["solution"]):
                result.update(
                    status="content_rejected",
                    rejection={"role": role, "reason": "solution_ineligible"},
                )
        elif role == "distractor":
            alternatives = contract.validate_distractors(
                raw, result["solution"]["answerText"]
            )
            result["distractors"] = alternatives
            result["question"] = contract.build_question(
                result["task"], result["solution"], alternatives
            )
        elif role == "reviewer":
            observation = contract.review_observation(
                raw,
                result["question"],
                plan["fixture"]["cases"][index]["context"]["minimumDifficulty"],
            )
            result["review_observation"] = observation
            if observation["eligible"]:
                result["status"] = "constructed"
            else:
                result.update(
                    status="content_rejected",
                    rejection={"role": role, "reason": observation["disposition"]},
                )
        else:
            raise ValueError("Unknown role.")
    except contract.ConstructionContentError as error:
        result.update(
            status="content_rejected",
            rejection={"role": role, "reason": str(error)},
        )


def _response_record(response):
    if not isinstance(response, dict):
        raise shared.TrialFailure("Malformed provider response.")
    blocks = response.get("output", {}).get("message", {}).get("content", [])
    if not isinstance(blocks, list) or any(not isinstance(b, dict) for b in blocks):
        raise shared.TrialFailure("Malformed provider content.")
    texts = [b["text"] for b in blocks if isinstance(b.get("text"), str)]
    if not texts:
        raise shared.TrialFailure("Provider response contains no final text.")
    return {
        "text": texts,
        "usage": response.get("usage", {}),
        "stopReason": response.get("stopReason"),
        "reasoningContentBlockCount": sum("reasoningContent" in b for b in blocks),
    }


def _usage_known(response):
    usage = response.get("usage", {})
    return isinstance(usage, dict) and all(
        type(usage.get(k)) is int and usage[k] >= 0
        for k in ("inputTokens", "outputTokens")
    )


class RecordingClient:
    """Dynamic-stage recorder with durable intent and no retry/resume path."""

    def __init__(self, client, report, persist):
        self.client, self.report, self.persist = client, report, persist
        self.failed = False

    def dispatch(self, index, role):
        if type(index) is not int or not 0 <= index < len(self.report["results"]):
            raise shared.TrialFailure("Unknown case index.")
        plan, result = self.report["plan"], self.report["results"][index]
        calls = self.report["calls"]
        previous = [c for c in calls if c["case_index"] == index]
        order = plan["jobs"][index]["role_order"]
        if (
            self.failed
            or len(calls) >= MAX_CALLS
            or len(previous) >= MAX_CALLS_PER_CASE
            or len(previous) >= len(order)
            or role != order[len(previous)]
            or result["status"] != "running"
            or any(
                r["status"] not in ("constructed", "content_rejected")
                for r in self.report["results"][:index]
            )
            or any(c["case_index"] > index for c in calls)
        ):
            raise shared.TrialFailure("Dispatch order or budget rejected before call.")
        request, bindings = _request(plan, index, role, result)
        size = shared.text_bytes(request)
        if (
            size > MAX_INPUT_BYTES
            or self.report["input_utf8_bytes"] + size > MAX_TOTAL_INPUT_BYTES
        ):
            raise shared.TrialFailure("Input budget rejected before provider call.")
        call = {
            "case_index": index,
            "case_id": result["case_id"],
            "role": role,
            "request": request,
            "request_canonical_sha256": _hash(request),
            "bindings": bindings,
            "input_utf8_bytes": size,
            "status": "dispatch_started",
            "provider_dispatch_attempted": False,
            "usage_known": False,
        }
        calls.append(call)
        self.report["input_utf8_bytes"] += size
        started = time.monotonic()
        try:
            self.persist()
            call["provider_dispatch_attempted"] = True
            reply = self.client.converse(**copy.deepcopy(request))
            call["response"] = _response_record(reply)
            call["usage_known"] = _usage_known(call["response"])
            if call["response"]["stopReason"] != "end_turn":
                raise shared.TrialFailure("Provider did not complete with end_turn.")
            call["status"] = "response_received"
            return "\n".join(call["response"]["text"])
        except Exception as error:
            self.failed = True
            call.update(
                status="operational_failure", error={"type": type(error).__name__}
            )
            provider = getattr(error, "response", None)
            if isinstance(provider, dict) and isinstance(
                provider.get("Error", {}).get("Code"), str
            ):
                call["error"]["provider_code"] = provider["Error"]["Code"]
            raise
        finally:
            call["elapsed_seconds"] = round(time.monotonic() - started, 3)
            self.persist()


def _totals(result, calls):
    result["dispatch_intents"] = len(calls)
    result["provider_calls"] = sum(c["provider_dispatch_attempted"] for c in calls)
    result["usage_known"] = all(c["usage_known"] for c in calls)
    result["known_usage_subtotal"] = {
        key: sum(c["response"]["usage"][key] for c in calls if c["usage_known"])
        for key in ("inputTokens", "outputTokens")
    }


def run_experiment(
    plan_path, approved_hash, directory, client=None, *, cli_credentials=False
):
    plan = load_frozen_plan(plan_path, approved_hash)
    directory.mkdir(parents=True, exist_ok=False)
    report = {
        "plan": plan,
        "plan_sha256": approved_hash,
        "status": "running",
        "stopped_early": False,
        "calls": [],
        "input_utf8_bytes": 0,
        "results": _initial_results(plan),
    }

    def persist():
        shared.write_json(directory / "capture.json", report)

    persist()
    try:
        recorder = RecordingClient(
            client
            if client is not None
            else shared.new_client(shared.SETTINGS, cli_credentials),
            report,
            persist,
        )
        for index, job in enumerate(plan["jobs"]):
            result = report["results"][index]
            result["status"] = "running"
            started = time.monotonic()
            try:
                for role in job["role_order"]:
                    raw = recorder.dispatch(index, role)
                    _apply_raw(plan, index, role, raw, result)
                    persist()
                    if result["status"] == "content_rejected":
                        break
            except Exception as error:
                result.update(
                    status="operational_failure",
                    error={"type": type(error).__name__},
                    failure_role=role,
                )
                report["stopped_early"] = True
            finally:
                _totals(
                    result, [c for c in report["calls"] if c["case_index"] == index]
                )
                result["elapsed_seconds"] = round(time.monotonic() - started, 3)
                persist()
            if report["stopped_early"]:
                break
        report["status"] = (
            "operational_failure" if report["stopped_early"] else "completed"
        )
    except Exception as error:
        report.update(
            status="operational_failure",
            stopped_early=True,
            error={"type": type(error).__name__},
        )
        raise
    finally:
        persist()
    return report


def replay_capture(report, approved_hash):
    """Rebuild completed or terminal-failed recorded stages; make no inference calls."""
    plan = _validate_plan(report["plan"], approved_hash)
    if report["plan_sha256"] != approved_hash or report["status"] not in (
        "completed",
        "operational_failure",
    ):
        raise ValueError("Replay requires a terminal capture for the frozen plan.")
    rebuilt = _initial_results(plan)
    calls = report["calls"]
    cursor, total, stopped = 0, 0, False
    if not isinstance(calls, list) or len(calls) > MAX_CALLS:
        raise ValueError("Invalid recorded call count.")
    # A setup/auth failure can occur before the first durable dispatch intent.
    # Retain it as zero-dispatch evidence, without inventing a provider result.
    if not calls and isinstance(report.get("error", {}).get("type"), str):
        stopped = True
    for index, job in enumerate(plan["jobs"]):
        if stopped or (
            cursor == len(calls) and report["results"][index]["status"] == "unattempted"
        ):
            break
        result = rebuilt[index]
        result["status"] = "running"
        case_calls = []
        for role in job["role_order"]:
            if cursor >= len(calls):
                request, _ = _request(plan, index, role, result)
                if (
                    shared.text_bytes(request) > MAX_INPUT_BYTES
                    or total + shared.text_bytes(request) > MAX_TOTAL_INPUT_BYTES
                ):
                    result.update(
                        status="operational_failure",
                        error={"type": "TrialFailure"},
                        failure_role=role,
                    )
                    stopped = True
                    break
                raise ValueError(
                    "A stage is missing without a recorded rejection/failure."
                )
            call = calls[cursor]
            request, bindings = _request(plan, index, role, result)
            size = shared.text_bytes(request)
            if (
                not _same(
                    [call.get("case_index"), call.get("case_id"), call.get("role")],
                    [index, job["case_id"], role],
                )
                or not _same(call.get("request"), request)
                or call.get("request_canonical_sha256") != _hash(request)
                or not _same(call.get("bindings"), bindings)
                or type(call.get("input_utf8_bytes")) is not int
                or call["input_utf8_bytes"] != size
                or size > MAX_INPUT_BYTES
                or total + size > MAX_TOTAL_INPUT_BYTES
            ):
                raise ValueError(
                    "Recorded dynamic request, correlation or budget changed."
                )
            total += size
            cursor += 1
            case_calls.append(call)
            response = call.get("response", {})
            if type(call.get("provider_dispatch_attempted")) is not bool:
                raise ValueError("Missing strict dispatch-attempt accounting.")
            if type(call.get("usage_known")) is not bool or call[
                "usage_known"
            ] != _usage_known(response):
                raise ValueError("Recorded usage accounting changed.")
            if call["status"] == "operational_failure":
                if not isinstance(call.get("error", {}).get("type"), str):
                    raise ValueError("Operational failure has no recorded error type.")
                result.update(
                    status="operational_failure",
                    error={"type": call["error"]["type"]},
                    failure_role=role,
                )
                stopped = True
                break
            if (
                call["status"] != "response_received"
                or response.get("stopReason") != "end_turn"
                or not call["provider_dispatch_attempted"]
            ):
                raise ValueError("Incomplete or nonterminal provider record.")
            if (
                not isinstance(response.get("text"), list)
                or not response["text"]
                or any(not isinstance(t, str) for t in response["text"])
                or type(response.get("reasoningContentBlockCount")) is not int
                or response["reasoningContentBlockCount"] < 0
            ):
                raise ValueError("Malformed stored provider content.")
            try:
                _apply_raw(plan, index, role, "\n".join(response["text"]), result)
            except Exception as error:
                result.update(
                    status="operational_failure",
                    error={"type": type(error).__name__},
                    failure_role=role,
                )
                stopped = True
                break
            if result["status"] == "content_rejected":
                break
        _totals(result, case_calls)
    if cursor != len(calls) or not _same(total, report["input_utf8_bytes"]):
        raise ValueError("Extra calls or changed aggregate input accounting.")
    if report["status"] == "completed" and any(
        r["status"] not in ("constructed", "content_rejected") for r in rebuilt
    ):
        raise ValueError("Completed capture leaves unattempted cases.")
    if not _same(report["stopped_early"], stopped):
        raise ValueError("Recorded stop state differs from replay.")
    if report["status"] != ("operational_failure" if stopped else "completed"):
        raise ValueError("Recorded terminal status differs from replay.")
    actual = [
        {k: v for k, v in row.items() if k != "elapsed_seconds"}
        for row in report["results"]
    ]
    if not _same(actual, rebuilt):
        raise ValueError(
            "Saved stage outputs, derived question, outcome or totals changed."
        )
    return {
        "results": rebuilt,
        "dispatch_intents": cursor,
        "provider_calls": sum(c["provider_dispatch_attempted"] for c in calls),
        "input_utf8_bytes": total,
        "scope": "Exact recorded construction replay only; factual and teaching assessments remain separate.",
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
        return int(
            run_experiment(
                args.plan,
                args.plan_sha256,
                args.output,
                cli_credentials=args.aws_cli_credentials,
            )["stopped_early"]
        )
    if args.fixture is None or args.plan is not None:
        parser.error("Preparation requires --fixture and no --plan.")
    plan = make_plan(json.loads(args.fixture.read_text(encoding="utf-8")))
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
