import base64
import json
import logging
import os
import re
import time
from datetime import datetime, timezone
from typing import Any


LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(os.getenv("LOG_LEVEL", "INFO"))

DEFAULT_MODEL_ID = "google.gemma-3-4b-it"
DEFAULT_FALLBACK_MODEL_ID = "amazon.nova-micro-v1:0"
DEFAULT_MAX_QUESTIONS = 20
DEFAULT_MAX_TOKENS = 6000
DEFAULT_TEMPERATURE = 0.35

CORS_HEADERS = {
    "Access-Control-Allow-Origin": os.getenv("CORS_ALLOW_ORIGIN", "*"),
    "Access-Control-Allow-Headers": "authorization,content-type,x-checkpoint-install-id",
    "Access-Control-Allow-Methods": "OPTIONS,POST",
}


class BadRequestError(ValueError):
    pass


class ProviderError(RuntimeError):
    pass


class RateLimitExceededError(RuntimeError):
    pass


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    return handle_http_request(event)


def handle_http_request(
    event: dict[str, Any],
    bedrock_client: Any | None = None,
    dynamodb_client: Any | None = None,
) -> dict[str, Any]:
    method = _http_method(event)
    if method == "OPTIONS":
        return _response(204, "")

    if method != "POST":
        return _error(405, "Method not allowed")

    if not _is_authorized(event):
        return _error(401, "Unauthorized")

    try:
        _check_rate_limits(event, dynamodb_client)
        payload = _decode_body(event)
        normalized = _normalize_request(payload)
        provider_payload = _generate_provider_payload(normalized, bedrock_client)
        questions = _sanitize_questions(provider_payload.get("questions", []), normalized)

        if not questions:
            raise ProviderError("Provider returned no usable questions.")

        return _response(200, {"questions": questions})
    except BadRequestError as error:
        return _error(400, str(error))
    except RateLimitExceededError:
        return _error(429, "Daily AI generation limit reached. Try again later.")
    except Exception:
        LOGGER.exception("Question generation failed")
        return _error(502, "Question generation failed")


def _http_method(event: dict[str, Any]) -> str:
    return (
        event.get("requestContext", {}).get("http", {}).get("method")
        or event.get("httpMethod")
        or "POST"
    ).upper()


def _is_authorized(event: dict[str, Any]) -> bool:
    expected_token = os.getenv("CHECKPOINT_BACKEND_TOKEN", "").strip()
    if not expected_token:
        return True

    headers = {str(key).lower(): value for key, value in (event.get("headers") or {}).items()}
    auth_header = str(headers.get("authorization", "")).strip()
    return auth_header == f"Bearer {expected_token}"


def _check_rate_limits(event: dict[str, Any], dynamodb_client: Any | None) -> None:
    table_name = os.getenv("RATE_LIMIT_TABLE_NAME", "").strip()
    if not table_name:
        return

    client = dynamodb_client or _dynamodb_client()
    headers = {str(key).lower(): value for key, value in (event.get("headers") or {}).items()}
    install_id = _rate_limit_component(headers.get("x-checkpoint-install-id"), fallback="missing-install")
    source_ip = _rate_limit_component(_source_ip(event), fallback="missing-ip")
    day = datetime.now(timezone.utc).strftime("%Y%m%d")
    expires_at = int(time.time()) + _int_env(
        "RATE_LIMIT_TTL_SECONDS",
        60 * 60 * 48,
        maximum=60 * 60 * 24 * 14,
    )

    limits = [
        (f"install#{install_id}#{day}", _int_env("MAX_REQUESTS_PER_INSTALL_PER_DAY", 40)),
        (f"ip#{source_ip}#{day}", _int_env("MAX_REQUESTS_PER_IP_PER_DAY", 400)),
    ]

    for key, limit in limits:
        _increment_rate_limit(client, table_name, key, limit, expires_at)


def _increment_rate_limit(
    client: Any,
    table_name: str,
    key: str,
    limit: int,
    expires_at: int,
) -> None:
    try:
        client.update_item(
            TableName=table_name,
            Key={"rateKey": {"S": key}},
            UpdateExpression="SET expiresAt = :expiresAt ADD #count :one",
            ConditionExpression="attribute_not_exists(#count) OR #count < :limit",
            ExpressionAttributeNames={"#count": "count"},
            ExpressionAttributeValues={
                ":one": {"N": "1"},
                ":limit": {"N": str(limit)},
                ":expiresAt": {"N": str(expires_at)},
            },
        )
    except Exception as error:
        if _is_conditional_check_failure(error):
            raise RateLimitExceededError from error
        raise


def _is_conditional_check_failure(error: Exception) -> bool:
    return (
        getattr(error, "response", {})
        .get("Error", {})
        .get("Code") == "ConditionalCheckFailedException"
    )


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


