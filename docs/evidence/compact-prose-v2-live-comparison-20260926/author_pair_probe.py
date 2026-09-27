"""One-shot, two-arm, author-only comparison of compact mapped prompt revisions.

Freeze a plan offline, review its hash, then execute once. The only wire-request
difference between arms is the native system prompt's opt-in v2 instruction.
"""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
from unittest.mock import patch

import boto3
from botocore.config import Config

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / "backend/bedrock-question-service"
PRIOR = ROOT / "docs/evidence/compact-typed-slots-qualification-20260926"
SOURCE_REVISION = "9477f772641e31a4a5f6ae98dbca4d96695a521e"
PRIOR_PLAN_SHA256 = "3e66ffd544aa05392febf11f57f1d609f44805ac98b5c1bf23bed4263caee62e"
PRIOR_CAPTURE_SHA256 = "020354a65b6029b72a2f087e0f6317a6638878ffb3a1c0143e70e4cd1dfc0fd7"
EXPECTED_ACCOUNT = "239342516379"
ENDPOINT = "https://bedrock-runtime.us-east-1.amazonaws.com"
STS_ENDPOINT = "https://sts.us-east-1.amazonaws.com"
PER_ARM_SECONDS = 220
OVERALL_SECONDS = 470
MIN_CREDENTIAL_LIFETIME_SECONDS = 570
PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"
sys.path.insert(0, str(SERVICE))
import native_output_contracts as native  # noqa: E402
import question_generation as runtime  # noqa: E402
from evals import bounded_bedrock_capture as safe  # noqa: E402


class IntegrityError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise IntegrityError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    return sha(path.read_bytes())


def canonical(value):
    return json.dumps(value, ensure_ascii=True, allow_nan=False,
                      sort_keys=True, separators=(",", ":")).encode()


def save_new(path, value):
    data = (json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2) + "\n").encode()
    with path.open("xb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def update_capture(value, previous_sha):
    require(CAPTURE.exists() and file_sha(CAPTURE) == previous_sha,
            "Capture was modified externally.")
    temporary = CAPTURE.with_suffix(".partial")
    require(not temporary.exists(), "Incomplete capture write exists.")
    with temporary.open("xb") as stream:
        stream.write((json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2) + "\n").encode())
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, CAPTURE)
    return file_sha(CAPTURE)


