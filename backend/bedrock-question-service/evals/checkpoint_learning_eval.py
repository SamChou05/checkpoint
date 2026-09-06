#!/usr/bin/env python3
"""Exercise actual review and generation against Bedrock; never deploys anything.

Use configured AWS credentials, BEDROCK_MODEL_ID, and AWS_REGION. Output includes
question text and reviewer reasoning, so use synthetic goals and private files.
The small correctness set is a regression gate, not an efficacy benchmark.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
import time
from pathlib import Path

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from question_generation import (  # noqa: E402
    ProviderCallBudget,
    _generate_sanitized_questions,
    _generate_with_bedrock,
    _model_attempts,
    _question_coverage_payload,
    _verification_model_id,
)
from question_verification import verify_questions  # noqa: E402
from request_contract import _normalize_request  # noqa: E402


def evaluate_review(case, client=None):
    request = _normalize_request({"goal": case["goal"], "targetCount": 1})
    reviews = []
    budget = ProviderCallBudget(1)

    def review(system, prompt):
        raw = _generate_with_bedrock(
            request,
            client,
            _verification_model_id(),
            user_prompt=prompt,
            system_prompt=system,
            call_budget=budget,
        )
        reviews.append(raw)
        return raw

    accepted = verify_questions([case["question"]], request, review)
    return {
        "case_id": case["case_id"],
        "passed": bool(accepted) == case["expected_accept"],
        "expected_accept": case["expected_accept"],
        "accepted": bool(accepted),
        "rationale": case["rationale"],
        "reviews": reviews,
        "provider_calls": budget.calls,
    }


def generate_sample(case, client=None):
    """Mirror finite inventory top-offs locally, with at most three bounded jobs."""
    base = _normalize_request({**case["payload"], "targetCount": 5})
    questions = []
    calls = 0
    jobs = 0
    for _ in range(3):
        request = copy.deepcopy(base)
        request["targetCount"] = 5 - len(questions)
        request["existingPrompts"] += [question["prompt"] for question in questions]
        request["existingQuestionCoverage"] += [
            _question_coverage_payload(question) for question in questions
        ]
        budget = ProviderCallBudget(5)
        questions += _generate_sanitized_questions(request, client, call_budget=budget)
        calls += budget.calls
        jobs += 1
        if len(questions) == 5:
            break
    return {
        "case_id": case["case_id"],
        "passed": len(questions) == 5,
        "questions": questions,
        "provider_calls": calls,
        "jobs": jobs,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--generation",
        action="store_true",
        help="Also generate five verified questions for each requested domain.",
    )
    args = parser.parse_args()
    results = []
    cases = [
        json.loads(line)
        for line in (SERVICE_DIR / "evals/fixtures/question_verification_cases.jsonl")
        .read_text()
        .splitlines()
    ]
    tasks = [
        (case["case_id"], lambda case=case: evaluate_review(case)) for case in cases
    ]
    if args.generation:
        domains = {
            "leetcode_style_interview_concrete_algorithms",
            "mcat_science_passage_reasoning",
            "lsat_logical_reasoning_medium",
        }
        for line in (
            (SERVICE_DIR / "evals/fixtures/question_generation_cases.jsonl")
            .read_text()
            .splitlines()
        ):
            case = json.loads(line)
            if case["case_id"] not in domains:
                continue

            tasks.append((case["case_id"], lambda case=case: generate_sample(case)))
    for case_id, run in tasks:
        started = time.monotonic()
        try:
            result = run()
        except Exception as error:
            result = {
                "case_id": case_id,
                "passed": False,
                "error_type": type(error).__name__,
            }
        result["elapsed_seconds"] = round(time.monotonic() - started, 2)
        results.append(result)
        Path(args.output).write_text(
            json.dumps(
                {
                    "model": _model_attempts()[0],
                    "review_model": _verification_model_id(),
                    "results": results,
                },
                indent=2,
            )
            + "\n"
        )
        print(
            json.dumps(
                {
                    key: value
                    for key, value in result.items()
                    if key not in {"reviews", "questions", "rationale"}
                }
            ),
            flush=True,
        )
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