def _decode_body(event: dict[str, Any]) -> dict[str, Any]:
    body = event.get("body")
    if body is None:
        raise BadRequestError("Missing JSON body.")

    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")

    try:
        payload = json.loads(body)
    except json.JSONDecodeError as error:
        raise BadRequestError("Body must be valid JSON.") from error

    if not isinstance(payload, dict):
        raise BadRequestError("Body must be a JSON object.")

    return payload


def _normalize_request(payload: dict[str, Any]) -> dict[str, Any]:
    goal = payload.get("goal")
    if not isinstance(goal, dict):
        raise BadRequestError("Missing goal object.")

    target_count = _clamped_int(payload.get("targetCount"), minimum=1, maximum=_max_questions())
    minimum_difficulty = _clamped_int(payload.get("minimumDifficulty"), minimum=1, maximum=5)

    learning_target = _clean_text(goal.get("learningTarget")) or _clean_text(goal.get("title"))
    if not learning_target:
        raise BadRequestError("Missing goal learningTarget.")

    content_topics = goal.get("contentTopics") or []
    if not isinstance(content_topics, list):
        content_topics = []

    normalized_topics = [_clean_text(topic) for topic in content_topics]
    normalized_topics = [topic for topic in normalized_topics if topic]

    return {
        "goal": {
            "title": _clean_text(goal.get("title")),
            "category": _clean_text(goal.get("category")),
            "focusAreas": _clean_text(goal.get("focusAreas")),
            "learningTarget": learning_target,
            "contentTopics": normalized_topics or [learning_target],
            "questionDirective": _clean_text(goal.get("questionDirective")),
            "needsSkillMap": bool(goal.get("needsSkillMap")),
            "preferredQuestionStyle": "Multiple Choice",
        },
        "competencies": _list_of_dicts(payload.get("competencies")),
        "existingPrompts": _list_of_strings(payload.get("existingPrompts")),
        "reportedPrompts": _list_of_strings(payload.get("reportedPrompts")),
        "targetCount": target_count,
        "minimumDifficulty": minimum_difficulty,
        "difficultyGuidance": _clean_text(payload.get("difficultyGuidance"))
        or _difficulty_guidance(minimum_difficulty),
    }


def _difficulty_guidance(level: int) -> str:
    if level <= 1:
        return "Foundations: direct recognition, definitions, single-step facts, and gentle distractors."
    if level == 2:
        return "Easy application: one concept in a familiar context with light reasoning and clear distractors."
    if level == 3:
        return "Medium application: apply concepts to a short scenario with qualifiers and plausible distractors."
    if level == 4:
        return "Hard reasoning: use multi-step logic, edge cases, constraints, counterexamples, or nuanced distractors."
    return "Expert synthesis: combine multiple concepts in a dense exam-style scenario with subtle traps."


def _generate_provider_payload(request: dict[str, Any], bedrock_client: Any | None) -> dict[str, Any]:
    errors: list[ProviderError] = []
    for model_id in _model_attempts():
        raw_text = _generate_with_bedrock(
            normalized_request=request,
            bedrock_client=bedrock_client,
            model_id=model_id,
        )
        try:
            return _extract_json_object(raw_text)
        except ProviderError as first_error:
            errors.append(first_error)

        retry_text = _generate_with_bedrock(
            normalized_request=request,
            bedrock_client=bedrock_client,
            model_id=model_id,
            user_prompt=_json_retry_prompt(request, raw_text),
        )
        try:
            return _extract_json_object(retry_text)
        except ProviderError as second_error:
            errors.append(second_error)

    raise errors[-1] if errors else ProviderError("Provider response was not valid JSON.")


def _generate_with_bedrock(
    normalized_request: dict[str, Any],
    bedrock_client: Any | None,
    model_id: str,
    user_prompt: str | None = None,
) -> str:
    client = bedrock_client or _bedrock_client()

    response = client.converse(
        modelId=model_id,
        system=[{"text": _system_prompt()}],
        messages=[
            {
                "role": "user",
                "content": [{"text": user_prompt or _user_prompt(normalized_request)}],
            }
        ],
        inferenceConfig={
            "maxTokens": _int_env("BEDROCK_MAX_TOKENS", DEFAULT_MAX_TOKENS),
            "temperature": _float_env("BEDROCK_TEMPERATURE", DEFAULT_TEMPERATURE),
        },
    )

    text_parts = []
    for block in response.get("output", {}).get("message", {}).get("content", []):
        text = block.get("text")
        if isinstance(text, str):
            text_parts.append(text)

    text = "\n".join(text_parts).strip()
    if not text:
        raise ProviderError("Bedrock returned an empty response.")

    return text


