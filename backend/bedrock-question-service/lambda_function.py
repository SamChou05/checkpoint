# Re-exported implementation symbols are part of the established tooling seam.
# ruff: noqa: F401
"""AWS Lambda entrypoints and HTTP orchestration for question generation.

Implementation modules own validation, provider access, prompts, skill-map
inference, and quality filtering. Their established symbols are re-exported
here so deployed handler paths and local tooling remain compatible.
"""

import base64
import binascii
import copy
import hashlib
import hmac
import json
import logging
import math
import os
import re
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Callable

import question_bank
from question_generation import (
    DEFAULT_BEDROCK_CONNECT_TIMEOUT_SECONDS,
    DEFAULT_BEDROCK_READ_TIMEOUT_SECONDS,
    DEFAULT_FALLBACK_MODEL_ID,
    DEFAULT_GENERATION_ATTEMPTS,
    DEFAULT_MAX_PROVIDER_CALLS,
    DEFAULT_MAX_TOKENS,
    DEFAULT_MIN_PROVIDER_REMAINING_MILLISECONDS,
    DEFAULT_MODEL_ID,
    DEFAULT_PROVIDER_DEADLINE_SAFETY_MILLISECONDS,
    DEFAULT_TEMPERATURE,
    SUPPORTED_OPENAI_REASONING_EFFORTS,
    ProviderCallBudget,
    _additional_model_request_fields,
    _bedrock_client,
    _conversation_prompt,
    _coverage_notes_text,
    _coverage_topic_summary,
    _generate_provider_payload,
    _generate_sanitized_questions,
    _generate_with_bedrock,
    _guardrail_config,
    _json_retry_prompt,
    _learner_level_text,
    _minimum_provider_remaining_milliseconds,
    _model_attempts,
    _model_attempts_with_fallback,
    _new_provider_call_budget,
    _openai_reasoning_effort,
    _prompt_variant_instructions,
    _question_skill_map_mode,
    _skill_allocation_text,
    _source_grounding_text,
    _system_prompt,
    _uses_inline_instructions,
    _user_prompt,
)
from question_quality import (
    GENERIC_META_CHOICE_SIGNALS,
    GENERIC_META_EXPECTED_ANSWER_SIGNALS,
    GENERIC_META_EXPLANATION_SIGNALS,
    GENERIC_META_SCENARIOS,
    MAX_PROVIDER_PROMPT_CHARS,
    _choice_set_key,
    _explanation_admits_bad_answer,
    _explanation_supported_choice,
    _explanation_supports_different_choice,
    _extract_json_object,
    _looks_like_answer_label,
    _looks_like_generic_meta_question,
    _looks_like_study_strategy,
    _matching_skill_map_entry,
    _matches_semantic_signal,
    _normalized_choices,
    _normalized_question_skill_tag,
    _parse_provider_json,
    _prompt_contains_embedded_options,
    _prompt_contains_latex_markup,
    _question_coverage_keys,
    _question_coverage_payload,
    _remaining_requested_skill_allocation,
    _sanitize_questions,
)
from request_contract import (
    DEFAULT_MAX_QUESTIONS,
    DEFAULT_MAX_REQUEST_BODY_BYTES,
    MAX_ARCHIVED_SKILL_NAME_FINGERPRINTS,
    MAX_OBJECTIVE_NAME_CHARS,
    MAX_SKILL_ALLOCATION_WEIGHT,
    MAX_SKILL_MAP_SKILLS,
    MAX_SKILL_NAME_CHARS,
    MAX_SKILL_OBJECTIVES,
    MAX_SOURCE_CONTEXT_CHARS,
    MAX_SOURCE_DOCUMENT_CHARS,
    MAX_SOURCE_DOCUMENT_NAME_CHARS,
    MAX_SOURCE_DOCUMENTS,
    SKILL_MAP_ID_PREFIX,
    SOURCE_TRUNCATION_MARKER,
    UNSUPPORTED_SKILL_NAME_SEPARATORS,
    _apportion_skill_allocation,
    _bool_env,
    _bounded_float_env,
    _canonical,
    _choice_uniqueness_key,
    _clamped_int,
    _clean_source_text,
    _clean_text,
    _clip,
    _decode_body,
    _deployment_environment,
    _deterministic_objective_id,
    _deterministic_skill_id,
    _difficulty_guidance,
    _duplicate_prompt_key,
    _float_env,
    _has_unsupported_skill_name_separator,
    _int_env,
    _is_development_environment,
    _is_production_environment,
    _list_of_question_coverage,
    _max_questions,
    _nonnegative_int,
    _normalize_request,
    _normalize_skill_map_evolution_request,
    _normalize_skill_map_inference_request,
    _normalized_archived_skill_name_fingerprints,
    _normalized_competencies,
    _normalized_desired_skill_allocation,
    _normalized_source_documents,
    _normalized_supplied_skill_map,
    _rate_limiting_required,
    _source_context_character_limits,
    _skill_map_fingerprint,
    _skill_name_fingerprint,
    _strip_answer_prefix,
    _strip_choice_label,
    _topics_from_focus,
    _topics_need_inference,
    _truncate_source_text,
    _uuid_key,
    _validated_string_list,
    _validated_text,
    _validated_uuid,
)
from service_errors import (
    BadRequestError,
    InvalidProviderResponseError,
    ProviderCallBudgetExceededError,
    ProviderError,
    RateLimitExceededError,
    SafetyInterventionError,
    ServiceConfigurationError,
)
from skill_maps import (
    MAX_EVOLUTION_REPLACEMENTS,
    MIN_INFERRED_SKILL_MAP_SKILLS,
    MIN_INFERRED_SKILL_OBJECTIVES,
    SKILL_MAP_EVOLUTION_ID_PREFIX,
    _deterministic_evolved_skill_id,
    _evolve_skill_map,
    _is_superficial_successor_name,
    _infer_skill_map,
    _sanitize_skill_map_evolution,
    _sanitize_inferred_skill_map,
    _skill_map_evolution_from_provider_text,
    _skill_map_evolution_retry_prompt,
    _skill_map_evolution_system_prompt,
    _skill_map_evolution_user_prompt,
    _skill_map_from_provider_text,
    _skill_map_model_attempts,
    _skill_map_retry_prompt,
    _skill_map_system_prompt,
    _skill_map_user_prompt,
    _skill_name_matches,
)


