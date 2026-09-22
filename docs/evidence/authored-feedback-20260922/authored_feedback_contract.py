"""Inactive authored-feedback transport prototype; no semantic approval or I/O.

The author writes all five learner-facing explanations. This module checks
shape, exact associations and text bounds, and copies content without rewriting
it. It does not solve questions, audit meaning, assign policy, or call providers.
"""

import copy
import hashlib
import json
import math
from typing import Any


CONTRACT_NAME = "experimental_authored_feedback_author_v1"
SLOTS = ("a", "b", "c", "d")
MAX_COUNT = 40
LEARNER_FIELDS = (
    "prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations",
)
OPTIONAL_METADATA = ("skillID", "objectiveID", "objective")


class AuthoredFeedbackFormatError(ValueError):
    """The proposed immutable authored response violates its local contract."""


def _object(properties: dict[str, Any], required: list[str] | None = None) -> dict[str, Any]:
    return {
        "type": "object",
        "properties": properties,
        "required": list(properties) if required is None else required,
        "additionalProperties": False,
    }


def author_schema(count: int) -> dict[str, Any]:
    """Fresh schema object in deliberate generation order; no shared mutation."""
    count = _checked_count(count)
    string = {"type": "string"}
    row = _object({
        "prompt": copy.deepcopy(string),
        "choices": _object({slot: copy.deepcopy(string) for slot in SLOTS}),
        "explanation": copy.deepcopy(string),
        "choiceFeedback": _object({slot: copy.deepcopy(string) for slot in SLOTS}),
        "correctChoice": {"type": "string", "enum": list(SLOTS)},
        "topic": copy.deepcopy(string),
        "difficulty": {"type": "integer"},
        "format": {"type": "string", "enum": ["Multiple Choice"]},
        **{key: copy.deepcopy(string) for key in OPTIONAL_METADATA},
    }, ["prompt", "choices", "explanation", "choiceFeedback", "correctChoice",
        "topic", "difficulty", "format"])
    return _object({"questions": _object({str(index): copy.deepcopy(row)
                                          for index in range(count)})})


def output_config(count: int) -> dict[str, Any]:
    """Candidate native configuration, never dispatched by this module.

    Local validation supplies length bounds and exact duplicate checks. Both
    native and local schemas require the trusted count's exact string identities,
    closed fields/slots and key-slot enum. Neither is a
    claim of Bedrock acceptance or factual correctness without qualification.
    """
    encoded = json.dumps(author_schema(count), ensure_ascii=True, separators=(",", ":"))
    return {"textFormat": {"type": "json_schema", "structure": {"jsonSchema": {
        "name": f"{CONTRACT_NAME}_n{count}", "schema": encoded,
    }}}}


def metadata(count: int) -> dict[str, str]:
    declaration = output_config(count)["textFormat"]["structure"]["jsonSchema"]
    encoded = declaration["schema"]
    return {"name": declaration["name"], "version": "1",
            "sha256": hashlib.sha256(encoded.encode("utf-8")).hexdigest()}


def _checked_count(count: Any) -> int:
    if type(count) is not int or not 1 <= count <= MAX_COUNT:
        raise AuthoredFeedbackFormatError("Expected count must be an integer from 1 through 40.")
    return count


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise AuthoredFeedbackFormatError("Duplicate JSON property.")
        result[key] = value
    return result


def _reject_constant(_value: str) -> None:
    raise AuthoredFeedbackFormatError("Nonstandard JSON constant.")


def _finite_float(text: str) -> float:
    value = float(text)
    if not math.isfinite(value):
        raise AuthoredFeedbackFormatError("Nonfinite JSON number.")
    return value


def _schema_validate(value: Any, schema: dict[str, Any]) -> None:
    """Strict types for this owned schema subset, including int != bool."""
    kind = schema["type"]
    expected = {"object": dict, "array": list, "string": str, "integer": int}[kind]
    if type(value) is not expected or "enum" in schema and value not in schema["enum"]:
        raise AuthoredFeedbackFormatError("Wrong native field type or enum.")
    if kind == "object":
        properties = schema["properties"]
        if not set(schema["required"]) <= set(value) or set(value) - set(properties):
            raise AuthoredFeedbackFormatError("Missing or unexpected native field.")
        for key, child in value.items():
            _schema_validate(child, properties[key])
    elif kind == "array":
        for child in value:
            _schema_validate(child, schema["items"])


