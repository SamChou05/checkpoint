"""Offline bounds, current verification gates and exact evidence replay."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_current_model_comparison as trial
from test_runtime_qualification import completed, payload


class CurrentModelComparisonTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.output = self.directory / "capture"
        self.plan_path = self.directory / "plan.json"
        snapshot = {"source_revision": "a" * 40, "source_sha256": {"probe": "b" * 64},
                    "dependencies": {"python": "test"}}
        for name, value in (("_source_snapshot", Mock(return_value=snapshot)),):
            patcher = patch.object(trial, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.plan = trial.make_plan()
        trial.shared.write_json(self.plan_path, self.plan)

    def case(self, request):
        tag = "question_solution_json" if request["system"][0]["text"] == trial.COMPLETE_SOLUTION_SYSTEM_PROMPT else "question_review_json"
        subject = payload(request, tag)
        question = subject["items"][0]
        case = next(c for c in self.plan["fixture"]["cases"] if c["question"]["prompt"] == question["prompt"])
        return case, subject

    def value(self, request):
        case, subject = self.case(request)
        choices = subject["items"][0]["choices"]
        marker = f"Scripted response from {request['modelId']}."
        if request["system"][0]["text"] == trial.COMPLETE_SOLUTION_SYSTEM_PROMPT:
            return {"solutions": [{"index": 0, "choices": [
                {"choice": choice, "judgment": "supported" if choice == case["question"]["expectedAnswer"] else "refuted",
                 "reason": marker} for choice in choices]}]}
        for row in subject["independentSolutions"][0]["choices"]:
            self.assertEqual(row["reason"], marker)
        difficulty = next((p["targetDifficulty"] for p in case["request"].get("adaptiveSkillPlans", [])
                           if p["skillID"] == case["question"].get("skillID")), case["request"].get("minimumDifficulty", 1))
        return {"reviews": [{"index": 0, "valid": True, "answer": case["question"]["expectedAnswer"],
                             "difficulty": difficulty, "explanation": "Scripted main feedback.",
                             "choiceExplanations": {c: "Scripted choice feedback." for c in choices}}]}

    def observer(self, request, *, on_progress, timeout, cli_credentials):
        saved = json.loads((self.output / "capture.json").read_text())
        call = saved["calls"][-1]
        self.assertEqual(call["status"], "launch_intent")
        self.assertEqual(call["request"], request)
        self.assertEqual(call["request_sha256"], trial._hash(request))
        self.assertEqual(timeout, 240)
        self.assertEqual(trial.caller.SETTINGS, trial.SETTINGS)
        self.assertFalse(cli_credentials)
        state = completed(self.value(request))
        on_progress(state)
        return state

    def run_trial(self, observer=None):
        return trial.run_trial(self.plan_path, trial._hash(self.plan), self.output,
                               observer=observer or self.observer)

    def fresh_destination(self, suffix):
        self.output = self.directory / f"capture-{suffix}"
        self.plan_path = self.directory / f"plan-{suffix}.json"
        trial.shared.write_json(self.plan_path, self.plan)

    def test_dry_plan_has_current_contracts_matched_settings_and_no_provider(self):
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")), patch.object(
            trial.caller, "observe_request", side_effect=AssertionError("No worker"),
        ), patch("builtins.print"):
            directory = self.directory / "dry"
            self.assertEqual(trial.main(["--directory", str(directory)]), 0)
            self.assertEqual(json.loads((directory / "plan.json").read_text()), self.plan)
        self.assertEqual(len(self.plan["jobs"]), 16)
        self.assertEqual(self.plan["maximum_calls"], 32)
        for index in range(8):
            jobs = self.plan["jobs"][index * 2:index * 2 + 2]
            self.assertEqual([j["model"] for j in jobs], list(trial.MODELS if index % 2 == 0 else reversed(trial.MODELS)))
            first, second = [copy.deepcopy(j["solver_request"]) for j in jobs]
            first.pop("modelId")
            second.pop("modelId")
            self.assertEqual(first, second)
            self.assertEqual(first["system"], [{"text": trial.COMPLETE_SOLUTION_SYSTEM_PROMPT}])
            self.assertEqual(first["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(first["additionalModelRequestFields"], {
                "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}})
            self.assertNotIn("outputConfig", first)
            subject = payload(jobs[0]["solver_request"], "question_solution_json")
            self.assertEqual(len(subject["items"][0]["choices"]), 4)
            for key in ("expectedAnswer", "explanation", "choiceExplanations", "assessment", "difficulty"):
                self.assertNotIn(key, subject["items"][0])

    def test_frozen_plan_source_settings_and_subject_changes_prevent_dispatch(self):
        mutations = [lambda p: p.update(maximum_calls=33),
                     lambda p: p["settings"].update(BEDROCK_CLAUDE_EFFORT="max"),
                     lambda p: p["jobs"][0]["solver_request"]["inferenceConfig"].update(maxTokens=16384),
                     lambda p: p["fixture"]["cases"][0]["question"].update(expectedAnswer="changed"),
                     lambda p: p["documents_sha256"].update(extra="a" * 64)]
        for mutation in mutations:
            plan = copy.deepcopy(self.plan)
            mutation(plan)
            trial.shared.write_json(self.plan_path, plan)
            observer = Mock(side_effect=AssertionError("No call"))
            with self.assertRaises(ValueError):
                trial.run_trial(self.plan_path, trial._hash(plan), self.output, observer=observer)
            observer.assert_not_called()
            self.assertFalse(self.output.exists())

    def test_preparation_rejects_stale_source_hashes_and_independent_assessment(self):
        packet = copy.deepcopy(self.plan["fixture"])
        packet["cases"][1]["question"]["expectedAnswer"] = "changed"
        fixture = self.directory / "changed.json"
        fixture.write_text(json.dumps(packet))
        with patch.object(trial, "FIXTURE", fixture), self.assertRaisesRegex(ValueError, "assessment"):
            trial.make_plan()
        assessment = json.loads(trial.ASSESSMENT.read_text())
        import hashlib
        assessment["fixture_sha256"] = hashlib.sha256(fixture.read_bytes()).hexdigest()
        changed_assessment = self.directory / "assessment.json"
        changed_assessment.write_text(json.dumps(assessment))
        with patch.object(trial, "FIXTURE", fixture), patch.object(trial, "ASSESSMENT", changed_assessment), self.assertRaisesRegex(ValueError, "original source identity"):
            trial.make_plan()

    def test_every_fresh_reviewer_uses_own_solver_and_exact_policy_replay(self):
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "BEDROCK_TEMPERATURE": "0.9"}):
            report = self.run_trial()
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 32)
        self.assertTrue(all(r["accepted"] for r in report["results"]))
        self.assertTrue(all(r["semantic_assessment"] == "unassessed" for r in report["results"]))
        export = self.directory / "assessment"
        trial.export_assessment(report, export)
        teaching = json.loads((export / "teaching.json").read_text())
        mapping = json.loads((export / "private-mapping.json").read_text())
        self.assertEqual(len(teaching), 16)
        self.assertTrue(all(t["raw_response"] and t["parsed_response"] for t in teaching))
        self.assertTrue(all("model" not in t and "expectedAnswer" not in t for t in teaching))
        for item, link in zip(teaching, mapping, strict=True):
            expected = payload(self.plan["jobs"][link["position"]]["solver_request"], "question_solution_json")
            self.assertEqual(item["choices"], expected["items"][0]["choices"])
        self.assertEqual(json.loads((self.output / "capture.json").read_text()), report)

    def test_solver_vetoes_skip_review_without_replacement(self):
        for name in ("zero", "multiple", "uncertain", "disagreement"):
            self.fresh_destination(name)

            def observer(request, **kwargs):
                self.assertEqual(request["system"][0]["text"], trial.COMPLETE_SOLUTION_SYSTEM_PROMPT)
                value = self.value(request)
                rows = value["solutions"][0]["choices"]
                if name == "zero":
                    for row in rows:
                        row["judgment"] = "refuted"
                elif name == "multiple":
                    for row in rows:
                        row["judgment"] = "supported"
                elif name == "uncertain":
                    rows[0]["judgment"] = "uncertain"
                else:
                    for row in rows:
                        row["judgment"] = "refuted" if row["judgment"] == "supported" else "supported"
                    supported = [r for r in rows if r["judgment"] == "supported"]
                    for row in supported[1:]:
                        row["judgment"] = "refuted"
                return completed(value)

            report = self.run_trial(observer)
            self.assertEqual(report["status"], "completed")
            self.assertEqual(len(report["calls"]), 16)
            self.assertTrue(all(not r["accepted"] for r in report["results"]))

    def test_completed_format_failure_and_whitespace_text_continue_fixed_jobs(self):
        for index, bad in enumerate(("not json", "   ", '{"solutions":[]}')):
            self.fresh_destination(index)
            report = self.run_trial(lambda request, **_: completed(bad))
            self.assertEqual(report["status"], "completed")
            self.assertEqual(len(report["calls"]), 16)
            self.assertTrue(all(not r["accepted"] for r in report["results"]))
            exported = self.directory / f"assessment-{index}"
            trial.export_assessment(report, exported)
            self.assertTrue(all(t["raw_response"] is None for t in json.loads((exported / "teaching.json").read_text())))

    def test_reviewer_bad_envelopes_keys_feedback_and_difficulty_keep_actual_gates(self):
        for index, mutation in enumerate((lambda v: v.update(extra="competing verdict"),
                                         lambda v: v["reviews"].append(copy.deepcopy(v["reviews"][0])),
                                         lambda v: v["reviews"][0].update(answer="wrong"),
                                         lambda v: v["reviews"][0].update(explanation="X" * 421),
                                         lambda v: v["reviews"][0].update(difficulty=0),
                                         lambda v: v["reviews"][0].update(explanation="Option A is correct."))):
            self.fresh_destination(f"review-{index}")

            def observer(request, **_):
                value = self.value(request)
                if "reviews" in value:
                    mutation(value)
                return completed(value)

            report = self.run_trial(observer)
            self.assertEqual(report["status"], "completed")
            self.assertEqual(len(report["calls"]), 32)
            self.assertTrue(all(not r["accepted"] for r in report["results"]))

    def test_difficulty_filter_preserves_teaching_for_independent_assessment(self):
        def observer(request, **_):
            value = self.value(request)
            if "reviews" in value:
                value["reviews"][0]["difficulty"] = 1
            return completed(value)
        report = self.run_trial(observer)
        self.assertEqual(report["status"], "completed")
        self.assertTrue(any(r["quality"]["review"].get("difficulty_floor") for r in report["results"]))
        exported = self.directory / "assessment"
        trial.export_assessment(report, exported)
        self.assertTrue(all(t["parsed_response"] for t in json.loads((exported / "teaching.json").read_text())))

    def test_operational_unknown_usage_and_cleanup_failures_stop_globally(self):
        states = [completed("{}", status="operational_failure", error_type="ClientError"),
                  completed(""),
                  completed("{}", local_worker_reaped=False), completed("{}", termination_attempted=True),
                  completed("{}", local_process_group_cleanup_confirmed=False), completed("{}", worker_exitcode=1)]
        unfinished = completed("{}")
        unfinished["response"]["stopReason"] = "max_tokens"
        states.append(unfinished)
        unknown = completed("{}", usage_known=False)
        unknown["response"]["usage"] = {}
        states.append(unknown)
        for index, state in enumerate(states):
            self.fresh_destination(f"failure-{index}")
            observer = Mock(return_value=state)
            report = self.run_trial(observer)
            self.assertEqual(report["status"], "operational_failure")
            self.assertEqual(observer.call_count, 1)
            self.assertEqual(report["results"][0]["status"], "operational_failure")
            self.assertTrue(all(r["status"] == "unattempted" for r in report["results"][1:]))

    def test_persistence_failure_prevents_first_or_further_dispatch(self):
        writer = trial.shared.write_json
        for fail_on in (1, 2, 3, 4):
            self.fresh_destination(f"disk-{fail_on}")
            writes = 0

            def persist(path, value):
                nonlocal writes
                writes += 1
                if writes >= fail_on:
                    raise OSError("Scripted disk failure")
                writer(path, value)

            observer = Mock(side_effect=self.observer)
            with patch.object(trial.shared, "write_json", side_effect=persist), self.assertRaises(OSError):
                self.run_trial(observer)
            self.assertLessEqual(observer.call_count, 0 if fail_on <= 2 else 1)

    def test_plan_cannot_be_rerun_to_new_directory_and_existing_capture_is_untouched(self):
        report = self.run_trial(lambda request, **_: completed("not json"))
        original = (self.output / "capture.json").read_bytes()
        for directory in (self.output, self.directory / "another"):
            observer = Mock()
            with self.assertRaises(FileExistsError):
                trial.run_trial(self.plan_path, trial._hash(self.plan), directory, observer=observer)
            observer.assert_not_called()
        self.assertEqual(report["status"], "completed")
        self.assertEqual((self.output / "capture.json").read_bytes(), original)

    def test_export_rejects_altered_raw_text_results_requests_and_accounting(self):
        report = self.run_trial()
        mutations = [lambda r: r["calls"][0]["observation"]["response"].update(text=r["calls"][0]["observation"]["response"]["text"] + " "),
                     lambda r: r["results"][0].update(accepted=[]),
                     lambda r: r["calls"][0]["request"].update(modelId=trial.MODELS[1]),
                     lambda r: r.update(input_utf8_bytes=0),
                     lambda r: r["calls"].reverse()]
        for index, mutation in enumerate(mutations):
            changed = copy.deepcopy(report)
            mutation(changed)
            destination = self.directory / f"bad-export-{index}"
            with self.assertRaises((ValueError, trial.ProviderError)):
                trial.export_assessment(changed, destination)
            self.assertFalse(destination.exists())

    def test_request_mismatch_after_solver_cannot_be_misclassified_as_content_loss(self):
        original = trial.generation._generate_legacy_with_bedrock

        def changed(*args, **kwargs):
            if args[4] == trial.COMPLETE_REVIEW_SYSTEM_PROMPT:
                args[1].converse(broken=True)
            return original(*args, **kwargs)

        with patch.object(trial.generation, "_generate_legacy_with_bedrock", side_effect=changed):
            report = self.run_trial()
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(len(report["calls"]), 1)


if __name__ == "__main__":
    unittest.main()