def baseline():
    require(file_sha(PRIOR / "plan.json") == PRIOR_PLAN_SHA256, "Prior plan drift.")
    require(file_sha(PRIOR / "capture.json") == PRIOR_CAPTURE_SHA256, "Prior capture drift.")
    prior_plan = safe.strict_json((PRIOR / "plan.json").read_text())
    prior_capture = safe.strict_json((PRIOR / "capture.json").read_text())
    request = prior_plan["jobs"][0]["request"]
    expected_environment = prior_plan["environment"]
    baseline_wire = prior_capture["calls"][0]["request"]
    require(prior_capture["calls"][0]["job"] == "mixed"
            and len(prior_plan["jobs"]) == 1 and request["targetCount"] == 5,
            "Baseline is not the original five-slot mixed job.")
    require(expected_environment["BEDROCK_FALLBACK_MODEL_ID"] == ""
            and expected_environment["BEDROCK_MODEL_ID"] == baseline_wire["modelId"],
            "Baseline model or fallback changed.")
    with patch.dict(os.environ, expected_environment, clear=True):
        assignments = runtime._mapped_fixed_slot_assignments(request, "constructed_quantitative", "array")
    require(assignments is not None and [item[2] for item in assignments.values()] == [3, 2],
            "Trusted assignment changed.")
    contract = native.AuthorSlotContract(
        5, "constructed_quantitative",
        tuple((skill_id, objective_id, skill_name, objective_name, count)
              for (skill_id, objective_id), (skill_name, objective_name, count) in assignments.items()),
        request["skillMap"]["skills"][0]["id"], request["minimumDifficulty"],
    )
    require(native.contract_metadata(contract)["name"] == prior_plan["initial_author_contract_name"],
            "Native contract changed.")
    wires = {}
    for arm in ("v1", "v2"):
        environment = {**expected_environment, "QUESTION_MAPPED_PROSE_PROMPT_REVISION": arm}
        with patch.dict(os.environ, environment, clear=True):
            system = native.native_prompt(runtime._system_prompt(), contract)
            user = runtime._user_prompt(request)
            config = native.native_output_config(contract)
        wire = copy.deepcopy(baseline_wire)
        wire["system"] = [{"text": system}]
        require(wire["messages"] == [{"role": "user", "content": [{"text": user}]}]
                and wire["outputConfig"] == config,
                "Current user prompt or native schema differs from baseline.")
        wires[arm] = wire
    require(wires["v1"] == baseline_wire, "Current v1 wire differs from recorded baseline.")
    require(wires["v1"]["system"] != wires["v2"]["system"]
            and {k: v for k, v in wires["v1"].items() if k != "system"}
            == {k: v for k, v in wires["v2"].items() if k != "system"},
            "Arms differ outside the system prompt.")
    require(sha(wires["v1"]["system"][0]["text"].encode()) ==
            "d866eed0f1521ac92f6de1091d4371621c2f5b8b37c69138b1606c57d23f9f30",
            "Baseline prompt pin changed.")
    require(sha(wires["v2"]["system"][0]["text"].encode()) ==
            "c51391f986adb65700cd4dab578b3c86f57a617ef294fe24db35a41dc56f7c1e",
            "Candidate prompt pin changed.")
    require(sha(config["textFormat"]["structure"]["jsonSchema"]["schema"].encode()) ==
            "eee8c873b7892a8b96e510777fe9ffbbc8d10cf70846644ea0993946c9c2bb3c",
            "Accepted schema pin changed.")
    return request, expected_environment, contract, wires


def source_pins():
    paths = [*sorted(SERVICE.glob("*.py")), SERVICE / "evals/bounded_bedrock_capture.py",
             SERVICE / "requirements.txt", PRIOR / "plan.json", PRIOR / "capture.json",
             HERE / "author_pair_probe.py",
             ROOT / "docs/evidence/compact-prose-prompt-v2-offline-20260926/RESULTS.md"]
    return {str(path.relative_to(ROOT)): file_sha(path) for path in paths}


def build_plan(order):
    require(order in (["v1", "v2"], ["v2", "v1"]), "Invalid randomized arm order.")
    require(subprocess.run(("git", "merge-base", "--is-ancestor", SOURCE_REVISION, "HEAD"),
                           cwd=ROOT, capture_output=True, check=False).returncode == 0,
            "Candidate checkout revision changed.")
    request, environment, contract, wires = baseline()
    return {"state": "frozen", "purpose": "author_only_prompt_revision_comparison",
            "source_revision": SOURCE_REVISION,
            "request_sha256": sha(canonical(request)),
            "environment": environment,
            "native_contract": native.contract_metadata(contract),
            "arm_order": order,
            "arm_wires": wires,
            "arm_wire_sha256": {arm: sha(canonical(wire)) for arm, wire in wires.items()},
            "source_sha256": source_pins(),
            "budget": {"provider_author_calls": 2, "per_arm_seconds": PER_ARM_SECONDS,
                       "overall_seconds": OVERALL_SECONDS, "sdk_attempts_per_call": 1,
                       "fallback": False, "repair": False, "top_up": False},
            "identity": {"account": EXPECTED_ACCOUNT, "region": "us-east-1",
                         "bedrock_endpoint": ENDPOINT, "sts_endpoint": STS_ENDPOINT,
                         "minimum_credential_lifetime_seconds": MIN_CREDENTIAL_LIFETIME_SECONDS}}


