import copy
import json
import os
import unittest
import uuid
from unittest import mock

import lambda_function
import question_bank


SECRET = "unit-test-question-bank-secret-at-least-32-characters"
INSTALL_ID = "install-123"


class FakeQueue:
    def __init__(self):
        self.messages = []

    def send_message(self, **kwargs):
        self.messages.append(kwargs)
        return {"MessageId": "message-1"}


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
            if "Delete" in operation:
                sk = operation["Delete"]["Key"]["sk"]["S"]
                self.questions = [item for item in self.questions if item["sk"]["S"] != sk]
            elif "Update" in operation and operation["Update"]["Key"]["sk"]["S"] == "META":
                values = operation["Update"]["ExpressionAttributeValues"]
                if ":after" in values:
                    self.meta["readyCount"] = values[":after"]
                    self.meta["state"] = values[":state"]
            elif "Put" in operation:
                item = operation["Put"]["Item"]
                if item["sk"]["S"].startswith("CLAIM#"):
                    self.claims[item["sk"]["S"]] = item
        return {}


class QuestionBankTests(unittest.TestCase):
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
            "QUOTA_HASH_SECRET",
        ]:
            os.environ.pop(key, None)

    def test_ensure_bank_identity_uses_owner_goal_and_explicit_revision(self):
        payload = _ensure_payload()
        normalized = _normalized_request()
        dynamo = object()
        queue = object()
        captured_bank_keys = []

        def update_configuration(
            _client,
            _table,
            bank_key,
            context_revision,
            _normalized,
            desired,
            low,
            _now,
        ):
            captured_bank_keys.append(bank_key["pk"]["S"])
            return _meta(
                bank_key["pk"]["S"],
                bank_key["pk"]["S"].split("#")[2],
                context_revision,
                desired=desired,
                low=low,
                ready=desired,
            )

        with (
            mock.patch.object(question_bank, "_activate_goal_version", return_value=""),
            mock.patch.object(question_bank, "_require_current_bank"),
            mock.patch.object(
                question_bank,
                "_update_bank_configuration",
                side_effect=update_configuration,
            ),
        ):
            first = question_bank.ensure_bank(
                payload,
                _event(),
                lambda _: normalized,
                dynamodb_client=dynamo,
                sqs_client=queue,
            )
            changed_poll = dict(payload)
            changed_poll["existingPrompts"] = ["A newly answered prompt"]
            second = question_bank.ensure_bank(
                changed_poll,
                _event(),
                lambda _: normalized,
                dynamodb_client=dynamo,
                sqs_client=queue,
            )

        self.assertEqual(first["bankID"], second["bankID"])
        self.assertEqual(captured_bank_keys[0], captured_bank_keys[1])
        self.assertNotIn(INSTALL_ID, captured_bank_keys[0])
        changed_revision = dict(payload)
        changed_revision["contextRevision"] = "fedcba9876543210"
        with (
            mock.patch.object(question_bank, "_activate_goal_version", return_value=""),
            mock.patch.object(question_bank, "_require_current_bank"),
            mock.patch.object(
                question_bank,
                "_update_bank_configuration",
                side_effect=update_configuration,
            ),
        ):
            third = question_bank.ensure_bank(
                changed_revision,
                _event(),
                lambda _: normalized,
                dynamodb_client=dynamo,
                sqs_client=queue,
            )
        self.assertNotEqual(first["bankID"], third["bankID"])

    def test_ensure_requires_context_revision_and_caps_server_target(self):
        missing = _ensure_payload()
        missing.pop("contextRevision")
        with self.assertRaises(question_bank.QuestionBankError) as raised:
            question_bank.ensure_bank(
                missing,
                _event(),
                lambda _: _normalized_request(),
                dynamodb_client=object(),
                sqs_client=object(),
            )
        self.assertEqual(raised.exception.status_code, 400)

        oversized = _ensure_payload()
        oversized["desiredCount"] = 101
        with self.assertRaises(question_bank.QuestionBankError) as raised:
            question_bank.ensure_bank(
                oversized,
                _event(),
                lambda _: _normalized_request(),
                dynamodb_client=object(),
                sqs_client=object(),
            )
        self.assertEqual(raised.exception.status_code, 400)

    def test_claim_is_owner_bound_atomic_and_idempotent(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        questions = []
        for integer in range(1, 4):
            item = copy.deepcopy(question)
            remote_id = str(uuid.UUID(int=integer))
            item["sk"] = {"S": f"QUESTION#{remote_id}"}
            stored = json.loads(item["questionJSON"]["S"])
            stored["remoteID"] = remote_id
            item["remoteID"] = {"S": remote_id}
            item["questionJSON"] = {
                "S": json.dumps(stored, separators=(",", ":"))
            }
            questions.append(item)
        dynamo = ClaimDynamo(meta, pointer, questions)
        queue = FakeQueue()
        payload = {"bankID": bank_id, "claimID": "claim-1", "limit": 5}

        first = question_bank.claim_questions(
            payload,
            _event(),
            dynamodb_client=dynamo,
            sqs_client=queue,
        )
        second = question_bank.claim_questions(
            payload,
            _event(),
            dynamodb_client=dynamo,
            sqs_client=queue,
        )

        self.assertEqual(first, second)
        self.assertEqual(len(first["questions"]), 1)
        self.assertEqual(first["questions"][0]["remoteID"], str(uuid.UUID(int=1)))
        self.assertEqual(len(dynamo.transactions), 1)
        self.assertEqual(queue.messages, [])

    def test_claim_rejects_meta_owned_by_a_different_principal(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["ownerHash"] = {"S": "0" * 64}
        dynamo = ClaimDynamo(meta, pointer, [question])
        with self.assertRaises(question_bank.QuestionBankError) as raised:
            question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "claim-1", "limit": 5},
                _event(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )
        self.assertEqual(raised.exception.status_code, 404)
        self.assertEqual(dynamo.transactions, [])

    def test_claim_reconciles_meta_count_after_question_ttl_expiry(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["readyCount"] = {"N": "5"}
        meta["generatedCount"] = {"N": "5"}
        dynamo = ClaimDynamo(meta, pointer, [question])

        response = question_bank.claim_questions(
            {"bankID": bank_id, "claimID": "ttl-reconcile", "limit": 2},
            _event(),
            dynamodb_client=dynamo,
            sqs_client=FakeQueue(),
        )

        self.assertEqual(len(response["questions"]), 1)
        self.assertEqual(response["readyCount"], 0)
        self.assertEqual(dynamo.meta["readyCount"], {"N": "0"})
        meta_update = next(
            item["Update"]
            for item in dynamo.transactions[0]["TransactItems"]
            if "Update" in item
        )
        self.assertEqual(
            meta_update["ExpressionAttributeValues"][":observed"],
            {"N": "5"},
        )

    def test_zero_watermark_is_finite_but_positive_watermark_refills(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        finite = ClaimDynamo(meta, pointer, [question])
        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "finite-claim", "limit": 1},
                _event(),
                dynamodb_client=finite,
                sqs_client=FakeQueue(),
            )
        refill.assert_not_called()

        bank_id, meta, pointer, question = _claim_records(low=1)
        replenishing = ClaimDynamo(meta, pointer, [question])
        with mock.patch.object(question_bank, "_ensure_refill") as refill:
            response = question_bank.claim_questions(
                {"bankID": bank_id, "claimID": "member-claim", "limit": 1},
                _event(),
                dynamodb_client=replenishing,
                sqs_client=FakeQueue(),
            )
        self.assertEqual(response["status"], "queued")
        refill.assert_called_once()

    def test_finite_bank_claim_then_ensure_never_exceeds_initial_generated_target(self):
        bank_id, meta, pointer, question = _claim_records(low=0)
        meta["desiredCount"] = {"N": "3"}
        meta["readyCount"] = {"N": "3"}
        meta["generatedCount"] = {"N": "3"}
        meta["initialFillComplete"] = {"BOOL": True}
        dynamo = ClaimDynamo(meta, pointer, [question])

        claimed = question_bank.claim_questions(
            {"bankID": bank_id, "claimID": "after-initial-fill", "limit": 1},
            _event(),
            dynamodb_client=dynamo,
            sqs_client=FakeQueue(),
        )
        self.assertEqual(claimed["readyCount"], 2)
        self.assertEqual(dynamo.meta["generatedCount"]["N"], "3")

        ensure_payload = _ensure_payload()
        ensure_payload["desiredCount"] = 3
        with (
            mock.patch.object(question_bank, "_activate_goal_version", return_value=bank_id),
            mock.patch.object(question_bank, "_require_current_bank"),
            mock.patch.object(
                question_bank,
                "_update_bank_configuration",
                return_value=dynamo.meta,
            ),
            mock.patch.object(question_bank, "_ensure_refill") as refill,
        ):
            ensured = question_bank.ensure_bank(
                ensure_payload,
                _event(),
                lambda _: _normalized_request(),
                dynamodb_client=dynamo,
                sqs_client=FakeQueue(),
            )
        self.assertEqual(ensured["readyCount"], 2)
        refill.assert_not_called()

    def test_worker_failure_reopens_enqueue_lease_for_dlq_recovery(self):
        class CaptureDynamo:
            def __init__(self):
                self.transaction = None

            def transact_write_items(self, **kwargs):
                self.transaction = kwargs["TransactItems"]

        dynamo = CaptureDynamo()
        question_bank._reset_job_for_retry(  # noqa: SLF001
            dynamo,
            "question-banks",
            {"pk": {"S": "BANK#owner#bank"}, "sk": {"S": "META"}},
            {"pk": {"S": "BANK#owner#bank"}, "sk": {"S": "JOB#job-1"}},
            "lease-token",
        )
        job_update = dynamo.transaction[0]["Update"]
        self.assertIn("enqueueStatus = :pending", job_update["UpdateExpression"])
        self.assertEqual(
            job_update["ExpressionAttributeValues"][":pending"], {"S": "pending"}
        )
        self.assertEqual(job_update["ExpressionAttributeValues"][":zero"], {"N": "0"})

    def test_prepared_question_ids_are_stable_uuid_and_deduplicated(self):
        raw = {
            "prompt": "Which statement follows?",
            "expectedAnswer": "The supported statement.",
            "choices": ["The supported statement.", "B", "C", "D"],
            "explanation": "The facts support it.",
            "topic": "Reasoning",
            "difficulty": 3,
            "format": "Multiple Choice",
        }
        first = question_bank._prepare_questions("a" * 64, [raw, raw], [])  # noqa: SLF001
        second = question_bank._prepare_questions("a" * 64, [raw], [])  # noqa: SLF001
        self.assertEqual(len(first), 1)
        self.assertEqual(first, second)
        uuid.UUID(first[0]["remoteID"])

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
            mock.patch.object(lambda_function, "_generate_sanitized_questions") as generation,
        ):
            response = lambda_function.handle_http_request(event)

        self.assertEqual(response["statusCode"], 202)
        ensure.assert_called_once()
        quota.assert_not_called()
        generation.assert_not_called()


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


if __name__ == "__main__":
    unittest.main()
