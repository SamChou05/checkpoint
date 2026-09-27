"""One-shot seven-row author-only content probe; importing is socket-free.

Only --launch-precheck and --execute can contact AWS. Both require a frozen
exact-byte plan and independent review lock. Preparation and tests use fakes.
"""

import argparse
import configparser
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import signal
import subprocess
import sys
import time
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = (ROOT / "backend/bedrock-question-service").resolve()
SOURCE_COMMIT = "d1483312b71f6b1335d1630547c85260aab8ef64"
TRIAL_ID = "generic-probability-directive-author-only-20260927-01"
PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"
REVIEW_LOCK = HERE / "review-approval.json"
LAUNCH_ATTEMPT = HERE / "launch-precheck-attempt.json"
LAUNCH_PRECHECK = HERE / "launch-precheck.json"
HELPER = SERVICE / "evals/bounded_bedrock_capture.py"
WORKSHEET_BUILDER = HERE / "make_worksheet.py"
sys.path.insert(0, str(SERVICE))

import awscrt  # noqa: E402
import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402
from botocore.session import get_session  # noqa: E402
from botocore.validate import validate_parameters  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_generation as runtime  # noqa: E402
import question_quality as quality  # noqa: E402
from question_bank_common import DurableProviderCallReservation  # noqa: E402
from request_contract import _normalize_request  # noqa: E402
from service_errors import ProviderError  # noqa: E402

_spec = importlib.util.spec_from_file_location("generic_reserve_bounded_capture", HELPER)
safe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(safe)

ENDPOINT = "https://bedrock-runtime.us-east-1.amazonaws.com"
STS_ENDPOINT = "https://sts.us-east-1.amazonaws.com"
EXPECTED_ACCOUNT_ID = "239342516379"
EXPECTED_PROFILE = "default"
EXPECTED_AWS_CLI_VERSION = "2.33.15"
REQUIRED_BOTO3_VERSION = "1.43.91"
REQUIRED_BOTOCORE_VERSION = "1.43.91"
REQUIRED_AWSCRT_VERSION = "0.36.0"
AWS_CLI_PATH = Path(shutil.which("aws") or "/__missing_aws_cli__/aws").resolve()
FROZEN_HOME = Path("/Users/samchou")
FROZEN_CONFIG_PATH = FROZEN_HOME / ".aws/config"
FROZEN_CREDENTIALS_PATH = FROZEN_HOME / ".aws/credentials"
FROZEN_CONFIG_SHA256 = "7f70246298d2f2897d39ee3a99a7353bfa9b83255ef95ba0db5f3a5623ea5f3d"
FROZEN_LOGIN_SESSION_SHA256 = "8731d91a75118f0c6e502e84b95a999bbf68e2c825830881788660d6ee32e1f2"
PROFILE_KEYS = frozenset({"login_session", "region"})
CLI_CREDENTIAL_ENV_NAMES = frozenset({
    "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_SECURITY_TOKEN",
    "AWS_ROLE_ARN", "AWS_ROLE_SESSION_NAME", "AWS_WEB_IDENTITY_TOKEN_FILE",
    "AWS_CONTAINER_CREDENTIALS_FULL_URI", "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI",
    "AWS_CONTAINER_AUTHORIZATION_TOKEN", "AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE",
})
SHARED_CREDENTIAL_DEFAULT_KEYS = frozenset({
    "aws_access_key_id", "aws_secret_access_key", "aws_session_token", "credential_process",
    "role_arn", "source_profile", "web_identity_token_file",
})
EXECUTE_SECONDS = 240
MAX_CALLS = 1
CAPTURE_HASHES = {}
IMPORTED_HARNESS_HASH = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
IMPORTED_HELPER_HASH = hashlib.sha256(HELPER.read_bytes()).hexdigest()
IMPORTED_WORKSHEET_BUILDER_HASH = hashlib.sha256(WORKSHEET_BUILDER.read_bytes()).hexdigest()


class IntegrityError(RuntimeError):
    pass


class WholeDeadlineExceeded(BaseException):
    pass


def deadline_alarm(_signal, _frame):
    raise WholeDeadlineExceeded("Whole 240-second deadline expired.")


def require(condition, message):
    if not condition:
        raise IntegrityError(message)


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True,
                                     allow_nan=False, separators=(",", ":")).encode()).hexdigest()


def check_capture(path):
    previous = CAPTURE_HASHES.get(path.resolve())
    require(previous is None or (path.is_file() and file_hash(path) == previous),
            "Capture was externally modified or removed.")


def save(path, value, *, exclusive=False):
    is_capture = type(value) is dict and "original_rows" in value and "calls" in value
    if is_capture:
        check_capture(path)
        value = copy.deepcopy(value)
        for observation in value.get("metrics", {}).get("ProviderObservations", []):
            observation.pop("stopReason", None)
            if "usage" in observation:
                observation["usage"] = safe.bounded_numbers(
                    observation["usage"], safe.USAGE_FIELDS)
    serialized = json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(serialized)
            stream.flush()
            os.fsync(stream.fileno())
    else:
        temporary = path.with_suffix(".partial")
        with temporary.open("x") as stream:
            stream.write(serialized)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    if is_capture:
        CAPTURE_HASHES[path.resolve()] = file_hash(path)


def safe_error_identity(error, secrets=()):
    response = getattr(error, "response", {})
    problem = response.get("Error", {}) if type(response) is dict else {}
    code = problem.get("Code") if type(problem) is dict else None
    return {"type": type(error).__name__, "code": safe.redact(code, secrets, maximum=128)}


