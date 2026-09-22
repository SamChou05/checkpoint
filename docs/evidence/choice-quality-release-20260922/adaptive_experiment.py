"""Freeze/run four adaptive-thinking calls through the actual production route."""
import argparse
from copy import deepcopy
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import time
from unittest import mock

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("endpoint_scoring_for_adaptive", HERE / "endpoint_experiment.py")
endpoint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(endpoint)
base = endpoint.base

import question_generation as runtime  # noqa: E402

ENVIRONMENT = {
    "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "BEDROCK_REGION": "us-east-1",
    "BEDROCK_CLAUDE_THINKING": "adaptive", "BEDROCK_CLAUDE_EFFORT": "high",
    "BEDROCK_THINKING_MAX_TOKENS": "16000", "BEDROCK_MAX_TOKENS": "6000",
    "BEDROCK_TEMPERATURE": "0.2", "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
    "BEDROCK_READ_TIMEOUT_SECONDS": "75", "MIN_PROVIDER_REMAINING_MILLISECONDS": "0",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "", "BEDROCK_GUARDRAIL_VERSION": "",
}


class OfflineCaptureClient:
    def __init__(self):
        self.requests = []

    def converse(self, **request):
        self.requests.append(deepcopy(request))
        return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": '{"solutions":[]}'}]}}}


def invoke(job, client, budget):
    return runtime._generate_with_bedrock(
        {}, client, job["request"]["modelId"],
        user_prompt=job["request"]["messages"][0]["content"][0]["text"],
        system_prompt=job["runtime_system_prompt"], call_budget=budget,
        contract="complete_choice_solver_v3",
    )


def source_files():
    return {**endpoint.source_files(),
            str((base.SERVICE / "question_generation.py").relative_to(base.REPO)): base.sha(base.SERVICE / "question_generation.py"),
            str((HERE / "endpoint_experiment.py").relative_to(base.REPO)): base.sha(HERE / "endpoint_experiment.py")}


def make_plan():
    original = json.loads((HERE / "endpoint-plan.json").read_text())
    endpoint.assert_bindings(original)
    endpoint.base.reviewed_packet()
    jobs = []
    fake = OfflineCaptureClient()
    budget = runtime.ProviderCallBudget(4)
    with mock.patch.dict(os.environ, ENVIRONMENT):
        for existing in original["jobs"]:
            job = deepcopy(existing)
            system, user = endpoint.candidate.build_solver_prompt(job["items"], {"goal": {"title": "Apply stated facts and established rules across common subjects"}}, audit_choice_pairs=True, choice_slots=True)
            assert endpoint.native_prompt(system, "complete_choice_solver_v3") == job["request"]["system"][0]["text"]
            assert user == job["request"]["messages"][0]["content"][0]["text"]
            job["runtime_system_prompt"] = system
            invoke(job, fake, budget)
            actual = fake.requests[-1]
            assert actual["inferenceConfig"] == {"maxTokens": 16000}
            assert actual["additionalModelRequestFields"] == {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}}
            for key in set(actual) | set(existing["request"]):
                if key not in {"inferenceConfig", "additionalModelRequestFields"}:
                    assert actual[key] == existing["request"][key], key
            job["request"] = actual
            job["request_sha256"] = base.digest(actual)
            jobs.append(job)
        try:
            invoke(jobs[-1], fake, budget)
        except runtime.ProviderCallBudgetExceededError:
            pass
        else:
            raise AssertionError("Fifth provider call was not blocked.")
        assert budget.calls == len(fake.requests) == 4
        with mock.patch("boto3.client") as factory:
            runtime._bedrock_client()
            config = factory.call_args.kwargs["config"]
            assert config.retries["total_max_attempts"] == 1
            assert config.connect_timeout == 3 and config.read_timeout == 75
    return {
        "experiment": "adaptive-high-endpoint-solver-qualification-20260922",
        "status": "frozen_awaiting_parent_dispatch_approval", "source_sha256": source_files(),
        "runner_sha256": base.sha(Path(__file__)), "document_sha256": base.sha(HERE / "ADAPTIVE_PLAN.md"),
        "disabled_plan_sha256": base.sha(HERE / "endpoint-plan.json"),
        "disabled_capture_sha256": base.sha(HERE / "endpoint-capture.json"),
        "reviewed_packet_sha256": base.sha(HERE / "controls-draft.json"),
        "gold_review_sha256": base.sha(HERE / "independent-gold-review.json"),
        "environment": ENVIRONMENT,
        "settings": {**original["settings"], "max_output_tokens": 16000, "thinking": "adaptive", "effort": "high", "temperature": "omitted by runtime"},
        "offline_runtime_checks": {"constructed_provider_requests": 4, "fifth_blocked_before_client": True, "production_sdk_total_max_attempts": 1, "connect_timeout_seconds": 3, "read_timeout_seconds": 75},
        "stop_policy": original["stop_policy"], "criteria": original["criteria"],
        "interpretation": "Four candidate calls only. Compare descriptively with historical disabled endpoint run, not a paired causal experiment. No production default toggle. Adaptive reasoning and final JSON share16000output tokens; measure actual latency/usage against240s full-worker constraint without claiming isolated solver proves worker feasibility.",
        "controls": original["controls"], "jobs": jobs,
    }


