"""Safe error redaction and exactly one diagnostic request, without network."""

import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from botocore.exceptions import ClientError

import error_diagnostic as probe


class Client:
    def __init__(self, respond):
        self.respond, self.calls = respond, []

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        return self.respond(request)


class ErrorDiagnosticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = probe.build_plan()

    def setUp(self):
        self.enterContext(patch.object(probe, "save"))
        self.enterContext(patch.object(probe.boto3, "client", side_effect=AssertionError("No SDK")))
        self.enterContext(patch.object(probe.subprocess, "check_output", side_effect=AssertionError("No credentials")))
        self.enterContext(patch("builtins.print"))

    def test_exact_failed_request_is_preserved_and_result_cannot_rescue_trial(self):
        original = json.loads((probe.HERE / "plan.json").read_text())
        capture = json.loads((probe.HERE / "capture.json").read_text())
        self.assertEqual(self.plan["request"], original["jobs"][0]["request"])
        self.assertEqual(self.plan["request"], capture["calls"][0]["request"])
        self.assertEqual(self.plan["request_sha256"], original["jobs"][0]["request_sha256"])
        self.assertIn("at0/2", self.plan["claim_limits"])

    def test_only_safe_error_fields_are_kept_and_secrets_redacted_before_bounds(self):
        key = "ASIA" + "X" * 16
        secret, token = "private-secret-value", "private-session-value"
        message = f"{key} {secret} {token} Bearer opaque-token aws_session_token=unknown-token " + "x" * 3000
        error = ClientError({"Error": {"Code": "ValidationException", "Message": message, "Secret": secret},
                             "ResponseMetadata": {"HTTPStatusCode": 400, "RequestId": "request-id", "HTTPHeaders": {"secret": secret}},
                             "Other": token}, "Converse")
        details = probe.safe_error_details(error, sensitive_values=(key, secret, token))
        self.assertEqual(set(details), {"Error", "HTTPStatus", "RequestId"})
        self.assertEqual(set(details["Error"]), {"Code", "Message"})
        self.assertEqual(details["HTTPStatus"], 400)
        self.assertEqual(details["RequestId"], "request-id")
        self.assertEqual(len(details["Error"]["Message"]), 2000)
        encoded = json.dumps(details)
        for sensitive in (key, secret, token, "opaque-token", "unknown-token", "HTTPHeaders"):
            self.assertNotIn(sensitive, encoded)
        self.assertIn("[REDACTED]", encoded)

    def test_missing_malformed_or_excess_error_fields_cannot_leak_exception_text(self):
        error = RuntimeError("Never serialize this arbitrary exception secret")
        expected = {"Error": {"Code": None, "Message": None}, "HTTPStatus": None, "RequestId": None}
        self.assertEqual(probe.safe_error_details(error), expected)
        for value in (None, [], "secret", {"Error": [], "ResponseMetadata": "secret"}):
            error.response = value
            self.assertEqual(probe.safe_error_details(error), expected)
        error.response = {"Error": {"Code": "c" * 200, "Message": "\ud800"},
                          "ResponseMetadata": {"HTTPStatusCode": True, "RequestId": "r" * 200}}
        details = probe.safe_error_details(error)
        self.assertEqual(len(details["Error"]["Code"]), 128)
        self.assertEqual(len(details["RequestId"]), 128)
        self.assertIsNone(details["HTTPStatus"])
        json.dumps(details, ensure_ascii=False).encode("utf-8")

    def test_one_error_dispatch_and_no_resume_or_expanded_budget(self):
        def fail(_):
            raise ClientError({"Error": {"Code": "ValidationException", "Message": "synthetic"}}, "Converse")
        client, capture = Client(fail), {"calls": []}
        probe.run_once(client, self.plan, capture, Path("unused"))
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(capture["status"], "completed_with_error_details")
        self.assertEqual(capture["calls"][0]["safe_error"]["Error"]["Code"], "ValidationException")
        with self.assertRaises(ValueError):
            probe.run_once(client, self.plan, capture, Path("unused"))
        expanded = copy.deepcopy(self.plan)
        expanded["limits"]["maximum_calls"] = 2
        with self.assertRaises(ValueError):
            probe.run_once(client, expanded, {"calls": []}, Path("unused"))
        self.assertEqual(len(client.calls), 1)

    def test_unexpected_success_retains_no_model_output_or_reasoning(self):
        client = Client(lambda _: {"output": {"message": {"content": [{"text": "PRIVATE MODEL OUTPUT"},
                                                                                    {"reasoningContent": {"text": "PRIVATE REASONING"}}]}}})
        capture = {"calls": []}
        probe.run_once(client, self.plan, capture, Path("unused"))
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(capture["status"], "unexpected_success_no_output_retained")
        self.assertNotIn("PRIVATE", json.dumps(capture))
        self.assertNotIn("reasoningContent", json.dumps(capture))

    def test_execute_uses_single_sdk_attempt_and_exact_read_connect_bounds(self):
        created = []
        def factory(*args, **kwargs):
            client = Client(lambda _: {})
            client.meta = SimpleNamespace(config=kwargs["config"])
            created.append(client)
            return client
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "plan.json"
            path.write_text(json.dumps(self.plan))
            with patch.object(probe, "PLAN", path), patch.object(probe, "build_plan", return_value=self.plan), \
                    patch.object(probe, "sha", return_value="synthetic-hash"), \
                    patch.object(probe.subprocess, "check_output", return_value=b'{"AccessKeyId":"synthetic-key","SecretAccessKey":"synthetic-secret"}') as credentials, \
                    patch.object(probe.boto3, "client", side_effect=factory) as sdk:
                probe.execute("synthetic-hash")
            self.assertEqual(credentials.call_count, 1)
            self.assertEqual(sdk.call_count, 1)
            self.assertEqual(len(created[0].calls), 1)
            config = created[0].meta.config
            self.assertEqual((config.connect_timeout, config.read_timeout, config.retries["total_max_attempts"]), (3, 75, 1))


if __name__ == "__main__":
    unittest.main()
