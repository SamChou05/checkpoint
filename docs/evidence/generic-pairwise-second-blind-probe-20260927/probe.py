#!/usr/bin/env python3
"""Run one frozen AWS CLI Converse request and save a filtered capture."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from datetime import datetime, timezone


HERE = Path(__file__).resolve().parent
PAIR_KEYS = [f"p{i}{j}" for i in range(1, 7) for j in range(i + 1, 7)]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def write_exclusive(path, obj):
    with path.open("x", encoding="utf-8") as handle:
        json.dump(obj, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def main():
    freeze = json.loads((HERE / "freeze.json").read_text(encoding="utf-8"))
    for name in ("plan.json", "request.json", "probe.py"):
        actual = sha256(HERE / name)
        if actual != freeze["sha256"][name]:
            raise RuntimeError(f"frozen hash mismatch: {name}")

    request = json.loads((HERE / "request.json").read_text(encoding="utf-8"))
    questions = json.loads(request["messages"][0]["content"][0]["text"])["questions"]
    assert len(questions) == 6
    assert all(set(q) == {"id", "prompt", "choices"} and len(q["choices"]) == 4 for q in questions)
    schema = json.loads(request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
    assert schema["required"] == PAIR_KEYS and schema["additionalProperties"] is False

    started = now()
    write_exclusive(HERE / "attempt.json", {
        "startedAtUtc": started,
        "operation": "aws bedrock-runtime converse",
        "maxAttempts": 1,
        "requestSha256": freeze["sha256"]["request.json"],
    })
    env = os.environ.copy()
    env["AWS_MAX_ATTEMPTS"] = "1"
    env["AWS_RETRY_MODE"] = "standard"
    command = [
        "aws", "bedrock-runtime", "converse",
        "--cli-input-json", f"file://{HERE / 'request.json'}",
        "--region", "us-east-1",
        "--output", "json",
        "--no-cli-pager",
        "--cli-connect-timeout", "10",
        "--cli-read-timeout", "120",
    ]
    t0 = time.monotonic()
    process = subprocess.run(command, capture_output=True, text=True, env=env, check=False)
    elapsed_ms = round((time.monotonic() - t0) * 1000)
    capture = {
        "startedAtUtc": started,
        "finishedAtUtc": now(),
        "elapsedMs": elapsed_ms,
        "account": "239342516379",
        "modelId": request["modelId"],
        "region": "us-east-1",
        "cliMaxAttempts": 1,
        "exitCode": process.returncode,
        "freezeSha256": sha256(HERE / "freeze.json"),
        "requestSha256": freeze["sha256"]["request.json"],
    }
    if process.returncode == 0:
        try:
            response = json.loads(process.stdout)
            blocks = response.get("output", {}).get("message", {}).get("content", [])
            texts = [block["text"] for block in blocks if "text" in block]
            if len(texts) != 1:
                capture.update(status="unexpected_content", textBlockCount=len(texts))
            else:
                flags = json.loads(texts[0])
                if set(flags) != set(PAIR_KEYS) or any(type(v) is not bool for v in flags.values()):
                    capture.update(status="invalid_schema_response")
                else:
                    capture.update(status="success", pairFlags={key: flags[key] for key in PAIR_KEYS})
            capture["stopReason"] = response.get("stopReason")
            capture["usage"] = response.get("usage")
            capture["metrics"] = response.get("metrics")
        except (ValueError, TypeError, KeyError):
            capture.update(status="unparseable_response")
    else:
        message = process.stderr.strip().splitlines()
        last = message[-1] if message else ""
        match = re.search(r"An error occurred \(([^)]+)\)", last)
        capture.update(status="cli_error", errorType=match.group(1) if match else "unknown")
    write_exclusive(HERE / "capture.json", capture)
    print(json.dumps(capture, ensure_ascii=False, indent=2))
    return 0 if capture["status"] == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
