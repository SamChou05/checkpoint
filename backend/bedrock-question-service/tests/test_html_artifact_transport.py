"""Fixed fake executables only: these tests never start Node or a browser."""

import base64
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from evals import html_artifact_question as artifact
from evals import observe_html_artifact as transport
from tests.test_html_artifact_question import observation, spec


class HTMLArtifactTransportTests(unittest.TestCase):
    def setUp(self):
        self.job = artifact.prepare_html_artifact(spec())
        self.envelope = observation(self.job, [False, False, True, False])

    def _run(self, body, *, deadline=None):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "fixed-observer"
            executable.write_text(
                f"#!{sys.executable}\nimport json, os, sys, time\n" + body,
                encoding="utf-8",
            )
            executable.chmod(0o700)
            with patch.object(
                transport,
                "PROCESS_TIMEOUT_SECONDS",
                3 if deadline is None else deadline,
            ):
                record = transport.observe_html_job(
                    self.job,
                    node=executable,
                    playwright_module=Path(directory) / "no-real-playwright",
                    browsers_path=Path(directory) / "no-real-browser",
                )
            self.assertEqual(record["node"], str(executable.resolve()))
            self.assertEqual(record["observer_path"], str(artifact.OBSERVER))
            return record

    def _reply(self, envelope, returncode=0):
        return self._run(
            "sys.stdin.buffer.read()\n"
            f"sys.stdout.write({(json.dumps(envelope) + chr(10))!r})\n"
            f"sys.exit({returncode})\n"
        )

    def test_exact_request_and_environment_are_captured_without_credentials(self):
        before = copy.deepcopy(self.job)
        with patch.dict(
            os.environ,
            {
                "AWS_ACCESS_KEY_ID": "fake-for-exclusion-only",
                "AWS_SECRET_ACCESS_KEY": "fake-secret-for-exclusion-only",
                "AWS_SESSION_TOKEN": "fake-session-for-exclusion-only",
                "NODE_OPTIONS": "must-not-reach-child",
            },
        ):
            result = self._run(
                "import hashlib\n"
                "raw = sys.stdin.buffer.read()\n"
                "sys.stderr.write(json.dumps({'stdin_sha256': hashlib.sha256(raw).hexdigest(), "
                "'environment': dict(os.environ), 'args': sys.argv[1:]}))\n"
                f"sys.stdout.write({json.dumps(self.envelope)!r})\n"
            )
        child = json.loads(result["stderr"])
        self.assertEqual(self.job, before)
        self.assertEqual(result["request"], before)
        self.assertEqual(result["stdin_text"], artifact.canonical(before) + "\n")
        self.assertEqual(result["stdin_sha256"], child["stdin_sha256"])
        self.assertEqual(result["stdin_bytes"], result["stdin_bytes_sent"])
        self.assertEqual(child["args"], [str(artifact.OBSERVER)])
        self.assertTrue(
            set(result["environment"])
            <= {
                "PATH",
                "HOME",
                "TMPDIR",
                "LANG",
                "CHECKPOINT_PLAYWRIGHT_MODULE",
                "PLAYWRIGHT_BROWSERS_PATH",
            }
        )
        self.assertFalse(any(k.startswith("AWS_") for k in child["environment"]))
        self.assertNotIn("NODE_OPTIONS", child["environment"])
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["reason"], "")
        self.assertEqual(result["returncode"], 0)
        self.assertEqual(result["envelope"], self.envelope)
        self.assertEqual(
            result["cleanup"],
            {
                "child_reaped": True,
                "termination_attempted": False,
                "browser_cleanup_confirmed": True,
            },
        )
        for stream in ("stdout", "stderr"):
            raw = base64.b64decode(result[stream + "_base64"])
            self.assertEqual(raw.decode("utf-8"), result[stream])
            self.assertEqual(len(raw), result[stream + "_bytes_seen"])
            self.assertEqual(len(raw), result[stream + "_retained_bytes"])

    def test_observation_success_is_separate_from_offered_answer_membership(self):
        envelope = observation(self.job, [True, False, True, False])
        result = self._reply(envelope)
        self.assertEqual(result["status"], "completed")
        with self.assertRaisesRegex(
            artifact.HTMLArtifactError, "observed_answer_not_uniquely_offered"
        ):
            artifact.bind_html_observation(self.job, result["envelope"])

    def test_closed_unsupported_observation_is_not_operational_or_answer_success(self):
        envelope = copy.deepcopy(self.envelope)
        envelope.update(
            status="unsupported",
            reason="property_not_boolean_on_target",
            values=None,
            serialized_dom="",
            serialized_dom_sha256="",
            target_outer_html="",
        )
        result = self._reply(envelope, 1)
        self.assertEqual(result["status"], "unsupported")
        self.assertEqual(result["envelope"]["reason"], envelope["reason"])
        self.assertTrue(result["cleanup"]["browser_cleanup_confirmed"])
        with self.assertRaises(artifact.HTMLArtifactError):
            artifact.bind_html_observation(self.job, result["envelope"])

    def test_malformed_missing_or_mismatched_observations_fail_closed(self):
        mutations = (
            lambda e: e.pop("values"),
            lambda e: e.update(values=[0, False, True, False]),
            lambda e: e.update(values=[False]),
            lambda e: e.update(job_id="wrong-job"),
            lambda e: e.update(serialized_dom_sha256="wrong-dom"),
            lambda e: e.update(unknown="unexpected"),
            lambda e: e["settings"].update(offline=1),
            lambda e: e["browser"].update(version=""),
            lambda e: e["cleanup"].update(browser="failed"),
            lambda e: e.pop("cleanup"),
        )
        for mutate in mutations:
            envelope = copy.deepcopy(self.envelope)
            mutate(envelope)
            with self.subTest(envelope=envelope):
                result = self._reply(envelope)
                self.assertEqual(result["status"], "operational_failure")
                self.assertFalse(result["cleanup"]["browser_cleanup_confirmed"])
                self.assertTrue(result["cleanup"]["child_reaped"])
        for text in ("{", '{"status":"observed","status":"observed"}', "null"):
            with self.subTest(text=text):
                result = self._run(
                    f"sys.stdin.buffer.read()\nsys.stdout.write({text!r})\n"
                )
                self.assertEqual(result["status"], "operational_failure")
                self.assertFalse(result["cleanup"]["browser_cleanup_confirmed"])

    def test_exit_code_and_cleanup_are_required_even_for_matching_observation(self):
        result = self._reply(self.envelope, 1)
        self.assertEqual(result["status"], "operational_failure")
        self.assertEqual(result["reason"], "observer_failed")
        # A confirmed close can coexist with a separate transport failure.
        self.assertTrue(result["cleanup"]["browser_cleanup_confirmed"])
        envelope = copy.deepcopy(self.envelope)
        envelope.update(status="operational_failure", reason="cleanup_failed")
        envelope["cleanup"]["context"] = "failed"
        result = self._reply(envelope, 1)
        self.assertEqual(result["status"], "operational_failure")
        self.assertFalse(result["cleanup"]["browser_cleanup_confirmed"])

    def test_partial_output_and_closed_pipes_cannot_evade_process_deadline(self):
        for body in (
            "os.write(1, b'{\"protocol\":')\ntime.sleep(60)\n",
            "os.close(1)\nos.close(2)\ntime.sleep(60)\n",
        ):
            started = time.monotonic()
            with self.subTest(body=body):
                result = self._run(body, deadline=0.2)
                self.assertLess(time.monotonic() - started, 2)
                self.assertEqual(result["status"], "operational_failure")
                self.assertEqual(result["reason"], "process_deadline")
                self.assertTrue(result["cleanup"]["termination_attempted"])
                self.assertTrue(result["cleanup"]["child_reaped"])
                self.assertFalse(result["cleanup"]["browser_cleanup_confirmed"])
                self.assertLess(result["returncode"], 0)

    def test_each_output_stream_is_bounded_and_overflow_terminates_child(self):
        for stream, descriptor in (("stdout", 1), ("stderr", 2)):
            with self.subTest(stream=stream):
                result = self._run(
                    f"os.write({descriptor}, b'x' * 65536)\ntime.sleep(60)\n"
                )
                self.assertEqual(result["status"], "operational_failure")
                self.assertEqual(result["reason"], stream + "_capture_limit")
                self.assertEqual(result[stream + "_retained_bytes"], 32768)
                self.assertGreater(result[stream + "_bytes_seen"], 32768)
                self.assertEqual(
                    base64.b64decode(result[stream + "_base64"]), b"x" * 32768
                )
                self.assertTrue(result["cleanup"]["termination_attempted"])
                self.assertTrue(result["cleanup"]["child_reaped"])
                self.assertFalse(result["cleanup"]["browser_cleanup_confirmed"])
                for name in ("stdout", "stderr"):
                    self.assertLessEqual(result[name + "_retained_bytes"], 32768)

    def test_invalid_utf8_is_preserved_as_bytes_and_never_accepted(self):
        result = self._run("sys.stdin.buffer.read()\nos.write(1, b'\\xff')\n")
        self.assertEqual(result["status"], "operational_failure")
        self.assertEqual(result["reason"], "invalid_output_utf8")
        self.assertIsNone(result["stdout"])
        self.assertEqual(base64.b64decode(result["stdout_base64"]), b"\xff")

    def test_input_limit_prevents_spawn_and_spawn_failure_is_explicit(self):
        large_job = {"text": "é" * 8192}
        with patch.object(transport.subprocess, "Popen") as spawn:
            result = transport.observe_html_job(
                large_job,
                node="/unused",
                playwright_module="/unused",
                browsers_path="/unused",
            )
        spawn.assert_not_called()
        self.assertEqual(result["reason"], "input_byte_limit_exceeded")
        self.assertGreater(result["stdin_bytes"], 16384)
        self.assertEqual(result["stdin_bytes_sent"], 0)
        self.assertFalse(result["child_started"])
        result = transport.observe_html_job(
            self.job,
            node="/nonexistent/checkpoint-transport-test-node",
            playwright_module="/unused",
            browsers_path="/unused",
        )
        self.assertEqual(result["status"], "operational_failure")
        self.assertEqual(result["reason"], "FileNotFoundError")
        self.assertFalse(result["child_started"])
        self.assertIsNone(result["returncode"])


if __name__ == "__main__":
    unittest.main()
