import json
import os
import unittest
import uuid


class FakeBedrockClient:
    def __init__(self, text, *, auto_review=True):
        self.texts = text if isinstance(text, list) else [text]
        self.calls = []
        self.review_calls = []
        self.solution_calls = []
        self.auto_review = auto_review
        self.last_questions = []

    def converse(self, **kwargs):
        prompt = kwargs["messages"][0]["content"][0]["text"]
        if self.auto_review and "<question_solution_json>" in prompt:
            self.solution_calls.append(kwargs)
            data = json.loads(
                prompt.split("<question_solution_json>\n", 1)[1].split(
                    "\n</question_solution_json>", 1
                )[0]
            )
            solutions = [
                {
                    "index": item["index"],
                    "answer": "Independent fixture solution of the stated problem.",
                    "limitations": "",
                    "outcome": "resolved",
                    "assumptionsRequired": [],
                }
                for item in data["items"]
            ]
            return {
                "output": {
                    "message": {
                        "content": [{"text": json.dumps({"solutions": solutions})}]
                    }
                }
            }
        if self.auto_review and "<question_review_json>" in prompt:
            # Existing provider tests use a trusted synthetic reviewer. Dedicated
            # verification tests disable this and script independent verdicts.
            self.review_calls.append(kwargs)
            data = json.loads(
                prompt.split("<question_review_json>\n", 1)[1].split(
                    "\n</question_review_json>", 1
                )[0]
            )
            reviews = []
            for item in data["items"]:
                question = next(
                    q
                    for q in self.last_questions
                    if q["prompt"].strip() == item["prompt"]
                )
                reviews.append(
                    {
                        "index": item["index"],
                        "valid": True,
                        "answer": question["expectedAnswer"],
                        "difficulty": question.get("difficulty", 3),
                        "explanation": question.get("explanation")
                        or "Independent fixture reasoning supports this answer.",
                        "choiceExplanations": {
                            choice: "Fixture reasoning explains this choice in the stated scenario."
                            for choice in item["choices"]
                        },
                    }
                )
            return {
                "output": {
                    "message": {"content": [{"text": json.dumps({"reviews": reviews})}]}
                }
            }
        text_index = min(len(self.calls), len(self.texts) - 1)
        self.calls.append(kwargs)
        value = self.texts[text_index]
        if isinstance(value, str):
            from question_quality import _extract_json_object

            try:
                self.last_questions = _extract_json_object(value).get("questions", [])
            except Exception:
                self.last_questions = []
        if isinstance(value, Exception):
            raise value
        if isinstance(value, dict):
            return value
        return {
            "output": {
                "message": {
                    "content": [
                        {
                            "text": value,
                        }
                    ]
                }
            }
        }

    @staticmethod
    def question_response(*questions):
        return json.dumps({"questions": list(questions)})

    @classmethod
    def returning_questions(cls, *questions):
        return cls(cls.question_response(*questions))


class TransactionQuotaExceeded(Exception):
    response = {
        "Error": {"Code": "TransactionCanceledException"},
        "CancellationReasons": [
            {"Code": "ConditionalCheckFailed"},
            {"Code": "None"},
        ],
    }


class FakeDynamoClient:
    def __init__(self, fail_on_call=None):
        self.fail_on_call = fail_on_call
        self.calls = []

    def transact_write_items(self, **kwargs):
        self.calls.append(kwargs)
        if self.fail_on_call == len(self.calls):
            raise TransactionQuotaExceeded()
        return {}


class FakeLambdaContext:
    def __init__(self, remaining_milliseconds):
        self.remaining_milliseconds = remaining_milliseconds

    def get_remaining_time_in_millis(self):
        return self.remaining_milliseconds


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
            "focusAreas": "Logical reasoning, reading comprehension",
            "learningTarget": "LSAT",
            "contentTopics": ["Logical Reasoning", "Reading Comprehension"],
            "questionDirective": "Generate original LSAT-style Logical Reasoning and Reading Comprehension questions.",
            "needsSkillMap": False,
            "preferredQuestionStyle": "Multiple Choice",
        },
        "competencies": [],
        "existingPrompts": [],
        "existingQuestionCoverage": [],
        "reportedPrompts": [],
        "targetCount": target_count,
        "minimumDifficulty": minimum_difficulty,
    }