def validate_frozen(plan, expected_sha):
    require(file_sha(PLAN) == expected_sha and plan == build_plan(plan["arm_order"]),
            "Frozen plan, source, or fixture drift.")


def freeze():
    require(not PLAN.exists() and not CAPTURE.exists(), "Trial already frozen or executed.")
    order = ["v1", "v2"] if secrets.randbelow(2) == 0 else ["v2", "v1"]
    plan = build_plan(order)
    save_new(PLAN, plan)
    return {"plan_sha256": file_sha(PLAN), "arm_order": order,
            "arm_wire_sha256": plan["arm_wire_sha256"], "provider_calls": 0}


def credential_session():
    forbidden = ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
                 "AWS_SECURITY_TOKEN", "AWS_WEB_IDENTITY_TOKEN_FILE", "AWS_ROLE_ARN",
                 "AWS_ENDPOINT_URL", "AWS_CONFIG_FILE", "AWS_SHARED_CREDENTIALS_FILE")
    require(not any(os.getenv(name) for name in forbidden), "Identity or endpoint override present.")
    require(os.getenv("AWS_PROFILE", "default") in ("", "default")
            and os.getenv("AWS_DEFAULT_PROFILE", "default") in ("", "default")
            and not any(name.startswith("AWS_ENDPOINT_URL") and value
                        for name, value in os.environ.items()),
            "AWS profile or endpoint override present.")
    prior_plan = safe.strict_json((PRIOR / "plan.json").read_text())
    config_path = Path.home() / ".aws/config"
    require(config_path.is_file() and not config_path.is_symlink()
            and file_sha(config_path) == prior_plan["model_and_transport"]["aws_config_sha256"],
            "Default AWS login configuration changed.")
    raw = safe.export_credentials()
    data = safe.strict_json(raw.decode())
    require(type(data) is dict and data.get("Version") == 1, "Credential format changed.")
    expires = datetime.fromisoformat(data["Expiration"].replace("Z", "+00:00"))
    require((expires - datetime.now(timezone.utc)).total_seconds() >= MIN_CREDENTIAL_LIFETIME_SECONDS,
            "Credentials expire before the bounded comparison.")
    fields = ("AccessKeyId", "SecretAccessKey", "SessionToken")
    require(all(type(data.get(field)) is str and data[field] for field in fields),
            "Credential field missing.")
    session = boto3.Session(aws_access_key_id=data["AccessKeyId"],
                            aws_secret_access_key=data["SecretAccessKey"],
                            aws_session_token=data["SessionToken"], region_name="us-east-1")
    return session, tuple(data[field] for field in fields), expires