def source_paths():
    """Pin the imported production closure; reject any later unpinned import."""
    imported = set()
    for module in tuple(sys.modules.values()):
        name = getattr(module, "__file__", None)
        if name is not None:
            path = Path(name).resolve()
            if path.parent == SERVICE:
                imported.add(path)
    imported.add(Path(runtime.__file__).resolve())
    return [*sorted(imported), SERVICE / "requirements.txt", HELPER]


def check_source_commit(paths):
    require(subprocess.run(("git", "merge-base", "--is-ancestor", SOURCE_COMMIT, "HEAD"),
                           cwd=ROOT, capture_output=True).returncode == 0,
            "Pinned source commit is not an ancestor.")
    for path in paths:
        relative = str(path.relative_to(ROOT))
        commit_bytes = subprocess.run(("git", "show", f"{SOURCE_COMMIT}:{relative}"),
                                      cwd=ROOT, capture_output=True, check=True).stdout
        require(path.read_bytes() == commit_bytes, f"Source differs from pinned commit: {relative}.")


def check_loaded_modules(pins):
    for module in tuple(sys.modules.values()):
        name = getattr(module, "__file__", None)
        if name is None:
            continue
        path = Path(name).resolve()
        if path.parent == SERVICE:
            relative = str(path.relative_to(ROOT))
            require(relative in pins and file_hash(path) == pins[relative],
                    f"Unpinned service module loaded: {relative}.")


def check_current_source(plan=None):
    paths = source_paths()
    check_source_commit(paths)
    pins = {str(path.relative_to(ROOT)): file_hash(path) for path in paths}
    if plan is not None:
        require(pins == plan["source_hashes"], "Service source hashes changed.")
        require(file_hash(HERE / "author_probe.py") == plan["harness_sha256"],
                "Harness bytes changed after review.")
        require(file_hash(HELPER) == plan["capture_helper_sha256"] == IMPORTED_HELPER_HASH,
                "Capture helper changed after import.")
        require(file_hash(WORKSHEET_BUILDER) == plan["worksheet_builder_sha256"]
                == IMPORTED_WORKSHEET_BUILDER_HASH,
                "Blind worksheet builder changed after review.")
    check_loaded_modules(pins)
    return pins


def contract_configs():
    contracts = [native.AuthorSlotContract(7, "prose")]
    return {native.contract_metadata(contract)["name"]: native.native_output_config(contract)
            for contract in contracts}


def author_wire(request, env):
    """Capture the production's first native request with a fake, without sockets."""
    calls = []

    def converse(**wire):
        calls.append(copy.deepcopy(wire))
        return {"stopReason": "end_turn", "output": {"message": {"content": [
            {"text": '{"questions":{}}'},
        ]}}}

    author_request = copy.deepcopy(request)
    author_request["targetCount"] = 7
    with patch.dict(os.environ, env, clear=True):
        try:
            runtime._generate_provider_payload(
                author_request, SimpleNamespace(converse=converse),
                call_budget=runtime.ProviderCallBudget(1),
            )
        except ProviderError:
            pass
    require(len(calls) == 1, "Offline author wire did not make exactly one fake call.")
    return calls[0]


def directive_from_analysis():
    analysis = ROOT / "docs/evidence/generic-reserve-author7-blind-20260927/DIFFICULTY_ANALYSIS.md"
    block = analysis.read_text().split("Suggested replacement text:\n\n", 1)[1].split("\n\n", 1)[0]
    lines = block.splitlines()
    require(all(line.startswith("> ") for line in lines), "Directive quotation changed.")
    directive = " ".join(line[2:] for line in lines)
    require(len(directive) == 681, "Recommended directive length changed.")
    return directive


def check_draft(protocol, request):
    require(protocol["state"] == "draft_waiting_for_candidate"
            and protocol["trial_id"] == TRIAL_ID
            and protocol["source_commit"] == SOURCE_COMMIT
            and protocol["directive_character_count"] == 681,
            "Draft trial identity or directive length changed.")
    baseline_path = ROOT / "docs/evidence/generic-reserve-seven-probe-v2-20260927/request.json"
    require(file_hash(baseline_path) == protocol["baseline_request_sha256"],
            "Trial 02 baseline request bytes changed.")
    baseline = safe.strict_json(baseline_path.read_text())
    comparison = copy.deepcopy(request)
    comparison["goal"]["questionDirective"] = baseline["goal"]["questionDirective"]
    require(comparison == baseline and request["goal"]["questionDirective"] == directive_from_analysis(),
            "Request differs beyond the exact recommended questionDirective.")
    require(_normalize_request(request) == request and request["targetCount"] == 5
            and request["minimumDifficulty"] == 2,
            "Synthetic probability request is no longer normalized or bounded.")
    expected_env = {
        "BEDROCK_REGION": "us-east-1",
        "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
        "QUESTION_AUTHOR_MODE": "prose",
        "QUESTION_AUTHOR_CARDINALITY_CONTRACT": "count_bound",
        "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
        "QUESTION_GENERIC_PROSE_RESERVE_7": "enabled",
        "BEDROCK_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
        "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
        "BEDROCK_FALLBACK_MODEL_ID": "",
        "BEDROCK_CLAUDE_THINKING": "adaptive",
        "BEDROCK_CLAUDE_EFFORT": "high",
        "BEDROCK_MAX_TOKENS": "6000",
        "BEDROCK_THINKING_MAX_TOKENS": "16000",
        "BEDROCK_TEMPERATURE": "0.2",
        "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
        "BEDROCK_READ_TIMEOUT_SECONDS": "200",
        "GENERATION_ATTEMPTS": "3",
        "MAX_PROVIDER_CALLS_PER_REQUEST": "6",
    }
    require(protocol["environment"] == expected_env, "Author environment changed.")
    require(protocol["limits"] == {
        "original_jobs": 1, "native_author_rows": 7, "author_calls": 1,
        "maximum_converse_calls": 1, "sdk_attempts_per_call": 1,
        "whole_execute_seconds": 240,
        "deadline_origin": "before_credential_export_and_execute_sts",
        "connect_timeout_seconds": 3, "read_timeout_seconds": 200,
        "sts_precheck_requests": 1, "sts_execute_requests": 1,
        "sts_sdk_attempts_per_request": 1,
        "resume_retry_fallback_topup_bank_queue_deploy": False,
    }, "One-call transport or budget changed.")
    require(protocol["author_gate"] == {
        "raw_rows": 7, "sanitized_rows": 7,
        "source_ordinals_exact": list(range(7)),
        "no_worker_verification": True,
        "blind_review_pending_on_success": True,
    }, "Author-only result gate changed.")
    require(protocol["blind_review"] == {
        "independent_reviewers": 2, "answer_blind": True,
        "source_ordinal_blind": True,
        "worksheet_from_all_seven_sanitized_rows": True,
        "private_answer_map_outside_git_mode": "0600",
        "hide_model_keys_until_both_locked": True,
    }, "Blind author review protocol changed.")


