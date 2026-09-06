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
    _new_provider_call_budget,
    _question_coverage_payload,
    _verification_model_id,
)
from question_verification import verify_questions  # noqa: E402
from request_contract import (  # noqa: E402
    _normalize_request,
    _normalize_skill_map_inference_request,
)
from skill_maps import _infer_skill_map  # noqa: E402
from question_quality import _remaining_requested_skill_allocation  # noqa: E402
from service_errors import ProviderCallBudgetExceededError  # noqa: E402


def evaluate_review(case, client=None):
    request = _normalize_request(
        {
            "goal": case["goal"],
            "sourceDocuments": case.get("sourceDocuments", []),
            "targetCount": 1,
        }
    )
    reviews = []
    budget = ProviderCallBudget(2)
    metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}

    def review(system, prompt):
        raw = _generate_with_bedrock(
            request,
            client,
            _verification_model_id(),
            user_prompt=prompt,
            system_prompt=system,
            call_budget=budget,
            request_metrics=metrics,
        )
        reviews.append(raw)
        return raw

    accepted = verify_questions(
        [case["question"]], request, review, metrics, solve=review
    )
    decisions = metrics.get("QuestionQuality", {}).get("review", {})
    semantic_rejection = any(
        decisions.get(reason, 0)
        for reason in (
            "rejected_by_model",
            "answer_disagreement",
            "unsupported_solution",
        )
    )
    return {
        "case_id": case["case_id"],
        "passed": bool(accepted) if case["expected_accept"] else semantic_rejection,
        "expected_accept": case["expected_accept"],
        "accepted": bool(accepted),
        "rationale": case["rationale"],
        "reviews": reviews,
        "provider_calls": budget.calls,
        "metrics": metrics,
    }


def generate_sample(case, client=None, *, infer_skills=False, max_jobs=3):
    """Mirror finite inventory top-offs locally, with at most three bounded jobs."""
    if type(max_jobs) is not int or not 1 <= max_jobs <= 3:
        raise ValueError("max_jobs must be between 1 and 3")
    payload = copy.deepcopy(case["payload"])
    target_count = 5
    calls = 0
    metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
    if infer_skills:
        inference_budget = ProviderCallBudget(3)
        skill_map = _infer_skill_map(
            _normalize_skill_map_inference_request(payload),
            client,
            call_budget=inference_budget,
            request_metrics=metrics,
        )
        calls += inference_budget.calls
        skills = skill_map["skills"]
        target_count = max(target_count, len(skills))
        payload["skillMap"] = skill_map
        # Synthetic targets test independent challenge levels, not the phone's
        # derivation of those levels from actual learner answers.
        minimum = _normalize_request(payload)["minimumDifficulty"]
        payload["adaptiveSkillPlans"] = [
            {
                "skillID": skill["id"],
                "targetDifficulty": max(minimum, 2 if index % 2 == 0 else 4),
                "evidenceCount": 0,
            }
            for index, skill in enumerate(skills)
        ]
        payload["desiredSkillAllocation"] = {
            skill["id"]: target_count // len(skills)
            + int(index < target_count % len(skills))
            for index, skill in enumerate(skills)
        }
    base = _normalize_request({**payload, "targetCount": target_count})
    questions = []
    jobs = 0
    errors = []
    for _ in range(max_jobs):
        request = copy.deepcopy(base)
        request["targetCount"] = target_count - len(questions)
        if base.get("skillMap"):
            request["requestedSkillAllocation"] = _remaining_requested_skill_allocation(
                base, questions
            )
        request["existingPrompts"] += [question["prompt"] for question in questions]
        request["existingQuestionCoverage"] += [
            _question_coverage_payload(question) for question in questions
        ]
        # Mirror runtime limits without consuming the deployed DynamoDB quota.
        budget = _new_provider_call_budget(None, reserve_call=lambda: None)
        try:
            questions += _generate_sanitized_questions(
                request, client, call_budget=budget, request_metrics=metrics
            )
        except ProviderCallBudgetExceededError:
            # Keep prior inventory visible in the report even if a bounded job
            # exhausts its calls without producing any reviewed questions.
            pass
        except Exception as error:
            # Preserve observations and prior inventory when a provider fails.
            errors.append({"job": jobs + 1, "error_type": type(error).__name__})
        calls += budget.calls
        jobs += 1
        if len(questions) == target_count or errors:
            break
    return {
        "case_id": case["case_id"],
        "passed": len(questions) == target_count,
        "target_count": target_count,
        "questions": questions,
        "skill_map": base.get("skillMap"),
        "adaptive_skill_plans": base["adaptiveSkillPlans"],
        "provider_calls": calls,
        "jobs": jobs,
        "errors": errors,
        "metrics": metrics,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--max-generation-jobs", type=int, choices=(1, 2, 3), default=3)
    parser.add_argument(
        "--review-fixtures",
        type=Path,
        default=SERVICE_DIR / "evals/fixtures/question_verification_cases.jsonl",
    )
    parser.add_argument(
        "--generation",
        action="store_true",
        help="Also generate reviewed questions for every selected generation fixture.",
    )
    parser.add_argument(
        "--generation-fixtures",
        type=Path,
        default=SERVICE_DIR / "evals/fixtures/question_generation_cases.jsonl",
        help="Any JSONL file containing case_id and a generation request payload.",
    )
    parser.add_argument(
        "--case-id",
        action="append",
        default=[],
        help="Run only these case IDs (repeatable); defaults to all eligible cases.",
    )
    parser.add_argument(
        "--infer-skills",
        action="store_true",
        help="Infer each goal's skills, then test different per-skill target levels with 5–6 questions.",
    )
    args = parser.parse_args()
    if args.infer_skills and not args.generation:
        parser.error("--infer-skills requires --generation")
    results = []
    cases = [json.loads(line) for line in args.review_fixtures.read_text().splitlines()]
    tasks = [
        (case["case_id"], lambda case=case: evaluate_review(case)) for case in cases
    ]
    if args.generation:
        for line in args.generation_fixtures.read_text().splitlines():
            case = json.loads(line)
            tasks.append(
                (
                    case["case_id"],
                    lambda case=case: generate_sample(
                        case,
                        infer_skills=args.infer_skills,
                        max_jobs=args.max_generation_jobs,
                    ),
                )
            )
    if args.case_id:
        unknown = set(args.case_id) - {case_id for case_id, _ in tasks}
        if unknown:
            parser.error("Unknown or disabled case IDs: " + ", ".join(sorted(unknown)))
        tasks = [(case_id, run) for case_id, run in tasks if case_id in args.case_id]
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
                    if key
                    not in {
                        "reviews",
                        "questions",
                        "rationale",
                        "skill_map",
                        "adaptive_skill_plans",
                    }
                }
            ),
            flush=True,
        )
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
