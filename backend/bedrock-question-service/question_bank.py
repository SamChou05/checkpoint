"""Durable asynchronous question-bank inventory backed by DynamoDB and SQS."""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import re
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Callable


LOGGER = logging.getLogger(__name__)

MAX_DESIRED_COUNT = 100
MAX_CLAIM_COUNT = 20
DEFAULT_BANK_TTL_SECONDS = 30 * 24 * 60 * 60
TOMBSTONE_TTL_SECONDS = 24 * 60 * 60
ENQUEUE_LEASE_SECONDS = 30
WORKER_LEASE_SECONDS = 180


class QuestionBankError(RuntimeError):
    def __init__(self, status_code: int, message: str, code: str):
        super().__init__(message)
        self.status_code = status_code
        self.code = code


class StaleBankError(RuntimeError):
    pass


def ensure_bank(
    payload: dict[str, Any],
    event: dict[str, Any],
    normalize_request: Callable[[dict[str, Any]], dict[str, Any]],
    *,
    dynamodb_client: Any | None = None,
    sqs_client: Any | None = None,
) -> dict[str, Any]:
    """Create/update a versioned bank and durably request any missing inventory."""
    table_name, queue_url = _configuration()
    client = dynamodb_client or _dynamodb_client()
    queue = sqs_client or _sqs_client()
    owner_digest = _owner_digest(event)

    goal = payload.get("goal")
    if not isinstance(goal, dict):
        raise QuestionBankError(400, "Missing goal object.", "invalid_request")
    goal_id = _required_identifier(goal.get("id"), "goal.id")
    desired_count = _required_int(payload.get("desiredCount"), "desiredCount", 1, MAX_DESIRED_COUNT)
    low_maximum = desired_count - 1
    low_watermark = _required_int(
        payload.get("lowWatermark", min(10, low_maximum)),
        "lowWatermark",
        0,
        low_maximum,
    )

    generation_payload = dict(payload)
    generation_payload["targetCount"] = min(desired_count, MAX_CLAIM_COUNT)
    normalized = normalize_request(generation_payload)
    context_revision = _required_revision(payload.get("contextRevision"))
    goal_key = _secret_digest("goal", goal_id)
    bank_id = _secret_digest("bank", f"{owner_digest}:{goal_key}:{context_revision}")
    bank_key = _bank_key(owner_digest, bank_id)
    pointer_key = _pointer_key(owner_digest, goal_key)
    now = int(time.time())

    previous_bank_id = _activate_goal_version(
        client,
        table_name,
        bank_key,
        pointer_key,
        bank_id,
        context_revision,
        goal_key,
        normalized,
        desired_count,
        low_watermark,
        now,
    )
    if previous_bank_id and previous_bank_id != bank_id:
        _mark_bank_superseded(client, table_name, owner_digest, previous_bank_id, now)

    meta = _update_bank_configuration(
        client,
        table_name,
        bank_key,
        context_revision,
        normalized,
        desired_count,
        low_watermark,
        now,
    )
    ready_count = _number(meta, "readyCount")
    generated_count = _number(meta, "generatedCount")
    finite_fill_complete = low_watermark == 0 and generated_count >= desired_count
    inventory_progress = generated_count if low_watermark == 0 else ready_count
    if inventory_progress >= desired_count:
        if low_watermark == 0 and not _boolean(meta, "initialFillComplete"):
            _mark_initial_fill_complete(client, table_name, bank_key, now)
            meta = _get_item(client, table_name, bank_key, consistent=True) or meta
    elif not finite_fill_complete:
        _ensure_refill(
            client,
            queue,
            table_name,
            queue_url,
            bank_key,
            pointer_key,
            meta,
            now,
        )
        meta = _get_item(client, table_name, bank_key, consistent=True) or meta

    _require_current_bank(client, table_name, pointer_key, bank_id)
    return _bank_response(meta)


