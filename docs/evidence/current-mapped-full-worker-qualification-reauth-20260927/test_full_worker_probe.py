"""Socket-free tests of the pinned agreement calibration full-worker path."""

import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import socket
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("agreement_full_worker_probe", HERE / "full_worker_probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)

from agreement_task_constructor import COMPOUND_SCENE, prepare_mapped_agreement_rows  # noqa: E402
from test_native_pipeline import (  # noqa: E402
    ScriptedNativeClient, authored_issue_flags, solver_map, solver_record, task_data,
)
def author_object():
    return {"questions": {
        "0": {"family": "fraction_quotient", "a": 3, "b": 7},
        "1": {"family": "bounded_quadratic_equation", "a": 4, "b": 8},
        "2": {"family": "bounded_ratio_threshold", "a": 5, "b": 9},
        "3": {"kind": "agreement_pair_v1", "scene": "coach", "order": "singular_first"},
        "4": {"kind": "agreement_pair_v1", "scene": COMPOUND_SCENE, "order": "plural_first"},
    }}


class FakeNetwork:
    def __init__(self, plan, agreement_difficulty=2):
        with patch.dict(os.environ, probe.ENVIRONMENT, clear=True):
            contract = probe.mapped_contract(plan["jobs"][0]["request"])
        adapted = json.loads(probe.native.adapt_native_response(json.dumps(author_object()), contract))
        prepared, math, english, failures = prepare_mapped_agreement_rows(adapted, contract)
        assert failures == [] and set(math) == {0, 1, 2} and set(english) == {3, 4}
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


class AgreementWorkerProbeTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, "connect", side_effect=AssertionError("No socket in offline test")))
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "capture.json"
        self.plan = probe.build_plan()

    def test_schema_sdk_and_exact_source_pins(self):
        pins = self.plan["candidate_pins"]
        self.assertEqual(self.plan["trial_id"], probe.TRIAL_ID)
        self.assertEqual(self.plan["previous_trial_audit_sha256"], probe.PREVIOUS_AUDIT_SHA256)
        self.assertEqual(pins["native_schema_bytes"], 2013)
        self.assertEqual(pins["native_schema_sha256"],
                         "be8391e81587d8dca861f46cfdb0f1a89e18d88ad19a3417105affab016f2d99")
        self.assertEqual(self.plan["environment"]["QUESTION_MAPPED_AGREEMENT_TASKS"], "enabled")
        self.assertEqual(self.plan["limits"]["calls_per_job"], 6)
        self.assertEqual(self.plan["limits"]["seconds_per_job"], 240)
        self.assertEqual(self.plan["limits"]["sts_preflight_requests"], 1)
        self.assertEqual(self.plan["limits"]["sts_execute_requests"], 1)
        self.assertEqual(self.plan["limits"]["sts_total_requests"], 2)
        self.assertEqual(self.plan["limits"]["deadline_origin"],
                         "execute_capture_start_before_credentials_and_sts")

    def test_real_worker_path_fake_provider_three_calls_and_proof(self):
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
        self.assertEqual(len(capture["jobs"][0]["passes"][0]["agreement"]), 2)
        saved = json.loads(self.path.read_text())
        self.assertEqual(saved["summary"]["returned_questions"], 5)
        self.assertEqual(saved["original_jobs"][0]["slots"], capture["original_jobs"][0]["slots"])
        with self.assertRaises(probe.IntegrityError):
            probe.run_jobs(self.plan, capture, self.path, network.client,
                           lambda: probe.check_plan(self.plan))
        self.assertEqual(len(network.calls), 3)

    def test_bounded_agreement_difficulty_three_admitted_four_vetoed(self):
        for difficulty, expected_count in ((3, 5), (4, 3)):
            network = FakeNetwork(self.plan, agreement_difficulty=difficulty)
            capture = probe.new_capture(self.plan)
            path = Path(self.temp.name) / f"difficulty-{difficulty}.json"
            probe.run_jobs(self.plan, capture, path, network.client,
                           lambda: probe.check_plan(self.plan))
            self.assertEqual(capture["summary"]["returned_questions"], expected_count)
            self.assertEqual(len(network.calls), 3)

    def test_one_sts_identity_request_in_each_phase(self):
        counts = {"preflight": 0, "execute": 0}

        class FakeSTS:
            def __init__(self, config, phase):
                self.meta = SimpleNamespace(config=config, endpoint_url=probe.STS_ENDPOINT,
                                            region_name="us-east-1")
                self.phase = phase

            def get_caller_identity(self):
                counts[self.phase] += 1
                return {"Account": probe.EXPECTED_ACCOUNT_ID}

        class FakeSession:
            def __init__(self, phase):
                self.phase = phase
                self.events = SimpleNamespace(register=lambda *args, **kwargs: None)

            def client(self, *args, **kwargs):
                self.assert_service(args, kwargs)
                return FakeSTS(kwargs["config"], self.phase)

            @staticmethod
            def assert_service(args, kwargs):
                assert args == ("sts",)
                assert kwargs["endpoint_url"] == probe.STS_ENDPOINT

        frozen = self.temp.name + "/frozen.json"
        Path(frozen).write_text(json.dumps({**self.plan, "state": "frozen"}))
        precheck_attempt = Path(self.temp.name) / "launch-attempt.json"
        precheck_record = Path(self.temp.name) / "launch-record.json"
        expires = datetime.now(timezone.utc) + timedelta(seconds=600)
        with patch.object(probe, "PLAN", Path(frozen)), \
                patch.object(probe, "LAUNCH_ATTEMPT", precheck_attempt), \
                patch.object(probe, "LAUNCH_PRECHECK", precheck_record), \
                patch.object(probe, "CAPTURE", Path(self.temp.name) / "unmade-capture.json"), \
                patch.object(probe, "check_plan"), \
                patch.object(probe, "require_review_go"), \
                patch.object(probe, "validate_identity_environment"), \
                patch.object(probe, "check_default_profile"), \
                patch.object(probe, "check_aws_cli"), \
                patch.object(probe, "default_profile_session", return_value=(None, (), expires)), \
                patch.object(probe.boto3, "Session", return_value=FakeSession("preflight")):
            record = probe.launch_precheck()
        self.assertEqual(record["pretrial_sts_requests"], 1)
        self.assertEqual(counts["preflight"], 1)
        capture = probe.new_capture(self.plan)
        identity_path = Path(self.temp.name) / "identity-capture.json"
        probe.save(identity_path, capture, exclusive=True)
        with patch.object(probe, "validate_identity_environment"):
            probe.verify_account_identity(FakeSession("execute"), capture, identity_path)
            with self.assertRaises(probe.IntegrityError):
                probe.verify_account_identity(FakeSession("execute"), capture, identity_path)
        self.assertEqual(counts, {"preflight": 1, "execute": 1})
        self.assertEqual(capture["identity_check"]["requests_reserved"], 1)

    def test_slow_setup_consumes_whole_execute_budget(self):
        current = [0.0]
        def clock():
            return current[0]
        deadline = probe.Deadline(clock)
        current[0] = 241.0  # credential export and STS elapsed before job dispatch
        network = FakeNetwork(self.plan)
        capture = probe.new_capture(self.plan)
        with self.assertRaises(probe.IntegrityError):
            probe.run_jobs(self.plan, capture, self.path, network.client,
                           lambda: probe.check_plan(self.plan),
                           clock=clock, deadline=deadline)
        self.assertEqual(network.calls, [])
        self.assertEqual(capture["reservations"], [])
        probe.finish(capture)
        probe.seal_execute_timing(capture, deadline)
        self.assertEqual(capture["summary"]["execute_elapsed_seconds"], 241.0)
        self.assertFalse(capture["summary"]["within_execute_deadline"])
        self.assertEqual(capture["summary"]["returned_questions"], 0)

    def test_submicrosecond_overrun_does_not_round_into_pass(self):
        current = [0.0]
        deadline = probe.Deadline(lambda: current[0])
        current[0] = 240.0000001
        capture = probe.new_capture(self.plan)
        probe.finish(capture)
        capture["summary"]["returned_questions"] = 5
        for slot in capture["original_jobs"][0]["slots"]:
            slot["status"] = "returned"
        probe.seal_execute_timing(capture, deadline)
        self.assertEqual(capture["summary"]["execute_elapsed_seconds"], 240.0)
        self.assertFalse(capture["summary"]["within_execute_deadline"])
        self.assertEqual(capture["summary"]["returned_questions"], 0)
        self.assertEqual([slot["status"] for slot in capture["original_jobs"][0]["slots"]],
                         ["late_uncredited"] * 5)

    def test_expired_credential_export_blocks_execute_sts(self):
        current = [0.0]
        def clock():
            return current[0]

        def slow_export():
            current[0] = 241.0
            return SimpleNamespace(), (), datetime.now(timezone.utc) + timedelta(seconds=600)

        plan_file = Path(self.temp.name) / "frozen-execute.json"
        plan_file.write_text(json.dumps({**self.plan, "state": "frozen"}))
        capture_path = Path(self.temp.name) / "execute-capture.json"
        with patch.object(probe, "PLAN", plan_file), \
                patch.object(probe, "CAPTURE", capture_path), \
                patch.object(probe, "require_review_go"), \
                patch.object(probe, "check_launch_record"), \
                patch.object(probe, "default_profile_session", side_effect=slow_export), \
                patch.object(probe, "verify_account_identity") as identity, \
                patch.object(probe.time, "monotonic", side_effect=clock):
            result = probe.execute(probe.file_hash(plan_file))
        identity.assert_not_called()
        self.assertEqual(result["summary"]["execute_elapsed_seconds"], 241.0)
        self.assertFalse(result["summary"]["within_execute_deadline"])
        self.assertEqual(result["summary"]["returned_questions"], 0)
        self.assertEqual(json.loads(capture_path.read_text())["calls"], [])

    def test_plan_drift_rejected_before_dispatch(self):
        tampered = copy.deepcopy(self.plan)
        tampered["environment"]["BEDROCK_MODEL_ID"] = "changed"
        with self.assertRaises(probe.IntegrityError):
            probe.check_plan(tampered)
        self.assertFalse(self.path.exists())

    def test_review_lock_requires_exact_frozen_hashes(self):
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

    def test_no_reservation_without_original_slot(self):
        network = FakeNetwork(self.plan)
        capture = probe.new_capture(self.plan)
        capture["call_slots"] = capture["call_slots"][:2]
        with self.assertRaises(probe.IntegrityError):
            probe.run_jobs(self.plan, capture, self.path, network.client,
                           lambda: probe.check_plan(self.plan))
        self.assertEqual(network.calls, [])

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

    def test_frozen_plan_hash_guards_source_and_harness(self):
        self.assertEqual(self.plan["candidate_pins"]["normalized_request_sha256"],
                         "212cea7d53ddefe17fbe8f2459705b46b871793e62e0e58b56cc11e3626e63ae")
        self.assertIn(str(HERE / "full_worker_probe.py"), self.plan["source_hashes"])
        with tempfile.TemporaryDirectory() as directory:
            plan_file = Path(directory) / "plan.json"
            plan_file.write_text(json.dumps({**self.plan, "state": "frozen"}))
            actual = probe.file_hash(plan_file)
            probe.check_plan(json.loads(plan_file.read_text()), plan_file, actual)
            with self.assertRaises(probe.IntegrityError):
                probe.check_plan(json.loads(plan_file.read_text()), plan_file, "0" * 64)


if __name__ == "__main__":
    unittest.main()
