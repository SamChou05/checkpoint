import copy
import json
import os
import unittest
import uuid

import question_bank


SECRET = "unit-test-question-bank-secret-at-least-32-characters"
INSTALL_ID = "install-123"


class FakeQueue:
    def __init__(self):
        self.messages = []

    def send_message(self, **kwargs):
        self.messages.append(kwargs)
        return {"MessageId": "message-1"}


class ConditionalFailure(RuntimeError):
    response = {"Error": {"Code": "ConditionalCheckFailedException"}}


class OutboxDynamo:
    def __init__(self, job, *, failed_marks=0):
        self.job = job
        self.failed_marks = failed_marks
        self.mark_attempts = 0

    def get_item(self, **_kwargs):
        return {"Item": self.job}

    def update_item(self, **kwargs):
        self.mark_attempts += 1
        if self.failed_marks:
            self.failed_marks -= 1
            raise RuntimeError("simulated crash after SQS accepted the message")
        if (
            self.job["status"]["S"] != "queued"
            or self.job["enqueueStatus"]["S"] == "sent"
        ):
            raise ConditionalFailure()
        self.job["enqueueStatus"] = kwargs["ExpressionAttributeValues"][":sent"]
        return {}


class ClaimDynamo:
    def __init__(self, meta, pointer, questions):
        self.meta = meta
        self.pointer = pointer
        self.questions = list(questions)
        self.claims = {}
        self.transactions = []

    def get_item(self, **kwargs):
        key = kwargs["Key"]
        pk = key["pk"]["S"]
        sk = key["sk"]["S"]
        if sk == "META":
            return {"Item": self.meta}
        if pk.startswith("OWNER#"):
            return {"Item": self.pointer}
        if sk.startswith("CLAIM#") and sk in self.claims:
            return {"Item": self.claims[sk]}
        return {}

    def query(self, **kwargs):
        return {"Items": self.questions[: kwargs.get("Limit", len(self.questions))]}

    def transact_write_items(self, **kwargs):
        self.transactions.append(kwargs)
        for operation in kwargs["TransactItems"]:
            if "Update" in operation:
                update = operation["Update"]
                sk = update["Key"]["sk"]["S"]
                values = update["ExpressionAttributeValues"]
                if sk == "META" and ":after" in values:
                    self.meta["readyCount"] = values[":after"]
                    if ":afterGenerated" in values:
                        self.meta["generatedCount"] = values[":afterGenerated"]
                    if ":state" in values:
                        self.meta["state"] = values[":state"]
                elif sk.startswith("QUESTION#"):
                    for item in self.questions:
                        if item["sk"]["S"] == sk:
                            item["state"] = (
                                values.get(":terminal")
                                or values.get(":discarded")
                                or values[":claimed"]
                            )
            elif "Put" in operation:
                item = operation["Put"]["Item"]
                if item["sk"]["S"].startswith("CLAIM#"):
                    self.claims[item["sk"]["S"]] = item
        return {}


def _event():
    return {
        "requestContext": {"http": {"method": "POST", "sourceIp": "198.51.100.1"}},
        "headers": {"X-Checkpoint-Install-ID": INSTALL_ID},
        "body": "{}",
    }


def _ensure_payload():
    return {
        "goal": {"id": "goal-123", "title": "Study logic"},
        "contextRevision": "0123456789abcdef",
        "desiredCount": 40,
        "lowWatermark": 0,
        "targetCount": 20,
        "minimumDifficulty": 3,
    }


def _normalized_request():
    return {
        "goal": {"title": "Study logic"},
        "competencies": [],
        "existingPrompts": [],
        "existingQuestionCoverage": [],
        "reportedPrompts": [],
        "sourceDocuments": [],
        "targetCount": 20,
        "minimumDifficulty": 3,
        "difficultyGuidance": "Medium application",
    }


def _pending_job():
    return {
        "pk": {"S": "BANK#owner#bank"},
        "sk": {"S": "JOB#job-1"},
        "itemType": {"S": "job"},
        "jobID": {"S": "job-1"},
        "contextRevision": {"S": "revision-1"},
        "status": {"S": "queued"},
        "enqueueStatus": {"S": "pending"},
    }


