#!/usr/bin/env python3
"""Replay a native runtime capture before reusing the offline delivery checks.

The resulting report is an input to QuestionDeliveryCaptureTests.swift. No
provider, production storage, client admission or factual assessment runs here.
"""
from __future__ import annotations

import argparse
import copy
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import socket
import sys
from unittest.mock import patch

SERVICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
from evals import checkpoint_delivery_check as delivery  # noqa: E402
from evals import checkpoint_runtime_qualification as runtime  # noqa: E402
from question_quality import _strict_json_object  # noqa: E402

EXPERIMENT = "native-fresh-workflow-v1"
COMPLETE_TEACHING_EXPERIMENT = "native-complete-teaching-workflow-v1"
EXPERIMENTS = {EXPERIMENT, COMPLETE_TEACHING_EXPERIMENT}
REQUEST_FIELDS = {"goal", "sourceDocuments", "targetCount", "minimumDifficulty", "feedbackContract"}
GOAL_FIELDS = {"title", "category", "currentLevel", "focusAreas"}
SOURCE_FIELDS = {"name", "text", "truncated"}
# Exact GoalCategory raw values; reject Swift's fallback to Custom for unknown input.
GOAL_CATEGORIES = {"Coding Interview", "Exam Prep", "Language Learning", "Fitness", "Writing", "Custom"}


def delivery_source_hashes():
    paths = sorted(set(delivery.SOURCE_FILES) | {
        str(Path(__file__).resolve().relative_to(delivery.ROOT)),
    })
    return {name: hashlib.sha256((delivery.ROOT / name).read_bytes()).hexdigest() for name in paths}


def _delivery_view(capture):
    """Bind all three operation occurrences and only Swift-supported context."""
    if type(capture) is not dict or capture.get("status") not in {"completed", "operational_failure"}:
        raise ValueError("A terminal native workflow capture is required.")
    plan = capture.get("plan")
    if type(plan) is not dict or plan.get("experiment") not in EXPERIMENTS:
        raise ValueError("Only the supported native fresh workflows are supported.")
    experiment = plan["experiment"]
    fixture = plan.get("fixture")
    cases = fixture.get("cases") if type(fixture) is dict else None
    planned, observed = plan.get("operations"), capture.get("operations")
    if type(fixture) is not dict or fixture.get("experiment") != experiment or any(
        type(rows) is not list or len(rows) != 3 for rows in (cases, planned, observed)
    ):
        raise ValueError("Exactly three planned and observed fresh operations are required.")
    ids = []
    for case, job, operation in zip(cases, planned, observed, strict=True):
        if not all(type(value) is dict for value in (case, job, operation)):
            raise ValueError("Invalid native operation record.")
        case_id = case.get("case_id")
        if (type(case_id) is not str or not case_id or case_id in ids
                or job.get("case_id") != case_id or operation.get("case_id") != case_id
                or job.get("kind") != "fresh" or operation.get("kind") != "fresh"):
            raise ValueError("Native operation identity changed.")
        ids.append(case_id)
        payload, request = case.get("payload"), job.get("request")
        if (type(payload) is not dict or set(payload) - REQUEST_FIELDS
                or type(request) is not dict):
            raise ValueError("The Swift delivery helper does not support this request context.")
        expected_contract = "authored_complete" if experiment == COMPLETE_TEACHING_EXPERIMENT else None
        if any(value.get("feedbackContract") != expected_contract for value in (payload, request)):
            raise ValueError("The original and normalized feedback contract must match the native workflow.")
        goal = payload.get("goal")
        if type(goal) is not dict or set(goal) - GOAL_FIELDS or type(goal.get("title")) is not str:
            raise ValueError("The Swift delivery helper does not support this goal context.")
        if ("category" in goal and (type(goal["category"]) is not str or goal["category"] not in GOAL_CATEGORIES)
                or any(key in goal and type(goal[key]) is not str for key in ("currentLevel", "focusAreas"))):
            raise ValueError("The Swift delivery helper would change or reject this goal context.")
        sources = payload.get("sourceDocuments", [])
        if type(sources) is not list or any(
            type(source) is not dict or set(source) - SOURCE_FIELDS
            or any(type(source.get(key)) is not str for key in ("name", "text"))
            or "truncated" in source and source["truncated"] is not None and type(source["truncated"]) is not bool
            for source in sources
        ):
            raise ValueError("The Swift delivery helper does not support these source fields.")
        for key, expected in (("targetCount", 5), ("minimumDifficulty", 3)):
            if any(type(value.get(key)) is not int or value[key] != expected for value in (payload, request)):
                raise ValueError("Native delivery must retain target five and difficulty three.")
        if (operation.get("status") not in {"completed", "coverage_failure", "operational_failure", "unattempted"}
                or type(operation.get("questions")) is not list
                or operation["status"] == "unattempted" and operation["questions"]):
            raise ValueError("Invalid operation availability or returned content.")
    # The archived helper reads raw requests from origin.cases. This is only a
    # delivery view; the captured plan and its exact replay remain unchanged.
    view = copy.deepcopy(capture)
    view["plan"]["origin"] = {"cases": copy.deepcopy(cases)}
    return view


