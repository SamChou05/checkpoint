"""No-network checks for the draft-only agreement qualification gate."""

import copy
import importlib.util
import json
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("qualification_guard", HERE / "qualification_guard.py")
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class DraftGuardTests(unittest.TestCase):
    def setUp(self):
        network_guard = patch.object(socket.socket, "connect", side_effect=AssertionError("No network"))
        network_guard.start()
        self.addCleanup(network_guard.stop)
        self.spec = json.loads((HERE / "qualification-spec.json").read_text())
        self.request = json.loads((HERE / "request.json").read_text())
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)

    def test_valid_draft_is_not_launchable(self):
        state = guard.check_draft(self.spec, self.request, directory=self.directory)
        self.assertEqual(state["provider_calls"], 0)
        self.assertFalse(state["freeze_allowed"])
        self.assertFalse(state["launch_allowed"])

    def test_source_claim_or_existing_capture_is_rejected(self):
        modified = copy.deepcopy(self.spec)
        modified["candidate_source_revision"] = "f" * 40
        with self.assertRaises(guard.ProtocolError):
            guard.check_draft(modified, self.request, directory=self.directory)
        (self.directory / "capture.json").write_text("{}")
        with self.assertRaises(guard.ProtocolError):
            guard.check_draft(self.spec, self.request, directory=self.directory)

    def test_request_schema_and_budget_drift_rejected(self):
        request = copy.deepcopy(self.request)
        request["targetCount"] = 4
        with self.assertRaises(guard.ProtocolError):
            guard.check_draft(self.spec, request, directory=self.directory)
        for section, key, value in (
            ("expected_current_author_contract", "native_schema_bytes", 2702),
            ("limits", "calls_per_job", 7),
            ("prespecified_gate", "agreement_policy10_required", 0),
        ):
            modified = copy.deepcopy(self.spec)
            modified[section][key] = value
            with self.assertRaises(guard.ProtocolError):
                guard.check_draft(modified, self.request, directory=self.directory)

    def test_old_three_of_five_cannot_pass(self):
        result = {"returned_original_slots": [0, 1, 2],
                  "verification_policy_revisions_by_slot": [8, 8, 8],
                  "provider_calls": 3, "elapsed_seconds": 128.485,
                  "within_execute_deadline": True,
                  "requested_skill_allocation_exact": True,
                  "independent_keys_pass": True,
                  "all_six_choice_pairs_pass": True,
                  "teaching_audit_pass": True,
                  "blind_reviews_locked": True,
                  "blind_reviews_pass": True,
                  "unresolved_content_uncertainty": 0}
        self.assertFalse(guard.official_gate(result))
        result["returned_original_slots"] = [0, 1, 2, 3, 4]
        result["verification_policy_revisions_by_slot"] = [8, 8, 8, 10, 10]
        self.assertTrue(guard.official_gate(result))
        result["provider_calls"] = 7
        self.assertFalse(guard.official_gate(result))


if __name__ == "__main__":
    unittest.main()
