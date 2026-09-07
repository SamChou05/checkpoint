#!/usr/bin/env python3
"""Dry-by-default paired 320/1200 stem-budget experiment; never serve its output.

Run this CLI in a dedicated evaluation process. Its scoped sanitizer override is
process-local, restored after each job, and never changes production source.
The shared recorder supplies durable dispatch intent, exact provider shape,
stage order, twelve/three call caps, UTF-8 input caps and no SDK retries.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import time
from unittest.mock import patch

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_source_authoring_eval as shared  # noqa: E402
from evals.checkpoint_model_comparison import canonical, digest, write_json  # noqa: E402
from generation_diagnostics import record_quality  # noqa: E402
import question_quality  # noqa: E402

EXPERIMENT = "paired-author-stem-budget-v1"
ARMS = {"stem_320": 320, "stem_1200": 1200}
MODEL, SETTINGS = shared.MODEL, shared.SETTINGS
MAX_CALLS, MAX_CALLS_PER_JOB = shared.MAX_CALLS, shared.MAX_CALLS_PER_JOB
STEM_INSTRUCTION = "Stem at most\n320 characters"
REVIEW_REASONS = {
    "accepted",
    "unsupported_solution",
    "solver_uncertain",
    "solver_unresolved_limitations",
    "solver_outcome_mismatch",
    "rejected_by_model",
    "answer_disagreement",
    "difficulty_floor",
    "difficulty_target",
    "invalid_choices",
    "answer_labels",
}


def source_hashes():
    return {
        **shared.source_hashes(),
        "evals/checkpoint_stem_length_eval.py": hashlib.sha256(
            Path(__file__).read_bytes()
        ).hexdigest(),
    }


def make_plan(packet):
    if question_quality.MAX_PROVIDER_PROMPT_CHARS != 320:
        raise ValueError("The unpatched production stem limit must still be 320.")
    with patch.dict(os.environ, SETTINGS):
        author = shared._system_prompt()
        if author.count(STEM_INSTRUCTION) != 1:
            raise ValueError("The exact single stem-budget instruction has changed.")
        # Reuse only the existing normalization/source/history validation and
        # counterbalanced ordering. Both new arms retain the full source packet.
        jobs = []
        for template in shared.planned_jobs(packet):
            limit = 320 if template["arm"] == "goal_only" else 1200
            request = copy.deepcopy(template["review_request"])
            jobs.append(
                {
                    "case_id": template["case_id"],
                    "arm": f"stem_{limit}",
                    "stem_limit_characters": limit,
                    "author_request": copy.deepcopy(request),
                    "review_request": request,
                    "author_user_prompt": shared._user_prompt(request),
                    "author_system_prompt": author.replace(
                        STEM_INSTRUCTION, f"Stem at most\n{limit} characters"
                    ),
                }
            )
    return {
        "experiment": EXPERIMENT,
        "fixture": copy.deepcopy(packet),
        "fixture_canonical_sha256": digest(canonical(packet)),
        "source_revision": shared.source_revision(),
        "source_sha256": source_hashes(),
        "dependencies": shared.dependencies(),
        "model": MODEL,
        "settings": copy.deepcopy(SETTINGS),
        "jobs": jobs,
        "system_prompts": {
            "solver": shared.SOLUTION_SYSTEM_PROMPT,
            "reviewer": shared.REVIEW_SYSTEM_PROMPT,
        },
        "maximum_calls": MAX_CALLS,
        "maximum_calls_per_job": MAX_CALLS_PER_JOB,
        "sdk_total_max_attempts": 1,
        "maximum_input_utf8_bytes_per_call": shared.MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": shared.MAX_TOTAL_INPUT_BYTES,
        "production_stem_limit_characters": 320,
        "input_budget_note": "Text bytes bound input allowance, not tokens or billed cost.",
        "comparison": "Only the author stem-limit numeral and matched process-local sanitizer limit differ; all model settings, sources, context and verifier prompts are identical.",
        "dynamic_prompt_note": "Frozen runtime builders construct solver/reviewer item payloads from generated content; complete requests are persisted before dispatch.",
        "isolation": "Execute only in a dedicated evaluation process; no serving, deployment, repair, retry or top-up.",
        "assessment": "Inventory acceptance, not correctness. Blind assessment and feedback assessment remain external.",
    }


def load_frozen_plan(path, approved_hash):
    plan = json.loads(path.read_text(encoding="utf-8"))
    if digest(canonical(plan)) != approved_hash:
        raise ValueError("The exact frozen canonical plan hash is required.")
    if plan != make_plan(plan["fixture"]):
        raise ValueError(
            "Frozen prompts, jobs, source, dependencies or budgets changed."
        )
    return plan


def occurrences(questions, job):
    rows = shared.raw_occurrences(questions, job)
    for row in rows:
        question = row["question"]
        prompt = question.get("prompt") if isinstance(question, dict) else None
        if isinstance(prompt, str):
            # Python's sanitizer counts code points, not UTF-8 bytes/graphemes.
            row["prompt_code_points"] = len(prompt)
            row["prompt_utf8_bytes"] = len(prompt.encode("utf-8"))
            row["sanitizer_prompt_code_points"] = len(
                question_quality._prompt_without_trailing_choice_echo(
                    prompt, question.get("choices")
                )
            )
    return rows


def production_observation(candidates, job, raw_rows):
    """Replay only deterministic sanitization; no second solver/reviewer call.

    Individual reasons identify the 320 gate independently of cross-item quota
    and duplicate effects; the complete batch observation retains those effects.
    """
    with patch.object(question_quality, "MAX_PROVIDER_PROMPT_CHARS", 320):
        for candidate, row in zip(candidates, raw_rows, strict=True):
            metrics = {}
            accepted = question_quality._sanitize_questions(
                [copy.deepcopy(candidate)], job["review_request"], metrics
            )
            row["production_320_individual"] = {
                "sanitized_count": len(accepted),
                "metrics": metrics,
            }
        metrics = {}
        sanitized = question_quality._sanitize_questions(
            copy.deepcopy(candidates), job["review_request"], metrics
        )
    return {
        "sanitized_count": len(sanitized),
        "metrics": metrics,
        "occurrences": occurrences(sanitized, job),
        "scope": "Current 320-character deterministic sanitizer only; not full production acceptance.",
    }


def execute_job(job, plan, result, recording, metrics, persist):
    budget = shared.ProviderCallBudget(MAX_CALLS_PER_JOB)

    def generate(stage, system, user):
        expected_system = (
            job["author_system_prompt"]
            if stage == "author"
            else plan["system_prompts"][stage]
        )
        if system != expected_system or (
            stage == "author" and user != job["author_user_prompt"]
        ):
            raise shared.TrialFailure("Stage prompt differs from frozen contract.")
        recording.stage, recording.system, recording.user = stage, system, user
        raw = shared._generate_with_bedrock(
            job["review_request"],
            recording,
            MODEL,
            user_prompt=user,
            system_prompt=system,
            call_budget=budget,
            request_metrics=metrics,
        )
        try:
            result["stage_outputs"][stage] = question_quality._extract_json_object(raw)
        except Exception:
            result["format_failure_stage"] = stage
            record_quality(metrics, "provider", "invalid_json")
            raise
        persist()
        if stage == "solver":
            items = json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])["items"]
            if shared._validated_solutions(raw, len(items)) is None:
                result["format_failure_stage"] = stage
                record_quality(metrics, "review", "invalid_solution")
                raise shared.TrialFailure("Malformed solver output.")
        elif stage == "reviewer":
            try:
                shared.validate_review(raw, user)
            except Exception:
                result["format_failure_stage"] = stage
                record_quality(metrics, "review", "invalid_envelope")
                raise
        return raw

    with (
        patch.dict(os.environ, SETTINGS),
        patch.object(
            question_quality, "MAX_PROVIDER_PROMPT_CHARS", job["stem_limit_characters"]
        ),
    ):
        generate("author", job["author_system_prompt"], job["author_user_prompt"])
        candidates = result["stage_outputs"]["author"].get("questions")
        if not isinstance(candidates, list):
            result["format_failure_stage"] = "author"
            record_quality(metrics, "sanitize", "invalid_envelope")
            raise shared.TrialFailure("Malformed author questions envelope.")
        result["raw_occurrences"] = occurrences(candidates, job)
        result["raw_count"] = len(candidates)
        result["raw_unblindable_count"] = sum(
            row["blinded"] is None for row in result["raw_occurrences"]
        )
        persist()
        try:
            shared.validate_author(candidates)
        except shared.TrialFailure:
            result["format_failure_stage"] = "author"
            record_quality(metrics, "sanitize", "invalid_item")
            raise
        result["production_320"] = production_observation(
            candidates, job, result["raw_occurrences"]
        )
        sanitized = question_quality._sanitize_questions(
            copy.deepcopy(candidates), job["review_request"], metrics
        )
        result["sanitized_occurrences"] = occurrences(sanitized, job)
        result["sanitized_count"] = len(sanitized)
        persist()
        returned = shared.verify_questions(
            copy.deepcopy(sanitized),
            copy.deepcopy(job["review_request"]),
            lambda system, user: generate("reviewer", system, user),
            metrics,
            solve=lambda system, user: generate("solver", system, user),
        )
        result["returned_occurrences"] = occurrences(returned, job)
    if set(metrics.get("QuestionQuality", {}).get("review", {})) - REVIEW_REASONS:
        raise shared.TrialFailure("Malformed runtime review result.")
    result.update(
        status="completed",
        returned_count=len(returned),
        inventory_target_met=len(returned) == 3,
    )


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
                "case_id": job["case_id"],
                "arm": job["arm"],
                "stem_limit_characters": job["stem_limit_characters"],
                "status": "unattempted",
                "raw_occurrences": [],
                "sanitized_occurrences": [],
                "returned_occurrences": [],
                "stage_outputs": {},
                "feedback_assessment": "unassessed",
            }
            for job in plan["jobs"]
        ],
    }

    def persist():
        write_json(directory / "capture.json", report)
        blinded = {}
        for result in report["results"]:
            rows = [
                row
                for stage in ("raw", "sanitized", "returned")
                for row in result[f"{stage}_occurrences"]
            ]
            rows += result.get("production_320", {}).get("occurrences", [])
            for row in rows:
                if row["blinded"] is not None:
                    blinded[row["blinded"]["id"]] = row["blinded"]
        write_json(
            directory / "blinded.json", [blinded[key] for key in sorted(blinded)]
        )

    persist()
    try:
        recording = shared.RecordingClient(
            client
            if client is not None
            else shared.new_client(SETTINGS, cli_credentials),
            report,
            persist,
        )
        for index, job in enumerate(plan["jobs"]):
            result = report["results"][index]
            result["status"], recording.job_index = "running", index
            metrics = {
                "ProviderCalls": 0,
                "BedrockInputTokens": 0,
                "BedrockOutputTokens": 0,
            }
            started = time.monotonic()
            try:
                execute_job(job, plan, result, recording, metrics, persist)
            except Exception as error:
                result.update(
                    status="operational_failure", error={"type": type(error).__name__}
                )
                report["stopped_early"] = True
            finally:
                calls = [call for call in report["calls"] if call["job_index"] == index]
                result["usage_known"] = all(call["usage_known"] for call in calls)
                for metric, key in (
                    ("BedrockInputTokens", "inputTokens"),
                    ("BedrockOutputTokens", "outputTokens"),
                ):
                    metrics[metric] = (
                        sum(call["response"]["usage"][key] for call in calls)
                        if result["usage_known"]
                        else None
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
