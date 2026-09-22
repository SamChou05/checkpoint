"""Recompute paired ordering outcomes from frozen captures, without model calls."""
from collections import Counter
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(calls):
    rows = [row for call in calls for row in call.get("score", {}).get("rows", [])]
    choices = [row for item in rows for row in item["choices"]]
    pairs = [row for item in rows for row in item["pairs"]]
    choice_order, pair_order = Counter(), Counter()
    reason_before = 0
    # Observe even structurally rejected payloads without crediting their labels
    # as admissible semantic results. Raw captures are never changed.
    for call in calls:
        if "raw" not in call:
            continue
        try:
            for record in json.loads(call["raw"])["solutions"]:
                for row in record["choices"]:
                    keys = list(row)
                    choice_order.update([tuple(keys)])
                    reason_before += keys.index("reason") < keys.index("judgment")
                pair_order.update(tuple(row) for row in record["choicePairs"])
        except (ValueError, KeyError, TypeError):
            continue
    return {
        "planned_calls": 4, "attempted_calls": len(calls),
        "completed_valid_calls": sum(call.get("score", {}).get("strict_schema_and_coverage_valid", False) for call in calls),
        "valid_retained": sum(row["eligible"] for row in rows if row["expected_eligible"]), "valid_denominator": 10,
        "defective_excluded": sum(not row["eligible"] for row in rows if not row["expected_eligible"]), "defective_denominator": 10,
        "defective_expected_veto": sum(row["veto_agrees"] for row in rows if not row["expected_eligible"]),
        "eligibility_agrees": sum(row["eligible"] == row["expected_eligible"] for row in rows),
        "all_gold_agrees": sum(row["all_gold_agrees"] for row in rows), "item_denominator": 20,
        "choice_correct": sum(row["judgment_agrees"] for row in choices), "choice_scored": len(choices), "choice_denominator": 80,
        "pair_correct": sum(row["relation_agrees"] for row in pairs), "pair_scored": len(pairs), "pair_denominator": 120,
        "uncertain_choices": sum(row["judgment"] == "uncertain" for row in choices),
        "uncertain_pairs": sum(row["relation"] == "uncertain" for row in pairs),
        "reason_before_judgment_rows": reason_before,
        "choice_rows_with_observed_order": sum(choice_order.values()),
        "choice_field_orders": [{"order": list(order), "count": count} for order, count in choice_order.items()],
        "pair_field_orders": [{"order": list(order), "count": count} for order, count in pair_order.items()],
        "usage": {key: sum(call.get("usage", {}).get(key, 0) for call in calls) for key in ["inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens", "cacheWriteInputTokens"]},
        "elapsed_seconds_sum": round(sum(call.get("elapsed_seconds", 0) for call in calls), 3),
        "failed_items": [row for row in rows if not row["all_gold_agrees"]],
        "calls": [{"call_index": call["call_index"], "batch_index": call["batch_index"], "stop_reason": call.get("stop_reason"), "error": call.get("error"), "elapsed_seconds": call.get("elapsed_seconds"), "usage": call.get("usage"), "all_gold_agrees": sum(row["all_gold_agrees"] for row in call.get("score", {}).get("rows", []))} for call in calls],
    }


def main():
    plan = json.loads((HERE / "order-plan.json").read_text())
    capture = json.loads((HERE / "order-capture.json").read_text())
    assert capture["status"] in {"complete", "stopped_after_failure"}, "Do not summarize an ongoing trial."
    assert capture["plan_byte_sha256"] == sha(HERE / "order-plan.json")
    assert plan["prior_failed_capture_sha256"] == sha(HERE / "capture.json")
    arms = {arm: summarize([call for call in capture["calls"] if call["arm"] == arm]) for arm in ["baseline", "reason_first"]}
    baseline, candidate = arms["baseline"], arms["reason_first"]
    checks = {
        "all_four_candidate_calls_valid": candidate["completed_valid_calls"] == 4,
        "all_80_choices_reason_before_judgment": candidate["reason_before_judgment_rows"] == 80,
        "all_ten_valid_retained": candidate["valid_retained"] == 10,
        "all_ten_defective_expected_veto": candidate["defective_expected_veto"] == 10,
        "all_80_choice_judgments_correct": candidate["choice_correct"] == 80,
        "all_120_pair_relations_correct": candidate["pair_correct"] == 120,
        "no_uncertain_judgments": candidate["uncertain_choices"] == candidate["uncertain_pairs"] == 0,
    }
    paired = {}
    for arm in arms:
        paired[arm] = {row["case_id"]: row for call in capture["calls"] if call["arm"] == arm for row in call.get("score", {}).get("rows", [])}
    comparisons = []
    for case in plan["controls"]:
        row = {"case_id": case["id"], "expected_eligible": case["expectedEligible"]}
        for arm in arms:
            actual = paired[arm].get(case["id"])
            row[arm] = None if actual is None else {"eligible": actual["eligible"], "veto": actual["veto"], "all_gold_agrees": actual["all_gold_agrees"], "choice_correct": sum(choice["judgment_agrees"] for choice in actual["choices"]), "pair_correct": sum(pair["relation_agrees"] for pair in actual["pairs"])}
        comparisons.append(row)
    qualified = all(checks.values())
    result = {
        "plan_byte_sha256": sha(HERE / "order-plan.json"), "capture_byte_sha256": sha(HERE / "order-capture.json"),
        "status": capture["status"], "arms": arms, "prospective_candidate_checks": checks,
        "candidate_qualified_on_fixed_suite": qualified,
        "narrow_hypothesis_supported_on_fixed_suite": qualified and baseline["completed_valid_calls"] == 4 and candidate["choice_correct"] > baseline["choice_correct"] and candidate["pair_correct"] >= baseline["pair_correct"],
        "paired_comparisons": comparisons,
        "limits": "One sample per variant/batch on twenty reused reviewed controls. No statistical significance, general accuracy, determinism or independent fresh-author yield claim. Earlier four-call failure stays separate and unchanged.",
    }
    (HERE / "order-summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"candidate_qualified": qualified, "hypothesis_supported": result["narrow_hypothesis_supported_on_fixed_suite"], "arms": {arm: {key: data[key] for key in ["completed_valid_calls", "valid_retained", "defective_expected_veto", "choice_correct", "pair_correct", "reason_before_judgment_rows", "usage", "elapsed_seconds_sum"]} for arm, data in arms.items()}}, indent=2))


if __name__ == "__main__":
    main()
