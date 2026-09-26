"""Draft four-call author-only prose comparison; preparation makes no provider calls."""

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
from types import SimpleNamespace
from unittest.mock import patch

import boto3
import botocore


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))
from request_contract import _normalize_request  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_generation as runtime  # noqa: E402
from service_errors import (  # noqa: E402
    ProviderCallBudgetExceededError, ProviderDeadlineExceededError, ProviderError,
    SafetyInterventionError, ServiceConfigurationError,
)

HELPER = SERVICE / "evals/bounded_bedrock_capture.py"
_spec = importlib.util.spec_from_file_location("prose_semantic_bounded_capture", HELPER)
safe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(safe)
IMPORTED_NATIVE_PROMPT = runtime.native_prompt
CONTRACT = "question_author_v3"
MODEL = "us.anthropic.claude-sonnet-4-6"
ENDPOINT = "https://bedrock-runtime.us-east-1.amazonaws.com"
BASE_COMMIT = "3e6612e00c9b062e7b08493104afcad5d7fe3044"
CANDIDATE_COMMIT = "ce304bfeb717fd794eb87b1e4b61921845612703"
ENV = {
    "BEDROCK_REGION": "us-east-1", "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
    "BEDROCK_MODEL_ID": MODEL, "BEDROCK_FALLBACK_MODEL_ID": "",
    "QUESTION_AUTHOR_MODE": "prose", "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
    "CHECKPOINT_PROMPT_VARIANT": "balanced", "BEDROCK_CLAUDE_THINKING": "adaptive",
    "BEDROCK_CLAUDE_EFFORT": "high", "BEDROCK_MAX_TOKENS": "6000",
    "BEDROCK_THINKING_MAX_TOKENS": "16000", "GENERATION_ATTEMPTS": "1",
    "MAX_PROVIDER_CALLS_PER_REQUEST": "1", "BEDROCK_READ_TIMEOUT_SECONDS": "200",
    "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3", "BEDROCK_GUARDRAIL_IDENTIFIER": "",
    "BEDROCK_GUARDRAIL_VERSION": "",
}
ORDER = (("baseline", "python_boolean"), ("candidate", "python_boolean"),
         ("candidate", "american_english"), ("baseline", "american_english"))
DRAFT, PLAN, CAPTURE = (HERE / name for name in ("plan-draft.json", "plan.json", "capture.json"))


class IntegrityError(RuntimeError):
    """A pinned source, request, budget, or capture changed."""


