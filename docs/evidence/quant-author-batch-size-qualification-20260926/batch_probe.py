"""One-shot numerical batch pilot; import and preflight make no provider calls."""

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
import subprocess
import sys
import time
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = (ROOT / "backend/bedrock-question-service").resolve()
DRAFT_SPEC = HERE / "plan-draft.json"
IMPORTED_DRAFT_SHA256 = hashlib.sha256(DRAFT_SPEC.read_bytes()).hexdigest()
DRAFT_DATA = json.loads(DRAFT_SPEC.read_text())
ORIGINAL_JOBS = HERE / "jobs-draft.json"
PRIOR_PLAN = ROOT / "docs/evidence/current-source-worker-successor-qualification-20260926/plan.json"
SOURCE_COMMIT = "53f7628f70393239b06ff2f5df380414aad36c88"
FIRST_REQUEST_SHA256 = "99c752418a6ee1905e243df3f0c415ee967465ad071491bb47763686538c5a7a"
FIRST_USER_SHA256 = "99b00c938fdca7ae78a74f325af944190e91dc5fc0c2e55fc76da51bf5fceef6"
FIRST_SYSTEM_SHA256 = "97cc29315d5119c55474f15acca4a62fad098ad6f5d9a54e4447c696836ee5c3"
AUTHOR_SCHEMA_SHA256 = "503d06557b7e1a9f6d0215cf2c4768917decdcbbdc7abe0fc13c89bddb979f15"
IMPORTED_SERVICE_HASHES = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(SERVICE.glob("*.py"))}
sys.path.insert(0, str(SERVICE))

