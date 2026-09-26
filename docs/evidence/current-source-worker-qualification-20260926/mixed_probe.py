"""Current-source worker-route probe; import and preflight make no provider calls."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
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
ORIGINAL_JOBS = ROOT / "docs/evidence/constructed-sonnet-long-read-qualification-20260922/jobs-draft.json"
SOURCE_COMMIT = "99cd50a3ed7ee8babe98ec9e8763cdd9f9edff53"
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
ENVIRONMENT = copy.deepcopy(DRAFT_DATA["trial_environment"])
AUTHOR_MODEL = ENVIRONMENT["BEDROCK_MODEL_ID"]
LIMITS = copy.deepcopy(DRAFT_DATA["limits"])
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
    require(len(plan["jobs"]) == 3 and all(job["request"]["targetCount"] == 5 for job in plan["jobs"]),
            "Original fifteen-slot assignment changed.")
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
    for name in ("AWS_ENDPOINT_URL", "AWS_ENDPOINT_URL_STS"):
        require(not environment.get(name), "An AWS endpoint override is present.")


def controlled_cli_environment(environment=None):
    """Keep the profile and login cache while excluding inherited endpoint settings."""
    source = os.environ if environment is None else environment
    child = {key: value for key, value in source.items()
             if not key.upper().startswith("AWS_ENDPOINT_URL")}
    child["AWS_PROFILE"] = EXPECTED_PROFILE
    child["AWS_DEFAULT_PROFILE"] = EXPECTED_PROFILE
    child["AWS_IGNORE_CONFIGURED_ENDPOINT_URLS"] = "true"
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
    validate_identity_environment()
    check_aws_cli()
    command = (str(AWS_CLI_PATH), "configure", "export-credentials", "--profile", EXPECTED_PROFILE,
               "--format", "process")
    child_environment = controlled_cli_environment()

    def spawn(actual, **kwargs):
        require(tuple(actual) == command and "env" not in kwargs,
                "Credential export command or subprocess environment changed.")
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


def verify_account_identity(session, capture, path):
    """Check the exact STS endpoint before any signed identity request."""
    validate_identity_environment()
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
    require(jobs == spec["fixed_jobs"] and [job["id"] for job in jobs] == ["quantitative", "python", "mixed"]
            and all(job["request"]["targetCount"] == 5 for job in jobs), "Fixed jobs changed.")
    require(ENVIRONMENT == spec["trial_environment"] and LIMITS == spec["limits"]
            and ENVIRONMENT["QUESTION_AUTHOR_CARDINALITY_CONTRACT"] == "array",
            "Trial settings or count-bound separation changed.")
    require(ENDPOINT == spec["endpoint"] and LIMITS["maximum_calls"] == 18
            and LIMITS["calls_per_job"] == 6 and LIMITS["seconds_per_job"] == 240,
            "Endpoint or hard budget changed.")
    require(spec["identity"] == {"profile": EXPECTED_PROFILE, "account": EXPECTED_ACCOUNT_ID,
                                 "sts_endpoint": STS_ENDPOINT,
                                 "aws_cli_version": EXPECTED_AWS_CLI_VERSION,
                                 "aws_cli_path": str(AWS_CLI_PATH),
                                 "cli_ignores_configured_endpoints": True,
                                 "minimum_credential_lifetime_seconds": MIN_CREDENTIAL_LIFETIME_SECONDS},
            "Intended AWS identity or CLI changed.")
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
    paths += [HERE / name for name in ("mixed_probe.py", "test_mixed_probe.py", "PLAN.md",
                                       "jobs-draft.json", "plan-draft.json")]
    paths = sorted(set(paths))
    contracts = [CONSTRUCTED_AUTHOR_CONTRACT,
                 *[kind(count) for kind in (native.SolverSlotContract,
                                           native.AuthoredSolutionFlagReviewContract) for count in range(1, 6)]]
    with patch.dict(os.environ, ENVIRONMENT, clear=True):
        initial = [{"system": native.native_prompt(runtime._system_prompt(), CONSTRUCTED_AUTHOR_CONTRACT),
                    "user": runtime._user_prompt(job["request"])} for job in jobs]
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
        guard(len(capture["reservations"]) < 18, "Global reservation ceiling.")
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
    require(len(capture["original_jobs"]) == 3 and len(capture["call_slots"]) == 18,
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
    capture["summary"] = {"planned_jobs": len(capture["original_jobs"]), "planned_questions": 15,
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
    check_aws_cli()
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
    group.add_argument("--freeze")
    group.add_argument("--execute")
    args = parser.parse_args()
    result = ({"draft_digest": digest(build_plan()), "plan": build_plan()} if args.draft else preflight() if args.preflight
              else freeze(args.freeze) if args.freeze else execute(args.execute))
    print(json.dumps(result, ensure_ascii=True, indent=2))
