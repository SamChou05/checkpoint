"""Socket-free tests for the pinned, author-only probability trial."""

import copy
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import author_probe as probe
import make_worksheet as worksheet

sys.path.insert(0, str(probe.SERVICE / "tests"))
from test_native_pipeline import ScriptedNativeClient, author_payload  # noqa: E402


class ProbabilityDirectiveAuthorProbeTests(unittest.TestCase):
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

    def fake_client(self, *, response_canary=None):
        script = ScriptedNativeClient(
            ("question_author_v4_n7", author_payload(*self.questions)),
        )

        class FakeClient:
            def __init__(self, config):
                self.meta = SimpleNamespace(
                    endpoint_url=probe.ENDPOINT, region_name="us-east-1", config=config)

            def converse(self, **wire):
                response = script.converse(**wire)
                if response_canary:
                    response["output"]["message"]["content"][0]["text"] = json.dumps(
                        {"credential_echo": response_canary})
                return response

        return script, lambda _service, **kwargs: FakeClient(kwargs["config"])

    def run_fake(self, **kwargs):
        script, factory = self.fake_client(**kwargs)
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / "capture.json"
        capture = probe.new_capture(self.plan)
        probe.save(path, capture, exclusive=True)
        probe.run_author(self.plan, capture, path, factory, lambda: None,
                         secrets=(kwargs["response_canary"],)
                         if kwargs.get("response_canary") else ())
        return script, capture, path

    def test_only_directive_changed_and_visible_verbatim_in_author_wire(self):
        plan = self.plan
        directive = probe.directive_from_analysis()
        self.assertEqual(len(directive), 681)
        self.assertEqual(plan["request"]["goal"]["questionDirective"], directive)
        self.assertEqual(plan["source_commit"], probe.SOURCE_COMMIT)
        self.assertEqual(plan["author_contract_name"], "question_author_v4_n7")
        self.assertEqual(plan["native_author_schema_bytes"], 1117)
        self.assertEqual(plan["native_author_schema_sha256"],
                         "48c4cebb7cf7478f7a049d9ca795ce366b3cb4f47488ac05f1301a10b6a34408")
        self.assertEqual(plan["author_wire_sha256"],
                         "6e928592cefbcced84b6c281b70261170737aa646eee10b91966507e6b4a55fa")
        self.assertEqual(plan["author_wire"]["messages"][0]["content"][0]["text"].count(directive), 2)
        self.assertEqual(plan["author_wire"]["inferenceConfig"], {"maxTokens": 16000})
        self.assertEqual(len(plan["allowed_contracts"]), 1)
        self.assertEqual(plan["worksheet_builder_sha256"],
                         probe.file_hash(probe.WORKSHEET_BUILDER))

    def test_offline_plan_and_fake_author_cannot_open_a_socket(self):
        with patch("socket.socket.connect", side_effect=AssertionError(
                "Offline preparation attempted a network connection.")):
            plan = probe.build_plan()
            self.assertEqual(plan["author_wire_sha256"],
                             "6e928592cefbcced84b6c281b70261170737aa646eee10b91966507e6b4a55fa")
            script, capture, _ = self.run_fake()
        self.assertEqual(len(script.calls), 1)
        self.assertEqual(capture["status"], "finished")

    def test_one_author_call_captures_all_seven_sources_without_worker_verification(self):
        script, capture, path = self.run_fake()
        self.assertEqual(len(script.calls), 1)
        self.assertEqual(capture["status"], "finished")
        self.assertEqual(capture["sanitized_source_ordinals"], list(range(7)))
        self.assertEqual([row["status"] for row in capture["original_rows"]],
                         ["sanitized"] * 7)
        self.assertEqual([row["sanitized_question"]["prompt"]
                          for row in capture["original_rows"]],
                         [question["prompt"] for question in self.questions])
        self.assertEqual(len(capture["calls"]), len(capture["reservations"]), 1)
        self.assertEqual(probe.finish(capture)["qualification"],
                         "pending_author_content_review")
        self.assertFalse(capture["summary"]["worker_qualified"])
        self.assertEqual(len(json.loads(path.read_text())["original_rows"]), 7)

    def test_production_pin_callback_does_not_reenter_author_stage(self):
        script, factory = self.fake_client()
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan_path = directory / "plan.json"
            frozen = {**self.plan, "state": "frozen"}
            probe.save(plan_path, frozen, exclusive=True)
            capture_path = directory / "capture.json"
            capture = probe.new_capture(frozen)
            probe.save(capture_path, capture, exclusive=True)
            with patch.object(probe, "PLAN", plan_path), \
                    patch.object(probe, "author_wire", side_effect=AssertionError(
                        "Live pin check re-entered the offline author stage.")):
                probe.run_author(
                    frozen, capture, capture_path, factory,
                    probe.production_pin_callback(frozen, probe.file_hash(plan_path)),
                )
            self.assertEqual(capture["status"], "finished")
            self.assertEqual(len(script.calls), 1)
            self.assertEqual(len(capture["reservations"]), 1)

    def test_keyless_worksheet_keeps_answer_map_outside_workbook(self):
        _, capture, path = self.run_fake()
        probe.finish(capture)
        probe.save(path, capture)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            worksheet_path = directory / "worksheet.json"
            private_dir = directory / "private"
            worksheet.create(path, probe.file_hash(path), worksheet_path, private_dir,
                             seed=b"A" * 32)
            public = json.loads(worksheet_path.read_text())
            private = json.loads((private_dir / "answer-map.json").read_text())
            self.assertEqual(len(public["items"]), len(private["items"]), 7)
            self.assertEqual(private["capture_sha256"], probe.file_hash(path))
            self.assertEqual(private["seed_hex"], (b"A" * 32).hex())
            self.assertEqual((private_dir / "answer-map.json").stat().st_mode & 0o777, 0o600)
            self.assertNotIn("expectedAnswer", worksheet_path.read_text())
            self.assertNotIn('"ordinal"', worksheet_path.read_text())
            self.assertNotIn('"capture_sha256"', worksheet_path.read_text())
            self.assertEqual([item["id"] for item in public["items"]],
                             [f"P{index:02d}" for index in range(1, 8)])
            self.assertTrue(all(private["items"][item["id"]]["ordinal"] != position
                                for position, item in enumerate(public["items"])))
            self.assertEqual([item["prompt"] for item in public["items"]], [
                self.questions[private["items"][item["id"]]["ordinal"]]["prompt"]
                for item in public["items"]
            ])
            another = directory / "another"
            worksheet.create(path, probe.file_hash(path), another / "worksheet.json",
                             another / "private", seed=b"A" * 32)
            self.assertEqual(worksheet_path.read_bytes(),
                             (another / "worksheet.json").read_bytes())
            self.assertEqual((private_dir / "answer-map.json").read_bytes(),
                             (another / "private/answer-map.json").read_bytes())

    def test_frozen_wire_drift_blocks_before_fake_dispatch(self):
        script, factory = self.fake_client()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "capture.json"
            capture = probe.new_capture(self.plan)
            probe.save(path, capture, exclusive=True)
            bad_plan = copy.deepcopy(self.plan)
            bad_plan["author_wire"]["modelId"] = "unreviewed-model"
            probe.run_author(bad_plan, capture, path, factory, lambda: None)
            self.assertEqual(script.calls, [])
            self.assertEqual(capture["status"], "failed")
            self.assertEqual(probe.finish(capture)["qualification"], "failed")

    def test_credential_echo_fails_closed_without_saving_secret(self):
        canary = "PRIVATE_FAKE_CREDENTIAL_ECHO_CANARY"
        _, capture, path = self.run_fake(response_canary=canary)
        self.assertEqual(capture["status"], "failed")
        self.assertNotIn(canary, path.read_text())
        self.assertEqual(probe.finish(capture)["qualification"], "failed")

    def test_expired_deadline_does_not_reserve_or_dispatch(self):
        script, factory = self.fake_client()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "capture.json"
            capture = probe.new_capture(self.plan)
            probe.save(path, capture, exclusive=True)
            deadline = probe.Deadline(lambda: 1000.0)
            deadline.started = 0.0
            with self.assertRaises(probe.IntegrityError):
                probe.run_author(self.plan, capture, path, factory, lambda: None,
                                 deadline=deadline)
            self.assertEqual(script.calls, [])
            self.assertEqual(capture["reservations"], [])

    def test_review_lock_and_immutable_capture_are_required_before_aws(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            capture_path = directory / "capture.json"
            probe.save(capture_path, probe.new_capture(self.plan), exclusive=True)
            capture_path.write_text("{}")
            with self.assertRaises(probe.IntegrityError):
                probe.check_capture(capture_path)
            frozen = {**self.plan, "state": "frozen"}
            plan_path = directory / "plan.json"
            probe.save(plan_path, frozen, exclusive=True)
            with patch.object(probe, "PLAN", plan_path), \
                    patch.object(probe, "REVIEW_LOCK", directory / "missing-review.json"):
                with self.assertRaises(probe.IntegrityError):
                    probe.launch_precheck()
            self.assertFalse((directory / "launch-precheck-attempt.json").exists())


if __name__ == "__main__":
    unittest.main()