def _stream_job_event(job, *, sequence_number="1"):
    return {
        "Records": [
            {
                "eventID": f"event-{sequence_number}",
                "eventName": "INSERT",
                "dynamodb": {
                    "SequenceNumber": sequence_number,
                    "NewImage": copy.deepcopy(job),
                },
            }
        ]
    }


def _meta(pk, bank_id, revision, *, desired, low, ready):
    owner_hash = pk.split("#")[1]
    goal_key = question_bank._secret_digest("goal", "goal-123")  # noqa: SLF001
    return {
        "pk": {"S": pk},
        "sk": {"S": "META"},
        "bankID": {"S": bank_id},
        "ownerHash": {"S": owner_hash},
        "goalKey": {"S": goal_key},
        "contextRevision": {"S": revision},
        "readyCount": {"N": str(ready)},
        "generatedCount": {"N": str(ready)},
        "desiredCount": {"N": str(desired)},
        "lowWatermark": {"N": str(low)},
        "state": {"S": "ready" if ready else "empty"},
        **(
            {"initialFillComplete": {"BOOL": True}}
            if low == 0 and ready >= desired
            else {}
        ),
    }


def _claim_records(*, low):
    owner_hash = question_bank._secret_digest("owner", INSTALL_ID)  # noqa: SLF001
    goal_key = question_bank._secret_digest("goal", "goal-123")  # noqa: SLF001
    revision = "0123456789abcdef"
    bank_id = question_bank._secret_digest(  # noqa: SLF001
        "bank", f"{owner_hash}:{goal_key}:{revision}"
    )
    pk = f"BANK#{owner_hash}#{bank_id}"
    meta = _meta(pk, bank_id, revision, desired=3, low=low, ready=1)
    pointer = {
        "pk": {"S": f"OWNER#{owner_hash}"},
        "sk": {"S": f"GOAL#{goal_key}"},
        "currentBankID": {"S": bank_id},
        "contextRevision": {"S": revision},
    }
    remote_id = str(uuid.UUID(int=1))
    question = {
        "pk": {"S": pk},
        "sk": {"S": f"QUESTION#{remote_id}"},
        "remoteID": {"S": remote_id},
        "state": {"S": "ready"},
        "questionJSON": {
            "S": json.dumps(
                {
                    "remoteID": remote_id,
                    "prompt": "Which statement follows?",
                    "expectedAnswer": "The supported statement.",
                    "choices": ["The supported statement.", "B", "C", "D"],
                    "explanation": "The facts support it.",
                    "topic": "Reasoning",
                    "difficulty": 3,
                    "format": "Multiple Choice",
                },
                separators=(",", ":"),
            )
        },
    }
    return bank_id, meta, pointer, question


class QuestionBankTestCase(unittest.TestCase):
    def setUp(self):
        os.environ.update(
            {
                "ALLOW_UNAUTHENTICATED_BACKEND": "true",
                "QUESTION_BANK_TABLE_NAME": "question-banks",
                "QUESTION_BANK_QUEUE_URL": "https://sqs.example/question-banks",
                "QUOTA_HASH_SECRET": SECRET,
            }
        )

    def tearDown(self):
        for key in [
            "ALLOW_UNAUTHENTICATED_BACKEND",
            "QUESTION_BANK_TABLE_NAME",
            "QUESTION_BANK_QUEUE_URL",
            "QUESTION_BANK_TTL_SECONDS",
            "QUESTION_BANK_FAILURE_COOLDOWN_SECONDS",
            "QUESTION_BANK_GENERATION_CHUNK_SIZE",
            "QUESTION_BANK_MAX_FAILED_GENERATION_JOBS",
            "QUESTION_BANK_MAX_RECEIVE_COUNT",
            "QUOTA_HASH_SECRET",
            "RATE_LIMIT_TABLE_NAME",
            "MAX_REQUESTS_PER_INSTALL_PER_DAY",
            "REQUIRE_RATE_LIMITING",
            "RATE_LIMIT_TTL_SECONDS",
        ]:
            os.environ.pop(key, None)
