import json
import unittest
from unittest.mock import Mock

from lambda_test_support import FakeBedrockClient, _raw_question, _request_payload
from question_generation import (
    ProviderCallBudget,
    _generate_sanitized_questions,
    _new_provider_call_budget,
)
from question_quality import _extract_json_object
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import ProviderCallBudgetExceededError, ProviderError


class IndependentQuestionSolutionTests(unittest.TestCase):
    def setUp(self):
        self.question = _raw_question(
            "Which result follows from these stated quantities?"
        )
        self.request = _normalize_request(_request_payload(target_count=1))

    def test_solver_never_sees_options_keys_or_existing_answer_history(self):
        self.request["existingQuestionCoverage"] = [self.question]
        solution = {
            "index": 0,
            "answer": "A bounded result under the stated assumptions.",
            "limitations": "An unstated condition would change the result.",
            "assumptionsRequired": [],
        }

        def solve(system, prompt):
            data = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])
            self.assertNotIn("existingQuestions", data)
            self.assertNotIn("choices", data["items"][0])
            self.assertNotIn("expectedAnswer", data["items"][0])
            self.assertNotIn("explanation", data["items"][0])
            self.assertNotIn("difficulty", data["items"][0])
            return json.dumps({"solutions": [solution]})

        def audit(system, prompt):
            data = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])
            self.assertEqual(data["independentSolutions"], [solution])
            return json.dumps({"reviews": [{"index": 0, "valid": False, "answer": ""}]})

        self.assertEqual(
            verify_questions([self.question], self.request, audit, solve=solve), []
        )

    def test_missing_or_malformed_solutions_never_reach_final_audit(self):
        for raw in [
            "{}",
            "broken",
            '{"solutions":[]}',
            '{"solutions":[{"index":true,"answer":"x","limitations":""}]}',
        ]:
            audit = Mock()
            metrics = {}
            self.assertEqual(
                verify_questions(
                    [self.question], self.request, audit, metrics, solve=lambda *_: raw
                ),
                [],
            )
            audit.assert_not_called()
            self.assertEqual(
                metrics["QuestionQuality"]["review"]["invalid_solution"], 1
            )

    def test_missing_premise_cannot_be_rescued_by_an_answer_choice(self):
        audit = Mock()
        metrics = {}

        def solve(*_):
            return json.dumps(
                {
                    "solutions": [
                        {
                            "index": 0,
                            "answer": "Only under an added condition.",
                            "limitations": "The result is conditional.",
                            "assumptionsRequired": [
                                "An input property not stated in the problem."
                            ],
                        }
                    ]
                }
            )

        self.assertEqual(
            verify_questions(
                [self.question], self.request, audit, metrics, solve=solve
            ),
            [],
        )
        audit.assert_not_called()
        self.assertEqual(
            metrics["QuestionQuality"]["review"], {"unsupported_solution": 1}
        )

    def test_filtering_unsupported_solutions_preserves_question_index_mapping(self):
        second = {
            **self.question,
            "prompt": "A second question with complete information.",
        }

        def solve(*_):
            return json.dumps(
                {
                    "solutions": [
                        {
                            "index": 1,
                            "answer": "A supported result.",
                            "limitations": "",
                            "assumptionsRequired": [],
                        },
                        {
                            "index": 0,
                            "answer": "A conditional result.",
                            "limitations": "",
                            "assumptionsRequired": ["Missing premise."],
                        },
                    ]
                }
            )

        def audit(system, prompt):
            data = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])
            self.assertEqual(len(data["items"]), 1)
            self.assertEqual(data["items"][0]["prompt"], second["prompt"])
            self.assertEqual(data["items"][0]["index"], 0)
            self.assertEqual(
                data["independentSolutions"][0]["answer"], "A supported result."
            )
            self.assertEqual(data["independentSolutions"][0]["index"], 0)
            return json.dumps(
                {
                    "reviews": [
                        {
                            "index": 0,
                            "valid": True,
                            "answer": second["expectedAnswer"],
                            "difficulty": 3,
                            "explanation": "The provided facts support this specific answer.",
                            "choiceExplanations": {
                                c: "The stated premises determine whether this choice holds."
                                for c in second["choices"]
                            },
                        }
                    ]
                }
            )

        accepted = verify_questions(
            [self.question, second], self.request, audit, solve=solve
        )
        self.assertEqual([q["prompt"] for q in accepted], [second["prompt"]])

    def test_useful_partial_batch_does_not_start_unaffordable_retry(self):
        self.request["targetCount"] = 2
        client = FakeBedrockClient.returning_questions(self.question)
        budget = ProviderCallBudget(5)
        accepted = _generate_sanitized_questions(
            self.request, client, call_budget=budget
        )
        self.assertEqual(len(accepted), 1)
        self.assertEqual(budget.calls, 3)
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(len(client.solution_calls), 1)
        self.assertEqual(len(client.review_calls), 1)

    def test_async_local_budget_cannot_exceed_its_durable_ceiling(self):
        from unittest.mock import patch

        with patch.dict(
            "os.environ",
            {
                "MAX_PROVIDER_CALLS_PER_REQUEST": "6",
                "QUESTION_BANK_MAX_RECEIVE_COUNT": "5",
            },
        ):
            self.assertEqual(
                _new_provider_call_budget(
                    None, reserve_call=lambda: None
                ).maximum_calls,
                5,
            )

    def test_duplicate_answer_properties_are_not_silently_overwritten(self):
        with self.assertRaises(ProviderError):
            _extract_json_object(
                '{"questions":[{"expectedAnswer":"first","expectedAnswer":"second"}]}'
            )

    def test_retry_uses_current_rejection_reason_without_lowering_challenge(self):
        class DifficultyClient(FakeBedrockClient):
            def converse(self, **kwargs):
                response = super().converse(**kwargs)
                prompt = kwargs["messages"][0]["content"][0]["text"]
                if "<question_review_json>" in prompt and len(self.review_calls) == 1:
                    content = response["output"]["message"]["content"][0]
                    data = json.loads(content["text"])
                    data["reviews"][0]["difficulty"] = 2
                    content["text"] = json.dumps(data)
                return response

        harder = _raw_question(
            "Which conclusion requires interpreting this new evidence?"
        )
        client = DifficultyClient(
            [
                FakeBedrockClient.question_response(self.question),
                FakeBedrockClient.question_response(harder),
            ]
        )
        metrics = {
            "ProviderCalls": 0,
            "BedrockInputTokens": 0,
            "BedrockOutputTokens": 0,
            "QuestionQuality": {"review": {"difficulty_floor": 7}},
        }
        budget = ProviderCallBudget(6)
        accepted = _generate_sanitized_questions(self.request, client, budget, metrics)
        prompt = client.calls[1]["messages"][0]["content"][0]["text"]
        data = json.loads(
            prompt.split("<generation_request_json>\n", 1)[1].split(
                "\n</generation_request_json>", 1
            )[0]
        )
        self.assertEqual(
            data["previousAttemptFeedback"], {"review": {"difficulty_floor": 1}}
        )
        self.assertEqual(data["minimumDifficulty"], 3)
        self.assertIn(self.question["prompt"], data["existingPrompts"])
        self.assertEqual([q["prompt"] for q in accepted], [harder["prompt"]])
        self.assertEqual(budget.calls, 6)
        self.assertNotIn("previousAttemptFeedback", self.request)

    def test_failed_pass_does_not_spend_remaining_calls_on_unreviewable_output(self):
        class RejectingClient(FakeBedrockClient):
            def converse(self, **kwargs):
                response = super().converse(**kwargs)
                if (
                    "<question_review_json>"
                    in kwargs["messages"][0]["content"][0]["text"]
                ):
                    response["output"]["message"]["content"][0]["text"] = json.dumps(
                        {"reviews": [{"index": 0, "valid": False, "answer": ""}]}
                    )
                return response

        client = RejectingClient.returning_questions(self.question)
        budget = ProviderCallBudget(5)
        with self.assertRaises(ProviderCallBudgetExceededError):
            _generate_sanitized_questions(self.request, client, budget)
        self.assertEqual(budget.calls, 3)
        self.assertEqual(len(client.calls), 1)

    def test_failed_top_up_preserves_previously_verified_inventory(self):
        from unittest.mock import patch

        self.request["targetCount"] = 2
        client = FakeBedrockClient(
            [
                FakeBedrockClient.question_response(self.question),
                TimeoutError("Synthetic top-up timeout"),
            ]
        )
        metrics = {
            "ProviderCalls": 0,
            "BedrockInputTokens": 0,
            "BedrockOutputTokens": 0,
        }
        with patch.dict("os.environ", {"BEDROCK_FALLBACK_MODEL_ID": ""}):
            accepted = _generate_sanitized_questions(
                self.request, client, ProviderCallBudget(6), metrics
            )
        self.assertEqual([q["prompt"] for q in accepted], [self.question["prompt"]])
        self.assertEqual(accepted[0]["verificationVersion"], 1)
        self.assertEqual(metrics["QuestionQuality"]["provider"]["request_failed"], 1)

    def test_provider_failure_before_any_verified_inventory_still_fails(self):
        from unittest.mock import patch

        with patch.dict("os.environ", {"BEDROCK_FALLBACK_MODEL_ID": ""}):
            with self.assertRaises(ProviderError):
                _generate_sanitized_questions(
                    self.request,
                    FakeBedrockClient(TimeoutError("Synthetic timeout")),
                    ProviderCallBudget(6),
                )