def _bounded_text(value: Any, minimum: int, maximum: int, field: str) -> None:
    # Only inspect stripped length; preserve original whitespace and all bytes.
    if (type(value) is not str or len(value.strip()) < minimum
            or len(value) > maximum):
        raise AuthoredFeedbackFormatError(f"{field} must contain {minimum}..{maximum} characters.")
    _utf8_text(value, field)


def _utf8_text(value: str, field: str) -> None:
    try:
        value.encode("utf-8")
    except UnicodeEncodeError as error:
        raise AuthoredFeedbackFormatError(f"{field} must be valid UTF-8 text.") from error


def _exact_choices(choices: Any) -> list[str]:
    if type(choices) is not list or len(choices) != 4:
        raise AuthoredFeedbackFormatError("Exactly four choices are required.")
    for choice in choices:
        _bounded_text(choice, 1, 140, "Choice")
    if len(set(choices)) != 4:
        raise AuthoredFeedbackFormatError("Duplicate exact choice text cannot be mapped to feedback.")
    return choices


def freeze_learner_payload(payload: Any) -> dict[str, Any]:
    """Require the complete five-field response and return an exact deep copy.

    A valid return is structurally well formed, not verified educational content.
    No normalization, semantic equivalence inference, or policy assignment occurs.
    """
    if type(payload) is not dict or set(payload) != set(LEARNER_FIELDS):
        raise AuthoredFeedbackFormatError("Exact learner fields are required.")
    _bounded_text(payload["prompt"], 12, 320, "Prompt")
    _bounded_text(payload["explanation"], 12, 420, "Main explanation")
    choices = _exact_choices(payload["choices"])
    answer = payload["expectedAnswer"]
    if type(answer) is not str or answer not in choices:
        raise AuthoredFeedbackFormatError("Expected answer must exactly match one offered choice.")
    feedback = payload["choiceExplanations"]
    if type(feedback) is not dict or set(feedback) != set(choices):
        raise AuthoredFeedbackFormatError("Feedback must exactly cover all four offered choices.")
    for explanation in feedback.values():
        _bounded_text(explanation, 12, 280, "Choice explanation")
    return copy.deepcopy(payload)


def learner_content_digest(payload: Any) -> str:
    """Digest only a validated full learner payload; never normalize its text."""
    frozen = freeze_learner_payload(payload)
    encoded = json.dumps(frozen, sort_keys=True, ensure_ascii=False,
                         allow_nan=False, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def adapt_author_response(raw: Any, *, expected_count: int) -> dict[str, Any]:
    """Resolve explicit transport slots to exact text only after full validation.

    All rows must be valid; partial results are never returned after an invalid
    sibling. This pure prototype uses an exact trusted count rather than silently
    truncating, filling or renumbering the author's batch.
    """
    count = _checked_count(expected_count)
    if type(raw) is not str:
        raise AuthoredFeedbackFormatError("Author response must be JSON text.")
    try:
        parsed = json.loads(raw, object_pairs_hook=_unique_object,
                            parse_constant=_reject_constant, parse_float=_finite_float)
    except ValueError as error:
        raise AuthoredFeedbackFormatError("Malformed author JSON.") from error
    _schema_validate(parsed, author_schema(count))
    adapted = []
    for index in range(count):
        question = parsed["questions"][str(index)]
        # The exact-duplicate check precedes the feedback dictionary, so two
        # different slot explanations can never silently overwrite one another.
        choices = _exact_choices([question["choices"][slot] for slot in SLOTS])
        feedback = {question["choices"][slot]: question["choiceFeedback"][slot]
                    for slot in SLOTS}
        learner = freeze_learner_payload({
            "prompt": question["prompt"],
            "choices": choices,
            "expectedAnswer": question["choices"][question["correctChoice"]],
            "explanation": question["explanation"],
            "choiceExplanations": feedback,
        })
        if not 1 <= question["difficulty"] <= 5:
            raise AuthoredFeedbackFormatError("Difficulty must be an integer from 1 through 5.")
        # Metadata remains data. Its adaptation never mints approval or supplies
        # missing tags. Production scope/allocation validation is still required.
        metadata_fields = {key: value for key, value in question.items()
                           if key in ("topic", "difficulty", "format", *OPTIONAL_METADATA)}
        for key, value in metadata_fields.items():
            if key != "difficulty":
                _utf8_text(value, key)
        adapted.append({**learner, **copy.deepcopy(metadata_fields)})
    return {"questions": adapted}
