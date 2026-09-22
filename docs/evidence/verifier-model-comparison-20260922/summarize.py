"""Offline paired decision/accounting summary; manual teaching audit is separate."""
from collections import Counter
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main():
    plan_path, capture_path = HERE / "plan.json", HERE / "capture.json"
    capture = json.loads(capture_path.read_text())
    assert hashlib.sha256(plan_path.read_bytes()).hexdigest() == capture["plan_sha256"]
    arms, paired = {}, {}
    for arm in ("sonnet", "opus"):
        calls = [call for call in capture["calls"] if call["arm"] == arm]
        items = [item for call in calls for item in call.get("assessment", {}).get("items", [])]
        usage = Counter()
        for call in calls:
            usage.update(call.get("response", {}).get("usage", {}))
        arms[arm] = {
            "planned_calls": 2, "attempted_calls": len(calls), "planned_items": 6,
            "structurally_assessed_items": len(items), "matching_dispositions": sum(item["matching_disposition"] for item in items),
            "bad_items_correctly_rejected_of_2": sum(not item["gold_eligible"] and not item["valid"] for item in items),
            "valid_items_retained_of_4": sum(item["gold_eligible"] and item["valid"] for item in items),
            "valid_items_with_exact_key_of_4": sum(item.get("exact_gold_key", False) for item in items),
            "valid_controls_meeting_separate_difficulty2_floor_of_4": sum(item["gold_eligible"] and item.get("difficulty", 0) >= 2 for item in items),
            "positive_local_validation_pass": sum(item.get("local_positive_validation_pass", False) for item in items),
            "provider_errors": [call.get("provider_error_type") for call in calls if call.get("provider_error_type")],
            "validation_errors": [call.get("validation_error_type") for call in calls if call.get("validation_error_type")],
            "stop_reasons": [call.get("response", {}).get("stopReason") for call in calls],
            "elapsed_seconds": round(sum(call["elapsed_seconds"] for call in calls), 3),
            "maximum_call_seconds": max((call["elapsed_seconds"] for call in calls), default=None),
            "reported_usage": usage, "usage_unknown_calls": sum("usage" not in call.get("response", {}) for call in calls),
        }
        for item in items:
            paired.setdefault(item["case_id"], {})[arm] = item
    result = {"plan_sha256": capture["plan_sha256"], "capture_sha256": hashlib.sha256(capture_path.read_bytes()).hexdigest(),
              "status": capture["status"], "planned_calls": 4, "actual_calls": len(capture["calls"]),
              "planned_item_assessments": 12, "arms": arms, "paired": paired,
              "manual_audit": "Pending separate independent audit of every generated main and choice explanation. Correct keys or negative dispositions alone do not establish sound teaching or a specific defect rationale.",
              "formal_qualification": ("failed operational criterion" if capture.get("stop_reason") else
                                       "failed decision criterion" if any(arm["matching_dispositions"] != 6 for arm in arms.values()) else
                                       "pending independent semantic audit"),
              "limitation": "Six reused diagnostic cases in two3-item batches per model; no new solver/author calls or worker yield measurement. No general quality, determinism, diversity or latency distribution claim."}
    audit_path = HERE / "independent-output-audit.json"
    if audit_path.exists():
        audit = json.loads(audit_path.read_text())
        result["independent_output_audit_sha256"] = hashlib.sha256(audit_path.read_bytes()).hexdigest()
        result["independent_content_summary"] = audit["summary"]
        result["manual_audit"] = "Completed independently for all12 reviews and60 explanation strings; see independent-output-audit.json."
        result["formal_qualification"] = "failed for both models"
    (HERE / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"status": result["status"], "actual_calls": result["actual_calls"], "arms": arms}, indent=2))


if __name__ == "__main__":
    main()
