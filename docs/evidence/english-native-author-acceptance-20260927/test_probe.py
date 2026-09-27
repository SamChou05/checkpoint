"""Socket-free checks for the exact English native-author probe."""

import hashlib
import json
import signal
import socket
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import probe

PLAN_SHA256 = "db6295d74338ddfe0219645fe0e41539c2c144cd1b254e6d681b27af36d0ace5"


class EnglishNativeAuthorProbeTest(unittest.TestCase):
    def test_frozen_wire_schema_and_fake_provider_compile(self):
        with patch.object(socket.socket, "connect", side_effect=AssertionError("network")):
            plan, wire, contract, request = probe.checked(PLAN_SHA256)

        self.assertEqual(plan["current_schema_bytes"], 2226)
        self.assertEqual(plan["current_schema_sha256"],
                         "3ac240ae33163d16481c18a9eb8d1032404e5f06bf30cdac4a96304ff637edda")
        self.assertEqual(plan["wire_sha256"], hashlib.sha256(probe.canonical(wire)).hexdigest())
        self.assertEqual(request["targetCount"], 5)
        self.assertEqual(contract.transport_name,
                         wire["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"])
        schema = json.loads(wire["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
        slots = schema["properties"]["questions"]["properties"]
        self.assertIn("partitive_paint", slots["3"]["properties"]["scene"]["enum"])
        self.assertNotIn("partitive_paint", slots["4"]["properties"]["scene"]["enum"])
        self.assertIn("compound_guides", slots["4"]["properties"]["scene"]["enum"])
        self.assertNotIn("compound_guides", slots["3"]["properties"]["scene"]["enum"])
        result = plan["fake_provider_english_repertoire_result"]
        self.assertEqual(result["chosen_scenes"], {"3": "partitive_paint", "4": "compound_guides"})
        self.assertEqual(result["offline_compilation"]["rows"], 5)
        self.assertEqual(result["offline_compilation"]["failures"], [])

    @unittest.skipUnless(hasattr(signal, "SIGALRM"), "POSIX timer required")
    def test_hard_deadline_interrupts_blocking_work(self):
        old_alarm = signal.getsignal(signal.SIGALRM)
        signal.signal(signal.SIGALRM, probe.deadline_alarm)
        started = time.monotonic()
        try:
            signal.setitimer(signal.ITIMER_REAL, 0.05)
            with self.assertRaises(probe.DeadlineExceeded):
                time.sleep(0.5)
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, old_alarm)
        self.assertLess(time.monotonic() - started, 0.4)

    def test_expiration_parses_utc_and_offset_and_rejects_naive(self):
        def snapshot(expiration):
            return json.dumps({"Expiration": expiration}).encode()

        utc = probe.parse_credential_expiration(snapshot("2026-09-27T12:00:00Z"))
        offset = probe.parse_credential_expiration(snapshot("2026-09-27T14:00:00+02:00"))
        self.assertEqual(utc, offset)
        for invalid in ("2026-09-27T12:00:00", "not-a-date", None):
            with self.subTest(invalid=invalid), self.assertRaises(RuntimeError):
                probe.parse_credential_expiration(snapshot(invalid))

    def test_one_export_snapshot_supplies_session_and_expiration(self):
        exported = json.dumps({
            "Version": 1, "AccessKeyId": "offline-key", "SecretAccessKey": "offline-secret",
            "SessionToken": "offline-token", "Expiration": "2026-09-27T12:00:00Z",
        }).encode()
        with (patch.object(socket.socket, "connect", side_effect=AssertionError("network")),
              patch.object(probe.safe, "export_credentials", return_value=exported) as exporter):
            session, secrets, expiration = probe.credential_session_with_expiration()
        exporter.assert_called_once_with()
        self.assertEqual(secrets, ("offline-key", "offline-secret", "offline-token"))
        self.assertEqual(session.region_name, "us-east-1")
        self.assertEqual(expiration,
                         probe.parse_credential_expiration(exported))

    def test_near_expiry_fails_closed_before_converse_with_safe_capture(self):
        self.assertEqual(probe.credential_remaining_at_dispatch(1150, now=1000), 150)
        with self.assertRaisesRegex(RuntimeError, "expires before"):
            probe.credential_remaining_at_dispatch(1149.999, now=1000)

        class FakeSTS:
            def get_caller_identity(self):
                return {"Account": probe.ACCOUNT}

        class FakeBedrock:
            def __init__(self):
                self.meta = probe.boto3.Session(
                    aws_access_key_id="offline", aws_secret_access_key="offline",
                    region_name="us-east-1").client(
                        "bedrock-runtime", endpoint_url=probe.BEDROCK_ENDPOINT,
                        config=probe.Config(retries={"total_max_attempts": 1,
                                                     "mode": "standard"})).meta
                self.calls = 0

            def converse(self, **_wire):
                self.calls += 1
                raise AssertionError("near-expiry capture dispatched Converse")

        bedrock = FakeBedrock()

        class FakeSession:
            def client(self, name, **_kwargs):
                return FakeSTS() if name == "sts" else bedrock

        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            lock = folder / "review-approval.json"
            capture = folder / "capture.json"
            plan = probe.safe.strict_json(probe.PLAN.read_text())
            lock.write_text(json.dumps({"plan_sha256": PLAN_SHA256,
                                        "harness_sha256": plan["harness_sha256"],
                                        "root_go": True, "independent_go": True}))
            with (patch.object(socket.socket, "connect", side_effect=AssertionError("network")),
                  patch.object(probe, "CAPTURE", capture),
                  patch.object(probe, "REVIEW_LOCK", lock),
                  patch.object(probe, "credential_session_with_expiration",
                               return_value=(FakeSession(), ("offline-secret",),
                                             time.time() + 100))):
                result = probe.execute(PLAN_SHA256)
            saved = probe.safe.strict_json(capture.read_text())
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["sts_calls"], 1)
        self.assertEqual(result["converse_calls"], 0)
        self.assertEqual(bedrock.calls, 0)
        self.assertEqual(saved["status"], "failed")
        self.assertNotIn("offline-secret", json.dumps(saved))


if __name__ == "__main__":
    unittest.main()
