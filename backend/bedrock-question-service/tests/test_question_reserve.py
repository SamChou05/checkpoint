import copy
import json
import os
import time
import unittest
from pathlib import Path

import lambda_function


INSTALL_ID = "install-12345678"
INSTALL_SECRET = "a-client-generated-secret-with-enough-entropy-123456"
GOAL_ID = "goal-1234"
GOAL_REVISION = "revision-1"


class ConditionalCheckFailed(Exception):
    response = {"Error": {"Code": "ConditionalCheckFailedException"}}


class FakeDynamoClient:
    def __init__(self):
        self.items = {}
        self.rate_counts = {}
        self.put_calls = []
        self.get_calls = []
        self.delete_calls = []
        self.query_calls = []
        self.fail_next_conditional_put = False

    @staticmethod
    def _item_key(table_name, item):
        return (
            table_name,
            item.get("pk", {}).get("S", ""),
            item.get("sk", {}).get("S", ""),
        )

    def put_item(self, **kwargs):
        self.put_calls.append(copy.deepcopy(kwargs))
        item = copy.deepcopy(kwargs["Item"])
        key = self._item_key(kwargs["TableName"], item)
        existing = self.items.get(key)
        condition = kwargs.get("ConditionExpression", "")
        values = kwargs.get("ExpressionAttributeValues", {})

        if self.fail_next_conditional_put:
            self.fail_next_conditional_put = False
            raise ConditionalCheckFailed()
        if condition == "attribute_not_exists(pk)" and existing is not None:
            raise ConditionalCheckFailed()
        if "secretHash = :secretHash" in condition:
            if existing is None or existing.get("secretHash") != values.get(":secretHash"):
                raise ConditionalCheckFailed()
        for field, token in [
            ("recordVersion", ":recordVersion"),
            ("goalRevision", ":goalRevision"),
            ("jobVersion", ":jobVersion"),
            ("leaseToken", ":leaseToken"),
        ]:
            if token in values:
                if existing is None or existing.get(field) != values[token]:
                    raise ConditionalCheckFailed()

        self.items[key] = item
        return {}

    def get_item(self, **kwargs):
        self.get_calls.append(copy.deepcopy(kwargs))
        key = (
            kwargs["TableName"],
            kwargs["Key"]["pk"]["S"],
            kwargs["Key"]["sk"]["S"],
        )
        item = self.items.get(key)
        return {"Item": copy.deepcopy(item)} if item is not None else {}

    def delete_item(self, **kwargs):
        self.delete_calls.append(copy.deepcopy(kwargs))
        key = (
            kwargs["TableName"],
            kwargs["Key"]["pk"]["S"],
            kwargs["Key"]["sk"]["S"],
        )
        self.items.pop(key, None)
        return {}

    def update_item(self, **kwargs):
        key = (kwargs["TableName"], kwargs["Key"]["rateKey"]["S"])
        count = self.rate_counts.get(key, 0)
        limit = int(kwargs["ExpressionAttributeValues"][":limit"]["N"])
        if count >= limit:
            raise ConditionalCheckFailed()
        self.rate_counts[key] = count + 1
        return {}

    def query(self, **kwargs):
        self.query_calls.append(copy.deepcopy(kwargs))
        partition = kwargs["ExpressionAttributeValues"][":partition"]["S"]
        now = int(kwargs["ExpressionAttributeValues"][":now"]["N"])
        matching = [
            copy.deepcopy(item)
            for (table_name, _, _), item in self.items.items()
            if table_name == kwargs["TableName"]
            and item.get("duePartition", {}).get("S") == partition
            and int(item.get("nextAttemptAt", {}).get("N", "0")) <= now
        ]
        matching.sort(key=lambda item: int(item["nextAttemptAt"]["N"]))
        return {"Items": matching[: kwargs.get("Limit", 25)]}

    def reserve_state(self, goal_id=GOAL_ID):
        item = self.items.get(
            (
                os.environ["RESERVE_TABLE_NAME"],
                f"INSTALL#{INSTALL_ID}",
                f"GOAL#{goal_id}",
            )
        )
        return lambda_function._reserve_state_from_item(copy.deepcopy(item)) if item else None