def claim_questions(
    payload: dict[str, Any],
    event: dict[str, Any],
    *,
    dynamodb_client: Any | None = None,
    sqs_client: Any | None = None,
) -> dict[str, Any]:
    """Atomically remove ready questions and persist the response by claim ID."""
    table_name, queue_url = _configuration()
    client = dynamodb_client or _dynamodb_client()
    queue = sqs_client or _sqs_client()
    owner_digest = _owner_digest(event)
    bank_id = _required_hex_identifier(payload.get("bankID"), "bankID")
    claim_id = _required_identifier(payload.get("claimID"), "claimID")
    limit = _required_int(payload.get("limit"), "limit", 1, MAX_CLAIM_COUNT)
    bank_key = _bank_key(owner_digest, bank_id)
    claim_key = {"pk": bank_key["pk"], "sk": _s(f"CLAIM#{_plain_digest(claim_id)}")}

    meta = _get_item(client, table_name, bank_key, consistent=True)
    _require_active_meta(meta, owner_digest)
    pointer_key = _pointer_key(owner_digest, _string(meta, "goalKey"))
    _require_current_bank(client, table_name, pointer_key, bank_id)

    existing_claim = _get_item(client, table_name, claim_key, consistent=True)
    if existing_claim:
        return _stored_claim(existing_claim)

    for _ in range(4):
        meta = _get_item(client, table_name, bank_key, consistent=True)
        _require_active_meta(meta, owner_digest)
        observed_ready = _number(meta, "readyCount")
        all_ready_items = _query_questions(
            client,
            table_name,
            bank_key,
            MAX_DESIRED_COUNT,
        )
        question_items = all_ready_items[:limit]
        questions = [_question_from_item(item) for item in question_items]
        # QUESTION records have their own TTL. Reconcile the cached counter to
        # the strongly consistent inventory instead of trusting a stale META.
        after_count = len(all_ready_items) - len(question_items)
        desired_count = _number(meta, "desiredCount")
        low_watermark = _number(meta, "lowWatermark")
        needs_refill = (
            low_watermark > 0
            and after_count <= low_watermark
            and after_count < desired_count
        )
        response = {
            "bankID": bank_id,
            "status": "queued" if needs_refill else ("ready" if after_count else "empty"),
            "readyCount": after_count,
            "targetCount": desired_count,
            "questions": questions,
        }
        now = int(time.time())
        transaction: list[dict[str, Any]] = []
        for item in question_items:
            transaction.append(
                {
                    "Delete": {
                        "TableName": table_name,
                        "Key": {"pk": item["pk"], "sk": item["sk"]},
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                }
            )
        transaction.extend(
            [
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": bank_key,
                        "UpdateExpression": "SET readyCount = :after, #state = :state, updatedAt = :now, expiresAt = :ttl",
                        "ConditionExpression": "readyCount = :observed AND attribute_not_exists(tombstonedAt)",
                        "ExpressionAttributeNames": {"#state": "state"},
                        "ExpressionAttributeValues": {
                            ":after": _n(after_count),
                            ":observed": _n(observed_ready),
                            ":state": _s(response["status"]),
                            ":now": _n(now),
                            ":ttl": _n(now + _bank_ttl_seconds()),
                        },
                    }
                },
                {
                    "Put": {
                        "TableName": table_name,
                        "Item": {
                            **claim_key,
                            "itemType": _s("claim"),
                            "responseJSON": _s(_json(response)),
                            "createdAt": _n(now),
                            "expiresAt": _n(now + _bank_ttl_seconds()),
                        },
                        "ConditionExpression": "attribute_not_exists(pk)",
                    }
                },
                {
                    "ConditionCheck": {
                        "TableName": table_name,
                        "Key": pointer_key,
                        "ConditionExpression": "currentBankID = :bank",
                        "ExpressionAttributeValues": {":bank": _s(bank_id)},
                    }
                },
            ]
        )
        try:
            client.transact_write_items(TransactItems=transaction)
        except Exception as error:
            existing_claim = _get_item(client, table_name, claim_key, consistent=True)
            if existing_claim:
                return _stored_claim(existing_claim)
            if _is_conditional_failure(error):
                continue
            raise

        if needs_refill:
            refreshed = _get_item(client, table_name, bank_key, consistent=True)
            if refreshed:
                try:
                    _ensure_refill(
                        client,
                        queue,
                        table_name,
                        queue_url,
                        bank_key,
                        pointer_key,
                        refreshed,
                        now,
                    )
                except Exception:
                    # The claim is already committed and must not become an error.
                    LOGGER.exception("Question-bank refill scheduling failed after claim")
        return response

    raise QuestionBankError(409, "Question inventory changed; retry the claim.", "claim_conflict")


def delete_bank(
    bank_id: str,
    event: dict[str, Any],
    *,
    dynamodb_client: Any | None = None,
) -> None:
    """Tombstone a bank immediately and best-effort purge its child records."""
    table_name, _ = _configuration()
    client = dynamodb_client or _dynamodb_client()
    owner_digest = _owner_digest(event)
    bank_id = _required_hex_identifier(bank_id, "bankID")
    bank_key = _bank_key(owner_digest, bank_id)
    meta = _get_item(client, table_name, bank_key, consistent=True)
    if not meta:
        return
    now = int(time.time())
    client.update_item(
        TableName=table_name,
        Key=bank_key,
        UpdateExpression=(
            "SET #state = :deleted, tombstonedAt = :now, updatedAt = :now, expiresAt = :ttl "
            "REMOVE generationRequest, activeJobID"
        ),
        ExpressionAttributeNames={"#state": "state"},
        ExpressionAttributeValues={
            ":deleted": _s("deleted"),
            ":now": _n(now),
            ":ttl": _n(now + TOMBSTONE_TTL_SECONDS),
        },
    )
    goal_key = _string(meta, "goalKey")
    if goal_key:
        pointer_key = _pointer_key(owner_digest, goal_key)
        try:
            client.update_item(
                TableName=table_name,
                Key=pointer_key,
                UpdateExpression="SET updatedAt = :now, expiresAt = :ttl REMOVE currentBankID, contextRevision",
                ConditionExpression="currentBankID = :bank",
                ExpressionAttributeValues={
                    ":now": _n(now),
                    ":ttl": _n(now + TOMBSTONE_TTL_SECONDS),
                    ":bank": _s(bank_id),
                },
            )
        except Exception as error:
            if not _is_conditional_failure(error):
                raise
    _purge_bank_children(client, table_name, bank_key)


def handle_worker_event(
    event: dict[str, Any],
    context: Any,
    generate_questions: Callable[[dict[str, Any]], list[dict[str, Any]]],
    *,
    dynamodb_client: Any | None = None,
    sqs_client: Any | None = None,
) -> dict[str, list[dict[str, str]]]:
    """SQS partial-batch handler; failed records remain visible for retry/DLQ."""
    failures: list[dict[str, str]] = []
    client = dynamodb_client or _dynamodb_client()
    queue = sqs_client or _sqs_client()
    for record in event.get("Records", []):
        message_id = str(record.get("messageId", "unknown"))
        try:
            message = json.loads(record.get("body", ""))
            _process_job(message, context, generate_questions, client, queue)
        except Exception:
            LOGGER.exception("Asynchronous question-bank worker failed")
            failures.append({"itemIdentifier": message_id})
    return {"batchItemFailures": failures}


