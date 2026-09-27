"""Frozen, one-shot, answer-key-blind pairwise diversity diagnostic."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT / "docs/evidence/generic-reserve-seven-probe-v4-20260927/capture.json"
REQUEST = HERE / "request.json"
PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"
MODEL = "us.anthropic.claude-sonnet-4-6"
ACCOUNT = "239342516379"
PAIRS = [f"p{i}{j}" for i in range(1, 7) for j in range(i + 1, 7)]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strict_json(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=unique)


def save_new(path, data):
    raw = (json.dumps(data, ensure_ascii=True, indent=2, allow_nan=False) + "\n").encode()
    with path.open("xb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    descriptor = os.open(HERE, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def replace_capture(data):
    temp = HERE / "capture.partial"
    if temp.exists():
        raise RuntimeError("capture temporary file already exists")
    raw = (json.dumps(data, ensure_ascii=True, indent=2, allow_nan=False) + "\n").encode()
    with temp.open("xb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, CAPTURE)
    descriptor = os.open(HERE, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def input_questions():
    source = strict_json(SOURCE.read_text())
    rows = source["original_rows"]
    selected = [row for row in rows if isinstance(row, dict) and isinstance(row.get("verified_question"), dict)]
    if [row["ordinal"] for row in selected] != list(range(1, 7)):
        raise ValueError("expected exactly verified source ordinals 1 through 6")
    questions = []
    for row in selected:
        question = row["verified_question"]
        prompt, choices = question["prompt"], question["choices"]
        if not isinstance(prompt, str) or not isinstance(choices, list) or len(choices) != 4 or not all(isinstance(c, str) for c in choices):
            raise ValueError("invalid visible question")
        questions.append({"id": row["ordinal"], "prompt": prompt, "choices": choices})
    return questions


def make_request():
    questions = input_questions()
    schema = {
        "type": "object", "properties": {pair: {"type": "boolean"} for pair in PAIRS},
        "required": PAIRS, "additionalProperties": False,
    }
    system = (
        "Judge ONLY whether each pair of the six multiple-choice questions materially repeats "
        "the same central learner decision or operation AND the same answer format. "
        "A changed story, objects, numbers, or wording does not make a repeated operation distinct. "
        "A shared broad topic alone does not make different operations a repeat. "
        "For every pair pIJ, where I and J are question ids, set true only when both conditions hold; "
        "otherwise set false. Inspect the prompts and four choices only. "
        "Do not solve, grade, teach, infer answer keys, or assess any other quality. "
        "Return only the fifteen booleans required by the schema."
    )
    wire = {
        "modelId": MODEL,
        "system": [{"text": system}],
        "messages": [{"role": "user", "content": [{"text": json.dumps({"questions": questions}, ensure_ascii=False, separators=(",", ":"))}]}],
        "inferenceConfig": {"maxTokens": 1200, "temperature": 0},
        "additionalModelRequestFields": {"thinking": {"type": "disabled"}},
        "outputConfig": {"textFormat": {"type": "json_schema", "structure": {"jsonSchema": {
            "name": "pairwise_material_repetition_v1", "schema": json.dumps(schema, ensure_ascii=True, separators=(",", ":")),
        }}}},
    }
    return wire, questions, schema


def freeze():
    if any(path.exists() for path in (PLAN, REQUEST, CAPTURE)):
        raise RuntimeError("trial files already exist")
    wire, questions, schema = make_request()
    save_new(REQUEST, wire)
    plan = {
        "state": "frozen", "trial_id": "generic-reserve-pairwise-diversity-20260927-01",
        "source_capture": str(SOURCE.relative_to(ROOT)), "source_capture_sha256": sha(SOURCE),
        "source_ordinals": [q["id"] for q in questions], "visible_fields": ["prompt", "choices"],
        "question_count": 6, "pair_ids": PAIRS, "pair_count": 15,
        "model": MODEL, "region": "us-east-1", "account": ACCOUNT,
        "maximum_converse_attempts": 1, "sdk_total_max_attempts": 1,
        "request_sha256": sha(REQUEST), "harness_sha256": sha(Path(__file__)),
        "schema_sha256": hashlib.sha256(wire["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"].encode()).hexdigest(),
        "credential_source": "AWS CLI default profile, no inherited credential overrides",
        "cli_connect_timeout_seconds": 3, "cli_read_timeout_seconds": 120,
        "credential_export_timeout_seconds": 15,
        "response_capture": "visible text and bounded usage only; no reasoning, signatures, credentials, or raw error text",
        "no_retry_or_repair": True,
    }
    save_new(PLAN, plan)
    return {"plan_sha256": sha(PLAN), "request_sha256": sha(REQUEST), "harness_sha256": sha(Path(__file__)), "source_sha256": sha(SOURCE)}


def verify_frozen(expected):
    if sha(PLAN) != expected:
        raise RuntimeError("plan hash mismatch")
    plan = strict_json(PLAN.read_text())
    if plan["state"] != "frozen" or plan["source_capture_sha256"] != sha(SOURCE) or plan["request_sha256"] != sha(REQUEST) or plan["harness_sha256"] != sha(Path(__file__)):
        raise RuntimeError("frozen file hash mismatch")
    if strict_json(REQUEST.read_text()) != make_request()[0]:
        raise RuntimeError("request differs from source-derived wire")
    if plan["pair_ids"] != PAIRS or plan["maximum_converse_attempts"] != 1 or plan["account"] != ACCOUNT:
        raise RuntimeError("trial contract mismatch")
    return plan


def aws_env():
    if any(key in os.environ for key in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_ROLE_ARN", "AWS_WEB_IDENTITY_TOKEN_FILE", "AWS_CONFIG_FILE", "AWS_SHARED_CREDENTIALS_FILE")):
        raise RuntimeError("AWS identity override in environment")
    if any(key.startswith("AWS_ENDPOINT_URL") for key in os.environ):
        raise RuntimeError("AWS endpoint override in environment")
    env = os.environ.copy()
    env.update(AWS_PROFILE="default", AWS_DEFAULT_PROFILE="default", AWS_REGION="us-east-1",
               AWS_DEFAULT_REGION="us-east-1", AWS_MAX_ATTEMPTS="1", AWS_RETRY_MODE="standard",
               AWS_IGNORE_CONFIGURED_ENDPOINT_URLS="true")
    return env


def precheck(expected):
    plan = verify_frozen(expected)
    env = aws_env()
    version = subprocess.run(["aws", "--version"], capture_output=True, text=True, timeout=5, env=env)
    if version.returncode or not (version.stdout + version.stderr).startswith("aws-cli/2.33.15 "):
        raise RuntimeError("AWS CLI version mismatch")
    # This is an offline shape check: skeleton generation never dispatches Converse.
    skeleton = subprocess.run(["aws", "bedrock-runtime", "converse", "--generate-cli-skeleton", "input"],
                              capture_output=True, text=True, timeout=10, env=env)
    if skeleton.returncode or "outputConfig" not in skeleton.stdout:
        raise RuntimeError("CLI Converse input shape lacks native outputConfig")
    return {"plan_sha256": expected, "request_sha256": plan["request_sha256"],
            "aws_cli": (version.stdout + version.stderr).split()[0], "native_shape_available": True,
            "provider_calls": 0}


def execute(expected):
    plan = verify_frozen(expected)
    env = aws_env()
    if CAPTURE.exists():
        raise RuntimeError("one-shot capture already exists")
    capture = {"plan_sha256": expected, "request_sha256": plan["request_sha256"],
               "source_capture_sha256": plan["source_capture_sha256"], "status": "reserved",
               "started_at": datetime.now(timezone.utc).isoformat(), "converse_attempts_reserved": 1,
               "converse_attempts_dispatched": 0, "account": None, "pair_flags": None,
               "elapsed_converse_seconds": None, "visible_response": None, "usage": None}
    save_new(CAPTURE, capture)
    start = time.monotonic()
    try:
        identity = subprocess.run(["aws", "sts", "get-caller-identity", "--region", "us-east-1",
                                   "--cli-connect-timeout", "3", "--cli-read-timeout", "10", "--output", "json"],
                                  capture_output=True, text=True, timeout=20, env=env)
        if identity.returncode or strict_json(identity.stdout).get("Account") != ACCOUNT:
            raise RuntimeError("STS account identity check failed")
        capture["account"] = ACCOUNT
        capture["status"] = "dispatch_attempted"
        capture["converse_attempts_dispatched"] = 1
        replace_capture(capture)
        # One CLI invocation, with retry count fixed at one. No retry or fallback path exists.
        response = subprocess.run(["aws", "bedrock-runtime", "converse", "--region", "us-east-1",
                                   "--cli-input-json", "file://" + str(REQUEST),
                                   "--cli-connect-timeout", "3", "--cli-read-timeout", "120",
                                   "--output", "json"], capture_output=True, text=True,
                                  timeout=135, env=env)
        capture["elapsed_converse_seconds"] = round(time.monotonic() - start, 6)
        if response.returncode:
            # Error strings are intentionally discarded; retain only a bounded CLI exit status.
            capture["status"] = "provider_error"
            capture["error"] = {"type": "AwsCliFailure", "exit_code": response.returncode}
        else:
            data = strict_json(response.stdout)
            blocks = data.get("output", {}).get("message", {}).get("content", [])
            texts = [block["text"] for block in blocks if isinstance(block, dict) and isinstance(block.get("text"), str)]
            if len(texts) != 1 or len(texts[0].encode()) > 100000:
                raise ValueError("visible response text bound failed")
            visible = strict_json(texts[0])
            if list(visible) != PAIRS or any(type(visible[key]) is not bool for key in PAIRS):
                raise ValueError("response violates fixed pair boolean contract")
            capture["visible_response"] = texts[0]
            capture["pair_flags"] = visible
            capture["usage"] = {k: v for k, v in data.get("usage", {}).items()
                                if k in ("inputTokens", "outputTokens", "totalTokens") and type(v) is int and 0 <= v <= 1000000000}
            capture["stop_reason"] = re.sub(r"[^A-Za-z_]", "", str(data.get("stopReason", "")))[:40]
            capture["status"] = "completed"
    except Exception as error:
        capture["status"] = "failed"
        capture["error"] = {"type": type(error).__name__}
    finally:
        capture["whole_execute_seconds"] = round(time.monotonic() - start, 6)
        replace_capture(capture)
    return {"status": capture["status"], "capture_sha256": sha(CAPTURE),
            "whole_execute_seconds": capture["whole_execute_seconds"], "pair_flags": capture["pair_flags"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--freeze", action="store_true")
    group.add_argument("--precheck", metavar="PLAN_SHA256")
    group.add_argument("--execute", metavar="PLAN_SHA256")
    args = parser.parse_args()
    result = freeze() if args.freeze else precheck(args.precheck) if args.precheck else execute(args.execute)
    print(json.dumps(result, ensure_ascii=True, sort_keys=True))
