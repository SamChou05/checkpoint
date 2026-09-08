"""Scripted transport tests only; no workers, provider calls or source fetches."""

import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_acquired_source_trial as trial
from test_acquired_source_review import capture, question


def packet(count=3):
    return {
        "experiment": trial.EXPERIMENT,
        "cases": [
            {
                "case_id": f"case-{i}",
                "context": {
                    "goal": {
                        "title": f"Learn topic {i}",
                        "currentLevel": "Intermediate",
                        "expectedAnswer": "PRIVATE_EXPECTATION",
                    },
                    "minimumDifficulty": 3,
                    "sourceDocuments": [{"text": "PRIVATE_OLD_SUMMARY"}],
                },
                "records": [capture()],
                "selections": [{"record_index": 0, "start": 8, "end": 37}],
                "external_assessment": "PRIVATE_EXPECTATION",
            }
            for i in range(count)
        ],
    }


def content(request):
    user = request["messages"][0]["content"][0]["text"]
    return json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])


def authored():
    return {k: v for k, v in question().items() if k != "verificationPolicyRevision"}


def review_for(request, **changes):
    data = content(request)
    q = data["question"]
    span = data["acquiredSources"]["spans"][0]
    citations = [{"source_id": span["source_id"], "quote": span["text"]}]
    return {
        "review": {
            "valid": True,
            "answer": authored()["expectedAnswer"],
            "difficulty": 3,
            "mainExplanation": "supported",
            "choiceExplanations": {c: "supported" for c in q["choices"]},
            "issues": [],
            **changes,
        },
        "evidence": {
            "item": copy.deepcopy(citations),
            "mainExplanation": copy.deepcopy(citations),
            "choiceExplanations": {c: copy.deepcopy(citations) for c in q["choices"]},
        },
    }


def completed(raw, stop="end_turn", **changes):
    return {
        "status": "completed",
        "error_type": None,
        "provider_dispatch_attempted": True,
        "usage_known": True,
        "response": {
            "text": raw,
            "content_valid": True,
            "usage": {"inputTokens": 10, "outputTokens": 20},
            "stopReason": stop,
            "reasoningContentBlockCount": 1,
        },
        "local_worker_reaped": True,
        "worker_exitcode": 0,
        "local_process_group_cleanup_confirmed": True,
        "termination_attempted": False,
        "sdk_elapsed_seconds": 0.1,
        "process_elapsed_seconds": 0.2,
        "remote_completion": "response_observed",
        **changes,
    }


class AcquiredSourceTrialTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.directory = Path(temp.name)
        self.plan_path = self.directory / "plan.json"
        self.output = self.directory / "capture"
        self.plan = trial.make_plan(packet())
        trial.shared.write_json(self.plan_path, self.plan)

    def run_trial(self, observer):
        return trial.run_trial(
            self.plan_path, trial._hash(self.plan), self.output, observer=observer
        )

    def good_observer(self, request, *, on_progress, timeout, **_):
        self.assertEqual(timeout, 300)
        before = json.loads((self.output / "capture.json").read_text())
        call = before["calls"][-1]
        self.assertEqual(call["request"], request)
        self.assertEqual(call["request_sha256"], trial._hash(request))
        self.assertIsNone(call["observation"])
        data = content(request)
        raw = (
            {"question": authored()} if "question" not in data else review_for(request)
        )
        state = completed(json.dumps(raw, ensure_ascii=False))
        on_progress(copy.deepcopy(state))
        return state

    def test_plan_whitelists_metadata_and_freezes_same_packet_and_inherited_settings(
        self,
    ):
        self.assertEqual(self.plan["maximum_calls"], 6)
        self.assertEqual(self.plan["settings"], trial.caller.SETTINGS)
        self.assertEqual(self.plan["settings"]["BEDROCK_READ_TIMEOUT_SECONDS"], "300")
        self.assertEqual(self.plan["settings"]["BEDROCK_CONNECT_TIMEOUT_SECONDS"], "3")
        self.assertEqual(self.plan["sdk_total_max_attempts"], 1)
        self.assertIn(
            "evals/checkpoint_author_latency_probe.py", self.plan["source_sha256"]
        )
        self.assertIn("evals/acquired_source_review.py", self.plan["source_sha256"])
        for case, job in zip(
            self.plan["fixture"]["cases"], self.plan["jobs"], strict=True
        ):
            self.assertNotIn("PRIVATE", json.dumps(job["author_request"]))
            data = content(job["author_request"])
            self.assertEqual(data["minimumDifficulty"], 3)
            self.assertEqual(data["sourceDocuments"], [])
            self.assertEqual(
                data["acquiredSources"],
                trial.audit.prepare_sources(case["records"], case["selections"]),
            )
        self.assertEqual(
            trial.load_frozen_plan(self.plan_path, trial._hash(self.plan)), self.plan
        )

    def test_six_calls_durable_dynamic_binding_unchanged_content_and_replay(self):
        observer = Mock(side_effect=self.good_observer)
        report = self.run_trial(observer)
        self.assertEqual(observer.call_count, 6)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(
            [c["role"] for c in report["calls"]], ["author", "auditor"] * 3
        )
        for author, audit_call in zip(
            report["calls"][::2], report["calls"][1::2], strict=True
        ):
            self.assertEqual(
                content(author["request"])["acquiredSources"],
                content(audit_call["request"])["acquiredSources"],
            )
            self.assertNotIn(
                "expectedAnswer", content(audit_call["request"])["question"]
            )
            self.assertNotIn("independentSolutions", content(audit_call["request"]))
        for result in report["results"]:
            self.assertEqual(result["question"], authored())
            self.assertEqual(result["audit"]["question"], authored())
            self.assertTrue(result["audit"]["eligible"])
            self.assertEqual(result["semantic_assessment"], "unassessed")
        self.assertEqual(trial.replay_capture(report)["results"], report["results"])
        self.assertEqual(json.loads((self.output / "capture.json").read_text()), report)
        with self.assertRaises(FileExistsError):
            self.run_trial(Mock())
        self.assertEqual(observer.call_count, 6)

    def test_author_contract_failure_skips_its_review_and_continues(self):
        count = 0

        def observer(request, **kwargs):
            nonlocal count
            count += 1
            if count == 1:
                return completed('{"question":{"prompt":"Incomplete"}}')
            return self.good_observer(request, **kwargs)

        report = self.run_trial(observer)
        self.assertEqual(count, 5)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["results"][0]["status"], "author_contract_rejected")
        self.assertEqual(
            [c["role"] for c in report["calls"] if c["case_id"] == "case-0"], ["author"]
        )
        self.assertEqual(trial.replay_capture(report)["results"], report["results"])

    def test_wrong_citation_and_difficulty_rejection_preserve_original_item(self):
        def observer(request, **kwargs):
            data = content(request)
            if "question" not in data:
                return self.good_observer(request, **kwargs)
            review = review_for(
                request, difficulty=2 if data["goal"]["title"].endswith("1") else 3
            )
            if data["goal"]["title"].endswith("0"):
                review["evidence"]["item"][0]["source_id"] = "invented"
            return completed(json.dumps(review))

        report = self.run_trial(observer)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["results"][0]["status"], "audit_contract_rejected")
        self.assertEqual(report["results"][0]["audit"]["reason"], "invalid_evidence")
        self.assertEqual(report["results"][1]["audit"]["reason"], "difficulty_floor")
        self.assertTrue(report["results"][2]["audit"]["eligible"])
        self.assertTrue(all(r["question"] == authored() for r in report["results"]))
        trial.replay_capture(report)

    def test_timeout_unknowns_stop_later_goals_and_do_not_credit_rejection(self):
        observer = Mock(
            return_value={
                "status": "operational_failure",
                "error_type": "ReadTimeoutError",
                "provider_dispatch_attempted": True,
                "usage_known": False,
                "local_worker_reaped": True,
                "local_process_group_cleanup_confirmed": True,
                "termination_attempted": False,
                "worker_exitcode": 0,
                "remote_completion": "unknown",
            }
        )
        report = self.run_trial(observer)
        self.assertEqual(observer.call_count, 1)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(
            [r["status"] for r in report["results"]],
            ["operational_failure", "unattempted", "unattempted"],
        )
        self.assertFalse(report["calls"][0]["observation"]["usage_known"])
        self.assertNotIn("response", report["calls"][0]["observation"])
        trial.replay_capture(report)

    def test_nonterminal_or_failed_cleanup_stops_globally(self):
        for name, state in (
            ("nonterminal", completed("{}", stop="max_tokens")),
            (
                "cleanup",
                completed(
                    '{"question":{}}', local_process_group_cleanup_confirmed=False
                ),
            ),
        ):
            with self.subTest(name=name):
                self.output = self.directory / name
                observer = Mock(return_value=state)
                report = self.run_trial(observer)
                self.assertEqual(observer.call_count, 1)
                self.assertEqual(report["status"], "operational_failure")
                trial.replay_capture(report)

    def test_plan_and_response_joins_reject_tampering_without_a_worker(self):
        observer = Mock()
        for changes in (
            {"maximum_calls": 7},
            {"settings": {}},
            {"dependencies": {}},
            {"source_sha256": {}},
        ):
            altered = {**self.plan, **changes}
            trial.shared.write_json(self.plan_path, altered)
            with self.assertRaises(ValueError):
                trial.run_trial(
                    self.plan_path, trial._hash(altered), self.output, observer=observer
                )
        observer.assert_not_called()
        self.assertFalse(self.output.exists())
        trial.shared.write_json(self.plan_path, self.plan)
        report = self.run_trial(self.good_observer)
        for field, value in (
            ("request_sha256", "changed"),
            ("case_id", "wrong"),
            ("role", "author"),
            ("source_packet_sha256", "bad"),
        ):
            altered = copy.deepcopy(report)
            altered["calls"][1][field] = value
            with self.assertRaises(ValueError):
                trial.replay_capture(altered)
        altered = copy.deepcopy(report)
        altered["results"][0]["question"]["explanation"] = "Rewritten"
        with self.assertRaises(ValueError):
            trial.replay_capture(altered)
        altered = copy.deepcopy(report)
        altered["calls"].append(copy.deepcopy(altered["calls"][-1]))
        with self.assertRaises(ValueError):
            trial.replay_capture(altered)

    def test_later_head_does_not_change_frozen_revision_but_unknown_commit_fails(self):
        with patch.object(trial.shared, "source_revision", return_value="f" * 40):
            self.assertEqual(
                trial.load_frozen_plan(self.plan_path, trial._hash(self.plan)),
                self.plan,
            )
        altered = {**self.plan, "source_revision": "f" * 40}
        trial.shared.write_json(self.plan_path, altered)
        with self.assertRaises(ValueError):
            trial.load_frozen_plan(self.plan_path, trial._hash(altered))

    def test_replay_does_not_promote_recorded_parent_failure_or_unfinished_capture(
        self,
    ):
        report = self.run_trial(self.good_observer)
        interrupted = {
            **report,
            "status": "operational_failure",
            "error_type": "OSError",
        }
        replay = trial.replay_capture(interrupted)
        self.assertEqual(replay["status"], "operational_failure")
        self.assertEqual(replay["derived_status"], "completed")
        self.assertEqual(replay["parent_error_type"], "OSError")
        replay = trial.replay_capture({**report, "status": "running"})
        self.assertEqual(replay["status"], "running")
        self.assertEqual(replay["derived_status"], "completed")

    def test_progress_persistence_failure_stops_even_if_injected_observer_swallows_it(
        self,
    ):
        original = trial.shared.write_json
        writes = 0

        def failing(path, value):
            nonlocal writes
            writes += 1
            if writes == 4:
                raise OSError("disk unavailable")
            return original(path, value)

        def observer(request, *, on_progress, **_):
            state = completed(json.dumps({"question": authored()}))
            try:
                on_progress(state)
            except OSError:
                pass
            return state

        observer = Mock(side_effect=observer)
        with patch.object(trial.shared, "write_json", side_effect=failing):
            report = self.run_trial(observer)
        self.assertEqual(observer.call_count, 1)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(trial.replay_capture(report)["status"], "operational_failure")

    def test_capture_write_failure_prevents_launch_even_if_observer_would_succeed(self):
        original = trial.shared.write_json
        writes = 0

        def failing(path, value):
            nonlocal writes
            writes += 1
            if writes == 3:  # the launch intent, before observer admission
                raise OSError("disk unavailable")
            return original(path, value)

        observer = Mock()
        with patch.object(trial.shared, "write_json", side_effect=failing):
            report = self.run_trial(observer)
        observer.assert_not_called()
        self.assertEqual(report["status"], "operational_failure")
        self.assertIsNone(report["calls"][0]["observation"])
        trial.replay_capture(report)

    def test_dry_cli_creates_plan_without_observer_or_credentials(self):
        fixture = self.directory / "fixture.json"
        trial.shared.write_json(fixture, packet())
        with (
            patch.object(
                trial.caller,
                "observe_request",
                side_effect=AssertionError("No observer"),
            ),
            patch.object(
                trial.shared, "new_client", side_effect=AssertionError("No client")
            ),
        ):
            self.assertEqual(
                trial.main(["--fixture", str(fixture), "--output", str(self.output)]), 0
            )
        self.assertEqual(json.loads((self.output / "plan.json").read_text()), self.plan)


if __name__ == "__main__":
    unittest.main()
