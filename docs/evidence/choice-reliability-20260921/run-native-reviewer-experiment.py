"""Separate four-call native follow-up, using the real production stage adapter.

Reuses the frozen controls and semantic prompts from the completed legacy trial.
Writes new native-plan/capture files; never edits the original experiment.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SERVICE = REPO / "backend" / "bedrock-question-service"
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
from botocore.config import Config  # noqa: E402
from question_generation import _generate_with_bedrock, ProviderCallBudget  # noqa: E402
from question_verification import verify_questions  # noqa: E402

spec = importlib.util.spec_from_file_location("original_reviewer_probe", HERE / "run-reviewer-experiment.py")
original = importlib.util.module_from_spec(spec)
spec.loader.exec_module(original)

SETTINGS = {
    "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
    "BEDROCK_MAX_TOKENS": "6000",
    "BEDROCK_TEMPERATURE": "0.2",
    "BEDROCK_CLAUDE_THINKING": "disabled",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "",
    "BEDROCK_GUARDRAIL_VERSION": "",
}


class CaptureOnlyClient:
    def converse(self, **request):
        self.request = request
        return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": '{"reviews":[]}'}]}}}


def stage(job, client, metrics=None):
    return _generate_with_bedrock(
        {}, client, "us.anthropic.claude-sonnet-4-6",
        user_prompt=job["semantic_user_prompt"],
        system_prompt=job["semantic_system_prompt"],
        call_budget=ProviderCallBudget(1), request_metrics=metrics,
        contract="default_reviewer_v1",
    )


def make_plan():
    os.environ.update(SETTINGS)
    old_path = HERE / "reviewer-plan.json"
    old = json.loads(old_path.read_text())
    jobs = []
    for old_job in old["jobs"]:
        job = {
            "call_index": old_job["call_index"], "arm": old_job["arm"],
            "semantic_system_prompt": old_job["request"]["system"][0]["text"],
            "semantic_user_prompt": old_job["request"]["messages"][0]["content"][0]["text"],
        }
        dry_client = CaptureOnlyClient()
        stage(job, dry_client)
        job["request"] = dry_client.request
        job["request_sha256"] = original.digest(dry_client.request)
        jobs.append(job)
    return {
        "experiment": "native-reviewer-core-diversity-20260921",
        "original_plan_sha256": hashlib.sha256(old_path.read_bytes()).hexdigest(),
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
        "source_sha256": {name: hashlib.sha256((SERVICE / name).read_bytes()).hexdigest() for name in ["question_generation.py", "question_verification.py", "native_output_contracts.py", "request_contract.py", "question_quality.py"]},
        "settings": {"env": SETTINGS, "region": "us-east-1", "connect_timeout_seconds": 3, "read_timeout_seconds": 75, "sdk_total_max_attempts": 1, "maximum_calls": 4},
        "scope": "New isolated reviewer-only trial, not a rerun/reclassification of the original four failed legacy calls. Same eight controls and current-core/pairwise semantic prompts, now generated with actual _generate_with_bedrock(contract=default_reviewer_v1), including native override/schema and adapter. No solver records or keys supplied to model. No production release claim.",
        "format_scoring": "Require native stage validation/adaptation, strict whole-object parsing, exact eight-review coverage and actual verify_questions feedback/key validation with preserve_reviewed_text=True. No JSON recovery and no retries. Invalid feedback can still reject an item after a schema-valid output.",
        "expected_cases": old["expected_cases"], "jobs": jobs,
    }


class RecordingClient:
    def __init__(self, real, job, record, capture, output):
        self.real, self.job, self.record = real, job, record
        self.capture, self.output = capture, output

    def converse(self, **request):
        if request != self.job["request"]:
            raise RuntimeError("Actual stage request differs from frozen plan.")
        self.record["dispatch_attempted"] = True
        original.save(self.output, self.capture)
        response = self.real.converse(**request)
        self.record["provider_raw"] = "\n".join(block["text"] for block in response["output"]["message"]["content"] if "text" in block)
        self.record["stop_reason"] = response.get("stopReason")
        self.record["usage"] = response.get("usage")
        original.save(self.output, self.capture)
        return response


def score(adapted, cases):
    result = original.score(adapted, cases)
    questions = [{"prompt": c["prompt"], "choices": c["choices"], "expectedAnswer": c["expectedAnswer"], "topic": "Literal reasoning", "explanation": "Fixture explanation hidden from reviewer.", "difficulty": 1} for c in cases]
    metrics = {}
    accepted = verify_questions(questions, {"minimumDifficulty": 1}, lambda *_: adapted, metrics, preserve_reviewed_text=True)
    result["native_preserved_parser_accepted_case_ids"] = [c["id"] for c in cases if any(q["prompt"] == c["prompt"] and q["choices"] == c["choices"] for q in accepted)]
    result["native_preserved_parser_metrics"] = metrics
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    plan = make_plan()
    path = HERE / "native-reviewer-plan.json"
    if path.exists() and json.loads(path.read_text()) != plan:
        raise RuntimeError("Existing frozen native plan differs; do not alter an experiment.")
    original.save(path, plan)
    if not args.run:
        print("Frozen four native calls; no dispatch.")
        return
    output = HERE / "native-reviewer-capture.json"
    if output.exists():
        raise RuntimeError("Refusing to overwrite a capture or repeat calls.")
    real = boto3.client("bedrock-runtime", region_name="us-east-1", config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1, "mode": "standard"}))
    capture = {"plan_sha256": original.digest(plan), "started_at": datetime.now(timezone.utc).isoformat(), "status": "running", "calls": []}
    original.save(output, capture)
    for job in plan["jobs"]:
        record = {"call_index": job["call_index"], "arm": job["arm"], "request_sha256": job["request_sha256"], "dispatch_attempted": False}
        capture["calls"].append(record)
        original.save(output, capture)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        client = RecordingClient(real, job, record, capture, output)
        start = time.monotonic()
        print(f"Dispatch {job['call_index'] + 1}/4 native: {job['arm']}", flush=True)
        try:
            adapted = stage(job, client, metrics)
            record.update({"elapsed_seconds": round(time.monotonic() - start, 3), "native_stage_valid": True, "adapted": adapted, "metrics": metrics, "score": score(adapted, plan["expected_cases"])})
            print(f"Complete {job['call_index'] + 1}/4 native: parse={record['score']['strict_parse']}; admitted={record['score']['native_preserved_parser_accepted_case_ids']}", flush=True)
        except Exception as error:
            record.update({"elapsed_seconds": round(time.monotonic() - start, 3), "native_stage_valid": False, "error_type": type(error).__name__, "error": str(error), "metrics": metrics})
            capture["status"] = "stopped_after_failure"
            original.save(output, capture)
            print(f"Stopped: {type(error).__name__}", flush=True)
            return
        original.save(output, capture)
    capture["status"] = "complete"
    capture["completed_at"] = datetime.now(timezone.utc).isoformat()
    original.save(output, capture)


if __name__ == "__main__":
    main()
