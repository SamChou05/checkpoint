"""Replay prior retained provider responses offline through the new verifier.

This is a regression diagnostic, never a fresh qualification result.
"""

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import socket
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PRIOR_CAPTURE = ROOT / "docs/evidence/mapped-agreement-full-worker-qualification-20260927/capture.json"
PRIOR_CAPTURE_SHA256 = "2bcb9b577d165b508debe70cf6d42b2cf749f006c03922650b9d154eab8ca251"
SPEC = importlib.util.spec_from_file_location("agreement_calibration_probe", HERE / "full_worker_probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


def replay():
    assert hashlib.sha256(PRIOR_CAPTURE.read_bytes()).hexdigest() == PRIOR_CAPTURE_SHA256
    previous = json.loads(PRIOR_CAPTURE.read_text())
    assert previous["summary"]["returned_questions"] == 3
    assert previous["jobs"][0]["returned_slot_ordinals"] == [0, 1, 2]
    prior_calls = previous["calls"]
    assert len(prior_calls) == 3 and all(call["dispatch_attempted"] is True for call in prior_calls)
    assert [call["stage"].split("_v")[0] for call in prior_calls] == [
        "question_author_constructed_mapped_agreement", "complete_choice_solver",
        "authored_solution_reviewer",
    ]
    plan = probe.build_plan()
    assert plan["candidate_source_revision"] == probe.SOURCE_COMMIT
    assert plan["candidate_pins"]["normalized_request_sha256"] == (
        "212cea7d53ddefe17fbe8f2459705b46b871793e62e0e58b56cc11e3626e63ae")
    capture = probe.new_capture(plan)

    class CapturedResponses:
        def __init__(self):
            self.index = 0

        def client(self, *args, **kwargs):
            assert args == ("bedrock-runtime",)
            assert set(kwargs) == {"region_name", "config"}
            return SimpleNamespace(
                meta=SimpleNamespace(config=kwargs["config"], endpoint_url=probe.ENDPOINT,
                                     region_name="us-east-1"),
                converse=self.converse,
            )

        def converse(self, **request):
            assert self.index < len(prior_calls), "New source requested an unplanned provider call"
            expected = prior_calls[self.index]
            assert request == expected["request"], "Provider wire changed during replay"
            self.index += 1
            return copy.deepcopy(expected["response"])

    network = CapturedResponses()
    with tempfile.TemporaryDirectory() as temporary:
        output = Path(temporary) / "capture.json"
        with patch.object(socket.socket, "connect", side_effect=AssertionError("Offline replay opened a socket")):
            probe.run_jobs(plan, capture, output, network.client, lambda: probe.check_plan(plan))
    assert network.index == 3
    assert capture["status"] == "completed_pending_review"
    assert capture["summary"]["returned_questions"] == 5
    assert capture["jobs"][0]["returned_slot_ordinals"] == [0, 1, 2, 3, 4]
    assert [row["verificationPolicyRevision"] for row in capture["jobs"][0]["returned"]] == [
        8, 8, 8, 10, 10,
    ]
    result = {"kind": "offline_regression_replay_not_fresh_qualification",
            "prior_capture_sha256": PRIOR_CAPTURE_SHA256,
            "prior_official_result": "3/5_original_slots_FAIL",
            "candidate_source_revision": probe.SOURCE_COMMIT,
            "replayed_original_slots": [0, 1, 2, 3, 4],
            "replayed_policy_revisions": [8, 8, 8, 10, 10],
            "captured_responses_reused": 3, "aws_provider_calls": 0,
            "result": "5/5_offline_regression_only"}
    assert result == json.loads((HERE / "offline-replay.json").read_text())
    return result


if __name__ == "__main__":
    print(json.dumps(replay(), indent=2, sort_keys=True))
