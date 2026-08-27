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
DEFAULT_GENERATION_CHUNK_COUNT = 5
DEFAULT_BANK_TTL_SECONDS = 30 * 24 * 60 * 60
WORKER_LEASE_SECONDS = 180
DEFAULT_MAX_RECEIVE_COUNT = 5
DEFAULT_FAILURE_COOLDOWN_SECONDS = 5 * 60


class QuestionBankError(RuntimeError):
    def __init__(self, status_code: int, message: str, code: str):
        super().__init__(message)
        self.status_code = status_code
        self.code = code


class NonRetryableGenerationError(RuntimeError):
    """A validated generation refusal that must remain terminal for this bank."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


class ProviderAttemptLimitError(RuntimeError):
    """The logical job has exhausted its provider-call allowance."""


def _validate_durable_skill_allocation(
    normalized_request: dict[str, Any],
    desired_count: int,
) -> None:
    skills = normalized_request.get("skillMap", {}).get("skills", [])
    if not skills:
        return
    allocation = normalized_request.get("desiredSkillAllocation", {})
    positive_skill_count = (
        sum(1 for count in allocation.values() if count > 0)
        if allocation
        else len(skills)
    )
    if desired_count < positive_skill_count:
        raise QuestionBankError(
            400,
            "desiredCount must provide at least one durable inventory slot for "
            "every positive-weight skill.",
            "invalid_request",
        )


def _skill_allocation_key(normalized_request: dict[str, Any]) -> str:
    skills = normalized_request.get("skillMap", {}).get("skills", [])
    if not skills:
        return "legacy"
    allocation = normalized_request.get("desiredSkillAllocation", {})
    entries = [
        {
            "skillID": skill["id"],
            "weight": allocation.get(skill["id"], 0) if allocation else 1,
        }
        for skill in skills
    ]
    entries.sort(key=lambda entry: entry["skillID"])
    return _plain_digest(_json(entries))


def _inventory_progress(meta: dict[str, Any]) -> int:
    """Use lifetime generation for finite banks and ready stock for refillable banks."""
    counter = "generatedCount" if _number(meta, "lowWatermark") == 0 else "readyCount"
    return _number(meta, counter)


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
    generation_payload["targetCount"] = min(desired_count, _generation_chunk_count())
    normalized = normalize_request(generation_payload)
    _validate_durable_skill_allocation(normalized, desired_count)
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
    if _inventory_progress(meta) >= desired_count:
        if low_watermark == 0 and not _boolean(meta, "initialFillComplete"):
            _mark_initial_fill_complete(client, table_name, bank_key, now)
            meta = _get_item(client, table_name, bank_key, consistent=True) or meta
    else:
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
    """Atomically claim ready questions and persist the response by claim ID."""
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
        response = _stored_claim(existing_claim)
        _recover_refill_after_claim(
            client,
            queue,
            table_name,
            queue_url,
            bank_key,
            pointer_key,
            response,
        )
        return response

    for _ in range(4):
        meta = _get_item(client, table_name, bank_key, consistent=True)
        _require_active_meta(meta, owner_digest)
        observed_ready = _number(meta, "readyCount")
        history_items = _query_question_history(client, table_name, bank_key)
        all_ready_items = [
            item
            for item in history_items
            # Before claimed-question history was introduced, claiming deleted
            # the row. A legacy row without state is therefore still ready.
            if _string(item, "state") in {"", "ready"}
        ]
        question_items = all_ready_items[:limit]
        questions = [_question_from_item(item) for item in question_items]
        # QUESTION records have their own TTL. Reconcile the cached counter to
        # the strongly consistent inventory instead of trusting a stale META.
        after_count = len(all_ready_items) - len(question_items)
        desired_count = _number(meta, "desiredCount")
        low_watermark = _number(meta, "lowWatermark")
        blocked_reason = _string(meta, "generationBlockedReason")
        finite_fill_pending = (
            low_watermark == 0
            and _number(meta, "generatedCount") < desired_count
        )
        needs_refill = not blocked_reason and (
            finite_fill_pending
            or (
                low_watermark > 0
                and after_count <= low_watermark
                and after_count < desired_count
            )
        )
        response = {
            "bankID": bank_id,
            "status": "queued" if needs_refill else ("ready" if after_count else "empty"),
            "readyCount": after_count,
            "targetCount": desired_count,
            "questions": questions,
        }
        now = int(time.time())
        meta_condition = "readyCount = :observed AND attribute_not_exists(tombstonedAt)"
        meta_values = {
            ":after": _n(after_count),
            ":observed": _n(observed_ready),
            ":state": _s(response["status"]),
            ":now": _n(now),
            ":ttl": _n(now + _bank_ttl_seconds()),
        }
        if blocked_reason:
            meta_condition += " AND generationBlockedReason = :blockedReason"
            meta_values[":blockedReason"] = _s(blocked_reason)
        else:
            meta_condition += " AND attribute_not_exists(generationBlockedReason)"
        transaction: list[dict[str, Any]] = []
        for item in question_items:
            transaction.append(
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": {"pk": item["pk"], "sk": item["sk"]},
                        "UpdateExpression": (
                            "SET #state = :claimed, claimedAt = :now, expiresAt = :ttl"
                        ),
                        "ConditionExpression": (
                            "attribute_not_exists(#state) OR #state = :ready"
                        ),
                        "ExpressionAttributeNames": {"#state": "state"},
                        "ExpressionAttributeValues": {
                            ":claimed": _s("claimed"),
                            ":ready": _s("ready"),
                            ":now": _n(now),
                            ":ttl": _n(now + _bank_ttl_seconds()),
                        },
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
                        "ConditionExpression": meta_condition,
                        "ExpressionAttributeNames": {"#state": "state"},
                        "ExpressionAttributeValues": meta_values,
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
                response = _stored_claim(existing_claim)
                _recover_refill_after_claim(
                    client,
                    queue,
                    table_name,
                    queue_url,
                    bank_key,
                    pointer_key,
                    response,
                )
                return response
            if _is_conditional_failure(error):
                continue
            raise

        _recover_refill_after_claim(
            client,
            queue,
            table_name,
            queue_url,
            bank_key,
            pointer_key,
            response,
        )
        return response

    raise QuestionBankError(409, "Question inventory changed; retry the claim.", "claim_conflict")


def _recover_refill_after_claim(
    client: Any,
    queue: Any,
    table_name: str,
    queue_url: str,
    bank_key: dict[str, Any],
    pointer_key: dict[str, Any],
    response: dict[str, Any],
) -> None:
    """Best-effort refill recovery for new and idempotently replayed claims."""
    if response.get("status") != "queued":
        return
    try:
        refreshed = _get_item(client, table_name, bank_key, consistent=True)
        if refreshed:
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
    except Exception:
        # The claim is already committed and must remain exactly replayable.
        LOGGER.exception("Question-bank refill recovery failed after claim")


def handle_worker_event(
    event: dict[str, Any],
    context: Any,
    generate_questions: Callable[[dict[str, Any]], list[dict[str, Any]]],
    *,
    dynamodb_client: Any | None = None,
    sqs_client: Any | None = None,
    on_terminal_failure: Callable[[str], None] | None = None,
) -> dict[str, list[dict[str, str]]]:
    """SQS partial-batch handler; failed records remain visible for retry/DLQ."""
    del context  # The generation callback owns deadline enforcement.
    failures: list[dict[str, str]] = []
    client = dynamodb_client or _dynamodb_client()
    queue = sqs_client or _sqs_client()
    for record in event.get("Records", []):
        message_id = str(record.get("messageId", "unknown"))
        message: dict[str, Any] | None = None
        try:
            message = json.loads(record.get("body", ""))
            _process_job(message, generate_questions, client, queue)
        except ProviderAttemptLimitError:
            if not isinstance(message, dict) or not message:
                failures.append({"itemIdentifier": message_id})
                continue
            _mark_job_terminal_failure(
                client,
                message,
                _max_receive_count(),
            )
            LOGGER.error("Question-bank job exhausted its provider-attempt allowance")
            if on_terminal_failure:
                on_terminal_failure("provider_attempt_limit")
        except Exception:
            LOGGER.exception("Asynchronous question-bank worker failed")
            if (
                isinstance(message, dict)
                and message
                and _receive_count(record) >= _max_receive_count()
            ):
                _mark_job_terminal_failure(
                    client,
                    message,
                    _receive_count(record),
                )
            failures.append({"itemIdentifier": message_id})
    return {"batchItemFailures": failures}


def handle_outbox_event(
    event: dict[str, Any],
    context: Any,
    *,
    dynamodb_client: Any | None = None,
    sqs_client: Any | None = None,
) -> dict[str, list[dict[str, str]]]:
    """Dispatch pending JOB records emitted by DynamoDB Streams to SQS."""
    del context
    table_name, queue_url = _configuration()
    client = dynamodb_client or _dynamodb_client()
    queue = sqs_client or _sqs_client()
    failures: list[dict[str, str]] = []
    for record in event.get("Records", []):
        sequence_number = str(
            record.get("dynamodb", {}).get("SequenceNumber")
            or record.get("eventID")
            or "unknown"
        )
        image = record.get("dynamodb", {}).get("NewImage")
        if not _is_pending_job_image(record.get("eventName"), image):
            continue
        job_key = {"pk": image["pk"], "sk": image["sk"]}
        try:
            _deliver_job(
                client,
                queue,
                table_name,
                queue_url,
                job_key,
                image,
            )
        except Exception:
            LOGGER.exception("Question-bank outbox delivery failed")
            failures.append({"itemIdentifier": sequence_number})
    return {"batchItemFailures": failures}


def _process_job(
    message: dict[str, Any],
    generate_questions: Callable[[dict[str, Any]], list[dict[str, Any]]],
    client: Any,
    queue: Any,
) -> None:
    """Lease one queued job, generate its deficit, and continue its refill chain."""
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
                "SET #status = :processing, enqueueStatus = :sent, "
                "leaseToken = :token, leaseUntil = :lease, updatedAt = :now"
            ),
            ConditionExpression=(
                "#status = :queued OR (#status = :processing AND leaseUntil < :now)"
            ),
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":queued": _s("queued"),
                ":processing": _s("processing"),
                ":sent": _s("sent"),
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
        status = _string(job, "status") if job else ""
        if status == "complete":
            _repair_completed_job_chain(
                client,
                queue,
                table_name,
                queue_url,
                bank_key,
                bank_pk,
                context_revision,
                now,
            )
            return
        if not job or status in {
            "blocked",
            "failed",
            "superseded",
            "rate_limited",
        }:
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
    deficit = max(0, desired_count - _inventory_progress(meta))
    if deficit == 0:
        _complete_job_without_questions(client, table_name, bank_key, job_key, lease_token, now)
        return

    _consume_worker_quota(client, table_name, job_key, acquired, owner_digest)
    generation_request = json.loads(_string(meta, "generationRequest"))
    existing_items = _query_question_history(client, table_name, bank_key)
    existing_questions = [_question_from_item(item) for item in existing_items]
    generation_request["targetCount"] = min(_generation_chunk_count(), deficit)
    if generation_request.get("skillMap"):
        generation_request["requestedSkillAllocation"] = _worker_skill_allocation(
            generation_request,
            existing_items,
            desired_count=desired_count,
            low_watermark=low_watermark,
            target_count=generation_request["targetCount"],
        )
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
                "skillID": question.get("skillID", ""),
                "objectiveID": question.get("objectiveID", ""),
                "objective": question.get("objective", ""),
                "prompt": question.get("prompt", ""),
                "expectedAnswer": question.get("expectedAnswer", ""),
                "choices": question.get("choices", []),
                "difficulty": question.get("difficulty", 1),
            }
            for question in existing_questions
        ]
    )[-30:]

    try:
        if not _reserve_provider_attempt(
            client,
            table_name,
            job_key,
            lease_token,
        ):
            raise ProviderAttemptLimitError
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
            prepared[:deficit],
            observed_desired_count=desired_count,
            observed_low_watermark=low_watermark,
            observed_ready_count=ready_count,
            observed_generated_count=generated_count,
        )
    except NonRetryableGenerationError as error:
        _mark_generation_blocked(
            client,
            table_name,
            bank_key,
            job_key,
            lease_token,
            error.code,
        )
        return
    except ProviderAttemptLimitError:
        raise
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


def _repair_completed_job_chain(
    client: Any,
    queue: Any,
    table_name: str,
    queue_url: str,
    bank_key: dict[str, Any],
    bank_pk: str,
    context_revision: str,
    now: int,
) -> None:
    """Resume refill chaining when a completed message is delivered again."""
    meta = _get_item(client, table_name, bank_key, consistent=True)
    if (
        not meta
        or meta.get("tombstonedAt")
        or _string(meta, "contextRevision") != context_revision
    ):
        return
    owner_digest, bank_id = _parse_bank_pk(bank_pk)
    pointer_key = _pointer_key(owner_digest, _string(meta, "goalKey"))
    pointer = _get_item(client, table_name, pointer_key, consistent=True)
    if pointer and _string(pointer, "currentBankID") == bank_id:
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
            "skillAllocationKey": _s(_skill_allocation_key(normalized)),
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
                "SET generationRequest = :request, skillAllocationKey = :allocation, "
                "desiredCount = :desired, lowWatermark = :low, "
                "updatedAt = :now, expiresAt = :ttl"
            ),
            ConditionExpression=(
                "contextRevision = :revision AND attribute_not_exists(tombstonedAt) "
                "AND (attribute_not_exists(skillAllocationKey) OR "
                "skillAllocationKey = :allocation)"
            ),
            ExpressionAttributeValues={
                ":request": _s(_json(normalized)),
                ":allocation": _s(_skill_allocation_key(normalized)),
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
    """Ensure at most one durable refill job exists for the bank's current deficit."""
    if meta.get("tombstonedAt") or _string(meta, "generationBlockedReason"):
        return False
    low_watermark = _number(meta, "lowWatermark")
    if _inventory_progress(meta) >= _number(meta, "desiredCount"):
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
            try:
                _deliver_job(client, queue, table_name, queue_url, job_key, job)
            except Exception:
                # The pending JOB is the durable outbox; its stream consumer retries.
                LOGGER.exception("Direct question-bank job delivery failed")
            return False
        if job and _string(job, "status") == "processing":
            # Re-enqueueing bypasses the original message's visibility and redrive timing.
            return False

        # Release only a pointer orphaned by expiry, DLQ handling, or supersession.
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
                    "AND contextRevision = :revision "
                    "AND attribute_not_exists(generationBlockedReason) "
                    "AND attribute_not_exists(tombstonedAt)"
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
                    "generationPass": _n(0),
                    "providerAttemptCount": _n(0),
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
                    try:
                        _deliver_job(
                            client,
                            queue,
                            table_name,
                            queue_url,
                            active_key,
                            active,
                        )
                    except Exception:
                        LOGGER.exception("Direct question-bank job delivery failed")
            return False
        raise
    job = _get_item(client, table_name, job_key, consistent=True) or transaction[1]["Put"]["Item"]
    try:
        _deliver_job(client, queue, table_name, queue_url, job_key, job)
    except Exception:
        LOGGER.exception("Direct question-bank job delivery failed")
    return True


