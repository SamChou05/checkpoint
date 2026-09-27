"""Frozen, one-job v12 mapped 3:2 full-worker qualification harness.

Preparation and tests are socket-free. AWS dispatch requires a separate exact-hash
review lock, fresh credential preflight, and an explicit --execute invocation.
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

from jsonschema import Draft202012Validator
from botocore.validate import validate_parameters

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = (ROOT / "backend/bedrock-question-service").resolve()
SOURCE_COMMIT = "1e411c345a34d867bbee445953c1d0b29101e66e"
SELECTOR_COMMIT = "75f52cb"
EXPLANATION_COMMIT = "67fee6e"
QUARANTINE_COMMIT = "1e411c3"
TRIAL_ID = "combined-v12-level2-quarantine-mapped-3x2-full-worker-20260927-01"
V12_AUTHOR_PLAN = ROOT / "docs/evidence/combined-v12-native-author-acceptance-20260927/plan.json"
V12_AUTHOR_PLAN_SHA256 = "663bea09f568c49e1e20adf543c61178d28963b8161f6ff299c1dea929902a7b"
V12_AUTHOR_CAPTURE = ROOT / "docs/evidence/combined-v12-native-author-acceptance-20260927/capture.json"
V12_AUTHOR_CAPTURE_SHA256 = "78a25d2c636c6246ab55cb0757c67b817590cd285fea0ba1784e92035cc9efe0"
PREVIOUS_WORKER_CAPTURE = ROOT / "docs/evidence/native-v9-teaching-fixed-full-worker-20260927/capture.json"
PREVIOUS_WORKER_CAPTURE_SHA256 = "a880fcf748b75f2c9ebcd7170edeb412b4f83712602ee3becdee7de929bf874a"
PREVIOUS_V12_WORKER_CAPTURE = ROOT / "docs/evidence/combined-v12-full-worker-qualification-20260927/capture.json"
PREVIOUS_V12_WORKER_CAPTURE_SHA256 = "fe66f66fe9bc1b8eefa62c167447e73a62d41cf362850a3db8cbc912298af31d"
PREVIOUS_V12_WORKER_RESULTS = ROOT / "docs/evidence/combined-v12-full-worker-qualification-20260927/RESULTS.md"
PREVIOUS_V12_WORKER_RESULTS_SHA256 = "8f9377abdba9fdf1bb4120184a3c290e3337ab1281979a8542645c6f568e5912"
SECOND_V12_WORKER_CAPTURE = ROOT / "docs/evidence/combined-v12-selector-first-full-worker-qualification-20260927/capture.json"
SECOND_V12_WORKER_CAPTURE_SHA256 = "d23f4fb1ac51d672a9ab9b2e4d95ca26c184dab0a2fb9631a11c2287a6b9f62f"
SECOND_V12_WORKER_RESULTS = ROOT / "docs/evidence/combined-v12-selector-first-full-worker-qualification-20260927/RESULTS.md"
SECOND_V12_WORKER_RESULTS_SHA256 = "800ac1dcb0cd1be0e32d81ad1232e4efcd4847f79ef91936db1ad265a022755e"
IMMEDIATE_PREDECESSOR_CAPTURE = ROOT / "docs/evidence/combined-v12-explained-full-worker-qualification-20260927/capture.json"
IMMEDIATE_PREDECESSOR_CAPTURE_SHA256 = "8337af2d8d23ede59ec0f487ab8095de2515719a4702ab29eabd49bffcaed696"
IMMEDIATE_PREDECESSOR_RESULTS = ROOT / "docs/evidence/combined-v12-explained-full-worker-qualification-20260927/RESULTS.md"
IMMEDIATE_PREDECESSOR_RESULTS_SHA256 = "988cc22bdd7d428b23a2ce0140d8b62b650fa46ed4067513c1804a0fb97e6e15"
REQUEST_FIXTURE = HERE / "request.json"
IMPORTED_SERVICE_HASHES = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                           for path in sorted(SERVICE.glob("*.py"))}
IMPORTED_HARNESS_HASH = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
sys.path.insert(0, str(SERVICE))

import awscrt  # noqa: E402
import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_generation as runtime  # noqa: E402
from quantitative_authoring import LEARNER_FIELDS  # noqa: E402
from question_bank_common import DurableProviderCallReservation  # noqa: E402
from service_errors import ProviderError, SafetyInterventionError, ServiceConfigurationError  # noqa: E402

HELPER = SERVICE / "evals/bounded_bedrock_capture.py"
IMPORTED_HELPER_HASH = hashlib.sha256(HELPER.read_bytes()).hexdigest()
_spec = importlib.util.spec_from_file_location("combined_v12_capture_helper", HELPER)
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
MIN_CREDENTIAL_LIFETIME_SECONDS = 300
LAUNCH_PRECHECK_MINIMUM_SECONDS = 360
LAUNCH_WINDOW_MINIMUM_SECONDS = 330
FROZEN_HOME = Path("/Users/samchou")
FROZEN_CONFIG_PATH = FROZEN_HOME / ".aws/config"
FROZEN_CREDENTIALS_PATH = FROZEN_HOME / ".aws/credentials"
FROZEN_CONFIG_SHA256 = "7f70246298d2f2897d39ee3a99a7353bfa9b83255ef95ba0db5f3a5623ea5f3d"
FROZEN_LOGIN_SESSION_SHA256 = "8731d91a75118f0c6e502e84b95a999bbf68e2c825830881788660d6ee32e1f2"
FROZEN_PROFILE_KEYS = frozenset({"login_session", "region"})
FROZEN_PROFILE_REGION = "us-east-1"
CLI_CREDENTIAL_ENV_NAMES = frozenset({
    "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_SECURITY_TOKEN",
    "AWS_ROLE_ARN", "AWS_ROLE_SESSION_NAME", "AWS_WEB_IDENTITY_TOKEN_FILE",
    "AWS_CONTAINER_CREDENTIALS_FULL_URI", "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI",
    "AWS_CONTAINER_AUTHORIZATION_TOKEN", "AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE",
})
SHARED_CREDENTIAL_DEFAULT_KEYS = frozenset({
    "aws_access_key_id", "aws_secret_access_key", "aws_session_token",
    "credential_process", "role_arn", "source_profile", "web_identity_token_file",
})
ENVIRONMENT = copy.deepcopy(json.loads(V12_AUTHOR_PLAN.read_text())["environment"])
_PROVISIONAL_REQUEST = json.loads(REQUEST_FIXTURE.read_text())
PROVISIONAL_GOAL_SHA256 = hashlib.sha256(json.dumps(
    _PROVISIONAL_REQUEST["goal"], sort_keys=True, separators=(",", ":"),
    ensure_ascii=True, allow_nan=False).encode()).hexdigest()
PROVISIONAL_SCOPE_SHA256 = runtime._mapped_author_scope_sha256(_PROVISIONAL_REQUEST)
AUTHOR_MODEL = ENVIRONMENT["BEDROCK_MODEL_ID"]
EXECUTE_SECONDS = 240
LIMITS = {"original_jobs": 1, "original_slots": 5, "calls_per_job": 6,
          "seconds_per_job": EXECUTE_SECONDS, "sdk_attempts_per_call": 1,
          "connect_timeout_seconds": 3, "read_timeout_ceiling_seconds": 200,
          "hard_deadline_enforcement": "SIGALRM_ITIMER_REAL_one_shot",
          "deadline_origin": "execute_capture_start_before_credentials_and_sts",
          "sts_preflight_requests": 1, "sts_execute_requests": 1,
          "sts_total_requests": 2, "sts_sdk_attempts_per_request": 1,
          "one_trial_execution": True, "retry_fallback_topup": False,
          "bank_queue_deploy_writes": False}
PLAN, CAPTURE = HERE / "plan.json", HERE / "capture.json"
LAUNCH_PRECHECK = HERE / "launch-precheck.json"
LAUNCH_ATTEMPT = HERE / "launch-precheck-attempt.json"
REVIEW_LOCK = HERE / "review-approval.json"
CAPTURE_HASHES = {}


class IntegrityError(RuntimeError):
    pass


class WholeDeadlineExceeded(BaseException):
    """Escape a provider socket read when the whole execute limit expires."""


def deadline_alarm(_signal, _frame):
    raise WholeDeadlineExceeded("Whole 240-second worker deadline expired.")


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


def _sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


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
            stream.flush()
            os.fsync(stream.fileno())
        _sync_directory(path.parent)
    else:
        temporary = path.with_suffix(".partial")
        with temporary.open("x") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        _sync_directory(path.parent)
    if is_capture:
        CAPTURE_HASHES[path.resolve()] = file_hash(path)


def safe_error_identity(error, secrets=()):
    """Persist only bounded, credential-redacted error type and provider code."""
    response = getattr(error, "response", {})
    problem = response.get("Error", {}) if type(response) is dict else {}
    code = problem.get("Code") if type(problem) is dict else None
    return {"type": type(error).__name__, "code": safe.redact(code, secrets, maximum=128)}


def new_capture(plan, plan_sha256=None):
    """Materialize the single original job and its slots before credentials."""
    require(len(plan["jobs"]) == 1 and plan["jobs"][0]["id"] == "mixed"
            and plan["jobs"][0]["request"]["targetCount"] == 5,
            "Original five-slot assignment changed.")
    bindings = original_slot_bindings(plan)
    original_jobs = [{"id": job["id"], "status": "unattempted",
                      "slots": [{**binding, "status": "unattempted"} for binding in bindings]}
                     for job in plan["jobs"]]
    call_slots = [{"job": job["id"], "ordinal": index, "status": "unattempted"}
                  for job in plan["jobs"] for index in range(6)]
    return {"plan": copy.deepcopy(plan), "plan_sha256": plan_sha256, "calls": [], "jobs": [],
            "original_jobs": original_jobs, "call_slots": call_slots, "reservations": [],
            "identity_check": {"profile": EXPECTED_PROFILE, "account": EXPECTED_ACCOUNT_ID,
                               "endpoint": STS_ENDPOINT, "status": "unattempted",
                               "requests_reserved": 0},
            "started_at": datetime.now(timezone.utc).isoformat(), "status": "setup"}


def validate_identity_environment(environment=None):
    environment = os.environ if environment is None else environment
    for name in ("AWS_PROFILE", "AWS_DEFAULT_PROFILE"):
        require(environment.get(name, EXPECTED_PROFILE) in ("", EXPECTED_PROFILE),
                "AWS identity profile differs from the frozen default profile.")
    require(not any(key.upper().startswith("AWS_ENDPOINT_URL") and value
                    for key, value in environment.items()),
            "An AWS endpoint override is present.")
    for name in ("AWS_CONFIG_FILE", "AWS_SHARED_CREDENTIALS_FILE"):
        require(not environment.get(name), "An AWS profile file path override is present.")


def check_profile_files(config_path, credentials_path, config_sha256, login_session_sha256):
    """Accept only the reviewed login-backed default profile as CLI input."""
    require(config_path.is_file() and not config_path.is_symlink()
            and file_hash(config_path) == config_sha256,
            "The default AWS profile configuration changed.")
    try:
        config = configparser.ConfigParser(interpolation=None, strict=True)
        config.read_string(config_path.read_text(encoding="utf-8"))
        require(config.has_section("default") and not config.has_section("profile default")
                and set(config["default"]) == FROZEN_PROFILE_KEYS,
                "The default AWS profile is not the reviewed login profile.")
        require(config["default"]["region"] == FROZEN_PROFILE_REGION
                and hashlib.sha256(config["default"]["login_session"].encode()).hexdigest()
                == login_session_sha256,
                "The default AWS login session or region changed.")
        if credentials_path.exists():
            require(credentials_path.is_file() and not credentials_path.is_symlink(),
                    "The shared AWS credentials path changed.")
            credentials = configparser.ConfigParser(interpolation=None, strict=True)
            credentials.read_string(credentials_path.read_text(encoding="utf-8"))
            require(not credentials.has_section("default")
                    and not credentials.has_section("profile default")
                    and not (set(credentials.defaults()) & SHARED_CREDENTIAL_DEFAULT_KEYS),
                    "Shared credentials provide a default identity.")
    except (OSError, UnicodeError, configparser.Error):
        raise IntegrityError("AWS profile files could not be validated.") from None


def check_default_profile():
    validate_identity_environment()
    require(Path(pwd.getpwuid(os.getuid()).pw_dir) == FROZEN_HOME,
            "The current user's home differs from the reviewed AWS profile.")
    check_profile_files(FROZEN_CONFIG_PATH, FROZEN_CREDENTIALS_PATH,
                        FROZEN_CONFIG_SHA256, FROZEN_LOGIN_SESSION_SHA256)


def controlled_cli_environment(environment=None):
    """Keep the profile and login cache while excluding inherited endpoint settings."""
    source = os.environ if environment is None else environment
    child = {key: value for key, value in source.items()
             if not key.upper().startswith("AWS_ENDPOINT_URL")
             and key.upper() not in CLI_CREDENTIAL_ENV_NAMES}
    child["HOME"] = str(FROZEN_HOME)
    child["AWS_CONFIG_FILE"] = str(FROZEN_CONFIG_PATH)
    child["AWS_SHARED_CREDENTIALS_FILE"] = str(FROZEN_CREDENTIALS_PATH)
    child["AWS_PROFILE"] = EXPECTED_PROFILE
    child["AWS_DEFAULT_PROFILE"] = EXPECTED_PROFILE
    child["AWS_IGNORE_CONFIGURED_ENDPOINT_URLS"] = "true"
    child["AWS_RETRY_MODE"] = "standard"
    child["AWS_MAX_ATTEMPTS"] = "1"
    return child


def check_aws_cli():
    """Fail before credential export if the frozen CLI binary or version changed."""
    require(AWS_CLI_PATH.is_file() and os.access(AWS_CLI_PATH, os.X_OK)
            and Path(shutil.which("aws") or "/__missing_aws_cli__/aws").resolve() == AWS_CLI_PATH,
            "Pinned AWS CLI executable changed.")
    try:
        result = subprocess.run((str(AWS_CLI_PATH), "--version"), capture_output=True,
                                timeout=5, env=controlled_cli_environment())
        output = (result.stdout + result.stderr).decode("utf-8", errors="replace").strip()
    except (OSError, subprocess.TimeoutExpired):
        raise IntegrityError("Pinned AWS CLI version unavailable.") from None
    require(result.returncode == 0 and bool(output)
            and output.split(maxsplit=1)[0] == f"aws-cli/{EXPECTED_AWS_CLI_VERSION}",
            "Pinned AWS CLI version changed.")


def validate_credential_lifetime(raw, now=None):
    """Require one exported snapshot to outlive the 240-second job and margin."""
    try:
        credentials = safe.strict_json(raw.decode("utf-8"))
        expiration = credentials.get("Expiration") if type(credentials) is dict else None
        if type(expiration) is not str or not 1 <= len(expiration) <= 64:
            raise ValueError
        expires_at = datetime.fromisoformat(expiration.replace("Z", "+00:00"))
        if expires_at.tzinfo is None:
            raise ValueError
    except (UnicodeError, ValueError, TypeError, OverflowError):
        raise IntegrityError("Exported credentials have no valid expiry bound.") from None
    current = datetime.now(timezone.utc) if now is None else now
    require((expires_at - current).total_seconds() >= MIN_CREDENTIAL_LIFETIME_SECONDS,
            "Exported credentials expire before the bounded trial ends.")
    return expires_at


def default_profile_session():
    """Export one explicit default-profile credential set for STS and Bedrock."""
    check_default_profile()
    check_aws_cli()
    command = (str(AWS_CLI_PATH), "configure", "export-credentials", "--profile", EXPECTED_PROFILE,
               "--format", "process")
    child_environment = controlled_cli_environment()

    def spawn(actual, **kwargs):
        require(tuple(actual) == command and "env" not in kwargs,
                "Credential export command or subprocess environment changed.")
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
    require("expires_at" in snapshot, "Credential export was not checked for expiration.")
    return session, secrets, snapshot["expires_at"]


def checked_sts_client(session):
    """Validate the resolved endpoint before a signed STS request."""
    client = session.client(
        "sts", region_name="us-east-1", endpoint_url=STS_ENDPOINT,
        config=Config(connect_timeout=3, read_timeout=10,
                      retries={"total_max_attempts": 1, "mode": "standard"}),
    )
    meta = client.meta
    config = meta.config
    require(meta.endpoint_url == STS_ENDPOINT and meta.region_name == "us-east-1"
            and config.connect_timeout == 3 and config.read_timeout == 10
            and config.retries.get("total_max_attempts") == 1,
            "STS transport differs from the frozen identity endpoint.")
    return client


def verify_account_identity(session, capture, path, *, deadline=None):
    """Check the exact STS endpoint before any signed identity request."""
    validate_identity_environment()
    require(capture["identity_check"]["requests_reserved"] == 0,
            "Execute identity request was already reserved.")
    client = checked_sts_client(session)
    capture["identity_check"]["status"] = "endpoint_validated"
    capture["identity_check"]["requests_reserved"] = 1
    save(path, capture)
    if deadline is not None:
        require(deadline.get_remaining_time_in_millis() >= 13_000,
                "Execute deadline cannot cover the signed STS request.")
    response = client.get_caller_identity()
    require(type(response) is dict and response.get("Account") == EXPECTED_ACCOUNT_ID,
            "AWS account differs from the frozen intended account.")
    capture["identity_check"]["status"] = "verified"
    save(path, capture)


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


def check_current_source(modules):
    """Require the pushed source revision and exact reviewed local bytes."""
    require(subprocess.run(("git", "merge-base", "--is-ancestor", SOURCE_COMMIT, "HEAD"),
                           cwd=ROOT, capture_output=True).returncode == 0,
            "The pinned source commit is not an ancestor of this checkout.")
    require(subprocess.run(("git", "merge-base", "--is-ancestor", SELECTOR_COMMIT, SOURCE_COMMIT),
                           cwd=ROOT, capture_output=True).returncode == 0,
            "The selector source revision is not part of this pinned commit.")
    require(subprocess.run(("git", "merge-base", "--is-ancestor", EXPLANATION_COMMIT, SOURCE_COMMIT),
                           cwd=ROOT, capture_output=True).returncode == 0,
            "The full-sentence explanation revision is not part of this pinned commit.")
    require(subprocess.run(("git", "merge-base", "--is-ancestor", QUARANTINE_COMMIT, SOURCE_COMMIT),
                           cwd=ROOT, capture_output=True).returncode == 0,
            "The level-2 sentence-selection quarantine is not part of this pinned commit.")
    require(subprocess.run(("git", "diff", "--quiet", SOURCE_COMMIT, "--",
                            "backend/bedrock-question-service"),
                           cwd=ROOT, capture_output=True).returncode == 0,
            "Backend source differs from the pinned source commit.")
    require(len(modules) == len(IMPORTED_SERVICE_HASHES)
            and {path.name: file_hash(path) for path in modules} == IMPORTED_SERVICE_HASHES,
            "Runtime source changed after import.")
    require(file_hash(HERE / "full_worker_probe.py") == IMPORTED_HARNESS_HASH,
            "Qualification harness changed after import.")
    require(file_hash(HELPER) == IMPORTED_HELPER_HASH,
            "Bounded capture helper changed after import.")


def check_execution_runtime():
    """Keep a live run on the source-pinned SDK; offline tests may use another."""
    require(boto3.__version__ == REQUIRED_BOTO3_VERSION
            and botocore.__version__ == REQUIRED_BOTOCORE_VERSION
            and awscrt.__version__ == REQUIRED_AWSCRT_VERSION,
            "Live SDK versions differ from the frozen worker transport.")


def mapped_contract(request):
    assignments = runtime._mapped_fixed_slot_assignments(request, "constructed_quantitative", "array")
    require(assignments is not None and runtime._mapped_agreement_route(request, assignments),
            "Mapped agreement route was not selected.")
    require(runtime._mapped_quantitative_family_route(request, assignments, True),
            "Mapped quantitative families route was not selected.")
    return runtime._mapped_author_contract(request, assignments, True, True)


def original_slot_bindings(plan):
    rows = []
    for skill_id, objective_id, skill_name, objective_name, count in plan["mapped_assignment"]["assignments"]:
        for _ in range(count):
            rows.append({"ordinal": len(rows),
                         "kind": "quantitative" if len(rows) < 3 else "agreement",
                         "skillID": skill_id, "objectiveID": objective_id,
                         "topic": skill_name, "objective": objective_name})
    require(len(rows) == 5 and [row["kind"] for row in rows] ==
            ["quantitative"] * 3 + ["agreement"] * 2,
            "Trusted original-slot bindings changed.")
    return rows


def build_plan():
    """Recompute every pin without sockets or credentials."""
    require(Path(runtime.__file__).resolve().parent == SERVICE,
            "Wrong runtime imported.")
    modules = sorted(SERVICE.glob("*.py"))
    check_current_source(modules)
    for path in modules:
        loaded = sys.modules.get(path.stem)
        if loaded is not None:
            require(Path(getattr(loaded, "__file__", "")).resolve() == path,
                    "A service module came from another checkout.")
    require(file_hash(PREVIOUS_V12_WORKER_CAPTURE) == PREVIOUS_V12_WORKER_CAPTURE_SHA256
            and file_hash(PREVIOUS_V12_WORKER_RESULTS) == PREVIOUS_V12_WORKER_RESULTS_SHA256,
            "First v12 predecessor evidence changed.")
    require(file_hash(SECOND_V12_WORKER_CAPTURE) == SECOND_V12_WORKER_CAPTURE_SHA256
            and file_hash(SECOND_V12_WORKER_RESULTS) == SECOND_V12_WORKER_RESULTS_SHA256,
            "Second v12 predecessor evidence changed.")
    require(file_hash(IMMEDIATE_PREDECESSOR_CAPTURE) == IMMEDIATE_PREDECESSOR_CAPTURE_SHA256
            and file_hash(IMMEDIATE_PREDECESSOR_RESULTS) == IMMEDIATE_PREDECESSOR_RESULTS_SHA256,
            "Immediate predecessor evidence changed.")
    immediate_predecessor = safe.strict_json(IMMEDIATE_PREDECESSOR_CAPTURE.read_text())
    require(immediate_predecessor["summary"]["returned_questions"] == 4
            and immediate_predecessor["jobs"][0]["returned_slot_ordinals"] == [0, 1, 2, 3]
            and [slot["status"] for slot in immediate_predecessor["original_jobs"][0]["slots"]] ==
                ["returned"] * 4 + ["unfilled"],
            "Immediate predecessor four-of-five failure was reclassified.")
    previous_v12_worker = safe.strict_json(PREVIOUS_V12_WORKER_CAPTURE.read_text())
    second_v12_worker = safe.strict_json(SECOND_V12_WORKER_CAPTURE.read_text())
    require(previous_v12_worker["summary"]["returned_questions"] == 4
            and previous_v12_worker["jobs"][0]["returned_slot_ordinals"] == [0, 1, 2, 3]
            and [slot["status"] for slot in previous_v12_worker["original_jobs"][0]["slots"]] ==
                ["returned"] * 4 + ["unfilled"],
            "First v12 predecessor four-of-five failure was reclassified.")
    require(second_v12_worker["summary"]["returned_questions"] == 4
            and second_v12_worker["jobs"][0]["returned_slot_ordinals"] == [0, 1, 2, 3]
            and [slot["status"] for slot in second_v12_worker["original_jobs"][0]["slots"]] ==
                ["returned"] * 4 + ["unfilled"],
            "Second v12 predecessor four-of-five failure was reclassified.")
    require(file_hash(V12_AUTHOR_PLAN) == V12_AUTHOR_PLAN_SHA256
            and file_hash(V12_AUTHOR_CAPTURE) == V12_AUTHOR_CAPTURE_SHA256
            and file_hash(PREVIOUS_WORKER_CAPTURE) == PREVIOUS_WORKER_CAPTURE_SHA256,
            "Predecessor evidence changed.")
    author_plan = safe.strict_json(V12_AUTHOR_PLAN.read_text())
    author_capture = safe.strict_json(V12_AUTHOR_CAPTURE.read_text())
    worker_capture = safe.strict_json(PREVIOUS_WORKER_CAPTURE.read_text())
    require(author_plan["source_commit"] ==
            "254d8af2f78b5f3b0e27c5b854e159ca21ac9391"
            and author_capture["status"] == "completed"
            and author_capture["converse_calls"] == 1
            and worker_capture["summary"]["returned_questions"] == 5,
            "Predecessor outcomes changed or were reclassified.")
    request = safe.strict_json(REQUEST_FIXTURE.read_text())
    require(request == _PROVISIONAL_REQUEST
            and file_hash(REQUEST_FIXTURE) == author_plan["request_sha256"]
            and digest(request) == author_plan["normalized_request_sha256"]
            and request["targetCount"] == 5
            and request["requestedSkillAllocation"] == {
                "11111111-1111-4111-8111-111111111111": 3,
                "22222222-2222-4222-8222-222222222222": 2,
            }, "Original 3:2 request changed.")
    require(ENVIRONMENT == author_plan["environment"]
            and ENVIRONMENT["BEDROCK_FALLBACK_MODEL_ID"] == ""
            and ENVIRONMENT["QUESTION_MAPPED_AGREEMENT_TASKS"] == "enabled"
            and ENVIRONMENT["QUESTION_MAPPED_QUANTITATIVE_FAMILIES"] == "enabled"
            and ENVIRONMENT["QUESTION_MAPPED_FIXED_FIVE_GOAL_SHA256"] == PROVISIONAL_GOAL_SHA256
            and ENVIRONMENT["QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256"] == PROVISIONAL_SCOPE_SHA256,
            "Exact-scope mapped environment changed.")
    with patch.dict(os.environ, ENVIRONMENT, clear=True):
        require(runtime._constructed_author_batch_size(request, "constructed_quantitative") == 5
                and not runtime._task_only_numerical_author(request, "constructed_quantitative", "array"),
                "The mixed fixture was assigned a numerical-only path.")
        contract = mapped_contract(request)
        system = native.native_prompt(runtime._system_prompt(), contract)
        user = runtime._user_prompt(request)
        config = native.native_output_config(contract)
    name = native.contract_metadata(contract)["name"]
    schema = config["textFormat"]["structure"]["jsonSchema"]["schema"]
    Draft202012Validator.check_schema(json.loads(schema))
    wire = {"modelId": ENVIRONMENT["BEDROCK_MODEL_ID"],
            "system": [{"text": system}],
            "messages": [{"role": "user", "content": [{"text": user}]}],
            "outputConfig": config,
            "inferenceConfig": {"maxTokens": 16000},
            "additionalModelRequestFields": {"thinking": {"type": "adaptive"},
                                             "output_config": {"effort": "high"}}}
    offline = boto3.Session(aws_access_key_id="offline", aws_secret_access_key="offline",
                            region_name="us-east-1").client("bedrock-runtime", endpoint_url=ENDPOINT)
    validate_parameters(wire, offline.meta.service_model.operation_model("Converse").input_shape)
    pins = {"goal_sha256": PROVISIONAL_GOAL_SHA256,
            "scope_sha256": PROVISIONAL_SCOPE_SHA256,
            "request_sha256": file_hash(REQUEST_FIXTURE),
            "normalized_request_sha256": digest(request),
            "native_contract_name": name,
            "system_prompt_sha256": hashlib.sha256(system.encode()).hexdigest(),
            "user_prompt_sha256": hashlib.sha256(user.encode()).hexdigest(),
            "native_schema_bytes": len(schema.encode()),
            "native_schema_sha256": hashlib.sha256(schema.encode()).hexdigest(),
            "native_config_sha256": digest(config),
            "exact_author_wire_sha256": digest(wire)}
    require(pins["native_contract_name"] == author_plan["author_contract"]
            and pins["native_schema_bytes"] == author_plan["current_schema_bytes"] == 2357
            and pins["native_schema_sha256"] == author_plan["current_schema_sha256"]
            and pins["system_prompt_sha256"] == author_plan["system_prompt_sha256"]
            and pins["user_prompt_sha256"] == author_plan["user_prompt_sha256"]
            and pins["exact_author_wire_sha256"] == author_plan["wire_sha256"]
            == "0317c2b75115c309232c02e6eddcedd230461fc63f5d18da7312502868092a0a",
            "The v12 author schema, prompts, or wire drifted.")
    contracts = [contract,
                 *[kind(count) for kind in (native.SolverSlotContract,
                                           native.AuthoredSolutionFlagReviewContract)
                    for count in range(1, 6)]]
    paths = [*modules, SERVICE / "requirements.txt", SERVICE / "template.yaml",
             HELPER, REQUEST_FIXTURE, HERE / "README.md", HERE / "full_worker_probe.py",
             HERE / "test_full_worker_probe.py", V12_AUTHOR_PLAN,
             V12_AUTHOR_CAPTURE, PREVIOUS_WORKER_CAPTURE,
             PREVIOUS_V12_WORKER_CAPTURE, PREVIOUS_V12_WORKER_RESULTS,
             SECOND_V12_WORKER_CAPTURE, SECOND_V12_WORKER_RESULTS,
             IMMEDIATE_PREDECESSOR_CAPTURE, IMMEDIATE_PREDECESSOR_RESULTS]
    require(all(path.is_file() for path in paths), "A frozen source or test file is absent.")
    return {"state": "draft_offline_ready", "trial_id": TRIAL_ID,
            "source_commit": SOURCE_COMMIT,
            "qualification_ready": False,
            "predecessor_hashes": {"v12_author_plan": V12_AUTHOR_PLAN_SHA256,
                                   "v12_author_capture": V12_AUTHOR_CAPTURE_SHA256,
                                   "v9_worker_capture": PREVIOUS_WORKER_CAPTURE_SHA256,
                                   "previous_v12_worker_capture": PREVIOUS_V12_WORKER_CAPTURE_SHA256,
                                   "previous_v12_worker_results": PREVIOUS_V12_WORKER_RESULTS_SHA256,
                                   "previous_v12_worker_returned_questions": 4,
                                   "second_v12_worker_capture": SECOND_V12_WORKER_CAPTURE_SHA256,
                                   "second_v12_worker_results": SECOND_V12_WORKER_RESULTS_SHA256,
                                   "second_v12_worker_returned_questions": 4,
                                   "immediate_predecessor_capture": IMMEDIATE_PREDECESSOR_CAPTURE_SHA256,
                                   "immediate_predecessor_results": IMMEDIATE_PREDECESSOR_RESULTS_SHA256,
                                   "immediate_predecessor_returned_questions": 4},
            "candidate_pins": pins,
            "source_root": str(SERVICE),
            "source_hashes": {str(path.relative_to(ROOT)): file_hash(path)
                              for path in sorted(set(paths))},
            "harness_sha256": IMPORTED_HARNESS_HASH,
            "jobs": [{"id": "mixed", "request": request}],
            "environment": copy.deepcopy(ENVIRONMENT),
            "limits": copy.deepcopy(LIMITS),
            "model_and_transport": {"author_model": AUTHOR_MODEL,
                                    "verification_model": ENVIRONMENT["BEDROCK_VERIFICATION_MODEL_ID"],
                                    "fallback_model": "", "bedrock_endpoint": ENDPOINT,
                                    "sts_endpoint": STS_ENDPOINT, "region": "us-east-1",
                                    "required_boto3_version": REQUIRED_BOTO3_VERSION,
                                    "required_botocore_version": REQUIRED_BOTOCORE_VERSION,
                                    "required_awscrt_version": REQUIRED_AWSCRT_VERSION,
                                    "aws_cli_version": EXPECTED_AWS_CLI_VERSION,
                                    "account": EXPECTED_ACCOUNT_ID},
            "identity": {"profile": EXPECTED_PROFILE,
                         "account": EXPECTED_ACCOUNT_ID,
                         "sts_endpoint": STS_ENDPOINT,
                         "minimum_credential_lifetime_seconds": MIN_CREDENTIAL_LIFETIME_SECONDS},
            "mapped_assignment": {"scope_json": runtime._mapped_author_scope_json(request),
                                  "assignments": [list(item) for item in contract.mapped_assignments],
                                  "quantitative_skill_id": contract.mapped_quantitative_skill_id,
                                  "quantitative_difficulty": contract.mapped_quantitative_difficulty,
                                  "agreement_tasks": True,
                                  "quantitative_families": True},
            "initial_author_contract_name": name,
            "contracts": {native.contract_metadata(item)["name"]:
                          native.native_output_config(item) for item in contracts},
            "initial_author_prompts": [{"system": system, "user": user}],
            "initial_author_wire": wire,
            "criteria": {"original_slots_returned": 5,
                         "arithmetic_compiled_policy_8": 3,
                         "agreement_compiled_policy_10": 2,
                         "agreement_reviewer_difficulty_allowed": [2, 3],
                         "requested_skill_allocation_exact": True,
                         "every_key_matches_independent_solution": True,
                         "all_six_choice_pairs_judged_per_item": True,
                         "teaching_sound_and_complete": True,
                         "execute_origin_total_seconds_at_most_240": True,
                         "credential_export_and_execute_sts_in_deadline": True,
                         "sts_identity_requests_preflight_execute_total": [1, 1, 2],
                         "deadline_and_call_budget_satisfied": True,
                         "unresolved_content_uncertainty": 0},
            "launch_precheck": {"status": "pending_independent_harness_review",
                                "minimum_exported_lifetime_seconds": LAUNCH_PRECHECK_MINIMUM_SECONDS,
                                "minimum_remaining_to_launch_seconds": LAUNCH_WINDOW_MINIMUM_SECONDS,
                                "minimum_execute_snapshot_seconds": MIN_CREDENTIAL_LIFETIME_SECONDS}}


def check_plan(plan, path=None, expected_hash=None):
    require(type(plan) is dict and plan.get("state") in {"draft_offline_ready", "frozen"}
            and {**plan, "state": "draft_offline_ready"} == build_plan()
            and plan["qualification_ready"] is False,
            "Reviewed offline source or plan drift.")
    if path is not None:
        require(file_hash(path) == expected_hash, "Plan bytes changed.")


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
        return max(0, int((EXECUTE_SECONDS - (self.clock() - self.started)) * 1000))


def run_job(job, capture, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic,
            deadline=None, credential_expires_at=None,
            credential_clock=lambda: datetime.now(timezone.utc)):
    deadline = Deadline(clock) if deadline is None else deadline
    require(deadline.get_remaining_time_in_millis() > 0,
            "Execute deadline elapsed before provider job.")
    original_job = next(item for item in capture["original_jobs"] if item["id"] == job["id"])
    require(original_job["status"] == "unattempted", "Original job was already attempted.")
    original_job["status"] = "running"
    row = {"id": job["id"], "status": "running", "returned": [], "passes": [],
           "metrics": {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}}
    capture["jobs"].append(row)
    budget = runtime.ProviderCallBudget(6, context=deadline)
    stage_context, sources, agreement_sources, accepted_objects = {}, {}, {}, {}
    author_stages = 0
    original_stage, original_prepare, original_sanitize = (
        runtime._generate_with_bedrock, runtime.prepare_mapped_agreement_rows,
        runtime._sanitize_questions,
    )
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
        guard(len(capture["reservations"]) < 6, "Global reservation ceiling.")
        call_slot = next(item for item in capture["call_slots"]
                         if item["job"] == job["id"] and item["ordinal"] == budget.calls)
        guard(call_slot["status"] == "unattempted", "Original call slot was already reserved.")
        call_slot["status"] = "reserved"
        capture["reservations"].append({"job": job["id"], "ordinal": budget.calls})
        save(path, capture)

    budget.reserve_call = DurableProviderCallReservation(reserve, 6)

    def stage(*args, **kwargs):
        nonlocal author_stages
        try:
            guard(not capture.get("global_stop"), "Global dispatch already stopped.")
            contract = kwargs.get("contract")
            name = native.contract_metadata(contract)["name"]
            guard(name in capture["plan"]["contracts"], "Unplanned native contract.")
            current_request = kwargs["normalized_request"]
            author = isinstance(contract, native.AuthorSlotContract) and contract.mapped_assignments is not None
            if author:
                guard(job["id"] == "mixed", "Author contract escaped the assigned mixed route.")
                guard(author_stages == 0 and current_request == job["request"],
                      "A second mapped author pass or changed assignment was attempted.")
                expected = mapped_contract(current_request)
                guard(contract == expected and contract.mapped_agreement_tasks
                      and name == capture["plan"]["initial_author_contract_name"],
                      "Actual compact author contract differs from the frozen assignment.")
                author_stages += 1
            if not capture["calls"]:
                guard(author, "First provider stage is not the planned mixed author.")
            system = kwargs.get("system_prompt") or runtime._system_prompt()
            prompt = kwargs.get("user_prompt") or runtime._user_prompt(kwargs["normalized_request"])
            stage_context.clear()
            stage_context.update(name=name, author=author, system=native.native_prompt(system, contract), prompt=prompt,
                                 output_config=native.native_output_config(contract))
            if author:
                first = capture["plan"]["initial_author_prompts"][
                    next(index for index, planned in enumerate(capture["plan"]["jobs"])
                         if planned["id"] == job["id"])]
                guard({"system": stage_context["system"], "user": prompt} == first,
                      "Actual first author prompt differs from frozen plan.")
        except Exception:
            capture["global_stop"] = "stage_configuration_integrity"
            raise
        try:
            return original_stage(*args, **kwargs)
        except ServiceConfigurationError:
            # A native schema/configuration failure stops this one-pass trial.
            capture["global_stop"] = "native_stage_configuration"
            raise

    def prepare(payload, contract, **kwargs):
        guard(contract == mapped_contract(job["request"]),
              "Agreement compiler lost the trusted five-slot contract.")
        raw, compiled, agreement, failures = original_prepare(payload, contract, **kwargs)
        guard(type(payload) is dict and type(payload.get("questions")) is list
              and len(payload["questions"]) == 5,
              "Adapted agreement author payload lost an original slot.")
        record = {"ordinal": len(row["passes"]), "author_payload": copy.deepcopy(payload),
                  "prepared": copy.deepcopy(raw), "compiled": [], "agreement": [], "sanitized": [],
                  "original_slot_assignments": copy.deepcopy(capture["plan"]["mapped_assignment"]),
                  "provider_schema_sha256": capture["plan"]["candidate_pins"]["native_schema_sha256"]}
        row["passes"].append(record)
        for index, provenance in compiled.items():
            source = {"source": [job["id"], record["ordinal"], index],
                      "spec": json.loads(provenance.spec_json), "learner": provenance.content()}
            sources[id(provenance)] = source
            record["compiled"].append(copy.deepcopy(source))
        for index, provenance in agreement.items():
            guard(index in (3, 4) and provenance.ordinal == index,
                  "Agreement proof lost original English slot.")
            source = {"source": [job["id"], record["ordinal"], index],
                      "task": json.loads(provenance.task_json),
                      "learner": learner(provenance.content())}
            agreement_sources[id(provenance)] = source
            record["agreement"].append(copy.deepcopy(source))
        record["compiler_rejections"] = failures
        return raw, compiled, agreement, failures

    def sanitize(*args, **kwargs):
        result = original_sanitize(*args, **kwargs)
        record = row["passes"][-1]
        for index, question in enumerate(result):
            provenance = kwargs.get("compiled_output", {}).get(index)
            agreement = kwargs.get("agreement_output", {}).get(index)
            guard(not (provenance is not None and agreement is not None),
                  "Candidate has two private proof types.")
            item = {"index": index, "source": [job["id"], record["ordinal"], index],
                    "source_stage": "sanitized", "question": copy.deepcopy(question)}
            if provenance is not None:
                guard(id(provenance) in sources, "Compiler provenance has no author source.")
                provenance.content(question)
                item["compiled_source"] = copy.deepcopy(sources[id(provenance)])
                item["original_slot_ordinals"] = [sources[id(provenance)]["source"][2]]
            elif agreement is not None:
                guard(id(agreement) in agreement_sources,
                      "Agreement proof has no original author source.")
                agreement.content(question)
                item["agreement_source"] = copy.deepcopy(agreement_sources[id(agreement)])
                item["original_slot_ordinals"] = [agreement.ordinal]
            else:
                guard(False, "Agreement route produced an unproved learner question.")
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
            agreement_source = copy.deepcopy(item.get("agreement_source"))
            if source is not None:
                guard(question.get("verificationPolicyRevision") == 8 and learner(question) == source["learner"],
                      "Compiled release changed exact five fields or provenance.")
            else:
                guard(agreement_source is not None
                      and question.get("verificationPolicyRevision") == 10
                      and learner(question) == agreement_source["learner"],
                      "Agreement release changed code-owned learner fields or policy.")
            entry = {"source": copy.deepcopy(item["source"]),
                     "compiled_source": source, "agreement_source": agreement_source,
                     "original_slot_ordinals": copy.deepcopy(item["original_slot_ordinals"]),
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
                    and cfg.connect_timeout == 3 and 2 <= cfg.read_timeout <= 200
                    and cfg.retries.get("total_max_attempts") == 1, "Unplanned transport.")
            guard(len(capture["calls"]) < 6 and budget.calls <= 6
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
                    "remaining_before_ms": budget.remaining_milliseconds(), "dispatch_attempted": None}
            if author:
                schema_text = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"]
                call["native_schema_sha256"] = hashlib.sha256(schema_text.encode()).hexdigest()
                guard(call["native_schema_sha256"] == capture["plan"]["candidate_pins"]["native_schema_sha256"],
                      "Author schema hash differs from frozen first-pass pin.")
                call["trusted_original_slot_bindings"] = original_slot_bindings(capture["plan"])
            call_slot = next(item for item in capture["call_slots"]
                             if item["job"] == job["id"] and item["ordinal"] == budget.calls - 1)
            guard(call_slot["status"] == "reserved", "Dispatch lacks its original reserved slot.")
            call_slot["status"] = "request_saved"
            capture["calls"].append(call)
            save(path, capture)
            started = clock()
            try:
                pins()
                minimum = runtime._minimum_provider_remaining_milliseconds(
                    connect_timeout=cfg.connect_timeout, read_timeout=cfg.read_timeout)
                if budget.remaining_milliseconds() < minimum:
                    raise runtime.ProviderDeadlineExceededError(
                        "Insufficient request time after capture persistence.")
                if credential_expires_at is not None:
                    credential_remaining_ms = int((credential_expires_at - credential_clock()).total_seconds() * 1000)
                    call["credential_remaining_before_ms"] = max(0, credential_remaining_ms)
                    guard(credential_remaining_ms >= minimum,
                          "Credential snapshot expires before this provider request can complete.")
                call["dispatch_attempted"] = True
                call_slot["status"] = "dispatch_attempted"
                save(path, capture)
                response = self.client.converse(**request)
                retained, omitted = safe.safe_response(response, secrets)
                retained.pop("safeResponseMetadata", None)
                visible = json.dumps(retained, ensure_ascii=False)
                guard(not any(secret and secret in visible for secret in secrets), "Credential echo in visible output.")
                guard(not decoded_credential_echo(response, secrets), "Credential echo in decoded native output.")
                if author:
                    raw_text = "\n".join(block["text"] for block in retained["output"]["message"]["content"]).strip()
                    call["raw_author_text_sha256"] = hashlib.sha256(raw_text.encode()).hexdigest()
                    try:
                        raw_object = safe.strict_json(raw_text)
                    except (ValueError, TypeError, RecursionError):
                        call["raw_author_object_status"] = "invalid_json"
                    else:
                        call["raw_author_object"] = raw_object
                        call["raw_author_object_status"] = "captured_before_adapter"
                call.update(response=retained, reasoning_blocks_omitted=omitted)
                call_slot["status"] = "completed"
                return response
            except Exception as error:
                call["error"] = safe_error_identity(error, secrets)
                if call["dispatch_attempted"] is None:
                    call["dispatch_attempted"] = False
                    call_slot["status"] = "deadline_blocked" if isinstance(
                        error, runtime.ProviderDeadlineExceededError) else "failed_before_dispatch"
                else:
                    call_slot["status"] = "failed_after_dispatch"
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
                patch.object(runtime, "_generate_with_bedrock", stage), patch.object(runtime, "prepare_mapped_agreement_rows", prepare), \
                patch.object(runtime, "_sanitize_questions", sanitize), patch.object(runtime, "verify_questions", verify):
            returned = runtime._generate_sanitized_questions(copy.deepcopy(job["request"]), None, budget, row["metrics"])
        provenance, returned_sources, returned_slot_ordinals = [], [], []
        for question in returned:
            observed = accepted_objects.get(id(question))
            guard(observed is not None and observed[0] is question and observed[1]["question"] == question,
                  "Runtime return lacks unchanged actual verifier-object identity.")
            slot_candidates = observed[1]["original_slot_ordinals"]
            guard(len(slot_candidates) == 1 and slot_candidates[0] not in returned_slot_ordinals
                  and 0 <= slot_candidates[0] < 5,
                  "Runtime return lacks one unique original-slot binding.")
            returned_slot_ordinals.append(slot_candidates[0])
            returned_sources.append(copy.deepcopy(observed[1]["source"]))
            provenance.append(copy.deepcopy(observed[1]["compiled_source"] or observed[1]["agreement_source"]))
        if len(returned) == 5:
            guard(set(returned_slot_ordinals) == set(range(5)),
                  "Full return does not cover all five original provider slots.")
        row.update(returned=returned, returned_provenance=provenance,
                   returned_sources=returned_sources, returned_slot_ordinals=returned_slot_ordinals,
                   status="finished")
    except Exception as error:
        row.update(status="failed", error=safe_error_identity(error, secrets))
        if isinstance(error, (IntegrityError, safe.CaptureBoundaryError)) or setup_failure(error) or not isinstance(error, (ProviderError, SafetyInterventionError)):
            capture["global_stop"] = "setup_or_integrity_failure"
    finally:
        raw_elapsed = clock() - deadline.started
        row.update(elapsed_seconds=round(raw_elapsed, 6), provider_calls=budget.calls,
                   remaining_ms=budget.remaining_milliseconds())
        row["within_deadline"] = raw_elapsed <= 240
        original_job["status"] = row["status"]
        returned_by_slot = set(row.get("returned_slot_ordinals", []))
        for index, slot in enumerate(original_job["slots"]):
            slot["status"] = ("returned" if index in returned_by_slot and row["within_deadline"]
                              else "late_uncredited" if index in returned_by_slot
                              else "unfilled")
        pins()
        save(path, capture)


def run_jobs(plan, capture, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic,
             deadline=None, credential_expires_at=None,
             credential_clock=lambda: datetime.now(timezone.utc)):
    require(not capture["calls"] and not capture["jobs"], "No resume or repeat.")
    require(len(capture["original_jobs"]) == 1 and len(capture["call_slots"]) == 6,
            "Original job or call slots were not materialized.")
    deadline = Deadline(clock) if deadline is None else deadline
    require(deadline.get_remaining_time_in_millis() > 0,
            "Execute deadline elapsed during credential or identity setup.")
    for job in plan["jobs"]:
        if capture.get("global_stop"):
            break
        run_job(job, capture, path, client_factory, pin_check, secrets=secrets, clock=clock,
                deadline=deadline,
                credential_expires_at=credential_expires_at, credential_clock=credential_clock)
    pin_check()
    finish(capture)
    save(path, capture)


def finish(capture):
    capture["summary"] = {"planned_jobs": len(capture["original_jobs"]), "planned_questions": 5,
                          "attempted_jobs": len(capture["jobs"]),
                          "unattempted_jobs": sum(job["status"] == "unattempted" for job in capture["original_jobs"]),
                          "reserved_calls": len(capture["reservations"]),
                          "attempted_calls": sum(call.get("dispatch_attempted") is True for call in capture["calls"]),
                          "unattempted_call_slots": sum(slot["status"] == "unattempted" for slot in capture["call_slots"]),
                          "returned_questions": sum(len(row["returned"]) for row in capture["jobs"] if row["within_deadline"]),
                          "independent_content_review": "pending", "qualified": False}
    usages = [call.get("response", {}).get("usage", {}) for call in capture["calls"]]
    capture["summary"]["reported_token_usage"] = {
        "input_tokens": sum(usage.get("inputTokens", 0) for usage in usages),
        "output_tokens": sum(usage.get("outputTokens", 0) for usage in usages),
        "calls_without_reported_usage": sum(not usage for usage in usages), "missing_usage_is_not_zero": True}
    capture["status"] = "globally_aborted" if capture.get("global_stop") else "completed_pending_review"


def seal_execute_timing(capture, deadline):
    """Credit returned slots only if the entire execute phase met 240 seconds."""
    raw_elapsed = deadline.clock() - deadline.started
    within = raw_elapsed <= EXECUTE_SECONDS and capture.get("global_stop") != "execute_deadline"
    capture["summary"]["execute_elapsed_seconds"] = round(raw_elapsed, 6)
    capture["summary"]["within_execute_deadline"] = within
    capture["summary"]["deadline_origin"] = LIMITS["deadline_origin"]
    if not within:
        capture["status"] = "deadline_exceeded"
        capture["global_stop"] = "execute_deadline"
        capture["summary"]["returned_questions"] = 0
        for job in capture["original_jobs"]:
            for slot in job["slots"]:
                if slot["status"] == "returned":
                    slot["status"] = "late_uncredited"


def preflight():
    """Run the harness's socket-free fake full-worker tests and schema checks."""
    build_plan()
    result = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", str(HERE),
                             "-p", "test_*.py", "-q"],
                            capture_output=True, text=True)
    require(result.returncode == 0, "Offline tests failed: " + result.stderr)
    return {"provider_calls": 0, "result": "passed", "output": result.stderr.strip()}


