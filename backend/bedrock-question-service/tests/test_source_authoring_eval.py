import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_source_authoring_eval as experiment


def packet():
    return {
        "prospective_rubric": "SECRET EXTERNAL RUBRIC",
        "cases": [
            {
                "case_id": f"goal-{i}",
                "payload": {
                    "goal": {
                        "title": f"Synthetic machine arithmetic {i}",
                        "focusAreas": "Combining two operations",
                    },
                    "sourceDocuments": [
                        {"name": "Machine rules", "text": 'SOURCE FACT\n    "a  b"'}
                    ],
                    "targetCount": 3,
                    "minimumDifficulty": 3,
                },
                "source_provenance": "SECRET PROVENANCE",
                "adjudication_checklist": ["SECRET CHECKLIST"],
            }
            for i in range(2)
        ],
    }


def questions():
    return [
        {
            "prompt": f"A machine doubles {value} and then adds 1. What is the final value?",
            "expectedAnswer": str(2 * value + 1),
            "choices": [str(2 * value + delta) for delta in (1, 0, 2, 3)],
            "explanation": "AUTHOR EXPLANATION",
            "topic": f"Machine computation {value}",
            "difficulty": 3,
            "format": "Multiple Choice",
        }
        for value in (4, 7, 11)
    ]


def response(payload, stop="end_turn"):
    return {
        "output": {
            "message": {
                "content": [
                    {
                        "reasoningContent": {
                            "reasoningText": {
                                "text": "PRIVATE THOUGHT",
                                "signature": "PRIVATE SIGNATURE",
                            }
                        }
                    },
                    {
                        "text": payload
                        if isinstance(payload, str)
                        else "```json\n" + json.dumps(payload) + "\n```"
                    },
                ]
            }
        },
        "stopReason": stop,
        "usage": {"inputTokens": 10, "outputTokens": 20},
    }


def wrapped_payload(request):
    text = request["messages"][0]["content"][0]["text"]
    return json.loads(text.split("\n", 1)[1].rsplit("\n", 1)[0])


class Client:
    def __init__(self, callback=None):
        self.requests = []
        self.callback = callback

    def converse(self, **request):
        self.requests.append(copy.deepcopy(request))
        system = request["system"][0]["text"]
        if system == experiment.SOLUTION_SYSTEM_PROMPT:
            stage = "solver"
            data = {
                "solutions": [
                    {
                        "index": item["index"],
                        "outcome": "resolved",
                        "answer": "The operations determine a unique value.",
                        "limitations": "",
                        "assumptionsRequired": [],
                    }
                    for item in wrapped_payload(request)["items"]
                ]
            }
        elif system == experiment.REVIEW_SYSTEM_PROMPT:
            stage = "reviewer"
            data = {
                "reviews": [
                    {
                        "index": item["index"],
                        "valid": True,
                        "answer": next(
                            q["expectedAnswer"]
                            for q in questions()
                            if q["prompt"] == item["prompt"].strip()
                        ),
                        "difficulty": 3,
                        "explanation": "The machine doubles its input, then adds one.",
                        "choiceExplanations": {
                            choice: "Compare this number with the two operations."
                            for choice in item["choices"]
                        },
                    }
                    for item in wrapped_payload(request)["items"]
                ]
            }
        else:
            stage, data = "author", {"questions": questions()}
        return self.callback(stage, data, request) if self.callback else response(data)


class SourceAuthoringTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.output = self.root / "capture"
        self.plan_path = self.root / "plan.json"
        self.packet = packet()

    def freeze(self):
        plan = experiment.make_plan(self.packet)
        experiment.write_json(self.plan_path, plan)
        return experiment.digest(experiment.canonical(plan))

    def run_eval(self, client=None):
        return experiment.run_experiment(
            self.plan_path,
            self.freeze(),
            self.output,
            client if client is not None else Client(),
        )

    def test_paired_intervention_twelve_calls_and_no_evaluator_or_reasoning_leakage(
        self,
    ):
        client = Client()
        report = self.run_eval(client)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(client.requests), 12)
        self.assertEqual(
            [r["arm"] for r in report["results"]],
            ["goal_only", "source_first", "source_first", "goal_only"],
        )
        for index, job in enumerate(report["plan"]["jobs"]):
            author, solver, reviewer = client.requests[3 * index : 3 * index + 3]
            self.assertEqual(
                "SOURCE FACT" in json.dumps(author), job["arm"] == "source_first"
            )
            for request in (solver, reviewer):
                data = wrapped_payload(request)
                self.assertEqual(
                    data["sourceDocuments"], job["review_request"]["sourceDocuments"]
                )
                self.assertEqual(data["goal"], job["review_request"]["goal"])
                self.assertEqual(
                    data["sourceDocuments"][0]["text"], 'SOURCE FACT\n    "a  b"'
                )
            self.assertNotIn("choices", json.dumps(wrapped_payload(solver)["items"]))
            self.assertNotIn("AUTHOR EXPLANATION", json.dumps(reviewer))
            self.assertEqual(report["results"][index]["returned_count"], 3)
        for first in (0, 2):
            a, b = report["plan"]["jobs"][first : first + 2]
            self.assertEqual(a["review_request"], b["review_request"])
            altered = copy.deepcopy(a["author_request"])
            altered["sourceDocuments"] = b["author_request"]["sourceDocuments"]
            self.assertEqual(altered, b["author_request"])
            self.assertEqual(
                client.requests[first * 3 + 1], client.requests[(first + 1) * 3 + 1]
            )
            self.assertEqual(
                client.requests[first * 3 + 2], client.requests[(first + 1) * 3 + 2]
            )
        for request in client.requests:
            self.assertEqual(request["modelId"], experiment.MODEL)
            self.assertEqual(request["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(
                request["additionalModelRequestFields"],
                {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
            )
            for secret in (
                "SECRET EXTERNAL RUBRIC",
                "SECRET PROVENANCE",
                "SECRET CHECKLIST",
            ):
                self.assertNotIn(secret, json.dumps(request))
        saved = (self.output / "capture.json").read_text()
        self.assertNotIn("PRIVATE THOUGHT", saved)
        self.assertNotIn("PRIVATE SIGNATURE", saved)
        self.assertTrue(
            all(
                call["response"]["reasoningContentBlockCount"] == 1
                for call in report["calls"]
            )
        )
        self.assertTrue(all(call["usage_known"] for call in report["calls"]))
        self.assertLessEqual(
            report["input_utf8_bytes"], experiment.MAX_TOTAL_INPUT_BYTES
        )

    def test_raw_and_changed_display_export_deduplicates_without_losing_occurrences(
        self,
    ):
        def modify(stage, data, request):
            if stage == "author":
                data["questions"][0]["prompt"] = (
                    "\n" + data["questions"][0]["prompt"] + "  "
                )
                data["questions"][0]["choices"][0] = " 9 "
            if stage == "reviewer":
                data["reviews"][1]["difficulty"] = 2
            return response(data)

        report = self.run_eval(Client(modify))
        self.assertEqual(report["status"], "completed")
        for result in report["results"]:
            self.assertEqual(result["raw_count"], 3)
            self.assertEqual(result["sanitized_count"], 3)
            self.assertEqual(result["returned_count"], 2)
            self.assertEqual(result["raw_unblindable_count"], 0)
            self.assertEqual(
                result["metrics"]["QuestionQuality"]["review"]["difficulty_floor"], 1
            )
            self.assertEqual(len(result["stage_outputs"]["reviewer"]["reviews"]), 3)
            self.assertNotEqual(
                result["raw_occurrences"][0]["blinded"]["id"],
                result["sanitized_occurrences"][0]["blinded"]["id"],
            )
            self.assertEqual(
                result["sanitized_occurrences"][0]["blinded"]["id"],
                result["returned_occurrences"][0]["blinded"]["id"],
            )
        blind = json.loads((self.output / "blinded.json").read_text())
        self.assertEqual(
            len(blind), 8
        )  # Four exact displays per goal, shared across arms.
        self.assertEqual(
            [item["id"] for item in blind], sorted(item["id"] for item in blind)
        )
        for item in blind:
            self.assertEqual(
                set(item), {"id", "goal", "sourceDocuments", "prompt", "choices"}
            )
            content = {key: value for key, value in item.items() if key != "id"}
            self.assertEqual(
                item["id"], experiment.digest(experiment.canonical(content))
            )

    def test_semantic_sanitizer_declines_do_not_retry_or_become_format_failures(self):
        def duplicate(stage, data, request):
            if stage == "author":
                for item in data["questions"]:
                    item["choices"][1] = item["choices"][0]
            return response(data)

        client = Client(duplicate)
        report = self.run_eval(client)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(client.requests), 4)
        self.assertTrue(
            all(
                result["raw_count"] == 3 and result["sanitized_count"] == 0
                for result in report["results"]
            )
        )
        self.assertTrue(
            all(
                result["metrics"]["QuestionQuality"]["sanitize"]["invalid_choices"] == 3
                for result in report["results"]
            )
        )

    def test_solver_abstention_and_control_rejection_are_not_operational_success_claims(
        self,
    ):
        for outcome, limitations, reason in (
            ("uncertain", "", "solver_uncertain"),
            ("no_solution", "", "solver_outcome_mismatch"),
            (
                "resolved",
                "An unresolved condition remains.",
                "solver_unresolved_limitations",
            ),
        ):
            with self.subTest(outcome=outcome):
                self.output = self.root / outcome

                def solve(stage, data, request):
                    if stage == "solver":
                        for row in data["solutions"]:
                            row["outcome"] = outcome
                            row["limitations"] = limitations
                    return response(data)

                report = self.run_eval(Client(solve))
                self.assertEqual(report["status"], "completed")
                self.assertEqual(len(report["calls"]), 8)
                for result in report["results"]:
                    self.assertEqual(result["returned_count"], 0)
                    self.assertEqual(
                        result["metrics"]["QuestionQuality"]["review"][reason], 3
                    )
                    self.assertEqual(result["feedback_assessment"], "unassessed")
                    self.assertEqual(
                        result["stage_outputs"]["solver"]["solutions"][0]["outcome"],
                        outcome,
                    )

    def test_author_malformed_types_are_preserved_and_stop_globally(self):
        def malformed(stage, data, request):
            data["questions"][0]["expectedAnswer"] = 9
            data["questions"][1] = None
            return response(data)

        report = self.run_eval(Client(malformed))
        first = report["results"][0]
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(len(report["calls"]), 1)
        self.assertEqual(first["raw_count"], 3)
        self.assertEqual(first["raw_unblindable_count"], 1)
        self.assertIsNone(first["raw_occurrences"][1]["question"])
        self.assertEqual(
            first["metrics"]["QuestionQuality"]["sanitize"]["invalid_item"], 1
        )
        self.assertEqual(first["format_failure_stage"], "author")
        self.assertTrue(
            all(result["status"] == "unattempted" for result in report["results"][1:])
        )

    def test_bad_json_and_non_end_turn_stop_without_repairs(self):
        for name, reply in (
            ("json", response('{"questions":')),
            ("refusal", response({"questions": []}, "refusal")),
        ):
            with self.subTest(name=name):
                self.output = self.root / name
                report = self.run_eval(Client(lambda *args: reply))
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(len(report["calls"]), 1)
                self.assertTrue(report["calls"][0]["usage_known"])
                self.assertEqual(
                    report["results"][0]["metrics"]["BedrockInputTokens"], 10
                )
                self.assertEqual(
                    report["results"][0]["metrics"]["BedrockOutputTokens"], 20
                )
                self.assertIn("response", report["calls"][0])

    def test_durable_intent_precedes_timeout_and_unknown_usage_is_not_zero(self):
        def fail(stage, data, request):
            saved = json.loads((self.output / "capture.json").read_text())
            self.assertEqual(saved["calls"][-1]["status"], "dispatch_started")
            self.assertEqual(saved["calls"][-1]["request"], request)
            if stage == "solver":
                raise TimeoutError("SECRET PROVIDER DETAIL")
            return response(data)

        report = self.run_eval(Client(fail))
        self.assertEqual(len(report["calls"]), 2)
        self.assertEqual(report["results"][0]["raw_count"], 3)
        self.assertEqual(len(report["results"][0]["sanitized_occurrences"]), 3)
        self.assertFalse(report["calls"][1]["usage_known"])
        self.assertNotIn("response", report["calls"][1])
        self.assertIsNone(report["results"][0]["metrics"]["BedrockInputTokens"])
        self.assertNotIn(
            "SECRET PROVIDER DETAIL", (self.output / "capture.json").read_text()
        )

    def test_malformed_solver_or_review_cannot_hide_as_semantic_rejection(self):
        for stage in ("solver", "reviewer"):
            with self.subTest(stage=stage):
                self.output = self.root / stage

                def malformed(actual_stage, data, request):
                    if actual_stage == stage:
                        if stage == "solver":
                            del data["solutions"][0]["outcome"]
                        else:
                            data["reviews"][0]["difficulty"] = 2
                            data["reviews"][0]["choiceExplanations"] = {}
                    return response(data)

                report = self.run_eval(Client(malformed))
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(len(report["calls"]), 2 if stage == "solver" else 3)
                self.assertIn(stage, report["results"][0]["stage_outputs"])
                reason = "invalid_solution" if stage == "solver" else "invalid_envelope"
                self.assertEqual(
                    report["results"][0]["metrics"]["QuestionQuality"]["review"][
                        reason
                    ],
                    1,
                )

    def test_frozen_plan_is_read_without_rewriting_and_rejects_changes_before_client(
        self,
    ):
        approved = self.freeze()
        original = self.plan_path.read_bytes()
        report = experiment.run_experiment(
            self.plan_path, approved, self.output, Client()
        )
        self.assertEqual(self.plan_path.read_bytes(), original)
        self.assertEqual(report["plan_sha256"], approved)
        with self.assertRaises(FileExistsError):
            experiment.run_experiment(self.plan_path, approved, self.output, Client())
        for invalid_hash in (None, "incorrect"):
            with patch.object(experiment, "new_client") as client:
                with self.assertRaises(ValueError):
                    experiment.run_experiment(
                        self.plan_path, invalid_hash, self.root / "unused"
                    )
                client.assert_not_called()
        with (
            patch.object(experiment, "source_hashes", return_value={}),
            self.assertRaises(ValueError),
        ):
            experiment.load_frozen_plan(self.plan_path, approved)
        plan = json.loads(original)
        plan["jobs"][0]["author_user_prompt"] += "UNFROZEN CHANGE"
        experiment.write_json(self.plan_path, plan)
        with self.assertRaises(ValueError):
            experiment.load_frozen_plan(
                self.plan_path, experiment.digest(experiment.canonical(plan))
            )

    def test_dry_cli_real_fixture_does_not_construct_client_or_load_credentials(self):
        path = experiment.SERVICE_DIR / "evals/fixtures/question_source_authoring.json"
        with (
            patch.object(experiment, "new_client") as client,
            patch("sys.stdout", io.StringIO()) as output,
        ):
            self.assertEqual(
                experiment.main(["--fixture", str(path), "--output", str(self.output)]),
                0,
            )
            printed = json.loads(output.getvalue())
            client.assert_not_called()
        self.assertFalse(printed["execute"])
        self.assertEqual(printed["maximum_calls"], 12)
        plan_path = self.output / "plan.json"
        plan = experiment.load_frozen_plan(plan_path, printed["plan_sha256"])
        self.assertEqual(len(plan["jobs"]), 4)
        self.assertEqual(plan["settings"]["BEDROCK_READ_TIMEOUT_SECONDS"], "100")
        self.assertEqual(plan["maximum_input_utf8_bytes_per_call"], 32000)

    def test_dispatch_limits_shape_order_and_disk_failure_prevent_provider_calls(self):
        client = Client()
        report = {"calls": [], "input_utf8_bytes": 0}
        recording = experiment.RecordingClient(client, report, lambda: None)
        recording.job_index, recording.stage, recording.system, recording.user = (
            0,
            "author",
            "system",
            "user",
        )
        request = {
            "modelId": experiment.MODEL,
            "system": [{"text": "system"}],
            "messages": [{"role": "user", "content": [{"text": "user"}]}],
            "inferenceConfig": {"maxTokens": 16000},
            "additionalModelRequestFields": {
                "thinking": {"type": "adaptive"},
                "output_config": {"effort": "high"},
            },
        }
        with self.assertRaises(experiment.TrialFailure):
            recording.converse(
                **{**request, "inferenceConfig": {"maxTokens": 16000, "temperature": 0}}
            )
        recording.stage = "reviewer"
        with self.assertRaises(experiment.TrialFailure):
            recording.converse(**request)
        recording.stage = "author"
        recording.user = "é" * 16000
        oversized = copy.deepcopy(request)
        oversized["messages"][0]["content"][0]["text"] = recording.user
        with self.assertRaises(experiment.TrialFailure):
            recording.converse(**oversized)
        recording.user = "user"
        report["input_utf8_bytes"] = experiment.MAX_TOTAL_INPUT_BYTES
        with self.assertRaises(experiment.TrialFailure):
            recording.converse(**request)
        report["input_utf8_bytes"] = 0
        report["calls"] = [{"job_index": -1, "stage": "author"}] * 12
        with self.assertRaises(experiment.TrialFailure):
            recording.converse(**request)
        report["calls"] = []
        recording.persist = lambda: (_ for _ in ()).throw(OSError("disk unavailable"))
        with self.assertRaises(OSError):
            recording.converse(**request)
        self.assertEqual(client.requests, [])

    def test_no_clipped_sources_or_existing_history_in_plan(self):
        for key, value in (
            ("sourceDocuments", [{"name": "rules", "text": "x" * 30000}]),
            ("existingPrompts", ["A prior generated question"]),
            ("targetCount", 4),
        ):
            with self.subTest(key=key):
                altered = packet()
                altered["cases"][0]["payload"][key] = value
                with self.assertRaises(ValueError):
                    experiment.make_plan(altered)


if __name__ == "__main__":
    unittest.main()