for _compatibility_type in (
    BadRequestError,
    InvalidProviderResponseError,
    ProviderError,
    RateLimitExceededError,
    ServiceConfigurationError,
    ProviderCallBudgetExceededError,
    SafetyInterventionError,
    ProviderCallBudget,
):
    _compatibility_type.__module__ = __name__
del _compatibility_type


LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(os.getenv("LOG_LEVEL", "INFO"))

DEFAULT_SERVICE_RETRY_AFTER_SECONDS = 300
METRIC_NAMESPACE = "Checkpoint/Backend"
METRIC_SERVICE = "QuestionGeneration"
HTTP_ROUTE_PATHS = {
    "/v1/questions",
    "/v1/skill-maps/evolve",
    "/v1/skill-maps/infer",
    "/v1/question-banks/ensure",
    "/v1/question-banks/claim",
}


def _service_mode() -> str:
    mode = os.getenv("SERVICE_MODE", "enabled").strip().lower()
    if mode in {"enabled", "drain", "disabled"}:
        return mode
    LOGGER.error("Invalid SERVICE_MODE; failing closed")
    return "disabled"


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    return handle_http_request(event, context=context)


def question_bank_worker_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Generate queued inventory independently of the HTTP request lifecycle."""
    started_at = time.monotonic()
    # Drain mode stops new HTTP work but intentionally finishes the durable
    # queue. Disabled deployments pause the SQS event source in the template;
    # this branch fails closed for any invocation already in flight while that
    # CloudFormation update is taking effect.
    if _service_mode() == "disabled":
        return {
            "batchItemFailures": [
                {"itemIdentifier": str(record.get("messageId", "unknown"))}
                for record in event.get("Records", [])
            ]
        }

    request_metrics = _new_request_metrics(context)
    safety_intervened = False
    terminal_failure = False

    def generate_questions(
        request: dict[str, Any],
        reserve_provider_call: Callable[[], None] | None = None,
    ) -> list[dict[str, Any]]:
        nonlocal safety_intervened
        request_metrics["QuestionsRequested"] += request["targetCount"]
        call_budget = _new_provider_call_budget(
            context,
            reserve_call=reserve_provider_call,
        )
        try:
            questions = _generate_sanitized_questions(
                request,
                None,
                call_budget=call_budget,
                request_metrics=request_metrics,
            )
        except SafetyInterventionError as error:
            safety_intervened = True
            raise question_bank.NonRetryableGenerationError(
                "safety_intervention"
            ) from error
        request_metrics["QuestionsReturned"] += len(questions)
        return questions

    def record_terminal_failure(_: str) -> None:
        nonlocal terminal_failure
        terminal_failure = True

    result = question_bank.handle_worker_event(
        event,
        context,
        generate_questions,
        on_terminal_failure=record_terminal_failure,
    )
    request_metrics["StatusCode"] = (
        502 if result["batchItemFailures"] or terminal_failure else 200
    )
    if terminal_failure:
        request_metrics["Outcome"] = "provider_failure"
    elif safety_intervened:
        request_metrics["Outcome"] = "safety_intervention"
    else:
        request_metrics["Outcome"] = (
            "async_success" if not result["batchItemFailures"] else "async_failure"
        )
    request_metrics["LatencyMilliseconds"] = round(
        (time.monotonic() - started_at) * 1000,
        2,
    )
    _emit_request_metrics(request_metrics)
    return result


def question_bank_outbox_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Forward durable pending job records from DynamoDB Streams to SQS."""
    return question_bank.handle_outbox_event(event, context)


