"""Freeze and run a reviewed 20-case native pair-solver qualification.

Four calls maximum, no retries, no production edits. --run reads the frozen
plan rather than rebuilding requests and refuses to replace a prior capture.
Gold review approval is required for preparation; parent approval is separately
required before invoking --run. No provider call occurs in the default mode.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
from itertools import combinations
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SERVICE = REPO / "backend" / "bedrock-question-service"
ARCHIVE = HERE.parent / "choice-reliability-followup-20260921" / "candidate_complete_question_solution.py"
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
from botocore.config import Config  # noqa: E402
import jsonschema  # noqa: E402
from native_output_contracts import (  # noqa: E402
    _reject_constant, _reject_duplicate_pairs, native_prompt,
)

spec = importlib.util.spec_from_file_location("qualified_archived_pair_solver", ARCHIVE)
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def reviewed_packet():
    packet_path = HERE / "controls-draft.json"
    review = json.loads((HERE / "independent-gold-review.json").read_text())
    if review.get("approved") is not True or review.get("reviewed_packet_sha256") != sha(packet_path):
        raise ValueError("Gold approval is absent or does not bind this exact packet.")
    packet = json.loads(packet_path.read_text())
    cases = packet["controls"]
    if len(cases) != 20 or len({c["id"] for c in cases}) != 20:
        raise ValueError("Expected twenty distinct reviewed cases.")
    if sorted(c["id"] for c in cases) != sorted(cid for batch in packet["batches"] for cid in batch):
        raise ValueError("Batches must cover all cases once.")
    if len(packet["batches"]) != 4 or any(len(batch) != 5 for batch in packet["batches"]):
        raise ValueError("Exactly four five-item batches are required.")
    for case in cases:
        if len(case["choices"]) != 4 or len(set(case["choices"])) != 4:
            raise ValueError("Each case requires four distinct exact strings.")
        if case["expectedAnswer"] not in case["choices"] or not set(case["supportedChoices"]).issubset(case["choices"]):
            raise ValueError("Gold key/support does not match offered text.")
        if (expected_veto(case) is None) != case["expectedEligible"]:
            raise ValueError("Eligibility and explicit gold judgments disagree.")
    return packet, review


def expected_veto(case):
    supported = case["supportedChoices"]
    if len(supported) > 1:
        return "solver_multiple_supported"
    if not supported:
        return "solver_zero_supported"
    if supported != [case["expectedAnswer"]]:
        return "answer_disagreement"
    if case["equivalentPairs"]:
        return "solver_equivalent_choices"
    return None


def make_plan():
    packet, review = reviewed_packet()
    cases = {case["id"]: case for case in packet["controls"]}
    prior_plan = json.loads((HERE.parent / "choice-reliability-followup-20260921" / "plan.json").read_text())
    previous = next(job for job in prior_plan["jobs"] if job["arm"] == "pairwise")
    output_config = previous["request"]["outputConfig"]
    jobs = []
    for batch_index, case_ids in enumerate(packet["batches"]):
        items = []
        for index, case_id in enumerate(case_ids):
            case = cases[case_id]
            offset = (3 * (batch_index * 5 + index) + 1) % 4
            options = case["choices"][offset:] + case["choices"][:offset]
            items.append({"index": index, "prompt": case["prompt"], "choices": options, "topic": case["topic"]})
        system, user = candidate.build_solver_prompt(items, {"goal": {"title": "Apply stated facts and established rules across common subjects"}}, audit_choice_pairs=True)
        request = {
            "modelId": "us.anthropic.claude-sonnet-4-6",
            "system": [{"text": native_prompt(system, "complete_choice_solver_v2")}],
            "messages": [{"role": "user", "content": [{"text": user}]}],
            "inferenceConfig": {"maxTokens": 6000, "temperature": 0.2},
            "additionalModelRequestFields": {"thinking": {"type": "disabled"}},
            "outputConfig": output_config,
        }
        if request["system"] != previous["request"]["system"]:
            raise ValueError("Candidate prompt differs from the archived tested prompt.")
        jobs.append({"call_index": batch_index, "case_ids": case_ids, "items": items, "request": request, "request_sha256": digest(request)})
    return {
        "experiment": "prospective-meaningful-choice-quality-release-20260922",
        "status": "frozen_after_independent_gold_review; awaiting_parent_dispatch_approval",
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
        "candidate_source": str(ARCHIVE.relative_to(REPO)), "candidate_sha256": sha(ARCHIVE),
        "runner_sha256": sha(Path(__file__)),
        "reviewed_packet_sha256": sha(HERE / "controls-draft.json"),
        "gold_review_sha256": sha(HERE / "independent-gold-review.json"),
        "rubric_sha256": sha(HERE / "RUBRIC_AND_PLAN.md"),
        "runtime_dependency_sha256": {name: sha(SERVICE / name) for name in ["question_quality.py", "request_contract.py", "generation_diagnostics.py", "service_errors.py"]},
        "settings": {"region": "us-east-1", "maximum_calls": 4, "sdk_total_max_attempts": 1, "connect_timeout_seconds": 3, "read_timeout_seconds": 75, "max_output_tokens": 6000},
        "scope": "Twenty new independently reviewed fixed cases, ten valid and ten defective; final two batches contain realistic mixed-topic application items. No author calls, keys/gold in solver input, baseline reruns, repairs, or production mutations. Prior failed results remain unchanged. This is bounded solver qualification, not broad accuracy or repeated-run stability.",
        "stop_policy": "Stop after the first transport, completion, JSON/schema, exact identity, coverage or reason-bound failure; preserve unattempted jobs. Continue all planned batches after semantic errors to retain the full frozen denominator. No retries or replacements.",
        "prospective_criteria": {"completed_valid_calls": 4, "valid_items_retained": 10, "defective_items_excluded_for_expected_reason": 10, "choice_judgments_correct": 80, "pair_relations_correct": 120, "uncertain_judgments": 0, "no_truncation_or_repair": True},
        "gold_review": review, "controls": packet["controls"], "jobs": jobs,
    }


def score(raw, job, cases):
    schema = json.loads(job["request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
    payload = json.loads(raw, object_pairs_hook=_reject_duplicate_pairs, parse_constant=_reject_constant)
    jsonschema.Draft202012Validator(schema).validate(payload)
    records = candidate.validate_batch(raw, job["items"], audit_choice_pairs=True)
    rows = []
    for item, record, case_id in zip(job["items"], records, job["case_ids"], strict=True):
        case = cases[case_id]
        veto = candidate.rejection_reason(record, {**item, "expectedAnswer": case["expectedAnswer"]}, audit_choice_pairs=True)
        equivalent = {frozenset(pair) for pair in case["equivalentPairs"]}
        choices = [{**row, "expected_judgment": "supported" if row["choice"] in case["supportedChoices"] else "refuted"} for row in record["choices"]]
        for row in choices:
            row["judgment_agrees"] = row["judgment"] == row["expected_judgment"]
        pairs = [{**pair, "expected_relation": "equivalent" if frozenset((pair["leftChoice"], pair["rightChoice"])) in equivalent else "distinct"} for pair in record["choicePairs"]]
        for pair in pairs:
            pair["relation_agrees"] = pair["relation"] == pair["expected_relation"]
        rows.append({"case_id": case_id, "expected_eligible": case["expectedEligible"], "eligible": veto is None, "expected_veto": expected_veto(case), "veto": veto,
                     "veto_agrees": veto == expected_veto(case), "choices": choices, "pairs": pairs,
                     "all_gold_agrees": veto == expected_veto(case) and all(r["judgment_agrees"] for r in choices) and all(r["relation_agrees"] for r in pairs)})
    return {"strict_schema_and_coverage_valid": True, "rows": rows}


def assert_frozen_bindings(plan):
    checks = {"candidate_sha256": ARCHIVE, "runner_sha256": Path(__file__), "reviewed_packet_sha256": HERE / "controls-draft.json", "gold_review_sha256": HERE / "independent-gold-review.json", "rubric_sha256": HERE / "RUBRIC_AND_PLAN.md"}
    for field, path in checks.items():
        if sha(path) != plan[field]:
            raise RuntimeError(f"Frozen binding changed: {field}.")
    for name, expected in plan["runtime_dependency_sha256"].items():
        if sha(SERVICE / name) != expected:
            raise RuntimeError(f"Frozen parser dependency changed: {name}.")
    for job in plan["jobs"]:
        if digest(job["request"]) != job["request_sha256"]:
            raise RuntimeError("Frozen provider request changed.")


def dry_validate(plan):
    """Synthetic gold exercises parser/scoring only; it is not model evidence."""
    cases = {case["id"]: case for case in plan["controls"]}
    for job in plan["jobs"]:
        records = []
        for item, case_id in zip(job["items"], job["case_ids"], strict=True):
            case = cases[case_id]
            equivalent = {frozenset(pair) for pair in case["equivalentPairs"]}
            records.append({
                "index": item["index"],
                "choices": [{"choice": value, "judgment": "supported" if value in case["supportedChoices"] else "refuted", "reason": "Synthetic gold for offline validator testing; not a model result."} for value in item["choices"]],
                "choicePairs": [{"leftChoice": a, "rightChoice": b, "relation": "equivalent" if frozenset((a, b)) in equivalent else "distinct", "reason": "Synthetic gold for offline validator testing; not a model result."} for a, b in combinations(item["choices"], 2)],
            })
        outcome = score(json.dumps({"solutions": records}), job, cases)
        if not all(row["all_gold_agrees"] for row in outcome["rows"]):
            raise AssertionError("Gold round-trip through actual candidate API disagrees.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    path = HERE / "plan.json"
    if not args.run:
        plan = make_plan()
        dry_validate(plan)
        if path.exists() and json.loads(path.read_text()) != plan:
            raise RuntimeError("Refusing to alter an existing frozen plan.")
        save(path, plan)
        print(f"Frozen 20 reviewed cases / four native calls; plan byte SHA256 {sha(path)}. No provider calls.")
        return
    plan = json.loads(path.read_text())
    assert_frozen_bindings(plan)
    output = HERE / "capture.json"
    if output.exists():
        raise RuntimeError("Refusing to replace a capture or repeat calls.")
    cases = {case["id"]: case for case in plan["controls"]}
    client = boto3.client("bedrock-runtime", region_name="us-east-1", config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1, "mode": "standard"}))
    capture = {"plan_sha256": digest(plan), "plan_byte_sha256": sha(path), "started_at": datetime.now(timezone.utc).isoformat(), "status": "running", "calls": []}
    save(output, capture)
    for job in plan["jobs"]:
        call = {"call_index": job["call_index"], "request_sha256": job["request_sha256"], "dispatch_attempted": True}
        capture["calls"].append(call)
        save(output, capture)
        start = time.monotonic()
        print(f"Dispatch {job['call_index'] + 1}/4", flush=True)
        try:
            response = client.converse(**job["request"])
            raw = "\n".join(block["text"] for block in response["output"]["message"]["content"] if "text" in block)
            call.update({"elapsed_seconds": round(time.monotonic() - start, 3), "raw": raw, "usage": response.get("usage"), "stop_reason": response.get("stopReason")})
            save(output, capture)
            if response.get("stopReason") != "end_turn":
                raise ValueError("Provider did not end normally; no repair or retry.")
            call["score"] = score(raw, job, cases)
            print(f"Complete {job['call_index'] + 1}/4; all-gold-agree={sum(r['all_gold_agrees'] for r in call['score']['rows'])}/5; eligible={[r['case_id'] for r in call['score']['rows'] if r['eligible']]}", flush=True)
        except Exception as error:
            call.update({"elapsed_seconds": round(time.monotonic() - start, 3), "error_type": type(error).__name__, "error": str(error)})
            capture["status"] = "stopped_after_failure"
            save(output, capture)
            print(f"Stopped: {type(error).__name__}", flush=True)
            return
        save(output, capture)
    capture["status"] = "complete"
    capture["completed_at"] = datetime.now(timezone.utc).isoformat()
    save(output, capture)


if __name__ == "__main__":
    main()
