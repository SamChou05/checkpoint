import copy
import json
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest import mock

from evals import checkpoint_learning_eval as learning_eval
from lambda_test_support import _raw_question
from service_errors import ProviderCallBudgetExceededError


class LearningEvalTests(unittest.TestCase):
    def test_title_only_goal_infers_skills_and_preserves_remaining_allocation(self):
        case = {
            "case_id": "new_subject",
            "payload": {"goal": {"title": "Learn Morrow"}},
        }
        original = copy.deepcopy(case)
        skill_map = {
            "version": 1,
            "skills": [
                {
                    "id": str(uuid.uuid4()),
                    "name": name,
                    "objectives": [{"id": str(uuid.uuid4()), "name": "Apply " + name}],
                }
                for name in ["Movement", "Resources", "Scoring"]
            ],
        }
        skills = skill_map["skills"]

        def infer(request, client, *, call_budget, request_metrics=None):
            self.assertEqual(request["goal"]["title"], "Learn Morrow")
            self.assertEqual(request["suggestedSkills"], [])
            call_budget.consume()
            return skill_map

        def item(skill, index):
            return {
                **_raw_question(
                    "A distinct scenario for learning Morrow " + str(index),
                    topic=skill["name"],
                ),
                "skillID": skill["id"],
                "objectiveID": skill["objectives"][0]["id"],
                "verificationVersion": 1,
            }

        batches = [
            [item(skills[0], 0), item(skills[0], 1), item(skills[1], 2)],
            [item(skills[1], 3), item(skills[2], 4)],
        ]
        requests = []

        def generate(request, client, *, call_budget, request_metrics=None):
            requests.append(request)
            call_budget.consume()
            call_budget.consume()
            return batches[len(requests) - 1]

        with (
            mock.patch.object(learning_eval, "_infer_skill_map", side_effect=infer),
            mock.patch.object(
                learning_eval, "_generate_sanitized_questions", side_effect=generate
            ),
        ):
            result = learning_eval.generate_sample(case, infer_skills=True)

        self.assertTrue(result["passed"])
        self.assertEqual(result["provider_calls"], 5)
        self.assertEqual(
            [p["targetDifficulty"] for p in result["adaptive_skill_plans"]], [2, 4, 2]
        )
        self.assertEqual(requests[1]["targetCount"], 2)
        self.assertEqual(
            requests[1]["requestedSkillAllocation"],
            {skills[1]["id"]: 1, skills[2]["id"]: 1},
        )
        self.assertEqual(
            requests[1]["existingPrompts"], [q["prompt"] for q in batches[0]]
        )
        self.assertEqual(case, original)

    def test_empty_bounded_jobs_retain_prior_inventory_in_report(self):
        question = _raw_question("A concrete scenario without a supplied skill map")
        with mock.patch.object(
            learning_eval,
            "_generate_sanitized_questions",
            side_effect=[[question], ProviderCallBudgetExceededError("exhausted"), []],
        ):
            result = learning_eval.generate_sample(
                {
                    "case_id": "new",
                    "payload": {"goal": {"title": "Learn something new"}},
                }
            )
        self.assertFalse(result["passed"])
        self.assertEqual(result["jobs"], 3)
        self.assertEqual(result["questions"], [question])
        self.assertIsNone(result["skill_map"])

    def test_cli_accepts_unlisted_goals_from_a_custom_fixture_file(self):
        with tempfile.TemporaryDirectory() as directory:
            fixtures = Path(directory) / "goals.jsonl"
            fixtures.write_text(
                json.dumps(
                    {
                        "case_id": "never_seen_before",
                        "payload": {"goal": {"title": "Learn a new game"}},
                    }
                )
                + "\n"
            )
            argv = [
                "eval",
                "--output",
                str(Path(directory) / "report.json"),
                "--generation",
                "--infer-skills",
                "--generation-fixtures",
                str(fixtures),
                "--case-id",
                "never_seen_before",
            ]
            with (
                mock.patch("sys.argv", argv),
                mock.patch.object(
                    learning_eval,
                    "generate_sample",
                    return_value={"case_id": "never_seen_before", "passed": True},
                ) as generate,
                mock.patch.object(learning_eval, "evaluate_review") as review,
                mock.patch("builtins.print"),
            ):
                self.assertEqual(learning_eval.main(), 0)
            self.assertEqual(
                generate.call_args.args[0]["payload"]["goal"]["title"],
                "Learn a new game",
            )
            self.assertTrue(generate.call_args.kwargs["infer_skills"])
            review.assert_not_called()

    def test_cli_generation_defaults_to_every_fixture_not_three_subjects(self):
        with tempfile.TemporaryDirectory() as directory:
            argv = [
                "eval",
                "--output",
                str(Path(directory) / "report.json"),
                "--generation",
            ]

            def passed(case, **kwargs):
                return {"case_id": case["case_id"], "passed": True}

            with (
                mock.patch("sys.argv", argv),
                mock.patch.object(
                    learning_eval, "generate_sample", side_effect=passed
                ) as generate,
                mock.patch.object(learning_eval, "evaluate_review", side_effect=passed),
                mock.patch("builtins.print"),
            ):
                self.assertEqual(learning_eval.main(), 0)
            fixtures = (
                (
                    learning_eval.SERVICE_DIR
                    / "evals/fixtures/question_generation_cases.jsonl"
                )
                .read_text()
                .splitlines()
            )
            self.assertEqual(generate.call_count, len(fixtures))
            titles = {
                call.args[0]["payload"]["goal"]["title"]
                for call in generate.call_args_list
            }
            self.assertIn("Learn photography", titles)
            self.assertIn("Learn the Morrow tabletop game", titles)
