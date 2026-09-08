import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_artifact_authoring_eval as experiment
from tests.test_solution_compatibility_eval import response


def packet():
    return {
        "experiment": experiment.EXPERIMENT,
        "assessment_only": "PRIVATE RUBRIC",
        "cases": [
            {
                "case_id": family + "-fresh",
                "family": family,
                "system_prompt": "Author two independent " + family + " artifacts.",
                "user_data": {
                    "goal": "Interpret " + family + " state",
                    "source": family + ' literal source\n    "red  blue"',
                },
                "assessment_only": "PRIVATE ANSWER",
            }
            for family in experiment.FAMILIES
        ],
    }


class Client:
    def __init__(self, callback=None):
        self.callback, self.requests = callback, []

    def converse(self, **request):
        self.requests.append(copy.deepcopy(request))
        data = {"candidates": [{"artifact": "FIRST RESPONSE ONLY"}, {}]}
        return self.callback(data, request) if self.callback else response(data)


class ArtifactAuthoringEvalTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.plan_path, self.output = self.root / "plan.json", self.root / "capture"
        self.packet = packet()
        # Contract tests do not depend on concurrent adapter implementation.
        # The actual source-hash implementation is independently tested below.
        mocked = patch.object(
            experiment,
            "source_hashes",
            return_value={name: "frozen" for name in experiment.ADAPTER_SOURCES},
        )
        mocked.start()
        self.addCleanup(mocked.stop)

    def freeze(self):
        plan = experiment.make_plan(self.packet)
        experiment.shared.write_json(self.plan_path, plan)
        return plan, experiment.shared.digest(experiment.shared.canonical(plan))

    def run_eval(self, callback=None):
        plan, approved = self.freeze()
        client = Client(callback)
        return experiment.run_experiment(
            self.plan_path, approved, self.output, client
        ), client

    def test_plan_freezes_two_isolated_exact_author_requests_and_limits(self):
        before = copy.deepcopy(self.packet)
        plan = experiment.make_plan(self.packet)
        self.assertEqual(before, self.packet)
        self.assertEqual(plan["maximum_calls"], 2)
        self.assertEqual(plan["maximum_calls_per_case"], 1)
        self.assertEqual(plan["maximum_input_utf8_bytes_per_call"], 32000)
        self.assertEqual(plan["maximum_input_utf8_bytes_total"], 64000)
        self.assertEqual(plan["sdk_total_max_attempts"], 1)
        self.assertEqual(plan["settings"]["BEDROCK_READ_TIMEOUT_SECONDS"], "100")
        self.assertEqual(plan["settings"]["BEDROCK_CONNECT_TIMEOUT_SECONDS"], "3")
        for index, job in enumerate(plan["jobs"]):
            case = self.packet["cases"][index]
            self.assertEqual(job["family"], experiment.FAMILIES[index])
            self.assertEqual(job["role_order"], ["author"])
            request = job["requests"]["author"]
            self.assertEqual(request["system"], [{"text": case["system_prompt"]}])
            self.assertEqual(request["modelId"], "us.anthropic.claude-opus-4-6-v1")
            self.assertEqual(request["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(
                request["additionalModelRequestFields"],
                {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
            )
            text = request["messages"][0]["content"][0]["text"]
            self.assertEqual(
                text,
                "<artifact_authoring_json>\n"
                + json.dumps(case["user_data"], ensure_ascii=False)
                + "\n</artifact_authoring_json>",
            )
            self.assertNotIn("PRIVATE", experiment.shared.canonical(request))
            self.assertNotIn(experiment.FAMILIES[1 - index], text)
            self.assertEqual(
                set(request),
                {
                    "modelId",
                    "system",
                    "messages",
                    "inferenceConfig",
                    "additionalModelRequestFields",
                },
            )

    def test_two_durable_calls_capture_raw_and_parsed_without_private_reasoning(self):
        def inspect(data, request):
            saved = json.loads((self.output / "capture.json").read_text())
            call = saved["calls"][-1]
            self.assertEqual(call["request"], request)
            self.assertEqual(call["status"], "dispatch_started")
            self.assertFalse(call["usage_known"])
            return response(data)

        report, client = self.run_eval(inspect)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(client.requests), 2)
        self.assertEqual(
            client.requests,
            [job["requests"]["author"] for job in report["plan"]["jobs"]],
        )
        self.assertNotIn(
            "FIRST RESPONSE ONLY", experiment.shared.canonical(client.requests)
        )
        self.assertEqual(
            report["input_utf8_bytes"], report["plan"]["planned_input_utf8_bytes"]
        )
        serialized = experiment.shared.canonical(report)
        self.assertNotIn("PRIVATE REASONING", serialized)
        self.assertNotIn("PRIVATE SIGNATURE", serialized)
        for call, result in zip(report["calls"], report["results"], strict=True):
            self.assertEqual(call["response"]["reasoningContentBlockCount"], 1)
            self.assertEqual(
                json.loads("\n".join(call["response"]["text"])),
                result["stage_outputs"]["author"],
            )
            self.assertEqual(result["candidate_assessment"], "unassessed")
            self.assertEqual(result["provider_calls"], 1)
            self.assertTrue(result["usage_known"])
            self.assertEqual(
                result["known_usage_subtotal"], {"inputTokens": 10, "outputTokens": 20}
            )
            self.assertNotIn("expectedAnswer", result)
            self.assertNotIn("observation", result)

    def test_only_envelope_is_validated_and_fences_use_runtime_parser(self):
        def fenced(data, _):
            # Deep candidate schemas are intentionally left to the later plan.
            data["candidates"] = [{"unsupported_artifact": True}, {"arbitrary": 7}]
            value = response(data)
            value["output"]["message"]["content"][-1]["text"] = (
                "```json\n" + json.dumps(data) + "\n```"
            )
            return value

        report, client = self.run_eval(fenced)
        self.assertEqual(len(client.requests), 2)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(
            report["results"][0]["stage_outputs"]["author"]["candidates"][0],
            {"unsupported_artifact": True},
        )

    def test_bad_author_envelope_stops_without_replacement_and_keeps_decoded_record(
        self,
    ):
        cases = [
            {"candidates": [{}]},
            {"candidates": [{}, {}, {}]},
            {"candidates": [{}, False]},
            {"candidates": [{}, {}], "key": 0},
        ]
        for index, data in enumerate(cases):
            with self.subTest(data=data):
                self.output = self.root / str(index)
                report, client = self.run_eval(lambda *_: response(data))
                self.assertEqual(len(client.requests), 1)
                self.assertTrue(report["stopped_early"])
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(report["results"][0]["stage_outputs"]["author"], data)
                self.assertEqual(report["results"][0]["format_failure_role"], "author")
                self.assertEqual(report["results"][1]["status"], "unattempted")

    def test_timeout_non_end_turn_and_malformed_json_keep_honest_capture(self):
        for kind in ("timeout", "refusal", "json"):
            with self.subTest(kind=kind):
                self.output = self.root / kind

                def failed(data, _):
                    if kind == "timeout":
                        raise TimeoutError("SECRET LOCAL DETAIL")
                    value = response(
                        data, "refusal" if kind == "refusal" else "end_turn"
                    )
                    if kind == "json":
                        value["output"]["message"]["content"][-1]["text"] = (
                            '{"candidates":'
                        )
                    return value

                report, client = self.run_eval(failed)
                self.assertEqual(len(client.requests), 1)
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(report["calls"][0]["usage_known"], kind != "timeout")
                self.assertEqual(report["results"][0]["usage_known"], kind != "timeout")
                self.assertEqual(
                    report["results"][0]["candidate_assessment"], "unassessed"
                )
                self.assertNotIn(
                    "SECRET LOCAL DETAIL", experiment.shared.canonical(report)
                )
                self.assertEqual(report["results"][1]["status"], "unattempted")

    def test_tampered_plan_and_existing_capture_fail_before_client_creation(self):
        plan, approved = self.freeze()
        changes = [
            lambda p: p.update(maximum_calls=3),
            lambda p: p["settings"].update(BEDROCK_READ_TIMEOUT_SECONDS="300"),
            lambda p: p["source_sha256"].update(
                {experiment.ADAPTER_SOURCES[0]: "changed"}
            ),
            lambda p: p["dependencies"].update(python="changed"),
            lambda p: p["jobs"].reverse(),
            lambda p: p["jobs"][0]["requests"]["author"].update(modelId="other-model"),
            lambda p: p["jobs"][0]["requests"]["author"]["messages"][0]["content"][
                0
            ].update(text="changed"),
        ]
        with patch.object(experiment.shared, "new_client") as client:
            with self.assertRaises(ValueError):
                experiment.run_experiment(self.plan_path, "wrong", self.output)
            for change in changes:
                altered = copy.deepcopy(plan)
                change(altered)
                experiment.shared.write_json(self.plan_path, altered)
                with self.assertRaises(ValueError):
                    experiment.run_experiment(
                        self.plan_path,
                        experiment.shared.digest(experiment.shared.canonical(altered)),
                        self.output,
                    )
            experiment.shared.write_json(self.plan_path, plan)
            self.output.mkdir()
            with self.assertRaises(FileExistsError):
                experiment.run_experiment(self.plan_path, approved, self.output)
            client.assert_not_called()

    def test_subclass_enforces_two_total_one_per_family_and_changed_request_bounds(
        self,
    ):
        plan, _ = self.freeze()
        report = {"plan": plan, "calls": [], "input_utf8_bytes": 0}
        client = Client()
        recorder = experiment.AuthorRecordingClient(client, report, lambda: None)
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.dispatch(1, "author")
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.dispatch(False, "author")
        recorder.dispatch(0, "author")
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.dispatch(0, "author")
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.dispatch(1, "reviewer")
        report["input_utf8_bytes"] = 64000
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.dispatch(1, "author")
        report["input_utf8_bytes"] = report["calls"][0]["input_utf8_bytes"]
        request = plan["jobs"][1]["requests"]["author"]
        request["toolConfig"] = {"tools": []}
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.dispatch(1, "author")
        request.pop("toolConfig")
        recorder.dispatch(1, "author")
        with self.assertRaises(experiment.shared.TrialFailure):
            recorder.dispatch(1, "author")
        self.assertEqual(len(client.requests), 2)

    def test_durable_write_failure_prevents_dispatch(self):
        _, approved = self.freeze()
        client = Client()
        real_write = experiment.shared.write_json

        def write(path, value):
            if value.get("calls"):
                raise OSError("No durable storage")
            real_write(path, value)

        with (
            patch.object(experiment.shared, "write_json", side_effect=write),
            self.assertRaises(OSError),
        ):
            experiment.run_experiment(self.plan_path, approved, self.output, client)
        self.assertEqual(client.requests, [])

    def test_fixture_bounds_order_and_dry_preparation_need_no_client(self):
        original = copy.deepcopy(self.packet)
        for change in (
            lambda p: p["cases"].reverse(),
            lambda p: p["cases"].pop(),
            lambda p: p["cases"][0]["user_data"].update(source="界" * 12000),
            lambda p: p["cases"][1].update(case_id=p["cases"][0]["case_id"]),
        ):
            changed = copy.deepcopy(original)
            change(changed)
            with self.assertRaises(ValueError):
                experiment.make_plan(changed)
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
        self.assertEqual(result["maximum_calls"], 2)
        self.assertFalse(result["execute"])
        experiment.load_frozen_plan(self.output / "plan.json", result["plan_sha256"])


class ArtifactSourceBindingTests(unittest.TestCase):
    def test_hashes_include_exact_adapter_and_observer_bytes_and_missing_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            names = (
                "evals/checkpoint_artifact_authoring_eval.py",
                *experiment.ADAPTER_SOURCES,
            )
            for name in names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((name + "\n").encode())
            with (
                patch.object(experiment, "SERVICE_DIR", root),
                patch.object(
                    experiment.shared,
                    "source_hashes",
                    return_value={"shared.py": "preserved"},
                ),
            ):
                hashes = experiment.source_hashes()
                self.assertEqual(hashes["shared.py"], "preserved")
                for name in names:
                    self.assertEqual(
                        hashes[name],
                        hashlib.sha256((root / name).read_bytes()).hexdigest(),
                    )
                (root / experiment.ADAPTER_SOURCES[-1]).unlink()
                with self.assertRaises(FileNotFoundError):
                    experiment.source_hashes()
