import copy
import io
import json
from pathlib import Path
import re
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_solution_compatibility_eval as experiment
from question_verification import REVIEW_SYSTEM_PROMPT
from request_contract import _normalize_request


def packet():
    cases = []
    for i in range(8):
        value = i + 2
        cases.append(
            {
                "case_id": f"machine-{value}",
                "request": _normalize_request(
                    {
                        "goal": {
                            "title": "Machine rules",
                            "focusAreas": "Apply operations",
                        },
                        "sourceDocuments": [
                            {
                                "name": "Rule sheet",
                                "text": 'Literal: "e\u0301  z"\n    double then add one.',
                            }
                        ],
                        "targetCount": 1,
                        "minimumDifficulty": 1,
                    }
                ),
                "question": {
                    "prompt": f"A machine doubles {value} and then adds 1. What is the final value?",
                    "choices": [str(2 * value + d) for d in (1, 0, 2, 3)],
                    "expectedAnswer": str(2 * value + 1),
                    "topic": "Machine operations",
                    "skillID": "machine-rule",
                    "objectiveID": "two-operations",
                    "difficulty": 2,
                    "format": "Multiple Choice",
                    "explanation": "PRIVATE AUTHOR EXPLANATION",
                    "choiceExplanations": {"hidden": "PRIVATE AUTHOR FEEDBACK"},
                },
                "solution": {
                    "index": 0,
                    "outcome": "resolved",
                    "answer": f"The final value is {2 * value + 1} after the two stated operations.",
                    "limitations": "",
                    "assumptionsRequired": [],
                },
                "external_assessment": "PRIVATE EXPECTED CRITERIA",
            }
        )
    return {"cases": cases, "provenance": "PRIVATE PROVENANCE"}


def payload(request):
    return json.loads(
        request["messages"][0]["content"][0]["text"]
        .split("\n", 1)[1]
        .rsplit("\n", 1)[0]
    )


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


def mapping(choices, key):
    return {
        "checks": [
            {
                "index": 0,
                "solverRecord": {
                    "status": "coherent",
                    "reason": "The stated result and outcome agree.",
                },
                "choices": [
                    {
                        "choice": choice,
                        "relation": "entailed" if choice == key else "contradicted",
                        "reason": "Compare the stated result with this exact value.",
                    }
                    for choice in choices
                ],
            }
        ]
    }


class Client:
    def __init__(self, callback=None):
        self.requests, self.callback = [], callback

    def converse(self, **request):
        self.requests.append(copy.deepcopy(request))
        item = payload(request)["items"][0]
        key = str(2 * int(re.search(r"doubles (\d+)", item["prompt"])[1]) + 1)
        if request["system"][0]["text"] == REVIEW_SYSTEM_PROMPT:
            role = "reviewer"
            data = {
                "reviews": [
                    {
                        "index": 0,
                        "valid": True,
                        "answer": key,
                        "difficulty": 2,
                        "explanation": "Double the supplied input and add one.",
                        "choiceExplanations": {
                            choice: "Compare this with the computed final value."
                            for choice in item["choices"]
                        },
                    }
                ]
            }
        else:
            role, data = "mapper", mapping(item["choices"], key)
        return self.callback(role, data, request) if self.callback else response(data)


