"""Candidate-by-default, four-call replicated author-only qualification harness.

Preparation and fake runs never construct an AWS client. Live execution requires
a separately reviewed frozen plan hash and a pinned named AWS profile.
"""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
from importlib.metadata import version
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))

from native_output_contracts import (  # noqa: E402
    AuthorSlotContract, adapt_native_response, contract_metadata, native_output_config,
)
from question_generation import ProviderCallBudget, _generate_provider_payload  # noqa: E402
from request_contract import _normalize_request  # noqa: E402
from service_errors import ProviderCallBudgetExceededError  # noqa: E402

FIXED = HERE / "fixed_requests.json"
PAIRS = 2
SLOTS_PER_ARM = 5
MAX_CALLS = PAIRS * 2
MAX_VISIBLE_BYTES = 256 * 1024
STOP_REASONS = {"end_turn", "stop_sequence", "max_tokens", "guardrail_intervened",
                "tool_use", "content_filtered"}
USAGE_FIELDS = {"inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens",
                "cacheWriteInputTokens"}
CHOICE_LABELS = "ABCD"
PAIR_LABELS = ("AB", "AC", "AD", "BC", "BD", "CD")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def file_hash(path):
    return sha(path.read_bytes())


def source_hashes():
    paths = sorted(SERVICE.glob("*.py")) + [SERVICE / "requirements.txt"]
    return {str(path.relative_to(ROOT)): file_hash(path) for path in paths}


def fake_row(index):
    return {
        "prompt": f"In a fictional rule set, which option is valid for case {index}?",
        "choices": {"a": "Option A", "b": "Option B", "c": "Option C", "d": "Option D"},
        "explanation": "The stated fictional rule selects option A for this synthetic row.",
        "correctChoice": "a", "topic": "Time-window constraints", "difficulty": 2,
        "format": "Multiple Choice",
    }


def fake_payload(mode, cardinality, count):
    rows = [fake_row(i) for i in range(count)]
    if mode != "prose":
        rows = [{
            "kind": "quantitative", "topic": "Exact fractions", "difficulty": 2,
            "task": {"kind": "exact_value", "unit": "unitless",
                     "nodes": [{"kind": "literal", "value": str(i + 2)}], "root": 0,
                     "choices": {"a": str(i + 2), "b": str(i + 3),
                                 "c": str(i + 4), "d": str(i + 5)}},
        } for i in range(count)]
        if mode == "constructed_quantitative":
            for row in rows:
                del row["task"]["choices"]
    questions = ({str(i): row for i, row in enumerate(rows)}
                 if cardinality == "count_bound" else rows)
    return {"questions": questions}


class FakeClient:
    def __init__(self, response):
        self.response = response
        self.requests = []

    def converse(self, **request):
        self.requests.append(copy.deepcopy(request))
        return copy.deepcopy(self.response)


def fake_response(job):
    return {"stopReason": "end_turn", "output": {"message": {"content": [
        {"text": json.dumps(fake_payload(job["author_mode"], job["cardinality_contract"],
                                     job["payload"]["targetCount"]))}
    ]}}}


def job_environment(fixed, job):
    return fixed["environment"] | {
        "QUESTION_AUTHOR_MODE": job["author_mode"],
        "QUESTION_AUTHOR_CARDINALITY_CONTRACT": job["cardinality_contract"],
        "QUESTION_FEEDBACK_CONTRACT": job["feedback_contract"],
    }


def dry_job(fixed, job):
    environment = job_environment(fixed, job)
    client = FakeClient(fake_response(job))
    with patch.dict(os.environ, environment, clear=True):
        normalized = _normalize_request(job["payload"])
        adapted = _generate_provider_payload(normalized, client, ProviderCallBudget(1))
    if len(client.requests) != 1 or len(adapted["questions"]) != job["payload"]["targetCount"]:
        raise RuntimeError("Dry dispatch did not complete exactly one author call.")
    request = client.requests[0]
    schema_config = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]
    expected_contract = (AuthorSlotContract(job["payload"]["targetCount"], job["author_mode"])
                         if job["cardinality_contract"] == "count_bound" else
                         {"prose": "question_author_v3", "mixed_quantitative": "question_author_mixed_v1",
                          "constructed_quantitative": "question_author_constructed_v1"}[job["author_mode"]])
    if request["outputConfig"] != native_output_config(expected_contract):
        raise RuntimeError("Selected native author schema differs from the expected contract.")
    return {
        **job, "environment": environment, "normalized_request": normalized,
        "provider_request": request, "provider_request_sha256": sha(encode(request)),
        "contract": contract_metadata(expected_contract),
        "schema_sha256": sha(schema_config["schema"].encode()),
        "system_prompt_sha256": sha(request["system"][0]["text"].encode()),
        "user_prompt_sha256": sha(request["messages"][0]["content"][0]["text"].encode()),
    }