def require_review_go(expected_plan_sha):
    """A separate lock prevents accidental AWS launch before two reviews."""
    require(REVIEW_LOCK.is_file() and REVIEW_LOCK.stat().st_size <= 4096,
            "Exact frozen plan awaits root and independent review.")
    record = safe.strict_json(REVIEW_LOCK.read_text())
    require(type(record) is dict and set(record) == {
        "plan_sha256", "harness_sha256", "source_commit", "root_go", "independent_go"}
        and record["plan_sha256"] == expected_plan_sha
        and record["harness_sha256"] == IMPORTED_HARNESS_HASH
        and record["source_commit"] == SOURCE_COMMIT
        and record["root_go"] is True and record["independent_go"] is True,
        "Review lock does not approve this frozen plan and harness.")

def check_launch_record(plan, *, now=None):
    """Reject a stale or unrelated pretrial refresh before freeze or capture."""
    require(LAUNCH_ATTEMPT.is_file() and LAUNCH_ATTEMPT.stat().st_size <= 8192
            and LAUNCH_PRECHECK.is_file() and LAUNCH_PRECHECK.stat().st_size <= 8192,
            "No bounded launch freshness record exists.")
    try:
        attempt = safe.strict_json(LAUNCH_ATTEMPT.read_text())
        record = safe.strict_json(LAUNCH_PRECHECK.read_text())
        require(type(attempt) is dict and set(attempt) == {
            "status", "draft_digest", "started_at", "maximum_sts_requests", "provider_calls"},
            "Launch precheck attempt shape changed.")
        require(type(record) is dict and set(record) == {
            "status", "draft_digest", "checked_at", "credential_expires_at",
            "credential_lifetime_seconds", "account", "pretrial_sts_requests",
            "botocore_signin_refresh_operations", "cli_signin_refresh_operations",
            "pretrial_aws_operations_budget", "provider_calls"},
            "Launch freshness record shape changed.")
        checked_at = datetime.fromisoformat(record["checked_at"].replace("Z", "+00:00"))
        expires_at = datetime.fromisoformat(record["credential_expires_at"].replace("Z", "+00:00"))
        require(checked_at.tzinfo is not None and expires_at.tzinfo is not None,
                "Launch freshness timestamps have no timezone.")
    except (OSError, UnicodeError, ValueError, TypeError, AttributeError, KeyError, OverflowError):
        raise IntegrityError("Launch freshness record is malformed.") from None
    draft = {**plan, "state": "draft_offline_ready"}
    require(attempt["status"] == "started" and attempt["draft_digest"] == digest(draft)
            and attempt["maximum_sts_requests"] == 1 and attempt["provider_calls"] == 0
            and record["status"] == "passed" and record["draft_digest"] == digest(draft)
            and record["account"] == EXPECTED_ACCOUNT_ID
            and record["pretrial_sts_requests"] == 1 and record["provider_calls"] == 0
            and type(record["botocore_signin_refresh_operations"]) is int
            and 0 <= record["botocore_signin_refresh_operations"] <= 1
            and record["cli_signin_refresh_operations"] == "unobserved; bounded 0-1"
            and record["pretrial_aws_operations_budget"] == 3
            and type(record["credential_lifetime_seconds"]) is int
            and record["credential_lifetime_seconds"] >= LAUNCH_PRECHECK_MINIMUM_SECONDS
            and record["credential_lifetime_seconds"] == int((expires_at - checked_at).total_seconds()),
            "Launch freshness record does not match the reviewed trial.")
    current = datetime.now(timezone.utc) if now is None else now
    require((expires_at - current).total_seconds() >= LAUNCH_WINDOW_MINIMUM_SECONDS,
            "Pretrial credential freshness window closed before launch.")
    return record


