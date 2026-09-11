"""Fresh native workflow through actual runtime; scripted content is not accuracy evidence."""

import copy
import hashlib
import json
import os
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import Mock, patch

import boto3
from evals import checkpoint_runtime_qualification as trial
from lambda_test_support import _raw_question, _request_payload
from test_runtime_qualification import completed, payload


class NativeWorkflowQualificationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.output = self.directory / "capture"
        self.plan_path = self.directory / "plan.json"
        self.packet = {"experiment": trial.NATIVE_WORKFLOW_EXPERIMENT, "cases": [
            {"case_id": f"scripted-goal-{index}", "payload": _request_payload()} for index in range(3)
        ]}
        for index, case in enumerate(self.packet["cases"]):
            case["payload"]["goal"]["title"] = f"Analyze evidence in goal {index}"
            case["payload"]["goal"]["currentLevel"] = 'I can trace:\n    print("a  b")'
        self.plan = trial.make_plan(self.packet)
        trial.shared.write_json(self.plan_path, self.plan)
        self.questions = [_raw_question(prompt) for prompt in (
            "A poll reports 60 of 100 votes. What assumption connects this sample to the population?",
            "A treatment group improved after random allocation. Which inference needs a control comparison?",
            "A forecast is updated after a sensor alarm. What connects the base rate and new evidence?",
            "A factory measures defects only in returned products. Which condition supports extrapolation?",
            "A game repeats independent rounds. Which assumption links one round to the next?",
        )]
        self.by_prompt = {q["prompt"]: q for q in self.questions}
        for target, name in ((socket.socket, "connect"), (boto3, "client"),
                             (boto3.session.Session, "client"), (trial.shared, "new_client")):
            self.enterContext(patch.object(target, name, side_effect=AssertionError("No network or SDK clients")))

    def run_trial(self, observer=None):
        return trial.run_trial(self.plan_path, trial._hash(self.plan), self.output,
                               observer=observer or self.observer)

    def observer(self, request, *, on_progress, timeout, **_):
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 240)
        capture = json.loads((self.output / "capture.json").read_text())
        call = capture["calls"][-1]
        self.assertEqual(call["request"], request)
        self.assertEqual(call["request_sha256"], trial._hash(request))
        self.assertEqual(call["lifecycle"], "observing")
        self.assertEqual(trial.caller.SETTINGS, self.plan["settings"])
        role = call["role"]
        self.assertEqual(trial._guard_request(request, self.plan["settings"], self.plan["native_contracts"]), role)
        if role == "author":
            response = {"questions": self.questions}
        elif role == "solver":
            items = payload(request, "question_solution_json")["items"]
            response = {"solutions": [{"index": item["index"], "choices": [
                {"choice": choice, "reason": "Scripted support only.",
                 "judgment": "supported" if choice == self.by_prompt[item["prompt"]]["expectedAnswer"] else "refuted"}
                for choice in reversed(item["choices"])
            ]} for item in reversed(items)]}
        else:
            self.assertEqual(role, "reviewer")
            items = payload(request, "question_review_json")["items"]
            response = {"reviews": [{
                "index": item["index"], "valid": True,
                "answer": self.by_prompt[item["prompt"]]["expectedAnswer"], "difficulty": 3,
                "explanation": "The supplied conditions establish this conclusion.",
                "choiceFeedback": [{"choice": choice, "explanation": "Scripted feedback for the exact offered choice."}
                                   for choice in reversed(item["choices"])],
            } for item in reversed(items)]}
        state = completed(response)
        on_progress(copy.deepcopy(state))
        return state

    def test_exact_native_contracts_fresh_flow_and_replay_without_network(self):
        self.assertEqual(self.plan["maximum_calls"], 18)
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 18 * 32768)
        self.assertEqual(self.plan["settings"]["GENERATION_ATTEMPTS"], "3")
        for name in ("native_output_contracts.py", "question_source_guidance.py", "complete_question_solution.py"):
            self.assertEqual(self.plan["source_sha256"][name], hashlib.sha256((trial.SERVICE_DIR / name).read_bytes()).hexdigest())
        for name in ("Checkpoint/Services/QuestionContext.swift", "CheckpointTests/QuestionDeliveryCaptureTests.swift",
                     "backend/bedrock-question-service/evals/checkpoint_native_delivery.py"):
            self.assertEqual(self.plan["delivery_source_sha256"][name],
                             hashlib.sha256((trial.SERVICE_DIR.parents[1] / name).read_bytes()).hexdigest())
        for role, stage in self.plan["native_contracts"].items():
            declaration = stage["outputConfig"]["textFormat"]["structure"]["jsonSchema"]
            self.assertEqual(stage["contract_metadata"]["name"], declaration["name"])
            self.assertEqual(stage["contract_metadata"]["sha256"], hashlib.sha256(declaration["schema"].encode()).hexdigest())
            self.assertEqual(stage["system_prompt_sha256"], hashlib.sha256(stage["system"][0]["text"].encode()).hexdigest())
        report = self.run_trial()
        self.assertEqual(report["status"], "completed")
        self.assertEqual([c["role"] for c in report["calls"]], ["author", "solver", "reviewer"] * 3)
        self.assertEqual([o["case_id"] for o in report["operations"]], [c["case_id"] for c in self.packet["cases"]])
        for index, operation in enumerate(report["operations"]):
            self.assertEqual(operation["result_category"], "full_delivery")
            self.assertEqual(operation["delivery_observation"], {
                "requested_count": 5, "returned_count": 5, "shortfall_count": 0,
                "author_calls": 1, "topoff_author_calls": 0, "author_json_repair_calls": 0,
            })
            self.assertEqual(report["calls"][index * 3]["request"], self.plan["operations"][index]["first_request"])
            for question in operation["questions"]:
                self.assertEqual(question["verificationPolicyRevision"], 2)
                self.assertEqual(set(question["choiceExplanations"]), set(question["choices"]))
        with patch.object(trial.caller, "observe_request", side_effect=AssertionError("No observer during replay")):
            self.assertEqual(trial.replay_capture(report), report)
        self.assertEqual(json.loads((self.output / "capture.json").read_text()), report)

    def test_native_topoff_preserves_dynamic_request_bytes_in_replay(self):
        author_calls = 0
        def observer(request, **kwargs):
            nonlocal author_calls
            if request["modelId"] == self.plan["settings"]["BEDROCK_MODEL_ID"]:
                author_calls += 1
                if author_calls in (1, 2):
                    data = payload(request, "generation_request_json")
                    self.assertEqual(data["targetCount"], 5 if author_calls == 1 else 3)
                    if author_calls == 2:
                        self.assertEqual(len(data["existingQuestionCoverage"]), 2)
                    return completed({"questions": self.questions[:2] if author_calls == 1 else self.questions[2:]})
            return self.observer(request, **kwargs)
        report = self.run_trial(observer)
        self.assertEqual(len(report["calls"]), 12)
        self.assertEqual(report["operations"][0]["budget_reservations"], 6)
        self.assertEqual(report["operations"][0]["delivery_observation"]["topoff_author_calls"], 1)
        self.assertEqual(trial.replay_capture(report), report)
        changed = copy.deepcopy(report)
        changed["calls"][3]["request"]["messages"][0]["content"][0]["text"] += " modified subject"
        changed["calls"][3]["request_sha256"] = trial._hash(changed["calls"][3]["request"])
        with self.assertRaises(ValueError):
            trial.replay_capture(changed)

    def test_completed_native_malformed_content_preserves_raw_text_and_continues(self):
        calls = 0
        def observer(request, **kwargs):
            nonlocal calls
            calls += 1
            return completed("  invalid native JSON {\n") if calls == 1 else self.observer(request, **kwargs)
        report = self.run_trial(observer)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["operations"][0]["status"], "coverage_failure")
        self.assertEqual(report["operations"][0]["result_category"], "native_contract_invalid")
        self.assertEqual(report["operations"][0]["questions"], [])
        self.assertEqual([c["role"] for c in report["calls"]], ["author"] + ["author", "solver", "reviewer"] * 2)
        self.assertEqual(report["calls"][0]["observation"]["response"]["text"], "  invalid native JSON {\n")
        self.assertEqual(trial.replay_capture(report), report)

    def test_empty_native_content_uses_three_attempts_and_continues(self):
        calls = 0
        def observer(request, **kwargs):
            nonlocal calls
            calls += 1
            return completed({"questions": []}) if calls <= 3 else self.observer(request, **kwargs)
        report = self.run_trial(observer)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["operations"][0]["result_category"], "no_returned_questions")
        self.assertEqual(report["operations"][0]["delivery_observation"]["author_calls"], 3)
        self.assertEqual(trial.replay_capture(report), report)

    def test_ordinary_six_call_content_exhaustion_continues_without_extra_dispatch(self):
        first_batch = copy.deepcopy(self.questions)
        second_batch = [_raw_question(prompt) for prompt in (
            "A traffic survey samples only weekday commuters. What assumption supports a claim about all travelers?",
            "A laboratory repeats a measurement after recalibration. Which condition makes the readings comparable?",
            "A claim about price depends on fixed demand. Which observation challenges the unchanged-demand assumption?",
            "A clinical sample omits nonresponders. What connection is needed before generalizing its outcome?",
            "An event forecast combines independent estimates. Which relationship would undermine that calculation?",
        )]
        self.by_prompt.update({q["prompt"]: q for q in second_batch})
        authors = 0
        def observer(request, **kwargs):
            nonlocal authors
            contract = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
            if contract == "question_author_v1":
                authors += 1
                return completed({"questions": first_batch if authors % 2 else second_batch})
            if contract == "default_reviewer_v1":
                items = payload(request, "question_review_json")["items"]
                return completed({"reviews": [{
                    "index": item["index"], "valid": False, "answer": "", "difficulty": 3,
                    "explanation": "", "choiceFeedback": [],
                } for item in items]})
            return self.observer(request, **kwargs)
        report = self.run_trial(observer)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 18)
        for operation in report["operations"]:
            self.assertEqual(operation["budget_reservations"], 6)
            self.assertEqual(operation["status"], "coverage_failure")
            self.assertEqual(operation["result_category"], "call_budget_exhausted")
            self.assertEqual(operation["runtime_error_type"], "ProviderCallBudgetExceededError")
            self.assertEqual(operation["questions"], [])
        self.assertEqual(trial.replay_capture(report), report)

    def _malformed_checking_stage(self, contract):
        failed = False
        def observer(request, **kwargs):
            nonlocal failed
            if not failed and request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"] == contract:
                failed = True
                # A complete transport response whose envelope violates this
                # stage's native contract must not become a transport failure.
                return completed({"unexpected_envelope": []})
            return self.observer(request, **kwargs)
        report = self.run_trial(observer)
        self.assertTrue(failed)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["operations"][0]["status"], "coverage_failure")
        self.assertEqual(report["operations"][0]["result_category"], "native_contract_invalid")
        self.assertEqual([operation["result_category"] for operation in report["operations"]][1:], ["full_delivery"] * 2)
        self.assertEqual(trial.replay_capture(report), report)

    def test_completed_solver_format_failure_allows_later_independent_goals(self):
        self._malformed_checking_stage("complete_choice_solver_v1")

    def test_completed_reviewer_format_failure_allows_later_independent_goals(self):
        self._malformed_checking_stage("default_reviewer_v1")

    def test_failed_topoff_latches_even_when_runtime_retains_partial_questions(self):
        authors = 0
        def observer(request, **kwargs):
            nonlocal authors
            if request["modelId"] == self.plan["settings"]["BEDROCK_MODEL_ID"]:
                authors += 1
                if authors == 1:
                    return completed({"questions": self.questions[:2]})
                return completed({}, status="operational_failure", error_type="ReadTimeoutError")
            return self.observer(request, **kwargs)
        report = self.run_trial(observer)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["operations"][0]["runtime_error_type"], None)
        self.assertEqual(len(report["operations"][0]["questions"]), 2)
        self.assertEqual([o["status"] for o in report["operations"]][1:], ["unattempted"] * 2)
        self.assertEqual(trial.replay_capture(report), report)

    def test_unknown_usage_stops_even_with_usable_native_content(self):
        state = completed({"questions": self.questions}, usage_known=False)
        state["response"]["usage"] = None
        observer = Mock(return_value=state)
        report = self.run_trial(observer)
        observer.assert_called_once()
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["accounting"]["unknown_usage_calls"], 1)
        self.assertEqual(trial.replay_capture(report), report)
        saved = copy.deepcopy(report["calls"][0])
        saved.update(lifecycle="completed", failure_phase=None, error_type=None)
        derived = trial._empty_report(self.plan)
        client = trial._RuntimeClient(derived, lambda: None, Mock(), replay=[saved])
        client.operation_index, client.settings = 0, self.plan["settings"]
        client.context = trial._OperationContext(derived["operations"][0], [
            saved["prepared_remaining_milliseconds"], round(saved["timeout_seconds"] * 1000),
        ])
        with self.assertRaisesRegex(ValueError, "Undeliverable saved response"):
            client.converse(**saved["request"])
        client.observer.assert_not_called()

    def test_prompt_schema_settings_and_plan_drift_prevent_dispatch(self):
        first = self.plan["operations"][0]["first_request"]
        mutations = []
        wrong = copy.deepcopy(first)
        wrong["system"][0]["text"] += " altered"
        mutations.append(wrong)
        wrong = copy.deepcopy(first)
        del wrong["outputConfig"]
        mutations.append(wrong)
        wrong = copy.deepcopy(first)
        wrapper = wrong["outputConfig"]["textFormat"]["structure"]["jsonSchema"]
        wrapper["schema"] = json.dumps(json.loads(wrapper["schema"]), sort_keys=True, separators=(",", ":"))
        mutations.append(wrong)
        wrong = copy.deepcopy(first)
        wrong["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"] = "complete_choice_solver_v1"
        mutations.append(wrong)
        wrong = copy.deepcopy(first)
        wrong["inferenceConfig"]["maxTokens"] = 16000
        mutations.append(wrong)
        for wrong in mutations:
            client = trial._RuntimeClient(trial._empty_report(self.plan), lambda: None, Mock())
            client.operation_index, client.settings = 0, self.plan["settings"]
            with self.assertRaises(ValueError):
                client.converse(**wrong)
            client.observer.assert_not_called()
            self.assertTrue(client.failed)
        for field in ("source_sha256", "dependencies", "native_contracts", "settings", "delivery_source_sha256"):
            changed = {**self.plan, field: {}}
            trial.shared.write_json(self.plan_path, changed)
            with self.assertRaises(ValueError):
                trial.run_trial(self.plan_path, trial._hash(changed), self.output, observer=Mock())
        self.assertFalse(self.output.exists())
        self.assertFalse(self.plan_path.with_name(self.plan_path.name + ".execution-claim.json").exists())

    def test_same_frozen_plan_cannot_execute_to_another_directory(self):
        self.run_trial()
        claim = self.plan_path.with_name(self.plan_path.name + ".execution-claim.json")
        self.assertEqual(json.loads(claim.read_text()), {
            "plan_sha256": trial._hash(self.plan), "directory": str(self.output.resolve()),
        })
        observer = Mock()
        with self.assertRaises(FileExistsError):
            trial.run_trial(self.plan_path, trial._hash(self.plan), self.directory / "elsewhere", observer=observer)
        observer.assert_not_called()
        self.assertFalse((self.directory / "elsewhere").exists())

    def test_fresh_fixture_rejects_extra_settings_wrong_counts_and_duplicate_ids(self):
        for mutate in (
            lambda packet: packet.update(settings={}),
            lambda packet: packet["cases"].pop(),
            lambda packet: packet["cases"][1].update(case_id=packet["cases"][0]["case_id"]),
            lambda packet: packet["cases"][0]["payload"].update(targetCount=True),
            lambda packet: packet["cases"][0]["payload"].update(minimumDifficulty=2),
        ):
            changed = copy.deepcopy(self.packet)
            mutate(changed)
            with self.assertRaises(ValueError):
                trial.make_plan(changed)
        with patch.dict(os.environ, {"BEDROCK_MAX_TOKENS": "16000", "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"}):
            self.assertEqual(trial.make_plan(self.packet), self.plan)


if __name__ == "__main__":
    unittest.main()
