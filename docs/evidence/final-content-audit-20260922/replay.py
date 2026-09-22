"""Replay exact frozen requests and strict content admission without network."""

import copy
import json
from pathlib import Path
from unittest.mock import patch

import final_audit_probe as probe


def main():
    plan = json.loads(probe.PLAN.read_text())
    capture = json.loads(probe.CAPTURE.read_text())
    assert probe.build_plan() == plan
    assert probe.sha(probe.PLAN.read_bytes()) == capture["plan_sha256"]
    checks = []
    with patch.object(probe.boto3, "client", side_effect=AssertionError("No network")), patch.object(
        probe.subprocess, "check_output", side_effect=AssertionError("No credentials")
    ):
        for row in capture["calls"]:
            call = plan["calls"][row["sequence"]]
            assert row["request"] == call["provider_request"]
            assert probe.sha(probe.canonical(row["request"])) == call["request_sha256"]
            result = {"sequence": row["sequence"], "exact_request": True}
            if "assessment" in row:
                response = copy.deepcopy(row["response"])
                assert probe.assess(response, call, plan) == row["assessment"]
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
    output = {"capture_sha256": probe.sha(probe.CAPTURE.read_bytes()), "plan_sha256": capture["plan_sha256"],
              "provider_calls": 0, "all_pinned_sources_inputs_and_dependencies_unchanged": True,
              "checks": checks, "planned_calls": len(plan["calls"]), "attempted_calls": len(capture["calls"]),
              "unattempted_calls": len(plan["calls"]) - len(capture["calls"])}
    probe.save(Path(__file__).with_name("replay-checks.json"), output)
    print(json.dumps(output))


if __name__ == "__main__":
    main()