def require(condition, message):
    if not condition:
        raise IntegrityError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def digest(value):
    encoded = json.dumps(value, sort_keys=True, ensure_ascii=True, allow_nan=False,
                         separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def save(path, value, *, exclusive=False):
    payload = json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(payload)
    else:
        temporary = path.with_suffix(".partial")
        temporary.write_text(payload)
        temporary.replace(path)


def suffix():
    text = (HERE / "candidate-suffix-draft.txt").read_text().rstrip("\n")
    require(text.startswith("For authored prose questions,") and text.endswith("an unconditional rule."),
            "Candidate guidance file changed shape.")
    return "\n\n" + text


def arm_prompt(system, contract, arm):
    require(contract == CONTRACT, "Author-only native prose contract changed.")
    candidate = IMPORTED_NATIVE_PROMPT(system, contract)
    addition = suffix()
    require(candidate.count(addition) == 1, "Candidate guidance missing or duplicated.")
    return candidate if arm == "candidate" else candidate.replace(addition, "", 1)


def generate(job, client=None, budget=None):
    with patch.object(runtime, "native_prompt", side_effect=lambda system, contract:
                      arm_prompt(system, contract, job["arm"])):
        return runtime._generate_provider_payload(copy.deepcopy(job["normalized_request"]), client, budget)


def author_request(job):
    captured = []

    def converse(**request):
        captured.append(copy.deepcopy(request))
        return {"stopReason": "end_turn", "output": {"message": {"content": [
            {"text": '{"questions":[]}'},
        ]}}}

    with patch.dict(os.environ, ENV, clear=True):
        generate(job, SimpleNamespace(converse=converse), runtime.ProviderCallBudget(1))
    require(len(captured) == 1, "Draft request used more or fewer than one fake call.")
    request = captured[0]
    require(request["modelId"] == MODEL and request["inferenceConfig"] == {"maxTokens": 16000},
            "Author model or inference config drift.")
    require(request["additionalModelRequestFields"] == {
        "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
        "Author reasoning config drift.")
    require(request["outputConfig"] == native.native_output_config(CONTRACT), "Native schema drift.")
    return request


def source_paths():
    return [*sorted(SERVICE.glob("*.py")), SERVICE / "requirements.txt", HELPER,
            *[HERE / name for name in ("author_probe.py", "test_author_probe.py", "jobs-draft.json",
                                        "candidate-suffix-draft.txt", "PLAN.md")]]


def verify_historical_prompt_delta():
    relative = "backend/bedrock-question-service/question_generation.py"
    candidate_source = (ROOT / relative).read_text()
    old = "        base_prompt += teaching"
    added = old + ' + """' + suffix() + '\n""".rstrip()'
    require(candidate_source.count(added) == 1, "Candidate source guidance delta changed.")
    baseline_source = candidate_source.replace(added, old, 1)
    for commit, expected in ((BASE_COMMIT, baseline_source), (CANDIDATE_COMMIT, candidate_source)):
        result = subprocess.run(["git", "show", f"{commit}:{relative}"], cwd=ROOT,
                                capture_output=True, text=True, check=True)
        require(result.stdout == expected, "Historical candidate/baseline source differs from exact guidance delta.")


def build_plan():
    verify_historical_prompt_delta()
    raw = safe.strict_json((HERE / "jobs-draft.json").read_text())
    require(raw["status"] == "draft_unfrozen_no_provider_calls"
            and [item["id"] for item in raw["jobs"]] == ["python_boolean", "american_english"],
            "Fixed scope draft changed.")
    normalized = {item["id"]: _normalize_request(item["request"]) for item in raw["jobs"]}
    require(all(item["targetCount"] == 5 and item["minimumDifficulty"] == 2
                for item in normalized.values()), "Five-slot scope changed.")
    with patch.dict(os.environ, ENV, clear=True):
        system = runtime._system_prompt()
    require(system.count(suffix()) == 1 and system.endswith(suffix()),
            "Candidate is not the exact final authored-solution guidance suffix.")
    calls = []
    for arm, scope in ORDER:
        job = {"index": len(calls), "arm": arm, "scope": scope,
               "normalized_request": normalized[scope]}
        job["request"] = author_request(job)
        job["request_sha256"] = digest(job["request"])
        calls.append(job)
    for base, candidate in ((0, 1), (3, 2)):
        a, b = calls[base]["request"], copy.deepcopy(calls[candidate]["request"])
        require(b["system"][0]["text"].replace(suffix(), "", 1) == a["system"][0]["text"],
                "Per-scope author prompt differs beyond exact suffix.")
        b["system"] = a["system"]
        require(a == b, "Per-scope author requests differ beyond candidate guidance.")
    return {
        "state": "draft", "source_root": str(ROOT), "candidate_commit": CANDIDATE_COMMIT,
        "baseline_source_commit": BASE_COMMIT,
        "source_hashes": {str(path.relative_to(ROOT)): sha(path) for path in source_paths()},
        "candidate_suffix_sha256": hashlib.sha256(suffix().encode()).hexdigest(),
        "environment": ENV, "endpoint": ENDPOINT, "contract": native.contract_metadata(CONTRACT),
        "dependencies": {"python": sys.version.split()[0], "boto3": boto3.__version__,
                         "botocore": botocore.__version__},
        "calls": calls,
        "limits": {"maximum_calls": 4, "calls_per_scope_arm": 1, "requested_slots_per_call": 5,
                   "requested_slots_total": 20, "read_seconds": 200, "connect_seconds": 3,
                   "sdk_total_attempts": 1, "retries": 0, "warmups": 0},
        "criteria": {
            "candidate_normal_native_endturn_calls": 2, "exact_five_rows_per_call": True,
            "candidate_usable_of_10": 10, "candidate_usable_per_scope": 5,
            "candidate_python_and_or_items": 3, "candidate_python_final_operand_items": 1,
            "candidate_python_skipped_operand_items": 1,
            "candidate_english_agreement_items": 3, "candidate_english_collective_items": 1,
            "candidate_english_reference_items": 2,
            "candidate_targeted_false_rule_or_ambiguous_distractor_count": 0,
            "observed_improvement_requires_baseline_targeted_defect": True,
            "candidate_usable_not_below_baseline_total_or_either_scope": True,
            "no_other_material_content_regression": True,
            "blind_literal_choice_and_pair_lock_before_key_or_main": True,
            "uncertainty_fails_item": True, "model_agreement_is_not_semantic_credit": True,
            "author_main_maximum": 320, "runtime_main_maximum": 420,
        },
        "failure_policy": "Each ordinary timeout, safety, malformed, late or provider failure consumes its sole call and zeroes five slots; continue other independent calls. Stop globally for source/request/capture integrity, credential or SDK setup, or call-budget violations. No retry, rescue, top-up, warmup or resume.",
        "claim_limits": "Author-only fresh diagnostic, not a same-item paired causal trial, worker qualification, verification approval, deployment approval or broad accuracy estimate. All 20 requested slots remain denominators. Independent blind review, not author or model agreement, owns semantic judgments.",
    }


def check_plan(plan, *, path=None, expected_sha=None):
    require(plan.get("state") in {"draft", "frozen"}
            and plan == {**build_plan(), "state": plan["state"]}, "Plan or source drift.")
    if path is not None:
        require(sha(path) == expected_sha, "Frozen plan bytes changed.")


def setup_failure(error):
    seen = set()
    while error is not None and id(error) not in seen:
        seen.add(id(error))
        if isinstance(error, (IntegrityError, safe.CaptureBoundaryError, ServiceConfigurationError)):
            return True
        if type(error).__name__ in {"NoCredentialsError", "PartialCredentialsError", "CredentialRetrievalError",
                                    "UnauthorizedSSOTokenError", "TokenRetrievalError", "NoRegionError",
                                    "ParamValidationError"}:
            return True
        response = getattr(error, "response", {})
        if isinstance(response, dict) and response.get("Error", {}).get("Code") in {
                "ExpiredTokenException", "UnrecognizedClientException", "InvalidSignatureException",
                "InvalidClientTokenId", "AccessDeniedException"}:
            return True
        error = error.__cause__
    return False


def visible_rows(retained):
    try:
        text = "\n".join(block["text"] for block in retained["output"]["message"]["content"])
        payload = safe.strict_json(text)
        return payload["questions"] if type(payload) is dict and type(payload.get("questions")) is list else None
    except (KeyError, TypeError, ValueError):
        return None


def decoded_credential_echo(response, secrets):
    text = "\n".join(block["text"] for block in response.get("output", {}).get("message", {}).get("content", [])
                     if type(block) is dict and type(block.get("text")) is str)
    if len(text.encode()) > safe.VISIBLE_RESPONSE_MAX_BYTES:
        raise safe.CaptureBoundaryError("Visible response exceeds capture allowance.")
    if any(secret and secret in text for secret in secrets):
        return True
    try:
        decoded = json.loads(text, object_pairs_hook=list)
    except (ValueError, RecursionError) as error:
        raise ProviderError("Malformed native JSON omitted from capture.") from error
    pending = [decoded]
    while pending:
        value = pending.pop()
        if type(value) is str and any(secret and secret in value for secret in secrets):
            return True
        if isinstance(value, (list, tuple)):
            pending.extend(value)
    return False


def valid_visible_envelope(response):
    if type(response) is not dict or type(response.get("output")) is not dict:
        return False
    message = response["output"].get("message")
    if type(message) is not dict or type(message.get("content")) is not list:
        return False
    return all(type(block) is dict for block in message["content"])


def summarize(capture):
    result = {"planned_calls": 4, "requested_slots": 20, "attempted_calls": 0,
              "independent_content_review": "pending", "semantic_credit": None}
    for arm in ("baseline", "candidate"):
        rows = [call for call in capture["calls"] if call["arm"] == arm]
        result[arm] = {"requested_slots": 10, "attempted_calls": sum(bool(x["dispatch_attempted"]) for x in rows),
                       "normal_exact_five_calls": sum(x["status"] == "assessed" for x in rows),
                       "observed_raw_rows": sum(len(x.get("raw_rows") or []) for x in rows),
                       "missing_or_failed_slots": sum(5 for x in rows if x["status"] != "assessed")}
        result["attempted_calls"] += result[arm]["attempted_calls"]
    return result


def blind_projection(capture):
    require(len(capture["calls"]) == 4, "Four calls required for fixed blind denominator.")
    worksheet, mapping = [], []
    for call in capture["calls"]:
        rows = call.get("raw_rows") or []
        for ordinal in range(5):
            identity = hashlib.sha256(f"{capture['plan_sha256']}:{call['index']}:{ordinal}".encode()).hexdigest()[:16]
            raw = rows[ordinal] if ordinal < len(rows) and type(rows[ordinal]) is dict else None
            choices = raw.get("choices") if raw else None
            valid = (type(raw) is dict and type(raw.get("prompt")) is str and type(choices) is dict
                     and set(choices) == set("abcd") and all(type(choices[k]) is str for k in "abcd"))
            rotation = int(identity[:8], 16) % 4
            offered = [choices[k] for k in "abcd"] if valid else []
            offered = offered[rotation:] + offered[:rotation]
            worksheet.append({"id": identity, "prompt": raw["prompt"] if valid else None,
                              "choices": offered, "shape": "readable" if valid else "missing_or_invalid",
                              "blind_review": {"literal_task": None, "premises": None,
                                               "four_choice_judgments": None,
                                               "six_pair_judgments": None, "uncertainty": None}})
            mapping.append({"id": identity, "call_index": call["index"], "raw_ordinal": ordinal,
                            "arm": call["arm"], "scope": call["scope"], "rotation": rotation})
    worksheet.sort(key=lambda x: x["id"])
    mapping.sort(key=lambda x: x["id"])
    return ({"capture_sha256": digest(capture), "requested_slots": 20, "items": worksheet,
             "instruction": "Lock literal-task answers, all four choice judgments and six pair meanings before opening author keys, explanations or arm mapping. Uncertainty and missing rows fail."},
            {"capture_sha256": digest(capture), "items": mapping})


class CaptureWriter:
    def __init__(self, path, capture):
        self.path = path
        save(path, capture, exclusive=True)
        self.expected = sha(path)

    def save(self, capture):
        require(self.path.exists() and sha(self.path) == self.expected, "Capture changed externally.")
        save(self.path, capture)
        self.expected = sha(self.path)


def initial_capture(plan, *, status="running"):
    capture = {"plan_sha256": digest(plan), "status": status,
               "started_at": datetime.now(timezone.utc).isoformat(),
               "calls": [{"index": job["index"], "arm": job["arm"], "scope": job["scope"],
                          "status": "unattempted", "dispatch_attempted": False} for job in plan["calls"]]}
    capture["summary"] = summarize(capture)
    return capture


def run_calls(plan, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic,
              existing_capture=None):
    require(len(plan["calls"]) == 4 and plan["limits"]["maximum_calls"] == 4,
            "Four-call ceiling changed.")
    if existing_capture is None:
        capture = initial_capture(plan)
        writer = CaptureWriter(path, capture)
    else:
        capture, writer = existing_capture
        require(writer.path == path and capture["plan_sha256"] == digest(plan)
                and capture["status"] == "setup" and not any(x["dispatch_attempted"] for x in capture["calls"]),
                "Existing durable capture is not an untouched setup reservation.")
        capture["status"] = "running"
        writer.save(capture)

    def guard(condition, message):
        if not condition:
            capture["global_stop"] = "request_transport_or_budget_integrity"
            raise IntegrityError(message)

    def pins():
        try:
            require(path.exists() and sha(path) == writer.expected, "Capture changed externally.")
            pin_check()
        except Exception:
            capture.setdefault("global_stop", "source_or_capture_integrity")
            raise

    for job, row in zip(plan["calls"], capture["calls"], strict=True):
        if capture.get("global_stop"):
            break
        budget = runtime.ProviderCallBudget(1)

        class Recorder:
            def __init__(self, client):
                self.client, self.meta = client, client.meta

            def converse(self, **request):
                pins()
                cfg = self.meta.config
                guard(request == job["request"] and digest(request) == job["request_sha256"],
                      "Actual author request drift.")
                guard(self.meta.endpoint_url == ENDPOINT and self.meta.region_name == "us-east-1"
                      and cfg.read_timeout == 200 and cfg.connect_timeout == 3
                      and cfg.retries.get("total_max_attempts") == 1, "SDK transport drift.")
                guard(not row["dispatch_attempted"] and budget.calls == 1
                      and sum(x["dispatch_attempted"] for x in capture["calls"]) < 4,
                      "Reservation or call ceiling violated.")
                row.update(status="dispatching", dispatch_attempted=True,
                           request=copy.deepcopy(request), request_sha256=digest(request))
                writer.save(capture)
                started = clock()
                try:
                    response = self.client.converse(**request)
                    if not valid_visible_envelope(response):
                        raise ProviderError("Malformed provider envelope omitted from capture.")
                    require(not decoded_credential_echo(response, secrets), "Credential echo in visible response.")
                    retained, omitted = safe.safe_response(response, secrets)
                    row.update(response=retained, reasoning_blocks_omitted=omitted)
                    return response
                except Exception as error:
                    row["provider_error"] = safe.safe_error(error, secrets)
                    if setup_failure(error):
                        capture["global_stop"] = "provider_setup_or_capture_integrity"
                    raise
                finally:
                    row["elapsed_seconds"] = round(clock() - started, 6)
                    pins()
                    writer.save(capture)

        def factory(*args, **kwargs):
            try:
                require(args == ("bedrock-runtime",) and set(kwargs) == {"region_name", "config"},
                        "SDK client factory drift.")
                return Recorder(client_factory(*args, **kwargs))
            except Exception:
                capture["global_stop"] = "sdk_factory_setup"
                raise

        try:
            pins()
            with patch.dict(os.environ, ENV, clear=True), patch.object(boto3, "client", factory):
                adapted = generate(job, budget=budget)
            require(row["dispatch_attempted"] and budget.calls == 1, "Author call was skipped.")
            row["raw_rows"] = visible_rows(row["response"])
            row["native_valid"] = True
            row["exact_five"] = len(adapted["questions"]) == 5
            pins()
            row["status"] = ("assessed" if row["response"]["stopReason"] == "end_turn"
                             and row["elapsed_seconds"] <= 200 and row["exact_five"] else "failed")
        except Exception as error:
            row.update(status="failed", local_error=safe.safe_error(error, secrets))
            row["raw_rows"] = visible_rows(row["response"]) if "response" in row else None
            if isinstance(error, ProviderCallBudgetExceededError) and not isinstance(
                error, ProviderDeadlineExceededError
            ):
                capture.setdefault("global_stop", "attempted_budget_overrun")
            elif setup_failure(error) or not isinstance(error, (ProviderError, SafetyInterventionError)):
                capture.setdefault("global_stop", "source_request_setup_or_capture_integrity")
        finally:
            row["runtime_budget_calls"] = budget.calls
            capture["summary"] = summarize(capture)
            writer.save(capture)
    capture["completed_at"] = datetime.now(timezone.utc).isoformat()
    capture["summary"] = summarize(capture)
    try:
        pins()
    except Exception as error:
        capture["completion_error"] = safe.safe_error(error, secrets)
    capture["status"] = "globally_stopped" if capture.get("global_stop") else "complete_pending_blind_review"
    writer.save(capture)
    return capture


def preflight():
    result = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", str(HERE),
                             "-p", "test_author_probe.py", "-q"], capture_output=True, text=True)
    require(result.returncode == 0, "Socket-blocked fake tests failed: " + result.stderr)
    return {"provider_calls": 0, "result": "passed", "output": result.stderr.strip()}


