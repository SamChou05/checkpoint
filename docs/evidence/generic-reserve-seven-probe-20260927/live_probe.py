"""One-shot seven-author/five-survivor full-worker probe; importing is socket-free.

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
SOURCE_COMMIT = "a6448403e3067354e040d7386822549f9d9f24bc"
TRIAL_ID = "generic-prose-seven-reserve-probability-20260927-01"
PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"
REVIEW_LOCK = HERE / "review-approval.json"
LAUNCH_ATTEMPT = HERE / "launch-precheck-attempt.json"
LAUNCH_PRECHECK = HERE / "launch-precheck.json"
HELPER = SERVICE / "evals/bounded_bedrock_capture.py"
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
from request_contract import _choice_uniqueness_key, _has_unambiguous_choices, _normalize_request  # noqa: E402
from service_errors import ProviderError, SafetyInterventionError, ServiceConfigurationError  # noqa: E402

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
MAX_CALLS = 6
CAPTURE_HASHES = {}
IMPORTED_HARNESS_HASH = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
IMPORTED_HELPER_HASH = hashlib.sha256(HELPER.read_bytes()).hexdigest()


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
        for job in value.get("jobs", []):
            for observation in job.get("metrics", {}).get("ProviderObservations", []):
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
        require(file_hash(HERE / "live_probe.py") == plan["harness_sha256"],
                "Harness bytes changed after review.")
        require(file_hash(HELPER) == plan["capture_helper_sha256"] == IMPORTED_HELPER_HASH,
                "Capture helper changed after import.")
    check_loaded_modules(pins)
    return pins


def contract_configs():
    contracts = [native.AuthorSlotContract(7, "prose")]
    contracts += [native.SolverSlotContract(count) for count in range(1, 8)]
    contracts += [native.AuthoredSolutionFlagReviewContract(count) for count in range(1, 8)]
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


def build_plan():
    import protocol_guard as draft

    protocol = draft.strict_json(HERE / "protocol.json")
    request = draft.strict_json(HERE / "request.json")
    draft.check_draft(protocol, request, check_artifacts=False)
    require(file_hash(HERE / "live_probe.py") == IMPORTED_HARNESS_HASH,
            "Harness changed after import.")
    require(file_hash(HELPER) == IMPORTED_HELPER_HASH,
            "Bounded capture helper changed after import.")
    require(_normalize_request(request) == request, "Request is no longer normalized.")
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
            "An inherited credential value entered the author wire.")
    user_text = wire["messages"][0]["content"][0]["text"]
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
        "request_sha256": file_hash(HERE / "request.json"),
        "protocol_sha256": file_hash(HERE / "protocol.json"),
        "request": request, "environment": copy.deepcopy(env),
        "author_contract_name": author_name,
        "author_wire": wire, "author_wire_sha256": digest(wire),
        "native_author_schema_bytes": len(schema.encode()),
        "native_author_schema_sha256": hashlib.sha256(schema.encode()).hexdigest(),
        "allowed_contracts": configs,
        "limits": copy.deepcopy(protocol["limits"]),
        "prespecified_gate": copy.deepcopy(protocol["prespecified_gate"]),
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
            and plan["limits"]["native_author_rows"] == 7,
            "Frozen original request or reserve size changed.")
    return {
        "plan_sha256": plan_sha256, "trial_id": TRIAL_ID,
        "source_commit": plan["source_commit"],
        "started_at": datetime.now(timezone.utc).isoformat(),
        "status": "setup", "global_stop": None,
        "original_rows": [{"ordinal": index, "status": "unattempted"}
                          for index in range(7)],
        "call_slots": [{"ordinal": index, "status": "unattempted"}
                       for index in range(MAX_CALLS)],
        "calls": [], "reservations": [], "jobs": [],
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


def run_job(plan, capture, path, client_factory, pin_check, *, secrets=(),
            clock=time.monotonic, deadline=None, credential_expires_at=None,
            credential_clock=lambda: datetime.now(timezone.utc)):
    """Exercise the real single-pass pipeline, recording seven source ordinals."""
    deadline = Deadline(clock) if deadline is None else deadline
    require(deadline.get_remaining_time_in_millis() > 0,
            "Whole execute deadline elapsed before provider job.")
    require(not capture["jobs"] and not capture["calls"] and not capture["reservations"],
            "Original job or provider call already attempted.")
    row = {"id": "original", "status": "running", "returned": [],
           "returned_source_ordinals": [], "accepted_source_ordinals": [],
           "metrics": {"ProviderCalls": 0, "BedrockInputTokens": 0,
                       "BedrockOutputTokens": 0}}
    capture["jobs"].append(row)
    capture["status"] = "running"
    save(path, capture)
    budget = runtime.ProviderCallBudget(MAX_CALLS, context=deadline)
    original_stage = runtime._generate_with_bedrock
    original_sanitize = runtime._sanitize_questions
    original_verify = runtime.verify_questions
    stage_context = {}
    stage_names = []
    source_by_prompt = {}
    candidate_by_prompt = {}
    accepted_objects = {}

    def guard(condition, message):
        if not condition:
            capture["global_stop"] = "request_or_provenance_integrity"
            raise IntegrityError(message)

    def pins():
        check_capture(path)
        pin_check()

    def reserve():
        guard(not capture.get("global_stop"), "Global dispatch already stopped.")
        guard(len(capture["reservations"]) < MAX_CALLS,
              "Global Converse reservation ceiling.")
        slot = capture["call_slots"][budget.calls]
        guard(slot["status"] == "unattempted", "Call slot already reserved.")
        slot["status"] = "reserved"
        capture["reservations"].append({"ordinal": budget.calls})
        save(path, capture)

    budget.reserve_call = DurableProviderCallReservation(reserve, MAX_CALLS)

    def stage(*args, **kwargs):
        contract = kwargs.get("contract")
        request = kwargs.get("normalized_request")
        guard(request == {**plan["request"], "targetCount": 7},
              "Provider stage request differs from frozen seven-row request.")
        name = native.contract_metadata(contract)["name"]
        guard(name in plan["allowed_contracts"], "Unplanned native contract.")
        cfg = native.native_output_config(contract)
        guard(cfg == plan["allowed_contracts"][name], "Native contract bytes changed.")
        if not stage_names:
            guard(name == plan["author_contract_name"], "First call is not seven-row author.")
        elif len(stage_names) == 1:
            guard(name.startswith("complete_choice_solver_v5_n"),
                  "Second call is not answer-blind complete-choice solver.")
        elif len(stage_names) == 2:
            guard(name.startswith("authored_solution_reviewer_v3_n"),
                  "Third call is not authored-teaching reviewer.")
        else:
            guard(False, "A fourth model stage was attempted.")
        stage_names.append(name)
        system = kwargs.get("system_prompt") or runtime._system_prompt()
        prompt = kwargs.get("user_prompt") or runtime._user_prompt(request)
        stage_context.clear()
        stage_context.update(name=name, system=native.native_prompt(system, contract),
                             prompt=prompt, output_config=cfg,
                             model_id=kwargs.get("model_id"))
        try:
            return original_stage(*args, **kwargs)
        except ServiceConfigurationError:
            capture["global_stop"] = "native_stage_configuration"
            raise

    def sanitize(raw_questions, *args, **kwargs):
        guard(len(stage_names) == 1 and not source_by_prompt,
              "Sanitizer did not receive the one original author pass.")
        guard(type(raw_questions) is list and len(raw_questions) == 7
              and all(type(item) is dict for item in raw_questions),
              "Adapted native author did not provide seven original rows.")
        for ordinal, item in enumerate(raw_questions):
            prompt = quality._prompt_without_trailing_choice_echo(
                item.get("prompt"), item.get("choices"))
            guard(type(prompt) is str and prompt and prompt not in source_by_prompt,
                  "Author row cannot be bound to a unique displayed stem.")
            source_by_prompt[prompt] = ordinal
            capture["original_rows"][ordinal].update(status="authored",
                                                      author_question=copy.deepcopy(item))
        save(path, capture)
        result = original_sanitize(raw_questions, *args, **kwargs)
        for question in result:
            ordinal = source_by_prompt.get(question["prompt"])
            guard(ordinal is not None and question["prompt"] not in candidate_by_prompt,
                  "Sanitized question lacks a unique authored source.")
            candidate_by_prompt[question["prompt"]] = (ordinal, copy.deepcopy(question))
            capture["original_rows"][ordinal].update(status="sanitized",
                                                      sanitized_question=copy.deepcopy(question))
        save(path, capture)
        return result

    def verify(questions, *args, **kwargs):
        guard(len(questions) == len(candidate_by_prompt)
              and all(question["prompt"] in candidate_by_prompt
                      and question == candidate_by_prompt[question["prompt"]][1]
                      for question in questions),
              "Verifier input lost exact sanitized candidate association.")
        returned = original_verify(questions, *args, **kwargs)
        for question in returned:
            bound = candidate_by_prompt.get(question["prompt"])
            guard(bound is not None, "Verifier returned an unknown source.")
            ordinal, original = bound
            for key in ("prompt", "choices", "expectedAnswer", "explanation"):
                guard(question[key] == original[key],
                      "Verification rewrote immutable learner content.")
            guard(question.get("verificationVersion") == 1
                  and question.get("verificationPolicyRevision") == 7,
                  "Verified generic row lacks authored-pair policy 7.")
            guard(id(question) not in accepted_objects,
                  "Verifier returned a duplicate object.")
            accepted_objects[id(question)] = (question, ordinal)
            capture["original_rows"][ordinal].update(status="verified",
                                                      verified_question=copy.deepcopy(question))
            row["accepted_source_ordinals"].append(ordinal)
        guard(row["accepted_source_ordinals"] == sorted(row["accepted_source_ordinals"]),
              "Verification reordered original author survivors.")
        save(path, capture)
        return returned

    class Recorder:
        def __init__(self, client):
            self.client, self.meta = client, client.meta

        def converse(self, **wire):
            guard(not capture.get("global_stop"), "Global dispatch already stopped.")
            pins()
            cfg = self.meta.config
            guard(self.meta.endpoint_url == ENDPOINT
                  and self.meta.region_name == "us-east-1"
                  and cfg.connect_timeout == 3
                  and 2 <= cfg.read_timeout <= 200
                  and cfg.retries.get("total_max_attempts") == 1,
                  "Bedrock transport differs from frozen endpoint/retry limits.")
            expected = {
                "modelId": stage_context["model_id"],
                "system": [{"text": stage_context["system"]}],
                "messages": [{"role": "user", "content": [{"text": stage_context["prompt"]}]}],
                "outputConfig": stage_context["output_config"],
                "inferenceConfig": {"maxTokens": 16000},
                "additionalModelRequestFields": {
                    "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
            }
            guard(wire == expected and wire["modelId"] in {
                plan["environment"]["BEDROCK_MODEL_ID"],
                plan["environment"]["BEDROCK_VERIFICATION_MODEL_ID"],
            }, "Actual model request differs from frozen stage wire.")
            if stage_context["name"] == plan["author_contract_name"]:
                guard(wire == plan["author_wire"], "Actual first author wire changed.")
            operation = get_session().get_service_model("bedrock-runtime").operation_model("Converse")
            validate_parameters(wire, operation.input_shape)
            ordinal = budget.calls - 1
            guard(0 <= ordinal < MAX_CALLS and len(capture["calls"]) == ordinal
                  and capture["call_slots"][ordinal]["status"] == "reserved",
                  "Converse lacks one durable call reservation.")
            slot = capture["call_slots"][ordinal]
            slot["status"] = "request_saved"
            call = {"ordinal": ordinal, "stage": stage_context["name"],
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
                if budget.remaining_milliseconds() < minimum:
                    raise runtime.ProviderDeadlineExceededError(
                        "Insufficient time after durable request capture.")
                if credential_expires_at is not None:
                    credential_remaining = int((credential_expires_at - credential_clock()).total_seconds() * 1000)
                    call["credential_remaining_before_ms"] = max(0, credential_remaining)
                    guard(credential_remaining >= minimum,
                          "Credential snapshot expires before provider request can complete.")
                call["dispatch_attempted"] = True
                slot["status"] = "dispatch_attempted"
                save(path, capture)
                response = self.client.converse(**wire)
                retained, omitted = safe.safe_response(response, secrets)
                retained.pop("safeResponseMetadata", None)
                visible = json.dumps(retained, ensure_ascii=False)
                guard(not any(secret and secret in visible for secret in secrets)
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

    def client(*args, **kwargs):
        guard(args == ("bedrock-runtime",) and set(kwargs) == {"region_name", "config"},
              "Unplanned SDK client creation.")
        return Recorder(client_factory(*args, **kwargs))

    try:
        pins()
        with patch.dict(os.environ, plan["environment"], clear=True), \
                patch.object(boto3, "client", client), \
                patch.object(runtime, "_generate_with_bedrock", stage), \
                patch.object(runtime, "_sanitize_questions", sanitize), \
                patch.object(runtime, "verify_questions", verify):
            returned = runtime._generate_sanitized_questions(
                copy.deepcopy(plan["request"]), None, budget, row["metrics"])
        seen = []
        for question in returned:
            bound = accepted_objects.get(id(question))
            guard(bound is not None and bound[0] is question,
                  "Final return lacks original verifier-object identity.")
            ordinal = bound[1]
            guard(ordinal not in seen, "Final return duplicated a source ordinal.")
            seen.append(ordinal)
            capture["original_rows"][ordinal]["status"] = "returned"
        guard(seen == row["accepted_source_ordinals"][:5],
              "Final output was not the earliest five accepted source rows.")
        row.update(status="finished", returned=copy.deepcopy(returned),
                   returned_source_ordinals=seen)
    except Exception as error:
        row.update(status="failed", error=safe_error_identity(error, secrets))
        if isinstance(error, (IntegrityError, safe.CaptureBoundaryError)) or not isinstance(
                error, (ProviderError, SafetyInterventionError)):
            capture["global_stop"] = "setup_or_integrity_failure"
    finally:
        elapsed = clock() - deadline.started
        row.update(provider_calls=budget.calls, elapsed_seconds=round(elapsed, 6),
                   within_deadline=elapsed <= EXECUTE_SECONDS,
                   stage_names=stage_names)
        for item in capture["original_rows"]:
            if item["status"] != "returned":
                item["status"] = "unfilled_" + item["status"]
        capture["status"] = row["status"]
        pins()
        save(path, capture)
    return row


def finish(capture):
    job = capture["jobs"][0] if capture["jobs"] else None
    returned = job.get("returned", []) if job else []
    returned_ordinals = job.get("returned_source_ordinals", []) if job else []
    accepted_ordinals = job.get("accepted_source_ordinals", []) if job else []
    machine_candidate = (
        capture.get("status") == "finished"
        and capture.get("global_stop") is None
        and job is not None and job.get("status") == "finished"
        and job.get("within_deadline") is True
        and len(returned) == 5
        and returned_ordinals == accepted_ordinals[:5]
        and len(set(returned_ordinals)) == 5
        and all(type(question) is dict
                and question.get("verificationVersion") == 1
                and question.get("verificationPolicyRevision") == 7
                and type(question.get("difficulty")) is int
                and 2 <= question["difficulty"] <= 5
                and type(question.get("choices")) is list
                and len(question["choices"]) == 4
                and all(type(choice) is str and _choice_uniqueness_key(choice)
                        for choice in question["choices"])
                and _has_unambiguous_choices(question["choices"])
                and question["choices"].count(question.get("expectedAnswer")) == 1
                for question in returned)
        and len(capture["calls"]) <= MAX_CALLS
        and len(capture["reservations"]) <= MAX_CALLS
    )
    capture["summary"] = {
        "original_jobs": 1,
        "authored_source_ordinals": list(range(7)),
        "accepted_source_ordinals": job.get("accepted_source_ordinals", []) if job else [],
        "returned_source_ordinals": returned_ordinals,
        "returned_questions": len(returned),
        "provider_calls": len(capture["calls"]),
        "provider_reservations": len(capture["reservations"]),
        "original_rows": [{"ordinal": item["ordinal"], "status": item["status"]}
                          for item in capture["original_rows"]],
        "blind_review_pending": True,
        "qualification": "pending_content_review" if machine_candidate else "failed",
    }
    return capture["summary"]


def preflight():
    build_plan()
    result = subprocess.run((sys.executable, "-B", "-m", "unittest", "discover",
                             "-s", str(HERE), "-p", "test_live_probe.py", "-q"),
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
        run_job(plan, capture, CAPTURE, session.client,
                lambda: check_plan(plan, PLAN, expected_hash),
                secrets=secrets, deadline=deadline,
                credential_expires_at=credential_expires_at)
    except WholeDeadlineExceeded:
        capture.update(status="deadline_exceeded", global_stop="execute_deadline",
                       error={"type": "WholeDeadlineExceeded", "code": "whole_execute_deadline"})
        for item in capture["original_rows"]:
            if item["status"] == "returned":
                item["status"] = "late_uncredited"
        if capture["jobs"]:
            capture["jobs"][0]["returned"] = []
            capture["jobs"][0]["returned_source_ordinals"] = []
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
            for item in capture["original_rows"]:
                if item["status"] == "returned":
                    item["status"] = "late_uncredited"
            if capture["jobs"]:
                capture["jobs"][0]["returned"] = []
                capture["jobs"][0]["returned_source_ordinals"] = []
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
