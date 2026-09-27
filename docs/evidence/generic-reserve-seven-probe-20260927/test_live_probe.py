"""Socket-free replay of the source-pinned generic full-worker harness."""

import copy
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import live_probe as probe

sys.path.insert(0, str(probe.SERVICE / "tests"))
from test_native_pipeline import (  # noqa: E402
    ScriptedNativeClient, author_payload, authored_issue_flags,
    solver_map, solver_record, task_data,
)


class LiveGenericReserveProbeTests(unittest.TestCase):
    def setUp(self):
        self.plan = probe.build_plan()
        self.questions = []
        for index in range(7):
            marked = index + 1
            total = index + 8
            answer = f"{marked}/{total}"
            choices = [answer, f"{marked + 1}/{total}",
                       f"{marked}/{total + 1}", f"{total}/{marked}"]
            choices = choices[index % 4:] + choices[:index % 4]
            self.questions.append({
                "prompt": f"A fair spinner has {total} equal sectors, {marked} of them blue. What is the chance of blue?",
                "choices": choices, "expectedAnswer": answer,
                "explanation": f"There are {marked} blue sectors out of {total} equally likely sectors, so the ratio is {answer}.",
                "topic": "Probability", "difficulty": 3, "format": "Multiple Choice",
            })

    def scripted(self, *, reviewer_rejected=(), solver_rejected=(),
                 usage_canary=None, response_canary=None):
        originals = {question["prompt"]: question for question in self.questions}
        reviewer_rejected = set(reviewer_rejected)
        solver_rejected = set(solver_rejected)

        def solve(request):
            items = task_data(request, "question_solution_json")["items"]
            records = []
            for item in items:
                self.assertNotIn("expectedAnswer", item)
                record = solver_record(item, originals[item["prompt"]]["expectedAnswer"])
                if item["index"] in solver_rejected:
                    for choice in record["choices"].values():
                        choice["judgment"] = "refuted"
                records.append(record)
            return solver_map(*records)

        def review(request):
            items = task_data(request, "question_review_json")["items"]
            rows = {}
            for item in items:
                original = originals[item["prompt"]]
                self.assertNotIn("expectedAnswer", item)
                rows[str(item["index"])] = {
                    "valid": item["index"] not in reviewer_rejected,
                    "answer": original["expectedAnswer"], "difficulty": 3,
                    "explanationSupport": "supported",
                    "issueFlags": authored_issue_flags(),
                }
            return {"reviews": rows}

        survivor_count = 7 - len(solver_rejected)
        script = ScriptedNativeClient(
            ("question_author_v4_n7", author_payload(*self.questions)),
            ("complete_choice_solver_v5_n7", solve),
            (f"authored_solution_reviewer_v3_n{survivor_count}", review),
        )

        class FakeClient:
            def __init__(self, config):
                self.meta = SimpleNamespace(
                    endpoint_url=probe.ENDPOINT, region_name="us-east-1", config=config)

            def converse(self, **wire):
                response = script.converse(**wire)
                if usage_canary:
                    response["usage"]["untrustedCanary"] = usage_canary
                if response_canary:
                    response["output"]["message"]["content"][0]["text"] = json.dumps({
                        "credential_echo": response_canary})
                return response

        return script, lambda _service, **kwargs: FakeClient(kwargs["config"])

    def replay(self, **kwargs):
        script, factory = self.scripted(**kwargs)
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / "capture.json"
        capture = probe.new_capture(self.plan)
        probe.save(path, capture, exclusive=True)
        row = probe.run_job(self.plan, capture, path, factory, lambda: None,
                            secrets=(kwargs["response_canary"],)
                            if kwargs.get("response_canary") else ())
        return script, row, capture, path

    def test_offline_plan_pins_native_seven_author_wire(self):
        plan = self.plan
        self.assertEqual(plan["source_commit"], probe.SOURCE_COMMIT)
        self.assertEqual(plan["author_contract_name"], "question_author_v4_n7")
        self.assertEqual(plan["native_author_schema_bytes"], 1117)
        self.assertEqual(plan["native_author_schema_sha256"],
                         "48c4cebb7cf7478f7a049d9ca795ce366b3cb4f47488ac05f1301a10b6a34408")
        self.assertEqual(plan["author_wire_sha256"],
                         "d8bd91195c1e31b0a5f298926a3ee2c072d7322ac851a1e9e284f1647f920891")
        self.assertEqual(plan["author_wire"]["inferenceConfig"], {"maxTokens": 16000})

    def test_seven_original_rows_return_earliest_five_verified(self):
        script, row, capture, path = self.replay()
        self.assertEqual(len(script.calls), 3)
        self.assertEqual(row["status"], "finished")
        self.assertEqual(row["returned_source_ordinals"], [0, 1, 2, 3, 4])
        self.assertEqual(row["accepted_source_ordinals"], list(range(7)))
        self.assertEqual([item["status"] for item in capture["original_rows"]],
                         ["returned"] * 5 + ["unfilled_verified"] * 2)
        self.assertEqual([item["status"] for item in capture["call_slots"][:3]],
                         ["completed"] * 3)
        self.assertEqual(len(capture["reservations"]), 3)
        self.assertEqual(json.loads(path.read_text())["jobs"][0]["provider_calls"], 3)

    def test_two_rejections_use_later_source_rows_without_relabeling(self):
        _, row, capture, _ = self.replay(reviewer_rejected={1, 4})
        self.assertEqual(row["returned_source_ordinals"], [0, 2, 3, 5, 6])
        self.assertEqual(row["accepted_source_ordinals"], [0, 2, 3, 5, 6])
        self.assertEqual(capture["original_rows"][1]["status"], "unfilled_sanitized")

    def test_underfilled_job_stays_failed_without_second_author_call(self):
        script, row, capture, _ = self.replay(reviewer_rejected={0, 2, 4})
        self.assertEqual(len(script.calls), 3)
        self.assertEqual(row["returned"], [])
        self.assertEqual(row["returned_source_ordinals"], [])
        self.assertEqual(len(row["accepted_source_ordinals"]), 4)
        self.assertTrue(all(item["status"] != "returned" for item in capture["original_rows"]))

    def test_capture_bounds_untrusted_usage_and_refuses_visible_credential_echo(self):
        _, row, _, path = self.replay(usage_canary="UNTRUSTED_USAGE_CANARY")
        self.assertEqual(row["status"], "finished")
        self.assertNotIn("UNTRUSTED_USAGE_CANARY", path.read_text())
        secret = "FAKE_CREDENTIAL_ECHO_CANARY"
        _, row, _, path = self.replay(response_canary=secret)
        self.assertEqual(row["status"], "failed")
        self.assertNotIn(secret, path.read_text())

    def test_capture_tamper_and_missing_review_lock_block_before_aws(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            capture_path = directory / "capture.json"
            probe.save(capture_path, probe.new_capture(self.plan), exclusive=True)
            capture_path.write_text("{}")
            with self.assertRaises(probe.IntegrityError):
                probe.check_capture(capture_path)
            plan_path = directory / "plan.json"
            probe.save(plan_path, {**self.plan, "state": "frozen"}, exclusive=True)
            with patch.object(probe, "PLAN", plan_path), \
                    patch.object(probe, "REVIEW_LOCK", directory / "missing-review.json"):
                with self.assertRaises(probe.IntegrityError):
                    probe.launch_precheck()
            self.assertFalse((directory / "launch-precheck-attempt.json").exists())

    def test_five_returned_cannot_hide_late_global_failure(self):
        _, row, capture, _ = self.replay()
        self.assertEqual(row["status"], "finished")
        self.assertEqual(probe.finish(capture)["qualification"], "pending_content_review")
        capture["global_stop"] = "late_failure"
        self.assertEqual(probe.finish(capture)["qualification"], "failed")
        capture["global_stop"] = None
        capture["status"] = "deadline_exceeded"
        self.assertEqual(probe.finish(capture)["qualification"], "failed")

    def test_five_returned_cannot_hide_low_or_malformed_difficulty_and_choices(self):
        _, _, capture, _ = self.replay()
        self.assertEqual(probe.finish(capture)["qualification"], "pending_content_review")
        for change in (
            {"difficulty": 1},
            {"difficulty": "3"},
            {"choices": ["1", "1", "2", "3"]},
            {"expectedAnswer": "not offered"},
        ):
            with self.subTest(change=change):
                damaged = copy.deepcopy(capture)
                damaged["jobs"][0]["returned"][2].update(change)
                self.assertEqual(probe.finish(damaged)["qualification"], "failed")

    def test_expired_deadline_refuses_before_provider_or_capture_mutation(self):
        script, factory = self.scripted()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "capture.json"
            capture = probe.new_capture(self.plan)
            probe.save(path, capture, exclusive=True)
            deadline = probe.Deadline(lambda: 1_000.0)
            deadline.started = 0.0
            with self.assertRaises(probe.IntegrityError):
                probe.run_job(self.plan, capture, path, factory, lambda: None,
                              deadline=deadline)
            self.assertEqual(script.calls, [])
            self.assertEqual(capture["jobs"], [])

    def test_endpoint_drift_refuses_before_scripted_provider_call(self):
        script, factory = self.scripted()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "capture.json"
            capture = probe.new_capture(self.plan)
            probe.save(path, capture, exclusive=True)

            def wrong_endpoint(*args, **kwargs):
                client = factory(*args, **kwargs)
                client.meta.endpoint_url = "https://unreviewed.invalid"
                return client

            row = probe.run_job(self.plan, capture, path, wrong_endpoint,
                                lambda: None)
            self.assertEqual(row["status"], "failed")
            self.assertEqual(script.calls, [])
            self.assertEqual(capture["global_stop"], "request_or_provenance_integrity")


if __name__ == "__main__":
    unittest.main()
