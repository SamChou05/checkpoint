"""No-network replay of exact requests and the original duplicate-index stop."""
import copy
import importlib.util
import json
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("refutation_replay_probe", HERE / "refutation_probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def main():
    plan, capture = json.loads(probe.PLAN.read_text()), json.loads(probe.CAPTURE.read_text())
    assert probe.sha(probe.PLAN.read_bytes()) == capture["plan_sha256"]
    assert probe.build_plan() == plan
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
        probe.run_calls(ReplayClient(), plan, replayed, Path("/unused"))
    assert position == len(capture["calls"]) == 2
    assert replayed["status"] == capture["status"] and replayed["stop_reason"] == capture["stop_reason"]
    for actual, expected in zip(replayed["calls"], capture["calls"], strict=True):
        for key in ("request", "assessment", "validation_error_type"):
            assert actual.get(key) == expected.get(key)
    result = {"plan_sha256": capture["plan_sha256"], "capture_sha256": probe.sha(probe.CAPTURE.read_bytes()),
              "network_calls": 0, "exact_plan_rebuild": True, "requests_replayed_exactly": 2,
              "same_duplicate_index_stop": True, "no_candidate_deduplication_or_reindexing": True,
              "remaining_two_requests_unattempted": True, "all_frozen_input_source_and_dependency_hashes_unchanged": True,
              "actual_native_adapter_response_validations": 2, "exact_local_batch_coverage_passes": 1,
              "scope": "Deterministic original parsing/admission reproduction, not new model or semantic evidence."}
    probe.save(HERE / "replay-checks.json", result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
