#!/usr/bin/env python3
"""Paired source access for authors; both verifier arms receive the same evidence.

Dry preparation freezes a plan. Execution reads that existing plan into a fresh
capture directory: four jobs, at most twelve calls, no repairs/retries/top-ups.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
from unittest.mock import patch

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals.checkpoint_full_pipeline_smoke import MODEL, SETTINGS as BASE_SETTINGS  # noqa: E402
from evals.checkpoint_model_comparison import (  # noqa: E402
    canonical,
    digest,
    new_client,
    validate_stage,
    write_json,
)
from question_generation import (  # noqa: E402
    ProviderCallBudget,
    _generate_with_bedrock,
    _system_prompt,
    _user_prompt,
)
from question_quality import _extract_json_object, _sanitize_questions  # noqa: E402
from generation_diagnostics import record_quality  # noqa: E402
from question_verification import (  # noqa: E402
    REVIEW_SYSTEM_PROMPT,
    SOLUTION_SYSTEM_PROMPT,
    _validated_solutions,
    verify_questions,
)
from request_contract import _normalize_request  # noqa: E402

MAX_CALLS = 12
MAX_CALLS_PER_JOB = 3
MAX_INPUT_BYTES = 32000
MAX_TOTAL_INPUT_BYTES = 384000
ARMS = ("goal_only", "source_first")
SETTINGS = {**BASE_SETTINGS, "CHECKPOINT_PROMPT_VARIANT": "balanced"}
EXPERIMENT = "source-access-at-authoring-v1"


def source_hashes():
    paths = sorted(SERVICE_DIR.glob("*.py")) + [
        SERVICE_DIR / name
        for name in (
            "evals/checkpoint_source_authoring_eval.py",
            "evals/checkpoint_model_comparison.py",
            "evals/checkpoint_full_pipeline_smoke.py",
            "evals/checkpoint_learning_eval.py",
            "evals/checkpoint_prompt_ablation.py",
        )
    ]
    return {
        str(path.relative_to(SERVICE_DIR)): hashlib.sha256(
            path.read_bytes()
        ).hexdigest()
        for path in paths
    }


def dependencies():
    result = {"python": platform.python_version()}
    for package in ("boto3", "botocore"):
        try:
            result[package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            result[package] = None
    return result


def source_revision():
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=SERVICE_DIR, text=True
    ).strip()


def planned_jobs(packet):
    cases = packet["cases"]
    if len(cases) != 2 or len({case["case_id"] for case in cases}) != 2:
        raise ValueError("Exactly two distinct goals are required.")
    jobs = []
    for index, case in enumerate(cases):
        payload = case["payload"]
        if payload.get("targetCount") != 3 or payload.get("minimumDifficulty") != 3:
            raise ValueError("Each goal must request three level-three questions.")
        review_request = _normalize_request(payload)
        if not review_request["sourceDocuments"]:
            raise ValueError("Each goal needs a reference packet.")
        original_sources = [
            {k: d[k] for k in ("name", "text")} for d in payload["sourceDocuments"]
        ]
        normalized_sources = [
            {k: d[k] for k in ("name", "text")}
            for d in review_request["sourceDocuments"]
        ]
        if original_sources != normalized_sources or any(
            d.get("truncated") for d in review_request["sourceDocuments"]
        ):
            raise ValueError(
                "References must survive normalization without clipping or rewriting."
            )
        if any(
            review_request.get(key)
            for key in (
                "existingPrompts",
                "existingQuestionCoverage",
                "reportedPrompts",
                "blockedStemFingerprints",
                "previousAttemptFeedback",
            )
        ):
            raise ValueError(
                "No prior generated questions or cross-arm coverage may enter this trial."
            )
        for arm in ARMS if index == 0 else ARMS[::-1]:
            author_request = copy.deepcopy(review_request)
            if arm == "goal_only":
                author_request["sourceDocuments"] = []
            jobs.append(
                {
                    "case_id": case["case_id"],
                    "arm": arm,
                    "author_request": author_request,
                    "review_request": copy.deepcopy(review_request),
                    "author_user_prompt": _user_prompt(author_request),
                }
            )
    return jobs


def make_plan(packet):
    with patch.dict(os.environ, SETTINGS):
        return {
            "experiment": EXPERIMENT,
            "fixture": copy.deepcopy(packet),
            "source_revision": source_revision(),
            "source_sha256": source_hashes(),
            "dependencies": dependencies(),
            "model": MODEL,
            "settings": SETTINGS,
            "system_prompts": {
                "author": _system_prompt(),
                "solver": SOLUTION_SYSTEM_PROMPT,
                "reviewer": REVIEW_SYSTEM_PROMPT,
            },
            "jobs": planned_jobs(packet),
            "maximum_calls": MAX_CALLS,
            "maximum_calls_per_job": MAX_CALLS_PER_JOB,
            "sdk_total_max_attempts": 1,
            "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
            "maximum_input_utf8_bytes_total": MAX_TOTAL_INPUT_BYTES,
            "input_budget_note": "Text bytes are an input allowance, not a certified token or billing cap.",
            "comparison": "Only author source access differs. Both review arms receive the same full source packet.",
            "dynamic_prompt_note": "Solver/reviewer item payloads depend on generated candidates; frozen builders construct them and complete requests are saved before dispatch.",
        }


def load_frozen_plan(path, approved_hash):
    plan = json.loads(path.read_text(encoding="utf-8"))
    if digest(canonical(plan)) != approved_hash:
        raise ValueError("The exact frozen canonical plan hash is required.")
    if (
        plan.get("experiment") != EXPERIMENT
        or plan.get("model") != MODEL
        or plan.get("settings") != SETTINGS
        or plan.get("source_sha256") != source_hashes()
        or plan.get("source_revision") != source_revision()
        or plan.get("dependencies") != dependencies()
    ):
        raise ValueError("Frozen source, dependencies, or settings no longer match.")
    with patch.dict(os.environ, SETTINGS):
        if plan["jobs"] != planned_jobs(plan["fixture"]) or plan["system_prompts"] != {
            "author": _system_prompt(),
            "solver": SOLUTION_SYSTEM_PROMPT,
            "reviewer": REVIEW_SYSTEM_PROMPT,
        }:
            raise ValueError("Frozen requests or prompts no longer match.")
    if any(
        plan.get(key) != value
        for key, value in {
            "maximum_calls": MAX_CALLS,
            "maximum_calls_per_job": MAX_CALLS_PER_JOB,
            "sdk_total_max_attempts": 1,
            "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
            "maximum_input_utf8_bytes_total": MAX_TOTAL_INPUT_BYTES,
        }.items()
    ):
        raise ValueError("The frozen budget does not match the bounded experiment.")
    return plan


class TrialFailure(RuntimeError):
    pass


def validate_author(candidates):
    """Types define the format boundary; semantic/length/choice defects use runtime filters."""
    required_text = ("prompt", "expectedAnswer", "explanation", "topic", "format")
    if any(
        not isinstance(item, dict)
        or any(not isinstance(item.get(key), str) for key in required_text)
        or type(item.get("difficulty")) is not int
        or not isinstance(item.get("choices"), list)
        or not all(isinstance(choice, str) for choice in item["choices"])
        for item in candidates
    ):
        raise TrialFailure("Malformed required author fields.")


class RecordingClient:
    def __init__(self, client, report, persist):
        self.client, self.report, self.persist = client, report, persist
        self.job_index = None
        self.stage = self.system = self.user = None
        self.failed = False

    def converse(self, **request):
        expected = {
            "modelId": MODEL,
            "system": [{"text": self.system}],
            "messages": [{"role": "user", "content": [{"text": self.user}]}],
            "inferenceConfig": {"maxTokens": 16000},
            "additionalModelRequestFields": {
                "thinking": {"type": "adaptive"},
                "output_config": {"effort": "high"},
            },
        }
        calls = self.report["calls"]
        previous = [
            call["stage"] for call in calls if call["job_index"] == self.job_index
        ]
        size = len(self.system.encode("utf-8")) + len(self.user.encode("utf-8"))
        if (
            self.failed
            or request != expected
            or len(calls) >= MAX_CALLS
            or previous + [self.stage]
            != ["author", "solver", "reviewer"][: len(previous) + 1]
            or len(previous) >= MAX_CALLS_PER_JOB
            or size > MAX_INPUT_BYTES
            or self.report["input_utf8_bytes"] + size > MAX_TOTAL_INPUT_BYTES
        ):
            raise TrialFailure(
                "Dispatch shape, stage order or budget rejected; no provider call made."
            )
        call = {
            "job_index": self.job_index,
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
            blocks = response.get("output", {}).get("message", {}).get("content", [])
            if not isinstance(blocks, list) or any(
                not isinstance(b, dict) for b in blocks
            ):
                raise TrialFailure("Malformed provider content.")
            usage = response.get("usage", {})
            call["response"] = {
                "text": [b["text"] for b in blocks if isinstance(b.get("text"), str)],
                "stopReason": response.get("stopReason"),
                "usage": usage,
                "reasoningContentBlockCount": sum(
                    "reasoningContent" in b for b in blocks
                ),
            }
            call["usage_known"] = isinstance(usage, dict) and all(
                type(usage.get(k)) is int and usage[k] >= 0
                for k in ("inputTokens", "outputTokens")
            )
            if response.get("stopReason") != "end_turn":
                raise TrialFailure("Provider did not finish with end_turn.")
            call["status"] = "response_received"
            return response
        except Exception as error:
            self.failed = True
            call.update(
                status="operational_failure", error={"type": type(error).__name__}
            )
            provider = getattr(error, "response", None)
            if isinstance(provider, dict) and isinstance(
                provider.get("Error", {}).get("Code"), str
            ):
                call["error"]["provider_code"] = provider["Error"]["Code"]
            raise
        finally:
            call["elapsed_seconds"] = round(time.monotonic() - started, 3)
            self.persist()


def validate_review(raw, user):
    items = json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])["items"]
    rows = _extract_json_object(raw).get("reviews")
    if not isinstance(rows, list) or len(rows) != len(items):
        raise TrialFailure("Malformed reviewer coverage.")
    indices = [row.get("index") for row in rows if isinstance(row, dict)]
    if (
        len(indices) != len(rows)
        or any(type(i) is not int for i in indices)
        or set(indices) != set(range(len(items)))
    ):
        raise TrialFailure("Malformed reviewer indices.")
    for row in rows:
        # Reuse the established per-item schema check after validating original indices.
        validate_stage(
            json.dumps({"reviews": [{**row, "index": 0}]}),
            "reviewer",
            items[row["index"]],
        )


def raw_occurrences(raw_questions, job):
    result = []
    for index, question in enumerate(raw_questions):
        blind = None
        if (
            isinstance(question, dict)
            and isinstance(question.get("prompt"), str)
            and isinstance(question.get("choices"), list)
            and all(isinstance(c, str) for c in question["choices"])
        ):
            content = {
                "goal": job["review_request"]["goal"],
                "sourceDocuments": job["review_request"]["sourceDocuments"],
                "prompt": question["prompt"],
                "choices": question["choices"],
            }
            blind = {"id": digest(canonical(content)), **content}
        result.append(
            {"item_index": index, "question": copy.deepcopy(question), "blinded": blind}
        )
    return result


def run_experiment(
    plan_path, approved_hash, directory, client=None, *, cli_credentials=False
):
    plan = load_frozen_plan(plan_path, approved_hash)
    directory.mkdir(parents=True, exist_ok=False)
    report = {
        "plan_sha256": approved_hash,
        "plan_path": str(plan_path.resolve()),
        "plan": plan,
        "status": "running",
        "stopped_early": False,
        "calls": [],
        "input_utf8_bytes": 0,
        "results": [
            {
                "case_id": j["case_id"],
                "arm": j["arm"],
                "status": "unattempted",
                "raw_occurrences": [],
                "sanitized_occurrences": [],
                "returned_occurrences": [],
                "stage_outputs": {},
                "feedback_assessment": "unassessed",
            }
            for j in plan["jobs"]
        ],
    }

    def persist():
        write_json(directory / "capture.json", report)
        blinded = {
            occ["blinded"]["id"]: occ["blinded"]
            for result in report["results"]
            for stage in ("raw", "sanitized", "returned")
            for occ in result[f"{stage}_occurrences"]
            if occ["blinded"] is not None
        }
        write_json(
            directory / "blinded.json", [blinded[key] for key in sorted(blinded)]
        )

    persist()
    try:
        recording = RecordingClient(
            client if client is not None else new_client(SETTINGS, cli_credentials),
            report,
            persist,
        )
        for job_index, job in enumerate(plan["jobs"]):
            result = report["results"][job_index]
            result["status"] = "running"
            recording.job_index = job_index
            metrics = {
                "ProviderCalls": 0,
                "BedrockInputTokens": 0,
                "BedrockOutputTokens": 0,
            }
            budget = ProviderCallBudget(MAX_CALLS_PER_JOB)
            started = time.monotonic()
            try:

                def generate(stage, system, user):
                    recording.stage, recording.system, recording.user = (
                        stage,
                        system,
                        user,
                    )
                    raw = _generate_with_bedrock(
                        job["review_request"],
                        recording,
                        MODEL,
                        user_prompt=user,
                        system_prompt=system,
                        call_budget=budget,
                        request_metrics=metrics,
                    )
                    try:
                        parsed = _extract_json_object(raw)
                    except Exception:
                        result["format_failure_stage"] = stage
                        record_quality(metrics, "provider", "invalid_json")
                        raise
                    result["stage_outputs"][stage] = parsed
                    persist()
                    if (
                        stage == "solver"
                        and _validated_solutions(
                            raw,
                            len(
                                json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])[
                                    "items"
                                ]
                            ),
                        )
                        is None
                    ):
                        result["format_failure_stage"] = stage
                        record_quality(metrics, "review", "invalid_solution")
                        raise TrialFailure("Malformed solver output.")
                    if stage == "reviewer":
                        try:
                            validate_review(raw, user)
                        except Exception:
                            result["format_failure_stage"] = stage
                            record_quality(metrics, "review", "invalid_envelope")
                            raise
                    return raw

                with patch.dict(os.environ, SETTINGS):
                    raw = generate(
                        "author",
                        plan["system_prompts"]["author"],
                        job["author_user_prompt"],
                    )
                    candidates = _extract_json_object(raw).get("questions")
                    if not isinstance(candidates, list):
                        result["format_failure_stage"] = "author"
                        record_quality(metrics, "sanitize", "invalid_envelope")
                        raise TrialFailure("Malformed author questions envelope.")
                    result["raw_occurrences"] = raw_occurrences(candidates, job)
                    result["raw_count"] = len(candidates)
                    result["raw_unblindable_count"] = sum(
                        occurrence["blinded"] is None
                        for occurrence in result["raw_occurrences"]
                    )
                    persist()
                    try:
                        validate_author(candidates)
                    except TrialFailure:
                        result["format_failure_stage"] = "author"
                        record_quality(metrics, "sanitize", "invalid_item")
                        raise
                    result["sanitized_questions"] = _sanitize_questions(
                        candidates, job["review_request"], metrics
                    )
                    result["sanitized_occurrences"] = raw_occurrences(
                        result["sanitized_questions"], job
                    )
                    result["sanitized_count"] = len(result["sanitized_questions"])
                    persist()
                    result["returned_questions"] = verify_questions(
                        copy.deepcopy(result["sanitized_questions"]),
                        copy.deepcopy(job["review_request"]),
                        lambda system, user: generate("reviewer", system, user),
                        metrics,
                        solve=lambda system, user: generate("solver", system, user),
                    )
                    result["returned_occurrences"] = raw_occurrences(
                        result["returned_questions"], job
                    )
                reasons = metrics.get("QuestionQuality", {}).get("review", {})
                if set(reasons) - {
                    "accepted",
                    "unsupported_solution",
                    "solver_uncertain",
                    "solver_outcome_mismatch",
                    "rejected_by_model",
                    "answer_disagreement",
                    "difficulty_floor",
                    "difficulty_target",
                    "invalid_choices",
                    "answer_labels",
                }:
                    raise TrialFailure("Malformed runtime review result.")
                result.update(
                    status="completed",
                    raw_count=len(candidates),
                    sanitized_count=len(result["sanitized_questions"]),
                    returned_count=len(result["returned_questions"]),
                    inventory_target_met=len(result["returned_questions"]) == 3,
                )
            except Exception as error:
                result.update(
                    status="operational_failure", error={"type": type(error).__name__}
                )
                report["stopped_early"] = True
            finally:
                job_calls = [
                    call for call in report["calls"] if call["job_index"] == job_index
                ]
                result["usage_known"] = all(call["usage_known"] for call in job_calls)
                # Runtime counters use zero defaults; do not represent unknown billing
                # as zero when a response is missing. Per-call known usage stays saved.
                if not result["usage_known"]:
                    metrics["BedrockInputTokens"] = None
                    metrics["BedrockOutputTokens"] = None
                else:
                    for metric, key in (
                        ("BedrockInputTokens", "inputTokens"),
                        ("BedrockOutputTokens", "outputTokens"),
                    ):
                        metrics[metric] = sum(
                            call["response"]["usage"][key] for call in job_calls
                        )
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
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--plan-sha256")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    if args.execute:
        if args.plan is None or args.fixture is not None:
            parser.error("Execution requires an existing --plan and no --fixture.")
        report = run_experiment(
            args.plan,
            args.plan_sha256,
            args.output,
            cli_credentials=args.aws_cli_credentials,
        )
        return int(report["stopped_early"])
    if args.fixture is None or args.plan is not None:
        parser.error("Preparation requires --fixture and no --plan.")
    plan = make_plan(json.loads(args.fixture.read_text(encoding="utf-8")))
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
