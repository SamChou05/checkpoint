"""Freeze/run four fixed-slot native solver qualification calls; no retries."""
import argparse
from copy import deepcopy
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("slot_qualification_base", HERE / "qualify_pair_solver.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

import complete_question_solution as candidate  # noqa: E402
from native_output_contracts import adapt_native_response, native_output_config, native_prompt  # noqa: E402


def source_files():
    return {str(path.relative_to(base.REPO)): base.sha(path) for path in [
        base.SERVICE / "complete_question_solution.py", base.SERVICE / "native_output_contracts.py",
        base.SERVICE / "question_quality.py", base.SERVICE / "request_contract.py",
        base.SERVICE / "generation_diagnostics.py", base.SERVICE / "service_errors.py",
        HERE / "qualify_pair_solver.py", base.ARCHIVE,
    ]}


def slots_from_request(job):
    user = job["request"]["messages"][0]["content"][0]["text"]
    return json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])["items"]


def make_plan():
    original = json.loads((HERE / "plan.json").read_text())
    packet, review = base.reviewed_packet()
    assert original["controls"] == packet["controls"]
    jobs = []
    for prior in original["jobs"]:
        job = deepcopy(prior)
        system, user = candidate.build_solver_prompt(job["items"], {"goal": {"title": "Apply stated facts and established rules across common subjects"}}, audit_choice_pairs=True, choice_slots=True)
        request = job["request"]
        request["system"] = [{"text": native_prompt(system, "complete_choice_solver_v3")}]
        request["messages"] = [{"role": "user", "content": [{"text": user}]}]
        request["outputConfig"] = native_output_config("complete_choice_solver_v3")
        job["request_sha256"] = base.digest(request)
        jobs.append(job)
    return {
        "experiment": "fixed-slot-native-solver-qualification-20260922",
        "status": "frozen_awaiting_parent_dispatch_approval",
        "source_sha256": source_files(), "runner_sha256": base.sha(Path(__file__)),
        "document_sha256": base.sha(HERE / "SLOT_PLAN.md"),
        "prior_qualification_plan_sha256": base.sha(HERE / "plan.json"),
        "prior_qualification_capture_sha256": base.sha(HERE / "capture.json"),
        "prior_order_capture_sha256": base.sha(HERE / "order-capture.json"),
        "reviewed_packet_sha256": base.sha(HERE / "controls-draft.json"),
        "gold_review_sha256": base.sha(HERE / "independent-gold-review.json"),
        "settings": original["settings"], "stop_policy": original["stop_policy"],
        "criteria": {**original["prospective_criteria"], "choice_reason_before_judgment_rows": 80, "pair_reason_before_relation_rows": 120},
        "scope": "Four candidate calls on the unchanged twenty reviewed reused controls; fixed choice/pair identifiers and trusted exact-text decoding, key-independent slot order, reasons before verdicts. No baseline/author calls or causal ordering claim; previous failures unchanged.",
        "controls": original["controls"], "jobs": jobs, "gold_review": review,
    }


def assert_bindings(plan):
    assert source_files() == plan["source_sha256"], "Frozen runtime changed."
    paths = {"runner_sha256": Path(__file__), "document_sha256": HERE / "SLOT_PLAN.md",
             "prior_qualification_plan_sha256": HERE / "plan.json", "prior_qualification_capture_sha256": HERE / "capture.json",
             "prior_order_capture_sha256": HERE / "order-capture.json", "reviewed_packet_sha256": HERE / "controls-draft.json",
             "gold_review_sha256": HERE / "independent-gold-review.json"}
    for key, path in paths.items():
        assert base.sha(path) == plan[key], f"Frozen binding changed: {key}"
    for job in plan["jobs"]:
        assert base.digest(job["request"]) == job["request_sha256"]
        assert job["request"]["outputConfig"] == native_output_config("complete_choice_solver_v3")


