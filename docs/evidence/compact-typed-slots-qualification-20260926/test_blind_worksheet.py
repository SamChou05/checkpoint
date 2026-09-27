"""Socket-blocked synthetic checks for the five-slot keyless projection."""

import hashlib
import importlib.util
import json
from pathlib import Path
import socket
import stat
import tempfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("compact_worker_blind_projection", HERE / "make_blind_worksheet.py")
projection = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(projection)


def save(path, value):
    raw = (json.dumps(value, indent=2) + "\n").encode()
    path.write_bytes(raw)
    return hashlib.sha256(raw).hexdigest()


class BlindWorksheetTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, "connect", side_effect=AssertionError("offline only")))
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)

    def fixture(self, counts=(4,)):
        ids = ("mixed",)
        plan = {"state": "frozen", "jobs": [{"id": name, "request": {"targetCount": 5}} for name in ids]}
        plan_sha = save(self.directory / "plan.json", plan)
        originals, observed = [], []
        for name, count in zip(ids, counts, strict=True):
            slots = [{"ordinal": ordinal, "status": "returned" if ordinal < count else "unfilled"}
                     for ordinal in range(5)]
            rows = []
            for ordinal in range(count):
                choices = [f"{name}-{ordinal}-{letter}" for letter in "abcd"]
                rows.append({"prompt": f"Synthetic question for {name} slot {ordinal}?",
                             "choices": choices, "expectedAnswer": choices[2],
                             "explanation": "SECRET_TEACHING", "choiceExplanations": {choices[0]: "SECRET_FEEDBACK"}})
            originals.append({"id": name, "slots": slots})
            observed.append({"id": name, "returned": rows,
                             "returned_slot_ordinals": list(range(count)),
                             "returned_sources": [[name, 0, ordinal] for ordinal in range(count)],
                             "returned_provenance": [None for _ in range(count)]})
        capture = {"status": "completed_pending_review", "plan": plan, "plan_sha256": plan_sha,
                   "summary": {"planned_questions": 5, "returned_questions": sum(counts)},
                   "original_jobs": originals, "jobs": observed,
                   "call_slots": [{"job": name, "ordinal": ordinal, "status": "unattempted"}
                                  for name in ids for ordinal in range(6)]}
        capture_sha = save(self.directory / "capture.json", capture)
        return plan, capture, plan_sha, capture_sha

    def test_all_five_slots_are_opaque_rotated_and_keyless(self):
        _, capture, plan_sha, capture_sha = self.fixture()
        result = projection.project(self.directory, capture_sha, plan_sha)
        worksheet = json.loads((self.directory / "blind-worksheet.json").read_text())
        private = json.loads((self.directory / "blind-private-map.json").read_text())
        self.assertEqual((result["requested_slots"], result["readable_returns"],
                          result["credited_returns"], result["unavailable_slots"]), (5, 4, 4, 1))
        self.assertEqual(len(worksheet["items"]), 5)
        self.assertEqual(len({item["id"] for item in worksheet["items"]}), 5)
        self.assertEqual(set(private["mapping"]), {item["id"] for item in worksheet["items"]})
        self.assertEqual(stat.S_IMODE((self.directory / "blind-private-map.json").stat().st_mode), 0o600)
        for item in worksheet["items"]:
            mapping = private["mapping"][item["id"]]
            self.assertEqual(set(mapping), {"job_id", "original_slot_ordinal", "slot_status",
                                            "returned_row_index", "display_to_source_index"})
            if item.get("unavailable"):
                self.assertEqual(set(item), {"id", "requested_slot", "unavailable"})
                self.assertIsNone(mapping["returned_row_index"])
                continue
            self.assertEqual(set(item), {"id", "requested_slot", "stem", "choices"})
            self.assertEqual(set(item["choices"]), set("ABCD"))
            source = next(job for job in capture["jobs"] if job["id"] == mapping["job_id"])
            row = source["returned"][mapping["returned_row_index"]]
            self.assertEqual(item["stem"], row["prompt"])
            self.assertEqual(list(item["choices"].values()),
                             [row["choices"][index] for index in mapping["display_to_source_index"]])
        visible = (self.directory / "blind-worksheet.json").read_text()
        for forbidden in ("expectedAnswer", "explanation", "choiceExplanations", "SECRET_TEACHING",
                          "SECRET_FEEDBACK", "returned_provenance"):
            self.assertNotIn(forbidden, visible)
        with self.assertRaises(ValueError):
            projection.project(self.directory, capture_sha, plan_sha)

    def test_wrong_input_hash_or_source_cardinality_fails_before_output(self):
        _, capture, plan_sha, capture_sha = self.fixture()
        with self.assertRaises(ValueError):
            projection.project(self.directory, "0" * 64, plan_sha)
        capture["jobs"][0]["returned_provenance"] = []
        changed_sha = save(self.directory / "capture.json", capture)
        with self.assertRaises(ValueError):
            projection.project(self.directory, changed_sha, plan_sha)
        self.assertFalse((self.directory / "blind-worksheet.json").exists())
        self.assertFalse((self.directory / "blind-private-map.json").exists())
        self.assertNotEqual(changed_sha, capture_sha)

    def test_terminal_abort_preserves_unavailable_original_denominator(self):
        _, capture, plan_sha, _ = self.fixture((0,))
        capture["status"] = "globally_aborted"
        capture["jobs"] = []
        for job in capture["original_jobs"]:
            for slot in job["slots"]:
                slot["status"] = "unattempted"
        capture_sha = save(self.directory / "capture.json", capture)
        result = projection.project(self.directory, capture_sha, plan_sha)
        self.assertEqual((result["readable_returns"], result["unavailable_slots"]), (0, 5))

    def test_partial_return_uses_original_slot_binding_not_output_position(self):
        _, capture, plan_sha, _ = self.fixture()
        capture["jobs"][0]["returned_slot_ordinals"] = [1, 2, 3, 4]
        capture["original_jobs"][0]["slots"][0]["status"] = "unfilled"
        capture["original_jobs"][0]["slots"][4]["status"] = "returned"
        capture_sha = save(self.directory / "capture.json", capture)
        projection.project(self.directory, capture_sha, plan_sha)
        private = json.loads((self.directory / "blind-private-map.json").read_text())
        self.assertEqual(sorted(item["original_slot_ordinal"] for item in private["mapping"].values()
                                if item["returned_row_index"] is not None), [1, 2, 3, 4])

    def test_late_diagnostic_return_is_visible_but_not_credited(self):
        _, capture, plan_sha, _ = self.fixture()
        capture["original_jobs"][0]["slots"][0]["status"] = "late_uncredited"
        capture["summary"]["returned_questions"] -= 1
        capture_sha = save(self.directory / "capture.json", capture)
        result = projection.project(self.directory, capture_sha, plan_sha)
        self.assertEqual((result["readable_returns"], result["credited_returns"],
                          result["late_diagnostic_returns"]), (4, 3, 1))


if __name__ == "__main__":
    unittest.main()