class FakeSQSClient:
    def __init__(self):
        self.messages = []
        self.fail_next = False

    def send_message(self, **kwargs):
        if self.fail_next:
            self.fail_next = False
            raise RuntimeError("SQS unavailable")
        self.messages.append(copy.deepcopy(kwargs))
        return {"MessageId": f"message-{len(self.messages)}"}

    def worker_event(self, index=-1):
        return {
            "Records": [
                {
                    "messageId": f"worker-{index}",
                    "body": self.messages[index]["MessageBody"],
                }
            ]
        }


class FakeBedrockClient:
    def __init__(self, payloads):
        self.payloads = payloads if isinstance(payloads, list) else [payloads]
        self.calls = []

    def converse(self, **kwargs):
        index = min(len(self.calls), len(self.payloads) - 1)
        payload = self.payloads[index]
        self.calls.append(copy.deepcopy(kwargs))
        if isinstance(payload, Exception):
            raise payload
        text = payload if isinstance(payload, str) else json.dumps(payload)
        return {"output": {"message": {"content": [{"text": text}]}}}


class QuestionReserveTests(unittest.TestCase):
    def setUp(self):
        os.environ["ALLOW_UNAUTHENTICATED_BACKEND"] = "true"
        os.environ["RESERVE_TABLE_NAME"] = "checkpoint-reserve"
        os.environ["RESERVE_QUEUE_URL"] = "https://sqs.example/reserve"
        self.dynamo = FakeDynamoClient()
        self.sqs = FakeSQSClient()

    def tearDown(self):
        for key in [
            "ALLOW_UNAUTHENTICATED_BACKEND",
            "CHECKPOINT_BACKEND_TOKEN",
            "RESERVE_TABLE_NAME",
            "RESERVE_QUEUE_URL",
            "RESERVE_TTL_SECONDS",
            "RATE_LIMIT_TABLE_NAME",
            "MAX_REQUESTS_PER_INSTALL_PER_DAY",
            "MAX_REQUESTS_PER_IP_PER_DAY",
            "MAX_RESERVE_BATCHES_PER_INSTALL_PER_DAY",
            "BEDROCK_MODEL_ID",
            "BEDROCK_FALLBACK_MODEL_ID",
        ]:
            os.environ.pop(key, None)

    def test_register_requires_bearer_and_client_secret_and_is_idempotent(self):
        os.environ["CHECKPOINT_BACKEND_TOKEN"] = "backend-token"
        missing_bearer = self._request("/reserve/register", {})
        self.assertEqual(missing_bearer["statusCode"], 401)

        missing_secret = self._request(
            "/reserve/register",
            {},
            bearer="backend-token",
            include_secret=False,
        )
        self.assertEqual(missing_secret["statusCode"], 401)
        self.assertEqual(
            json.loads(missing_secret["body"]),
            json.loads(missing_bearer["body"]),
        )

        first = self._request("/reserve/register", {}, bearer="backend-token")
        second = self._request("/reserve/register", {}, bearer="backend-token")
        conflict = self._request(
            "/reserve/register",
            {},
            bearer="backend-token",
            secret="a-different-client-secret-with-32-characters",
        )

        self.assertEqual(first["statusCode"], 200)
        self.assertEqual(second["statusCode"], 200)
        self.assertEqual(conflict["statusCode"], 409)
        self.assertNotIn(INSTALL_SECRET, first["body"])
        auth = self.dynamo.items[("checkpoint-reserve", f"INSTALL#{INSTALL_ID}", "AUTH")]
        self.assertEqual(
            auth["secretHash"]["S"],
            lambda_function._secret_hash(INSTALL_SECRET),
        )

    def test_same_secret_registration_renews_auth_ttl(self):
        os.environ["RESERVE_TTL_SECONDS"] = "100"
        lambda_function._reserve_register(self.dynamo, INSTALL_ID, INSTALL_SECRET, 1_000)
        renewed = lambda_function._reserve_register(
            self.dynamo,
            INSTALL_ID,
            INSTALL_SECRET,
            1_050,
        )
        auth = self.dynamo.items[("checkpoint-reserve", f"INSTALL#{INSTALL_ID}", "AUTH")]

        self.assertEqual(renewed["expiresAt"], 1_150)
        self.assertEqual(auth["expiresAt"]["N"], "1150")
        self.assertEqual(auth["createdAt"]["N"], "1000")

    def test_register_rate_limit_returns_429(self):
        os.environ["RATE_LIMIT_TABLE_NAME"] = "rate-limits"
        os.environ["MAX_REQUESTS_PER_INSTALL_PER_DAY"] = "1"
        self.assertEqual(self._request("/reserve/register", {})["statusCode"], 200)
        response = self._request("/reserve/register", {})
        self.assertEqual(response["statusCode"], 429)

    def test_reserve_routes_accept_a_configured_base_path_prefix(self):
        response = self._request("/api/reserve/register", {})
        self.assertEqual(response["statusCode"], 200)

    def test_synchronous_generation_remains_valid_at_a_base_path(self):
        event = {
            "rawPath": "/api",
            "requestContext": {"http": {"method": "POST", "path": "/api"}},
            "headers": {},
            "body": json.dumps(_generation_request()),
        }
        response = lambda_function.handle_http_request(
            event,
            bedrock_client=FakeBedrockClient(
                {"questions": [_raw_question("Which LSAT conclusion follows?")]}
            ),
        )
        self.assertEqual(response["statusCode"], 200)

    def test_sync_requires_install_auth_and_rejects_stale_sequences(self):
        self._register()
        payload = self._sync_payload(sequence=4)
        invalid = self._request("/reserve/sync", payload, secret="x" * 40)
        self.assertEqual(invalid["statusCode"], 401)

        first = self._request("/reserve/sync", payload)
        repeated = self._request("/reserve/sync", payload)
        stale = self._request("/reserve/sync", self._sync_payload(sequence=3))
        conflicting = self._request(
            "/reserve/sync",
            self._sync_payload(sequence=4, desired=2),
        )

        self.assertEqual(first["statusCode"], 200)
        self.assertEqual(repeated["statusCode"], 200)
        self.assertEqual(stale["statusCode"], 409)
        self.assertEqual(conflicting["statusCode"], 409)
        self.assertEqual(len(self.sqs.messages), 1)
        message = json.loads(self.sqs.messages[0]["MessageBody"])
        self.assertEqual(set(message), {"pk", "sk", "goalRevision", "jobVersion"})
        self.assertNotIn("generationRequest", self.sqs.messages[0]["MessageBody"])

    def test_new_revision_invalidates_stale_worker_result(self):
        self._register()
        self._request("/reserve/sync", self._sync_payload(sequence=1))
        stale_event = self.sqs.worker_event(0)
        self._request(
            "/reserve/sync",
            self._sync_payload(sequence=2, revision="revision-2"),
        )
        bedrock = FakeBedrockClient({"questions": [_raw_question("Which LSAT inference follows?")]})

        result = lambda_function.handle_reserve_worker_event(
            stale_event,
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=1_000,
        )

        self.assertEqual(result, {"batchItemFailures": []})
        self.assertEqual(len(bedrock.calls), 0)
        self.assertEqual(self.dynamo.reserve_state()["goalRevision"], "revision-2")

    def test_desired_zero_purges_and_stale_worker_cannot_store(self):
        self._register()
        self._request("/reserve/sync", self._sync_payload(sequence=1))
        stale_event = self.sqs.worker_event(0)
        stop = self._sync_payload(sequence=2, desired=0)
        stop.pop("generationRequest")
        response = self._request("/reserve/sync", stop)
        bedrock = FakeBedrockClient({"questions": [_raw_question("Which LSAT claim follows?")]})
        lambda_function.handle_reserve_worker_event(
            stale_event,
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=1_000,
        )
        state = self.dynamo.reserve_state()

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(state["state"], "stopped")
        self.assertEqual(state["requestJSON"], "")
        self.assertEqual(state["preparedQuestions"], [])
        self.assertEqual(state["deliveryQuestions"], [])
        self.assertEqual(state["duePartition"], "")
        self.assertEqual(len(bedrock.calls), 0)

        resumed = self._request("/reserve/sync", self._sync_payload(sequence=3))
        self.assertEqual(json.loads(resumed["body"])["state"], "queued")

    def test_worker_success_is_deduplicated_and_pull_retries_same_delivery(self):
        self._register()
        self._request("/reserve/sync", self._sync_payload(sequence=1))
        event = self.sqs.worker_event()
        bedrock = FakeBedrockClient(
            {"questions": [_raw_question("Which LSAT assumption is required?")]}
        )
        first = lambda_function.handle_reserve_worker_event(
            event,
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=1_000,
        )
        duplicate = lambda_function.handle_reserve_worker_event(
            event,
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=1_001,
        )
        first_pull = self._request("/reserve/pull", self._goal_payload())
        second_pull = self._request("/reserve/pull", self._goal_payload())
        first_body = json.loads(first_pull["body"])
        second_body = json.loads(second_pull["body"])

        self.assertEqual(first, {"batchItemFailures": []})
        self.assertEqual(duplicate, {"batchItemFailures": []})
        self.assertEqual(len(bedrock.calls), 1)
        self.assertEqual(first_body["delivery"], second_body["delivery"])
        self.assertEqual(first_body["delivery"]["goalRevision"], GOAL_REVISION)
        self.assertIn("reserveQuestionID", first_body["delivery"]["questions"][0])
        state_item = self.dynamo.items[
            ("checkpoint-reserve", f"INSTALL#{INSTALL_ID}", f"GOAL#{GOAL_ID}")
        ]
        self.assertNotIn("preparedQuestionsJSON", state_item)
        self.assertIn("deliveryQuestionsJSON", state_item)

    def test_partial_worker_success_keeps_remaining_deficit_due_for_recovery(self):
        self._register()
        self._request("/reserve/sync", self._sync_payload(sequence=1, desired=3))
        bedrock = FakeBedrockClient(
            {"questions": [_raw_question("Which LSAT assumption is required?")]}
        )

        lambda_function.handle_reserve_worker_event(
            self.sqs.worker_event(),
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=1_000,
        )
        partial = self.dynamo.reserve_state()

        self.assertEqual(len(partial["preparedQuestions"]), 1)
        self.assertEqual(partial["state"], "idle")
        self.assertEqual(partial["duePartition"], lambda_function.RESERVE_DUE_PARTITION)
        self.assertEqual(partial["nextAttemptAt"], 1_000)

        recovered = lambda_function.handle_reserve_worker_event(
            {"operation": "reserveRecovery"},
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=1_000,
        )
        self.assertEqual(recovered["recovered"], 1)
        self.assertEqual(self.dynamo.reserve_state()["state"], "queued")

    def test_ack_is_idempotent_never_clears_wrong_delivery_and_refills(self):
        delivery = self._prepare_and_pull()
        wrong = self._request(
            "/reserve/ack",
            {**self._goal_payload(), "deliveryID": "wrong-delivery"},
        )
        self.assertEqual(wrong["statusCode"], 200)
        self.assertEqual(self.dynamo.reserve_state()["deliveryID"], delivery["deliveryID"])

        accepted = self._request(
            "/reserve/ack",
            {**self._goal_payload(), "deliveryID": delivery["deliveryID"]},
        )
        queued_after_ack = len(self.sqs.messages)
        repeated = self._request(
            "/reserve/ack",
            {**self._goal_payload(), "deliveryID": delivery["deliveryID"]},
        )

        self.assertEqual(accepted["statusCode"], 200)
        self.assertEqual(repeated["statusCode"], 200)
        self.assertEqual(len(self.sqs.messages), queued_after_ack)
        state = self.dynamo.reserve_state()
        self.assertEqual(state["deliveryQuestions"], [])
        self.assertEqual(state["refillEpoch"], 1)
        self.assertEqual(state["state"], "queued")

    def test_ack_history_prevents_same_question_from_refill(self):
        self._register()
        self._request("/reserve/sync", self._sync_payload(sequence=1))
        duplicate_prompt = "Which LSAT assumption is required by the stimulus?"
        novel_prompt = "Which LSAT inference is best supported by the stimulus?"
        novel_question = _raw_question(novel_prompt)
        novel_question["expectedAnswer"] = "The inference directly supported by the stated evidence."
        novel_question["choices"][0] = novel_question["expectedAnswer"]
        novel_question["explanation"] = "Only that inference follows from the stated evidence."
        novel_question["subtopic"] = "supported inference"
        novel_question["avenue"] = "Interpretation or inference"
        bedrock = FakeBedrockClient(
            [
                {"questions": [_raw_question(duplicate_prompt)]},
                {
                    "questions": [
                        _raw_question(duplicate_prompt),
                        novel_question,
                    ]
                },
            ]
        )
        lambda_function.handle_reserve_worker_event(
            self.sqs.worker_event(0),
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=1_000,
        )
        delivery = json.loads(
            self._request("/reserve/pull", self._goal_payload())["body"]
        )["delivery"]
        self._request(
            "/reserve/ack",
            {**self._goal_payload(), "deliveryID": delivery["deliveryID"]},
        )
        # A later sync whose client history is sparse must not erase the compact
        # delivery history retained by the server.
        self._request("/reserve/sync", self._sync_payload(sequence=2))
        stored_request = json.loads(self.dynamo.reserve_state()["requestJSON"])
        self.assertIn(duplicate_prompt, stored_request["existingPrompts"])
        lambda_function.handle_reserve_worker_event(
            self.sqs.worker_event(-1),
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=1_100,
        )
        prompts = [q["prompt"] for q in self.dynamo.reserve_state()["preparedQuestions"]]

        self.assertEqual(prompts, [novel_prompt])
        self.assertNotIn("sourcePrompt", self.dynamo.reserve_state()["preparedQuestions"][0])

    def test_worker_failure_backs_off_and_stops_after_five_attempts(self):
        self._register()
        self._request("/reserve/sync", self._sync_payload(sequence=1))
        bedrock = FakeBedrockClient(RuntimeError("provider unavailable"))
        message_index = 0
        now = 1_000

        for attempt in range(lambda_function.RESERVE_MAX_FAILURES):
            lambda_function.handle_reserve_worker_event(
                self.sqs.worker_event(message_index),
                bedrock_client=bedrock,
                dynamodb_client=self.dynamo,
                sqs_client=self.sqs,
                now=now,
            )
            state = self.dynamo.reserve_state()
            if attempt < lambda_function.RESERVE_MAX_FAILURES - 1:
                self.assertEqual(state["state"], "idle")
                now = state["nextAttemptAt"]
                recovered = lambda_function.handle_reserve_worker_event(
                    {"operation": "reserveRecovery"},
                    dynamodb_client=self.dynamo,
                    sqs_client=self.sqs,
                    now=now,
                )
                self.assertEqual(recovered["recovered"], 1)
                message_index += 1

        state = self.dynamo.reserve_state()
        self.assertEqual(state["state"], "failed")
        self.assertEqual(state["failureCount"], lambda_function.RESERVE_MAX_FAILURES)
        self.assertEqual(state["duePartition"], "")
        self.assertEqual(
            len(bedrock.calls),
            lambda_function.RESERVE_MAX_FAILURES
            * len(lambda_function._model_attempts()),
        )

        queued_count = len(self.sqs.messages)
        same_request = self._request(
            "/reserve/sync",
            self._sync_payload(sequence=2),
        )
        self.assertEqual(json.loads(same_request["body"])["state"], "failed")
        self.assertEqual(len(self.sqs.messages), queued_count)

        changed = self._sync_payload(sequence=3)
        changed["generationRequest"]["goal"]["questionDirective"] = (
            "Generate LSAT questions with a newly corrected scope."
        )
        changed_response = self._request("/reserve/sync", changed)
        self.assertEqual(json.loads(changed_response["body"])["state"], "queued")
        self.assertEqual(self.dynamo.reserve_state()["failureCount"], 0)

    def test_sync_during_worker_backoff_does_not_bypass_due_time(self):
        self._register()
        self._request("/reserve/sync", self._sync_payload(sequence=1))
        bedrock = FakeBedrockClient(RuntimeError("provider unavailable"))
        now = int(time.time())
        lambda_function.handle_reserve_worker_event(
            self.sqs.worker_event(0),
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=now,
        )
        state_before = self.dynamo.reserve_state()
        messages_before = len(self.sqs.messages)

        response = self._request(
            "/reserve/sync",
            self._sync_payload(sequence=2),
        )
        state_after = self.dynamo.reserve_state()

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(state_after["state"], "idle")
        self.assertEqual(state_after["failureCount"], 1)
        self.assertEqual(state_after["nextAttemptAt"], state_before["nextAttemptAt"])
        self.assertEqual(len(self.sqs.messages), messages_before)

    def test_conditional_races_reload_instead_of_returning_503(self):
        delivery = self._prepare_and_pull()
        # A duplicate ack that loses its compare-and-put returns the still-held
        # state, and a retry remains safe.
        self.dynamo.fail_next_conditional_put = True
        raced_ack = self._request(
            "/reserve/ack",
            {**self._goal_payload(), "deliveryID": delivery["deliveryID"]},
        )
        self.assertEqual(raced_ack["statusCode"], 200)
        self.assertEqual(self.dynamo.reserve_state()["deliveryID"], delivery["deliveryID"])

        accepted = self._request(
            "/reserve/ack",
            {**self._goal_payload(), "deliveryID": delivery["deliveryID"]},
        )
        self.assertEqual(accepted["statusCode"], 200)

        # A concurrent sync compare failure is retried against the latest item.
        self.dynamo.fail_next_conditional_put = True
        sync = self._request("/reserve/sync", self._sync_payload(sequence=2))
        self.assertEqual(sync["statusCode"], 200)

    def test_pull_conditional_race_returns_current_state_and_retry_holds_batch(self):
        self._register()
        self._request("/reserve/sync", self._sync_payload(sequence=1))
        bedrock = FakeBedrockClient(
            {"questions": [_raw_question("Which LSAT inference follows from the facts?")]}
        )
        lambda_function.handle_reserve_worker_event(
            self.sqs.worker_event(0),
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=1_000,
        )
        self.dynamo.fail_next_conditional_put = True
        raced = self._request("/reserve/pull", self._goal_payload())
        retried = self._request("/reserve/pull", self._goal_payload())

        self.assertEqual(raced["statusCode"], 200)
        self.assertIsNone(json.loads(raced["body"])["delivery"])
        self.assertIsNotNone(json.loads(retried["body"])["delivery"])

    def test_send_failure_and_expired_generating_job_remain_recoverable(self):
        self._register()
        self.sqs.fail_next = True
        self._request("/reserve/sync", self._sync_payload(sequence=1))
        state = self.dynamo.reserve_state()
        self.assertEqual(state["state"], "idle")
        self.assertEqual(state["duePartition"], lambda_function.RESERVE_DUE_PARTITION)

        recovered = lambda_function.handle_reserve_worker_event(
            {"operation": "reserveRecovery"},
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=state["nextAttemptAt"],
        )
        self.assertEqual(recovered["recovered"], 1)
        queued = self.dynamo.reserve_state()
        queued["state"] = "generating"
        queued["leaseToken"] = "abandoned-lease"
        queued["leaseExpiresAt"] = 2_000
        queued["nextAttemptAt"] = 2_000
        queued["duePartition"] = lambda_function.RESERVE_DUE_PARTITION
        lambda_function._reserve_save_state(
            self.dynamo,
            queued,
            queued["recordVersion"],
        )
        before_version = self.dynamo.reserve_state()["jobVersion"]

        recovered = lambda_function.handle_reserve_worker_event(
            {"operation": "reserveRecovery"},
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=2_000,
        )
        after = self.dynamo.reserve_state()
        self.assertEqual(recovered["recovered"], 1)
        self.assertEqual(after["state"], "queued")
        self.assertGreater(after["jobVersion"], before_version)

    def test_worker_daily_quota_blocks_bedrock_until_next_utc_day(self):
        os.environ["RATE_LIMIT_TABLE_NAME"] = "rate-limits"
        os.environ["MAX_RESERVE_BATCHES_PER_INSTALL_PER_DAY"] = "1"
        now = int(time.time())
        delivery = self._prepare_and_pull(now=now)
        self._request(
            "/reserve/ack",
            {**self._goal_payload(), "deliveryID": delivery["deliveryID"]},
        )
        bedrock = FakeBedrockClient(
            {"questions": [_raw_question("Which new LSAT inference follows?")]}
        )
        before_calls = len(bedrock.calls)
        lambda_function.handle_reserve_worker_event(
            self.sqs.worker_event(-1),
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=now + 1,
        )
        state = self.dynamo.reserve_state()

        self.assertEqual(len(bedrock.calls), before_calls)
        self.assertEqual(state["state"], "quotaLimited")
        self.assertGreater(state["nextAttemptAt"], now + 1)
        messages_before = len(self.sqs.messages)
        retry_sync = self._request("/reserve/sync", self._sync_payload(sequence=2))
        self.assertEqual(json.loads(retry_sync["body"])["state"], "quotaLimited")
        self.assertEqual(len(self.sqs.messages), messages_before)

    def test_delete_is_authenticated_goal_scoped_and_idempotent(self):
        self._register()
        self._request("/reserve/sync", self._sync_payload(sequence=1))
        payload = {"goalIDs": [GOAL_ID]}
        first = self._request("/reserve/delete", payload)
        second = self._request("/reserve/delete", payload)

        self.assertEqual(first["statusCode"], 200)
        self.assertEqual(second["statusCode"], 200)
        self.assertIsNone(self.dynamo.reserve_state())
        self.assertIn(
            ("checkpoint-reserve", f"INSTALL#{INSTALL_ID}", "AUTH"),
            self.dynamo.items,
        )

    def test_pull_revision_mismatch_never_returns_delivery(self):
        self._prepare_and_pull()
        response = self._request(
            "/reserve/pull",
            {"goalID": GOAL_ID, "goalRevision": "old-revision"},
        )
        self.assertEqual(response["statusCode"], 409)
        self.assertNotIn("questions", response["body"])

    def test_worst_case_utf8_reserve_item_stays_below_dynamo_limit(self):
        state = lambda_function._new_reserve_state(
            INSTALL_ID,
            GOAL_ID,
            GOAL_REVISION,
            1,
            "d" * 64,
            "c" * 64,
            20,
            json.dumps({"history": "😀" * 22_000}, ensure_ascii=False),
            1_000,
        )
        question = {
            "reserveQuestionID": "00000000-0000-0000-0000-000000000001",
            "prompt": "😀" * 280,
            "expectedAnswer": "😀" * 280,
            "choices": ["😀" * 140] * 4,
            "explanation": "😀" * 420,
            "topic": "😀" * 48,
            "subtopic": "😀" * 64,
            "avenue": "Transfer to a new scenario",
            "difficulty": 5,
            "format": "Multiple Choice",
        }
        state["preparedQuestions"] = [copy.deepcopy(question) for _ in range(20)]
        item = lambda_function._reserve_state_item(state)
        size = lambda_function._reserve_item_size_bytes(item)

        self.assertLess(size, 400 * 1024)
        self.assertLessEqual(size, lambda_function.MAX_RESERVE_ITEM_BYTES)

    def test_sam_template_declares_encrypted_bounded_recovery_resources(self):
        template = Path(__file__).resolve().parents[1].joinpath("template.yaml").read_text()

        self.assertIn("QuestionReserveTable:", template)
        self.assertIn("ProjectionType: KEYS_ONLY", template)
        self.assertGreaterEqual(template.count("SSEEnabled: true"), 2)
        self.assertGreaterEqual(template.count("SqsManagedSseEnabled: true"), 2)
        self.assertIn("Type: ScheduleV2", template)
        self.assertIn("ScheduleExpression: rate(15 minutes)", template)
        self.assertIn("FunctionResponseTypes:", template)
        self.assertIn("MaximumConcurrency: 4", template)

    def _register(self):
        response = self._request("/reserve/register", {})
        self.assertEqual(response["statusCode"], 200)

    def _prepare_and_pull(self, now=1_000):
        if (
            "checkpoint-reserve",
            f"INSTALL#{INSTALL_ID}",
            "AUTH",
        ) not in self.dynamo.items:
            self._register()
        self._request("/reserve/sync", self._sync_payload(sequence=1))
        bedrock = FakeBedrockClient(
            {"questions": [_raw_question("Which LSAT flaw is present in the argument?")]}
        )
        lambda_function.handle_reserve_worker_event(
            self.sqs.worker_event(0),
            bedrock_client=bedrock,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
            now=now,
        )
        body = json.loads(self._request("/reserve/pull", self._goal_payload())["body"])
        return body["delivery"]

    def _request(
        self,
        path,
        payload,
        *,
        secret=INSTALL_SECRET,
        include_secret=True,
        bearer=None,
    ):
        headers = {"X-Checkpoint-Install-ID": INSTALL_ID}
        if include_secret:
            headers["X-Checkpoint-Install-Secret"] = secret
        if bearer:
            headers["Authorization"] = f"Bearer {bearer}"
        event = {
            "rawPath": path,
            "requestContext": {
                "http": {
                    "method": "POST",
                    "path": path,
                    "sourceIp": "198.51.100.10",
                }
            },
            "headers": headers,
            "body": json.dumps(payload),
        }
        return lambda_function.handle_http_request(
            event,
            dynamodb_client=self.dynamo,
            sqs_client=self.sqs,
        )

    @staticmethod
    def _goal_payload(revision=GOAL_REVISION):
        return {"goalID": GOAL_ID, "goalRevision": revision}

    @staticmethod
    def _sync_payload(sequence, desired=1, revision=GOAL_REVISION):
        return {
            "goalID": GOAL_ID,
            "goalRevision": revision,
            "syncSequence": sequence,
            "desiredReserveCount": desired,
            "generationRequest": _generation_request(target_count=max(1, desired)),
        }


