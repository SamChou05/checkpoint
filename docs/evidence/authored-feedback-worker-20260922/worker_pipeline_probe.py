"""Bounded production-generation experiment, pending root review and freeze.

Import and preflight never dispatch. Freeze pins all inputs; execute requires its
exact hash and an unused capture path. Credentials stay in memory. Local evidence
reservations do not exercise the deployed queue, ledger, lease, or worker handler.
"""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import inspect
import json
import math
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE_ROOT = Path("/tmp/checkpoint-authored-feedback-scope")
SERVICE = SOURCE_ROOT / "backend/bedrock-question-service"
DOMAIN_PLAN = HERE.parent / "question-reliability-release-20260922/pipeline-plan-v2.json"
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
import botocore  # noqa: E402
import authored_feedback_audit as audit  # noqa: E402
import authored_feedback_contract as author  # noqa: E402
import authored_feedback_verification as verifier  # noqa: E402
import question_generation as runtime  # noqa: E402
from complete_question_solution import COMPLETE_SOLUTION_SLOT_SYSTEM_PROMPT, rejection_reason, validate_batch  # noqa: E402
from native_output_contracts import (  # noqa: E402
    AuthoredFeedbackAuthorContract, AuthoredFeedbackReviewContract,
    SolverSlotContract, adapt_native_response, contract_metadata,
    native_output_config, native_prompt,
)
from question_bank_common import DurableProviderCallReservation  # noqa: E402
from service_errors import ProviderError  # noqa: E402
from service_errors import ProviderCallBudgetExceededError, ProviderDeadlineExceededError  # noqa: E402

ENVIRONMENT = {
    "BEDROCK_REGION": "us-east-1", "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
    "BEDROCK_MODEL_ID": "moonshotai.kimi-k2.5",
    "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
    "BEDROCK_FALLBACK_MODEL_ID": "", "BEDROCK_KIMI_THINKING": "disabled",
    "BEDROCK_CLAUDE_THINKING": "adaptive", "BEDROCK_CLAUDE_EFFORT": "high",
    "BEDROCK_MAX_TOKENS": "6000", "BEDROCK_THINKING_MAX_TOKENS": "16000",
    "BEDROCK_TEMPERATURE": "0.2", "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
    "BEDROCK_READ_TIMEOUT_SECONDS": "100", "BEDROCK_GUARDRAIL_IDENTIFIER": "",
    "BEDROCK_GUARDRAIL_VERSION": "", "QUESTION_FEEDBACK_CONTRACT": "authored_feedback",
    "CHECKPOINT_PROMPT_VARIANT": "balanced", "GENERATION_ATTEMPTS": "3",
    "MAX_PROVIDER_CALLS_PER_REQUEST": "6", "MIN_PROVIDER_REMAINING_MILLISECONDS": "0",
    "MAX_QUESTIONS_PER_BATCH": "20",
}
LIMITS = {
    "maximum_calls": 36, "maximum_calls_per_job": 6, "sdk_total_max_attempts": 1,
    "job_deadline_seconds": 240, "maximum_read_timeout_seconds": 100,
    "connect_timeout_seconds": 3, "minimum_read_timeout_seconds": 2,
    "author": {"maxTokens": 6000, "temperature": 0.2, "thinking": "disabled"},
    "solver": {"maxTokens": 16000, "thinking": "adaptive", "effort": "high"},
    "audit": {"maxTokens": 16000, "thinking": "adaptive", "effort": "high"},
}
CONTRACT_TYPES = (AuthoredFeedbackAuthorContract, SolverSlotContract, AuthoredFeedbackReviewContract)
ENDPOINT = "https://bedrock-runtime.us-east-1.amazonaws.com"
CREDENTIAL_COMMAND = ("aws", "configure", "export-credentials", "--format", "process")
CREDENTIAL_LIMITS = {"timeout_seconds": 15, "maximum_output_bytes": 32768}
PLAN_MAX_BYTES = 8 * 1024 * 1024
PRIMARY_CRITERIA = {
    "minimum_admitted_per_job": 3, "minimum_total_admitted_of_30": 27,
    "every_admitted_item": "Independently correct key, unique answer, distinct and plausible choices, task/assignment fit, novelty, difficulty, main explanation and all four choice explanations; uncertainty fails.",
    "all_six_jobs_in_denominator": True, "zero_defective_admitted_items": True,
    "all_attempts_retained": True, "reason_labels": "separate diagnostic",
    "provider_and_model_output_failures": "separate raw-attempt diagnostic; handled failures do not invalidate prior exact verified content",
    "structural_checks_cannot_qualify_release": True,
}
FAILURE_POLICY = (
    "Run each of the six unchanged jobs once through the actual production route, which owns normal retries, "
    "top-ups, termination and partial returns within six calls and 240 seconds. Continue the next fixed job after "
    "routine provider, non-end_turn, malformed output, deadline, local-call or durable-quota refusal. Count only "
    "content returned by runtime; retain all raw failures and all six jobs in the denominator. No harness retries, "
    "replacement jobs or rescues. Global abort only for credential/SDK setup, source/hash/request integrity, or "
    "dispatch/account-budget violation. Never dispatch above six calls per job or 36 total. No deployment or storage writes."
)
IMPORTED_SERVICE_HASHES = {str(path.relative_to(SERVICE)): hashlib.sha256(path.read_bytes()).hexdigest()
                           for path in sorted(SERVICE.glob("*.py"))}
