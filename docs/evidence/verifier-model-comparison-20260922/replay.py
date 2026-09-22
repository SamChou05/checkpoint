"""No-network frozen request and native/local assessment replay."""
import copy
import importlib.util
import json
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("verifier_replay_probe", HERE / "verifier_model_probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def main():
    plan = json.loads(probe.PLAN.read_text())
    capture = json.loads(probe.CAPTURE.read_text())
    packet = json.loads((HERE / "controls-draft.json").read_text())
    assert probe.sha(probe.PLAN.read_bytes()) == capture["plan_sha256"]
    assert probe.sources() == plan["source_sha256"]
    rebuilt = probe.build_plan()
    rebuilt["source_revision"] = plan["source_revision"]
    assert rebuilt == plan
    position = 0

    class ReplayClient:
        def converse(self, **request):
            nonlocal position
            expected = capture["calls"][position]
            position += 1
            assert request == expected["request"]
            return copy.deepcopy(expected["response"])

    replayed = {"calls": []}
    with patch.object(probe, "save"), patch("builtins.print"):
        probe.run_calls(ReplayClient(), plan, packet, replayed, Path("/unused"))
    assert position == len(capture["calls"]) == 4
    for observed, expected in zip(replayed["calls"], capture["calls"], strict=True):
        assert observed["request"] == expected["request"]
        assert observed["assessment"] == expected["assessment"]
    config = probe.Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1})
    assert config.connect_timeout == 3 and config.read_timeout == 75 and config.retries["total_max_attempts"] == 1
    result = {"plan_sha256": capture["plan_sha256"], "capture_sha256": probe.sha(probe.CAPTURE.read_bytes()),
              "network_calls": 0, "sources_match_frozen_plan": True, "exact_plan_rebuilt": True,
              "exact_requests_and_assessments_replayed": 4, "model_id_only_paired_request_delta": True,
              "three_second_connect_75_second_read_sdk_one_attempt": True,
              "native_and_exact_local_coverage_valid_responses": 4,
              "original_gold_packet_unchanged": True, "scope": "Deterministic application assessment replay; no new evidence of semantic correctness."}
    probe.save(HERE / "replay-checks.json", result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