def build_plan():
    protocol = safe.strict_json((HERE / "protocol.json").read_text())
    request = safe.strict_json((HERE / "request.json").read_text())
    check_draft(protocol, request)
    require(file_hash(HERE / "author_probe.py") == IMPORTED_HARNESS_HASH,
            "Harness changed after import.")
    require(file_hash(HELPER) == IMPORTED_HELPER_HASH,
            "Bounded capture helper changed after import.")
    require(file_hash(WORKSHEET_BUILDER) == IMPORTED_WORKSHEET_BUILDER_HASH,
            "Blind worksheet builder changed after import.")
    env = protocol["environment"]
    with patch.dict(os.environ, env, clear=True):
        require(runtime._generic_prose_reserve_enabled(
            request, "prose", "count_bound", "authored_solution"),
            "Frozen request no longer selects the opt-in generic reserve.")
    wire = author_wire(request, env)
    require(set(wire) == {"modelId", "system", "messages", "outputConfig",
                          "inferenceConfig", "additionalModelRequestFields"},
            "Offline wire contains an unreviewed request member.")
    serialized_wire = json.dumps(wire, ensure_ascii=False)
    sensitive_values = [os.environ[name] for name in CLI_CREDENTIAL_ENV_NAMES
                        if name in os.environ and os.environ[name]]
    require(not any(secret in serialized_wire for secret in sensitive_values),
            "Inherited credential value entered the author wire.")
    user_text = wire["messages"][0]["content"][0]["text"]
    directive = directive_from_analysis()
    require(user_text.count(directive) == 2,
            "The exact directive is not visible in both author prompt positions.")
    marker = "<generation_request_json>\n"
    require(user_text.count(marker) == 1 and user_text.count("\n</generation_request_json>") == 1,
            "Synthetic request envelope changed.")
    embedded = safe.strict_json(user_text.split(marker, 1)[1].split(
        "\n</generation_request_json>", 1)[0])
    expected_embedded = {key: value for key, value in request.items()
                         if key not in {"blockedStemFingerprints", "stemFingerprintVersion"}}
    expected_embedded["targetCount"] = 7
    require(embedded == expected_embedded,
            "Author wire includes non-synthetic or changed request context.")
    configs = contract_configs()
    pins = check_current_source()
    author_name = native.AuthorSlotContract(7, "prose").name
    require(wire["outputConfig"] == configs[author_name],
            "Native author schema differs from allowed contract.")
    schema = wire["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"]
    require(wire["modelId"] == env["BEDROCK_MODEL_ID"]
            and wire["inferenceConfig"] == {"maxTokens": 16000}
            and wire["additionalModelRequestFields"] == {
                "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
            "Author model or reasoning wire changed.")
    operation = get_session().get_service_model("bedrock-runtime").operation_model("Converse")
    validate_parameters(wire, operation.input_shape)
    return {
        "state": "draft_offline_ready", "trial_id": TRIAL_ID,
        "source_commit": SOURCE_COMMIT, "source_hashes": pins,
        "harness_sha256": IMPORTED_HARNESS_HASH,
        "capture_helper_sha256": IMPORTED_HELPER_HASH,
        "worksheet_builder_sha256": IMPORTED_WORKSHEET_BUILDER_HASH,
        "request_sha256": file_hash(HERE / "request.json"),
        "protocol_sha256": file_hash(HERE / "protocol.json"),
        "request": request, "environment": copy.deepcopy(env),
        "author_contract_name": author_name,
        "author_wire": wire, "author_wire_sha256": digest(wire),
        "native_author_schema_bytes": len(schema.encode()),
        "native_author_schema_sha256": hashlib.sha256(schema.encode()).hexdigest(),
        "allowed_contracts": configs,
        "limits": copy.deepcopy(protocol["limits"]),
        "author_gate": copy.deepcopy(protocol["author_gate"]),
        "blind_review": copy.deepcopy(protocol["blind_review"]),
        "model_and_transport": {
            "region": "us-east-1", "bedrock_endpoint": ENDPOINT, "sts_endpoint": STS_ENDPOINT,
            "account": EXPECTED_ACCOUNT_ID, "profile": EXPECTED_PROFILE,
            "boto3_version": REQUIRED_BOTO3_VERSION,
            "botocore_version": REQUIRED_BOTOCORE_VERSION,
            "awscrt_version": REQUIRED_AWSCRT_VERSION,
            "aws_cli_version": EXPECTED_AWS_CLI_VERSION,
        },
    }

def check_plan(plan, path=None, expected_hash=None):
    require(plan.get("state") == "frozen"
            and {**plan, "state": "draft_offline_ready"} == build_plan(),
            "Frozen source, request, schema, or plan drifted.")
    if path is not None:
        require(file_hash(path) == expected_hash, "Frozen plan bytes changed.")


def check_live_pins(plan, expected_hash):
    """Recheck immutable bytes during dispatch without generating a fake wire."""
    require(PLAN.is_file() and PLAN.stat().st_size <= 8 * 1024 * 1024
            and file_hash(PLAN) == expected_hash
            and safe.strict_json(PLAN.read_text()) == plan,
            "Frozen plan bytes or in-memory plan changed during live stage.")
    require(file_hash(HERE / "request.json") == plan["request_sha256"]
            and file_hash(HERE / "protocol.json") == plan["protocol_sha256"],
            "Frozen request or protocol bytes changed during live stage.")
    check_current_source(plan)


def production_pin_callback(plan, expected_hash):
    """The exact callback shared by live execution and socket-free replay."""
    return lambda: check_live_pins(plan, expected_hash)


def check_execution_runtime():
    require(boto3.__version__ == REQUIRED_BOTO3_VERSION
            and botocore.__version__ == REQUIRED_BOTOCORE_VERSION
            and awscrt.__version__ == REQUIRED_AWSCRT_VERSION,
            "Live SDK versions differ from reviewed transport.")


def validate_identity_environment(environment=None):
    environment = os.environ if environment is None else environment
    for name in ("AWS_PROFILE", "AWS_DEFAULT_PROFILE"):
        require(environment.get(name, EXPECTED_PROFILE) in ("", EXPECTED_PROFILE),
                "AWS identity profile differs from frozen default.")
    require(not any(key.upper().startswith("AWS_ENDPOINT_URL") and value
                    for key, value in environment.items()),
            "An AWS endpoint override is present.")
    for name in ("AWS_CONFIG_FILE", "AWS_SHARED_CREDENTIALS_FILE"):
        require(not environment.get(name), "An AWS profile file override is present.")
    require(not any(environment.get(name) for name in CLI_CREDENTIAL_ENV_NAMES),
            "Inherited AWS credential or role environment is present.")


def check_default_profile():
    validate_identity_environment()
    require(Path(pwd.getpwuid(os.getuid()).pw_dir) == FROZEN_HOME,
            "Current home differs from reviewed AWS profile.")
    require(FROZEN_CONFIG_PATH.is_file() and not FROZEN_CONFIG_PATH.is_symlink()
            and file_hash(FROZEN_CONFIG_PATH) == FROZEN_CONFIG_SHA256,
            "Default AWS profile configuration changed.")
    try:
        config = configparser.ConfigParser(interpolation=None, strict=True)
        config.read_string(FROZEN_CONFIG_PATH.read_text(encoding="utf-8"))
        require(config.has_section("default") and not config.has_section("profile default")
                and set(config["default"]) == {"region", "login_session"}
                and config["default"]["region"] == "us-east-1"
                and hashlib.sha256(config["default"]["login_session"].encode()).hexdigest()
                == FROZEN_LOGIN_SESSION_SHA256,
                "Default AWS login profile changed.")
        if FROZEN_CREDENTIALS_PATH.exists():
            require(FROZEN_CREDENTIALS_PATH.is_file() and not FROZEN_CREDENTIALS_PATH.is_symlink(),
                    "Shared AWS credentials path changed.")
            credentials = configparser.ConfigParser(interpolation=None, strict=True)
            credentials.read_string(FROZEN_CREDENTIALS_PATH.read_text(encoding="utf-8"))
            require(not credentials.has_section("default")
                    and not credentials.has_section("profile default")
                    and not (set(credentials.defaults()) & SHARED_CREDENTIAL_DEFAULT_KEYS),
                    "Shared credentials provide another default identity.")
    except (OSError, UnicodeError, configparser.Error):
        raise IntegrityError("AWS profile files could not be validated.") from None


def controlled_cli_environment(environment=None):
    source = os.environ if environment is None else environment
    child = {key: value for key, value in source.items()
             if not key.upper().startswith("AWS_ENDPOINT_URL")
             and key.upper() not in CLI_CREDENTIAL_ENV_NAMES}
    child.update(HOME=str(FROZEN_HOME), AWS_CONFIG_FILE=str(FROZEN_CONFIG_PATH),
                 AWS_SHARED_CREDENTIALS_FILE=str(FROZEN_CREDENTIALS_PATH),
                 AWS_PROFILE=EXPECTED_PROFILE, AWS_DEFAULT_PROFILE=EXPECTED_PROFILE,
                 AWS_IGNORE_CONFIGURED_ENDPOINT_URLS="true",
                 AWS_RETRY_MODE="standard", AWS_MAX_ATTEMPTS="1")
    return child


def check_aws_cli():
    require(AWS_CLI_PATH.is_file() and os.access(AWS_CLI_PATH, os.X_OK)
            and Path(shutil.which("aws") or "/__missing_aws_cli__/aws").resolve() == AWS_CLI_PATH,
            "Pinned AWS CLI executable changed.")
    try:
        result = subprocess.run((str(AWS_CLI_PATH), "--version"), capture_output=True,
                                timeout=5, env=controlled_cli_environment())
        output = (result.stdout + result.stderr).decode("utf-8", errors="replace").strip()
    except (OSError, subprocess.TimeoutExpired):
        raise IntegrityError("Pinned AWS CLI version unavailable.") from None
    require(result.returncode == 0 and output.split(maxsplit=1)[0]
            == f"aws-cli/{EXPECTED_AWS_CLI_VERSION}", "Pinned AWS CLI version changed.")


def validate_credential_lifetime(raw, now=None):
    try:
        credentials = safe.strict_json(raw.decode("utf-8"))
        expiration = credentials.get("Expiration") if type(credentials) is dict else None
        require(type(expiration) is str and 1 <= len(expiration) <= 64,
                "Exported credentials lack bounded expiration.")
        expires_at = datetime.fromisoformat(expiration.replace("Z", "+00:00"))
        require(expires_at.tzinfo is not None, "Exported credentials lack timezone.")
    except (UnicodeError, ValueError, TypeError, OverflowError):
        raise IntegrityError("Exported credentials have invalid expiration.") from None
    current = datetime.now(timezone.utc) if now is None else now
    require((expires_at - current).total_seconds() >= 300,
            "Credential snapshot expires before bounded trial ends.")
    return expires_at


def default_profile_session():
    check_default_profile()
    check_aws_cli()
    command = (str(AWS_CLI_PATH), "configure", "export-credentials", "--profile",
               EXPECTED_PROFILE, "--format", "process")
    child_environment = controlled_cli_environment()

    def spawn(actual, **kwargs):
        require(tuple(actual) == command and "env" not in kwargs,
                "Credential export command or environment changed.")
        check_default_profile()
        return subprocess.Popen(actual, env=child_environment, **kwargs)

    original_export = safe.export_credentials
    snapshot = {}

    def checked_export():
        raw = original_export()
        snapshot["expires_at"] = validate_credential_lifetime(raw)
        return raw

    controlled_subprocess = SimpleNamespace(Popen=spawn, PIPE=subprocess.PIPE,
                                             DEVNULL=subprocess.DEVNULL)
    with patch.object(safe, "CREDENTIAL_COMMAND", command), \
            patch.object(safe, "subprocess", controlled_subprocess), \
            patch.object(safe, "export_credentials", checked_export):
        session, secrets = safe.credential_session()
    require("expires_at" in snapshot, "Credential export expiration was not checked.")
    return session, secrets, snapshot["expires_at"]


def checked_sts_client(session):
    client = session.client(
        "sts", region_name="us-east-1", endpoint_url=STS_ENDPOINT,
        config=Config(connect_timeout=3, read_timeout=10,
                      retries={"total_max_attempts": 1, "mode": "standard"}),
    )
    meta = client.meta
    cfg = meta.config
    require(meta.endpoint_url == STS_ENDPOINT and meta.region_name == "us-east-1"
            and cfg.connect_timeout == 3 and cfg.read_timeout == 10
            and cfg.retries.get("total_max_attempts") == 1,
            "STS endpoint or SDK retry limit changed.")
    return client


def verify_account_identity(session, capture, path, *, deadline=None):
    validate_identity_environment()
    require(capture["identity_check"]["requests_reserved"] == 0,
            "Execute STS identity call was already reserved.")
    client = checked_sts_client(session)
    capture["identity_check"]["status"] = "endpoint_validated"
    capture["identity_check"]["requests_reserved"] = 1
    save(path, capture)
    if deadline is not None:
        require(deadline.get_remaining_time_in_millis() >= 13_000,
                "Deadline cannot cover execute STS request.")
    identity = client.get_caller_identity()
    require(type(identity) is dict and identity.get("Account") == EXPECTED_ACCOUNT_ID,
            "AWS account differs from reviewed intended account.")
    capture["identity_check"]["status"] = "verified"
    save(path, capture)


def decoded_credential_echo(response, secrets):
    content = response.get("output", {}).get("message", {}).get("content", [])
    text = "\n".join(block["text"] for block in content
                     if isinstance(block, dict) and isinstance(block.get("text"), str)).strip()
    if len(text.encode()) > safe.VISIBLE_RESPONSE_MAX_BYTES:
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


def new_capture(plan, plan_sha256=None):
    require(plan["request"]["targetCount"] == 5
            and plan["limits"]["native_author_rows"] == 7
            and plan["limits"]["maximum_converse_calls"] == 1,
            "Frozen original request or author-only call allowance changed.")
    return {
        "plan_sha256": plan_sha256, "trial_id": TRIAL_ID,
        "source_commit": plan["source_commit"],
        "started_at": datetime.now(timezone.utc).isoformat(),
        "status": "setup", "global_stop": None,
        "original_rows": [{"ordinal": index, "status": "unattempted"}
                          for index in range(7)],
        "call_slots": [{"ordinal": 0, "status": "unattempted"}],
        "calls": [], "reservations": [],
        "identity_check": {"profile": EXPECTED_PROFILE,
                           "account": EXPECTED_ACCOUNT_ID,
                           "endpoint": STS_ENDPOINT,
                           "status": "unattempted", "requests_reserved": 0},
    }


class Deadline:
    def __init__(self, clock):
        self.clock, self.started = clock, clock()

    def get_remaining_time_in_millis(self):
        return max(0, int((EXECUTE_SECONDS - (self.clock() - self.started)) * 1000))


def run_author(plan, capture, path, client_factory, pin_check, *, secrets=(),
               clock=time.monotonic, deadline=None, credential_expires_at=None,
               credential_clock=lambda: datetime.now(timezone.utc)):
    """Run exactly the production native seven-row author, then local sanitizer."""
    deadline = Deadline(clock) if deadline is None else deadline
    require(deadline.get_remaining_time_in_millis() > 0,
            "Whole execute deadline elapsed before author job.")
    require(not capture["calls"] and not capture["reservations"]
            and capture["call_slots"][0]["status"] == "unattempted",
            "Author call already attempted.")
    capture["status"] = "running"
    save(path, capture)
    budget = runtime.ProviderCallBudget(MAX_CALLS, context=deadline)
    metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0,
               "BedrockOutputTokens": 0}
    author_request = {**copy.deepcopy(plan["request"]), "targetCount": 7}
    slot = capture["call_slots"][0]

    def pins():
        check_capture(path)
        pin_check()

    def reserve():
        require(capture["global_stop"] is None
                and not capture["reservations"]
                and slot["status"] == "unattempted",
                "The sole Converse slot was already reserved.")
        slot["status"] = "reserved"
        capture["reservations"].append({"ordinal": 0})
        save(path, capture)

    budget.reserve_call = DurableProviderCallReservation(reserve, MAX_CALLS)

    class Recorder:
        def __init__(self, client):
            self.client, self.meta = client, client.meta

        def converse(self, **wire):
            pins()
            cfg = self.meta.config
            require(self.meta.endpoint_url == ENDPOINT
                    and self.meta.region_name == "us-east-1"
                    and cfg.connect_timeout == 3
                    and 2 <= cfg.read_timeout <= 200
                    and cfg.retries.get("total_max_attempts") == 1,
                    "Bedrock transport differs from frozen endpoint/retry limits.")
            require(wire == plan["author_wire"]
                    and wire["outputConfig"] == plan["allowed_contracts"][
                        plan["author_contract_name"]],
                    "Actual author request differs from the frozen wire and schema.")
            operation = get_session().get_service_model("bedrock-runtime").operation_model("Converse")
            validate_parameters(wire, operation.input_shape)
            require(slot["status"] == "reserved" and len(capture["reservations"]) == 1
                    and not capture["calls"],
                    "Converse lacks its one durable reservation.")
            slot["status"] = "request_saved"
            call = {"ordinal": 0, "stage": plan["author_contract_name"],
                    "request": copy.deepcopy(wire), "dispatch_attempted": False,
                    "sdk_attempts": 1, "connect_timeout": cfg.connect_timeout,
                    "read_timeout": cfg.read_timeout}
            capture["calls"].append(call)
            save(path, capture)
            started = clock()
            try:
                pins()
                minimum = runtime._minimum_provider_remaining_milliseconds(
                    connect_timeout=cfg.connect_timeout, read_timeout=cfg.read_timeout)
                require(budget.remaining_milliseconds() >= minimum,
                        "Insufficient time after durable author request capture.")
                if credential_expires_at is not None:
                    remaining = int((credential_expires_at - credential_clock()).total_seconds() * 1000)
                    call["credential_remaining_before_ms"] = max(0, remaining)
                    require(remaining >= minimum,
                            "Credential snapshot expires before author request can complete.")
                call["dispatch_attempted"] = True
                slot["status"] = "dispatch_attempted"
                save(path, capture)
                response = self.client.converse(**wire)
                retained, omitted = safe.safe_response(response, secrets)
                retained.pop("safeResponseMetadata", None)
                visible = json.dumps(retained, ensure_ascii=False)
                require(not any(secret and secret in visible for secret in secrets)
                        and not decoded_credential_echo(response, secrets),
                        "Credential echo in visible model response.")
                call.update(response=retained, reasoning_blocks_omitted=omitted)
                slot["status"] = "completed"
                return response
            except Exception as error:
                call["error"] = safe_error_identity(error, secrets)
                slot["status"] = ("failed_after_dispatch" if call["dispatch_attempted"]
                                  else "failed_before_dispatch")
                if isinstance(error, (IntegrityError, safe.CaptureBoundaryError)):
                    capture["global_stop"] = "capture_or_transport_integrity"
                raise
            finally:
                call["elapsed_seconds"] = round(clock() - started, 6)
                pins()
                save(path, capture)

    try:
        pins()
        with patch.dict(os.environ, plan["environment"], clear=True):
            client = client_factory(
                "bedrock-runtime", region_name="us-east-1",
                config=Config(connect_timeout=3, read_timeout=200,
                              retries={"total_max_attempts": 1, "mode": "standard"}),
            )
            payload = runtime._generate_provider_payload(
                author_request, Recorder(client), call_budget=budget,
                request_metrics=metrics,
            )
            raw_rows = payload.get("questions")
            require(type(raw_rows) is list and len(raw_rows) == 7
                    and all(type(item) is dict for item in raw_rows),
                    "Native author did not yield seven source rows.")
            source_by_prompt = {}
            for ordinal, item in enumerate(raw_rows):
                prompt = quality._prompt_without_trailing_choice_echo(
                    item.get("prompt"), item.get("choices"))
                require(type(prompt) is str and prompt and prompt not in source_by_prompt,
                        "Author row lacks a unique displayed stem.")
                source_by_prompt[prompt] = ordinal
                capture["original_rows"][ordinal].update(
                    status="authored", author_question=copy.deepcopy(item))
            save(path, capture)
            sanitized = runtime._sanitize_questions(
                raw_rows, author_request, metrics,
                preserve_authored_explanation=True,
            )
            seen = set()
            for question in sanitized:
                ordinal = source_by_prompt.get(question["prompt"])
                require(ordinal is not None and ordinal not in seen,
                        "Sanitized question cannot be tied to one authored source.")
                seen.add(ordinal)
                capture["original_rows"][ordinal].update(
                    status="sanitized", sanitized_question=copy.deepcopy(question))
            capture["sanitized_source_ordinals"] = sorted(seen)
            capture["status"] = "finished"
    except Exception as error:
        capture["status"] = "failed"
        capture["error"] = safe_error_identity(error, secrets)
        if isinstance(error, (IntegrityError, safe.CaptureBoundaryError)):
            capture["global_stop"] = "setup_or_integrity_failure"
    finally:
        elapsed = clock() - deadline.started
        capture["whole_execute_seconds"] = round(elapsed, 6)
        capture["within_deadline"] = elapsed <= EXECUTE_SECONDS
        capture["metrics"] = metrics
        for item in capture["original_rows"]:
            if item["status"] == "unattempted":
                item["status"] = "unfilled_unattempted"
        pins()
        save(path, capture)
    return capture


