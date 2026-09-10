#!/usr/bin/env python3
"""Paired complete-choice solver ordering diagnostic; dry by default.

Only the example's row order and equivalent schema property order vary. The
production provider adapter and validators still own requests and admission.
No author, reviewer, retry, label repair, deployment or accuracy certification.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
from unittest.mock import patch

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from complete_question_solution import (  # noqa: E402
    build_solver_prompt, validate_batch, rejection_reason, CompleteSolutionFormatError,
)
from evals import checkpoint_native_stage_probe as probe  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_generation as generation  # noqa: E402
from service_errors import ProviderError  # noqa: E402

shared, runtime = probe.shared, probe.runtime
_hash, _same, _source_snapshot = probe._hash, probe._same, probe._source_snapshot
ROOT = SERVICE_DIR.parents[1]
FIXTURE = SERVICE_DIR / "evals/fixtures/question_solver_order.json"
PROTOCOL = ROOT / "docs/QUESTION_SOLVER_ORDER_PROTOCOL.md"
CONTROL_PACKET = ROOT / "docs/evidence/solver-order-preparation-20260910/control-packet.json"
CONTROL_REVIEW = CONTROL_PACKET.with_name("control-review.json")
EXPERIMENT = "solver-judgment-reason-order-v1"
CONTRACT = "complete_choice_solver_v1"
MODEL = "us.anthropic.claude-sonnet-4-6"
ARMS = ("judgment_first", "reason_first")
MAX_CALLS, MAX_INPUT_BYTES = 32, 32 * 1024
SETTINGS = copy.deepcopy(probe.SETTINGS)
OLD_EXAMPLE = '"judgment":"supported|refuted|uncertain","reason":"concise decisive reason"'
NEW_EXAMPLE = '"reason":"concise decisive reason","judgment":"supported|refuted|uncertain"'


def ordered_config(arm):
    if arm not in ARMS:
        raise ValueError("Unknown order arm.")
    config = native.native_output_config(CONTRACT)
    if arm == ARMS[0]:
        return config
    wrapper = config["textFormat"]["structure"]["jsonSchema"]
    original = json.loads(wrapper["schema"])
    schema = copy.deepcopy(original)
    row = schema["properties"]["solutions"]["items"]["properties"]["choices"]["items"]
    row["properties"] = {key: row["properties"][key] for key in ("choice", "reason", "judgment")}
    # Preserve every other key's existing serialized order and the required list.
    # Sorting here would silently erase the experimental intervention.
    wrapper["schema"] = json.dumps(schema, separators=(",", ":"))
    if schema != original:
        raise ValueError("Order intervention changed schema semantics.")
    return config


def _invoke(batch, arm, client):
    subject = batch["subject"]
    system, user = build_solver_prompt(subject["items"], subject)
    if probe._subject({"messages": [{"content": [{"text": user}]}]}, "solver") != subject:
        raise ValueError("Current subject builder changed the frozen subject.")
    if system.count(OLD_EXAMPLE) != 1:
        raise ValueError("Current solver example changed.")
    if arm == ARMS[1]:
        system = system.replace(OLD_EXAMPLE, NEW_EXAMPLE)
    config = ordered_config(arm)
    with patch.dict(os.environ, SETTINGS), patch.object(
        generation, "native_output_config", return_value=config,
    ):
        return generation._generate_with_bedrock(
            subject, client, MODEL, user, system, contract=CONTRACT,
        )


def _request(batch, arm):
    requests = []

    class Client:
        def converse(self, **request):
            requests.append(copy.deepcopy(request))
            raise probe._Captured()

    try:
        _invoke(batch, arm, Client())
    except probe._Captured:
        pass
    if len(requests) != 1 or len(shared.canonical(requests[0]).encode()) > MAX_INPUT_BYTES:
        raise ValueError("Exactly one bounded solver request required.")
    return requests[0]


def make_plan(*, source_revision=None):
    packet = json.loads(FIXTURE.read_text())
    batches = packet["batches"]
    if (packet["experiment"] != EXPERIMENT or len(batches) != 8
            or len({b["batch_id"] for b in batches}) != 8):
        raise ValueError("Eight distinct frozen batches required.")
    blind = json.loads(CONTROL_PACKET.read_text())
    review = json.loads(CONTROL_REVIEW.read_text())
    if (blind["batches"] != [{"batch_id": b["batch_id"], "subject": b["subject"]} for b in batches]
            or review["packet_sha256"] != hashlib.sha256(CONTROL_PACKET.read_bytes()).hexdigest()
            or [b["batch_id"] for b in review["batches"]] != [b["batch_id"] for b in batches]):
        raise ValueError("Independent control review does not bind these exact subjects.")
    for batch, reviewed in zip(batches, review["batches"], strict=True):
        for item, assessment, independent in zip(batch["subject"]["items"], batch["assessment"]["items"],
                                                 reviewed["items"], strict=True):
            if (independent["index"] != item["index"] or independent["prompt"] != item["prompt"]
                    or [r["text"] for r in independent["choices"]] != item["choices"]):
                raise ValueError("Independent item identity changed.")
            for expected, observed in zip(assessment["expected_choices"], independent["choices"], strict=True):
                if expected["judgment"] is not None and expected["judgment"] != observed["status"]:
                    raise ValueError("Resolve or retain the independent assessment disagreement before freezing.")
    for batch in batches:
        provenance = batch["provenance"]
        if batch["kind"] == "historical":
            path = (ROOT / provenance["path"]).resolve()
            if (not path.is_relative_to(ROOT.resolve())
                    or hashlib.sha256(path.read_bytes()).hexdigest() != provenance["byte_sha256"]):
                raise ValueError("Historical origin changed.")
            origin = json.loads(path.read_text())
            prior = origin["calls"][provenance["call_index"]]
            if probe._subject(prior["request"], "solver") != batch["subject"]:
                raise ValueError("Historical subject or choice order changed.")
        items = batch["subject"]["items"]
        assessments = batch["assessment"]["items"]
        if [a["index"] for a in assessments] != [i["index"] for i in items]:
            raise ValueError("Assessment index coverage changed.")
        for item, assessment in zip(items, assessments, strict=True):
            if (assessment["key"] not in item["choices"]
                    or [r["choice"] for r in assessment["expected_choices"]] != item["choices"]):
                raise ValueError("Assessment choice coverage changed.")
    jobs = []
    for repeat in range(2):
        for index, batch in enumerate(batches):
            arms = ARMS if (index + repeat) % 2 == 0 else tuple(reversed(ARMS))
            for arm in arms:
                request = _request(batch, arm)
                jobs.append({"position": len(jobs), "batch_id": batch["batch_id"],
                             "repeat": repeat, "arm": arm, "batch": batch,
                             # The shared fixed-job observer stores this provenance field.
                             "archived_call_index": batch["provenance"].get("call_index"),
                             "request": request, "request_sha256": _hash(request)})
    if len(jobs) != MAX_CALLS:
        raise ValueError("Unexpected call count.")
    return {"experiment": EXPERIMENT, **_source_snapshot(source_revision),
            "documents_sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in (FIXTURE, PROTOCOL, CONTROL_PACKET, CONTROL_REVIEW)},
            "jobs": jobs, "settings": SETTINGS, "maximum_calls": MAX_CALLS,
            "maximum_input_utf8_bytes_per_call": MAX_INPUT_BYTES,
            "maximum_input_utf8_bytes_total": MAX_CALLS * MAX_INPUT_BYTES,
            "planned_input_utf8_bytes": sum(len(shared.canonical(j["request"]).encode()) for j in jobs),
            "maximum_output_tokens_per_call": 6000, "sdk_total_max_attempts": 1,
            "worker_deadline_seconds": probe.WORKER_SECONDS,
            "scope": "Selected paired solver diagnostic. Repetitions are not independent subjects. No full review, delivery, authoring or production promotion. Assess rationale correctness separately from declared eligibility."}


def load_frozen_plan(path, expected_hash):
    plan = json.loads(path.read_text())
    if _hash(plan) != expected_hash or not _same(plan, make_plan(source_revision=plan.get("source_revision"))):
        raise ValueError("Plan, source, subjects, assessments or settings changed.")
    return plan


def content_observation(job, state):
    result = {"stage_validation": "unavailable", "items": [],
              "semantic_assessment": "unassessed", "full_production_acceptance": "not_run"}
    if not runtime._usable_observation(state):
        return result

    class Client:
        def converse(self, **request):
            if not _same(request, job["request"]):
                raise ValueError("Offline provider request binding changed.")
            return runtime._provider_response(state)

    try:
        raw = _invoke(job["batch"], job["arm"], Client())
        parsed = json.loads(raw)
        # Inspect provider field order before validators reorder arrays.
        result["emitted_row_orders"] = [list(row) for item in parsed["solutions"] for row in item["choices"]]
        records = validate_batch(raw, job["batch"]["subject"]["items"])
    except (ProviderError, CompleteSolutionFormatError):
        result["stage_validation"] = "rejected"
        return result
    result["stage_validation"] = "passed"
    for record, item, assessment in zip(records, job["batch"]["subject"]["items"],
                                        job["batch"]["assessment"]["items"], strict=True):
        reason = rejection_reason(record, {**item, "expectedAnswer": assessment["key"]})
        expected = {row["choice"]: row["judgment"] for row in assessment["expected_choices"]}
        comparable = all(value in ("supported", "refuted", "uncertain") for value in expected.values())
        result["items"].append({"index": item["index"], "record": record,
                                "rejection_reason": reason,
                                "matches_frozen_judgments": (all(row["judgment"] == expected[row["choice"]]
                                                              for row in record["choices"]) if comparable else None),
                                "rationale_correctness": "unassessed",
                                "judgment_reason_consistency": "unassessed"})
    return result


def run_trial(path, expected_hash, directory, *, cli_credentials=False, observer=None):
    plan = load_frozen_plan(path, expected_hash)
    if directory.exists():
        raise FileExistsError(directory)
    claim = path.with_name(path.name + ".execution-claim.json")
    with claim.open("x", encoding="utf-8") as handle:
        handle.write(shared.canonical({"plan_sha256": expected_hash, "directory": str(directory.resolve())}))
        handle.flush()
        os.fsync(handle.fileno())
    descriptor = os.open(claim.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    def observed(request, **kwargs):
        state = (observer or probe.caller.observe_request)(request, **kwargs)
        if state.get("status") == "completed" and not state.get("usage_known"):
            state = {**state, "status": "operational_failure", "error_type": "UnknownUsage"}
        return state

    return probe.run_frozen_jobs(plan, directory, cli_credentials=cli_credentials,
                                 observer=observed, content_observer=content_observation)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--plan-sha256")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    if args.execute:
        if args.plan is None or args.plan_sha256 is None:
            parser.error("Execution requires --plan and --plan-sha256.")
        report = run_trial(args.plan, args.plan_sha256, args.directory,
                           cli_credentials=args.aws_cli_credentials)
        return 0 if report["status"] == "completed" else 1
    if args.plan is not None or args.plan_sha256 is not None or args.aws_cli_credentials:
        parser.error("Dry preparation accepts only a new --directory.")
    plan = make_plan()
    args.directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    shared.write_json(args.directory / "plan.json", plan)
    print(json.dumps({"plan_sha256": _hash(plan), "maximum_calls": MAX_CALLS, "execute": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