def _process_job(
    message: dict[str, Any],
    context: Any,
    generate_questions: Callable[[dict[str, Any]], list[dict[str, Any]]],
    client: Any,
    queue: Any,
) -> None:
    del context  # Generation deadline enforcement is supplied by the caller callback.
    table_name, queue_url = _configuration()
    bank_pk = _required_internal_string(message.get("bankPK"), "bankPK")
    job_id = _required_internal_string(message.get("jobID"), "jobID")
    context_revision = _required_internal_string(
        message.get("contextRevision"), "contextRevision"
    )
    bank_key = {"pk": _s(bank_pk), "sk": _s("META")}
    job_key = {"pk": _s(bank_pk), "sk": _s(f"JOB#{job_id}")}
    now = int(time.time())
    lease_token = str(uuid.uuid4())
    try:
        acquired = client.update_item(
            TableName=table_name,
            Key=job_key,
            UpdateExpression=(
                "SET #status = :processing, leaseToken = :token, leaseUntil = :lease, updatedAt = :now"
            ),
            ConditionExpression=(
                "#status = :queued OR (#status = :processing AND leaseUntil < :now)"
            ),
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":queued": _s("queued"),
                ":processing": _s("processing"),
                ":token": _s(lease_token),
                ":lease": _n(now + WORKER_LEASE_SECONDS),
                ":now": _n(now),
            },
            ReturnValues="ALL_NEW",
        ).get("Attributes", {})
    except Exception as error:
        if not _is_conditional_failure(error):
            raise
        job = _get_item(client, table_name, job_key, consistent=True)
        if not job or _string(job, "status") in {"complete", "superseded", "rate_limited"}:
            return
        raise

    meta = _get_item(client, table_name, bank_key, consistent=True)
    if (
        not meta
        or meta.get("tombstonedAt")
        or _string(meta, "contextRevision") != context_revision
    ):
        _finish_stale_job(client, table_name, job_key, lease_token)
        return
    owner_digest, bank_id = _parse_bank_pk(bank_pk)
    pointer_key = _pointer_key(owner_digest, _string(meta, "goalKey"))
    pointer = _get_item(client, table_name, pointer_key, consistent=True)
    if not pointer or _string(pointer, "currentBankID") != bank_id:
        _finish_stale_job(client, table_name, job_key, lease_token)
        return

    ready_count = _number(meta, "readyCount")
    generated_count = _number(meta, "generatedCount")
    desired_count = _number(meta, "desiredCount")
    low_watermark = _number(meta, "lowWatermark")
    inventory_progress = generated_count if low_watermark == 0 else ready_count
    deficit = max(0, desired_count - inventory_progress)
    if deficit == 0:
        _complete_job_without_questions(client, table_name, bank_key, job_key, lease_token, now)
        return

    _consume_worker_quota(client, table_name, job_key, acquired, owner_digest)
    generation_request = json.loads(_string(meta, "generationRequest"))
    existing_items = _query_questions(client, table_name, bank_key, MAX_DESIRED_COUNT)
    existing_questions = [_question_from_item(item) for item in existing_items]
    generation_request["targetCount"] = min(MAX_CLAIM_COUNT, deficit)
    generation_request["existingPrompts"] = list(
        dict.fromkeys(
            generation_request.get("existingPrompts", [])
            + [question.get("prompt", "") for question in existing_questions]
        )
    )[-30:]
    generation_request["existingQuestionCoverage"] = (
        generation_request.get("existingQuestionCoverage", [])
        + [
            {
                "topic": question.get("topic", ""),
                "prompt": question.get("prompt", ""),
                "expectedAnswer": question.get("expectedAnswer", ""),
                "difficulty": question.get("difficulty", 1),
            }
            for question in existing_questions
        ]
    )[-30:]

    try:
        generated = generate_questions(generation_request)
        prepared = _prepare_questions(bank_id, generated, existing_items)
        if not prepared:
            raise RuntimeError("Provider returned no new usable questions.")
        _commit_generated_questions(
            client,
            table_name,
            bank_key,
            job_key,
            pointer_key,
            bank_id,
            context_revision,
            lease_token,
            prepared,
        )
    except Exception:
        _reset_job_for_retry(client, table_name, bank_key, job_key, lease_token)
        raise

    refreshed = _get_item(client, table_name, bank_key, consistent=True)
    if refreshed and not refreshed.get("tombstonedAt"):
        _ensure_refill(
            client,
            queue,
            table_name,
            queue_url,
            bank_key,
            pointer_key,
            refreshed,
            int(time.time()),
        )


def _activate_goal_version(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
    pointer_key: dict[str, Any],
    bank_id: str,
    context_revision: str,
    goal_key: str,
    normalized: dict[str, Any],
    desired_count: int,
    low_watermark: int,
    now: int,
) -> str:
    existing_meta = _get_item(client, table_name, bank_key, consistent=True)
    if existing_meta and existing_meta.get("tombstonedAt"):
        raise QuestionBankError(410, "Question bank was deleted.", "bank_deleted")
    if not existing_meta:
        owner_hash, _ = _parse_bank_pk(_string_from_key(bank_key["pk"]))
        item = {
            **bank_key,
            "itemType": _s("meta"),
            "bankID": _s(bank_id),
            "goalKey": _s(goal_key),
            "contextRevision": _s(context_revision),
            "ownerHash": _s(owner_hash),
            "generationRequest": _s(_json(normalized)),
            "desiredCount": _n(desired_count),
            "lowWatermark": _n(low_watermark),
            "readyCount": _n(0),
            "generatedCount": _n(0),
            "state": _s("empty"),
            "createdAt": _n(now),
            "updatedAt": _n(now),
            "expiresAt": _n(now + _bank_ttl_seconds()),
        }
        try:
            client.put_item(
                TableName=table_name,
                Item=item,
                ConditionExpression="attribute_not_exists(pk)",
            )
        except Exception as error:
            if not _is_conditional_failure(error):
                raise

    for _ in range(4):
        pointer = _get_item(client, table_name, pointer_key, consistent=True)
        previous_bank_id = _string(pointer, "currentBankID") if pointer else ""
        if previous_bank_id == bank_id:
            try:
                client.update_item(
                    TableName=table_name,
                    Key=pointer_key,
                    UpdateExpression=(
                        "SET contextRevision = :revision, updatedAt = :now, expiresAt = :ttl"
                    ),
                    ConditionExpression="currentBankID = :bank",
                    ExpressionAttributeValues={
                        ":revision": _s(context_revision),
                        ":now": _n(now),
                        ":ttl": _n(now + _bank_ttl_seconds()),
                        ":bank": _s(bank_id),
                    },
                )
                return previous_bank_id
            except Exception as error:
                if not _is_conditional_failure(error):
                    raise
                continue
        values = {
            ":bank": _s(bank_id),
            ":revision": _s(context_revision),
            ":now": _n(now),
            ":ttl": _n(now + _bank_ttl_seconds()),
        }
        if pointer:
            condition = "currentBankID = :previous"
            values[":previous"] = _s(previous_bank_id)
        else:
            condition = "attribute_not_exists(pk)"
        try:
            client.update_item(
                TableName=table_name,
                Key=pointer_key,
                UpdateExpression=(
                    "SET currentBankID = :bank, contextRevision = :revision, updatedAt = :now, expiresAt = :ttl"
                ),
                ConditionExpression=condition,
                ExpressionAttributeValues=values,
            )
            return previous_bank_id
        except Exception as error:
            if not _is_conditional_failure(error):
                raise
    raise QuestionBankError(409, "Goal context changed concurrently; retry ensure.", "bank_conflict")