def _deliver_job(
    client: Any,
    queue: Any,
    table_name: str,
    queue_url: str,
    job_key: dict[str, Any],
    job: dict[str, Any],
) -> None:
    current = _get_item(client, table_name, job_key, consistent=True) or job
    if (
        _string(current, "status") != "queued"
        or _string(current, "enqueueStatus") == "sent"
    ):
        return
    bank_pk = _required_internal_string(_string(current, "pk"), "bankPK")
    job_id = _required_internal_string(_string(current, "jobID"), "jobID")
    context_revision = _required_internal_string(
        _string(current, "contextRevision"), "contextRevision"
    )
    queue.send_message(
        QueueUrl=queue_url,
        MessageBody=_json(
            {
                "bankPK": bank_pk,
                "jobID": job_id,
                "contextRevision": context_revision,
            }
        ),
    )
    try:
        client.update_item(
            TableName=table_name,
            Key=job_key,
            UpdateExpression=(
                "SET enqueueStatus = :sent, enqueuedAt = :now, updatedAt = :now "
                "REMOVE enqueueToken, enqueueLeaseUntil"
            ),
            ConditionExpression=(
                "#status = :queued AND "
                "(attribute_not_exists(enqueueStatus) OR enqueueStatus <> :sent)"
            ),
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":queued": _s("queued"),
                ":sent": _s("sent"),
                ":now": _n(int(time.time())),
            },
        )
    except Exception as error:
        # A concurrent direct/stream dispatcher can win after both sends, and
        # a worker can acquire the message before this bookkeeping update.
        if not _is_conditional_failure(error):
            raise


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


