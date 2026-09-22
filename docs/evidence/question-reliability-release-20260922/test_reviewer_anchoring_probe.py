"""Offline runner checks; fake provider only, no credentials or network."""

import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("anchoring_probe_test_target", HERE / "reviewer_anchoring_probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class FakeClient:
    def __init__(self, respond):
        self.respond = respond
        self.calls = []

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return self.respond(request)


class ReviewerAnchoringProbeTests(unittest.TestCase):
    def setUp(self):
        self.plan = probe.load_plan()
        self.enterContext(patch.object(probe.boto3, "client", side_effect=AssertionError("No live SDK clients")))
        self.enterContext(patch.object(probe.subprocess, "check_output", side_effect=AssertionError("No credentials")))
        self.saves = self.enterContext(patch.object(probe, "save"))
        self.gold = {item["prompt"]: item for item in self.plan["gold_items"]}

    def response(self, request, mutate=None):
        rows = []
        for item in probe.user_data(request)["items"]:
            rows.append({"index": item["index"], "valid": True,
                         "answer": self.gold[item["prompt"]]["expected_answer"], "difficulty": 2,
                         "explanation": "Offline fixture only; independent semantic audit remains required.",
                         "choiceFeedback": [{"choice": choice, "explanation": "Offline feedback fixture with adequate bounds."}
                                            for choice in item["choices"]]})
        if mutate:
            mutate(rows)
        return {"stopReason": "end_turn", "usage": {"inputTokens": 1, "outputTokens": 1},
                "output": {"message": {"content": [{"text": json.dumps({"reviews": rows})}]}}}

    def run_fake(self, respond):
        client = FakeClient(respond)
        capture = {"calls": []}
        probe.run_calls(client, self.plan, capture, Path("/unused"))
        return client, capture

    def test_request_delta_and_orchestration_import_are_isolated(self):
        self.assertNotIn("question_verification", sys.modules)
        self.assertEqual(len(probe.source_hashes()), 3)
        self.assertTrue(all("question_verification" not in path for path in probe.source_hashes()))
        self.assertEqual([(c["job_index"], c["arm"]) for c in self.plan["calls"]],
                         [(0, "with_solutions"), (0, "without_solutions"),
                          (1, "without_solutions"), (1, "with_solutions")])

    def test_four_requests_run_exactly_once_and_remain_pending_semantic_audit(self):
        client, capture = self.run_fake(self.response)
        self.assertEqual(client.calls, [c["provider_request"] for c in self.plan["calls"]])
        self.assertEqual(len(capture["calls"]), 4)
        self.assertEqual(capture["status"], "dispatch_complete_pending_semantic_audit")
        for row in capture["calls"]:
            self.assertTrue(all(item["local_admission_pass"] for item in row["assessment"]["items"]))
            self.assertTrue(all(item["semantic_adjudication"] == "pending" for item in row["assessment"]["items"]))

    def test_transport_and_non_end_turn_stop_without_retry(self):
        def error(_request):
            raise TimeoutError("synthetic")

        for respond, reason in ((error, "transport_failure"), (lambda _: {"stopReason": "max_tokens"}, "non_end_turn")):
            with self.subTest(reason=reason):
                client, capture = self.run_fake(respond)
                self.assertEqual(len(client.calls), 1)
                self.assertEqual(capture["stop_reason"], reason)
                self.assertEqual(capture["status"], "stopped_after_failure")

    def test_schema_and_index_coverage_errors_stop_with_raw_response_retained(self):
        for mutate in (lambda rows: rows.pop(), lambda rows: rows[1].update(index=0),
                       lambda rows: rows[0].update(index=True), lambda rows: rows[0].update(unexpected="field")):
            with self.subTest(mutate=mutate):
                client, capture = self.run_fake(lambda request: self.response(request, mutate))
                self.assertEqual(len(client.calls), 1)
                self.assertEqual(capture["stop_reason"], "structural_failure")
                self.assertIn("response", capture["calls"][0])

    def test_duplicate_json_fields_stop_in_real_native_adapter(self):
        def respond(request):
            result = self.response(request)
            block = result["output"]["message"]["content"][0]
            block["text"] = block["text"].replace('"index": 0', '"index": 0, "index": 0', 1)
            return result
        client, capture = self.run_fake(respond)
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(capture["stop_reason"], "structural_failure")

    def test_semantic_admission_failures_are_counted_and_do_not_trigger_extra_calls(self):
        def mutate(rows):
            rows[0]["answer"] = "wrong exact key"
            rows[1]["explanation"] = "x" * 421
            rows[2]["difficulty"] = 1
            rows[3]["choiceFeedback"][0]["explanation"] = "Option A is the correct answer in this fixture."
            rows[4]["difficulty"] = 4
        client, capture = self.run_fake(lambda request: self.response(request, mutate))
        self.assertEqual(len(client.calls), 4)
        self.assertNotIn("stop_reason", capture)
        for row in capture["calls"]:
            assessed = row["assessment"]["items"]
            self.assertEqual([item["local_admission_pass"] for item in assessed], [False, False, False, False, True])
            self.assertFalse(assessed[4]["difficulty_requested_range_met"])

    def test_rejected_valid_controls_are_false_rejections_not_removed_denominators(self):
        def mutate(rows):
            for row in rows:
                row.update(valid=False, answer="", difficulty=0, explanation="", choiceFeedback=[])
        client, capture = self.run_fake(lambda request: self.response(request, mutate))
        self.assertEqual(len(client.calls), 4)
        for row in capture["calls"]:
            self.assertEqual(len(row["assessment"]["items"]), 5)
            self.assertTrue(all(item["false_rejection"] and not item["local_admission_pass"]
                                for item in row["assessment"]["items"]))

    def test_known_paint_error_is_not_misreported_as_automatically_semantically_valid(self):
        captured = json.loads((HERE / "pipeline-capture-v2.json").read_text())
        assessed = probe.assess(captured["calls"][2]["response"], self.plan["calls"][0], self.plan)
        self.assertTrue(assessed["items"][2]["local_admission_pass"])
        self.assertEqual(assessed["items"][2]["semantic_adjudication"], "pending")
        self.assertIn("3:3", assessed["adapted_response"]["reviews"][2]["choiceExplanations"]["9 liters"])

    def test_call_ceiling_cannot_dispatch_a_fifth_request(self):
        client = FakeClient(self.response)
        with self.assertRaises(RuntimeError):
            probe.run_calls(client, self.plan, {"calls": [{}, {}, {}, {}]}, Path("/unused"))
        self.assertEqual(client.calls, [])

    def test_existing_capture_blocks_before_credentials_or_sdk_client(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capture.json"
            path.write_text("old evidence")
            with patch.object(probe, "CAPTURE", path), patch.object(probe, "preflight", return_value=(self.plan, {})):
                # Restore only the real exclusive-write behavior for this check.
                def exclusive_save(target, value, *, exclusive=False):
                    with target.open("x" if exclusive else "w") as stream:
                        json.dump(value, stream)
                with patch.object(probe, "save", side_effect=exclusive_save), self.assertRaises(FileExistsError):
                    probe.execute("unused")
            self.assertEqual(path.read_text(), "old evidence")


if __name__ == "__main__":
    unittest.main()