def _update_bank_configuration(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
    context_revision: str,
    normalized: dict[str, Any],
    desired_count: int,
    low_watermark: int,
    now: int,
) -> dict[str, Any]:
    try:
        return client.update_item(
            TableName=table_name,
            Key=bank_key,
            UpdateExpression=(
                "SET generationRequest = :request, desiredCount = :desired, lowWatermark = :low, "
                "updatedAt = :now, expiresAt = :ttl"
            ),
            ConditionExpression="contextRevision = :revision AND attribute_not_exists(tombstonedAt)",
            ExpressionAttributeValues={
                ":request": _s(_json(normalized)),
                ":desired": _n(desired_count),
                ":low": _n(low_watermark),
                ":now": _n(now),
                ":ttl": _n(now + _bank_ttl_seconds()),
                ":revision": _s(context_revision),
            },
            ReturnValues="ALL_NEW",
        )["Attributes"]
    except Exception as error:
        if _is_conditional_failure(error):
            raise QuestionBankError(409, "Question bank context is stale.", "stale_bank") from error
        raise


def _ensure_refill(
    client: Any,
    queue: Any,
    table_name: str,
    queue_url: str,
    bank_key: dict[str, Any],
    pointer_key: dict[str, Any],
    meta: dict[str, Any],
    now: int,
) -> bool:
    if meta.get("tombstonedAt"):
        return False
    low_watermark = _number(meta, "lowWatermark")
    inventory_progress = (
        _number(meta, "generatedCount")
        if low_watermark == 0
        else _number(meta, "readyCount")
    )
    if inventory_progress >= _number(meta, "desiredCount"):
        if low_watermark == 0 and not _boolean(
            meta, "initialFillComplete"
        ):
            _mark_initial_fill_complete(client, table_name, bank_key, now)
        return False
    active_job_id = _string(meta, "activeJobID")
    if active_job_id:
        job_key = {"pk": bank_key["pk"], "sk": _s(f"JOB#{active_job_id}")}
        job = _get_item(client, table_name, job_key, consistent=True)
        if job and _string(job, "status") == "queued":
            _deliver_job(client, queue, table_name, queue_url, job_key, job, now)
            return False
        if (
            job
            and _string(job, "status") == "processing"
            and _number(job, "leaseUntil") < now
        ):
            try:
                recovered = client.update_item(
                    TableName=table_name,
                    Key=job_key,
                    UpdateExpression=(
                        "SET #status = :queued, enqueueStatus = :pending, "
                        "enqueueLeaseUntil = :zero, updatedAt = :now "
                        "REMOVE leaseToken, leaseUntil, enqueueToken"
                    ),
                    ConditionExpression="#status = :processing AND leaseUntil < :now",
                    ExpressionAttributeNames={"#status": "status"},
                    ExpressionAttributeValues={
                        ":queued": _s("queued"),
                        ":pending": _s("pending"),
                        ":processing": _s("processing"),
                        ":zero": _n(0),
                        ":now": _n(now),
                    },
                    ReturnValues="ALL_NEW",
                )["Attributes"]
                _deliver_job(
                    client,
                    queue,
                    table_name,
                    queue_url,
                    job_key,
                    recovered,
                    now,
                )
            except Exception as error:
                if not _is_conditional_failure(error):
                    raise
            return False
        if job and _string(job, "status") == "processing":
            return False

        # A job can expire, be DLQ-resolved, or be superseded between the META
        # update and a later ensure. Release only the exact orphaned pointer.
        try:
            client.update_item(
                TableName=table_name,
                Key=bank_key,
                UpdateExpression="SET updatedAt = :now REMOVE activeJobID",
                ConditionExpression="activeJobID = :job",
                ExpressionAttributeValues={":job": _s(active_job_id), ":now": _n(now)},
            )
        except Exception as error:
            if not _is_conditional_failure(error):
                raise
        refreshed = _get_item(client, table_name, bank_key, consistent=True)
        if refreshed and not _string(refreshed, "activeJobID"):
            return _ensure_refill(
                client,
                queue,
                table_name,
                queue_url,
                bank_key,
                pointer_key,
                refreshed,
                now,
            )
        return False

    refill_after = _number(meta, "refillAfter")
    if refill_after > now:
        return False
    job_id = str(uuid.uuid4())
    job_key = {"pk": bank_key["pk"], "sk": _s(f"JOB#{job_id}")}
    context_revision = _string(meta, "contextRevision")
    bank_id = _string(meta, "bankID")
    inventory_condition = (
        "generatedCount < desiredCount"
        if low_watermark == 0
        else "readyCount < desiredCount"
    )
    transaction = [
        {
            "Update": {
                "TableName": table_name,
                "Key": bank_key,
                "UpdateExpression": "SET activeJobID = :job, #state = :queued, updatedAt = :now, expiresAt = :ttl",
                "ConditionExpression": (
                    f"attribute_not_exists(activeJobID) AND {inventory_condition} "
                    "AND contextRevision = :revision AND attribute_not_exists(tombstonedAt)"
                ),
                "ExpressionAttributeNames": {"#state": "state"},
                "ExpressionAttributeValues": {
                    ":job": _s(job_id),
                    ":queued": _s("queued"),
                    ":now": _n(now),
                    ":ttl": _n(now + _bank_ttl_seconds()),
                    ":revision": _s(context_revision),
                },
            }
        },
        {
            "Put": {
                "TableName": table_name,
                "Item": {
                    **job_key,
                    "itemType": _s("job"),
                    "jobID": _s(job_id),
                    "bankID": _s(bank_id),
                    "contextRevision": _s(context_revision),
                    "status": _s("queued"),
                    "enqueueStatus": _s("pending"),
                    "enqueueLeaseUntil": _n(0),
                    "generationPass": _n(0),
                    "createdAt": _n(now),
                    "updatedAt": _n(now),
                    "expiresAt": _n(now + _bank_ttl_seconds()),
                },
                "ConditionExpression": "attribute_not_exists(pk)",
            }
        },
        {
            "ConditionCheck": {
                "TableName": table_name,
                "Key": pointer_key,
                "ConditionExpression": "currentBankID = :bank",
                "ExpressionAttributeValues": {":bank": _s(bank_id)},
            }
        },
    ]
    try:
        client.transact_write_items(TransactItems=transaction)
    except Exception as error:
        if _is_conditional_failure(error):
            refreshed = _get_item(client, table_name, bank_key, consistent=True)
            if refreshed and _string(refreshed, "activeJobID"):
                active_id = _string(refreshed, "activeJobID")
                active_key = {"pk": bank_key["pk"], "sk": _s(f"JOB#{active_id}")}
                active = _get_item(client, table_name, active_key, consistent=True)
                if active and _string(active, "status") == "queued":
                    _deliver_job(client, queue, table_name, queue_url, active_key, active, now)
            return False
        raise
    job = _get_item(client, table_name, job_key, consistent=True) or transaction[1]["Put"]["Item"]
    _deliver_job(client, queue, table_name, queue_url, job_key, job, now)
    return True