def handle_http_request(
    event: dict[str, Any],
    bedrock_client: Any | None = None,
    dynamodb_client: Any | None = None,
    sqs_client: Any | None = None,
    context: Any | None = None,
) -> dict[str, Any]:
    started_at = time.monotonic()
    request_metrics = _new_request_metrics(context)
    outcome = "unknown"
    response: dict[str, Any]
    try:
        method = _http_method(event)
        path = _request_path(event)
        if method == "OPTIONS":
            outcome = "preflight"
            response = _response(204, "")
        elif method != "POST":
            outcome = "method_not_allowed"
            response = _error(405, "Method not allowed")
        elif (service_mode := _service_mode()) != "enabled":
            outcome = f"service_{service_mode}"
            response = _error(
                503,
                "Question generation is temporarily unavailable.",
                code="service_unavailable",
                headers={"Retry-After": str(_service_retry_after_seconds())},
            )
        elif not _is_authorized(event):
            outcome = "unauthorized"
            response = _error(401, "Unauthorized")
        else:
            # Decode and validate every client-controlled field before quota is charged.
            payload = _decode_body(event)
            if path == "/v1/skill-maps/infer":
                normalized = _normalize_skill_map_inference_request(payload)
                _check_rate_limits(event, dynamodb_client)
                call_budget = _new_provider_call_budget(context)
                skill_map = _infer_skill_map(
                    normalized,
                    bedrock_client,
                    call_budget=call_budget,
                    request_metrics=request_metrics,
                )
                outcome = "skill_map_success"
                response = _response(200, {"skillMap": skill_map})
            elif path == "/v1/skill-maps/evolve":
                normalized = _normalize_skill_map_evolution_request(payload)
                _check_rate_limits(event, dynamodb_client)
                call_budget = _new_provider_call_budget(context)
                evolution = _evolve_skill_map(
                    normalized,
                    bedrock_client,
                    call_budget=call_budget,
                    request_metrics=request_metrics,
                )
                outcome = "skill_map_evolution_success"
                response = _response(200, evolution)
            elif path == "/v1/question-banks/ensure":
                bank = question_bank.ensure_bank(
                    payload,
                    event,
                    _normalize_request,
                    dynamodb_client=dynamodb_client,
                    sqs_client=sqs_client,
                )
                outcome = "bank_ensured"
                response = _response(202, bank)
            elif path == "/v1/question-banks/claim":
                claim = question_bank.claim_questions(
                    payload,
                    event,
                    dynamodb_client=dynamodb_client,
                    sqs_client=sqs_client,
                )
                request_metrics["QuestionsReturned"] = len(claim["questions"])
                outcome = "bank_claimed"
                response = _response(200, claim)
            elif path not in {"", "/v1/questions"}:
                outcome = "not_found"
                response = _error(404, "Not found", code="not_found")
            else:
                normalized = _normalize_request(payload)
                request_metrics["QuestionsRequested"] = normalized["targetCount"]
                _check_rate_limits(event, dynamodb_client)
                call_budget = _new_provider_call_budget(context)
                questions = _generate_sanitized_questions(
                    normalized,
                    bedrock_client,
                    call_budget=call_budget,
                    request_metrics=request_metrics,
                )

                if not questions:
                    raise ProviderError("Provider returned no usable questions.")

                request_metrics["QuestionsReturned"] = len(questions)
                outcome = "success"
                response = _response(200, {"questions": questions})
    except question_bank.QuestionBankError as error:
        outcome = f"question_bank_{error.code}"
        response = _error(error.status_code, str(error), code=error.code)
    except BadRequestError as error:
        outcome = "bad_request"
        response = _error(400, str(error), code="invalid_request")
    except RateLimitExceededError:
        outcome = "rate_limited"
        response = _error(
            429,
            "Daily AI generation limit reached. Try again later.",
            code="rate_limited",
            headers={"Retry-After": str(_rate_limit_retry_after_seconds())},
        )
    except SafetyInterventionError:
        outcome = "safety_intervention"
        response = _error(
            422,
            "This request could not be processed safely.",
            code="safety_intervention",
        )
    except ServiceConfigurationError:
        outcome = "configuration_error"
        LOGGER.error("Backend configuration failed closed")
        response = _error(
            503,
            "Question generation is temporarily unavailable.",
            code="service_unavailable",
            headers={"Retry-After": str(_service_retry_after_seconds())},
        )
    except InvalidProviderResponseError:
        outcome = "provider_invalid_response"
        LOGGER.error("Question provider returned invalid output")
        response = _error(
            502,
            "Question generation returned invalid output",
            code="provider_invalid_response",
            headers={"Retry-After": str(_provider_retry_after_seconds())},
        )
    except ProviderError:
        outcome = "provider_failure"
        LOGGER.error("Question provider failed")
        response = _error(
            502,
            "Question generation failed",
            code="provider_failure",
            headers={"Retry-After": str(_provider_retry_after_seconds())},
        )
    except Exception:
        outcome = "system_failure"
        LOGGER.exception("Question generation failed")
        response = _error(
            502,
            "Question generation failed",
            code="system_failure",
            headers={"Retry-After": str(_provider_retry_after_seconds())},
        )

    request_metrics["StatusCode"] = response["statusCode"]
    request_metrics["LatencyMilliseconds"] = round(
        (time.monotonic() - started_at) * 1000, 2
    )
    request_metrics["Outcome"] = outcome
    _emit_request_metrics(request_metrics)
    return response


