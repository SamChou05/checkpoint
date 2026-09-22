"""Mechanical denominators; human reason audit remains a separate requirement."""

import json

import final_audit_probe as probe


def main():
    plan = json.loads(probe.PLAN.read_text())
    capture = json.loads(probe.CAPTURE.read_text())
    result = {"plan_sha256": probe.sha(probe.PLAN.read_bytes()), "capture_sha256": probe.sha(probe.CAPTURE.read_bytes()),
              "status": capture["status"], "planned_calls": 6, "attempted_calls": len(capture["calls"]),
              "unattempted_calls": 6 - len(capture["calls"]), "planned_item_reviews": 36, "arms": {}}
    for arm in ("disabled", "adaptive"):
        calls = [row for row in capture["calls"] if row["arm"] == arm]
        items = [item for row in calls for item in row.get("assessment", {}).get("items", [])]
        usages = [row["response"]["usage"] for row in calls if "usage" in row.get("response", {})]
        decisions = sum(item["matching_disposition"] for item in items)
        retained = sum(item["gold_verdict"] == item["verdict"] == "accepted" for item in items)
        rejected = sum(item["gold_verdict"] == item["verdict"] == "rejected" for item in items)
        result["arms"][arm] = {
            "planned_calls": 3, "attempted_calls": len(calls), "unattempted_calls": 3 - len(calls),
            "strict_complete_batches": sum("assessment" in row for row in calls), "planned_items": 18,
            "assessed_items": len(items), "failed_or_unattempted_items": 18 - len(items),
            "correct_dispositions": decisions, "sound_retained_of_9": retained, "bad_rejected_of_9": rejected,
            "all_dispositions_pass": len(items) == decisions == 18,
            "reason_quality": "Requires separate independent manual audit; no mechanical semantic pass assigned.",
            "accepted_original_content_unchanged": all(item.get("accepted_content_exactly_unchanged", True) for item in items),
            "actual_reason_before_verdict_rows": sum(row.get("assessment", {}).get("actual_reason_before_verdict_rows", 0) for row in calls),
            "input_tokens_known": sum(usage["inputTokens"] for usage in usages),
            "output_tokens_known": sum(usage["outputTokens"] for usage in usages),
            "usage_unknown_calls": len(calls) - len(usages),
            "latency_seconds_sum": round(sum(row["elapsed_seconds"] for row in calls), 3),
            "latency_seconds_max": max((row["elapsed_seconds"] for row in calls), default=None),
            "reasoning_blocks_omitted": sum(row.get("reasoning_blocks_omitted", 0) for row in calls),
            "cases": items,
        }
    audit_path = probe.HERE / "independent-output-audit.json"
    if audit_path.exists():
        audit = json.loads(audit_path.read_text())
        assert audit["sources"]["capture.json"] == result["capture_sha256"]
        result["independent_audit_sha256"] = probe.sha(audit_path.read_bytes())
        result["independent_arm_summary"] = audit["arm_summary"]
    assert len(plan["calls"]) == 6
    probe.save(probe.HERE / "summary.json", result)
    print(json.dumps({key: value for key, value in result.items() if key != "arms"}))
    for arm, data in result["arms"].items():
        print(json.dumps({"arm": arm, **{key: value for key, value in data.items() if key != "cases"}}))


if __name__ == "__main__":
    main()