def _deliver_job(
    client: Any,
    queue: Any,
    table_name: str,
    queue_url: str,
    job_key: dict[str, Any],
    job: dict[str, Any],
    now: int,
) -> None:
    if _string(job, "enqueueStatus") == "sent":
        return
    lease_token = str(uuid.uuid4())
    try:
        leased = client.update_item(
            TableName=table_name,
            Key=job_key,
            UpdateExpression="SET enqueueStatus = :sending, enqueueToken = :token, enqueueLeaseUntil = :lease, updatedAt = :now",
            ConditionExpression=(
                "#status = :queued AND (enqueueStatus = :pending OR enqueueLeaseUntil < :now)"
            ),
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":queued": _s("queued"),
                ":pending": _s("pending"),
                ":sending": _s("sending"),
                ":token": _s(lease_token),
                ":lease": _n(now + ENQUEUE_LEASE_SECONDS),
                ":now": _n(now),
            },
            ReturnValues="ALL_NEW",
        )["Attributes"]
    except Exception as error:
        if _is_conditional_failure(error):
            return
        raise
    queue.send_message(
        QueueUrl=queue_url,
        MessageBody=_json(
            {
                "bankPK": _string(leased, "pk"),
                "jobID": _string(leased, "jobID"),
                "contextRevision": _string(leased, "contextRevision"),
            }
        ),
    )
    client.update_item(
        TableName=table_name,
        Key=job_key,
        UpdateExpression="SET enqueueStatus = :sent, enqueuedAt = :now, updatedAt = :now REMOVE enqueueToken",
        ConditionExpression="enqueueToken = :token",
        ExpressionAttributeValues={
            ":sent": _s("sent"),
            ":now": _n(int(time.time())),
            ":token": _s(lease_token),
        },
    )


def _mark_initial_fill_complete(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
    now: int,
) -> None:
    try:
        client.update_item(
            TableName=table_name,
            Key=bank_key,
            UpdateExpression=(
                "SET initialFillComplete = :true, updatedAt = :now, expiresAt = :ttl"
            ),
            ConditionExpression=(
                "lowWatermark = :zero AND generatedCount >= desiredCount "
                "AND attribute_not_exists(tombstonedAt)"
            ),
            ExpressionAttributeValues={
                ":true": {"BOOL": True},
                ":zero": _n(0),
                ":now": _n(now),
                ":ttl": _n(now + _bank_ttl_seconds()),
            },
        )
    except Exception as error:
        if not _is_conditional_failure(error):
            raise


def _consume_worker_quota(
    client: Any,
    question_table: str,
    job_key: dict[str, Any],
    job: dict[str, Any],
    owner_digest: str,
) -> None:
    rate_table = os.getenv("RATE_LIMIT_TABLE_NAME", "").strip()
    if not rate_table:
        if _required_rate_limiting():
            raise RuntimeError("Rate-limit table is required.")
        return
    generation_pass = _number(job, "generationPass")
    if _number(job, "quotaChargedPass", default=-1) == generation_pass:
        return
    day = datetime.now(timezone.utc).strftime("%Y%m%d")
    expires_at = int(time.time()) + _integer_env("RATE_LIMIT_TTL_SECONDS", 172800)
    limit = _integer_env("MAX_REQUESTS_PER_INSTALL_PER_DAY", 40)
    transaction = [
        {
            "Update": {
                "TableName": rate_table,
                "Key": {"rateKey": _s(f"async-install#{owner_digest}#{day}")},
                "UpdateExpression": "SET expiresAt = :ttl ADD #count :one",
                "ConditionExpression": "attribute_not_exists(#count) OR #count < :limit",
                "ExpressionAttributeNames": {"#count": "count"},
                "ExpressionAttributeValues": {
                    ":ttl": _n(expires_at),
                    ":one": _n(1),
                    ":limit": _n(limit),
                },
            }
        },
        {
            "Update": {
                "TableName": question_table,
                "Key": job_key,
                "UpdateExpression": "SET quotaChargedPass = :pass",
                "ConditionExpression": "generationPass = :pass AND (attribute_not_exists(quotaChargedPass) OR quotaChargedPass <> :pass)",
                "ExpressionAttributeValues": {":pass": _n(generation_pass)},
            }
        },
    ]
    try:
        client.transact_write_items(TransactItems=transaction)
    except Exception as error:
        refreshed = _get_item(client, question_table, job_key, consistent=True)
        if refreshed and _number(refreshed, "quotaChargedPass", default=-1) == generation_pass:
            return
        if _is_conditional_failure(error):
            _mark_rate_limited(client, question_table, job_key)
            raise QuestionBankError(429, "Daily asynchronous generation limit reached.", "rate_limited") from error
        raise


