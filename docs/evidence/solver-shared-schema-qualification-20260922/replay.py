"""No-network strict replay with distinct structural and semantic summaries."""

import json
from unittest.mock import patch

import solver_shared_schema_probe as probe


def main():
    plan = json.loads(probe.PLAN.read_text())
    capture = json.loads(probe.CAPTURE.read_text())
    assert probe.sha(probe.PLAN) == capture["plan_sha256"]
    assert probe.build_plan() == plan
    checks = []
    with patch.object(probe.boto3, "client", side_effect=AssertionError("No network")), patch.object(
        probe.subprocess, "check_output", side_effect=AssertionError("No credentials")
    ):
        for call in capture["calls"]:
            job = plan["jobs"][call["call_index"]]
            assert call["request"] == job["request"]
            assert probe.digest(call["request"]) == call["request_sha256"] == job["request_sha256"]
            check = {"call_index": call["call_index"], "exact_request": True}
            if "assessment" in call:
                assert probe.assess(call["raw"], job, plan) == call["assessment"]
                check["strict_assessment_reproduced"] = True
            elif call.get("validation_error_type"):
                try:
                    probe.assess(call["raw"], job, plan)
                except Exception as error:
                    assert type(error).__name__ == call["validation_error_type"]
                    check["same_validation_failure"] = True
                else:
                    raise AssertionError("Historical validation failure did not recur.")
            else:
                check["provider_or_stop_failure_preserved"] = True
            checks.append(check)
    valid = [call for call in capture["calls"] if "assessment" in call]
    assessments = [call["assessment"] for call in valid]
    semantic_rows = [row for assessment in assessments for row in assessment["semantic_rows"]]
    choices = [value for row in semantic_rows for value in row["choices"]]
    pairs = [value for row in semantic_rows for value in row["pairs"]]
    structure = {"planned_calls": 2, "attempted_calls": len(capture["calls"]), "valid_calls": len(valid),
                 "failed_calls": len(capture["calls"]) - len(valid), "unattempted_calls": 2 - len(capture["calls"]),
                 "identity_denominator": 10, "trusted_identities": sum(value["trusted_identities"] for value in assessments),
                 "choice_denominator": 40, "choice_slots": sum(value["choice_slots"] for value in assessments),
                 "pair_denominator": 60, "pair_slots": sum(value["pair_slots"] for value in assessments),
                 "all_exact_bindings_and_decoded_content": (all(value["exact_bindings_and_decoded_content"] for value in assessments) if assessments else None),
                 "all_end_turn_within75s": len(capture["calls"]) == 2 and all(call.get("stop_reason") == "end_turn" and call["elapsed_seconds"] <= 75 for call in capture["calls"]),
                 "all_sources_and_requests_unchanged": True}
    structural_pass = (structure["valid_calls"] == 2 and structure["trusted_identities"] == 10
                       and structure["choice_slots"] == 40 and structure["pair_slots"] == 60
                       and structure["all_exact_bindings_and_decoded_content"] and structure["all_end_turn_within75s"])
    semantic = {"item_denominator": 10, "scored_items": len(semantic_rows),
                "all_gold_labels_and_veto_agree": sum(row["all_gold_agrees"] for row in semantic_rows),
                "choice_judgments_correct": sum(value["judgment_agrees"] for value in choices), "choice_denominator": 40,
                "pair_relations_correct": sum(value["relation_agrees"] for value in pairs), "pair_denominator": 60,
                "eligible_gold_denominator": sum(case["expectedEligible"] for case in plan["controls"]),
                "eligible_retained": sum(row["expected_eligible"] and row["eligible"] for row in semantic_rows),
                "defective_gold_denominator": sum(not case["expectedEligible"] for case in plan["controls"]),
                "defective_excluded": sum(not row["expected_eligible"] and not row["eligible"] for row in semantic_rows),
                "uncertain_choices": sum(value["judgment"] == "uncertain" for value in choices),
                "uncertain_pairs": sum(value["relation"] == "uncertain" for value in pairs),
                "all_reasons_require_independent_audit": True,
                "these_scores_do_not_change_structural_qualification": True}
    usages = [call["usage"] for call in capture["calls"] if call.get("usage") is not None]
    result = {"plan_sha256": capture["plan_sha256"], "capture_sha256": probe.sha(probe.CAPTURE),
              "provider_calls_in_replay": 0, "checks": checks, "qualified_count_scope": 5,
              "native_contract": plan["native_contract"],
              "actual_output_order": {"choice_reason_before_judgment": sum(value["choice_reason_before_judgment_rows"] for value in assessments),
                                      "choice_denominator": 40,
                                      "pair_reason_before_relation": sum(value["pair_reason_before_relation_rows"] for value in assessments),
                                      "pair_denominator": 60}, "structurally_qualified_on_two_batches": structural_pass,
              "structural": structure, "semantic": semantic,
              "input_tokens_known": sum(usage["inputTokens"] for usage in usages),
              "output_tokens_known": sum(usage["outputTokens"] for usage in usages),
              "unknown_usage_calls": len(capture["calls"]) - len(usages),
              "total_elapsed_seconds": round(sum(call["elapsed_seconds"] for call in capture["calls"]), 3),
              "maximum_elapsed_seconds": max((call["elapsed_seconds"] for call in capture["calls"]), default=0),
              "reasoning_blocks_omitted": sum(call.get("reasoning_content_block_count", 0) for call in capture["calls"]),
              "semantic_rows": semantic_rows}
    audit = probe.HERE / "independent-output-audit.json"
    if audit.exists():
        result["independent_audit_sha256"] = probe.sha(audit)
    probe.save(probe.HERE / "replay-summary.json", result)
    print(json.dumps({key: value for key, value in result.items() if key != "semantic_rows"}))


if __name__ == "__main__":
    main()