_CREDENTIAL_REDACTIONS = ()
USAGE_FIELDS = ("inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens", "cacheWriteInputTokens")


def sha(value):
    return hashlib.sha256(value).hexdigest()


def save(path, value, *, exclusive=False):
    """Persist evidence; create plans/captures exclusively and update atomically."""
    if type(value) is dict and "calls" in value and "jobs" in value:
        value = copy.deepcopy(value)
        # Runtime records raw usage in its own telemetry. Sanitize only the
        # persisted snapshot, leaving its response and metrics objects untouched.
        for job in value["jobs"]:
            for observation in job.get("metrics", {}).get("ProviderObservations", []):
                if "usage" in observation:
                    observation["usage"] = bounded_numbers(observation["usage"], USAGE_FIELDS)
    encoded = json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(encoded)
        return
    temporary = path.with_suffix(".partial")
    temporary.write_text(encoded)
    temporary.replace(path)


def source_manifest():
    modules = sorted(SERVICE.glob("*.py"))
    if len(modules) != 26 or Path(runtime.__file__).resolve().parent != SERVICE.resolve():
        raise RuntimeError("Expected the explicitly selected final 26-module runtime.")
    if {path.name: sha(path.read_bytes()) for path in modules} != IMPORTED_SERVICE_HASHES:
        raise RuntimeError("Service files changed after runtime import.")
    for path in modules:
        loaded = sys.modules.get(path.stem)
        if loaded is not None and Path(getattr(loaded, "__file__", "")).resolve() != path.resolve():
            raise RuntimeError("A service module was imported from a different checkout.")
    return {"source_root": str(SOURCE_ROOT.resolve()),
            "service": {str(path.relative_to(SERVICE)): sha(path.read_bytes())
                        for path in [*modules, SERVICE / "requirements.txt", SERVICE / "scripts/validate-native-sdk.py"]},
            "harness": {path.name: sha(path.read_bytes())
                        for path in (Path(__file__), HERE / "test_worker_pipeline_probe.py", HERE / "PLAN.md")},
            "domain_plan_sha256": sha(DOMAIN_PLAN.read_bytes())}


def domain_jobs():
    jobs = json.loads(DOMAIN_PLAN.read_text())["jobs"]
    if len(jobs) != 6 or any(job["request"]["targetCount"] != 5 for job in jobs):
        raise RuntimeError("The unchanged six-domain, thirty-item specifications are required.")
    return copy.deepcopy(jobs)


def contract_registry():
    return {contract_metadata(kind(count))["name"]: contract_metadata(kind(count))
            for kind in CONTRACT_TYPES for count in range(1, 41)}


def stage_contract_pins():
    result = {}
    with patch.dict(os.environ, ENVIRONMENT, clear=True):
        systems = (runtime._system_prompt(), COMPLETE_SOLUTION_SLOT_SYSTEM_PROMPT,
                   verifier.FULL_FEEDBACK_AUDIT_SYSTEM_PROMPT)
        for kind, system in zip(CONTRACT_TYPES, systems, strict=True):
            for count in range(1, 41):
                contract = kind(count)
                metadata = contract_metadata(contract)
                result[metadata["name"]] = {"metadata": metadata, "output_config": native_output_config(contract),
                                            "system_prompt": native_prompt(system, contract)}
    return result


def dependencies():
    return {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__}


def execution_pins():
    domain_source = strict_json(DOMAIN_PLAN.read_text())
    with patch.dict(os.environ, ENVIRONMENT, clear=True):
        initial_prompts = [runtime._user_prompt(job["request"]) for job in domain_jobs()]
    return {"sources": source_manifest(), "dependencies": dependencies(), "jobs": domain_jobs(),
            "domain_source_input_and_gold_rules": domain_source,
            "environment": copy.deepcopy(ENVIRONMENT), "limits": copy.deepcopy(LIMITS),
            "endpoint": ENDPOINT, "registered_stage_contracts": stage_contract_pins(),
            "initial_author_user_prompts": initial_prompts, "prospective_criteria": copy.deepcopy(PRIMARY_CRITERIA),
            "failure_policy": FAILURE_POLICY, "credential_command": list(CREDENTIAL_COMMAND),
            "credential_limits": copy.deepcopy(CREDENTIAL_LIMITS),
            "runtime_boundary": "Real generation route with local durable-reservation journal; no deployed queue, lease, ledger, worker handler or inventory writes."}


def draft_description():
    return {"status": "draft_not_frozen", "sources": source_manifest(), "jobs": domain_jobs(),
            "dependencies": dependencies(),
            "environment": ENVIRONMENT, "proposed_limits": LIMITS,
            "registered_contracts": contract_registry(),
            "primary_criteria": copy.deepcopy(PRIMARY_CRITERIA),
            "reason_labels": "separate diagnostic; cannot replace learner-content criteria",
            "provider_calls": 0, "authorization": "none; root must review and select final bounds"}


class Deadline:
    def __init__(self, clock=time.monotonic):
        self.clock, self.start = clock, clock()

    def get_remaining_time_in_millis(self):
        return max(0, int((240 - (self.clock() - self.start)) * 1000))


