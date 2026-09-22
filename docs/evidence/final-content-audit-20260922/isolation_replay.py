"""Read-only replay of the frozen singleton diagnostic, with complete denominator."""

import copy
import json
from unittest.mock import patch

import isolation_probe as probe


def main():
    original = probe.original
    plan = json.loads(probe.PLAN.read_text())
    capture = json.loads(probe.CAPTURE.read_text())
    assert probe.build_plan() == plan
    assert original.sha(probe.PLAN.read_bytes()) == capture["plan_sha256"]
    checks = []
    with patch.object(original.boto3, "client", side_effect=AssertionError("No network")), patch.object(
        probe.subprocess, "check_output", side_effect=AssertionError("No credentials")
    ):
        for row in capture["calls"]:
            call = plan["calls"][row["sequence"]]
            assert row["request"] == call["provider_request"]
            assert original.sha(original.canonical(row["request"])) == call["request_sha256"]
            result = {"sequence": row["sequence"], "source_slot": call["source_slot"], "exact_request": True}
            if "assessment" in row:
                assert probe.assess(copy.deepcopy(row["response"]), call, plan) == row["assessment"]
                result["strict_native_and_immutable_admission_replay"] = True
            elif row.get("validation_error_type"):
                try:
                    probe.assess(row["response"], call, plan)
                except Exception as error:
                    assert type(error).__name__ == row["validation_error_type"]
                    result["same_validation_failure"] = True
                else:
                    raise AssertionError("Saved failure was not reproduced.")
            else:
                result["preserved_provider_or_stop_failure"] = True
            assert "reasoningContent" not in json.dumps(row.get("response", {}))
            checks.append(result)
    items = [item for row in capture["calls"] for item in row.get("assessment", {}).get("items", [])]
    usages = [row["response"]["usage"] for row in capture["calls"] if "usage" in row.get("response", {})]
    result = {"capture_sha256": original.sha(probe.CAPTURE.read_bytes()), "plan_sha256": capture["plan_sha256"],
              "provider_calls_in_replay": 0, "all_pinned_original_and_new_sources_inputs_dependencies_unchanged": True,
              "source_plan_sha256": plan["source_plan_sha256"], "checks": checks,
              "status": capture["status"], "planned_calls": 6, "attempted_calls": len(capture["calls"]),
              "unattempted_calls": 6 - len(capture["calls"]), "planned_items": 6, "strict_assessed_items": len(items),
              "failed_or_unattempted_items": 6 - len(items),
              "exact_dispositions": sum(item["matching_disposition"] for item in items),
              "sound_accepted_of_3": sum(item["verdict"] == item["gold_verdict"] == "accepted" for item in items),
              "defective_rejected_of_3": sum(item["verdict"] == item["gold_verdict"] == "rejected" for item in items),
              "all_accepted_content_unchanged": all(item.get("accepted_content_exactly_unchanged", True) for item in items),
              "reason_before_verdict_count": sum(row.get("assessment", {}).get("actual_reason_before_verdict_rows", 0) for row in capture["calls"]),
              "reason_quality_requires_independent_audit": True,
              "input_tokens_known": sum(usage["inputTokens"] for usage in usages),
              "output_tokens_known": sum(usage["outputTokens"] for usage in usages),
              "usage_unknown_calls": len(capture["calls"]) - len(usages),
              "latency_seconds_sum": round(sum(row["elapsed_seconds"] for row in capture["calls"]), 3),
              "latency_seconds_max": max((row["elapsed_seconds"] for row in capture["calls"]), default=None),
              "reasoning_blocks_omitted": sum(row.get("reasoning_blocks_omitted", 0) for row in capture["calls"]),
              "case_results": items}
    audit_path = probe.HERE / "independent-isolation-output-audit.json"
    if audit_path.exists():
        result["independent_audit_sha256"] = original.sha(audit_path.read_bytes())
    original.save(probe.HERE / "isolation-replay-summary.json", result)
    print(json.dumps({key: value for key, value in result.items() if key != "case_results"}))


if __name__ == "__main__":
    main()
