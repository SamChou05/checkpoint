"""Socket-free checks for the exact English native-author probe."""

import hashlib
import json
import signal
import socket
import time
import unittest
from unittest.mock import patch

import probe

PLAN_SHA256 = "634d19695af337950e0465322c729446030dbfb18419f4ada12c53348522f2fb"


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


if __name__ == "__main__":
    unittest.main()