def _model_attempts() -> list[str]:
    primary = os.getenv("BEDROCK_MODEL_ID", DEFAULT_MODEL_ID).strip() or DEFAULT_MODEL_ID
    fallback = os.getenv("BEDROCK_FALLBACK_MODEL_ID", DEFAULT_FALLBACK_MODEL_ID).strip()
    models = [primary]
    if fallback and fallback not in models:
        models.append(fallback)
    return models


def _bedrock_client() -> Any:
    import boto3

    region = os.getenv("BEDROCK_REGION") or os.getenv("AWS_REGION")
    return boto3.client("bedrock-runtime", region_name=region)


def _dynamodb_client() -> Any:
    import boto3

    region = os.getenv("AWS_REGION") or os.getenv("BEDROCK_REGION")
    return boto3.client("dynamodb", region_name=region)


def _system_prompt() -> str:
    return """
You generate multiple-choice checkpoint questions for an academic screen-time blocker.
Return only valid JSON with this exact shape:
{"questions":[{"prompt":"...","expectedAnswer":"...","choices":["...","...","...","..."],"explanation":"...","topic":"...","difficulty":3,"format":"Multiple Choice"}]}

Rules:
- Generate original knowledge-check questions about the learning target itself.
- Treat words like study, prepare, pass, learn, and ace as user intent, not as the tested subject.
- Do not ask about study plans, productivity, motivation, app blocking, screen time, or next steps unless the learning target is explicitly study skills.
- Each question must have exactly 4 choices.
- expectedAnswer must exactly match one choice.
- difficulty must be an integer from 1 to 5 and not below the requested minimum.
- Match the requested difficulty guidance; do not relabel an easy question as hard.
- Keep questions answerable in 30 seconds to 3 minutes.
- Avoid duplicate prompts and avoid prompts the user reported.
- Prefer practical exam-style or skill-check questions over definitions when the minimum difficulty is 3 or higher.
- If the request needs a skill map, infer 4 to 6 subject-matter skills from the learning target and use those exact skill names as question topics.
""".strip()


def _user_prompt(request: dict[str, Any]) -> str:
    compact_request = json.dumps(request, separators=(",", ":"), ensure_ascii=False)
    return f"""
Here is the user's generation request JSON:
{compact_request}

Generate {request["targetCount"]} level {request["minimumDifficulty"]} of 5 difficulty multiple-choice questions.
Difficulty guidance: {request["difficultyGuidance"]}
Make the questions meaningfully match that level; do not merely set the difficulty number.
The actual learning target to test is: {request["goal"]["learningTarget"]}
Content topics: {", ".join(request["goal"]["contentTopics"])}
Question style guidance: {request["goal"]["questionDirective"] or "Ask objective knowledge-check questions."}
Skill map mode: {"infer a new 4-to-6 topic skill map and use those skill names as question topics" if request["goal"]["needsSkillMap"] else "use the provided content topics as the skill map"}

Return only the JSON object. Do not wrap it in Markdown.
""".strip()


def _json_retry_prompt(request: dict[str, Any], malformed_text: str) -> str:
    compact_request = json.dumps(request, separators=(",", ":"), ensure_ascii=False)
    excerpt = _clip(malformed_text, 1200)
    return f"""
Your previous response was not valid JSON for this request:
{compact_request}

Previous malformed response excerpt:
{excerpt}

Generate {request["targetCount"]} multiple-choice questions now.
Difficulty guidance: {request["difficultyGuidance"]}
Return only one compact JSON object with this exact shape:
{{"questions":[{{"prompt":"...","expectedAnswer":"...","choices":["...","...","...","..."],"explanation":"...","topic":"...","difficulty":{request["minimumDifficulty"]},"format":"Multiple Choice"}}]}}

No prose, headings, Markdown, comments, or numbering outside the JSON object.
""".strip()


def _extract_json_object(text: str) -> dict[str, Any]:
    trimmed = text.strip()
    if trimmed.startswith("```"):
        trimmed = re.sub(r"^```(?:json)?\s*", "", trimmed)
        trimmed = re.sub(r"\s*```$", "", trimmed)

    candidates = [trimmed]
    start = trimmed.find("{")
    end = trimmed.rfind("}")
    if start != -1 and end != -1 and end > start:
        candidates.append(trimmed[start : end + 1])

    for candidate in candidates:
        parsed = _parse_provider_json(candidate)
        if parsed is not None:
            return parsed

    array_start = trimmed.find("[")
    array_end = trimmed.rfind("]")
    if array_start != -1 and array_end != -1 and array_end > array_start:
        parsed = _parse_provider_json(trimmed[array_start : array_end + 1])
        if parsed is not None:
            return parsed

    raise ProviderError("Provider response was not valid JSON.")


def _parse_provider_json(candidate: str) -> dict[str, Any] | None:
    try:
        parsed = json.loads(candidate)
    except json.JSONDecodeError:
        return None

    if isinstance(parsed, dict):
        return parsed

    if isinstance(parsed, list):
        return {"questions": parsed}

    return None


