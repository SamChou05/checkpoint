#!/usr/bin/env python3
"""Capture and score cross-domain question-generation evaluations."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any


SERVICE_DIR = Path(__file__).resolve().parents[1]
if str(SERVICE_DIR) not in sys.path:
    sys.path.insert(0, str(SERVICE_DIR))

import lambda_function  # noqa: E402


DEFAULT_FIXTURE_PATH = Path(__file__).resolve().parent / "fixtures" / "question_generation_cases.jsonl"
DEFAULT_FORBIDDEN_TERMS = [
    "blocked app",
    "screen time",
    "open another app",
    "study schedule",
    "study plan",
    "motivation",
]
DISALLOWED_CHOICE_TEXT = {
    "alloftheabove",
    "noneoftheabove",
    "bothaandb",
    "bothbandc",
    "allchoicesarecorrect",
}
SCENARIO_SIGNALS = [
    "if ",
    "when ",
    "suppose ",
    "given ",
    "because ",
    "therefore",
    "however",
    "a student",
    "an engineer",
    "a runner",
    "a function",
    "a passage",
    "an argument",
    "scenario",
    "constraint",
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate Checkpoint AI question-generation outputs.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    score_parser = subparsers.add_parser("score", help="Score captured model responses against fixtures.")
    score_parser.add_argument("--fixtures", default=str(DEFAULT_FIXTURE_PATH), help="JSONL fixture file.")
    score_parser.add_argument("--responses", required=True, help="JSONL response file to score.")
    score_parser.add_argument("--output", help="Optional JSON report path.")
    score_parser.add_argument("--markdown-output", help="Optional Markdown summary path.")
    score_parser.add_argument("--no-fail", action="store_true", help="Always exit 0 after writing the report.")

    capture_parser = subparsers.add_parser(
        "capture-bedrock",
        help="Invoke the configured Bedrock backend prompt for each fixture and write responses JSONL.",
    )
    capture_parser.add_argument("--fixtures", default=str(DEFAULT_FIXTURE_PATH), help="JSONL fixture file.")
    capture_parser.add_argument("--responses", required=True, help="JSONL response output path.")
    capture_parser.add_argument("--runs-per-case", type=int, default=1, help="Number of generations per fixture.")
    capture_parser.add_argument(
        "--prompt-variant",
        default=None,
        help="Optional CHECKPOINT_PROMPT_VARIANT value for prompt A/B experiments.",
    )
    capture_parser.add_argument("--sleep-seconds", type=float, default=0.0, help="Delay between provider calls.")
    capture_parser.add_argument("--stop-on-error", action="store_true", help="Stop capture after the first provider error.")
    capture_parser.add_argument("--no-fail", action="store_true", help="Exit 0 even when provider errors are captured.")

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


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as file:
        for line_number, line in enumerate(file, start=1):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            try:
                record = json.loads(stripped)
            except json.JSONDecodeError as error:
                raise ValueError(f"{path}:{line_number} is not valid JSONL") from error
            if not isinstance(record, dict):
                raise ValueError(f"{path}:{line_number} must contain a JSON object")
            records.append(record)
    return records


def score_response_file(fixtures_path: Path, responses_path: Path) -> dict[str, Any]:
    fixtures = {fixture["case_id"]: fixture for fixture in load_jsonl(fixtures_path)}
    responses = load_jsonl(responses_path)
    grouped_responses: dict[str, list[dict[str, Any]]] = {}

    for response in responses:
        case_id = response.get("case_id")
        if not isinstance(case_id, str):
            raise ValueError("Each response row must include a string case_id")
        grouped_responses.setdefault(case_id, []).append(response)

    case_results = []
    for case_id, fixture in fixtures.items():
        rows = grouped_responses.get(case_id, [])
        if not rows:
            case_results.append(missing_case_result(fixture))
            continue

        for response in rows:
            case_results.append(score_case_response(fixture, response))

    passed_cases = sum(1 for result in case_results if result["passed"])
    failed_cases = len(case_results) - passed_cases
    total_questions = sum(result["question_count"] for result in case_results)
    total_usable = sum(result["usable_count"] for result in case_results)

    return {
        "summary": {
            "fixture_count": len(fixtures),
            "response_runs": len(case_results),
            "passed_cases": passed_cases,
            "failed_cases": failed_cases,
            "total_questions": total_questions,
            "total_usable_questions": total_usable,
            "usable_question_rate": ratio(total_usable, total_questions),
        },
        "cases": case_results,
    }


def missing_case_result(fixture: dict[str, Any]) -> dict[str, Any]:
    return {
        "case_id": fixture["case_id"],
        "description": fixture.get("description", ""),
        "run": None,
        "passed": False,
        "question_count": 0,
        "usable_count": 0,
        "minimum_usable_questions": minimum_usable_questions(fixture),
        "failures": ["No response row found for this fixture."],
        "warnings": [],
        "questions": [],
    }


def score_case_response(fixture: dict[str, Any], response: dict[str, Any]) -> dict[str, Any]:
    questions = extract_questions(response)
    question_results = [score_question(question, fixture, index) for index, question in enumerate(questions)]
    usable_count = sum(1 for result in question_results if not result["failures"])
    min_usable = minimum_usable_questions(fixture)
    failures: list[str] = []
    warnings: list[str] = []

    provider_error = response.get("provider_error")
    if isinstance(provider_error, dict):
        error_type = clean_text(provider_error.get("type"))
        message = clean_text(provider_error.get("message"))
        failures.append(f"Provider error during capture: {error_type}: {message}")

    if usable_count < min_usable:
        failures.append(f"Only {usable_count} usable questions; expected at least {min_usable}.")

    seen_prompts: set[str] = set()
    for result in question_results:
        prompt_key = duplicate_prompt_key(result["prompt"])
        if prompt_key and prompt_key in seen_prompts:
            failures.append(f"Duplicate or near-duplicate prompt in batch: {result['prompt']}")
        seen_prompts.add(prompt_key)
        warnings.extend(f"Q{result['index'] + 1}: {warning}" for warning in result["warnings"])

    return {
        "case_id": fixture["case_id"],
        "description": fixture.get("description", ""),
        "run": response.get("run"),
        "passed": not failures,
        "question_count": len(questions),
        "usable_count": usable_count,
        "minimum_usable_questions": min_usable,
        "failures": failures,
        "warnings": warnings,
        "questions": question_results,
    }


def extract_questions(response: dict[str, Any]) -> list[dict[str, Any]]:
    if isinstance(response.get("questions"), list):
        return [question for question in response["questions"] if isinstance(question, dict)]

    body = response.get("body")
    if isinstance(body, str):
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError:
            return []
        if isinstance(parsed, dict) and isinstance(parsed.get("questions"), list):
            return [question for question in parsed["questions"] if isinstance(question, dict)]

    payload = response.get("response")
    if isinstance(payload, dict) and isinstance(payload.get("questions"), list):
        return [question for question in payload["questions"] if isinstance(question, dict)]

    return []


def score_question(question: dict[str, Any], fixture: dict[str, Any], index: int) -> dict[str, Any]:
    payload = fixture["payload"]
    expected = fixture.get("expect", {})
    minimum_difficulty = int(payload.get("minimumDifficulty", 1))
    configured_forbidden_terms = list(expected.get("forbidden_terms", []))
    forbidden_terms = configured_forbidden_terms or DEFAULT_FORBIDDEN_TERMS
    required_terms = [str(term) for term in expected.get("required_terms_any", []) if str(term).strip()]
    required_grounding_terms = [
        str(term)
        for term in expected.get("required_grounding_terms_any", [])
        if str(term).strip()
    ]

    prompt = clean_text(question.get("prompt"))
    expected_answer = clean_text(question.get("expectedAnswer"))
    explanation = clean_text(question.get("explanation"))
    topic = clean_text(question.get("topic"))
    choices = [
        cleaned
        for choice in question.get("choices", [])
        if (cleaned := clean_text(choice))
    ]
    difficulty = integer(question.get("difficulty"))
    format_value = clean_text(question.get("format")).lower()
    combined_text = " ".join([prompt, expected_answer, explanation, topic, " ".join(choices)])
    learner_visible_text = " ".join([prompt, expected_answer, " ".join(choices)])

    failures: list[str] = []
    warnings: list[str] = []

    if len(prompt) < 12:
        failures.append("Prompt is blank or too short.")
    if looks_truncated(prompt):
        failures.append("Prompt appears truncated at the sanitizer length limit.")
    if asks_for_free_response_artifact(prompt):
        failures.append("Prompt asks for a free-response artifact instead of a multiple-choice decision.")
    if looks_like_generic_meta_question(prompt, expected_answer, choices, explanation):
        failures.append("Question uses a generic meta-reasoning filler instead of subject-matter content.")
    if prompt_contains_embedded_options(prompt):
        failures.append("Prompt embeds answer options instead of keeping options only in choices.")
    if prompt_contains_latex_markup(prompt):
        failures.append("Prompt includes LaTeX markup that may not render cleanly in the app.")
    if not expected_answer:
        failures.append("Missing expectedAnswer.")
    if looks_like_answer_label(expected_answer):
        failures.append("expectedAnswer is an answer label instead of answer text.")
    if not explanation:
        failures.append("Missing explanation.")
    if not topic:
        failures.append("Missing topic.")
    if format_value not in {"multiple choice", "multiplechoice", ""}:
        failures.append(f"Unexpected format: {question.get('format')!r}.")
    if len(choices) != 4:
        failures.append(f"Expected 4 choices, found {len(choices)}.")
    elif any(looks_like_answer_label(choice) for choice in choices):
        failures.append("One or more choices are answer labels instead of answer text.")
    if difficulty < minimum_difficulty:
        failures.append(f"Difficulty {difficulty} is below requested minimum {minimum_difficulty}.")

    expected_matches = sum(1 for choice in choices if choice == expected_answer)
    if expected_matches != 1:
        failures.append(f"expectedAnswer must exactly match one choice; found {expected_matches}.")

    if len({choice_key(choice) for choice in choices}) != len(choices):
        failures.append("Choices are duplicates after case, punctuation, and answer-label normalization.")

    disallowed_choices = [choice for choice in choices if choice_key(choice) in DISALLOWED_CHOICE_TEXT]
    if disallowed_choices:
        failures.append(f"Disallowed choice text: {', '.join(disallowed_choices)}.")

    if expected_is_bare_output(expected_answer) and choices_have_mixed_output_types(choices):
        failures.append("Expected answer is a bare output, but choices mix outputs with explanations.")

    if explanation_supports_different_choice(expected_answer, choices, explanation):
        failures.append("Explanation supports a different answer choice than expectedAnswer.")

    duplicate_blocked = blocked_prompt_duplicate(prompt, payload)
    if duplicate_blocked:
        failures.append(f"Prompt duplicates existing/reported prompt: {duplicate_blocked}")

    leaked_terms = sorted({term for term in forbidden_terms if contains_term(combined_text, term)})
    if leaked_terms:
        failures.append(f"Forbidden terms appeared: {', '.join(leaked_terms)}.")

    if required_terms and not any(contains_term(combined_text, term) for term in required_terms):
        failures.append(f"No required subject signal found; expected one of: {', '.join(required_terms)}.")

    if required_grounding_terms and not any(
        contains_term(learner_visible_text, term) for term in required_grounding_terms
    ):
        failures.append(
            "Question and choices are not visibly grounded in the learning goal; "
            f"expected one of: {', '.join(required_grounding_terms)}."
        )

    if difficulty >= 3 and prompt and not has_scenario_signal(prompt):
        warnings.append("Difficulty is 3+ but prompt has weak scenario/application signal.")

    if has_choice_length_imbalance(choices):
        warnings.append("Answer choices have large length imbalance that may clue the answer.")

    if re.search(r"\bwhich of the following is (?:true|false)\b", prompt, flags=re.IGNORECASE):
        warnings.append("Prompt uses generic true/false wording.")

    return {
        "index": index,
        "prompt": prompt,
        "topic": topic,
        "difficulty": difficulty,
        "failures": failures,
        "warnings": warnings,
    }


def minimum_usable_questions(fixture: dict[str, Any]) -> int:
    expected = fixture.get("expect", {})
    if isinstance(expected.get("min_usable_questions"), int):
        return expected["min_usable_questions"]
    return integer(fixture.get("payload", {}).get("targetCount")) or 1


def blocked_prompt_duplicate(prompt: str, payload: dict[str, Any]) -> str | None:
    prompt_key = canonical(prompt)
    for source_key in ["existingPrompts", "reportedPrompts"]:
        for blocked in payload.get(source_key, []):
            if prompt_key == canonical(str(blocked)):
                return str(blocked)
    return None


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
                        normalized = lambda_function._normalize_request(fixture["payload"])  # noqa: SLF001
                        questions, raw_attempts = capture_generation_attempts(normalized)
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
                    file.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
                    file.flush()
                    if record.get("provider_error") and stop_on_error:
                        print(f"Stopped after provider error for {fixture['case_id']} run {run}.", file=sys.stderr)
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
        print(f"Captured {error_count} provider errors in {responses_path}.", file=sys.stderr)
    return error_count


def capture_generation_attempts(request: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
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
        provider_payload = lambda_function._generate_provider_payload(current_request, None)  # noqa: SLF001
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
        current_request["existingPrompts"] = (
            request["existingPrompts"] + [question["prompt"] for question in questions]
        )

    return questions[:target_count], raw_attempts


def write_report(report: dict[str, Any], output: str | None, markdown_output: str | None) -> None:
    if output:
        output_path = Path(output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

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


def clean_text(value: Any) -> str:
    return lambda_function._clean_text(value)  # noqa: SLF001


def integer(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def canonical(value: str) -> str:
    return lambda_function._canonical(value)  # noqa: SLF001


def duplicate_prompt_key(prompt: str) -> str:
    return lambda_function._duplicate_prompt_key(prompt)  # noqa: SLF001


def choice_key(value: str) -> str:
    return lambda_function._choice_uniqueness_key(value)  # noqa: SLF001


def contains_term(text: str, term: str) -> bool:
    cleaned_term = clean_text(term)
    if not cleaned_term:
        return False
    return cleaned_term.lower() in text.lower()


def has_scenario_signal(prompt: str) -> bool:
    lowered = prompt.lower()
    return (
        any(signal in lowered for signal in SCENARIO_SIGNALS)
        or ":" in prompt
        or ("?" in prompt and len(prompt) >= 90)
    )


def looks_truncated(prompt: str) -> bool:
    if len(prompt) < 355:
        return False
    return prompt[-1] not in ".?!`)]}'\""


def asks_for_free_response_artifact(prompt: str) -> bool:
    return bool(
        re.search(
            r"\b(write|create|produce)\s+(?:a\s+)?(?:function|code|algorithm|program|plan)\b",
            prompt,
            flags=re.IGNORECASE,
        )
    )


def looks_like_answer_label(value: str) -> bool:
    return lambda_function._looks_like_answer_label(value)  # noqa: SLF001


def looks_like_generic_meta_question(
    prompt: str,
    expected_answer: str,
    choices: list[str],
    explanation: str,
) -> bool:
    return lambda_function._looks_like_generic_meta_question(  # noqa: SLF001
        prompt,
        expected_answer,
        choices,
        explanation,
    )


def prompt_contains_embedded_options(prompt: str) -> bool:
    return lambda_function._prompt_contains_embedded_options(prompt)  # noqa: SLF001


def prompt_contains_latex_markup(prompt: str) -> bool:
    return lambda_function._prompt_contains_latex_markup(prompt)  # noqa: SLF001


def explanation_supports_different_choice(
    expected_answer: str,
    choices: list[str],
    explanation: str,
) -> bool:
    return lambda_function._explanation_supports_different_choice(expected_answer, choices, explanation)  # noqa: SLF001


def expected_is_bare_output(expected_answer: str) -> bool:
    stripped = expected_answer.strip()
    if stripped.lower() in {"true", "false", "null", "none", "undefined", "infinity", "-infinity", "∞", "-∞"}:
        return True
    if re.fullmatch(r"-?\d+(?:\.\d+)?", stripped):
        return True
    if re.fullmatch(r"-?\d+(?:\.\d+)?\s*/\s*-?\d+(?:\.\d+)?", stripped):
        return True
    if re.fullmatch(r"[-+*/^().\d\sπpie]+", stripped, flags=re.IGNORECASE) and re.search(r"\d", stripped):
        return True
    if re.fullmatch(r"\[[^\]]+\]", stripped):
        return True
    return False


def choices_have_mixed_output_types(choices: list[str]) -> bool:
    if len(choices) != 4:
        return False
    bare_count = sum(1 for choice in choices if expected_is_bare_output(choice))
    return 0 < bare_count < len(choices)


def has_choice_length_imbalance(choices: list[str]) -> bool:
    if len(choices) != 4:
        return False
    lengths = [len(choice) for choice in choices]
    shortest = max(1, min(lengths))
    longest = max(lengths)
    return longest - shortest >= 60 and longest / shortest >= 3


def ratio(numerator: int, denominator: int) -> float:
    return numerator / denominator if denominator else 0.0


def escape_markdown_table(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", "<br>")


if __name__ == "__main__":
    raise SystemExit(main())
