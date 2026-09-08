import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_immutable_review_eval as runner


def packet():
    question = {
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
        "difficulty": 1,
        "format": "Multiple Choice",
    }
    return {
        "experiment": runner.EXPERIMENT,
        "cases": [
            {
                "case_id": f"case_{i}",
                "question": copy.deepcopy(question),
                "context": {
                    "goal": {"title": "Practice integer arithmetic"},
                    "sourceDocuments": [],
                    "minimumDifficulty": 1,
                },
                "expect": {"not_provider_context": "private fixture label"},
            }
            for i in range(6)
        ],
    }


def response(question, **updates):
    review = {
        "valid": True,
        "answer": question["expectedAnswer"],
        "difficulty": 1,
        "mainExplanation": "supported",
        "choiceExplanations": {c: "supported" for c in question["choices"]},
        "issues": [],
    }
    review.update(updates)
    return {
        "output": {
            "message": {
                "role": "assistant",
                "content": [
                    {
                        "reasoningContent": {
                            "reasoningText": {"text": "PRIVATE_REASONING_NOT_CAPTURED"}
                        }
                    },
                    {"text": json.dumps({"review": review})},
                ],
            }
        },
        "stopReason": "end_turn",
        "usage": {"inputTokens": 100, "outputTokens": 30},
    }


class ScriptedClient:
    def __init__(self, responses, before=None):
        self.responses = responses
        self.requests = []
        self.before = before

    def converse(self, **request):
        if self.before:
            self.before(request, len(self.requests))
        self.requests.append(copy.deepcopy(request))
        value = self.responses[len(self.requests) - 1]
        if isinstance(value, Exception):
            raise value
        return value


class ImmutableReviewEvalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.packet = packet()
        self.plan = runner.make_plan(self.packet)
        self.path = self.root / "plan.json"
        runner.shared.write_json(self.path, self.plan)
        self.plan_hash = runner._hash(self.plan)
        self.output = self.root / "capture"

    def run_trial(self, client):
        return runner.run_experiment(
            self.path, self.plan_hash, self.output, client=client
        )

    def client(self):
        return ScriptedClient([response(c["question"]) for c in self.packet["cases"]])

    def test_six_requests_are_durable_then_replay_exact_content(self):
        client = self.client()

        def check(request, index):
            durable = json.loads((self.output / "capture.json").read_text())
            self.assertEqual(durable["calls"][index]["request"], request)
            self.assertEqual(
                durable["calls"][index]["request_canonical_sha256"],
                runner._hash(request),
            )

        client.before = check
        report = self.run_trial(client)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(client.requests), 6)
        self.assertNotIn("private fixture label", json.dumps(client.requests))
        self.assertNotIn("PRIVATE_REASONING_NOT_CAPTURED", json.dumps(report))
        for case, result in zip(self.packet["cases"], report["results"], strict=True):
            self.assertEqual(result["observation"]["question"], case["question"])
        replay = runner.replay_capture(report, self.plan_hash)
        self.assertEqual(replay["provider_calls"], 6)
        self.assertEqual(replay["results"], report["results"])

    def test_unsupported_feedback_rejects_case_without_stopping_next(self):
        client = self.client()
        client.responses[0] = response(
            self.packet["cases"][0]["question"], mainExplanation="unsupported"
        )
        report = self.run_trial(client)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(
            report["results"][0]["observation"]["reason"], "unsupported_feedback"
        )
        self.assertEqual(len(client.requests), 6)

    def test_malformed_review_is_not_semantic_rejection_and_stops(self):
        client = self.client()
        client.responses[0]["output"]["message"]["content"] = [
            {"text": '{"review":{"valid":true}}'}
        ]
        report = self.run_trial(client)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(len(client.requests), 1)
        self.assertEqual(report["results"], [])
        self.assertEqual(
            runner.replay_capture(report, self.plan_hash)["provider_calls"], 1
        )

    def test_provider_failure_stops_and_preserves_completed_prefix(self):
        client = self.client()
        client.responses[1] = TimeoutError()
        report = self.run_trial(client)
        self.assertEqual(len(client.requests), 2)
        self.assertEqual(len(report["results"]), 1)
        self.assertFalse(report["calls"][1]["usage_known"])
        self.assertEqual(
            runner.replay_capture(report, self.plan_hash)["provider_calls"], 2
        )

    def test_token_limit_preserves_usage_but_stops_without_acceptance(self):
        client = self.client()
        client.responses[0]["stopReason"] = "max_tokens"
        report = self.run_trial(client)
        self.assertEqual(len(client.requests), 1)
        self.assertTrue(report["calls"][0]["usage_known"])
        self.assertEqual(report["results"], [])

    def test_malformed_message_preserves_returned_usage(self):
        client = self.client()
        client.responses[0]["output"]["message"]["content"] = "malformed"
        report = self.run_trial(client)
        self.assertEqual(len(client.requests), 1)
        self.assertTrue(report["calls"][0]["usage_known"])
        self.assertFalse(report["calls"][0]["response"]["content_valid"])
        self.assertEqual(report["calls"][0]["response"]["usage"]["outputTokens"], 30)
        self.assertEqual(
            runner.replay_capture(report, self.plan_hash)["provider_calls"], 1
        )

    def test_replay_rejects_altered_usage_and_reasoning_count(self):
        report = self.run_trial(self.client())
        for field, value in (("usage_known", 1), ("usage_known", False)):
            altered = copy.deepcopy(report)
            altered["calls"][0][field] = value
            with self.assertRaises(ValueError):
                runner.replay_capture(altered, self.plan_hash)
        altered = copy.deepcopy(report)
        altered["calls"][0]["response"]["reasoningContentBlockCount"] = True
        with self.assertRaises(ValueError):
            runner.replay_capture(altered, self.plan_hash)

    def test_recovered_post_call_persistence_failure_retains_completed_prefix(self):
        client = self.client()
        original = runner.shared.write_json
        count = 0

        def write(path, value):
            nonlocal count
            count += 1
            if count == 4:
                raise OSError("synthetic final-per-call persistence failure")
            return original(path, value)

        with patch.object(runner.shared, "write_json", side_effect=write):
            report = self.run_trial(client)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["error_phase"], "call_persist")
        self.assertEqual(len(client.requests), 1)
        self.assertEqual(len(report["results"]), 1)
        self.assertEqual(
            runner.replay_capture(report, self.plan_hash)["provider_calls"], 1
        )

    def test_wrong_plan_or_changed_input_prevents_provider_dispatch(self):
        client = self.client()
        with self.assertRaises(ValueError):
            runner.run_experiment(self.path, "0" * 64, self.output, client=client)
        changed = copy.deepcopy(self.plan)
        changed["jobs"][0]["request"]["inferenceConfig"]["maxTokens"] += 1
        runner.shared.write_json(self.path, changed)
        with self.assertRaises(ValueError):
            runner.run_experiment(
                self.path, runner._hash(changed), self.output, client=client
            )
        self.assertEqual(client.requests, [])

    def test_persistence_failure_prevents_dispatch_and_counts_zero_calls(self):
        client = self.client()
        original = runner.shared.write_json
        count = 0

        def write(path, value):
            nonlocal count
            count += 1
            if count == 2:
                raise OSError("synthetic persistence failure")
            return original(path, value)

        with patch.object(runner.shared, "write_json", side_effect=write):
            report = self.run_trial(client)
        self.assertEqual(client.requests, [])
        self.assertIs(report["calls"][0]["provider_dispatch_attempted"], False)
        self.assertEqual(
            runner.replay_capture(report, self.plan_hash)["provider_calls"], 0
        )

    def test_replay_rejects_changed_joins_content_status_and_case_order(self):
        report = self.run_trial(self.client())
        mutations = []
        value = copy.deepcopy(report)
        value["results"][0]["observation"]["question"]["explanation"] += " altered"
        mutations.append(value)
        value = copy.deepcopy(report)
        value["calls"][0]["case_index"] = False
        mutations.append(value)
        value = copy.deepcopy(report)
        value["calls"] = list(reversed(value["calls"]))
        mutations.append(value)
        value = copy.deepcopy(report)
        value["status"] = "running"
        mutations.append(value)
        for value in mutations:
            with self.subTest(value=value["status"]), self.assertRaises(ValueError):
                runner.replay_capture(value, self.plan_hash)

    def test_existing_capture_cannot_be_overwritten_or_resumed(self):
        report = self.run_trial(self.client())
        client = self.client()
        with self.assertRaises(FileExistsError):
            self.run_trial(client)
        self.assertEqual(client.requests, [])
        self.assertEqual(json.loads((self.output / "capture.json").read_text()), report)

    def test_subset_is_a_new_exact_plan_with_no_unlisted_dispatch(self):
        self.packet["cases"] = self.packet["cases"][1:]
        self.plan = runner.make_plan(self.packet)
        self.plan_hash = runner._hash(self.plan)
        runner.shared.write_json(self.path, self.plan)
        client = self.client()
        report = self.run_trial(client)
        self.assertEqual(self.plan["maximum_calls"], 5)
        self.assertEqual(len(client.requests), 5)
        self.assertEqual(
            runner.replay_capture(report, self.plan_hash)["provider_calls"], 5
        )
        self.assertEqual(report["calls"][0]["case_id"], "case_1")
        for size in (0, 7):
            invalid = packet()
            invalid["cases"] = [copy.deepcopy(invalid["cases"][0]) for _ in range(size)]
            for i, case in enumerate(invalid["cases"]):
                case["case_id"] = str(i)
            with self.assertRaises(ValueError):
                runner.make_plan(invalid)


if __name__ == "__main__":
    unittest.main()
