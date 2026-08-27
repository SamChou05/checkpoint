#!/usr/bin/env python3
# Scoring exports remain available from this historical CLI module.
# ruff: noqa: F401
"""Capture and score cross-domain question-generation evaluations."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any


SERVICE_DIR = Path(__file__).resolve().parents[1]
if str(SERVICE_DIR) not in sys.path:
    sys.path.insert(0, str(SERVICE_DIR))

import lambda_function  # noqa: E402
from evals.question_eval_scoring import (  # noqa: E402
    DEFAULT_FORBIDDEN_TERMS,
    DISALLOWED_CHOICE_TEXT,
    SCENARIO_SIGNALS,
    asks_for_free_response_artifact,
    blocked_prompt_duplicate,
    canonical,
    choice_key,
    choices_have_mixed_output_types,
    clean_text,
    contains_term,
    duplicate_prompt_key,
    escape_markdown_table,
    expected_is_bare_output,
    explanation_supports_different_choice,
    extract_questions,
    has_choice_length_imbalance,
    has_scenario_signal,
    integer,
    load_jsonl,
    looks_like_answer_label,
    looks_like_generic_meta_question,
    looks_truncated,
    minimum_usable_questions,
    missing_case_result,
    prompt_contains_embedded_options,
    prompt_contains_latex_markup,
    ratio,
    score_case_response,
    score_question,
    score_response_file,
)


DEFAULT_FIXTURE_PATH = (
    Path(__file__).resolve().parent / "fixtures" / "question_generation_cases.jsonl"
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate Checkpoint AI question-generation outputs."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    score_parser = subparsers.add_parser(
        "score", help="Score captured model responses against fixtures."
    )
    score_parser.add_argument(
        "--fixtures", default=str(DEFAULT_FIXTURE_PATH), help="JSONL fixture file."
    )
    score_parser.add_argument(
        "--responses", required=True, help="JSONL response file to score."
    )
    score_parser.add_argument("--output", help="Optional JSON report path.")
    score_parser.add_argument(
        "--markdown-output", help="Optional Markdown summary path."
    )
    score_parser.add_argument(
        "--no-fail", action="store_true", help="Always exit 0 after writing the report."
    )

    capture_parser = subparsers.add_parser(
        "capture-bedrock",
        help="Invoke the configured Bedrock backend prompt for each fixture and write responses JSONL.",
    )
    capture_parser.add_argument(
        "--fixtures", default=str(DEFAULT_FIXTURE_PATH), help="JSONL fixture file."
    )
    capture_parser.add_argument(
        "--responses", required=True, help="JSONL response output path."
    )
    capture_parser.add_argument(
        "--runs-per-case",
        type=int,
        default=1,
        help="Number of generations per fixture.",
    )
    capture_parser.add_argument(
        "--prompt-variant",
        default=None,
        help="Optional CHECKPOINT_PROMPT_VARIANT value for prompt A/B experiments.",
    )
    capture_parser.add_argument(
        "--sleep-seconds", type=float, default=0.0, help="Delay between provider calls."
    )
    capture_parser.add_argument(
        "--stop-on-error",
        action="store_true",
        help="Stop capture after the first provider error.",
    )
    capture_parser.add_argument(
        "--no-fail",
        action="store_true",
        help="Exit 0 even when provider errors are captured.",
    )

    args = parser.parse_args()
    if args.command == "score":
        report = score_response_file(Path(args.fixtures), Path(args.responses))
        write_report(report, args.output, args.markdown_output)
        print(summary_text(report))
        return 0 if args.no_fail or report["summary"]["failed_cases"] == 0 else 1

    error_count = capture_bedrock_responses(
        fixtures_path=Path(args.fixtures),
        responses_path=Path(args.responses),
        runs_per_case=args.runs_per_case,
        prompt_variant=args.prompt_variant,
        sleep_seconds=args.sleep_seconds,
        stop_on_error=args.stop_on_error,
    )
    return 0 if args.no_fail or error_count == 0 else 1


def capture_bedrock_responses(
    fixtures_path: Path,
    responses_path: Path,
    runs_per_case: int,
    prompt_variant: str | None,
    sleep_seconds: float,
    stop_on_error: bool,
) -> int:
    fixtures = load_jsonl(fixtures_path)
    responses_path.parent.mkdir(parents=True, exist_ok=True)
    error_count = 0
    previous_variant = os.environ.get("CHECKPOINT_PROMPT_VARIANT")
    if prompt_variant is not None:
        os.environ["CHECKPOINT_PROMPT_VARIANT"] = prompt_variant
    active_variant = os.environ.get("CHECKPOINT_PROMPT_VARIANT", "balanced")

    try:
        with responses_path.open("w", encoding="utf-8") as file:
            for fixture in fixtures:
                for run in range(1, runs_per_case + 1):
                    try:
                        normalized = lambda_function._normalize_request(
                            fixture["payload"]
                        )  # noqa: SLF001
                        questions, raw_attempts = capture_generation_attempts(
                            normalized
                        )
                        result_fields = {
                            "questions": questions,
                            "raw_question_count": sum(
                                len(attempt["raw_questions"])
                                for attempt in raw_attempts
                            ),
                            "raw_attempts": raw_attempts,
                            "raw_questions": [
                                question
                                for attempt in raw_attempts
                                for question in attempt["raw_questions"]
                            ],
                        }
                    except Exception as error:  # pragma: no cover - exact provider failures vary by environment.
                        error_count += 1
                        result_fields = {
                            "questions": [],
                            "provider_error": {
                                "type": type(error).__name__,
                                "message": clean_text(str(error)),
                            },
                        }
                    record = {
                        "case_id": fixture["case_id"],
                        "run": run,
                        "captured_at": int(time.time()),
                        "prompt_variant": active_variant,
                        "model_attempts": lambda_function._model_attempts(),  # noqa: SLF001
                        **result_fields,
                    }
                    file.write(
                        json.dumps(record, ensure_ascii=False, separators=(",", ":"))
                        + "\n"
                    )
                    file.flush()
                    if record.get("provider_error") and stop_on_error:
                        print(
                            f"Stopped after provider error for {fixture['case_id']} run {run}.",
                            file=sys.stderr,
                        )
                        return error_count
                    if sleep_seconds > 0:
                        time.sleep(sleep_seconds)
    finally:
        if prompt_variant is not None:
            if previous_variant is None:
                os.environ.pop("CHECKPOINT_PROMPT_VARIANT", None)
            else:
                os.environ["CHECKPOINT_PROMPT_VARIANT"] = previous_variant
    if error_count:
        print(
            f"Captured {error_count} provider errors in {responses_path}.",
            file=sys.stderr,
        )
    return error_count


def capture_generation_attempts(
    request: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    target_count = request["targetCount"]
    attempts = lambda_function._int_env(  # noqa: SLF001
        "GENERATION_ATTEMPTS",
        lambda_function.DEFAULT_GENERATION_ATTEMPTS,
        maximum=5,
    )
    questions: list[dict[str, Any]] = []
    raw_attempts: list[dict[str, Any]] = []
    current_request = json.loads(json.dumps(request))

    for attempt_number in range(1, attempts + 1):
        provider_payload = lambda_function._generate_provider_payload(
            current_request, None
        )  # noqa: SLF001
        raw_questions = provider_payload.get("questions", [])
        if not isinstance(raw_questions, list):
            raw_questions = []
        sanitized = lambda_function._sanitize_questions(raw_questions, current_request)  # noqa: SLF001
        raw_attempts.append(
            {
                "attempt": attempt_number,
                "requested_count": current_request["targetCount"],
                "raw_questions": raw_questions,
                "sanitized_count": len(sanitized),
            }
        )
        questions.extend(sanitized)

        if len(questions) >= target_count:
            break

        current_request = json.loads(json.dumps(request))
        current_request["targetCount"] = target_count - len(questions)
        current_request["existingPrompts"] = request["existingPrompts"] + [
            question["prompt"] for question in questions
        ]

    return questions[:target_count], raw_attempts


def write_report(
    report: dict[str, Any], output: str | None, markdown_output: str | None
) -> None:
    if output:
        output_path = Path(output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(
            json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )

    if markdown_output:
        markdown_path = Path(markdown_output)
        markdown_path.parent.mkdir(parents=True, exist_ok=True)
        markdown_path.write_text(markdown_report(report), encoding="utf-8")


def summary_text(report: dict[str, Any]) -> str:
    summary = report["summary"]
    return (
        f"Prompt eval: {summary['passed_cases']}/{summary['response_runs']} response runs passed; "
        f"{summary['total_usable_questions']}/{summary['total_questions']} questions usable "
        f"({summary['usable_question_rate']:.1%})."
    )


def markdown_report(report: dict[str, Any]) -> str:
    lines = [
        "# Checkpoint Question Generation Eval",
        "",
        summary_text(report),
        "",
        "| Case | Run | Pass | Usable | Failures | Warnings |",
        "| --- | ---: | :---: | ---: | --- | --- |",
    ]
    for result in report["cases"]:
        failures = "<br>".join(result["failures"]) if result["failures"] else ""
        warnings = "<br>".join(result["warnings"][:5]) if result["warnings"] else ""
        lines.append(
            "| {case_id} | {run} | {passed} | {usable}/{count} | {failures} | {warnings} |".format(
                case_id=result["case_id"],
                run="" if result["run"] is None else result["run"],
                passed="yes" if result["passed"] else "no",
                usable=result["usable_count"],
                count=result["question_count"],
                failures=escape_markdown_table(failures),
                warnings=escape_markdown_table(warnings),
            )
        )
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    raise SystemExit(main())
