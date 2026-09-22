"""Freeze/run eight paired native calls isolating choice field order.

Default: offline freeze and invariant checks. --run requires parent approval.
No prompt edits; only choice-row schema property/required order changes.
"""
import argparse
from collections import Counter
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import importlib.util
import inspect
import json
from pathlib import Path
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("frozen_release_qualification", HERE / "qualify_pair_solver.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)


def choice_schema(schema):
    return schema["properties"]["solutions"]["items"]["properties"]["choices"]["items"]


def schema_container(request):
    return request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]


def reorder_choice_fields(request):
    candidate = deepcopy(request)
    original = schema_container(request)["schema"]
    schema = json.loads(original)
    row = choice_schema(schema)
    assert list(row["properties"]) == ["choice", "judgment", "reason"]
    assert row["required"] == ["choice", "judgment", "reason"]
    row["properties"] = {key: row["properties"][key] for key in ["choice", "reason", "judgment"]}
    row["required"] = ["choice", "reason", "judgment"]
    schema_container(candidate)["schema"] = json.dumps(schema, separators=(",", ":"), ensure_ascii=True)
    # Reversing exactly the proposed intervention must recover every request byte.
    restored = deepcopy(candidate)
    restored_schema = json.loads(schema_container(restored)["schema"])
    restored_row = choice_schema(restored_schema)
    restored_row["properties"] = {key: restored_row["properties"][key] for key in ["choice", "judgment", "reason"]}
    restored_row["required"] = ["choice", "judgment", "reason"]
    schema_container(restored)["schema"] = json.dumps(restored_schema, separators=(",", ":"), ensure_ascii=True)
    assert restored == request
    assert schema_container(restored)["schema"] == original
    # JSON-schema semantics are unchanged: required is a set, property order has
    # no validation meaning. Preserve other arrays, including all pair schema data.
    baseline_schema = json.loads(original)
    comparable = deepcopy(schema)
    choice_schema(comparable)["required"] = choice_schema(baseline_schema)["required"]
    assert comparable == baseline_schema
    assert candidate != request
    return candidate


def helper_hashes():
    return {name: hashlib.sha256(inspect.getsource(getattr(base, name)).encode()).hexdigest()
            for name in ["_reject_constant", "_reject_duplicate_pairs"]}


def make_plan():
    original_path = HERE / "plan.json"
    original = json.loads(original_path.read_text())
    base.assert_frozen_bindings(original)
    jobs = []
    for batch, existing in enumerate(original["jobs"]):
        order = ["baseline", "reason_first"] if batch % 2 == 0 else ["reason_first", "baseline"]
        for arm in order:
            job = deepcopy(existing)
            job.update({"call_index": len(jobs), "batch_index": batch, "arm": arm})
            if arm == "reason_first":
                job["request"] = reorder_choice_fields(existing["request"])
            job["request_sha256"] = base.digest(job["request"])
            job["schema_string_sha256"] = hashlib.sha256(schema_container(job["request"])["schema"].encode()).hexdigest()
            jobs.append(job)
    return {
        "experiment": "paired-choice-reason-before-judgment-20260922",
        "status": "frozen_awaiting_parent_dispatch_approval",
        "parent_qualification_plan_sha256": base.sha(original_path),
        "prior_failed_capture_sha256": base.sha(HERE / "capture.json"),
        "runner_sha256": base.sha(Path(__file__)), "plan_document_sha256": base.sha(HERE / "ORDER_PLAN.md"),
        "strict_json_helper_source_sha256": helper_hashes(),
        "settings": {**original["settings"], "maximum_calls": 8},
        "intervention": "Only choice-row native schema properties/required serialized order changes from choice,judgment,reason to choice,reason,judgment. No field/prompt/input/settings/pair-schema change.",
        "gold": "Exact previously independently reviewed twenty-case packet. Reused controls, not new held-out cases. Frozen labels and prior failed results unchanged.",
        "scoring": "Same archived candidate APIs and strict JSON/native validation as prior qualification. Record raw key ordering separately from semantic agreement.",
        "stop_policy": original["stop_policy"],
        "prospective_candidate_criteria": {**original["prospective_criteria"], "choice_reason_before_judgment_rows": 80},
        "hypothesis_support_criteria": "Candidate qualifies, has fewer incorrect correctness labels than contemporaneous baseline, and no pair-label regression. Equal results do not establish semantic benefit. No broad accuracy or determinism claim.",
        "planned_denominators_per_arm": {"calls": 4, "items": 20, "valid": 10, "defective": 10, "choices": 80, "pairs": 120},
        "controls": original["controls"], "jobs": jobs,
    }


