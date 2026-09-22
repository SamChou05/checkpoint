"""Offline prompt isolation, independent-input hiding, and exact four-call bounds."""

import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import adversarial_probe as probe


class Client:
    def __init__(self, respond):
        self.calls, self.respond = [], respond

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return self.respond(request)


class AdversarialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = probe.build_plan()

    def setUp(self):
        self.enterContext(patch.object(probe.original, "save"))
        self.enterContext(patch.object(probe.original.boto3, "client", side_effect=AssertionError("No SDK")))
        self.enterContext(patch.object(probe.subprocess, "check_output", side_effect=AssertionError("No credentials")))
        self.enterContext(patch("builtins.print"))

    def response(self, request, mutate=None):
        cases = {probe.original.contract.content_digest(case["learner_item"]): case for case in self.plan["cases"]}
        rows = {}
        for slot, item in probe.original.user_data(request)["items"].items():
            case = cases[probe.original.contract.content_digest(item)]
            rows[slot] = {"reason": "Synthetic offline result; requires independent semantic audit.",
                          "verdict": {"accept": "accepted", "reject": "rejected"}[case["gold"]["required_gate_decision"]]}
        if mutate:
            mutate(rows)
        return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": json.dumps({"audits": rows})}]}}}

    def test_original18_content_order_gold_and_only_prompt_delta(self):
        source = json.loads(probe.source_probe.PLAN.read_text())
        self.assertEqual(self.plan["cases"][:18], source["cases"])
        prompt = (probe.HERE / "auditor-adversarial-prompt-proposal.txt").read_text().removesuffix("\n")
        for call, old in zip(self.plan["calls"][:3], source["calls"], strict=True):
            request = copy.deepcopy(call["provider_request"])
            self.assertEqual(request["system"], [{"text": prompt}])
            request["system"] = old["provider_request"]["system"]
            self.assertEqual(request, old["provider_request"])

    def test_fresh_six_are_exact_payloads_with_no_gold_labels_or_prompt_instructions(self):
        call = self.plan["calls"][3]
        data = probe.original.user_data(call["provider_request"])
        self.assertEqual(set(data), {"goal", "skillMap", "sourceDocuments", "items"})
        expected = [case for case in self.plan["cases"] if case["batch"] == 3]
        self.assertEqual(len(expected), 6)
        self.assertEqual(data["items"], {case["slot"]: case["learner_item"] for case in expected})
        self.assertEqual(sum(case["gold"]["required_gate_decision"] == "accept" for case in expected), 3)
        for item in data["items"].values():
            self.assertEqual(set(item), {"prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations"})
            self.assertEqual(set(item["choices"]), set(item["choiceExplanations"]))
        check = copy.deepcopy(call["provider_request"])
        check["messages"] = self.plan["calls"][0]["provider_request"]["messages"]
        self.assertEqual(check, self.plan["calls"][0]["provider_request"])

    def test_four_fake_calls_produce24_pending_results(self):
        client, capture = Client(self.response), {"calls": []}
        probe.run_calls(client, self.plan, capture, Path("/unused"))
        self.assertEqual(len(client.calls), 4)
        items = [item for row in capture["calls"] for item in row["assessment"]["items"]]
        self.assertEqual(len(items), 24)
        self.assertTrue(all(item["matching_disposition"] for item in items))
        self.assertTrue(all(item["reason_manual_audit"] == "pending" for item in items))

    def test_extra_call_or_nonfresh_capture_blocked_before_dispatch(self):
        expanded = copy.deepcopy(self.plan)
        expanded["calls"].append(expanded["calls"][0])
        for plan, capture in ((expanded, {"calls": []}), (self.plan, {"calls": [{}]})):
            client = Client(self.response)
            with self.assertRaisesRegex(ValueError, "Exactly four"):
                probe.run_calls(client, plan, capture, Path("/unused"))
            self.assertEqual(client.calls, [])

    def test_transport_truncation_and_length_failure_stop_without_retries(self):
        def timeout(_request):
            raise TimeoutError("synthetic")

        for respond in (timeout, lambda _: {"stopReason": "max_tokens"},
                        lambda request: self.response(request, lambda rows: rows["0"].update(reason="x" * 601))):
            client, capture = Client(respond), {"calls": []}
            probe.run_calls(client, self.plan, capture, Path("/unused"))
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["status"], "stopped_after_failure")

    def test_semantic_miss_no_extra_calls_or_rescue(self):
        client = Client(lambda request: self.response(request, lambda rows: rows["0"].update(verdict="uncertain")))
        capture = {"calls": []}
        probe.run_calls(client, self.plan, capture, Path("/unused"))
        self.assertEqual(len(client.calls), 4)
        self.assertEqual(sum(not item["matching_disposition"] for row in capture["calls"] for item in row["assessment"]["items"]), 4)


if __name__ == "__main__":
    unittest.main()
