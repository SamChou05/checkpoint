import copy
import json
import multiprocessing
import os
from pathlib import Path
import signal
import socket
import sys
import tempfile
import time
from types import ModuleType
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_author_latency_probe as probe


def provider_reply(text="not JSON", stop="end_turn"):
    return {
        "output": {"message": {"role": "assistant", "content": [
            {"reasoningContent": {"reasoningText": {"text": "PRIVATE_REASONING"}}},
            {"text": text},
        ]}},
        "usage": {"inputTokens": 23, "outputTokens": 41,
                  "credential": "NOT_USAGE"},
        "stopReason": stop,
        "ResponseMetadata": {"HTTPHeaders": {"secret": "PRIVATE_HEADER"}},
    }


def captured_response(text="not JSON", stop="end_turn"):
    return {
        "text": text, "content_valid": True,
        "usage": {"inputTokens": 23, "outputTokens": 41},
        "stopReason": stop, "reasoningContentBlockCount": 1,
    }


def completed(text="not JSON", stop="end_turn", elapsed=101.25):
    return {
        "status": "completed", "error_type": None,
        "provider_dispatch_attempted": True, "usage_known": True,
        "response": captured_response(text, stop),
        "sdk_elapsed_seconds": elapsed, "process_elapsed_seconds": elapsed + 0.1,
        "local_worker_reaped": True, "worker_exitcode": 0,
        "local_process_group_cleanup_confirmed": True,
        "termination_attempted": False, "remote_completion": "response_observed",
    }


def ready(connection, request):
    os.setsid()
    probe._send(connection, {"kind": "ready", "request_sha256": probe._hash(request),
                            "process_group_id": os.getpid()})
    if connection.recv(1) != b"G":
        raise RuntimeError("Missing parent admission")


def fake_complete(connection, request, _settings, _credentials, _deadline):
    ready(connection, request)
    binding = probe._hash(request)
    probe._send(connection, {"kind": "dispatch", "request_sha256": binding})
    probe._send(connection, {"kind": "response", "request_sha256": binding,
                            "response": captured_response(), "sdk_elapsed_seconds": 0.01})
    probe._send(connection, {"kind": "complete", "request_sha256": binding})
    connection.close()


def fake_partial_frame(connection, _request, _settings, _credentials, _deadline):
    connection.sendall(b'{"kind":')
    time.sleep(5)


def fake_response_then_stall(connection, request, _settings, _credentials, _deadline):
    ready(connection, request)
    binding = probe._hash(request)
    probe._send(connection, {"kind": "dispatch", "request_sha256": binding})
    probe._send(connection, {"kind": "response", "request_sha256": binding,
                            "response": captured_response(), "sdk_elapsed_seconds": 0.01})
    time.sleep(5)


def fake_wrong_binding(connection, _request, _settings, _credentials, _deadline):
    probe._send(connection, {"kind": "dispatch", "request_sha256": "wrong"})
    time.sleep(5)


def fake_overflow(connection, _request, _settings, _credentials, _deadline):
    connection.sendall(b"x" * (probe.MAX_CAPTURE_BYTES + 1))
    time.sleep(5)


def fake_orphan(connection, request, _settings, _credentials, _deadline):
    ready(connection, request)
    if os.fork() == 0:
        # This inert child deliberately survives its leader; if cleanup fails,
        # it writes a marker. No network, SDK, or model-authored code executes.
        time.sleep(0.6)
        Path(request["test_marker"]).write_text("survived")
        os._exit(0)
    connection.close()
    os.kill(os.getpid(), signal.SIGALRM)


class AuthorLatencyProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plan = probe.make_plan()
        self.path = self.root / "plan.json"
        probe.shared.write_json(self.path, self.plan)
        self.approved = probe._hash(self.plan)
        self.output = self.root / "capture"

    def test_frozen_selection_preserves_exact_original_bodies_and_only_window_changes(self):
        parent_path = probe.SERVICE_DIR.parents[1] / "docs/evidence/complete-authoring-plan-20260908.json"
        parent = json.loads(parent_path.read_text())
        self.assertEqual([j["parent_case_index"] for j in self.plan["jobs"]], [0, 2])
        self.assertEqual([j["request"] for j in self.plan["jobs"]],
                         [parent["jobs"][i]["author_request"] for i in (0, 2)])
        changed = {k for k in parent["settings"] if parent["settings"][k] != self.plan["settings"][k]}
        self.assertEqual(changed, {"BEDROCK_READ_TIMEOUT_SECONDS"})
        self.assertEqual(self.plan["maximum_calls"], 2)
        self.assertEqual(self.plan["sdk_total_max_attempts"], 1)
        for job in self.plan["jobs"]:
            for hidden in ("external_assessment", "provenance", "case_id"):
                self.assertNotIn(hidden, json.dumps(job["request"]))
        self.assertEqual(probe.load_frozen_plan(self.path, self.approved), self.plan)

    def test_source_origin_and_plan_tamper_fail_before_worker_or_output(self):
        transport = Mock()
        for field, value in (("source_revision", "changed"), ("maximum_calls", 3),
                             ("source_sha256", {"changed": "0" * 64})):
            with self.subTest(field=field):
                altered = {**self.plan, field: value}
                probe.shared.write_json(self.path, altered)
                with self.assertRaises(ValueError):
                    probe.run_probe(self.path, probe._hash(altered), self.output, transport=transport)
        probe.shared.write_json(self.path, self.plan)
        with patch.object(probe.shared, "dependencies", return_value={"changed": True}):
            with self.assertRaises(ValueError):
                probe.run_probe(self.path, self.approved, self.output, transport=transport)
        with patch.dict(probe.ORIGINS, {"capture": "0" * 64}):
            with self.assertRaises(ValueError):
                probe.make_plan()
        with patch.dict(probe.SETTINGS, {"BEDROCK_REASONING_EFFORT": "medium"}):
            with self.assertRaises(ValueError):
                probe.make_plan()
        transport.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_new_capture_durable_before_launch_and_invalid_content_remains_observation(self):
        requests = []

        def transport(request, *, on_progress, **_kwargs):
            existing = json.loads((self.output / "capture.json").read_text())
            entry = existing["calls"][-1]
            self.assertEqual(entry["request"], request)
            self.assertEqual(entry["request_canonical_sha256"], probe._hash(request))
            self.assertEqual(entry["status"], "launch_intent")
            self.assertIsNone(entry["provider_dispatch_attempted"])
            requests.append(copy.deepcopy(request))
            state = completed(stop="end_turn" if len(requests) == 1 else "max_tokens")
            on_progress(state)
            return state

        report = probe.run_probe(self.path, self.approved, self.output, transport=transport)
        self.assertEqual(len(requests), 2)
        self.assertEqual(report["status"], "completed")
        self.assertEqual([r["status"] for r in report["results"]],
                         ["author_contract_rejected", "incomplete_content"])
        self.assertTrue(all(r["semantic_assessment"] == "unassessed" for r in report["results"]))
        self.assertEqual(report["calls"][0]["completion_window"], "after_100_within_300_seconds")
        self.assertEqual(json.loads((self.output / "capture.json").read_text()), report)
        with self.assertRaises(FileExistsError):
            probe.run_probe(self.path, self.approved, self.output, transport=Mock())

    def test_unknown_timeout_usage_stops_second_job_without_bad_content_credit(self):
        transport = Mock(return_value={
            "status": "operational_failure", "error_type": "ProcessDeadline",
            "provider_dispatch_attempted": True, "usage_known": False,
            "local_worker_reaped": True, "termination_attempted": True,
            "worker_exitcode": -15, "process_elapsed_seconds": 300.02,
            "remote_completion": "unknown",
        })
        report = probe.run_probe(self.path, self.approved, self.output, transport=transport)
        transport.assert_called_once()
        self.assertEqual(report["status"], "operational_failure")
        self.assertNotIn("response", report["calls"][0])
        self.assertEqual(report["results"][0]["semantic_assessment"], "unknown")
        self.assertEqual(report["results"][1]["status"], "unattempted")

    def test_persistence_failure_cannot_start_worker_or_second_job(self):
        actual = probe.shared.write_json
        transport = Mock(return_value=completed())
        writes = 0

        def fail_launch(path, value):
            nonlocal writes
            writes += 1
            if writes == 2:
                raise OSError("synthetic sink failure")
            actual(path, value)

        with patch.object(probe.shared, "write_json", side_effect=fail_launch):
            report = probe.run_probe(self.path, self.approved, self.output, transport=transport)
        self.assertEqual(report["status"], "operational_failure")
        transport.assert_not_called()

    def test_worker_projects_final_text_only_and_preserves_sdk_error_type(self):
        for failed in (False, True):
            with self.subTest(failed=failed):
                receiver, sender = socket.socketpair()
                client = Mock()
                client.converse.side_effect = RuntimeError("SECRET_EXCEPTION") if failed else None
                client.converse.return_value = provider_reply()
                with patch.object(probe.shared, "new_client", return_value=client) as factory:
                    probe._sdk_exchange(sender, self.plan["jobs"][0]["request"], probe.SETTINGS, False)
                sender.close()
                raw = bytearray()
                while chunk := receiver.recv(65536):
                    raw.extend(chunk)
                receiver.close()
                messages = [json.loads(line) for line in raw.splitlines()]
                factory.assert_called_once_with(probe.SETTINGS, False)
                client.converse.assert_called_once_with(**self.plan["jobs"][0]["request"])
                for secret in ("PRIVATE_REASONING", "PRIVATE_HEADER", "SECRET_EXCEPTION", "NOT_USAGE"):
                    self.assertNotIn(secret.encode(), raw)
                if failed:
                    self.assertEqual(messages[-1]["error_type"], "RuntimeError")
                    self.assertTrue(messages[-1]["dispatched"])
                else:
                    self.assertEqual(messages[1]["response"], captured_response())
                    self.assertEqual(messages[-1]["kind"], "complete")

    def test_sdk_factory_sets_300_second_read_window_and_one_attempt_without_aws(self):
        boto = ModuleType("boto3")
        boto.client = Mock()
        config = ModuleType("botocore.config")
        config.Config = Mock(side_effect=lambda **kwargs: kwargs)
        with patch.dict(sys.modules, {"boto3": boto, "botocore.config": config}):
            probe.shared.new_client(probe.SETTINGS, False)
        boto.client.assert_called_once_with("bedrock-runtime", region_name="us-east-1", config={
            "connect_timeout": 3, "read_timeout": 300,
            "retries": {"mode": "standard", "total_max_attempts": 1},
        })

    def test_actual_worker_deadline_handles_partial_frames_and_retains_observed_response(self):
        for worker in (fake_partial_frame, fake_response_then_stall):
            with self.subTest(worker=worker.__name__):
                result = probe.observe_request(self.plan["jobs"][0]["request"], worker=worker,
                    context=multiprocessing.get_context("fork"), timeout=0.1)
                self.assertEqual(result["status"], "operational_failure")
                self.assertEqual(result["error_type"], "ProcessDeadline")
                self.assertTrue(result["local_worker_reaped"])
                self.assertTrue(result["termination_attempted"])
                self.assertLess(result["process_elapsed_seconds"], 1.5)
                self.assertEqual(result["usage_known"], worker is fake_response_then_stall)
                if worker is fake_partial_frame:
                    self.assertIsNone(result["provider_dispatch_attempted"])
                else:
                    self.assertEqual(result["response"]["text"], "not JSON")

    def test_success_and_malformed_or_oversized_worker_capture(self):
        for worker in (fake_complete, fake_wrong_binding, fake_overflow):
            with self.subTest(worker=worker.__name__):
                result = probe.observe_request(self.plan["jobs"][0]["request"], worker=worker,
                    context=multiprocessing.get_context("fork"), timeout=1)
                self.assertTrue(result["local_worker_reaped"])
                self.assertEqual(result["status"], "completed" if worker is fake_complete else "operational_failure")
                if worker is fake_complete:
                    self.assertFalse(result["termination_attempted"])
                    self.assertEqual(result["worker_exitcode"], 0)
                else:
                    self.assertFalse(result["usage_known"])

    def test_known_group_is_cleaned_even_after_leader_alarm_exit(self):
        marker = self.root / "orphan-survived"
        result = probe.observe_request({"test_marker": str(marker)}, worker=fake_orphan,
            context=multiprocessing.get_context("fork"), timeout=0.3)
        self.assertEqual(result["status"], "operational_failure")
        self.assertEqual(result["worker_exitcode"], -signal.SIGALRM)
        self.assertTrue(result["local_worker_reaped"])
        self.assertTrue(result["termination_attempted"])
        self.assertTrue(result["local_process_group_cleanup_confirmed"])
        self.assertLess(result["process_elapsed_seconds"], 1.5)
        time.sleep(0.65)
        self.assertFalse(marker.exists())

    def test_ready_capture_failure_never_permits_dispatch(self):
        progress = []

        def fail_ready(state):
            progress.append(state)
            raise OSError("synthetic failed durable readiness record")

        result = probe.observe_request(self.plan["jobs"][0]["request"], worker=fake_complete,
            context=multiprocessing.get_context("fork"), timeout=1, on_progress=fail_ready)
        self.assertEqual(len(progress), 1)
        self.assertEqual(progress[0]["status"], "running")
        self.assertIn("local_process_group_id", progress[0])
        self.assertEqual(result["status"], "operational_failure")
        self.assertEqual(result["error_type"], "OSError")
        self.assertNotIn("response", result)
        self.assertTrue(result["local_process_group_cleanup_confirmed"])

    def test_group_disappearance_race_is_normal_but_permission_failure_is_not_cleanup(self):
        process = Mock(pid=987654, exitcode=0)
        process.is_alive.return_value = False
        with patch.object(probe.os, "killpg", side_effect=ProcessLookupError):
            result = probe._cleanup_worker(process, process.pid, completed=True, deadline=time.monotonic())
        self.assertTrue(result["local_process_group_cleanup_confirmed"])
        self.assertFalse(result["termination_attempted"])
        with patch.object(probe.os, "killpg", side_effect=PermissionError):
            result = probe._cleanup_worker(process, process.pid, completed=True, deadline=time.monotonic())
        self.assertFalse(result["local_process_group_cleanup_confirmed"])

    def test_dry_cli_never_creates_a_client(self):
        with patch.object(probe.shared, "new_client", side_effect=AssertionError("no client")):
            self.assertEqual(probe.main(["--output", str(self.root / "dry")]), 0)
        with self.assertRaises(SystemExit):
            probe.main(["--execute", "--output", str(self.root / "missing")])


if __name__ == "__main__":
    unittest.main()