def prepare():
    fixed = json.loads(FIXED.read_text())
    jobs = fixed["jobs"]
    if len(jobs) != MAX_CALLS or len({job["id"] for job in jobs}) != MAX_CALLS:
        raise RuntimeError("The fixed matrix must contain exactly four unique jobs.")
    if len({job.get("assignment_id") for job in jobs}) != PAIRS:
        raise RuntimeError("The fixed matrix must contain two distinct assignments.")
    prepared = [dry_job(fixed, job) for job in jobs]
    for pair_index in range(PAIRS):
        first, second = prepared[2 * pair_index:2 * pair_index + 2]
        expected_order = (("array", "count_bound") if pair_index % 2 == 0
                          else ("count_bound", "array"))
        if (first["assignment_id"] != second["assignment_id"]
                or (first["cardinality_contract"], second["cardinality_contract"]) != expected_order
                or first["normalized_request"] != second["normalized_request"]
                or any(job["author_mode"] != "prose" or job["payload"]["targetCount"] != SLOTS_PER_ARM
                       for job in (first, second))):
            raise RuntimeError("Replicated pair differs in request, arm order or five-slot prose scope.")
    plan = {
        "status": "candidate", "experiment": fixed["experiment"],
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_sha256": source_hashes(),
        "plan_document_sha256": file_hash(HERE / "PLAN.md"),
        "fixed_requests_sha256": file_hash(FIXED),
        "harness_sha256": file_hash(Path(__file__)),
        "sdk_versions": {name: version(name) for name in ("boto3", "botocore", "jsonschema")},
        "python_version": list(sys.version_info[:3]),
        "region": fixed["region"], "model_id": fixed["model_id"],
        "endpoint_url": "https://bedrock-runtime.us-east-1.amazonaws.com",
        "capture_path": str((HERE / "capture.json").relative_to(ROOT)),
        "credential_pin": {"profile": "default", "account_id": "239342516379",
                           "provider_method": "login"},
        "limits": {"maximum_bedrock_author_calls": MAX_CALLS, "maximum_calls_per_job": 1,
                   "sdk_total_max_attempts": 1, "connect_timeout_seconds": 3,
                   "read_timeout_seconds": 200, "retries": 0, "warmups": 0,
                   "topups": 0, "solver_calls": 0, "reviewer_calls": 0,
                   "maximum_visible_response_bytes": MAX_VISIBLE_BYTES},
        "criteria": {
            "structural": {"normal_stop_reason": "end_turn", "strict_native_schema_and_adapter": True,
                           "raw_count_must_equal_target_count": True,
                           "fixed_map_requires_exact_dense_keys": True,
                           "failed_or_unattempted_slots_remain_in_denominator": True},
            "prose_replication": {"assignment_pairs": PAIRS,
                           "requested_original_slots_per_arm_per_assignment": SLOTS_PER_ARM,
                           "primary_measure": "independently_usable_original_slots_out_of_ten_per_arm",
                           "primary_novelty_scope": "within_each_five_row_arm_only",
                           "cross_arm_novelty": "separate_sensitivity_only",
                           "candidate_followup_minimum_usable_total": 8,
                           "candidate_followup_requires_at_least_baseline_total": True,
                           "candidate_followup_minimum_pairs_not_below_baseline": 2,
                           "candidate_followup_requires_both_candidate_batches_structural": True,
                           "single_trial_general_yield_claim_allowed": False},
            "semantic": {"independent_blind_answer_first": True,
                         "uncertain_row_usable": False, "filler_or_duplicate_row_usable": False,
                         "compiler_or_sanitizer_success_is_not_correctness": True},
            "blind_projection": {"version": 3, "prose_requested_slots": PAIRS * 2 * SLOTS_PER_ARM,
                                 "choice_rotation": "cryptographic_random_cyclic",
                                 "opaque_id_hex_characters": 24,
                                 "all_projected_items_require_locked_blind_answer": True,
                                 "choice_judgment_keys": list(CHOICE_LABELS),
                                 "pair_relation_keys": list(PAIR_LABELS),
                                 "premise_sufficiency_required": True,
                                 "capture_sha256_required_before_projection": True,
                                 "private_map_sha256_required_before_lock": True},
        },
        "jobs": prepared,
    }
    path = HERE / "plan-candidate.json"
    path.write_text(json.dumps(plan, indent=2, ensure_ascii=False) + "\n")
    return path


class RecordingClient:
    def __init__(self, client, job, credential_values=(), before_dispatch=None, after_response=None):
        self.client = client
        self.job = job
        self.credential_values = tuple(value for value in credential_values if value)
        self.before_dispatch = before_dispatch
        self.after_response = after_response
        self.calls = 0
        self.meta = getattr(client, "meta", None)
        self.observation = None

    def converse(self, **request):
        if self.calls or sha(encode(request)) != self.job["provider_request_sha256"]:
            raise RuntimeError("Unexpected or repeated provider request.")
        if self.before_dispatch is not None:
            self.before_dispatch()
        self.calls += 1
        started = time.monotonic()
        try:
            response = self.client.converse(**request)
        except Exception as error:
            # Error messages may contain request details or credential material.
            error_response = getattr(error, "response", None)
            error_detail = error_response.get("Error") if isinstance(error_response, dict) else None
            code = error_detail.get("Code") if isinstance(error_detail, dict) else None
            if (not isinstance(code, str) or re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", code) is None
                    or any(secret in code for secret in self.credential_values)):
                code = None
            error_type = type(error).__name__
            if re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,79}", error_type) is None:
                error_type = "Exception"
            self.observation = {"outcome": "provider_error", "error_type": error_type,
                                "error_code": code, "elapsed_seconds": round(time.monotonic() - started, 3)}
            self._persist_observation()
            raise
        output = response.get("output") if isinstance(response, dict) else None
        message = output.get("message") if isinstance(output, dict) else None
        blocks = message.get("content") if isinstance(message, dict) else None
        valid_blocks = isinstance(blocks, list) and all(isinstance(block, dict) for block in blocks)
        visible = [block["text"] for block in blocks if isinstance(block.get("text"), str)] if valid_blocks else []
        safe_visible, redaction = (safe_visible_text(visible, self.credential_values)
                                   if valid_blocks else (None, "invalid_content_blocks"))
        stop_reason, stop_valid = safe_stop_reason(response.get("stopReason") if isinstance(response, dict) else None)
        usage, usage_valid = safe_usage(response.get("usage") if isinstance(response, dict) else None)
        self.observation = {
            "outcome": "response", "elapsed_seconds": round(time.monotonic() - started, 3),
            "stop_reason": stop_reason, "stop_reason_valid": stop_valid,
            "usage": usage, "usage_valid": usage_valid,
            "visible_text_blocks": safe_visible, "capture_redaction": redaction,
            "reasoning_content_block_count": sum("reasoningContent" in block for block in blocks)
            if valid_blocks else None,
        }
        self._persist_observation()
        return response

    def _persist_observation(self):
        if self.after_response is not None:
            self.after_response(self.observation)