def strict_json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate input property.")
            result[key] = value
        return result
    def nonfinite(_):
        raise ValueError("Nonfinite JSON.")

    def finite(text):
        value = float(text)
        if not math.isfinite(value):
            raise ValueError("Nonfinite JSON.")
        return value

    return json.loads(text, object_pairs_hook=unique, parse_constant=nonfinite, parse_float=finite)


def tagged(request, tag, *, embedded=False):
    text = request["messages"][0]["content"][0]["text"]
    opening, closing = f"<{tag}>\n", f"\n</{tag}>"
    if text.count(opening) != 1 or text.count(closing) != 1:
        raise ValueError("Missing or repeated stage wrapper.")
    if not embedded and not (text.startswith(opening) and text.endswith(closing)):
        raise ValueError("Unexpected text outside stage input.")
    return strict_json(text.split(opening, 1)[1].split(closing, 1)[0])


def learner_content(question):
    return author.freeze_learner_payload({field: question[field] for field in author.LEARNER_FIELDS})


def bounded_numbers(values, allowed):
    if type(values) is not dict:
        return {}
    return {key: values[key] for key in allowed if key in values
            and type(values[key]) in {int, float} and math.isfinite(values[key])
            and 0 <= values[key] <= 1_000_000_000_000}


def safe_response(response):
    message = response.get("output", {}).get("message", {})
    content = message.get("content", [])
    count = sum(isinstance(block, dict) and "reasoningContent" in block for block in content)
    retained = {"output": {"message": {"content": [
        {"text": block["text"]} for block in content if isinstance(block, dict)
        and "reasoningContent" not in block and type(block.get("text")) is str]}},
        "stopReason": redact(response.get("stopReason", ""))[:128]}
    for field, allowed in (("usage", USAGE_FIELDS),
                           ("metrics", ("latencyMs",))):
        retained[field] = bounded_numbers(response.get(field), allowed)
    metadata = response.get("ResponseMetadata", {})
    if type(metadata) is dict:
        retained["safeResponseMetadata"] = {
            "requestId": redact(metadata.get("RequestId", ""))[:128],
            "httpStatus": metadata.get("HTTPStatusCode") if type(metadata.get("HTTPStatusCode")) is int else None}
    return retained, count


def redact(value):
    text = str(value)
    for secret in sorted(_CREDENTIAL_REDACTIONS, key=len, reverse=True):
        if secret:
            text = text.replace(secret, "[REDACTED_CREDENTIAL]")
    return text


def error_details(error):
    result = {"error_type": type(error).__name__}
    response = getattr(error, "response", None)
    if isinstance(response, dict):
        problem, metadata = response.get("Error", {}), response.get("ResponseMetadata", {})
        result.update(provider_code=redact(problem.get("Code", ""))[:128],
                      provider_message=redact(problem.get("Message", ""))[:2000],
                      http_status=metadata.get("HTTPStatusCode") if type(metadata.get("HTTPStatusCode")) is int else None,
                      request_id=redact(metadata.get("RequestId", ""))[:128])
    return result


def credential_failure(error):
    return (type(error).__name__ in {"NoCredentialsError", "PartialCredentialsError", "CredentialRetrievalError",
                                    "UnauthorizedSSOTokenError", "TokenRetrievalError"}
            or error_details(error).get("provider_code") in {"ExpiredTokenException", "UnrecognizedClientException",
                                                            "InvalidSignatureException", "InvalidClientTokenId", "AccessDeniedException"})


def initial_capture(jobs):
    return {"status": "fake_preflight", "calls": [], "reservations": [], "failures": [],
            "jobs": [{"index": job["index"], "requested_count": job["request"]["targetCount"],
                      "status": "unattempted", "accepted": [], "passes": [],
                      "metrics": {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}}
                     for job in jobs]}


def summary(capture):
    jobs, calls = capture["jobs"], capture["calls"]
    counts = [len(job["accepted"]) for job in jobs]
    complete = len(jobs) == 6 and all(job["status"] == "finished" for job in jobs)
    return {"requested_total": sum(job["requested_count"] for job in jobs), "accepted_total": sum(counts),
            "accepted_by_job": counts, "provider_dispatch_attempts": len(calls),
            "local_reservations": len(capture["reservations"]),
            "yield_criterion_passed": len(counts) == 6 and min(counts) >= 3 and sum(counts) >= 27,
            "all_attempts_succeeded": bool(calls) and complete and not capture["failures"]
            and all(call.get("outcome") == "end_turn" for call in calls),
            "all_returned_content_has_exact_provenance": sum(counts) > 0
            and all(len(job.get("returned_provenance", [])) == len(job["accepted"]) for job in jobs),
            "recorded_failure_count": len(capture["failures"]),
            "provider_failure_calls": sum(call.get("outcome") == "provider_failure" for call in calls),
            "model_output_failure_calls": sum(call.get("outcome") in {"model_output_failure", "non_end_turn"} for call in calls),
            "global_integrity_abort": capture.get("stop_dispatching", False),
            "qualification_evidence_eligible": not capture.get("stop_dispatching", False),
            "deadline_criterion_passed": complete and all(job.get("within_240_second_deadline", False) for job in jobs),
            "semantic_adjudication": "pending_independent_audit", "reason_labels": "separate_diagnostic",
            "release_qualified": False}


