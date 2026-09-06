#!/usr/bin/env python3
"""Dry by default, paired single-item review; no activation, repair or promotion."""

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

from question_generation import ProviderCallBudget, _generate_with_bedrock  # noqa: E402
from question_quality import _extract_json_object  # noqa: E402
from question_verification import (  # noqa: E402
    REVIEW_SYSTEM_PROMPT,
    SOLUTION_SYSTEM_PROMPT,
    _bounded_explanation,
    _has_reviewable_choices,
    _validated_solutions,
    verify_questions,
)

MODELS = ["us.anthropic.claude-opus-4-6-v1", "us.anthropic.claude-opus-5"]
FIXTURE_PATH = SERVICE_DIR / "evals/fixtures/question_model_comparison.json"
MAX_CALLS = 16
MAX_CALLS_PER_JOB = 2
MAX_INPUT_BYTES = 16000
MAX_TOTAL_INPUT_BYTES = 256000
REQUIRED_SETTINGS = {
    "AWS_REGION": "us-east-1",
    "BEDROCK_REGION": "us-east-1",
    "BEDROCK_CLAUDE_THINKING": "adaptive",
    "BEDROCK_CLAUDE_EFFORT": "high",
    "BEDROCK_THINKING_MAX_TOKENS": "16000",
    "BEDROCK_MAX_TOKENS": "16000",
    "BEDROCK_FALLBACK_MODEL_ID": "",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "",
    "BEDROCK_GUARDRAIL_VERSION": "",
}


def canonical(value):
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def write_json(path, value):
    """Persist evidence before dispatch; a failed write prevents further calls."""
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        handle.write(
            json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
        )
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def make_plan(packet):
    if packet.get("models") != MODELS:
        raise ValueError("The paired comparison requires the two exact model IDs.")
    cases, settings = packet["cases"], packet["settings"]
    if len(cases) != 4 or len({case["case_id"] for case in cases}) != 4:
        raise ValueError("Exactly four unique cases are required.")
    if any(settings.get(key) != value for key, value in REQUIRED_SETTINGS.items()):
        raise ValueError("The fixture must preserve the declared provider settings.")
    if (
        settings.get("BEDROCK_READ_TIMEOUT_SECONDS") != "100"
        or settings.get("BEDROCK_CONNECT_TIMEOUT_SECONDS") != "3"
    ):
        raise ValueError("Use the explicit bounded fixture deadlines.")
    for case in cases:
        request, question = case["request"], case["question"]
        if (
            type(case["expected_accept"]) is not bool
            or type(case["expected_model_valid"]) is not bool
            or not isinstance(request.get("goal"), dict)
            or not isinstance(request.get("sourceDocuments"), list)
            or not isinstance(question.get("prompt"), str)
            or not question["prompt"]
            or not isinstance(question.get("topic"), str)
            or not _has_reviewable_choices(question)
        ):
            raise ValueError(
                "Each case needs its full normalized request and unchanged reviewable question."
            )
    source_files = [
        "question_generation.py",
        "question_verification.py",
        "question_quality.py",
        "request_contract.py",
        "question_difficulty.py",
        "generation_diagnostics.py",
        "service_errors.py",
        "evals/checkpoint_model_comparison.py",
        "evals/checkpoint_prompt_ablation.py",
    ]
    return {
        "experiment": "paired-model-single-item-review-v1",
        "fixture": copy.deepcopy(packet),
        "system_prompts": {
            "solver": SOLUTION_SYSTEM_PROMPT,
            "reviewer": REVIEW_SYSTEM_PROMPT,
        },
        "source_revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=SERVICE_DIR, text=True
        ).strip(),
        "source_sha256": {
            name: hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
            for name in source_files
        },
        "jobs": [
            {"case_id": case["case_id"], "model": model}
            for index, case in enumerate(cases)
            for model in (MODELS if index % 2 == 0 else list(reversed(MODELS)))
        ],
        "maximum_calls": MAX_CALLS,
        "maximum_calls_per_case_arm": MAX_CALLS_PER_JOB,
        "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": MAX_TOTAL_INPUT_BYTES,
        "input_budget_note": "Text bytes are a conservative allowance, not a certified token or billing cap.",
        "sdk_total_max_attempts": 1,
        "feedback_scoring": "Independent review required; decision matches alone never establish full correctness.",
    }


class ComparisonFailure(RuntimeError):
    pass


