#!/usr/bin/env python3
"""One bounded full-pipeline generation job for each selected synthetic goal.

At most 36 real provider calls, six per goal. By default, stop the entire
experiment on a provider failure. Opt-in continuation advances to the next
independent goal, never retrying a failed goal or expanding its call budget.
Capture exact request prompts and only final response text, never reasoning
content. Separate blind exports cover retained questions and all parseable raw
author candidates, excluding answers, explanations, difficulty, and verdicts.
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
from question_quality import _extract_json_object  # noqa: E402
from question_verification import (  # noqa: E402
    REVIEW_SYSTEM_PROMPT,
    SOLUTION_SYSTEM_PROMPT,
)
from request_contract import _normalize_request  # noqa: E402
from service_errors import ProviderError  # noqa: E402

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


def load_cases(case_ids=None):
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
    if not case_ids:
        return cases
    if len(set(case_ids)) != len(case_ids):
        raise ValueError("Each selected goal must appear only once.")
    by_id = {case["case_id"]: case for case in cases}
    unknown = set(case_ids) - set(by_id)
    if unknown:
        raise ValueError("Unknown goal IDs: " + ", ".join(sorted(unknown)))
    return [by_id[case_id] for case_id in case_ids]


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


def raw_author_items(case, calls, author_system_prompt):
    """Export exact raw candidates without exposing author keys or survival.

    Use the same JSON extractor as runtime; invalid JSON remains an observed
    parse failure. No heuristic or model repair is performed by this exporter.
    A full content hash is stable across later calls and different goal order.
    """
    blinded, keys, observations = [], [], []
    for call_index, call in enumerate(calls, 1):
        if call["request"].get("system") != [{"text": author_system_prompt}]:
            continue
        observation = {"call_index": call_index}
        response = call.get("response")
        if not isinstance(response, dict):
            observation["status"] = "provider_error"
            observations.append(observation)
            continue
        try:
            payload = _extract_json_object("\n".join(response.get("text", [])))
        except ProviderError:
            observation["status"] = "invalid_json"
            observations.append(observation)
            continue
        questions = payload.get("questions")
        if not isinstance(questions, list):
            observation["status"] = "invalid_questions_envelope"
            observations.append(observation)
            continue
        observation.update(
            status="parsed",
            raw_item_count=len(questions),
            blindable_item_count=0,
            unblindable_item_indices=[],
        )
        for item_index, question in enumerate(questions):
            if (
                not isinstance(question, dict)
                or not isinstance(question.get("prompt"), str)
                or not isinstance(question.get("choices"), list)
                or not all(isinstance(choice, str) for choice in question["choices"])
            ):
                observation["unblindable_item_indices"].append(item_index)
                continue
            content = {
                "goal": case["payload"]["goal"],
                "sourceDocuments": case["payload"]["sourceDocuments"],
                "prompt": question["prompt"],
                "choices": question["choices"],
            }
            content_id = hashlib.sha256(
                json.dumps(
                    content, ensure_ascii=False, sort_keys=True, separators=(",", ":")
                ).encode()
            ).hexdigest()
            blinded.append({"id": content_id, **content})
            keys.append(
                {
                    "id": content_id,
                    "case_id": case["case_id"],
                    "call_index": call_index,
                    "item_index": item_index,
                    "question": copy.deepcopy(question),
                }
            )
            observation["blindable_item_count"] += 1
        observations.append(observation)
    return blinded, keys, observations


def run_experiment(directory, cases, client=None, *, continue_after_goal_failure=False):
    if not 1 <= len(cases) <= 6 or len({case["case_id"] for case in cases}) != len(
        cases
    ):
        raise ValueError("At most six unique goals may run in this bounded experiment.")
    if type(continue_after_goal_failure) is not bool:
        raise ValueError("The continuation policy must be explicitly true or false.")
    total_call_cap = min(MAX_TOTAL_CALLS, MAX_CALLS_PER_GOAL * len(cases))
    directory.mkdir(parents=True, exist_ok=False)
    report = {
        "settings": SETTINGS,
        "max_calls_per_goal": MAX_CALLS_PER_GOAL,
        "max_total_calls": total_call_cap,
        "max_jobs_per_goal": 1,
        "continue_after_goal_failure": continue_after_goal_failure,
        "had_goal_failures": False,
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
    raw_blinded_by_id = {}
    raw_keys = []
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
        write_json(directory / "blinded_raw_authors.json", [])
        write_json(directory / "raw_author_keys.json", raw_keys)
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
            raw_blinded, keys, observations = raw_author_items(
                case, capture.calls, prompts["author"]
            )
            result["raw_author_observations"] = observations
            raw_blinded_by_id.update({item["id"]: item for item in raw_blinded})
            raw_keys.extend(keys)
            report["results"].append(result)
            blinded.extend(blinded_items(case, result["questions"]))
            total_calls = sum(
                item["actual_provider_calls"] for item in report["results"]
            )
            provider_rejections = (
                result["metrics"].get("QuestionQuality", {}).get("provider", {})
            )
            result["goal_failed"] = bool(
                capture.failed
                or result["errors"]
                or provider_rejections.get("request_failed")
                or provider_rejections.get("output_truncated")
            )
            report["had_goal_failures"] |= result["goal_failed"]
            report["stopped_early"] = bool(
                result["goal_failed"]
                and not continue_after_goal_failure
                or total_calls >= total_call_cap
                and len(report["results"]) < len(cases)
            )
            write_json(directory / "capture.json", report)
            write_json(directory / "blinded.json", blinded)
            write_json(
                directory / "blinded_raw_authors.json", list(raw_blinded_by_id.values())
            )
            write_json(directory / "raw_author_keys.json", raw_keys)
            print(
                json.dumps(
                    {
                        "case_id": case["case_id"],
                        "retained": len(result["questions"]),
                        "target": result["target_count"],
                        "calls": len(capture.calls),
                        "elapsed_seconds": result["elapsed_seconds"],
                        "errors": result["errors"],
                        "goal_failed": result["goal_failed"],
                        "stopped_early": report["stopped_early"],
                        "blinded_path": str(directory / "blinded.json"),
                        "blinded_raw_authors_path": str(
                            directory / "blinded_raw_authors.json"
                        ),
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
    parser.add_argument(
        "--case-id",
        action="append",
        default=[],
        help="Select a goal in run order (repeatable); defaults to all six goals.",
    )
    parser.add_argument(
        "--continue-after-goal-failure",
        action="store_true",
        help="Proceed to the next independent goal after a failure; do not retry it.",
    )
    args = parser.parse_args()
    try:
        cases = load_cases(args.case_id)
    except ValueError as error:
        parser.error(str(error))
    if args.dry_run:
        print(
            json.dumps(
                {
                    "cases": [case["case_id"] for case in cases],
                    "max_calls": min(
                        MAX_TOTAL_CALLS, MAX_CALLS_PER_GOAL * len(cases)
                    ),
                    "continue_after_goal_failure": args.continue_after_goal_failure,
                    "settings": SETTINGS,
                },
                indent=2,
            )
        )
        return 0
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    report = run_experiment(
        args.output_dir,
        cases,
        continue_after_goal_failure=args.continue_after_goal_failure,
    )
    return (
        0
        if not report["stopped_early"]
        and not report["had_goal_failures"]
        and all(item["passed"] for item in report["results"])
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
