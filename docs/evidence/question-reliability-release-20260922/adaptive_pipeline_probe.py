"""Proposed adaptive worker qualification with real shrinking SDK timeouts.

--preflight is offline. Do not --prepare until the reviewer candidate is selected;
--execute additionally requires parent approval of the resulting frozen plan.
No deployment or learner-bank writes. Credentials stay in memory.
"""
import argparse
import copy
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("previous_pipeline_probe", HERE / "pipeline_probe.py")
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)

import question_generation as runtime  # noqa: E402
from native_output_contracts import adapt_native_response, contract_metadata  # noqa: E402

ENVIRONMENT = {
    **old.ENVIRONMENT, "BEDROCK_REGION": "us-east-1",
    "BEDROCK_CLAUDE_THINKING": "adaptive", "BEDROCK_CLAUDE_EFFORT": "high",
    "BEDROCK_THINKING_MAX_TOKENS": "16000",
}
CONTRACTS = old.CONTRACTS


def sources():
    return {**old.sources(), **{str(path.relative_to(old.ROOT)): old.sha(path.read_bytes()) for path in [
        Path(__file__), HERE / "test_adaptive_pipeline_deadline.py", HERE / "ADAPTIVE_PIPELINE_PLAN.md",
    ]}}


class Deadline:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.start = clock()

    def get_remaining_time_in_millis(self):
        return max(0, int((240 - (self.clock() - self.start)) * 1000))


def safe_response(response):
    result = copy.deepcopy(response)
    content = result.get("output", {}).get("message", {}).get("content", [])
    reasoning_blocks = sum("reasoningContent" in block for block in content)
    if "output" in result and "message" in result["output"]:
        result["output"]["message"]["content"] = [block for block in content if "reasoningContent" not in block]
    return result, reasoning_blocks


class Recorder:
    def __init__(self, client, capture, job, path, budget):
        self.client, self.capture, self.job, self.path, self.budget = client, capture, job, path, budget
        # The runtime rechecks the actual configured timeout after SDK setup.
        self.meta = client.meta

    def converse(self, **request):
        if self.capture.get("stop_dispatching"):
            raise RuntimeError("Dispatch stopped after provider failure.")
        if len(self.capture["calls"]) >= 36 or sum(call["job"] == self.job for call in self.capture["calls"]) >= 6:
            raise RuntimeError("Frozen dispatch ceiling reached.")
        model = request["modelId"]
        if model == ENVIRONMENT["BEDROCK_MODEL_ID"]:
            expected_inference = {"maxTokens": 6000, "temperature": 0.2}
            expected_additional = {"thinking": {"type": "disabled"}}
        elif model == ENVIRONMENT["BEDROCK_VERIFICATION_MODEL_ID"]:
            expected_inference = {"maxTokens": 16000}
            expected_additional = {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}}
        else:
            raise RuntimeError("Unplanned model.")
        if request["inferenceConfig"] != expected_inference or request.get("additionalModelRequestFields") != expected_additional:
            raise RuntimeError("Unplanned inference settings.")
        contract = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
        if contract not in CONTRACTS:
            raise RuntimeError("Unplanned stage contract.")
        connect, read = runtime._client_transport_timeouts(self)
        remaining = self.budget.remaining_milliseconds()
        minimum = runtime._minimum_provider_remaining_milliseconds(connect_timeout=connect, read_timeout=read)
        if remaining < minimum:
            raise RuntimeError("Runtime admitted an SDK timeout beyond the remaining deadline.")
        call = {"job": self.job, "request": copy.deepcopy(request), "dispatch_attempted": True,
                "started_at": datetime.now(timezone.utc).isoformat(),
                "remaining_before_dispatch_ms": remaining, "minimum_required_ms": minimum,
                "connect_timeout_seconds": connect, "read_timeout_seconds": read,
                "sdk_total_max_attempts": self.meta.config.retries.get("total_max_attempts"),
                "provider_budget_calls_at_dispatch": self.budget.calls}
        self.capture["calls"].append(call)
        old.save(self.path, self.capture)
        started = time.monotonic()
        try:
            response = self.client.converse(**request)
            retained, reasoning_blocks = safe_response(response)
            call.update(response=retained, reasoning_content_block_count=reasoning_blocks,
                        reasoning_text_retained=False)
            stop = response.get("stopReason")
            call["outcome"] = "end_turn" if stop == "end_turn" else "truncation" if stop == "max_tokens" else "abnormal_completion"
            if stop != "end_turn":
                self.capture["stop_dispatching"] = True
            raw = "\n".join(block["text"] for block in retained.get("output", {}).get("message", {}).get("content", []) if "text" in block)
            try:
                adapt_native_response(raw, contract)
            except Exception as error:
                call["native_transport_valid"] = False
                call["native_validation_error_type"] = type(error).__name__
            else:
                call["native_transport_valid"] = True
            return response
        except Exception as error:
            call["outcome"] = "transport_error"
            call["provider_error_type"] = type(error).__name__
            self.capture["stop_dispatching"] = True
            raise
        finally:
            call["elapsed_seconds"] = round(time.monotonic() - started, 3)
            call["remaining_after_response_ms"] = self.budget.remaining_milliseconds()
            old.save(self.path, self.capture)


