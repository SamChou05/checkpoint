import os
import json
import unittest
from unittest.mock import patch

from lambda_test_support import FakeBedrockClient, _request_payload
from question_generation import ProviderCallBudget, _generate_with_bedrock
from request_contract import _normalize_request
from service_errors import ServiceConfigurationError


OPUS_5_IDENTIFIERS = [
    "anthropic.claude-opus-5",
    "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-opus-5",
    *[
        model
        for prefix in ("us.", "eu.", "au.", "global.")
        for model in (
            prefix + "anthropic.claude-opus-5",
            "arn:aws:bedrock:us-east-1:123456789012:inference-profile/"
            + prefix
            + "anthropic.claude-opus-5",
        )
    ],
]


class ReasoningConfigurationTests(unittest.TestCase):
    def invoke(self, model, settings, *, metrics=None, content=None):
        if content is None:
            content = [
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
        client = FakeBedrockClient(
            {
                "output": {"message": {"content": content}},
            }
        )
        with patch.dict(os.environ, settings, clear=True):
            text = _generate_with_bedrock(
                _normalize_request(_request_payload()),
                client,
                model,
                request_metrics=metrics,
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

    def test_max_effort_is_explicitly_supported_for_known_opus_46_identifiers(self):
        for model in [
            "anthropic.claude-opus-4-6-v1",
            "us.anthropic.claude-opus-4-6-v1",
            "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-opus-4-6-v1",
            "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.anthropic.claude-opus-4-6-v1",
        ]:
            with self.subTest(model=model):
                request = self.invoke(
                    model,
                    {
                        "BEDROCK_CLAUDE_THINKING": "adaptive",
                        "BEDROCK_CLAUDE_EFFORT": "max",
                    },
                )
                self.assertEqual(request["inferenceConfig"], {"maxTokens": 16000})
                self.assertEqual(
                    request["additionalModelRequestFields"],
                    {
                        "thinking": {"type": "adaptive"},
                        "output_config": {"effort": "max"},
                    },
                )

    def test_claude_defaults_still_disable_thinking_and_adaptive_defaults_to_high(self):
        model = "us.anthropic.claude-opus-4-6-v1"
        ordinary = self.invoke(model, {})
        self.assertEqual(
            ordinary["additionalModelRequestFields"], {"thinking": {"type": "disabled"}}
        )
        self.assertEqual(
            ordinary["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2}
        )
        adaptive = self.invoke(model, {"BEDROCK_CLAUDE_THINKING": "adaptive"})
        self.assertEqual(
            adaptive["additionalModelRequestFields"]["output_config"],
            {"effort": "high"},
        )

    def test_exact_opus_5_identifiers_use_explicit_adaptive_high_and_16k_budget(self):
        for model in OPUS_5_IDENTIFIERS:
            with self.subTest(model=model):
                request = self.invoke(
                    model,
                    {
                        "BEDROCK_CLAUDE_THINKING": "adaptive",
                        "BEDROCK_TEMPERATURE": "0.7",
                    },
                )
                self.assertEqual(request["modelId"], model)
                self.assertEqual(request["inferenceConfig"], {"maxTokens": 16000})
                self.assertEqual(
                    request["additionalModelRequestFields"],
                    {
                        "thinking": {"type": "adaptive"},
                        "output_config": {"effort": "high"},
                    },
                )

    def test_opus_5_disabled_and_default_omit_sampling_and_keep_fast_budget(self):
        for model in OPUS_5_IDENTIFIERS:
            for settings in ({}, {"BEDROCK_CLAUDE_THINKING": "disabled"}):
                with self.subTest(model=model, settings=settings):
                    request = self.invoke(
                        model,
                        {
                            **settings,
                            "BEDROCK_TEMPERATURE": "0.7",
                            "BEDROCK_THINKING_MAX_TOKENS": "12000",
                        },
                    )
                    self.assertEqual(request["inferenceConfig"], {"maxTokens": 6000})
                    self.assertEqual(
                        request["additionalModelRequestFields"],
                        {
                            "thinking": {"type": "disabled"},
                            "output_config": {"effort": "high"},
                        },
                    )

    def test_opus_5_effort_ladder_and_bounded_thinking_budget(self):
        for mode, efforts in (
            ("adaptive", ("low", "medium", "high", "xhigh", "max")),
            ("disabled", ("low", "medium", "high")),
        ):
            for effort in efforts:
                with self.subTest(mode=mode, effort=effort):
                    request = self.invoke(
                        "us.anthropic.claude-opus-5",
                        {
                            "BEDROCK_CLAUDE_THINKING": mode,
                            "BEDROCK_CLAUDE_EFFORT": effort,
                            "BEDROCK_THINKING_MAX_TOKENS": "999999",
                        },
                    )
                    self.assertEqual(
                        request["additionalModelRequestFields"],
                        {
                            "thinking": {"type": mode},
                            "output_config": {"effort": effort},
                        },
                    )
                    self.assertEqual(
                        request["inferenceConfig"],
                        {"maxTokens": 16384 if mode == "adaptive" else 6000},
                    )

    def test_opus_5_matching_does_not_enable_settings_on_other_identifiers(self):
        for model in (
            "anthropic.claude-opus-50",
            "anthropic.claude-opus-5-v1",
            "us.anthropic.claude-opus-5:0",
            "apac.anthropic.claude-opus-5",
            "custom.anthropic.claude-opus-5",
            "anthropic.claude-sonnet-5",
            "arbitrary/path/anthropic.claude-opus-5",
            "arn:aws:sagemaker:us-east-1::foundation-model/anthropic.claude-opus-5",
            "arn:aws:bedrock:us-east-1::custom-model/anthropic.claude-opus-5",
            "arn:aws:bedrock:us-east-1::foundation-model/other/anthropic.claude-opus-5",
            "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-opus-5-v1",
        ):
            with self.subTest(model=model):
                request = self.invoke(model, {"BEDROCK_CLAUDE_THINKING": "adaptive"})
                self.assertNotIn("additionalModelRequestFields", request)
                self.assertEqual(
                    request["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2}
                )

    def test_invalid_opus_5_thinking_and_effort_fail_before_provider_reservation(self):
        for settings in (
            {"BEDROCK_CLAUDE_THINKING": "enabled"},
            {"BEDROCK_CLAUDE_THINKING": "auto"},
            {"BEDROCK_CLAUDE_EFFORT": "max"},
            *[
                {"BEDROCK_CLAUDE_THINKING": mode, "BEDROCK_CLAUDE_EFFORT": effort}
                for mode, efforts in (
                    ("adaptive", ("unlimited", "none")),
                    ("disabled", ("xhigh", "max", "unlimited")),
                )
                for effort in efforts
            ],
        ):
            with self.subTest(settings=settings):
                client = FakeBedrockClient("{}")
                budget = ProviderCallBudget(1)
                metrics = {"ProviderCalls": 0}
                with (
                    patch.dict(os.environ, settings, clear=True),
                    self.assertRaises(ServiceConfigurationError),
                ):
                    _generate_with_bedrock(
                        _normalize_request(_request_payload()),
                        client,
                        "us.anthropic.claude-opus-5",
                        call_budget=budget,
                        request_metrics=metrics,
                    )
                self.assertEqual(client.calls, [])
                self.assertEqual(budget.calls, 0)
                self.assertEqual(metrics["ProviderCalls"], 0)

    def test_observations_measure_returned_blocks_without_retaining_private_content(
        self,
    ):
        for thinking, reasoning_blocks in [
            ("adaptive", []),
            (
                "disabled",
                [
                    {
                        "reasoningContent": {
                            "reasoningText": {
                                "text": "private-reasoning-marker",
                                "signature": "private-signature-marker",
                            }
                        }
                    },
                    {
                        "reasoningContent": {
                            "redactedContent": b"private-redacted-marker"
                        }
                    },
                ],
            ),
        ]:
            with self.subTest(thinking=thinking):
                metrics = {
                    "ProviderCalls": 0,
                    "BedrockInputTokens": 0,
                    "BedrockOutputTokens": 0,
                }
                self.invoke(
                    "us.anthropic.claude-opus-4-6-v1",
                    {"BEDROCK_CLAUDE_THINKING": thinking},
                    metrics=metrics,
                    content=[*reasoning_blocks, {"text": '{"questions":[]}'}],
                )
                observation = metrics["ProviderObservations"][0]
                self.assertEqual(
                    observation["reasoningConfig"]["thinking"]["type"], thinking
                )
                self.assertEqual(
                    observation["reasoningContentBlockCount"], len(reasoning_blocks)
                )
                self.assertNotIn("private-", json.dumps(metrics))

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
            *[
                (
                    model,
                    {
                        "BEDROCK_CLAUDE_THINKING": "adaptive",
                        "BEDROCK_CLAUDE_EFFORT": "max",
                    },
                )
                for model in [
                    "us.anthropic.claude-sonnet-4-6",
                    "us.anthropic.claude-opus-4-6-v2",
                    "us.anthropic.claude-opus-4-6-v1-unrecognized",
                ]
            ],
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