def finish(capture):
    successful = (
        capture.get("status") == "finished"
        and capture.get("global_stop") is None
        and capture.get("within_deadline") is True
        and capture.get("sanitized_source_ordinals") == list(range(7))
        and all(item["status"] == "sanitized"
                and type(item.get("author_question")) is dict
                and type(item.get("sanitized_question")) is dict
                for item in capture["original_rows"])
        and len(capture["calls"]) == len(capture["reservations"]) == 1
        and capture["call_slots"][0]["status"] == "completed"
    )
    capture["summary"] = {
        "authored_source_ordinals": [item["ordinal"] for item in capture["original_rows"]
                                     if "author_question" in item],
        "sanitized_source_ordinals": capture.get("sanitized_source_ordinals", []),
        "provider_calls": len(capture["calls"]),
        "provider_reservations": len(capture["reservations"]),
        "original_rows": [{"ordinal": item["ordinal"], "status": item["status"]}
                          for item in capture["original_rows"]],
        "qualification": "pending_author_content_review" if successful else "failed",
        "worker_qualified": False,
    }
    return capture["summary"]


def preflight():
    build_plan()
    result = subprocess.run((sys.executable, "-B", "-m", "unittest", "discover",
                             "-s", str(HERE), "-p", "test_author_probe.py", "-q"),
                            capture_output=True, text=True)
    require(result.returncode == 0, "Socket-free live harness tests failed: " + result.stderr)
    return {"provider_calls": 0, "result": "passed", "output": result.stderr.strip()}


