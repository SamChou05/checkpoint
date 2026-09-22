"""Frozen-request reviewer comparison; prepare/check are offline, execute is explicit.

Dispatch imports only the native adapter and its error types. The evolving final
review orchestration and positional-reference helper are deliberately not loaded.
"""

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

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402
from native_output_contracts import adapt_native_response, contract_metadata  # noqa: E402

PLAN = HERE / "reviewer-anchoring-plan.json"
MANIFEST = HERE / "reviewer-anchoring-execution.json"
CAPTURE = HERE / "reviewer-anchoring-capture.json"
PLAN_SHA = "57f1579949bd230ae178ae481cd57a3937e3042ade9b049e14311032e1a5e50e"
CONTRACT = "default_reviewer_v1"
PREFIX = "<question_review_json>\n"
SUFFIX = "\n</question_review_json>"


def sha(value):
    return hashlib.sha256(value).hexdigest()


def canonical(value):
    # Matches the immutable prospective plan's request hashing definition.
    return json.dumps(value, sort_keys=True, ensure_ascii=False).encode()


def save(path, value, *, exclusive=False):
    encoded = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(encoded)
    else:
        temporary = path.with_suffix(".partial")
        temporary.write_text(encoded)
        temporary.replace(path)


def dependencies():
    return {"python": sys.version.split()[0], "boto3": boto3.__version__,
            "botocore": botocore.__version__}


def source_hashes():
    files = (Path(__file__), SERVICE / "native_output_contracts.py", SERVICE / "service_errors.py")
    return {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in files}


def user_data(request):
    text = request["messages"][0]["content"][0]["text"]
    if not text.startswith(PREFIX) or not text.endswith(SUFFIX):
        raise ValueError("Unexpected frozen user payload.")
    return json.loads(text[len(PREFIX):-len(SUFFIX)])


def load_plan():
    raw = PLAN.read_bytes()
    if sha(raw) != PLAN_SHA:
        raise RuntimeError("Original prospective plan changed.")
    plan = json.loads(raw)
    if plan["dependencies"] != dependencies():
        raise RuntimeError("Planned dependencies changed.")
    if plan["registered_contract"] != contract_metadata(CONTRACT):
        raise RuntimeError("Native reviewer contract changed.")
    if len(plan["calls"]) != 4:
        raise RuntimeError("Expected four fixed calls.")
    for sequence, call in enumerate(plan["calls"]):
        request = call["provider_request"]
        if sequence != call["sequence"] or sha(canonical(request)) != call["request_sha256"]:
            raise RuntimeError("Frozen request changed.")
        if request["modelId"] != "us.anthropic.claude-sonnet-4-6":
            raise RuntimeError("Unplanned model.")
        if request["inferenceConfig"] != {"maxTokens": 6000, "temperature": 0.2}:
            raise RuntimeError("Unplanned sampling settings.")
        if request.get("additionalModelRequestFields") != {"thinking": {"type": "disabled"}}:
            raise RuntimeError("Unplanned thinking mode.")
        data = user_data(request)
        if len(data["items"]) != 5 or [item["index"] for item in data["items"]] != list(range(5)):
            raise RuntimeError("Unexpected frozen batch.")
    for job in (0, 1):
        arms = {c["arm"]: c["provider_request"] for c in plan["calls"] if c["job_index"] == job}
        baseline, treatment = copy.deepcopy(arms["with_solutions"]), copy.deepcopy(arms["without_solutions"])
        bp, tp = user_data(baseline), user_data(treatment)
        del bp["independentSolutions"]
        if bp != tp:
            raise RuntimeError("Treatment changes more than the intended field.")
        baseline["messages"][0]["content"][0]["text"] = treatment["messages"][0]["content"][0]["text"]
        if baseline != treatment:
            raise RuntimeError("Non-payload request differences.")
    return plan


def prepare():
    plan = load_plan()
    manifest = {
        "experiment": "Executable freeze for unchanged reviewer anchoring plan",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "plan_path": str(PLAN.relative_to(ROOT)), "plan_sha256": PLAN_SHA,
        "dispatch_source_sha256": source_hashes(), "dependencies": dependencies(),
        "source_binding": "This manifest supersedes only the original plan's all-service execution dependency check. Its source hashes remain historical preparation provenance. Exact frozen requests, prospective criteria, order, settings, maximum calls and stop rules are unchanged. No question_verification.py code is imported or executed; its helper may evolve independently.",
        "validation_scope": "Use the actual frozen default_reviewer_v1 native adapter for JSON/schema/negative adaptation, then frozen experiment-local index coverage, exact key, difficulty, feedback coverage/bounds and original answer-letter predicates. This is a provider-input comparison, not a replay of evolving production orchestration or a new policy stamp. Independently adjudicate semantic and positional-reference correctness across every returned feedback item.",
        "maximum_provider_calls": 4, "sdk_total_max_attempts": 1,
        "connect_timeout_seconds": 3, "read_timeout_seconds": 75,
        "region": "us-east-1", "capture_path": str(CAPTURE.relative_to(ROOT)),
        "native_contract": plan["registered_contract"],
    }
    save(MANIFEST, manifest, exclusive=True)
    print(json.dumps({"manifest_sha256": sha(MANIFEST.read_bytes()), "plan_sha256": PLAN_SHA}))