def _prepare_questions(
    bank_id: str,
    generated: list[dict[str, Any]],
    existing_items: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    existing_ids = {_string(item, "remoteID") for item in existing_items}
    prepared: list[dict[str, Any]] = []
    seen = set(existing_ids)
    for question in generated:
        canonical = _json(question)
        remote_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"checkpoint:{bank_id}:{canonical}"))
        if remote_id in seen:
            continue
        seen.add(remote_id)
        prepared.append({**question, "remoteID": remote_id})
        if len(prepared) >= MAX_CLAIM_COUNT:
            break
    return prepared


def _commit_generated_questions(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
    job_key: dict[str, Any],
    pointer_key: dict[str, Any],
    bank_id: str,
    context_revision: str,
    lease_token: str,
    questions: list[dict[str, Any]],
) -> None:
    now = int(time.time())
    transaction: list[dict[str, Any]] = []
    for question in questions:
        transaction.append(
            {
                "Put": {
                    "TableName": table_name,
                    "Item": {
                        "pk": bank_key["pk"],
                        "sk": _s(f"QUESTION#{question['remoteID']}"),
                        "itemType": _s("question"),
                        "remoteID": _s(question["remoteID"]),
                        "questionJSON": _s(_json(question)),
                        "createdAt": _n(now),
                        "expiresAt": _n(now + _bank_ttl_seconds()),
                    },
                    "ConditionExpression": "attribute_not_exists(pk)",
                }
            }
        )
    transaction.extend(
        [
            {
                "Update": {
                    "TableName": table_name,
                    "Key": bank_key,
                    "UpdateExpression": (
                        "ADD readyCount :count, generatedCount :count "
                        "SET #state = :state, updatedAt = :now, expiresAt = :ttl "
                        "REMOVE activeJobID"
                    ),
                    "ConditionExpression": (
                        "activeJobID = :job AND contextRevision = :revision "
                        "AND attribute_not_exists(tombstonedAt)"
                    ),
                    "ExpressionAttributeNames": {"#state": "state"},
                    "ExpressionAttributeValues": {
                        ":count": _n(len(questions)),
                        ":state": _s("ready"),
                        ":now": _n(now),
                        ":ttl": _n(now + _bank_ttl_seconds()),
                        ":job": _s(_string_from_key(job_key["sk"]).removeprefix("JOB#")),
                        ":revision": _s(context_revision),
                    },
                }
            },
            {
                "Update": {
                    "TableName": table_name,
                    "Key": job_key,
                    "UpdateExpression": (
                        "SET #status = :complete, producedCount = :count, updatedAt = :now, "
                        "generationPass = generationPass + :one REMOVE leaseToken, leaseUntil"
                    ),
                    "ConditionExpression": "leaseToken = :token",
                    "ExpressionAttributeNames": {"#status": "status"},
                    "ExpressionAttributeValues": {
                        ":complete": _s("complete"),
                        ":count": _n(len(questions)),
                        ":now": _n(now),
                        ":one": _n(1),
                        ":token": _s(lease_token),
                    },
                }
            },
            {
                "ConditionCheck": {
                    "TableName": table_name,
                    "Key": pointer_key,
                    "ConditionExpression": "currentBankID = :bank AND contextRevision = :revision",
                    "ExpressionAttributeValues": {
                        ":bank": _s(bank_id),
                        ":revision": _s(context_revision),
                    },
                }
            },
        ]
    )
    if len(transaction) > 25:
        raise RuntimeError("Question-bank transaction exceeds DynamoDB's item limit.")
    client.transact_write_items(TransactItems=transaction)


def _complete_job_without_questions(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
    job_key: dict[str, Any],
    lease_token: str,
    now: int,
) -> None:
    client.transact_write_items(
        TransactItems=[
            {
                "Update": {
                    "TableName": table_name,
                    "Key": bank_key,
                    "UpdateExpression": "SET #state = :ready, updatedAt = :now REMOVE activeJobID",
                    "ConditionExpression": "activeJobID = :job AND attribute_not_exists(tombstonedAt)",
                    "ExpressionAttributeNames": {"#state": "state"},
                    "ExpressionAttributeValues": {
                        ":ready": _s("ready"),
                        ":now": _n(now),
                        ":job": _s(_string_from_key(job_key["sk"]).removeprefix("JOB#")),
                    },
                }
            },
            {
                "Update": {
                    "TableName": table_name,
                    "Key": job_key,
                    "UpdateExpression": "SET #status = :complete, updatedAt = :now REMOVE leaseToken, leaseUntil",
                    "ConditionExpression": "leaseToken = :token",
                    "ExpressionAttributeNames": {"#status": "status"},
                    "ExpressionAttributeValues": {
                        ":complete": _s("complete"),
                        ":now": _n(now),
                        ":token": _s(lease_token),
                    },
                }
            },
        ]
    )


def _reset_job_for_retry(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
    job_key: dict[str, Any],
    lease_token: str,
) -> None:
    now = int(time.time())
    try:
        client.transact_write_items(
            TransactItems=[
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": job_key,
                        "UpdateExpression": (
                            "SET #status = :queued, enqueueStatus = :pending, "
                            "enqueueLeaseUntil = :zero, updatedAt = :now "
                            "REMOVE leaseToken, leaseUntil, enqueueToken"
                        ),
                        "ConditionExpression": "leaseToken = :token",
                        "ExpressionAttributeNames": {"#status": "status"},
                        "ExpressionAttributeValues": {
                            ":queued": _s("queued"),
                            ":pending": _s("pending"),
                            ":zero": _n(0),
                            ":now": _n(now),
                            ":token": _s(lease_token),
                        },
                    }
                },
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": bank_key,
                        "UpdateExpression": "SET #state = :queued, updatedAt = :now",
                        "ExpressionAttributeNames": {"#state": "state"},
                        "ExpressionAttributeValues": {":queued": _s("queued"), ":now": _n(now)},
                    }
                },
            ]
        )
    except Exception:
        LOGGER.exception("Failed to release question-bank worker lease")