def check_capture(capture):
    view = _delivery_view(capture)
    plan = capture["plan"]
    if plan.get("delivery_source_sha256") != delivery_source_hashes():
        raise ValueError("Delivery sources differ from the frozen native plan.")
    before = copy.deepcopy(capture)
    with ExitStack() as stack:
        for target, method in (
            (socket.socket, "connect"), (socket.socket, "connect_ex"),
            (boto3, "client"), (boto3.session.Session, "client"),
            (runtime.shared, "new_client"), (runtime.caller, "observe_request"),
        ):
            stack.enter_context(patch.object(
                target, method, side_effect=AssertionError("Native delivery forbids network and provider calls"),
            ))
        replay = runtime.replay_capture(capture)
        if replay != before or capture != before:
            raise ValueError("Native delivery requires exact, nonmutating runtime replay.")
        report = delivery.check_capture(view)
    report["native_capture_binding"] = {
        "experiment": plan["experiment"],
        "capture_canonical_sha256": runtime._hash(capture),
        "plan_sha256": capture["plan_sha256"],
        "source_revision": plan["source_revision"],
        "source_sha256": copy.deepcopy(plan["source_sha256"]),
        "delivery_source_sha256": copy.deepcopy(plan["delivery_source_sha256"]),
        "dependencies": copy.deepcopy(plan["dependencies"]),
        "exact_runtime_replay": True,
        "capture_status": capture["status"],
    }
    wrapper_path = str(Path(__file__).resolve().relative_to(delivery.ROOT))
    report["source_sha256"][wrapper_path] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    if report["source_sha256"] != plan["delivery_source_sha256"]:
        raise ValueError("Delivery sources changed during the offline check.")
    report["requested_count"] = 15
    for result, operation in zip(report["operations"], capture["operations"], strict=True):
        result["runtime_status"] = operation["status"]
        result["requested_count"] = 5
        result["result_category"] = operation.get("result_category")
    report["scope"] += (
        " Native source/plan/request replay precedes delivery. Original raw goal/source context "
        "is retained for all three initial-practice operations, including unattempted slots. "
        "No supplied skill map, adaptive history or explicit derived-context override is supported. "
        "Client retention and composed feedback remain pending the separate Swift capture test."
    )
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.output.exists():
        raise FileExistsError("Delivery output already exists.")
    raw = args.capture.read_bytes()
    report = check_capture(_strict_json_object(raw.decode("utf-8")))
    report["capture_sha256"] = hashlib.sha256(raw).hexdigest()
    report["capture_path"] = str(args.capture.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")
    print(json.dumps({"output": str(args.output), "passed": report["passed"],
                      "runtime_returned_count": report["runtime_returned_count"],
                      "bank_claimable_count": report["bank_claimable_count"],
                      "client_retained_count": None}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
