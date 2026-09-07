import copy
import io
import json
from pathlib import Path
import re
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_stem_length_eval as experiment


def packet():
    return {
        "prospective_assessment": "SECRET RUBRIC",
        "cases": [
            {
                "case_id": f"goal-{i}",
                "payload": {
                    "goal": {
                        "title": f"Machine rules {i}",
                        "focusAreas": "Apply two operations",
                    },
                    "sourceDocuments": [
                        {"name": "Rules", "text": 'SOURCE FACT\n    "a  b"'}
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


def questions(lengths=None):
    result = []
    for i, value in enumerate((4, 7, 11)):
        prompt = f"A machine doubles {value} and then adds 1. What is the final value?"
        if lengths is not None:
            prompt += '\nLiteral tag: "é e\u0301  z";\n    x = 1\nStatus log: '
            prompt += "x" * (lengths[i] - len(prompt))
            assert len(prompt) == lengths[i]
        result.append(
            {
                "prompt": prompt,
                "expectedAnswer": str(2 * value + 1),
                "choices": [str(2 * value + delta) for delta in (1, 0, 2, 3)],
                "explanation": "AUTHOR EXPLANATION",
                "topic": f"Machine {value}",
                "difficulty": 3,
                "format": "Multiple Choice",
            }
        )
    return result


def payload(request):
    text = request["messages"][0]["content"][0]["text"]
    return json.loads(text.split("\n", 1)[1].rsplit("\n", 1)[0])


def response(data, stop="end_turn"):
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
                    {
                        "text": data
                        if isinstance(data, str)
                        else json.dumps(data, ensure_ascii=False)
                    },
                ]
            }
        },
        "stopReason": stop,
        "usage": {"inputTokens": 10, "outputTokens": 20},
    }


class Client:
    def __init__(self, callback=None, lengths=None):
        self.requests, self.callback, self.lengths = [], callback, lengths

    def converse(self, **request):
        self.requests.append(copy.deepcopy(request))
        system = request["system"][0]["text"]
        if system == experiment.shared.SOLUTION_SYSTEM_PROMPT:
            stage = "solver"
            data = {
                "solutions": [
                    {
                        "index": item["index"],
                        "outcome": "resolved",
                        "answer": "The two stated operations determine the value.",
                        "limitations": "",
                        "assumptionsRequired": [],
                    }
                    for item in payload(request)["items"]
                ]
            }
        elif system == experiment.shared.REVIEW_SYSTEM_PROMPT:
            stage = "reviewer"
            data = {
                "reviews": [
                    {
                        "index": item["index"],
                        "valid": True,
                        "answer": str(
                            2 * int(re.search(r"doubles (\d+)", item["prompt"])[1]) + 1
                        ),
                        "difficulty": 3,
                        "explanation": "Double the input, then add one.",
                        "choiceExplanations": {
                            choice: "Compare with the computed value."
                            for choice in item["choices"]
                        },
                    }
                    for item in payload(request)["items"]
                ]
            }
        else:
            stage, data = "author", {"questions": questions(self.lengths)}
        return self.callback(stage, data, request) if self.callback else response(data)


class StemLengthTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.plan_path, self.output = self.root / "plan.json", self.root / "capture"
        self.packet = packet()

    def freeze(self):
        plan = experiment.make_plan(self.packet)
        experiment.write_json(self.plan_path, plan)
        return experiment.digest(experiment.canonical(plan))

    def run_eval(self, client=None):
        approved = self.freeze()
        return experiment.run_experiment(
            self.plan_path, approved, self.output, client or Client()
        )

    def test_plan_intervention_is_only_one_author_numeral_with_identical_context(self):
        plan = experiment.make_plan(self.packet)
        self.assertEqual(
            [j["arm"] for j in plan["jobs"]],
            ["stem_320", "stem_1200", "stem_1200", "stem_320"],
        )
        for offset in (0, 2):
            pair = {
                j["stem_limit_characters"]: j for j in plan["jobs"][offset : offset + 2]
            }
            self.assertEqual(
                pair[320]["author_system_prompt"].replace(
                    experiment.STEM_INSTRUCTION, "Stem at most\n1200 characters"
                ),
                pair[1200]["author_system_prompt"],
            )
            self.assertIn("explanation at most 320", pair[1200]["author_system_prompt"])
            for key in ("author_request", "review_request", "author_user_prompt"):
                self.assertEqual(pair[320][key], pair[1200][key])
            self.assertEqual(pair[320]["author_request"], pair[320]["review_request"])
            self.assertEqual(
                pair[1200]["review_request"]["sourceDocuments"][0]["text"],
                'SOURCE FACT\n    "a  b"',
            )
        self.assertEqual(
            plan["fixture_canonical_sha256"],
            experiment.digest(experiment.canonical(self.packet)),
        )
        for path in (
            "evals/checkpoint_stem_length_eval.py",
            "evals/checkpoint_source_authoring_eval.py",
            "evals/checkpoint_model_comparison.py",
            "evals/checkpoint_prompt_ablation.py",
            "question_quality.py",
            "question_verification.py",
        ):
            self.assertIn(path, plan["source_sha256"])
        self.assertEqual(plan["maximum_calls"], 12)
        self.assertEqual(plan["maximum_calls_per_job"], 3)
        self.assertEqual(plan["sdk_total_max_attempts"], 1)

    def test_twelve_matched_calls_are_durable_before_dispatch_and_do_not_leak_criteria(
        self,
    ):
        def inspect(stage, data, request):
            saved = json.loads((self.output / "capture.json").read_text())
            self.assertEqual(saved["calls"][-1]["status"], "dispatch_started")
            self.assertEqual(saved["calls"][-1]["request"], request)
            self.assertFalse(saved["calls"][-1]["usage_known"])
            return response(data)

        client = Client(inspect)
        report = self.run_eval(client)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(client.requests), 12)
        self.assertTrue(all(r["returned_count"] == 3 for r in report["results"]))
        for index, job in enumerate(report["plan"]["jobs"]):
            author, solver, reviewer = client.requests[index * 3 : index * 3 + 3]
            self.assertEqual(author["system"][0]["text"], job["author_system_prompt"])
            for request in (solver, reviewer):
                self.assertEqual(
                    payload(request)["sourceDocuments"],
                    job["review_request"]["sourceDocuments"],
                )
                self.assertEqual(
                    payload(request)["goal"], job["review_request"]["goal"]
                )
            self.assertNotIn("choices", json.dumps(payload(solver)["items"]))
            self.assertNotIn("AUTHOR EXPLANATION", json.dumps(reviewer))
        for first in (0, 2):
            for stage in (1, 2):
                self.assertEqual(
                    client.requests[first * 3 + stage],
                    client.requests[(first + 1) * 3 + stage],
                )
        for request in client.requests:
            self.assertEqual(request["modelId"], "us.anthropic.claude-opus-4-6-v1")
            self.assertEqual(request["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(
                request["additionalModelRequestFields"],
                {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
            )
            for secret in ("SECRET RUBRIC", "SECRET PROVENANCE", "SECRET CHECKLIST"):
                self.assertNotIn(secret, json.dumps(request))
        saved = (self.output / "capture.json").read_text()
        self.assertNotIn("PRIVATE REASONING", saved)
        self.assertNotIn("PRIVATE SIGNATURE", saved)
        self.assertEqual(experiment.question_quality.MAX_PROVIDER_PROMPT_CHARS, 320)

    def test_actual_320_321_1200_boundaries_preserve_content_and_production_rejection(
        self,
    ):
        report = self.run_eval(Client(lengths=(320, 321, 1200)))
        self.assertEqual(report["status"], "completed")
        for result in report["results"]:
            limit = result["stem_limit_characters"]
            self.assertEqual(result["sanitized_count"], 1 if limit == 320 else 3)
            self.assertEqual(result["returned_count"], 1 if limit == 320 else 3)
            self.assertEqual(result["production_320"]["sanitized_count"], 1)
            self.assertEqual(
                result["production_320"]["metrics"]["QuestionQuality"]["sanitize"][
                    "prompt_length"
                ],
                2,
            )
            for row, original in zip(
                result["raw_occurrences"], questions((320, 321, 1200)), strict=True
            ):
                self.assertEqual(row["question"], original)
                length = len(original["prompt"])
                self.assertEqual(row["prompt_code_points"], length)
                self.assertEqual(row["sanitizer_prompt_code_points"], length)
                self.assertGreater(row["prompt_utf8_bytes"], length)
                self.assertEqual(
                    row["production_320_individual"]["sanitized_count"],
                    int(length <= 320),
                )
            for row in result["sanitized_occurrences"] + result["returned_occurrences"]:
                self.assertEqual(
                    row["question"]["prompt"],
                    next(
                        q["prompt"]
                        for q in questions((320, 321, 1200))
                        if q["expectedAnswer"] == row["question"]["expectedAnswer"]
                    ),
                )
        self.assertEqual(experiment.question_quality.MAX_PROVIDER_PROMPT_CHARS, 320)

    def test_1201_decline_is_not_clipped_or_repaired_and_zero_inventory_continues(self):
        report = self.run_eval(Client(lengths=(1201, 1201, 1201)))
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 4)
        for result in report["results"]:
            self.assertEqual(
                (
                    result["raw_count"],
                    result["sanitized_count"],
                    result["returned_count"],
                ),
                (3, 0, 0),
            )
            self.assertEqual(
                result["metrics"]["QuestionQuality"]["sanitize"]["prompt_length"], 3
            )
            self.assertEqual(result["raw_occurrences"][0]["prompt_code_points"], 1201)
            self.assertFalse(result["inventory_target_met"])

    def test_raw_normalized_returned_identities_are_answer_free_and_keep_rejected_items(
        self,
    ):
        def change(stage, data, request):
            if stage == "author":
                data["questions"][0]["prompt"] = (
                    "\n" + data["questions"][0]["prompt"] + "  "
                )
            if stage == "reviewer":
                data["reviews"][1]["difficulty"] = 2
            return response(data)

        report = self.run_eval(Client(change))
        for result in report["results"]:
            self.assertEqual(result["returned_count"], 2)
            raw, clean = (
                result["raw_occurrences"][0],
                result["sanitized_occurrences"][0],
            )
            self.assertEqual(raw["prompt_code_points"], clean["prompt_code_points"] + 1)
            self.assertEqual(
                raw["sanitizer_prompt_code_points"], clean["prompt_code_points"]
            )
            self.assertNotEqual(raw["blinded"]["id"], clean["blinded"]["id"])
        blinded = json.loads((self.output / "blinded.json").read_text())
        self.assertEqual(len(blinded), 8)
        for item in blinded:
            self.assertEqual(
                set(item), {"id", "goal", "sourceDocuments", "prompt", "choices"}
            )
            self.assertEqual(
                item["id"],
                experiment.digest(
                    experiment.canonical({k: v for k, v in item.items() if k != "id"})
                ),
            )

    def test_malformed_author_solver_reviewer_stop_all_jobs_and_preserve_responses(
        self,
    ):
        for failing in ("author", "solver", "reviewer"):
            with self.subTest(failing=failing):
                self.output = self.root / failing

                def malformed(stage, data, request):
                    if stage == failing:
                        if stage == "author":
                            data["questions"][1] = None
                        elif stage == "solver":
                            del data["solutions"][0]["outcome"]
                        else:
                            data["reviews"][0]["choiceExplanations"] = {}
                    return response(data)

                report = self.run_eval(Client(malformed))
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(
                    len(report["calls"]),
                    ("author", "solver", "reviewer").index(failing) + 1,
                )
                self.assertEqual(report["results"][0]["format_failure_stage"], failing)
                self.assertIn(failing, report["results"][0]["stage_outputs"])
                self.assertTrue(
                    all(r["status"] == "unattempted" for r in report["results"][1:])
                )
                if failing == "author":
                    self.assertIsNone(
                        report["results"][0]["raw_occurrences"][1]["question"]
                    )
                self.assertEqual(
                    experiment.question_quality.MAX_PROVIDER_PROMPT_CHARS, 320
                )

    def test_timeout_unknown_usage_and_non_end_turn_stop_without_retries(self):
        for kind in ("timeout", "max_tokens", "invalid_json"):
            with self.subTest(kind=kind):
                self.output = self.root / kind

                def fail(stage, data, request):
                    if stage == "solver":
                        if kind == "timeout":
                            raise TimeoutError("PRIVATE PROVIDER DETAIL")
                        if kind == "invalid_json":
                            return response('{"solutions":')
                        return response(data, stop="max_tokens")
                    return response(data)

                report = self.run_eval(Client(fail))
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(len(report["calls"]), 2)
                self.assertEqual(report["calls"][-1]["usage_known"], kind != "timeout")
                self.assertEqual(
                    report["results"][0]["metrics"]["BedrockInputTokens"],
                    None if kind == "timeout" else 20,
                )
                self.assertNotIn(
                    "PRIVATE PROVIDER DETAIL",
                    (self.output / "capture.json").read_text(),
                )
                self.assertEqual(
                    experiment.question_quality.MAX_PROVIDER_PROMPT_CHARS, 320
                )

    def test_solver_limitations_are_abstention_observations_not_operational_or_correctness_claims(
        self,
    ):
        def block(stage, data, request):
            if stage == "solver":
                for row in data["solutions"]:
                    row["limitations"] = "An unresolved condition remains."
            return response(data)

        report = self.run_eval(Client(block))
        self.assertEqual((report["status"], len(report["calls"])), ("completed", 8))
        for result in report["results"]:
            self.assertEqual(result["returned_count"], 0)
            self.assertEqual(result["feedback_assessment"], "unassessed")
            self.assertEqual(
                result["metrics"]["QuestionQuality"]["review"][
                    "solver_unresolved_limitations"
                ],
                3,
            )

    def test_frozen_changes_and_existing_output_prevent_client_construction(self):
        approved = self.freeze()
        original = self.plan_path.read_bytes()
        experiment.run_experiment(self.plan_path, approved, self.output, Client())
        self.assertEqual(self.plan_path.read_bytes(), original)
        with patch.object(experiment.shared, "new_client") as client:
            with self.assertRaises(FileExistsError):
                experiment.run_experiment(self.plan_path, approved, self.output)
            for invalid in (None, "wrong"):
                with self.assertRaises(ValueError):
                    experiment.run_experiment(
                        self.plan_path, invalid, self.root / "unused"
                    )
            client.assert_not_called()
        for field in (
            "maximum_calls",
            "source_sha256",
            "dependencies",
            "source_revision",
            "fixture_canonical_sha256",
        ):
            with self.subTest(field=field):
                plan = json.loads(original)
                plan[field] = "changed"
                experiment.write_json(self.plan_path, plan)
                with self.assertRaises(ValueError):
                    experiment.load_frozen_plan(
                        self.plan_path, experiment.digest(experiment.canonical(plan))
                    )
        plan = json.loads(original)
        plan["jobs"][1]["author_system_prompt"] += " EXTRA INSTRUCTION"
        experiment.write_json(self.plan_path, plan)
        with self.assertRaises(ValueError):
            experiment.load_frozen_plan(
                self.plan_path, experiment.digest(experiment.canonical(plan))
            )

    def test_prompt_anchor_and_production_cap_drift_prevent_preparation(self):
        with (
            patch.object(
                experiment.shared,
                "_system_prompt",
                return_value="Stem at most 320 characters",
            ),
            self.assertRaises(ValueError),
        ):
            experiment.make_plan(self.packet)
        with (
            patch.object(
                experiment.question_quality, "MAX_PROVIDER_PROMPT_CHARS", 1200
            ),
            self.assertRaises(ValueError),
        ):
            experiment.make_plan(self.packet)

    def test_shared_dispatch_budgets_and_disk_failure_are_enforced_without_calls(self):
        client = Client()
        report = {"calls": [], "input_utf8_bytes": 0}
        recorder = experiment.shared.RecordingClient(client, report, lambda: None)
        recorder.job_index, recorder.stage, recorder.system, recorder.user = (
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
        for prior in (
            [{"job_index": -1, "stage": "author"}] * 12,
            [{"job_index": 0, "stage": s} for s in ("author", "solver", "reviewer")],
        ):
            report["calls"] = prior
            with self.assertRaises(experiment.shared.TrialFailure):
                recorder.converse(**request)
        report["calls"] = []
        report["input_utf8_bytes"] = experiment.shared.MAX_TOTAL_INPUT_BYTES
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.converse(**request)
        report["input_utf8_bytes"] = 0
        recorder.user = "é" * 16000
        oversized = copy.deepcopy(request)
        oversized["messages"][0]["content"][0]["text"] = recorder.user
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.converse(**oversized)
        recorder.user = "user"
        recorder.persist = lambda: (_ for _ in ()).throw(OSError("Disk failure"))
        with self.assertRaises(OSError):
            recorder.converse(**request)
        self.assertEqual(client.requests, [])

    def test_dynamic_reviewer_system_mismatch_cannot_dispatch(self):
        original = experiment.shared.verify_questions

        def altered(questions, request, review, metrics, *, solve):
            return original(
                questions,
                request,
                lambda system, user: review(system + " changed", user),
                metrics,
                solve=solve,
            )

        with patch.object(experiment.shared, "verify_questions", side_effect=altered):
            report = self.run_eval()
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(len(report["calls"]), 2)

    def test_dry_cli_and_single_sdk_attempt_configuration(self):
        fixture = self.root / "fixture.json"
        experiment.write_json(fixture, self.packet)
        with (
            patch.object(experiment.shared, "new_client") as client,
            patch("sys.stdout", io.StringIO()) as output,
        ):
            self.assertEqual(
                experiment.main(
                    ["--fixture", str(fixture), "--output", str(self.output)]
                ),
                0,
            )
            printed = json.loads(output.getvalue())
            client.assert_not_called()
        self.assertFalse(printed["execute"])
        plan = experiment.load_frozen_plan(
            self.output / "plan.json", printed["plan_sha256"]
        )
        self.assertEqual(len(plan["jobs"]), 4)
        # The normal backend test interpreter need not install the optional SDK.
        # Inspect the real factory's arguments through inert module substitutes.
        factory = Mock()
        fake_boto3 = types.ModuleType("boto3")
        fake_boto3.client = factory
        fake_botocore = types.ModuleType("botocore")
        fake_config = types.ModuleType("botocore.config")
        fake_config.Config = lambda **kwargs: types.SimpleNamespace(**kwargs)
        with patch.dict(
            "sys.modules",
            {
                "boto3": fake_boto3,
                "botocore": fake_botocore,
                "botocore.config": fake_config,
            },
        ):
            experiment.shared.new_client(experiment.SETTINGS, False)
            self.assertEqual(
                factory.call_args.kwargs["config"].retries["total_max_attempts"], 1
            )
            self.assertEqual(factory.call_args.kwargs["config"].read_timeout, 100)