def require_review_go(plan_sha256):
    require(REVIEW_LOCK.is_file() and REVIEW_LOCK.stat().st_size <= 4096,
            "Exact frozen plan awaits root and independent review.")
    record = safe.strict_json(REVIEW_LOCK.read_text())
    require(type(record) is dict and set(record) == {
        "plan_sha256", "harness_sha256", "source_commit", "root_go", "independent_go"}
        and record["plan_sha256"] == plan_sha256
        and record["harness_sha256"] == IMPORTED_HARNESS_HASH
        and record["source_commit"] == SOURCE_COMMIT
        and record["root_go"] is True and record["independent_go"] is True,
        "Review lock does not approve this exact plan and harness.")


def check_launch_record(plan_sha256, *, now=None):
    require(LAUNCH_ATTEMPT.is_file() and LAUNCH_ATTEMPT.stat().st_size <= 8192
            and LAUNCH_PRECHECK.is_file() and LAUNCH_PRECHECK.stat().st_size <= 8192,
            "No bounded launch freshness record exists.")
    try:
        attempt = safe.strict_json(LAUNCH_ATTEMPT.read_text())
        record = safe.strict_json(LAUNCH_PRECHECK.read_text())
        checked_at = datetime.fromisoformat(record["checked_at"].replace("Z", "+00:00"))
        expires_at = datetime.fromisoformat(record["credential_expires_at"].replace("Z", "+00:00"))
        require(checked_at.tzinfo is not None and expires_at.tzinfo is not None,
                "Launch freshness timestamps have no timezone.")
    except (OSError, UnicodeError, ValueError, TypeError, AttributeError, KeyError, OverflowError):
        raise IntegrityError("Launch freshness record is malformed.") from None
    require(type(attempt) is dict and set(attempt) == {
        "status", "plan_sha256", "started_at", "maximum_sts_requests", "provider_calls"}
        and attempt["status"] == "started"
        and attempt["plan_sha256"] == plan_sha256
        and attempt["maximum_sts_requests"] == 1
        and attempt["provider_calls"] == 0,
        "Launch precheck attempt differs from reviewed plan.")
    require(type(record) is dict and set(record) == {
        "status", "plan_sha256", "checked_at", "credential_expires_at",
        "credential_lifetime_seconds", "account", "pretrial_sts_requests",
        "botocore_signin_refresh_operations", "provider_calls"}
        and record["status"] == "passed"
        and record["plan_sha256"] == plan_sha256
        and record["account"] == EXPECTED_ACCOUNT_ID
        and record["pretrial_sts_requests"] == 1
        and record["provider_calls"] == 0
        and type(record["botocore_signin_refresh_operations"]) is int
        and 0 <= record["botocore_signin_refresh_operations"] <= 1
        and type(record["credential_lifetime_seconds"]) is int
        and record["credential_lifetime_seconds"] >= 360
        and record["credential_lifetime_seconds"] == int((expires_at - checked_at).total_seconds()),
        "Launch freshness record differs from reviewed identity/budget.")
    current = datetime.now(timezone.utc) if now is None else now
    require(0 <= (current - checked_at).total_seconds() <= 120
            and (expires_at - current).total_seconds() >= 330,
            "Pretrial credential freshness window closed before launch.")
    return record


