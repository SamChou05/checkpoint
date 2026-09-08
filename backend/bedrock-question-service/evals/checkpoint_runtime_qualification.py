#!/usr/bin/env python3
"""Local policy-two runtime qualification; dry by default, no Lambda invocation.

One fixed batch (at most two calls), then one fresh generation operation (six).
The unchanged runtime owns parsing, filtering, top-offs and JSON repair. The
existing isolated caller owns transport/deadlines; this file adds no supervisor.
Operational completion and policy stamps are not factual correctness scores.
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
import time
from types import SimpleNamespace
from unittest.mock import patch

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_author_latency_probe as caller  # noqa: E402
import question_generation as generation  # noqa: E402
from question_verification import (  # noqa: E402
    COMPLETE_REVIEW_SYSTEM_PROMPT, verify_questions,
)
from complete_question_solution import COMPLETE_SOLUTION_SYSTEM_PROMPT  # noqa: E402
from request_contract import _normalize_request  # noqa: E402
from service_errors import ProviderError  # noqa: E402

shared, recorded = caller.shared, caller.recorded
_hash, _same = recorded._hash, recorded._same
EXPERIMENT = "policy-two-runtime-qualification-v1"
MAX_CALLS, MAX_INPUT_BYTES = 8, 32 * 1024
OPERATION_SECONDS = 240
SETTINGS = {
    "AWS_REGION": "us-east-1", "BEDROCK_REGION": "us-east-1",
    "BEDROCK_MODEL_ID": "moonshotai.kimi-k2.5",
    "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
    "BEDROCK_FALLBACK_MODEL_ID": "", "BEDROCK_KIMI_THINKING": "disabled",
    "BEDROCK_CLAUDE_THINKING": "disabled", "BEDROCK_CLAUDE_EFFORT": "high",
    "BEDROCK_REASONING_EFFORT": "none", "BEDROCK_MAX_TOKENS": "6000",
    "BEDROCK_THINKING_MAX_TOKENS": "16000", "BEDROCK_TEMPERATURE": "0.2",
    "BEDROCK_READ_TIMEOUT_SECONDS": "75", "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
    "MIN_PROVIDER_REMAINING_MILLISECONDS": "0",
    "MAX_PROVIDER_CALLS_PER_REQUEST": "6", "GENERATION_ATTEMPTS": "3",
    "QUESTION_BANK_GENERATION_CHUNK_SIZE": "5",
    "CHECKPOINT_PROMPT_VARIANT": "balanced",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "", "BEDROCK_GUARDRAIL_VERSION": "",
}


class QualificationFailure(ProviderError):
    """A local operational failure, latched independently of runtime recovery."""


class _RequestCaptured(BaseException):
    pass


def _first_request(request, questions=None):
    captured = []

    class Client:
        def converse(self, **kwargs):
            captured.append(copy.deepcopy(kwargs))
            raise _RequestCaptured()

    def invoke(system, user):
        return generation._generate_with_bedrock(
            request, Client(), generation._verification_model_id(), user, system,
        )

    try:
        if questions is None:
            generation._generate_with_bedrock(request, Client(), SETTINGS["BEDROCK_MODEL_ID"])
        else:
            verify_questions(copy.deepcopy(questions), request, invoke, solve=invoke,
                             solver_contract="complete_choices")
    except _RequestCaptured:
        pass
    if len(captured) != 1:
        raise ValueError("The initial runtime request must exist.")
    _guard_request(captured[0])
    return captured[0]


def _role(request):
    if request.get("modelId") == SETTINGS["BEDROCK_MODEL_ID"]:
        if request.get("system") != [{"text": generation._system_prompt()}]:
            raise ValueError("Unexpected author instructions.")
        user = request["messages"][0]["content"][0]["text"]
        return "author_json_repair" if user.startswith("Your previous response could not be parsed") else "author"
    system = request.get("system")
    if system == [{"text": COMPLETE_SOLUTION_SYSTEM_PROMPT}]:
        return "solver"
    if system == [{"text": COMPLETE_REVIEW_SYSTEM_PROMPT}]:
        return "reviewer"
    raise ValueError("Unexpected runtime role.")


def _guard_request(request):
    role = _role(request)
    expected_model = SETTINGS["BEDROCK_MODEL_ID" if role.startswith("author") else "BEDROCK_VERIFICATION_MODEL_ID"]
    if (
        request.get("modelId") != expected_model
        or not _same(request.get("inferenceConfig"), {"maxTokens": 6000, "temperature": 0.2})
        or not _same(request.get("additionalModelRequestFields"), {"thinking": {"type": "disabled"}})
        or set(request) != {"modelId", "messages", "system", "inferenceConfig", "additionalModelRequestFields"}
        or len(shared.canonical(request).encode("utf-8")) > MAX_INPUT_BYTES
    ):
        raise ValueError("Unexpected provider settings/shape or input allowance exceeded.")
    return role


def make_plan(packet, *, source_revision=None):
    if type(packet) is not dict or packet.get("experiment") != EXPERIMENT:
        raise ValueError("Wrong experiment fixture.")
    fixed, fresh = packet["fixed"], packet["fresh"]
    cases = fixed["cases"]
    if (type(cases) is not list or len(cases) != 5
            or any(type(c.get("case_id")) is not str or not c["case_id"] for c in cases)
            or len({c["case_id"] for c in cases}) != 5
            or type(fresh.get("case_id")) is not str or not fresh["case_id"]):
        raise ValueError("Five distinct fixed cases and one fresh goal required.")
    for payload in (fixed["request"], fresh["payload"]):
        if type(payload.get("targetCount")) is not int or payload["targetCount"] != 5:
            raise ValueError("Both operations must request five questions.")
    revision = shared.source_revision() if source_revision is None else source_revision
    if (type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision)
            or subprocess.run(["git", "cat-file", "-e", revision + "^{commit}"],
                              cwd=SERVICE_DIR, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode):
        raise ValueError("A resolvable full source revision is required.")
    with patch.dict(os.environ, SETTINGS):
        fixed_request = _normalize_request(copy.deepcopy(fixed["request"]))
        fresh_request = _normalize_request(copy.deepcopy(fresh["payload"]))
        questions = [copy.deepcopy(case["question"]) for case in cases]
        first = [_first_request(fixed_request, questions), _first_request(fresh_request)]
    sources = shared.source_hashes()
    for name in ("evals/checkpoint_runtime_qualification.py", "evals/checkpoint_author_latency_probe.py",
                 "evals/checkpoint_immutable_review_eval.py", "evals/question_immutable_review.py",
                 "evals/question_complete_author.py", "evals/checkpoint_solution_compatibility_eval.py"):
        sources[name] = hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
    return {
        "experiment": EXPERIMENT, "fixture": copy.deepcopy(packet), "fixture_sha256": _hash(packet),
        "source_revision": revision, "source_sha256": sources, "dependencies": shared.dependencies(),
        "settings": copy.deepcopy(SETTINGS),
        "operations": [
            {"kind": "fixed", "request": fixed_request, "questions": questions,
             "maximum_calls": 2, "first_request": first[0]},
            {"kind": "fresh", "case_id": fresh["case_id"], "request": fresh_request,
             "maximum_calls": 6, "first_request": first[1]},
        ],
        "maximum_calls": MAX_CALLS, "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": MAX_CALLS * MAX_INPUT_BYTES,
        "operation_seconds": OPERATION_SECONDS, "sdk_total_max_attempts": 1,
        "runtime_deadline_constants": {
            "client_setup_milliseconds": generation.DEFAULT_PROVIDER_CLIENT_SETUP_MILLISECONDS,
            "safety_milliseconds": generation.DEFAULT_PROVIDER_DEADLINE_SAFETY_MILLISECONDS,
        },
        "maximum_worker_capture_bytes": caller.MAX_CAPTURE_BYTES,
        "failure_policy": "Observer, unfinished response, correlation, input-budget or persistence failure latches a global stop, including runtime-caught top-up failures. No provider-failure retry, model fallback, resumption or replacement operation. Existing runtime content top-offs and malformed-author JSON repair remain within six calls and are recorded distinctly.",
        "scope": "Local direct-model calls through current production functions, not deployed Lambda or bank writes. Observed deployed worker model aliases/read75/token6000/thinking-disabled limits; connect3 and temperature0.2 are runtime defaults. Balanced prompt and disabled guardrails are explicit trial settings. Fixed diagnostic acceptance and fresh yield do not establish factual, feedback or difficulty correctness.",
        "timing_scope": "Two independent 240-second operation clocks. Each existing isolated observer is bounded by the remaining operation time, with read75/connect3 and SDK1; bounded local cleanup can extend that wait slightly. The supplied fixed75 transport causes conservative runtime admission; deployed _bedrock_client can instead shorten its read timeout late in an operation. This is not an exact late-deadline Lambda simulation. Parent persistence is not hard real-time. Missing responses have unknown usage and remote completion.",
    }


def load_frozen_plan(path, approved_hash):
    plan = json.loads(Path(path).read_text())
    if _hash(plan) != approved_hash or not _same(plan, make_plan(plan["fixture"], source_revision=plan.get("source_revision"))):
        raise ValueError("Exact frozen source, plan, requests, settings and dependencies required.")
    return plan


def _usable_observation(state):
    if type(state) is not dict or type(state.get("usage_known")) is not bool:
        raise ValueError("Malformed observer record.")
    if state.get("provider_dispatch_attempted") is not None and type(state["provider_dispatch_attempted"]) is not bool:
        raise ValueError("Malformed dispatch observation.")
    response = state.get("response")
    if response is not None:
        recorded._validate_response_record(response)
        if state["usage_known"] != recorded._usage_known(response):
            raise ValueError("Usage-known mismatch.")
        usage = response["usage"]
        if usage is not None and (type(usage) is not dict or any(
            k not in {"inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens", "cacheWriteInputTokens"}
            or type(v) is not int or v < 0 for k, v in usage.items()
        )):
            raise ValueError("Invalid or unexpected usage fields.")
    elif state["usage_known"]:
        raise ValueError("Missing response cannot have known usage.")
    if state.get("status") not in {"completed", "operational_failure"}:
        raise ValueError("Observer must be terminal.")
    return bool(
        state["status"] == "completed" and state.get("error_type") is None
        and state.get("provider_dispatch_attempted") is True
        and state.get("local_worker_reaped") is True
        and state.get("local_process_group_cleanup_confirmed") is True
        and type(state.get("worker_exitcode")) is int and state["worker_exitcode"] == 0
        and state.get("termination_attempted") is False and response is not None
        and response["content_valid"] and response["stopReason"] == "end_turn"
    )


def _provider_response(state):
    response = state["response"]
    # Empty placeholders reproduce only the observed block count; private
    # reasoning text/signatures were never captured and are not reconstructed.
    blocks = [{"text": response["text"]}] + [
        {"reasoningContent": {}} for _ in range(response["reasoningContentBlockCount"])
    ]
    return {"output": {"message": {"role": "assistant", "content": blocks}},
            "usage": response["usage"] or {}, "stopReason": response["stopReason"]}


def _metrics_without_runtime_intervals(metrics):
    result = copy.deepcopy(metrics)
    for observation in result.get("ProviderObservations", []):
        observation.pop("elapsedSeconds", None)
    return result


class _OperationContext:
    def __init__(self, result, frozen=None):
        self.result, self.frozen, self.cursor = result, frozen, 0
        self.started = time.monotonic()

    def get_remaining_time_in_millis(self):
        if self.frozen is None:
            value = max(0, int((OPERATION_SECONDS - (time.monotonic() - self.started)) * 1000))
        else:
            if self.cursor >= len(self.frozen):
                raise ValueError("Missing recorded operation-clock observation.")
            value = self.frozen[self.cursor]
            self.cursor += 1
            if (type(value) is not int or not 0 <= value <= OPERATION_SECONDS * 1000
                    or self.result["remaining_milliseconds"] and value > self.result["remaining_milliseconds"][-1]):
                raise ValueError("Invalid operation-clock observation.")
        self.result["remaining_milliseconds"].append(value)
        return value


class _RuntimeClient:
    def __init__(self, report, persist, observer, cli_credentials=False, replay=None):
        self.report, self.persist, self.observer = report, persist, observer
        self.cli_credentials, self.replay = cli_credentials, replay
        self.failed = False
        self.meta = SimpleNamespace(config=SimpleNamespace(
            connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1},
        ))

    def converse(self, **request):
        if self.failed:
            raise QualificationFailure("Prior operational failure; no later dispatch.")
        operation = self.report["operations"][self.operation_index]
        position = len(self.report["calls"])
        count = sum(c["operation_index"] == self.operation_index for c in self.report["calls"])
        try:
            role = _guard_request(request)
            if position >= MAX_CALLS or count >= operation["maximum_calls"]:
                raise ValueError("Call cap exceeded.")
            if self.operation_index == 0 and role not in ("solver", "reviewer"):
                raise ValueError("Fixed batch cannot invoke an author.")
            remaining = self.context.get_remaining_time_in_millis()
            if remaining <= 0:
                raise ValueError("Operation deadline exhausted.")
            call = {"operation_index": self.operation_index, "operation_call_index": count,
                    "role": role, "request": copy.deepcopy(request), "request_sha256": _hash(request),
                    "input_utf8_bytes": len(shared.canonical(request).encode("utf-8")),
                    "prepared_remaining_milliseconds": remaining,
                    "timeout_seconds": None, "lifecycle": "prepared",
                    "observer_started": False, "observation": None,
                    "failure_phase": None, "error_type": None}
            self.report["calls"].append(call)
            if self.replay is not None:
                if position >= len(self.replay):
                    raise ValueError("Missing saved provider call.")
                saved = self.replay[position]
                for key in ("operation_index", "operation_call_index", "role", "request", "request_sha256",
                            "input_utf8_bytes", "prepared_remaining_milliseconds"):
                    if not _same(call[key], saved.get(key)):
                        raise ValueError("Dynamic request or operation binding mismatch.")
                call.update(copy.deepcopy(saved))
                if type(saved.get("observer_started")) is not bool:
                    raise ValueError("Invalid observer admission observation.")
                if saved["failure_phase"] in {"prepare_persistence", "admission_persistence"}:
                    if saved["timeout_seconds"] is not None or saved["observer_started"]:
                        raise ValueError("Timeout cannot precede successful admission persistence.")
                else:
                    remaining = self.context.get_remaining_time_in_millis()
                    if not _same(saved["timeout_seconds"], remaining / 1000):
                        raise ValueError("Actual observer timeout differs from operation clock.")
                    admission_failed = remaining < generation._minimum_provider_remaining_milliseconds(
                        connect_timeout=3, read_timeout=75,
                    )
                    if ((saved["failure_phase"] == "deadline_admission") != admission_failed
                            or admission_failed and saved["observer_started"]):
                        raise ValueError("Saved observer admission contradicts the runtime deadline gate.")
                if saved["observation"] is not None:
                    usable = _usable_observation(saved["observation"])
                else:
                    usable = False
                if saved["failure_phase"] is not None:
                    if (saved["lifecycle"] != "failed" or type(saved["error_type"]) is not str
                            or saved["failure_phase"] not in {"prepare_persistence", "admission_persistence",
                                                              "deadline_admission", "progress_persistence",
                                                              "observation", "response_persistence"}
                            or not saved["observer_started"] and (
                                saved["failure_phase"] not in {"prepare_persistence", "admission_persistence", "deadline_admission"}
                                or saved["observation"] is not None)):
                        raise ValueError("Invalid failed-call record.")
                    self.failed = True
                    raise QualificationFailure("Recorded operational failure.")
                if (saved["lifecycle"] != "completed" or saved["error_type"] is not None
                        or not saved["observer_started"] or not usable):
                    raise ValueError("Undeliverable saved response.")
                return _provider_response(saved["observation"])
            phase = "prepare_persistence"
            try:
                self.persist()
                call["lifecycle"] = "observing"
                phase = "admission_persistence"
                self.persist()
                # Disk waits consume this operation's budget. The observer's
                # first ready callback persists this measured timeout before
                # its child is permitted to initialize credentials or dispatch.
                phase = "deadline_admission"
                remaining = self.context.get_remaining_time_in_millis()
                call["timeout_seconds"] = remaining / 1000
                if remaining < generation._minimum_provider_remaining_milliseconds(
                    connect_timeout=3, read_timeout=75,
                ):
                    raise QualificationFailure("Insufficient operation time after durable preparation.")

                def progress(state):
                    nonlocal phase
                    call["observation"] = copy.deepcopy(state)
                    phase = "progress_persistence"
                    try:
                        self.persist()
                    except Exception:
                        self.failed = True
                        raise
                    phase = "observation"

                phase = "observation"
                call["observer_started"] = True
                state = self.observer(copy.deepcopy(request), cli_credentials=self.cli_credentials,
                                      on_progress=progress, timeout=remaining / 1000)
                call["observation"] = copy.deepcopy(state)
                if self.failed or not _usable_observation(state):
                    raise QualificationFailure("Provider observation did not complete safely.")
                call["lifecycle"] = "completed"
                phase = "response_persistence"
                self.persist()
            except Exception as error:
                self.failed = True
                call.update(lifecycle="failed", failure_phase=phase, error_type=type(error).__name__)
                raise QualificationFailure("Bounded observation failed.") from None
            return _provider_response(state)
        except Exception:
            self.failed = True
            raise


def _execute(plan, report, persist, observer=None, *, cli_credentials=False, replay=None):
    client = _RuntimeClient(report, persist, observer, cli_credentials, replay and replay["calls"])
    with patch.dict(os.environ, SETTINGS), patch.object(caller, "SETTINGS", copy.deepcopy(SETTINGS)):
        for index, job in enumerate(plan["operations"]):
            result = report["operations"][index]
            result["status"] = "running"
            context = _OperationContext(result, None if replay is None else replay["operations"][index]["remaining_milliseconds"])
            client.operation_index, client.context = index, context
            budget = generation.ProviderCallBudget(job["maximum_calls"], context=context)
            metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
            error_type, questions = None, []
            try:
                persist()
                request = copy.deepcopy(job["request"])
                if job["kind"] == "fixed":
                    def invoke(system, user):
                        return generation._generate_with_bedrock(
                            request, client, generation._verification_model_id(), user, system,
                            budget, metrics,
                        )
                    questions = verify_questions(copy.deepcopy(job["questions"]), request, invoke,
                                                 metrics, solve=invoke, solver_contract="complete_choices")
                else:
                    questions = generation._generate_sanitized_questions(request, client, budget, metrics)
            except Exception as error:
                error_type = type(error).__name__
                client.failed = True
            if replay is not None and context.cursor != len(context.frozen):
                raise ValueError("Unused operation-clock observations.")
            result.update(status="operational_failure" if client.failed else "completed",
                          questions=questions, runtime_error_type=error_type,
                          budget_reservations=budget.calls,
                          metrics=_metrics_without_runtime_intervals(metrics))
            persist()
            if client.failed:
                break
    report["status"] = "operational_failure" if client.failed else "completed"
    report["accounting"] = _accounting(report["calls"])


def _accounting(calls):
    states = [c.get("observation") or {} for c in calls]
    def known_tokens(state, key):
        usage = (state.get("response") or {}).get("usage")
        value = usage.get(key) if type(usage) is dict else None
        return value if type(value) is int and value >= 0 else 0

    return {
        "prepared_calls": len(calls),
        "observed_dispatch_attempts": sum(s.get("provider_dispatch_attempted") is True for s in states),
        "known_not_dispatched_calls": sum(not c["observer_started"] or s.get("provider_dispatch_attempted") is False
                                          for c, s in zip(calls, states, strict=True)),
        "unknown_dispatch_calls": sum(c["observer_started"] and s.get("provider_dispatch_attempted") is None
                                      for c, s in zip(calls, states, strict=True)),
        "known_usage_subtotal": {key: sum(known_tokens(s, key) for s in states)
                                 for key in ("inputTokens", "outputTokens")},
        "unknown_usage_calls": sum(c["observer_started"] and s.get("provider_dispatch_attempted") is not False
                                   and s.get("usage_known") is not True for c, s in zip(calls, states, strict=True)),
        "input_utf8_bytes": sum(c["input_utf8_bytes"] for c in calls),
    }


def _empty_report(plan):
    return {"plan": copy.deepcopy(plan), "plan_sha256": _hash(plan), "status": "running", "calls": [],
            "operations": [{"kind": j["kind"], "maximum_calls": j["maximum_calls"],
                            "status": "unattempted", "remaining_milliseconds": [], "questions": []}
                           for j in plan["operations"]]}


def run_trial(plan_path, approved_hash, directory, *, observer=None, cli_credentials=False):
    plan = load_frozen_plan(plan_path, approved_hash)
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    report = _empty_report(plan)

    def persist():
        shared.write_json(directory / "capture.json", report)

    persist()
    try:
        _execute(plan, report, persist, observer or caller.observe_request, cli_credentials=cli_credentials)
    except Exception as error:
        report.update(status="operational_failure", parent_error_type=type(error).__name__)
        report["accounting"] = _accounting(report["calls"])
    finally:
        persist()
    return report


def replay_capture(report):
    plan = report["plan"]
    if report["plan_sha256"] != _hash(plan) or not _same(plan, make_plan(plan["fixture"], source_revision=plan["source_revision"])):
        raise ValueError("Frozen source/plan changed.")
    if report.get("parent_error_type") or report.get("status") not in {"completed", "operational_failure"}:
        raise ValueError("Interrupted parent persistence is a diagnostic capture, not a replayable terminal run.")
    derived = _empty_report(plan)
    _execute(plan, derived, lambda: None, replay=report)
    if not _same(derived, report):
        raise ValueError("Runtime replay differs from captured requests, decisions or accounting.")
    return derived


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--approved-plan-sha256")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--cli-credentials", action="store_true")
    parser.add_argument("--replay", type=Path)
    args = parser.parse_args(argv)
    if args.replay:
        value = replay_capture(json.loads(args.replay.read_text()))
        args.output.mkdir(parents=True, exist_ok=False)
        shared.write_json(args.output / "replay.json", value)
    elif args.execute:
        if not args.plan or not args.approved_plan_sha256:
            parser.error("Execution requires an exact frozen plan and canonical hash.")
        value = run_trial(args.plan, args.approved_plan_sha256, args.output, cli_credentials=args.cli_credentials)
    else:
        if not args.fixture:
            parser.error("Dry preparation requires --fixture.")
        value = make_plan(json.loads(args.fixture.read_text()))
        args.output.mkdir(parents=True, exist_ok=False)
        shared.write_json(args.output / "plan.json", value)
    print(json.dumps({"status": value.get("status", "prepared"), "sha256": _hash(value)}))
    return int(value.get("status") == "operational_failure")


if __name__ == "__main__":
    raise SystemExit(main())