class RecordingClient:
    def __init__(self, client, report, persist):
        self.client, self.report, self.persist = client, report, persist
        self.job = None
        self.stage = None
        self.expected_user = None
        self.failed = False

    def converse(self, **request):
        expected_system = {
            "solver": SOLUTION_SYSTEM_PROMPT,
            "reviewer": REVIEW_SYSTEM_PROMPT,
        }[self.stage]
        expected = {
            "modelId": self.job["model"],
            "system": [{"text": expected_system}],
            "messages": [{"role": "user", "content": [{"text": self.expected_user}]}],
            "inferenceConfig": {"maxTokens": 16000},
            "additionalModelRequestFields": {
                "thinking": {"type": "adaptive"},
                "output_config": {"effort": "high"},
            },
        }
        size = len(expected_system.encode()) + len(self.expected_user.encode())
        calls = self.report["calls"]
        count = sum(
            call["case_id"] == self.job["case_id"]
            and call["model"] == self.job["model"]
            for call in calls
        )
        if (
            self.failed
            or request != expected
            or self.job["model"] not in MODELS
            or len(calls) >= MAX_CALLS
            or count >= MAX_CALLS_PER_JOB
            or size > MAX_INPUT_BYTES
            or self.report["input_utf8_bytes"] + size > MAX_TOTAL_INPUT_BYTES
        ):
            raise ComparisonFailure(
                "Dispatch contract or budget failed; no provider call made."
            )
        call = {
            **self.job,
            "stage": self.stage,
            "request": copy.deepcopy(request),
            "input_utf8_bytes": size,
            "status": "dispatch_started",
            "usage_known": False,
        }
        calls.append(call)
        self.report["input_utf8_bytes"] += size
        self.persist()
        started = time.monotonic()
        try:
            response = self.client.converse(**request)
            content = response.get("output", {}).get("message", {}).get("content", [])
            if not isinstance(content, list) or any(
                not isinstance(block, dict) for block in content
            ):
                raise ComparisonFailure("Malformed provider content.")
            call["response"] = {
                "text": [
                    block["text"]
                    for block in content
                    if isinstance(block.get("text"), str)
                ],
                "usage": response.get("usage", {}),
                "stopReason": response.get("stopReason"),
                "reasoningContentBlockCount": sum(
                    "reasoningContent" in block for block in content
                ),
            }
            usage = response.get("usage", {})
            call["usage_known"] = isinstance(usage, dict) and all(
                type(usage.get(key)) is int and usage[key] >= 0
                for key in ("inputTokens", "outputTokens")
            )
            if response.get("stopReason") != "end_turn":
                raise ComparisonFailure("Provider did not complete with end_turn.")
            call["status"] = "response_received"
            return response
        except Exception as error:
            self.failed = True
            call["status"] = "operational_failure"
            call["error"] = {"type": type(error).__name__}
            provider = getattr(error, "response", {}).get("Error", {})
            if isinstance(provider, dict) and isinstance(provider.get("Code"), str):
                call["error"]["provider_code"] = provider["Code"]
            raise
        finally:
            call["elapsed_seconds"] = round(time.monotonic() - started, 3)
            self.persist()


def validate_stage(raw, stage, question):
    """Use runtime fence parsing, while refusing malformed semantic rejections."""
    if stage == "solver":
        if _validated_solutions(raw, 1) is None:
            raise ComparisonFailure("Malformed solver output.")
        return
    reviews = _extract_json_object(raw).get("reviews")
    if (
        not isinstance(reviews, list)
        or len(reviews) != 1
        or not isinstance(reviews[0], dict)
    ):
        raise ComparisonFailure("Malformed review envelope.")
    item = reviews[0]
    if (
        type(item.get("index")) is not int
        or item["index"] != 0
        or type(item.get("valid")) is not bool
    ):
        raise ComparisonFailure("Malformed review index or verdict.")
    if not item["valid"]:
        if item.get("answer") != "":
            raise ComparisonFailure("Malformed negative verdict.")
        return
    feedback = item.get("choiceExplanations")
    if (
        item.get("answer") not in question["choices"]
        or type(item.get("difficulty")) is not int
        or not 1 <= item["difficulty"] <= 5
        or not _bounded_explanation(item.get("explanation"), 420)
        or not isinstance(feedback, dict)
        or set(feedback) != set(question["choices"])
        or not all(_bounded_explanation(value, 280) for value in feedback.values())
    ):
        raise ComparisonFailure("Malformed positive review or feedback.")


def new_client(settings, cli_credentials):
    if cli_credentials:
        from evals.checkpoint_prompt_ablation import use_aws_cli_credentials

        use_aws_cli_credentials()
    import boto3
    from botocore.config import Config

    return boto3.client(
        "bedrock-runtime",
        region_name=settings["BEDROCK_REGION"],
        config=Config(
            connect_timeout=3,
            read_timeout=int(settings["BEDROCK_READ_TIMEOUT_SECONDS"]),
            retries={"mode": "standard", "total_max_attempts": 1},
        ),
    )


