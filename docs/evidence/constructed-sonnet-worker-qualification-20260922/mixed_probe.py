"""Unfrozen Sonnet-author constructed-task actual-route qualification; import and preflight make no calls."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = Path("/Users/samchou/.codex/worktrees/constructed-quantitative-authoring/Checkpoint/backend/bedrock-question-service").resolve()
ORIGINAL_JOBS = ROOT / "docs/evidence/quantitative-mixed-qualification-20260922/jobs-draft.json"
BASELINE_PLAN = ROOT / "docs/evidence/constructed-worker-qualification-20260922/plan.json"
BASELINE_CAPTURE = BASELINE_PLAN.with_name("capture.json")
BASELINE_PLAN_SHA256 = "29ca1b56074a64c9af5306c6c3e14880a6c7d9ed53bb065c6e2d0dd22f81b87c"
BASELINE_CAPTURE_SHA256 = "49833e414ec775090b3408ff6b73d5b967c401fd64b6b4294d7533f1ac8c2658"
AUTHOR_MODEL = "us.anthropic.claude-sonnet-4-6"
IMPORTED_SERVICE_HASHES = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(SERVICE.glob("*.py"))}
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
import botocore  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_generation as runtime  # noqa: E402
import question_quality as quality  # noqa: E402
from quantitative_authoring import LEARNER_FIELDS, CONSTRUCTED_AUTHOR_CONTRACT  # noqa: E402
from question_bank_common import DurableProviderCallReservation  # noqa: E402
from service_errors import ProviderError, SafetyInterventionError, ServiceConfigurationError  # noqa: E402

HELPER = SERVICE / "evals/bounded_bedrock_capture.py"
IMPORTED_HELPER_HASH = hashlib.sha256(HELPER.read_bytes()).hexdigest()
_spec = importlib.util.spec_from_file_location("mixed_capture_helper", HELPER)
safe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(safe)
ENDPOINT = "https://bedrock-runtime.us-east-1.amazonaws.com"
ENVIRONMENT = {
    "BEDROCK_REGION": "us-east-1", "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
    "QUESTION_AUTHOR_MODE": "constructed_quantitative", "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
    "BEDROCK_MODEL_ID": AUTHOR_MODEL, "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
    "BEDROCK_FALLBACK_MODEL_ID": "",
    "BEDROCK_CLAUDE_THINKING": "adaptive", "BEDROCK_CLAUDE_EFFORT": "high",
    "BEDROCK_MAX_TOKENS": "6000", "BEDROCK_KIMI_THINKING": "disabled", "BEDROCK_TEMPERATURE": "0.2", "BEDROCK_THINKING_MAX_TOKENS": "16000",
    "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3", "BEDROCK_READ_TIMEOUT_SECONDS": "100",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "", "BEDROCK_GUARDRAIL_VERSION": "",
    "GENERATION_ATTEMPTS": "3", "MAX_PROVIDER_CALLS_PER_REQUEST": "6",
    "MIN_PROVIDER_REMAINING_MILLISECONDS": "0", "CHECKPOINT_PROMPT_VARIANT": "balanced",
    "MAX_QUESTIONS_PER_BATCH": "20",
}
LIMITS = {"jobs": 3, "questions_per_job": 5, "maximum_calls": 18, "calls_per_job": 6,
          "seconds_per_job": 240, "read_ceiling": 100, "connect_timeout": 3, "sdk_attempts": 1}
PLAN, CAPTURE = HERE / "plan.json", HERE / "capture.json"
CAPTURE_HASHES = {}


class IntegrityError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise IntegrityError(message)


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True,
                                    allow_nan=False, separators=(",", ":")).encode()).hexdigest()


def check_capture(path):
    previous = CAPTURE_HASHES.get(path.resolve())
    require(previous is None or (path.is_file() and file_hash(path) == previous), "Capture was externally modified or removed.")


def save(path, value, *, exclusive=False):
    is_capture = type(value) is dict and "jobs" in value and "calls" in value
    if is_capture:
        check_capture(path)
    if type(value) is dict and "jobs" in value and "calls" in value:
        value = copy.deepcopy(value)
        for job in value["jobs"]:
            for observation in job.get("metrics", {}).get("ProviderObservations", []):
                # Keep this only in the bounded/redacted call response. The
                # runtime observation duplicates untrusted provider text.
                observation.pop("stopReason", None)
                if "usage" in observation:
                    observation["usage"] = safe.bounded_numbers(observation["usage"], safe.USAGE_FIELDS)
    text = json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(text)
    else:
        temporary = path.with_suffix(".partial")
        temporary.write_text(text)
        temporary.replace(path)
    if is_capture:
        CAPTURE_HASHES[path.resolve()] = file_hash(path)


def learner(question):
    return {key: copy.deepcopy(question[key]) for key in LEARNER_FIELDS}


def decoded_credential_echo(response, secrets):
    """Inspect the runtime's exact text concatenation without retaining it.

    Preserve duplicate JSON members during this scan so a later member cannot
    hide an earlier decoded string. Parsing failure grants no format approval;
    the unchanged native adapter handles malformed output as an ordinary failure.
    """
    content = response.get("output", {}).get("message", {}).get("content", [])
    text = "\n".join(block["text"] for block in content
                     if isinstance(block, dict) and isinstance(block.get("text"), str)).strip()
    if len(text.encode("utf-8")) > safe.VISIBLE_RESPONSE_MAX_BYTES:
        raise safe.CaptureBoundaryError("Visible runtime text exceeds capture allowance.")
    try:
        decoded = json.loads(text, object_pairs_hook=list)
    except (ValueError, RecursionError):
        return False
    pending = [decoded]
    while pending:
        value = pending.pop()
        if isinstance(value, str) and any(secret and secret in value for secret in secrets):
            return True
        if isinstance(value, (list, tuple)):
            pending.extend(value)
    return False


def build_plan():
    require(file_hash(HELPER) == IMPORTED_HELPER_HASH, "Capture helper changed after import.")
    require(Path(runtime.__file__).resolve().parent == SERVICE, "Wrong candidate runtime imported.")
    modules = sorted(SERVICE.glob("*.py"))
    require(len(modules) == 27 and (SERVICE / "quantitative_choice_construction.py") in modules,
            "Expected all 27 candidate runtime modules, including construction.")
    require({path.name: file_hash(path) for path in modules} == IMPORTED_SERVICE_HASHES, "Service files changed during or after import.")
    for path in modules:
        loaded = sys.modules.get(path.stem)
        if loaded is not None:
            require(Path(getattr(loaded, "__file__", "")).resolve() == path, "A service module came from another checkout.")
    require((HERE / "jobs-draft.json").read_bytes() == ORIGINAL_JOBS.read_bytes(), "Original goal requests changed.")
    jobs = safe.strict_json((HERE / "jobs-draft.json").read_text())["jobs"]
    require(file_hash(BASELINE_PLAN) == BASELINE_PLAN_SHA256
            and file_hash(BASELINE_CAPTURE) == BASELINE_CAPTURE_SHA256, "Original baseline plan/capture changed.")
    baseline = safe.strict_json(BASELINE_PLAN.read_text())
    require(baseline["state"] == "frozen" and len(baseline["source_hashes"]) == 37,
            "Expected frozen baseline with all37source pins.")
    for name, expected in baseline["source_hashes"].items():
        require(file_hash(Path(name)) == expected, "Frozen baseline source pin changed.")
    require([job["id"] for job in jobs] == ["quantitative", "python", "mixed"]
            and all(job["request"]["targetCount"] == 5 for job in jobs), "Fixed jobs changed.")
    require(jobs == baseline["jobs"] and LIMITS == baseline["limits"]
            and ENVIRONMENT == {**baseline["environment"], "BEDROCK_MODEL_ID": AUTHOR_MODEL},
            "Baseline jobs, budgets or settings beyond the author model changed.")
    paths = [*modules, SERVICE / "requirements.txt", SERVICE / "scripts/validate-native-sdk.py",
             HELPER, ORIGINAL_JOBS, BASELINE_PLAN, HERE / "mixed_probe.py", HERE / "test_mixed_probe.py",
             HERE / "PLAN.md", HERE / "jobs-draft.json", HERE / "make_blind_review.py", BASELINE_CAPTURE,
             *[Path(name) for name in baseline["source_hashes"]]]
    paths = sorted(set(paths))
    contracts = [CONSTRUCTED_AUTHOR_CONTRACT, *[kind(count) for kind in (native.SolverSlotContract, native.AuthoredSolutionFlagReviewContract)
                                       for count in range(1, 6)]]
    with patch.dict(os.environ, ENVIRONMENT, clear=True):
        initial = [{"system": native.native_prompt(runtime._system_prompt(), CONSTRUCTED_AUTHOR_CONTRACT),
                    "user": runtime._user_prompt(job["request"])} for job in jobs]
    require(initial == baseline["initial_author_prompts"], "Initial author system/task inputs changed.")
    require(all(native.native_output_config(contract) == baseline["contracts"][native.contract_metadata(contract)["name"]]
                for contract in contracts),
            "Author, prose solver or immutable auditor contracts changed.")
    return {"state": "draft", "source_root": str(SERVICE), "jobs": jobs, "environment": ENVIRONMENT,
            "limits": LIMITS, "endpoint": ENDPOINT, "source_hashes": {str(path): file_hash(path) for path in paths},
            "contracts": {native.contract_metadata(contract)["name"]: native.native_output_config(contract) for contract in contracts},
            "initial_author_prompts": initial,
            "dependencies": {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__},
            "criteria": copy.deepcopy(baseline["criteria"]),
            "credential_limits": {"seconds": safe.CREDENTIAL_TIMEOUT_SECONDS, "bytes": safe.CREDENTIAL_MAX_BYTES},
            "failure_policy": "Actual runtime owns bounded top-ups/partial returns. Independent jobs continue after ordinary provider/model/deadline/quota failure. Global credentials/setup/source/request/provenance/budget drift stops all dispatch. No harness retry or resume. Missing timeout usage is unknown.",
            "reused_scopes": {"original_jobs_path": str(ORIGINAL_JOBS), "original_jobs_sha256": file_hash(ORIGINAL_JOBS),
                              "baseline_plan_path": str(BASELINE_PLAN), "baseline_plan_sha256": file_hash(BASELINE_PLAN),
                              "baseline_capture_path": str(BASELINE_CAPTURE), "baseline_capture_sha256": file_hash(BASELINE_CAPTURE),
                              "baseline_source_pin_count": len(baseline["source_hashes"]),
                              "same_goal_requests": True, "not_a_matched_causal_comparison": True,
                              "changes": ["BEDROCK_MODEL_ID only: Kimi K2.5 to Sonnet4.6; unchanged existing adaptive/high Claude settings yield16000tokens and omit sampling for the author"],
                              "unchanged": ["runtime source0e4619f", "task-only author prompt/schema", "solver/auditor models and contracts", "three jobs", "all prospective criteria", "top-ups and budgets"]},
            "claim_limits": "Three newly generated candidate batches on repeated scopes, not fresh-domain generalization, a matched causal comparison, arbitrary-topic accuracy or deployed worker/inventory qualification; independent learner-content adjudication required."}


def check_plan(plan, path=None, expected_hash=None):
    require(plan == {**build_plan(), "state": plan["state"]} and plan["state"] in {"draft", "frozen"}, "Source or plan drift.")
    if path is not None:
        require(file_hash(path) == expected_hash, "Frozen plan bytes changed.")


def setup_failure(error):
    if type(error).__name__ in {"NoCredentialsError", "PartialCredentialsError", "CredentialRetrievalError",
                               "UnauthorizedSSOTokenError", "TokenRetrievalError", "NoRegionError", "ParamValidationError"}:
        return True
    response = getattr(error, "response", {})
    return type(response) is dict and response.get("Error", {}).get("Code") in {
        "ExpiredTokenException", "UnrecognizedClientException", "InvalidSignatureException", "InvalidClientTokenId", "AccessDeniedException"}


class Deadline:
    def __init__(self, clock):
        self.clock, self.started = clock, clock()

    def get_remaining_time_in_millis(self):
        return max(0, int((240 - (self.clock() - self.started)) * 1000))


def run_job(job, capture, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic):
    row = {"id": job["id"], "status": "running", "returned": [], "passes": [],
           "metrics": {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}}
    capture["jobs"].append(row)
    deadline = Deadline(clock)
    budget = runtime.ProviderCallBudget(6, context=deadline)
    stage_context, sources, accepted_objects = {}, {}, {}
    original_stage, original_prepare, original_sanitize = runtime._generate_with_bedrock, runtime.prepare_mixed_rows, runtime._sanitize_questions
    original_verify = runtime.verify_questions

    def guard(condition, message):
        if not condition:
            capture["global_stop"] = "request_transport_or_provenance_integrity"
            raise IntegrityError(message)

    def pins():
        try:
            check_capture(path)
            pin_check()
        except Exception:
            capture["global_stop"] = "source_integrity"
            raise

    def reserve():
        guard(not capture.get("global_stop"), "Global dispatch already stopped.")
        guard(len(capture["reservations"]) < 18, "Global reservation ceiling.")
        capture["reservations"].append({"job": job["id"], "ordinal": budget.calls})
        save(path, capture)

    budget.reserve_call = DurableProviderCallReservation(reserve, 6)

    def stage(*args, **kwargs):
        try:
            guard(not capture.get("global_stop"), "Global dispatch already stopped.")
            contract = kwargs.get("contract")
            name = native.contract_metadata(contract)["name"]
            guard(name in capture["plan"]["contracts"], "Unplanned native contract.")
            author = contract == CONSTRUCTED_AUTHOR_CONTRACT
            system = kwargs.get("system_prompt") or runtime._system_prompt()
            prompt = kwargs.get("user_prompt") or runtime._user_prompt(kwargs["normalized_request"])
            stage_context.clear()
            stage_context.update(name=name, author=author, system=native.native_prompt(system, contract), prompt=prompt,
                                 output_config=native.native_output_config(contract))
        except Exception:
            capture["global_stop"] = "stage_configuration_integrity"
            raise
        try:
            return original_stage(*args, **kwargs)
        except ServiceConfigurationError:
            # The runtime preserves prior verified output after a failed top-up.
            # A native schema/configuration failure still stops this trial globally.
            capture["global_stop"] = "native_stage_configuration"
            raise

    def prepare(payload, **kwargs):
        guard(kwargs == {"construct_choices": True}, "Constructed author mode lost its trusted adapter setting.")
        result = original_prepare(payload, **kwargs)
        raw, compiled, failures = result
        record = {"ordinal": len(row["passes"]), "author_payload": copy.deepcopy(payload),
                  "prepared": copy.deepcopy(raw), "compiled": [], "sanitized": []}
        row["passes"].append(record)
        for index, provenance in compiled.items():
            source = {"source": [job["id"], record["ordinal"], index],
                      "spec": json.loads(provenance.spec_json), "learner": provenance.content()}
            sources[id(provenance)] = source
            record["compiled"].append(copy.deepcopy(source))
        record["compiler_rejections"] = failures
        return raw, compiled, failures

    def sanitize(*args, **kwargs):
        result = original_sanitize(*args, **kwargs)
        record = row["passes"][-1]
        for index, question in enumerate(result):
            provenance = kwargs.get("compiled_output", {}).get(index)
            item = {"index": index, "source": [job["id"], record["ordinal"], index],
                    "source_stage": "sanitized", "question": copy.deepcopy(question)}
            if provenance is not None:
                guard(id(provenance) in sources, "Compiler provenance has no author source.")
                provenance.content(question)
                item["compiled_source"] = copy.deepcopy(sources[id(provenance)])
            else:
                # Exact current-pass bindings using the actual sanitizer's
                # existing text adapters, never fuzzy matching across retries.
                # Identical raw duplicates may share this teaching; no claim is
                # made that their raw ordinal is unique. The observer identity
                # used after verification is the unique sanitized ordinal.
                raw_matches = [raw_index for raw_index, raw in enumerate(record["prepared"])
                               if type(raw) is dict and raw.get("explanation") == question["explanation"]
                               and quality._prompt_without_trailing_choice_echo(raw.get("prompt"), raw.get("choices")) == question["prompt"]
                               and quality._choice_uniqueness_key(str(raw.get("expectedAnswer") or "")) == question["expectedAnswer"]
                               and quality._normalized_choices(raw.get("choices"), question["expectedAnswer"]) == question["choices"]]
                guard(bool(raw_matches), "Sanitized prose main has no exact author-content binding.")
                item["author_main_sources"] = [[job["id"], record["ordinal"], raw_index] for raw_index in raw_matches]
            record["sanitized"].append(item)
        return result

    def verify(questions, *args, **kwargs):
        record = row["passes"][-1]
        guard(len(questions) == len(record["sanitized"]), "Verifier input lacks current-pass sources.")
        by_prompt = {}
        for question, item in zip(questions, record["sanitized"], strict=True):
            guard(question == item["question"] and question["prompt"] not in by_prompt,
                  "Verifier input lost exact current-pass association.")
            by_prompt[question["prompt"]] = item
        returned = original_verify(questions, *args, **kwargs)
        record["verified"] = []
        for question in returned:
            # Sanitization guarantees unique stems within this pass. The final
            # generator return is bound to these actual accepted objects, never
            # searched by learner content across different author attempts.
            item = by_prompt.get(question["prompt"])
            guard(item is not None, "Verifier returned an unknown current-pass item.")
            original = item["question"]
            for key in ("prompt", "choices", "expectedAnswer", "explanation"):
                guard(question[key] == original[key], "Verifier rewrote immutable learner content.")
            source = copy.deepcopy(item.get("compiled_source"))
            if source is not None:
                guard(question.get("verificationPolicyRevision") == 8 and learner(question) == source["learner"],
                      "Compiled release changed exact five fields or provenance.")
            else:
                guard(question.get("verificationPolicyRevision") == 7 and question.get("choiceExplanations") == {},
                      "Prose release acquired choice feedback or the wrong policy.")
            entry = {"source": copy.deepcopy(item["source"]), "compiled_source": source,
                     "question": copy.deepcopy(question)}
            guard(id(question) not in accepted_objects, "Verifier repeated a returned object.")
            # Keep a strong reference so Python cannot recycle an earlier id.
            accepted_objects[id(question)] = (question, entry)
            record["verified"].append(copy.deepcopy(entry))
        return returned

    class Recorder:
        def __init__(self, client):
            self.client, self.meta = client, client.meta

        def converse(self, **request):
            guard(not capture.get("global_stop"), "Global dispatch already stopped.")
            pins()
            cfg = self.meta.config
            guard(self.meta.endpoint_url == ENDPOINT and self.meta.region_name == "us-east-1"
                    and cfg.connect_timeout == 3 and 2 <= cfg.read_timeout <= 100
                    and cfg.retries.get("total_max_attempts") == 1, "Unplanned transport.")
            guard(len(capture["calls"]) < 18 and budget.calls <= 6
                    and len([call for call in capture["calls"] if call["job"] == job["id"]]) < budget.calls,
                    "Dispatch lacks a call reservation.")
            author = stage_context["author"]
            guard(request == {"modelId": ENVIRONMENT["BEDROCK_MODEL_ID" if author else "BEDROCK_VERIFICATION_MODEL_ID"],
                "system": [{"text": stage_context["system"]}],
                "messages": [{"role": "user", "content": [{"text": stage_context["prompt"]}]}],
                "outputConfig": stage_context["output_config"],
                "inferenceConfig": {"maxTokens": 16000},
                "additionalModelRequestFields": {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}}}, "Actual request drift.")
            call = {"job": job["id"], "stage": stage_context["name"], "request": copy.deepcopy(request),
                    "read_timeout": cfg.read_timeout, "connect_timeout": cfg.connect_timeout, "sdk_attempts": 1,
                    "remaining_before_ms": budget.remaining_milliseconds()}
            capture["calls"].append(call)
            save(path, capture)
            started = clock()
            try:
                response = self.client.converse(**request)
                retained, omitted = safe.safe_response(response, secrets)
                visible = json.dumps(retained, ensure_ascii=False)
                guard(not any(secret and secret in visible for secret in secrets), "Credential echo in visible output.")
                guard(not decoded_credential_echo(response, secrets), "Credential echo in decoded native output.")
                call.update(response=retained, reasoning_blocks_omitted=omitted)
                return response
            except Exception as error:
                call["error"] = safe.safe_error(error, secrets)
                if setup_failure(error) or isinstance(error, (IntegrityError, safe.CaptureBoundaryError)):
                    capture["global_stop"] = "provider_setup_or_capture_integrity"
                raise
            finally:
                call["elapsed_seconds"] = round(clock() - started, 6)
                call["remaining_after_ms"] = budget.remaining_milliseconds()
                try:
                    pins()
                except Exception:
                    capture["global_stop"] = "post_dispatch_source_drift"
                    raise
                finally:
                    save(path, capture)

    def client(*args, **kwargs):
        try:
            guard(not capture.get("global_stop"), "Global dispatch already stopped.")
            guard(args == ("bedrock-runtime",) and set(kwargs) == {"region_name", "config"}, "Unplanned SDK client creation.")
            return Recorder(client_factory(*args, **kwargs))
        except Exception:
            capture["global_stop"] = "sdk_factory_setup"
            raise

    try:
        pins()
        with patch.dict(os.environ, ENVIRONMENT, clear=True), patch.object(boto3, "client", client), \
                patch.object(runtime, "_generate_with_bedrock", stage), patch.object(runtime, "prepare_mixed_rows", prepare), \
                patch.object(runtime, "_sanitize_questions", sanitize), patch.object(runtime, "verify_questions", verify):
            returned = runtime._generate_sanitized_questions(copy.deepcopy(job["request"]), None, budget, row["metrics"])
        provenance, returned_sources = [], []
        for question in returned:
            observed = accepted_objects.get(id(question))
            guard(observed is not None and observed[0] is question and observed[1]["question"] == question,
                  "Runtime return lacks unchanged actual verifier-object identity.")
            returned_sources.append(copy.deepcopy(observed[1]["source"]))
            provenance.append(copy.deepcopy(observed[1]["compiled_source"]))
        row.update(returned=returned, returned_provenance=provenance, returned_sources=returned_sources, status="finished")
    except Exception as error:
        row.update(status="failed", error=safe.safe_error(error, secrets))
        if isinstance(error, (IntegrityError, safe.CaptureBoundaryError)) or setup_failure(error) or not isinstance(error, (ProviderError, SafetyInterventionError)):
            capture["global_stop"] = "setup_or_integrity_failure"
    finally:
        row.update(elapsed_seconds=round(clock() - deadline.started, 6), provider_calls=budget.calls,
                   remaining_ms=budget.remaining_milliseconds())
        row["within_deadline"] = row["elapsed_seconds"] <= 240
        pins()
        save(path, capture)


def run_jobs(plan, capture, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic):
    require(not capture["calls"] and not capture["jobs"], "No resume or repeat.")
    for job in plan["jobs"]:
        if capture.get("global_stop"):
            break
        run_job(job, capture, path, client_factory, pin_check, secrets=secrets, clock=clock)
    pin_check()
    finish(capture)
    save(path, capture)


def finish(capture):
    capture["summary"] = {"planned_jobs": 3, "planned_questions": 15, "attempted_jobs": len(capture["jobs"]),
                          "attempted_calls": len(capture["calls"]),
                          "returned_questions": sum(len(row["returned"]) for row in capture["jobs"] if row["within_deadline"]),
                          "independent_content_review": "pending", "qualified": False}
    usages = [call.get("response", {}).get("usage", {}) for call in capture["calls"]]
    capture["summary"]["reported_token_usage"] = {
        "input_tokens": sum(usage.get("inputTokens", 0) for usage in usages),
        "output_tokens": sum(usage.get("outputTokens", 0) for usage in usages),
        "calls_without_reported_usage": sum(not usage for usage in usages), "missing_usage_is_not_zero": True}
    capture["status"] = "globally_aborted" if capture.get("global_stop") else "completed_pending_review"


def preflight():
    result = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", str(HERE),
                             "-p", "test_mixed_probe.py", "-q"], capture_output=True, text=True)
    require(result.returncode == 0, "Offline tests failed: " + result.stderr)
    return {"provider_calls": 0, "result": "passed", "output": result.stderr.strip()}


def freeze(reviewed_digest):
    draft = build_plan()
    require(digest(draft) == reviewed_digest, "Draft digest changed.")
    preflight()
    require(build_plan() == draft, "Sources changed during preflight.")
    save(PLAN, {**draft, "state": "frozen"}, exclusive=True)
    return {"plan_sha256": file_hash(PLAN), "provider_calls": 0}


def execute(expected_hash):
    require(PLAN.stat().st_size <= 8 * 1024 * 1024 and file_hash(PLAN) == expected_hash, "Plan bound/hash failed.")
    plan = safe.strict_json(PLAN.read_text())
    require(plan["state"] == "frozen", "Plan is not frozen.")
    check_plan(plan, PLAN, expected_hash)
    capture = {"plan": plan, "plan_sha256": expected_hash, "calls": [], "jobs": [], "reservations": [],
               "started_at": datetime.now(timezone.utc).isoformat(), "status": "setup"}
    save(CAPTURE, capture, exclusive=True)
    secrets = ()
    try:
        session, secrets = safe.credential_session()
        run_jobs(plan, capture, CAPTURE, session.client, lambda: check_plan(plan, PLAN, expected_hash), secrets=secrets)
    except BaseException as error:
        capture.update(status="globally_aborted", global_stop="setup_or_interruption", error=safe.safe_error(error, secrets))
        finish(capture)
        save(CAPTURE, capture)
        if isinstance(error, (SystemExit, KeyboardInterrupt)):
            raise
    return {"capture": str(CAPTURE), "status": capture["status"], "summary": capture.get("summary")}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--draft", action="store_true")
    group.add_argument("--preflight", action="store_true")
    group.add_argument("--freeze")
    group.add_argument("--execute")
    args = parser.parse_args()
    result = ({"draft_digest": digest(build_plan()), "plan": build_plan()} if args.draft else preflight() if args.preflight
              else freeze(args.freeze) if args.freeze else execute(args.execute))
    print(json.dumps(result, ensure_ascii=True, indent=2))