class JobObserver:
    def __init__(self, capture, row, path, budget, request, *, integrity_check=None, stage_pins=None):
        self.capture, self.row, self.path, self.budget = capture, row, path, budget
        self.request, self.expected, self.current_pass = request, None, None
        self.final_stage_failure_dispatched = False
        self.integrity_check, self.stage_pins = integrity_check, stage_pins

    def failure(self, error, where, *, global_abort=False):
        if global_abort:
            self.capture["stop_dispatching"] = True
        self.capture["failures"].append({"job": self.row["index"], "where": where,
                                         "scope": "global" if global_abort else "attempt_or_job", **error_details(error)})
        save(self.path, self.capture)

    def guard(self):
        if self.capture.get("stop_dispatching"):
            raise ProviderError("Draft trial stopped after an earlier failure.")
        self.check_integrity()

    def check_integrity(self):
        if self.integrity_check is not None:
            try:
                self.integrity_check()
            except Exception as error:
                self.failure(error, "frozen_integrity", global_abort=True)
                raise

    def reserve(self):
        self.guard()
        if len(self.capture["reservations"]) >= 36:
            error = ProviderError("Global reservation ceiling reached.")
            self.failure(error, "account_budget", global_abort=True)
            raise error
        self.capture["reservations"].append({"job": self.row["index"],
                                             "remaining_before_ms": self.budget.remaining_milliseconds()})
        save(self.path, self.capture)

    def stage(self, original, *args, **kwargs):
        self.guard()
        bound = inspect.signature(original).bind(*args, **kwargs)
        bound.apply_defaults()
        context = bound.arguments
        contract = context["contract"]
        if type(contract) not in CONTRACT_TYPES or context["call_budget"] is not self.budget:
            error = ProviderError("Unplanned stage or budget.")
            self.failure(error, "stage_integrity", global_abort=True)
            raise error
        self.expected = context
        calls_before = len(self.capture["calls"])
        try:
            return original(*args, **kwargs)
        except Exception as error:
            self.final_stage_failure_dispatched = len(self.capture["calls"]) > calls_before
            if not self.capture.get("stop_dispatching"):
                self.failure(error, "runtime_stage_outcome")
            raise
        finally:
            self.expected = None

    def inspect_request(self, request):
        context = self.expected
        if context is None:
            raise ValueError("No trusted runtime call context.")
        contract = context["contract"]
        if set(request) != {"modelId", "messages", "inferenceConfig", "additionalModelRequestFields", "system", "outputConfig"}:
            raise ValueError("Unplanned request fields.")
        if self.stage_pins is not None:
            frozen = self.stage_pins[contract_metadata(contract)["name"]]
            if (request["outputConfig"] != frozen["output_config"]
                    or request["system"] != [{"text": frozen["system_prompt"]}]):
                raise ValueError("Request differs from the frozen schema or system prompt.")
        is_author = isinstance(contract, AuthoredFeedbackAuthorContract)
        expected_model = ENVIRONMENT["BEDROCK_MODEL_ID" if is_author else "BEDROCK_VERIFICATION_MODEL_ID"]
        if request["modelId"] != expected_model or request["outputConfig"] != native_output_config(contract):
            raise ValueError("Unplanned model or exact schema.")
        inference = {"maxTokens": 6000, "temperature": 0.2} if is_author else {"maxTokens": 16000}
        additional = {"thinking": {"type": "disabled"}} if is_author else {
            "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}}
        if request["inferenceConfig"] != inference or request.get("additionalModelRequestFields") != additional:
            raise ValueError("Unplanned stage settings.")
        prompt = context["user_prompt"] or runtime._user_prompt(context["normalized_request"])
        system = native_prompt(context["system_prompt"] or runtime._system_prompt(), contract)
        if request["messages"] != [{"role": "user", "content": [{"text": prompt}]}] or request.get("system") != [{"text": system}]:
            raise ValueError("Runtime prompt changed in transport.")
        if is_author:
            data = tagged(request, "generation_request_json", embedded=True)
            if data != runtime._provider_visible_request(context["normalized_request"]) or contract.count != context["normalized_request"]["targetCount"]:
                raise ValueError("Author count differs from the trusted current pass.")
        elif isinstance(contract, SolverSlotContract):
            items = tagged(request, "question_solution_json")["items"]
            if type(items) is not list or len(items) != contract.count or any(
                    type(item.get("index")) is not int or item["index"] != index for index, item in enumerate(items)):
                raise ValueError("Solver input identities are not exact and dense.")
            sources = []
            for item in items:
                matches = [source for source in self.current_pass["authored"] if "sanitized" in source
                           and source["sanitized"]["prompt"] == item["prompt"]]
                if len(matches) != 1:
                    raise ValueError("Solver input has no unique sanitized source.")
                source = matches[0]
                question = source["sanitized"]
                choices = question["choices"]
                slots = dict(zip("abcd", sorted(choices, key=lambda choice: (
                    sha(json.dumps([question["prompt"], choice], ensure_ascii=True, separators=(",", ":")).encode()),
                    choice)), strict=True))
                expected_item = {"index": len(sources), "prompt": question["prompt"], "choices": slots,
                                 "choicePairs": {pair: {"leftChoice": slots[pair[0]], "rightChoice": slots[pair[1]]}
                                                 for pair in ("ab", "ac", "ad", "bc", "bd", "cd")},
                                 **{field: question[field] for field in ("skillID", "objectiveID", "topic", "objective")
                                    if field in question}}
                if item != expected_item or source["source_id"] in sources:
                    raise ValueError("Solver subject, assignment, or pair endpoints changed.")
                sources.append(source["source_id"])
            self.current_pass.update(solver_sources=sources, solver_input=copy.deepcopy(items))
        else:
            data = tagged(request, "authored_feedback_audit_json")
            expected = self.current_pass.get("audit_input") if self.current_pass else None
            if data != expected or set(data["items"]) != {str(index) for index in range(contract.count)}:
                raise ValueError("Audit map differs from the observed immutable originals.")
            if request["system"] != [{"text": verifier.FULL_FEEDBACK_AUDIT_SYSTEM_PROMPT}]:
                raise ValueError("Full audit prompt changed.")
        return contract

    def observe_audit_input(self, original, *args, **kwargs):
        self.guard()
        if self.current_pass is None:
            raise ProviderError("Audit has no preceding author pass.")
        bound = inspect.signature(original).bind(*args, **kwargs)
        payloads = bound.arguments["original_payloads"]
        sources, used = [], set()
        for payload in payloads:
            frozen = author.freeze_learner_payload(payload)
            matches = [row for row in self.current_pass["authored"]
                       if row["source_id"] not in used and row["learner"] == frozen
                       and row["source_id"] in self.current_pass.get("solver_approved_sources", [])]
            if len(matches) != 1:
                raise ProviderError("Audit content lacks a unique exact author source.")
            sources.append(matches[0]["source_id"])
            used.add(matches[0]["source_id"])
        result = original(*args, **kwargs)
        fields = ("topic", "skillID", "objectiveID", "objective")
        by_source = {row["source_id"]: row for row in self.current_pass["authored"]}
        expected_assignments = [{field: by_source[source_id]["sanitized"][field]
                                 for field in fields if field in by_source[source_id]["sanitized"]}
                                for source_id in sources]
        history = self.current_pass["request"].get("existingQuestionCoverage", [])[-30:]
        expected_history = [{field: entry[field] for field in ("prompt", *fields) if field in entry}
                            for entry in history]
        expected_input = {field: copy.deepcopy(self.current_pass["request"].get(field))
                          for field in ("goal", "skillMap", "sourceDocuments")}
        expected_input.update(existingQuestionCoverage=expected_history, items={})
        for index, payload in enumerate(payloads):
            slots = dict(zip("abcd", payload["choices"], strict=True))
            expected_input["items"][str(index)] = {"prompt": payload["prompt"], "choices": slots,
                "feedback": {"main": payload["explanation"],
                             **{slot: payload["choiceExplanations"][text] for slot, text in slots.items()}},
                "assignment": expected_assignments[index]}
        if result != expected_input:
            raise ProviderError("Audit learner content, assignment, scope, or history changed from trusted originals.")
        self.current_pass.update(audit_sources=sources, audit_input=copy.deepcopy(result),
                                 audit_originals=copy.deepcopy(payloads))
        save(self.path, self.capture)
        return result

    def assess_response(self, raw, contract, request):
        adapted = adapt_native_response(raw, contract)
        if isinstance(contract, AuthoredFeedbackAuthorContract):
            questions = strict_json(adapted)["questions"]
            number = len(self.row["passes"])
            self.current_pass = {"index": number, "request": copy.deepcopy(self.expected["normalized_request"]), "authored": [
                {"source_id": f"{self.row['index']}:{number}:{index}", "learner": learner_content(question),
                 "digest": author.learner_content_digest(learner_content(question)), "question": question}
                for index, question in enumerate(questions)]}
            self.row["passes"].append(self.current_pass)
        elif isinstance(contract, SolverSlotContract):
            items = tagged(request, "question_solution_json")["items"]
            restored = [{**item, "choices": [item["choices"][slot] for slot in "abcd"]} for item in items]
            solutions = validate_batch(adapted, restored, audit_choice_pairs=True, choice_slots=True)
            by_source = {source["source_id"]: source["sanitized"] for source in self.current_pass["authored"]
                         if "sanitized" in source}
            self.current_pass["solver_approved_sources"] = [source_id for source_id, solution in zip(
                self.current_pass["solver_sources"], solutions, strict=True)
                if rejection_reason(solution, by_source[source_id], audit_choice_pairs=True) is None]
        else:
            self.current_pass["audit_rows"] = audit.validate(adapted, contract.count)
        return adapted

    def observe_sanitized(self, questions, original, context):
        if self.current_pass is None:
            raise ProviderError("Sanitizer has no preceding author pass.")
        raw_questions = context["raw_questions"]
        if raw_questions != [source["question"] for source in self.current_pass["authored"]]:
            raise ProviderError("Sanitizer did not receive the exact authored rows.")
        for question in questions:
            matches = [source for source in self.current_pass["authored"]
                       if source["learner"] == learner_content(question)]
            if len(matches) > 1:
                # Identical teaching is a model output possibility, not an
                # integrity failure. Replay only the pure sanitizer on prefixes
                # to identify which original row its ordered checks admitted.
                matched = []
                previous = []
                for index, source in enumerate(self.current_pass["authored"]):
                    prefix = original(copy.deepcopy(raw_questions[:index + 1]), copy.deepcopy(context["request"]),
                                      preserve_authored_explanation=context["preserve_authored_explanation"],
                                      preserve_authored_feedback=context["preserve_authored_feedback"])
                    if source in matches and len(prefix) > len(previous) and prefix[-1] == question:
                        matched.append(source)
                    previous = prefix
                matches = matched
            if len(matches) != 1:
                raise ProviderError("Sanitized content has no unique intact author source.")
            matches[0]["sanitized"] = copy.deepcopy(question)
        return questions

    def verify_returned(self, questions):
        eligible = []
        for run in self.row["passes"]:
            for index, source_id in enumerate(run.get("audit_sources", [])):
                assessment = run.get("audit_rows", {}).get(str(index))
                if assessment is None:
                    continue
                original = run["audit_originals"][index]
                key = author.SLOTS[original["choices"].index(original["expectedAnswer"])]
                if (assessment["task"]["judgment"] == "supported" and assessment["answerChoice"] == key
                        and all(value["judgment"] == "supported" for value in assessment["feedback"].values())):
                    eligible.append((source_id, original, assessment["difficulty"]))
        used, provenance = set(), []
        for question in questions:
            content = learner_content(question)
            matches = [(identity, difficulty) for identity, original, difficulty in eligible
                       if identity not in used and original == content]
            if len(matches) != 1:
                raise ProviderError("Returned content has no unique intact approved author source.")
            identity, difficulty = matches[0]
            if (question.get("verificationVersion") != 1 or question.get("verificationPolicyRevision") != 5
                    or type(question.get("difficulty")) is not int or question["difficulty"] != difficulty
                    or difficulty < self.request.get("minimumDifficulty", 1)):
                raise ProviderError("Returned policy or audited difficulty changed.")
            target = next((plan["targetDifficulty"] for plan in self.request.get("adaptiveSkillPlans", [])
                           if plan["skillID"] == question.get("skillID")), None)
            if target is not None and difficulty != target:
                raise ProviderError("Returned content misses its unchanged adaptive target.")
            used.add(identity)
            provenance.append({"source_id": identity, "digest": author.learner_content_digest(content)})
        self.row["returned_provenance"] = provenance


class Recorder:
    def __init__(self, client, observer):
        self.client, self.observer, self.meta = client, observer, client.meta

    def converse(self, **request):
        observer = self.observer
        observer.guard()
        capture, row, budget = observer.capture, observer.row, observer.budget
        try:
            if len(capture["calls"]) >= 36 or sum(call["job"] == row["index"] for call in capture["calls"]) >= 6:
                raise ValueError("Dispatch ceiling reached.")
            contract = observer.inspect_request(request)
            connect, read = runtime._client_transport_timeouts(self)
            remaining = budget.remaining_milliseconds()
            minimum = runtime._minimum_provider_remaining_milliseconds(connect_timeout=connect, read_timeout=read)
            if connect != 3 or not 2 <= read <= 100 or remaining is None:
                raise ValueError("Transport configuration differs from proposed bounds.")
            if self.meta.endpoint_url != ENDPOINT or self.meta.region_name != "us-east-1":
                raise ValueError("SDK client endpoint or region changed.")
            if self.meta.config.retries.get("total_max_attempts") != 1:
                raise ValueError("SDK total_max_attempts must be exactly one.")
            if remaining < minimum:
                raise ProviderDeadlineExceededError("Transport no longer fits the worker deadline.")
        except Exception as error:
            observer.failure(error, "request_admission", global_abort=not isinstance(error, ProviderCallBudgetExceededError))
            raise ProviderError("Draft request failed admission.") from error
        call = {"job": row["index"], "request": copy.deepcopy(request), "dispatch_attempted": True,
                "structured_output": contract_metadata(contract), "started_at": datetime.now(timezone.utc).isoformat(),
                "remaining_before_ms": remaining, "minimum_required_ms": minimum,
                "connect_timeout_seconds": connect, "read_timeout_seconds": read,
                "sdk_total_max_attempts": self.meta.config.retries.get("total_max_attempts"),
                "endpoint": self.meta.endpoint_url, "region": self.meta.region_name,
                "provider_budget_calls_at_dispatch": budget.calls}
        capture["calls"].append(call)
        save(observer.path, capture)
        started = time.monotonic()
        try:
            try:
                response = self.client.converse(**request)
            except Exception as error:
                call.update(outcome="provider_failure", **error_details(error))
                observer.failure(error, "provider_attempt", global_abort=credential_failure(error))
                raise
            finally:
                try:
                    observer.check_integrity()
                    call["integrity_after_dispatch"] = True
                except Exception:
                    call["integrity_after_dispatch"] = False
                    raise
            retained, count = safe_response(response)
            call.update(response=retained, reasoning_content_block_count=count, reasoning_text_retained=False)
            if response.get("stopReason") != "end_turn":
                call.update(outcome="non_end_turn", exact_transport_and_provenance=False)
                observer.failure(ProviderError("Non-end_turn completion."), "model_completion")
                # The production route decides whether this response is usable.
                return response
            raw = "\n".join(block["text"] for block in retained.get("output", {}).get("message", {}).get("content", [])
                            if isinstance(block, dict) and "text" in block)
            try:
                observer.assess_response(raw, contract, request)
            except (ProviderError, ValueError, TypeError) as error:
                call.update(outcome="model_output_failure", exact_transport_and_provenance=False, **error_details(error))
                observer.failure(error, "model_output")
                # Return the untouched response so only runtime owns retries,
                # top-ups, failure propagation, and verified partial results.
                return response
            call.update(outcome="end_turn", exact_transport_and_provenance=True)
            return response
        except Exception as error:
            if "outcome" not in call:
                call.update(outcome="harness_integrity_failure", **error_details(error))
                observer.failure(error, "response_observer_integrity", global_abort=True)
            raise
        finally:
            call["elapsed_seconds"] = round(time.monotonic() - started, 3)
            call["remaining_after_ms"] = budget.remaining_milliseconds()
            save(observer.path, capture)


def run_job(job, capture, path, *, client_factory, clock=time.monotonic, integrity_check=None, stage_pins=None):
    """Exercise real generation with an explicitly injected client factory.

    Local saved reservation records stand in for durable-call admission;
    no deployed storage or queue is accessed.
    """
    if capture.get("stop_dispatching"):
        return
    row = next(row for row in capture["jobs"] if row["index"] == job["index"])
    if row["status"] != "unattempted":
        raise RuntimeError("A job cannot be replayed inside one capture.")
    deadline = Deadline(clock)
    budget = runtime.ProviderCallBudget(6, context=deadline)
    observer = JobObserver(capture, row, path, budget, copy.deepcopy(job["request"]),
                           integrity_check=integrity_check, stage_pins=stage_pins)
    reservation = DurableProviderCallReservation(observer.reserve, 6)
    budget.reserve_call = reservation
    row["status"] = "running"
    started = clock()
    original_stage, original_input = runtime._generate_with_bedrock, audit.build_input
    original_sanitize = runtime._sanitize_questions

    def factory(call_budget=None):
        observer.guard()
        try:
            if call_budget is not budget:
                raise ValueError("Client factory received a different budget.")
            return Recorder(client_factory(call_budget), observer)
        except Exception as error:
            observer.failure(error, "client_admission", global_abort=not isinstance(error, ProviderCallBudgetExceededError))
            raise

    def stage(*args, **kwargs):
        return observer.stage(original_stage, *args, **kwargs)

    def audit_input(*args, **kwargs):
        try:
            return observer.observe_audit_input(original_input, *args, **kwargs)
        except Exception as error:
            observer.failure(error, "audit_provenance", global_abort=True)
            raise

    def sanitize(*args, **kwargs):
        questions = original_sanitize(*args, **kwargs)
        try:
            bound = inspect.signature(original_sanitize).bind(*args, **kwargs)
            bound.apply_defaults()
            return observer.observe_sanitized(questions, original_sanitize, bound.arguments)
        except Exception as error:
            observer.failure(error, "sanitizer_provenance", global_abort=True)
            raise

    try:
        with patch.dict(os.environ, ENVIRONMENT, clear=True), patch.object(runtime, "_bedrock_client", factory), \
                patch.object(runtime, "_generate_with_bedrock", stage), patch.object(audit, "build_input", audit_input):
            with patch.object(runtime, "_sanitize_questions", sanitize):
                returned = runtime._generate_sanitized_questions(copy.deepcopy(job["request"]), None, budget, row["metrics"])
            try:
                observer.verify_returned(returned)
            except Exception as error:
                observer.failure(error, "returned_provenance", global_abort=True)
                raise
            row["accepted"] = returned
        row["status"] = "finished"
    except Exception as error:
        row.update(status="failed", **error_details(error))
        if not capture.get("stop_dispatching"):
            observer.failure(error, "runtime_job_outcome", global_abort=not isinstance(
                error, ProviderError) and not observer.final_stage_failure_dispatched)
    row.update(elapsed_seconds=round(clock() - started, 3), remaining_ms=deadline.get_remaining_time_in_millis(),
               provider_budget_calls=budget.calls, local_reservations=6 - reservation.remaining_calls)
    row["within_240_second_deadline"] = row["elapsed_seconds"] <= 240
    save(path, capture)


def run_jobs(jobs, capture, path, *, client_factory, clock=time.monotonic, integrity_check=None, stage_pins=None):
    """Run all fixed jobs independently, unless an integrity condition aborts."""
    if jobs != domain_jobs():
        raise RuntimeError("The selected six domain requests changed.")
    baseline = source_manifest()
    capture["run_source_snapshot"] = baseline
    for job in jobs:
        if capture.get("stop_dispatching"):
            break
        try:
            if source_manifest() != baseline:
                raise RuntimeError("Source changed between jobs.")
            if integrity_check is not None:
                integrity_check()
        except Exception as error:
            capture["stop_dispatching"] = True
            capture["failures"].append({"scope": "global", "where": "source_integrity", **error_details(error)})
            break
        run_job(job, capture, path, client_factory=client_factory, clock=clock,
                integrity_check=integrity_check, stage_pins=stage_pins)
    capture["summary"] = summary(capture)
    save(path, capture)


def preflight():
    result = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", str(HERE),
                             "-p", "test_worker_pipeline_probe.py", "-v"], capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError("Fake-only preflight failed:\n" + result.stdout + result.stderr)
    return {"status": "draft_not_frozen", "provider_network_calls": 0, "result": "passed",
            "test_output": result.stderr.strip()}


