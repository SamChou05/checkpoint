"""Capture boundary checks require no AWS access or model calls."""

import json
import subprocess
import sys
import unittest
from unittest.mock import patch

from botocore.exceptions import ClientError
from evals import bounded_bedrock_capture as capture


class BoundedCaptureTests(unittest.TestCase):
    def test_import_does_not_select_runtime_checkout(self):
        result = subprocess.run([sys.executable, "-B", "-c",
                                 "import sys; import evals.bounded_bedrock_capture; "
                                 "assert 'question_generation' not in sys.modules; "
                                 "assert 'native_output_contracts' not in sys.modules"],
                                check=False, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_exact_credential_values_are_used_without_environment_or_disk_writes(self):
        values = {"Version": 1, "AccessKeyId": "SYNTHETIC_ACCESS", "SecretAccessKey": "SYNTHETIC_SECRET",
                  "SessionToken": "SYNTHETIC_SESSION"}
        with patch.object(capture, "export_credentials", return_value=json.dumps(values).encode()), \
                patch.object(capture.boto3, "Session") as session:
            _, secrets = capture.credential_session()
        session.assert_called_once_with(aws_access_key_id=values["AccessKeyId"], aws_secret_access_key=values["SecretAccessKey"],
                                        aws_session_token=values["SessionToken"], region_name="us-east-1")
        self.assertEqual(secrets, tuple(values[key] for key in ("AccessKeyId", "SecretAccessKey", "SessionToken")))

    def test_malformed_credentials_never_create_session(self):
        for value in ({"Version": True}, {"Version": 1}, {"Version": 1, "AccessKeyId": "a" * 129, "SecretAccessKey": "s"}):
            with self.subTest(value=value), patch.object(capture, "export_credentials", return_value=json.dumps(value).encode()), \
                    patch.object(capture.boto3, "Session") as session:
                with self.assertRaises(capture.CaptureBoundaryError):
                    capture.credential_session()
                session.assert_not_called()
        for raw in ('{"Version":1,"Version":1}', '{"Version":NaN}', '{"Version":1e999}'):
            with self.subTest(raw=raw), self.assertRaises(capture.CaptureBoundaryError):
                capture.strict_json(raw)

    def test_credential_export_is_bounded_and_reaps_local_child_processes(self):
        commands = [("import sys; sys.stdout.write('x'*100)", 16, 1),
                    ("import time; time.sleep(5)", 1024, 0.05)]
        for script, limit, timeout in commands:
            with self.subTest(script=script), \
                    patch.object(capture, "CREDENTIAL_COMMAND", (sys.executable, "-c", script)), \
                    patch.object(capture, "CREDENTIAL_MAX_BYTES", limit), \
                    patch.object(capture, "CREDENTIAL_TIMEOUT_SECONDS", timeout):
                with self.assertRaises(capture.CaptureBoundaryError):
                    capture.export_credentials()
        with patch.object(capture, "CREDENTIAL_COMMAND", (sys.executable, "-c", "print('{}', end='')")):
            self.assertEqual(capture.export_credentials(), b"{}")

    def test_visible_response_is_exact_and_unknown_private_metadata_is_omitted(self):
        text = ' {"answer":"1/3"}\r\n'
        response = {"output": {"message": {"content": [
            {"reasoningContent": {"reasoningText": {"text": "PRIVATE_REASON", "signature": "PRIVATE_SIGNATURE"}}},
            {"text": text}]}}, "stopReason": "end_turn",
            "usage": {"inputTokens": 1, "outputTokens": 2, "totalTokens": True, "unknown": "PRIVATE_USAGE"},
            "metrics": {"latencyMs": float("nan")},
            "ResponseMetadata": {"RequestId": "known-request", "HTTPStatusCode": 200,
                                 "HTTPHeaders": {"authorization": "PRIVATE_HEADER"}}}
        saved, omitted = capture.safe_response(response)
        self.assertEqual(saved["output"]["message"]["content"], [{"text": text}])
        self.assertEqual(saved["usage"], {"inputTokens": 1, "outputTokens": 2})
        self.assertEqual(saved["metrics"], {})
        self.assertEqual(omitted, 1)
        self.assertNotIn("PRIVATE_", json.dumps(saved))
        with patch.object(capture, "VISIBLE_RESPONSE_MAX_BYTES", 2), self.assertRaises(capture.CaptureBoundaryError):
            capture.safe_response(response)

    def test_error_redaction_precedes_truncation_and_drops_legal_urls(self):
        secret = "SYNTHETIC_SECRET_THAT_MUST_NOT_BE_SAVED"
        message = "x" * 1990 + secret + ' offerToken="PRIVATE_OFFER" https://example.test/legal?signature=PRIVATE_URL'
        error = ClientError({"Error": {"Code": "AccessDeniedException", "Message": message},
                             "ResponseMetadata": {"RequestId": secret, "HTTPHeaders": {"authorization": secret}}}, "Converse")
        saved = capture.safe_error(error, (secret,))
        self.assertLessEqual(len(saved["message"]), 2000)
        self.assertNotIn("SYNTHETIC_SECRET", json.dumps(saved))
        self.assertNotIn("PRIVATE_", json.dumps(capture.safe_error(ClientError(
            {"Error": {"Message": message[1990:]}}, "Converse"), (secret,))))


if __name__ == "__main__":
    unittest.main()
