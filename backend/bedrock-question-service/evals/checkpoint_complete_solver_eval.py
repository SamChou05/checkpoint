#!/usr/bin/env python3
"""Dry-by-default, sixteen-call comparison of stem-only and complete-MCQ solving.

Uses the unchanged bounded compatibility recorder. No author, reviewer, repair,
production mutation, or automatic factual correctness assessment is performed.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys
import time

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_solution_compatibility_eval as shared  # noqa: E402
from evals.question_complete_solver import (  # noqa: E402
    complete_solution_observation,
    solver_prompt,
    validate_complete_solution,
)
from question_quality import _extract_json_object  # noqa: E402
from question_verification import (  # noqa: E402
    _has_reviewable_choices,
    _solver_rejection_reason,
    _validated_solutions,
)

EXPERIMENT = "complete-mcq-first-solver-v1"
ROLES = ("stem_only", "complete_mcq")


def source_hashes():
    result = shared.source_hashes()
    for name in (
        "evals/checkpoint_complete_solver_eval.py",
        "evals/question_complete_solver.py",
    ):
        result[name] = hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
    return result


def make_plan(packet):
    cases = packet.get("cases")
    if (
        not isinstance(cases, list)
        or len(cases) != 8
        or any(
            not isinstance(c, dict)
            or not isinstance(c.get("case_id"), str)
            or not c["case_id"]
            for c in cases
        )
        or len({c["case_id"] for c in cases}) != 8
    ):
        raise ValueError("Exactly eight distinct fixed cases are required.")
    jobs = []
    for i, case in enumerate(cases):
        question, request = case["question"], case["request"]
        if (
            not isinstance(question, dict)
            or not _has_reviewable_choices(question)
            or not isinstance(question.get("prompt"), str)
            or not question["prompt"]
            or not isinstance(question.get("topic"), str)
            or not isinstance(request, dict)
            or not isinstance(request.get("goal"), dict)
            or not isinstance(request.get("sourceDocuments"), list)
            or request.get("existingQuestionCoverage")
        ):
            raise ValueError(
                "Fixed questions need exact reviewable choices and context without answer-bearing history."
            )
        requests = {
            role: shared.converse_request(
                *solver_prompt(copy.deepcopy(case), complete=role == "complete_mcq")
            )
            for role in ROLES
        }
        if any(
            shared.text_bytes(r) > shared.MAX_INPUT_BYTES for r in requests.values()
        ):
            raise ValueError("A frozen request exceeds the per-call input allowance.")
        jobs.append(
            {
                "case_id": case["case_id"],
                "fixture_case_index": i,
                "role_order": list(ROLES if i % 2 == 0 else reversed(ROLES)),
                "requests": requests,
                "question_canonical_sha256": shared.digest(shared.canonical(question)),
            }
        )
    total = sum(shared.text_bytes(r) for j in jobs for r in j["requests"].values())
    if total > shared.MAX_TOTAL_INPUT_BYTES:
        raise ValueError("The frozen total exceeds the input allowance.")
    return {
        "experiment": EXPERIMENT,
        "fixture": copy.deepcopy(packet),
        "fixture_canonical_sha256": shared.digest(shared.canonical(packet)),
        "source_revision": shared.source_revision(),
        "source_sha256": source_hashes(),
        "dependencies": shared.dependencies(),
        "model": shared.MODEL,
        "settings": copy.deepcopy(shared.SETTINGS),
        "jobs": jobs,
        "maximum_calls": shared.MAX_CALLS,
        "maximum_calls_per_case": shared.MAX_CALLS_PER_CASE,
        "maximum_input_utf8_bytes_per_call": shared.MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": shared.MAX_TOTAL_INPUT_BYTES,
        "planned_input_utf8_bytes": total,
        "sdk_total_max_attempts": 1,
        "comparison": "Current stem-only first solver versus complete-MCQ first solver. The candidate changes input visibility, instructions and output contract; this is not an isolated context-only ablation.",
        "scope": "Fixed questions, fresh solutions only. Baseline eligibility is pre-review only. No author, final reviewer, retry, repair, serving change or automatic correctness score. Uncertainty is not defect-detection credit.",
        "input_budget_note": "UTF-8 text and output token allowances are not a dollar-cost cap. SDK read timeout is not a hard total deadline; timeout usage can remain unknown.",
    }


def load_frozen_plan(path, approved_hash):
    plan = json.loads(path.read_text(encoding="utf-8"))
    if shared.digest(shared.canonical(plan)) != approved_hash:
        raise ValueError("The exact canonical frozen-plan hash is required.")
    if plan != make_plan(plan["fixture"]):
        raise ValueError(
            "Frozen requests, source, dependencies, settings or limits changed."
        )
    return plan


def observe(raw, role, case):
    if role == "stem_only":
        solutions = _validated_solutions(raw, 1)
        if solutions is None:
            raise shared.TrialFailure("Malformed current-solver response.")
        reason = _solver_rejection_reason(solutions[0], case["question"])
        return {
            "validated_solution": solutions[0],
            "pre_review_eligibility": reason is None,
            "pre_review_rejection_reason": reason,
            "scope": "Current solver field gates only; no final reviewer ran and no factual correctness or final acceptance is established.",
        }
    parsed = validate_complete_solution(raw, case["question"]["choices"])
    return complete_solution_observation(parsed, case["question"]["expectedAnswer"])


def run_experiment(
    plan_path, approved_hash, directory, client=None, *, cli_credentials=False
):
    plan = load_frozen_plan(plan_path, approved_hash)
    directory.mkdir(parents=True, exist_ok=False)
    report = {
        "plan": plan,
        "plan_sha256": approved_hash,
        "status": "running",
        "stopped_early": False,
        "calls": [],
        "input_utf8_bytes": 0,
        "results": [
            {
                "case_id": j["case_id"],
                "status": "unattempted",
                "stage_outputs": {},
                "observations": {},
                "correctness_assessment": "unassessed",
            }
            for j in plan["jobs"]
        ],
    }

    def persist():
        shared.write_json(directory / "capture.json", report)

    persist()
    try:
        recorder = shared.RecordingClient(
            client
            if client is not None
            else shared.new_client(shared.SETTINGS, cli_credentials),
            report,
            persist,
        )
        for index, job in enumerate(plan["jobs"]):
            result, case = report["results"][index], plan["fixture"]["cases"][index]
            result["status"] = "running"
            started = time.monotonic()
            try:
                for role in job["role_order"]:
                    raw = recorder.dispatch(index, role)
                    try:
                        parsed = _extract_json_object(raw)
                        observation = observe(raw, role, case)
                    except Exception:
                        result["format_failure_role"] = role
                        raise
                    result["stage_outputs"][role] = parsed
                    result["observations"][role] = observation
                    persist()
                result["status"] = "completed"
            except Exception as error:
                result.update(
                    status="operational_failure", error={"type": type(error).__name__}
                )
                report["stopped_early"] = True
            finally:
                calls = [c for c in report["calls"] if c["case_index"] == index]
                result["usage_known"] = all(c["usage_known"] for c in calls)
                result["known_usage_subtotal"] = {
                    k: sum(c["response"]["usage"][k] for c in calls if c["usage_known"])
                    for k in ("inputTokens", "outputTokens")
                }
                result["provider_calls"] = len(calls)
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
            parser.error("Execution requires --plan and no --fixture.")
        return int(
            run_experiment(
                args.plan,
                args.plan_sha256,
                args.output,
                cli_credentials=args.aws_cli_credentials,
            )["stopped_early"]
        )
    if args.fixture is None or args.plan is not None:
        parser.error("Preparation requires --fixture and no --plan.")
    plan = make_plan(json.loads(args.fixture.read_text(encoding="utf-8")))
    args.output.mkdir(parents=True, exist_ok=False)
    shared.write_json(args.output / "plan.json", plan)
    print(
        json.dumps(
            {
                "plan_sha256": shared.digest(shared.canonical(plan)),
                "maximum_calls": shared.MAX_CALLS,
                "execute": False,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