def _reserve_provider_attempt(
    client: Any,
    table_name: str,
    job_key: dict[str, Any],
    lease_token: str,
) -> bool:
    """Atomically reserve one provider call across all duplicate deliveries."""
    limit = _max_receive_count()
    try:
        client.update_item(
            TableName=table_name,
            Key=job_key,
            UpdateExpression=(
                "SET providerAttemptCount = "
                "if_not_exists(providerAttemptCount, :zero) + :one, updatedAt = :now"
            ),
            ConditionExpression=(
                "leaseToken = :token AND "
                "(attribute_not_exists(providerAttemptCount) OR providerAttemptCount < :limit)"
            ),
            ExpressionAttributeValues={
                ":zero": _n(0),
                ":one": _n(1),
                ":limit": _n(limit),
                ":token": _s(lease_token),
                ":now": _n(int(time.time())),
            },
        )
        return True
    except Exception as error:
        if not _is_conditional_failure(error):
            raise
        job = _get_item(client, table_name, job_key, consistent=True)
        if job and _number(job, "providerAttemptCount") >= limit:
            return False
        raise


def _worker_skill_allocation(
    generation_request: dict[str, Any],
    existing_items: list[dict[str, Any]],
    *,
    desired_count: int,
    low_watermark: int,
    target_count: int,
) -> dict[str, int]:
    """Derive this worker chunk from stable whole-bank weights and server inventory."""
    skills = generation_request.get("skillMap", {}).get("skills", [])
    skill_ids = [skill.get("id", "") for skill in skills if skill.get("id")]
    if not skill_ids or target_count <= 0:
        return {}

    desired_allocation = generation_request.get("desiredSkillAllocation", {})
    targets = _apportion_skill_counts(
        skill_ids,
        desired_allocation if isinstance(desired_allocation, dict) else {},
        desired_count,
    )
    relevant_items = (
        existing_items
        if low_watermark == 0
        else [item for item in existing_items if _string(item, "state") in {"", "ready"}]
    )
    counts = {skill_id: 0 for skill_id in skill_ids}
    for item in relevant_items:
        try:
            question = _question_from_item(item)
        except (json.JSONDecodeError, TypeError):
            continue
        skill_id = question.get("skillID")
        if skill_id in counts:
            counts[skill_id] += 1

    deficits = {
        skill_id: max(0, targets.get(skill_id, 0) - counts.get(skill_id, 0))
        for skill_id in skill_ids
    }
    return _allocate_deficit_chunk(deficits, min(target_count, sum(deficits.values())))


