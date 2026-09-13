#!/usr/bin/env python3
"""Bounded synthetic pipeline audit, recording actual stage inputs and outputs.

Dry by default. No bank/network writes other than opt-in Bedrock inference.
Only checked-in synthetic fixtures may run. Provider reasoning, credentials,
headers, request IDs and SDK error messages are never persisted. A failed call
stops that case; the next independent case retains its own six-call ceiling.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from unittest.mock import patch

SERVICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE))

import question_generation as generation  # noqa: E402
import question_verification as verification  # noqa: E402
from evals.checkpoint_prompt_ablation import use_aws_cli_credentials  # noqa: E402
from question_bank_worker import _prepare_questions  # noqa: E402
from request_contract import _normalize_request  # noqa: E402

FIXTURES = SERVICE / "evals/fixtures/question_correctness_trace.json"
SETTINGS = {
    "AWS_REGION": "us-east-1", "BEDROCK_REGION": "us-east-1",
    "BEDROCK_MODEL_ID": "moonshotai.kimi-k2.5",
    "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
    "BEDROCK_FALLBACK_MODEL_ID": "", "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy",
    "BEDROCK_KIMI_THINKING": "disabled", "BEDROCK_CLAUDE_THINKING": "disabled",
    "BEDROCK_CLAUDE_EFFORT": "high", "BEDROCK_MAX_TOKENS": "6000",
    "BEDROCK_THINKING_MAX_TOKENS": "16000", "BEDROCK_TEMPERATURE": "0.2",
    "BEDROCK_READ_TIMEOUT_SECONDS": "75", "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
    "MAX_PROVIDER_CALLS_PER_REQUEST": "6", "GENERATION_ATTEMPTS": "3",
    "QUESTION_FEEDBACK_CONTRACT": "reviewer_written",
    "CHECKPOINT_PROMPT_VARIANT": "balanced",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "", "BEDROCK_GUARDRAIL_VERSION": "",
}


def write(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + "\n")


def digest(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


class TraceClient:
    def __init__(self, client, trace, save, cap=6):
        self.client, self.trace, self.save, self.cap = client, trace, save, cap
        self.failed = False

    def converse(self, **request):
        calls = self.trace["calls"]
        if self.failed or len(calls) >= self.cap:
            raise RuntimeError("Audit call limit reached.")
        record = {"call": len(calls) + 1, "request": copy.deepcopy(request)}
        calls.append(record)
        self.save()
        start = time.monotonic()
        try:
            response = self.client.converse(**request)
            record["response"] = {
                "text": [b["text"] for b in response.get("output", {}).get("message", {}).get("content", [])
                         if isinstance(b, dict) and isinstance(b.get("text"), str)],
                "stopReason": response.get("stopReason"), "usage": response.get("usage", {}),
            }
            return response
        except Exception as error:
            self.failed = True
            record["error_type"] = type(error).__name__
            raise
        finally:
            record["elapsed_seconds"] = round(time.monotonic() - start, 3)
            self.save()


def run_case(case, directory, client, *, maximum_calls=6):
    if type(maximum_calls) is not int or not 1 <= maximum_calls <= 6:
        raise ValueError("Audit case limit must be between one and six calls.")
    trace = {"case_id": case["id"], "original_request": copy.deepcopy(case["payload"]),
             "calls": [], "stages": [], "final": [], "metrics": {
                 "ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}}
    def save():
        write(directory / (case["id"] + ".json"), trace)
    capture = TraceClient(client, trace, save, cap=maximum_calls)
    # The orchestration reserves a complete three-stage pass even when the
    # author is replaced by a fixed offline payload. TraceClient remains the
    # hard limit on actual SDK invocations for these two-call matched runs.
    budget = generation.ProviderCallBudget(max(3, maximum_calls))

    def observe(module, name, stage, project):
        original = getattr(module, name)

        def wrapped(*args, **kwargs):
            record = {"stage": stage, "after_provider_call": len(trace["calls"]),
                      "input": copy.deepcopy(project(args, kwargs))}
            trace["stages"].append(record)
            try:
                result = original(*args, **kwargs)
                record["output"] = copy.deepcopy(result)
                return result
            except Exception as error:
                record["error_type"] = type(error).__name__
                raise
            finally:
                record["quality_after"] = copy.deepcopy(trace["metrics"].get("QuestionQuality", {}))
                save()
        return patch.object(module, name, wrapped)

    start = time.monotonic()
    try:
        request = _normalize_request(case["payload"])
        trace["normalized_request"] = copy.deepcopy(request)
        save()
        with (
            observe(generation, "_generate_provider_payload", "author_parse", lambda a, k: a[0]),
            observe(generation, "_sanitize_questions", "sanitize", lambda a, k: {"questions": a[0], "request": a[1]}),
            observe(generation, "verify_questions", "verification", lambda a, k: {"questions": a[0], "request": a[1]}),
            observe(verification, "validate_batch", "solver_parse", lambda a, k: {"raw": a[0], "items": a[1]}),
            observe(verification, "complete_solution_rejection_reason", "solver_decision", lambda a, k: {"solution": a[0], "question": a[1]}),
        ):
            trace["final"] = generation._generate_sanitized_questions(
                request, capture, call_budget=budget, request_metrics=trace["metrics"])
        # Real bank preparation and JSON roundtrip, without touching DynamoDB.
        prepared = _prepare_questions("synthetic-correctness-audit", trace["final"], [])
        trace["bank_prepared"] = prepared
        trace["transport_roundtrip"] = json.loads(json.dumps({"questions": prepared}, ensure_ascii=False))
    except Exception as error:
        trace["error_type"] = type(error).__name__
    trace["elapsed_seconds"] = round(time.monotonic() - start, 3)
    trace["budget_calls"] = budget.calls
    trace["final_content_ids"] = [digest(q) for q in trace["final"]]
    save()
    return trace


def load_cases(ids):
    cases = json.loads(FIXTURES.read_text())
    if len(cases) != 12 or len({c["id"] for c in cases}) != 12:
        raise ValueError("Expected twelve distinct frozen synthetic cases.")
    if len(set(ids)) != len(ids) or set(ids) - {c["id"] for c in cases}:
        raise ValueError("Unknown or repeated case ID.")
    selected = [c for c in cases if not ids or c["id"] in ids]
    for case in selected:
        if case["payload"]["targetCount"] != 2:
            raise ValueError("Two requested questions per case.")
        _normalize_request(case["payload"])
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--case-id", action="append", default=[])
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args()
    cases = load_cases(args.case_id)
    plan = {"case_ids": [c["id"] for c in cases], "max_provider_calls": 6 * len(cases),
            "fixture_sha256": digest(cases), "settings": SETTINGS}
    if not args.execute:
        print(json.dumps(plan, indent=2))
        return
    args.output_dir.mkdir(parents=True, exist_ok=False)
    plan["source_revision"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=SERVICE, text=True).strip()
    plan["source_sha256"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in SERVICE.glob("*.py")}
    write(args.output_dir / "plan.json", plan)
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    with patch.dict(os.environ, SETTINGS):
        client = generation._bedrock_client()
        for case in cases:
            trace = run_case(case, args.output_dir, client)
            print(json.dumps({"case_id": case["id"], "returned": len(trace["final"]),
                              "calls": len(trace["calls"]), "seconds": trace["elapsed_seconds"],
                              "quality": trace["metrics"].get("QuestionQuality"),
                              "error_type": trace.get("error_type")}), flush=True)


if __name__ == "__main__":
    main()