def safe_stop_reason(value):
    return (value, True) if isinstance(value, str) and value in STOP_REASONS else (None, False)


def safe_usage(value):
    if not isinstance(value, dict) or any(key not in USAGE_FIELDS for key in value):
        return None, False
    if any(type(count) is not int or not 0 <= count <= 10_000_000 for count in value.values()):
        return None, False
    return dict(value), True


def parse_visible_json(blocks, credential_values):
    """Bound, parse and inspect text before it can enter a durable capture."""
    if not isinstance(blocks, list) or not all(isinstance(block, str) for block in blocks):
        return None, "invalid_visible_blocks"
    try:
        if sum(len(block.encode("utf-8")) for block in blocks) + max(0, len(blocks) - 1) > MAX_VISIBLE_BYTES:
            return None, "oversized_visible_text"
    except UnicodeError:
        return None, "invalid_utf8_text"
    raw = "\n".join(blocks)
    duplicates = []

    def pairs_hook(pairs):
        seen = set()
        for key, _ in pairs:
            if key in seen:
                duplicates.append(key)
            seen.add(key)
        return dict(pairs)

    def reject_constant(value):
        raise ValueError(f"Non-JSON constant: {value}")

    try:
        decoded = json.loads(raw, object_pairs_hook=pairs_hook, parse_constant=reject_constant)
    except (TypeError, ValueError, RecursionError):
        return None, "malformed_json"
    if duplicates:
        return None, "duplicate_json_key"

    def strings(value):
        if isinstance(value, str):
            yield value
        elif isinstance(value, dict):
            for key, item in value.items():
                yield key
                yield from strings(item)
        elif isinstance(value, (list, tuple)):
            for item in value:
                yield from strings(item)

    try:
        if any(secret in raw or any(secret in part for part in strings(decoded))
               for secret in credential_values):
            return None, "credential_text"
    except RecursionError:
        return None, "malformed_json"
    return decoded, None


def safe_visible_text(blocks, credential_values):
    _, redaction = parse_visible_json(blocks, credential_values)
    return (blocks, None) if redaction is None else (None, redaction)


def structural_observation(job, observation):
    """Keep transport validity separate from later independent content review."""
    if observation is None or observation["outcome"] != "response":
        return {"eligible": False, "reason": "no_response", "raw_count": None}
    if observation.get("capture_redaction"):
        return {"eligible": False, "reason": "capture_redacted", "raw_count": None}
    if observation["stop_reason"] != "end_turn":
        return {"eligible": False, "reason": "incomplete_stop", "raw_count": None}
    try:
        from jsonschema import Draft202012Validator

        raw_text = "\n".join(observation["visible_text_blocks"])
        raw, parse_error = parse_visible_json(observation["visible_text_blocks"], ())
        if parse_error:
            return {"eligible": False, "reason": parse_error, "raw_count": None}
        schema = json.loads(job["provider_request"]["outputConfig"]["textFormat"]
                            ["structure"]["jsonSchema"]["schema"])
        errors = list(Draft202012Validator(schema).iter_errors(raw))
        questions = raw.get("questions") if isinstance(raw, dict) else None
        raw_count = len(questions) if isinstance(questions, (list, dict)) else None
        raw_rows = list(questions.values()) if isinstance(questions, dict) else questions
        typed_count = sum(isinstance(row, dict) and row.get("kind") == "quantitative"
                          for row in raw_rows) if isinstance(raw_rows, list) else None
        shape = "object" if job["cardinality_contract"] == "count_bound" else "array"
        exact = (isinstance(questions, dict if shape == "object" else list)
                 and raw_count == job["payload"]["targetCount"])
        contract = (AuthorSlotContract(job["payload"]["targetCount"], job["author_mode"])
                    if shape == "object" else
                    {"prose": "question_author_v3", "mixed_quantitative": "question_author_mixed_v1",
                     "constructed_quantitative": "question_author_constructed_v1"}[job["author_mode"]])
        try:
            adapt_native_response(raw_text, contract)
            adapter_valid = True
        except Exception:
            adapter_valid = False
        valid = not errors and exact and adapter_valid
        return {"eligible": valid, "reason": "valid" if valid else
                "schema_or_count_invalid", "raw_count": raw_count, "schema_error_count": len(errors),
                "adapter_valid": adapter_valid,
                "typed_row_count": typed_count,
                "raw_question_keys": list(questions) if isinstance(questions, dict) else None}
    except (ValueError, TypeError):
        return {"eligible": False, "reason": "malformed_json", "raw_count": None}