def _apportion_skill_counts(
    skill_ids: list[str],
    desired_allocation: dict[str, int],
    desired_count: int,
) -> dict[str, int]:
    """Apportion a total while reserving one slot for every positive-weight skill."""
    if desired_count <= 0 or not skill_ids:
        return {}
    weights = {
        skill_id: max(0, int(desired_allocation.get(skill_id, 0)))
        for skill_id in skill_ids
    }
    if not any(weights.values()):
        weights = {skill_id: 1 for skill_id in skill_ids}
    positive_skill_ids = [
        skill_id for skill_id in skill_ids if weights[skill_id] > 0
    ]
    targets = {skill_id: 0 for skill_id in skill_ids}
    if desired_count < len(positive_skill_ids):
        ranked = sorted(
            positive_skill_ids,
            key=lambda skill_id: (
                weights[skill_id],
                -skill_ids.index(skill_id),
            ),
            reverse=True,
        )
        for skill_id in ranked[:desired_count]:
            targets[skill_id] = 1
        return targets

    for skill_id in positive_skill_ids:
        targets[skill_id] = 1
    remaining_count = desired_count - len(positive_skill_ids)
    weight_total = sum(weights.values())
    exact = {
        skill_id: remaining_count * weights[skill_id] / weight_total
        for skill_id in skill_ids
    }
    additions = {skill_id: int(exact[skill_id]) for skill_id in skill_ids}
    targets = {
        skill_id: targets[skill_id] + additions[skill_id]
        for skill_id in skill_ids
    }
    remainder = desired_count - sum(targets.values())
    ranked = sorted(
        skill_ids,
        key=lambda skill_id: (
            exact[skill_id] - additions[skill_id],
            -skill_ids.index(skill_id),
        ),
        reverse=True,
    )
    for skill_id in ranked[:remainder]:
        targets[skill_id] += 1
    return targets


