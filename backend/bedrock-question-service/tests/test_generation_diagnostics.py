import copy
import json
import unittest

from generation_diagnostics import quality_summary
from lambda_test_support import _raw_question, _request_payload
from question_generation import _generate_with_bedrock
from question_quality import _sanitize_questions
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import ProviderError


class GenerationDiagnosticsTests(unittest.TestCase):
    def test_sanitization_accounts_for_candidates_without_logging_content(self):
        request = _normalize_request(_request_payload(target_count=5))
        good = _raw_question("What follows from this private-goal-marker argument?")
        long = {**good, "prompt": "x" * 321}
        duplicate = copy.deepcopy(good)
        metrics = {}
        accepted = _sanitize_questions([long, good, duplicate, None], request, metrics)
        self.assertEqual(len(accepted), 1)
        counts = quality_summary(metrics)["sanitize"]
        self.assertEqual(
            counts,
            {"prompt_length": 1, "accepted": 1, "duplicate_stem": 1, "invalid_item": 1},
        )
        self.assertEqual(sum(counts.values()), 4)
        self.assertNotIn("private-goal-marker", json.dumps(metrics))

    def test_review_distinguishes_wrong_answer_from_wrong_level(self):
        question = _raw_question("Which conclusion follows from the given evidence?")
        request = _normalize_request(_request_payload(target_count=1))
        for review, expected in [
            ({"valid": False}, "rejected_by_model"),
            ({"valid": True, "answer": "a different answer"}, "answer_disagreement"),
            (
                {"valid": True, "answer": question["expectedAnswer"], "difficulty": 1},
                "difficulty_floor",
            ),
        ]:
            metrics = {}
            self.assertEqual(
                verify_questions(
                    [question],
                    request,
                    lambda *_: json.dumps({"reviews": [{"index": 0, **review}]}),
                    metrics,
                ),
                [],
            )
            self.assertEqual(quality_summary(metrics), {"review": {expected: 1}})

    def test_truncated_response_is_rejected_even_when_text_parses(self):
        class TruncatedClient:
            def converse(self, **_):
                return {
                    "stopReason": "max_tokens",
                    "output": {
                        "message": {
                            "content": [
                                {"reasoningContent": {"redactedContent": b"private"}},
                                {"text": '{"questions": []}'},
                            ]
                        }
                    },
                }

        metrics = {
            "ProviderCalls": 0,
            "BedrockInputTokens": 0,
            "BedrockOutputTokens": 0,
        }
        with self.assertRaisesRegex(ProviderError, "token budget"):
            _generate_with_bedrock(
                _normalize_request(_request_payload()),
                TruncatedClient(),
                "test-model",
                request_metrics=metrics,
            )
        self.assertEqual(
            quality_summary(metrics), {"provider": {"output_truncated": 1}}
        )
        self.assertEqual(
            metrics["ProviderObservations"][0]["reasoningContentBlockCount"], 1
        )
        self.assertNotIn("private", json.dumps(metrics))

    def test_logging_only_allows_fixed_reason_names_and_positive_counts(self):
        self.assertEqual(
            quality_summary(
                {
                    "QuestionQuality": {
                        "review": {
                            "learner-secret": 1,
                            "accepted": "private",
                            "answer_disagreement": 2,
                        }
                    }
                }
            ),
            {"review": {"answer_disagreement": 2}},
        )