def run_experiment(
    packet, directory, approved_plan_sha256, client=None, *, cli_credentials=False
):
    plan = make_plan(packet)
    if approved_plan_sha256 != digest(canonical(plan)):
        raise ValueError("The exact current canonical plan hash must be approved.")
    directory.mkdir(parents=True, exist_ok=False)
    write_json(directory / "plan.json", plan)
    report = {
        "plan_sha256": approved_plan_sha256,
        "calls": [],
        "input_utf8_bytes": 0,
        "results": [
            {
                **job,
                "status": "unattempted",
                "inventory_acceptance_matches_expected": None,
                "semantic_verdict_matches_expected": None,
                "stage_outputs": {},
                "feedback_assessment": "unassessed",
            }
            for job in plan["jobs"]
        ],
        "stopped_early": False,
        "status": "running",
    }

    def persist():
        write_json(directory / "capture.json", report)

    persist()
    try:
        recording = RecordingClient(
            client
            if client is not None
            else new_client(packet["settings"], cli_credentials),
            report,
            persist,
        )
        by_id = {case["case_id"]: case for case in packet["cases"]}
        for result in report["results"]:
            case = by_id[result["case_id"]]
            recording.job = {key: result[key] for key in ("case_id", "model")}
            result["status"] = "running"
            persist()
            metrics = {
                "ProviderCalls": 0,
                "BedrockInputTokens": 0,
                "BedrockOutputTokens": 0,
            }
            budget = ProviderCallBudget(MAX_CALLS_PER_JOB)
            started = time.monotonic()
            try:

                def generate(stage, system, user):
                    recording.stage, recording.expected_user = stage, user
                    raw = _generate_with_bedrock(
                        case["request"],
                        recording,
                        result["model"],
                        user_prompt=user,
                        system_prompt=system,
                        call_budget=budget,
                        request_metrics=metrics,
                    )
                    validate_stage(raw, stage, case["question"])
                    result["stage_outputs"][stage] = _extract_json_object(raw)
                    persist()
                    return raw

                settings = {
                    **packet["settings"],
                    "BEDROCK_MODEL_ID": result["model"],
                    "BEDROCK_VERIFICATION_MODEL_ID": result["model"],
                }
                with patch.dict(os.environ, settings):
                    returned = verify_questions(
                        [copy.deepcopy(case["question"])],
                        copy.deepcopy(case["request"]),
                        lambda system, user: generate("reviewer", system, user),
                        metrics,
                        solve=lambda system, user: generate("solver", system, user),
                    )
                reasons = metrics.get("QuestionQuality", {}).get("review", {})
                semantic_rejection = any(
                    reasons.get(key)
                    for key in ("unsupported_solution", "rejected_by_model")
                )
                malformed = set(reasons) - {
                    "unsupported_solution",
                    "rejected_by_model",
                    "answer_disagreement",
                    "difficulty_floor",
                    "difficulty_target",
                    "accepted",
                }
                if malformed:
                    raise ComparisonFailure("Malformed runtime verification result.")
                review = (
                    result["stage_outputs"]
                    .get("reviewer", {})
                    .get("reviews", [None])[0]
                )
                model_valid = review["valid"] if review is not None else None
                result.update(
                    status="completed",
                    accepted=bool(returned),
                    semantic_rejection=semantic_rejection,
                    returned_questions=returned,
                    model_valid=model_valid,
                    reviewed_key_matches_original=(
                        review["answer"] == case["question"]["expectedAnswer"]
                        if model_valid
                        else None
                    ),
                    inventory_acceptance_matches_expected=bool(returned)
                    == case["expected_accept"],
                    semantic_verdict_matches_expected=(
                        model_valid == case["expected_model_valid"]
                        if review is not None
                        else not case["expected_model_valid"]
                        if semantic_rejection
                        else None
                    ),
                )
            except Exception as error:
                result.update(
                    status="operational_failure",
                    error={"type": type(error).__name__},
                    inventory_acceptance_matches_expected=None,
                    semantic_verdict_matches_expected=None,
                )
                report["stopped_early"] = True
            finally:
                result["metrics"] = metrics
                result["elapsed_seconds"] = round(time.monotonic() - started, 3)
                persist()
            if report["stopped_early"]:
                break
        report["status"] = (
            "operational_failure" if report["stopped_early"] else "completed"
        )
    except Exception as error:
        report.update(
            status="operational_failure",
            stopped_early=True,
            error={"type": type(error).__name__},
        )
        raise
    finally:
        persist()
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, default=FIXTURE_PATH)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--plan-sha256")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    packet = json.loads(args.fixture.read_text())
    if args.execute:
        report = run_experiment(
            packet,
            args.output,
            args.plan_sha256,
            cli_credentials=args.aws_cli_credentials,
        )
        return 1 if report["stopped_early"] else 0
    plan = make_plan(packet)
    args.output.mkdir(parents=True, exist_ok=False)
    write_json(args.output / "plan.json", plan)
    print(
        json.dumps(
            {
                "plan_sha256": digest(canonical(plan)),
                "maximum_calls": MAX_CALLS,
                "execute": False,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
