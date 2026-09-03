"""DynamoDB shapes, identifiers, configuration, and client access."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import time
from typing import Any

from question_bank_common import (
    DEFAULT_BANK_TTL_SECONDS,
    DEFAULT_FAILURE_COOLDOWN_SECONDS,
    DEFAULT_GENERATION_CHUNK_COUNT,
    DEFAULT_MAX_RECEIVE_COUNT,
    MAX_CLAIM_COUNT,
    QuestionBankError,
)


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
    retry_is_pending = _number(meta, "refillAfter") > int(time.time()) and not _boolean(
        meta, "initialFillComplete"
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
    response = {
        "bankID": _string(meta, "bankID"),
        "status": state,
        "readyCount": ready,
        "targetCount": target,
    }
    blocked_reason = _string(meta, "generationBlockedReason")
    if blocked_reason:
        response["generationBlockedReason"] = blocked_reason
    return response


def _stored_claim(item: dict[str, Any]) -> dict[str, Any]:
    return json.loads(_string(item, "responseJSON"))


def _question_from_item(item: dict[str, Any]) -> dict[str, Any]:
    return json.loads(_string(item, "questionJSON"))


def _require_active_meta(meta: dict[str, Any] | None, owner_digest: str) -> None:
    if not meta:
        raise QuestionBankError(404, "Question bank not found.", "bank_not_found")
    if meta.get("tombstonedAt"):
        raise QuestionBankError(
            410, "Question bank was deleted or superseded.", "bank_deleted"
        )
    if not hmac.compare_digest(_string(meta, "ownerHash"), owner_digest):
        raise QuestionBankError(404, "Question bank not found.", "bank_not_found")


def _require_current_bank(
    client: Any, table_name: str, pointer_key: dict[str, Any], bank_id: str
) -> None:
    pointer = _get_item(client, table_name, pointer_key, consistent=True)
    if not pointer or _string(pointer, "currentBankID") != bank_id:
        raise QuestionBankError(
            409, "Question bank belongs to an older goal context.", "stale_bank"
        )


def _configuration() -> tuple[str, str]:
    table_name = os.getenv("QUESTION_BANK_TABLE_NAME", "").strip()
    queue_url = os.getenv("QUESTION_BANK_QUEUE_URL", "").strip()
    if not table_name or not queue_url:
        raise QuestionBankError(
            503, "Question banks are temporarily unavailable.", "service_unavailable"
        )
    secret = os.getenv("QUOTA_HASH_SECRET", "").strip()
    if len(secret) < 32:
        raise QuestionBankError(
            503, "Question banks are temporarily unavailable.", "service_unavailable"
        )
    return table_name, queue_url


def _owner_digest(event: dict[str, Any]) -> str:
    headers = {
        str(key).lower(): value for key, value in (event.get("headers") or {}).items()
    }
    install_id = _required_identifier(
        headers.get("x-checkpoint-install-id"), "X-Checkpoint-Install-ID"
    )
    return _secret_digest("owner", install_id)


def _required_revision(value: Any) -> str:
    if not isinstance(value, str):
        raise QuestionBankError(400, "contextRevision must be text.", "invalid_request")
    cleaned = value.strip()
    if (
        not cleaned
        or len(cleaned) > 128
        or any(ord(character) < 33 for character in cleaned)
    ):
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
    return client.get_item(
        TableName=table_name, Key=key, ConsistentRead=consistent
    ).get("Item")


def _required_identifier(value: Any, field: str) -> str:
    if not isinstance(value, str):
        raise QuestionBankError(400, f"{field} must be text.", "invalid_request")
    cleaned = " ".join(value.split()).strip()
    if (
        not cleaned
        or len(cleaned) > 128
        or not re.fullmatch(r"[A-Za-z0-9_.:@/+\-=]+", cleaned)
    ):
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
        raise QuestionBankError(
            400, f"{field} must be an integer.", "invalid_request"
        ) from error
    if result < minimum or result > maximum:
        raise QuestionBankError(
            400, f"{field} must be between {minimum} and {maximum}.", "invalid_request"
        )
    return result


def _secret_digest(namespace: str, value: str) -> str:
    secret = os.getenv("QUOTA_HASH_SECRET", "").strip()
    return hmac.new(
        secret.encode(), f"checkpoint-{namespace}-v1:{value}".encode(), hashlib.sha256
    ).hexdigest()


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
        return any(
            reason.get("Code") == "ConditionalCheckFailed"
            for reason in reasons
            if isinstance(reason, dict)
        ) or "ConditionalCheckFailed" in str(response)
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
    configured = os.getenv("REQUIRE_RATE_LIMITING", "false").lower() in {
        "1",
        "true",
        "yes",
    }
    return configured or environment in {"production", "prod"}


def _dynamodb_client() -> Any:
    import boto3

    return boto3.client("dynamodb", region_name=os.getenv("AWS_REGION"))


def _sqs_client() -> Any:
    import boto3

    return boto3.client("sqs", region_name=os.getenv("AWS_REGION"))
