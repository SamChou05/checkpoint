"""Offline check: exact modelId-only change and inherited three-call hard stop."""

import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import opus46_probe as probe


class Client:
    def __init__(self):
        self.calls = []

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": json.dumps({
            "audits": {str(i): {"reason": "Synthetic offline result; not actual provider evidence.", "verdict": "uncertain"}
                       for i in range(6)}})}]}}}


class OpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = probe.build_plan()

    def setUp(self):
        self.enterContext(patch.object(probe.original, "save"))
        self.enterContext(patch.object(probe.original.boto3, "client", side_effect=AssertionError("No SDK")))
        self.enterContext(patch.object(probe.subprocess, "check_output", side_effect=AssertionError("No credentials")))
        self.enterContext(patch("builtins.print"))

    def test_only_model_id_changes_exact_requests_and_gold_criteria(self):
        source = json.loads(probe.shared.PLAN.read_text())
        self.assertEqual(self.plan["cases"], source["cases"])
        self.assertEqual(self.plan["prospective_criteria"], source["prospective_criteria"])
        self.assertEqual(self.plan["limits"], source["limits"])
        for call, old in zip(self.plan["calls"], source["calls"], strict=True):
            request = copy.deepcopy(call["provider_request"])
            self.assertEqual(request["modelId"], probe.MODEL)
            request["modelId"] = old["provider_request"]["modelId"]
            self.assertEqual(request, old["provider_request"])
        self.assertNotEqual(probe.PLAN, probe.shared.PLAN)
        self.assertNotEqual(probe.CAPTURE, probe.shared.CAPTURE)

    def test_three_calls_then_hard_ceiling_with_no_semantic_repair(self):
        client, capture = Client(), {"calls": []}
        plan = copy.deepcopy(self.plan)
        plan["calls"].append(plan["calls"][0])
        with self.assertRaisesRegex(RuntimeError, "Three-call"):
            probe.shared.run_calls(client, plan, capture, Path("/unused"))
        self.assertEqual(len(client.calls), 3)
        self.assertEqual(sum(len(row["assessment"]["items"]) for row in capture["calls"]), 18)
        self.assertTrue(all(not item["matching_disposition"] for row in capture["calls"] for item in row["assessment"]["items"]))


if __name__ == "__main__":
    unittest.main()
