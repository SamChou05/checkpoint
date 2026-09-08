import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_complete_authoring_eval as runner


def question():
    return {
        "prompt": "For integers x = 2 and y = 3, what is x + y?",
        "choices": ["5", "6", "1", "-1"],
        "expectedAnswer": "5",
        "explanation": "Adding the two given integers gives five.",
        "choiceExplanations": {
            "5": "Two plus three equals five.",
            "6": "Six is their product, not their sum.",
            "1": "One is the difference y minus x.",
            "-1": "Negative one is the difference x minus y.",
        },
        "topic": "Integer arithmetic",
        "difficulty": 5,
        "format": "Multiple Choice",
    }


def packet():
    return {
        "experiment": runner.EXPERIMENT,
        "cases": [
            {
                "case_id": f"case_{i}",
                "context": {
                    "goal": {
                        "title": "Practice reasoning",
                        "not_context": "HIDDEN_GOAL",
                    },
                    "sourceDocuments": [],
                    "minimumDifficulty": 3,
                    "independentSolutions": "HIDDEN_SOLVER",
                },
                "externalAssessment": "HIDDEN_EXPECTATIONS",
                "provenance": "HIDDEN_PROVENANCE",
            }
            for i in range(4)
        ],
    }


def response(value):
    return {
        "output": {
            "message": {
                "role": "assistant",
                "content": [
                    {
                        "reasoningContent": {
                            "reasoningText": {"text": "PRIVATE_REASONING"}
                        }
                    },
                    {"text": json.dumps(value)},
                ],
            }
        },
        "usage": {"inputTokens": 100, "outputTokens": 70},
        "stopReason": "end_turn",
    }


def solution(**updates):
    return response(
        {
            "solutions": [
                {
                    "index": 0,
                    "outcome": "resolved",
                    "answer": "5",
                    "limitations": "",
                    "assumptionsRequired": [],
                    **updates,
                }
            ]
        }
    )


def audit(**updates):
    return response(
        {
            "review": {
                "valid": True,
                "answer": "5",
                "difficulty": 3,
                "mainExplanation": "supported",
                "choiceExplanations": {c: "supported" for c in question()["choices"]},
                "issues": [],
                **updates,
            }
        }
    )


def triplet():
    # Synthetic controls exercise orchestration, not factual difficulty scoring.
    return [response({"question": question()}), solution(), audit()]


class ScriptedClient:
    def __init__(self, responses, before=None):
        self.responses, self.requests, self.before = responses, [], before

    def converse(self, **request):
        if self.before:
            self.before(request, len(self.requests))
        self.requests.append(copy.deepcopy(request))
        reply = self.responses[len(self.requests) - 1]
        if isinstance(reply, Exception):
            raise reply
        return copy.deepcopy(reply)


class CompleteAuthoringEvalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plan = runner.make_plan(packet())
        self.plan_path = self.root / "plan.json"
        runner.shared.write_json(self.plan_path, self.plan)
        self.plan_hash = runner._hash(self.plan)
        self.output = self.root / "capture"

    def run_trial(self, replies, before=None):
        client = ScriptedClient(replies, before)
        report = runner.run_experiment(
            self.plan_path, self.plan_hash, self.output, client
        )
        replay = runner.replay_capture(report, self.plan_hash)
        self.assertEqual(replay["provider_calls"], len(client.requests))
        self.assertEqual(json.loads((self.output / "capture.json").read_text()), report)
        return report, client

    def test_fresh_sequence_keeps_author_text_and_binds_every_stage(self):
        def durable(request, index):
            capture = json.loads((self.output / "capture.json").read_text())
            self.assertEqual(capture["calls"][index]["request"], request)
            self.assertFalse(capture["calls"][index]["provider_dispatch_attempted"])

        report, client = self.run_trial(triplet() * 4, durable)
        self.assertEqual(len(client.requests), 12)
        self.assertEqual(report["status"], "completed")
        for result in report["results"]:
            self.assertEqual(result["status"], "eligible")
            self.assertEqual(result["question"], question())
            self.assertEqual(
                result["observation"]["question"], {**question(), "difficulty": 3}
            )
        self.assertNotIn("PRIVATE_REASONING", json.dumps(report))
        self.assertNotIn("verificationVersion", json.dumps(report["results"]))

    def test_no_answer_or_assessment_leak_and_no_solver_anchoring_of_auditor(self):
        report, client = self.run_trial(triplet() * 4)
        for request in client.requests:
            text = json.dumps(request)
            for secret in (
                "HIDDEN_GOAL",
                "HIDDEN_SOLVER",
                "HIDDEN_EXPECTATIONS",
                "HIDDEN_PROVENANCE",
            ):
                self.assertNotIn(secret, text)
        solver_text = client.requests[1]["messages"][0]["content"][0]["text"]
        for key in ("choices", "expectedAnswer", "explanation", "difficulty"):
            self.assertNotIn('"' + key + '"', solver_text)
        auditor_text = client.requests[2]["messages"][0]["content"][0]["text"]
        self.assertNotIn('"solution"', auditor_text)
        self.assertNotIn('"outcome"', auditor_text)
        self.assertNotIn('"expectedAnswer"', auditor_text)
        self.assertIn('"choiceExplanations"', auditor_text)
        self.assertIn("solution_canonical_sha256", report["calls"][2]["bindings"])

    def test_existing_solver_veto_skips_auditor_without_losing_other_goals(self):
        replies = [
            triplet()[0],
            solution(limitations="The required conditions are not given."),
        ] + triplet() * 3
        report, client = self.run_trial(replies)
        self.assertEqual(len(client.requests), 11)
        self.assertEqual(report["results"][0]["status"], "solver_rejected")
        self.assertEqual(
            report["results"][0]["rejection"], "solver_unresolved_limitations"
        )
        self.assertEqual(report["calls"][2]["case_index"], 1)
        self.assertEqual(sum(r["status"] == "eligible" for r in report["results"]), 3)

    def test_issue_veto_overrides_approval_and_floor_is_enforced(self):
        replies = triplet()[:2] + [audit(issues=["The promised result is impossible."])]
        replies += triplet()[:2] + [audit(difficulty=2)] + triplet() * 2
        report, _ = self.run_trial(replies)
        self.assertEqual(report["results"][0]["rejection"], "reported_issues")
        self.assertEqual(report["results"][1]["rejection"], "difficulty_floor")
        self.assertEqual(sum(r["status"] == "eligible" for r in report["results"]), 2)

    def test_oversized_author_content_is_never_clipped_or_retried(self):
        oversized = {**question(), "explanation": "x" * 421}
        report, client = self.run_trial(
            [response({"question": oversized})] + triplet() * 3
        )
        self.assertEqual(len(client.requests), 10)
        self.assertEqual(report["results"][0]["status"], "contract_rejected")
        self.assertNotIn("question", report["results"][0])
        self.assertIn("x" * 421, report["calls"][0]["response"]["text"])

    def test_provider_failure_stops_every_later_dispatch_with_known_prefix(self):
        report, client = self.run_trial(triplet()[:2] + [RuntimeError("synthetic")])
        self.assertEqual(len(client.requests), 3)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["results"][0]["status"], "operational_failure")
        self.assertTrue(
            all(r["status"] == "unattempted" for r in report["results"][1:])
        )
        self.assertFalse(report["calls"][-1]["usage_known"])
        with self.assertRaises(FileExistsError):
            runner.run_experiment(self.plan_path, self.plan_hash, self.output, client)

    def test_malformed_content_preserves_usage_and_rejects_its_case(self):
        malformed = response({"unexpected": True})
        report, client = self.run_trial([malformed] + triplet() * 3)
        self.assertEqual(len(client.requests), 10)
        self.assertEqual(report["results"][0]["status"], "contract_rejected")
        self.assertTrue(report["calls"][0]["usage_known"])

    def test_replay_rejects_changed_request_content_result_or_call_order(self):
        report, _ = self.run_trial(triplet() * 4)
        for change in ("request", "question", "result", "order", "usage", "unfinished"):
            changed = copy.deepcopy(report)
            if change == "request":
                changed["calls"][1]["request"]["messages"][0]["content"][0]["text"] += (
                    "extra"
                )
                changed["calls"][1]["request_canonical_sha256"] = runner._hash(
                    changed["calls"][1]["request"]
                )
            elif change == "question":
                changed["calls"][2]["bindings"]["question_canonical_sha256"] = "0" * 64
            elif change == "result":
                changed["results"][0]["observation"]["question"]["explanation"] += (
                    "extra"
                )
            elif change == "order":
                changed["calls"][1], changed["calls"][2] = (
                    changed["calls"][2],
                    changed["calls"][1],
                )
            elif change == "usage":
                changed["calls"][0]["usage_known"] = False
            else:
                changed["calls"].pop()
            with self.subTest(change=change), self.assertRaises(ValueError):
                runner.replay_capture(changed, self.plan_hash)

    def test_wrong_plan_and_changed_source_block_before_dispatch(self):
        client = ScriptedClient([])
        with self.assertRaises(ValueError):
            runner.run_experiment(self.plan_path, "wrong", self.output, client)
        with patch.object(runner.shared, "source_revision", return_value="different"):
            with self.assertRaises(ValueError):
                runner.run_experiment(
                    self.plan_path, self.plan_hash, self.output, client
                )
        self.assertFalse(self.output.exists())
        self.assertEqual(client.requests, [])

    def test_client_setup_failure_has_zero_dispatch_and_replays(self):
        with patch.object(
            runner.shared, "new_client", side_effect=RuntimeError("setup")
        ):
            report = runner.run_experiment(self.plan_path, self.plan_hash, self.output)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(
            runner.replay_capture(report, self.plan_hash)["provider_calls"], 0
        )

    def test_derived_request_budget_failure_preserves_prefix_and_skips_dispatch(self):
        original = runner._request

        def over_budget(plan, index, role, result):
            request, bindings = original(plan, index, role, result)
            if index == 0 and role == "solver":
                request["messages"][0]["content"][0]["text"] += (
                    "x" * runner.MAX_INPUT_BYTES
                )
            return request, bindings

        with patch.object(runner, "_request", side_effect=over_budget):
            report, client = self.run_trial([triplet()[0]] + triplet() * 3)
            self.assertEqual(len(client.requests), 10)
            self.assertEqual(report["results"][0]["status"], "budget_rejected")
            self.assertEqual(report["results"][0]["question"], question())
            self.assertNotIn("solution", report["results"][0])
            self.assertEqual(report["calls"][1]["case_index"], 1)

    def test_malformed_auditor_is_a_contract_failure_not_a_semantic_veto(self):
        report, _ = self.run_trial(
            triplet()[:2] + [response({"review": {}})] + triplet() * 3
        )
        self.assertEqual(report["results"][0]["status"], "contract_rejected")
        self.assertEqual(report["results"][0]["rejection"], "invalid_review")


if __name__ == "__main__":
    unittest.main()
