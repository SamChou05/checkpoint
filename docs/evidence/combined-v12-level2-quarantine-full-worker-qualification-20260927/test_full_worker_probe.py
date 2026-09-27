"""Socket-free regression tests for the frozen v12 full-worker trial."""

import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SERVICE = HERE.parents[2] / "backend/bedrock-question-service"
sys.path[:0] = [str(SERVICE), str(SERVICE / "tests")]
SPEC = importlib.util.spec_from_file_location("combined_v12_full_worker_probe", HERE / "full_worker_probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)

from agreement_task_constructor import prepare_mapped_agreement_rows  # noqa: E402
from test_native_pipeline import (  # noqa: E402
    ScriptedNativeClient, authored_issue_flags, solver_map, solver_record, task_data,
)


def author_object():
    return {"questions": {
        "0": {"family": "fraction_product_complement", "a": 4, "b": 6},
        "1": {"family": "bounded_quadratic_exclusion_count", "a": 6, "b": 8},
        "2": {"family": "bounded_centered_square_count", "a": 4, "b": 7},
        "3": {"kind": "agreement_pair_v1", "scene": "partitive_paint", "order": "plural_first"},
        "4": {"kind": "agreement_pair_v1", "scene": "select_archive", "order": "singular_first"},
    }}


class FakeNetwork:
    def __init__(self, plan, agreement_difficulty=2):
        with patch.dict(os.environ, probe.ENVIRONMENT, clear=True):
            contract = probe.mapped_contract(plan["jobs"][0]["request"])
        adapted = json.loads(probe.native.adapt_native_response(json.dumps(author_object()), contract))
        prepared, math, english, failures = prepare_mapped_agreement_rows(adapted, contract)
        assert failures == [] and set(math) == {0, 1, 2} and set(english) == {3, 4}
        selected = prepared[4]
        selected_task = json.loads(english[4].task_json)
        assert json.loads(english[4].source_task_json)["scene"] == "select_archive"
        assert selected_task == {"kind": "agreement_pair_v1", "scene": "compound_clerks",
                                 "order": "plural_first"}
        assert not selected_task["scene"].startswith("select_")
        assert selected["prompt"].count("___") == 2
        assert len(set(selected["choices"])) == 4
        assert len(selected["explanation"]) <= 420
        assert selected["explanation"].endswith("Therefore the ordered pair is keeps; review.")
        known = {row["prompt"]: row["expectedAnswer"] for row in prepared}

        def solver(request):
            items = task_data(request, "question_solution_json")["items"]
            assert len(items) == 2
            assert {item["prompt"] for item in items} == {prepared[3]["prompt"], prepared[4]["prompt"]}
            return solver_map(*(solver_record(item, known[item["prompt"]]) for item in items))

        def reviewer(request):
            items = task_data(request, "question_review_json")["items"]
            assert len(items) == 5
            return {"reviews": {str(item["index"]): {
                "valid": True, "answer": known[item["prompt"]],
                "difficulty": agreement_difficulty if item["index"] in (3, 4) else 2,
                "explanationSupport": "supported", "issueFlags": authored_issue_flags(),
            } for item in items}}

        self.scripted = ScriptedNativeClient(
            (contract.transport_name, author_object()),
            ("complete_choice_solver_v5_n2", solver),
            ("authored_solution_reviewer_v3_n5", reviewer),
        )

    @property
    def calls(self):
        return self.scripted.calls

    def client(self, *args, **kwargs):
        return SimpleNamespace(
            meta=SimpleNamespace(config=kwargs["config"], endpoint_url=probe.ENDPOINT,
                                 region_name="us-east-1"),
            converse=self.scripted.converse,
        )


class CombinedV12FullWorkerTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, "connect",
                                       side_effect=AssertionError("No socket in offline test")))
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "capture.json"
        self.plan = probe.build_plan()

    def test_source_schema_wire_and_trial_limits(self):
        pins = self.plan["candidate_pins"]
        self.assertEqual(self.plan["source_commit"], probe.SOURCE_COMMIT)
        self.assertEqual(self.plan["trial_id"], probe.TRIAL_ID)
        self.assertEqual(self.plan["predecessor_hashes"]["v12_author_capture"],
                         probe.V12_AUTHOR_CAPTURE_SHA256)
        self.assertEqual(self.plan["predecessor_hashes"]["previous_v12_worker_capture"],
                         probe.PREVIOUS_V12_WORKER_CAPTURE_SHA256)
        self.assertEqual(self.plan["predecessor_hashes"]["previous_v12_worker_results"],
                         probe.PREVIOUS_V12_WORKER_RESULTS_SHA256)
        self.assertEqual(self.plan["predecessor_hashes"]["previous_v12_worker_returned_questions"], 4)
        self.assertEqual(self.plan["predecessor_hashes"]["second_v12_worker_capture"],
                         probe.SECOND_V12_WORKER_CAPTURE_SHA256)
        self.assertEqual(self.plan["predecessor_hashes"]["second_v12_worker_results"],
                         probe.SECOND_V12_WORKER_RESULTS_SHA256)
        self.assertEqual(self.plan["predecessor_hashes"]["second_v12_worker_returned_questions"], 4)
        self.assertEqual(self.plan["predecessor_hashes"]["immediate_predecessor_capture"],
                         probe.IMMEDIATE_PREDECESSOR_CAPTURE_SHA256)
        self.assertEqual(self.plan["predecessor_hashes"]["immediate_predecessor_results"],
                         probe.IMMEDIATE_PREDECESSOR_RESULTS_SHA256)
        self.assertEqual(self.plan["predecessor_hashes"]["immediate_predecessor_returned_questions"], 4)
        self.assertEqual(pins["native_schema_bytes"], 2357)
        self.assertEqual(pins["native_schema_sha256"],
                         "495db717d6b3fd6cc5272cdb289c7d77d9ca2e275b7c1d3f0cb856c1a18b6934")
        self.assertEqual(pins["exact_author_wire_sha256"],
                         "0317c2b75115c309232c02e6eddcedd230461fc63f5d18da7312502868092a0a")
        self.assertEqual(self.plan["limits"]["calls_per_job"], 6)
        self.assertEqual(self.plan["limits"]["seconds_per_job"], 240)
        self.assertFalse(self.plan["limits"]["retry_fallback_topup"])
        self.assertFalse(self.plan["limits"]["bank_queue_deploy_writes"])
        self.assertEqual(len(self.plan["jobs"]), 1)
        self.assertEqual(self.plan["jobs"][0]["request"]["targetCount"], 5)

    def test_real_worker_path_fake_provider_three_calls_and_proofs(self):
        network = FakeNetwork(self.plan)
        capture = probe.new_capture(self.plan)
        probe.run_jobs(self.plan, capture, self.path, network.client,
                       lambda: probe.check_plan(self.plan))
        self.assertEqual(capture["status"], "completed_pending_review")
        self.assertEqual(len(network.calls), 3)
        self.assertEqual(capture["summary"]["returned_questions"], 5)
        self.assertEqual([item["verificationPolicyRevision"] for item in capture["jobs"][0]["returned"]],
                         [8, 8, 8, 10, 10])
        self.assertEqual(capture["jobs"][0]["returned_slot_ordinals"], list(range(5)))
        self.assertEqual([item["status"] for item in capture["original_jobs"][0]["slots"]],
                         ["returned"] * 5)
        self.assertEqual(len(capture["reservations"]), 3)
        self.assertEqual(len(capture["jobs"][0]["passes"][0]["compiled"]), 3)
        self.assertEqual(len(capture["jobs"][0]["passes"][0]["agreement"]), 2)
        selected = capture["jobs"][0]["passes"][0]["agreement"][1]["task"]
        self.assertEqual(selected, {"kind": "agreement_pair_v1",
                                    "scene": "compound_clerks", "order": "plural_first"})
        self.assertEqual(capture["jobs"][0]["returned"][4]["difficulty"], 2)
        self.assertEqual(json.loads(self.path.read_text())["summary"]["returned_questions"], 5)
        with self.assertRaises(probe.IntegrityError):
            probe.run_jobs(self.plan, capture, self.path, network.client,
                           lambda: probe.check_plan(self.plan))
        self.assertEqual(len(network.calls), 3)

    def test_invalid_author_cannot_retry_or_top_up(self):
        network = FakeNetwork(self.plan)
        original = network.scripted.converse

        def corrupt_first(**request):
            response = original(**request)
            if len(network.calls) == 1:
                response["output"]["message"]["content"][0]["text"] = '{"questions":{}}'
            return response

        network.scripted.converse = corrupt_first
        capture = probe.new_capture(self.plan)
        probe.run_jobs(self.plan, capture, self.path, network.client,
                       lambda: probe.check_plan(self.plan))
        self.assertEqual(len(network.calls), 1)
        self.assertEqual(len(capture["reservations"]), 1)
        self.assertEqual(capture["summary"]["returned_questions"], 0)
        self.assertEqual(capture["jobs"][0]["status"], "failed")

    def test_agreement_reviewer_difficulty_four_vetoes_original_slots(self):
        network = FakeNetwork(self.plan, agreement_difficulty=4)
        capture = probe.new_capture(self.plan)
        probe.run_jobs(self.plan, capture, self.path, network.client,
                       lambda: probe.check_plan(self.plan))
        self.assertEqual(capture["summary"]["returned_questions"], 3)
        self.assertEqual(len(network.calls), 3)

    def test_credential_expiry_preflight_and_execute_deadline(self):
        now = datetime.now(timezone.utc)
        with self.assertRaisesRegex(probe.IntegrityError, "expire"):
            probe.validate_credential_lifetime(json.dumps({
                "Expiration": (now + timedelta(seconds=299)).isoformat(),
            }).encode(), now=now)
        self.assertEqual(probe.validate_credential_lifetime(json.dumps({
            "Expiration": (now + timedelta(seconds=301)).isoformat(),
        }).encode(), now=now), now + timedelta(seconds=301))
        current = [0.0]
        deadline = probe.Deadline(lambda: current[0])
        current[0] = 241.0
        network = FakeNetwork(self.plan)
        capture = probe.new_capture(self.plan)
        with self.assertRaises(probe.IntegrityError):
            probe.run_jobs(self.plan, capture, self.path, network.client,
                           lambda: probe.check_plan(self.plan),
                           clock=lambda: current[0], deadline=deadline)
        self.assertEqual(network.calls, [])
        self.assertEqual(capture["reservations"], [])

    def test_submicrosecond_deadline_overrun_revokes_return_credit(self):
        current = [0.0]
        deadline = probe.Deadline(lambda: current[0])
        current[0] = 240.0000001
        capture = probe.new_capture(self.plan)
        probe.finish(capture)
        capture["summary"]["returned_questions"] = 5
        for slot in capture["original_jobs"][0]["slots"]:
            slot["status"] = "returned"
        probe.seal_execute_timing(capture, deadline)
        self.assertFalse(capture["summary"]["within_execute_deadline"])
        self.assertEqual(capture["summary"]["returned_questions"], 0)
        self.assertEqual([slot["status"] for slot in capture["original_jobs"][0]["slots"]],
                         ["late_uncredited"] * 5)

    def test_capture_rejects_decoded_credential_echo(self):
        response = {"output": {"message": {"content": [{"text":
                    '{"visible":"ok","secret":"token-marker"}'}]}}}
        self.assertTrue(probe.decoded_credential_echo(response, ("token-marker",)))
        self.assertFalse(probe.decoded_credential_echo(response, ("other-token",)))

    def test_hard_watchdog_interrupts_credential_setup_before_sts(self):
        plan_file = Path(self.temp.name) / "watchdog-plan.json"
        plan_file.write_text(json.dumps({**self.plan, "state": "frozen"}))
        capture_path = Path(self.temp.name) / "watchdog-capture.json"
        with patch.object(probe, "PLAN", plan_file), \
                patch.object(probe, "CAPTURE", capture_path), \
                patch.object(probe, "EXECUTE_SECONDS", 0.05), \
                patch.object(probe, "require_review_go"), \
                patch.object(probe, "check_execution_runtime"), \
                patch.object(probe, "check_launch_record"), \
                patch.object(probe, "default_profile_session",
                             side_effect=lambda: time.sleep(0.2)), \
                patch.object(probe, "verify_account_identity") as identity:
            result = probe.execute(probe.file_hash(plan_file))
        identity.assert_not_called()
        self.assertEqual(result["status"], "deadline_exceeded")
        self.assertFalse(result["summary"]["within_execute_deadline"])
        self.assertEqual(json.loads(capture_path.read_text())["calls"], [])

    def test_launch_precheck_requires_review_before_aws(self):
        plan_file = Path(self.temp.name) / "precheck-plan.json"
        plan_file.write_text(json.dumps({**self.plan, "state": "frozen"}))
        with patch.object(probe, "PLAN", plan_file), \
                patch.object(probe, "REVIEW_LOCK", Path(self.temp.name) / "missing-review.json"), \
                patch.object(probe, "check_default_profile") as profile, \
                patch.object(probe, "checked_sts_client") as sts:
            with self.assertRaises(probe.IntegrityError):
                probe.launch_precheck()
        profile.assert_not_called()
        sts.assert_not_called()

    def test_plan_drift_review_lock_and_runtime_fail_closed(self):
        tampered = copy.deepcopy(self.plan)
        tampered["environment"]["BEDROCK_MODEL_ID"] = "changed"
        with self.assertRaises(probe.IntegrityError):
            probe.check_plan(tampered)
        lock = Path(self.temp.name) / "review-approval.json"
        with patch.object(probe, "REVIEW_LOCK", lock):
            with self.assertRaises(probe.IntegrityError):
                probe.require_review_go("f" * 64)
            lock.write_text(json.dumps({"plan_sha256": "f" * 64,
                "harness_sha256": probe.IMPORTED_HARNESS_HASH,
                "source_commit": probe.SOURCE_COMMIT,
                "root_go": True, "independent_go": True}))
            probe.require_review_go("f" * 64)
            with self.assertRaises(probe.IntegrityError):
                probe.require_review_go("e" * 64)
        with patch.object(probe.boto3, "__version__", "wrong"):
            with self.assertRaises(probe.IntegrityError):
                probe.check_execution_runtime()


if __name__ == "__main__":
    unittest.main()