def check_frozen(plan, provided_hash):
    if plan["status"] != "frozen" or any(value == "REVIEW_REQUIRED"
                                            for value in plan["credential_pin"].values()):
        raise RuntimeError("Only a reviewed frozen plan with completed credential pins may execute.")
    if len(plan["jobs"]) != MAX_CALLS or plan["limits"]["maximum_bedrock_author_calls"] != MAX_CALLS:
        raise RuntimeError("Live call ceiling drifted.")
    if plan["limits"]["maximum_visible_response_bytes"] != MAX_VISIBLE_BYTES:
        raise RuntimeError("Capture byte limit drifted.")
    if file_hash(FIXED) != plan["fixed_requests_sha256"] or source_hashes() != plan["source_sha256"]:
        raise RuntimeError("Fixed inputs or runtime source drifted.")
    if file_hash(HERE / "PLAN.md") != plan["plan_document_sha256"]:
        raise RuntimeError("Prospective assessment criteria document drifted.")
    if file_hash(Path(__file__)) != plan["harness_sha256"]:
        raise RuntimeError("Harness drifted.")
    if list(sys.version_info[:3]) != plan["python_version"]:
        raise RuntimeError("Python interpreter version drifted.")
    if {name: version(name) for name in ("boto3", "botocore", "jsonschema")} != plan["sdk_versions"]:
        raise RuntimeError("SDK or schema validator version drifted.")
    if subprocess.run(["git", "merge-base", "--is-ancestor", plan["source_revision"], "HEAD"],
                      cwd=ROOT, check=False).returncode != 0:
        raise RuntimeError("Pinned source revision is not an ancestor of execution checkout.")
    fixed = json.loads(FIXED.read_text())
    for expected, job in zip(plan["jobs"], fixed["jobs"], strict=True):
        if dry_job(fixed, job) != expected:
            raise RuntimeError("Actual author request or selected schema drifted.")
    if provided_hash != file_hash(HERE / "plan.json"):
        raise RuntimeError("Frozen plan hash differs from reviewed hash.")


