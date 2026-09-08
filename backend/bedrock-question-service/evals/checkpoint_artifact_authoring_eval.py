#!/usr/bin/env python3
"""Dry-by-default, two-call artifact authorship capture; no native observations.

Generated specs remain unassessed. A separately frozen observation plan must
bind to these exact outputs before any artifact execution or key construction.
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
from question_quality import _extract_json_object  # noqa: E402

EXPERIMENT = "artifact-first-authoring-v1"
FAMILIES = ("python", "html")
MAX_CALLS, MAX_CALLS_PER_CASE = 2, 1
MAX_INPUT_BYTES, MAX_TOTAL_INPUT_BYTES = 32000, 64000
ADAPTER_SOURCES = (
    "evals/python_artifact_question.py",
    "evals/html_artifact_question.py",
    "evals/observe_html_artifact.js",
)


def source_hashes():
    result = shared.source_hashes()
    for name in ("evals/checkpoint_artifact_authoring_eval.py", *ADAPTER_SOURCES):
        # Missing adapters prevent freezing; there is no incomplete-source plan.
        result[name] = hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
    return result


def make_plan(packet):
    cases = packet.get("cases") if isinstance(packet, dict) else None
    if (
        not isinstance(packet, dict)
        or packet.get("experiment") != EXPERIMENT
        or not isinstance(cases, list)
        or len(cases) != 2
        or any(
            not isinstance(case, dict)
            or not isinstance(case.get("case_id"), str)
            or not case["case_id"].strip()
            or case.get("family") != FAMILIES[index]
            or not isinstance(case.get("system_prompt"), str)
            or not case["system_prompt"].strip()
            or not isinstance(case.get("user_data"), dict)
            for index, case in enumerate(cases)
        )
        or len({case["case_id"] for case in cases}) != 2
    ):
        raise ValueError(
            "Exactly two distinct author cases, Python then HTML, are required."
        )
    jobs = []
    for index, case in enumerate(cases):
        user = (
            "<artifact_authoring_json>\n"
            + json.dumps(case["user_data"], ensure_ascii=False, allow_nan=False)
            + "\n</artifact_authoring_json>"
        )
        request = shared.converse_request(case["system_prompt"], user)
        if shared.text_bytes(request) > MAX_INPUT_BYTES:
            raise ValueError(
                "A planned author request exceeds the input text allowance."
            )
        jobs.append(
            {
                "case_id": case["case_id"],
                "family": case["family"],
                "fixture_case_index": index,
                "role_order": ["author"],
                "requests": {"author": request},
                "user_data_canonical_sha256": shared.digest(
                    shared.canonical(case["user_data"])
                ),
            }
        )
    total = sum(shared.text_bytes(job["requests"]["author"]) for job in jobs)
    if total > MAX_TOTAL_INPUT_BYTES:
        raise ValueError("The planned total exceeds the input text allowance.")
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
        "maximum_calls": MAX_CALLS,
        "maximum_calls_per_case": MAX_CALLS_PER_CASE,
        "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": MAX_TOTAL_INPUT_BYTES,
        "planned_input_utf8_bytes": total,
        "sdk_total_max_attempts": 1,
        "scope": "Two independent author calls only. No artifact preparation/execution, key derivation, solver, review, feedback rewrite, repair, retry, top-up or production change. Candidate schemas and content remain unassessed.",
        "input_budget_note": "UTF-8 bytes are not tokens or a certified cost cap. Read timeout is not a hard total deadline; timeout usage remains unknown.",
    }


def load_frozen_plan(path, approved_hash):
    plan = json.loads(path.read_text(encoding="utf-8"))
    if shared.digest(shared.canonical(plan)) != approved_hash:
        raise ValueError("The exact canonical frozen-plan hash is required.")
    if plan != make_plan(plan["fixture"]):
        raise ValueError(
            "Frozen requests, sources, dependencies, settings or limits changed."
        )
    return plan


class AuthorRecordingClient(shared.RecordingClient):
    """Add tighter author-only bounds without replacing durable SDK recording."""

    def __init__(self, client, report, persist):
        super().__init__(client, report, persist)
        self.expected_requests = [
            copy.deepcopy(job["requests"]["author"]) for job in report["plan"]["jobs"]
        ]

    def dispatch(self, case_index, role):
        count = len(self.report["calls"])
        if (
            self.failed
            or type(case_index) is not int
            or count >= MAX_CALLS
            or case_index != count
            or role != "author"
        ):
            raise shared.TrialFailure("Author call order or two-call limit rejected.")
        request = self.report["plan"]["jobs"][case_index]["requests"][role]
        size = shared.text_bytes(request)
        if (
            request != self.expected_requests[case_index]
            or size > MAX_INPUT_BYTES
            or self.report["input_utf8_bytes"] + size > MAX_TOTAL_INPUT_BYTES
            or any(call["case_index"] == case_index for call in self.report["calls"])
        ):
            raise shared.TrialFailure(
                "Author request changed or input/family budget exceeded."
            )
        return super().dispatch(case_index, role)


def validate_author(parsed):
    if (
        set(parsed) != {"candidates"}
        or not isinstance(parsed["candidates"], list)
        or len(parsed["candidates"]) != 2
        or any(not isinstance(candidate, dict) for candidate in parsed["candidates"])
    ):
        raise shared.TrialFailure("Author must return exactly two candidate objects.")
    return parsed


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
                "case_id": job["case_id"],
                "family": job["family"],
                "status": "unattempted",
                "stage_outputs": {},
                "candidate_assessment": "unassessed",
            }
            for job in plan["jobs"]
        ],
    }

    def persist():
        shared.write_json(directory / "capture.json", report)

    persist()
    try:
        recorder = AuthorRecordingClient(
            client
            if client is not None
            else shared.new_client(shared.SETTINGS, cli_credentials),
            report,
            persist,
        )
        for index, result in enumerate(report["results"]):
            result["status"] = "running"
            started = time.monotonic()
            try:
                raw = recorder.dispatch(index, "author")
                try:
                    result["stage_outputs"]["author"] = _extract_json_object(raw)
                    validate_author(result["stage_outputs"]["author"])
                except Exception:
                    result["format_failure_role"] = "author"
                    raise
                result["status"] = "completed"
            except Exception as error:
                result.update(
                    status="operational_failure", error={"type": type(error).__name__}
                )
                report["stopped_early"] = True
            finally:
                calls = [
                    call for call in report["calls"] if call["case_index"] == index
                ]
                result["provider_calls"] = len(calls)
                result["usage_known"] = bool(calls) and all(
                    call["usage_known"] for call in calls
                )
                result["known_usage_subtotal"] = {
                    key: sum(
                        call["response"]["usage"][key]
                        for call in calls
                        if call["usage_known"]
                    )
                    for key in ("inputTokens", "outputTokens")
                }
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
        if args.plan is None or args.fixture is not None or not args.plan_sha256:
            parser.error(
                "Execution requires --plan and --plan-sha256, without --fixture."
            )
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
                "maximum_calls": MAX_CALLS,
                "execute": False,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
