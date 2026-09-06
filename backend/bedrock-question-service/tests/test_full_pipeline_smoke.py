import ast
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_full_pipeline_smoke as smoke
from lambda_test_support import FakeBedrockClient


class FullPipelineSmokeTests(unittest.TestCase):
    def test_selected_goals_preserve_requested_order_and_reject_unknown_or_duplicates(
        self,
    ):
        selected = ["morrow_rules", "spanish_grammar_pronouns"]
        self.assertEqual(
            [case["case_id"] for case in smoke.load_cases(selected)], selected
        )
        with self.assertRaises(ValueError):
            smoke.load_cases(["unknown_goal"])
        with self.assertRaises(ValueError):
            smoke.load_cases(["morrow_rules", "morrow_rules"])

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

    def test_opt_in_failure_isolated_to_one_goal_without_retry_or_budget_expansion(
        self,
    ):
        cases = smoke.load_cases(
            [
                "spanish_grammar_pronouns",
                "sourdough_fermentation",
                "photography_exposure",
                "morrow_rules",
            ]
        )
        client = FakeBedrockClient([TimeoutError("private detail"), '{"questions":[]}'])
        with tempfile.TemporaryDirectory() as temp, patch("builtins.print"):
            directory = Path(temp) / "run"
            report = smoke.run_experiment(
                directory, cases, client, continue_after_goal_failure=True
            )
            self.assertFalse(report["stopped_early"])
            self.assertTrue(report["had_goal_failures"])
            self.assertEqual(report["max_total_calls"], 24)
            self.assertEqual(len(report["results"]), 4)
            self.assertEqual(
                [row["case_id"] for row in report["results"]],
                [case["case_id"] for case in cases],
            )
            self.assertEqual(report["results"][0]["actual_provider_calls"], 1)
            self.assertTrue(report["results"][0]["goal_failed"])
            self.assertTrue(all(row["jobs"] == 1 for row in report["results"]))
            self.assertTrue(
                all(
                    not row["provider_failed"] and row["actual_provider_calls"] > 0
                    for row in report["results"][1:]
                )
            )
            self.assertLessEqual(len(client.calls), 24)
            self.assertTrue(
                all(row["actual_provider_calls"] <= 6 for row in report["results"])
            )
            self.assertEqual(
                json.loads((directory / "blinded_raw_authors.json").read_text()), []
            )

    def test_dry_run_reports_selected_four_goal_cap_and_explicit_policy(self):
        output = io.StringIO()
        selected = [case["case_id"] for case in smoke.load_cases()[2:]]
        argv = ["smoke", "--output-dir", "unused", "--dry-run"]
        for case_id in selected:
            argv += ["--case-id", case_id]
        argv += ["--continue-after-goal-failure"]
        with patch("sys.argv", argv), patch("sys.stdout", output):
            self.assertEqual(smoke.main(), 0)
        report = json.loads(output.getvalue())
        self.assertEqual(report["cases"], selected)
        self.assertEqual(report["max_calls"], 24)
        self.assertTrue(report["continue_after_goal_failure"])

    def test_raw_author_export_preserves_exact_content_and_separates_keys(self):
        case = smoke.load_cases()[0]
        question = {
            "prompt": 'What is value.replace("  ", "|", 1)?\nKeep spaces.',
            "choices": ['""', '" "', '"  "', '"|"'],
            "expectedAnswer": '"|"',
            "explanation": "secret author feedback marker",
            "difficulty": 3,
        }
        author_call = {
            "request": {"system": [{"text": "author system"}]},
            "response": {
                "text": ["```json\n" + json.dumps({"questions": [question]}) + "\n```"]
            },
        }
        reviewer_call = {
            "request": {"system": [{"text": "reviewer system"}]},
            "response": {"text": [json.dumps({"questions": [question]})]},
        }
        blinded, keys, observations = smoke.raw_author_items(
            case, [author_call, reviewer_call], "author system"
        )
        self.assertEqual(len(blinded), 1)
        self.assertEqual(len(keys), 1)
        item = blinded[0]
        self.assertEqual(item["prompt"], question["prompt"])
        self.assertEqual(item["choices"], question["choices"])
        self.assertEqual(
            set(item), {"id", "goal", "sourceDocuments", "prompt", "choices"}
        )
        content = {key: value for key, value in item.items() if key != "id"}
        expected_id = hashlib.sha256(
            json.dumps(
                content, ensure_ascii=False, sort_keys=True, separators=(",", ":")
            ).encode()
        ).hexdigest()
        self.assertEqual(item["id"], expected_id)
        self.assertEqual(keys[0]["id"], item["id"])
        self.assertEqual(keys[0]["question"], question)
        self.assertNotIn("marker", json.dumps(blinded))
        self.assertEqual(observations[0]["blindable_item_count"], 1)
        self.assertEqual(
            smoke.raw_author_items(case, [reviewer_call, author_call], "author system")[
                0
            ][0]["id"],
            item["id"],
        )

    def test_raw_parse_and_shape_failures_remain_observed_without_export_repair(self):
        responses = [
            {"text": ['{"questions": [']},
            {"text": ['{"questions": null}']},
            {"text": ['{"questions":[{"prompt":"x","choices":null}]}']},
            None,
        ]
        calls = [
            {
                "request": {"system": [{"text": "author"}]},
                **({"response": response} if response is not None else {"error": {}}),
            }
            for response in responses
        ]
        blinded, keys, observations = smoke.raw_author_items(
            smoke.load_cases()[0], calls, "author"
        )
        self.assertEqual(blinded, [])
        self.assertEqual(keys, [])
        self.assertEqual(
            [row["status"] for row in observations],
            ["invalid_json", "invalid_questions_envelope", "parsed", "provider_error"],
        )
        self.assertEqual(observations[2]["raw_item_count"], 1)
        self.assertEqual(observations[2]["unblindable_item_indices"], [0])

    def test_raw_export_includes_rejected_candidates_and_deduplicates_only_blind_ids(
        self,
    ):
        question = {
            "prompt": "A malformed choice-count fixture still needs an independent audit.",
            "choices": ["first", "second", "third"],
            "expectedAnswer": "first",
            "explanation": "Author explanation marker",
            "difficulty": 3,
            "topic": "loops",
        }
        client = FakeBedrockClient.returning_questions(question)
        with tempfile.TemporaryDirectory() as temp, patch("builtins.print"):
            directory = Path(temp) / "run"
            report = smoke.run_experiment(directory, smoke.load_cases()[:1], client)
            self.assertEqual(report["results"][0]["questions"], [])
            blinded = json.loads((directory / "blinded_raw_authors.json").read_text())
            keys = json.loads((directory / "raw_author_keys.json").read_text())
            self.assertEqual(len(blinded), 1)
            self.assertEqual(blinded[0]["choices"], question["choices"])
            self.assertEqual(len(keys), len(client.calls))
            self.assertTrue(all(row["id"] == blinded[0]["id"] for row in keys))
            self.assertGreater(len(keys), 1)
            self.assertEqual(report["max_total_calls"], 6)

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
