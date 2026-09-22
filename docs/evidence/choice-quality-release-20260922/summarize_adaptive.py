"""Summarize the completed adaptive-thinking trial without model calls or repairs."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    plan = json.loads((HERE / "adaptive-plan.json").read_text())
    capture = json.loads((HERE / "adaptive-capture.json").read_text())
    assert capture["status"] in {"complete", "stopped_after_failure"}
    assert capture["plan_byte_sha256"] == sha(HERE / "adaptive-plan.json")
    rows = [row for call in capture["calls"] for row in call.get("score", {}).get("rows", [])]
    choices = [row for item in rows for row in item["choices"]]
    pairs = [row for item in rows for row in item["pairs"]]
    counts = {
        "planned_calls": 4, "attempted_calls": len(capture["calls"]),
        "completed_valid_calls": sum(call.get("score", {}).get("strict_schema_and_coverage_valid", False) for call in capture["calls"]),
        "valid_retained": sum(row["eligible"] for row in rows if row["expected_eligible"]), "valid_denominator": 10,
        "defective_excluded": sum(not row["eligible"] for row in rows if not row["expected_eligible"]), "defective_denominator": 10,
        "defective_expected_veto": sum(row["veto_agrees"] for row in rows if not row["expected_eligible"]),
        "all_gold_agrees": sum(row["all_gold_agrees"] for row in rows), "item_denominator": 20,
        "choice_correct": sum(row["judgment_agrees"] for row in choices), "choice_scored": len(choices), "choice_denominator": 80,
        "pair_correct": sum(row["relation_agrees"] for row in pairs), "pair_scored": len(pairs), "pair_denominator": 120,
        "uncertain_choices": sum(row["judgment"] == "uncertain" for row in choices),
        "uncertain_pairs": sum(row["relation"] == "uncertain" for row in pairs),
        "choice_reason_before_judgment_rows": sum(call.get("score", {}).get("observed_order", {}).get("choice_reason_before_judgment_rows", 0) for call in capture["calls"]),
        "pair_reason_before_relation_rows": sum(call.get("score", {}).get("observed_order", {}).get("pair_reason_before_relation_rows", 0) for call in capture["calls"]),
    }
    checks = {
        "completed_calls": counts["completed_valid_calls"] == 4,
        "valid_retained": counts["valid_retained"] == 10,
        "defective_expected_veto": counts["defective_expected_veto"] == 10,
        "correctness": counts["choice_correct"] == 80,
        "pair_labels": counts["pair_correct"] == 120,
        "reason_order": counts["choice_reason_before_judgment_rows"] == 80 and counts["pair_reason_before_relation_rows"] == 120,
        "no_uncertainty": counts["uncertain_choices"] == counts["uncertain_pairs"] == 0,
    }
    result = {
        "plan_byte_sha256": sha(HERE / "adaptive-plan.json"), "capture_byte_sha256": sha(HERE / "adaptive-capture.json"),
        "source_sha256": plan["source_sha256"], "status": capture["status"],
        "counts": counts, "criteria_checks": checks, "qualified_on_fixed_suite": all(checks.values()),
        "usage": {key: sum(call.get("usage", {}).get(key, 0) for call in capture["calls"]) for key in ["inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens", "cacheWriteInputTokens"]},
        "elapsed_seconds_sum": round(sum(call.get("elapsed_seconds", 0) for call in capture["calls"]), 3),
        "maximum_call_seconds": max((call.get("elapsed_seconds", 0) for call in capture["calls"]), default=0),
        "reasoning_content_block_count": sum(call.get("reasoning_content_block_count", 0) for call in capture["calls"]),
        "provider_budget_calls": capture.get("provider_budget_calls"),
        "failed_items": [row for row in rows if not row["all_gold_agrees"]],
        "per_call": [{"call_index": call["call_index"], "stop_reason": call.get("stop_reason"), "error": call.get("error"), "elapsed_seconds": call.get("elapsed_seconds"), "usage": call.get("usage"), "reasoning_content_block_count": call.get("reasoning_content_block_count"), "all_gold_agrees": sum(row["all_gold_agrees"] for row in call.get("score", {}).get("rows", []))} for call in capture["calls"]],
        "limits": "One sample per batch on 20 reused reviewed cases. Adaptive/high reasoning with runtime-required sampling/output-cap changes; unchanged endpoint input, prompt and schema, not a causal isolation or general accuracy/determinism result. Earlier failures unchanged.",
    }
    disabled = json.loads((HERE / "endpoint-summary.json").read_text())
    result["historical_disabled_comparison"] = {
        "paired_causal_comparison": False,
        "disabled_counts": disabled["counts"], "disabled_usage": disabled["usage"],
        "disabled_elapsed_seconds_sum": disabled["elapsed_seconds_sum"],
        "disabled_maximum_call_seconds": max(call["elapsed_seconds"] for call in disabled["per_call"]),
        "elapsed_seconds_sum_ratio": result["elapsed_seconds_sum"] / disabled["elapsed_seconds_sum"],
        "output_tokens_ratio": result["usage"]["outputTokens"] / disabled["usage"]["outputTokens"],
    }
    (HERE / "adaptive-summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({key: result[key] for key in ["qualified_on_fixed_suite", "counts", "usage", "elapsed_seconds_sum", "capture_byte_sha256"]}, indent=2))


if __name__ == "__main__":
    main()