class CaptureJournal:
    """Exclusive, fsynced reservation log; never resumes or overwrites a run."""

    def __init__(self, path, initial):
        self.path = path
        self.capture = initial
        self.expected_sha256 = None
        self.active_index = None
        self._write(exclusive=True)

    def _write(self, *, exclusive=False):
        data = (json.dumps(self.capture, indent=2, ensure_ascii=False) + "\n").encode()
        target = self.path if exclusive else self.path.with_suffix(".partial")
        descriptor = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if not exclusive:
            os.replace(target, self.path)
        directory = os.open(self.path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
        self.expected_sha256 = sha(data)

    def ensure_integrity(self):
        if file_hash(self.path) != self.expected_sha256:
            raise RuntimeError("Durable capture changed outside this process; no further dispatch.")

    def update(self):
        self.ensure_integrity()
        self._write()

    def reserve(self, job, plan, provided_hash):
        # The capture and all reviewed pins are checked immediately before each
        # actual Converse call, then the reservation is fsynced before transport.
        self.ensure_integrity()
        check_frozen(plan, provided_hash)
        if self.active_index is not None or len(self.capture["jobs"]) >= MAX_CALLS:
            raise RuntimeError("A provider dispatch reservation is already active or exhausted.")
        if [entry["id"] for entry in self.capture["jobs"]] != [
            entry["id"] for entry in plan["jobs"][:len(self.capture["jobs"])]
        ]:
            raise RuntimeError("Capture job order differs from reviewed plan.")
        if job["id"] != plan["jobs"][len(self.capture["jobs"])]["id"]:
            raise RuntimeError("Provider job order drifted.")
        self.active_index = len(self.capture["jobs"])
        self.capture["jobs"].append({
            "id": job["id"], "arm": job["cardinality_contract"],
            "provider_request_sha256": job["provider_request_sha256"],
            "dispatch_status": "reserved_before_converse",
            "reserved_at_utc": datetime.now(timezone.utc).isoformat(),
        })
        self.update()

    def record_transport(self, observation):
        if self.active_index is None or not isinstance(observation, dict):
            raise RuntimeError("No durable reservation exists for provider observation.")
        entry = self.capture["jobs"][self.active_index]
        if "transport" in entry:
            raise RuntimeError("Provider observation was already captured.")
        entry["transport"] = observation
        entry["dispatch_status"] = "provider_response_captured"
        self.update()

    def complete(self, outcome):
        if self.active_index is None:
            raise RuntimeError("No durable reservation exists for provider outcome.")
        self.capture["jobs"][self.active_index].update(outcome)
        self.capture["jobs"][self.active_index]["dispatch_status"] = "completed"
        self.update()
        self.active_index = None


def finalize_author_job(journal, job, recorder, outcome, plan, provided_hash):
    """Assess only after a durable response, then recheck pins before completion."""
    if journal.active_index is None or recorder.calls != 1:
        raise RuntimeError("Author dispatch ended without exactly one durable reservation.")
    captured = journal.capture["jobs"][journal.active_index].get("transport")
    if captured is None or captured != recorder.observation:
        raise RuntimeError("Provider response was not durably captured before adaptation.")
    outcome["provider_calls"] = recorder.calls
    outcome["structure"] = structural_observation(job, recorder.observation)
    journal.ensure_integrity()
    check_frozen(plan, provided_hash)
    journal.complete(outcome)


def static_session_for_snapshot(boto3_module, frozen_credentials, region):
    """Make the signer use the exact in-memory values scanned in output."""
    session = boto3_module.Session(
        aws_access_key_id=frozen_credentials.access_key,
        aws_secret_access_key=frozen_credentials.secret_key,
        aws_session_token=frozen_credentials.token,
        region_name=region,
    )
    signing_credentials = session.get_credentials()
    if signing_credentials is None or signing_credentials.method != "explicit":
        raise RuntimeError("Bedrock signer is not using explicit frozen credentials.")
    signed = signing_credentials.get_frozen_credentials()
    if (signed.access_key, signed.secret_key, signed.token) != (
        frozen_credentials.access_key, frozen_credentials.secret_key, frozen_credentials.token,
    ):
        raise RuntimeError("Bedrock signer credentials differ from the scanned snapshot.")
    return session


def execute(provided_hash, capture_path):
    plan_path = HERE / "plan.json"
    plan = json.loads(plan_path.read_text())
    check_frozen(plan, provided_hash)
    if capture_path.resolve() != (ROOT / plan["capture_path"]).resolve():
        raise RuntimeError("Capture path differs from reviewed pin.")
    profile = plan["credential_pin"]["profile"]
    capture = {"experiment": plan["experiment"], "plan_sha256": provided_hash,
               "source_revision": plan["source_revision"], "account_id": None,
               "credential_profile": profile, "credential_provider_method": None,
               "created_at_utc": datetime.now(timezone.utc).isoformat(),
               "preflight_status": "started", "jobs": []}
    journal = CaptureJournal(capture_path, capture)  # Before credentials, STS or Bedrock setup.
    try:
        if any(os.getenv(key) for key in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN")):
            raise RuntimeError("Ambient exported AWS credentials are prohibited.")
        import boto3
        import botocore
        from botocore.config import Config

        profile_session = boto3.Session(profile_name=profile, region_name=plan["region"])
        credentials = profile_session.get_credentials()
        if credentials is None or credentials.method != plan["credential_pin"]["provider_method"]:
            raise RuntimeError("Credential provider source differs from reviewed pin.")
        frozen_credentials = credentials.get_frozen_credentials()
        signing_session = static_session_for_snapshot(boto3, frozen_credentials, plan["region"])
        # STS verifies the exact static signing snapshot used by Bedrock.
        identity = signing_session.client("sts", config=Config(connect_timeout=3, read_timeout=10,
                                                               retries={"total_max_attempts": 1})).get_caller_identity()
        if (not isinstance(identity.get("Account"), str)
                or re.fullmatch(r"[0-9]{12}", identity["Account"]) is None
                or identity["Account"] != plan["credential_pin"]["account_id"]):
            raise RuntimeError("AWS account differs from reviewed pin.")
        client = signing_session.client("bedrock-runtime", config=Config(
            connect_timeout=3, read_timeout=200, retries={"total_max_attempts": 1}))
        if client.meta.endpoint_url != plan["endpoint_url"]:
            raise RuntimeError("Bedrock endpoint differs from reviewed pin.")
        journal.capture.update({
            "preflight_status": "passed", "account_id": identity["Account"],
            "credential_provider_method": credentials.method,
            "bedrock_signer_source": "static_frozen_named_profile_snapshot",
            "boto3_version": boto3.__version__, "botocore_version": botocore.__version__,
        })
        journal.update()
    except Exception as error:
        journal.capture.update({"preflight_status": "failed", "preflight_error_type": type(error).__name__})
        journal.update()
        raise
    for job in plan["jobs"]:
        def before_dispatch(job=job):
            journal.reserve(job, plan, provided_hash)

        recorder = RecordingClient(client, job, (
            frozen_credentials.access_key, frozen_credentials.secret_key,
            frozen_credentials.token,
        ), before_dispatch=before_dispatch, after_response=journal.record_transport)
        budget = ProviderCallBudget(1)
        outcome = {}
        budget_overrun = False
        with patch.dict(os.environ, job["environment"]):
            try:
                adapted = _generate_provider_payload(job["normalized_request"], recorder, budget)
                outcome["adapted_count"] = len(adapted.get("questions", []))
                if recorder.observation and not recorder.observation.get("capture_redaction"):
                    outcome["adapted_payload"] = adapted
            except ProviderCallBudgetExceededError as error:
                outcome["runtime_outcome"] = type(error).__name__
                budget_overrun = True
            except Exception as error:
                outcome["runtime_outcome"] = type(error).__name__
        finalize_author_job(journal, job, recorder, outcome, plan, provided_hash)
        if budget_overrun:
            raise RuntimeError("Author call budget overrun attempt; later jobs remain unattempted.")
    check_frozen(plan, provided_hash)
    journal.ensure_integrity()
    return capture_path


def write_exclusive_json(path, value):
    data = (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    directory = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
    return sha(data)


def check_projection_plan(plan_path, capture_path):
    plan = json.loads(plan_path.read_text())
    capture = json.loads(capture_path.read_text())
    if plan.get("status") != "frozen" or capture.get("plan_sha256") != file_hash(plan_path):
        raise RuntimeError("Blind assessment requires the matching frozen capture plan.")
    if (plan.get("harness_sha256") != file_hash(Path(__file__))
            or plan.get("plan_document_sha256") != file_hash(HERE / "PLAN.md")
            or plan.get("criteria", {}).get("blind_projection", {}).get("version") != 3):
        raise RuntimeError("Blind projection code or prospective criteria drifted.")
    return plan, capture


def prose_sources(job, entry):
    """Recover every requested prose slot and surplus row from its native shape."""
    target_count = job["payload"]["targetCount"]
    blocks = (entry.get("transport") or {}).get("visible_text_blocks")
    raw, error = parse_visible_json(blocks, ())
    questions = raw.get("questions") if error is None and isinstance(raw, dict) else None
    if job["cardinality_contract"] == "array":
        rows = questions if isinstance(questions, list) else []
        sources = [(position, None, rows[position] if position < len(rows) else None,
                    position < target_count)
                   for position in range(max(target_count, len(rows)))]
        diagnostics = {"raw_count": len(rows) if isinstance(questions, list) else None,
                       "surplus_positions": list(range(target_count, len(rows))),
                       "missing_positions": list(range(len(rows), target_count))}
    elif job["cardinality_contract"] == "count_bound":
        rows = questions if isinstance(questions, dict) else {}
        required = {str(position) for position in range(target_count)}
        sources = [(position, str(position), rows.get(str(position)), True)
                   for position in range(target_count)]
        sources.extend((None, key, rows[key], False) for key in sorted(set(rows) - required))
        diagnostics = {"raw_count": len(rows) if isinstance(questions, dict) else None,
                       "raw_question_keys": list(rows),
                       "missing_keys": sorted(required - set(rows)),
                       "extra_keys": sorted(set(rows) - required)}
    else:
        raise RuntimeError("Unexpected prose cardinality arm in blind projection.")
    return sources, diagnostics


def projectable_prose_row(row):
    return (isinstance(row, dict) and isinstance(row.get("prompt"), str)
            and isinstance(row.get("choices"), dict)
            and set(row["choices"]) == {"a", "b", "c", "d"}
            and all(isinstance(value, str) for value in row["choices"].values()))


def incomplete_capture_denominator(plan, capture):
    observed = capture.get("jobs") if isinstance(capture.get("jobs"), list) else []
    by_id = {entry.get("id"): entry for entry in observed if isinstance(entry, dict)}
    return {job["id"]: {"requested_original_slots": job["payload"]["targetCount"],
                        "completed_author_call": by_id.get(job["id"], {}).get("dispatch_status") == "completed",
                        "favorable_trial_credit": 0}
            for job in plan["jobs"]}


def project_blind(capture_path, plan_path, worksheet_path, private_path, expected_capture_hash):
    """Create a keyless, arm-blind worksheet and private provenance map."""
    if worksheet_path.exists() or private_path.exists():
        raise RuntimeError("Blind projection output exists; no overwrite is allowed.")
    if not isinstance(expected_capture_hash, str) or expected_capture_hash != file_hash(capture_path):
        raise RuntimeError("Blind projection requires the exact out-of-band capture SHA-256.")
    plan, capture = check_projection_plan(plan_path, capture_path)
    expected = plan["jobs"]
    observed = capture.get("jobs")
    if (not isinstance(observed, list) or len(observed) != MAX_CALLS
            or any(entry.get("id") != job["id"] or entry.get("dispatch_status") != "completed"
                   or entry.get("provider_request_sha256") != job["provider_request_sha256"]
                   for entry, job in zip(observed, expected, strict=True))):
        denominator = incomplete_capture_denominator(plan, capture)
        raise RuntimeError("Capture incomplete; no blind worksheet. Failed denominators: "
                           + json.dumps(denominator, sort_keys=True))
    items = []
    mapping = {}
    diagnostics = {}
    for job, entry in zip(expected, observed, strict=True):
        if job["author_mode"] != "prose" or job["payload"]["targetCount"] != SLOTS_PER_ARM:
            raise RuntimeError("Blind projection prose matrix drifted.")
        sources, diagnostics[job["id"]] = prose_sources(job, entry)
        for position, source_key, row, requested_slot in sources:
            opaque_id = secrets.token_hex(12)
            while opaque_id in mapping:
                opaque_id = secrets.token_hex(12)
            projected = {"id": opaque_id, "requested_slot": requested_slot}
            labels = None
            if projectable_prose_row(row):
                offset = secrets.randbelow(4)
                labels = list("abcd")[offset:] + list("abcd")[:offset]
                projected["stem"] = row["prompt"]
                projected["choices"] = {display: row["choices"][source]
                                        for display, source in zip("ABCD", labels, strict=True)}
            else:
                projected["unavailable"] = True
            items.append(projected)
            mapping[opaque_id] = {"job_id": job["id"], "original_row_position": position,
                                  "raw_question_key": source_key, "requested_slot": requested_slot,
                                  "display_to_source_choice": labels,
                                  "author_key": row.get("correctChoice") if isinstance(row, dict) else None,
                                  "author_explanation": row.get("explanation") if isinstance(row, dict) else None}
    secrets.SystemRandom().shuffle(items)
    expected_slots = sum(job["payload"]["targetCount"] for job in expected)
    if sum(item["requested_slot"] for item in items) != expected_slots:
        raise RuntimeError("Blind worksheet lost a requested prose slot.")
    if file_hash(capture_path) != expected_capture_hash:
        raise RuntimeError("Capture changed during blind projection.")
    worksheet = {"version": 3, "capture_sha256": expected_capture_hash,
                 "plan_sha256": file_hash(plan_path), "items": items}
    worksheet_sha = write_exclusive_json(worksheet_path, worksheet)
    private = {"version": 3, "worksheet_sha256": worksheet_sha,
               "capture_sha256": worksheet["capture_sha256"], "mapping": mapping,
               "raw_shape_diagnostics": diagnostics}
    private_sha = write_exclusive_json(private_path, private)
    return {"capture_sha256": expected_capture_hash,
            "worksheet_sha256": worksheet_sha, "private_map_sha256": private_sha}


def verify_private_provenance(plan, capture, worksheet, private):
    """Reconstruct every displayed item from immutable captured author rows."""
    if (set(worksheet) != {"version", "capture_sha256", "plan_sha256", "items"}
            or worksheet["version"] != 3 or not isinstance(worksheet["items"], list)
            or set(private) != {"version", "worksheet_sha256", "capture_sha256",
                                "mapping", "raw_shape_diagnostics"}
            or private["version"] != 3 or not isinstance(private["mapping"], dict)):
        raise RuntimeError("Blind projection structure drifted.")
    expected_sources = {}
    expected_diagnostics = {}
    for job, entry in zip(plan["jobs"], capture["jobs"], strict=True):
        sources, expected_diagnostics[job["id"]] = prose_sources(job, entry)
        for position, source_key, row, requested_slot in sources:
            identity = (job["id"], position, source_key)
            expected_sources[identity] = (row, requested_slot)
    if private["raw_shape_diagnostics"] != expected_diagnostics:
        raise RuntimeError("Private map raw-shape diagnostics differ from capture.")
    ids = [item.get("id") for item in worksheet["items"] if isinstance(item, dict)]
    if (len(ids) != len(worksheet["items"]) or len(ids) != len(set(ids))
            or set(ids) != set(private["mapping"])):
        raise RuntimeError("Blind item identities differ from private map.")
    seen_sources = set()
    source_fields = {"job_id", "original_row_position", "raw_question_key", "requested_slot",
                     "display_to_source_choice", "author_key", "author_explanation"}
    for item in worksheet["items"]:
        opaque_id = item["id"]
        if not isinstance(opaque_id, str) or re.fullmatch(r"[0-9a-f]{24}", opaque_id) is None:
            raise RuntimeError("Blind item has an invalid opaque identity.")
        source = private["mapping"][opaque_id]
        if not isinstance(source, dict) or set(source) != source_fields:
            raise RuntimeError("Private mapping shape differs from projection protocol.")
        identity = (source["job_id"], source["original_row_position"], source["raw_question_key"])
        if identity not in expected_sources or identity in seen_sources:
            raise RuntimeError("Private mapping source identity differs from capture.")
        seen_sources.add(identity)
        row, requested_slot = expected_sources[identity]
        if (type(item.get("requested_slot")) is not bool or item["requested_slot"] != requested_slot
                or type(source["requested_slot"]) is not bool or source["requested_slot"] != requested_slot
                or source["author_key"] != (row.get("correctChoice") if isinstance(row, dict) else None)
                or source["author_explanation"] != (row.get("explanation") if isinstance(row, dict) else None)):
            raise RuntimeError("Private mapping key, explanation or slot differs from capture.")
        labels = source["display_to_source_choice"]
        if projectable_prose_row(row):
            rotations = [list("abcd")[offset:] + list("abcd")[:offset] for offset in range(4)]
            if type(labels) is not list or labels not in rotations:
                raise RuntimeError("Private choice rotation differs from capture.")
            expected_choices = {display: row["choices"][original]
                                for display, original in zip(CHOICE_LABELS, labels, strict=True)}
            if (set(item) != {"id", "requested_slot", "stem", "choices"}
                    or item["stem"] != row["prompt"] or item["choices"] != expected_choices):
                raise RuntimeError("Blind display choices or stem differ from captured row.")
        elif item != {"id": opaque_id, "requested_slot": requested_slot, "unavailable": True} or labels is not None:
            raise RuntimeError("Unavailable blind slot differs from captured row.")
    expected_slots = sum(job["payload"]["targetCount"] for job in plan["jobs"])
    if (seen_sources != set(expected_sources)
            or sum(item["requested_slot"] for item in worksheet["items"]) != expected_slots):
        raise RuntimeError("Blind projection lost a captured or requested slot.")


def validate_blind_answers(items, answers):
    if not isinstance(answers, dict) or set(answers) != {item["id"] for item in items}:
        raise RuntimeError("Blind review must cover every projected item exactly once.")
    required_fields = {"independent_answer", "reasoning", "uncertain", "choice_judgments",
                       "pair_relations", "premise_sufficiency"}
    for item in items:
        answer = answers[item["id"]]
        if (not isinstance(answer, dict) or set(answer) != required_fields
                or not isinstance(answer["reasoning"], str) or not answer["reasoning"].strip()
                or type(answer["uncertain"]) is not bool
                or not isinstance(answer["choice_judgments"], dict)
                or set(answer["choice_judgments"]) != set(CHOICE_LABELS)
                or not isinstance(answer["pair_relations"], dict)
                or set(answer["pair_relations"]) != set(PAIR_LABELS)):
            raise RuntimeError("Blind review lacks exact choice and pair judgments.")
        unavailable = item.get("unavailable") is True
        if unavailable:
            if (answer["independent_answer"] != "unavailable" or not answer["uncertain"]
                    or answer["premise_sufficiency"] != "unavailable"
                    or set(answer["choice_judgments"].values()) != {"unavailable"}
                    or set(answer["pair_relations"].values()) != {"unavailable"}):
                raise RuntimeError("Unavailable row must be recorded as unavailable in every judgment.")
        else:
            chosen = answer["independent_answer"]
            if (chosen not in {*CHOICE_LABELS, "unavailable"}
                    or answer["premise_sufficiency"] not in {"sufficient", "insufficient", "uncertain"}
                    or any(value not in {"correct", "incorrect", "uncertain"}
                           for value in answer["choice_judgments"].values())
                    or any(value not in {"distinct", "equivalent", "uncertain"}
                           for value in answer["pair_relations"].values())
                    or (chosen == "unavailable" and (not answer["uncertain"]
                                                     or answer["premise_sufficiency"] == "sufficient"))
                    or (chosen in CHOICE_LABELS and not answer["uncertain"]
                        and answer["choice_judgments"][chosen] != "correct")):
                raise RuntimeError("Blind review contains an invalid available-row judgment.")


def lock_blind_review(capture_path, plan_path, worksheet_path, private_path, review_path, lock_path,
                      expected_private_hash):
    if lock_path.exists():
        raise RuntimeError("Blind review lock exists; no overwrite is allowed.")
    if not isinstance(expected_private_hash, str) or file_hash(private_path) != expected_private_hash:
        raise RuntimeError("Blind lock requires the exact out-of-band private-map SHA-256.")
    plan, capture = check_projection_plan(plan_path, capture_path)
    review_hash = file_hash(review_path)
    worksheet = json.loads(worksheet_path.read_text())
    private = json.loads(private_path.read_text())
    review = json.loads(review_path.read_text())
    if (worksheet["capture_sha256"] != file_hash(capture_path)
            or worksheet["plan_sha256"] != file_hash(plan_path)
            or private["worksheet_sha256"] != file_hash(worksheet_path)
            or private["capture_sha256"] != worksheet["capture_sha256"]):
        raise RuntimeError("Blind worksheet or capture changed before lock.")
    verify_private_provenance(plan, capture, worksheet, private)
    validate_blind_answers(worksheet["items"], review.get("answers"))
    if (file_hash(capture_path) != worksheet["capture_sha256"]
            or file_hash(plan_path) != worksheet["plan_sha256"]
            or file_hash(worksheet_path) != private["worksheet_sha256"]
            or file_hash(private_path) != expected_private_hash
            or file_hash(review_path) != review_hash):
        raise RuntimeError("Blind evidence changed during lock validation.")
    lock = {"version": 1, "capture_sha256": worksheet["capture_sha256"],
            "worksheet_sha256": file_hash(worksheet_path),
            "private_map_sha256": expected_private_hash,
            "blind_review_sha256": review_hash,
            "locked_at_utc": datetime.now(timezone.utc).isoformat()}
    return write_exclusive_json(lock_path, lock)


def unblind_review(capture_path, plan_path, worksheet_path, private_path, review_path, lock_path,
                   approved_lock_hash, output_path):
    if output_path.exists() or file_hash(lock_path) != approved_lock_hash:
        raise RuntimeError("Unblinding requires the exact saved blind-lock hash and unused output path.")
    plan, capture = check_projection_plan(plan_path, capture_path)
    lock = json.loads(lock_path.read_text())
    if (file_hash(capture_path) != lock["capture_sha256"]
            or file_hash(worksheet_path) != lock["worksheet_sha256"]
            or file_hash(private_path) != lock["private_map_sha256"]
            or file_hash(review_path) != lock["blind_review_sha256"]):
        raise RuntimeError("Blind artifacts changed after lock.")
    worksheet = json.loads(worksheet_path.read_text())
    private = json.loads(private_path.read_text())
    review = json.loads(review_path.read_text())
    if private["worksheet_sha256"] != lock["worksheet_sha256"]:
        raise RuntimeError("Private mapping does not match locked worksheet.")
    verify_private_provenance(plan, capture, worksheet, private)
    validate_blind_answers(worksheet["items"], review.get("answers"))
    combined = {"version": 1, "blind_lock_sha256": approved_lock_hash, "items": []}
    for item in worksheet["items"]:
        source = private["mapping"][item["id"]]
        combined["items"].append({**item, "blind_review": review["answers"][item["id"]],
                                  "source": source})
    if (file_hash(capture_path) != lock["capture_sha256"]
            or file_hash(plan_path) != worksheet["plan_sha256"]
            or file_hash(worksheet_path) != lock["worksheet_sha256"]
            or file_hash(private_path) != lock["private_map_sha256"]
            or file_hash(review_path) != lock["blind_review_sha256"]):
        raise RuntimeError("Blind evidence changed during unblinding.")
    return write_exclusive_json(output_path, combined)


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare", action="store_true", help="write non-executable plan candidate using fake dispatches")
    mode.add_argument("--execute", action="store_true", help="execute separately frozen, reviewed plan")
    mode.add_argument("--blind-project", action="store_true", help="make keyless prose worksheet")
    mode.add_argument("--lock-blind", action="store_true", help="lock independent blind answers")
    mode.add_argument("--unblind", action="store_true", help="unblind only after exact review lock")
    parser.add_argument("--plan-sha256", help="out-of-band approved exact frozen plan hash")
    parser.add_argument("--capture", type=Path, default=HERE / "capture.json")
    parser.add_argument("--capture-sha256", help="exact capture hash printed by execution")
    parser.add_argument("--worksheet", type=Path, default=HERE / "blind-worksheet.json")
    parser.add_argument("--private-map", type=Path, default=HERE / "blind-private-map.json")
    parser.add_argument("--private-map-sha256", help="exact map hash printed by blind projection")
    parser.add_argument("--review", type=Path, default=HERE / "blind-review.json")
    parser.add_argument("--lock", type=Path, default=HERE / "blind-lock.json")
    parser.add_argument("--lock-sha256")
    parser.add_argument("--unblinded", type=Path, default=HERE / "unblinded-review.json")
    args = parser.parse_args()
    if args.prepare:
        path = prepare()
        print(f"{path}: sha256={file_hash(path)}")
    elif args.execute:
        if not args.plan_sha256:
            parser.error("Execution requires --plan-sha256.")
        path = execute(args.plan_sha256, args.capture)
        print(f"{path}: sha256={file_hash(path)}")
    elif args.blind_project:
        if not args.capture_sha256:
            parser.error("Blind projection requires --capture-sha256 from execution.")
        hashes = project_blind(args.capture, HERE / "plan.json", args.worksheet, args.private_map,
                               args.capture_sha256)
        print(json.dumps(hashes, sort_keys=True))
    elif args.lock_blind:
        if not args.private_map_sha256:
            parser.error("Blind lock requires --private-map-sha256 from projection.")
        print(f"blind_lock_sha256={lock_blind_review(args.capture, HERE / 'plan.json', args.worksheet, args.private_map,
                                                     args.review, args.lock, args.private_map_sha256)}")
    else:
        if not args.lock_sha256:
            parser.error("Unblinding requires --lock-sha256.")
        print(f"unblinded_sha256={unblind_review(args.capture, HERE / 'plan.json', args.worksheet, args.private_map,
                                                 args.review, args.lock, args.lock_sha256,
                                                 args.unblinded)}")


if __name__ == "__main__":
    main()