def execute(expected_sha):
    require(PLAN.exists() and not CAPTURE.exists(), "Trial has not been frozen or has run.")
    plan = safe.strict_json(PLAN.read_text())
    validate_frozen(plan, expected_sha)
    capture = {"plan_sha256": expected_sha, "state": "started",
               "started_at": datetime.now(timezone.utc).isoformat(),
               "arm_order": plan["arm_order"], "identity": "unattempted", "calls": [],
               "slots": {arm: "unattempted" for arm in ("v1", "v2")}}
    save_new(CAPTURE, capture)
    current_sha = file_sha(CAPTURE)
    started = time.monotonic()
    secrets_used = ()
    try:
        session, secrets_used, expiration = credential_session()
        sts = session.client("sts", endpoint_url=STS_ENDPOINT,
                             config=Config(connect_timeout=3, read_timeout=10,
                                           retries={"total_max_attempts": 1, "mode": "standard"}))
        require(sts.get_caller_identity()["Account"] == EXPECTED_ACCOUNT,
                "AWS account mismatch.")
        capture["identity"] = "verified"
        current_sha = update_capture(capture, current_sha)
        for arm in plan["arm_order"]:
            validate_frozen(plan, expected_sha)
            remaining = OVERALL_SECONDS - (time.monotonic() - started)
            require(remaining >= 15, "Overall deadline exhausted before next arm.")
            require((expiration - datetime.now(timezone.utc)).total_seconds() > 15,
                    "Credentials expired before next arm.")
            read_timeout = min(200, PER_ARM_SECONDS - 5, int(remaining) - 5)
            client = session.client("bedrock-runtime", region_name="us-east-1",
                                    endpoint_url=ENDPOINT,
                                    config=Config(connect_timeout=3, read_timeout=read_timeout,
                                                  retries={"total_max_attempts": 1, "mode": "standard"}))
            require(client.meta.endpoint_url == ENDPOINT and client.meta.region_name == "us-east-1"
                    and client.meta.config.retries.get("total_max_attempts") == 1,
                    "Bedrock transport changed.")
            wire = plan["arm_wires"][arm]
            require(sha(canonical(wire)) == plan["arm_wire_sha256"][arm], "Wire request drift.")
            call = {"arm": arm, "wire_sha256": plan["arm_wire_sha256"][arm],
                    "started_at": datetime.now(timezone.utc).isoformat(), "state": "reserved"}
            capture["slots"][arm] = "reserved"
            capture["calls"].append(call)
            current_sha = update_capture(capture, current_sha)
            call_started = time.monotonic()
            try:
                response = client.converse(**wire)
                retained, reasoning_blocks = safe.safe_response(response, secrets_used)
                require(not any(secret and secret in canonical(retained).decode() for secret in secrets_used),
                        "Credential echo detected in response.")
                call["response"] = retained
                call["reasoning_content_block_count"] = reasoning_blocks
                text = "\n".join(block["text"] for block in retained["output"]["message"]["content"]).strip()
                try:
                    adapted = native.adapt_native_response(text, baseline()[2])
                    call["adapted"] = safe.strict_json(adapted)
                    call["state"] = "native_adapted"
                except Exception as error:
                    call["state"] = "native_adaptation_failed"
                    call["error"] = {"type": type(error).__name__}
            except Exception as error:
                call["state"] = "provider_or_capture_failed"
                call["error"] = safe.safe_error(error, secrets_used)
            call["elapsed_seconds"] = round(time.monotonic() - call_started, 3)
            call["finished_at"] = datetime.now(timezone.utc).isoformat()
            capture["slots"][arm] = call["state"]
            current_sha = update_capture(capture, current_sha)
        capture["state"] = "complete"
    except BaseException as error:
        capture["state"] = "aborted"
        capture["error"] = {"type": type(error).__name__}
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            current_sha = update_capture(capture, current_sha)
            raise
    capture["elapsed_seconds"] = round(time.monotonic() - started, 3)
    capture["finished_at"] = datetime.now(timezone.utc).isoformat()
    update_capture(capture, current_sha)
    return {"capture_sha256": file_sha(CAPTURE), "state": capture["state"],
            "calls": len(capture["calls"]), "slots": capture["slots"]}


def preflight():
    request, environment, contract, wires = baseline()
    require(len(wires) == 2 and request["targetCount"] == 5
            and environment["BEDROCK_MODEL_ID"] == wires["v1"]["modelId"],
            "Offline paired fixture changed.")
    return {"status": "offline_ready", "source_revision": SOURCE_REVISION,
            "request_sha256": sha(canonical(request)),
            "system_prompt_sha256": {arm: sha(wire["system"][0]["text"].encode())
                                     for arm, wire in wires.items()},
            "native_schema_sha256": sha(wires["v1"]["outputConfig"]["textFormat"]
                                         ["structure"]["jsonSchema"]["schema"].encode()),
            "wire_difference": "system[0].text only", "provider_calls": 0}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--preflight", action="store_true")
    group.add_argument("--freeze", action="store_true")
    group.add_argument("--execute", metavar="PLAN_SHA256")
    args = parser.parse_args()
    result = preflight() if args.preflight else freeze() if args.freeze else execute(args.execute)
    print(json.dumps(result, ensure_ascii=True, indent=2))