def score(raw, job, cases):
    schema = json.loads(job["request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
    payload = json.loads(raw, object_pairs_hook=base._reject_duplicate_pairs, parse_constant=base._reject_constant)
    base.jsonschema.Draft202012Validator(schema).validate(payload)
    adapted = adapt_native_response(raw, "complete_choice_solver_v3")
    records = candidate.validate_batch(adapted, job["items"], audit_choice_pairs=True, choice_slots=True)
    legacy_job = json.loads((HERE / "plan.json").read_text())["jobs"][job["call_index"]]
    result = base.score(json.dumps({"solutions": records}, ensure_ascii=False), legacy_job, cases)
    for item, record, row in zip(job["items"], records, result["rows"], strict=True):
        key = cases[row["case_id"]]["expectedAnswer"]
        assert candidate.rejection_reason(record, {**item, "expectedAnswer": key}, audit_choice_pairs=True) == row["veto"]
    result["observed_order"] = {
        "choice_reason_before_judgment_rows": sum(list(row).index("reason") < list(row).index("judgment") for item in payload["solutions"] for row in item["choices"].values()),
        "pair_reason_before_relation_rows": sum(list(row).index("reason") < list(row).index("relation") for item in payload["solutions"] for row in item["choicePairs"].values()),
    }
    return result


def dry_validate(plan):
    cases = {case["id"]: case for case in plan["controls"]}
    for job in plan["jobs"]:
        records = []
        for item, case_id in zip(slots_from_request(job), job["case_ids"], strict=True):
            case = cases[case_id]
            choices = item["choices"]
            equivalents = {frozenset(pair) for pair in case["equivalentPairs"]}
            records.append({"index": item["index"],
                            "choices": {slot: {"reason": "Synthetic gold; not a model judgment.", "judgment": "supported" if text in case["supportedChoices"] else "refuted"} for slot, text in choices.items()},
                            "choicePairs": {pair: {"reason": "Synthetic gold; not a model judgment.", "relation": "equivalent" if frozenset((choices[pair[0]], choices[pair[1]])) in equivalents else "distinct"} for pair in candidate.CHOICE_PAIR_SLOTS}})
        result = score(json.dumps({"solutions": records}), job, cases)
        assert all(row["all_gold_agrees"] for row in result["rows"])
        assert result["observed_order"] == {"choice_reason_before_judgment_rows": 20, "pair_reason_before_relation_rows": 30}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    path = HERE / "slot-plan.json"
    if not args.run:
        plan = make_plan()
        assert_bindings(plan)
        dry_validate(plan)
        if path.exists() and json.loads(path.read_text()) != plan:
            raise RuntimeError("Refusing to change a frozen plan.")
        base.save(path, plan)
        print(f"Frozen four native slot requests; plan byte SHA256 {base.sha(path)}. Dry validation passed; no provider calls.")
        return
    plan = json.loads(path.read_text())
    assert_bindings(plan)
    output = HERE / "slot-capture.json"
    if output.exists():
        raise RuntimeError("Refusing to overwrite capture or repeat calls.")
    cases = {case["id"]: case for case in plan["controls"]}
    client = base.boto3.client("bedrock-runtime", region_name="us-east-1", config=base.Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1, "mode": "standard"}))
    capture = {"plan_sha256": base.digest(plan), "plan_byte_sha256": base.sha(path), "started_at": datetime.now(timezone.utc).isoformat(), "status": "running", "calls": []}
    base.save(output, capture)
    for job in plan["jobs"]:
        assert_bindings(plan)
        call = {"call_index": job["call_index"], "request_sha256": job["request_sha256"], "dispatch_attempted": True}
        capture["calls"].append(call)
        base.save(output, capture)
        print(f"Dispatch {job['call_index'] + 1}/4", flush=True)
        start = time.monotonic()
        try:
            response = client.converse(**job["request"])
            raw = "\n".join(block["text"] for block in response["output"]["message"]["content"] if "text" in block)
            call.update({"elapsed_seconds": round(time.monotonic() - start, 3), "raw": raw, "usage": response.get("usage"), "stop_reason": response.get("stopReason")})
            base.save(output, capture)
            if response.get("stopReason") != "end_turn":
                raise ValueError("Abnormal completion; no repair or retry.")
            call["score"] = score(raw, job, cases)
            print(f"Complete {job['call_index'] + 1}/4: all-gold={sum(row['all_gold_agrees'] for row in call['score']['rows'])}/5", flush=True)
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
