import json
import os
import time
import unittest

import lambda_function


class FakeBedrockClient:
    def __init__(self, text):
        self.texts = text if isinstance(text, list) else [text]
        self.calls = []

    def converse(self, **kwargs):
        text_index = min(len(self.calls), len(self.texts) - 1)
        self.calls.append(kwargs)
        return {
            "output": {
                "message": {
                    "content": [
                        {
                            "text": self.texts[text_index],
                        }
                    ]
                }
            }
        }


class ConditionalCheckFailed(Exception):
    response = {"Error": {"Code": "ConditionalCheckFailedException"}}


class FakeDynamoClient:
    def __init__(self, fail_on_call=None):
        self.fail_on_call = fail_on_call
        self.calls = []

    def update_item(self, **kwargs):
        self.calls.append(kwargs)
        if self.fail_on_call == len(self.calls):
            raise ConditionalCheckFailed()
        return {}


class BedrockQuestionServiceTests(unittest.TestCase):
    def tearDown(self):
        for key in [
            "BEDROCK_MODEL_ID",
            "BEDROCK_FALLBACK_MODEL_ID",
            "CHECKPOINT_BACKEND_TOKEN",
            "MAX_QUESTIONS_PER_BATCH",
            "RATE_LIMIT_TABLE_NAME",
            "MAX_REQUESTS_PER_INSTALL_PER_DAY",
            "MAX_REQUESTS_PER_IP_PER_DAY",
            "RATE_LIMIT_TTL_SECONDS",
        ]:
            os.environ.pop(key, None)

    def test_generates_contract_response_from_bedrock_json(self):
        client = FakeBedrockClient(
            json.dumps(
                {
                    "questions": [
                        {
                            "prompt": "LSAT Logical Reasoning: All plaintiffs who filed late were dismissed. Rivera was not dismissed. Which assumption is needed?",
                            "expectedAnswer": "Every filing was either late or timely.",
                            "choices": [
                                "Every filing was either late or timely.",
                                "Rivera had the strongest claim.",
                                "Dismissed plaintiffs can appeal.",
                                "The court reviewed every document twice.",
                            ],
                            "explanation": "The conclusion needs a complete late-versus-timely split.",
                            "topic": "Logical Reasoning",
                            "difficulty": 3,
                            "format": "Multiple Choice",
                        }
                    ]
                }
            )
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=3, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertEqual(len(body["questions"]), 1)
        self.assertEqual(body["questions"][0]["format"], "Multiple Choice")
        self.assertEqual(body["questions"][0]["difficulty"], 3)
        self.assertEqual(client.calls[0]["modelId"], "google.gemma-3-4b-it")
        self.assertIn("Study for the LSAT", client.calls[0]["messages"][0]["content"][0]["text"])

    def test_accepts_provider_top_level_question_array(self):
        client = FakeBedrockClient(
            json.dumps(
                [
                    _raw_question(
                        "LSAT Logical Reasoning: If every credited claim requires evidence and Park's claim was credited, what follows?"
                    )
                ]
            )
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("LSAT Logical Reasoning", questions[0]["prompt"])

    def test_retries_once_when_provider_returns_non_json(self):
        client = FakeBedrockClient(
            [
                "Here are two LSAT questions in prose instead of JSON.",
                json.dumps({"questions": [_raw_question("LSAT Logical Reasoning: Which answer identifies the argument's required assumption?")]}),
            ]
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(len(client.calls), 2)
        retry_prompt = client.calls[1]["messages"][0]["content"][0]["text"]
        self.assertIn("previous response was not valid JSON", retry_prompt)
        self.assertEqual(len(json.loads(response["body"])["questions"]), 1)

    def test_uses_fallback_model_after_primary_json_failures(self):
        os.environ["BEDROCK_MODEL_ID"] = "google.gemma-3-4b-it"
        os.environ["BEDROCK_FALLBACK_MODEL_ID"] = "amazon.nova-micro-v1:0"
        client = FakeBedrockClient(
            [
                "Not JSON.",
                "Still not JSON.",
                json.dumps({"questions": [_raw_question("LSAT Logical Reasoning: Which assumption lets the conclusion follow?")]}),
            ]
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual([call["modelId"] for call in client.calls], [
            "google.gemma-3-4b-it",
            "google.gemma-3-4b-it",
            "amazon.nova-micro-v1:0",
        ])
        self.assertEqual(len(json.loads(response["body"])["questions"]), 1)

    def test_extracts_json_from_markdown_and_repairs_answer_choice(self):
        client = FakeBedrockClient(
            """
```json
{
  "questions": [
    {
      "prompt": "LSAT Reading Comprehension: A critic calls a policy useful but incomplete. What is the critic's attitude?",
      "expectedAnswer": "Qualified approval.",
      "choices": ["Total rejection.", "Neutral description.", "Confusion about the policy.", "Unqualified enthusiasm."],
      "explanation": "Useful is positive, while incomplete limits the approval.",
      "topic": "Reading Comprehension",
      "difficulty": 2,
      "format": "Multiple Choice"
    }
  ]
}
```
"""
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=4)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        question = json.loads(response["body"])["questions"][0]
        self.assertEqual(question["choices"][0], "Qualified approval.")
        self.assertEqual(question["difficulty"], 4)

    def test_filters_duplicates_and_study_strategy_prompts(self):
        client = FakeBedrockClient(
            json.dumps(
                {
                    "questions": [
                        {
                            "prompt": "Existing prompt",
                            "expectedAnswer": "A",
                            "choices": ["A", "B", "C", "D"],
                            "explanation": "Duplicate.",
                            "topic": "Logical Reasoning",
                            "difficulty": 3,
                            "format": "Multiple Choice",
                        },
                        {
                            "prompt": "How should you study for the LSAT after missing a flaw question?",
                            "expectedAnswer": "Review the flaw type.",
                            "choices": ["Review the flaw type.", "Open another app.", "Stop reading.", "Skip the topic."],
                            "explanation": "Study advice.",
                            "topic": "Study plan",
                            "difficulty": 3,
                            "format": "Multiple Choice",
                        },
                        {
                            "prompt": "LSAT Logical Reasoning: An argument infers causation from a before-after change. What flaw is most likely?",
                            "expectedAnswer": "It treats temporal order as sufficient proof of causation.",
                            "choices": [
                                "It treats temporal order as sufficient proof of causation.",
                                "It defines the conclusion too narrowly.",
                                "It proves the opposite conclusion.",
                                "It relies on a mathematical calculation.",
                            ],
                            "explanation": "A before-after pattern alone does not prove causation.",
                            "topic": "Logical Reasoning",
                            "difficulty": 4,
                            "format": "Multiple Choice",
                        },
                    ]
                }
            )
        )

        payload = _request_payload(target_count=3, minimum_difficulty=3)
        payload["existingPrompts"] = ["Existing prompt"]
        response = lambda_function.handle_http_request(_event(payload), bedrock_client=client)

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("causation", questions[0]["prompt"])

    def test_rejects_missing_goal(self):
        response = lambda_function.handle_http_request(_event({"targetCount": 3}))

        self.assertEqual(response["statusCode"], 400)
        self.assertIn("Missing goal", response["body"])

    def test_optional_backend_token(self):
        os.environ["CHECKPOINT_BACKEND_TOKEN"] = "test-token"

        response = lambda_function.handle_http_request(_event(_request_payload()))

        self.assertEqual(response["statusCode"], 401)

    def test_honors_model_and_batch_limit_environment(self):
        os.environ["BEDROCK_MODEL_ID"] = "amazon.custom-cheap-model-v1:0"
        os.environ["MAX_QUESTIONS_PER_BATCH"] = "2"
        client = FakeBedrockClient(
            json.dumps(
                {
                    "questions": [
                        _raw_question("Question one about LSAT assumptions?"),
                        _raw_question("Question two about LSAT weaken answers?"),
                        _raw_question("Question three about LSAT inference answers?"),
                    ]
                }
            )
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=10)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(len(json.loads(response["body"])["questions"]), 2)
        self.assertEqual(client.calls[0]["modelId"], "amazon.custom-cheap-model-v1:0")

    def test_rate_limit_counters_are_incremented_before_generation(self):
        os.environ["RATE_LIMIT_TABLE_NAME"] = "checkpoint-rate-limits"
        os.environ["MAX_REQUESTS_PER_INSTALL_PER_DAY"] = "8"
        os.environ["MAX_REQUESTS_PER_IP_PER_DAY"] = "80"
        os.environ["RATE_LIMIT_TTL_SECONDS"] = "172800"
        bedrock_client = FakeBedrockClient(json.dumps({"questions": [_raw_question("Question one about LSAT assumptions?")]}))
        dynamo_client = FakeDynamoClient()
        started_at = int(time.time())

        response = lambda_function.handle_http_request(
            _event(
                _request_payload(target_count=1),
                headers={"X-Checkpoint-Install-ID": "install-123"},
                source_ip="203.0.113.10",
            ),
            bedrock_client=bedrock_client,
            dynamodb_client=dynamo_client,
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(len(dynamo_client.calls), 2)
        install_key = dynamo_client.calls[0]["Key"]["rateKey"]["S"]
        ip_key = dynamo_client.calls[1]["Key"]["rateKey"]["S"]
        self.assertTrue(install_key.startswith("install#install-123#"))
        self.assertTrue(ip_key.startswith("ip#203.0.113.10#"))
        self.assertEqual(dynamo_client.calls[0]["ExpressionAttributeValues"][":limit"]["N"], "8")
        self.assertEqual(dynamo_client.calls[1]["ExpressionAttributeValues"][":limit"]["N"], "80")
        expires_at = int(dynamo_client.calls[0]["ExpressionAttributeValues"][":expiresAt"]["N"])
        self.assertGreaterEqual(expires_at - started_at, 172800)
        self.assertEqual(len(bedrock_client.calls), 1)

    def test_rate_limit_returns_429_before_bedrock_call(self):
        os.environ["RATE_LIMIT_TABLE_NAME"] = "checkpoint-rate-limits"
        bedrock_client = FakeBedrockClient(json.dumps({"questions": [_raw_question("Question one about LSAT assumptions?")]}))
        dynamo_client = FakeDynamoClient(fail_on_call=1)

        response = lambda_function.handle_http_request(
            _event(
                _request_payload(target_count=1),
                headers={"X-Checkpoint-Install-ID": "install-123"},
                source_ip="203.0.113.10",
            ),
            bedrock_client=bedrock_client,
            dynamodb_client=dynamo_client,
        )

        self.assertEqual(response["statusCode"], 429)
        self.assertEqual(len(bedrock_client.calls), 0)


def _event(payload, headers=None, source_ip="198.51.100.4"):
    return {
        "requestContext": {"http": {"method": "POST", "sourceIp": source_ip}},
        "headers": headers or {},
        "body": json.dumps(payload),
    }


def _request_payload(target_count=5, minimum_difficulty=3):
    return {
        "goal": {
            "title": "Study for the LSAT",
            "deadline": "2026-07-01T00:00:00Z",
            "category": "Exam Prep",
            "currentLevel": "Solid on basics, weak on timed logical reasoning.",
            "focusAreas": "Logical reasoning, reading comprehension",
            "learningTarget": "LSAT",
            "contentTopics": ["Logical Reasoning", "Reading Comprehension"],
            "questionDirective": "Generate original LSAT-style Logical Reasoning and Reading Comprehension questions.",
            "preferredQuestionStyle": "Multiple Choice",
        },
        "competencies": [],
        "existingPrompts": [],
        "reportedPrompts": [],
        "targetCount": target_count,
        "minimumDifficulty": minimum_difficulty,
    }


def _raw_question(prompt):
    return {
        "prompt": prompt,
        "expectedAnswer": "The answer that follows from the stimulus.",
        "choices": [
            "The answer that follows from the stimulus.",
            "A choice that goes beyond the stimulus.",
            "A choice that contradicts the premise.",
            "A choice that is irrelevant to the conclusion.",
        ],
        "explanation": "The correct answer stays closest to the stimulus.",
        "topic": "Logical Reasoning",
        "difficulty": 3,
        "format": "Multiple Choice",
    }


if __name__ == "__main__":
    unittest.main()