def _finish_stale_job(
    client: Any,
    table_name: str,
    job_key: dict[str, Any],
    lease_token: str,
) -> None:
    try:
        client.update_item(
            TableName=table_name,
            Key=job_key,
            UpdateExpression="SET #status = :stale, updatedAt = :now REMOVE leaseToken, leaseUntil",
            ConditionExpression="leaseToken = :token",
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":stale": _s("superseded"),
                ":now": _n(int(time.time())),
                ":token": _s(lease_token),
            },
        )
    except Exception:
        LOGGER.exception("Failed to mark stale question-bank job")


def _mark_rate_limited(client: Any, table_name: str, job_key: dict[str, Any]) -> None:
    bank_key = {"pk": job_key["pk"], "sk": _s("META")}
    now = datetime.now(timezone.utc)
    retry_at = int((datetime.combine(now.date() + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)).timestamp())
    job_id = _string_from_key(job_key["sk"]).removeprefix("JOB#")
    try:
        client.transact_write_items(
            TransactItems=[
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": job_key,
                        "UpdateExpression": "SET #status = :limited, updatedAt = :now REMOVE leaseToken, leaseUntil",
                        "ExpressionAttributeNames": {"#status": "status"},
                        "ExpressionAttributeValues": {":limited": _s("rate_limited"), ":now": _n(int(now.timestamp()))},
                    }
                },
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": bank_key,
                        "UpdateExpression": "SET refillAfter = :retry, #state = :empty, updatedAt = :now REMOVE activeJobID",
                        "ConditionExpression": "activeJobID = :job",
                        "ExpressionAttributeNames": {"#state": "state"},
                        "ExpressionAttributeValues": {
                            ":retry": _n(retry_at),
                            ":empty": _s("empty"),
                            ":now": _n(int(now.timestamp())),
                            ":job": _s(job_id),
                        },
                    }
                },
            ]
        )
    except Exception:
        LOGGER.exception("Failed to mark asynchronous generation rate limit")


def _mark_bank_superseded(
    client: Any,
    table_name: str,
    owner_digest: str,
    bank_id: str,
    now: int,
) -> None:
    try:
        client.update_item(
            TableName=table_name,
            Key=_bank_key(owner_digest, bank_id),
            UpdateExpression=(
                "SET #state = :stale, updatedAt = :now, expiresAt = :ttl"
            ),
            ConditionExpression="attribute_exists(pk)",
            ExpressionAttributeNames={"#state": "state"},
            ExpressionAttributeValues={
                ":stale": _s("superseded"),
                ":now": _n(now),
                ":ttl": _n(now + _bank_ttl_seconds()),
            },
        )
    except Exception as error:
        if not _is_conditional_failure(error):
            LOGGER.exception("Failed to mark superseded question bank")


def _purge_bank_children(client: Any, table_name: str, bank_key: dict[str, Any]) -> None:
    items = _query_all(client, table_name, bank_key)
    children = [item for item in items if _string_from_key(item["sk"]) != "META"]
    for offset in range(0, len(children), 25):
        requests = [
            {"DeleteRequest": {"Key": {"pk": item["pk"], "sk": item["sk"]}}}
            for item in children[offset : offset + 25]
        ]
        if requests:
            client.batch_write_item(RequestItems={table_name: requests})


def _query_questions(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
    limit: int,
) -> list[dict[str, Any]]:
    response = client.query(
        TableName=table_name,
        KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
        ExpressionAttributeValues={":pk": bank_key["pk"], ":prefix": _s("QUESTION#")},
        ConsistentRead=True,
        Limit=limit,
    )
    return response.get("Items", [])