def prepare(path):
    previous_path = HERE / "pipeline-plan-v2.json"
    previous = json.loads(previous_path.read_text())
    assert len(previous["jobs"]) == 6 and all(job["request"]["targetCount"] == 5 for job in previous["jobs"])
    plan = {
        "experiment": "Fresh full native pipeline with adaptive worker verification and actual shrinking SDK timeouts",
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=old.ROOT, text=True).strip(),
        "source_sha256": sources(), "environment": ENVIRONMENT,
        "source_domain_plan_sha256": old.sha(previous_path.read_bytes()), "jobs": previous["jobs"],
        "dependencies": {"python": sys.version.split()[0], "boto3": old.boto3.__version__, "botocore": old.botocore.__version__},
        "limits": {"maximum_calls": 36, "maximum_calls_per_job": 6, "sdk_total_max_attempts": 1,
                   "job_deadline_seconds": 240, "maximum_read_timeout_seconds": 75,
                   "connect_timeout_seconds": 3, "minimum_read_timeout_seconds": 2,
                   "author_max_output_tokens": 6000, "verification_shared_thinking_output_tokens": 16000,
                   "region": "us-east-1"},
        "prospective_criteria": previous["prospective_criteria"],
        "failure_policy": previous["failure_policy"],
        "interpretation": "Six fresh author generations on unchanged domain specifications, not reuse of prior accepted rows. Same minimum 3 per job/minimum 27 of 30 and every-admitted-content criteria. Actual production _bedrock_client is rebuilt for each call with the current 240s worker context; the runtime shrinks read timeouts and rechecks after client setup. Per-call timeouts, remaining time, provider slots, transport/truncation/schema outcomes and partial yields are retained. No population accuracy or determinism claim; no production default toggle.",
        "registered_contracts": {name: contract_metadata(name) for name in CONTRACTS},
        "offline_preflight": preflight(),
    }
    old.save(path, plan, exclusive=True)
    print(json.dumps({"plan_sha256": old.sha(path.read_bytes()), "maximum_calls": 36}))


def execute(expected_hash, plan_path):
    encoded = plan_path.read_bytes()
    plan = json.loads(encoded)
    if old.sha(encoded) != expected_hash or sources() != plan["source_sha256"]:
        raise RuntimeError("Frozen plan or source changed.")
    if plan["dependencies"] != {"python": sys.version.split()[0], "boto3": old.boto3.__version__, "botocore": old.botocore.__version__}:
        raise RuntimeError("Frozen dependency versions changed.")
    if plan["environment"] != ENVIRONMENT:
        raise RuntimeError("Frozen environment changed.")
    capture = {"plan_sha256": expected_hash, "started_at": datetime.now(timezone.utc).isoformat(),
               "calls": [], "jobs": [], "client_admission_failures": [], "status": "preflight"}
    path = plan_path.with_name(plan_path.name.replace("plan", "capture", 1))
    if path == plan_path:
        raise RuntimeError("Plan filename must include 'plan'.")
    old.save(path, capture, exclusive=True)
    credentials = json.loads(subprocess.check_output(
        ["aws", "configure", "export-credentials", "--format", "process"], stderr=subprocess.DEVNULL))
    session = old.boto3.Session(aws_access_key_id=credentials["AccessKeyId"],
                               aws_secret_access_key=credentials["SecretAccessKey"],
                               aws_session_token=credentials.get("SessionToken"), region_name="us-east-1")
    del credentials
    original_factory = runtime._bedrock_client
    capture["status"] = "running"
    with patch.dict(os.environ, ENVIRONMENT), patch("boto3.client", session.client):
        for job in plan["jobs"]:
            if capture.get("stop_dispatching"):
                break
            if sources() != plan["source_sha256"]:
                raise RuntimeError("Frozen source changed between jobs.")
            row = {"index": job["index"], "metrics": {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}}
            capture["jobs"].append(row)
            started = time.monotonic()
            deadline = Deadline()
            budget = runtime.ProviderCallBudget(6, context=deadline)

            def factory(call_budget=None):
                if call_budget is not budget:
                    raise RuntimeError("A stage did not share the job's provider/deadline budget.")
                try:
                    client = original_factory(call_budget)
                except Exception as error:
                    capture["client_admission_failures"].append({"job": job["index"], "error_type": type(error).__name__,
                                                               "remaining_ms": budget.remaining_milliseconds(),
                                                               "provider_budget_calls": budget.calls})
                    old.save(path, capture)
                    raise
                return Recorder(client, capture, job["index"], path, budget)

            print(f"Job {job['index'] + 1}/6: {job['request']['goal']['title']}", flush=True)
            try:
                with patch.object(runtime, "_bedrock_client", factory):
                    row["accepted"] = runtime._generate_sanitized_questions(
                        copy.deepcopy(job["request"]), None, budget, row["metrics"])
            except Exception as error:
                row["error_type"] = type(error).__name__
            row["elapsed_seconds"] = round(time.monotonic() - started, 3)
            row["remaining_ms"] = deadline.get_remaining_time_in_millis()
            row["provider_budget_calls"] = budget.calls
            row["within_240_second_deadline"] = row["elapsed_seconds"] <= 240
            old.save(path, capture)
            print(f"Accepted {len(row.get('accepted', []))}/5; calls={row['metrics']['ProviderCalls']}; seconds={row['elapsed_seconds']}", flush=True)
    capture["status"] = "stopped_after_failure" if capture.get("stop_dispatching") else "complete"
    capture["finished_at"] = datetime.now(timezone.utc).isoformat()
    old.save(path, capture)


def preflight():
    spec = importlib.util.spec_from_file_location("adaptive_deadline_checks", HERE / "test_adaptive_pipeline_deadline.py")
    checks = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checks)
    return checks.run_checks()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--preflight", action="store_true")
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--execute", metavar="PLAN_SHA256")
    parser.add_argument("--plan", type=Path, default=HERE / "pipeline-adaptive-plan.json")
    args = parser.parse_args()
    if args.preflight:
        print(json.dumps(preflight(), indent=2))
    elif args.prepare:
        prepare(args.plan)
    else:
        execute(args.execute, args.plan)
