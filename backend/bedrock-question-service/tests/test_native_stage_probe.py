"""Native diagnostic admission and content accounting; no provider calls."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_native_stage_probe as probe
from test_runtime_qualification import completed


class NativeStageProbeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.output = self.directory / "capture"
        self.plan_path = self.directory / "plan.json"
        self.snapshot = {"source_revision": "a" * 40, "source_sha256": {"probe": "b" * 64},
                         "dependencies": {"python": "test"}}
        patcher = patch.object(probe, "_source_snapshot", return_value=self.snapshot)
        self.snapshot_mock = patcher.start()
        self.addCleanup(patcher.stop)
        self.plan = probe.make_plan()
        probe.shared.write_json(self.plan_path, self.plan)

    def value(self, job):
        if job["role"] == "solver":
            return {"solutions": [{"index": item["index"], "choices": [
                {"choice": choice, "judgment": "refuted", "reason": "Scripted test only."}
                for choice in item["choices"]]} for item in job["subject"]["items"]]}
        reviews = []
        for item in job["subject"]["items"]:
            review = {"index": item["index"], "valid": True, "answer": item["choices"][0], "difficulty": 3}
            if job["role"] == "reviewer":
                review.update(explanation="Scripted test only.", choiceFeedback=[
                    {"choice": choice, "explanation": "Scripted test only."} for choice in item["choices"]])
            else:
                review.update(explanationSupport="supported", issues=[])
            reviews.append(review)
        return {"reviews": reviews}

    def observer(self, request, *, on_progress, timeout, cli_credentials):
        saved = json.loads((self.output / "capture.json").read_text())
        call = saved["calls"][-1]
        job = self.plan["jobs"][call["position"]]
        self.assertEqual(call["status"], "launch_intent")
        self.assertEqual(job["request"], request)
        self.assertEqual(call["request_sha256"], probe._hash(request))
        self.assertEqual(timeout, 240)
        self.assertEqual(probe.caller.SETTINGS, probe.SETTINGS)
        self.assertFalse(cli_credentials)
        state = completed(self.value(job))
        on_progress(state)
        return state

    def run_probe(self, observer=None):
        return probe.run_probe(self.plan_path, probe._hash(self.plan), self.output,
                               observer=observer or self.observer)

    def test_frozen_requests_preserve_archive_and_cover_every_failure(self):
        self.assertEqual(self.plan["maximum_calls"], 10)
        self.assertEqual([j["archived_call_index"] for j in self.plan["jobs"]],
                         [7, 14, 16, 18, 20, 7, 5, 5, 28, 28])
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 327680)
        origin = json.loads(probe.ORIGIN.read_text())
        for job in self.plan["jobs"]:
            old = origin["calls"][job["archived_call_index"]]
            expected = copy.deepcopy(old["request"])
            expected["system"] = [{"text": probe.native.native_prompt(
                expected["system"][0]["text"], job["contract"])}]
            expected["outputConfig"] = probe.native.native_output_config(job["contract"])
            self.assertEqual(job["request"], expected)
            self.assertEqual(job["normalized_operation_request"],
                             origin["plan"]["operations"][old["operation_index"]]["request"])
            self.assertEqual(job["request"]["modelId"], "us.anthropic.claude-sonnet-4-6")
            self.assertEqual(job["request"]["inferenceConfig"], {"maxTokens": 6000, "temperature": .2})
            self.assertEqual(job["request"]["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})
            self.assertLessEqual(job["input_utf8_bytes"], 32768)
        for a, b in ((0, 5), (6, 7), (8, 9)):
            self.assertEqual(self.plan["jobs"][a]["request"], self.plan["jobs"][b]["request"])

    def test_dry_cli_has_no_network_and_requires_fresh_directory(self):
        dry = self.directory / "dry"
        with patch.object(probe.shared, "new_client", side_effect=AssertionError("No SDK")), patch.object(
            probe.caller, "observe_request", side_effect=AssertionError("No worker"),
        ), patch("builtins.print"):
            self.assertEqual(probe.main(["--directory", str(dry)]), 0)
            self.assertEqual(json.loads((dry / "plan.json").read_text()), self.plan)
            with self.assertRaises(FileExistsError):
                probe.main(["--directory", str(dry)])

    def test_source_dependency_request_and_allowance_changes_reject_before_dispatch(self):
        for mutation in (lambda p: p["dependencies"].update(python="other"),
                         lambda p: p.update(maximum_calls=11),
                         lambda p: p.update(maximum_input_utf8_bytes_per_call=65536),
                         lambda p: p["jobs"][0]["request"]["inferenceConfig"].update(maxTokens=9000),
                         lambda p: p["source_sha256"].update(probe="c" * 64)):
            changed = copy.deepcopy(self.plan)
            mutation(changed)
            probe.shared.write_json(self.plan_path, changed)
            observer = Mock(side_effect=AssertionError("Not admitted"))
            with self.assertRaises(ValueError):
                probe.run_probe(self.plan_path, probe._hash(changed), self.output, observer=observer)
            observer.assert_not_called()
            self.assertFalse(self.output.exists())

    def test_wrong_plan_hash_and_existing_capture_cannot_resume(self):
        with self.assertRaises(ValueError):
            probe.run_probe(self.plan_path, "0" * 64, self.output)
        self.output.mkdir()
        observer = Mock(side_effect=AssertionError("Not admitted"))
        with self.assertRaises(FileExistsError):
            self.run_probe(observer)
        observer.assert_not_called()

    def test_origin_change_and_input_or_call_cap_fail_closed(self):
        altered = self.directory / "altered.json"
        altered.write_bytes(probe.ORIGIN.read_bytes() + b" ")
        with patch.object(probe, "ORIGIN", altered), self.assertRaises(ValueError):
            probe.make_plan()
        with patch.object(probe, "MAX_INPUT_BYTES", 100), self.assertRaises(ValueError):
            probe.make_plan()
        with patch.object(probe, "CALL_INDEXES", probe.CALL_INDEXES + (7,)), self.assertRaises(ValueError):
            probe.make_plan()

    def test_all_ten_valid_contracts_remain_semantically_unassessed(self):
        with patch.object(probe.shared, "new_client", side_effect=AssertionError("No SDK")):
            report = self.run_probe()
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 10)
        self.assertEqual(json.loads((self.output / "capture.json").read_text()), report)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        for call in report["calls"]:
            self.assertTrue(call["provider_dispatch_attempted"])
            self.assertTrue(call["usage_known"])
        for result in report["results"]:
            self.assertEqual(result["raw_schema_validation"], "passed")
            self.assertEqual(result["adaptation"], "passed")
            self.assertEqual(result["stage_validation"], "passed")
            self.assertEqual(result["semantic_assessment"], "unassessed")
            self.assertEqual(result["full_production_acceptance"], "not_run")

    def test_schema_failure_is_completed_content_and_does_not_retry_or_stop(self):
        count = 0

        def observer(request, **kwargs):
            nonlocal count
            count += 1
            if count == 1:
                return completed('Prose followed by ```json\n{"solutions": []}\n```')
            return self.observer(request, **kwargs)

        report = self.run_probe(observer)
        self.assertEqual(count, 10)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["results"][0]["raw_schema_validation"], "rejected")
        self.assertEqual(report["results"][0]["adaptation"], "unavailable")

    def test_schema_adaptation_and_correlation_are_separate(self):
        solver = self.plan["jobs"][0]
        observation = probe.content_observation(solver, completed({"solutions": []}))
        self.assertEqual(observation["raw_schema_validation"], "passed")
        self.assertEqual(observation["adaptation"], "passed")
        self.assertEqual(observation["stage_validation"], "rejected")
        reviewer = self.plan["jobs"][6]
        value = self.value(reviewer)
        rows = value["reviews"][0]["choiceFeedback"]
        rows.append(copy.deepcopy(rows[0]))
        observation = probe.content_observation(reviewer, completed(value))
        self.assertEqual(observation["raw_schema_validation"], "passed")
        self.assertEqual(observation["adaptation"], "rejected")
        self.assertEqual(observation["stage_validation"], "unavailable")

    def test_all_stages_require_exact_original_index_and_choice_correlation(self):
        for position in (0, 6, 8):
            job = self.plan["jobs"][position]
            value = self.value(job)
            records = value["solutions" if job["role"] == "solver" else "reviews"]
            records[0]["index"] = 100
            result = probe.content_observation(job, completed(value))
            self.assertEqual(result["raw_schema_validation"], "passed")
            self.assertEqual(result["stage_validation"], "rejected")
        job = self.plan["jobs"][6]
        value = self.value(job)
        value["reviews"][0]["choiceFeedback"][0]["choice"] += " "
        self.assertEqual(probe.content_observation(job, completed(value))["stage_validation"], "rejected")

    def test_provider_unfinished_or_cleanup_failure_stops_all_later_calls(self):
        states = [completed("{}", status="operational_failure", error_type="ClientError"),
                  completed("{}", local_worker_reaped=False),
                  completed("{}", local_process_group_cleanup_confirmed=False),
                  completed("{}", worker_exitcode=1), completed("{}", termination_attempted=True)]
        unfinished = completed("{}")
        unfinished["response"]["stopReason"] = "max_tokens"
        states.append(unfinished)
        for index, state in enumerate(states):
            self.output = self.directory / f"failure-{index}"
            observer = Mock(return_value=state)
            report = self.run_probe(observer)
            self.assertEqual(report["status"], "operational_failure")
            self.assertEqual(observer.call_count, 1)
            self.assertEqual(len(report["calls"]), 1)
            self.assertEqual(report["results"][1]["status"], "unattempted")

    def test_initial_or_preparation_persistence_failure_prevents_provider(self):
        original = probe.shared.write_json
        for fail_on in (1, 2):
            self.output = self.directory / f"write-{fail_on}"
            writes = 0

            def write(path, value):
                nonlocal writes
                writes += 1
                if writes == fail_on:
                    raise OSError("Sensitive diagnostic detail must not be captured")
                original(path, value)

            observer = Mock(side_effect=AssertionError("Not admitted"))
            with patch.object(probe.shared, "write_json", side_effect=write):
                if fail_on == 1:
                    with self.assertRaises(OSError):
                        self.run_probe(observer)
                else:
                    report = self.run_probe(observer)
                    self.assertEqual(report["error_type"], "OSError")
                    self.assertNotIn("Sensitive", json.dumps(report))
            observer.assert_not_called()

    def test_admission_write_failure_latches_even_if_observer_swallows_it(self):
        original = probe.shared.write_json
        writes = 0

        def write(path, value):
            nonlocal writes
            writes += 1
            if writes == 3:
                raise OSError("Private exception detail")
            original(path, value)

        def observer(request, *, on_progress, **kwargs):
            try:
                on_progress({"status": "running", "provider_dispatch_attempted": None,
                             "local_process_group_id": 123})
            except OSError:
                pass
            return completed(self.value(self.plan["jobs"][0]))

        mocked = Mock(side_effect=observer)
        with patch.object(probe.shared, "write_json", side_effect=write):
            report = self.run_probe(mocked)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(mocked.call_count, 1)


class SourceBindingTests(unittest.TestCase):
    def test_sdk_must_match_qualified_packaged_versions(self):
        for versions in ({"boto3": "1.43.89", "botocore": "1.43.91"},
                         {"boto3": "1.43.91", "botocore": None}):
            with patch.object(probe.shared, "dependencies", return_value=versions):
                with self.assertRaisesRegex(ValueError, "packaged"):
                    probe._source_snapshot("0" * 40)

    def test_snapshot_requires_resolvable_commit_and_exact_committed_tool_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            service = root / "backend/bedrock-question-service"
            (service / "evals").mkdir(parents=True)
            (service / "native_output_contracts.py").write_text("native = 1\n")
            tool = service / "evals/checkpoint_native_stage_probe.py"
            tool.write_text("probe = 1\n")
            (service / "requirements.txt").write_text("boto3\n")
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                            "commit", "-qm", "Fixture"], cwd=root, check=True)
            revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
            with patch.object(probe, "SERVICE_DIR", service), patch.object(
                probe.shared, "dependencies", return_value={"python": "test", **probe.REQUIRED_SDK},
            ):
                snapshot = probe._source_snapshot(revision)
                self.assertEqual(snapshot["source_revision"], revision)
                self.assertEqual(snapshot["source_sha256"]["evals/checkpoint_native_stage_probe.py"],
                                 hashlib.sha256(tool.read_bytes()).hexdigest())
                with self.assertRaises(ValueError):
                    probe._source_snapshot("0" * 40)
                tool.write_text("probe = 2\n")
                with self.assertRaises(ValueError):
                    probe._source_snapshot(revision)


if __name__ == "__main__":
    unittest.main()
