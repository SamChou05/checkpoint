"""One exact-request diagnostic repeat; preserve only bounded safe AWS details."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

import boto3
import botocore
from botocore.config import Config

HERE = Path(__file__).resolve().parent
PLAN = HERE / "error-diagnostic-plan.json"
CAPTURE = HERE / "error-diagnostic-capture.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def save(path, value, *, exclusive=False):
    text = json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(text)
    else:
        partial = path.with_suffix(".partial")
        partial.write_text(text)
        partial.replace(path)


def _safe_text(value, limit, sensitive_values):
    if type(value) is not str:
        return None
    for secret in sorted((secret for secret in sensitive_values if type(secret) is str and secret), key=len, reverse=True):
        value = value.replace(secret, "[REDACTED]")
    value = re.sub(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b", "[REDACTED]", value)
    value = re.sub(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+", "Bearer [REDACTED]", value)
    value = re.sub(r"(?i)(aws_secret_access_key|aws_session_token|authorization)(\s*[:=]\s*)[^\s,;]+",
                   r"\1\2[REDACTED]", value)
    # Replace malformed Unicode instead of leaking a raw serialization error.
    return value.encode("utf-8", errors="replace").decode("utf-8")[:limit]


def safe_error_details(error, *, sensitive_values=()):
    """No str(error), stack, headers, request body or arbitrary response fields."""
    response = getattr(error, "response", None)
    response = response if type(response) is dict else {}
    failure = response.get("Error")
    failure = failure if type(failure) is dict else {}
    metadata = response.get("ResponseMetadata")
    metadata = metadata if type(metadata) is dict else {}
    status = metadata.get("HTTPStatusCode")
    return {"Error": {"Code": _safe_text(failure.get("Code"), 128, sensitive_values),
                      "Message": _safe_text(failure.get("Message"), 2000, sensitive_values)},
            "HTTPStatus": status if type(status) is int else None,
            "RequestId": _safe_text(metadata.get("RequestId"), 128, sensitive_values)}


def build_plan():
    original = json.loads((HERE / "plan.json").read_text())
    capture = json.loads((HERE / "capture.json").read_text())
    assert capture["plan_sha256"] == sha(HERE / "plan.json")
    assert capture["status"] == "stopped_after_failure" and len(capture["calls"]) == 1
    assert capture["calls"][0]["provider_error_type"] == "ValidationException"
    request = copy.deepcopy(original["jobs"][0]["request"])
    assert request == capture["calls"][0]["request"]
    assert digest(request) == original["jobs"][0]["request_sha256"]
    return {"experiment": "One diagnostic repeat to recover missing AWS ValidationException details",
            "source_failed_plan_sha256": sha(HERE / "plan.json"), "source_failed_capture_sha256": sha(HERE / "capture.json"),
            "source_sha256": {name: sha(HERE / name) for name in ("ERROR_DIAGNOSTIC_PLAN.md", "error_diagnostic.py", "test_error_diagnostic.py")},
            "dependencies": {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__},
            "request": request, "request_sha256": digest(request),
            "limits": {"maximum_calls": 1, "sdk_total_max_attempts": 1, "connect_timeout_seconds": 3, "read_timeout_seconds": 75,
                       "region": "us-east-1", "error_code_characters": 128, "error_message_characters": 2000, "request_id_characters": 128},
            "stop_policy": "One dispatch only, no retries/warmups/resume/replacements. Retain only safe bounded error/status/request-ID details; no model output or reasoning.",
            "claim_limits": "Diagnostic repeat, not rescue or continuation of failed structural qualification. Any unexpected success leaves that trial at0/2 and supplies no semantic/deployment/promotion approval."}


def run_once(client, plan, capture, path, *, sensitive_values=()):
    if capture["calls"] or plan["limits"]["maximum_calls"] != 1:
        raise ValueError("One diagnostic dispatch requires a fresh empty capture.")
    row = {"request_sha256": plan["request_sha256"], "dispatch_attempted": True}
    capture["calls"].append(row)
    save(path, capture)
    started = time.monotonic()
    try:
        client.converse(**copy.deepcopy(plan["request"]))
    except Exception as error:
        row["safe_error"] = safe_error_details(error, sensitive_values=sensitive_values)
        capture["status"] = "completed_with_error_details"
    else:
        capture["status"] = "unexpected_success_no_output_retained"
    finally:
        row["elapsed_seconds"] = round(time.monotonic() - started, 3)
        capture["completed_at"] = datetime.now(timezone.utc).isoformat()
        save(path, capture)


def execute(expected_hash):
    plan = json.loads(PLAN.read_text())
    assert sha(PLAN) == expected_hash and build_plan() == plan
    capture = {"plan_sha256": expected_hash, "calls": [], "status": "preflight", "started_at": datetime.now(timezone.utc).isoformat()}
    save(CAPTURE, capture, exclusive=True)
    credentials = json.loads(subprocess.check_output(["aws", "configure", "export-credentials", "--format", "process"], stderr=subprocess.DEVNULL))
    sensitive_values = tuple(credentials.get(key) for key in ("AccessKeyId", "SecretAccessKey", "SessionToken"))
    client = boto3.client("bedrock-runtime", region_name="us-east-1", aws_access_key_id=credentials["AccessKeyId"],
                         aws_secret_access_key=credentials["SecretAccessKey"], aws_session_token=credentials.get("SessionToken"),
                         config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1}))
    del credentials
    assert (client.meta.config.connect_timeout, client.meta.config.read_timeout, client.meta.config.retries["total_max_attempts"]) == (3, 75, 1)
    run_once(client, plan, capture, CAPTURE, sensitive_values=sensitive_values)
    print(json.dumps({"status": capture["status"], "calls": len(capture["calls"]), "capture_sha256": sha(CAPTURE)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--execute", metavar="PLAN_SHA256")
    args = parser.parse_args()
    if args.prepare:
        save(PLAN, build_plan(), exclusive=True)
        print(json.dumps({"plan_sha256": sha(PLAN), "maximum_calls": 1, "provider_calls": 0}))
    else:
        execute(args.execute)
