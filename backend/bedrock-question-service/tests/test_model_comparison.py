import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_model_comparison as experiment
from request_contract import _normalize_request


def packet():
    request = _normalize_request(
        {"goal": {"title": "Synthetic arithmetic"}, "minimumDifficulty": 3}
    )
    question = {
        "prompt": "What is 2 + 2?",
        "expectedAnswer": "4",
        "choices": ["4", "3", "5", "6"],
        "topic": "addition",
        "difficulty": 3,
        "explanation": "AUTHOR EXPLANATION HIDDEN",
        "format": "Multiple Choice",
    }
    return {
        "models": experiment.MODELS[:],
        "settings": {
            **experiment.REQUIRED_SETTINGS,
            "BEDROCK_READ_TIMEOUT_SECONDS": "100",
            "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
        },
        "cases": [
            {
                "case_id": f"case-{i}",
                "request": copy.deepcopy(request),
                "question": copy.deepcopy(question),
                "expected_accept": True,
                "expected_model_valid": True,
                "rationale": "SECRET EVALUATOR RATIONALE",
                "feedback_requirements": ["SECRET FEEDBACK REQUIREMENT"],
            }
            for i in range(4)
        ],
    }


def solution(assumptions=None, *, outcome="resolved"):
    return {
        "solutions": [
            {
                "index": 0,
                "answer": "The sum is four.",
                "limitations": "",
                "outcome": outcome,
                "assumptionsRequired": assumptions or [],
            }
        ]
    }


def review(valid=True, difficulty=3):
    return {
        "reviews": [
            {
                "index": 0,
                "valid": valid,
                "answer": "4" if valid else "",
                "difficulty": difficulty,
                "explanation": "Adding two and two gives four.",
                "choiceExplanations": {
                    choice: "This is the exact sum."
                    if choice == "4"
                    else "This number differs from the sum."
                    for choice in ["4", "3", "5", "6"]
                },
            }
        ]
    }


def response(payload, stop="end_turn"):
    return {
        "output": {
            "message": {
                "content": [
                    {
                        "reasoningContent": {
                            "reasoningText": {
                                "text": "PRIVATE REASONING",
                                "signature": "PRIVATE SIGNATURE",
                            }
                        }
                    },
                    {"text": "```json\n" + json.dumps(payload) + "\n```"},
                ]
            }
        },
        "stopReason": stop,
        "usage": {"inputTokens": 10, "outputTokens": 20},
    }


class Client:
    def __init__(self, callback=None):
        self.requests = []
        self.callback = callback

    def converse(self, **request):
        self.requests.append(copy.deepcopy(request))
        if self.callback:
            return self.callback(request)
        return response(
            solution()
            if request["system"][0]["text"] == experiment.SOLUTION_SYSTEM_PROMPT
            else review()
        )


class ModelComparisonTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.output = Path(self.directory.name) / "run"
        self.packet = packet()

    def run_eval(self, client=None):
        plan_hash = experiment.digest(
            experiment.canonical(experiment.make_plan(self.packet))
        )
        return experiment.run_experiment(
            self.packet, self.output, plan_hash, client or Client()
        )

    def test_paired_order_exact_requests_caps_and_no_private_content(self):
        client = Client()
        report = self.run_eval(client)
        self.assertEqual(len(client.requests), 16)
        self.assertEqual(
            [r["model"] for r in report["results"]],
            experiment.MODELS
            + experiment.MODELS[::-1]
            + experiment.MODELS
            + experiment.MODELS[::-1],
        )
        self.assertTrue(all(r["accepted"] for r in report["results"]))
        self.assertTrue(
            all(r["semantic_verdict_matches_expected"] for r in report["results"])
        )
        self.assertTrue(
            all(r["feedback_assessment"] == "unassessed" for r in report["results"])
        )
        self.assertLessEqual(report["input_utf8_bytes"], 256000)
        for request in client.requests:
            self.assertEqual(request["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(
                request["additionalModelRequestFields"],
                {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
            )
            text = json.dumps(request)
            for forbidden in (
                "SECRET EVALUATOR",
                "SECRET FEEDBACK",
                "AUTHOR EXPLANATION",
                "expected_accept",
                "expected_model_valid",
            ):
                self.assertNotIn(forbidden, text)
        saved = (self.output / "capture.json").read_text()
        self.assertNotIn("PRIVATE REASONING", saved)
        self.assertNotIn("PRIVATE SIGNATURE", saved)
        self.assertEqual(
            report["calls"][0]["response"]["reasoningContentBlockCount"], 1
        )

    def test_preserves_full_historical_context_and_original_question(self):
        history = {
            "prompt": "A historical item",
            "expectedAnswer": "HISTORICAL KEY",
            "choices": ["HISTORICAL KEY"],
        }
        self.packet["cases"][0]["request"]["existingQuestionCoverage"] = [history]
        before = copy.deepcopy(self.packet)
        client = Client()
        report = self.run_eval(client)
        self.assertNotIn("HISTORICAL KEY", json.dumps(client.requests[0]))
        self.assertIn("HISTORICAL KEY", json.dumps(client.requests[1]))
        self.assertEqual(self.packet, before)
        returned = report["results"][0]["returned_questions"][0]
        for key in ("prompt", "choices", "expectedAnswer"):
            self.assertEqual(returned[key], self.packet["cases"][0]["question"][key])

    def test_difficulty_removal_is_distinct_from_factual_verdict(self):
        client = Client(
            lambda request: response(
                solution()
                if request["system"][0]["text"] == experiment.SOLUTION_SYSTEM_PROMPT
                else review(difficulty=2)
            )
        )
        report = self.run_eval(client)
        result = report["results"][0]
        self.assertFalse(result["accepted"])
        self.assertFalse(result["inventory_acceptance_matches_expected"])
        self.assertTrue(result["model_valid"])
        self.assertTrue(result["semantic_verdict_matches_expected"])
        self.assertTrue(result["reviewed_key_matches_original"])
        self.assertEqual(
            result["stage_outputs"]["reviewer"]["reviews"][0]["difficulty"], 2
        )

    def test_semantic_rejection_is_preserved_without_a_retry(self):
        self.packet["cases"][0].update(
            expected_accept=False, expected_model_valid=False
        )
        client = Client(
            lambda request: response(solution(["An absent fact is required."]))
        )
        report = self.run_eval(client)
        self.assertEqual(len(client.requests), 8)
        self.assertTrue(report["results"][0]["semantic_rejection"])
        self.assertTrue(report["results"][0]["semantic_verdict_matches_expected"])
        self.assertFalse(report["stopped_early"])
        self.assertIsNone(report["results"][0]["model_valid"])

    def test_exceptional_outcome_mismatch_is_control_rejection_not_failure(self):
        self.packet["cases"][0].update(
            expected_accept=False, expected_model_valid=False
        )
        client = Client(lambda request: response(solution(outcome="no_solution")))
        report = self.run_eval(client)
        self.assertEqual(len(client.requests), 8)
        result = report["results"][0]
        self.assertEqual(result["status"], "completed")
        self.assertFalse(report["stopped_early"])
        self.assertFalse(result["abstained"])
        self.assertEqual(result["solver_outcome"], "no_solution")
        self.assertEqual(
            result["metrics"]["QuestionQuality"]["review"],
            {"solver_outcome_mismatch": 1},
        )
        self.assertTrue(result["semantic_rejection"])
        self.assertTrue(result["semantic_verdict_matches_expected"])
        self.assertNotIn("reviewer", result["stage_outputs"])

    def test_solver_uncertainty_is_an_abstention_without_correctness_credit(self):
        self.packet["cases"][0].update(
            expected_accept=False, expected_model_valid=False
        )
        client = Client(
            lambda request: response(
                solution(["A premise cannot be established."], outcome="uncertain")
            )
        )
        report = self.run_eval(client)
        self.assertEqual(len(client.requests), 8)
        result = report["results"][0]
        self.assertEqual(result["status"], "completed")
        self.assertFalse(report["stopped_early"])
        self.assertTrue(result["abstained"])
        self.assertFalse(result["semantic_rejection"])
        self.assertIsNone(result["semantic_verdict_matches_expected"])
        self.assertTrue(result["inventory_acceptance_matches_expected"])
        self.assertEqual(
            result["stage_outputs"]["solver"]["solutions"][0]["outcome"], "uncertain"
        )
        self.assertNotIn("reviewer", result["stage_outputs"])

    def test_valid_false_is_a_semantic_verdict(self):
        self.packet["cases"][0]["expected_model_valid"] = False
        client = Client(
            lambda request: response(
                solution()
                if request["system"][0]["text"] == experiment.SOLUTION_SYSTEM_PROMPT
                else review(valid=False)
            )
        )
        report = self.run_eval(client)
        self.assertTrue(report["results"][0]["semantic_verdict_matches_expected"])
        self.assertTrue(report["results"][0]["semantic_rejection"])
        self.assertEqual(len(client.requests), 16)

    def test_non_end_turn_stops_with_saved_text_and_unattempted_jobs(self):
        client = Client(lambda request: response(solution(), stop="refusal"))
        report = self.run_eval(client)
        self.assertEqual(len(client.requests), 1)
        self.assertTrue(report["stopped_early"])
        self.assertEqual(report["calls"][0]["response"]["stopReason"], "refusal")
        self.assertEqual(report["results"][0]["status"], "operational_failure")
        self.assertIsNone(report["results"][0]["semantic_verdict_matches_expected"])
        self.assertTrue(
            all(r["status"] == "unattempted" for r in report["results"][1:])
        )

    def test_malformed_solver_or_review_cannot_pass_a_negative_case(self):
        for malformed_stage in ("solver", "reviewer"):
            with self.subTest(stage=malformed_stage):
                self.output = Path(self.directory.name) / malformed_stage
                self.packet["cases"][0].update(
                    expected_accept=False, expected_model_valid=False
                )

                def callback(request):
                    stage = (
                        "solver"
                        if request["system"][0]["text"]
                        == experiment.SOLUTION_SYSTEM_PROMPT
                        else "reviewer"
                    )
                    return response(
                        {"solutions": []}
                        if stage == "solver" and stage == malformed_stage
                        else {"reviews": [{"index": 0, "valid": "false", "answer": ""}]}
                        if stage == malformed_stage
                        else solution()
                    )

                client = Client(callback)
                report = self.run_eval(client)
                self.assertEqual(
                    len(client.requests), 1 if malformed_stage == "solver" else 2
                )
                self.assertEqual(report["results"][0]["status"], "operational_failure")
                self.assertIsNone(
                    report["results"][0]["semantic_verdict_matches_expected"]
                )

    def test_provider_error_persists_attempt_before_dispatch(self):
        def fail(request):
            saved = json.loads((self.output / "capture.json").read_text())
            self.assertEqual(saved["calls"][0]["status"], "dispatch_started")
            raise TimeoutError("PRIVATE PROVIDER DETAIL")

        report = self.run_eval(Client(fail))
        self.assertEqual(len(report["calls"]), 1)
        self.assertEqual(report["calls"][0]["error"], {"type": "TimeoutError"})
        self.assertFalse(report["calls"][0]["usage_known"])
        self.assertNotIn(
            "PRIVATE PROVIDER DETAIL", (self.output / "capture.json").read_text()
        )

    def test_pre_dispatch_write_failure_never_calls_provider(self):
        original = experiment.write_json

        def writer(path, value):
            if path.name == "capture.json" and value["calls"]:
                raise OSError("disk unavailable")
            original(path, value)

        client = Client()
        with (
            patch.object(experiment, "write_json", side_effect=writer),
            self.assertRaises(OSError),
        ):
            self.run_eval(client)
        self.assertEqual(client.requests, [])

    def test_plan_hash_and_fresh_output_required_before_client_creation(self):
        with patch.object(experiment, "new_client") as factory:
            with self.assertRaises(ValueError):
                experiment.run_experiment(self.packet, self.output, "wrong")
            self.assertFalse(self.output.exists())
            self.output.mkdir()
            plan_hash = experiment.digest(
                experiment.canonical(experiment.make_plan(self.packet))
            )
            with self.assertRaises(FileExistsError):
                experiment.run_experiment(self.packet, self.output, plan_hash)
            factory.assert_not_called()

    def test_input_byte_guard_counts_utf8_and_never_clips(self):
        self.packet["cases"][0]["request"]["sourceDocuments"] = [
            {"text": "é" * 8000, "name": "Oversize exact source"}
        ]
        client = Client()
        report = self.run_eval(client)
        self.assertEqual(client.requests, [])
        self.assertEqual(report["calls"], [])
        self.assertTrue(report["stopped_early"])

    def test_dry_run_never_constructs_client_or_loads_credentials(self):
        fixture = Path(self.directory.name) / "fixture.json"
        fixture.write_text(json.dumps(self.packet))
        with patch.object(experiment, "new_client") as factory:
            self.assertEqual(
                experiment.main(
                    [
                        "--fixture",
                        str(fixture),
                        "--output",
                        str(self.output),
                        "--aws-cli-credentials",
                    ]
                ),
                0,
            )
            factory.assert_not_called()
        self.assertTrue((self.output / "plan.json").exists())


if __name__ == "__main__":
    unittest.main()