def _allocate_deficit_chunk(
    deficits: dict[str, int],
    target_count: int,
) -> dict[str, int]:
    allocation = {skill_id: 0 for skill_id in deficits}
    remaining_deficits = dict(deficits)
    remaining_slots = target_count
    # Prioritize the largest deficits so chunks smaller than the skill map do
    # not starve later entries; stable sort keeps map order as the tie-breaker.
    ordered_skill_ids = sorted(
        remaining_deficits,
        key=lambda skill_id: remaining_deficits[skill_id],
        reverse=True,
    )
    for skill_id in ordered_skill_ids:
        if remaining_slots <= 0:
            break
        deficit = remaining_deficits[skill_id]
        if deficit <= 0:
            continue
        allocation[skill_id] += 1
        remaining_deficits[skill_id] -= 1
        remaining_slots -= 1
    for _ in range(remaining_slots):
        candidates = [
            skill_id
            for skill_id, remaining in remaining_deficits.items()
            if remaining > 0
        ]
        if not candidates:
            break
        selected = max(candidates, key=lambda skill_id: remaining_deficits[skill_id])
        allocation[selected] += 1
        remaining_deficits[selected] -= 1
    return {
        skill_id: count for skill_id, count in allocation.items() if count > 0
    }


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
    *,
    observed_desired_count: int,
    observed_low_watermark: int,
    observed_ready_count: int,
    observed_generated_count: int,
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
                        "state": _s("ready"),
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
                        "AND desiredCount = :observedDesired "
                        "AND lowWatermark = :observedLow "
                        "AND readyCount <= :observedReady "
                        "AND generatedCount = :observedGenerated "
                        "AND attribute_not_exists(tombstonedAt)"
                    ),
                    "ExpressionAttributeNames": {"#state": "state"},
                    "ExpressionAttributeValues": {
                        ":count": _n(len(questions)),
                        ":state": _s("ready"),
                        ":now": _n(now),
                        ":ttl": _n(now + _bank_ttl_seconds()),
                        ":job": _s(_job_id_from_key(job_key)),
                        ":revision": _s(context_revision),
                        ":observedDesired": _n(observed_desired_count),
                        ":observedLow": _n(observed_low_watermark),
                        ":observedReady": _n(observed_ready_count),
                        ":observedGenerated": _n(observed_generated_count),
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
                        ":job": _s(_job_id_from_key(job_key)),
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
                            "SET #status = :queued, updatedAt = :now "
                            "REMOVE leaseToken, leaseUntil"
                        ),
                        "ConditionExpression": "leaseToken = :token",
                        "ExpressionAttributeNames": {"#status": "status"},
                        "ExpressionAttributeValues": {
                            ":queued": _s("queued"),
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


def _mark_generation_blocked(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
    job_key: dict[str, Any],
    lease_token: str,
    reason: str,
) -> None:
    """Stop automatic generation for this exact bank context."""
    now = int(time.time())
    job_id = _job_id_from_key(job_key)
    client.transact_write_items(
        TransactItems=[
            {
                "Update": {
                    "TableName": table_name,
                    "Key": job_key,
                    "UpdateExpression": (
                        "SET #status = :blocked, failureCode = :reason, "
                        "failedAt = :now, updatedAt = :now REMOVE leaseToken, leaseUntil"
                    ),
                    "ConditionExpression": "leaseToken = :token",
                    "ExpressionAttributeNames": {"#status": "status"},
                    "ExpressionAttributeValues": {
                        ":blocked": _s("blocked"),
                        ":reason": _s(reason),
                        ":now": _n(now),
                        ":token": _s(lease_token),
                    },
                }
            },
            {
                "Update": {
                    "TableName": table_name,
                    "Key": bank_key,
                    "UpdateExpression": (
                        "SET #state = :blocked, generationBlockedReason = :reason, "
                        "updatedAt = :now REMOVE activeJobID, refillAfter"
                    ),
                    "ConditionExpression": "activeJobID = :job",
                    "ExpressionAttributeNames": {"#state": "state"},
                    "ExpressionAttributeValues": {
                        ":blocked": _s("blocked"),
                        ":reason": _s(reason),
                        ":now": _n(now),
                        ":job": _s(job_id),
                    },
                }
            },
        ]
    )


def _mark_job_terminal_failure(
    client: Any,
    message: dict[str, Any],
    receive_count: int,
) -> None:
    """Terminally fail a poison job while preserving SQS redrive to the DLQ."""
    table_name, _ = _configuration()
    bank_pk = _required_internal_string(message.get("bankPK"), "bankPK")
    job_id = _required_internal_string(message.get("jobID"), "jobID")
    job_key = {"pk": _s(bank_pk), "sk": _s(f"JOB#{job_id}")}
    bank_key = {"pk": _s(bank_pk), "sk": _s("META")}
    now = int(time.time())
    retry_at = now + _failure_cooldown_seconds()
    try:
        client.transact_write_items(
            TransactItems=[
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": job_key,
                        "UpdateExpression": (
                            "SET #status = :failed, failedAt = :now, "
                            "failureReceiveCount = :receives, updatedAt = :now "
                            "REMOVE leaseToken, leaseUntil"
                        ),
                        "ConditionExpression": (
                            "#status = :queued OR #status = :processing"
                        ),
                        "ExpressionAttributeNames": {"#status": "status"},
                        "ExpressionAttributeValues": {
                            ":failed": _s("failed"),
                            ":queued": _s("queued"),
                            ":processing": _s("processing"),
                            ":receives": _n(receive_count),
                            ":now": _n(now),
                        },
                    }
                },
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": bank_key,
                        "UpdateExpression": (
                            "SET #state = :failed, refillAfter = :retry, updatedAt = :now "
                            "REMOVE activeJobID"
                        ),
                        "ConditionExpression": "activeJobID = :job",
                        "ExpressionAttributeNames": {"#state": "state"},
                        "ExpressionAttributeValues": {
                            ":failed": _s("failed"),
                            ":retry": _n(retry_at),
                            ":now": _n(now),
                            ":job": _s(job_id),
                        },
                    }
                },
            ]
        )
    except Exception as error:
        if not _is_conditional_failure(error):
            raise


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
    job_id = _job_id_from_key(job_key)
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