def launch_precheck():
    require(PLAN.is_file() and PLAN.stat().st_size <= 8 * 1024 * 1024,
            "Frozen plan is missing.")
    plan = safe.strict_json(PLAN.read_text())
    plan_sha = file_hash(PLAN)
    check_plan(plan, PLAN, plan_sha)
    require_review_go(plan_sha)
    check_execution_runtime()
    require(not LAUNCH_ATTEMPT.exists() and not LAUNCH_PRECHECK.exists()
            and not CAPTURE.exists(),
            "Launch precheck or trial artifact already exists.")
    check_default_profile()
    check_aws_cli()
    save(LAUNCH_ATTEMPT, {
        "status": "started", "plan_sha256": plan_sha,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "maximum_sts_requests": 1, "provider_calls": 0,
    }, exclusive=True)
    signin_refresh_operations = []

    def before_signin_refresh(**_):
        require(not signin_refresh_operations, "Pretrial sign-in refresh ceiling exceeded.")
        signin_refresh_operations.append(1)

    previous_handler = signal.getsignal(signal.SIGALRM)
    try:
        signal.signal(signal.SIGALRM, deadline_alarm)
        signal.setitimer(signal.ITIMER_REAL, 45)
        with patch.dict(os.environ, controlled_cli_environment(), clear=True):
            profile_session = boto3.Session(profile_name=EXPECTED_PROFILE,
                                            region_name="us-east-1")
            profile_session.events.register("before-call.signin.CreateOAuth2Token",
                                            before_signin_refresh)
            identity = checked_sts_client(profile_session).get_caller_identity()
        require(type(identity) is dict and identity.get("Account") == EXPECTED_ACCOUNT_ID,
                "Pretrial AWS account differs from frozen intended account.")
        _, _, expires_at = default_profile_session()
        checked_at = datetime.now(timezone.utc)
        lifetime = int((expires_at - checked_at).total_seconds())
        require(lifetime >= 360, "Pretrial credential snapshot is not fresh enough.")
        record = {
            "status": "passed", "plan_sha256": plan_sha,
            "checked_at": checked_at.isoformat(),
            "credential_expires_at": expires_at.isoformat(),
            "credential_lifetime_seconds": lifetime,
            "account": EXPECTED_ACCOUNT_ID, "pretrial_sts_requests": 1,
            "botocore_signin_refresh_operations": len(signin_refresh_operations),
            "provider_calls": 0,
        }
        save(LAUNCH_PRECHECK, record, exclusive=True)
        return record
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_handler)


