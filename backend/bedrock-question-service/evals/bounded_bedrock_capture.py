"""Eval-only credentials and response filtering, with no runtime imports or calls.

Importing capture helpers must not select a production checkout or run inference.
Callers own their frozen requests, budgets, source pins and admission criteria.
"""

import json
import math
import os
import re
import selectors
import subprocess
import time

import boto3


CREDENTIAL_COMMAND = ("aws", "configure", "export-credentials", "--format", "process")
CREDENTIAL_TIMEOUT_SECONDS = 15
CREDENTIAL_MAX_BYTES = 32768
VISIBLE_RESPONSE_MAX_BYTES = 1024 * 1024
USAGE_FIELDS = ("inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens", "cacheWriteInputTokens")


class CaptureBoundaryError(ValueError):
    """A capture cannot safely retain or use its input; no input text is echoed."""


def strict_json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise CaptureBoundaryError("Duplicate JSON property.")
            result[key] = value
        return result

    def nonfinite(_):
        raise CaptureBoundaryError("Nonfinite JSON number.")

    def finite(value):
        parsed = float(value)
        if not math.isfinite(parsed):
            raise CaptureBoundaryError("Nonfinite JSON number.")
        return parsed

    return json.loads(text, object_pairs_hook=unique, parse_constant=nonfinite, parse_float=finite)


def export_credentials():
    """Read CLI credentials into memory with independent time and byte limits."""
    process = subprocess.Popen(CREDENTIAL_COMMAND, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    data = bytearray()
    deadline = time.monotonic() + CREDENTIAL_TIMEOUT_SECONDS
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise CaptureBoundaryError("Credential export exceeded its time bound.")
                chunk = os.read(process.stdout.fileno(), min(4096, CREDENTIAL_MAX_BYTES + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > CREDENTIAL_MAX_BYTES:
                    raise CaptureBoundaryError("Credential export exceeded its size bound.")
        if process.wait(timeout=max(0.001, deadline - time.monotonic())) != 0:
            raise CaptureBoundaryError("Credential export failed.")
        return bytes(data)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=3)
        process.stdout.close()


def credential_session():
    credentials = strict_json(export_credentials().decode("utf-8"))
    if type(credentials) is not dict or type(credentials.get("Version")) is not int or credentials["Version"] != 1:
        raise CaptureBoundaryError("Credential process format is invalid.")
    for field, maximum in (("AccessKeyId", 128), ("SecretAccessKey", 256), ("SessionToken", 16384)):
        value = credentials.get(field)
        if field == "SessionToken" and value is None:
            continue
        if type(value) is not str or not value or len(value) > maximum:
            raise CaptureBoundaryError("Credential process field is invalid.")
    secrets = tuple(credentials[field] for field in ("AccessKeyId", "SecretAccessKey", "SessionToken") if credentials.get(field))
    return boto3.Session(aws_access_key_id=credentials["AccessKeyId"],
                         aws_secret_access_key=credentials["SecretAccessKey"],
                         aws_session_token=credentials.get("SessionToken"), region_name="us-east-1"), secrets


def redact(value, secrets=(), *, maximum=2000):
    if type(value) is not str:
        return None
    for secret in sorted((secret for secret in secrets if type(secret) is str and secret), key=len, reverse=True):
        value = value.replace(secret, "[REDACTED_CREDENTIAL]")
    value = re.sub(r'https?://[^\s<>"\']+', "[REDACTED_URL]", value)
    value = re.sub(r'(?i)\bofferToken\s*[:=]\s*(?:"[^"]*"|[^\s,;]+)', "offerToken=[REDACTED]", value)
    return value.encode("utf-8", errors="replace").decode()[:maximum]


def bounded_numbers(values, allowed):
    if type(values) is not dict:
        return {}
    return {key: values[key] for key in allowed if key in values
            and type(values[key]) in {int, float} and math.isfinite(values[key])
            and 0 <= values[key] <= 1_000_000_000_000}


def safe_response(response, secrets=()):
    """Preserve exact visible text; omit native reasoning and unneeded metadata."""
    content = response.get("output", {}).get("message", {}).get("content", [])
    texts = [{"text": block["text"]} for block in content if type(block) is dict
             and "reasoningContent" not in block and type(block.get("text")) is str]
    if sum(len(block["text"].encode("utf-8")) for block in texts) > VISIBLE_RESPONSE_MAX_BYTES:
        raise CaptureBoundaryError("Visible response exceeds capture allowance.")
    retained = {"output": {"message": {"content": texts}},
                "stopReason": redact(response.get("stopReason", ""), secrets, maximum=128),
                "usage": bounded_numbers(response.get("usage"), USAGE_FIELDS),
                "metrics": bounded_numbers(response.get("metrics"), ("latencyMs",))}
    metadata = response.get("ResponseMetadata", {})
    if type(metadata) is dict:
        retained["safeResponseMetadata"] = {
            "requestId": redact(metadata.get("RequestId", ""), secrets, maximum=128),
            "httpStatus": metadata.get("HTTPStatusCode") if type(metadata.get("HTTPStatusCode")) is int else None}
    return retained, sum(type(block) is dict and "reasoningContent" in block for block in content)


def safe_error(error, secrets=()):
    response = getattr(error, "response", {})
    response = response if type(response) is dict else {}
    problem, metadata = response.get("Error", {}), response.get("ResponseMetadata", {})
    problem = problem if type(problem) is dict else {}
    metadata = metadata if type(metadata) is dict else {}
    return {"type": type(error).__name__, "code": redact(problem.get("Code"), secrets, maximum=128),
            "message": redact(problem.get("Message"), secrets),
            "request_id": redact(metadata.get("RequestId"), secrets, maximum=128),
            "http_status": metadata.get("HTTPStatusCode") if type(metadata.get("HTTPStatusCode")) is int else None}