def launch_precheck():
    """One explicit pretrial STS refresh and metadata-only credential check."""
    require(PLAN.is_file() and PLAN.stat().st_size <= 8 * 1024 * 1024,
            "Frozen plan is missing.")
    plan = safe.strict_json(PLAN.read_text())
    require(plan.get("state") == "frozen", "Plan is not frozen.")
    plan_sha = file_hash(PLAN)
    check_plan(plan, PLAN, plan_sha)
    require_review_go(plan_sha)
    check_execution_runtime()
    draft = {**plan, "state": "draft_offline_ready"}
    require(not LAUNCH_ATTEMPT.exists() and not LAUNCH_PRECHECK.exists()
            and not CAPTURE.exists(),
            "A launch precheck or trial artifact already exists.")
    validate_identity_environment()
    check_default_profile()
    check_aws_cli()
    save(LAUNCH_ATTEMPT, {"status": "started", "draft_digest": digest(draft),
                          "started_at": datetime.now(timezone.utc).isoformat(),
                          "maximum_sts_requests": 1, "provider_calls": 0}, exclusive=True)
    signin_refresh_operations = []

    def before_signin_refresh(**_):
        require(not signin_refresh_operations, "Pretrial Signin refresh call ceiling exceeded.")
        signin_refresh_operations.append(1)

    with patch.dict(os.environ, controlled_cli_environment(), clear=True):
        profile_session = boto3.Session(profile_name=EXPECTED_PROFILE, region_name="us-east-1")
        profile_session.events.register("before-call.signin.CreateOAuth2Token", before_signin_refresh)
        identity = checked_sts_client(profile_session).get_caller_identity()
    require(type(identity) is dict and identity.get("Account") == EXPECTED_ACCOUNT_ID,
            "Pretrial AWS account differs from the frozen intended account.")
    _, _, expires_at = default_profile_session()
    checked_at = datetime.now(timezone.utc)
    lifetime = int((expires_at - checked_at).total_seconds())
    require(lifetime >= LAUNCH_PRECHECK_MINIMUM_SECONDS,
            "Pretrial credential snapshot is not fresh enough for launch.")
    record = {"status": "passed", "draft_digest": digest(draft), "checked_at": checked_at.isoformat(),
              "credential_expires_at": expires_at.isoformat(),
              "credential_lifetime_seconds": lifetime, "account": EXPECTED_ACCOUNT_ID,
              "pretrial_sts_requests": 1,
              "botocore_signin_refresh_operations": len(signin_refresh_operations),
              "cli_signin_refresh_operations": "unobserved; bounded 0-1",
              "pretrial_aws_operations_budget": 3, "provider_calls": 0}
    save(LAUNCH_PRECHECK, record, exclusive=True)
    return record


