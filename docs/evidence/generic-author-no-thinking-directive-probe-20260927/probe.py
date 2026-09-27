"""One-shot disabled-thinking directive comparison; offline modes are socket-free."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from unittest.mock import patch

from botocore.config import Config
from botocore.session import get_session
from botocore.validate import validate_parameters


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASELINE_DIR = ROOT / "docs/evidence/generic-author-no-thinking-probe-20260927"
BASELINE_PLAN = BASELINE_DIR / "plan.json"
BASELINE_HARNESS = BASELINE_DIR / "probe.py"
BASELINE_PLAN_SHA = "e6b73e56fee680d8ea3725f7150b3a12596d014bb3ba102f3e423b7fb94444c9"
BASELINE_HARNESS_SHA = "514ada7e2be3dcf423228ebf26a96f7dc1d0bbe9e519eb77c7326822b3c6d918"
SOURCE_COMMIT = "d1483312b71f6b1335d1630547c85260aab8ef64"
PROBE_ID = "generic-probability-author-no-thinking-directive-20260927-01"
PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"
REVIEW_LOCK = HERE / "review-approval.json"
PRECHECK = HERE / "launch-precheck.json"
PRECHECK_ATTEMPT = HERE / "launch-precheck-attempt.json"
EXECUTE_SECONDS = 240
EXPECTED_ACCOUNT = "239342516379"
ENDPOINT = "https://bedrock-runtime.us-east-1.amazonaws.com"
IMPORTED_HASH = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
_capture_hash = None

if hashlib.sha256(BASELINE_HARNESS.read_bytes()).hexdigest() != BASELINE_HARNESS_SHA:
    raise RuntimeError("Reviewed baseline harness bytes changed.")
_spec = importlib.util.spec_from_file_location("author_probe_baseline", BASELINE_HARNESS)
baseline = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(baseline)
safe = baseline.safe
runtime = baseline.runtime
native = baseline.native
transport = baseline.baseline


class IntegrityError(RuntimeError):
    pass


class DeadlineExpired(BaseException):
    pass


def require(condition, message):
    if not condition:
        raise IntegrityError(message)


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True,
                                     allow_nan=False, separators=(",", ":")).encode()).hexdigest()


def strict_file(path, maximum=8 * 1024 * 1024):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= maximum,
            f"Missing or oversized artifact: {path.name}.")
    return safe.strict_json(path.read_text(encoding="utf-8"))


def save(path, value, *, exclusive=False, capture=False):
    global _capture_hash
    if capture and _capture_hash is not None:
        require(path.is_file() and file_hash(path) == _capture_hash,
                "Capture changed outside this process.")
    payload = json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2) + "\n"
    target = path if exclusive else path.with_suffix(".partial")
    with target.open("x") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    if not exclusive:
        os.replace(target, path)
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    if capture:
        _capture_hash = file_hash(path)


def directive_from_analysis():
    analysis = ROOT / "docs/evidence/generic-reserve-author7-blind-20260927/DIFFICULTY_ANALYSIS.md"
    block = analysis.read_text().split("Suggested replacement text:\n\n", 1)[1].split("\n\n", 1)[0]
    lines = block.splitlines()
    require(all(line.startswith("> ") for line in lines), "Directive quote changed.")
    directive = " ".join(line[2:] for line in lines)
    require(len(directive) == 681, "Recommended directive length changed.")
    return directive


def baseline_artifacts():
    require(file_hash(BASELINE_PLAN) == BASELINE_PLAN_SHA,
            "No-thinking baseline plan changed.")
    plan = strict_file(BASELINE_PLAN)
    require(plan["source_commit"] == SOURCE_COMMIT
            and plan["harness_sha256"] == BASELINE_HARNESS_SHA
            and plan["environment"]["BEDROCK_CLAUDE_THINKING"] == "disabled",
            "No-thinking baseline source, harness, or mode changed.")
    transport.check_source_commit([ROOT / path for path in plan["source_hashes"]])
    for relative, expected in plan["source_hashes"].items():
        require(file_hash(ROOT / relative) == expected,
                f"Pinned service file changed: {relative}.")
    transport.check_loaded_modules(plan["source_hashes"])
    return plan


def build_plan():
    require(file_hash(__file__) == IMPORTED_HASH, "Harness changed after import.")
    old = baseline_artifacts()
    request = strict_file(HERE / "request.json")
    protocol = strict_file(HERE / "protocol.json")
    old_directive = old["request"]["goal"]["questionDirective"]
    new_directive = directive_from_analysis()
    comparison = copy.deepcopy(request)
    comparison["goal"]["questionDirective"] = old_directive
    require(comparison == old["request"]
            and request["goal"]["questionDirective"] == new_directive
            and transport._normalize_request(request) == request,
            "Synthetic request differs beyond the exact recommended directive.")
    require(protocol["state"] == "draft" and protocol["probe_id"] == PROBE_ID
            and protocol["baseline_plan_sha256"] == BASELINE_PLAN_SHA
            and protocol["source_commit"] == SOURCE_COMMIT,
            "Author-only protocol identity changed.")
    expected_env = old["environment"]
    require(protocol["environment"] == expected_env,
            "Disabled-thinking environment changed from the baseline.")
    require(protocol["limits"] == old["limits"] == {
        "original_jobs": 1, "converse_reservations": 1,
        "sdk_attempts_per_reservation": 1, "whole_execute_seconds": 240,
        "connect_timeout_seconds": 3, "read_timeout_seconds": 200,
        "preflight_sts_requests": 1, "execute_sts_requests": 1,
        "retries": 0, "worker_verification": False,
    }, "Author-only call bounds changed.")
    require(protocol["question_quality_gate"] == old["quality_scope"],
            "Author-only quality scope changed.")
    wire = transport.author_wire(request, expected_env)
    prior = old["author_wire"]
    prior_text = prior["messages"][0]["content"][0]["text"]
    require(prior_text.count(old_directive) == 2
            and wire["messages"][0]["content"][0]["text"].count(new_directive) == 2,
            "Author guidance does not appear twice in the expected prompt positions.")
    expected_wire = copy.deepcopy(prior)
    expected_wire["messages"][0]["content"][0]["text"] = prior_text.replace(
        old_directive, new_directive,
    )
    require(wire == expected_wire,
            "Provider-visible wire changed beyond the question directive.")
    require(wire["inferenceConfig"] == {"maxTokens": 6000, "temperature": 0.2}
            and wire["additionalModelRequestFields"] == {"thinking": {"type": "disabled"}}
            and wire["modelId"] == "us.anthropic.claude-sonnet-4-6"
            and wire["outputConfig"] == prior["outputConfig"],
            "Disabled-thinking model, inference controls, or native schema changed.")
    operation = get_session().get_service_model("bedrock-runtime").operation_model("Converse")
    validate_parameters(wire, operation.input_shape)
    schema = wire["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"]
    return {
        "state": "draft_offline_ready", "probe_id": PROBE_ID,
        "source_commit": SOURCE_COMMIT, "source_hashes": old["source_hashes"],
        "baseline_plan_sha256": BASELINE_PLAN_SHA,
        "baseline_harness_sha256": BASELINE_HARNESS_SHA,
        "harness_sha256": IMPORTED_HASH,
        "worksheet_builder_sha256": file_hash(HERE / "make_worksheet.py"),
        "request_sha256": file_hash(HERE / "request.json"),
        "protocol_sha256": file_hash(HERE / "protocol.json"),
        "request": request, "environment": expected_env,
        "author_contract_name": old["author_contract_name"],
        "author_wire": wire, "author_wire_sha256": digest(wire),
        "native_author_schema_sha256": hashlib.sha256(schema.encode()).hexdigest(),
        "native_author_schema_bytes": len(schema.encode()),
        "limits": protocol["limits"],
        "quality_scope": protocol["question_quality_gate"],
        "model_and_transport": old["model_and_transport"],
    }


def check_plan(expected_hash):
    require(PLAN.is_file() and file_hash(PLAN) == expected_hash,
            "Frozen plan hash changed.")
    plan = strict_file(PLAN)
    require(plan.get("state") == "frozen"
            and {**plan, "state": "draft_offline_ready"} == build_plan(),
            "Frozen plan differs from source, request, or exact wire.")
    return plan


def check_live_pins(plan, expected_hash):
    require(PLAN.is_file() and file_hash(PLAN) == expected_hash
            and strict_file(PLAN) == plan,
            "Frozen plan changed during execution.")
    require(file_hash(__file__) == plan["harness_sha256"]
            and file_hash(HERE / "make_worksheet.py") == plan["worksheet_builder_sha256"]
            and file_hash(HERE / "request.json") == plan["request_sha256"]
            and file_hash(HERE / "protocol.json") == plan["protocol_sha256"],
            "Author-only artifact changed during execution.")
    baseline_artifacts()


def review_go(plan_hash):
    lock = strict_file(REVIEW_LOCK, 4096)
    require(set(lock) == {"plan_sha256", "harness_sha256", "source_commit",
                          "root_go", "independent_go"}
            and lock["plan_sha256"] == plan_hash
            and lock["harness_sha256"] == IMPORTED_HASH
            and lock["source_commit"] == SOURCE_COMMIT
            and lock["root_go"] is True and lock["independent_go"] is True,
            "This exact plan and harness lack root and independent approval.")


def deadline_alarm(_number, _frame):
    raise DeadlineExpired("Whole author-only execute deadline expired.")


def preflight():
    build_plan()
    result = subprocess.run((sys.executable, "-B", "-m", "unittest", "discover",
                             "-s", str(HERE), "-p", "test_probe.py", "-q"),
                            capture_output=True, text=True, timeout=45)
    require(result.returncode == 0,
            "Socket-free author-only tests failed: " + result.stderr)
    return {"provider_calls": 0, "result": "passed", "tests": result.stderr.strip()}


def freeze(reviewed_digest):
    require(not any(path.exists() for path in (PLAN, CAPTURE, PRECHECK, PRECHECK_ATTEMPT)),
            "This probe has already been frozen or attempted.")
    draft = build_plan()
    require(digest(draft) == reviewed_digest, "Draft digest changed.")
    save(PLAN, {**draft, "state": "frozen"}, exclusive=True)
    return {"plan_sha256": file_hash(PLAN), "provider_calls": 0}


def launch_precheck():
    plan_hash = file_hash(PLAN)
    check_plan(plan_hash)
    review_go(plan_hash)
    transport.check_execution_runtime()
    require(not any(path.exists() for path in (CAPTURE, PRECHECK, PRECHECK_ATTEMPT)),
            "Precheck or one-shot capture already exists.")
    transport.check_default_profile()
    transport.check_aws_cli()
    save(PRECHECK_ATTEMPT, {"state": "started", "plan_sha256": plan_hash,
                            "at": datetime.now(timezone.utc).isoformat(),
                            "sts_requests_reserved": 1, "provider_calls": 0}, exclusive=True)
    previous = signal.getsignal(signal.SIGALRM)
    try:
        signal.signal(signal.SIGALRM, deadline_alarm)
        signal.setitimer(signal.ITIMER_REAL, 45)
        with patch.dict(os.environ, transport.controlled_cli_environment(), clear=True):
            session = transport.boto3.Session(profile_name="default", region_name="us-east-1")
            identity = transport.checked_sts_client(session).get_caller_identity()
        require(identity.get("Account") == EXPECTED_ACCOUNT, "AWS account changed.")
        _, _, expires = transport.default_profile_session()
        now = datetime.now(timezone.utc)
        require((expires - now).total_seconds() >= 360,
                "AWS credentials expire before the probe can finish.")
        result = {"state": "passed", "plan_sha256": plan_hash,
                  "checked_at": now.isoformat(), "credential_expires_at": expires.isoformat(),
                  "account": EXPECTED_ACCOUNT, "sts_requests": 1, "provider_calls": 0}
        save(PRECHECK, result, exclusive=True)
        return result
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def check_precheck(plan_hash):
    attempt = strict_file(PRECHECK_ATTEMPT, 4096)
    record = strict_file(PRECHECK, 4096)
    require(attempt["state"] == "started" and attempt["plan_sha256"] == plan_hash
            and attempt["sts_requests_reserved"] == 1 and attempt["provider_calls"] == 0,
            "Launch precheck reservation changed.")
    require(record["state"] == "passed" and record["plan_sha256"] == plan_hash
            and record["account"] == EXPECTED_ACCOUNT and record["sts_requests"] == 1
            and record["provider_calls"] == 0,
            "AWS launch identity precheck changed.")
    now = datetime.now(timezone.utc)
    checked = datetime.fromisoformat(record["checked_at"])
    expires = datetime.fromisoformat(record["credential_expires_at"])
    require(checked.tzinfo is not None and expires.tzinfo is not None
            and 0 <= (now - checked).total_seconds() <= 120
            and (expires - now).total_seconds() >= 330,
            "AWS launch freshness window closed.")


def new_capture(plan_hash):
    return {"probe_id": PROBE_ID, "plan_sha256": plan_hash,
            "started_at": datetime.now(timezone.utc).isoformat(),
            "status": "setup", "identity_check": "pending",
            "reservation": "unattempted", "call": None,
            "author_outcome": "unavailable", "author_rows": None,
            "worker_qualified": False}


def run_one_call(plan, plan_hash, capture, path, client, *, secrets=(),
                 clock=time.monotonic):
    """Dispatch the exact reviewed author wire once, after a durable reservation."""
    check_live_pins(plan, plan_hash)
    require(capture["reservation"] == "unattempted" and capture["call"] is None,
            "A provider reservation already exists.")
    config = client.meta.config
    require(client.meta.endpoint_url == ENDPOINT and client.meta.region_name == "us-east-1"
            and config.connect_timeout == 3 and config.read_timeout == 200
            and config.retries.get("total_max_attempts") == 1,
            "Bedrock endpoint, timeout, or retry configuration changed.")
    wire = plan["author_wire"]
    require(digest(wire) == plan["author_wire_sha256"]
            and wire["inferenceConfig"] == {"maxTokens": 6000, "temperature": 0.2}
            and wire["additionalModelRequestFields"] == {"thinking": {"type": "disabled"}},
            "Actual Converse wire changed.")
    operation = get_session().get_service_model("bedrock-runtime").operation_model("Converse")
    validate_parameters(wire, operation.input_shape)
    capture["reservation"] = "durable"
    capture["call"] = {"ordinal": 0, "stage": "author7", "request": copy.deepcopy(wire),
                       "dispatch_attempted": False, "sdk_attempts": 1}
    save(path, capture, capture=True)
    started = clock()
    try:
        check_live_pins(plan, plan_hash)
        capture["call"]["dispatch_attempted"] = True
        capture["status"] = "dispatch_attempted"
        save(path, capture, capture=True)
        response = client.converse(**wire)
        retained, omitted = safe.safe_response(response, secrets)
        retained.pop("safeResponseMetadata", None)
        serialized = json.dumps(retained, ensure_ascii=False)
        require(not any(secret and secret in serialized for secret in secrets)
                and not transport.decoded_credential_echo(response, secrets),
                "Model response echoed a credential.")
        capture["call"]["response"] = retained
        capture["call"]["reasoning_blocks_omitted"] = omitted
        capture["status"] = "completed"
        capture["author_outcome"] = "incomplete"
        if retained.get("stopReason") in ("end_turn", "stop_sequence"):
            visible = "\n".join(block["text"] for block in retained["output"]["message"]["content"])
            try:
                adapted = safe.strict_json(native.adapt_native_response(
                    visible, native.AuthorSlotContract(7, "prose")))
                rows = adapted["questions"]
                require(type(rows) is list and len(rows) == 7,
                        "Native adapter did not return all seven authored rows.")
                capture["author_rows"] = rows
                capture["author_outcome"] = "seven_native_rows"
            except (ValueError, KeyError, TypeError, transport.ProviderError):
                capture["author_outcome"] = "invalid_native_rows"
    except Exception as error:
        capture["status"] = "failed_after_dispatch" if capture["call"]["dispatch_attempted"] else "failed_before_dispatch"
        capture["call"]["error"] = transport.safe_error_identity(error, secrets)
        capture["author_outcome"] = "unavailable"
    finally:
        capture["call"]["elapsed_seconds"] = round(clock() - started, 6)
        save(path, capture, capture=True)


def execute(plan_hash):
    plan = check_plan(plan_hash)
    review_go(plan_hash)
    transport.check_execution_runtime()
    check_precheck(plan_hash)
    require(not CAPTURE.exists(), "This one-shot probe has already been attempted.")
    started = time.monotonic()
    capture = new_capture(plan_hash)
    save(CAPTURE, capture, exclusive=True, capture=True)
    secrets = ()
    previous = signal.getsignal(signal.SIGALRM)
    try:
        signal.signal(signal.SIGALRM, deadline_alarm)
        remaining = EXECUTE_SECONDS - (time.monotonic() - started)
        require(remaining > 0, "Execute deadline expired before credential export.")
        signal.setitimer(signal.ITIMER_REAL, remaining)
        session, secrets, expires = transport.default_profile_session()
        require((expires - datetime.now(timezone.utc)).total_seconds() >= 300,
                "Exported credentials expire during the probe.")
        check_live_pins(plan, plan_hash)
        capture["identity_check"] = "reserved"
        save(CAPTURE, capture, capture=True)
        identity = transport.checked_sts_client(session).get_caller_identity()
        require(identity.get("Account") == EXPECTED_ACCOUNT,
                "AWS account differs from reviewed account.")
        capture["identity_check"] = "verified"
        save(CAPTURE, capture, capture=True)
        client = session.client("bedrock-runtime", region_name="us-east-1", endpoint_url=ENDPOINT,
                                config=Config(connect_timeout=3, read_timeout=200,
                                              retries={"total_max_attempts": 1,
                                                       "mode": "standard"}))
        run_one_call(plan, plan_hash, capture, CAPTURE, client, secrets=secrets)
    except DeadlineExpired:
        capture["status"] = "deadline_exceeded"
        capture["author_outcome"] = "unavailable"
    except BaseException as error:
        capture["status"] = "globally_aborted"
        capture["error"] = transport.safe_error_identity(error, secrets)
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            raise
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
        capture["whole_execute_seconds"] = round(time.monotonic() - started, 6)
        if capture["whole_execute_seconds"] > EXECUTE_SECONDS:
            capture["status"] = "deadline_exceeded"
            capture["author_outcome"] = "unavailable"
        save(CAPTURE, capture, capture=True)
    return {"capture": str(CAPTURE), "status": capture["status"],
            "author_outcome": capture["author_outcome"],
            "worker_qualified": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--draft", action="store_true")
    group.add_argument("--preflight", action="store_true")
    group.add_argument("--freeze", metavar="DRAFT_SHA256")
    group.add_argument("--launch-precheck", action="store_true")
    group.add_argument("--execute", metavar="PLAN_SHA256")
    args = parser.parse_args()
    if args.draft:
        draft = build_plan()
        result = {"draft_sha256": digest(draft),
                  "author_wire_sha256": draft["author_wire_sha256"],
                  "native_author_schema_sha256": draft["native_author_schema_sha256"],
                  "native_author_schema_bytes": draft["native_author_schema_bytes"],
                  "provider_calls": 0}
    elif args.preflight:
        result = preflight()
    elif args.freeze:
        result = freeze(args.freeze)
    elif args.launch_precheck:
        result = launch_precheck()
    else:
        result = execute(args.execute)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
