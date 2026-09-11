#!/usr/bin/env python3
"""Local runtime qualification; dry by default, no Lambda invocation.

Original mode: one fixed batch (two calls), then fresh generation (six).
Frozen-recheck mode: the same archived five candidates in two two-call arms.
Authored-solution mode: three fresh two-item goals, at most three calls each.
Author comparison: repeat those inputs with two author models, eighteen calls.
Focused application: compare two Kimi author prompts under the same limits.
Native workflow: three fresh five-item goals, at most six calls each.
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
import native_output_contracts as native  # noqa: E402
from question_verification import (  # noqa: E402
    COMPLETE_REVIEW_SYSTEM_PROMPT, verify_questions,
)
from complete_question_solution import COMPLETE_SOLUTION_SYSTEM_PROMPT  # noqa: E402
from request_contract import _normalize_request  # noqa: E402
from question_quality import _extract_json_object, _sanitize_questions  # noqa: E402
from question_teaching import AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT  # noqa: E402
from service_errors import (  # noqa: E402
    InvalidProviderResponseError, ProviderCallBudgetExceededError, ProviderError,
)

shared, recorded = caller.shared, caller.recorded
_hash, _same = recorded._hash, recorded._same
EXPERIMENT = "policy-two-runtime-qualification-v1"
RECHECK_EXPERIMENT = "policy-two-frozen-recheck-v1"
AUTHORED_EXPERIMENT = "authored-solution-fresh-v1"
AUTHOR_COMPARISON_EXPERIMENT = "authored-solution-author-comparison-v1"
FOCUSED_APPLICATION_EXPERIMENT = "authored-solution-focused-application-v1"
NATIVE_WORKFLOW_EXPERIMENT = "native-fresh-workflow-v1"
AUTHOR_COMPARISON_ORIGIN = SERVICE_DIR.parents[1] / "docs/evidence/authored-solution-fresh-fixture-20260908.json"
AUTHOR_COMPARISON_ORIGIN_SHA256 = "6fe797f70ab10c8d6418743c213337b406d15448f75ffb4bebe0abdb2fb2693d"
RECHECK_ORIGIN = SERVICE_DIR.parents[1] / "docs/evidence/runtime-qualification-capture-20260908.json"
RECHECK_ORIGIN_SHA256 = "6b4e90c111164618d042fe7b920d15bf0bd878dbd4b1a397b8de694c95bb3c5d"
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
    "QUESTION_FEEDBACK_CONTRACT": "reviewer_written",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "", "BEDROCK_GUARDRAIL_VERSION": "",
}


class QualificationFailure(ProviderError):
    """A local operational failure, latched independently of runtime recovery."""


class _RequestCaptured(BaseException):
    pass


def _first_request(request, questions=None, *, settings=None):
    settings = SETTINGS if settings is None else settings
    captured = []

    class Client:
        def converse(self, **kwargs):
            captured.append(copy.deepcopy(kwargs))
            raise _RequestCaptured()

    def invoke(system, user):
        return generation._generate_legacy_with_bedrock(
            request, Client(), generation._verification_model_id(), user, system,
        )

    try:
        if questions is None:
            if settings.get("BEDROCK_STRUCTURED_OUTPUT_MODE") == "native":
                generation._generate_with_bedrock(
                    request, Client(), settings["BEDROCK_MODEL_ID"], contract="question_author_v1",
                )
            else:
                generation._generate_legacy_with_bedrock(request, Client(), settings["BEDROCK_MODEL_ID"])
        else:
            verify_questions(copy.deepcopy(questions), request, invoke, solve=invoke,
                             solver_contract="complete_choices")
    except _RequestCaptured:
        pass
    if len(captured) != 1:
        raise ValueError("The initial runtime request must exist.")
    _guard_request(captured[0], settings)
    return captured[0]


def _native_stage_contracts():
    result = {}
    for role, contract, system in (
        ("author", "question_author_v1", generation._system_prompt()),
        ("solver", "complete_choice_solver_v1", COMPLETE_SOLUTION_SYSTEM_PROMPT),
        ("reviewer", "default_reviewer_v1", COMPLETE_REVIEW_SYSTEM_PROMPT),
    ):
        prompt = native.native_prompt(system, contract)
        result[role] = {
            "system": [{"text": prompt}], "system_prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
            "outputConfig": native.native_output_config(contract),
            "contract_metadata": native.contract_metadata(contract),
        }
    return result


def _role(request, settings=None, native_contracts=None):
    if (settings or {}).get("BEDROCK_STRUCTURED_OUTPUT_MODE") == "native":
        for role, stage in (native_contracts or _native_stage_contracts()).items():
            if _same(request.get("system"), stage["system"]):
                user = request["messages"][0]["content"][0]["text"]
                return "author_json_repair" if role == "author" and user.startswith(
                    "Your previous response could not be parsed",
                ) else role
        raise ValueError("Unexpected native runtime role or changed system prompt.")
    system = request.get("system")
    if system == [{"text": generation._system_prompt()}]:
        user = request["messages"][0]["content"][0]["text"]
        return "author_json_repair" if user.startswith("Your previous response could not be parsed") else "author"
    if system == [{"text": COMPLETE_SOLUTION_SYSTEM_PROMPT}]:
        return "solver"
    if system == [{"text": COMPLETE_REVIEW_SYSTEM_PROMPT}]:
        return "reviewer"
    if system == [{"text": AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT}]:
        return "teaching_auditor"
    raise ValueError("Unexpected runtime role.")


def _guard_request(request, settings=None, native_contracts=None):
    settings = SETTINGS if settings is None else settings
    is_native = settings.get("BEDROCK_STRUCTURED_OUTPUT_MODE") == "native"
    contracts = (native_contracts or _native_stage_contracts()) if is_native else None
    role = _role(request, settings, contracts)
    expected_model = settings["BEDROCK_MODEL_ID" if role.startswith("author") else "BEDROCK_VERIFICATION_MODEL_ID"]
    adaptive = not role.startswith("author") and settings["BEDROCK_CLAUDE_THINKING"] == "adaptive"
    inference = {"maxTokens": 6000} if adaptive else {"maxTokens": 6000, "temperature": 0.2}
    additional = ({"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}}
                  if adaptive else {"thinking": {"type": "disabled"}})
    if (
        request.get("modelId") != expected_model
        or role == "teaching_auditor" and settings["QUESTION_FEEDBACK_CONTRACT"] != "authored_solution"
        or role == "reviewer" and settings["QUESTION_FEEDBACK_CONTRACT"] == "authored_solution"
        or not _same(request.get("inferenceConfig"), inference)
        or not _same(request.get("additionalModelRequestFields"), additional)
        or set(request) != ({"modelId", "messages", "system", "inferenceConfig", "additionalModelRequestFields"}
                            | ({"outputConfig"} if is_native else set()))
        or len(shared.canonical(request).encode("utf-8")) > MAX_INPUT_BYTES
    ):
        raise ValueError("Unexpected provider settings/shape or input allowance exceeded.")
    if is_native:
        stage = contracts["author" if role.startswith("author") else role]
        config = request.get("outputConfig")
        if not _same(config, stage["outputConfig"]):
            raise ValueError("Native output contract bytes changed.")
        declaration = config["textFormat"]["structure"]["jsonSchema"]
        if (declaration["name"] != stage["contract_metadata"]["name"]
                or hashlib.sha256(declaration["schema"].encode()).hexdigest() != stage["contract_metadata"]["sha256"]
                or hashlib.sha256(request["system"][0]["text"].encode()).hexdigest() != stage["system_prompt_sha256"]):
            raise ValueError("Native prompt/schema identity mismatch.")
    return role


def make_plan(packet, *, source_revision=None):
    if type(packet) is dict and packet.get("experiment") == NATIVE_WORKFLOW_EXPERIMENT:
        return _make_native_workflow_plan(packet, source_revision=source_revision)
    if type(packet) is dict and packet.get("experiment") in {
        AUTHOR_COMPARISON_EXPERIMENT, FOCUSED_APPLICATION_EXPERIMENT,
    }:
        return _make_author_comparison_plan(packet, source_revision=source_revision)
    if type(packet) is dict and packet.get("experiment") == AUTHORED_EXPERIMENT:
        return _make_authored_plan(packet, source_revision=source_revision)
    if type(packet) is dict and packet.get("experiment") == RECHECK_EXPERIMENT:
        return _make_recheck_plan(packet, source_revision=source_revision)
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
    snapshot = _source_snapshot(source_revision)
    with patch.dict(os.environ, {**SETTINGS, "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"}):
        fixed_request = _normalize_request(copy.deepcopy(fixed["request"]))
        fresh_request = _normalize_request(copy.deepcopy(fresh["payload"]))
        questions = [copy.deepcopy(case["question"]) for case in cases]
        first = [_first_request(fixed_request, questions), _first_request(fresh_request)]
    return {
        "experiment": EXPERIMENT, "fixture": copy.deepcopy(packet), "fixture_sha256": _hash(packet),
        **snapshot,
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


def _make_native_workflow_plan(packet, *, source_revision):
    cases = packet.get("cases")
    if (set(packet) != {"experiment", "cases"} or type(cases) is not list or len(cases) != 3
            or any(type(case) is not dict or set(case) != {"case_id", "payload"}
                   or type(case["case_id"]) is not str or not case["case_id"].strip() for case in cases)
            or len({case["case_id"] for case in cases}) != 3):
        raise ValueError("Exactly three distinct fresh case_id/payload cases are required.")
    settings = {**SETTINGS, "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "MAX_QUESTIONS_PER_BATCH": "5"}
    operations = []
    with patch.dict(os.environ, settings):
        contracts = _native_stage_contracts()
        for case in cases:
            payload = case["payload"]
            if (type(payload) is not dict or type(payload.get("targetCount")) is not int
                    or payload["targetCount"] != 5 or type(payload.get("minimumDifficulty")) is not int
                    or payload["minimumDifficulty"] != 3):
                raise ValueError("Each fresh goal must request five questions at minimum difficulty three.")
            request = _normalize_request(copy.deepcopy(payload))
            if request["targetCount"] != 5 or request["minimumDifficulty"] != 3:
                raise ValueError("Normalization changed the fixed target or difficulty.")
            operations.append({"kind": "fresh", "case_id": case["case_id"], "request": request,
                               "maximum_calls": 6, "first_request": _first_request(request, settings=settings)})
    # Only this new mode binds the later offline backend/Swift delivery path.
    # Historical plans retain their original source-snapshot scope.
    from evals import checkpoint_delivery_check as delivery
    delivery_sources = sorted(set(delivery.SOURCE_FILES) | {
        "backend/bedrock-question-service/evals/checkpoint_native_delivery.py",
    })
    return {
        "experiment": NATIVE_WORKFLOW_EXPERIMENT, "fixture": copy.deepcopy(packet), "fixture_sha256": _hash(packet),
        **_source_snapshot(source_revision), "settings": settings, "native_contracts": contracts,
        "delivery_source_sha256": {
            name: hashlib.sha256((delivery.ROOT / name).read_bytes()).hexdigest() for name in delivery_sources
        },
        "operations": operations, "maximum_calls": 18,
        "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": 18 * MAX_INPUT_BYTES,
        "operation_seconds": OPERATION_SECONDS, "sdk_total_max_attempts": 1,
        "runtime_deadline_constants": {
            "client_setup_milliseconds": generation.DEFAULT_PROVIDER_CLIENT_SETUP_MILLISECONDS,
            "safety_milliseconds": generation.DEFAULT_PROVIDER_DEADLINE_SAFETY_MILLISECONDS,
        },
        "maximum_worker_capture_bytes": caller.MAX_CAPTURE_BYTES,
        "failure_policy": "Six calls and three ordinary generation attempts per goal; eighteen calls total. Native author, solver and reviewer requests must match frozen prompt/schema bytes, hashes, models and inference settings. Completed content rejection or recognized native format failure may continue to the next independent goal. Ordinary call-budget exhaustion is a coverage failure. Observer, dispatch, correlation, unknown-usage, unfinished-response, cleanup and persistence failures latch a global stop even if runtime retains a partial batch. Deadline/durable-budget and unrecognized exceptions stop. No added repair, retry, fallback, resume or replacement operation; an exclusive claim beside the original plan prevents its reuse with another output directory.",
        "scope": "Three fresh five-item local production workflows use Kimi authoring and Sonnet verification, disabled thinking, temperature0.2,6000tokens, native structured output and reviewer_written feedback. Only each original payload enters normalization and provider prompts. New source guidance and author/solver ordering remain part of the exact frozen runtime. No deployment, bank write or quality certification. Returned counts, format compliance and policy stamps do not establish factual correctness, reasonable distractors, teaching or difficulty.",
        "timing_scope": "Three separate240-second operation clocks; existing isolated observers use read75/connect3/SDK1 and at most32KiB per serialized request. Local cleanup can extend a wait slightly; parent persistence is not hard real-time. Fixed75 transport admission is conservative versus deployed late-operation read shortening. Missing responses leave remote completion and billing unknown.",
    }


def _source_snapshot(source_revision):
    revision = shared.source_revision() if source_revision is None else source_revision
    if (type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision)
            or subprocess.run(["git", "cat-file", "-e", revision + "^{commit}"],
                              cwd=SERVICE_DIR, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode):
        raise ValueError("A resolvable full source revision is required.")
    sources = shared.source_hashes()
    for name in ("evals/checkpoint_runtime_qualification.py", "evals/checkpoint_author_latency_probe.py",
                 "evals/checkpoint_immutable_review_eval.py", "evals/question_immutable_review.py",
                 "evals/question_complete_author.py", "evals/checkpoint_solution_compatibility_eval.py"):
        sources[name] = hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
    return {"source_revision": revision, "source_sha256": sources, "dependencies": shared.dependencies()}


def _make_authored_plan(packet, *, source_revision):
    cases = packet.get("cases")
    if (type(cases) is not list or len(cases) != 3
            or any(type(c) is not dict or type(c.get("case_id")) is not str
                   or not c["case_id"].strip() for c in cases)
            or len({c["case_id"] for c in cases}) != 3):
        raise ValueError("Exactly three distinct fresh goal cases are required.")
    settings = {**SETTINGS, "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
                "GENERATION_ATTEMPTS": "1", "MAX_PROVIDER_CALLS_PER_REQUEST": "3",
                "BEDROCK_THINKING_MAX_TOKENS": "6000"}
    if "trial_constraints" in packet:
        constraints = packet["trial_constraints"]
        expected = {
            "case_order": [c["case_id"] for c in cases], "requested_items_per_goal": 2,
            "requested_items_total": 6, "minimum_difficulty": 3,
            "maximum_provider_calls_per_goal": 3, "maximum_provider_calls_total": 9,
            "sdk_total_max_attempts": 1, "operation_seconds_per_goal": 240,
            "maximum_serialized_request_utf8_bytes_per_call": MAX_INPUT_BYTES,
            "maximum_serialized_request_utf8_bytes_total": 9 * MAX_INPUT_BYTES,
        }
        if (type(constraints) is not dict or type(constraints.get("environment")) is not dict
                or any(k not in settings or not _same(v, settings[k]) for k, v in constraints["environment"].items())
                or any(not _same(constraints.get(k), v) for k, v in expected.items())):
            raise ValueError("Declared fixture limits must match the fixed execution contract.")
    operations = []
    with patch.dict(os.environ, {**settings, "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"}):
        for case in cases:
            payload = case.get("payload")
            if (type(payload) is not dict or type(payload.get("targetCount")) is not int
                    or payload["targetCount"] != 2 or type(payload.get("minimumDifficulty")) is not int
                    or payload["minimumDifficulty"] != 3):
                raise ValueError("Every goal must request exactly two items at minimum difficulty three.")
            request = _normalize_request(copy.deepcopy(payload))
            operations.append({"kind": "fresh", "case_id": case["case_id"],
                               "request": request, "maximum_calls": 3,
                               "first_request": _first_request(request, settings=settings)})
    return {
        "experiment": AUTHORED_EXPERIMENT, "fixture": copy.deepcopy(packet), "fixture_sha256": _hash(packet),
        **_source_snapshot(source_revision), "settings": settings, "operations": operations,
        "maximum_calls": 9, "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": 9 * MAX_INPUT_BYTES,
        "operation_seconds": OPERATION_SECONDS, "sdk_total_max_attempts": 1,
        "runtime_deadline_constants": {
            "client_setup_milliseconds": generation.DEFAULT_PROVIDER_CLIENT_SETUP_MILLISECONDS,
            "safety_milliseconds": generation.DEFAULT_PROVIDER_DEADLINE_SAFETY_MILLISECONDS,
        },
        "maximum_worker_capture_bytes": caller.MAX_CAPTURE_BYTES,
        "failure_policy": "At most three calls per goal and nine total. One generation attempt; no added repair, top-up, fallback, retry, resume or replacement operation. Existing runtime author JSON repair remains visible and consumes the same three-call allowance, disqualifying a full unrepaired result. Operational/unfinished-response/cleanup/persistence failure stops all later goals. Ordinary content rejection remains separate.",
        "scope": "Fresh authoring through actual production functions with the authored_solution server opt-in, not deployed Lambda or bank writes. Kimi authors; Sonnet complete-choice solver and immutable main-teaching auditor use explicit disabled thinking and6000tokens. Only case payloads enter normalization; external assessment/provenance remains outside provider inputs. All raw final outputs are retained. Full unrepaired batch is a path/yield observation, not correctness, plausible-distractor or difficulty certification. Author main guidance remains320characters while immutable runtime admission permits420; no text is clipped to make it pass.",
        "timing_scope": "Three separate240-second operation clocks, bounded existing workers with read75/connect3/SDK1 and at most32KiB per serialized request. Local cleanup can extend a wait slightly; parent persistence is not hard real-time. Fixed75 transport admission is conservative versus deployed late-operation read shortening. No response means unknown usage/content/remote completion.",
    }


def _make_author_comparison_plan(packet, *, source_revision):
    focused = packet == {"experiment": FOCUSED_APPLICATION_EXPERIMENT}
    if not focused and packet != {"experiment": AUTHOR_COMPARISON_EXPERIMENT}:
        raise ValueError("The author comparison has no configurable inputs or profiles.")
    raw = AUTHOR_COMPARISON_ORIGIN.read_bytes()
    if hashlib.sha256(raw).hexdigest() != AUTHOR_COMPARISON_ORIGIN_SHA256:
        raise ValueError("The exact original three-goal fixture is required.")
    origin = json.loads(raw)
    base = _make_authored_plan(origin, source_revision=source_revision)
    operations = []
    for index, job in enumerate(base["operations"]):
        profile_key = "CHECKPOINT_PROMPT_VARIANT" if focused else "BEDROCK_MODEL_ID"
        request_key = "system" if focused else "modelId"
        profiles = ([("balanced", "balanced"), ("focused_application", "focused_application")]
                    if focused else [("kimi", "moonshotai.kimi-k2.5"),
                                     ("opus", "us.anthropic.claude-opus-4-6-v1")])
        if index == 1:
            profiles.reverse()
        for arm, value in profiles:
            settings = {**base["settings"], profile_key: value}
            if focused and not _same({k: v for k, v in settings.items() if k != profile_key},
                                     {k: v for k, v in base["settings"].items() if k != profile_key}):
                raise ValueError("Focused author profiles may differ only in prompt variant.")
            with patch.dict(os.environ, {**settings, "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"}):
                first = _first_request(job["request"], settings=settings)
            if not _same({k: v for k, v in first.items() if k != request_key},
                         {k: v for k, v in job["first_request"].items() if k != request_key}):
                raise ValueError(f"Paired author requests may differ only in {request_key}.")
            operations.append({**copy.deepcopy(job), "arm": arm, "settings": settings,
                               "first_request": first})
        if focused and _same(operations[-2]["first_request"]["system"], operations[-1]["first_request"]["system"]):
            raise ValueError("Focused and balanced author system prompts must differ.")
    plan = {
        **base, "experiment": packet["experiment"],
        "fixture": copy.deepcopy(packet), "fixture_sha256": _hash(packet),
        "origin": {"path": str(AUTHOR_COMPARISON_ORIGIN.relative_to(SERVICE_DIR.parents[1])),
                   "fixture_byte_sha256": AUTHOR_COMPARISON_ORIGIN_SHA256,
                   "fixture_canonical_sha256": _hash(origin), "fixture": origin,
                   "scope": "Original fixture and its original trial limits are provenance. This new paired plan freezes its own six-operation, eighteen-call limits. No previous questions, answers or error notes are inputs."},
        "operations": operations, "maximum_calls": 18,
        "maximum_input_utf8_bytes_total": 18 * MAX_INPUT_BYTES,
        "failure_policy": "At most three calls per operation and eighteen total. One generation attempt; no added repair, top-up, fallback, retry, resume or replacement. Existing author JSON repair consumes the same three-call allowance and disqualifies a full unrepaired batch. Operational, unfinished-response, cleanup or persistence failure stops all later operations.",
        "scope": "New contemporaneous author comparison on three selected original goal/source payloads: Kimi then Opus, Opus then Kimi, Kimi then Opus. Only author modelId changes in paired initial requests. Both use Sonnet complete-choice solving and immutable main-teaching audit, disabled thinking, 6000 tokens and temperature 0.2. Downstream requests depend on each arm's new candidates and solver survivors. No previous generated content or external assessment is sent. This is not a randomized general accuracy estimate, matched candidate comparison, deployment or default promotion. Author main guidance remains 320 characters; runtime admission permits 420 without clipping.",
        "timing_scope": "Six separate 240-second operation clocks; unchanged workers use read 75 seconds, connect 3 seconds and one SDK attempt. Each serialized request is bounded to 32 KiB. Local cleanup can extend a wait slightly; parent persistence is not hard real-time. Missing responses leave usage and remote completion unknown.",
    }
    if focused:
        plan["scope"] = "New paired Kimi author prompt comparison on three selected original goal/source payloads: balanced then focused_application, reversed on the middle goal. Only the author system prompt differs in paired initial requests; model, user content, output contract and inference settings stay fixed. Both use Sonnet complete-choice solving and immutable main-teaching audit, disabled thinking, 6000 tokens and temperature 0.2. Downstream inputs depend on each arm's new candidates and survivors. No previous generated content, keys, error notes or external assessment enters provider inputs. This is not a randomized general accuracy estimate, a comparison of identical generated candidates, deployment or default promotion. Author main guidance remains 320 characters and runtime admission 420, without clipping."
    return plan


def _make_recheck_plan(packet, *, source_revision):
    if packet != {"experiment": RECHECK_EXPERIMENT}:
        raise ValueError("The frozen recheck has no configurable inputs or profiles.")
    raw = RECHECK_ORIGIN.read_bytes()
    if hashlib.sha256(raw).hexdigest() != RECHECK_ORIGIN_SHA256:
        raise ValueError("The exact committed origin capture is required.")
    origin = json.loads(raw)
    prior = origin["plan"]
    if origin["status"] != "completed" or origin["plan_sha256"] != _hash(prior):
        raise ValueError("Origin capture/plan binding failed.")
    snapshot = _source_snapshot(source_revision)
    runtime = {k: v for k, v in snapshot["source_sha256"].items() if not k.startswith("evals/")}
    if runtime != {k: v for k, v in prior["source_sha256"].items() if not k.startswith("evals/")}:
        raise ValueError("Runtime sources changed since the original capture.")
    settings = {**SETTINGS, "BEDROCK_THINKING_MAX_TOKENS": "6000"}
    with patch.dict(os.environ, {**settings, "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"}):
        # Normalize the original user payload, never the already normalized object.
        request = _normalize_request(copy.deepcopy(prior["fixture"]["fresh"]["payload"]))
        if not _same(request, prior["operations"][1]["request"]):
            raise ValueError("Original normalized request cannot be reconstructed exactly.")
        author = origin["calls"][2]
        author_text = author["observation"]["response"]["text"]
        raw_questions = _extract_json_object(author_text).get("questions")
        questions = _sanitize_questions(raw_questions, request)
        if author["role"] != "author" or len(raw_questions) != 5 or len(questions) != 5:
            raise ValueError("Exactly the five original fresh candidates are required.")
        first = _first_request(request, questions, settings=settings)
        if not _same(first, origin["calls"][3]["request"]):
            raise ValueError("Original solver input/settings cannot be reconstructed exactly.")
    operations = []
    for mode in ("disabled", "adaptive"):
        profile = {**settings, "BEDROCK_CLAUDE_THINKING": mode}
        with patch.dict(os.environ, {**profile, "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"}):
            initial = _first_request(request, questions, settings=profile)
        if any(not _same(initial[k], first[k]) for k in ("modelId", "system", "messages")):
            raise ValueError("The two arms must preserve identical solver subject input.")
        operations.append({"kind": "fixed", "arm": mode, "settings": profile,
                           "request": copy.deepcopy(request), "questions": copy.deepcopy(questions),
                           "maximum_calls": 2, "first_request": initial})
    return {
        **copy.deepcopy(prior), **snapshot,
        "experiment": RECHECK_EXPERIMENT, "fixture": copy.deepcopy(packet), "fixture_sha256": _hash(packet),
        "settings": settings, "operations": operations, "maximum_calls": 4,
        "maximum_input_utf8_bytes_total": 4 * MAX_INPUT_BYTES,
        "origin": {
            "path": str(RECHECK_ORIGIN.relative_to(SERVICE_DIR.parents[1])),
            "capture_sha256": RECHECK_ORIGIN_SHA256, "plan_sha256": origin["plan_sha256"],
            "source_revision": prior["source_revision"], "source_sha256": prior["source_sha256"],
            "raw_author_call_index": 2, "baseline_call_indexes": [3, 4],
            "raw_author_text_sha256": hashlib.sha256(author_text.encode("utf-8")).hexdigest(),
            "normalized_request_sha256": _hash(request), "sanitized_candidates_sha256": _hash(questions),
            "runtime_sources_unchanged": True,
        },
        "failure_policy": "At most one solver and one survivor-only reviewer per arm. No author, repair, top-off, retries, fallback or resume. Operational/unfinished-response/cleanup/persistence failure stops both arms. Normal runtime content rejection remains distinct and does not force a reviewer call when no item survives.",
        "scope": "A new disabled-then-adaptive paired diagnostic on five selected archived authored MCQs, not fresh authoring or a randomized accuracy estimate. Both arms use Sonnet4.6/6000; adaptive sends high effort without sampling controls, disabled sends temperature0.2 without an effort field. Solver and reviewer settings change together. Original disabled results are historical evidence only. New reviewers see new solver survivors/reasons and generate feedback; they do not audit the old returned teaching fields. No deployed calls, bank writes or correctness guarantees.",
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
        self.settings = SETTINGS
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
            role = _guard_request(request, self.settings, self.report["plan"].get("native_contracts"))
            if position >= self.report["plan"]["maximum_calls"] or count >= operation["maximum_calls"]:
                raise ValueError("Call cap exceeded.")
            if operation["kind"] == "fixed" and role not in ("solver", "reviewer"):
                raise ValueError("Fixed batch cannot invoke an author.")
            if (self.report["plan"]["experiment"] == NATIVE_WORKFLOW_EXPERIMENT and count == 0
                    and not _same(request, self.report["plan"]["operations"][self.operation_index]["first_request"])):
                raise ValueError("Initial native request differs from the frozen plan.")
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
                    if (self.report["plan"]["experiment"] == NATIVE_WORKFLOW_EXPERIMENT
                            and not saved["observation"]["usage_known"]):
                        usable = False
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
                if (self.failed or not _usable_observation(state)
                        or self.report["plan"]["experiment"] == NATIVE_WORKFLOW_EXPERIMENT and not state["usage_known"]):
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


def _delivery_content_failure(error, calls):
    # Exact types exclude deadline/durable subclasses and unrelated failures.
    if type(error) is ProviderCallBudgetExceededError:
        return "call_budget_exhausted"
    if type(error) is InvalidProviderResponseError:
        return "invalid_provider_content"
    traceback = error.__traceback__
    while traceback is not None and traceback.tb_next is not None:
        traceback = traceback.tb_next
    if (type(error) is ProviderError and traceback is not None
            and traceback.tb_frame.f_code is _extract_json_object.__code__
            and [c["role"] for c in calls[-2:]] == ["author", "author_json_repair"]
            and all(c["lifecycle"] == "completed" and _usable_observation(c["observation"])
                    for c in calls[-2:])):
        return "malformed_author_json"
    # Native adaptation fails before legacy author JSON repair. Author errors
    # are wrapped by the payload function; solver/reviewer errors propagate.
    # Reproduce the content failure through the adapter, not its error prose.
    if (type(error) is ProviderError and traceback is not None
            and traceback.tb_frame.f_code in {
                generation._generate_provider_payload.__code__, generation._generate_with_bedrock.__code__,
                native.adapt_native_response.__code__,
            }
            and calls and calls[-1]["lifecycle"] == "completed" and _usable_observation(calls[-1]["observation"])
            and "outputConfig" in calls[-1]["request"]):
        last = calls[-1]
        contract = last["request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
        try:
            native.adapt_native_response(last["observation"]["response"]["text"].strip(), contract)
        except ProviderError:
            return "native_contract_invalid"
    return None


def _execute(plan, report, persist, observer=None, *, cli_credentials=False, replay=None):
    client = _RuntimeClient(report, persist, observer, cli_credentials, replay and replay["calls"])
    for index, job in enumerate(plan["operations"]):
        settings = job.get("settings", plan["settings"])
        native_workflow = plan["experiment"] == NATIVE_WORKFLOW_EXPERIMENT
        environment = {**settings, "BEDROCK_STRUCTURED_OUTPUT_MODE": "native" if native_workflow else "legacy"}
        with patch.dict(os.environ, environment), patch.object(caller, "SETTINGS", copy.deepcopy(settings)):
            result = report["operations"][index]
            result["status"] = "running"
            context = _OperationContext(result, None if replay is None else replay["operations"][index]["remaining_milliseconds"])
            client.operation_index, client.context = index, context
            client.settings = settings
            budget = generation.ProviderCallBudget(job["maximum_calls"], context=context)
            metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
            error_type, content_failure, questions = None, None, []
            runtime_started = False
            try:
                persist()
                runtime_started = True
                request = copy.deepcopy(job["request"])
                if job["kind"] == "fixed":
                    def invoke(system, user):
                        return generation._generate_legacy_with_bedrock(
                            request, client, generation._verification_model_id(), user, system,
                            budget, metrics,
                        )
                    questions = verify_questions(copy.deepcopy(job["questions"]), request, invoke,
                                                 metrics, solve=invoke, solver_contract="complete_choices")
                else:
                    questions = generation._generate_sanitized_questions(request, client, budget, metrics)
            except Exception as error:
                error_type = type(error).__name__
                if native_workflow and runtime_started and not client.failed:
                    content_failure = _delivery_content_failure(
                        error, [c for c in report["calls"] if c["operation_index"] == index],
                    )
                if content_failure is None:
                    client.failed = True
            if replay is not None and context.cursor != len(context.frozen):
                raise ValueError("Unused operation-clock observations.")
            result.update(status="operational_failure" if client.failed else "completed",
                          questions=questions, runtime_error_type=error_type,
                          budget_reservations=budget.calls,
                          metrics=_metrics_without_runtime_intervals(metrics))
            if native_workflow:
                roles = [c["role"] for c in report["calls"] if c["operation_index"] == index]
                target = job["request"]["targetCount"]
                if not client.failed and not questions:
                    result["status"] = "coverage_failure"
                result["result_category"] = (
                    "operational_failure" if client.failed else content_failure
                    or ("no_returned_questions" if not questions else
                        "full_delivery" if len(questions) == target else "partial_delivery")
                )
                result["delivery_observation"] = {
                    "requested_count": target, "returned_count": len(questions),
                    "shortfall_count": target - len(questions), "author_calls": roles.count("author"),
                    "topoff_author_calls": max(0, roles.count("author") - 1),
                    "author_json_repair_calls": roles.count("author_json_repair"),
                }
            if plan["experiment"] in {AUTHORED_EXPERIMENT, AUTHOR_COMPARISON_EXPERIMENT,
                                      FOCUSED_APPLICATION_EXPERIMENT}:
                repairs = sum(c["operation_index"] == index and c["role"] == "author_json_repair"
                              for c in report["calls"])
                result["authored_solution_observation"] = {
                    "requested_count": job["request"]["targetCount"], "returned_count": len(questions),
                    "author_json_repair_calls": repairs,
                    "full_unrepaired_batch": not client.failed and repairs == 0
                    and len(questions) == job["request"]["targetCount"],
                }
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
                            **({key: copy.deepcopy(j[key]) for key in ("arm", "case_id", "settings")}
                               if plan["experiment"] in {AUTHOR_COMPARISON_EXPERIMENT,
                                                         FOCUSED_APPLICATION_EXPERIMENT} else {}),
                            **({"case_id": j["case_id"]} if plan["experiment"] == NATIVE_WORKFLOW_EXPERIMENT else {}),
                            "status": "unattempted", "remaining_milliseconds": [], "questions": []}
                           for j in plan["operations"]]}


def run_trial(plan_path, approved_hash, directory, *, observer=None, cli_credentials=False):
    plan = load_frozen_plan(plan_path, approved_hash)
    directory = Path(directory)
    if plan["experiment"] == NATIVE_WORKFLOW_EXPERIMENT:
        if directory.exists():
            raise FileExistsError(directory)
        path = Path(plan_path).resolve()
        claim = path.with_name(path.name + ".execution-claim.json")
        with claim.open("x", encoding="utf-8") as handle:
            handle.write(shared.canonical({"plan_sha256": approved_hash, "directory": str(directory.resolve())}))
            handle.flush()
            os.fsync(handle.fileno())
        descriptor = os.open(claim.parent, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
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
