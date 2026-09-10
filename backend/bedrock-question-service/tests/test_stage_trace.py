"""Real sequential runtime with local responses; trace must not change decisions."""
import copy
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from evals import checkpoint_stage_trace as trace
import test_delivery_comparison as support
from test_runtime_qualification import completed


class StageTraceTests(unittest.TestCase):
    def setUp(self):
        self.helper = support.DeliveryComparisonTests("test_full_normal_runtime_both_contracts_and_exact_no_client_replay")
        self.helper.setUp()
        self.addCleanup(self.helper.doCleanups)
        self.runtime = support.trial
        self.source = self.runtime.SERVICE_DIR

    def capture(self, change=None):
        def observer(request, **kwargs):
            state = self.helper.observer(request, **kwargs)
            saved = json.loads((self.helper.output / "capture.json").read_text())["calls"][-1]
            if change is not None:
                replacement = change(saved, state)
                if replacement is not None:
                    state = completed(replacement)
                    kwargs["on_progress"](copy.deepcopy(state))
            return state
        return self.helper.run_trial(observer)

    def traced(self, capture):
        original = copy.deepcopy(capture)
        result = trace.trace_capture(capture, self.source, runtime=self.runtime)
        self.assertEqual(capture, original)
        self.assertTrue(result["exact_replay"])
        return result

    def test_stateful_duplicate_and_surplus_have_actual_raw_ordinals(self):
        questions = self.helper.questions[0]
        raw = [questions[0], questions[0], *questions[1:7]]
        capture = self.capture(lambda call, _: {"questions": raw}
                               if call["operation_index"] == 0 and call["operation_call_index"] == 0 else None)
        result = self.traced(capture)
        batch = result["sanitizer_batches"][0]
        self.assertEqual(batch["raw_questions"], raw)
        self.assertEqual([(e["raw_ordinal"], e["reason"]) for e in batch["events"] if e["scope"] == "candidate"],
                         [(0, "accepted"), (1, "duplicate_stem"), (2, "accepted"),
                          (3, "accepted"), (4, "accepted"), (5, "accepted")])
        self.assertEqual(batch["events"][-1], {"reason": "surplus", "count": 2, "scope": "batch"})
        self.assertEqual([q["occurrence"].rsplit(":", 1)[1] for q in batch["admitted"]], ["0", "2", "3", "4", "5"])
        self.assertEqual([q["question"] for q in result["operations"][0]["returned"]], capture["operations"][0]["questions"])

    def test_solver_rejection_and_dense_review_indices_keep_occurrences(self):
        def change(call, state):
            if call["operation_index"] == 0 and call["operation_call_index"] == 1:
                response = json.loads(state["response"]["text"])
                for row in response["solutions"][0]["choices"]:
                    row["judgment"] = "refuted"
                return response
        result = self.traced(self.capture(change))
        verification = result["verifications"][0]
        solver, reviewer = verification["provider_batches"]
        self.assertEqual([link["index"] for link in solver["links"]], [0, 1, 2, 3, 4])
        self.assertEqual([link["index"] for link in reviewer["links"]], [0, 1, 2, 3])
        self.assertEqual([link["occurrence"] for link in reviewer["links"]], [link["occurrence"] for link in solver["links"][1:]])
        self.assertEqual([decision["record"]["index"] for decision in verification["solver_decisions"]], [0, 1, 2, 3, 4])
        self.assertEqual(verification["solver_decisions"][0]["rejection_reason"], "solver_zero_supported")
        self.assertTrue(all(d["rejection_reason"] is None for d in verification["solver_decisions"][1:]))
        self.assertEqual([r["occurrence"] for r in verification["returned"]], [link["occurrence"] for link in reviewer["links"]])

    def test_malformed_solver_is_only_a_batch_format_failure(self):
        result = self.traced(self.capture(lambda call, _: "not JSON" if call["role"] == "solver" else None))
        for verification in result["verifications"]:
            self.assertFalse(verification["solver_decisions"])
            self.assertFalse(verification["returned"])
            self.assertTrue(all(p["role"] == "solver" for p in verification["provider_batches"]))
            if verification["candidates"]:
                self.assertIn({"scope": "batch", "reason": "invalid_solution", "count": len(verification["candidates"])},
                              verification["events"])

    def test_nonarray_author_envelope_has_no_invented_candidate_identity(self):
        result = self.traced(self.capture(lambda call, _: {"questions": {"unusable": True}}
                                         if call["operation_index"] == 0 and call["role"] == "author" else None))
        batches = [b for b in result["sanitizer_batches"] if b["operation_index"] == 0]
        self.assertEqual(len(batches), 3)
        for batch in batches:
            self.assertEqual(batch["events"], [{"scope": "batch", "reason": "invalid_envelope", "count": 1}])
            self.assertEqual(batch["admitted"], [])

    def test_author_repair_identity_and_both_teaching_contracts(self):
        self.helper.modes[0] = "repair_success"
        capture = self.capture()
        result = self.traced(capture)
        self.assertEqual(capture["calls"][1]["role"], "author_json_repair")
        self.assertEqual(result["sanitizer_batches"][0]["call_index"], 1)
        self.assertTrue(all(q["occurrence"].split(":")[-2] == "1" for q in result["sanitizer_batches"][0]["admitted"]))
        for op, saved in zip(result["operations"], capture["operations"], strict=True):
            self.assertEqual([q["question"] for q in op["returned"]], saved["questions"])
        self.assertFalse(result["operations"][1]["returned"][0]["question"]["choiceExplanations"])
        self.assertTrue(result["operations"][0]["returned"][0]["question"]["choiceExplanations"])

    def test_changed_source_capture_and_missing_identity_are_refused(self):
        capture = self.capture()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "changed.py"
            path.write_text("changed")
            altered = copy.deepcopy(capture)
            altered["plan"]["source_sha256"] = {"changed.py": "0" * 64}
            with self.assertRaisesRegex(ValueError, "Frozen source mismatch"):
                trace.trace_capture(altered, directory, runtime=self.runtime)
        for field in ("request", "response"):
            altered = copy.deepcopy(capture)
            if field == "request":
                altered["calls"][0]["request"]["modelId"] = "changed"
            else:
                altered["calls"][1]["observation"]["response"]["text"] = "{}"
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.traced(altered)
        observer = trace.StageObserver(self.runtime, capture, trace.digest(capture))
        with self.assertRaisesRegex(ValueError, "no observed predecessor"):
            observer.identity({"prompt": self.helper.questions[0][0]["prompt"]})

    def test_profile_restored_on_success_and_replay_failure(self):
        capture = self.capture()
        original = sys.getprofile()
        def callback(frame, event, arg):
            pass
        try:
            sys.setprofile(callback)
            self.traced(capture)
            self.assertIs(sys.getprofile(), callback)
            with patch.object(self.runtime, "replay_capture", side_effect=ValueError("failure")), self.assertRaises(ValueError):
                self.traced(capture)
            self.assertIs(sys.getprofile(), callback)
        finally:
            sys.setprofile(original)

    def test_real_verifier_unwind_keeps_transport_failure_and_missing_return(self):
        def observer(request, **kwargs):
            state = self.helper.observer(request, **kwargs)
            call = json.loads((self.helper.output / "capture.json").read_text())["calls"][-1]
            if call["role"] == "solver":
                state = {"status": "operational_failure", "error_type": "ReadTimeoutError",
                         "provider_dispatch_attempted": True, "usage_known": False}
                kwargs["on_progress"](copy.deepcopy(state))
            return state
        capture = self.helper.run_trial(observer)
        self.assertEqual(capture["status"], "operational_failure")
        self.assertEqual(len(capture["calls"]), 2)
        result = self.traced(capture)
        self.assertEqual(result["verifications"][0]["return_state"], "unavailable")
        self.assertIsNone(result["verifications"][0]["returned"])

    def test_cached_bound_module_from_another_source_is_refused(self):
        capture = self.capture()
        for name in ("question_teaching", "verification_policy", "generation_diagnostics"):
            with self.subTest(module=name), patch.dict(sys.modules, {
                name: SimpleNamespace(__file__=f"/different/source/{name}.py"),
            }), self.assertRaisesRegex(ValueError, "fresh interpreter"):
                trace.trace_capture(capture, self.source, runtime=self.runtime)

    def test_undispatched_topoff_does_not_inherit_prior_reviewer_call(self):
        self.helper.modes[0] = "short"
        original = self.runtime._OperationContext.get_remaining_time_in_millis

        def clock(context):
            remaining = original(context)
            calls = json.loads((self.helper.output / "capture.json").read_text())["calls"]
            if (len(calls) == 3 and calls[-1]["lifecycle"] == "completed"
                    and context.result.get("arm") == "reviewer_written"
                    and context.result.get("case_id") == self.helper.plan["operations"][0]["case_id"]):
                context.result["remaining_milliseconds"][-1] = 0
                return 0
            return remaining

        with patch.object(self.runtime._OperationContext, "get_remaining_time_in_millis", clock):
            capture = self.capture()
        self.assertEqual(len(capture["operations"][0]["questions"]), 2)
        result = self.traced(capture)
        payloads = [p for p in result["author_payloads"] if p["operation_index"] == 0]
        self.assertEqual(len(payloads), 2)
        self.assertEqual(payloads[0]["call_indexes"], [0])
        self.assertEqual(payloads[1]["call_indexes"], [])
        self.assertIsNone(payloads[1]["call_index"])
        self.assertEqual(payloads[1]["return_state"], "unavailable")


if __name__ == "__main__":
    unittest.main()
