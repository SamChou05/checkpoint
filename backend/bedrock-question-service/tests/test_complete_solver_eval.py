import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_complete_solver_eval as experiment
from question_verification import SOLUTION_SYSTEM_PROMPT, verify_questions
from tests.test_solution_compatibility_eval import packet, response


class Client:
    """Fixed harmless replies; no provider SDK or model inference."""

    def __init__(self, plan, callback=None):
        self.plan, self.callback, self.requests = plan, callback, []
        self.order = [
            (i, role)
            for i, job in enumerate(plan["jobs"])
            for role in job["role_order"]
        ]

    def converse(self, **request):
        index, role = self.order[len(self.requests)]
        self.requests.append(copy.deepcopy(request))
        case = self.plan["fixture"]["cases"][index]
        if role == "stem_only":
            data = {"solutions": [copy.deepcopy(case["solution"])]}
        else:
            data = {
                "solutions": [
                    {
                        "index": 0,
                        "choices": [
                            {
                                "choice": choice,
                                "judgment": "supported"
                                if choice == case["question"]["expectedAnswer"]
                                else "refuted",
                                "reason": "Compare the result of the two explicit operations.",
                            }
                            for choice in reversed(case["question"]["choices"])
                        ],
                    }
                ]
            }
        return self.callback(role, data, request) if self.callback else response(data)


class CompleteSolverEvalTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.plan_path, self.output = self.root / "plan.json", self.root / "capture"
        self.packet = packet()
        # A previous solution is deliberately present outside the question data.
        for case in self.packet["cases"]:
            case["solution"]["answer"] += " PRIVATE OLD SOLUTION"

    def freeze(self):
        plan = experiment.make_plan(self.packet)
        experiment.shared.write_json(self.plan_path, plan)
        return plan, experiment.shared.digest(experiment.shared.canonical(plan))

    def run_eval(self, callback=None):
        plan, approved = self.freeze()
        client = Client(plan, callback)
        return experiment.run_experiment(
            self.plan_path, approved, self.output, client
        ), client

    def test_frozen_baseline_is_actual_runtime_callback_and_candidate_is_isolated(self):
        before = copy.deepcopy(self.packet)
        plan = experiment.make_plan(self.packet)
        self.assertEqual(self.packet, before)
        self.assertEqual(len(plan["jobs"]), 8)
        self.assertEqual(plan["maximum_calls"], 16)
        self.assertEqual(plan["maximum_calls_per_case"], 2)
        self.assertEqual(plan["sdk_total_max_attempts"], 1)
        self.assertIn("not an isolated context-only ablation", plan["comparison"])
        for i, job in enumerate(plan["jobs"]):
            case = self.packet["cases"][i]
            captured = []

            class Captured(Exception):
                pass

            def solve(system, user):
                captured.append((system, user))
                raise Captured()

            review = Mock(
                side_effect=AssertionError("No final review in this experiment")
            )
            with self.assertRaises(Captured):
                verify_questions(
                    [copy.deepcopy(case["question"])],
                    copy.deepcopy(case["request"]),
                    review,
                    solve=solve,
                )
            review.assert_not_called()
            self.assertEqual(
                job["requests"]["stem_only"],
                experiment.shared.converse_request(*captured[0]),
            )
            self.assertEqual(captured[0][0], SOLUTION_SYSTEM_PROMPT)
            baseline_user = job["requests"]["stem_only"]["messages"][0]["content"][0][
                "text"
            ]
            candidate_user = job["requests"]["complete_mcq"]["messages"][0]["content"][
                0
            ]["text"]
            self.assertNotIn('"choices"', baseline_user)
            for choice in case["question"]["choices"]:
                self.assertIn(json.dumps(choice, ensure_ascii=False), candidate_user)
            for text in (baseline_user, candidate_user):
                self.assertNotIn("PRIVATE", text)
                self.assertNotIn("expectedAnswer", text)
                self.assertNotIn("choiceExplanations", text)
                self.assertNotIn("external_assessment", text)
                self.assertIn(
                    json.dumps(case["question"]["prompt"], ensure_ascii=False), text
                )
                self.assertIn(
                    json.dumps(
                        case["request"]["sourceDocuments"][0]["text"],
                        ensure_ascii=False,
                    ),
                    text,
                )
            self.assertEqual(
                job["role_order"],
                ["stem_only", "complete_mcq"]
                if i % 2 == 0
                else ["complete_mcq", "stem_only"],
            )
        for name in (
            "evals/checkpoint_complete_solver_eval.py",
            "evals/question_complete_solver.py",
            "evals/checkpoint_solution_compatibility_eval.py",
            "question_verification.py",
            "evals/checkpoint_prompt_ablation.py",
        ):
            self.assertIn(name, plan["source_sha256"])

    def test_same_stem_variant_changes_complete_input_but_not_current_solver_input(
        self,
    ):
        first = copy.deepcopy(self.packet["cases"][0])
        changed = copy.deepcopy(first)
        changed["case_id"] = "same-stem-different-choices"
        changed["question"]["choices"] = ["6", "8", "10", "12"]
        changed["question"]["expectedAnswer"] = "6"
        self.packet["cases"][:2] = [first, changed]
        plan = experiment.make_plan(self.packet)
        self.assertEqual(
            plan["jobs"][0]["requests"]["stem_only"],
            plan["jobs"][1]["requests"]["stem_only"],
        )
        self.assertNotEqual(
            plan["jobs"][0]["requests"]["complete_mcq"],
            plan["jobs"][1]["requests"]["complete_mcq"],
        )

    def test_sixteen_durable_calls_with_frozen_second_role_and_final_text_only(self):
        def inspect(role, data, request):
            saved = json.loads((self.output / "capture.json").read_text())
            call = saved["calls"][-1]
            self.assertEqual(call["request"], request)
            self.assertEqual(call["status"], "dispatch_started")
            self.assertFalse(call["usage_known"])
            # This output must never become input to any later role/case.
            if role == "stem_only":
                data["solutions"][0]["answer"] += " RESPONSE ISOLATION SENTINEL"
            else:
                data["solutions"][0]["choices"][0]["reason"] += (
                    " RESPONSE ISOLATION SENTINEL"
                )
            return response(data)

        report, client = self.run_eval(inspect)
        self.assertEqual(report["status"], "completed")
        expected = [
            j["requests"][role]
            for j in report["plan"]["jobs"]
            for role in j["role_order"]
        ]
        self.assertEqual(client.requests, expected)
        self.assertEqual(len(client.requests), 16)
        self.assertNotIn(
            "RESPONSE ISOLATION SENTINEL", experiment.shared.canonical(client.requests)
        )
        self.assertIn(
            "RESPONSE ISOLATION SENTINEL",
            experiment.shared.canonical(report["results"]),
        )
        self.assertNotIn("PRIVATE REASONING", experiment.shared.canonical(report))
        self.assertNotIn("PRIVATE SIGNATURE", experiment.shared.canonical(report))
        self.assertEqual(
            report["input_utf8_bytes"], report["plan"]["planned_input_utf8_bytes"]
        )
        for result in report["results"]:
            self.assertEqual(
                set(result["stage_outputs"]), {"stem_only", "complete_mcq"}
            )
            self.assertEqual(set(result["observations"]), {"stem_only", "complete_mcq"})
            self.assertTrue(result["observations"]["stem_only"]["pre_review_eligibility"])
            self.assertEqual(result["provider_calls"], 2)
            self.assertEqual(
                result["known_usage_subtotal"], {"inputTokens": 20, "outputTokens": 40}
            )
            self.assertEqual(result["correctness_assessment"], "unassessed")
            self.assertNotIn("returned_questions", result)
        for call in report["calls"]:
            self.assertEqual(call["request"]["modelId"], experiment.shared.MODEL)
            self.assertEqual(call["request"]["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(call["response"]["reasoningContentBlockCount"], 1)

    def test_baseline_uncertainty_and_limitations_are_only_pre_review_observations(
        self,
    ):
        def blocked(role, data, request):
            if role == "stem_only":
                number = len(seen)
                seen.append(request)
                if number == 0:
                    data["solutions"][0]["outcome"] = "uncertain"
                elif number == 1:
                    data["solutions"][0]["limitations"] = (
                        "An unproved condition is required."
                    )
            return response(data)

        seen = []
        report, client = self.run_eval(blocked)
        self.assertEqual(len(client.requests), 16)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(
            [
                r["observations"]["stem_only"]["pre_review_rejection_reason"]
                for r in report["results"][:2]
            ],
            ["solver_uncertain", "solver_unresolved_limitations"],
        )
        self.assertTrue(
            all(r["correctness_assessment"] == "unassessed" for r in report["results"])
        )
        self.assertTrue(
            all("complete_mcq" in r["observations"] for r in report["results"])
        )

    def test_candidate_uncertainty_is_preserved_without_format_or_provider_failure(
        self,
    ):
        def uncertain(role, data, request):
            if role == "complete_mcq":
                for row in data["solutions"][0]["choices"]:
                    row["judgment"] = "uncertain"
            return response(data)

        report, client = self.run_eval(uncertain)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(client.requests), 16)
        for result in report["results"]:
            self.assertFalse(
                result["observations"]["complete_mcq"]["pre_review_eligibility"]
            )
            self.assertEqual(
                result["observations"]["complete_mcq"]["disposition"], "uncertain"
            )
            self.assertEqual(
                {
                    row["judgment"]
                    for row in result["stage_outputs"]["complete_mcq"]["solutions"][0][
                        "choices"
                    ]
                },
                {"uncertain"},
            )
            self.assertEqual(result["correctness_assessment"], "unassessed")
            self.assertNotIn("format_failure_role", result)

    def test_malformed_outputs_stop_and_preserve_raw_without_credit(self):
        for failing_role, expected_calls in (("stem_only", 1), ("complete_mcq", 2)):
            with self.subTest(role=failing_role):
                self.output = self.root / failing_role

                def malformed(role, data, request):
                    if role == failing_role:
                        if role == "stem_only":
                            data["solutions"][0].pop("outcome")
                        else:
                            data["solutions"][0]["choices"][0]["judgment"] = "invented"
                    return response(data)

                report, client = self.run_eval(malformed)
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(len(client.requests), expected_calls)
                self.assertEqual(
                    report["results"][0]["format_failure_role"], failing_role
                )
                self.assertNotIn(failing_role, report["results"][0]["observations"])
                self.assertTrue(report["calls"][-1]["response"]["text"])
                self.assertTrue(
                    all(r["status"] == "unattempted" for r in report["results"][1:])
                )

    def test_provider_failure_and_non_end_turn_stop_with_honest_usage(self):
        for timeout in (True, False):
            with self.subTest(timeout=timeout):
                self.output = self.root / str(timeout)

                def failed(role, data, request):
                    if timeout:
                        raise TimeoutError("LOCAL DETAIL NOT CAPTURED")
                    return response(data, "max_tokens")

                report, client = self.run_eval(failed)
                self.assertEqual(len(client.requests), 1)
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(report["calls"][0]["usage_known"], not timeout)
                self.assertEqual(report["results"][0]["observations"], {})
                self.assertEqual(
                    report["results"][0]["correctness_assessment"], "unassessed"
                )
                self.assertNotIn(
                    "LOCAL DETAIL NOT CAPTURED", experiment.shared.canonical(report)
                )

    def test_frozen_hash_full_rebuild_and_existing_output_checked_before_client(self):
        plan, approved = self.freeze()
        mutations = [
            lambda p: p.update(maximum_calls=17),
            lambda p: p["dependencies"].update(python="changed"),
            lambda p: p["source_sha256"].update(
                {"evals/question_complete_solver.py": "changed"}
            ),
            lambda p: p["source_sha256"].update(
                {"evals/checkpoint_solution_compatibility_eval.py": "changed"}
            ),
            lambda p: p["jobs"][0]["requests"]["stem_only"]["messages"][0]["content"][
                0
            ].update(text="changed"),
            lambda p: p["jobs"][0]["requests"]["complete_mcq"]["system"][0].update(
                text="changed"
            ),
            lambda p: p["jobs"][0].update(role_order=["complete_mcq", "stem_only"]),
        ]
        with patch.object(experiment.shared, "new_client") as client:
            with self.assertRaises(ValueError):
                experiment.run_experiment(self.plan_path, "wrong", self.output)
            for change in mutations:
                changed = copy.deepcopy(plan)
                change(changed)
                experiment.shared.write_json(self.plan_path, changed)
                with self.assertRaises(ValueError):
                    experiment.run_experiment(
                        self.plan_path,
                        experiment.shared.digest(experiment.shared.canonical(changed)),
                        self.output,
                    )
            experiment.shared.write_json(self.plan_path, plan)
            self.output.mkdir()
            with self.assertRaises(FileExistsError):
                experiment.run_experiment(self.plan_path, approved, self.output)
            client.assert_not_called()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_durable_capture_failure_prevents_sdk_dispatch(self):
        plan, approved = self.freeze()
        client = Client(plan)
        real_write = experiment.shared.write_json

        def write(path, value):
            if value.get("calls"):
                raise OSError("No durable storage")
            return real_write(path, value)

        with (
            patch.object(experiment.shared, "write_json", side_effect=write),
            self.assertRaises(OSError),
        ):
            experiment.run_experiment(self.plan_path, approved, self.output, client)
        self.assertEqual(client.requests, [])

    def test_limits_and_dry_cli_need_no_sdk_or_credentials(self):
        original = copy.deepcopy(self.packet)
        self.packet["cases"][0]["request"]["sourceDocuments"][0]["text"] = "界" * 12000
        with self.assertRaises(ValueError):
            experiment.make_plan(self.packet)
        self.packet = original
        fixture = self.root / "fixture.json"
        experiment.shared.write_json(fixture, self.packet)
        with (
            patch.object(experiment.shared, "new_client") as client,
            patch("sys.stdout", io.StringIO()) as stdout,
        ):
            self.assertEqual(
                experiment.main(
                    ["--fixture", str(fixture), "--output", str(self.output)]
                ),
                0,
            )
            client.assert_not_called()
        result = json.loads(stdout.getvalue())
        self.assertFalse(result["execute"])
        self.assertEqual(result["maximum_calls"], 16)
        plan = experiment.load_frozen_plan(
            self.output / "plan.json", result["plan_sha256"]
        )
        self.assertEqual(plan["maximum_input_utf8_bytes_per_call"], 32000)
        self.assertEqual(plan["maximum_input_utf8_bytes_total"], 512000)
