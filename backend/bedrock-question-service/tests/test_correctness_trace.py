import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals.checkpoint_correctness_trace import SETTINGS, TraceClient, load_cases, run_case
from lambda_test_support import FakeBedrockClient, _raw_question


class CorrectnessTraceTests(unittest.TestCase):
    def test_matrix_has_multiple_cases_per_domain_and_both_source_modes(self):
        cases = load_cases([])
        self.assertEqual(len(cases), 12)
        for domain in {case["domain"] for case in cases}:
            subset = [case for case in cases if case["domain"] == domain]
            self.assertEqual(len(subset), 3)
            self.assertEqual({bool(c["payload"]["sourceDocuments"]) for c in subset}, {True, False})
        for ids in [["missing"], [cases[0]["id"], cases[0]["id"]]]:
            with self.assertRaises(ValueError):
                load_cases(ids)

    def test_exact_runtime_stages_and_bank_transport_are_captured(self):
        case = load_cases(["math_arithmetic"])[0]
        questions = [_raw_question("Which quantity follows from the first calculation?"),
                     _raw_question("Which quantity follows from the second calculation?")]
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, SETTINGS):
            trace = run_case(case, Path(temp), FakeBedrockClient.returning_questions(*questions))
            saved = json.loads((Path(temp) / "math_arithmetic.json").read_text())
        self.assertEqual(saved, trace)
        self.assertEqual(len(trace["calls"]), 3)
        self.assertEqual(len(trace["final"]), 2)
        self.assertEqual(trace["budget_calls"], 3)
        for stage in ["author_parse", "sanitize", "verification", "solver_parse", "solver_decision"]:
            self.assertIn(stage, [s["stage"] for s in trace["stages"]])
        self.assertEqual(trace["bank_prepared"], trace["transport_roundtrip"]["questions"])
        for question, row in zip(trace["final"], trace["bank_prepared"], strict=True):
            self.assertEqual(question, {k: v for k, v in row.items() if k != "remoteID"})

    def test_failure_stops_real_calls_and_does_not_save_error_details(self):
        class Failing:
            calls = 0

            def converse(self, **request):
                self.calls += 1
                raise ValueError("private SDK detail")

        client = Failing()
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, SETTINGS):
            trace = run_case(load_cases(["math_arithmetic"])[0], Path(temp), client)
        self.assertEqual(client.calls, 1)
        self.assertEqual(len(trace["calls"]), 1)
        self.assertNotIn("private SDK detail", json.dumps(trace))
        self.assertEqual(trace["final"], [])

    def test_capture_excludes_reasoning_and_enforces_cap(self):
        response = {"output": {"message": {"content": [
            {"text": "{}"}, {"reasoningContent": {"reasoningText": {"text": "private reasoning"}}}
        ]}}, "stopReason": "end_turn"}
        trace = {"calls": []}
        capture = TraceClient(FakeBedrockClient(response), trace, lambda: None, cap=1)
        self.assertEqual(capture.converse(messages=[{"content": [{"text": "synthetic"}]}]), response)
        self.assertNotIn("private reasoning", json.dumps(trace))
        with self.assertRaises(RuntimeError):
            capture.converse(messages=[])
        self.assertEqual(len(trace["calls"]), 1)
