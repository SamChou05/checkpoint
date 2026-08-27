"""Question-bank worker allocation, persistence, and failure handling."""

from __future__ import annotations

import json
import os
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from question_bank_common import LOGGER, MAX_CLAIM_COUNT, QuestionBankError
from question_bank_store import (
    _bank_ttl_seconds,
    _configuration,
    _failure_cooldown_seconds,
    _get_item,
    _integer_env,
    _is_conditional_failure,
    _job_id_from_key,
    _json,
    _max_receive_count,
    _n,
    _number,
    _question_from_item,
    _required_internal_string,
    _required_rate_limiting,
    _s,
    _string,
)


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
        if (
            refreshed
            and _number(refreshed, "quotaChargedPass", default=-1) == generation_pass
        ):
            return
        if _is_conditional_failure(error):
            _mark_rate_limited(client, question_table, job_key)
            raise QuestionBankError(
                429, "Daily asynchronous generation limit reached.", "rate_limited"
            ) from error
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
        else [
            item for item in existing_items if _string(item, "state") in {"", "ready"}
        ]
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
    positive_skill_ids = [skill_id for skill_id in skill_ids if weights[skill_id] > 0]
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
        skill_id: targets[skill_id] + additions[skill_id] for skill_id in skill_ids
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
    return {skill_id: count for skill_id, count in allocation.items() if count > 0}


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
        remote_id = str(
            uuid.uuid5(uuid.NAMESPACE_URL, f"checkpoint:{bank_id}:{canonical}")
        )
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
                        "ExpressionAttributeValues": {
                            ":queued": _s("queued"),
                            ":now": _n(now),
                        },
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
    retry_at = int(
        (
            datetime.combine(
                now.date() + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc
            )
        ).timestamp()
    )
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
                        "ExpressionAttributeValues": {
                            ":limited": _s("rate_limited"),
                            ":now": _n(int(now.timestamp())),
                        },
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