def _http_method(event: dict[str, Any]) -> str:
    return (
        event.get("requestContext", {}).get("http", {}).get("method")
        or event.get("httpMethod")
        or "POST"
    ).upper()


def _request_path(event: dict[str, Any]) -> str:
    gateway_path = event.get("rawPath") or event.get("requestContext", {}).get(
        "http", {}
    ).get("path")
    path = str(gateway_path or event.get("path") or "").rstrip("/")
    if path in HTTP_ROUTE_PATHS:
        return path

    stage = str(event.get("requestContext", {}).get("stage") or "").strip("/")
    stage_prefix = f"/{stage}"
    if stage and (path == stage_prefix or path.startswith(f"{stage_prefix}/")):
        candidate = path[len(stage_prefix) :]
        if candidate in HTTP_ROUTE_PATHS:
            return candidate
    return path


def _request_headers(event: dict[str, Any]) -> dict[str, Any]:
    return {
        str(key).lower(): value for key, value in (event.get("headers") or {}).items()
    }


def _is_authorized(event: dict[str, Any]) -> bool:
    expected_token = os.getenv("CHECKPOINT_BACKEND_TOKEN", "").strip()
    if not expected_token:
        return _is_development_environment() and _bool_env(
            "ALLOW_UNAUTHENTICATED_BACKEND", False
        )

    headers = _request_headers(event)
    auth_header = str(headers.get("authorization", "")).strip()
    return hmac.compare_digest(auth_header, f"Bearer {expected_token}")