def freeze(reviewed_digest):
    require(not PLAN.exists() and not CAPTURE.exists()
            and not LAUNCH_ATTEMPT.exists() and not LAUNCH_PRECHECK.exists(),
            "Trial plan, freshness record or capture already exists.")
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
    require_review_go(expected_hash)
    check_execution_runtime()
    check_launch_record(plan)
    deadline = Deadline(time.monotonic)
    capture = new_capture(plan, expected_hash)
    save(CAPTURE, capture, exclusive=True)
    secrets = ()
    old_alarm = signal.getsignal(signal.SIGALRM)
    try:
        signal.signal(signal.SIGALRM, deadline_alarm)
        remaining = EXECUTE_SECONDS - (deadline.clock() - deadline.started)
        require(remaining > 0, "Execute deadline elapsed before credential export.")
        signal.setitimer(signal.ITIMER_REAL, remaining)
        require(deadline.get_remaining_time_in_millis() > 0,
                "Execute deadline elapsed before credential export.")
        session, secrets, credential_expires_at = default_profile_session()
        require(deadline.get_remaining_time_in_millis() >= 13_000,
                "Execute deadline cannot cover the 3+10 second STS timeout.")
        verify_account_identity(session, capture, CAPTURE, deadline=deadline)
        run_jobs(plan, capture, CAPTURE, session.client, lambda: check_plan(plan, PLAN, expected_hash),
                 secrets=secrets, deadline=deadline,
                 credential_expires_at=credential_expires_at)
    except WholeDeadlineExceeded:
        capture.update(status="deadline_exceeded", global_stop="execute_deadline",
                       error={"type": "WholeDeadlineExceeded", "code": "whole_execute_deadline"})
        finish(capture)
        save(CAPTURE, capture)
    except BaseException as error:
        capture.update(status="globally_aborted", global_stop="setup_or_interruption",
                       error=safe_error_identity(error, secrets))
        finish(capture)
        save(CAPTURE, capture)
        if isinstance(error, (SystemExit, KeyboardInterrupt)):
            raise
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old_alarm)
        if "summary" in capture:
            seal_execute_timing(capture, deadline)
            save(CAPTURE, capture)
    return {"capture": str(CAPTURE), "status": capture["status"], "summary": capture.get("summary")}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--draft", action="store_true")
    group.add_argument("--preflight", action="store_true")
    group.add_argument("--launch-precheck", action="store_true")
    group.add_argument("--freeze")
    group.add_argument("--execute")
    args = parser.parse_args()
    result = ({"draft_digest": digest(build_plan()), "plan": build_plan()} if args.draft else preflight() if args.preflight
              else launch_precheck() if args.launch_precheck else freeze(args.freeze) if args.freeze
              else execute(args.execute))
    print(json.dumps(result, ensure_ascii=True, indent=2))
