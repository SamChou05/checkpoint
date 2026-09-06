#!/usr/bin/env python3
"""Compare unchanged review with/without supplied evidence; never deploys.

Evidence packets are manually curated feasibility fixtures, not an automated
retrieval system. Questions, keys, model settings, and review prompts stay fixed.
The evidence documents contain reference facts, not expected review verdicts.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
import random
import sys
import time

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals.checkpoint_learning_eval import evaluate_review  # noqa: E402
from evals.checkpoint_prompt_ablation import use_aws_cli_credentials  # noqa: E402
from question_verification import (  # noqa: E402
    REVIEW_SYSTEM_PROMPT,
    SOLUTION_SYSTEM_PROMPT,
)
import question_verification  # noqa: E402


def make_plan(packet, repeats, seed):
    jobs = []
    for repeat in range(repeats):
        for case in packet["cases"]:
            for arm in ("unaided", "evidence"):
                supplied = copy.deepcopy(case)
                if arm == "evidence":
                    supplied["sourceDocuments"] = supplied.get(
                        "sourceDocuments", []
                    ) + (copy.deepcopy(packet["evidence_by_case_id"][case["case_id"]]))
                jobs.append({"repeat": repeat + 1, "arm": arm, "case": supplied})
    random.Random(seed).shuffle(jobs)
    return jobs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--fixtures",
        type=Path,
        default=SERVICE_DIR / "evals/fixtures/question_evidence_feasibility.json",
    )
    parser.add_argument("--repeats", type=int, choices=(1, 2, 3), default=1)
    parser.add_argument("--seed", type=int, default=9062026)
    parser.add_argument("--model", default="us.anthropic.claude-opus-4-6-v1")
    parser.add_argument("--effort", choices=("high", "max"), default="high")
    parser.add_argument("--arm", action="append", choices=("unaided", "evidence"))
    parser.add_argument(
        "--prompt-snapshot",
        type=Path,
        help="Reuse exact solution_prompt and review_prompt from an earlier capture.",
    )
    parser.add_argument("--aws-cli-credentials", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    packet = json.loads(args.fixtures.read_text())
    jobs = make_plan(packet, args.repeats, args.seed)
    if args.arm:
        jobs = [job for job in jobs if job["arm"] in args.arm]
    if args.dry_run:
        print(json.dumps({"reviews": len(jobs), "maximum_calls": 2 * len(jobs)}))
        return 0
    if args.output.exists():
        parser.error("Use a new output file; previous attempts must remain intact.")
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    solution_prompt, review_prompt = SOLUTION_SYSTEM_PROMPT, REVIEW_SYSTEM_PROMPT
    if args.prompt_snapshot:
        snapshot = json.loads(args.prompt_snapshot.read_text())
        solution_prompt, review_prompt = (
            snapshot["solution_prompt"],
            snapshot["review_prompt"],
        )
        if not all(
            isinstance(prompt, str) and prompt.strip()
            for prompt in (solution_prompt, review_prompt)
        ):
            parser.error("Prompt snapshot must contain nonempty prompt strings.")
        question_verification.SOLUTION_SYSTEM_PROMPT = solution_prompt
        question_verification.REVIEW_SYSTEM_PROMPT = review_prompt
    os.environ.update(
        AWS_REGION="us-east-1",
        BEDROCK_MODEL_ID=args.model,
        BEDROCK_VERIFICATION_MODEL_ID=args.model,
        BEDROCK_CLAUDE_THINKING="adaptive",
        BEDROCK_CLAUDE_EFFORT=args.effort,
        BEDROCK_THINKING_MAX_TOKENS="16000",
        BEDROCK_MAX_TOKENS="16000",
        BEDROCK_READ_TIMEOUT_SECONDS="100",
    )
    report = {
        "model": args.model,
        "seed": args.seed,
        "repeats": args.repeats,
        "maximum_calls": len(jobs) * 2,
        "fixture": packet,
        "solution_prompt": solution_prompt,
        "review_prompt": review_prompt,
        "settings": {
            "thinking": "adaptive",
            "effort": args.effort,
            "max_tokens": 16000,
        },
        "results": [],
    }
    for job in jobs:
        started = time.monotonic()
        try:
            result = evaluate_review(job["case"])
        except Exception as error:
            result = {
                "case_id": job["case"]["case_id"],
                "passed": False,
                "error_type": type(error).__name__,
            }
        result.update(
            arm=job["arm"],
            repeat=job["repeat"],
            elapsed_seconds=round(time.monotonic() - started, 3),
        )
        report["results"].append(result)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(
            json.dumps(
                {
                    key: result.get(key)
                    for key in (
                        "case_id",
                        "arm",
                        "repeat",
                        "passed",
                        "accepted",
                        "error_type",
                    )
                }
            ),
            flush=True,
        )
        if result.get("error_type"):
            # Stop this run on provider failure; no hidden retries or substitution.
            break
    return 0 if len(report["results"]) == len(jobs) else 1


if __name__ == "__main__":
    raise SystemExit(main())
