"""Two-call v2 reviewer follow-up with the unchanged failed-arm controls.

Freeze exact production stage requests before dispatch. This is a new experiment;
the prior v1 failure and all prior plans/captures remain unchanged.
"""

import argparse
import copy
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402
from live_native_probe import save, sha, write_new  # noqa: E402

from native_output_contracts import contract_metadata  # noqa: E402
from question_generation import ProviderCallBudget, _generate_with_bedrock  # noqa: E402
from question_verification import verify_questions  # noqa: E402


def source_hashes():
    return {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in [
        Path(__file__), HERE / "live_native_probe.py",
        *[SERVICE / name for name in (
            "native_output_contracts.py", "question_generation.py", "question_quality.py",
            "question_verification.py", "complete_question_solution.py", "request_contract.py",
        )],
    ]}


def stage(plan, client, metrics):
    with patch.dict(os.environ, plan["environment"]):
        return _generate_with_bedrock(
            {}, client, "us.anthropic.claude-sonnet-4-6",
            system_prompt=plan["semantic_system_prompt"], user_prompt=plan["semantic_user_prompt"],
            contract="default_reviewer_v2", call_budget=ProviderCallBudget(1), request_metrics=metrics,
        )


def prepare():
    original_path = ROOT / "docs/evidence/choice-reliability-20260921/native-reviewer-plan.json"
    original = json.loads(original_path.read_text())
    failed_arm = original["jobs"][2]
    assert failed_arm["arm"] == "explicit_diversity"
    plan = {
        "kind": "Two v2 native reviewer calls using unchanged prior failed-arm semantic prompts and eight controls",
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_sha256": source_hashes(),
        "prior_v1_plan_sha256": sha(original_path.read_bytes()),
        "environment": original["settings"]["env"],
        "semantic_system_prompt": failed_arm["semantic_system_prompt"],
        "semantic_user_prompt": failed_arm["semantic_user_prompt"],
        "expected_cases": original["expected_cases"],
        "contract": contract_metadata("default_reviewer_v2"),
        "limits": {"maximum_dispatches": 2, "sdk_total_max_attempts": 1,
                   "read_timeout_seconds": 75, "connect_timeout_seconds": 3, "region": "us-east-1"},
        "scope": "Reviewer-only shape and controlled verdict smoke using actual production v2 provider adapter. No author/solver calls, deployment or bank writes. The explicit-diversity semantic prompt is experimental and is not promoted into the production reviewer prompt by this schema fix.",
    }

    class DryClient:
        def converse(self, **request):
            self.request = request
            return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": '{"reviews":[]}'}]}}}

    client = DryClient()
    stage(plan, client, None)
    plan["request"] = client.request
    path = HERE / "reviewer-v2-plan.json"
    write_new(path, plan)
    print(json.dumps({"plan": str(path), "sha256": sha(path.read_bytes()), "maximum_calls": 2}))


def score(adapted, cases):
    rows = json.loads(adapted)["reviews"]
    indexes = [row["index"] for row in rows]
    if sorted(indexes) != list(range(len(cases))):
        raise ValueError("Review indexes do not cover each control exactly once")
    by_index = {row["index"]: row for row in rows}
    questions = [{"prompt": case["prompt"], "choices": case["choices"],
                  "expectedAnswer": case["expectedAnswer"], "topic": "Literal reasoning",
                  "explanation": "Synthetic fixture explanation hidden from reviewer.", "difficulty": 1}
                 for case in cases]
    metrics = {}
    retained = verify_questions(questions, {"minimumDifficulty": 1}, lambda *_: adapted,
                                metrics, preserve_reviewed_text=True)
    return {
        "cases": [{"id": case["id"], "expected_valid": case["expected_valid"],
                   "declared_valid": by_index[index]["valid"],
                   "verdict_matches": by_index[index]["valid"] is case["expected_valid"],
                   "rejected_fields": sorted(by_index[index]) if by_index[index]["valid"] is False else None}
                  for index, case in enumerate(cases)],
        "admitted_case_ids": [case["id"] for case in cases
                              if any(q["prompt"] == case["prompt"] and q["choices"] == case["choices"] for q in retained)],
        "admission_metrics": metrics,
    }


def execute(expected_sha):
    path = HERE / "reviewer-v2-plan.json"
    if sha(path.read_bytes()) != expected_sha:
        raise SystemExit("Plan hash mismatch")
    plan = json.loads(path.read_text())
    if plan["source_sha256"] != source_hashes():
        raise SystemExit("Source changed after plan freeze")
    output = HERE / "reviewer-v2-capture.json"
    capture = {"plan_sha256": expected_sha, "status": "preflight", "calls": [],
               "started_at": datetime.now(timezone.utc).isoformat(),
               "dependencies": {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__}}
    write_new(output, capture)
    try:
        credentials = json.loads(subprocess.check_output(
            ["aws", "configure", "export-credentials", "--format", "process"], stderr=subprocess.DEVNULL,
        ))
        real = boto3.client("bedrock-runtime", region_name="us-east-1",
            aws_access_key_id=credentials["AccessKeyId"], aws_secret_access_key=credentials["SecretAccessKey"],
            aws_session_token=credentials.get("SessionToken"),
            config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1}))
        del credentials
        capture["status"] = "running"
        for iteration in range(2):
            record = {"iteration": iteration + 1, "dispatch_attempted": False}
            capture["calls"].append(record)

            class Recorder:
                def converse(self, **request):
                    if request != plan["request"]:
                        raise RuntimeError("Stage request differs from frozen plan")
                    if record["dispatch_attempted"]:
                        raise RuntimeError("No retries permitted")
                    record["dispatch_attempted"] = True
                    save(output, capture)
                    response = real.converse(**request)
                    record["response"] = {
                        "stopReason": response.get("stopReason"), "usage": response.get("usage"),
                        "content": [copy.deepcopy(block) for block in response.get("output", {}).get("message", {}).get("content", [])
                                    if "reasoningContent" not in block],
                    }
                    save(output, capture)
                    return response

            metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
            started = time.monotonic()
            try:
                adapted = stage(plan, Recorder(), metrics)
                record.update(adapted=adapted, score=score(adapted, plan["expected_cases"]), outcome="completed")
            except Exception as error:
                record.update(outcome="failed", exception_type=type(error).__name__,
                              provider_error_code=getattr(error, "response", {}).get("Error", {}).get("Code"))
                capture["status"] = "stopped_after_failure"
            finally:
                record.update(elapsed_seconds=round(time.monotonic() - started, 3), metrics=metrics)
                save(output, capture)
            if capture["status"] == "stopped_after_failure":
                break
        else:
            capture["status"] = "completed"
    except Exception as error:
        capture.update(status="preflight_failed", exception_type=type(error).__name__)
    finally:
        capture["finished_at"] = datetime.now(timezone.utc).isoformat()
        save(output, capture)
    print(json.dumps({"capture": str(output), "status": capture["status"],
                      "dispatches": sum(call["dispatch_attempted"] for call in capture["calls"])}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--prepare", action="store_true")
    group.add_argument("--execute", metavar="PLAN_SHA256")
    arguments = parser.parse_args()
    prepare() if arguments.prepare else execute(arguments.execute)
