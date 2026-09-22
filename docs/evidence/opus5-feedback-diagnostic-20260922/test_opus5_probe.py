"""Fake-only diagnostic tests; expected labels are not model-quality evidence."""

import copy
import importlib.util
import json
from pathlib import Path
import socket
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from botocore.config import Config
from botocore.exceptions import ClientError
from botocore.session import Session
from botocore.validate import validate_parameters

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("opus5_diagnostic_tested", HERE / "opus5_probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class FakeClient:
    def __init__(self, plan, modify=None):
        self.plan, self.modify, self.requests = plan, modify, []
        self.meta = SimpleNamespace(config=Config(connect_timeout=3, read_timeout=100, retries={"total_max_attempts": 1}),
                                    endpoint_url=probe.safe.ENDPOINT, region_name="us-east-1")

    def converse(self, **request):
        index = len(self.requests)
        self.requests.append(copy.deepcopy(request))
        expected = {row["case_id"]: row for row in self.plan["field_expectations"]}
        rows = {}
        for number, cid in enumerate(self.plan["calls"][index]["case_ids"]):
            gold = expected[cid]
            def assessment(judgment):
                return {"reason": "Synthetic expected-label fixture, not an educational audit.", "judgment": judgment}
            rows[str(number)] = {"task": assessment(gold["task"]["expected_judgment"]),
                                 "answerChoice": gold["answer_set"]["expected_answerChoice"], "difficulty": 3,
                                 "feedback": {slot: assessment(row["expected_judgment"]) for slot, row in gold["feedback"].items()}}
        payload = {"reviews": rows}
        response = {"stopReason": "end_turn", "output": {"message": {"content": [{"text": json.dumps(payload)}]}},
                    "usage": {"inputTokens": 100, "outputTokens": 200}}
        return self.modify(index, payload, response) if self.modify else response


class DiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, "connect", side_effect=AssertionError("No network in fake tests")))
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "capture.json"
        self.plan = probe.build_plan()
        self.capture = {"calls": [], "status": "fake"}

    def run_fake(self, modify=None, **kwargs):
        client = FakeClient(self.plan, modify)
        probe.run_calls(client, self.plan, self.capture, self.path, **kwargs)
        return client

    def test_all24_full_originals_gold_exact_scope_and_sdk_requests(self):
        original, expected = probe.controls.source_cases()
        self.assertEqual(self.plan["cases"], original["cases"])
        self.assertEqual(self.plan["field_expectations"], list(expected.values()))
        self.assertEqual([call["count"] for call in self.plan["calls"]], [5, 5, 5, 5, 4])
        self.assertEqual([i for call in self.plan["calls"] for i in call["source_indices"]], list(range(24)))
        self.assertIsNone(self.plan["normalized_scope"]["skillMap"])
        self.assertEqual({k: v for k, v in self.plan["normalized_scope"].items() if k != "skillMap"},
                         {k: v for k, v in self.plan["original_scope"].items() if k != "skillMap"})
        shape = Session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        for call in self.plan["calls"]:
            request = call["request"]
            validate_parameters(request, shape)  # SDK shape only; no provider-support claim.
            self.assertNotIn("outputConfig", request)
            self.assertNotIn("toolConfig", request)
            self.assertEqual(request["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(request["additionalModelRequestFields"], {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}})
            self.assertTrue(request["system"][0]["text"].startswith(probe.controls.verification.FULL_FEEDBACK_AUDIT_SYSTEM_PROMPT))
            self.assertIn(call["local_schema"]["schema"], request["system"][0]["text"])
            originals = [original["cases"][i]["learner_item"] for i in call["source_indices"]]
            prompt = probe.audit.build_user_prompt(originals, self.plan["normalized_scope"], assignments=[{} for _ in originals], history=[])
            self.assertEqual(request["messages"][0]["content"][0]["text"], prompt)
            data = probe.controls.data(prompt)
            self.assertNotIn("expectedAnswer", json.dumps(data))
            self.assertNotIn("gold", data)

    def test_five_calls_strictly_adapt_and_select_only_exact_originals(self):
        client = self.run_fake()
        self.assertEqual(len(client.requests), 5)
        summary = self.capture["summary"]
        self.assertEqual(summary["correct_admissions"], 24)
        self.assertEqual(summary["sound_accepted"], 12)
        self.assertEqual(summary["defective_admitted"], 0)
        self.assertTrue(summary["known_admission_criteria_pass"])
        self.assertFalse(summary["production_qualified"])
        self.assertEqual(sum(len(row["assessment"]["rows"]) for row in self.capture["calls"]), 24)

    def test_timeout_failed_batch_earns_no_credit_but_next_four_run(self):
        def modify(index, payload, response):
            if index == 0:
                raise TimeoutError("Synthetic provider timeout")
            return response
        client = self.run_fake(modify)
        self.assertEqual(len(client.requests), 5)
        self.assertEqual(self.capture["summary"]["assessed_items"], 19)
        self.assertEqual(self.capture["summary"]["unavailable_items"], 5)
        self.assertEqual(self.capture["summary"]["reported_token_usage"]["calls_without_reported_usage"], 1)
        self.assertFalse(self.capture.get("global_stop"))

    def test_assessment_crossing_elapsed_limit_loses_batch_credit(self):
        timestamps = iter([0, 99.9, 100.1] + [101] * 12)
        client = self.run_fake(clock=lambda: next(timestamps))
        self.assertEqual(len(client.requests), 5)
        first = self.capture["calls"][0]
        self.assertEqual(first["elapsed_seconds"], 100.1)
        self.assertEqual(first["failure"], "elapsed_limit")
        self.assertNotIn("assessment", first)
        self.assertEqual(self.capture["summary"]["assessed_items"], 19)
        self.assertFalse(self.capture["summary"]["known_admission_criteria_pass"])

    def test_malformed_duplicate_missing_or_non_end_turn_responses_have_no_repair(self):
        for kind in ("fence", "duplicate", "missing", "unknown", "non_end_turn"):
            self.capture = {"calls": []}
            def modify(index, payload, response):
                if index:
                    return response
                text = json.dumps(payload)
                if kind == "fence":
                    text = "```json\n" + text + "\n```"
                elif kind == "duplicate":
                    text = text.replace('"difficulty": 3', '"difficulty":3,"difficulty":4', 1)
                elif kind == "missing":
                    payload["reviews"].pop("0")
                    text = json.dumps(payload)
                elif kind == "unknown":
                    payload["reviews"]["0"]["extra"] = True
                    text = json.dumps(payload)
                else:
                    response["stopReason"] = "max_tokens"
                response["output"]["message"]["content"] = [{"text": text}]
                return response
            with self.subTest(kind=kind):
                self.assertEqual(len(self.run_fake(modify).requests), 5)
                self.assertEqual(self.capture["summary"]["assessed_items"], 19)
                self.assertFalse(self.capture.get("global_stop"))

    def test_unsafe_sdk_and_source_drift_stop_before_or_after_dispatch(self):
        client = FakeClient(self.plan)
        client.meta.config = Config(connect_timeout=3, read_timeout=100, retries={"total_max_attempts": 2})
        probe.run_calls(client, self.plan, self.capture, self.path)
        self.assertEqual(client.requests, [])
        self.assertTrue(self.capture["global_stop"])
        self.capture = {"calls": []}
        client = FakeClient(self.plan)
        def check():
            if client.requests:
                raise probe.controls.IntegrityError("Synthetic source drift during dispatch")
        probe.run_calls(client, self.plan, self.capture, self.path, pin_check=check)
        self.assertEqual(len(client.requests), 1)
        self.assertEqual(self.capture["summary"]["assessed_items"], 0)
        self.assertFalse(self.capture["summary"]["known_admission_criteria_pass"])

    def test_reasoning_signatures_headers_and_unknown_metadata_are_not_persisted(self):
        def modify(index, payload, response):
            response["output"]["message"]["content"].insert(0, {"reasoningContent": {"reasoningText": {"text": "PRIVATE_REASON", "signature": "PRIVATE_SIGNATURE"}}})
            response["ResponseMetadata"] = {"HTTPHeaders": {"authorization": "PRIVATE_HEADER"}, "unexpected": "PRIVATE_OTHER"}
            response["usage"]["unknown"] = "PRIVATE_USAGE"
            return response
        self.run_fake(modify)
        self.assertNotIn("PRIVATE_", self.path.read_text())

    def test_credentials_offer_tokens_and_legal_urls_never_reach_errors(self):
        secrets = ("SYNTHETIC_ACCESS", "SYNTHETIC_SECRET", "SYNTHETIC_SESSION")
        def modify(index, payload, response):
            raise ClientError({"Error": {"Code": "AccessDeniedException", "Message": " ".join(secrets)
                + " offerToken=PRIVATE_OFFER https://legal.example.test/file?X-Amz-Signature=PRIVATE_SIGNED"}}, "Converse")
        client = self.run_fake(modify, secrets=secrets)
        self.assertEqual(len(client.requests), 1)
        text = self.path.read_text()
        self.assertTrue(all(secret not in text for secret in secrets))
        self.assertNotIn("PRIVATE_", text)
        self.assertEqual(self.capture["summary"]["unavailable_items"], 24)

    def test_freeze_digest_exact_pins_and_no_overwrite(self):
        path = Path(self.directory.name) / "plan.json"
        with patch.object(probe, "preflight", return_value={"result": "passed"}):
            with self.assertRaises(probe.controls.IntegrityError):
                probe.freeze("0" * 64, path)
            result = probe.freeze(probe.digest(self.plan), path)
            self.assertEqual(probe.file_hash(path), result["plan_sha256"])
            probe.check_plan(json.loads(path.read_text()), path, result["plan_sha256"])
            with self.assertRaises(FileExistsError):
                probe.freeze(probe.digest(self.plan), path)
        self.assertEqual(json.loads(path.read_text())["plan_state"], "frozen")

    def test_execute_requires_access_confirmation_and_rejects_config_before_credentials(self):
        path = Path(self.directory.name) / "plan.json"
        plan = {**copy.deepcopy(self.plan), "plan_state": "frozen"}
        probe.save(path, plan)
        with patch.object(probe.safe, "credential_session") as credentials:
            with self.assertRaises(probe.controls.IntegrityError):
                probe.execute(probe.file_hash(path), plan_path=path, capture_path=self.path)
            plan["limits"]["maximum_calls"] = 6
            probe.save(path, plan)
            with self.assertRaises(probe.controls.IntegrityError):
                probe.execute(probe.file_hash(path), agreement_confirmed=True, plan_path=path, capture_path=self.path)
            credentials.assert_not_called()

    def test_execute_fake_session_and_exclusive_capture(self):
        path = Path(self.directory.name) / "plan.json"
        probe.save(path, {**self.plan, "plan_state": "frozen"})
        client = FakeClient(self.plan)
        session = SimpleNamespace(client=lambda *args, **kwargs: client)
        with patch.object(probe.safe, "credential_session", return_value=(session, ())):
            result = probe.execute(probe.file_hash(path), agreement_confirmed=True, plan_path=path, capture_path=self.path)
        self.assertEqual(result["summary"]["correct_admissions"], 24)
        with patch.object(probe.safe, "credential_session") as credentials:
            with self.assertRaises(FileExistsError):
                probe.execute(probe.file_hash(path), agreement_confirmed=True, plan_path=path, capture_path=self.path)
            credentials.assert_not_called()


if __name__ == "__main__":
    unittest.main()