class SolutionCompatibilityTests(unittest.TestCase):
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
        return experiment.run_experiment(
            self.plan_path, self.freeze(), self.output, client or Client()
        )

    def test_only_role_prompt_differs_with_exact_runtime_context_and_no_key_leak(self):
        before = copy.deepcopy(self.packet)
        plan = experiment.make_plan(self.packet)
        self.assertEqual(before, self.packet)
        self.assertEqual(len(plan["jobs"]), 8)
        self.assertEqual(plan["maximum_calls"], 16)
        self.assertEqual(plan["maximum_calls_per_case"], 2)
        self.assertEqual(plan["sdk_total_max_attempts"], 1)
        for i, job in enumerate(plan["jobs"]):
            with self.subTest(i=i):
                self.assertEqual(
                    job["role_order"],
                    ["reviewer", "mapper"] if i % 2 == 0 else ["mapper", "reviewer"],
                )
                review, mapper = (
                    copy.deepcopy(job["requests"]["reviewer"]),
                    copy.deepcopy(job["requests"]["mapper"]),
                )
                self.assertEqual(review.pop("system"), [{"text": REVIEW_SYSTEM_PROMPT}])
                self.assertEqual(
                    mapper.pop("system"), [{"text": experiment.MAPPER_SYSTEM_PROMPT}]
                )
                self.assertEqual(review, mapper)
                data = payload(review)
                case = self.packet["cases"][i]
                self.assertEqual(data["goal"], case["request"]["goal"])
                self.assertEqual(
                    data["sourceDocuments"], case["request"]["sourceDocuments"]
                )
                self.assertEqual(data["independentSolutions"], [case["solution"]])
                self.assertEqual(data["items"][0]["skillID"], "machine-rule")
                self.assertEqual(data["items"][0]["objectiveID"], "two-operations")
                self.assertEqual(data["items"][0]["topic"], case["question"]["topic"])
                self.assertEqual(
                    job["choice_positions"],
                    [
                        {"position": p, "choice": c}
                        for p, c in enumerate(data["items"][0]["choices"])
                    ],
                )
                self.assertNotIn("expectedAnswer", experiment.canonical(review))
                self.assertNotIn("explanation", experiment.canonical(review))
                self.assertNotIn("PRIVATE", experiment.canonical(review))
        for file in (
            "question_verification.py",
            "question_generation.py",
            "evals/checkpoint_solution_compatibility_eval.py",
            "evals/checkpoint_model_comparison.py",
            "evals/checkpoint_source_authoring_eval.py",
            "evals/checkpoint_prompt_ablation.py",
        ):
            self.assertIn(file, plan["source_sha256"])

    def test_sixteen_durable_single_attempt_calls_preserve_raw_and_current_baseline(
        self,
    ):
        def inspect(role, data, request):
            saved = json.loads((self.output / "capture.json").read_text())
            self.assertEqual(saved["calls"][-1]["status"], "dispatch_started")
            self.assertEqual(saved["calls"][-1]["request"], request)
            self.assertFalse(saved["calls"][-1]["usage_known"])
            return response(data)

        client = Client(inspect)
        report = self.run_eval(client)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(client.requests), 16)
        self.assertEqual(
            client.requests,
            [
                job["requests"][role]
                for job in report["plan"]["jobs"]
                for role in job["role_order"]
            ],
        )
        self.assertEqual(
            report["input_utf8_bytes"], report["plan"]["planned_input_utf8_bytes"]
        )
        for result in report["results"]:
            self.assertTrue(result["baseline_eligibility"])
            self.assertTrue(result["baseline_and_strict_mapping_eligibility"])
            self.assertTrue(result["baseline_and_weak_selected_answer_compatibility"])
            self.assertEqual(
                result["baseline"]["returned_questions"][0]["verificationVersion"], 1
            )
            self.assertEqual(set(result["stage_outputs"]), {"reviewer", "mapper"})
            self.assertEqual(result["correctness_assessment"], "unassessed")
            self.assertEqual(
                result["known_usage_subtotal"], {"inputTokens": 20, "outputTokens": 40}
            )
        for call in report["calls"]:
            self.assertEqual(call["request"]["modelId"], experiment.MODEL)
            self.assertEqual(call["request"]["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(
                call["request"]["additionalModelRequestFields"],
                {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
            )
            self.assertEqual(call["response"]["reasoningContentBlockCount"], 1)
        self.assertNotIn("PRIVATE REASONING", experiment.canonical(report))
        self.assertNotIn("PRIVATE SIGNATURE", experiment.canonical(report))

    def test_strict_weak_and_abstention_are_separate_from_factual_judgment(self):
        choices, key = ["5", "4", "6", "7"], "5"
        job = {
            "choice_positions": [
                {"position": i, "choice": c} for i, c in enumerate(choices)
            ]
        }
        variants = [
            (
                "coherent",
                ["entailed", "contradicted", "contradicted", "contradicted"],
                True,
                True,
                False,
                "compatible",
            ),
            (
                "coherent",
                ["entailed", "not_established", "contradicted", "contradicted"],
                True,
                False,
                True,
                "unresolved_relation",
            ),
            (
                "uncertain",
                ["entailed", "contradicted", "contradicted", "contradicted"],
                False,
                False,
                True,
                "uncertain_record",
            ),
            (
                "inconsistent",
                ["not_established"] * 4,
                False,
                False,
                False,
                "inconsistent_record",
            ),
            (
                "coherent",
                ["contradicted", "entailed", "contradicted", "contradicted"],
                False,
                False,
                False,
                "key_disagreement",
            ),
            (
                "coherent",
                ["entailed", "entailed", "contradicted", "contradicted"],
                False,
                False,
                False,
                "nonunique_mapping",
            ),
            (
                "coherent",
                ["contradicted"] * 4,
                False,
                False,
                False,
                "nonunique_mapping",
            ),
        ]
        for status, relations, weak, strict, abstained, disposition in variants:
            with self.subTest(status=status, relations=relations):
                data = mapping(choices, key)
                data["checks"][0]["solverRecord"]["status"] = status
                for row, relation in zip(data["checks"][0]["choices"], relations):
                    row["relation"] = relation
                # Choice output order does not change exact local position joins.
                data["checks"][0]["choices"].reverse()
                observed = experiment.mapping_observation(
                    experiment.validate_mapper(json.dumps(data), choices), job, key
                )
                self.assertEqual(observed["weak_selected_answer_compatibility"], weak)
                self.assertEqual(observed["strict_mapping_eligibility"], strict)
                self.assertEqual(observed["abstained"], abstained)
                self.assertEqual(observed["disposition"], disposition)
                self.assertNotIn("correct", observed)
                self.assertNotIn("defect_detected", observed)

    def test_mapper_never_replaces_current_reviewer_acceptance(self):
        def reject(role, data, request):
            if role == "reviewer":
                number = int(
                    re.search(r"doubles (\d+)", payload(request)["items"][0]["prompt"])[
                        1
                    ]
                )
                review = data["reviews"][0]
                if number == 2:
                    review.update(valid=False, answer="")
                elif number == 3:
                    review["answer"] = str(number * 2)
                elif number == 4:
                    review["difficulty"] = 1
            return response(data)

        self.packet["cases"][2]["request"]["minimumDifficulty"] = 2
        report = self.run_eval(Client(reject))
        self.assertEqual(report["status"], "completed")
        self.assertEqual(
            [r["baseline_eligibility"] for r in report["results"][:4]],
            [False, False, False, True],
        )
        for result in report["results"][:3]:
            self.assertTrue(result["mapping"]["strict_mapping_eligibility"])
            self.assertFalse(result["baseline_and_strict_mapping_eligibility"])
            self.assertEqual(result["correctness_assessment"], "unassessed")

    def test_mapper_schema_rejects_unknowns_coercion_omission_and_changed_choices(self):
        choices = ['"e\u0301"', '"é x"', '"a  b"', '"a b"']
        base = mapping(choices, choices[0])
        mutations = [
            lambda d: d.update(extra=1),
            lambda d: d["checks"].append(copy.deepcopy(d["checks"][0])),
            lambda d: d["checks"][0].update(index=False),
            lambda d: d["checks"][0].update(index=1),
            lambda d: d["checks"][0].pop("solverRecord"),
            lambda d: d["checks"][0]["solverRecord"].update(status="resolved"),
            lambda d: d["checks"][0]["solverRecord"].update(status=None),
            lambda d: d["checks"][0]["solverRecord"].update(extra=True),
            lambda d: d["checks"][0]["solverRecord"].update(reason=" "),
            lambda d: d["checks"][0]["solverRecord"].update(reason="x" * 601),
            lambda d: d["checks"][0]["choices"].pop(),
            lambda d: d["checks"][0]["choices"][0].update(relation="true"),
            lambda d: d["checks"][0]["choices"][0].update(reason=False),
            lambda d: d["checks"][0]["choices"][0].update(choice='"é"'),
            lambda d: d["checks"][0]["choices"][0].update(choice=choices[1]),
            lambda d: d["checks"][0]["choices"][2].update(choice='"a b"'),
        ]
        self.assertEqual(
            experiment.validate_mapper(
                "```json\n" + json.dumps(base) + "\n```", choices
            ),
            base,
        )
        for change in mutations:
            data = copy.deepcopy(base)
            change(data)
            with self.subTest(data=data), self.assertRaises(Exception):
                experiment.validate_mapper(json.dumps(data), choices)
        with self.assertRaises(Exception):
            experiment.validate_mapper('{"checks":[],"checks":[]}', choices)

    def test_malformed_mapper_stops_with_raw_partial_case_and_no_rejection_credit(self):
        def malformed(role, data, request):
            if role == "mapper":
                data["checks"][0]["solverRecord"]["status"] = "unknown"
            return response(data)

        client = Client(malformed)
        report = self.run_eval(client)
        self.assertEqual(len(client.requests), 2)
        self.assertEqual(report["status"], "operational_failure")
        first = report["results"][0]
        self.assertEqual(first["format_failure_role"], "mapper")
        self.assertTrue(first["baseline_eligibility"])
        self.assertIsNone(first["baseline_and_strict_mapping_eligibility"])
        self.assertNotIn("mapping", first)
        self.assertEqual(
            first["stage_outputs"]["mapper"]["checks"][0]["solverRecord"]["status"],
            "unknown",
        )
        self.assertIn('"unknown"', report["calls"][-1]["response"]["text"][0])
        self.assertTrue(
            all(r["status"] == "unattempted" for r in report["results"][1:])
        )

    def test_malformed_negative_reviewer_is_not_successful_rejection(self):
        def malformed(role, data, request):
            data["reviews"][0].update(valid=False, answer="5")
            return response(data)

        client = Client(malformed)
        report = self.run_eval(client)
        self.assertEqual(len(client.requests), 1)
        self.assertEqual(report["status"], "operational_failure")
        self.assertIsNone(report["results"][0]["baseline_eligibility"])
        self.assertEqual(report["results"][0]["format_failure_role"], "reviewer")

    def test_provider_timeout_stops_once_and_keeps_usage_unknown(self):
        client = Client(lambda *_: (_ for _ in ()).throw(TimeoutError("not persisted")))
        report = self.run_eval(client)
        self.assertEqual(len(client.requests), 1)
        self.assertEqual(report["status"], "operational_failure")
        call = report["calls"][0]
        self.assertFalse(call["usage_known"])
        self.assertNotIn("response", call)
        self.assertFalse(report["results"][0]["usage_known"])
        self.assertIsNone(report["results"][0]["baseline_eligibility"])
        self.assertNotIn("not persisted", experiment.canonical(report))

    def test_non_end_turn_preserves_response_and_known_usage_without_retry(self):
        report = self.run_eval(
            Client(lambda role, data, request: response(data, "max_tokens"))
        )
        self.assertEqual(len(report["calls"]), 1)
        self.assertTrue(report["calls"][0]["usage_known"])
        self.assertEqual(report["calls"][0]["response"]["stopReason"], "max_tokens")
        self.assertEqual(
            report["results"][0]["known_usage_subtotal"],
            {"inputTokens": 10, "outputTokens": 20},
        )
        self.assertEqual(report["status"], "operational_failure")
        self.assertIsNone(report["results"][0]["baseline_eligibility"])

    def test_full_frozen_rebuild_and_output_guards_run_before_client_creation(self):
        approved = self.freeze()
        plan = json.loads(self.plan_path.read_text())
        variants = [
            lambda p: p.update(maximum_calls=17),
            lambda p: p["dependencies"].update(python="changed"),
            lambda p: p["source_sha256"].update(
                {"question_verification.py": "changed"}
            ),
            lambda p: p["settings"].update(BEDROCK_CLAUDE_EFFORT="low"),
            lambda p: p["jobs"][0]["requests"]["mapper"]["messages"][0]["content"][
                0
            ].update(text="changed"),
            lambda p: p["jobs"][0].update(role_order=["mapper", "reviewer"]),
        ]
        with patch.object(experiment, "new_client") as client:
            with self.assertRaises(ValueError):
                experiment.run_experiment(self.plan_path, "wrong", self.output)
            for change in variants:
                changed = copy.deepcopy(plan)
                change(changed)
                experiment.write_json(self.plan_path, changed)
                with self.subTest(change=change), self.assertRaises(ValueError):
                    experiment.run_experiment(
                        self.plan_path,
                        experiment.digest(experiment.canonical(changed)),
                        self.output,
                    )
            experiment.write_json(self.plan_path, plan)
            self.output.mkdir()
            with self.assertRaises(FileExistsError):
                experiment.run_experiment(self.plan_path, approved, self.output)
            client.assert_not_called()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_preparation_refuses_trimmed_invalid_or_pre_review_blocked_solution(self):
        variants = [
            lambda p: p["cases"][0]["solution"].pop("outcome"),
            lambda p: p["cases"][0]["solution"].update(answer=" padded answer "),
            lambda p: p["cases"][0]["solution"].update(outcome="uncertain"),
            lambda p: p["cases"][0]["solution"].update(limitations="none"),
            lambda p: p["cases"][0]["solution"].update(
                assumptionsRequired=["An unstated extra premise."]
            ),
            lambda p: p["cases"][0]["request"].update(
                existingQuestionCoverage=[{"expectedAnswer": "5"}]
            ),
            lambda p: p["cases"][0]["question"].update(expectedAnswer="unoffered"),
            lambda p: p["cases"].pop(),
            lambda p: p["cases"][0].update(case_id=p["cases"][1]["case_id"]),
        ]
        for change in variants:
            changed = copy.deepcopy(self.packet)
            change(changed)
            with self.subTest(change=change), self.assertRaises(ValueError):
                experiment.make_plan(changed)

    def test_utf8_and_recording_limits_are_checked_before_dispatch(self):
        # Code-point count alone would fit; exact UTF-8 request bytes do not.
        self.packet["cases"][0]["request"]["sourceDocuments"] = [
            {"name": "Unicode", "text": "界" * 10000}
        ]
        with self.assertRaises(ValueError):
            experiment.make_plan(self.packet)
        self.packet = packet()
        plan = experiment.make_plan(self.packet)
        for setup, case, role in (
            (lambda r: None, 0, "mapper"),
            (lambda r: r.update(input_utf8_bytes=512000), 0, "reviewer"),
            (lambda r: r.update(calls=[{}] * 16), 0, "reviewer"),
            (
                lambda r: r["plan"]["jobs"][0]["requests"]["reviewer"]["system"][
                    0
                ].update(text="界" * 10667),
                0,
                "reviewer",
            ),
        ):
            report = {"plan": copy.deepcopy(plan), "calls": [], "input_utf8_bytes": 0}
            setup(report)
            client = Client()
            recording = experiment.RecordingClient(client, report, lambda: None)
            with self.assertRaises(experiment.TrialFailure):
                recording.dispatch(case, role)
            self.assertEqual(client.requests, [])
        report = {"plan": plan, "calls": [], "input_utf8_bytes": 0}
        client = Client()
        recording = experiment.RecordingClient(client, report, lambda: None)
        recording.budgets[0].consume()
        recording.budgets[0].consume()
        with self.assertRaises(Exception):
            recording.dispatch(0, "reviewer")
        self.assertEqual(client.requests, [])

    def test_failed_durable_intent_prevents_call_and_further_admission(self):
        report = {
            "plan": experiment.make_plan(self.packet),
            "calls": [],
            "input_utf8_bytes": 0,
        }
        client = Client()
        recording = experiment.RecordingClient(
            client, report, Mock(side_effect=OSError("disk full"))
        )
        with self.assertRaises(OSError):
            recording.dispatch(0, "reviewer")
        self.assertEqual(client.requests, [])
        self.assertTrue(recording.failed)
        with self.assertRaises(experiment.TrialFailure):
            recording.dispatch(0, "mapper")
        self.assertEqual(client.requests, [])

    def test_dry_cli_and_real_factory_sdk_shape_without_optional_sdk_installed(self):
        fixture = self.root / "fixture.json"
        experiment.write_json(fixture, self.packet)
        with (
            patch.object(experiment, "new_client") as client,
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
        self.assertEqual(
            len(
                experiment.load_frozen_plan(
                    self.output / "plan.json", printed["plan_sha256"]
                )["jobs"]
            ),
            8,
        )
        factory = Mock()
        fake_boto3, fake_botocore, fake_config = (
            types.ModuleType(n) for n in ("boto3", "botocore", "botocore.config")
        )
        fake_boto3.client = factory
        fake_config.Config = lambda **kwargs: types.SimpleNamespace(**kwargs)
        with patch.dict(
            "sys.modules",
            {
                "boto3": fake_boto3,
                "botocore": fake_botocore,
                "botocore.config": fake_config,
            },
        ):
            experiment.new_client(experiment.SETTINGS, False)
        self.assertEqual(factory.call_args.args, ("bedrock-runtime",))
        config = factory.call_args.kwargs["config"]
        self.assertEqual(config.read_timeout, 100)
        self.assertEqual(config.connect_timeout, 3)
        self.assertEqual(config.retries["total_max_attempts"], 1)

    def test_actual_frozen_fixture_is_eligible_without_loading_client(self):
        fixture = (
            experiment.SERVICE_DIR
            / "evals/fixtures/question_solution_compatibility.json"
        )
        with patch.object(experiment, "new_client") as client:
            plan = experiment.make_plan(json.loads(fixture.read_text()))
            client.assert_not_called()
        self.assertEqual(len(plan["jobs"]), 8)
        self.assertLessEqual(plan["planned_input_utf8_bytes"], 512000)
        self.assertTrue(
            all(
                text not in request["messages"][0]["content"][0]["text"]
                for text in (
                    "external_assessment",
                    "expected_mapper_decision",
                    "source_provenance",
                )
                for job in plan["jobs"]
                for request in job["requests"].values()
            )
        )
