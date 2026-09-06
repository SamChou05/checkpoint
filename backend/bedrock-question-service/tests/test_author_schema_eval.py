import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_author_schema_eval as experiment
from lambda_test_support import FakeBedrockClient


def response(text, stop="end_turn"):
    return {
        "stopReason": stop,
        "output": {
            "message": {
                "content": [
                    {"text": text},
                    {
                        "reasoningContent": {
                            "reasoningText": {"text": "private-thinking"}
                        }
                    },
                ]
            }
        },
    }


def question():
    return {
        "prompt": "In Python 3, what does len('abc') return?",
        "choices": ["3", "2", "4", "0"],
        "expectedAnswer": "3",
        "explanation": "There are three characters.",
        "topic": "string handling",
        "difficulty": 3,
        "format": "Multiple Choice",
    }


class AuthorSchemaEvalTests(unittest.TestCase):
    def reference_plan(self):
        with patch.dict("os.environ", experiment.SETTINGS):
            request = experiment.make_plan(9062026)[0]["request"]
            user = experiment._user_prompt(request)
        return {
            "git_revision": "earlier-frozen-revision",
            "system": "Earlier exact system prompt.",
            "user": user,
            "model": experiment.MODEL,
            "read_timeout_seconds": 300,
            "settings": copy.deepcopy(experiment.SETTINGS),
        }

    def test_four_calls_vary_only_output_config_and_keep_raw_blind_items(self):
        payload = {"questions": [question()]}
        client = FakeBedrockClient(response(json.dumps(payload)))
        with tempfile.TemporaryDirectory() as temp, patch("builtins.print"):
            directory = Path(temp) / "run"
            results = experiment.run_experiment(directory, client)
            self.assertEqual(len(client.calls), 4)
            self.assertEqual([r["repetition"] for r in results], [1, 1, 2, 2])
            base = copy.deepcopy(client.calls[0])
            base.pop("outputConfig", None)
            for result, call in zip(results, client.calls):
                plain = copy.deepcopy(call)
                config = plain.pop("outputConfig", None)
                self.assertEqual(plain, base)
                self.assertEqual(config is not None, result["arm"] == "structured")
                self.assertEqual(result["questions"], [question()])
                self.assertTrue(result["strict_json"])
                self.assertTrue(result["runtime_parse"])
                self.assertTrue(result["schema_match"])
            self.assertEqual(base["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(
                base["additionalModelRequestFields"]["thinking"], {"type": "adaptive"}
            )
            blinded = json.loads((directory / "blinded.json").read_text())
            self.assertEqual(len(blinded), 4)
            self.assertEqual(
                set(blinded[0]), {"id", "goal", "sourceDocuments", "prompt", "choices"}
            )
            for path in directory.glob("*.json"):
                self.assertNotIn("private-thinking", path.read_text())

    def test_fences_and_invalid_expression_have_distinct_runtime_outcomes(self):
        payload = json.dumps({"questions": [question()]})
        invalid = '{"questions":[{"choices":"one|two".split("|")}]} '
        client = FakeBedrockClient(
            [
                response(invalid),
                response(f"```json\n{payload}\n```"),
                response(payload),
                response(payload),
            ]
        )
        with tempfile.TemporaryDirectory() as temp, patch("builtins.print"):
            results = experiment.run_experiment(Path(temp) / "run", client)
        self.assertEqual(len(client.calls), 4)  # No repair calls hidden in the arms.
        self.assertFalse(results[0]["runtime_parse"])
        self.assertEqual(results[0]["questions"], [])
        self.assertFalse(results[1]["strict_json"])
        self.assertTrue(results[1]["runtime_parse"])
        self.assertTrue(results[1]["schema_match"])

    def test_provider_failure_stops_without_leaking_exception_text(self):
        client = FakeBedrockClient(TimeoutError("private-transport-detail"))
        with tempfile.TemporaryDirectory() as temp, patch("builtins.print"):
            directory = Path(temp) / "run"
            results = experiment.run_experiment(directory, client)
            self.assertEqual(len(client.calls), 1)
            self.assertTrue(results[0]["stopped_early"])
            self.assertTrue(results[0]["provider_failed"])
            for path in directory.glob("*.json"):
                self.assertNotIn("private-transport-detail", path.read_text())

    def test_refusal_or_truncation_cannot_be_scored_as_a_usable_answer(self):
        for stop in ("refusal", "max_tokens"):
            with self.subTest(stop=stop):
                client = FakeBedrockClient(
                    response(json.dumps({"questions": [question()]}), stop)
                )
                with tempfile.TemporaryDirectory() as temp, patch("builtins.print"):
                    results = experiment.run_experiment(Path(temp) / "run", client)
                self.assertEqual(len(client.calls), 1)
                self.assertTrue(results[0]["stopped_early"])
                self.assertFalse(results[0]["runtime_parse"])
                self.assertEqual(results[0]["questions"], [])

    def test_schema_compliance_is_separate_from_question_correctness(self):
        payload = {"questions": [question()]}
        payload["questions"][0]["choices"] = ["wrong"]
        self.assertTrue(experiment.matches_schema(payload))
        payload["questions"][0]["difficulty"] = True
        self.assertFalse(experiment.matches_schema(payload))
        payload["questions"][0]["difficulty"] = 3
        payload["questions"][0]["unexpected"] = "extra"
        self.assertFalse(experiment.matches_schema(payload))

    def test_each_capture_refuses_a_second_real_call(self):
        client = FakeBedrockClient(response('{"questions":[]}'))
        with tempfile.TemporaryDirectory() as temp:
            capture = experiment.AuthorCapture(client, Path(temp) / "call.json", True)
            request = {"messages": [{"content": [{"text": "synthetic"}]}]}
            capture.converse(**request)
            with self.assertRaises(RuntimeError):
                capture.converse(**request)
            self.assertNotIn("outputConfig", request)
            self.assertEqual(len(client.calls), 1)

    def test_two_selected_ordinary_calls_preserve_exact_reference_request_and_both_prompts(
        self,
    ):
        client = FakeBedrockClient(response(json.dumps({"questions": [question()]})))
        baseline = self.reference_plan()
        with tempfile.TemporaryDirectory() as temp, patch("builtins.print"):
            reference = Path(temp) / "reference.json"
            reference.write_text(json.dumps(baseline))
            directory = Path(temp) / "run"
            results = experiment.run_experiment(
                directory,
                client,
                arms=("ordinary",),
                repetitions=2,
                max_calls=2,
                reference_plan=reference,
            )
            plan = json.loads((directory / "plan.json").read_text())
            blinded = json.loads((directory / "blinded.json").read_text())
        self.assertEqual(len(client.calls), 2)
        self.assertEqual([item["arm"] for item in results], ["ordinary", "ordinary"])
        self.assertEqual([item["repetition"] for item in results], [1, 2])
        self.assertEqual(plan["maximum_calls"], 2)
        self.assertEqual(plan["planned_calls"], 2)
        self.assertEqual(plan["selected_arms"], ["ordinary"])
        self.assertIsNone(plan["schema"])
        self.assertEqual(plan["user"], baseline["user"])
        self.assertEqual(plan["baseline_comparison"]["system"], baseline["system"])
        self.assertEqual(plan["baseline_comparison"]["user"], baseline["user"])
        self.assertTrue(plan["baseline_comparison"]["user_request_identical"])
        self.assertNotEqual(plan["system"], baseline["system"])
        self.assertEqual(len(blinded), 2)
        self.assertEqual(client.calls[0], client.calls[1])
        for call in client.calls:
            self.assertNotIn("outputConfig", call)
            self.assertEqual(call["system"], [{"text": plan["system"]}])
            self.assertEqual(
                call["messages"][0]["content"], [{"text": baseline["user"]}]
            )

    def test_invalid_selection_or_insufficient_cap_fails_before_calls(self):
        selections = [
            {"arms": ()},
            {"arms": ("ordinary", "ordinary")},
            {"arms": ("unknown",)},
            {"repetitions": 0},
            {"repetitions": 3},
            {"max_calls": 2},
            {"max_calls": 5},
        ]
        for selection in selections:
            client = FakeBedrockClient(response('{"questions":[]}'))
            with (
                tempfile.TemporaryDirectory() as temp,
                self.subTest(selection=selection),
            ):
                directory = Path(temp) / "run"
                with self.assertRaises(ValueError):
                    experiment.run_experiment(directory, client, **selection)
                self.assertFalse(directory.exists())
                self.assertEqual(client.calls, [])

    def test_reference_request_or_settings_drift_fails_before_calls(self):
        baseline = self.reference_plan()
        variants = [
            {"user": baseline["user"] + " "},
            {"model": "changed"},
            {"read_timeout_seconds": 100},
            {"settings": {}},
            {"system": ""},
        ]
        for variant in variants:
            client = FakeBedrockClient(response('{"questions":[]}'))
            with tempfile.TemporaryDirectory() as temp, self.subTest(variant=variant):
                reference = Path(temp) / "reference.json"
                reference.write_text(json.dumps({**baseline, **variant}))
                directory = Path(temp) / "run"
                with self.assertRaises(ValueError):
                    experiment.run_experiment(
                        directory,
                        client,
                        arms=("ordinary",),
                        max_calls=2,
                        reference_plan=reference,
                    )
                self.assertFalse(directory.exists())
                self.assertEqual(client.calls, [])


if __name__ == "__main__":
    unittest.main()
