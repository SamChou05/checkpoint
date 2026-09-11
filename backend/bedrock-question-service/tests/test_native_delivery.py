"""Native replay admission plus actual offline bank preparation and claims."""
import copy
import hashlib
import json
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_native_delivery as native
from test_delivery_check import captured_question, complete_question
import test_complete_teaching_workflow_qualification as complete_workflow_tests
import test_native_workflow_qualification as workflow_tests
from test_runtime_qualification import completed


def capture(*, complete=False):
    cases, jobs, operations = [], [], []
    for index in range(3):
        case_id = f"fresh-{index}"
        payload = {
            "goal": {"title": f"Interpret motion {index}", "category": "Custom",
                     "currentLevel": "Trace 'a  b'.", "focusAreas": "Distance and time"},
            "sourceDocuments": [{"name": "Rate", "text": "Distance = speed × time.", "truncated": False}],
            "targetCount": 5, "minimumDifficulty": 3,
        }
        if complete:
            payload["feedbackContract"] = "authored_complete"
        cases.append({"case_id": case_id, "payload": payload})
        jobs.append({"case_id": case_id, "kind": "fresh", "request": copy.deepcopy(payload)})
        operations.append({"case_id": case_id, "kind": "fresh", "status": "completed",
                           "questions": [(complete_question if complete else captured_question)(index + 1)],
                           "result_category": "partial_delivery"})
    experiment = native.COMPLETE_TEACHING_EXPERIMENT if complete else native.EXPERIMENT
    plan = {"experiment": experiment,
            "fixture": {"experiment": experiment, "cases": cases},
            "operations": jobs, "source_revision": "a" * 40, "source_sha256": {}, "dependencies": {},
            "delivery_source_sha256": native.delivery_source_hashes()}
    return {"plan": plan, "plan_sha256": native.runtime._hash(plan),
            "status": "completed", "operations": operations}