def preflight(expected_hash):
    raw = MANIFEST.read_bytes()
    manifest = json.loads(raw)
    if sha(raw) != expected_hash or manifest["plan_sha256"] != PLAN_SHA:
        raise RuntimeError("Execution manifest changed.")
    if manifest["dispatch_source_sha256"] != source_hashes() or manifest["dependencies"] != dependencies():
        raise RuntimeError("Executable dependency freeze changed.")
    if "question_verification" in sys.modules:
        raise RuntimeError("Unexpected import of evolving reviewer orchestration.")
    return load_plan(), manifest


def assess(response, call, plan):
    """Structural failure raises; semantic/admission failures remain scored output."""
    if response.get("stopReason") != "end_turn":
        raise ValueError("Non-end_turn response.")
    blocks = response["output"]["message"]["content"]
    text = "".join(block["text"] for block in blocks if "text" in block)
    adapted = json.loads(adapt_native_response(text, CONTRACT))
    rows = adapted["reviews"]
    if len(rows) != 5:
        raise ValueError("Incomplete reviewer batch.")
    by_index = {}
    for row in rows:
        index = row.get("index")
        if type(index) is not int or index not in range(5) or index in by_index:
            raise ValueError("Invalid or duplicate review index.")
        by_index[index] = row
    items = user_data(call["provider_request"])["items"]
    gold = {item["item_index"]: item for item in plan["gold_items"] if item["job_index"] == call["job_index"]}
    assessments = []
    for index, item in enumerate(items):
        row, expected = by_index[index], gold[index]
        valid = row["valid"] is True
        if not valid:
            assessments.append({"index": index, "valid": False, "false_rejection": True,
                                "local_admission_pass": False, "semantic_adjudication": "pending"})
            continue
        explanation, feedback = row["explanation"], row["choiceExplanations"]
        difficulty = row["difficulty"]
        exact_coverage = set(feedback) == set(item["choices"])
        bounded = 12 <= len(explanation.strip()) <= 420 and len(explanation) <= 420 and all(
            type(value) is str and 12 <= len(value.strip()) <= 280 and len(value) <= 280
            for value in feedback.values()
        )
        old_answer_labels = any(re.search(r"\b(?:choice|option|answer)\s+[A-D]\b", value, re.I)
                                for value in [explanation, *feedback.values()])
        correct_key = row["answer"] == expected["expected_answer"]
        difficulty_typed = type(difficulty) is int and 1 <= difficulty <= 5
        minimum_met = difficulty_typed and difficulty >= 2
        assessments.append({
            "index": index, "valid": True, "false_rejection": False,
            "exact_gold_key": correct_key, "exact_feedback_coverage": exact_coverage,
            "feedback_within_bounds": bounded, "original_answer_letter_predicate": old_answer_labels,
            "difficulty": difficulty, "difficulty_valid_type_and_range": difficulty_typed,
            "difficulty_minimum_met": minimum_met, "difficulty_requested_range_met": difficulty_typed and 2 <= difficulty <= 3,
            "local_admission_pass": correct_key and exact_coverage and bounded and not old_answer_labels and minimum_met,
            "semantic_adjudication": "pending",
        })
    return {"adapted_response": adapted, "items": assessments}


def run_calls(client, plan, capture, path):
    for call in plan["calls"]:
        if len(capture["calls"]) >= 4:
            raise RuntimeError("Frozen four-call ceiling reached.")
        row = {"sequence": call["sequence"], "job_index": call["job_index"], "arm": call["arm"],
               "request": copy.deepcopy(call["provider_request"]), "request_sha256": call["request_sha256"],
               "started_at": datetime.now(timezone.utc).isoformat(), "dispatch_attempted": True}
        capture["calls"].append(row)
        save(path, capture)
        start = time.monotonic()
        try:
            response = client.converse(**copy.deepcopy(call["provider_request"]))
        except Exception as error:
            row["provider_error_type"] = type(error).__name__
            capture["stop_reason"] = "transport_failure"
        else:
            row["response"] = response
            if response.get("stopReason") != "end_turn":
                capture["stop_reason"] = "non_end_turn"
            else:
                try:
                    row["assessment"] = assess(response, call, plan)
                except Exception as error:
                    row["validation_error_type"] = type(error).__name__
                    capture["stop_reason"] = "structural_failure"
        finally:
            row["elapsed_seconds"] = round(time.monotonic() - start, 3)
            save(path, capture)
        if "stop_reason" in capture:
            break
    capture["status"] = "stopped_after_failure" if "stop_reason" in capture else "dispatch_complete_pending_semantic_audit"
    capture["finished_at"] = datetime.now(timezone.utc).isoformat()
    save(path, capture)


def execute(expected_hash):
    plan, manifest = preflight(expected_hash)
    capture = {"plan_sha256": PLAN_SHA, "execution_manifest_sha256": expected_hash,
               "started_at": datetime.now(timezone.utc).isoformat(), "calls": [], "status": "preflight"}
    save(CAPTURE, capture, exclusive=True)
    credentials = json.loads(subprocess.check_output(
        ["aws", "configure", "export-credentials", "--format", "process"], stderr=subprocess.DEVNULL))
    client = boto3.client("bedrock-runtime", region_name=manifest["region"],
                         aws_access_key_id=credentials["AccessKeyId"], aws_secret_access_key=credentials["SecretAccessKey"],
                         aws_session_token=credentials.get("SessionToken"),
                         config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1}))
    del credentials
    capture["status"] = "running"
    run_calls(client, plan, capture, CAPTURE)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--check", metavar="MANIFEST_SHA256")
    action.add_argument("--execute", metavar="MANIFEST_SHA256")
    args = parser.parse_args()
    if args.prepare:
        prepare()
    elif args.check:
        preflight(args.check)
        print("Frozen execution preflight passed; no provider call.")
    else:
        execute(args.execute)