def assert_bindings(plan):
    assert source_files() == plan["source_sha256"], "Frozen runtime changed."
    for field, path in [("runner_sha256", Path(__file__)), ("document_sha256", HERE / "ADAPTIVE_PLAN.md"),
                        ("disabled_plan_sha256", HERE / "endpoint-plan.json"), ("disabled_capture_sha256", HERE / "endpoint-capture.json"),
                        ("reviewed_packet_sha256", HERE / "controls-draft.json"), ("gold_review_sha256", HERE / "independent-gold-review.json")]:
        assert base.sha(path) == plan[field], f"Frozen binding changed: {field}"
    assert plan["environment"] == ENVIRONMENT
    for job in plan["jobs"]:
        assert base.digest(job["request"]) == job["request_sha256"]


class LiveCaptureClient:
    def __init__(self, delegate, job, call):
        self.delegate, self.job, self.call = delegate, job, call
        self.meta = delegate.meta

    def converse(self, **request):
        if request != self.job["request"]:
            raise AssertionError("Actual runtime request differs from frozen provider bytes.")
        self.call["dispatch_attempted"] = True
        response = self.delegate.converse(**request)
        content = response.get("output", {}).get("message", {}).get("content", [])
        self.call.update({"raw": "\n".join(block["text"] for block in content if "text" in block),
                          "usage": response.get("usage"), "stop_reason": response.get("stopReason"),
                          "reasoning_content_block_count": sum("reasoningContent" in block for block in content),
                          "reasoning_text_retained": False})
        return response


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    path = HERE / "adaptive-plan.json"
    if not args.run:
        plan = make_plan()
        assert_bindings(plan)
        endpoint.dry_validate(plan)
        if path.exists() and json.loads(path.read_text()) != plan:
            raise RuntimeError("Refusing to change a frozen plan.")
        base.save(path, plan)
        print(f"Frozen four adaptive runtime requests; plan byte SHA256 {base.sha(path)}. Offline route/budget/SDK/gold checks passed; no provider calls.")
        return
    plan = json.loads(path.read_text())
    assert_bindings(plan)
    output = HERE / "adaptive-capture.json"
    if output.exists():
        raise RuntimeError("Refusing to replace capture or repeat calls.")
    cases = {case["id"]: case for case in plan["controls"]}
    capture = {"plan_sha256": base.digest(plan), "plan_byte_sha256": base.sha(path), "started_at": datetime.now(timezone.utc).isoformat(), "status": "running", "calls": []}
    base.save(output, capture)
    with mock.patch.dict(os.environ, ENVIRONMENT):
        client = runtime._bedrock_client()
        budget = runtime.ProviderCallBudget(4)
        for job in plan["jobs"]:
            assert_bindings(plan)
            call = {"call_index": job["call_index"], "request_sha256": job["request_sha256"], "dispatch_attempted": False}
            capture["calls"].append(call)
            base.save(output, capture)
            print(f"Dispatch {job['call_index'] + 1}/4 adaptive", flush=True)
            start = time.monotonic()
            try:
                raw = invoke(job, LiveCaptureClient(client, job, call), budget)
                call["elapsed_seconds"] = round(time.monotonic() - start, 3)
                base.save(output, capture)
                if call["stop_reason"] != "end_turn":
                    raise ValueError("Abnormal completion; no retry or repair.")
                call["score"] = endpoint.score(raw, job, cases)
                print(f"Complete {job['call_index'] + 1}/4: all-gold={sum(row['all_gold_agrees'] for row in call['score']['rows'])}/5; seconds={call['elapsed_seconds']}", flush=True)
            except Exception as error:
                call.update({"elapsed_seconds": round(time.monotonic() - start, 3), "error_type": type(error).__name__, "error": str(error)})
                capture["status"] = "stopped_after_failure"
                capture["provider_budget_calls"] = budget.calls
                base.save(output, capture)
                print(f"Stopped: {type(error).__name__}", flush=True)
                return
            base.save(output, capture)
        capture["provider_budget_calls"] = budget.calls
    capture["status"] = "complete"
    capture["completed_at"] = datetime.now(timezone.utc).isoformat()
    base.save(output, capture)


if __name__ == "__main__":
    main()
