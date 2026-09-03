# Re-exported implementation symbols preserve the established module seam.
# ruff: noqa: F401
"""Durable asynchronous question-bank facade backed by DynamoDB and SQS.

Inventory, storage, and worker details live in focused modules. Existing
symbols remain re-exported here for handlers, tests, and operational tooling.
"""

from __future__ import annotations

import json
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Callable

from question_bank_common import (
    DEFAULT_BANK_TTL_SECONDS,
    DEFAULT_FAILURE_COOLDOWN_SECONDS,
    DEFAULT_GENERATION_CHUNK_COUNT,
    DEFAULT_MAX_RECEIVE_COUNT,
    LOGGER,
    MAX_CLAIM_COUNT,
    MAX_DESIRED_COUNT,
    WORKER_LEASE_SECONDS,
    NonRetryableGenerationError,
    ProviderAttemptLimitError,
    ProviderQuotaLimitError,
    QuestionBankError,
    _normalized_stem_identity,
    _stem_fingerprint,
    _validated_blocked_stem_fingerprints,
)
from question_bank_inventory import (
    _activate_goal_version,
    _deliver_job,
    _ensure_refill,
    _inventory_progress,
    _mark_bank_superseded,
    _mark_initial_fill_complete,
    _skill_allocation_key,
    _update_bank_configuration,
    _validate_durable_skill_allocation,
)
from question_bank_store import (
    _bank_key,
    _bank_response,
    _bank_ttl_seconds,
    _boolean,
    _configuration,
    _dynamodb_client,
    _failure_cooldown_seconds,
    _generation_chunk_count,
    _get_item,
    _integer_env,
    _is_conditional_failure,
    _is_pending_job_image,
    _job_id_from_key,
    _json,
    _max_receive_count,
    _n,
    _number,
    _owner_digest,
    _parse_bank_pk,
    _plain_digest,
    _pointer_key,
    _query_bank_items,
    _query_question_history,
    _question_from_item,
    _receive_count,
    _require_active_meta,
    _require_current_bank,
    _required_hex_identifier,
    _required_identifier,
    _required_int,
    _required_internal_string,
    _required_rate_limiting,
    _required_revision,
    _s,
    _secret_digest,
    _sqs_client,
    _stored_claim,
    _string,
    _string_from_key,
)
from question_bank_worker import (
    _allocate_deficit_chunk,
    _apportion_skill_counts,
    _commit_generated_questions,
    _complete_job_without_questions,
    _finish_stale_job,
    _mark_generation_blocked,
    _mark_job_terminal_failure,
    _mark_rate_limited,
    _prepare_questions,
    _recent_question_items,
    _reserve_provider_attempt,
    _reset_job_for_retry,
    _worker_objective_allocation,
    _worker_skill_allocation,
)


for _compatibility_type in (
    QuestionBankError,
    NonRetryableGenerationError,
    ProviderAttemptLimitError,
    ProviderQuotaLimitError,
):
    _compatibility_type.__module__ = __name__
del _compatibility_type