def _check_rate_limits(event: dict[str, Any], dynamodb_client: Any | None) -> None:
    table_name = os.getenv("RATE_LIMIT_TABLE_NAME", "").strip()
    if not table_name:
        if _rate_limiting_required():
            raise ServiceConfigurationError("Rate-limit table is required.")
        return

    hash_secret = os.getenv("QUOTA_HASH_SECRET", "").strip()
    if len(hash_secret) < 32:
        raise ServiceConfigurationError(
            "Quota hash secret must be at least 32 characters."
        )

    client = dynamodb_client or _dynamodb_client()
    headers = _request_headers(event)
    install_id = _rate_limit_component(
        headers.get("x-checkpoint-install-id"), fallback="missing-install"
    )
    source_ip = _rate_limit_component(_source_ip(event), fallback="missing-ip")
    day = datetime.now(timezone.utc).strftime("%Y%m%d")
    expires_at = int(time.time()) + _int_env(
        "RATE_LIMIT_TTL_SECONDS",
        60 * 60 * 48,
        maximum=60 * 60 * 24 * 14,
    )

    limits = [
        (
            f"install#{_quota_identifier_digest(hash_secret, 'install', install_id)}#{day}",
            _int_env("MAX_REQUESTS_PER_INSTALL_PER_DAY", 40),
        ),
        (
            f"ip#{_quota_identifier_digest(hash_secret, 'ip', source_ip)}#{day}",
            _int_env("MAX_REQUESTS_PER_IP_PER_DAY", 400),
        ),
    ]

    _consume_rate_limits_atomically(client, table_name, limits, expires_at)


def _consume_rate_limits_atomically(
    client: Any,
    table_name: str,
    limits: list[tuple[str, int]],
    expires_at: int,
) -> None:
    transaction_items = []
    for key, limit in limits:
        transaction_items.append(
            {
                "Update": {
                    "TableName": table_name,
                    "Key": {"rateKey": {"S": key}},
                    "UpdateExpression": "SET expiresAt = :expiresAt ADD #count :one",
                    "ConditionExpression": "attribute_not_exists(#count) OR #count < :limit",
                    "ExpressionAttributeNames": {"#count": "count"},
                    "ExpressionAttributeValues": {
                        ":one": {"N": "1"},
                        ":limit": {"N": str(limit)},
                        ":expiresAt": {"N": str(expires_at)},
                    },
                }
            }
        )

    try:
        client.transact_write_items(TransactItems=transaction_items)
    except Exception as error:
        if _is_quota_transaction_failure(error):
            raise RateLimitExceededError from error
        raise


def _is_quota_transaction_failure(error: Exception) -> bool:
    response = getattr(error, "response", {})
    error_code = response.get("Error", {}).get("Code")
    if error_code == "ConditionalCheckFailedException":
        return True
    if error_code != "TransactionCanceledException":
        return False
    if any(
        reason.get("Code") == "ConditionalCheckFailed"
        for reason in response.get("CancellationReasons", [])
        if isinstance(reason, dict)
    ):
        return True
    return "ConditionalCheckFailed" in str(response.get("Error", {}).get("Message", ""))


def _quota_identifier_digest(secret: str, identifier_type: str, value: str) -> str:
    message = f"checkpoint-quota-v1:{identifier_type}:{value}".encode()
    return hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()


def _source_ip(event: dict[str, Any]) -> str:
    return (
        event.get("requestContext", {}).get("http", {}).get("sourceIp")
        or event.get("requestContext", {}).get("identity", {}).get("sourceIp")
        or ""
    )


def _rate_limit_component(value: Any, fallback: str) -> str:
    cleaned = _clean_text(value)
    if not cleaned:
        return fallback
    return re.sub(r"[^A-Za-z0-9_.:-]", "-", cleaned)[:96]


