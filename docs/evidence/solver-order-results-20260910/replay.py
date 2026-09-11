#!/usr/bin/env python3
"""Offline replay and blinded assessment packets for the frozen order trial."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import socket
import sys
from unittest.mock import patch


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", type=Path, required=True)
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.checkout / "backend/bedrock-question-service"))
    from evals import checkpoint_solver_order as trial

    capture = json.loads(args.capture.read_text())
    assert capture["status"] in ("completed", "operational_failure")
    plan = capture["plan"]
    assert trial._hash(plan) == capture["plan_sha256"]
    assert trial._same(plan, trial.make_plan(source_revision=plan["source_revision"]))
    assert len(capture["results"]) == len(plan["jobs"]) == 32
    calls = {call["position"]: call for call in capture["calls"]}
    metrics = {arm: {"calls": Counter(), "items": Counter(), "orders": Counter(),
                     "historical": Counter(), "fresh": Counter()} for arm in trial.ARMS}
    rows, errors, subjects = [], [], {}
    usage = Counter()
    with patch.object(socket.socket, "connect", side_effect=AssertionError("Network forbidden during replay")):
        for job, saved in zip(plan["jobs"], capture["results"], strict=True):
            call = calls.get(job["position"])
            assert job["position"] == saved["position"]
            if call:
                assert job["request_sha256"] == call["request_sha256"] == trial._hash(job["request"])
                state = call["observation"]
                assert state["local_worker_reaped"] and state["local_process_group_cleanup_confirmed"]
                replayed = trial.content_observation(job, state)
                assert replayed == {key: value for key, value in saved.items() if key not in ("position", "status")}
                if call["usage_known"]:
                    usage.update(state["response"]["usage"])
            else:
                assert saved["status"] == "unattempted"
                replayed = {"stage_validation": "unattempted", "items": []}
            metric = metrics[job["arm"]]
            metric["calls"].update(["planned", saved["status"]])
            if call:
                metric["calls"].update([replayed["stage_validation"]])
            for order in replayed.get("emitted_row_orders", []):
                metric["orders"].update(["/".join(order)])
            records = {item["index"]: item for item in replayed["items"]}
            if replayed["stage_validation"] == "rejected":
                class Client:
                    def converse(self, **request):
                        assert trial._same(request, job["request"])
                        return trial.runtime._provider_response(state)
                try:
                    raw = trial._invoke(job["batch"], job["arm"], Client())
                except trial.ProviderError as error:
                    phase, detail = "native_or_adapter", str(error)
                else:
                    try:
                        trial.validate_batch(raw, job["batch"]["subject"]["items"])
                    except trial.CompleteSolutionFormatError as error:
                        phase, detail = "batch_format_or_correlation", str(error)
                    else:
                        raise AssertionError("Rejected result unexpectedly validated")
                errors.append({"position": job["position"], "phase": phase, "detail": detail})
            for item, expected in zip(job["batch"]["subject"]["items"], job["batch"]["assessment"]["items"], strict=True):
                subject_key = (job["batch_id"], item["index"])
                subjects[subject_key] = {"subject": {**job["batch"]["subject"], "items": [item]},
                                         "kind": "historical" if job["batch"]["kind"] == "historical" else "fresh", "scorable": expected["scorable"]}
                observed = records.get(item["index"])
                row = {"id": "o" + digest([capture["plan_sha256"], job["position"], item["index"]])[:16],
                       "position": job["position"], "batch_id": job["batch_id"], "index": item["index"],
                       "kind": "historical" if job["batch"]["kind"] == "historical" else "fresh", "repeat": job["repeat"], "arm": job["arm"],
                       "premise_verdict": expected["premise_verdict"], "scorable": expected["scorable"],
                       "available": observed is not None, "expected": expected, "observed": observed}
                rows.append(row)
                for counter in (metric["items"], metric[row["kind"]]):
                    counter["planned"] += 1
                    counter["available"] += observed is not None
                    if not expected["scorable"]:
                        counter["ambiguous_planned"] += 1
                        continue
                    counter["scorable_planned"] += 1
                    counter["scorable_available"] += observed is not None
                    counter["exact_choice_match"] += bool(observed and observed["matches_frozen_judgments"])
                    counter["choice_rows_planned"] += 4
                    if observed:
                        counter["choice_rows_available"] += 4
                        counter["choice_rows_match"] += sum(a["judgment"] == b["judgment"] for a,b in zip(expected["expected_choices"], observed["record"]["choices"], strict=True))
                    valid = expected["premise_verdict"] == "unique"
                    label = "valid" if valid else "defective"
                    counter[label + "_planned"] += 1
                    counter[label + "_available"] += observed is not None
                    counter[label + "_eligible"] += bool(observed and observed["rejection_reason"] is None)
                    counter[label + "_vetoed"] += bool(observed and observed["rejection_reason"] is not None)

    # Assign each subject's repeats and arms to the same reviewer, balanced by kind/scorability.
    assignments = {}
    for group in ("historical_scored", "historical_ambiguous", "fresh"):
        keys = sorted(key for key, value in subjects.items() if
                      ("fresh" if value["kind"] == "fresh" else "historical_scored" if value["scorable"] else "historical_ambiguous") == group)
        for index, key in enumerate(keys):
            assignments[key] = "a" if index % 2 == 0 else "b"
    packets = {letter: [] for letter in "ab"}
    judgments = {letter: [] for letter in "ab"}
    for row in rows:
        if not row["available"]:
            continue
        key = (row["batch_id"], row["index"])
        letter = assignments[key]
        record = row["observed"]["record"]
        # No arm/repeat/key/expectation, and canonical field presentation hides the intervention.
        packets[letter].append({"id": row["id"], "subject": subjects[key]["subject"],
                                "choice_reasons": [{"choice": value["choice"], "reason": value["reason"]} for value in record["choices"]]})
        judgments[letter].append({"id": row["id"], "choice_judgments": [{"choice": value["choice"], "judgment": value["judgment"]} for value in record["choices"]]})
    args.directory.mkdir(parents=True, exist_ok=False)
    for letter in "ab":
        write(args.directory / f"rationale-packet-{letter}.json", sorted(packets[letter], key=lambda value: value["id"]))
        write(args.directory / f"judgments-{letter}.json", sorted(judgments[letter], key=lambda value: value["id"]))
    write(args.directory / "mapping.json", rows)
    paired = defaultdict(dict)
    for row in rows:
        if row["scorable"]:
            paired[(row["batch_id"], row["index"], row["repeat"])][row["arm"]] = row
    paired_counts = Counter()
    for pair in paired.values():
        left, right = pair["judgment_first"], pair["reason_first"]
        if not left["available"] or not right["available"]:
            paired_counts["unavailable"] += 1
            continue
        a, b = left["observed"]["matches_frozen_judgments"], right["observed"]["matches_frozen_judgments"]
        paired_counts["both_correct" if a and b else "reason_first_only" if b else "judgment_first_only" if a else "neither_correct"] += 1
    completed = [call["observation"]["response"] for call in calls.values() if call["status"] == "completed"]
    write(args.directory / "mechanical-results.json", {"capture_byte_sha256": hashlib.sha256(args.capture.read_bytes()).hexdigest(),
          "plan_sha256": capture["plan_sha256"], "capture_status": capture["status"],
          "offline_replayed_calls": len(calls), "usage_known_calls": sum(call["usage_known"] for call in calls.values()),
          "usage": usage, "usage_scope": "Observed completed responses only; timed-out request usage is unknown.",
          "by_arm": metrics, "validation_failures": errors, "paired_scored_responses": paired_counts,
          "completed_stop_reasons": Counter(response["stopReason"] for response in completed),
          "completed_output_tokens_min": min(response["usage"]["outputTokens"] for response in completed),
          "completed_output_tokens_max": max(response["usage"]["outputTokens"] for response in completed),
          "rationale_assessment": "pending", "production_acceptance": "not_run"})
    print(json.dumps({"by_arm": metrics, "usage": usage, "validation_failures": errors,
                      "assessment_packet_sizes": {key: len(value) for key,value in packets.items()}}, indent=2))


if __name__ == "__main__":
    main()
