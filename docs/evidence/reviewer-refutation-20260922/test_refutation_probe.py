"""No-network tests of isolation, gold hiding, frozen schema and stop/count rules."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("refutation_probe_test", HERE / "refutation_probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class FakeClient:
    def __init__(self, respond):
        self.calls, self.respond = [], respond

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return self.respond(request)


class RefutationProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = probe.build_plan()
        cls.gold = {case["item"]["prompt"]: case["gold"] for case in cls.plan["cases"]}

    def setUp(self):
        self.enterContext(patch.object(probe, "save"))
        self.enterContext(patch.object(probe.boto3, "client", side_effect=AssertionError("No SDK setup")))
        self.enterContext(patch.object(probe.subprocess, "check_output", side_effect=AssertionError("No credential access")))
        self.enterContext(patch("builtins.print"))

    def response(self, request, mutate=None):
        rows = []
        for item in probe.user_data(request)["items"]:
            gold = self.gold[item["prompt"]]
            rows.append({"index": item["index"], "valid": gold["eligible"], "answer": gold["answer"] or "",
                         "difficulty": 2 if gold["eligible"] else 0,
                         "explanation": "Offline fixture only; actual semantic audit remains required." if gold["eligible"] else "",
                         "choiceFeedback": [{"choice": choice, "explanation": "Offline feedback fixture with adequate length."}
                                            for choice in item["choices"]] if gold["eligible"] else []})
        if mutate:
            mutate(rows)
        return {"stopReason": "end_turn", "usage": {"inputTokens": 1, "outputTokens": 1},
                "output": {"message": {"content": [{"text": json.dumps({"reviews": rows})}]}}}

    def fake_run(self, respond, plan=None):
        client, capture = FakeClient(respond), {"calls": []}
        probe.run_calls(client, plan or self.plan, capture, Path("/unused"))
        return client, capture

    def test_only_selected_system_span_changes(self):
        self.assertEqual([(call["batch"], call["arm"]) for call in self.plan["calls"]],
                         [(0, "baseline"), (0, "candidate"), (1, "candidate"), (1, "baseline")])
        for batch in (0, 1):
            pair = {call["arm"]: copy.deepcopy(call["provider_request"]) for call in self.plan["calls"] if call["batch"] == batch}
            baseline = pair["baseline"]["system"][0]["text"]
            candidate = pair["candidate"]["system"][0]["text"]
            span = (HERE / "baseline-paragraph.txt").read_text().removesuffix("\n")
            replacement = (HERE / "candidate-paragraph.txt").read_text().removesuffix("\n")
            before, after = baseline.split(span)
            self.assertEqual(candidate, before + replacement + after)
            self.assertIn("NATIVE TRANSPORT OVERRIDE", after)
            pair["baseline"]["system"][0]["text"] = candidate
            self.assertEqual(pair["baseline"], pair["candidate"])

    def test_runtime_source_not_imported_or_bound(self):
        self.assertNotIn("question_generation", sys.modules)
        self.assertNotIn("question_verification", sys.modules)
        self.assertTrue(all(path.startswith("docs/evidence/reviewer-refutation-20260922/") for path in probe.sources()))
        self.assertEqual(self.plan["native_contract"]["sha256"], "77c15c631555d0d83bfaa2e0ba1c19478c51d2573586220cce2ce94684bfe2fe")

    def test_exact_six_items_and_fixture_bytes_gold_hidden(self):
        for call in self.plan["calls"]:
            data = probe.user_data(call["provider_request"])
            expected = [case for case in self.plan["cases"] if case["batch"] == call["batch"]]
            self.assertEqual(data["items"], [case["item"] for case in expected])
            self.assertEqual(data["independentSolutions"], [case["solution"] for case in expected])
            self.assertEqual([item["index"] for item in data["items"]], list(range(6)))
            self.assertNotIn("gold", data)
            self.assertNotIn("provenance", data)
            for item in data["items"]:
                self.assertNotIn("answer", item)
                self.assertNotIn("expectedAnswer", item)
                self.assertNotIn("explanation", item)
            self.assertEqual(call["provider_request"]["modelId"], probe.MODEL)
            self.assertEqual(call["provider_request"]["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})

    def test_four_fake_calls_complete_once_with_semantics_pending(self):
        client, capture = self.fake_run(self.response)
        self.assertEqual(client.calls, [call["provider_request"] for call in self.plan["calls"]])
        self.assertEqual(capture["status"], "complete_pending_manual_audit")
        self.assertEqual(sum(len(call["assessment"]["items"]) for call in capture["calls"]), 24)
        self.assertTrue(all(item["matching_disposition"] for call in capture["calls"] for item in call["assessment"]["items"]))

    def test_fifth_call_blocked_and_sdk_limits_fixed(self):
        plan = copy.deepcopy(self.plan)
        plan["calls"].append(plan["calls"][0])
        client, capture = FakeClient(self.response), {"calls": []}
        with self.assertRaisesRegex(RuntimeError, "Four-call"):
            probe.run_calls(client, plan, capture, Path("/unused"))
        self.assertEqual(len(client.calls), 4)
        config = probe.Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1})
        self.assertEqual((config.connect_timeout, config.read_timeout, config.retries["total_max_attempts"]), (3, 75, 1))

    def test_transport_and_truncation_stop_without_retry(self):
        def timeout(_request):
            raise TimeoutError("synthetic")

        for respond in (timeout, lambda _: {"stopReason": "max_tokens"}):
            client, capture = self.fake_run(respond)
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["status"], "stopped_after_failure")

    def test_bad_coverage_types_schema_and_positive_feedback_stop(self):
        for mutate in (lambda rows: rows.pop(), lambda rows: rows[0].update(index=-1),
                       lambda rows: rows[1].update(index=0), lambda rows: rows[0].update(index=True),
                       lambda rows: rows[0].update(extra="wrong"), lambda rows: rows[2]["choiceFeedback"].pop(),
                       lambda rows: rows[2].update(explanation="short")):
            client, capture = self.fake_run(lambda request: self.response(request, mutate))
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["stop_reason"], "structural_failure")
            self.assertIn("response", capture["calls"][0])

    def test_false_rejection_is_failure_without_repair(self):
        def reject_valid(rows):
            rows[2].update(valid=False, answer="", explanation="", choiceFeedback=[], difficulty=0)

        client, capture = self.fake_run(lambda request: self.response(request, reject_valid))
        self.assertEqual(len(client.calls), 4)
        self.assertFalse(capture["calls"][0]["assessment"]["items"][2]["matching_disposition"])

    def test_duplicate_json_key_rejected_by_frozen_native_adapter(self):
        def duplicate(request):
            response = self.response(request)
            block = response["output"]["message"]["content"][0]
            block["text"] = block["text"].replace('"index": 0', '"index": 0, "index": 0', 1)
            return response

        client, capture = self.fake_run(duplicate)
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(capture["stop_reason"], "structural_failure")

    def test_reasoning_text_and_signature_not_retained(self):
        response = self.response(self.plan["calls"][0]["provider_request"])
        response["output"]["message"]["content"].insert(0, {"reasoningContent": {"reasoningText": {"text": "synthetic", "signature": "synthetic"}}})
        saved, count = probe.safe_response(response)
        self.assertEqual(count, 1)
        self.assertNotIn("reasoningContent", saved["output"]["message"]["content"][0])
        self.assertIn("reasoningContent", response["output"]["message"]["content"][0])


if __name__ == "__main__":
    unittest.main()
