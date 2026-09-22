"""Offline mechanical summary; independent content audits remain separate."""
from collections import Counter
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_payload(call):
    return json.loads("\n".join(block["text"] for block in call.get("response", {}).get(
        "output", {}).get("message", {}).get("content", []) if "text" in block))


def input_payload(call):
    content = call["request"]["messages"][0]["content"][0]["text"]
    return json.loads(content[content.index("{"):content.rindex("}") + 1])


def stage_name(call):
    return call["request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]


def bounds(row):
    choices = row.get("choices", [])
    feedback = row.get("choiceExplanations", {})
    return (
        isinstance(row.get("prompt"), str) and 0 < len(row["prompt"]) <= 320
        and len(choices) == 4 and len(set(choices)) == 4
        and all(isinstance(choice, str) and 0 < len(choice) <= 140 for choice in choices)
        and row.get("expectedAnswer") in choices
        and isinstance(row.get("explanation"), str) and 0 < len(row["explanation"]) <= 420
        and set(feedback) == set(choices)
        and all(isinstance(reason, str) and 0 < len(reason) <= 280 for reason in feedback.values())
    )


def summarize():
    plan_path = HERE / "pipeline-adaptive-plan.json"
    capture_path = HERE / "pipeline-adaptive-capture.json"
    plan, capture = json.loads(plan_path.read_text()), json.loads(capture_path.read_text())
    assert capture["plan_sha256"] == sha(plan_path)
    calls = capture["calls"]
    rows = {row["index"]: row for row in capture["jobs"]}
    jobs, stage_checks = [], []
    aggregate_quality = {}
    for job in plan["jobs"]:
        row = rows.get(job["index"], {})
        job_calls = [call for call in calls if call["job"] == job["index"]]
        admitted = row.get("accepted", [])
        quality = row.get("metrics", {}).get("QuestionQuality", {})
        for stage, reasons in quality.items():
            aggregate_quality.setdefault(stage, Counter()).update(reasons)
        jobs.append({
            "index": job["index"], "title": job["request"]["goal"]["title"],
            "planned_target": 5, "attempted": bool(row), "completed": "elapsed_seconds" in row,
            "calls": len(job_calls), "responses_with_usage": sum("usage" in call.get("response", {}) for call in job_calls), "admitted": len(admitted),
            "mechanical_bounds_and_exact_feedback_coverage": sum(bounds(item) for item in admitted),
            "elapsed_seconds": row.get("elapsed_seconds"), "remaining_ms": row.get("remaining_ms"),
            "within_240_second_deadline": row.get("within_240_second_deadline"),
            "error_type": row.get("error_type"), "quality_diagnostics": quality,
            "input_tokens": sum(call.get("response", {}).get("usage", {}).get("inputTokens", 0) for call in job_calls),
            "output_tokens": sum(call.get("response", {}).get("usage", {}).get("outputTokens", 0) for call in job_calls),
        })
    for index, call in enumerate(calls):
        stage = stage_name(call)
        if "response" not in call:
            continue
        raw = text_payload(call)
        check = {"call": index, "job": call["job"], "stage": stage,
                 "native_transport_valid": call.get("native_transport_valid")}
        if stage != "question_author_v3":
            expected = [item["index"] for item in input_payload(call)["items"]]
            key = "solutions" if stage == "complete_choice_solver_v3" else "reviews"
            indexes = [item.get("index") for item in raw[key]]
            check.update(expected_indexes=expected, returned_indexes=indexes,
                         exact_index_coverage=all(type(value) is int for value in indexes)
                         and len(indexes) == len(expected) and sorted(indexes) == sorted(expected))
        else:
            check["returned_items"] = len(raw["questions"])
        stage_checks.append(check)
    model_usage = {}
    for call in calls:
        bucket = model_usage.setdefault(call["request"]["modelId"], Counter())
        bucket["calls"] += 1
        bucket.update(call.get("response", {}).get("usage", {}))
    timeouts = [call["read_timeout_seconds"] for call in calls]
    missing_coverage = [check for check in stage_checks if check.get("exact_index_coverage") is False]
    final = capture["status"] != "running"
    yield_pass = all(job["admitted"] >= 3 for job in jobs) and sum(job["admitted"] for job in jobs) >= 27
    structural_pass = final and len(jobs) == 6 and all(job["completed"] for job in jobs) and not missing_coverage and all(
        call.get("outcome") == "end_turn" and call.get("native_transport_valid") is True for call in calls)
    return {
        "plan_sha256": sha(plan_path), "capture_sha256": sha(capture_path), "capture_status": capture["status"],
        "planned_jobs": 6, "planned_target_items": 30, "maximum_provider_calls": 36,
        "attempted_jobs": sum(job["attempted"] for job in jobs), "completed_jobs": sum(job["completed"] for job in jobs),
        "unattempted_jobs": sum(not job["attempted"] for job in jobs), "attempted_provider_calls": len(calls),
        "admitted_items": sum(job["admitted"] for job in jobs), "model_usage": model_usage,
        "usage_limitation": "Observed usage covers returned responses only; the timed-out provider attempt returned no usage and may have incurred unreported work.",
        "provider_elapsed_seconds": round(sum(call.get("elapsed_seconds", 0) for call in calls), 3),
        "total_job_elapsed_seconds": round(sum(job["elapsed_seconds"] or 0 for job in jobs), 3),
        "maximum_call_seconds": max((call.get("elapsed_seconds", 0) for call in calls), default=0),
        "call_outcomes": Counter(call.get("outcome", "in_flight") for call in calls),
        "contract_call_counts": Counter(stage_name(call) for call in calls),
        "all_sdk_one_attempt": all(call["sdk_total_max_attempts"] == 1 for call in calls),
        "read_timeout_min_seconds": min(timeouts, default=None), "read_timeout_max_seconds": max(timeouts, default=None),
        "shrunk_read_timeout_calls": [i for i, call in enumerate(calls) if call["read_timeout_seconds"] < 75],
        "client_admission_failures": capture["client_admission_failures"],
        "all_admitted_timeouts_fit_remaining_budget": all(call["minimum_required_ms"] <= call["remaining_before_dispatch_ms"] for call in calls),
        "reasoning_blocks_omitted": sum(call.get("reasoning_content_block_count", 0) for call in calls),
        "reasoning_content_absent_from_capture": all("reasoningContent" not in block for call in calls for block in call.get(
            "response", {}).get("output", {}).get("message", {}).get("content", [])),
        "quality_diagnostics": aggregate_quality, "stage_checks": stage_checks, "jobs": jobs,
        "frozen_yield_criterion_pass": yield_pass, "frozen_transport_schema_coverage_criterion_pass": structural_pass,
        "formal_qualification": "failed" if final and (not yield_pass or not structural_pass) else "pending independent content review",
        "content_review": "Independent manual audits are separate artifacts; mechanical checks do not establish factual correctness, distinct meaning or feedback fidelity.",
    }


if __name__ == "__main__":
    result = summarize()
    path = HERE / "pipeline-adaptive-summary.json"
    path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({key: result[key] for key in (
        "capture_status", "attempted_provider_calls", "admitted_items", "formal_qualification")}, indent=2))
