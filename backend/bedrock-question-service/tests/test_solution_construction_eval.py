import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_solution_construction_eval as experiment
from tests.test_solution_compatibility_eval import response


def task():
    return {
        "prompt": "A machine doubles 3 and then adds 1. What is the final value?",
        "topic": "Machine operations",
        "objective": "Apply two ordered operations",
        "difficulty": 3,
    }


def packet():
    cases = [
        {
            "case_id": f"case-{i}",
            "context": {
                "goal": {
                    "title": f"Machine rules {i}",
                    "focusAreas": "Ordered operations",
                    "private": "PRIVATE GOAL",
                },
                "sourceDocuments": [
                    {
                        "name": "Rules",
                        "text": 'Keep exact "e\u0301  z"\n    spacing.',
                        "private": "PRIVATE SOURCE",
                    }
                ],
                "minimumDifficulty": 3,
                "private": "PRIVATE CONTEXT",
            },
            "external_assessment": {"expected": "PRIVATE EXPECTED KEY"},
        }
        for i in range(4)
    ]
    cases[-1]["fixed_task"] = task()
    return {
        "experiment": experiment.EXPERIMENT,
        "cases": cases,
        "provenance": "PRIVATE METADATA",
    }


def stage_data(role):
    if role == "author":
        return {"task": task()}
    if role == "solver":
        return {
            "solution": {
                "status": "answered",
                "answerText": "7",
                "support": "Double three to six, then add one. PRIVATE SUPPORT",
                "assumptionsRequired": [],
            }
        }
    if role == "distractor":
        return {
            "distractors": [
                {
                    "text": value,
                    "explanation": f"The ordered operations produce seven, not {value}.",
                }
                for value in ("6", "8", "9")
            ],
            "explanation": "Doubling three produces six, then adding one gives seven.",
            "answerExplanation": "Seven is the result after both operations in order.",
        }
    return {
        "reviews": [
            {
                "index": 0,
                "valid": True,
                "answer": "7",
                "difficulty": 3,
                "explanation": "Doubling three produces six, then adding one gives seven.",
                "choiceExplanations": {
                    value: "Apply both operations in their stated order to obtain seven."
                    for value in ("7", "6", "8", "9")
                },
            }
        ]
    }


class Client:
    """Scripted transport only; never creates an SDK client."""

    def __init__(self, callback=None):
        self.callback, self.requests, self.roles = callback, [], []

    def converse(self, **request):
        role = next(
            k
            for k, v in experiment.contract.PROMPTS.items()
            if v == request["system"][0]["text"]
        )
        self.requests.append(copy.deepcopy(request))
        self.roles.append(role)
        data = stage_data(role)
        return self.callback(role, data, request) if self.callback else response(data)


class SolutionConstructionEvalTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.plan_path, self.output = self.root / "plan.json", self.root / "capture"
        self.packet = packet()

    def freeze(self):
        plan = experiment.make_plan(self.packet)
        experiment.shared.write_json(self.plan_path, plan)
        return plan, experiment._hash(plan)

    def run_eval(self, callback=None):
        plan, approved = self.freeze()
        client = Client(callback)
        return experiment.run_experiment(
            self.plan_path, approved, self.output, client
        ), client

    def test_fifteen_calls_key_freeze_and_replay(self):
        def check(role, data, request):
            saved = json.loads((self.output / "capture.json").read_text())
            call = saved["calls"][-1]
            self.assertEqual(call["request"], request)
            self.assertEqual(call["status"], "dispatch_started")
            self.assertEqual(
                call["request_canonical_sha256"], experiment._hash(request)
            )
            user = request["messages"][0]["content"][0]["text"]
            for sentinel in (
                "PRIVATE GOAL",
                "PRIVATE SOURCE",
                "PRIVATE CONTEXT",
                "PRIVATE EXPECTED KEY",
                "PRIVATE METADATA",
            ):
                self.assertNotIn(sentinel, user)
            if role in ("author", "solver"):
                self.assertNotIn("answerText", user)
                self.assertNotIn('"choices"', user)
            if role == "reviewer":
                self.assertNotIn("PRIVATE SUPPORT", user)
                self.assertNotIn("expectedAnswer", user)
                self.assertNotIn("choiceExplanations", user)
            return response(data)

        report, client = self.run_eval(check)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(
            client.roles, list(experiment.ROLES) * 3 + list(experiment.ROLES[1:])
        )
        self.assertEqual(len(client.requests), 15)
        self.assertNotIn("PRIVATE REASONING", experiment.shared.canonical(report))
        self.assertNotIn("PRIVATE SIGNATURE", experiment.shared.canonical(report))
        for row in report["results"]:
            self.assertEqual(row["status"], "constructed")
            self.assertEqual(row["question"]["prompt"], task()["prompt"])
            self.assertEqual(
                row["question"]["expectedAnswer"], row["solution"]["answerText"]
            )
            self.assertEqual(
                row["review_observation"]["question"]["expectedAnswer"], "7"
            )
            self.assertNotIn("verificationVersion", row["question"])
            self.assertEqual(row["correctness_assessment"], "unassessed")
        rebuilt = experiment.replay_capture(report, report["plan_sha256"])
        self.assertEqual(rebuilt["provider_calls"], 15)
        self.assertEqual(rebuilt["input_utf8_bytes"], report["input_utf8_bytes"])

    def test_plan_preserves_order_limits_and_source_hashes(self):
        self.packet["cases"].insert(0, self.packet["cases"].pop())
        original = copy.deepcopy(self.packet)
        plan = experiment.make_plan(self.packet)
        self.assertEqual(self.packet, original)
        self.assertEqual(plan["jobs"][0]["role_order"], list(experiment.ROLES[1:]))
        self.assertEqual(plan["maximum_calls"], 15)
        self.assertEqual(plan["maximum_calls_per_case"], 4)
        self.assertEqual(plan["maximum_input_utf8_bytes_per_call"], 32000)
        self.assertEqual(plan["maximum_input_utf8_bytes_total"], 480000)
        self.assertEqual(plan["sdk_total_max_attempts"], 1)
        self.assertEqual(plan["model"], experiment.shared.MODEL)
        self.assertEqual(plan["settings"]["BEDROCK_READ_TIMEOUT_SECONDS"], "100")
        for name in (
            "evals/question_solution_construction.py",
            "evals/checkpoint_solution_construction_eval.py",
            "evals/checkpoint_solution_compatibility_eval.py",
            "evals/checkpoint_model_comparison.py",
            "question_verification.py",
        ):
            self.assertIn(name, plan["source_sha256"])

    def test_invalid_case_inventory_fails_before_client(self):
        for mutate in (
            lambda p: p.update(experiment="different-experiment"),
            lambda p: p["cases"].pop(),
            lambda p: p["cases"][0].update(case_id=p["cases"][1]["case_id"]),
            lambda p: p["cases"][0].update(fixed_task=task()),
            lambda p: p["cases"][-1].pop("fixed_task"),
        ):
            with self.subTest(mutate=mutate):
                value = packet()
                mutate(value)
                with self.assertRaises(ValueError):
                    experiment.make_plan(value)

    def test_uncertain_solution_rejects_only_its_case(self):
        changed = False

        def uncertain(role, data, request):
            nonlocal changed
            if role == "solver" and not changed:
                changed = True
                data["solution"].update(status="uncertain", answerText="")
            return response(data)

        report, client = self.run_eval(uncertain)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(client.requests), 13)
        self.assertEqual(
            report["results"][0]["rejection"]["reason"], "solution_ineligible"
        )
        self.assertEqual(client.roles[:3], ["author", "solver", "author"])
        self.assertEqual(
            experiment.replay_capture(report, report["plan_sha256"])["provider_calls"],
            13,
        )

    def test_well_typed_overlong_content_rejects_case_without_truncation(self):
        changed = False

        def long_task(role, data, request):
            nonlocal changed
            if role == "author" and not changed:
                changed = True
                data["task"]["prompt"] = "x" * 321
            return response(data)

        report, client = self.run_eval(long_task)
        self.assertEqual(len(client.requests), 12)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["results"][0]["status"], "content_rejected")
        self.assertEqual(
            report["results"][0]["stage_outputs"]["author"]["task"]["prompt"], "x" * 321
        )
        self.assertNotIn("task", report["results"][0])
        experiment.replay_capture(report, report["plan_sha256"])

    def test_duplicate_distractors_reject_without_repair(self):
        changed = False

        def duplicate(role, data, request):
            nonlocal changed
            if role == "distractor" and not changed:
                changed = True
                data["distractors"][0]["text"] = "7"
            return response(data)

        report, client = self.run_eval(duplicate)
        self.assertEqual(len(client.requests), 14)
        self.assertEqual(report["results"][0]["status"], "content_rejected")
        self.assertNotIn("question", report["results"][0])
        experiment.replay_capture(report, report["plan_sha256"])

    def test_approving_reviewer_cannot_replace_key(self):
        def disagreement(role, data, request):
            if role == "reviewer":
                data["reviews"][0]["answer"] = "6"
            return response(data)

        report, _ = self.run_eval(disagreement)
        for row in report["results"]:
            self.assertEqual(row["status"], "content_rejected")
            self.assertEqual(row["rejection"]["reason"], "answer_disagreement")
            self.assertEqual(row["question"]["expectedAnswer"], "7")
        experiment.replay_capture(report, report["plan_sha256"])

    def test_provider_failure_stops_all_remaining_dispatch(self):
        def fail(role, data, request):
            raise TimeoutError("synthetic")

        report, client = self.run_eval(fail)
        self.assertEqual(len(client.requests), 1)
        self.assertEqual(report["status"], "operational_failure")
        self.assertTrue(report["stopped_early"])
        self.assertEqual(
            [r["status"] for r in report["results"]],
            ["operational_failure"] + ["unattempted"] * 3,
        )
        self.assertFalse(report["calls"][0]["usage_known"])
        experiment.replay_capture(report, report["plan_sha256"])

    def test_malformed_envelope_or_non_end_turn_stops_trial(self):
        for name, reply in (
            ("json", response("not json")),
            ("envelope", response({"task": []})),
            ("stop", response(stage_data("author"), stop="max_tokens")),
        ):
            with self.subTest(name=name):
                self.output = self.root / name
                report, client = self.run_eval(lambda *_: reply)
                self.assertEqual(len(client.requests), 1)
                self.assertEqual(report["status"], "operational_failure")
                experiment.replay_capture(report, report["plan_sha256"])

    def test_persistence_failure_prevents_provider_dispatch(self):
        _, approved = self.freeze()
        client = Client()
        writer = experiment.shared.write_json
        calls = 0

        def fail_dispatch_write(path, value):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("synthetic fsync failure")
            return writer(path, value)

        with patch.object(
            experiment.shared, "write_json", side_effect=fail_dispatch_write
        ):
            report = experiment.run_experiment(
                self.plan_path, approved, self.output, client
            )
        self.assertEqual(client.requests, [])
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["calls"][0]["error"]["type"], "OSError")
        self.assertFalse(report["calls"][0]["provider_dispatch_attempted"])
        self.assertEqual(report["results"][0]["provider_calls"], 0)
        replayed = experiment.replay_capture(report, approved)
        self.assertEqual(replayed["dispatch_intents"], 1)
        self.assertEqual(replayed["provider_calls"], 0)

    def test_existing_directory_and_mutated_plan_never_dispatch(self):
        plan, approved = self.freeze()
        client = Client()
        self.output.mkdir()
        with self.assertRaises(FileExistsError):
            experiment.run_experiment(self.plan_path, approved, self.output, client)
        self.assertEqual(client.requests, [])
        plan["maximum_calls"] = 16
        experiment.shared.write_json(self.plan_path, plan)
        for claimed_hash in (approved, experiment._hash(plan)):
            with self.assertRaises(ValueError):
                experiment.run_experiment(
                    self.plan_path, claimed_hash, self.output, client
                )
        self.assertEqual(client.requests, [])

    def test_budget_and_order_checks_happen_before_call(self):
        plan, _ = self.freeze()
        report = {
            "plan": plan,
            "results": experiment._initial_results(plan),
            "calls": [],
            "input_utf8_bytes": 0,
        }
        report["results"][0]["status"] = "running"
        client = Client()
        recorder = experiment.RecordingClient(client, report, Mock())
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.dispatch(0, "solver")
        with patch.object(experiment, "MAX_INPUT_BYTES", 1):
            with self.assertRaises(experiment.shared.TrialFailure):
                recorder.dispatch(0, "author")
        report["input_utf8_bytes"] = experiment.MAX_TOTAL_INPUT_BYTES
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.dispatch(0, "author")
        report["input_utf8_bytes"] = 0
        report["calls"] = [{"case_index": 0}] * 15
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.dispatch(0, "author")
        self.assertEqual(client.requests, [])

    def test_replay_rejects_mutated_joins_and_json_type_changes(self):
        report, _ = self.run_eval()
        changes = (
            lambda r: r.update(status="operational_failure"),
            lambda r: r["calls"].pop(),
            lambda r: r["results"][0]["stage_outputs"].pop("solver"),
            lambda r: r["calls"][1]["request"]["messages"][0]["content"][0].update(
                text="changed"
            ),
            lambda r: r["calls"][2]["bindings"].update(
                solution_canonical_sha256="0" * 64
            ),
            lambda r: r["results"][0]["question"].update(expectedAnswer="6"),
            lambda r: r["results"][0]["stage_outputs"]["reviewer"]["reviews"][0].update(
                valid=1
            ),
            lambda r: r["calls"][0].update(case_index=False),
            lambda r: r["calls"][0].update(usage_known=1),
            lambda r: r["calls"].append(copy.deepcopy(r["calls"][-1])),
            lambda r: r["plan"]["settings"].update(BEDROCK_READ_TIMEOUT_SECONDS="300"),
        )
        for mutate in changes:
            with self.subTest(mutate=mutate):
                changed = copy.deepcopy(report)
                mutate(changed)
                with self.assertRaises(ValueError):
                    experiment.replay_capture(changed, report["plan_sha256"])

    def test_zero_dispatch_client_setup_failure_replays_without_invented_call(self):
        _, approved = self.freeze()
        with patch.object(
            experiment.shared,
            "new_client",
            side_effect=RuntimeError("synthetic auth setup"),
        ):
            with self.assertRaises(RuntimeError):
                experiment.run_experiment(self.plan_path, approved, self.output)
        report = json.loads((self.output / "capture.json").read_text())
        self.assertEqual(report["calls"], [])
        self.assertEqual(report["status"], "operational_failure")
        self.assertTrue(report["stopped_early"])
        replayed = experiment.replay_capture(report, approved)
        self.assertEqual(replayed["provider_calls"], 0)
        self.assertEqual(
            [r["status"] for r in replayed["results"]], ["unattempted"] * 4
        )

    def test_cli_dry_preparation_does_not_make_client(self):
        fixture = self.root / "fixture.json"
        fixture.write_text(json.dumps(self.packet))
        with (
            patch.object(experiment.shared, "new_client") as client,
            patch("sys.stdout", new_callable=io.StringIO),
        ):
            self.assertEqual(
                experiment.main(
                    ["--fixture", str(fixture), "--output", str(self.output)]
                ),
                0,
            )
        client.assert_not_called()
        self.assertTrue((self.output / "plan.json").is_file())
        self.assertFalse((self.output / "capture.json").exists())
