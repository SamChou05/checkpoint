"""Actual runtime with scripted observer responses; no SDK, workers or inference."""

import copy
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


if __name__ == "__main__":
    unittest.main()