def freeze(plan_path, candidate):
    if not candidate.strip() or len(candidate) > 2000:
        raise RuntimeError("A bounded root-selected candidate description is required.")
    if plan_path.exists():
        raise RuntimeError("The plan already exists; frozen experiments cannot be overwritten.")
    report = preflight()
    plan = {"plan_version": 1, "candidate": candidate,
            "frozen_at": datetime.now(timezone.utc).isoformat(), "pins": execution_pins(),
            "offline_preflight": report}
    save(plan_path, plan, exclusive=True)
    return {"plan_path": str(plan_path.resolve()), "plan_sha256": sha(plan_path.read_bytes()), "maximum_calls": 36}


def read_frozen_plan(plan_path, expected_hash):
    if plan_path.stat().st_size > PLAN_MAX_BYTES:
        raise RuntimeError("Frozen plan exceeds its input bound.")
    encoded = plan_path.read_bytes()
    if sha(encoded) != expected_hash:
        raise RuntimeError("Frozen plan hash changed.")
    plan = strict_json(encoded.decode("utf-8"))
    if (set(plan) != {"plan_version", "candidate", "frozen_at", "pins", "offline_preflight"}
            or plan["plan_version"] != 1 or plan["pins"] != execution_pins()
            or plan["offline_preflight"].get("result") != "passed"
            or plan["offline_preflight"].get("provider_network_calls") != 0):
        raise RuntimeError("Frozen source, inputs, contracts, settings, bounds or criteria changed.")
    return plan