def assert_bindings(plan):
    for key, path in [
        ("parent_qualification_plan_sha256", HERE / "plan.json"),
        ("prior_failed_capture_sha256", HERE / "capture.json"),
        ("runner_sha256", Path(__file__)),
        ("plan_document_sha256", HERE / "ORDER_PLAN.md"),
    ]:
        assert base.sha(path) == plan[key], f"Frozen binding changed: {key}"
    base.assert_frozen_bindings(json.loads((HERE / "plan.json").read_text()))
    assert helper_hashes() == plan["strict_json_helper_source_sha256"]
    for job in plan["jobs"]:
        assert base.digest(job["request"]) == job["request_sha256"]
        assert hashlib.sha256(schema_container(job["request"])["schema"].encode()).hexdigest() == job["schema_string_sha256"]


def observed_order(raw):
    choices, pairs = Counter(), Counter()
    reason_before = 0
    for record in json.loads(raw)["solutions"]:
        for row in record["choices"]:
            keys = list(row)
            choices.update([tuple(keys)])
            reason_before += keys.index("reason") < keys.index("judgment")
        pairs.update(tuple(row) for row in record["choicePairs"])
    return {"choices": [{"order": list(order), "count": count} for order, count in choices.items()],
            "pairs": [{"order": list(order), "count": count} for order, count in pairs.items()],
            "choice_reason_before_judgment_rows": reason_before}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    plan_path = HERE / "order-plan.json"
    if not args.run:
        plan = make_plan()
        base.dry_validate(plan)
        assert_bindings(plan)
        if plan_path.exists() and json.loads(plan_path.read_text()) != plan:
            raise RuntimeError("Refusing to mutate an existing frozen plan.")
        base.save(plan_path, plan)
        print(f"Frozen eight paired requests; plan byte SHA256 {base.sha(plan_path)}. Offline validation passed; no provider calls.")
        return
    plan = json.loads(plan_path.read_text())
    assert_bindings(plan)
    output = HERE / "order-capture.json"
    if output.exists():
        raise RuntimeError("Refusing to overwrite capture or repeat calls.")
    cases = {case["id"]: case for case in plan["controls"]}
    client = base.boto3.client("bedrock-runtime", region_name="us-east-1", config=base.Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1, "mode": "standard"}))
    capture = {"plan_sha256": base.digest(plan), "plan_byte_sha256": base.sha(plan_path), "started_at": datetime.now(timezone.utc).isoformat(), "status": "running", "calls": []}
    base.save(output, capture)
    for job in plan["jobs"]:
        assert_bindings(plan)
        call = {"call_index": job["call_index"], "batch_index": job["batch_index"], "arm": job["arm"], "request_sha256": job["request_sha256"], "dispatch_attempted": True}
        capture["calls"].append(call)
        base.save(output, capture)
        print(f"Dispatch {job['call_index'] + 1}/8: batch {job['batch_index']} {job['arm']}", flush=True)
        start = time.monotonic()
        try:
            response = client.converse(**job["request"])
            raw = "\n".join(block["text"] for block in response["output"]["message"]["content"] if "text" in block)
            call.update({"elapsed_seconds": round(time.monotonic() - start, 3), "raw": raw, "usage": response.get("usage"), "stop_reason": response.get("stopReason")})
            base.save(output, capture)
            if response.get("stopReason") != "end_turn":
                raise ValueError("Abnormal completion; no repair or retry.")
            call["score"] = base.score(raw, job, cases)
            call["observed_order"] = observed_order(raw)
            print(f"Complete {job['call_index'] + 1}/8: all-gold={sum(row['all_gold_agrees'] for row in call['score']['rows'])}/5; reason-first rows={call['observed_order']['choice_reason_before_judgment_rows']}/20", flush=True)
        except Exception as error:
            call.update({"elapsed_seconds": round(time.monotonic() - start, 3), "error_type": type(error).__name__, "error": str(error)})
            capture["status"] = "stopped_after_failure"
            base.save(output, capture)
            print(f"Stopped: {type(error).__name__}", flush=True)
            return
        base.save(output, capture)
    capture["status"] = "complete"
    capture["completed_at"] = datetime.now(timezone.utc).isoformat()
    base.save(output, capture)


if __name__ == "__main__":
    main()