def _query_question_history(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
) -> list[dict[str, Any]]:
    return _query_bank_items(client, table_name, bank_key, sort_key_prefix="QUESTION#")


def _query_bank_items(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
    *,
    sort_key_prefix: str | None = None,
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    last_key = None
    while True:
        request: dict[str, Any] = {
            "TableName": table_name,
            "KeyConditionExpression": "pk = :pk",
            "ExpressionAttributeValues": {":pk": bank_key["pk"]},
            "ConsistentRead": True,
        }
        if sort_key_prefix is not None:
            request["KeyConditionExpression"] += " AND begins_with(sk, :prefix)"
            request["ExpressionAttributeValues"][":prefix"] = _s(sort_key_prefix)
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
    retry_is_pending = (
        _number(meta, "refillAfter") > int(time.time())
        and not _boolean(meta, "initialFillComplete")
    )
    if _string(meta, "generationBlockedReason"):
        state = "ready" if ready else "empty"
    elif state == "failed" or retry_is_pending:
        # A cooldown is delayed work, not terminal exhaustion. Keeping it
        # queued lets finite-bank clients distinguish a retryable empty bank
        # from one that has generated and served its full lifetime allowance.
        state = "queued"
    elif state not in {"queued", "processing", "ready", "empty"}:
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


def _job_id_from_key(job_key: dict[str, Any]) -> str:
    return _string_from_key(job_key["sk"]).removeprefix("JOB#")


def _is_conditional_failure(error: Exception) -> bool:
    response = getattr(error, "response", {})
    code = response.get("Error", {}).get("Code", "")
    if code == "ConditionalCheckFailedException":
        return True
    if code == "TransactionCanceledException":
        reasons = response.get("CancellationReasons", [])
        return any(reason.get("Code") == "ConditionalCheckFailed" for reason in reasons if isinstance(reason, dict)) or "ConditionalCheckFailed" in str(response)
    return False


def _is_pending_job_image(event_name: Any, image: Any) -> bool:
    if event_name not in {"INSERT", "MODIFY"} or not isinstance(image, dict):
        return False
    return (
        _string(image, "itemType") == "job"
        and _string(image, "status") == "queued"
        and _string(image, "enqueueStatus") == "pending"
        and _string(image, "sk").startswith("JOB#")
    )


def _receive_count(record: dict[str, Any]) -> int:
    try:
        return max(
            1,
            int(record.get("attributes", {}).get("ApproximateReceiveCount", "1")),
        )
    except (TypeError, ValueError, AttributeError):
        return 1


def _max_receive_count() -> int:
    return _integer_env(
        "QUESTION_BANK_MAX_RECEIVE_COUNT",
        DEFAULT_MAX_RECEIVE_COUNT,
    )


def _generation_chunk_count() -> int:
    return min(
        MAX_CLAIM_COUNT,
        _integer_env(
            "QUESTION_BANK_GENERATION_CHUNK_SIZE",
            DEFAULT_GENERATION_CHUNK_COUNT,
        ),
    )


def _failure_cooldown_seconds() -> int:
    return _integer_env(
        "QUESTION_BANK_FAILURE_COOLDOWN_SECONDS",
        DEFAULT_FAILURE_COOLDOWN_SECONDS,
    )


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
