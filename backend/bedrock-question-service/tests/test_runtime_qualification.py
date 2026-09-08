"""Actual runtime with scripted observer responses; no SDK, workers or inference."""

import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_runtime_qualification as trial
from lambda_test_support import _raw_question


FIXTURE = trial.SERVICE_DIR / "evals/fixtures/question_runtime_qualification.json"


def payload(request, tag):
    text = request["messages"][0]["content"][0]["text"]
    return json.loads(text.split(f"<{tag}>\n", 1)[1].split(f"\n</{tag}>", 1)[0])


def completed(value, **changes):
    return {
        "status": "completed", "error_type": None, "provider_dispatch_attempted": True,
        "usage_known": True,
        "response": {
            "text": value if type(value) is str else json.dumps(value, ensure_ascii=False),
            "content_valid": True, "stopReason": "end_turn",
            "usage": {"inputTokens": 11, "outputTokens": 17},
            "reasoningContentBlockCount": 0,
        },
        "local_worker_reaped": True, "local_process_group_cleanup_confirmed": True,
        "worker_exitcode": 0, "termination_attempted": False,
        "sdk_elapsed_seconds": 0.1, "process_elapsed_seconds": 0.2,
        "remote_completion": "response_observed", **changes,
    }


class RuntimeQualificationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.output = self.directory / "capture"
        self.plan_path = self.directory / "plan.json"
        self.packet = json.loads(FIXTURE.read_text())
        self.plan = trial.make_plan(self.packet)
        trial.shared.write_json(self.plan_path, self.plan)
        self.fresh = [_raw_question(prompt) for prompt in (
            "A poll reports 60 of 100 votes. What assumption connects this sample to the population?",
            "A treatment group improved after random allocation. Which inference needs a control comparison?",
            "A forecast is updated after a sensor alarm. What connects the base rate and new evidence?",
            "A factory measures defects only in returned products. Which condition supports extrapolation?",
            "A game repeats independent rounds. Which assumption links one round to the next?",
        )]
        self.questions = {q["prompt"]: q for q in self.fresh}
        self.questions.update({c["question"]["prompt"]: c["question"] for c in self.packet["fixed"]["cases"]})
        self.warranted = {c["question"]["prompt"]: c["assessment"]["warranted_choices"]
                          for c in self.packet["fixed"]["cases"]}

    def run_trial(self, observer=None):
        return trial.run_trial(self.plan_path, trial._hash(self.plan), self.output,
                               observer=observer or self.observer)

    def observer(self, request, *, on_progress, timeout, **_):
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 240)
        saved = json.loads((self.output / "capture.json").read_text())
        call = saved["calls"][-1]
        self.assertEqual(call["request"], request)
        self.assertEqual(call["request_sha256"], trial._hash(request))
        self.assertEqual(call["lifecycle"], "observing")
        self.assertIsNone(call["observation"])
        self.assertEqual(trial.caller.SETTINGS, trial.SETTINGS)
        role = call["role"]
        if role.startswith("author"):
            response = {"questions": self.fresh}
        elif role == "solver":
            items = payload(request, "question_solution_json")["items"]
            response = {"solutions": [{
                "index": item["index"],
                "choices": [{
                    "choice": choice,
                    "judgment": "supported" if choice in self.warranted.get(
                        item["prompt"], [self.questions[item["prompt"]]["expectedAnswer"]]) else "refuted",
                    "reason": "This is a scripted contract observation, not a semantic benchmark.",
                } for choice in reversed(item["choices"])],
            } for item in reversed(items)]}
        else:
            items = payload(request, "question_review_json")["items"]
            response = {"reviews": [{
                "index": item["index"], "valid": True,
                "answer": self.questions[item["prompt"]]["expectedAnswer"], "difficulty": 3,
                "explanation": "The supplied conditions establish the indicated conclusion.",
                "choiceExplanations": {c: "The exact stated facts determine this choice's adequacy."
                                       for c in item["choices"]},
            } for item in reversed(items)]}
        state = completed(response)
        on_progress(copy.deepcopy(state))
        return state

    def test_plan_uses_runtime_prompts_actual_settings_and_no_external_labels(self):
        self.assertEqual(self.plan["maximum_calls"], 8)
        self.assertEqual([j["maximum_calls"] for j in self.plan["operations"]], [2, 6])
        self.assertIn("complete_question_solution.py", self.plan["source_sha256"])
        self.assertIn("evals/checkpoint_author_latency_probe.py", self.plan["source_sha256"])
        for job in self.plan["operations"]:
            request = job["first_request"]
            self.assertEqual(request["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})
            self.assertEqual(request["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})
            self.assertNotIn("assessment", json.dumps(request))
            self.assertNotIn("expected_accept", json.dumps(request))
        solver = payload(self.plan["operations"][0]["first_request"], "question_solution_json")
        self.assertEqual(len(solver["items"]), 5)
        self.assertNotIn("expectedAnswer", json.dumps(solver))
        self.assertNotIn("Deliberately invalid fixed", json.dumps(solver))
        with patch.dict(os.environ, {"BEDROCK_MAX_TOKENS": "10", "BEDROCK_TEMPERATURE": "0.9"}):
            self.assertEqual(trial.make_plan(self.packet), self.plan)

    def test_actual_five_item_batch_survivor_join_fresh_generation_and_exact_replay(self):
        report = self.run_trial()
        self.assertEqual(report["status"], "completed")
        self.assertEqual([c["role"] for c in report["calls"]], ["solver", "reviewer", "author", "solver", "reviewer"])
        fixed, fresh = report["operations"]
        self.assertEqual(len(fixed["questions"]), 2)
        self.assertEqual(len(fresh["questions"]), 5)
        self.assertEqual([q["prompt"] for q in fixed["questions"]], [
            self.packet["fixed"]["cases"][i]["question"]["prompt"] for i in (0, 4)
        ])
        for question in fixed["questions"] + fresh["questions"]:
            self.assertEqual(question["verificationVersion"], 1)
            self.assertEqual(question["verificationPolicyRevision"], 2)
        review_items = payload(report["calls"][1]["request"], "question_review_json")["items"]
        self.assertEqual([i["index"] for i in review_items], [0, 1])
        self.assertEqual([i["prompt"] for i in review_items], [q["prompt"] for q in fixed["questions"]])
        self.assertEqual(report["accounting"]["observed_dispatch_attempts"], 5)
        self.assertEqual(report["accounting"]["known_usage_subtotal"], {"inputTokens": 55, "outputTokens": 85})
        with patch.object(trial.caller, "observe_request", side_effect=AssertionError("No provider")):
            self.assertEqual(trial.replay_capture(report), report)
        self.assertEqual(json.loads((self.output / "capture.json").read_text()), report)
        with self.assertRaises(FileExistsError):
            self.run_trial(Mock())

    def test_runtime_topoff_has_two_distinct_author_requests_and_eight_call_ceiling(self):
        authors = 0

        def observer(request, **kwargs):
            nonlocal authors
            if request["modelId"] == trial.SETTINGS["BEDROCK_MODEL_ID"]:
                authors += 1
                requested = payload(request, "generation_request_json")
                self.assertEqual(requested["targetCount"], 5 if authors == 1 else 3)
                if authors == 2:
                    self.assertEqual(len(requested["existingQuestionCoverage"]), 2)
                return completed({"questions": self.fresh[:2] if authors == 1 else self.fresh[2:]})
            return self.observer(request, **kwargs)

        report = self.run_trial(observer)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 8)
        self.assertEqual(report["operations"][1]["budget_reservations"], 6)
        self.assertEqual(len(report["operations"][1]["questions"]), 5)
        self.assertEqual(trial.replay_capture(report), report)

    def test_failed_topoff_latches_even_when_runtime_returns_prior_accepted_questions(self):
        authors = 0

        def observer(request, **kwargs):
            nonlocal authors
            if request["modelId"] == trial.SETTINGS["BEDROCK_MODEL_ID"]:
                authors += 1
                if authors == 1:
                    return completed({"questions": self.fresh[:2]})
                return {"status": "operational_failure", "error_type": "ReadTimeoutError",
                        "provider_dispatch_attempted": True, "usage_known": False}
            return self.observer(request, **kwargs)

        report = self.run_trial(observer)
        self.assertEqual(len(report["calls"]), 6)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["operations"][1]["runtime_error_type"], None)
        self.assertEqual(len(report["operations"][1]["questions"]), 2)
        self.assertEqual(report["accounting"]["unknown_usage_calls"], 1)
        self.assertEqual(trial.replay_capture(report), report)

    def test_runtime_json_repair_is_explicit_and_raw_text_unchanged(self):
        authors = 0

        def observer(request, **kwargs):
            nonlocal authors
            if request["modelId"] == trial.SETTINGS["BEDROCK_MODEL_ID"]:
                authors += 1
                if authors == 1:
                    return completed("  unfinished JSON {  \n")
            return self.observer(request, **kwargs)

        report = self.run_trial(observer)
        self.assertEqual(report["calls"][2]["observation"]["response"]["text"], "  unfinished JSON {  \n")
        self.assertEqual([c["role"] for c in report["calls"]][2:], ["author", "author_json_repair", "solver", "reviewer"])
        self.assertEqual(trial.replay_capture(report), report)

    def test_legacy_solver_shape_cannot_reach_fixed_review_but_content_failure_continues(self):
        calls = 0

        def observer(request, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 1:
                return completed({"solutions": [{"index": 0, "answer": "Old shape"}]})
            return self.observer(request, **kwargs)

        report = self.run_trial(observer)
        self.assertEqual([c["role"] for c in report["calls"]], ["solver", "author", "solver", "reviewer"])
        self.assertEqual(report["operations"][0]["questions"], [])
        self.assertEqual(len(report["operations"][1]["questions"]), 5)
        self.assertEqual(trial.replay_capture(report), report)

    def test_non_end_turn_cleanup_and_unknown_failure_stop_before_fresh(self):
        states = [completed({}), completed({}), {"status": "operational_failure", "error_type": "ProcessDeadline",
                                                 "provider_dispatch_attempted": None, "usage_known": False}]
        states[0]["response"]["stopReason"] = "max_tokens"
        states[1]["local_process_group_cleanup_confirmed"] = False
        for index, state in enumerate(states):
            with self.subTest(index=index):
                self.output = self.directory / f"failed-{index}"
                observer = Mock(return_value=state)
                report = self.run_trial(observer)
                self.assertEqual(observer.call_count, 1)
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(report["operations"][1]["status"], "unattempted")
                self.assertEqual(trial.replay_capture(report), report)

    def test_plan_and_dynamic_replay_reject_modified_types_keys_and_results(self):
        observer = Mock()
        for changes in ({"maximum_calls": 9}, {"settings": {}}, {"source_sha256": {}}, {"dependencies": {}}):
            plan = {**self.plan, **changes}
            trial.shared.write_json(self.plan_path, plan)
            with self.assertRaises(ValueError):
                self.run_trial(observer)
        observer.assert_not_called()
        self.assertFalse(self.output.exists())
        trial.shared.write_json(self.plan_path, self.plan)
        report = self.run_trial()
        for path, value in (
            (("calls", 0, "request", "inferenceConfig", "maxTokens"), True),
            (("calls", 1, "role"), "solver"),
            (("calls", 0, "request_sha256"), "edited"),
            (("calls", 0, "observation", "usage_known"), 1),
            (("operations", 0, "questions", 0, "expectedAnswer"), "edited"),
            (("status",), "operational_failure"),
        ):
            altered = copy.deepcopy(report)
            target = altered
            for component in path[:-1]:
                target = target[component]
            target[path[-1]] = value
            with self.subTest(path=path), self.assertRaises(ValueError):
                trial.replay_capture(altered)
        altered = copy.deepcopy(report)
        altered["calls"].append(copy.deepcopy(altered["calls"][-1]))
        with self.assertRaises(ValueError):
            trial.replay_capture(altered)

    def test_progress_write_failure_stops_even_when_observer_swallows_callback_error(self):
        original = trial.shared.write_json
        writes = 0

        def write(path, value):
            nonlocal writes
            writes += 1
            if writes == 5:
                raise OSError("Synthetic unavailable disk")
            return original(path, value)

        def observer(request, *, on_progress, **_):
            state = completed({"solutions": []})
            try:
                on_progress(state)
            except OSError:
                pass
            return state

        observer = Mock(side_effect=observer)
        with patch.object(trial.shared, "write_json", side_effect=write):
            report = self.run_trial(observer)
        self.assertEqual(observer.call_count, 1)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(trial.replay_capture(report), report)

    def test_request_write_failure_prevents_observer_and_replays_recorded_prefix(self):
        original = trial.shared.write_json
        writes = 0

        def write(path, value):
            nonlocal writes
            writes += 1
            if writes == 3:
                raise OSError("Synthetic unavailable disk")
            return original(path, value)

        observer = Mock()
        with patch.object(trial.shared, "write_json", side_effect=write):
            report = self.run_trial(observer)
        observer.assert_not_called()
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(trial.replay_capture(report), report)

    def test_deadline_and_input_caps_refuse_additional_dispatch(self):
        report = trial._empty_report(self.plan)
        client = trial._RuntimeClient(report, lambda: None, Mock())
        client.operation_index = 0
        client.context = Mock(get_remaining_time_in_millis=Mock(return_value=0))
        with patch.dict(os.environ, trial.SETTINGS), self.assertRaises(ValueError):
            client.converse(**self.plan["operations"][0]["first_request"])
        client.observer.assert_not_called()
        client = trial._RuntimeClient(trial._empty_report(self.plan), lambda: None, Mock())
        client.operation_index = 0
        request = copy.deepcopy(self.plan["operations"][0]["first_request"])
        request["messages"][0]["content"][0]["text"] += "x" * trial.MAX_INPUT_BYTES
        with patch.dict(os.environ, trial.SETTINGS), self.assertRaises(ValueError):
            client.converse(**request)
        client.observer.assert_not_called()

    def test_slow_successful_prelaunch_write_rechecks_clock_before_observer(self):
        original = trial.shared.write_json
        clock = [100.0]
        writes = 0

        def write(path, value):
            nonlocal writes
            writes += 1
            result = original(path, value)
            if writes == 4:  # request and admission intent are durable
                clock[0] += 241
            return result

        observer = Mock()
        with patch.object(trial.time, "monotonic", side_effect=lambda: clock[0]), patch.object(
            trial.shared, "write_json", side_effect=write,
        ):
            report = self.run_trial(observer)
        observer.assert_not_called()
        self.assertEqual(report["status"], "operational_failure")
        call = report["calls"][0]
        self.assertEqual(call["prepared_remaining_milliseconds"], 240000)
        self.assertEqual(call["timeout_seconds"], 0.0)
        self.assertEqual(call["failure_phase"], "deadline_admission")
        self.assertFalse(call["observer_started"])
        self.assertEqual(report["accounting"]["known_not_dispatched_calls"], 1)
        self.assertEqual(trial.replay_capture(report), report)

    def test_dry_cli_and_replay_never_initialize_provider(self):
        with patch.object(trial.caller, "observe_request", side_effect=AssertionError("No provider")):
            self.assertEqual(trial.main(["--fixture", str(FIXTURE), "--output", str(self.output)]), 0)
        self.assertEqual(json.loads((self.output / "plan.json").read_text()), self.plan)

    def test_replay_cannot_claim_observer_admitted_after_its_deadline(self):
        report = self.run_trial()
        saved = copy.deepcopy(report["calls"][0])
        saved["prepared_remaining_milliseconds"] = 240000
        saved["timeout_seconds"] = 0.0
        derived = trial._empty_report(self.plan)
        client = trial._RuntimeClient(derived, lambda: None, Mock(), replay=[saved])
        client.operation_index = 0
        client.context = trial._OperationContext(derived["operations"][0], [240000, 0])
        with patch.dict(os.environ, trial.SETTINGS), self.assertRaisesRegex(ValueError, "deadline gate"):
            client.converse(**saved["request"])
        client.observer.assert_not_called()


class FrozenRuntimeRecheckTests(unittest.TestCase):
    """Synthetic current-source origins avoid pinning production to old code."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.output = self.directory / "capture"
        self.plan_path = self.directory / "plan.json"
        self.packet = {"experiment": trial.RECHECK_EXPERIMENT}
        prior = trial.make_plan(json.loads(FIXTURE.read_text()))
        request = prior["operations"][1]["request"]
        raw_questions = [_raw_question(
            f"Observation set {i} records a baseline and a changed condition. Which conclusion follows from these facts?"
        ) for i in range(5)]
        candidates = trial._sanitize_questions(raw_questions, request)
        with patch.dict(os.environ, trial.SETTINGS):
            first = trial._first_request(request, candidates)
        # Evaluator provenance may differ; production/prompt sources must match.
        prior["source_sha256"]["evals/checkpoint_runtime_qualification.py"] = "0" * 64
        self.origin = {
            "plan": prior, "plan_sha256": trial._hash(prior), "status": "completed",
            "calls": [{}, {}, {
                "role": "author", "request": prior["operations"][1]["first_request"],
                "observation": completed({"questions": raw_questions}),
            }, {"request": first}, {}],
        }
        origin_bytes = json.dumps(self.origin, ensure_ascii=False).encode("utf-8")
        origin_path = Mock(wraps=trial.RECHECK_ORIGIN)
        origin_path.read_bytes.return_value = origin_bytes
        origin_path.read_text.return_value = origin_bytes.decode("utf-8")
        for target, value in (("RECHECK_ORIGIN", origin_path),
                              ("RECHECK_ORIGIN_SHA256", hashlib.sha256(origin_bytes).hexdigest())):
            replacement = patch.object(trial, target, value)
            replacement.start()
            self.addCleanup(replacement.stop)
        self.plan = trial.make_plan(self.packet)
        trial.shared.write_json(self.plan_path, self.plan)
        self.questions = self.plan["operations"][0]["questions"]
        self.keys = {q["prompt"]: q["expectedAnswer"] for q in self.questions}
        self.excluded = {self.questions[i]["prompt"] for i in (0, 2)}

    def run_trial(self, observer=None):
        return trial.run_trial(self.plan_path, trial._hash(self.plan), self.output,
                               observer=observer or self.observer)

    def observer(self, request, *, on_progress, timeout, **_):
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 240)
        report = json.loads((self.output / "capture.json").read_text())
        call = report["calls"][-1]
        job = self.plan["operations"][call["operation_index"]]
        self.assertEqual(call["request"], request)
        self.assertEqual(call["request_sha256"], trial._hash(request))
        self.assertEqual(trial.caller.SETTINGS, job["settings"])
        adaptive = job["arm"] == "adaptive"
        if call["role"] == "solver":
            items = payload(request, "question_solution_json")["items"]
            value = {"solutions": [{
                "index": item["index"], "choices": [{
                    "choice": choice,
                    "judgment": "supported" if choice == self.keys[item["prompt"]]
                    and not (adaptive and item["prompt"] in self.excluded) else "refuted",
                    "reason": "A scripted declared judgment for transport testing only.",
                } for choice in reversed(item["choices"])],
            } for item in reversed(items)]}
        else:
            self.assertEqual(call["role"], "reviewer")
            data = payload(request, "question_review_json")
            items = data["items"]
            self.assertEqual([i["index"] for i in items], list(range(len(items))))
            self.assertEqual(len(items), 3 if adaptive else 5)
            self.assertEqual([i["index"] for i in data["independentSolutions"]], list(range(len(items))))
            value = {"reviews": [{
                "index": item["index"], "valid": True, "difficulty": 3,
                "answer": self.keys[item["prompt"]],
                "explanation": "This is scripted feedback for a transport test, not a factual assessment.",
                "choiceExplanations": {c: "This scripted explanation only tests exact response binding."
                                       for c in item["choices"]},
            } for item in reversed(items)]}
        state = completed(value)
        state["response"]["reasoningContentBlockCount"] = int(adaptive)
        on_progress(copy.deepcopy(state))
        return state

    def test_exact_archive_reconstruction_same_inputs_and_only_allowed_request_differences(self):
        with patch.object(trial, "_normalize_request", wraps=trial._normalize_request) as normalize:
            self.assertEqual(trial.make_plan(self.packet), self.plan)
        normalize.assert_called_once_with(self.origin["plan"]["fixture"]["fresh"]["payload"])
        self.assertEqual(self.plan["maximum_calls"], 4)
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 4 * trial.MAX_INPUT_BYTES)
        disabled, adaptive = self.plan["operations"]
        self.assertEqual([j["arm"] for j in (disabled, adaptive)], ["disabled", "adaptive"])
        self.assertEqual([j["maximum_calls"] for j in (disabled, adaptive)], [2, 2])
        self.assertEqual(disabled["request"], self.origin["plan"]["operations"][1]["request"])
        self.assertEqual(disabled["request"], adaptive["request"])
        self.assertEqual(disabled["questions"], adaptive["questions"])
        self.assertEqual(len(disabled["questions"]), 5)
        self.assertEqual(disabled["first_request"], self.origin["calls"][3]["request"])
        for key in ("modelId", "messages", "system"):
            self.assertEqual(disabled["first_request"][key], adaptive["first_request"][key])
        self.assertEqual(adaptive["first_request"]["inferenceConfig"], {"maxTokens": 6000})
        self.assertEqual(adaptive["first_request"]["additionalModelRequestFields"], {
            "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"},
        })
        provenance = self.plan["origin"]
        self.assertEqual(provenance["capture_sha256"], hashlib.sha256(trial.RECHECK_ORIGIN.read_bytes()).hexdigest())
        self.assertEqual(provenance["normalized_request_sha256"], trial._hash(disabled["request"]))
        self.assertEqual(provenance["sanitized_candidates_sha256"], trial._hash(self.questions))
        self.assertNotEqual(self.plan["source_sha256"]["evals/checkpoint_runtime_qualification.py"],
                            provenance["source_sha256"]["evals/checkpoint_runtime_qualification.py"])
        sent = payload(disabled["first_request"], "question_solution_json")
        self.assertEqual(len(sent["items"]), 5)
        for item in sent["items"]:
            self.assertFalse(set(item) & {"expectedAnswer", "explanation", "choiceExplanations", "assessment", "difficulty"})

    def test_both_arms_use_actual_survivor_filtering_four_calls_and_exact_replay(self):
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")):
            report = self.run_trial()
            self.assertEqual(trial.replay_capture(report), report)
        self.assertEqual(report["status"], "completed")
        self.assertEqual([c["role"] for c in report["calls"]], ["solver", "reviewer"] * 2)
        self.assertEqual([c["operation_index"] for c in report["calls"]], [0, 0, 1, 1])
        self.assertEqual([len(j["questions"]) for j in report["operations"]], [5, 3])
        self.assertEqual([j["budget_reservations"] for j in report["operations"]], [2, 2])
        self.assertEqual([q["prompt"] for q in report["operations"][1]["questions"]],
                         [q["prompt"] for q in self.questions if q["prompt"] not in self.excluded])
        self.assertEqual(report["accounting"]["known_usage_subtotal"], {"inputTokens": 44, "outputTokens": 68})
        for index in (0, 2):
            self.assertEqual(report["calls"][index]["request"], self.plan["operations"][index // 2]["first_request"])
        for call_index in (1, 3):
            changed = copy.deepcopy(report)
            changed["calls"][call_index]["request"]["messages"][0]["content"][0]["text"] += "changed"
            with self.assertRaises(ValueError):
                trial.replay_capture(changed)

    def test_zero_survivors_and_malformed_response_do_not_force_review_or_repair(self):
        def none_supported(request, **_):
            items = payload(request, "question_solution_json")["items"]
            return completed({"solutions": [{
                "index": i["index"], "choices": [{"choice": c, "judgment": "refuted", "reason": "Scripted refutation."}
                                                   for c in i["choices"]],
            } for i in items]})
        for index, observer in enumerate((none_supported, Mock(return_value=completed("malformed JSON")))):
            self.output = self.directory / f"content-{index}"
            report = self.run_trial(observer)
            self.assertEqual(report["status"], "completed")
            self.assertEqual([c["role"] for c in report["calls"]], ["solver", "solver"])
            self.assertTrue(all(not j["questions"] for j in report["operations"]))
            self.assertEqual(trial.replay_capture(report), report)

    def test_recheck_profiles_caps_order_source_and_inputs_cannot_be_modified(self):
        paths = [
            (("maximum_calls",), 5), (("maximum_input_utf8_bytes_total",), 999999),
            (("operations", 1, "maximum_calls"), 3), (("operations", 1, "arm"), "disabled"),
            (("operations", 1, "settings", "BEDROCK_THINKING_MAX_TOKENS"), "16000"),
            (("operations", 1, "settings", "BEDROCK_CLAUDE_EFFORT"), "max"),
            (("operations", 1, "first_request", "inferenceConfig", "maxTokens"), True),
            (("operations", 0, "request", "minimumDifficulty"), 1),
            (("origin", "capture_sha256"), "wrong"), (("source_sha256", "question_verification.py"), "wrong"),
        ]
        observer = Mock()
        for path, value in paths:
            changed = copy.deepcopy(self.plan)
            target = changed
            for part in path[:-1]:
                target = target[part]
            target[path[-1]] = value
            trial.shared.write_json(self.plan_path, changed)
            with self.subTest(path=path), self.assertRaises(ValueError):
                trial.run_trial(self.plan_path, trial._hash(changed), self.output, observer=observer)
        observer.assert_not_called()
        self.assertFalse(self.output.exists())
        with self.assertRaises(ValueError):
            trial.make_plan({**self.packet, "profile": "adaptive"})
        with patch.object(trial, "RECHECK_ORIGIN_SHA256", "wrong"), self.assertRaisesRegex(ValueError, "origin capture"):
            trial.make_plan(self.packet)
        original_snapshot = trial._source_snapshot(None)
        original_snapshot["source_sha256"]["question_verification.py"] = "changed"
        with patch.object(trial, "_source_snapshot", return_value=original_snapshot), self.assertRaisesRegex(ValueError, "Runtime sources"):
            trial.make_plan(self.packet)

    def test_later_arm_failure_stops_without_retries_and_preserves_earlier_results(self):
        def observer(request, **kwargs):
            if trial.caller.SETTINGS["BEDROCK_CLAUDE_THINKING"] == "adaptive":
                return {"status": "operational_failure", "error_type": "ReadTimeoutError",
                        "provider_dispatch_attempted": True, "usage_known": False}
            return self.observer(request, **kwargs)
        report = self.run_trial(observer)
        self.assertEqual(len(report["calls"]), 3)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(len(report["operations"][0]["questions"]), 5)
        self.assertEqual(report["operations"][1]["questions"], [])
        self.assertEqual(report["accounting"]["unknown_usage_calls"], 1)
        self.assertEqual(trial.replay_capture(report), report)

    def test_recheck_prelaunch_deadline_input_role_and_call_caps_prevent_dispatch(self):
        for mode in (0, 1):
            job = self.plan["operations"][mode]
            for violation in ("deadline", "bytes", "calls", "author"):
                report = trial._empty_report(self.plan)
                client = trial._RuntimeClient(report, lambda: None, Mock())
                client.operation_index, client.settings = mode, job["settings"]
                client.context = Mock(get_remaining_time_in_millis=Mock(return_value=79000))
                request = copy.deepcopy(job["first_request"])
                if violation == "deadline":
                    client.context.get_remaining_time_in_millis.side_effect = [240000, 0]
                elif violation == "bytes":
                    request["messages"][0]["content"][0]["text"] += "é" * trial.MAX_INPUT_BYTES
                elif violation == "calls":
                    report["calls"] = [{"operation_index": mode}] * 2
                else:
                    request = copy.deepcopy(self.origin["calls"][2]["request"])
                with patch.dict(os.environ, job["settings"]), self.subTest(mode=mode, violation=violation), self.assertRaises(Exception):
                    client.converse(**request)
                client.observer.assert_not_called()

    def test_recheck_dry_cli_never_creates_client_and_uses_fresh_directory(self):
        fixture = self.directory / "fixture.json"
        trial.shared.write_json(fixture, self.packet)
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")), patch.object(
            trial.caller, "observe_request", side_effect=AssertionError("No worker"),
        ):
            self.assertEqual(trial.main(["--fixture", str(fixture), "--output", str(self.output)]), 0)
        self.assertEqual(json.loads((self.output / "plan.json").read_text()), self.plan)
        with self.assertRaises(FileExistsError):
            trial.main(["--fixture", str(fixture), "--output", str(self.output)])


class FreshAuthoredSolutionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.output = self.directory / "capture"
        self.plan_path = self.directory / "plan.json"
        fixture = trial.SERVICE_DIR.parents[1] / "docs/evidence/authored-solution-fresh-fixture-20260908.json"
        self.packet = json.loads(fixture.read_text())
        for case in self.packet["cases"]:
            case["prospective_independent_assessment"]["test_sentinel"] = "EXTERNAL ASSESSMENT MUST NOT BE SENT"
        self.plan = trial.make_plan(self.packet)
        trial.shared.write_json(self.plan_path, self.plan)
        self.questions = [[_raw_question(
            f"Observation set {goal}-{i} states a relation and its condition. Which conclusion follows?",
            explanation=f"  Use the stated relation for case {goal}-{i}.\r\n    Apply its condition to establish the conclusion.  ",
        ) for i in range(2)] for goal in range(3)]
        self.by_prompt = {q["prompt"]: q for batch in self.questions for q in batch}

    def run_trial(self, observer=None):
        return trial.run_trial(self.plan_path, trial._hash(self.plan), self.output,
                               observer=observer or self.observer)

    def observer(self, request, *, on_progress, timeout, **_):
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 240)
        saved = json.loads((self.output / "capture.json").read_text())
        call = saved["calls"][-1]
        operation = call["operation_index"]
        self.assertEqual(call["request"], request)
        self.assertEqual(trial.caller.SETTINGS,
                         self.plan["operations"][operation].get("settings", self.plan["settings"]))
        self.assertNotIn("EXTERNAL ASSESSMENT MUST NOT BE SENT", json.dumps(request))
        self.assertEqual(request["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})
        if call["role"].startswith("author"):
            value = {"questions": self.questions[operation]}
        elif call["role"] == "solver":
            data = payload(request, "question_solution_json")
            self.assertEqual(data["sourceDocuments"], self.plan["operations"][operation]["request"]["sourceDocuments"])
            for item in data["items"]:
                self.assertFalse(set(item) & {"explanation", "expectedAnswer", "difficulty"})
            value = {"solutions": [{
                "index": item["index"], "choices": [{
                    "choice": c, "judgment": "supported" if c == self.by_prompt[item["prompt"]]["expectedAnswer"] else "refuted",
                    "reason": "SOLVER REASON MUST NOT REACH TEACHING AUDITOR",
                } for c in item["choices"]],
            } for item in data["items"]]}
        else:
            self.assertEqual(call["role"], "teaching_auditor")
            self.assertNotIn("SOLVER REASON MUST NOT REACH", json.dumps(request))
            data = payload(request, "question_review_json")
            self.assertNotIn("independentSolutions", data)
            self.assertEqual(data["sourceDocuments"], self.plan["operations"][operation]["request"]["sourceDocuments"])
            for item in data["items"]:
                self.assertEqual(item["explanation"], self.by_prompt[item["prompt"]]["explanation"])
                self.assertFalse(set(item) & {"expectedAnswer", "difficulty", "choiceExplanations"})
            value = {"reviews": [{"index": item["index"], "valid": True,
                                   "answer": self.by_prompt[item["prompt"]]["expectedAnswer"],
                                   "difficulty": 3, "explanationSupport": "supported", "issues": []}
                                  for item in reversed(data["items"])]}
        state = completed(value)
        on_progress(copy.deepcopy(state))
        return state

    def test_actual_three_goal_path_preserves_authored_main_with_nine_call_bound_and_replay(self):
        self.assertEqual(self.plan["maximum_calls"], 9)
        self.assertEqual([j["maximum_calls"] for j in self.plan["operations"]], [3, 3, 3])
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 9 * 32768)
        self.assertIn("question_teaching.py", self.plan["source_sha256"])
        self.assertEqual(self.plan["settings"]["GENERATION_ATTEMPTS"], "1")
        self.assertEqual(self.plan["settings"]["MAX_PROVIDER_CALLS_PER_REQUEST"], "3")
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")):
            report = self.run_trial()
            self.assertEqual(trial.replay_capture(report), report)
        self.assertEqual(report["status"], "completed")
        self.assertEqual([c["role"] for c in report["calls"]], ["author", "solver", "teaching_auditor"] * 3)
        self.assertEqual(report["accounting"]["observed_dispatch_attempts"], 9)
        for index, operation in enumerate(report["operations"]):
            self.assertEqual(operation["budget_reservations"], 3)
            self.assertEqual(operation["authored_solution_observation"], {
                "requested_count": 2, "returned_count": 2, "author_json_repair_calls": 0,
                "full_unrepaired_batch": True,
            })
            author_call = report["calls"][index * 3]
            self.assertEqual(author_call["request"], self.plan["operations"][index]["first_request"])
            raw_authored = json.loads(author_call["observation"]["response"]["text"])["questions"]
            for original, returned in zip(raw_authored, operation["questions"], strict=True):
                self.assertEqual(original["explanation"].encode(), returned["explanation"].encode())
                self.assertEqual(returned["choiceExplanations"], {})
                self.assertEqual(returned["verificationPolicyRevision"], 3)
        tampered = copy.deepcopy(report)
        tampered["operations"][2]["questions"][0]["explanation"] += " replacement"
        with self.assertRaises(ValueError):
            trial.replay_capture(tampered)

    def test_fresh_fixture_and_execution_settings_are_fixed_before_any_client(self):
        for edit in ("count", "duplicate", "target", "floor", "constraints"):
            packet = copy.deepcopy(self.packet)
            if edit == "count":
                packet["cases"].pop()
            elif edit == "duplicate":
                packet["cases"][1]["case_id"] = packet["cases"][0]["case_id"]
            elif edit == "target":
                packet["cases"][0]["payload"]["targetCount"] = True
            elif edit == "floor":
                packet["cases"][0]["payload"]["minimumDifficulty"] = 2
            else:
                packet["trial_constraints"]["environment"]["GENERATION_ATTEMPTS"] = "2"
            with self.subTest(edit=edit), self.assertRaises(ValueError):
                trial.make_plan(packet)
        observer = Mock()
        for path, value in ((("maximum_calls",), 10), (("settings", "QUESTION_FEEDBACK_CONTRACT"), "reviewer_written"),
                            (("settings", "GENERATION_ATTEMPTS"), "2"), (("operations", 2, "maximum_calls"), 4)):
            changed = copy.deepcopy(self.plan)
            target = changed
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] = value
            trial.shared.write_json(self.plan_path, changed)
            with self.assertRaises(ValueError):
                trial.run_trial(self.plan_path, trial._hash(changed), self.output, observer=observer)
        observer.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_existing_repair_uses_same_three_calls_and_cannot_complete_or_start_later_goals(self):
        calls = 0
        def observer(request, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 1:
                return completed("Malformed original author {\n")
            return self.observer(request, **kwargs)
        report = self.run_trial(observer)
        self.assertEqual([c["role"] for c in report["calls"]], ["author", "author_json_repair", "solver"])
        self.assertEqual(report["calls"][0]["observation"]["response"]["text"], "Malformed original author {\n")
        self.assertEqual(report["operations"][0]["budget_reservations"], 3)
        self.assertEqual(report["operations"][0]["authored_solution_observation"], {
            "requested_count": 2, "returned_count": 0, "author_json_repair_calls": 1,
            "full_unrepaired_batch": False,
        })
        self.assertEqual(report["operations"][0]["runtime_error_type"], "ProviderCallBudgetExceededError")
        self.assertEqual([j["status"] for j in report["operations"]][1:], ["unattempted", "unattempted"])
        self.assertEqual(trial.replay_capture(report), report)

    def test_unsupported_teaching_is_content_rejection_but_cleanup_failure_stops_later_goals(self):
        def reject_teaching(request, **kwargs):
            state = self.observer(request, **kwargs)
            value = json.loads(state["response"]["text"])
            if "reviews" in value:
                for row in value["reviews"]:
                    row["explanationSupport"] = "unsupported"
                state["response"]["text"] = json.dumps(value)
            return state
        report = self.run_trial(reject_teaching)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 9)
        self.assertTrue(all(not j["questions"] and not j["authored_solution_observation"]["full_unrepaired_batch"]
                            for j in report["operations"]))
        self.assertEqual(trial.replay_capture(report), report)
        self.output = self.directory / "failed-cleanup"
        failure = completed({})
        failure["local_process_group_cleanup_confirmed"] = False
        observer = Mock(return_value=failure)
        report = self.run_trial(observer)
        observer.assert_called_once()
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual([j["status"] for j in report["operations"]][1:], ["unattempted", "unattempted"])

    def test_historical_feedback_is_explicitly_pinned_and_fresh_dry_mode_has_no_client(self):
        baseline_packet = json.loads(FIXTURE.read_text())
        baseline = trial.make_plan(baseline_packet)
        with patch.dict(os.environ, {"QUESTION_FEEDBACK_CONTRACT": "authored_solution"}):
            self.assertEqual(trial.make_plan(baseline_packet), baseline)
        self.assertEqual(baseline["settings"]["QUESTION_FEEDBACK_CONTRACT"], "reviewer_written")
        fixture = self.directory / "fixture.json"
        trial.shared.write_json(fixture, self.packet)
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")), patch.object(
            trial.caller, "observe_request", side_effect=AssertionError("No worker"),
        ):
            self.assertEqual(trial.main(["--fixture", str(fixture), "--output", str(self.output)]), 0)
        self.assertEqual(json.loads((self.output / "plan.json").read_text()), self.plan)


class AuthoredAuthorComparisonTests(unittest.TestCase):
    # Reuse the existing scripted author/solver/auditor seam, not live workers.
    observer = FreshAuthoredSolutionTests.observer
    run_trial = FreshAuthoredSolutionTests.run_trial

    def setUp(self):
        FreshAuthoredSolutionTests.setUp(self)
        self.packet = {"experiment": trial.AUTHOR_COMPARISON_EXPERIMENT}
        self.plan = trial.make_plan(self.packet)
        trial.shared.write_json(self.plan_path, self.plan)
        self.questions = [copy.deepcopy(batch) for batch in self.questions for _ in range(2)]

    def test_six_operations_preserve_paired_inputs_mains_and_eighteen_call_replay(self):
        self.assertEqual(self.plan["maximum_calls"], 18)
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 18 * 32768)
        self.assertEqual([j["arm"] for j in self.plan["operations"]],
                         ["kimi", "opus", "opus", "kimi", "kimi", "opus"])
        for left, right in zip(self.plan["operations"][::2], self.plan["operations"][1::2], strict=True):
            self.assertEqual(left["case_id"], right["case_id"])
            self.assertEqual(left["request"], right["request"])
            self.assertEqual({k: v for k, v in left["first_request"].items() if k != "modelId"},
                             {k: v for k, v in right["first_request"].items() if k != "modelId"})
            self.assertNotEqual(left["first_request"]["modelId"], right["first_request"]["modelId"])
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")):
            report = self.run_trial()
            self.assertEqual(trial.replay_capture(report), report)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 18)
        self.assertEqual([c["role"] for c in report["calls"]], ["author", "solver", "teaching_auditor"] * 6)
        for index, (job, result) in enumerate(zip(self.plan["operations"], report["operations"], strict=True)):
            for key in ("arm", "case_id", "settings"):
                self.assertEqual(result[key], job[key])
            self.assertEqual(result["budget_reservations"], 3)
            self.assertTrue(result["authored_solution_observation"]["full_unrepaired_batch"])
            calls = report["calls"][index * 3:index * 3 + 3]
            self.assertEqual(calls[0]["request"], job["first_request"])
            self.assertEqual([c["request"]["modelId"] for c in calls],
                             [job["settings"]["BEDROCK_MODEL_ID"], "us.anthropic.claude-sonnet-4-6",
                              "us.anthropic.claude-sonnet-4-6"])
            for original, returned in zip(self.questions[index], result["questions"], strict=True):
                self.assertEqual(original["explanation"].encode(), returned["explanation"].encode())
                self.assertEqual(returned["choiceExplanations"], {})
                self.assertEqual(returned["verificationPolicyRevision"], 3)

    def test_fixed_origin_profiles_and_model_roles_reject_drift_before_dispatch(self):
        with self.assertRaises(ValueError):
            trial.make_plan({**self.packet, "payload": {}})
        altered_origin = Mock(wraps=trial.AUTHOR_COMPARISON_ORIGIN)
        altered_origin.read_bytes.return_value = b'{"modified":true}'
        with patch.object(trial, "AUTHOR_COMPARISON_ORIGIN", altered_origin), self.assertRaises(ValueError):
            trial.make_plan(self.packet)
        self.assertEqual(self.plan["origin"]["fixture_byte_sha256"], trial.AUTHOR_COMPARISON_ORIGIN_SHA256)
        origin = json.loads(trial.AUTHOR_COMPARISON_ORIGIN.read_text())
        self.assertEqual(self.plan["origin"]["fixture"], origin)
        for index, case in enumerate(origin["cases"]):
            self.assertEqual(self.plan["operations"][index * 2]["request"],
                             trial._normalize_request(copy.deepcopy(case["payload"])))
        for job in self.plan["operations"][:2]:
            with patch.dict(os.environ, job["settings"]):
                wrong_model = copy.deepcopy(job["first_request"])
                wrong_model["modelId"] = job["settings"]["BEDROCK_VERIFICATION_MODEL_ID"]
                self.assertEqual(trial._role(wrong_model), "author")
                with self.assertRaises(ValueError):
                    trial._guard_request(wrong_model, job["settings"])
        observer = Mock()
        for path, value in ((("maximum_calls",), 19), (("operations", 1, "maximum_calls"), 4),
                            (("operations", 1, "settings", "BEDROCK_MAX_TOKENS"), "16000"),
                            (("operations", 1, "settings", "BEDROCK_VERIFICATION_MODEL_ID"), "us.anthropic.claude-opus-4-6-v1")):
            changed = copy.deepcopy(self.plan)
            target = changed
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] = value
            trial.shared.write_json(self.plan_path, changed)
            with self.assertRaises(ValueError):
                trial.run_trial(self.plan_path, trial._hash(changed), self.output, observer=observer)
        observer.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_comparison_dry_run_does_not_change_existing_modes_or_start_workers(self):
        old_packet = json.loads(FIXTURE.read_text())
        old_plan = trial.make_plan(old_packet)
        fresh_packet = json.loads(trial.AUTHOR_COMPARISON_ORIGIN.read_text())
        fresh_plan = trial.make_plan(fresh_packet)
        fixture = self.directory / "comparison.json"
        trial.shared.write_json(fixture, self.packet)
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")), patch.object(
            trial.caller, "observe_request", side_effect=AssertionError("No worker"),
        ), patch.dict(os.environ, self.plan["operations"][1]["settings"]):
            self.assertEqual(trial.main(["--fixture", str(fixture), "--output", str(self.output)]), 0)
            self.assertEqual(trial.make_plan(old_packet), old_plan)
            self.assertEqual(trial.make_plan(fresh_packet), fresh_plan)
        self.assertEqual(json.loads((self.output / "plan.json").read_text()), self.plan)
        self.assertEqual(old_plan["settings"]["QUESTION_FEEDBACK_CONTRACT"], "reviewer_written")
        self.assertEqual([j["first_request"]["modelId"] for j in fresh_plan["operations"]],
                         ["moonshotai.kimi-k2.5"] * 3)


class FocusedApplicationComparisonTests(unittest.TestCase):
    observer = FreshAuthoredSolutionTests.observer
    run_trial = FreshAuthoredSolutionTests.run_trial

    def setUp(self):
        FreshAuthoredSolutionTests.setUp(self)
        self.packet = {"experiment": trial.FOCUSED_APPLICATION_EXPERIMENT}
        self.plan = trial.make_plan(self.packet)
        trial.shared.write_json(self.plan_path, self.plan)
        self.questions = [copy.deepcopy(batch) for batch in self.questions for _ in range(2)]

    def test_system_only_pairs_execute_six_operations_and_replay_exact_teaching(self):
        self.assertEqual([j["arm"] for j in self.plan["operations"]],
                         ["balanced", "focused_application", "focused_application", "balanced",
                          "balanced", "focused_application"])
        self.assertEqual(self.plan["maximum_calls"], 18)
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 18 * 32768)
        for left, right in zip(self.plan["operations"][::2], self.plan["operations"][1::2], strict=True):
            self.assertEqual(left["request"], right["request"])
            self.assertEqual({k: v for k, v in left["settings"].items() if k != "CHECKPOINT_PROMPT_VARIANT"},
                             {k: v for k, v in right["settings"].items() if k != "CHECKPOINT_PROMPT_VARIANT"})
            self.assertEqual({k: v for k, v in left["first_request"].items() if k != "system"},
                             {k: v for k, v in right["first_request"].items() if k != "system"})
            self.assertNotEqual(left["first_request"]["system"], right["first_request"]["system"])
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")):
            report = self.run_trial()
            self.assertEqual(trial.replay_capture(report), report)
        self.assertEqual(report["status"], "completed")
        self.assertEqual([c["role"] for c in report["calls"]], ["author", "solver", "teaching_auditor"] * 6)
        self.assertEqual([c["request"]["modelId"] for c in report["calls"]],
                         ["moonshotai.kimi-k2.5", "us.anthropic.claude-sonnet-4-6",
                          "us.anthropic.claude-sonnet-4-6"] * 6)
        for index, (job, result) in enumerate(zip(self.plan["operations"], report["operations"], strict=True)):
            for key in ("case_id", "arm", "settings"):
                self.assertEqual(result[key], job[key])
            self.assertEqual(result["budget_reservations"], 3)
            self.assertTrue(result["authored_solution_observation"]["full_unrepaired_batch"])
            self.assertEqual(report["calls"][index * 3]["request"], job["first_request"])
            for original, returned in zip(self.questions[index], result["questions"], strict=True):
                self.assertEqual(original["explanation"].encode(), returned["explanation"].encode())
                self.assertEqual(returned["verificationPolicyRevision"], 3)
                self.assertEqual(returned["choiceExplanations"], {})

    def test_identical_systems_non_system_changes_and_modified_origin_fail_closed(self):
        balanced = self.plan["operations"][0]["first_request"]["system"][0]["text"]
        with patch.object(trial.generation, "_system_prompt", return_value=balanced), self.assertRaises(ValueError):
            trial.make_plan(self.packet)
        original = trial._first_request
        def changed_user(*args, **kwargs):
            request = original(*args, **kwargs)
            if kwargs.get("settings", {}).get("CHECKPOINT_PROMPT_VARIANT") == "focused_application":
                request["messages"][0]["content"][0]["text"] += " Extra treatment context"
            return request
        with patch.object(trial, "_first_request", side_effect=changed_user), self.assertRaises(ValueError):
            trial.make_plan(self.packet)
        origin = Mock(wraps=trial.AUTHOR_COMPARISON_ORIGIN)
        origin.read_bytes.return_value = b'{"modified":true}'
        with patch.object(trial, "AUTHOR_COMPARISON_ORIGIN", origin), self.assertRaises(ValueError):
            trial.make_plan(self.packet)
        with self.assertRaises(ValueError):
            trial.make_plan({**self.packet, "variant": "compact"})

    def test_frozen_profile_tampering_blocks_dispatch_and_old_modes_remain_isolated(self):
        observer = Mock()
        for path, value in ((("operations", 1, "settings", "BEDROCK_MODEL_ID"), "us.anthropic.claude-opus-4-6-v1"),
                            (("operations", 1, "settings", "CHECKPOINT_PROMPT_VARIANT"), "compact"),
                            (("maximum_calls",), 19)):
            altered = copy.deepcopy(self.plan)
            target = altered
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] = value
            trial.shared.write_json(self.plan_path, altered)
            with self.assertRaises(ValueError):
                trial.run_trial(self.plan_path, trial._hash(altered), self.output, observer=observer)
        observer.assert_not_called()
        self.assertFalse(self.output.exists())
        packets = [json.loads(FIXTURE.read_text()), json.loads(trial.AUTHOR_COMPARISON_ORIGIN.read_text()),
                   {"experiment": trial.AUTHOR_COMPARISON_EXPERIMENT}]
        before = [trial.make_plan(packet) for packet in packets]
        with patch.dict(os.environ, self.plan["operations"][1]["settings"]):
            self.assertEqual([trial.make_plan(packet) for packet in packets], before)


if __name__ == "__main__":
    unittest.main()
