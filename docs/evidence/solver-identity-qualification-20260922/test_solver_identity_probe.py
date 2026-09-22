"""Offline request isolation, actual decoder fidelity and two-call hard limits."""

import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import solver_identity_probe as probe


class Client:
    def __init__(self, respond):
        self.respond, self.calls = respond, []

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return self.respond(request)


class SolverIdentityProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = probe.build_plan()

    def setUp(self):
        self.enterContext(patch.object(probe, "save"))
        self.enterContext(patch.object(probe.boto3, "client", side_effect=AssertionError("No SDK")))
        self.enterContext(patch.object(probe.subprocess, "check_output", side_effect=AssertionError("No credentials")))
        self.enterContext(patch("builtins.print"))

    def response(self, request, mutate=None):
        cases = {case["prompt"]: case for case in self.plan["controls"]}
        rows = {}
        for item in probe.user_data(request)["items"]:
            case = cases[item["prompt"]]
            equivalents = {frozenset(pair) for pair in case["equivalentPairs"]}
            rows[str(item["index"])] = {
                "choices": {slot: {"reason": f"  Synthetic gold for {slot}; not a provider judgment.\n",
                                   "judgment": "supported" if choice in case["supportedChoices"] else "refuted"}
                            for slot, choice in item["choices"].items()},
                "choicePairs": {slot: {"reason": f"  Synthetic exact pair {slot}.\n",
                                       "relation": "equivalent" if frozenset(endpoints.values()) in equivalents else "distinct"}
                                for slot, endpoints in item["choicePairs"].items()},
            }
        if mutate:
            mutate(rows)
        return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": json.dumps({"solutions": rows})}]}}}

    def test_first_two_requests_only_change_native_identity_envelope(self):
        previous = json.loads((probe.SOURCE / "adaptive-plan.json").read_text())
        for job, old in zip(self.plan["jobs"], previous["jobs"][:2], strict=True):
            changed = copy.deepcopy(job["request"])
            changed["system"], changed["outputConfig"] = old["request"]["system"], old["request"]["outputConfig"]
            self.assertEqual(changed, old["request"])
            self.assertEqual(job["items"], old["items"])
            self.assertEqual(job["case_ids"], old["case_ids"])
            self.assertTrue(job["request"]["system"][0]["text"].startswith(old["request"]["system"][0]["text"] + "\n\nNATIVE SOLVER IDENTITY OVERRIDE"))
            self.assertEqual(job["request"]["outputConfig"], probe.native.native_output_config(probe.native.SolverSlotContract(5)))
            self.assertEqual(job["request"]["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(job["request"]["additionalModelRequestFields"], {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}})
            self.assertNotIn("expectedAnswer", json.dumps(probe.user_data(job["request"])))
            self.assertNotIn("supportedChoices", json.dumps(probe.user_data(job["request"])))
        ids = [case_id for job in previous["jobs"][:2] for case_id in job["case_ids"]]
        self.assertEqual(self.plan["controls"], [next(case for case in previous["controls"] if case["id"] == case_id) for case_id in ids])

    def test_actual_adapter_and_local_decoder_keep_all_content_and_endpoints(self):
        for job in self.plan["jobs"]:
            raw = self.response(job["request"])["output"]["message"]["content"][0]["text"]
            rows = json.loads(raw)["solutions"]
            reversed_raw = json.dumps({"solutions": dict(reversed(list(rows.items())))})
            result = probe.assess(reversed_raw, job, self.plan)
            self.assertTrue(result["structural_valid"])
            self.assertEqual((result["trusted_identities"], result["choice_slots"], result["pair_slots"]), (5, 20, 30))
            self.assertTrue(result["exact_bindings_and_decoded_content"])
            self.assertTrue(all(row["all_gold_agrees"] for row in result["semantic_rows"]))
            self.assertEqual(result["choice_reason_before_judgment_rows"], 20)
            self.assertEqual(result["pair_reason_before_relation_rows"], 30)
            self.assertEqual(result["decoded"], {"solutions": [{"index": index, **rows[str(index)]} for index in range(5)]})

    def test_two_calls_only_and_expanded_or_resumed_trials_refused(self):
        client, capture = Client(self.response), {"calls": []}
        probe.run_calls(client, self.plan, capture, Path("unused"))
        self.assertEqual(len(client.calls), 2)
        self.assertEqual(capture["status"], "complete_pending_independent_audit")
        expanded = copy.deepcopy(self.plan)
        expanded["jobs"].append(copy.deepcopy(expanded["jobs"][0]))
        for plan, previous in ((expanded, {"calls": []}), (self.plan, {"calls": [{}]})):
            blocked = Client(self.response)
            with self.assertRaises(ValueError):
                probe.run_calls(blocked, plan, previous, Path("unused"))
            self.assertEqual(blocked.calls, [])

    def test_semantic_miss_does_not_change_structural_credit_or_create_retry(self):
        def wrong(request):
            def mutate(rows):
                for row in rows.values():
                    for choice in row["choices"].values():
                        choice["judgment"] = "uncertain"
            return self.response(request, mutate)
        client, capture = Client(wrong), {"calls": []}
        probe.run_calls(client, self.plan, capture, Path("unused"))
        self.assertEqual(len(client.calls), 2)
        self.assertTrue(all(row["assessment"]["structural_valid"] for row in capture["calls"]))
        self.assertFalse(any(item["all_gold_agrees"] for row in capture["calls"] for item in row["assessment"]["semantic_rows"]))

    def test_native_and_strict_local_failure_stop_without_salvage(self):
        def nested_index(rows):
            rows["0"]["index"] = 0
        def wrong_identity(rows):
            rows["-1"] = rows.pop("4")
        def long_pair_reason(rows):
            rows["4"]["choicePairs"]["ab"]["reason"] = "x" * 241
        def long_choice_reason(rows):
            rows["4"]["choices"]["d"]["reason"] = "x" * 601
        for mutate in (nested_index, wrong_identity, long_pair_reason, long_choice_reason):
            client, capture = Client(lambda request: self.response(request, mutate)), {"calls": []}
            probe.run_calls(client, self.plan, capture, Path("unused"))
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["stop_reason"], "structural_failure")
            self.assertNotIn("assessment", capture["calls"][0])

    def test_transport_completion_and_elapsed_failures_stop_first_call(self):
        def transport(_):
            raise TimeoutError("Synthetic transport failure")
        def truncated(request):
            value = self.response(request)
            value["stopReason"] = "max_tokens"
            return value
        for respond, reason in ((transport, "provider_failure"), (truncated, "non_end_turn")):
            client, capture = Client(respond), {"calls": []}
            probe.run_calls(client, self.plan, capture, Path("unused"))
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["stop_reason"], reason)
        client, capture = Client(self.response), {"calls": []}
        with patch.object(probe.time, "monotonic", side_effect=[0.0, 75.001, 75.002]):
            probe.run_calls(client, self.plan, capture, Path("unused"))
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(capture["stop_reason"], "provider_elapsed_limit")

    def test_reasoning_text_and_signatures_are_not_saved(self):
        def respond(request):
            value = self.response(request)
            value["output"]["message"]["content"].append({"reasoningContent": {"reasoningText": {"text": "PRIVATE SYNTHETIC", "signature": "PRIVATE SYNTHETIC"}}})
            return value
        client, capture = Client(respond), {"calls": []}
        probe.run_calls(client, self.plan, capture, Path("unused"))
        self.assertEqual(sum(row["reasoning_content_block_count"] for row in capture["calls"]), 2)
        self.assertNotIn("reasoningContent", json.dumps(capture))
        self.assertNotIn("PRIVATE SYNTHETIC", json.dumps(capture))


if __name__ == "__main__":
    unittest.main()
