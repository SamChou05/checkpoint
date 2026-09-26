"""Socket-blocked draft request, capture and 20-slot projection tests."""

import copy
import importlib.util
import json
from pathlib import Path
import socket
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from botocore.exceptions import ReadTimeoutError


HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("prose_semantic_author_probe_tested", HERE / "author_probe.py")
probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(probe)


def question(index):
    return {"prompt": f"For the new Boolean case {index}, which value follows from the stated expression?",
            "choices": {"a": "one", "b": "two", "c": "three", "d": "four"},
            "correctChoice": "b", "explanation": "The supplied expression evaluates to two in this case.",
            "topic": "Python 3 Boolean expressions", "difficulty": 2, "format": "Multiple Choice"}


class Fake:
    def __init__(self, modify=None):
        self.modify = modify
        self.calls = []

    def factory(self, *args, **kwargs):
        return SimpleNamespace(
            meta=SimpleNamespace(config=kwargs["config"], endpoint_url=probe.ENDPOINT,
                                 region_name="us-east-1"), converse=self.converse)

    def converse(self, **request):
        index = len(self.calls)
        self.calls.append(copy.deepcopy(request))
        response = {"stopReason": "end_turn", "output": {"message": {"content": [
            {"text": json.dumps({"questions": [question(i) for i in range(5)]})}]}}}
        response["usage"] = {"inputTokens": 10, "outputTokens": 20}
        return self.modify(index, response) if self.modify else response


class ProseSemanticAuthorProbeTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, "connect",
                                       side_effect=AssertionError("No network in offline preflight")))
        self.enterContext(patch.object(probe.safe, "export_credentials",
                                       side_effect=AssertionError("No credential export in preflight")))
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "capture.json"
        self.plan = probe.build_plan()

    def run_fake(self, fake=None):
        fake = fake or Fake()
        return probe.run_calls(self.plan, self.path, fake.factory,
                               lambda: probe.check_plan(self.plan), clock=lambda: 1.0), fake

    def test_exact_requests_and_four_call_plan(self):
        self.assertEqual([(job["arm"], job["scope"]) for job in self.plan["calls"]], list(probe.ORDER))
        self.assertEqual(self.plan["limits"]["maximum_calls"], 4)
        self.assertEqual(self.plan["limits"]["requested_slots_total"], 20)
        criteria = self.plan["criteria"]
        self.assertEqual(criteria["candidate_usable_of_10"], 10)
        self.assertEqual(criteria["candidate_python_and_or_items"], 3)
        self.assertEqual(criteria["candidate_python_final_operand_items"], 1)
        self.assertEqual(criteria["candidate_python_skipped_operand_items"], 1)
        self.assertEqual(criteria["candidate_english_agreement_items"], 3)
        self.assertEqual(criteria["candidate_english_collective_items"], 1)
        self.assertEqual(criteria["candidate_english_reference_items"], 2)
        self.assertEqual(criteria["candidate_targeted_false_rule_or_ambiguous_distractor_count"], 0)
        self.assertTrue(criteria["observed_improvement_requires_baseline_targeted_defect"])
        self.assertTrue(criteria["candidate_usable_not_below_baseline_total_or_either_scope"])
        self.assertTrue(criteria["uncertainty_fails_item"])
        self.assertTrue(criteria["model_agreement_is_not_semantic_credit"])
        for base, candidate in ((0, 1), (3, 2)):
            a = self.plan["calls"][base]["request"]
            b = copy.deepcopy(self.plan["calls"][candidate]["request"])
            self.assertEqual(b["system"][0]["text"].replace(probe.suffix(), "", 1),
                             a["system"][0]["text"])
            b["system"] = a["system"]
            self.assertEqual(a, b)
            self.assertEqual(a["outputConfig"], b["outputConfig"])
            self.assertEqual(a["modelId"], probe.MODEL)
            self.assertEqual(a["inferenceConfig"], {"maxTokens": 16000})
        self.assertEqual(self.plan["contract"]["name"], probe.CONTRACT)
        self.assertTrue(self.plan["source_hashes"])

    def test_fake_capture_and_blind_projection_keep_twenty_slots(self):
        capture, fake = self.run_fake()
        self.assertEqual(len(fake.calls), 4)
        self.assertEqual(capture["summary"]["attempted_calls"], 4)
        self.assertEqual(capture["summary"]["baseline"]["normal_exact_five_calls"], 2)
        self.assertEqual(capture["summary"]["candidate"]["normal_exact_five_calls"], 2)
        self.assertEqual(capture["status"], "complete_pending_blind_review")
        self.assertEqual(probe.safe.strict_json(self.path.read_text()), capture)
        worksheet, mapping = probe.blind_projection(capture)
        self.assertEqual(len(worksheet["items"]), 20)
        self.assertEqual(len(mapping["items"]), 20)
        self.assertEqual(len({row["id"] for row in worksheet["items"]}), 20)
        self.assertTrue(all(row["shape"] == "readable" for row in worksheet["items"]))
        for item in worksheet["items"]:
            self.assertEqual(set(item), {"id", "prompt", "choices", "shape", "blind_review"})
            self.assertNotIn("correctChoice", item)
            self.assertNotIn("explanation", item)
            self.assertNotIn("arm", item)
        self.assertEqual(capture["summary"]["semantic_credit"], None)

    def test_timeout_consumes_one_scope_arm_without_retry_or_rescue(self):
        def fail_first(index, response):
            if index == 0:
                raise ReadTimeoutError(endpoint_url=probe.ENDPOINT)
            return response

        capture, fake = self.run_fake(Fake(fail_first))
        self.assertEqual(len(fake.calls), 4)
        self.assertEqual([row["runtime_budget_calls"] for row in capture["calls"]], [1, 1, 1, 1])
        self.assertEqual(capture["calls"][0]["status"], "failed")
        self.assertEqual(capture["summary"]["baseline"]["missing_or_failed_slots"], 5)
        self.assertEqual(capture["summary"]["candidate"]["normal_exact_five_calls"], 2)
        worksheet, _ = probe.blind_projection(capture)
        self.assertEqual(sum(row["shape"] == "missing_or_invalid" for row in worksheet["items"]), 5)

    def test_surplus_rows_never_replace_primary_slots(self):
        def surplus(index, response):
            content = response["output"]["message"]["content"][0]
            payload = json.loads(content["text"])
            payload["questions"].append(question(5))
            content["text"] = json.dumps(payload)
            return response

        capture, fake = self.run_fake(Fake(surplus))
        self.assertEqual(len(fake.calls), 4)
        self.assertTrue(all(len(row["raw_rows"]) == 6 for row in capture["calls"]))
        self.assertTrue(all(row["status"] == "failed" for row in capture["calls"]))
        worksheet, _ = probe.blind_projection(capture)
        self.assertEqual(len(worksheet["items"]), 20)

    def test_malformed_visible_json_is_omitted_and_does_not_retry(self):
        def malformed(index, response):
            if index == 0:
                response["output"]["message"]["content"][0]["text"] = (
                    '{"echo":"\\u0053ECRET-VALUE",')
            return response

        capture, fake = self.run_fake(Fake(malformed))
        self.assertEqual(len(fake.calls), 4)
        self.assertEqual(capture["calls"][0]["status"], "failed")
        self.assertNotIn("response", capture["calls"][0])
        self.assertNotIn("\\u0053ECRET-VALUE", self.path.read_text())
        self.assertNotIn("SECRET-VALUE", self.path.read_text())
        self.assertEqual(capture["summary"]["candidate"]["normal_exact_five_calls"], 2)

    def test_nonobject_provider_envelope_is_omitted_and_other_calls_continue(self):
        capture, fake = self.run_fake(Fake(lambda index, response: ["malformed"]
                                           if index == 0 else response))
        self.assertEqual(len(fake.calls), 4)
        self.assertEqual(capture["calls"][0]["status"], "failed")
        self.assertNotIn("response", capture["calls"][0])
        self.assertNotIn("malformed", self.path.read_text())
        self.assertEqual(capture["summary"]["candidate"]["normal_exact_five_calls"], 2)

    def test_credential_echo_stops_without_retaining_visible_secret(self):
        def echo(index, response):
            response["output"]["message"]["content"][0]["text"] = (
                '{"questions":[],"echo":"\\u0053ECRET-VALUE","echo":"safe"}')
            return response

        fake = Fake(echo)
        capture = probe.run_calls(self.plan, self.path, fake.factory,
                                  lambda: probe.check_plan(self.plan),
                                  secrets=("SECRET-VALUE",), clock=lambda: 1.0)
        self.assertEqual(len(fake.calls), 1)
        self.assertEqual(capture["status"], "globally_stopped")
        self.assertNotIn("\\u0053ECRET-VALUE", self.path.read_text())
        self.assertNotIn("SECRET-VALUE", self.path.read_text())

    def test_source_or_capture_tampering_aborts_before_dispatch(self):
        changed = copy.deepcopy(self.plan)
        changed["calls"][0]["request"]["modelId"] = "changed"
        with self.assertRaises(probe.IntegrityError):
            probe.check_plan(changed)
        fake = Fake()
        capture = probe.run_calls(changed, self.path, fake.factory, lambda: None,
                                  clock=lambda: 1.0)
        self.assertEqual(len(fake.calls), 0)
        self.assertEqual(capture["summary"]["attempted_calls"], 0)
        self.assertEqual(capture["status"], "globally_stopped")

    def test_source_drift_during_local_assessment_stops_before_next_dispatch(self):
        original = probe.visible_rows
        drifted = False

        def assess(response):
            nonlocal drifted
            rows = original(response)
            drifted = True
            return rows

        def check_pin():
            if drifted:
                raise probe.IntegrityError("Source drift during local assessment.")

        fake = Fake()
        with patch.object(probe, "visible_rows", side_effect=assess):
            capture = probe.run_calls(self.plan, self.path, fake.factory, check_pin,
                                      clock=lambda: 1.0)
        self.assertEqual(len(fake.calls), 1)
        self.assertEqual(capture["status"], "globally_stopped")
        self.assertEqual(capture["global_stop"], "source_or_capture_integrity")
        self.assertEqual(capture["calls"][0]["status"], "failed")
        self.assertEqual(capture["calls"][1]["status"], "unattempted")
        self.assertEqual(probe.safe.strict_json(self.path.read_text()), capture)

    def test_source_drift_at_final_completion_cannot_mark_review_pending(self):
        original = probe.summarize
        drifted = False

        def summarize(capture):
            nonlocal drifted
            result = original(capture)
            if "completed_at" in capture and all(
                row["status"] == "assessed" for row in capture["calls"]
            ):
                drifted = True
            return result

        def check_pin():
            if drifted:
                raise probe.IntegrityError("Source drift before final completion.")

        fake = Fake()
        with patch.object(probe, "summarize", side_effect=summarize):
            capture = probe.run_calls(self.plan, self.path, fake.factory, check_pin,
                                      clock=lambda: 1.0)
        self.assertEqual(len(fake.calls), 4)
        self.assertEqual(capture["status"], "globally_stopped")
        self.assertEqual(capture["global_stop"], "source_or_capture_integrity")
        self.assertEqual(capture["completion_error"]["type"], "IntegrityError")
        self.assertEqual(probe.safe.strict_json(self.path.read_text()), capture)

    def test_second_budget_reservation_stops_without_second_provider_call(self):
        original = probe.generate

        def second_reservation(job, client=None, budget=None):
            result = original(job, client, budget)
            budget.consume()
            return result

        fake = Fake()
        with patch.object(probe, "generate", side_effect=second_reservation):
            capture = probe.run_calls(self.plan, self.path, fake.factory, lambda: None,
                                      clock=lambda: 1.0)
        self.assertEqual(len(fake.calls), 1)
        self.assertEqual(capture["status"], "globally_stopped")
        self.assertEqual(capture["global_stop"], "attempted_budget_overrun")
        self.assertEqual(capture["calls"][0]["runtime_budget_calls"], 1)
        self.assertEqual(capture["calls"][0]["local_error"]["type"],
                         "ProviderCallBudgetExceededError")
        self.assertEqual(capture["calls"][1]["status"], "unattempted")
        self.assertEqual(probe.safe.strict_json(self.path.read_text()), capture)

    def test_reasoning_content_is_not_retained(self):
        def reasoning(index, response):
            response["output"]["message"]["content"].insert(
                0, {"reasoningContent": {"reasoningText": {"text": "PRIVATE-REASONING"}}})
            return response

        capture, _ = self.run_fake(Fake(reasoning))
        self.assertEqual(capture["status"], "complete_pending_blind_review")
        self.assertTrue(all(call["reasoning_blocks_omitted"] == 1 for call in capture["calls"]))
        self.assertNotIn("PRIVATE-REASONING", self.path.read_text())

    def test_setup_failure_is_durable_zero_call_and_cannot_resume(self):
        frozen = {**self.plan, "state": "frozen"}
        frozen_path = Path(self.temp.name) / "synthetic-frozen-plan.json"
        probe.save(frozen_path, frozen, exclusive=True)
        with (patch.object(probe, "PLAN", frozen_path), patch.object(probe, "CAPTURE", self.path),
              patch.object(probe.safe, "credential_session",
                           side_effect=RuntimeError("SECRET-VALUE must not be recorded"))):
            capture = probe.execute(probe.sha(frozen_path))
            self.assertEqual(capture["status"], "globally_stopped")
            self.assertEqual(capture["global_stop"], "credential_setup")
            self.assertEqual(capture["reviewed_frozen_plan_sha256"], probe.sha(frozen_path))
            self.assertEqual(capture["summary"]["attempted_calls"], 0)
            self.assertTrue(all(row["status"] == "unattempted" for row in capture["calls"]))
            self.assertEqual(probe.safe.strict_json(self.path.read_text()), capture)
            self.assertNotIn("SECRET-VALUE", self.path.read_text())
            with self.assertRaises(probe.IntegrityError):
                probe.execute(probe.sha(frozen_path))

    def test_final_writer_cannot_replace_tampered_capture(self):
        def tamper(index, response):
            self.path.write_text("TAMPERED CAPTURE")
            return response

        fake = Fake(tamper)
        with self.assertRaises(probe.IntegrityError):
            probe.run_calls(self.plan, self.path, fake.factory,
                            lambda: probe.check_plan(self.plan), clock=lambda: 1.0)
        self.assertEqual(len(fake.calls), 1)
        self.assertEqual(self.path.read_text(), "TAMPERED CAPTURE")


if __name__ == "__main__":
    unittest.main()