def freeze(reviewed_digest):
    require(not any(path.exists() for path in (
        PLAN, CAPTURE, LAUNCH_ATTEMPT, LAUNCH_PRECHECK)),
        "Trial plan, freshness record or capture already exists.")
    draft = build_plan()
    require(digest(draft) == reviewed_digest, "Draft digest changed.")
    preflight()
    require(build_plan() == draft, "Sources changed during socket-free preflight.")
    save(PLAN, {**draft, "state": "frozen"}, exclusive=True)
    return {"plan_sha256": file_hash(PLAN), "provider_calls": 0}


def execute(expected_hash):
    require(PLAN.is_file() and PLAN.stat().st_size <= 8 * 1024 * 1024
            and file_hash(PLAN) == expected_hash,
            "Frozen plan bound or hash failed.")
    plan = safe.strict_json(PLAN.read_text())
    check_plan(plan, PLAN, expected_hash)
    require_review_go(expected_hash)
    check_execution_runtime()
    check_launch_record(expected_hash)
    require(not CAPTURE.exists(), "This one-shot trial already has a capture.")
    deadline = Deadline(time.monotonic)
    capture = new_capture(plan, expected_hash)
    save(CAPTURE, capture, exclusive=True)
    secrets = ()
    previous_handler = signal.getsignal(signal.SIGALRM)
    try:
        signal.signal(signal.SIGALRM, deadline_alarm)
        remaining = EXECUTE_SECONDS - (deadline.clock() - deadline.started)
        require(remaining > 0, "Execute deadline elapsed before credential export.")
        signal.setitimer(signal.ITIMER_REAL, remaining)
        session, secrets, credential_expires_at = default_profile_session()
        verify_account_identity(session, capture, CAPTURE, deadline=deadline)
        run_author(plan, capture, CAPTURE, session.client,
                production_pin_callback(plan, expected_hash),
                secrets=secrets, deadline=deadline,
                credential_expires_at=credential_expires_at)
    except WholeDeadlineExceeded:
        capture.update(status="deadline_exceeded", global_stop="execute_deadline",
                       error={"type": "WholeDeadlineExceeded", "code": "whole_execute_deadline"})
        save(CAPTURE, capture)
    except BaseException as error:
        capture.update(status="globally_aborted", global_stop="setup_or_interruption",
                       error=safe_error_identity(error, secrets))
        save(CAPTURE, capture)
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            raise
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_handler)
        elapsed = deadline.clock() - deadline.started
        capture["whole_execute_seconds"] = round(elapsed, 6)
        if elapsed > EXECUTE_SECONDS:
            capture["global_stop"] = "execute_deadline"
        finish(capture)
        save(CAPTURE, capture)
    return {"capture": str(CAPTURE), "status": capture["status"],
            "summary": capture.get("summary")}


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
        result = build_plan()
        print(json.dumps({"draft_sha256": digest(result),
                          "author_wire_sha256": result["author_wire_sha256"],
                          "native_author_schema_sha256": result["native_author_schema_sha256"],
                          "native_author_schema_bytes": result["native_author_schema_bytes"],
                          "provider_calls": 0}, sort_keys=True))
    elif args.preflight:
        print(json.dumps(preflight(), sort_keys=True))
    elif args.freeze:
        print(json.dumps(freeze(args.freeze), sort_keys=True))
    elif args.launch_precheck:
        print(json.dumps(launch_precheck(), sort_keys=True))
    else:
        print(json.dumps(execute(args.execute), sort_keys=True))


if __name__ == "__main__":
    main()