def _dynamodb_client() -> Any:
    import boto3
    from botocore.config import Config

    region = os.getenv("AWS_REGION") or os.getenv("BEDROCK_REGION")
    return boto3.client(
        "dynamodb",
        region_name=region,
        config=Config(
            connect_timeout=2,
            read_timeout=5,
            retries={"total_max_attempts": 2, "mode": "standard"},
        ),
    )


def _service_retry_after_seconds() -> int:
    return _int_env(
        "SERVICE_RETRY_AFTER_SECONDS",
        DEFAULT_SERVICE_RETRY_AFTER_SECONDS,
        maximum=86_400,
    )


def _provider_retry_after_seconds() -> int:
    return _int_env("PROVIDER_RETRY_AFTER_SECONDS", 30, maximum=3_600)


def _rate_limit_retry_after_seconds() -> int:
    return _int_env("RATE_LIMIT_RETRY_AFTER_SECONDS", 3_600, maximum=86_400)


def _new_request_metrics(context: Any | None) -> dict[str, Any]:
    return {
        "RequestId": str(getattr(context, "aws_request_id", "unavailable")),
        "ProviderCalls": 0,
        "BedrockInputTokens": 0,
        "BedrockOutputTokens": 0,
        "QuestionsRequested": 0,
        "QuestionsReturned": 0,
    }


def _emit_request_metrics(metrics: dict[str, Any]) -> None:
    emit_by_default = bool(os.getenv("AWS_LAMBDA_FUNCTION_NAME"))
    if not _bool_env("EMIT_STRUCTURED_METRICS", emit_by_default):
        return

    status_code = _nonnegative_int(metrics.get("StatusCode"))
    outcome = str(metrics.get("Outcome", "unknown"))
    metric_values = {
        "Requests": 1,
        "Errors": int(status_code >= 500),
        "ProviderFailures": int(outcome == "provider_failure"),
        "SafetyInterventions": int(outcome == "safety_intervention"),
        "RateLimitedRequests": int(outcome == "rate_limited"),
        "ServiceUnavailableRequests": int(
            outcome.startswith("service_") or outcome == "configuration_error"
        ),
        "ProviderCalls": _nonnegative_int(metrics.get("ProviderCalls")),
        "BedrockInputTokens": _nonnegative_int(metrics.get("BedrockInputTokens")),
        "BedrockOutputTokens": _nonnegative_int(metrics.get("BedrockOutputTokens")),
        "QuestionsRequested": _nonnegative_int(metrics.get("QuestionsRequested")),
        "QuestionsReturned": _nonnegative_int(metrics.get("QuestionsReturned")),
        "LatencyMilliseconds": max(0.0, float(metrics.get("LatencyMilliseconds", 0.0))),
    }
    metric_definitions = [
        {
            "Name": name,
            "Unit": "Milliseconds" if name == "LatencyMilliseconds" else "Count",
        }
        for name in metric_values
    ]
    payload = {
        "_aws": {
            "Timestamp": int(time.time() * 1_000),
            "CloudWatchMetrics": [
                {
                    "Namespace": METRIC_NAMESPACE,
                    "Dimensions": [["Service"]],
                    "Metrics": metric_definitions,
                }
            ],
        },
        "Service": METRIC_SERVICE,
        "Outcome": outcome,
        "StatusCode": status_code,
        "RequestId": str(metrics.get("RequestId", "unavailable")),
        **metric_values,
    }
    try:
        # Raw JSON on stdout is the Lambda-supported Embedded Metric Format transport.
        print(json.dumps(payload, separators=(",", ":"), sort_keys=True))
    except Exception:
        LOGGER.exception("Failed to emit request metrics")


def _response(
    status_code: int,
    body: Any,
    headers: dict[str, str] | None = None,
) -> dict[str, Any]:
    if body == "":
        serialized_body = ""
    else:
        serialized_body = json.dumps(body, separators=(",", ":"))

    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
            **(headers or {}),
        },
        "body": serialized_body,
    }


def _error(
    status_code: int,
    message: str,
    code: str | None = None,
    headers: dict[str, str] | None = None,
) -> dict[str, Any]:
    body = {"error": message}
    if code:
        body["code"] = code
    return _response(status_code, body, headers=headers)
