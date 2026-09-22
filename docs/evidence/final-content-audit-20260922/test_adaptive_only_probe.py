"""No-network checks of exact replayed requests and new bounded denominator."""

import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import adaptive_only_probe as probe


class FakeClient:
    def __init__(self, respond):
        self.calls, self.respond = [], respond

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return self.respond(request)


class AdaptiveOnlyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = probe.build_plan()

    def setUp(self):
        self.enterContext(patch.object(probe.original, "save"))
        self.enterContext(patch.object(probe.original.boto3, "client", side_effect=AssertionError("No SDK client")))
        self.enterContext(patch.object(probe.subprocess, "check_output", side_effect=AssertionError("No credentials")))
        self.enterContext(patch("builtins.print"))

    def response(self, request, mutate=None):
        cases = {probe.original.contract.content_digest(case["learner_item"]): case for case in self.plan["cases"]}
        rows = {}
        for slot, item in probe.original.user_data(request)["items"].items():
            case = cases[probe.original.contract.content_digest(item)]
            rows[slot] = {"reason": "Synthetic test evidence; independent semantic review required.",
                          "verdict": {"accept": "accepted", "reject": "rejected"}[case["gold"]["required_gate_decision"]]}
        if mutate:
            mutate(rows)
        return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": json.dumps({"audits": rows})}]}}}

    def test_exact_old_adaptive_requests_and_all_gold_preserved(self):
        old = json.loads(probe.original.PLAN.read_text())
        self.assertEqual(self.plan["cases"], old["cases"])
        self.assertEqual(self.plan["prospective_criteria"], old["prospective_criteria"])
        self.assertEqual([call["source_sequence"] for call in self.plan["calls"]], [1, 2, 5])
        for call in self.plan["calls"]:
            self.assertEqual(call["provider_request"], old["calls"][call["source_sequence"]]["provider_request"])
            self.assertEqual(call["request_sha256"], old["calls"][call["source_sequence"]]["request_sha256"])
        self.assertNotEqual(probe.PLAN, probe.original.PLAN)
        self.assertNotEqual(probe.CAPTURE, probe.original.CAPTURE)

    def test_three_calls_complete_18_items_without_network(self):
        client, capture = FakeClient(self.response), {"calls": []}
        probe.run_calls(client, self.plan, capture, Path("/unused"))
        self.assertEqual(len(client.calls), 3)
        self.assertEqual(capture["status"], "complete_pending_manual_audit")
        self.assertEqual(sum(len(row["assessment"]["items"]) for row in capture["calls"]), 18)

    def test_fourth_call_blocked(self):
        plan = copy.deepcopy(self.plan)
        plan["calls"].append(plan["calls"][0])
        client, capture = FakeClient(self.response), {"calls": []}
        with self.assertRaisesRegex(RuntimeError, "Three-call"):
            probe.run_calls(client, plan, capture, Path("/unused"))
        self.assertEqual(len(client.calls), 3)

    def test_first_provider_stop_or_local_reason_failure_stops_all(self):
        def timeout(_request):
            raise TimeoutError("synthetic")

        for respond in (timeout, lambda _: {"stopReason": "max_tokens"},
                        lambda request: self.response(request, lambda rows: rows["0"].update(reason="x" * 601))):
            client, capture = FakeClient(respond), {"calls": []}
            probe.run_calls(client, self.plan, capture, Path("/unused"))
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["status"], "stopped_after_failure")

    def test_semantic_failure_retains_planned_denominator_no_repair(self):
        client = FakeClient(lambda request: self.response(request, lambda rows: rows["0"].update(verdict="uncertain")))
        capture = {"calls": []}
        probe.run_calls(client, self.plan, capture, Path("/unused"))
        self.assertEqual(len(client.calls), 3)
        self.assertTrue(any(not item["matching_disposition"] for row in capture["calls"] for item in row["assessment"]["items"]))


if __name__ == "__main__":
    unittest.main()
