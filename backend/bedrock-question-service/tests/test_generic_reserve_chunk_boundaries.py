"""Seven-row source identity and all-or-nothing two-chunk verification."""

import unittest
from unittest.mock import patch

import question_generation as generation
from lambda_test_support import FakeLambdaContext
from service_errors import (
    ProviderCallBudgetExceededError, ProviderDeadlineExceededError, ProviderError,
)
import test_generic_prose_reserve as fixture


class GenericReserveChunkBoundaryTests(unittest.TestCase):
    # Use the same authored rows and real native-stage fake as the first reserve
    # tests without inheriting their test methods a second time.
    setUp = fixture.GenericProseReserveTests.setUp
    client = fixture.GenericProseReserveTests.client

    def test_vetoes_in_both_chunks_keep_five_original_keys_and_teaching(self):
        client = self.client(solver_rejected={1}, review_rejected={5})
        result = generation._generate_sanitized_questions(
            self.request, client, generation.ProviderCallBudget(5),
        )
        expected = [self.questions[index] for index in (0, 2, 3, 4, 6)]
        self.assertEqual(len(client.calls), 5)
        self.assertEqual([row["prompt"] for row in result], [row["prompt"] for row in expected])
        self.assertEqual([row["expectedAnswer"] for row in result],
                         [row["expectedAnswer"] for row in expected])
        self.assertEqual([row["explanation"] for row in result],
                         [row["explanation"] for row in expected])
        self.assertEqual([row["choiceExplanations"] for row in result], [{}] * 5)

    def test_four_survivors_after_both_chunks_return_no_partial_batch(self):
        client = self.client(solver_rejected={1, 5}, review_rejected={6})
        result = generation._generate_sanitized_questions(
            self.request, client, generation.ProviderCallBudget(5),
        )
        self.assertEqual(result, [])
        self.assertEqual(len(client.calls), 5)

    def test_second_reviewer_novelty_flag_vetoes_cross_chunk_repeat(self):
        client = self.client()
        reviewer = client.steps[4][1]

        def flag_first_second_chunk_row(request):
            response = reviewer(request)
            response["reviews"]["0"]["issueFlags"]["novelty"] = True
            return response

        client.steps[4] = (client.steps[4][0], flag_first_second_chunk_row)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        result = generation._generate_sanitized_questions(
            self.request, client, generation.ProviderCallBudget(5), metrics,
        )
        self.assertEqual([row["prompt"] for row in result],
                         [self.questions[index]["prompt"] for index in (0, 1, 2, 3, 5)])
        self.assertEqual(metrics["QuestionQuality"]["review"]["reported_issues"], 1)

    def test_malformed_second_solver_or_reviewer_fails_whole_pass(self):
        for stage, malformed, expected_calls in (
            (3, {"solutions": {}}, 4),
            (4, {"reviews": {}}, 5),
        ):
            with self.subTest(stage=stage):
                client = self.client()
                client.steps[stage] = (client.steps[stage][0], malformed)
                with self.assertRaises(ProviderError):
                    generation._generate_sanitized_questions(
                        self.request, client, generation.ProviderCallBudget(5),
                    )
                self.assertEqual(len(client.calls), expected_calls)

    def test_deadline_after_first_verified_chunk_blocks_second(self):
        context = FakeLambdaContext(300_000)
        client = self.client()
        reviewer = client.steps[2][1]

        def review_then_expire(request):
            response = reviewer(request)
            context.remaining_milliseconds = 0
            return response

        client.steps[2] = (client.steps[2][0], review_then_expire)
        with self.assertRaises(ProviderDeadlineExceededError):
            generation._generate_sanitized_questions(
                self.request, client, generation.ProviderCallBudget(5, context=context),
            )
        self.assertEqual(len(client.calls), 3)

    def test_duplicate_author_stem_is_rejected_before_chunking(self):
        client = self.client(sanitized_indexes=[0, 2, 3, 4, 5, 6])
        author_name, authored = client.steps[0]
        authored["questions"][1]["prompt"] = self.questions[0]["prompt"]
        client.steps[0] = (author_name, authored)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        result = generation._generate_sanitized_questions(
            self.request, client, generation.ProviderCallBudget(5), metrics,
        )
        self.assertEqual(metrics["QuestionQuality"]["sanitize"]["duplicate_stem"], 1)
        self.assertEqual([row["prompt"] for row in result],
                         [self.questions[index]["prompt"] for index in (0, 2, 3, 4, 5)])
        self.assertEqual(len({row["prompt"] for row in result}), 5)
        self.assertEqual(len(client.calls), 5)

    def test_author_fallback_consumes_sixth_call_and_budget_still_fails_closed(self):
        with patch.dict("os.environ", {"BEDROCK_FALLBACK_MODEL_ID": "moonshotai.kimi-k2.5"}):
            client = self.client()
            client.steps.insert(0, ("question_author_v4_n7", RuntimeError("transient author error")))
            budget = generation.ProviderCallBudget(20)
            result = generation._generate_sanitized_questions(
                self.request, client, budget,
            )
            self.assertEqual(len(result), 5)
            self.assertEqual(len(client.calls), 6)
            self.assertEqual((budget.calls, budget.maximum_calls), (6, 6))

            client = self.client()
            client.steps.insert(0, ("question_author_v4_n7", RuntimeError("transient author error")))
            with self.assertRaises(ProviderCallBudgetExceededError):
                generation._generate_sanitized_questions(
                    self.request, client, generation.ProviderCallBudget(5),
                )
            self.assertEqual(len(client.calls), 4)