class NativeDeliveryTests(unittest.TestCase):
    def test_complete_native_replay_preserves_explicit_context_through_actual_bank(self):
        harness = complete_workflow_tests.CompleteTeachingWorkflowQualificationTests()
        try:
            harness.setUp()
            harness.packet = copy.deepcopy(capture(complete=True)["plan"]["fixture"])
            harness.plan = native.runtime.make_plan(harness.packet)
            native.runtime.shared.write_json(harness.plan_path, harness.plan)
            value = harness.run_trial()
            report = native.check_capture(value)
            self.assertTrue(report["passed"])
            self.assertEqual(report["runtime_returned_count"], 15)
            self.assertEqual(report["bank_claimable_count"], 15)
            self.assertEqual(report["native_capture_binding"]["experiment"], native.COMPLETE_TEACHING_EXPERIMENT)
            self.assertEqual(report["source_sha256"], value["plan"]["delivery_source_sha256"])
            for result, original in zip(report["operations"], harness.packet["cases"], strict=True):
                self.assertEqual(result["request"], original["payload"])
                self.assertEqual(result["bank_feedback_contract"], "authored_complete")
                self.assertEqual(result["claim_request"]["minimumVerificationPolicyRevision"], 4)
                self.assertTrue(all(q["verificationPolicyRevision"] == 4 for q in result["claim_response"]["questions"]))
        finally:
            harness.doCleanups()

    def test_complete_selector_cannot_be_removed_rewritten_or_added_to_old_mode(self):
        for side in ("raw", "normalized"):
            for selector in (None, "reviewer_written", "authored_solution", True):
                value = capture(complete=True)
                request = (value["plan"]["fixture"]["cases"][0]["payload"] if side == "raw"
                           else value["plan"]["operations"][0]["request"])
                request["feedbackContract"] = selector
                with self.subTest(side=side, selector=selector), patch.object(native.runtime, "replay_capture") as replay:
                    with self.assertRaises(ValueError):
                        native.check_capture(value)
                    replay.assert_not_called()
        value = capture()
        value["plan"]["fixture"]["cases"][0]["payload"]["feedbackContract"] = "authored_complete"
        with self.assertRaises(ValueError):
            native.check_capture(value)

    def test_real_native_replay_and_delivery_preserve_content_failed_and_empty_goals(self):
        for scenario in ("full", "invalid", "empty"):
            with self.subTest(scenario=scenario):
                harness = workflow_tests.NativeWorkflowQualificationTests()
                self.addCleanup(harness.doCleanups)
                try:
                    harness.setUp()
                    harness.packet = copy.deepcopy(capture()["plan"]["fixture"])
                    harness.plan = native.runtime.make_plan(harness.packet)
                    native.runtime.shared.write_json(harness.plan_path, harness.plan)
                    attempts = 0

                    def observer(request, **kwargs):
                        nonlocal attempts
                        attempts += 1
                        if scenario == "invalid" and attempts == 1:
                            return completed("invalid native JSON {")
                        if scenario == "empty" and attempts <= 3:
                            return completed({"questions": []})
                        return harness.observer(request, **kwargs)

                    value = harness.run_trial(observer)
                    report = native.check_capture(value)
                    expected = 15 if scenario == "full" else 10
                    self.assertTrue(report["passed"])
                    self.assertEqual(report["requested_count"], 15)
                    self.assertEqual(report["runtime_returned_count"], expected)
                    self.assertEqual(report["bank_claimable_count"], expected)
                    self.assertEqual(len(report["operations"]), 3)
                    self.assertIsNone(report["client_retained_count"])
                    if scenario != "full":
                        first = report["operations"][0]
                        self.assertEqual(first["runtime_status"], "coverage_failure")
                        self.assertEqual(first["runtime_returned_count"], 0)
                        self.assertEqual(first["requested_count"], 5)
                    changed = copy.deepcopy(value)
                    changed["plan"]["source_sha256"]["question_source_guidance.py"] = "0" * 64
                    with self.assertRaises(ValueError):
                        native.check_capture(changed)
                finally:
                    harness.doCleanups()

    def test_exact_replay_precedes_real_prepare_claim_and_context_export(self):
        value = capture()
        value["plan"]["operations"][0]["request"]["goal"]["title"] = "Normalized title"
        before = copy.deepcopy(value)
        with patch.object(native.runtime, "replay_capture", side_effect=copy.deepcopy) as replay:
            report = native.check_capture(value)
        replay.assert_called_once_with(value)
        self.assertEqual(value, before)
        self.assertTrue(report["passed"])
        self.assertEqual(report["runtime_returned_count"], 3)
        self.assertEqual(report["bank_claimable_count"], 3)
        self.assertEqual(report["requested_count"], 15)
        self.assertIsNone(report["client_retained_count"])
        self.assertEqual(report["operations"][0]["request"], value["plan"]["fixture"]["cases"][0]["payload"])
        self.assertTrue(report["native_capture_binding"]["exact_runtime_replay"])
        self.assertEqual(report["source_sha256"], value["plan"]["delivery_source_sha256"])
        wrapper = str(Path(native.__file__).relative_to(native.delivery.ROOT))
        self.assertEqual(report["source_sha256"][wrapper], hashlib.sha256(Path(native.__file__).read_bytes()).hexdigest())
        for original, operation in zip(value["operations"], report["operations"], strict=True):
            self.assertEqual(operation["runtime_questions"], original["questions"])
            self.assertEqual(operation["claim_response"], operation["repeat_claim_response"])

    def test_availability_and_preparation_losses_keep_original_denominators(self):
        value = capture()
        duplicate = copy.deepcopy(value["operations"][0]["questions"][0])
        value["operations"][0]["questions"].append(duplicate)
        value["status"] = "operational_failure"
        value["operations"][1].update(status="operational_failure", questions=[])
        value["operations"][2].update(status="unattempted", questions=[])
        with patch.object(native.runtime, "replay_capture", side_effect=copy.deepcopy):
            report = native.check_capture(value)
        self.assertFalse(report["passed"])
        self.assertEqual(report["runtime_returned_count"], 2)
        self.assertEqual(report["bank_claimable_count"], 1)
        self.assertEqual(report["requested_count"], 15)
        self.assertEqual([op["runtime_status"] for op in report["operations"]],
                         ["completed", "operational_failure", "unattempted"])
        self.assertEqual(len(report["operations"][0]["runtime_questions"]), 2)

    def test_replay_failure_or_mutation_cannot_reach_delivery(self):
        def mutate(value):
            value["operations"][0]["questions"].clear()
            return value
        for replay in (lambda _: {}, mutate):
            with self.subTest(replay=replay), patch.object(native.runtime, "replay_capture", side_effect=replay), patch.object(
                native.delivery, "check_capture",
            ) as deliver, self.assertRaises(ValueError):
                native.check_capture(capture())
            deliver.assert_not_called()

    def test_network_and_provider_creation_are_forbidden_during_replay(self):
        def connect(_):
            with socket.socket() as client:
                client.connect(("127.0.0.1", 1))
        for replay in (connect, lambda _: native.runtime.shared.new_client({}, False),
                       lambda _: native.boto3.client("bedrock-runtime")):
            with self.subTest(replay=replay), patch.object(native.runtime, "replay_capture", side_effect=replay), self.assertRaisesRegex(
                AssertionError, "forbids network and provider",
            ):
                native.check_capture(capture())

    def test_unbound_or_unsupported_context_fails_before_replay(self):
        mutations = (
            lambda v: v.update(status="running"),
            lambda v: v["plan"].update(experiment="legacy"),
            lambda v: v["operations"].pop(),
            lambda v: v["operations"][0].update(case_id="another-case"),
            lambda v: v["operations"][0].update(status="unattempted"),
            lambda v: v["plan"]["fixture"]["cases"][0]["payload"].update(skillMap={}),
            lambda v: v["plan"]["fixture"]["cases"][0]["payload"]["goal"].update(learningTarget="Unrepresented override"),
            lambda v: v["plan"]["fixture"]["cases"][0]["payload"]["goal"].update(category="Physics"),
            lambda v: v["plan"]["fixture"]["cases"][0]["payload"]["goal"].update(focusAreas=["Distance"]),
            lambda v: v["plan"]["fixture"]["cases"][0]["payload"]["sourceDocuments"][0].update(url="https://example.com"),
            lambda v: v["plan"]["fixture"]["cases"][0]["payload"]["sourceDocuments"][0].update(truncated="true"),
            lambda v: v["plan"]["operations"][0]["request"].update(targetCount=2),
            lambda v: v["plan"].pop("delivery_source_sha256"),
            lambda v: v["plan"]["delivery_source_sha256"].update({"Checkpoint/Models/GoalModels.swift": "0" * 64}),
        )
        for mutation in mutations:
            value = capture()
            mutation(value)
            with self.subTest(mutation=mutation), patch.object(native.runtime, "replay_capture") as replay, self.assertRaises(ValueError):
                native.check_capture(value)
            replay.assert_not_called()

    def test_source_change_during_delivery_is_not_certified(self):
        actual = native.delivery.check_capture

        def changed_report(view):
            report = actual(view)
            report["source_sha256"]["Checkpoint/Models/GoalModels.swift"] = "0" * 64
            return report

        with patch.object(native.runtime, "replay_capture", side_effect=copy.deepcopy), patch.object(
            native.delivery, "check_capture", side_effect=changed_report,
        ), self.assertRaisesRegex(ValueError, "changed during"):
            native.check_capture(capture())

    def test_cli_binds_original_bytes_and_refuses_overwrite_or_duplicate_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / "capture.json", Path(directory) / "delivery.json"
            source.write_text(json.dumps(capture(), ensure_ascii=False, indent=2) + "\n")
            with patch.object(native.runtime, "replay_capture", side_effect=copy.deepcopy), patch("builtins.print"):
                self.assertEqual(native.main(["--capture", str(source), "--output", str(output)]), 0)
            report = json.loads(output.read_text())
            self.assertEqual(report["capture_sha256"], hashlib.sha256(source.read_bytes()).hexdigest())
            with self.assertRaises(FileExistsError):
                native.main(["--capture", str(source), "--output", str(output)])
            source.write_text('{"status":"completed","status":"running"}')
            with self.assertRaises(native.runtime.ProviderError):
                native.main(["--capture", str(source), "--output", str(Path(directory) / "other.json")])


if __name__ == "__main__":
    unittest.main()
