"""Recompute the frozen four-call outcome without changing source artifacts."""
from collections import Counter
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    plan = json.loads((HERE / "plan.json").read_text())
    capture = json.loads((HERE / "capture.json").read_text())
    assert capture["plan_byte_sha256"] == sha(HERE / "plan.json")
    rows = [row for call in capture["calls"] for row in call.get("score", {}).get("rows", [])]
    choices = [choice for row in rows for choice in row["choices"]]
    pairs = [pair for row in rows for pair in row["pairs"]]
    choice_orders, pair_orders = Counter(), Counter()
    for call in capture["calls"]:
        if "raw" in call:
            for record in json.loads(call["raw"])["solutions"]:
                choice_orders.update(tuple(choice) for choice in record["choices"])
                pair_orders.update(tuple(pair) for pair in record["choicePairs"])
    counts = {
        "planned_calls": 4, "attempted_calls": len(capture["calls"]),
        "strict_valid_completed_calls": sum(call.get("score", {}).get("strict_schema_and_coverage_valid", False) for call in capture["calls"]),
        "valid_retained": sum(row["eligible"] for row in rows if row["expected_eligible"]), "valid_denominator": 10,
        "defective_excluded": sum(not row["eligible"] for row in rows if not row["expected_eligible"]), "defective_denominator": 10,
        "defective_excluded_for_expected_reason": sum(row["veto_agrees"] for row in rows if not row["expected_eligible"]),
        "eligibility_agrees": sum(row["eligible"] == row["expected_eligible"] for row in rows), "item_denominator": 20,
        "all_gold_agrees": sum(row["all_gold_agrees"] for row in rows),
        "choice_judgments_correct": sum(row["judgment_agrees"] for row in choices), "choice_denominator": 80,
        "pair_relations_correct": sum(row["relation_agrees"] for row in pairs), "pair_denominator": 120,
        "uncertain_choice_judgments": sum(row["judgment"] == "uncertain" for row in choices),
        "uncertain_pair_relations": sum(row["relation"] == "uncertain" for row in pairs),
    }
    result = {
        "qualification_passed": False,
        "plan_byte_sha256": sha(HERE / "plan.json"), "capture_byte_sha256": sha(HERE / "capture.json"),
        "counts": counts,
        "usage": {key: sum(call.get("usage", {}).get(key, 0) for call in capture["calls"]) for key in ["inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens", "cacheWriteInputTokens"]},
        "elapsed_seconds_sum": round(sum(call["elapsed_seconds"] for call in capture["calls"]), 3),
        "choice_field_orders": [{"order": list(order), "count": count} for order, count in choice_orders.items()],
        "pair_field_orders": [{"order": list(order), "count": count} for order, count in pair_orders.items()],
        "failed_items": [row for row in rows if not row["all_gold_agrees"]],
        "per_call": [{"call_index": call["call_index"], "elapsed_seconds": call["elapsed_seconds"], "usage": call.get("usage"), "stop_reason": call.get("stop_reason"), "error": call.get("error"), "all_gold_agrees": sum(row["all_gold_agrees"] for row in call.get("score", {}).get("rows", []))} for call in capture["calls"]],
        "limits": "Fixed reviewed suite, one candidate response per batch. No general accuracy, repeated-run stability, author yield, or causal ordering claim. Exact reason prose is not independently scored by the pair-label totals. Previous failed gold/results unchanged.",
    }
    assert len(plan["controls"]) == counts["item_denominator"]
    (HERE / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"counts": counts, "usage": result["usage"], "elapsed_seconds_sum": result["elapsed_seconds_sum"]}, indent=2))


if __name__ == "__main__":
    main()