import awscrt  # noqa: E402
import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402
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
STS_ENDPOINT = "https://sts.us-east-1.amazonaws.com"
EXPECTED_ACCOUNT_ID = "239342516379"
EXPECTED_PROFILE = "default"
EXPECTED_AWS_CLI_VERSION = "2.33.15"
AWS_CLI_PATH = Path(shutil.which("aws") or "/__missing_aws_cli__/aws").resolve()
MIN_CREDENTIAL_LIFETIME_SECONDS = 780
LAUNCH_PRECHECK_MINIMUM_SECONDS = 840
LAUNCH_WINDOW_MINIMUM_SECONDS = 810
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
ENVIRONMENT = copy.deepcopy(DRAFT_DATA["trial_environment"])
AUTHOR_MODEL = ENVIRONMENT["BEDROCK_MODEL_ID"]
LIMITS = copy.deepcopy(DRAFT_DATA["limits"])
PLAN, CAPTURE = HERE / "plan.json", HERE / "capture.json"
LAUNCH_PRECHECK = HERE / "launch-precheck.json"
LAUNCH_ATTEMPT = HERE / "launch-precheck-attempt.json"
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
    """Materialize all original job, question and call slots before credentials."""
    require(len(plan["jobs"]) == 1 and plan["jobs"][0]["id"] == "quantitative"
            and plan["jobs"][0]["request"]["targetCount"] == 5,
            "Original five-slot numerical assignment changed.")
    original_jobs = [{"id": job["id"], "status": "unattempted",
                      "slots": [{"ordinal": index, "status": "unattempted"} for index in range(5)]}
                     for job in plan["jobs"]]
    call_slots = [{"job": job["id"], "ordinal": index, "status": "unattempted"}
                  for job in plan["jobs"] for index in range(6)]
    return {"plan": copy.deepcopy(plan), "plan_sha256": plan_sha256, "calls": [], "jobs": [],
            "original_jobs": original_jobs, "call_slots": call_slots, "reservations": [],
            "identity_check": {"profile": EXPECTED_PROFILE, "account": EXPECTED_ACCOUNT_ID,
                               "endpoint": STS_ENDPOINT, "status": "unattempted"},
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
    """Require one exported snapshot to outlive all three 240-second jobs."""
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


def verify_account_identity(session, capture, path):
    """Check the exact STS endpoint before any signed identity request."""
    validate_identity_environment()
    client = checked_sts_client(session)
    capture["identity_check"]["status"] = "endpoint_validated"
    save(path, capture)
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
    """Bind every current-source and prior-evidence byte in the reviewed draft."""
    require(file_hash(DRAFT_SPEC) == IMPORTED_DRAFT_SHA256, "Reviewed draft changed after import.")
    spec = safe.strict_json(DRAFT_SPEC.read_text())
    require(spec["state"] == "draft_unfrozen_offline_only" and spec["source_commit"] == SOURCE_COMMIT,
            "Unexpected current-source draft revision.")
    require(len(modules) == 29 and {path.name for path in modules} == set(IMPORTED_SERVICE_HASHES),
            "Current runtime module set changed.")
    require({path.name: file_hash(path) for path in modules} == IMPORTED_SERVICE_HASHES,
            "Imported runtime source changed.")
    require(len(spec["source_hashes"]) == 32, "Current source pin count changed.")
    for relative, expected in spec["source_hashes"].items():
        require(file_hash(ROOT / relative) == expected, "Current source pin changed: " + relative)
    for relative, expected in spec["prior_failed_full_worker_evidence_sha256"].items():
        require(file_hash(ROOT / relative) == expected, "Prior evidence pin changed: " + relative)
    require(len(spec["preflight_artifact_sha256"]) == 4, "Preflight artifact pin count changed.")
    for relative, expected in spec["preflight_artifact_sha256"].items():
        require(file_hash(ROOT / relative) == expected, "Preflight artifact pin changed: " + relative)
    return spec


def build_plan():
    require(file_hash(HELPER) == IMPORTED_HELPER_HASH, "Capture helper changed after import.")
    require(Path(runtime.__file__).resolve().parent == SERVICE, "Wrong current runtime imported.")
    modules = sorted(SERVICE.glob("*.py"))
    spec = check_current_source(modules)
    for path in modules:
        loaded = sys.modules.get(path.stem)
        if loaded is not None:
            require(Path(getattr(loaded, "__file__", "")).resolve() == path,
                    "A service module came from another checkout.")
    require(file_hash(HERE / "jobs-draft.json") == spec["fixed_jobs_source_sha256"]
            and file_hash(ORIGINAL_JOBS) == spec["fixed_jobs_source_sha256"],
            "Fixed job bytes changed.")
    jobs = safe.strict_json((HERE / "jobs-draft.json").read_text())["jobs"]
    require(jobs == spec["fixed_jobs"] and [job["id"] for job in jobs] == ["quantitative"]
            and all(job["request"]["targetCount"] == 5 for job in jobs), "Fixed jobs changed.")
    prior = safe.strict_json(PRIOR_PLAN.read_text())
    require(jobs[0] == prior["jobs"][0], "Numerical request differs from the pinned prior trial.")
    require(ENVIRONMENT == spec["trial_environment"] and LIMITS == spec["limits"]
            and ENVIRONMENT["QUESTION_AUTHOR_CARDINALITY_CONTRACT"] == "array"
            and ENVIRONMENT["QUESTION_CONSTRUCTED_AUTHOR_BATCH_SIZE"] == "3",
            "Trial settings or count-bound separation changed.")
    require(ENVIRONMENT == {**prior["environment"], "QUESTION_CONSTRUCTED_AUTHOR_BATCH_SIZE": "3"},
            "Trial changed a prior environment value besides author batch size.")
    require(ENDPOINT == spec["endpoint"] and LIMITS["maximum_calls"] == 6
            and LIMITS["calls_per_job"] == 6 and LIMITS["seconds_per_job"] == 240,
            "Endpoint or hard budget changed.")
    require(spec["identity"] == {"profile": EXPECTED_PROFILE, "account": EXPECTED_ACCOUNT_ID,
                                 "sts_endpoint": STS_ENDPOINT,
                                 "aws_cli_version": EXPECTED_AWS_CLI_VERSION,
                                 "aws_cli_path": str(AWS_CLI_PATH),
                                 "cli_ignores_configured_endpoints": True,
                                 "minimum_credential_lifetime_seconds": MIN_CREDENTIAL_LIFETIME_SECONDS,
                                 "config_path": str(FROZEN_CONFIG_PATH),
                                 "config_sha256": FROZEN_CONFIG_SHA256,
                                 "default_profile_keys": sorted(FROZEN_PROFILE_KEYS),
                                 "login_session_sha256": FROZEN_LOGIN_SESSION_SHA256,
                                 "region": FROZEN_PROFILE_REGION,
                                 "shared_credentials_path": str(FROZEN_CREDENTIALS_PATH),
                                 "shared_credentials_default_section": "absent"},
            "Intended AWS identity or CLI changed.")
    require(spec["launch_precheck"] == {
        "path": "docs/evidence/quant-author-batch-size-qualification-20260926/launch-precheck.json",
        "attempt_path": "docs/evidence/quant-author-batch-size-qualification-20260926/launch-precheck-attempt.json",
        "pretrial_signed_sts_requests": 1, "pretrial_signin_operations_max": 2,
        "pretrial_aws_operations_max": 3, "model_calls": 0,
        "exported_snapshot_minimum_lifetime_seconds": LAUNCH_PRECHECK_MINIMUM_SECONDS,
        "minimum_remaining_before_freeze_and_execute_seconds": LAUNCH_WINDOW_MINIMUM_SECONDS,
        "execute_snapshot_minimum_lifetime_seconds": MIN_CREDENTIAL_LIFETIME_SECONDS,
        "provider_retry": "none",
        "scope": "one-shot separate pretrial refresh and metadata-only freshness proof; a durable attempt marker precedes at most one explicit STS request and no trial capture, model call or frozen plan is created by precheck",
    }, "Successor launch freshness policy changed.")
    require(spec["predecessor_setup_abort"] == {
        "plan_sha256": "2b5eef877b8c86280d88be14eeef0bb7a6e9940c8d3b829339ba1223b17bffbb",
        "capture_sha256": "5fa9ab811293d1f442317bb02f41eb66d900db912e31d4e4e7f39ed88a8d9f26",
        "sts_requests": 0, "bedrock_calls": 0, "attempted_jobs": 0,
        "unattempted_provider_slots": 18, "model_observations": 0,
    }, "Predecessor zero-model-call boundary changed.")
    check_default_profile()
    require(AWS_CLI_PATH.is_file() and os.access(AWS_CLI_PATH, os.X_OK),
            "Pinned AWS CLI executable is missing.")
    dependencies = {"python": sys.version.split()[0], "boto3": boto3.__version__,
                    "botocore": botocore.__version__, "awscrt": awscrt.__version__}
    required_environment = spec["offline_validation_environment"]
    require(dependencies == {"python": required_environment["python_version"],
                             "boto3": required_environment["boto3_version"],
                             "botocore": required_environment["botocore_version"],
                             "awscrt": required_environment["awscrt_version"]},
            "Pinned Python or AWS SDK dependency changed.")
    paths = [ROOT / relative for relative in [*spec["source_hashes"],
                                                *spec["prior_failed_full_worker_evidence_sha256"]]]
    paths += [HERE / name for name in ("batch_probe.py", "test_batch_probe.py", "PLAN.md",
                                       "jobs-draft.json", "plan-draft.json")]
    paths = sorted(set(paths))
    contracts = [CONSTRUCTED_AUTHOR_CONTRACT,
                 *[kind(count) for kind in (native.SolverSlotContract,
                                           native.AuthoredSolutionFlagReviewContract) for count in range(1, 6)]]
    with patch.dict(os.environ, ENVIRONMENT, clear=True):
        require(runtime._constructed_author_batch_size(jobs[0]["request"], "constructed_quantitative") == 3,
                "Candidate author batch cap is not active.")
        initial = [{"system": native.native_prompt(runtime._system_prompt(), CONSTRUCTED_AUTHOR_CONTRACT),
                    "user": runtime._user_prompt({**job["request"], "targetCount": 3})} for job in jobs]
    require(digest({**jobs[0]["request"], "targetCount": 3}) == FIRST_REQUEST_SHA256
            and hashlib.sha256(initial[0]["user"].encode()).hexdigest() == FIRST_USER_SHA256
            and hashlib.sha256(initial[0]["system"].encode()).hexdigest() == FIRST_SYSTEM_SHA256
            and digest(native.native_output_config(CONSTRUCTED_AUTHOR_CONTRACT)) == AUTHOR_SCHEMA_SHA256,
            "Frozen first author request, prompt, or schema drifted.")
    return {"state": "draft", "source_root": str(SERVICE),
            "source_revision": {"commit": SOURCE_COMMIT, "module_count": len(modules),
                                "boolean_guard_sha256": spec["source_hashes"]["backend/bedrock-question-service/python_boolean_teaching.py"]},
            "draft_spec_sha256": file_hash(DRAFT_SPEC), "jobs": jobs, "environment": ENVIRONMENT,
            "limits": LIMITS, "endpoint": ENDPOINT, "identity": copy.deepcopy(spec["identity"]),
            "source_hashes": {str(path): file_hash(path) for path in paths},
            "contracts": {native.contract_metadata(contract)["name"]: native.native_output_config(contract)
                          for contract in contracts},
            "initial_author_prompts": initial,
            "dependencies": dependencies,
            "criteria": copy.deepcopy(spec["criteria"]),
            "credential_limits": {"seconds": safe.CREDENTIAL_TIMEOUT_SECONDS,
                                  "bytes": safe.CREDENTIAL_MAX_BYTES},
            "failure_policy": spec["failure_policy"],
            "launch_precheck": copy.deepcopy(spec["launch_precheck"]),
            "predecessor_setup_abort": copy.deepcopy(spec["predecessor_setup_abort"]),
            "reused_scopes": {"original_jobs_path": str(ORIGINAL_JOBS),
                              "original_jobs_sha256": file_hash(ORIGINAL_JOBS),
                              "prior_evidence_sha256": copy.deepcopy(spec["prior_failed_full_worker_evidence_sha256"]),
                              "same_goal_requests": True, "not_a_matched_causal_comparison": True},
            "claim_limits": spec["claim_limits"]}


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


def run_job(job, capture, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic,
            credential_expires_at=None, credential_clock=lambda: datetime.now(timezone.utc)):
    original_job = next(item for item in capture["original_jobs"] if item["id"] == job["id"])
    require(original_job["status"] == "unattempted", "Original job was already attempted.")
    original_job["status"] = "running"
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
        guard(len(capture["reservations"]) < 6, "Global reservation ceiling.")
        call_slot = next(item for item in capture["call_slots"]
                         if item["job"] == job["id"] and item["ordinal"] == budget.calls)
        guard(call_slot["status"] == "unattempted", "Original call slot was already reserved.")
        call_slot["status"] = "reserved"
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
            if author:
                guard(1 <= kwargs["normalized_request"]["targetCount"] <= 3,
                      "Author escaped the frozen three-item batch cap.")
                if not row["passes"]:
                    planned = capture["plan"]["initial_author_prompts"][0]
                    guard(native.native_prompt(system, contract) == planned["system"]
                          and prompt == planned["user"], "Initial author prompt drift.")
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
                response = self.client.converse(**request)
                retained, omitted = safe.safe_response(response, secrets)
                retained.pop("safeResponseMetadata", None)
                visible = json.dumps(retained, ensure_ascii=False)
                guard(not any(secret and secret in visible for secret in secrets), "Credential echo in visible output.")
                guard(not decoded_credential_echo(response, secrets), "Credential echo in decoded native output.")
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
        row.update(status="failed", error=safe_error_identity(error, secrets))
        if isinstance(error, (IntegrityError, safe.CaptureBoundaryError)) or setup_failure(error) or not isinstance(error, (ProviderError, SafetyInterventionError)):
            capture["global_stop"] = "setup_or_integrity_failure"
    finally:
        row.update(elapsed_seconds=round(clock() - deadline.started, 6), provider_calls=budget.calls,
                   remaining_ms=budget.remaining_milliseconds())
        row["within_deadline"] = row["elapsed_seconds"] <= 240
        original_job["status"] = row["status"]
        for index, slot in enumerate(original_job["slots"]):
            slot["status"] = ("returned" if index < len(row["returned"]) and row["within_deadline"]
                              else "late_uncredited" if index < len(row["returned"])
                              else "unfilled")
        pins()
        save(path, capture)


def run_jobs(plan, capture, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic,
             credential_expires_at=None, credential_clock=lambda: datetime.now(timezone.utc)):
    require(not capture["calls"] and not capture["jobs"], "No resume or repeat.")
    require(len(capture["original_jobs"]) == 1 and len(capture["call_slots"]) == 6,
            "Original job or call slots were not materialized.")
    for job in plan["jobs"]:
        if capture.get("global_stop"):
            break
        run_job(job, capture, path, client_factory, pin_check, secrets=secrets, clock=clock,
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


def preflight():
    check_default_profile()
    check_aws_cli()
    result = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", str(HERE),
                             "-p", "test_batch_probe.py", "-q"], capture_output=True, text=True)
    require(result.returncode == 0, "Offline tests failed: " + result.stderr)
    return {"provider_calls": 0, "result": "passed", "output": result.stderr.strip()}


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
    draft = {**plan, "state": "draft"}
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
    draft = build_plan()
    require(not LAUNCH_ATTEMPT.exists() and not LAUNCH_PRECHECK.exists()
            and not PLAN.exists() and not CAPTURE.exists(),
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
    draft = build_plan()
    require(digest(draft) == reviewed_digest, "Draft digest changed.")
    check_launch_record(draft)
    preflight()
    require(build_plan() == draft, "Sources changed during preflight.")
    check_launch_record(draft)
    save(PLAN, {**draft, "state": "frozen"}, exclusive=True)
    return {"plan_sha256": file_hash(PLAN), "provider_calls": 0}


def execute(expected_hash):
    require(PLAN.stat().st_size <= 8 * 1024 * 1024 and file_hash(PLAN) == expected_hash, "Plan bound/hash failed.")
    plan = safe.strict_json(PLAN.read_text())
    require(plan["state"] == "frozen", "Plan is not frozen.")
    check_plan(plan, PLAN, expected_hash)
    check_launch_record(plan)
    capture = new_capture(plan, expected_hash)
    save(CAPTURE, capture, exclusive=True)
    secrets = ()
    try:
        session, secrets, credential_expires_at = default_profile_session()
        verify_account_identity(session, capture, CAPTURE)
        run_jobs(plan, capture, CAPTURE, session.client, lambda: check_plan(plan, PLAN, expected_hash),
                 secrets=secrets, credential_expires_at=credential_expires_at)
    except BaseException as error:
        capture.update(status="globally_aborted", global_stop="setup_or_interruption",
                       error=safe_error_identity(error, secrets))
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
    group.add_argument("--launch-precheck", action="store_true")
    group.add_argument("--freeze")
    group.add_argument("--execute")
    args = parser.parse_args()
    result = ({"draft_digest": digest(build_plan()), "plan": build_plan()} if args.draft else preflight() if args.preflight
              else launch_precheck() if args.launch_precheck else freeze(args.freeze) if args.freeze
              else execute(args.execute))
    print(json.dumps(result, ensure_ascii=True, indent=2))
