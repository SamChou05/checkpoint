"""Mechanical stopped-trial accounting without repairing duplicate identities."""
from collections import Counter
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main():
    plan_path, capture_path = HERE / "plan.json", HERE / "capture.json"
    capture = json.loads(capture_path.read_text())
    assert hashlib.sha256(plan_path.read_bytes()).hexdigest() == capture["plan_sha256"]
    arms, calls = {}, []
    for arm in ("baseline", "candidate"):
        selected = [call for call in capture["calls"] if call["arm"] == arm]
        items = [item for call in selected for item in call.get("assessment", {}).get("items", [])]
        usage = Counter()
        for call in selected:
            usage.update(call.get("response", {}).get("usage", {}))
        arms[arm] = {"planned_calls": 2, "attempted_calls": len(selected), "planned_logical_items": 12,
                     "strictly_assessed_items": len(items), "matching_assessed_dispositions": sum(item["matching_disposition"] for item in items),
                     "planned_valid_items": 8, "planned_bad_items": 4,
                     "assessed_valid_exact_keys": sum(item.get("exact_gold_key", False) for item in items),
                     "assessed_bad_correct_rejections": sum(not item["gold_eligible"] and not item["valid"] for item in items),
                     "unattempted_prospective_items": 6, "elapsed_seconds": round(sum(call["elapsed_seconds"] for call in selected), 3),
                     "reported_usage": usage, "strict_candidate_semantic_credit": "none: failed entire envelope" if arm == "candidate" else "independent manual audit remains separate"}
    for call in capture["calls"]:
        raw = json.loads("".join(block["text"] for block in call["response"]["output"]["message"]["content"] if "text" in block))
        rows = raw["reviews"]
        indexes = [row["index"] for row in rows]
        calls.append({"sequence": call["sequence"], "batch": call["batch"], "arm": call["arm"],
                      "raw_rows": len(rows), "raw_indexes": indexes, "raw_positive_reviews": sum(row["valid"] for row in rows),
                      "raw_main_and_choice_strings": sum(1 + len(row["choiceFeedback"]) for row in rows),
                      "duplicate_indexes": [index for index, count in Counter(indexes).items() if count > 1],
                      "strict_batch_coverage_pass": "assessment" in call,
                      "validation_error_type": call.get("validation_error_type"), "stop_reason": call["response"]["stopReason"]})
    result = {"plan_sha256": capture["plan_sha256"], "capture_sha256": hashlib.sha256(capture_path.read_bytes()).hexdigest(),
              "status": capture["status"], "stop_reason": capture.get("stop_reason"), "planned_calls": 4,
              "actual_calls": len(capture["calls"]), "unattempted_calls": 4 - len(capture["calls"]),
              "planned_logical_item_reviews": 24, "raw_reviews_returned": sum(call["raw_rows"] for call in calls),
              "raw_explanation_strings": sum(call["raw_main_and_choice_strings"] for call in calls),
              "arms": arms, "calls": calls, "formal_qualification": "failed; no prompt promotion",
              "no_salvage": "The seven-row candidate response remains a failed six-item envelope. No duplicate dropping, reindexing, retry or repaired batch score is supplied.",
              "limits": "Fresh cases were never dispatched. Candidate raw content may be audited diagnostically but receives no valid-stage or complete-trial semantic credit. No inference that the prompt caused the duplicate."}
    audit_path = HERE / "independent-output-audit.json"
    if audit_path.exists():
        result["independent_output_audit_sha256"] = hashlib.sha256(audit_path.read_bytes()).hexdigest()
    (HERE / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({key: result[key] for key in ("actual_calls", "unattempted_calls", "raw_reviews_returned", "formal_qualification")}, indent=2))


if __name__ == "__main__":
    main()