def freeze(reviewed_sha):
    require(DRAFT.exists() and sha(DRAFT) == reviewed_sha and not PLAN.exists(),
            "Reviewed exact draft required; no overwrite.")
    draft = safe.strict_json(DRAFT.read_text())
    check_plan(draft)
    preflight()
    check_plan(draft)
    save(PLAN, {**draft, "state": "frozen"}, exclusive=True)
    return {"plan_sha256": sha(PLAN), "provider_calls": 0}


def execute(reviewed_plan_sha):
    require(PLAN.exists() and sha(PLAN) == reviewed_plan_sha and not CAPTURE.exists(),
            "Exact frozen plan required; no resume or overwrite.")
    plan = safe.strict_json(PLAN.read_text())
    require(plan["state"] == "frozen", "Draft cannot authorize dispatch.")
    check_plan(plan, path=PLAN, expected_sha=reviewed_plan_sha)
    capture = initial_capture(plan, status="setup")
    capture["reviewed_frozen_plan_sha256"] = reviewed_plan_sha
    writer = CaptureWriter(CAPTURE, capture)
    try:
        session, secrets = safe.credential_session()
    except BaseException as error:
        capture.update(status="globally_stopped", global_stop="credential_setup",
                       error={"type": type(error).__name__, "code": "credential_setup_failed"},
                       completed_at=datetime.now(timezone.utc).isoformat())
        writer.save(capture)
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            raise
        return capture
    return run_calls(plan, CAPTURE, session.client,
                     lambda: check_plan(plan, path=PLAN, expected_sha=reviewed_plan_sha),
                     secrets=secrets, existing_capture=(capture, writer))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare", action="store_true")
    mode.add_argument("--preflight", action="store_true")
    mode.add_argument("--freeze", metavar="REVIEWED_DRAFT_SHA256")
    mode.add_argument("--execute", metavar="REVIEWED_PLAN_SHA256")
    args = parser.parse_args()
    if args.prepare:
        draft = build_plan()
        save(DRAFT, draft)
        result = {"draft_path": str(DRAFT), "draft_sha256": sha(DRAFT), "digest": digest(draft),
                  "provider_calls": 0}
    elif args.preflight:
        result = preflight()
    elif args.freeze:
        result = freeze(args.freeze)
    else:
        result = execute(args.execute)
    print(json.dumps(result, ensure_ascii=True, indent=2))
