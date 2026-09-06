"""Question-bank worker allocation, persistence, and failure handling."""

from __future__ import annotations

import json
import os
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from question_bank_common import (
    DEFAULT_MAX_FAILED_GENERATION_JOBS,
    LOGGER,
    MAX_CLAIM_COUNT,
    ProviderQuotaLimitError,
    _normalized_stem_identity,
)
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


def _reserve_provider_attempt(
    client: Any,
    table_name: str,
    job_key: dict[str, Any],
    lease_token: str,
    owner_digest: str | None = None,
) -> bool:
    """Atomically reserve one imminent provider call and its async quota unit."""
    provider_limit = _max_receive_count()
    rate_table = os.getenv("RATE_LIMIT_TABLE_NAME", "").strip()
    if not rate_table and _required_rate_limiting():
        raise RuntimeError("Rate-limit table is required.")
    if rate_table and not owner_digest:
        raise RuntimeError("Owner digest is required for asynchronous rate limiting.")

    provider_update = {
        "TableName": table_name,
        "Key": job_key,
        "UpdateExpression": (
            "SET providerAttemptCount = "
            "if_not_exists(providerAttemptCount, :zero) + :one, updatedAt = :now"
        ),
        "ConditionExpression": (
            "leaseToken = :token AND "
            "(attribute_not_exists(providerAttemptCount) OR providerAttemptCount < :limit)"
        ),
        "ExpressionAttributeValues": {
            ":zero": _n(0),
            ":one": _n(1),
            ":limit": _n(provider_limit),
            ":token": _s(lease_token),
            ":now": _n(int(time.time())),
        },
    }
    rate_key: dict[str, Any] | None = None
    daily_limit = 0
    try:
        if rate_table:
            day = datetime.now(timezone.utc).strftime("%Y%m%d")
            rate_key = {"rateKey": _s(f"async-install#{owner_digest}#{day}")}
            daily_limit = _integer_env("MAX_REQUESTS_PER_INSTALL_PER_DAY", 40)
            expires_at = int(time.time()) + _integer_env(
                "RATE_LIMIT_TTL_SECONDS", 172800
            )
            client.transact_write_items(
                TransactItems=[
                    {"Update": provider_update},
                    {
                        "Update": {
                            "TableName": rate_table,
                            "Key": rate_key,
                            "UpdateExpression": (
                                "SET expiresAt = :ttl ADD #count :one"
                            ),
                            "ConditionExpression": (
                                "attribute_not_exists(#count) OR #count < :limit"
                            ),
                            "ExpressionAttributeNames": {"#count": "count"},
                            "ExpressionAttributeValues": {
                                ":ttl": _n(expires_at),
                                ":one": _n(1),
                                ":limit": _n(daily_limit),
                            },
                        }
                    },
                ]
            )
        else:
            client.update_item(**provider_update)
        return True
    except Exception as error:
        job = _get_item(client, table_name, job_key, consistent=True)
        if not job or _string(job, "leaseToken") != lease_token:
            raise
        if _number(job, "providerAttemptCount") >= provider_limit:
            return False
        if rate_table and rate_key is not None:
            quota = _get_item(client, rate_table, rate_key, consistent=True)
            if quota and _number(quota, "count") >= daily_limit:
                raise ProviderQuotaLimitError(
                    "Daily asynchronous provider-call quota reached."
                ) from error
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
    relevant_items = [
        item
        for item in existing_items
        if _string(item, "state")
        in ({"", "ready", "claimed"} if low_watermark == 0 else {"", "ready"})
    ]
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