def export_credentials():
    """Read only bounded AWS CLI process-format output into memory."""
    process = subprocess.Popen(CREDENTIAL_COMMAND, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    data = bytearray()
    deadline = time.monotonic() + CREDENTIAL_LIMITS["timeout_seconds"]
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise RuntimeError("Credential export exceeded its time bound.")
                chunk = os.read(process.stdout.fileno(), min(4096, CREDENTIAL_LIMITS["maximum_output_bytes"] + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > CREDENTIAL_LIMITS["maximum_output_bytes"]:
                    raise RuntimeError("Credential export exceeded its size bound.")
        if process.wait(timeout=max(0.001, deadline - time.monotonic())) != 0:
            raise RuntimeError("Credential export failed.")
        return bytes(data)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=3)
        process.stdout.close()


def credential_session():
    credentials = strict_json(export_credentials().decode("utf-8"))
    if type(credentials) is not dict or credentials.get("Version") != 1:
        raise RuntimeError("Credential process format is invalid.")
    for field, maximum in (("AccessKeyId", 128), ("SecretAccessKey", 256), ("SessionToken", 16384)):
        value = credentials.get(field)
        if field == "SessionToken" and value is None:
            continue
        if type(value) is not str or not value or len(value) > maximum:
            raise RuntimeError("Credential process field is invalid.")
    secrets = tuple(credentials[field] for field in ("AccessKeyId", "SecretAccessKey", "SessionToken") if credentials.get(field))
    session = boto3.Session(aws_access_key_id=credentials["AccessKeyId"],
                           aws_secret_access_key=credentials["SecretAccessKey"],
                           aws_session_token=credentials.get("SessionToken"), region_name="us-east-1")
    del credentials
    return session, secrets


def execute(expected_hash, plan_path):
    global _CREDENTIAL_REDACTIONS
    plan = read_frozen_plan(plan_path, expected_hash)
    if "plan" not in plan_path.name:
        raise RuntimeError("Plan filename must contain 'plan' to derive its exclusive capture.")
    capture_path = plan_path.with_name(plan_path.name.replace("plan", "capture", 1))
    capture = initial_capture(plan["pins"]["jobs"])
    capture.update(status="credential_setup", plan_sha256=expected_hash,
                   started_at=datetime.now(timezone.utc).isoformat())
    save(capture_path, capture, exclusive=True)
    previous_redactions = _CREDENTIAL_REDACTIONS

    def check_pins():
        read_frozen_plan(plan_path, expected_hash)

    try:
        session, _CREDENTIAL_REDACTIONS = credential_session()
        check_pins()
        original_factory = runtime._bedrock_client
        capture["status"] = "running"
        with patch("boto3.client", session.client):
            run_jobs(plan["pins"]["jobs"], capture, capture_path, client_factory=original_factory,
                     integrity_check=check_pins, stage_pins=plan["pins"]["registered_stage_contracts"])
        check_pins()
    except BaseException as error:
        capture["stop_dispatching"] = True
        capture["failures"].append({"scope": "global", "where": "execution_setup_or_integrity", **error_details(error)})
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            raise
    finally:
        capture.update(status="globally_aborted" if capture.get("stop_dispatching") else "complete",
                       finished_at=datetime.now(timezone.utc).isoformat(), summary=summary(capture))
        save(capture_path, capture)
        _CREDENTIAL_REDACTIONS = previous_redactions
    return {"capture_path": str(capture_path.resolve()), "status": capture["status"], "summary": capture["summary"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--preflight", action="store_true")
    action.add_argument("--freeze", action="store_true")
    action.add_argument("--execute", metavar="PLAN_SHA256")
    parser.add_argument("--candidate", default="")
    parser.add_argument("--plan", type=Path, default=HERE / "worker-plan.json")
    args = parser.parse_args()
    result = preflight() if args.preflight else freeze(args.plan, args.candidate) if args.freeze else execute(args.execute, args.plan)
    print(json.dumps(result, indent=2))
