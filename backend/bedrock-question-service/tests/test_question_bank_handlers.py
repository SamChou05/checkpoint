import json
import unittest
from unittest import mock

import lambda_function
import question_bank
from question_bank_test_support import (
    QuestionBankTestCase,
    _ensure_payload,
    _event,
)


class QuestionBankHandlerTests(QuestionBankTestCase):
    def test_worker_reports_only_failed_sqs_records(self):
        event = {
            "Records": [
                {"messageId": "ok", "body": "{}"},
                {"messageId": "failed", "body": "{}"},
            ]
        }
        with (
            mock.patch.object(
                question_bank,
                "_process_job",
                side_effect=[None, RuntimeError("provider unavailable")],
            ),
            mock.patch.object(question_bank.LOGGER, "exception"),
        ):
            result = question_bank.handle_worker_event(
                event,
                object(),
                lambda _: [],
                dynamodb_client=object(),
                sqs_client=object(),
            )
        self.assertEqual(result, {"batchItemFailures": [{"itemIdentifier": "failed"}]})

    def test_http_routes_ensure_without_synchronous_generation_or_quota(self):
        event = _event()
        event["rawPath"] = "/v1/question-banks/ensure"
        event["requestContext"]["stage"] = "prod"
        event["body"] = json.dumps(_ensure_payload())
        with (
            mock.patch.object(
                lambda_function.question_bank,
                "ensure_bank",
                return_value={
                    "bankID": "a" * 64,
                    "status": "queued",
                    "readyCount": 0,
                    "targetCount": 40,
                },
            ) as ensure,
            mock.patch.object(lambda_function, "_check_rate_limits") as quota,
            mock.patch.object(
                lambda_function, "_generate_sanitized_questions"
            ) as generation,
        ):
            response = lambda_function.handle_http_request(event)

        self.assertEqual(response["statusCode"], 202)
        ensure.assert_called_once()
        quota.assert_not_called()
        generation.assert_not_called()


if __name__ == "__main__":
    unittest.main()
