"""Offline singleton request parity, native identity and hard dispatch bounds."""

import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import isolation_probe as probe


class Client:
    def __init__(self, respond):
        self.calls, self.respond = [], respond

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return self.respond(request)


class IsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = probe.build_plan()

    def setUp(self):
        self.enterContext(patch.object(probe.original, "save"))
        self.enterContext(patch.object(probe.original.boto3, "client", side_effect=AssertionError("No SDK")))
        self.enterContext(patch.object(probe.subprocess, "check_output", side_effect=AssertionError("No credentials")))
        self.enterContext(patch("builtins.print"))

    def response(self, request, mutate=None):
        payload = probe.original.user_data(request)["items"]["0"]
        case = next(case for case in self.plan["cases"] if case["learner_item"] == payload)
        rows = {"0": {"reason": "Synthetic offline judgment; semantic audit remains required.",
                      "verdict": {"accept": "accepted", "reject": "rejected"}[case["gold"]["required_gate_decision"]]}}
        if mutate:
            mutate(rows)
        return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": json.dumps({"audits": rows})}]}}}

    def test_exact_payloads_gold_order_prompt_scope_and_settings(self):
        source = json.loads(probe.source_probe.PLAN.read_text())
        source_call = source["calls"][2]
        request = source_call["provider_request"]
        expected_cases = [next(case for case in source["cases"] if case["case_id"] == case_id)
                          for case_id in source_call["case_ids"]]
        self.assertEqual(self.plan["cases"], expected_cases)
        self.assertEqual(len(self.plan["calls"]), 6)
        for index, call in enumerate(self.plan["calls"]):
            actual = call["provider_request"]
            self.assertEqual(call["case_ids"], [expected_cases[index]["case_id"]])
            data = probe.original.user_data(actual)
            old_data = probe.original.user_data(request)
            self.assertEqual(data.pop("items"), {"0": expected_cases[index]["learner_item"]})
            old_data.pop("items")
            self.assertEqual(data, old_data)
            self.assertEqual(set(data), {"goal", "skillMap", "sourceDocuments"})
            expected = copy.deepcopy(request)
            expected["messages"] = actual["messages"]
            expected["outputConfig"] = probe.original.contract.output_config(1)
            self.assertEqual(actual, expected)
            self.assertEqual(call["request_sha256"], probe.original.sha(probe.original.canonical(actual)))
            self.assertEqual(actual["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(actual["additionalModelRequestFields"], {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}})

    def test_six_successes_have_one_exact_identity_and_unchanged_admission(self):
        client = Client(self.response)
        capture = {"calls": []}
        probe.run_calls(client, self.plan, capture, Path("unused"))
        self.assertEqual(len(client.calls), 6)
        self.assertEqual(capture["status"], "complete_pending_manual_audit")
        self.assertEqual(sum(row["assessment"]["items"][0]["matching_disposition"] for row in capture["calls"]), 6)
        self.assertEqual(sum(len(row["assessment"]["accepted_content_hashes"]) for row in capture["calls"]), 3)
        self.assertTrue(all(row["assessment"]["originals_unchanged"] for row in capture["calls"]))
        self.assertTrue(all(list(row["assessment"]["audits"]) == ["0"] for row in capture["calls"]))

    def test_expanded_or_resumed_capture_rejected_before_dispatch(self):
        client = Client(self.response)
        expanded = copy.deepcopy(self.plan)
        expanded["calls"].append(copy.deepcopy(expanded["calls"][0]))
        for plan, capture in ((expanded, {"calls": []}), (self.plan, {"calls": [{}]})):
            with self.assertRaises(ValueError):
                probe.run_calls(client, plan, capture, Path("unused"))
        self.assertEqual(client.calls, [])

    def test_transport_and_non_end_stop_once_without_retry(self):
        def failure(_):
            raise TimeoutError("Synthetic timeout")
        def truncated(request):
            result = self.response(request)
            result["stopReason"] = "max_tokens"
            return result
        for respond, expected in ((failure, "transport_failure"), (truncated, "non_end_turn")):
            client, capture = Client(respond), {"calls": []}
            probe.run_calls(client, self.plan, capture, Path("unused"))
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["stop_reason"], expected)
            self.assertEqual(capture["status"], "stopped_after_failure")
            self.assertNotIn("assessment", capture["calls"][0])

    def test_reason_bound_unknown_identity_and_duplicate_json_stop(self):
        responders = [
            lambda request: self.response(request, lambda rows: rows["0"].update(reason="x" * 601)),
            lambda request: self.response(request, lambda rows: rows.update({"1": copy.deepcopy(rows["0"])})),
            lambda request: self.response(request, lambda rows: rows["0"].update(verdict="repair")),
        ]
        duplicate = '{"audits":{"0":{"reason":"Valid bounded text.","verdict":"accepted"},"0":{"reason":"Valid bounded text.","verdict":"accepted"}}}'
        responders.append(lambda _: {"stopReason": "end_turn", "output": {"message": {"content": [{"text": duplicate}]}}})
        for respond in responders:
            client, capture = Client(respond), {"calls": []}
            probe.run_calls(client, self.plan, capture, Path("unused"))
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["stop_reason"], "structural_failure")
            self.assertNotIn("assessment", capture["calls"][0])

    def test_semantic_miss_preserved_and_reasoning_redacted(self):
        def respond(request):
            result = self.response(request, lambda rows: rows["0"].update(verdict="accepted"))
            result["output"]["message"]["content"].append({"reasoningContent": {"reasoningText": {"text": "Do not save", "signature": "Do not save"}}})
            return result
        client, capture = Client(respond), {"calls": []}
        probe.run_calls(client, self.plan, capture, Path("unused"))
        self.assertEqual(len(client.calls), 6)
        self.assertEqual(sum(row["assessment"]["items"][0]["matching_disposition"] for row in capture["calls"]), 3)
        self.assertEqual(sum(row["reasoning_blocks_omitted"] for row in capture["calls"]), 6)
        self.assertNotIn("reasoningContent", json.dumps(capture))
        self.assertNotIn("Do not save", json.dumps(capture))

    def test_execute_uses_one_sdk_attempt_and_exact_timeouts(self):
        created = []
        def factory(*args, **kwargs):
            client = Client(self.response)
            client.meta = SimpleNamespace(config=kwargs["config"])
            created.append(client)
            return client
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "plan.json"
            path.write_text(json.dumps(self.plan))
            with patch.object(probe, "PLAN", path), patch.object(probe, "build_plan", return_value=self.plan), \
                    patch.object(probe.subprocess, "check_output", return_value=b'{"AccessKeyId":"synthetic","SecretAccessKey":"synthetic"}') as credentials, \
                    patch.object(probe.original.boto3, "client", side_effect=factory) as sdk:
                probe.execute(probe.original.sha(path.read_bytes()))
            self.assertEqual(credentials.call_count, 1)
            self.assertEqual(sdk.call_count, 1)
            self.assertEqual(len(created[0].calls), 6)
            config = created[0].meta.config
            self.assertEqual((config.connect_timeout, config.read_timeout, config.retries["total_max_attempts"]), (3, 75, 1))


if __name__ == "__main__":
    unittest.main()
