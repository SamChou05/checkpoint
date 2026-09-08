#!/usr/bin/env python3
"""Check synchronous response provenance and existing structural/domain heuristics."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any

import lambda_function
from evals import checkpoint_question_eval
from verification_policy import (
    VERIFICATION_POLICY_REVISION,
    VERIFICATION_VERSION,
    meets_verification_policy,
)


SERVICE_DIR = Path(__file__).resolve().parent
DEFAULT_FIXTURES = (
    SERVICE_DIR / "evals" / "fixtures" / "question_generation_cases.jsonl"
)
DEFAULT_XCCONFIG = SERVICE_DIR.parents[1] / "Checkpoint" / "Config" / "Secrets.xcconfig"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Check /v1/questions response policy and structural/domain heuristics. "
            "This does not test asynchronous banks or establish factual correctness."
        )
    )
    parser.add_argument(
        "--case-id",
        default="backyard_beekeeping_raw_goal",
        help="Fixture case to send.",
    )
    parser.add_argument("--fixtures", type=Path, default=DEFAULT_FIXTURES)
    parser.add_argument("--xcconfig", type=Path, default=DEFAULT_XCCONFIG)
    parser.add_argument("--timeout", type=float, default=50.0)
    parser.add_argument(
        "--target-count",
        type=int,
        choices=range(1, 21),
        default=5,
        help="Number of questions to request; defaults to five, with at least min(target, 5) required.",
    )
    parser.add_argument(
        "--minimum-policy-revision",
        type=int,
        choices=range(1, VERIFICATION_POLICY_REVISION + 1),
        default=VERIFICATION_POLICY_REVISION,
        help=(
            "Minimum returned policy revision (default: current). "
            "An explicit older revision is only a legacy diagnostic; typed wire/policy stamps remain required."
        ),
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print question prompts and item-level eval failures; never prints endpoint credentials.",
    )
    args = parser.parse_args()

    endpoint, token = backend_configuration(args.xcconfig)
    fixture = load_fixture(args.fixtures, args.case_id)
    payload = fixture["payload"]
    payload["targetCount"] = args.target_count

    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "X-Checkpoint-Install-ID": str(uuid.uuid4()),
        },
    )

    started_at = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=args.timeout) as response:
            status_code = response.status
            response_payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        print(f"Backend smoke failed with HTTP {error.code}.", file=sys.stderr)
        return 1
    except (OSError, ValueError) as error:
        print(
            f"Backend smoke failed before validation: {type(error).__name__}.",
            file=sys.stderr,
        )
        return 1

    elapsed = time.monotonic() - started_at
    raw_questions = (
        response_payload.get("questions")
        if isinstance(response_payload, dict)
        else None
    )
    if status_code != 200 or not isinstance(raw_questions, list):
        print("Backend smoke returned an invalid response envelope.", file=sys.stderr)
        return 1

    # Check the actual response before the author-oriented sanitizer drops the
    # stamps. Every item is checked, including any beyond the minimum count.
    for index, question in enumerate(raw_questions):
        if not isinstance(question, dict) or not meets_verification_policy(
            question, args.minimum_policy_revision
        ):
            print(
                f"Backend smoke failed response provenance at item {index + 1}: "
                f"expected typed wire {VERIFICATION_VERSION} and policy >= "
                f"{args.minimum_policy_revision}.",
                file=sys.stderr,
            )
            return 1

    normalized_request = lambda_function._normalize_request(payload)  # noqa: SLF001
    accepted_questions = lambda_function._sanitize_questions(  # noqa: SLF001
        raw_questions,
        normalized_request,
    )
    required_count = min(args.target_count, 5)
    if len(accepted_questions) < required_count or len(accepted_questions) != len(
        raw_questions
    ):
        print(
            "Backend smoke failed structural validation: "
            f"{len(accepted_questions)}/{len(raw_questions)} returned items admitted; "
            f"at least {required_count} required.",
            file=sys.stderr,
        )
        return 1

    evaluation_fixture = {
        **fixture,
        "payload": payload,
        "expect": {
            **fixture.get("expect", {}),
            "min_usable_questions": required_count,
        },
    }
    evaluation = checkpoint_question_eval.score_case_response(
        evaluation_fixture,
        {
            "case_id": args.case_id,
            "run": 1,
            "questions": accepted_questions,
        },
    )
    if not evaluation["passed"] or evaluation["usable_count"] != len(raw_questions):
        print(
            "Backend smoke failed fixture heuristics: "
            f"{evaluation['usable_count']}/{len(raw_questions)} returned items usable.",
            file=sys.stderr,
        )
        for failure in evaluation["failures"][:3]:
            print(f"- {failure}", file=sys.stderr)
        if args.verbose:
            for question in evaluation["questions"]:
                if not question["failures"]:
                    continue
                print(
                    f"Q{question['index'] + 1}: {question['prompt']}", file=sys.stderr
                )
                for failure in question["failures"]:
                    print(f"  - {failure}", file=sys.stderr)
        return 1

    print(
        "Synchronous backend smoke passed: "
        f"{evaluation['usable_count']}/{len(raw_questions)} returned questions passed "
        f"policy >= {args.minimum_policy_revision}, wire {VERIFICATION_VERSION}, "
        f"and fixture heuristics for {args.case_id} in {elapsed:.1f}s "
        f"(minimum count {required_count}). "
        "Asynchronous bank flow and factual correctness are not established."
    )
    return 0


def backend_configuration(xcconfig: Path) -> tuple[str, str]:
    endpoint = os.getenv("CHECKPOINT_SMOKE_ENDPOINT", "").strip()
    token = os.getenv("CHECKPOINT_SMOKE_TOKEN", "").strip()
    if bool(endpoint) != bool(token):
        raise SystemExit(
            "Both CHECKPOINT_SMOKE_ENDPOINT and CHECKPOINT_SMOKE_TOKEN are required."
        )
    if not endpoint:
        if not xcconfig.exists():
            raise SystemExit(f"Missing backend configuration: {xcconfig}")

        text = xcconfig.read_text(encoding="utf-8")
        endpoint = xcconfig_value(text, "CHECKPOINT_AI_BACKEND_ENDPOINT").replace(
            ":/$()/",
            "://",
            1,
        )
        token = xcconfig_value(text, "CHECKPOINT_AI_BACKEND_TOKEN")

    if not endpoint.startswith("https://") or len(token) < 32:
        raise SystemExit("Backend endpoint or token is not production-shaped.")
    return endpoint, token


def xcconfig_value(text: str, key: str) -> str:
    match = re.search(rf"^{re.escape(key)}\s*=\s*(.+)$", text, flags=re.MULTILINE)
    if not match:
        raise SystemExit(f"Missing {key} in backend configuration.")
    return match.group(1).strip()


def load_fixture(path: Path, case_id: str) -> dict[str, Any]:
    with path.open(encoding="utf-8") as fixture_file:
        for line in fixture_file:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            fixture = json.loads(stripped)
            if fixture.get("case_id") == case_id:
                return fixture
    raise SystemExit(f"Unknown fixture case: {case_id}")


if __name__ == "__main__":
    raise SystemExit(main())
