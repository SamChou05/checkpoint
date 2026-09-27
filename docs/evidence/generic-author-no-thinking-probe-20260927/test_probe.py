"""Socket-free checks for the exact author delta and one-call ledger."""

import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import probe


class FakeClient:
    def __init__(self, callback, *, fails=False):
        self.meta = SimpleNamespace(endpoint_url=probe.ENDPOINT, region_name="us-east-1",
                                    config=SimpleNamespace(connect_timeout=3, read_timeout=200,
                                                           retries={"total_max_attempts": 1}))
        self.callback = callback
        self.fails = fails
        self.calls = 0

    def converse(self, **wire):
        self.calls += 1
        self.callback(wire)
        if self.fails:
            raise RuntimeError("fake provider failure")
        return {"stopReason": "max_tokens", "output": {"message": {"content": [
            {"text": '{"questions":{"0":'},
        ]}}, "usage": {"inputTokens": 100, "outputTokens": 6000}}


class ProbeTests(unittest.TestCase):
    def test_only_thinking_budget_and_sampling_differ_from_trial03(self):
        draft = probe.build_plan()
        prior = probe.baseline_artifacts()["author_wire"]
        wire = draft["author_wire"]
        self.assertEqual({key: value for key, value in wire.items()
                          if key not in {"inferenceConfig", "additionalModelRequestFields"}},
                         {key: value for key, value in prior.items()
                          if key not in {"inferenceConfig", "additionalModelRequestFields"}})
        self.assertEqual(wire["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})
        self.assertEqual(wire["additionalModelRequestFields"],
                         {"thinking": {"type": "disabled"}})
        self.assertEqual(draft["request_sha256"],
                         probe.baseline_artifacts()["request_sha256"])
        self.assertEqual(draft["native_author_schema_sha256"],
                         probe.baseline_artifacts()["native_author_schema_sha256"])

    def test_single_reservation_precedes_dispatch_and_no_retry(self):
        draft = probe.build_plan()
        plan = {**draft, "state": "frozen"}
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            plan_path = directory / "plan.json"
            capture_path = directory / "capture.json"
            plan_path.write_text(json.dumps(plan, indent=2) + "\n")
            plan_hash = probe.file_hash(plan_path)
            capture = probe.new_capture(plan_hash)
            probe._capture_hash = None
            probe.save(capture_path, capture, exclusive=True, capture=True)

            def at_dispatch(wire):
                saved = json.loads(capture_path.read_text())
                self.assertEqual(saved["reservation"], "durable")
                self.assertTrue(saved["call"]["dispatch_attempted"])
                self.assertEqual(saved["call"]["sdk_attempts"], 1)
                self.assertEqual(wire, plan["author_wire"])

            with patch.object(probe, "PLAN", plan_path):
                client = FakeClient(at_dispatch)
                probe.run_one_call(plan, plan_hash, capture, capture_path, client)
                self.assertEqual(client.calls, 1)
                self.assertEqual(capture["status"], "completed")
                self.assertEqual(capture["author_outcome"], "incomplete")
                self.assertIsNone(capture["author_rows"])
                self.assertFalse(capture["worker_qualified"])

            capture_path.unlink()
            probe._capture_hash = None
            probe.save(capture_path, probe.new_capture(plan_hash), exclusive=True, capture=True)
            failed_capture = json.loads(capture_path.read_text())
            with patch.object(probe, "PLAN", plan_path):
                failed_client = FakeClient(at_dispatch, fails=True)
                probe.run_one_call(plan, plan_hash, failed_capture, capture_path, failed_client)
                self.assertEqual(failed_client.calls, 1)
                self.assertEqual(failed_capture["status"], "failed_after_dispatch")
                self.assertEqual(failed_capture["call"]["error"]["type"], "RuntimeError")

    def test_worksheet_builder_requires_terminal_seven_rows(self):
        import importlib.util
        path = probe.HERE / "make_worksheet.py"
        spec = importlib.util.spec_from_file_location("author_no_thinking_worksheet", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            private = directory / "private"
            capture_path = directory / "capture.json"
            public_path = directory / "worksheet.json"
            rows = [{"prompt": f"Scenario {index}", "choices": ["a", "b", "c", "d"],
                     "expectedAnswer": "a"} for index in range(7)]
            capture_path.write_text(json.dumps({"status": "completed",
                                                "author_outcome": "seven_native_rows",
                                                "worker_qualified": False,
                                                "author_rows": rows}))
            with patch.object(module, "CAPTURE", capture_path), \
                    patch.object(module, "WORKSHEET", public_path), \
                    patch.object(module, "PRIVATE", private), \
                    patch.object(module, "SEED", private / "worksheet-seed.bin"), \
                    patch.object(module, "ANSWER_MAP", private / "answer-map.json"), \
                    patch.object(sys, "argv", ["make_worksheet.py", "--capture-sha256",
                                               module.sha(capture_path)]):
                module.main()
            public = json.loads(public_path.read_text())
            self.assertEqual([item["id"] for item in public["items"]],
                             [f"Q{index:02d}" for index in range(1, 8)])
            self.assertNotIn("source_ordinal", public_path.read_text())
            self.assertNotIn("capture_sha256", public_path.read_text())
            answers = json.loads((private / "answer-map.json").read_text())["answers"]
            self.assertEqual(len({entry["source_ordinal"] for entry in answers.values()}), 7)
            self.assertTrue(all(answers[item["id"]]["source_ordinal"] != index
                                for index, item in enumerate(public["items"])))
            self.assertEqual((private / "answer-map.json").stat().st_mode & 0o777, 0o600)
            self.assertEqual((private / "worksheet-seed.bin").stat().st_mode & 0o777, 0o600)
            self.assertEqual(os.stat(private).st_mode & 0o777, 0o700)


if __name__ == "__main__":
    unittest.main()
