"""Offline admission and context-isolation tests; no provider or worker calls."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_reviewer_independence_probe as probe
from test_runtime_qualification import completed


class ReviewerIndependenceProbeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.output = self.directory / "capture"
        self.plan_path = self.directory / "plan.json"
        self.snapshot = {
            "source_revision": "a" * 40,
            "source_sha256": {"probe.py": "b" * 64},
            "dependencies": {"python": "test", "boto3": "1.43.91", "botocore": "1.43.91"},
        }
        snapshot = patch.object(probe.native_probe, "_source_snapshot", return_value=self.snapshot)
        self.snapshot_mock = snapshot.start()
        self.addCleanup(snapshot.stop)
        self.plan = probe.make_plan()
        probe.shared.write_json(self.plan_path, self.plan)

    @staticmethod
    def value(job):
        # Deliberately no factual assessment: positive declarations must never
        # become semantic approval merely by passing these response contracts.
        candidates = {item["prompt"]: item for item in job["policy_input"]["candidates"]}
        return {"reviews": [
            {"index": item["index"], "valid": True,
             "answer": candidates[item["prompt"]]["expectedAnswer"],
             "difficulty": 3, "explanation": "Scripted, unverified teaching.",
             "choiceFeedback": [{"choice": choice, "explanation": "Unverified model claim."}
                                for choice in item["choices"]]}
            for item in job["subject"]["items"]
        ]}

    def observer(self, request, *, on_progress, timeout, cli_credentials):
        saved = json.loads((self.output / "capture.json").read_text())
        call = saved["calls"][-1]
        job = self.plan["jobs"][call["position"]]
        self.assertEqual(saved["plan_sha256"], probe._hash(self.plan))
        self.assertEqual(call["status"], "launch_intent")
        self.assertEqual(call["request_sha256"], probe._hash(request))
        self.assertEqual(request, job["request"])
        self.assertEqual(timeout, 240)
        self.assertFalse(cli_credentials)
        self.assertEqual(probe.native_probe.caller.SETTINGS, self.plan["settings"])
        state = completed(self.value(job))
        on_progress(state)
        return state

    def run_probe(self, observer=None):
        return probe.run_probe(self.plan_path, probe._hash(self.plan), self.output,
                               observer=observer or self.observer)

    def test_actual_archived_batches_and_current_provider_settings_are_fixed(self):
        jobs = self.plan["jobs"]
        self.assertEqual(len(jobs), 10)
        self.assertEqual(self.plan["maximum_calls"], 10)
        self.assertEqual(self.plan["maximum_input_utf8_bytes_per_call"], 32768)
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 327680)
        self.assertEqual(self.plan["per_worker_deadline_seconds"], 240)
        self.assertEqual(self.plan["sdk_total_max_attempts"], 1)
        self.assertEqual(self.plan["maximum_worker_capture_bytes"], 262144)
        self.assertEqual([j["archived_call_index"] for j in jobs],
                         [2, 2, 5, 5, 23, 23, 1, 1, 4, 4])
        self.assertEqual([len(j["subject"]["items"]) for j in jobs[::2]], [3, 1, 1, 2, 5])
        self.assertEqual(len({item["prompt"] for j in jobs for item in j["subject"]["items"]}), 12)
        self.assertEqual([j["arm"] for j in jobs], [
            "solver_context", "withheld_solver_context",
            "withheld_solver_context", "solver_context",
            "solver_context", "withheld_solver_context",
            "withheld_solver_context", "solver_context",
            "solver_context", "withheld_solver_context",
        ])
        self.assertEqual(sum(j["input_utf8_bytes"] for j in jobs),
                         self.plan["planned_input_utf8_bytes"])
        for relative, expected_hash, _ in probe.ORIGINS:
            path = probe.SERVICE_DIR.parents[1] / "docs/evidence" / relative
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), expected_hash)
            archive = json.loads(path.read_text())
            for job in (j for j in jobs if j["origin_path"] == relative):
                old = archive["calls"][job["archived_call_index"]]
                self.assertEqual(job["source_request"], old["request"])
                self.assertEqual(job["normalized_operation_request"],
                                 archive["plan"]["operations"][old["operation_index"]]["request"])
                request = job["request"]
                self.assertEqual(request["modelId"], "us.anthropic.claude-sonnet-4-6")
                self.assertEqual(request["inferenceConfig"], {"maxTokens": 6000, "temperature": .2})
                self.assertEqual(request["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})
                self.assertEqual(job["contract"], "default_reviewer_v1")
                self.assertEqual(job["request_sha256"], probe._hash(request))
                self.assertEqual(job["input_utf8_bytes"], len(probe.shared.canonical(request).encode()))
                self.assertLessEqual(job["input_utf8_bytes"], 32768)

    def test_only_complete_solver_field_differs_inside_each_pair(self):
        for pair_index in range(5):
            pair = self.plan["jobs"][2 * pair_index:2 * pair_index + 2]
            arms = {job["arm"]: job for job in pair}
            control, treatment = arms["solver_context"], arms["withheld_solver_context"]
            original = probe.native_probe._subject(control["source_request"], "reviewer")
            self.assertEqual(control["subject"], original)
            expected_subject = copy.deepcopy(original)
            self.assertTrue(expected_subject.pop("independentSolutions"))
            self.assertEqual(treatment["subject"], expected_subject)
            expected_request = copy.deepcopy(control["request"])
            expected_request["messages"][0]["content"][0]["text"] = (
                "<question_review_json>\n" + json.dumps(expected_subject, ensure_ascii=False)
                + "\n</question_review_json>"
            )
            self.assertEqual(treatment["request"], expected_request)
            self.assertEqual(control["contract_metadata"], treatment["contract_metadata"])
            self.assertEqual(control["request"]["system"], self.plan["jobs"][0]["request"]["system"])
            self.assertEqual(control["subject"]["items"], treatment["subject"]["items"])
            self.assertEqual(control["source_request"], treatment["source_request"])
            self.assertNotIn("arm", expected_subject)
            self.assertNotIn("assessment", expected_subject)

    def test_dry_cli_never_creates_provider_or_worker_and_cannot_overwrite(self):
        destination = self.directory / "dry"
        with patch.object(probe.shared, "new_client", side_effect=AssertionError("No provider")), patch.object(
            probe.native_probe.caller, "observe_request", side_effect=AssertionError("No worker"),
        ), patch.object(probe.native_probe.generation, "_bedrock_client", side_effect=AssertionError("No SDK")), patch(
            "builtins.print",
        ):
            self.assertEqual(probe.main(["--directory", str(destination)]), 0)
            self.assertEqual(json.loads((destination / "plan.json").read_text()), self.plan)
            with self.assertRaises(FileExistsError):
                probe.main(["--directory", str(destination)])

    def test_rehashed_plan_mutations_cannot_authorize_different_work(self):
        mutations = {
            "arm": lambda p: p["jobs"][0].update(arm="withheld_solver_context"),
            "case": lambda p: p["jobs"][0].update(archived_call_index=5),
            "source": lambda p: p["source_sha256"].update({"probe.py": "c" * 64}),
            "sdk": lambda p: p["dependencies"].update(botocore="1.43.89"),
            "request": lambda p: p["jobs"][0]["request"]["inferenceConfig"].update(maxTokens=9000),
            "subject": lambda p: p["jobs"][0]["subject"]["items"][0].update(prompt="A substitute question"),
            "policy_key": lambda p: p["jobs"][0]["policy_input"]["candidates"][0].update(expectedAnswer="Substitute key"),
            "policy_solver": lambda p: p["jobs"][0]["policy_input"].update(solver_text='{"solutions": []}'),
            "order": lambda p: p["jobs"].reverse(),
            "extra_job": lambda p: p["jobs"].append(copy.deepcopy(p["jobs"][0])),
            "call_cap": lambda p: p.update(maximum_calls=11),
            "deadline": lambda p: p.update(per_worker_deadline_seconds=300),
            "input_cap": lambda p: p.update(maximum_input_utf8_bytes_per_call=65536),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                changed = copy.deepcopy(self.plan)
                mutate(changed)
                probe.shared.write_json(self.plan_path, changed)
                observer = Mock(side_effect=AssertionError("Not admitted"))
                with self.assertRaises(ValueError):
                    probe.run_probe(self.plan_path, probe._hash(changed), self.output, observer=observer)
                observer.assert_not_called()
                self.assertFalse(self.output.exists())

    def test_changed_source_snapshot_and_bad_hash_fail_before_dispatch(self):
        with self.assertRaises(ValueError):
            probe.run_probe(self.plan_path, "0" * 64, self.output)
        changed = copy.deepcopy(self.snapshot)
        changed["source_sha256"]["probe.py"] = "c" * 64
        self.snapshot_mock.return_value = changed
        observer = Mock(side_effect=AssertionError("Not admitted"))
        with self.assertRaises(ValueError):
            self.run_probe(observer)
        observer.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_either_raw_origin_byte_change_is_rejected_even_if_json_unchanged(self):
        original = Path.read_bytes
        for relative, _, _ in probe.ORIGINS:
            target = probe.SERVICE_DIR.parents[1] / "docs/evidence" / relative

            def changed(path):
                raw = original(path)
                return raw + b" " if path == target else raw

            with self.subTest(origin=relative), patch.object(Path, "read_bytes", changed):
                with self.assertRaisesRegex(ValueError, "capture bytes"):
                    probe.make_plan()

    def test_frozen_assessment_or_bound_file_changes_prevent_preparation(self):
        original = Path.read_bytes
        freeze_path = probe.ASSESSMENT_DIR / "first-pass-freeze.json"
        freeze = json.loads(freeze_path.read_text())
        for target in (freeze_path, *(probe.ASSESSMENT_DIR / name for name in freeze["files"])):
            def changed(path):
                raw = original(path)
                return raw + b" " if path == target else raw

            with self.subTest(path=target.name), patch.object(Path, "read_bytes", changed):
                with self.assertRaises(ValueError):
                    probe.make_plan()

    def test_extra_jobs_and_oversized_requests_are_not_prepared(self):
        origins = list(probe.ORIGINS)
        relative, digest, indexes = origins[0]
        origins[0] = (relative, digest, (*indexes, indexes[-1]))
        with patch.object(probe, "ORIGINS", tuple(origins)), self.assertRaises(ValueError):
            probe.make_plan()
        with patch.object(probe.native_probe, "MAX_INPUT_BYTES", 100), self.assertRaises(ValueError):
            probe.make_plan()

    def test_shared_runner_dispatches_exact_ten_jobs_without_semantic_approval(self):
        observer = Mock(side_effect=self.observer)
        with patch.object(probe.shared, "new_client", side_effect=AssertionError("No provider")):
            report = self.run_probe(observer)
        self.assertEqual(observer.call_count, 10)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 10)
        self.assertEqual(json.loads((self.output / "capture.json").read_text()), report)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        for call, result in zip(report["calls"], report["results"], strict=True):
            self.assertEqual(result["stage_validation"], "passed")
            self.assertEqual(result["stage_validation_scope"], "default_reviewer_index_and_choice_coverage_only")
            self.assertEqual(result["semantic_assessment"], "unassessed")
            self.assertEqual(result["full_production_acceptance"], "offline_policy_replay_only")
            self.assertEqual(result["policy_callbacks"], ["solver", "reviewer", "native_transport"])
            self.assertEqual(call["status"], "completed")
        with patch.object(probe.shared, "new_client", side_effect=AssertionError("No provider")), patch.object(
            probe.native_probe.caller, "observe_request", side_effect=AssertionError("No worker"),
        ):
            for job, call, result in zip(self.plan["jobs"], report["calls"], report["results"], strict=True):
                replay = probe.content_observation(job, call["observation"])
                self.assertEqual(replay, {k: v for k, v in result.items() if k not in ("position", "status")})
        observer.reset_mock()
        with self.assertRaises(FileExistsError):
            self.run_probe(observer)
        observer.assert_not_called()

    def test_actual_policy_preserves_solver_veto_and_same_returns_in_both_arms(self):
        # The second archived batch includes one rejected gradebook candidate;
        # omitting its solver from the provider payload must not rescue it.
        for pair_index in range(5):
            pair = self.plan["jobs"][2 * pair_index:2 * pair_index + 2]
            observations = [probe.content_observation(job, completed(self.value(job))) for job in pair]
            self.assertEqual(observations[0], observations[1])
            for job, result in zip(pair, observations, strict=True):
                returned = result["simulated_returned_questions"]
                self.assertEqual(result["simulated_return_count"], len(job["subject"]["items"]))
                self.assertEqual({q["prompt"] for q in returned},
                                 {q["prompt"] for q in job["subject"]["items"]})
                self.assertTrue(all(q["verificationPolicyRevision"] == 2 for q in returned))
                self.assertTrue(all(q["explanation"] == "Scripted, unverified teaching." for q in returned))
                self.assertEqual(result["semantic_assessment"], "unassessed")
            if pair_index == 1:
                self.assertEqual(len(pair[0]["policy_input"]["candidates"]), 2)
                self.assertEqual(observations[0]["policy_metrics"]["review"]["solver_multiple_supported"], 1)
                self.assertEqual(observations[0]["simulated_return_count"], 1)

    def test_positive_declarations_cannot_override_key_difficulty_or_teaching_limits(self):
        job = self.plan["jobs"][0]
        for failure in ("answer", "difficulty", "main_length", "choice_feedback_length"):
            with self.subTest(failure=failure):
                value = self.value(job)
                first = value["reviews"][0]
                if failure == "answer":
                    first["answer"] = next(c for c in job["subject"]["items"][0]["choices"]
                                           if c != first["answer"])
                elif failure == "difficulty":
                    first["difficulty"] = 1
                elif failure == "main_length":
                    first["explanation"] = "x" * 421
                else:
                    first["choiceFeedback"][0]["explanation"] = "x" * 281
                result = probe.content_observation(job, completed(value))
                self.assertEqual(result["raw_schema_validation"], "passed")
                self.assertEqual(result["semantic_assessment"], "unassessed")
                self.assertEqual(result["full_production_acceptance"], "offline_policy_replay_only")
                self.assertEqual(result["simulated_return_count"], 2)
                self.assertNotIn(job["subject"]["items"][0]["prompt"],
                                 [q["prompt"] for q in result["simulated_returned_questions"]])

    def test_only_exact_known_old_prompt_migration_is_accepted(self):
        jobs = self.plan["jobs"]
        for job in jobs:
            old = job["source_request"]
            current = probe._current_request(old)
            expected = copy.deepcopy(old)
            expected["system"] = [{"text": probe.COMPLETE_REVIEW_SYSTEM_PROMPT}]
            self.assertEqual(current, expected)
            self.assertEqual(current != old, job["origin_path"].startswith("runtime-qualification"))
            self.assertEqual(old, job["source_request"])
        changed = copy.deepcopy(jobs[-1]["source_request"])
        changed["system"][0]["text"] += "\nChange the task to make one answer work."
        self.assertEqual(probe._current_request(changed), changed)

    def test_policy_callback_or_native_request_mutation_cannot_replay(self):
        for mutate in (
            lambda j: j["policy_input"]["solver_request"]["system"][0].update(text="Different solver"),
            lambda j: j["source_request"]["messages"][0]["content"][0].update(text="Different review"),
        ):
            job = copy.deepcopy(self.plan["jobs"][0])
            value = self.value(job)
            mutate(job)
            with self.assertRaises(ValueError):
                probe.content_observation(job, completed(value))
        job = copy.deepcopy(self.plan["jobs"][0])
        job["request"]["inferenceConfig"]["maxTokens"] = 7000
        result = probe.content_observation(job, completed(self.value(job)))
        self.assertEqual(result["adaptation"], "rejected")
        self.assertEqual(result["full_production_acceptance"], "not_run")

    def test_completed_content_failures_continue_without_repair_or_extra_calls(self):
        def observer(request, **kwargs):
            state = self.observer(request, **kwargs)
            position = len(json.loads((self.output / "capture.json").read_text())["calls"]) - 1
            if position == 0:
                state["response"]["text"] = 'Preamble {"reviews": []}'
            elif position == 1:
                value = self.value(self.plan["jobs"][position])
                feedback = value["reviews"][0]["choiceFeedback"]
                feedback.append(copy.deepcopy(feedback[0]))
                state["response"]["text"] = json.dumps(value)
            elif position == 2:
                state["response"]["text"] = '{"reviews": []}'
            return state

        mocked = Mock(side_effect=observer)
        report = self.run_probe(mocked)
        self.assertEqual(mocked.call_count, 10)
        self.assertEqual(report["status"], "completed")
        expected = [("rejected", "unavailable", "unavailable"),
                    ("passed", "rejected", "unavailable"),
                    ("passed", "passed", "rejected")]
        for result, stages in zip(report["results"], expected):
            self.assertEqual(tuple(result[k] for k in ("raw_schema_validation", "adaptation", "stage_validation")), stages)
            self.assertEqual(result["status"], "completed")
            self.assertEqual(result["semantic_assessment"], "unassessed")

    def test_provider_unfinished_cleanup_and_usage_failures_stop_later_jobs(self):
        unfinished = completed("{}")
        unfinished["response"]["stopReason"] = "max_tokens"
        failures = [completed("{}", status="operational_failure", error_type="ClientError"),
                    completed("{}", local_worker_reaped=False),
                    completed("{}", local_process_group_cleanup_confirmed=False),
                    completed("{}", worker_exitcode=1), completed("{}", termination_attempted=True),
                    completed("{}", usage_known=False), unfinished]
        for index, state in enumerate(failures):
            with self.subTest(index=index):
                self.output = self.directory / f"failure-{index}"
                calls = 0

                def observer(request, **kwargs):
                    nonlocal calls
                    calls += 1
                    return self.observer(request, **kwargs) if calls == 1 else state

                report = self.run_probe(observer)
                self.assertEqual(calls, 2)
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(report["results"][0]["status"], "completed")
                self.assertTrue(all(r["status"] == "unattempted" for r in report["results"][2:]))

    def test_unknown_observer_error_stops_and_does_not_persist_exception_text(self):
        observer = Mock(side_effect=RuntimeError("Private provider diagnostic"))
        report = self.run_probe(observer)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["error_type"], "RuntimeError")
        self.assertEqual(observer.call_count, 1)
        self.assertNotIn("Private provider diagnostic", json.dumps(report))

    def test_launch_persistence_failure_prevents_observer_dispatch(self):
        original = probe.shared.write_json
        writes = 0

        def write(path, value):
            nonlocal writes
            writes += 1
            if writes == 2:
                raise OSError("Private persistence diagnostic")
            original(path, value)

        observer = Mock(side_effect=AssertionError("Not admitted"))
        with patch.object(probe.shared, "write_json", side_effect=write):
            report = self.run_probe(observer)
        observer.assert_not_called()
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["error_type"], "OSError")
        self.assertNotIn("Private persistence diagnostic", json.dumps(report))

    def test_export_preserves_all_exact_reviews_and_hides_arm_solver_and_policy(self):
        report = self.run_probe()
        destination = self.directory / "assessment"
        with patch.object(probe.shared, "new_client", side_effect=AssertionError("No provider")), patch.object(
            probe.native_probe.caller, "observe_request", side_effect=AssertionError("No worker"),
        ):
            self.assertEqual(probe.export_assessment(report, destination), 24)
        packet = json.loads((destination / "reviews.json").read_text())
        mapping = json.loads((destination / "private-mapping.json").read_text())
        binding = json.loads((destination / "binding.json").read_text())
        self.assertEqual(len(packet["reviews"]), 24)
        self.assertEqual(len({row["id"] for row in packet["reviews"]}), 24)
        identities = {row["id"]: row for row in mapping}
        for row in packet["reviews"]:
            self.assertEqual(set(row), {"id", "goal", "sourceDocuments", "question", "review", "content_status"})
            self.assertEqual(row["content_status"], "review_available")
            identity = identities[row["id"]]
            job = report["plan"]["jobs"][identity["position"]]
            item = next(item for item in job["subject"]["items"] if item["index"] == identity["item_index"])
            self.assertEqual(row["goal"], job["subject"].get("goal"))
            self.assertEqual(row["sourceDocuments"], job["subject"].get("sourceDocuments"))
            self.assertEqual(row["question"], {k: item[k] for k in ("prompt", "choices", "topic")})
            raw = json.loads(report["calls"][identity["position"]]["observation"]["response"]["text"])
            review = next(r for r in raw["reviews"] if r["index"] == item["index"])
            self.assertEqual(row["review"], {k: v for k, v in review.items() if k != "index"})
        serialized = json.dumps(packet)
        for forbidden in ("independentSolutions", "simulated_returned_questions", "policy_metrics",
                          "solver_context", "withheld_solver_context", "archived_call_index"):
            self.assertNotIn(forbidden, serialized)
        self.assertEqual(binding["capture_canonical_sha256"], probe._hash(report))
        self.assertEqual(binding["plan_sha256"], report["plan_sha256"])
        self.assertEqual(binding["planned_item_occurrences"], 24)
        for filename, digest in binding["files"].items():
            self.assertEqual(hashlib.sha256((destination / filename).read_bytes()).hexdigest(), digest)
        with self.assertRaises(FileExistsError):
            probe.export_assessment(report, destination)

    def test_export_partial_capture_keeps_unavailable_slots_without_fake_reviews(self):
        count = 0

        def observer(request, **kwargs):
            nonlocal count
            count += 1
            if count == 1:
                return completed('Preamble {"reviews": []}')
            if count == 3:
                return completed("{}", status="operational_failure", error_type="ClientError")
            return self.observer(request, **kwargs)

        report = self.run_probe(observer)
        self.assertEqual(count, 3)
        self.assertEqual(report["status"], "operational_failure")
        destination = self.directory / "partial-assessment"
        self.assertEqual(probe.export_assessment(report, destination), 24)
        rows = json.loads((destination / "reviews.json").read_text())["reviews"]
        available = [row for row in rows if row["content_status"] == "review_available"]
        unavailable = [row for row in rows if row["content_status"] == "no_correlated_review"]
        self.assertEqual(len(available), 3)
        self.assertEqual(len(unavailable), 21)
        self.assertTrue(all(row["review"] is None for row in unavailable))

    def test_export_rejects_stale_content_results_and_broken_capture_binding(self):
        original = self.run_probe()

        def alter_raw_response(report):
            response = report["calls"][0]["observation"]["response"]
            value = json.loads(response["text"])
            value["reviews"][0]["answer"] = "A choice never offered"
            response["text"] = json.dumps(value)

        mutations = (
            lambda r: r.update(status="running"),
            lambda r: r.update(plan_sha256="0" * 64),
            lambda r: r["calls"][0].update(request_sha256="0" * 64),
            lambda r: r["calls"].append(copy.deepcopy(r["calls"][0])),
            alter_raw_response,
        )
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                report = copy.deepcopy(original)
                mutate(report)
                destination = self.directory / f"bad-assessment-{index}"
                with self.assertRaises(ValueError):
                    probe.export_assessment(report, destination)
                self.assertFalse(destination.exists())

    def test_changed_rejected_review_is_bound_even_when_policy_outcome_is_unchanged(self):
        def observer(request, **kwargs):
            state = self.observer(request, **kwargs)
            value = json.loads(state["response"]["text"])
            for review in value["reviews"]:
                review.update(valid=False, answer="", explanation="", choiceFeedback=[], difficulty=0)
            state["response"]["text"] = json.dumps(value)
            return state

        report = self.run_probe(observer)
        self.assertEqual(report["status"], "completed")
        self.assertTrue(all(result["simulated_return_count"] == 0 for result in report["results"]))
        state = report["calls"][0]["observation"]
        value = json.loads(state["response"]["text"])
        value["reviews"][0]["difficulty"] = 1
        state["response"]["text"] = json.dumps(value)
        recalculated = probe.content_observation(self.plan["jobs"][0], state)
        prior = {k: v for k, v in report["results"][0].items() if k not in ("position", "status")}
        self.assertEqual({k: v for k, v in recalculated.items() if k != "response_text_sha256"},
                         {k: v for k, v in prior.items() if k != "response_text_sha256"})
        self.assertNotEqual(recalculated["response_text_sha256"], prior["response_text_sha256"])
        with self.assertRaises(ValueError):
            probe.export_assessment(report, self.directory / "stale-rejection-assessment")


class ReviewerIndependenceSourceTests(unittest.TestCase):
    def test_incompatible_sdk_is_rejected_before_any_client_or_worker(self):
        for versions in ({"boto3": "1.43.89", "botocore": "1.43.91"},
                         {"boto3": "1.43.91", "botocore": None}):
            with self.subTest(versions=versions), patch.object(probe.shared, "dependencies", return_value=versions), patch.object(
                probe.shared, "new_client", side_effect=AssertionError("No provider"),
            ), patch.object(probe.native_probe.caller, "observe_request", side_effect=AssertionError("No worker")):
                with self.assertRaisesRegex(ValueError, "packaged"):
                    probe.make_plan()

    def test_unresolvable_source_revision_is_rejected(self):
        with patch.object(probe.shared, "dependencies", return_value=probe.native_probe.REQUIRED_SDK):
            for revision in ("main", "0" * 40):
                with self.subTest(revision=revision), self.assertRaises(ValueError):
                    probe.make_plan(source_revision=revision)


if __name__ == "__main__":
    unittest.main()
