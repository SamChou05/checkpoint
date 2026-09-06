import os
import unittest
from unittest.mock import patch

from lambda_test_support import FakeBedrockClient, _request_payload
from question_generation import _generate_with_bedrock
from request_contract import _normalize_request
from service_errors import ServiceConfigurationError


class ReasoningConfigurationTests(unittest.TestCase):
    def invoke(self, model, settings):
        client = FakeBedrockClient(
            {
                "output": {
                    "message": {
                        "content": [
                            {
                                "reasoningContent": {
                                    "reasoningText": {
                                        "text": "private reasoning",
                                        "signature": "opaque",
                                    }
                                }
                            },
                            {"text": '{"questions":[]}'},
                        ]
                    }
                }
            }
        )
        with patch.dict(os.environ, settings, clear=True):
            text = _generate_with_bedrock(
                _normalize_request(_request_payload()), client, model
            )
        self.assertEqual(text, '{"questions":[]}')
        return client.calls[0]

    def test_kimi_thinking_has_room_and_recommended_sampling(self):
        request = self.invoke(
            "arn:aws:bedrock:us-east-1::foundation-model/moonshotai.kimi-k2.5",
            {"BEDROCK_KIMI_THINKING": "enabled"},
        )
        self.assertEqual(
            request["additionalModelRequestFields"], {"thinking": {"type": "enabled"}}
        )
        self.assertEqual(
            request["inferenceConfig"],
            {"maxTokens": 16000, "temperature": 1.0, "topP": 0.95},
        )

    def test_claude_adaptive_does_not_send_incompatible_sampling(self):
        for model in [
            "us.anthropic.claude-sonnet-4-6",
            "us.anthropic.claude-opus-4-6-v1",
        ]:
            request = self.invoke(
                model,
                {
                    "BEDROCK_CLAUDE_THINKING": "adaptive",
                    "BEDROCK_CLAUDE_EFFORT": "medium",
                    "BEDROCK_TEMPERATURE": "0.7",
                },
            )
            self.assertEqual(request["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(
                request["additionalModelRequestFields"],
                {
                    "thinking": {"type": "adaptive"},
                    "output_config": {"effort": "medium"},
                },
            )

    def test_reasoning_budget_is_bounded_and_separate_from_fast_mode(self):
        settings = {
            "BEDROCK_KIMI_THINKING": "enabled",
            "BEDROCK_THINKING_MAX_TOKENS": "999999",
        }
        self.assertEqual(
            self.invoke("moonshotai.kimi-k2.5", settings)["inferenceConfig"][
                "maxTokens"
            ],
            16384,
        )
        self.assertEqual(
            self.invoke("amazon.nova-lite-v1:0", settings)["inferenceConfig"][
                "maxTokens"
            ],
            6000,
        )

    def test_invalid_modes_fail_before_spending_a_provider_call(self):
        for model, settings in [
            ("moonshotai.kimi-k2.5", {"BEDROCK_KIMI_THINKING": "adaptive"}),
            ("us.anthropic.claude-sonnet-4-6", {"BEDROCK_CLAUDE_THINKING": "enabled"}),
            (
                "us.anthropic.claude-sonnet-4-6",
                {
                    "BEDROCK_CLAUDE_THINKING": "adaptive",
                    "BEDROCK_CLAUDE_EFFORT": "unlimited",
                },
            ),
        ]:
            client = FakeBedrockClient("{}")
            with (
                patch.dict(os.environ, settings, clear=True),
                self.assertRaises(ServiceConfigurationError),
            ):
                _generate_with_bedrock(
                    _normalize_request(_request_payload()), client, model
                )
            self.assertEqual(client.calls, [])
