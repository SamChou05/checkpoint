import ast
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_full_pipeline_smoke as smoke
from lambda_test_support import FakeBedrockClient


class FullPipelineSmokeTests(unittest.TestCase):
    def test_fixtures_preserve_executable_python_and_existing_morrow_rules(self):
        cases = smoke.load_cases()
        self.assertEqual(len(cases), 6)
        python_source = cases[0]["payload"]["sourceDocuments"][0]["text"]
        ast.parse(python_source)
        self.assertIn('value.replace("  ", "|", 1)', python_source)
        self.assertIn('\n        if value == "":\n            continue', python_source)
        for case in cases[1:5]:
            self.assertEqual(case["payload"]["sourceDocuments"], [])
            self.assertEqual(set(case["payload"]["goal"]), {"title", "focusAreas"})
        existing = [
            json.loads(line)
            for line in (
                smoke.SERVICE_DIR / "evals/fixtures/question_generation_cases.jsonl"
            )
            .read_text()
            .splitlines()
        ]
        morrow = next(
            case for case in existing if case["case_id"] == "fictional_game_source_goal"
        )
        self.assertEqual(
            cases[-1]["payload"]["sourceDocuments"],
            morrow["payload"]["sourceDocuments"],
        )

    def test_real_pipeline_stops_entire_experiment_after_first_provider_failure(self):
        client = FakeBedrockClient(TimeoutError("Do not retain this provider detail"))
        with tempfile.TemporaryDirectory() as temp, patch("builtins.print"):
            directory = Path(temp) / "run"
            report = smoke.run_experiment(directory, smoke.load_cases(), client)
            self.assertTrue(report["stopped_early"])
            self.assertEqual(len(report["results"]), 1)
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(report["results"][0]["actual_provider_calls"], 1)
            self.assertEqual(report["results"][0]["jobs"], 1)
            self.assertTrue(report["results"][0]["errors"])
            self.assertEqual(json.loads((directory / "blinded.json").read_text()), [])
            calls = next(directory.glob("*.calls.json")).read_text()
            self.assertIn("TimeoutError", calls)
            self.assertNotIn("Do not retain", calls)
            self.assertIn("system", json.loads(calls)[0]["request"])

    def test_capture_enforces_six_real_calls_and_does_not_persist_reasoning_content(
        self,
    ):
        client = FakeBedrockClient(
            {
                "output": {
                    "message": {
                        "content": [
                            {
                                "reasoningContent": {
                                    "reasoningText": {"text": "private-marker"}
                                }
                            },
                            {
                                "reasoningContent": {
                                    "redactedContent": b"private-marker"
                                }
                            },
                            {"text": '{"questions":[]}'},
                        ]
                    }
                },
            }
        )
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "calls.json"
            capture = smoke.CapturingClient(client, path)
            for _ in range(6):
                capture.converse(messages=[{"content": [{"text": "synthetic prompt"}]}])
            with self.assertRaises(RuntimeError):
                capture.converse(messages=[{"content": [{"text": "synthetic prompt"}]}])
            self.assertEqual(len(client.calls), 6)
            self.assertNotIn("private-marker", path.read_text())
            self.assertEqual(len(json.loads(path.read_text())), 6)

    def test_blinded_output_excludes_answers_feedback_and_difficulty(self):
        case = smoke.load_cases()[0]
        question = {
            "prompt": "A synthetic stem.",
            "choices": ["one", "two", "three", "four"],
            "expectedAnswer": "one",
            "explanation": "Answer explanation marker",
            "choiceExplanations": {"one": "Choice feedback marker"},
            "difficulty": 3,
        }
        blinded = smoke.blinded_items(case, [question])
        self.assertEqual(
            set(blinded[0]), {"id", "goal", "sourceDocuments", "prompt", "choices"}
        )
        self.assertEqual(
            blinded[0]["sourceDocuments"], case["payload"]["sourceDocuments"]
        )
        self.assertNotIn("marker", json.dumps(blinded))

    def test_more_than_six_goals_cannot_bypass_global_call_limit(self):
        with tempfile.TemporaryDirectory() as temp, self.assertRaises(ValueError):
            smoke.run_experiment(Path(temp) / "run", smoke.load_cases() * 2)


if __name__ == "__main__":
    unittest.main()
