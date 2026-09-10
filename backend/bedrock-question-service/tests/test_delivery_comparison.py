"""Fixed delivery comparison through actual runtime; scripted observations only."""

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
from service_errors import (
    DurableProviderCallBudgetExceededError, InvalidProviderResponseError,
    ProviderDeadlineExceededError, ProviderError,
)
from test_runtime_qualification import completed, payload


class DeliveryComparisonTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.output = self.directory / "capture"
        self.plan_path = self.directory / "plan.json"
        self.packet = {"experiment": trial.DELIVERY_COMPARISON_EXPERIMENT}
        self.plan = trial.make_plan(self.packet)
        trial.shared.write_json(self.plan_path, self.plan)
        self.modes, self.author_passes = {}, {}
        self.questions = [[_raw_question(
            f"Observation set {operation}-{index} gives evidence and a condition. Which conclusion follows?",
        ) for index in range(10)] for operation in range(6)]
        self.by_prompt = {q["prompt"]: q for batch in self.questions for q in batch}

    def run_trial(self, observer=None):
        return trial.run_trial(self.plan_path, trial._hash(self.plan), self.output,
                               observer=observer or self.observer)

    def observer(self, request, *, on_progress, timeout, **_):
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 240)
        capture = json.loads((self.output / "capture.json").read_text())
        call = capture["calls"][-1]
        operation, role = call["operation_index"], call["role"]
        job = self.plan["operations"][operation]
        self.assertEqual(trial.caller.SETTINGS, job["settings"])
        self.assertEqual(call["request"], request)
        self.assertEqual(call["request_sha256"], trial._hash(request))
        mode = self.modes.get(operation)
        if role == "author":
            self.author_passes[operation] = self.author_passes.get(operation, 0) + 1
        author_pass = self.author_passes[operation]
        if mode == "transport" or mode == "partial_transport" and author_pass == 2:
            return {"status": "operational_failure", "error_type": "ReadTimeoutError",
                    "provider_dispatch_attempted": True, "usage_known": False}
        if role.startswith("author"):
            if mode == "malformed" or mode in {"repair_success", "repair_rejected"} and role == "author":
                value = "  incomplete JSON {  \n"
            elif mode == "empty" or mode == "partial_content" and author_pass == 2:
                value = {"questions": []}
            else:
                batch = self.questions[operation][(author_pass - 1) * 5:author_pass * 5]
                if mode in {"short", "partial_transport", "partial_content"}:
                    batch = self.questions[operation][:2] if author_pass == 1 else self.questions[operation][2:5]
                value = {"questions": batch}
        elif role == "solver":
            data = payload(request, "question_solution_json")
            self.assertEqual(data["sourceDocuments"], job["request"]["sourceDocuments"])
            value = {"solutions": [{"index": item["index"], "choices": [{
                "choice": choice,
                "judgment": "supported" if mode != "solver_reject" and choice == self.by_prompt[item["prompt"]]["expectedAnswer"] else "refuted",
                "reason": "Scripted choice judgment tests routing, not factual correctness.",
            } for choice in item["choices"]]} for item in data["items"]]}
        else:
            data = payload(request, "question_review_json")
            self.assertEqual(data["sourceDocuments"], job["request"]["sourceDocuments"])
            reviews = []
            for item in data["items"]:
                review = {"index": item["index"], "valid": mode not in {"reject", "repair_rejected"},
                          "answer": self.by_prompt[item["prompt"]]["expectedAnswer"], "difficulty": 3}
                if role == "teaching_auditor":
                    self.assertNotIn("independentSolutions", data)
                    self.assertEqual(item["explanation"], self.by_prompt[item["prompt"]]["explanation"])
                    review.update(explanationSupport="supported", issues=[])
                else:
                    self.assertEqual(role, "reviewer")
                    review.update(explanation="The stated condition establishes this exact conclusion.",
                                  choiceExplanations={c: "This scripted reason checks exact choice binding."
                                                      for c in item["choices"]})
                reviews.append(review)
            value = {"reviews": reviews}
        state = completed(value)
        on_progress(copy.deepcopy(state))
        return state

    def assert_replay(self, report):
        with patch.object(trial.caller, "observe_request", side_effect=AssertionError("No worker")), patch.object(
            trial.shared, "new_client", side_effect=AssertionError("No SDK"),
        ):
            self.assertEqual(trial.replay_capture(report), report)
        self.assertEqual(json.loads((self.output / "capture.json").read_text()), report)

    def test_exact_fixed_payloads_normal_settings_pair_order_and_no_example_leak(self):
        raw = trial.DELIVERY_COMPARISON_ORIGIN.read_bytes()
        origin = json.loads(raw)
        self.assertEqual(hashlib.sha256(raw).hexdigest(), trial.DELIVERY_COMPARISON_ORIGIN_SHA256)
        self.assertEqual(self.plan["maximum_calls"], 36)
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 36 * 32768)
        self.assertEqual(self.plan["operation_seconds"], 240)
        self.assertEqual([j["arm"] for j in self.plan["operations"]], [
            "reviewer_written", "authored_solution", "authored_solution",
            "reviewer_written", "reviewer_written", "authored_solution",
        ])
        for index, case in enumerate(origin["cases"]):
            expected_payload = {**case["payload"], "targetCount": 5}
            with patch.dict(os.environ, trial.SETTINGS):
                normalized = trial._normalize_request(expected_payload)
            frozen = self.plan["origin"]["cases"][index]
            self.assertEqual(frozen["payload"], case["payload"])
            self.assertEqual(frozen["payload_sha256"], trial._hash(case["payload"]))
            self.assertEqual(frozen["delivery_payload_sha256"], trial._hash(expected_payload))
            self.assertEqual(frozen["normalized_request_sha256"], trial._hash(normalized))
            pair = self.plan["operations"][index * 2:index * 2 + 2]
            self.assertEqual(pair[0]["request"], pair[1]["request"])
            for job in pair:
                self.assertEqual(job["case_id"], case["case_id"])
                self.assertEqual(job["request"], normalized)
                self.assertEqual(job["maximum_calls"], 6)
                self.assertEqual(job["settings"], {**trial.SETTINGS, "MAX_QUESTIONS_PER_BATCH": "5",
                                                  "QUESTION_FEEDBACK_CONTRACT": job["arm"]})
                self.assertEqual(job["settings"]["GENERATION_ATTEMPTS"], "3")
                first = job["first_request"]
                with patch.dict(os.environ, job["settings"]):
                    self.assertEqual(first, trial._first_request(normalized, settings=job["settings"]))
                self.assertEqual(payload(first, "generation_request_json")["sourceDocuments"], normalized["sourceDocuments"])
                self.assertEqual(first["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})
                self.assertEqual(first["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})
                sent = json.dumps(first)
                self.assertNotIn(case["assessment_scope"], sent)
                for demo in origin["demonstrations"]:
                    self.assertNotIn(demo["question"]["prompt"], sent)
                self.assertNotIn("assessment_scope", sent)
                self.assertNotIn("demonstrations", sent)
                self.assertLessEqual(len(trial.shared.canonical(first).encode()), 32768)
            self.assertNotEqual(pair[0]["first_request"]["system"], pair[1]["first_request"]["system"])

    def test_hostile_ambient_batch_limit_cannot_silently_reduce_the_frozen_target(self):
        with patch.dict(os.environ, {"MAX_QUESTIONS_PER_BATCH": "2"}):
            plan = trial.make_plan(self.packet)
            self.assertEqual(plan, self.plan)
            self.assertEqual([j["request"]["targetCount"] for j in plan["operations"]], [5] * 6)
            self.assertEqual([j["request"]["minimumDifficulty"] for j in plan["operations"]], [3] * 6)

    def test_full_normal_runtime_both_contracts_and_exact_no_client_replay(self):
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")):
            report = self.run_trial()
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 18)
        self.assertEqual(report["accounting"]["observed_dispatch_attempts"], 18)
        for index, operation in enumerate(report["operations"]):
            self.assertEqual(operation["arm"], self.plan["operations"][index]["arm"])
            self.assertEqual(operation["result_category"], "full_delivery")
            self.assertEqual(operation["delivery_observation"], {
                "requested_count": 5, "returned_count": 5, "shortfall_count": 0,
                "author_calls": 1, "topoff_author_calls": 0, "author_json_repair_calls": 0,
            })
            for question in operation["questions"]:
                self.assertEqual(question["verificationPolicyRevision"], 3 if operation["arm"] == "authored_solution" else 2)
        self.assert_replay(report)

    def test_all_rejected_passes_exhaust_budget_then_next_independent_operation_runs(self):
        self.modes[0] = "reject"
        report = self.run_trial()
        first = report["operations"][0]
        self.assertEqual(report["status"], "completed")
        self.assertEqual(first["status"], "coverage_failure")
        self.assertEqual(first["result_category"], "call_budget_exhausted")
        self.assertEqual(first["runtime_error_type"], "ProviderCallBudgetExceededError")
        self.assertEqual(first["budget_reservations"], 6)
        self.assertEqual(first["questions"], [])
        self.assertEqual([c["role"] for c in report["calls"][:6]], ["author", "solver", "reviewer"] * 2)
        retry = payload(report["calls"][3]["request"], "generation_request_json")
        self.assertEqual(retry["targetCount"], 5)
        self.assertEqual(len(retry["existingPrompts"]), 5)
        self.assertTrue(retry["previousAttemptFeedback"]["review"])
        self.assertEqual(report["operations"][1]["result_category"], "full_delivery")
        self.assertEqual(len(report["calls"]), 21)
        self.assert_replay(report)

    def test_solver_rejection_reserves_no_unaffordable_third_pass(self):
        self.modes[0] = "solver_reject"
        report = self.run_trial()
        self.assertEqual(report["operations"][0]["result_category"], "call_budget_exhausted")
        self.assertEqual(report["operations"][0]["budget_reservations"], 4)
        self.assertEqual([c["role"] for c in report["calls"][:4]], ["author", "solver"] * 2)
        self.assertEqual(report["operations"][1]["result_category"], "full_delivery")
        self.assert_replay(report)

    def test_completed_malformed_author_and_bounded_repair_are_content_failure(self):
        self.modes[0] = "malformed"
        report = self.run_trial()
        first = report["operations"][0]
        self.assertEqual(first["status"], "coverage_failure")
        self.assertEqual(first["result_category"], "malformed_author_json")
        self.assertEqual(first["runtime_error_type"], "ProviderError")
        self.assertEqual(first["budget_reservations"], 2)
        self.assertEqual(first["delivery_observation"]["author_json_repair_calls"], 1)
        self.assertEqual(first["metrics"]["QuestionQuality"]["provider"]["invalid_json"], 2)
        self.assertEqual(len(report["calls"]), 17)
        for call in report["calls"][:2]:
            self.assertEqual(call["observation"]["response"]["text"], "  incomplete JSON {  \n")
        self.assertEqual(report["operations"][1]["result_category"], "full_delivery")
        self.assert_replay(report)

    def test_repair_then_rejection_spends_four_calls_before_coverage_failure(self):
        self.modes[0] = "repair_rejected"
        report = self.run_trial()
        first = report["operations"][0]
        self.assertEqual(first["result_category"], "call_budget_exhausted")
        self.assertEqual(first["budget_reservations"], 4)
        self.assertEqual(first["delivery_observation"]["author_json_repair_calls"], 1)
        self.assertEqual(report["operations"][1]["result_category"], "full_delivery")
        self.assert_replay(report)

    def test_repair_and_topoff_success_preserve_the_actual_normal_runtime(self):
        self.modes.update({0: "repair_success", 1: "short", 2: "empty"})
        report = self.run_trial()
        self.assertEqual([c["role"] for c in report["calls"][:4]], ["author", "author_json_repair", "solver", "reviewer"])
        self.assertEqual(report["operations"][0]["result_category"], "full_delivery")
        self.assertEqual(report["operations"][1]["budget_reservations"], 6)
        self.assertEqual(report["operations"][1]["delivery_observation"]["topoff_author_calls"], 1)
        second = [c for c in report["calls"] if c["operation_index"] == 1][3]
        request = payload(second["request"], "generation_request_json")
        self.assertEqual(request["targetCount"], 3)
        self.assertEqual(len(request["existingQuestionCoverage"]), 2)
        self.assertEqual(report["operations"][2]["status"], "coverage_failure")
        self.assertEqual(report["operations"][2]["result_category"], "no_returned_questions")
        self.assertIsNone(report["operations"][2]["runtime_error_type"])
        self.assertEqual(report["operations"][2]["budget_reservations"], 3)
        self.assert_replay(report)

    def test_transport_failure_latches_global_stop_and_unknown_usage(self):
        self.modes[0] = "transport"
        report = self.run_trial()
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(len(report["calls"]), 1)
        self.assertEqual(report["operations"][0]["result_category"], "operational_failure")
        self.assertEqual([o["status"] for o in report["operations"]][1:], ["unattempted"] * 5)
        self.assertEqual(report["accounting"]["unknown_usage_calls"], 1)
        self.assert_replay(report)

    def test_partial_content_return_remains_measurable_and_later_operations_continue(self):
        self.modes[0] = "partial_content"
        report = self.run_trial()
        first = report["operations"][0]
        self.assertEqual(first["status"], "completed")
        self.assertEqual(first["result_category"], "partial_delivery")
        self.assertEqual(first["budget_reservations"], 4)
        self.assertEqual(first["delivery_observation"]["returned_count"], 2)
        self.assertEqual(first["delivery_observation"]["shortfall_count"], 3)
        self.assertIsNone(first["runtime_error_type"])
        self.assertEqual(report["operations"][1]["result_category"], "full_delivery")
        self.assert_replay(report)

    def test_runtime_retains_partial_batch_when_later_admission_deadline_is_caught(self):
        self.modes[0] = "short"
        clock = [0.0]

        def observer(request, **kwargs):
            state = self.observer(request, **kwargs)
            saved = json.loads((self.output / "capture.json").read_text())
            if len(saved["calls"]) == 3:
                clock[0] = 200.0
            return state

        with patch.object(trial.time, "monotonic", side_effect=lambda: clock[0]):
            report = self.run_trial(observer)
        first = report["operations"][0]
        self.assertEqual(first["result_category"], "partial_delivery")
        self.assertEqual(first["budget_reservations"], 3)
        self.assertEqual(len(first["questions"]), 2)
        self.assertIsNone(first["runtime_error_type"])
        self.assertEqual(first["remaining_milliseconds"][-1], 40000)
        self.assertEqual(report["operations"][1]["result_category"], "full_delivery")
        self.assert_replay(report)

    def test_failed_topoff_stops_even_if_runtime_preserves_earlier_questions(self):
        self.modes[0] = "partial_transport"
        report = self.run_trial()
        first = report["operations"][0]
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(first["result_category"], "operational_failure")
        self.assertEqual(len(first["questions"]), 2)
        self.assertIsNone(first["runtime_error_type"])
        self.assertEqual(first["delivery_observation"]["shortfall_count"], 3)
        self.assertEqual(len(report["calls"]), 4)
        self.assertEqual(report["operations"][1]["status"], "unattempted")
        self.assert_replay(report)

    def test_deadline_durable_unknown_and_persistence_errors_cannot_be_content_failures(self):
        for error in (ProviderDeadlineExceededError("late"), DurableProviderCallBudgetExceededError("quota"),
                      ProviderError("Provider response was not valid JSON."), ValueError("unexpected")):
            with self.subTest(error=type(error).__name__):
                report = trial._empty_report(self.plan)
                observer = Mock(side_effect=AssertionError("No provider"))
                with patch.object(trial.generation, "_generate_sanitized_questions", side_effect=error):
                    trial._execute(self.plan, report, lambda: None, observer)
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(report["operations"][1]["status"], "unattempted")
                observer.assert_not_called()
        report = trial._empty_report(self.plan)
        persist = Mock(side_effect=[InvalidProviderResponseError("persistence failed"), None])
        trial._execute(self.plan, report, persist, Mock(side_effect=AssertionError("No provider")))
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["operations"][0]["result_category"], "operational_failure")

    def test_origin_source_settings_arm_and_response_tampering_fail_closed(self):
        with self.assertRaises(ValueError):
            trial.make_plan({**self.packet, "targetCount": 2})
        with patch.object(trial, "DELIVERY_COMPARISON_ORIGIN_SHA256", "wrong"), self.assertRaises(ValueError):
            trial.make_plan(self.packet)
        for change in ("source", "dependencies", "arm", "settings", "payload"):
            altered = copy.deepcopy(self.plan)
            if change == "source":
                altered["source_sha256"]["question_generation.py"] = "0" * 64
            elif change == "dependencies":
                altered["dependencies"]["boto3"] = "different"
            elif change == "arm":
                altered["operations"][0]["arm"] = "authored_solution"
            elif change == "settings":
                altered["operations"][0]["settings"]["GENERATION_ATTEMPTS"] = "1"
            else:
                altered["origin"]["cases"][0]["payload"]["targetCount"] = 5
            path = self.directory / f"{change}.json"
            trial.shared.write_json(path, altered)
            with self.subTest(change=change), self.assertRaises(ValueError):
                trial.load_frozen_plan(path, trial._hash(altered))
        report = self.run_trial()
        altered = copy.deepcopy(report)
        altered["operations"][0]["result_category"] = "partial_delivery"
        with self.assertRaises(ValueError):
            trial.replay_capture(altered)
        altered = copy.deepcopy(report)
        altered["calls"][0]["request"]["system"][0]["text"] += "Changed"
        with self.assertRaises(ValueError):
            trial.replay_capture(altered)

    def test_dry_cli_has_no_provider_or_worker(self):
        fixture = self.directory / "fixture.json"
        trial.shared.write_json(fixture, self.packet)
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")), patch.object(
            trial.caller, "observe_request", side_effect=AssertionError("No worker"),
        ):
            self.assertEqual(trial.main(["--fixture", str(fixture), "--output", str(self.output)]), 0)
        self.assertEqual(json.loads((self.output / "plan.json").read_text()), self.plan)


if __name__ == "__main__":
    unittest.main()