def _worker_objective_allocation(
    generation_request: dict[str, Any],
    existing_items: list[dict[str, Any]],
    *,
    desired_count: int,
    low_watermark: int,
    requested_skill_allocation: dict[str, int],
) -> list[dict[str, Any]]:
    """Nest a worker chunk's skill slots into balanced objective quotas.

    Finite banks count both ready and claimed history so later chunks expand
    lifetime coverage. Replenishing banks count only currently ready inventory,
    matching the skill-allocation semantics for a rolling stock of questions.
    """
    skills = generation_request.get("skillMap", {}).get("skills", [])
    if not skills or not requested_skill_allocation:
        return []

    skill_ids = [skill.get("id", "") for skill in skills if skill.get("id")]
    desired_allocation = generation_request.get("desiredSkillAllocation", {})
    whole_bank_skill_targets = _apportion_skill_counts(
        skill_ids,
        desired_allocation if isinstance(desired_allocation, dict) else {},
        desired_count,
    )
    relevant_states = {"", "ready", "claimed"} if low_watermark == 0 else {"", "ready"}

    objective_owners: dict[str, tuple[str, str]] = {}
    for skill in skills:
        skill_id = skill.get("id", "")
        if not skill_id:
            continue
        for objective in skill.get("objectives", []):
            objective_id = objective.get("id", "")
            objective_key = _uuid_identity_key(objective_id)
            if objective_key:
                objective_owners[objective_key] = (skill_id, objective_id)

    existing_counts: dict[tuple[str, str], int] = {}
    for item in existing_items:
        if _string(item, "state") not in relevant_states:
            continue
        try:
            question = _question_from_item(item)
        except (json.JSONDecodeError, TypeError):
            continue
        if not isinstance(question, dict):
            continue
        objective_owner = objective_owners.get(
            _uuid_identity_key(question.get("objectiveID"))
        )
        if not objective_owner:
            continue
        skill_id, objective_id = objective_owner
        if _uuid_identity_key(question.get("skillID")) != _uuid_identity_key(skill_id):
            continue
        pair = (skill_id, objective_id)
        existing_counts[pair] = existing_counts.get(pair, 0) + 1

    requested_objectives: list[dict[str, Any]] = []
    for skill in skills:
        skill_id = skill.get("id", "")
        batch_slots = requested_skill_allocation.get(skill_id, 0)
        if isinstance(batch_slots, bool) or not isinstance(batch_slots, int):
            continue
        batch_slots = max(0, batch_slots)
        objective_ids = [
            objective.get("id", "")
            for objective in skill.get("objectives", [])
            if objective.get("id")
        ]
        if batch_slots == 0 or not objective_ids:
            continue

        whole_skill_target = max(0, whole_bank_skill_targets.get(skill_id, 0))
        plan = next(
            (
                plan
                for plan in generation_request.get("adaptiveSkillPlans", [])
                if plan["skillID"] == skill_id
            ),
            {},
        )
        focus_ids = set(plan.get("focusObjectiveIDs", []))
        whole_objective_targets = _apportion_skill_counts(
            objective_ids,
            {
                objective_id: 3 if objective_id in focus_ids else 1
                for objective_id in objective_ids
            },
            whole_skill_target,
        )
        deficits = {
            objective_id: max(
                0,
                whole_objective_targets.get(objective_id, 0)
                - existing_counts.get((skill_id, objective_id), 0),
            )
            for objective_id in objective_ids
        }
        chunk_allocation = _allocate_deficit_chunk(deficits, batch_slots)

        # Normalized banks make the target deficits large enough for every
        # requested skill slot. Keep this fallback deterministic if legacy or
        # manually repaired rows make their counters disagree.
        remaining_slots = batch_slots - sum(chunk_allocation.values())
        while remaining_slots > 0:
            selected = min(
                objective_ids,
                key=lambda objective_id: (
                    existing_counts.get((skill_id, objective_id), 0)
                    + chunk_allocation.get(objective_id, 0),
                    objective_ids.index(objective_id),
                ),
            )
            chunk_allocation[selected] = chunk_allocation.get(selected, 0) + 1
            remaining_slots -= 1

        requested_objectives.extend(
            {
                "skillID": skill_id,
                "objectiveID": objective_id,
                "count": chunk_allocation[objective_id],
            }
            for objective_id in objective_ids
            if chunk_allocation.get(objective_id, 0) > 0
        )

    return requested_objectives


def _uuid_identity_key(value: Any) -> str:
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, AttributeError, TypeError):
        return ""


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
    existing_stem_identities: set[str] = set()
    for item in existing_items:
        try:
            existing_question = _question_from_item(item)
        except (json.JSONDecodeError, TypeError):
            continue
        if not isinstance(existing_question, dict):
            continue
        stem_identity = _normalized_stem_identity(existing_question.get("prompt"))
        if stem_identity:
            existing_stem_identities.add(stem_identity)

    prepared: list[dict[str, Any]] = []
    seen = set(existing_ids)
    seen_stems = set(existing_stem_identities)
    for question in generated:
        if not isinstance(question, dict):
            continue
        stem_identity = _normalized_stem_identity(question.get("prompt"))
        if not stem_identity or stem_identity in seen_stems:
            continue
        canonical = _json(question)
        legacy_remote_id = str(
            uuid.uuid5(uuid.NAMESPACE_URL, f"checkpoint:{bank_id}:{canonical}")
        )
        remote_id = str(
            uuid.uuid5(
                uuid.NAMESPACE_URL,
                f"checkpoint:{bank_id}:stem:v2:{stem_identity}",
            )
        )
        if remote_id in seen or legacy_remote_id in seen:
            continue
        seen.add(remote_id)
        seen_stems.add(stem_identity)
        prepared.append({**question, "remoteID": remote_id})
        if len(prepared) >= MAX_CLAIM_COUNT:
            break
    return prepared


