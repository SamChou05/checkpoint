"""Production SDK factory with fake transports and a declining Lambda clock."""

import contextlib
import io
import json
import os
import sys
import types
from unittest import mock

import lambda_function
from lambda_test_support import (
    BackendTestCase,
    FakeBedrockClient,
    FakeLambdaContext,
    _event,
    _raw_question,
    _request_payload,
)
from question_generation import ProviderCallBudget, _generate_with_bedrock
from request_contract import _normalize_request
from service_errors import ProviderDeadlineExceededError, ServiceConfigurationError


class ProviderDeadlineTests(BackendTestCase):
    @contextlib.contextmanager
    def sdk(self, context, *, durations=(), setup_milliseconds=0):
        """Exercise the production factory without credentials, network, or sleep."""
        shared = FakeBedrockClient.returning_questions(
            _raw_question("Which conclusion follows from the stated evidence?")
        )
        configurations = []
        calls = []
        durations = iter(durations)

        def factory(service, *, config, **_kwargs):
            self.assertEqual(service, "bedrock-runtime")
            configurations.append(config)
            context.remaining_milliseconds -= setup_milliseconds

            def converse(**request):
                calls.append((context.remaining_milliseconds, config))
                response = shared.converse(**request)
                context.remaining_milliseconds -= next(durations, 0)
                return response

            return types.SimpleNamespace(
                meta=types.SimpleNamespace(config=config), converse=converse
            )

        boto3 = types.ModuleType("boto3")
        boto3.client = mock.Mock(side_effect=factory)
        botocore = types.ModuleType("botocore")
        config_module = types.ModuleType("botocore.config")
        config_module.Config = lambda **values: types.SimpleNamespace(**values)
        botocore.config = config_module
        with mock.patch.dict(
            sys.modules,
            {"boto3": boto3, "botocore": botocore, "botocore.config": config_module},
        ):
            yield configurations, calls, shared, boto3.client

    def test_http_author_solver_and_review_share_declining_thirty_second_deadline(self):
        # The deployed fixed 26-second floor refused the final review after the
        # first two successful calls took 4.8 seconds. Also cover a slower pair.
        for durations in ((3000, 1800, 1200), (7000, 6000, 1300)):
            with self.subTest(durations=durations):
                context = FakeLambdaContext(30_000)
                with self.sdk(context, durations=durations, setup_milliseconds=100) as (
                    configs,
                    calls,
                    shared,
                    _factory,
                ):
                    response = lambda_function.handle_http_request(
                        _event(_request_payload(target_count=1)), context=context
                    )

                self.assertEqual(response["statusCode"], 200)
                question = json.loads(response["body"])["questions"][0]
                self.assertEqual(question["verificationVersion"], 1)
                self.assertEqual(question["verificationPolicyRevision"], 1)
                self.assertEqual(
                    (
                        len(shared.calls),
                        len(shared.solution_calls),
                        len(shared.review_calls),
                    ),
                    (1, 1, 1),
                )
                self.assertEqual(len(configs), 3)
                self.assertLess(configs[-1].read_timeout, 20)
                for remaining, config in calls:
                    self.assertEqual(config.connect_timeout, 3)
                    self.assertGreaterEqual(config.read_timeout, 2)
                    self.assertLessEqual(config.read_timeout, 20)
                    self.assertLess(
                        (config.connect_timeout + config.read_timeout) * 1000 + 2000,
                        remaining,
                    )
                    self.assertEqual(config.retries["total_max_attempts"], 1)

    def test_real_client_keeps_configured_short_timeout_and_worker_timeout_ceiling(
        self,
    ):
        for remaining, configured in ((30_000, 4.0), (240_000, 75.0)):
            with self.subTest(configured=configured):
                with mock.patch.dict(
                    os.environ, {"BEDROCK_READ_TIMEOUT_SECONDS": str(configured)}
                ):
                    context = FakeLambdaContext(remaining)
                    with self.sdk(context) as (configs, _calls, _shared, _factory):
                        _generate_with_bedrock(
                            _normalize_request(_request_payload(target_count=1)),
                            None,
                            "amazon.nova-lite-v1:0",
                            call_budget=ProviderCallBudget(1, context=context),
                        )
                    self.assertEqual(configs[0].read_timeout, configured)

    def test_safe_minimum_refuses_before_client_reservation_or_provider(self):
        context = FakeLambdaContext(8_000)
        reserve = mock.Mock()
        budget = ProviderCallBudget(1, context=context, reserve_call=reserve)
        with self.sdk(context) as (_configs, calls, _shared, factory):
            with self.assertRaises(ProviderDeadlineExceededError):
                _generate_with_bedrock(
                    {}, None, "model", user_prompt="Synthetic input", call_budget=budget
                )
        factory.assert_not_called()
        reserve.assert_not_called()
        self.assertEqual(calls, [])
        self.assertEqual(budget.calls, 0)

    def test_explicit_admission_floor_still_refuses_a_shorter_transport(self):
        os.environ["MIN_PROVIDER_REMAINING_MILLISECONDS"] = "26000"
        context = FakeLambdaContext(25_200)
        budget = ProviderCallBudget(1, context=context)
        with self.sdk(context) as (_configs, calls, _shared, factory):
            with self.assertRaises(ProviderDeadlineExceededError):
                _generate_with_bedrock(
                    {}, None, "model", user_prompt="Synthetic input", call_budget=budget
                )
        factory.assert_not_called()
        self.assertEqual(calls, [])
        self.assertEqual(budget.calls, 0)

    def test_slow_sdk_construction_is_rechecked_before_spending_a_call(self):
        context = FakeLambdaContext(12_000)
        budget = ProviderCallBudget(1, context=context)
        with self.sdk(context, setup_milliseconds=1200) as (
            _configs,
            calls,
            _shared,
            factory,
        ):
            with self.assertRaises(ProviderDeadlineExceededError):
                _generate_with_bedrock(
                    {}, None, "model", user_prompt="Synthetic input", call_budget=budget
                )
        factory.assert_called_once()
        self.assertEqual(calls, [])
        self.assertEqual(budget.calls, 0)

    def test_slow_durable_reservation_cannot_start_an_unaffordable_transport(self):
        context = FakeLambdaContext(12_000)

        def reserve():
            context.remaining_milliseconds -= 3000

        reservation = mock.Mock(side_effect=reserve)
        budget = ProviderCallBudget(1, context=context, reserve_call=reservation)
        with self.sdk(context) as (_configs, calls, _shared, _factory):
            with self.assertRaises(ProviderDeadlineExceededError):
                _generate_with_bedrock(
                    {}, None, "model", user_prompt="Synthetic input", call_budget=budget
                )
        reservation.assert_called_once()
        self.assertEqual(calls, [])
        self.assertEqual(budget.calls, 0)

    def test_injected_sdk_client_uses_its_actual_timeout_without_mutating_it(self):
        client = FakeBedrockClient.returning_questions(
            _raw_question("A valid question?")
        )
        config = types.SimpleNamespace(
            connect_timeout=3, read_timeout=60, retries={"total_max_attempts": 1}
        )
        client.meta = types.SimpleNamespace(config=config)
        budget = ProviderCallBudget(1, context=FakeLambdaContext(30_000))
        with self.assertRaises(ProviderDeadlineExceededError):
            _generate_with_bedrock(
                {}, client, "model", user_prompt="Synthetic input", call_budget=budget
            )
        self.assertEqual((config.connect_timeout, config.read_timeout), (3, 60))
        self.assertEqual(client.calls, [])
        self.assertEqual(budget.calls, 0)

    def test_injected_sdk_retries_cannot_evade_one_attempt_deadline(self):
        for retries in ({}, {"total_max_attempts": 2}, {"max_attempts": 1}):
            with self.subTest(retries=retries):
                client = FakeBedrockClient.returning_questions(
                    _raw_question("A valid question?")
                )
                client.meta = types.SimpleNamespace(
                    config=types.SimpleNamespace(
                        connect_timeout=1, read_timeout=2, retries=retries
                    )
                )
                budget = ProviderCallBudget(1, context=FakeLambdaContext(30_000))
                with self.assertRaises(ServiceConfigurationError):
                    _generate_with_bedrock(
                        {},
                        client,
                        "model",
                        user_prompt="Synthetic input",
                        call_budget=budget,
                    )
                self.assertEqual(client.calls, [])
                self.assertEqual(budget.calls, 0)

    def test_http_deadline_refusal_has_distinct_safe_diagnostics(self):
        os.environ["EMIT_STRUCTURED_METRICS"] = "true"
        context = FakeLambdaContext(7_000)
        output = io.StringIO()
        payload = _request_payload(target_count=1)
        payload["goal"]["title"] = "private-topic-marker"
        with self.sdk(context), contextlib.redirect_stdout(output):
            response = lambda_function.handle_http_request(
                _event(payload), context=context
            )
        metrics = json.loads(output.getvalue())
        self.assertEqual(response["statusCode"], 502)
        self.assertEqual(
            json.loads(response["body"])["code"], "provider_deadline_exhausted"
        )
        self.assertEqual(metrics["Outcome"], "provider_deadline_exhausted")
        self.assertEqual(metrics["ProviderCalls"], 0)
        self.assertNotIn("private-topic-marker", output.getvalue())