def _generation_request(target_count=1):
    return {
        "goal": {
            "title": "Study for the LSAT",
            "deadline": "2026-07-01T00:00:00Z",
            "category": "Exam Prep",
            "focusAreas": "Logical reasoning",
            "learningTarget": "LSAT",
            "contentTopics": ["Logical Reasoning"],
            "questionDirective": "Generate original LSAT questions.",
            "needsSkillMap": False,
            "preferredQuestionStyle": "Multiple Choice",
        },
        "competencies": [],
        "existingPrompts": [],
        "existingQuestionCoverage": [],
        "coveragePlan": [],
        "reportedPrompts": [],
        "reportedQuestionFeedback": [],
        "targetCount": target_count,
        "minimumDifficulty": 3,
    }


def _raw_question(prompt):
    return {
        "prompt": prompt,
        "expectedAnswer": "The answer that follows from the stimulus.",
        "choices": [
            "The answer that follows from the stimulus.",
            "A choice that contradicts the stimulus.",
            "A choice that adds an unsupported claim.",
            "A choice that is irrelevant to the conclusion.",
        ],
        "explanation": "The correct answer stays closest to the supplied stimulus.",
        "topic": "Logical Reasoning",
        "subtopic": "argument evaluation",
        "avenue": "Application",
        "difficulty": 3,
        "format": "Multiple Choice",
    }


if __name__ == "__main__":
    unittest.main()
