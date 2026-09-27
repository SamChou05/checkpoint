"""Mutation checks for the offline mixed successor draft guard."""

import copy
import json
import unittest
from unittest.mock import patch

import check_draft as draft


class DraftGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = json.loads((draft.HERE / "plan-draft.json").read_text())
        cls.jobs = json.loads((draft.HERE / "jobs-draft.json").read_text())
        cls.prior = json.loads((draft.ROOT / "docs/evidence/task-only-full-worker-qualification-20260926/jobs-draft.json").read_text())

    def test_pinned_original_evidence_and_assignment(self):
        self.assertEqual(draft.check_files()["aws_operations"], 0)

    def test_allocation_drift_rejected(self):
        jobs = copy.deepcopy(self.jobs)
        jobs["jobs"][0]["request"]["requestedSkillAllocation"][draft.ARITHMETIC[0]] = 2
        with self.assertRaises(ValueError):
            draft.validate(self.spec, jobs, self.prior)

    def test_relaxed_return_gate_rejected(self):
        spec = copy.deepcopy(self.spec)
        spec["gates"]["original_slots_returned"] = 4
        with self.assertRaises(ValueError):
            draft.validate(spec, self.jobs, self.prior)

    def test_premature_launch_rejected(self):
        spec = copy.deepcopy(self.spec)
        spec["aws_launch_authorized"] = True
        with self.assertRaises(ValueError):
            draft.validate(spec, self.jobs, self.prior)

    def test_missing_mapped_field_rejected(self):
        spec = copy.deepcopy(self.spec)
        spec["source_acceptance"]["mandatory_mapped_fields"].remove("objectiveID")
        with self.assertRaises(ValueError):
            draft.validate(spec, self.jobs, self.prior)

    def test_scope_flag_drift_rejected(self):
        spec = copy.deepcopy(self.spec)
        spec["trial_environment"]["QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256"] = "0" * 64
        with self.assertRaises(ValueError):
            draft.validate(spec, self.jobs, self.prior)

    def test_reviewed_source_byte_drift_rejected(self):
        original = draft.sha256
        target = draft.ROOT / "backend/bedrock-question-service/question_generation.py"
        with patch.object(draft, "sha256",
                          side_effect=lambda path: "bad" if path == target else original(path)):
            with self.assertRaises(ValueError):
                draft.check_files()

    def test_extra_job_rejected(self):
        jobs = copy.deepcopy(self.jobs)
        jobs["jobs"].append(copy.deepcopy(jobs["jobs"][0]))
        with self.assertRaises(ValueError):
            draft.validate(self.spec, jobs, self.prior)


if __name__ == "__main__":
    unittest.main()
