#!/usr/bin/env python3
"""One bounded full-pipeline generation job for each of six synthetic goals.

At most 36 real provider calls, six per goal. Stop the entire experiment on a
provider failure; never resume or retry an unsuccessful experiment implicitly.
Capture exact request prompts and only final response text, never reasoning
content. Blinded output excludes authored answers, explanations, and difficulty.
No deployed queue, skill inference, learner simulation, or deployment is run.
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

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals.checkpoint_learning_eval import generate_sample  # noqa: E402
from evals.checkpoint_prompt_ablation import use_aws_cli_credentials  # noqa: E402
from question_generation import _bedrock_client, _system_prompt  # noqa: E402
from question_verification import (  # noqa: E402
    REVIEW_SYSTEM_PROMPT,
    SOLUTION_SYSTEM_PROMPT,
)
from request_contract import _normalize_request  # noqa: E402

FIXTURE_PATH = SERVICE_DIR / "evals/fixtures/question_full_pipeline_smoke.json"
MAX_CALLS_PER_GOAL = 6
MAX_TOTAL_CALLS = 36
MODEL = "us.anthropic.claude-opus-4-6-v1"
SETTINGS = {
    "AWS_REGION": "us-east-1",
    "BEDROCK_REGION": "us-east-1",
    "BEDROCK_MODEL_ID": MODEL,
    "BEDROCK_VERIFICATION_MODEL_ID": MODEL,
    "BEDROCK_FALLBACK_MODEL_ID": "",
    "BEDROCK_CLAUDE_THINKING": "adaptive",
    "BEDROCK_CLAUDE_EFFORT": "high",
    "BEDROCK_THINKING_MAX_TOKENS": "16000",
    "BEDROCK_MAX_TOKENS": "16000",
    "BEDROCK_READ_TIMEOUT_SECONDS": "100",
    "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
    "MAX_PROVIDER_CALLS_PER_REQUEST": "6",
    "QUESTION_BANK_MAX_RECEIVE_COUNT": "6",
    "GENERATION_ATTEMPTS": "3",
    "CHECKPOINT_PROMPT_VARIANT": "balanced",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "",
    "BEDROCK_GUARDRAIL_VERSION": "",
}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def load_cases():
    cases = json.loads(FIXTURE_PATH.read_text())
    if len(cases) != 6 or len({case["case_id"] for case in cases}) != 6:
        raise ValueError("The smoke experiment requires six unique synthetic goals.")
    for case in cases:
        payload = case["payload"]
        if payload["targetCount"] != 5 or payload["minimumDifficulty"] != 3:
            raise ValueError("Every goal must request five intermediate questions.")
        request = _normalize_request(payload)
        if [
            {key: document[key] for key in ("name", "text")}
            for document in request["sourceDocuments"]
        ] != payload["sourceDocuments"]:
            raise ValueError("Source text must survive normalization unchanged.")
    return cases


class CapturingClient:
    """Observe the actual pipeline calls; do not replace their decisions."""

    def __init__(self, client, path):
        self.client = client
        self.path = path
        self.calls = []
        self.failed = False

    def converse(self, **request):
        if self.failed or len(self.calls) >= MAX_CALLS_PER_GOAL:
            raise RuntimeError("Experiment call limit reached; no provider call made.")
        call = {"request": copy.deepcopy(request)}
        self.calls.append(call)
        write_json(self.path, self.calls)
        started = time.monotonic()
        try:
            response = self.client.converse(**request)
            call["response"] = {
                "text": [
                    block["text"]
                    for block in response.get("output", {})
                    .get("message", {})
                    .get("content", [])
                    if isinstance(block, dict) and isinstance(block.get("text"), str)
                ],
                "stopReason": response.get("stopReason"),
                "usage": response.get("usage", {}),
            }
            return response
        except Exception as error:
            self.failed = True
            detail = {"type": type(error).__name__}
            error_response = getattr(error, "response", None)
            provider_error = (
                error_response.get("Error")
                if isinstance(error_response, dict)
                else None
            )
            if isinstance(provider_error, dict) and provider_error.get("Code"):
                detail["provider_code"] = provider_error["Code"]
            call["error"] = detail
            raise
        finally:
            call["elapsed_seconds"] = round(time.monotonic() - started, 3)
            write_json(self.path, self.calls)


def blinded_items(case, questions):
    return [
        {
            "id": f"{case['case_id']}-{index + 1:02d}",
            "goal": case["payload"]["goal"],
            "sourceDocuments": case["payload"]["sourceDocuments"],
            "prompt": question["prompt"],
            "choices": question["choices"],
        }
        for index, question in enumerate(questions)
    ]


def run_experiment(directory, cases, client=None):
    if not 1 <= len(cases) <= 6 or len({case["case_id"] for case in cases}) != len(
        cases
    ):
        raise ValueError("At most six unique goals may run in this bounded experiment.")
    directory.mkdir(parents=True, exist_ok=False)
    report = {
        "settings": SETTINGS,
        "max_calls_per_goal": MAX_CALLS_PER_GOAL,
        "max_total_calls": MAX_TOTAL_CALLS,
        "max_jobs_per_goal": 1,
        "cases": cases,
        "results": [],
        "stopped_early": False,
    }
    try:
        report["git_revision"] = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=SERVICE_DIR, text=True
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        report["git_revision"] = None
    blinded = []
    with patch.dict(os.environ, SETTINGS):
        prompts = {
            "author": _system_prompt(),
            "solver": SOLUTION_SYSTEM_PROMPT,
            "reviewer": REVIEW_SYSTEM_PROMPT,
        }
        write_json(directory / "system_prompts.json", prompts)
        report["system_prompt_hashes"] = {
            stage: hashlib.sha256(text.encode()).hexdigest()
            for stage, text in prompts.items()
        }
        write_json(directory / "capture.json", report)
        write_json(directory / "blinded.json", blinded)
        base_client = client if client is not None else _bedrock_client()
        for case in cases:
            capture = CapturingClient(
                base_client, directory / f"{case['case_id']}.calls.json"
            )
            started = time.monotonic()
            result = generate_sample(case, capture, infer_skills=False, max_jobs=1)
            result["elapsed_seconds"] = round(time.monotonic() - started, 3)
            result["actual_provider_calls"] = len(capture.calls)
            result["provider_failed"] = capture.failed
            report["results"].append(result)
            blinded.extend(blinded_items(case, result["questions"]))
            total_calls = sum(
                item["actual_provider_calls"] for item in report["results"]
            )
            provider_rejections = (
                result["metrics"].get("QuestionQuality", {}).get("provider", {})
            )
            report["stopped_early"] = bool(
                capture.failed
                or result["errors"]
                or provider_rejections.get("request_failed")
                or provider_rejections.get("output_truncated")
                or total_calls >= MAX_TOTAL_CALLS
                and len(report["results"]) < len(cases)
            )
            write_json(directory / "capture.json", report)
            write_json(directory / "blinded.json", blinded)
            print(
                json.dumps(
                    {
                        "case_id": case["case_id"],
                        "retained": len(result["questions"]),
                        "target": result["target_count"],
                        "calls": len(capture.calls),
                        "elapsed_seconds": result["elapsed_seconds"],
                        "errors": result["errors"],
                        "stopped_early": report["stopped_early"],
                        "blinded_path": str(directory / "blinded.json"),
                    }
                ),
                flush=True,
            )
            if report["stopped_early"]:
                break
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--aws-cli-credentials", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    cases = load_cases()
    if args.dry_run:
        print(
            json.dumps(
                {
                    "cases": [case["case_id"] for case in cases],
                    "max_calls": MAX_TOTAL_CALLS,
                    "settings": SETTINGS,
                },
                indent=2,
            )
        )
        return 0
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    report = run_experiment(args.output_dir, cases)
    return (
        0
        if not report["stopped_early"]
        and all(item["passed"] for item in report["results"])
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
