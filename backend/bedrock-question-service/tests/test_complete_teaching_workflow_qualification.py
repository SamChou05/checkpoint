"""Synthetic complete-teaching qualification; network and inference are forbidden."""

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
from complete_question_teaching import compose_feedback_displays
from lambda_test_support import _raw_question, _request_payload
from test_runtime_qualification import completed, payload


class CompleteTeachingWorkflowQualificationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.output = self.directory / "capture"
        self.plan_path = self.directory / "plan.json"
        self.packet = {"experiment": trial.NATIVE_COMPLETE_TEACHING_EXPERIMENT, "cases": [
            {"case_id": f"synthetic-complete-{index}", "payload": {
                **_request_payload(), "feedbackContract": "authored_complete",
            }} for index in range(3)
        ]}
        for index, case in enumerate(self.packet["cases"]):
            case["payload"]["goal"]["title"] = f"Analyze evidence in synthetic subject {index}"
        self.plan = trial.make_plan(self.packet)
        trial.shared.write_json(self.plan_path, self.plan)
        self.questions = [_raw_question(prompt) for prompt in (
            "A poll reports 60 of 100 votes. What assumption connects this sample to the population?",
            "A treatment group improved after random allocation. Which inference needs a control comparison?",
            "A forecast is updated after a sensor alarm. What connects the base rate and new evidence?",
            "A factory measures defects only in returned products. Which condition supports extrapolation?",
            "A game repeats independent rounds. Which assumption links one round to the next?",
        )]
        for question in self.questions:
            question["explanation"] = "  The stated conditions establish the indicated conclusion.\nPreserve these exact bytes.  "
            question["choiceExplanations"] = {
                choice: "The stated facts determine whether this exact choice answers the question.  "
                for choice in question["choices"]
            }
        self.by_prompt = {q["prompt"]: q for q in self.questions}
        for target, name in ((socket.socket, "connect"), (boto3, "client"),
                             (boto3.session.Session, "client"), (trial.shared, "new_client")):
            self.enterContext(patch.object(target, name, side_effect=AssertionError("No network or SDK clients")))

    def run_trial(self, observer=None):
        return trial.run_trial(self.plan_path, trial._hash(self.plan), self.output,
                               observer=observer or self.observer)

    def authored(self, questions):
        rows = copy.deepcopy(questions)
        for row in rows:
            feedback = row.pop("choiceExplanations")
            row["choiceFeedback"] = [{"choice": choice, "explanation": feedback[choice]}
                                     for choice in reversed(row["choices"])]
        return {"questions": rows}

    def observer(self, request, *, on_progress, timeout, **_):
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 240)
        saved = json.loads((self.output / "capture.json").read_text())["calls"][-1]
        self.assertEqual(saved["request"], request)
        self.assertEqual(saved["lifecycle"], "observing")
        self.assertEqual(trial.caller.SETTINGS["QUESTION_FEEDBACK_CONTRACT"], "reviewer_written")
        role = trial._guard_request(request, self.plan["settings"], self.plan["native_contracts"],
                                    maximum_input_bytes=self.plan["maximum_input_utf8_bytes_per_call"])
        self.assertEqual(role, saved["role"])
        if role == "author":
            self.assertEqual(payload(request, "generation_request_json")["feedbackContract"], "authored_complete")
            response = self.authored(self.questions)
        elif role == "solver":
            data = payload(request, "question_solution_json")
            self.assertNotIn("expectedAnswer", json.dumps(data))
            self.assertNotIn("choiceExplanations", json.dumps(data))
            self.assertTrue(all("explanation" not in item for item in data["items"]))
            response = {"solutions": [{"index": item["index"], "choices": [
                {"choice": choice, "reason": "Scripted support is not semantic evidence.",
                 "judgment": "supported" if choice == self.by_prompt[item["prompt"]]["expectedAnswer"] else "refuted"}
                for choice in reversed(item["choices"])
            ]} for item in reversed(data["items"])]}
        else:
            self.assertEqual(role, "reviewer")
            data = payload(request, "question_review_json")
            self.assertNotIn("independentSolutions", data)
            for item in data["items"]:
                self.assertNotIn("expectedAnswer", item)
                self.assertEqual(item["feedbackDisplays"], compose_feedback_displays(item))
                self.assertEqual(item["explanation"], self.by_prompt[item["prompt"]]["explanation"])
            response = {"reviews": [{
                "index": item["index"], "valid": True,
                "answer": self.by_prompt[item["prompt"]]["expectedAnswer"], "difficulty": 3,
                "explanationSupport": "supported", "issues": [], "choiceFeedbackSupport": [
                    {"choice": choice, "feedbackSupport": "supported", "displaySupport": "supported"}
                    for choice in reversed(item["choices"])
                ],
            } for item in reversed(data["items"])]}
        state = completed(response)
        on_progress(copy.deepcopy(state))
        return state

    def test_explicit_selector_freezes_correct_contracts_and_fixed_limits(self):
        self.assertEqual(self.plan["settings"]["QUESTION_FEEDBACK_CONTRACT"], "reviewer_written")
        self.assertEqual(self.plan["maximum_calls"], 18)
        self.assertEqual([o["maximum_calls"] for o in self.plan["operations"]], [6, 6, 6])
        self.assertEqual(self.plan["maximum_input_utf8_bytes_per_call"], 65536)
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 18 * 65536)
        self.assertEqual(self.plan["operation_seconds"], 240)
        self.assertEqual(self.plan["settings"]["BEDROCK_MAX_TOKENS"], "6000")
        expected = {"author": "question_author_complete_v1", "solver": "complete_choice_solver_v1",
                    "reviewer": "complete_teaching_reviewer_v1"}
        for role, stage in self.plan["native_contracts"].items():
            declaration = stage["outputConfig"]["textFormat"]["structure"]["jsonSchema"]
            self.assertEqual(declaration["name"], expected[role])
            self.assertEqual(stage["contract_metadata"]["sha256"], hashlib.sha256(declaration["schema"].encode()).hexdigest())
            self.assertEqual(stage["system_prompt_sha256"], hashlib.sha256(stage["system"][0]["text"].encode()).hexdigest())
        self.assertIn("complete_question_teaching.py", self.plan["source_sha256"])
        for operation in self.plan["operations"]:
            self.assertEqual(operation["request"]["feedbackContract"], "authored_complete")
            self.assertEqual(payload(operation["first_request"], "generation_request_json")["feedbackContract"], "authored_complete")
            self.assertEqual(operation["first_request"]["outputConfig"], self.plan["native_contracts"]["author"]["outputConfig"])
        with patch.dict(os.environ, {"QUESTION_FEEDBACK_CONTRACT": "authored_solution", "BEDROCK_MAX_TOKENS": "16000"}):
            self.assertEqual(trial.make_plan(self.packet), self.plan)

    def test_full_delivery_preserves_teaching_and_replay_without_network(self):
        report = self.run_trial()
        self.assertEqual(report["status"], "completed")
        self.assertEqual([c["role"] for c in report["calls"]], ["author", "solver", "reviewer"] * 3)
        for operation in report["operations"]:
            self.assertEqual(operation["result_category"], "full_delivery")
            self.assertEqual(len(operation["questions"]), 5)
            for question in operation["questions"]:
                original = self.by_prompt[question["prompt"]]
                self.assertEqual(question["verificationPolicyRevision"], 4)
                for field in ("prompt", "expectedAnswer", "choices", "explanation", "choiceExplanations"):
                    self.assertEqual(question[field], original[field])
        with patch.object(trial.caller, "observe_request", side_effect=AssertionError("No replay observer")):
            self.assertEqual(trial.replay_capture(report), report)
        altered = copy.deepcopy(report)
        altered["operations"][0]["questions"][0]["choiceExplanations"][self.questions[0]["choices"][0]] += " changed"
        with self.assertRaises(ValueError):
            trial.replay_capture(altered)

    def test_selector_missing_wrong_counts_and_contract_drift_block_before_dispatch(self):
        for change in ({"feedbackContract": None}, {"feedbackContract": "reviewer_written"},
                       {"feedbackContract": True}, {"targetCount": 4}, {"minimumDifficulty": 2}):
            packet = copy.deepcopy(self.packet)
            packet["cases"][0]["payload"].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                trial.make_plan(packet)
        packet = copy.deepcopy(self.packet)
        del packet["cases"][0]["payload"]["feedbackContract"]
        with self.assertRaises(ValueError):
            trial.make_plan(packet)
        altered = copy.deepcopy(self.plan)
        altered["native_contracts"]["reviewer"]["system"][0]["text"] += " changed"
        trial.shared.write_json(self.plan_path, altered)
        observer = Mock()
        with self.assertRaises(ValueError):
            trial.run_trial(self.plan_path, trial._hash(altered), self.output, observer=observer)
        observer.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_new_64k_guard_boundary_does_not_expand_old_mode(self):
        request = copy.deepcopy(self.plan["operations"][0]["first_request"])
        text = request["messages"][0]["content"][0]
        text["text"] += "x" * (65536 - len(trial.shared.canonical(request).encode()))
        self.assertEqual(len(trial.shared.canonical(request).encode()), 65536)
        self.assertEqual(trial._guard_request(request, self.plan["settings"], self.plan["native_contracts"],
                                             maximum_input_bytes=65536), "author")
        with self.assertRaises(ValueError):
            trial._guard_request(request, self.plan["settings"], self.plan["native_contracts"])
        text["text"] += "x"
        client = trial._RuntimeClient(trial._empty_report(self.plan), lambda: None, Mock())
        client.operation_index, client.settings = 0, self.plan["settings"]
        with self.assertRaisesRegex(ValueError, "input allowance"):
            client.converse(**request)
        client.observer.assert_not_called()
        self.assertTrue(client.failed)
        old = copy.deepcopy(self.packet)
        old["experiment"] = trial.NATIVE_WORKFLOW_EXPERIMENT
        for case in old["cases"]:
            del case["payload"]["feedbackContract"]
        prior = trial.make_plan(old)
        self.assertEqual(prior["maximum_input_utf8_bytes_per_call"], 32768)
        self.assertEqual(prior["maximum_input_utf8_bytes_total"], 18 * 32768)
        self.assertEqual(prior["native_contracts"]["author"]["contract_metadata"]["name"], "question_author_v1")
        self.assertEqual(prior["native_contracts"]["reviewer"]["contract_metadata"]["name"], "default_reviewer_v1")

    def test_topoff_keeps_selector_and_six_call_budget_per_goal(self):
        authors = 0
        def observer(request, **kwargs):
            nonlocal authors
            if request["modelId"] == self.plan["settings"]["BEDROCK_MODEL_ID"]:
                authors += 1
                self.assertEqual(payload(request, "generation_request_json")["feedbackContract"], "authored_complete")
                return completed(self.authored(self.questions[:2] if authors % 2 else self.questions[2:]))
            return self.observer(request, **kwargs)
        report = self.run_trial(observer)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 18)
        self.assertEqual([o["budget_reservations"] for o in report["operations"]], [6, 6, 6])
        self.assertTrue(all(o["delivery_observation"]["topoff_author_calls"] == 1 for o in report["operations"]))
        self.assertEqual(trial.replay_capture(report), report)

    def test_complete_audit_above_old_input_cap_captures_and_replays(self):
        for index, question in enumerate(self.questions):
            question["choices"] = [f"Scenario {index}.{choice}: ".ljust(140, "x") for choice in range(4)]
            question["expectedAnswer"] = question["choices"][0]
            question["explanation"] = question["explanation"].ljust(420, "x")
            question["choiceExplanations"] = {
                choice: "Synthetic maximum-length feedback for input accounting. ".ljust(280, "x")
                for choice in question["choices"]
            }
        for case in self.packet["cases"]:
            case["payload"]["sourceDocuments"] = [{
                "name": "Synthetic context for byte accounting", "text": "Study context. " * 400,
            }]
        self.plan = trial.make_plan(self.packet)
        trial.shared.write_json(self.plan_path, self.plan)
        report = self.run_trial()
        self.assertEqual(report["status"], "completed")
        review_calls = [call for call in report["calls"] if call["role"] == "reviewer"]
        self.assertEqual(len(review_calls), 3)
        self.assertTrue(all(32768 < call["input_utf8_bytes"] <= 65536 for call in review_calls))
        self.assertTrue(all(call["input_utf8_bytes"] <= 65536 for call in report["calls"]))
        self.assertEqual(trial.replay_capture(report), report)

    def test_native_format_failure_continues_but_unknown_usage_stops_and_plan_cannot_repeat(self):
        calls = 0
        def observer(request, **kwargs):
            nonlocal calls
            calls += 1
            return completed("bad native JSON {") if calls == 1 else self.observer(request, **kwargs)
        report = self.run_trial(observer)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["operations"][0]["result_category"], "native_contract_invalid")
        self.assertEqual([o["result_category"] for o in report["operations"]][1:], ["full_delivery"] * 2)
        self.assertEqual(trial.replay_capture(report), report)
        with self.assertRaises(FileExistsError):
            trial.run_trial(self.plan_path, trial._hash(self.plan), self.directory / "repeat", observer=Mock())
        second_plan = self.directory / "separate-synthetic-plan.json"
        trial.shared.write_json(second_plan, self.plan)
        state = completed(self.authored(self.questions), usage_known=False)
        state["response"]["usage"] = None
        failed = trial.run_trial(second_plan, trial._hash(self.plan), self.directory / "unknown", observer=Mock(return_value=state))
        self.assertEqual(failed["status"], "operational_failure")
        self.assertEqual(len(failed["calls"]), 1)
        self.assertEqual([o["status"] for o in failed["operations"]][1:], ["unattempted"] * 2)
        self.assertEqual(trial.replay_capture(failed), failed)


if __name__ == "__main__":
    unittest.main()
