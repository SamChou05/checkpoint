"""Offline native-shape, immutable-content, pairing, stopping and SDK-bound tests."""

import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import botocore.session
from botocore.validate import validate_parameters
import jsonschema

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("final_audit_probe_test", HERE / "final_audit_probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
contract = probe.contract


def audits(count=6, verdict="accepted"):
    return {"audits": {str(index): {"reason": "Synthetic test evidence, not a provider judgment.", "verdict": verdict}
                       for index in range(count)}}


class ContractTests(unittest.TestCase):
    def test_all_40_counts_are_closed_and_reason_precedes_verdict(self):
        for count in range(1, 41):
            schema = contract.schema(count)
            jsonschema.Draft202012Validator.check_schema(schema)
            jsonschema.Draft202012Validator(schema).validate(audits(count))
            required = [str(index) for index in range(count)]
            self.assertEqual(schema["properties"]["audits"]["required"], required)
            self.assertFalse(schema["additionalProperties"])
            self.assertFalse(schema["properties"]["audits"]["additionalProperties"])
            for row in schema["properties"]["audits"]["properties"].values():
                self.assertEqual(list(row["properties"]), ["reason", "verdict"])
                self.assertEqual(row["required"], ["reason", "verdict"])
                self.assertFalse(row["additionalProperties"])
            self.assertEqual(list(contract.validate(json.dumps(audits(count)), count)), required)
            config = contract.output_config(count)["textFormat"]["structure"]["jsonSchema"]
            self.assertEqual(config["name"], f"final_content_audit_v1_n{count}")
            self.assertEqual(json.loads(config["schema"]), schema)
            self.assertEqual(contract.metadata(count)["sha256"], probe.sha(config["schema"].encode()))

    def test_invalid_counts_and_types(self):
        for count in (0, 41, -1, True, False, 6.0, "6", None):
            for action in (contract.schema, contract.output_config, contract.metadata):
                with self.assertRaises(ValueError):
                    action(count)

    def test_json_identity_and_field_failures(self):
        malformed = ['{"audits":{},"audits":{}}', json.dumps(audits()) + " junk", "[]", "null",
                     '{"audits":{"0":{"reason":"first","reason":"second","verdict":"accepted"}}}']
        for mutate in (lambda value: value.update(extra=True), lambda value: value["audits"].pop("0"),
                       lambda value: value["audits"].update({"6": value["audits"]["0"]}),
                       lambda value: value["audits"].update({"-1": value["audits"].pop("0")}),
                       lambda value: value["audits"]["0"].update(answer="replacement"),
                       lambda value: value["audits"]["0"].pop("reason"),
                       lambda value: value["audits"].update({"0": []}),
                       lambda value: value["audits"]["0"].update(verdict=True),
                       lambda value: value["audits"]["0"].update(verdict="accept")):
            value = audits()
            mutate(value)
            malformed.append(json.dumps(value))
        for raw in malformed:
            with self.assertRaises((ValueError, TypeError)):
                contract.validate(raw, 6)

    def test_reason_exact_bound_nonblank_types_and_no_normalization(self):
        for reason in ("", "  \n", "x" * 601, None, True, 3, [], {}):
            value = audits()
            value["audits"]["0"]["reason"] = reason
            with self.assertRaises(ValueError):
                contract.validate(json.dumps(value), 6)
        for reason in ("é" * 600, "  exact reason  "):
            value = audits()
            value["audits"]["0"]["reason"] = reason
            self.assertEqual(contract.validate(json.dumps(value), 6)["0"]["reason"], reason)

    def test_select_originals_only_without_mutation_or_aliasing(self):
        originals = [{"prompt": " exact  bytes", "nested": {"choice": [str(index)]}} for index in range(3)]
        raw = audits(3)
        raw["audits"]["1"]["verdict"] = "rejected"
        raw["audits"]["2"]["verdict"] = "uncertain"
        snapshot = copy.deepcopy(originals)
        selected = contract.select_accepted(json.dumps(raw), originals)
        self.assertEqual(selected, [snapshot[0]])
        self.assertEqual(originals, snapshot)
        self.assertEqual(contract.content_digest(selected[0]), contract.content_digest(originals[0]))
        selected[0]["nested"]["choice"].append("changed later")
        self.assertEqual(originals, snapshot)
        raw["audits"]["0"]["explanation"] = "repair"
        with self.assertRaises(ValueError):
            contract.select_accepted(json.dumps(raw), originals)


class FakeClient:
    def __init__(self, respond):
        self.calls, self.respond = [], respond

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return self.respond(request)


class ProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = probe.build_plan()
        cls.gold = {contract.content_digest(case["learner_item"]): case["gold"]["required_gate_decision"] for case in cls.plan["cases"]}

    def setUp(self):
        self.enterContext(patch.object(probe, "save"))
        self.enterContext(patch.object(probe.boto3, "client", side_effect=AssertionError("No SDK client")))
        self.enterContext(patch.object(probe.subprocess, "check_output", side_effect=AssertionError("No credentials")))
        self.enterContext(patch("builtins.print"))

    def response(self, request, mutate=None):
        rows = audits()
        for slot, item in probe.user_data(request)["items"].items():
            rows["audits"][slot]["verdict"] = {"accept": "accepted", "reject": "rejected"}[self.gold[contract.content_digest(item)]]
        if mutate:
            mutate(rows)
        return {"stopReason": "end_turn", "usage": {"inputTokens": 1, "outputTokens": 1},
                "output": {"message": {"content": [{"text": json.dumps(rows)}]}}}

    def fake_run(self, respond, plan=None):
        client, capture = FakeClient(respond), {"calls": []}
        probe.run_calls(client, plan or self.plan, capture, Path("/unused"))
        return client, capture

    def test_exact_six_request_pairing_and_native_sdk_shapes(self):
        self.assertEqual([(call["batch"], call["arm"]) for call in self.plan["calls"]],
                         [(0, "disabled"), (0, "adaptive"), (1, "adaptive"), (1, "disabled"), (2, "disabled"), (2, "adaptive")])
        operation = botocore.session.get_session().get_service_model("bedrock-runtime").operation_model("Converse")
        for call in self.plan["calls"]:
            validate_parameters(call["provider_request"], operation.input_shape)
            self.assertEqual(call["provider_request"]["outputConfig"], contract.output_config(6))
        for batch in range(3):
            pair = [copy.deepcopy(call["provider_request"]) for call in self.plan["calls"] if call["batch"] == batch]
            for request in pair:
                del request["inferenceConfig"], request["additionalModelRequestFields"]
            self.assertEqual(*pair)

    def test_inputs_exact_and_evaluator_fields_hidden(self):
        for call in self.plan["calls"]:
            data = probe.user_data(call["provider_request"])
            self.assertEqual(set(data), {"goal", "skillMap", "sourceDocuments", "items"})
            self.assertEqual(list(data["items"]), list(map(str, range(6))))
            selected = [case for case in self.plan["cases"] if case["batch"] == call["batch"]]
            self.assertEqual(data["items"], {case["slot"]: case["learner_item"] for case in selected})
            self.assertEqual([probe.sha(probe.canonical(item)) for item in data["items"].values()],
                             sorted(probe.sha(probe.canonical(item)) for item in data["items"].values()))
            for item in data["items"].values():
                self.assertEqual(set(item), {"prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations"})
        self.assertNotIn("question_generation", sys.modules)
        self.assertNotIn("question_verification", sys.modules)

    def test_six_fake_calls_complete_36_items_with_reason_audit_pending(self):
        client, capture = self.fake_run(self.response)
        self.assertEqual(client.calls, [call["provider_request"] for call in self.plan["calls"]])
        self.assertEqual(capture["status"], "complete_pending_manual_audit")
        items = [item for call in capture["calls"] for item in call["assessment"]["items"]]
        self.assertEqual(len(items), 36)
        self.assertTrue(all(item["matching_disposition"] and item["reason_manual_audit"] == "pending" for item in items))
        self.assertTrue(all(item.get("accepted_content_exactly_unchanged", True) for item in items))

    def test_seventh_call_and_sdk_retries_bounded(self):
        plan = copy.deepcopy(self.plan)
        plan["calls"].append(plan["calls"][0])
        client, capture = FakeClient(self.response), {"calls": []}
        with self.assertRaisesRegex(RuntimeError, "Six-call"):
            probe.run_calls(client, plan, capture, Path("/unused"))
        self.assertEqual(len(client.calls), 6)
        config = probe.Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1})
        self.assertEqual((config.connect_timeout, config.read_timeout, config.retries["total_max_attempts"]), (3, 75, 1))

    def test_provider_and_truncation_stop_preserve_remaining_denominator(self):
        def timeout(_request):
            raise TimeoutError("synthetic")

        for respond in (timeout, lambda _: {"stopReason": "max_tokens"}):
            client, capture = self.fake_run(respond)
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["status"], "stopped_after_failure")
            self.assertEqual(len(self.plan["calls"]) - len(client.calls), 5)

    def test_structural_failures_stop_and_keep_raw(self):
        for mutate in (lambda value: value["audits"].pop("0"),
                       lambda value: value["audits"]["0"].update(index=0),
                       lambda value: value["audits"]["0"].update(reason="x" * 601)):
            client, capture = self.fake_run(lambda request: self.response(request, mutate))
            self.assertEqual(len(client.calls), 1)
            self.assertEqual(capture["stop_reason"], "structural_failure")
            self.assertIn("response", capture["calls"][0])

    def test_uncertainty_and_false_decisions_fail_without_extra_calls(self):
        for verdict in ("accepted", "rejected", "uncertain"):
            def mutate(value):
                for row in value["audits"].values():
                    row["verdict"] = verdict
            client, capture = self.fake_run(lambda request: self.response(request, mutate))
            self.assertEqual(len(client.calls), 6)
            self.assertTrue(any(not item["matching_disposition"] for call in capture["calls"] for item in call["assessment"]["items"]))

    def test_reasoning_redacted_without_altering_original(self):
        response = self.response(self.plan["calls"][0]["provider_request"])
        response["output"]["message"]["content"].insert(0, {"reasoningContent": {"reasoningText": {"text": "synthetic private text", "signature": "synthetic"}}})
        saved, count = probe.safe_response(response)
        self.assertEqual(count, 1)
        self.assertNotIn("reasoningContent", json.dumps(saved))
        self.assertIn("reasoningContent", response["output"]["message"]["content"][0])


if __name__ == "__main__":
    unittest.main()
