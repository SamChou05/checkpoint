"""No-network reproduction of actual application admission from frozen final JSON."""
import copy
import importlib.util
import json
import os
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("adaptive_pipeline", HERE / "adaptive_pipeline_probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

from botocore.exceptions import ReadTimeoutError  # noqa: E402


def run():
    plan_path = HERE / "pipeline-adaptive-plan.json"
    capture_path = HERE / "pipeline-adaptive-capture.json"
    plan, capture = json.loads(plan_path.read_text()), json.loads(capture_path.read_text())
    assert probe.sources() == plan["source_sha256"], "Replay requires the exact frozen runtime sources."
    assert capture["plan_sha256"] == probe.old.sha(plan_path.read_bytes())
    preflight = probe.preflight()
    results = []
    for job in capture["jobs"]:
        calls = [call for call in capture["calls"] if call["job"] == job["index"]]
        position = 0

        class ReplayClient:
            meta = SimpleNamespace(config=SimpleNamespace(connect_timeout=3, read_timeout=75))

            def converse(self, **request):
                nonlocal position
                assert position < len(calls), "Unexpected extra application dispatch."
                expected = calls[position]
                position += 1
                assert request == expected["request"], "Application request changed."
                if expected.get("provider_error_type") == "ReadTimeoutError":
                    raise ReadTimeoutError(endpoint_url="https://offline-replay.invalid")
                assert expected["outcome"] == "end_turn"
                return copy.deepcopy(expected["response"])

        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        budget = probe.runtime.ProviderCallBudget(6)
        accepted, error_type = [], None
        with patch.dict(os.environ, plan["environment"]), patch.object(probe.runtime, "_bedrock_client", return_value=ReplayClient()):
            try:
                accepted = probe.runtime._generate_sanitized_questions(
                    copy.deepcopy(plan["jobs"][job["index"]]["request"]), None, budget, metrics)
            except Exception as error:
                error_type = type(error).__name__
        assert position == len(calls)
        assert accepted == job.get("accepted", [])
        assert error_type == job.get("error_type")
        assert metrics.get("QuestionQuality") == job["metrics"].get("QuestionQuality")
        assert budget.calls == job["provider_budget_calls"]
        results.append({"job": job["index"], "requests_byte_equivalent_as_objects": position,
                        "exact_admitted_rows_equal": True, "quality_diagnostics_equal": True,
                        "provider_error_type_equal": True, "provider_calls_equal": budget.calls})
    result = {"plan_sha256": probe.old.sha(plan_path.read_bytes()), "capture_sha256": probe.old.sha(capture_path.read_bytes()),
              "network_calls": 0, "sources_match_frozen_plan": True, "offline_deadline_and_ceiling_tests": preflight,
              "jobs": results, "all_replay_checks_pass": True,
              "limitation": "Replays retained final JSON, usage and the recorded timeout type; provider reasoning blocks were intentionally omitted. It verifies deterministic application admission and exact request construction, not new model correctness."}
    probe.old.save(HERE / "pipeline-adaptive-replay-checks.json", result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    run()
