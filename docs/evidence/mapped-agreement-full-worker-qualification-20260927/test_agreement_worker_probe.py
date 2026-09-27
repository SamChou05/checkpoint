"""Socket-free tests of the pinned agreement full-worker capture path."""

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
from test_quantitative_authoring import exact_task  # noqa: E402


def author_object():
    def number(value):
        task = exact_task(value)
        del task["choices"]
        return task

    return {"questions": {
        "0": number("8"), "1": number("10"), "2": number("12"),
        "3": {"kind": "agreement_pair_v1", "scene": "coach", "order": "singular_first"},
        "4": {"kind": "agreement_pair_v1", "scene": COMPOUND_SCENE, "order": "plural_first"},
    }}


class FakeNetwork:
    def __init__(self, plan):
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
                "valid": True, "answer": known[item["prompt"]], "difficulty": 2,
                "explanationSupport": "supported", "issueFlags": authored_issue_flags(),
            } for item in items}}

        self.scripted = ScriptedNativeClient(
            (contract.name, author_object()),
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
        self.assertEqual(pins["native_schema_bytes"], 2701)
        self.assertEqual(pins["native_schema_sha256"],
                         "2e2508e3c7944a0b51246e6fa5febcdd57b84c0003ae81315f36c1107cdbbb6c")
        self.assertEqual(self.plan["environment"]["QUESTION_MAPPED_AGREEMENT_TASKS"], "enabled")
        self.assertEqual(self.plan["limits"]["calls_per_job"], 6)
        self.assertEqual(self.plan["limits"]["seconds_per_job"], 240)

    def test_real_worker_path_fake_provider_three_calls_and_proof(self):
        network = FakeNetwork(self.plan)
        capture = probe.new_capture(self.plan)
        probe.run_jobs(self.plan, capture, self.path, network.client,
                       lambda: probe.check_plan(self.plan))
        self.assertEqual(capture["status"], "completed_pending_review")
        self.assertEqual(len(network.calls), 3)
        self.assertEqual(capture["summary"]["returned_questions"], 5)
        self.assertEqual([item["verificationPolicyRevision"] for item in capture["jobs"][0]["returned"]],
                         [8, 8, 8, 9, 9])
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