def _recent_question_items(
    existing_items: list[dict[str, Any]],
    limit: int,
) -> list[dict[str, Any]]:
    """Select deterministic creation-time feedback from UUID-keyed question rows."""
    if limit <= 0:
        return []
    ordered = sorted(
        existing_items,
        key=lambda item: (
            _number(item, "createdAt"),
            _string(item, "sk"),
        ),
    )
    return ordered[-limit:]


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
    """Fail one exhausted job and terminally block a persistently failing bank."""
    table_name, _ = _configuration()
    bank_pk = _required_internal_string(message.get("bankPK"), "bankPK")
    job_id = _required_internal_string(message.get("jobID"), "jobID")
    context_revision = _required_internal_string(
        message.get("contextRevision"), "contextRevision"
    )
    job_key = {"pk": _s(bank_pk), "sk": _s(f"JOB#{job_id}")}
    bank_key = {"pk": _s(bank_pk), "sk": _s("META")}
    now = int(time.time())
    meta = _get_item(client, table_name, bank_key, consistent=True)
    if (
        not meta
        or meta.get("tombstonedAt")
        or _string(meta, "generationBlockedReason")
        or _string(meta, "activeJobID") != job_id
        or _string(meta, "contextRevision") != context_revision
    ):
        return

    observed_failure_count = max(0, _number(meta, "failedGenerationJobCount"))
    failed_generation_job_count = observed_failure_count + 1
    reached_bank_failure_limit = (
        failed_generation_job_count >= _max_failed_generation_jobs()
    )
    bank_values = {
        ":failedCount": _n(failed_generation_job_count),
        ":observedFailedCount": _n(observed_failure_count),
        ":now": _n(now),
        ":job": _s(job_id),
        ":revision": _s(context_revision),
    }
    bank_condition = (
        "activeJobID = :job AND contextRevision = :revision "
        "AND attribute_not_exists(tombstonedAt) "
        "AND attribute_not_exists(generationBlockedReason) "
        "AND (attribute_not_exists(failedGenerationJobCount) OR "
        "failedGenerationJobCount = :observedFailedCount)"
    )
    if reached_bank_failure_limit:
        bank_update_expression = (
            "SET #state = :blocked, generationBlockedReason = :reason, "
            "generationBlockedAt = :now, failedGenerationJobCount = :failedCount, "
            "updatedAt = :now REMOVE activeJobID, refillAfter"
        )
        bank_values.update(
            {
                ":blocked": _s("blocked"),
                ":reason": _s("provider_failure_limit"),
            }
        )
    else:
        bank_update_expression = (
            "SET #state = :failed, refillAfter = :retry, "
            "failedGenerationJobCount = :failedCount, updatedAt = :now "
            "REMOVE activeJobID"
        )
        bank_values.update(
            {
                ":failed": _s("failed"),
                ":retry": _n(now + _failure_cooldown_seconds()),
            }
        )
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
                        "UpdateExpression": bank_update_expression,
                        "ConditionExpression": bank_condition,
                        "ExpressionAttributeNames": {"#state": "state"},
                        "ExpressionAttributeValues": bank_values,
                    }
                },
            ]
        )
    except Exception as error:
        if not _is_conditional_failure(error):
            raise


def _max_failed_generation_jobs() -> int:
    return _integer_env(
        "QUESTION_BANK_MAX_FAILED_GENERATION_JOBS",
        DEFAULT_MAX_FAILED_GENERATION_JOBS,
    )


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


def _mark_rate_limited(client: Any, table_name: str, job_key: dict[str, Any]) -> bool:
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
        return True
    except Exception:
        LOGGER.exception("Failed to mark asynchronous generation rate limit")
        return False