def _sanitize_questions(raw_questions: Any, request: dict[str, Any]) -> list[dict[str, Any]]:
    if not isinstance(raw_questions, list):
        return []

    minimum_difficulty = request["minimumDifficulty"]
    blocked_prompts = {
        _canonical(prompt)
        for prompt in request["existingPrompts"] + request["reportedPrompts"]
    }
    seen_prompts = set(blocked_prompts)
    sanitized: list[dict[str, Any]] = []

    for raw_question in raw_questions:
        if not isinstance(raw_question, dict):
            continue

        prompt = _clip(_clean_text(raw_question.get("prompt")), 360)
        expected_answer = _clip(_clean_text(raw_question.get("expectedAnswer")), 280)
        explanation = _clip(_clean_text(raw_question.get("explanation")), 420)
        topic = _clip(_clean_text(raw_question.get("topic")), 48)
        if not topic:
            topic = request["goal"]["contentTopics"][0]

        prompt_key = _canonical(prompt)
        if (
            len(prompt) < 12
            or not expected_answer
            or not explanation
            or prompt_key in seen_prompts
            or _looks_like_study_strategy(prompt, request["goal"]["learningTarget"])
        ):
            continue

        choices = _normalized_choices(raw_question.get("choices"), expected_answer)
        if len(choices) != 4:
            continue

        difficulty = _clamped_int(raw_question.get("difficulty"), minimum=1, maximum=5)
        if difficulty < minimum_difficulty:
            continue

        seen_prompts.add(prompt_key)
        sanitized.append(
            {
                "prompt": prompt,
                "expectedAnswer": expected_answer,
                "choices": choices,
                "explanation": explanation,
                "topic": topic,
                "difficulty": difficulty,
                "format": "Multiple Choice",
            }
        )

        if len(sanitized) >= request["targetCount"]:
            break

    return sanitized


def _normalized_choices(raw_choices: Any, expected_answer: str) -> list[str]:
    if not isinstance(raw_choices, list):
        raw_choices = []

    choices = [_clip(_clean_text(choice), 140) for choice in raw_choices]
    choices = [choice for choice in choices if choice]

    unique_choices: list[str] = []
    seen = set()
    for choice in [expected_answer] + choices:
        key = _canonical(choice)
        if key and key not in seen:
            seen.add(key)
            unique_choices.append(choice)

    if len(unique_choices) < 4:
        return []

    expected_key = _canonical(expected_answer)
    distractors = [choice for choice in unique_choices if _canonical(choice) != expected_key]
    return [expected_answer] + distractors[:3]


def _looks_like_study_strategy(prompt: str, learning_target: str) -> bool:
    target = learning_target.lower()
    if "study skill" in target or "productivity" in target or "time management" in target:
        return False

    normalized = _canonical(prompt)
    blocked_phrases = [
        "how should you study",
        "study plan",
        "study schedule",
        "study strategy",
        "practice schedule",
        "next step",
        "visible progress",
        "motivation",
        "blocked app",
        "screen time",
        "open another app",
    ]
    return any(phrase.replace(" ", "") in normalized for phrase in blocked_phrases)


def _list_of_dicts(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, dict)][:20]


def _list_of_strings(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [_clean_text(item) for item in value if _clean_text(item)][:30]


def _clean_text(value: Any) -> str:
    if value is None:
        return ""
    return " ".join(str(value).split()).strip()


def _canonical(value: str) -> str:
    return "".join(character.lower() for character in value if character.isalnum())


def _clip(value: str, limit: int) -> str:
    return value[:limit].strip()


def _clamped_int(value: Any, minimum: int, maximum: int) -> int:
    try:
        integer = int(value)
    except (TypeError, ValueError):
        integer = minimum
    return max(minimum, min(maximum, integer))


def _max_questions() -> int:
    raw_value = os.getenv("MAX_QUESTIONS_PER_BATCH")
    if not raw_value:
        return DEFAULT_MAX_QUESTIONS
    return _clamped_int(raw_value, minimum=1, maximum=40)


def _int_env(key: str, default: int, maximum: int = 20000) -> int:
    return _clamped_int(os.getenv(key), minimum=1, maximum=maximum) if os.getenv(key) else default


def _float_env(key: str, default: float) -> float:
    try:
        return float(os.getenv(key, ""))
    except ValueError:
        return default


def _response(status_code: int, body: Any) -> dict[str, Any]:
    if body == "":
        serialized_body = ""
    else:
        serialized_body = json.dumps(body, separators=(",", ":"))

    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            **CORS_HEADERS,
        },
        "body": serialized_body,
    }


def _error(status_code: int, message: str) -> dict[str, Any]:
    return _response(status_code, {"error": message})
