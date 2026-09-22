"""No-network verification of the single safe-error diagnostic capture."""

import json
from unittest.mock import patch

import error_diagnostic as diagnostic


def main():
    with patch.object(diagnostic.boto3, "client", side_effect=AssertionError("No network")), patch.object(
        diagnostic.subprocess, "check_output", side_effect=AssertionError("No credentials")
    ):
        plan = json.loads(diagnostic.PLAN.read_text())
        capture = json.loads(diagnostic.CAPTURE.read_text())
        assert diagnostic.build_plan() == plan
        assert capture["plan_sha256"] == diagnostic.sha(diagnostic.PLAN)
        assert capture["status"] == "completed_with_error_details"
        assert len(capture["calls"]) == plan["limits"]["maximum_calls"] == 1
        call = capture["calls"][0]
        assert set(call) == {"request_sha256", "dispatch_attempted", "safe_error", "elapsed_seconds"}
        assert call["dispatch_attempted"] is True
        assert call["request_sha256"] == plan["request_sha256"] == diagnostic.digest(plan["request"])
        assert 0 <= call["elapsed_seconds"] <= 75
        error = call["safe_error"]
        assert set(error) == {"Error", "HTTPStatus", "RequestId"}
        assert set(error["Error"]) == {"Code", "Message"}
        assert error["Error"]["Code"] == "ValidationException"
        assert error["HTTPStatus"] == 400
        for value, limit in ((error["Error"]["Code"], 128), (error["Error"]["Message"], 2000), (error["RequestId"], 128)):
            assert type(value) is str and 0 < len(value) <= limit
        assert "The compiled grammar is too large" in error["Error"]["Message"]
        original = json.loads((diagnostic.HERE / "capture.json").read_text())
        assert len(original["calls"]) == 1 and original["status"] == "stopped_after_failure"
        assert original["calls"][0]["request"] == plan["request"]
        result = {
            "diagnostic_plan_sha256": diagnostic.sha(diagnostic.PLAN),
            "diagnostic_capture_sha256": diagnostic.sha(diagnostic.CAPTURE),
            "original_plan_sha256": diagnostic.sha(diagnostic.HERE / "plan.json"),
            "original_capture_sha256": diagnostic.sha(diagnostic.HERE / "capture.json"),
            "provider_calls_in_replay": 0,
            "diagnostic_dispatches": 1,
            "exact_rejected_request_reused": True,
            "safe_error_fields_and_bounds_only": True,
            "model_output_or_reasoning_retained": False,
            "diagnostic_elapsed_seconds": call["elapsed_seconds"],
            "original_structurally_qualified_calls": 0,
            "original_planned_calls": 2,
            "original_failure_preserved": True,
        }
        diagnostic.save(diagnostic.HERE / "error-diagnostic-replay-summary.json", result)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