MAX_CLAIM_TRANSACTION_QUESTION_UPDATES = 22
MAX_DUPLICATE_CLEANUP_QUESTION_UPDATES = 23


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
    desired_count = _required_int(
        payload.get("desiredCount"), "desiredCount", 1, MAX_DESIRED_COUNT
    )
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
    effective_desired_count = max(desired_count, _number(meta, "desiredCount"))
    effective_low_watermark = _number(meta, "lowWatermark")
    if _inventory_progress(meta) >= effective_desired_count:
        if effective_low_watermark == 0 and not _boolean(
            meta, "initialFillComplete"
        ):
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

    try:
        blocked_stem_fingerprints = set(
            _validated_blocked_stem_fingerprints(
                payload.get("blockedStemFingerprints")
            )
        )
    except ValueError as error:
        raise QuestionBankError(400, str(error), "invalid_request") from error

    for _ in range(8):
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
        seen_stem_identities = set()
        for item in history_items:
            if _string(item, "state") != "claimed":
                continue
            try:
                question = _question_from_item(item)
            except (json.JSONDecodeError, TypeError):
                continue
            if not isinstance(question, dict):
                continue
            stem_identity = _normalized_stem_identity(question.get("prompt"))
            if stem_identity:
                seen_stem_identities.add(stem_identity)
        question_items = []
        claimed_items = []
        discard_items = []
        questions = []
        for item in all_ready_items:
            question_items.append(item)
            try:
                question = _question_from_item(item)
            except (json.JSONDecodeError, TypeError):
                discard_items.append(item)
                continue
            if not isinstance(question, dict):
                discard_items.append(item)
                continue
            stem_identity = _normalized_stem_identity(question.get("prompt"))
            stem_is_blocked = (
                _stem_fingerprint(question.get("prompt"))
                in blocked_stem_fingerprints
            )
            if (
                not stem_identity
                or stem_is_blocked
                or stem_identity in seen_stem_identities
            ):
                discard_items.append(item)
                continue
            seen_stem_identities.add(stem_identity)
            claimed_items.append(item)
            questions.append(question)
            if len(questions) >= limit:
                break
        if len(question_items) > MAX_CLAIM_TRANSACTION_QUESTION_UPDATES:
            # A claim needs three transaction slots for META, its idempotency
            # record, and the active-goal condition. Retire enough bad legacy
            # rows first, then rebuild a full unique claim from fresh state.
            _consume_duplicate_question_rows(
                client,
                table_name,
                bank_key,
                pointer_key,
                meta,
                discard_items[:MAX_DUPLICATE_CLEANUP_QUESTION_UPDATES],
            )
            continue
        # Every scanned row is terminally transitioned below. Valid rows become
        # claimed; malformed or duplicate legacy rows become discarded and
        # therefore never masquerade as questions that were actually served.
        # QUESTION records have their own TTL. Reconcile the cached counter to
        # the strongly consistent inventory instead of trusting a stale META.
        after_count = len(all_ready_items) - len(question_items)
        desired_count = _number(meta, "desiredCount")
        low_watermark = _number(meta, "lowWatermark")
        observed_generated = _number(meta, "generatedCount")
        after_generated = (
            max(0, observed_generated - len(discard_items))
            if low_watermark == 0
            else observed_generated
        )
        blocked_reason = _string(meta, "generationBlockedReason")
        finite_fill_pending = low_watermark == 0 and after_generated < desired_count
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
            "status": "queued"
            if needs_refill
            else ("ready" if after_count else "empty"),
            "readyCount": after_count,
            "targetCount": desired_count,
            "questions": questions,
        }
        if blocked_reason:
            response["generationBlockedReason"] = blocked_reason
        now = int(time.time())
        meta_condition = (
            "readyCount = :observed AND desiredCount = :observedDesired "
            "AND lowWatermark = :observedLow "
            "AND attribute_not_exists(tombstonedAt)"
        )
        meta_values = {
            ":after": _n(after_count),
            ":observed": _n(observed_ready),
            ":observedDesired": _n(desired_count),
            ":observedLow": _n(low_watermark),
            ":state": _s(response["status"]),
            ":now": _n(now),
            ":ttl": _n(now + _bank_ttl_seconds()),
        }
        meta_setters = [
            "readyCount = :after",
            "#state = :state",
            "updatedAt = :now",
            "expiresAt = :ttl",
        ]
        if low_watermark == 0 and discard_items:
            meta_condition += " AND generatedCount = :observedGenerated"
            meta_values[":observedGenerated"] = _n(observed_generated)
            meta_values[":afterGenerated"] = _n(after_generated)
            meta_setters.append("generatedCount = :afterGenerated")
        if blocked_reason:
            meta_condition += " AND generationBlockedReason = :blockedReason"
            meta_values[":blockedReason"] = _s(blocked_reason)
        else:
            meta_condition += " AND attribute_not_exists(generationBlockedReason)"
        transaction: list[dict[str, Any]] = []
        claimed_keys = {_string(item, "sk") for item in claimed_items}
        for item in question_items:
            is_claimed = _string(item, "sk") in claimed_keys
            terminal_state = "claimed" if is_claimed else "discarded"
            terminal_timestamp = "claimedAt" if is_claimed else "discardedAt"
            stale_timestamp = "discardedAt" if is_claimed else "claimedAt"
            transaction.append(
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": {"pk": item["pk"], "sk": item["sk"]},
                        "UpdateExpression": (
                            f"SET #state = :terminal, {terminal_timestamp} = :now, "
                            f"expiresAt = :ttl REMOVE {stale_timestamp}"
                        ),
                        "ConditionExpression": (
                            "attribute_not_exists(#state) OR #state = :ready"
                        ),
                        "ExpressionAttributeNames": {"#state": "state"},
                        "ExpressionAttributeValues": {
                            ":terminal": _s(terminal_state),
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
                        "UpdateExpression": "SET " + ", ".join(meta_setters),
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

    raise QuestionBankError(
        409, "Question inventory changed; retry the claim.", "claim_conflict"
    )


def _consume_duplicate_question_rows(
    client: Any,
    table_name: str,
    bank_key: dict[str, Any],
    pointer_key: dict[str, Any],
    meta: dict[str, Any],
    items: list[dict[str, Any]],
) -> None:
    """Retire legacy duplicate/corrupt rows before an atomic full-size claim."""
    if not items:
        return
    observed_ready = _number(meta, "readyCount")
    after_count = max(0, observed_ready - len(items))
    desired_count = _number(meta, "desiredCount")
    low_watermark = _number(meta, "lowWatermark")
    observed_generated = _number(meta, "generatedCount")
    after_generated = (
        max(0, observed_generated - len(items))
        if low_watermark == 0
        else observed_generated
    )
    blocked_reason = _string(meta, "generationBlockedReason")
    finite_fill_pending = low_watermark == 0 and after_generated < desired_count
    needs_refill = not blocked_reason and (
        finite_fill_pending
        or (
            low_watermark > 0
            and after_count <= low_watermark
            and after_count < desired_count
        )
    )
    state = "queued" if needs_refill else ("ready" if after_count else "empty")
    now = int(time.time())
    transaction: list[dict[str, Any]] = []
    for item in items:
        transaction.append(
            {
                "Update": {
                    "TableName": table_name,
                    "Key": {"pk": item["pk"], "sk": item["sk"]},
                    "UpdateExpression": (
                        "SET #state = :discarded, discardedAt = :now, "
                        "expiresAt = :ttl REMOVE claimedAt"
                    ),
                    "ConditionExpression": (
                        "attribute_not_exists(#state) OR #state = :ready"
                    ),
                    "ExpressionAttributeNames": {"#state": "state"},
                    "ExpressionAttributeValues": {
                        ":discarded": _s("discarded"),
                        ":ready": _s("ready"),
                        ":now": _n(now),
                        ":ttl": _n(now + _bank_ttl_seconds()),
                    },
                }
            }
        )
    meta_condition = (
        "readyCount = :observed AND desiredCount = :observedDesired "
        "AND lowWatermark = :observedLow "
        "AND attribute_not_exists(tombstonedAt)"
    )
    meta_values = {
        ":after": _n(after_count),
        ":observed": _n(observed_ready),
        ":observedDesired": _n(desired_count),
        ":observedLow": _n(low_watermark),
        ":state": _s(state),
        ":now": _n(now),
        ":ttl": _n(now + _bank_ttl_seconds()),
    }
    meta_setters = [
        "readyCount = :after",
        "#state = :state",
        "updatedAt = :now",
        "expiresAt = :ttl",
    ]
    if low_watermark == 0:
        meta_condition += " AND generatedCount = :observedGenerated"
        meta_values[":observedGenerated"] = _n(observed_generated)
        meta_values[":afterGenerated"] = _n(after_generated)
        meta_setters.append("generatedCount = :afterGenerated")
    if blocked_reason:
        meta_condition += " AND generationBlockedReason = :blockedReason"
        meta_values[":blockedReason"] = _s(blocked_reason)
    else:
        meta_condition += " AND attribute_not_exists(generationBlockedReason)"

    transaction.extend(
        [
            {
                "Update": {
                    "TableName": table_name,
                    "Key": bank_key,
                    "UpdateExpression": "SET " + ", ".join(meta_setters),
                    "ConditionExpression": meta_condition,
                    "ExpressionAttributeNames": {"#state": "state"},
                    "ExpressionAttributeValues": meta_values,
                }
            },
            {
                "ConditionCheck": {
                    "TableName": table_name,
                    "Key": pointer_key,
                    "ConditionExpression": "currentBankID = :bank",
                    "ExpressionAttributeValues": {
                        ":bank": _s(_string(meta, "bankID"))
                    },
                }
            },
        ]
    )
    try:
        client.transact_write_items(TransactItems=transaction)
    except Exception as error:
        if not _is_conditional_failure(error):
            raise


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
    generate_questions: Callable[
        [dict[str, Any], Callable[[], None]], list[dict[str, Any]]
    ],
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
                _receive_count(record),
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
    generate_questions: Callable[
        [dict[str, Any], Callable[[], None]], list[dict[str, Any]]
    ],
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
        client.update_item(
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
        )
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
        _complete_job_without_questions(
            client, table_name, bank_key, job_key, lease_token, now
        )
        return

    generation_request = json.loads(_string(meta, "generationRequest"))
    existing_items = _query_question_history(client, table_name, bank_key)
    recent_items = _recent_question_items(
        [item for item in existing_items if _string(item, "state") != "discarded"],
        30,
    )
    existing_questions = [_question_from_item(item) for item in recent_items]
    generation_request["targetCount"] = min(_generation_chunk_count(), deficit)
    if generation_request.get("skillMap"):
        requested_skill_allocation = _worker_skill_allocation(
            generation_request,
            existing_items,
            desired_count=desired_count,
            low_watermark=low_watermark,
            target_count=generation_request["targetCount"],
        )
        generation_request["requestedSkillAllocation"] = requested_skill_allocation
        generation_request["requestedObjectiveAllocation"] = (
            _worker_objective_allocation(
                generation_request,
                existing_items,
                desired_count=desired_count,
                low_watermark=low_watermark,
                requested_skill_allocation=requested_skill_allocation,
            )
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

    def reserve_provider_call() -> None:
        if not _reserve_provider_attempt(
            client,
            table_name,
            job_key,
            lease_token,
            owner_digest,
        ):
            raise ProviderAttemptLimitError

    try:
        generated = generate_questions(generation_request, reserve_provider_call)
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
    except ProviderQuotaLimitError:
        if _mark_rate_limited(client, table_name, job_key):
            return
        _reset_job_for_retry(client, table_name, bank_key, job_key, lease_token)
        raise
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
