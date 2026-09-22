"""Deterministic fake-provider checks; no live credential or network operations."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("verifier_model_probe_test", HERE / "verifier_model_probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class FakeClient:
    def __init__(self, respond):
        self.respond, self.calls = respond, []

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return self.respond(request)


class VerifierModelProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = probe.build_plan(require_review=False)
        cls.packet = json.loads((HERE / "controls-draft.json").read_text())
        cls.gold = {case["historical_item"]["prompt"]: case["gold"] for case in cls.packet["cases"]}

    def setUp(self):
        self.enterContext(patch.object(probe.boto3, "client", side_effect=AssertionError("No SDK setup in tests")))
        self.enterContext(patch.object(probe.subprocess, "check_output", side_effect=AssertionError("No credentials in tests")))
        self.enterContext(patch.object(probe, "save"))

    def response(self, request, mutate=None):
        rows = []
        for item in probe.input_payload(request)["items"]:
            gold = self.gold[item["prompt"]]
            rows.append({"index": item["index"], "valid": gold["eligible"], "answer": gold["answer"] or "",
                         "difficulty": 2 if gold["eligible"] else 0,
                         "explanation": "Offline explanation fixture; semantic quality remains unassessed." if gold["eligible"] else "",
                         "choiceFeedback": [{"choice": choice, "explanation": "Offline feedback fixture with sufficient bounds."}
                                            for choice in item["choices"]] if gold["eligible"] else []})
        if mutate:
            mutate(rows)
        return {"stopReason": "end_turn", "usage": {"inputTokens": 1, "outputTokens": 1},
                "output": {"message": {"content": [{"text": json.dumps({"reviews": rows})}]}}}

    def fake_run(self, respond, plan=None):
        client, capture = FakeClient(respond), {"calls": []}
        probe.run_calls(client, plan or self.plan, self.packet, capture, Path("/unused"))
        return client, capture

    def test_only_model_id_changes_in_each_pair(self):
        self.assertEqual([(call["batch"], call["arm"]) for call in self.plan["calls"]],
                         [(0, "sonnet"), (0, "opus"), (1, "opus"), (1, "sonnet")])
        for batch in (0, 1):
            pair = [copy.deepcopy(call["provider_request"]) for call in self.plan["calls"] if call["batch"] == batch]
            for request in pair:
                request.pop("modelId")
                self.assertEqual(request["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})
                self.assertEqual(request["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})
            self.assertEqual(*pair)

    def test_historical_choice_and_reason_bytes_preserved_gold_hidden(self):
        for batch in (0, 1):
            data = probe.payload(self.packet, batch)
            cases = [case for case in self.packet["cases"] if case["batch"] == batch]
            for index, case in enumerate(cases):
                for key, historical in [("items", "historical_item"), ("independentSolutions", "historical_independent_solution")]:
                    expected = copy.deepcopy(case[historical])
                    expected["index"] = index
                    self.assertEqual(data[key][index], expected)
            for item in data["items"]:
                self.assertNotIn("expectedAnswer", item)
                self.assertNotIn("explanation", item)
                self.assertNotIn("gold", item)
            self.assertEqual(len(data["items"]), 3)

    def test_four_calls_exactly_once_and_manual_semantics_pending(self):
        client, capture = self.fake_run(self.response)
        self.assertEqual(client.calls, [call["provider_request"] for call in self.plan["calls"]])
        self.assertEqual(capture["status"], "complete_pending_manual_audit")
        self.assertEqual(len(capture["calls"]), 4)
        self.assertTrue(all(item["matching_disposition"] for row in capture["calls"] for item in row["assessment"]["items"]))

    def test_fifth_call_is_locally_blocked(self):
        plan = copy.deepcopy(self.plan)
        plan["calls"].append(plan["calls"][0])
        client = FakeClient(self.response)
        capture = {"calls": []}
        with self.assertRaisesRegex(RuntimeError, "Four-call"):
            probe.run_calls(client, plan, self.packet, capture, Path("/unused"))
        self.assertEqual(len(client.calls), 4)

    def test_transport_and_truncation_stop_after_one_attempt(self):
        def timeout(_request):
            raise TimeoutError("synthetic")

        for respond in (timeout, lambda _: {"stopReason": "max_tokens"}):
            client, capture = self.fake_run(respond)
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["status"], "stopped_after_failure")

    def test_invalid_index_schema_and_positive_coverage_stop(self):
        for mutate in (lambda rows: rows.pop(), lambda rows: rows[0].update(index=-1),
                       lambda rows: rows[0].update(index=True), lambda rows: rows[1].update(index=0),
                       lambda rows: rows[0].update(extra="wrong"), lambda rows: rows[-1]["choiceFeedback"].pop()):
            client, capture = self.fake_run(lambda request: self.response(request, mutate))
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["stop_reason"], "structural_failure")
            self.assertIn("response", capture["calls"][0])

    def test_mismatching_semantic_disposition_is_retained_without_extra_calls(self):
        def reject_valid(rows):
            rows[-1].update(valid=False, answer="", explanation="", choiceFeedback=[], difficulty=0)

        client, capture = self.fake_run(lambda request: self.response(request, reject_valid))
        self.assertEqual(len(client.calls), 4)
        self.assertFalse(capture["calls"][0]["assessment"]["items"][-1]["matching_disposition"])

    def test_duplicate_json_fields_fail_in_real_native_adapter(self):
        def duplicate(request):
            response = self.response(request)
            block = response["output"]["message"]["content"][0]
            block["text"] = block["text"].replace('"index": 0', '"index": 0, "index": 0', 1)
            return response

        client, capture = self.fake_run(duplicate)
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(capture["stop_reason"], "structural_failure")

    def test_reasoning_blocks_never_retained(self):
        response = self.response(self.plan["calls"][0]["provider_request"])
        response["output"]["message"]["content"].insert(0, {"reasoningContent": {"reasoningText": {"text": "synthetic", "signature": "synthetic"}}})
        retained, count = probe.redacted(response)
        self.assertEqual(count, 1)
        self.assertNotIn("reasoningContent", retained["output"]["message"]["content"][0])
        self.assertIn("reasoningContent", response["output"]["message"]["content"][0])


if __name__ == "__main__":
    unittest.main()