def _query_all(client: Any, table_name: str, bank_key: dict[str, Any]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    last_key = None
    while True:
        request: dict[str, Any] = {
            "TableName": table_name,
            "KeyConditionExpression": "pk = :pk",
            "ExpressionAttributeValues": {":pk": bank_key["pk"]},
            "ConsistentRead": True,
        }
        if last_key:
            request["ExclusiveStartKey"] = last_key
        response = client.query(**request)
        items.extend(response.get("Items", []))
        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            return items


def _bank_response(meta: dict[str, Any]) -> dict[str, Any]:
    ready = _number(meta, "readyCount")
    target = _number(meta, "desiredCount")
    state = _string(meta, "state")
    if state not in {"queued", "processing", "ready", "empty"}:
        state = "ready" if ready else "empty"
    return {
        "bankID": _string(meta, "bankID"),
        "status": state,
        "readyCount": ready,
        "targetCount": target,
    }


def _stored_claim(item: dict[str, Any]) -> dict[str, Any]:
    return json.loads(_string(item, "responseJSON"))


def _question_from_item(item: dict[str, Any]) -> dict[str, Any]:
    return json.loads(_string(item, "questionJSON"))


def _require_active_meta(meta: dict[str, Any] | None, owner_digest: str) -> None:
    if not meta:
        raise QuestionBankError(404, "Question bank not found.", "bank_not_found")
    if meta.get("tombstonedAt"):
        raise QuestionBankError(410, "Question bank was deleted or superseded.", "bank_deleted")
    if not hmac.compare_digest(_string(meta, "ownerHash"), owner_digest):
        raise QuestionBankError(404, "Question bank not found.", "bank_not_found")


def _require_current_bank(client: Any, table_name: str, pointer_key: dict[str, Any], bank_id: str) -> None:
    pointer = _get_item(client, table_name, pointer_key, consistent=True)
    if not pointer or _string(pointer, "currentBankID") != bank_id:
        raise QuestionBankError(409, "Question bank belongs to an older goal context.", "stale_bank")


def _configuration() -> tuple[str, str]:
    table_name = os.getenv("QUESTION_BANK_TABLE_NAME", "").strip()
    queue_url = os.getenv("QUESTION_BANK_QUEUE_URL", "").strip()
    if not table_name or not queue_url:
        raise QuestionBankError(503, "Question banks are temporarily unavailable.", "service_unavailable")
    secret = os.getenv("QUOTA_HASH_SECRET", "").strip()
    if len(secret) < 32:
        raise QuestionBankError(503, "Question banks are temporarily unavailable.", "service_unavailable")
    return table_name, queue_url


def _owner_digest(event: dict[str, Any]) -> str:
    headers = {str(key).lower(): value for key, value in (event.get("headers") or {}).items()}
    install_id = _required_identifier(headers.get("x-checkpoint-install-id"), "X-Checkpoint-Install-ID")
    return _secret_digest("owner", install_id)


def _required_revision(value: Any) -> str:
    if not isinstance(value, str):
        raise QuestionBankError(400, "contextRevision must be text.", "invalid_request")
    cleaned = value.strip()
    if not cleaned or len(cleaned) > 128 or any(ord(character) < 33 for character in cleaned):
        raise QuestionBankError(400, "contextRevision is invalid.", "invalid_request")
    return cleaned


def _bank_key(owner_digest: str, bank_id: str) -> dict[str, Any]:
    return {"pk": _s(f"BANK#{owner_digest}#{bank_id}"), "sk": _s("META")}


def _pointer_key(owner_digest: str, goal_key: str) -> dict[str, Any]:
    return {"pk": _s(f"OWNER#{owner_digest}"), "sk": _s(f"GOAL#{goal_key}")}


def _parse_bank_pk(value: str) -> tuple[str, str]:
    parts = value.split("#")
    if len(parts) != 3 or parts[0] != "BANK":
        raise RuntimeError("Malformed internal bank key.")
    return parts[1], parts[2]


def _get_item(
    client: Any,
    table_name: str,
    key: dict[str, Any],
    *,
    consistent: bool,
) -> dict[str, Any] | None:
    return client.get_item(TableName=table_name, Key=key, ConsistentRead=consistent).get("Item")


def _required_identifier(value: Any, field: str) -> str:
    if not isinstance(value, str):
        raise QuestionBankError(400, f"{field} must be text.", "invalid_request")
    cleaned = " ".join(value.split()).strip()
    if not cleaned or len(cleaned) > 128 or not re.fullmatch(r"[A-Za-z0-9_.:@/+\-=]+", cleaned):
        raise QuestionBankError(400, f"{field} is invalid.", "invalid_request")
    return cleaned


def _required_hex_identifier(value: Any, field: str) -> str:
    cleaned = _required_identifier(value, field)
    if not re.fullmatch(r"[0-9a-f]{64}", cleaned):
        raise QuestionBankError(400, f"{field} is invalid.", "invalid_request")
    return cleaned


def _required_internal_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value or len(value) > 256:
        raise RuntimeError(f"Malformed worker {field}.")
    return value


def _required_int(value: Any, field: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool):
        raise QuestionBankError(400, f"{field} must be an integer.", "invalid_request")
    try:
        result = int(value)
    except (TypeError, ValueError) as error:
        raise QuestionBankError(400, f"{field} must be an integer.", "invalid_request") from error
    if result < minimum or result > maximum:
        raise QuestionBankError(400, f"{field} must be between {minimum} and {maximum}.", "invalid_request")
    return result


def _secret_digest(namespace: str, value: str) -> str:
    secret = os.getenv("QUOTA_HASH_SECRET", "").strip()
    return hmac.new(secret.encode(), f"checkpoint-{namespace}-v1:{value}".encode(), hashlib.sha256).hexdigest()


def _plain_digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def _json(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def _s(value: Any) -> dict[str, str]:
    return {"S": str(value)}


def _n(value: int) -> dict[str, str]:
    return {"N": str(int(value))}


def _string(item: dict[str, Any] | None, name: str) -> str:
    if not item:
        return ""
    value = item.get(name, {})
    return str(value.get("S", "")) if isinstance(value, dict) else ""


def _number(item: dict[str, Any] | None, name: str, default: int = 0) -> int:
    if not item:
        return default
    try:
        return int(item.get(name, {}).get("N", default))
    except (TypeError, ValueError, AttributeError):
        return default


def _boolean(item: dict[str, Any] | None, name: str) -> bool:
    if not item:
        return False
    value = item.get(name, {})
    return bool(value.get("BOOL", False)) if isinstance(value, dict) else False


def _string_from_key(value: dict[str, str]) -> str:
    return value.get("S", "")


def _is_conditional_failure(error: Exception) -> bool:
    response = getattr(error, "response", {})
    code = response.get("Error", {}).get("Code", "")
    if code == "ConditionalCheckFailedException":
        return True
    if code == "TransactionCanceledException":
        reasons = response.get("CancellationReasons", [])
        return any(reason.get("Code") == "ConditionalCheckFailed" for reason in reasons if isinstance(reason, dict)) or "ConditionalCheckFailed" in str(response)
    return False


def _integer_env(name: str, default: int) -> int:
    try:
        return max(1, int(os.getenv(name, str(default))))
    except ValueError:
        return default


def _bank_ttl_seconds() -> int:
    return _integer_env("QUESTION_BANK_TTL_SECONDS", DEFAULT_BANK_TTL_SECONDS)


def _required_rate_limiting() -> bool:
    environment = os.getenv("DEPLOYMENT_ENVIRONMENT", "development").lower()
    configured = os.getenv("REQUIRE_RATE_LIMITING", "false").lower() in {"1", "true", "yes"}
    return configured or environment in {"production", "prod"}


def _dynamodb_client() -> Any:
    import boto3

    return boto3.client("dynamodb", region_name=os.getenv("AWS_REGION"))


def _sqs_client() -> Any:
    import boto3

    return boto3.client("sqs", region_name=os.getenv("AWS_REGION"))