def _raw_question(
    prompt,
    difficulty=3,
    *,
    expected_answer=None,
    explanation=None,
    topic="Logical Reasoning",
):
    scenario_id = (
        sum((index + 1) * ord(character) for index, character in enumerate(prompt))
        % 100_000
    )
    resolved_answer = expected_answer or (
        f"The argument requires assumption link {scenario_id} between its evidence and conclusion."
    )
    resolved_explanation = explanation or (
        f"Assumption link {scenario_id} supplies the missing connection between this argument's "
        "evidence and conclusion."
    )
    return {
        "prompt": prompt,
        "expectedAnswer": resolved_answer,
        "choices": [
            resolved_answer,
            "The evidence proves a broader conclusion than the argument makes.",
            "The conclusion directly contradicts every stated premise.",
            "The argument depends only on an unrelated numerical calculation.",
        ],
        "explanation": resolved_explanation,
        "topic": topic,
        "difficulty": difficulty,
        "format": "Multiple Choice",
    }


def _skill_map(version=1, *, empty_objectives=False):
    first_skill_id = str(uuid.UUID("11111111-1111-4111-8111-111111111111")).upper()
    second_skill_id = str(uuid.UUID("22222222-2222-4222-8222-222222222222")).upper()
    return {
        "version": version,
        "skills": [
            {
                "id": first_skill_id,
                "name": "Argument Analysis",
                "objectives": []
                if empty_objectives
                else [
                    {
                        "id": str(
                            uuid.UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
                        ).upper(),
                        "name": "Identify necessary assumptions",
                    }
                ],
            },
            {
                "id": second_skill_id,
                "name": "Evidence Evaluation",
                "objectives": [
                    {
                        "id": str(
                            uuid.UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
                        ).upper(),
                        "name": "Distinguish correlation from causation",
                    }
                ],
            },
        ],
    }


class BackendTestCase(unittest.TestCase):
    def setUp(self):
        os.environ["ALLOW_UNAUTHENTICATED_BACKEND"] = "true"

    def tearDown(self):
        for key in [
            "BEDROCK_MODEL_ID",
            "SKILL_MAP_MODEL_ID",
            "BEDROCK_FALLBACK_MODEL_ID",
            "BEDROCK_REASONING_EFFORT",
            "CHECKPOINT_BACKEND_TOKEN",
            "ALLOW_UNAUTHENTICATED_BACKEND",
            "MAX_QUESTIONS_PER_BATCH",
            "RATE_LIMIT_TABLE_NAME",
            "QUOTA_HASH_SECRET",
            "REQUIRE_RATE_LIMITING",
            "MAX_REQUESTS_PER_INSTALL_PER_DAY",
            "MAX_REQUESTS_PER_IP_PER_DAY",
            "RATE_LIMIT_TTL_SECONDS",
            "MAX_REQUEST_BODY_BYTES",
            "MAX_PROVIDER_CALLS_PER_REQUEST",
            "MIN_PROVIDER_REMAINING_MILLISECONDS",
            "BEDROCK_CONNECT_TIMEOUT_SECONDS",
            "BEDROCK_READ_TIMEOUT_SECONDS",
            "BEDROCK_SDK_MAX_ATTEMPTS",
            "SERVICE_MODE",
            "SERVICE_RETRY_AFTER_SECONDS",
            "DEPLOYMENT_ENVIRONMENT",
            "BEDROCK_GUARDRAIL_IDENTIFIER",
            "BEDROCK_GUARDRAIL_VERSION",
            "EMIT_STRUCTURED_METRICS",
            "CHECKPOINT_PROMPT_VARIANT",
        ]:
            os.environ.pop(key, None)
