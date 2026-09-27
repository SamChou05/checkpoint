"""No provider, network, or credential path is imported by these tests."""

import copy
import tempfile
import unittest
from pathlib import Path

import protocol_guard as guard


class ProtocolGuardTests(unittest.TestCase):
    def setUp(self):
        self.protocol = guard.strict_json(guard.HERE / "protocol.json")
        self.request = guard.strict_json(guard.HERE / "request.json")
        self.request_bytes = (guard.HERE / "request.json").read_bytes()

    def check(self, protocol=None, request=None, directory=None, request_bytes=None,
              check_artifacts=False):
        return guard.check_draft(
            self.protocol if protocol is None else protocol,
            self.request if request is None else request,
            directory=guard.HERE if directory is None else directory,
            request_bytes=self.request_bytes if request_bytes is None else request_bytes,
            check_artifacts=check_artifacts,
        )

    def test_draft_is_inert_and_request_is_normalized(self):
        result = self.check()
        self.assertEqual(result["provider_calls"], 0)
        self.assertFalse(result["launch_allowed"])

    def test_request_or_candidate_drift_refuses(self):
        with self.assertRaises(guard.ProtocolError):
            self.check(request_bytes=self.request_bytes + b" ")
        changed = copy.deepcopy(self.request)
        changed["skillMap"] = {"skills": []}
        with self.assertRaises(guard.ProtocolError):
            self.check(request=changed)
        changed = copy.deepcopy(self.protocol)
        changed["candidate_source_commit"] = "frozen-too-soon"
        with self.assertRaises(guard.ProtocolError):
            self.check(protocol=changed)

    def test_launch_artifact_or_budget_drift_refuses(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "capture.json").write_text("{}")
            with self.assertRaises(guard.ProtocolError):
                self.check(directory=directory, check_artifacts=True)
        changed = copy.deepcopy(self.protocol)
        changed["limits"]["maximum_converse_calls"] = 7
        with self.assertRaises(guard.ProtocolError):
            self.check(protocol=changed)

    def test_illustrative_gate_rejects_missing_reordered_and_partial_survivors(self):
        valid = {
            "authored_source_ordinals": list(range(7)),
            "accepted_source_ordinals": [0, 2, 3, 5, 6],
            "returned_source_ordinals": [0, 2, 3, 5, 6],
            "verification_versions": [1] * 5,
            "verification_policy_revisions": [7] * 5,
            "offered_choice_counts": [4] * 5,
            "offered_key_counts": [1] * 5,
            "backend_difficulties": [2, 2, 3, 3, 2],
            "independent_unique_keys": True,
            "distinct_choice_pair_counts": [6] * 5,
            "all_self_contained_and_on_topic": True,
            "all_teaching_sound": True,
            "no_strong_cross_question_repeats": True,
            "blind_reviews_locked": True,
            "blind_review_count": 2,
            "blind_reviewer_difficulties": [[2, 3, 2, 3, 2], [2, 2, 3, 3, 2]],
            "blind_reviews_pass": True,
            "unresolved_content_uncertainty": 0,
            "converse_calls": 3,
            "whole_execute_seconds": 180,
            "deadline_included_credential_export_and_sts": True,
            "no_second_job_or_repair": True,
        }
        self.assertTrue(guard.illustrative_gate(valid))
        for change in (
            {"accepted_source_ordinals": [0, 2, 3, 5]},
            {"returned_source_ordinals": [2, 0, 3, 5, 6]},
            {"returned_source_ordinals": [0, 2, 3, 5, 5]},
            {"verification_policy_revisions": [7, 7, 7, 7, 4]},
            {"offered_key_counts": [1, 1, 2, 1, 1]},
            {"backend_difficulties": [2, 2, 1, 2, 2]},
            {"blind_reviewer_difficulties": [[2, 3, 2, 3, 2], [2, 2, 4, 3, 2]]},
            {"distinct_choice_pair_counts": [6, 6, 5, 6, 6]},
            {"no_strong_cross_question_repeats": False},
            {"blind_reviews_locked": False},
            {"whole_execute_seconds": 241},
            {"converse_calls": 7},
        ):
            with self.subTest(change=change):
                self.assertFalse(guard.illustrative_gate({**valid, **change}))

    def test_duplicate_json_members_refuse(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "input.json"
            path.write_text('{"state":"draft", "state":"frozen"}')
            with self.assertRaises(guard.ProtocolError):
                guard.strict_json(path)


if __name__ == "__main__":
    unittest.main()
