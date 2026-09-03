"""Question-bank versioning, inventory scheduling, and delivery."""

from __future__ import annotations

import time
import uuid
from typing import Any

from question_bank_common import LOGGER, QuestionBankError
from question_bank_store import (
    _bank_key,
    _bank_ttl_seconds,
    _boolean,
    _is_conditional_failure,
    _json,
    _n,
    _number,
    _parse_bank_pk,
    _plain_digest,
    _required_internal_string,
    _s,
    _string,
    _string_from_key,
)


def _facade() -> Any:
    """Resolve compatibility seams lazily to avoid an import cycle."""
    import question_bank

    return question_bank


def _validate_durable_skill_allocation(
    normalized_request: dict[str, Any],
    desired_count: int,
) -> None:
    skills = normalized_request.get("skillMap", {}).get("skills", [])
    if not skills:
        return
    allocation = normalized_request.get("desiredSkillAllocation", {})
    skill_ids = [skill["id"] for skill in skills]
    weights = (
        {skill_id: allocation.get(skill_id, 0) for skill_id in skill_ids}
        if allocation
        else {skill_id: 1 for skill_id in skill_ids}
    )
    apportioned_targets = _facade()._apportion_skill_counts(
        skill_ids,
        weights,
        desired_count,
    )
    requires_full_objective_coverage = (
        normalized_request.get("requiresFullObjectiveCoverage") is True
    )
    undersized_skills = [
        skill
        for skill in skills
        if weights[skill["id"]] > 0
        and apportioned_targets.get(skill["id"], 0)
        < (
            max(1, len(skill.get("objectives", [])))
            if requires_full_objective_coverage
            else 1
        )
    ]
    if undersized_skills:
        coverage_requirement = (
            " and every active objective within that skill"
            if requires_full_objective_coverage
            else ""
        )
        raise QuestionBankError(
            400,
            "desiredCount and desiredSkillAllocation must provide at least one "
            "durable inventory slot for every positive-weight skill"
            f"{coverage_requirement}.",
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
    existing_meta = _facade()._get_item(client, table_name, bank_key, consistent=True)
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
            "failedGenerationJobCount": _n(0),
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
        pointer = _facade()._get_item(client, table_name, pointer_key, consistent=True)
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
    raise QuestionBankError(
        409, "Goal context changed concurrently; retry ensure.", "bank_conflict"
    )


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
    values = {
        ":request": _s(_json(normalized)),
        ":allocation": _s(_skill_allocation_key(normalized)),
        ":desired": _n(desired_count),
        ":low": _n(low_watermark),
        ":now": _n(now),
        ":ttl": _n(now + _bank_ttl_seconds()),
        ":revision": _s(context_revision),
    }
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
                "skillAllocationKey = :allocation) "
                "AND (attribute_not_exists(desiredCount) OR desiredCount <= :desired)"
            ),
            ExpressionAttributeValues=values,
            ReturnValues="ALL_NEW",
        )["Attributes"]
    except Exception as error:
        if not _is_conditional_failure(error):
            raise

    try:
        return client.update_item(
            TableName=table_name,
            Key=bank_key,
            UpdateExpression=(
                "SET generationRequest = :request, skillAllocationKey = :allocation, "
                "lowWatermark = :low, updatedAt = :now, expiresAt = :ttl"
            ),
            ConditionExpression=(
                "contextRevision = :revision AND attribute_not_exists(tombstonedAt) "
                "AND (attribute_not_exists(skillAllocationKey) OR "
                "skillAllocationKey = :allocation) AND desiredCount >= :desired"
            ),
            ExpressionAttributeValues=values,
            ReturnValues="ALL_NEW",
        )["Attributes"]
    except Exception as error:
        if _is_conditional_failure(error):
            raise QuestionBankError(
                409, "Question bank context is stale.", "stale_bank"
            ) from error
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
        if low_watermark == 0 and not _boolean(meta, "initialFillComplete"):
            _mark_initial_fill_complete(client, table_name, bank_key, now)
        return False
    active_job_id = _string(meta, "activeJobID")
    if active_job_id:
        job_key = {"pk": bank_key["pk"], "sk": _s(f"JOB#{active_job_id}")}
        job = _facade()._get_item(client, table_name, job_key, consistent=True)
        if job and _string(job, "status") == "queued":
            try:
                _facade()._deliver_job(
                    client, queue, table_name, queue_url, job_key, job
                )
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
        refreshed = _facade()._get_item(client, table_name, bank_key, consistent=True)
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
            refreshed = _facade()._get_item(
                client, table_name, bank_key, consistent=True
            )
            if refreshed and _string(refreshed, "activeJobID"):
                active_id = _string(refreshed, "activeJobID")
                active_key = {"pk": bank_key["pk"], "sk": _s(f"JOB#{active_id}")}
                active = _facade()._get_item(
                    client, table_name, active_key, consistent=True
                )
                if active and _string(active, "status") == "queued":
                    try:
                        _facade()._deliver_job(
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
    job = (
        _facade()._get_item(client, table_name, job_key, consistent=True)
        or transaction[1]["Put"]["Item"]
    )
    try:
        _facade()._deliver_job(client, queue, table_name, queue_url, job_key, job)
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
    current = _facade()._get_item(client, table_name, job_key, consistent=True) or job
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
