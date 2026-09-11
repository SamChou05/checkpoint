"""Versioned Bedrock structured-output contracts for production model stages.

Schemas describe transport shape only.  Correlation, counts, semantic quality,
and answer agreement remain the responsibility of the existing stage validators.
"""

import copy
import hashlib
import json
import os
from typing import Any, Literal

from service_errors import ProviderError, ServiceConfigurationError


Contract = Literal[
    "question_author_v1",
    "skill_map_inference_v1",
    "skill_map_evolution_v1",
    "complete_choice_solver_v1",
    "default_reviewer_v1",
    "authored_solution_reviewer_v1",
]

_STRING = {"type": "string"}
_INTEGER = {"type": "integer"}
_BOOLEAN = {"type": "boolean"}


def _object(properties: dict[str, Any], required: list[str] | None = None) -> dict[str, Any]:
    return {
        "type": "object",
        "properties": properties,
        "required": required if required is not None else list(properties),
        "additionalProperties": False,
    }


_SCHEMAS: dict[Contract, dict[str, Any]] = {
    "question_author_v1": _object({
        "questions": {"type": "array", "items": _object({
            "prompt": _STRING, "choices": {"type": "array", "items": _STRING},
            "expectedAnswer": _STRING, "explanation": _STRING, "topic": _STRING,
            "difficulty": _INTEGER, "format": {"type": "string", "enum": ["Multiple Choice"]},
            "skillID": _STRING, "objectiveID": _STRING, "objective": _STRING,
        }, ["prompt", "choices", "expectedAnswer", "explanation", "topic", "difficulty", "format"])}
    }),
    "skill_map_inference_v1": _object({
        "skills": {"type": "array", "items": _object({
            "name": _STRING,
            "objectives": {"type": "array", "items": _object({"name": _STRING})},
        })}
    }),
    "skill_map_evolution_v1": _object({
        "changes": {"type": "array", "items": _object({
            "action": {"type": "string", "enum": ["advance"]},
            "predecessorSkillID": _STRING,
            "successor": _object({
                "name": _STRING,
                "objectives": {"type": "array", "items": _object({"name": _STRING})},
            }),
        })}
    }),
    "complete_choice_solver_v1": _object({
        "solutions": {"type": "array", "items": _object({
            "index": _INTEGER,
            "choices": {"type": "array", "items": _object({
                "choice": _STRING,
                "judgment": {"type": "string", "enum": ["supported", "refuted", "uncertain"]},
                "reason": _STRING,
            })},
        })}
    }),
    # A uniform negative representation avoids a provider-hostile nullable enum:
    # rejected reviews use answer:"" and choiceFeedback:[]. Application checks
    # prevent that representation from being accepted as learner content.
    "default_reviewer_v1": _object({
        "reviews": {"type": "array", "items": _object({
            "index": _INTEGER, "valid": _BOOLEAN, "answer": _STRING,
            "difficulty": _INTEGER, "explanation": _STRING,
            "choiceFeedback": {"type": "array", "items": _object({
                "choice": _STRING, "explanation": _STRING,
            })},
        })}
    }),
    "authored_solution_reviewer_v1": _object({
        "reviews": {"type": "array", "items": _object({
            "index": _INTEGER, "valid": _BOOLEAN, "answer": _STRING,
            "difficulty": _INTEGER,
            "explanationSupport": {"type": "string", "enum": ["supported", "unsupported", "uncertain"]},
            "issues": {"type": "array", "items": _STRING},
        })}
    }),
}


def output_mode() -> str:
    mode = os.getenv("BEDROCK_STRUCTURED_OUTPUT_MODE", "legacy").strip().lower()
    if mode not in {"legacy", "native"}:
        raise ServiceConfigurationError(
            "BEDROCK_STRUCTURED_OUTPUT_MODE must be legacy or native."
        )
    return mode


def native_output_config(contract: Contract) -> dict[str, Any]:
    """Return an independent wrapper with stable schema serialization."""
    schema = json.dumps(_SCHEMAS[contract], sort_keys=True, separators=(",", ":"))
    if contract in {"question_author_v1", "complete_choice_solver_v1"}:
        ordered = json.loads(schema)
        if contract == "complete_choice_solver_v1":
            row = ordered["properties"]["solutions"]["items"]["properties"]["choices"]["items"]
            fields = ("choice", "reason", "judgment")
        else:
            row = ordered["properties"]["questions"]["items"]
            # Native output places required properties before optional ones.
            # Within each group, match the author prompt's finished-item example.
            fields = ("prompt", "explanation", "expectedAnswer", "choices", "topic",
                      "difficulty", "format", "skillID", "objectiveID", "objective")
        # Match the prompts' explanation-before-answer examples at the provider
        # boundary. Preserve every other serialized key order and required list;
        # sorting again would erase this intervention without changing validity.
        row["properties"] = {key: row["properties"][key] for key in fields}
        schema = json.dumps(ordered, separators=(",", ":"))
    return {"textFormat": {"type": "json_schema", "structure": {"jsonSchema": {
        "name": contract, "schema": schema,
    }}}}


def contract_metadata(contract: Contract) -> dict[str, str]:
    config = native_output_config(contract)
    schema = config["textFormat"]["structure"]["jsonSchema"]["schema"]
    return {"name": contract, "version": "1", "sha256": hashlib.sha256(schema.encode()).hexdigest()}


def ensure_supported_model(model_id: str) -> None:
    normalized = model_id.lower()
    if not any(value in normalized for value in ("moonshotai.kimi-k2.5", "anthropic.claude-sonnet-4-6")):
        raise ServiceConfigurationError(
            "Configured model is outside the native structured-output support allowlist."
        )


def native_prompt(system_prompt: str, contract: Contract) -> str:
    if contract == "default_reviewer_v1":
        return system_prompt + """

NATIVE TRANSPORT OVERRIDE: Return the schema's choiceFeedback array, not
choiceExplanations. For an accepted review return exactly one row for every
offered choice, preserving exact choice bytes. For a rejected review use
answer:"", explanation:"", and choiceFeedback:[]. Every review, including a
rejection, must include index, valid, answer, difficulty, explanation, and
choiceFeedback. Use difficulty:0 if rejecting without a difficulty assessment.
This replaces the earlier output example and minimal negative response shape.
Do not add fields.
"""
    return system_prompt + f"\n\nNATIVE TRANSPORT: Return only the JSON shape constrained by {contract}."


def adapt_native_response(raw: str, contract: Contract) -> str:
    """Validate native JSON before any provider-only shape is adapted."""
    try:
        payload = json.loads(raw, object_pairs_hook=_reject_duplicate_pairs, parse_constant=_reject_constant)
    except (TypeError, ValueError) as error:
        raise ProviderError("Native stage returned malformed JSON.") from error
    try:
        _validate_schema_value(payload, _SCHEMAS[contract])
    except ValueError as error:
        raise ProviderError("Native stage response violates its contract.") from error
    if contract != "default_reviewer_v1":
        return raw
    if type(payload) is not dict or set(payload) != {"reviews"} or type(payload["reviews"]) is not list:
        raise ProviderError("Native reviewer returned an invalid envelope.")
    adapted = copy.deepcopy(payload)
    for review in adapted["reviews"]:
        expected = {"index", "valid", "answer", "difficulty", "explanation", "choiceFeedback"}
        if type(review) is not dict or set(review) != expected or type(review["valid"]) is not bool:
            raise ProviderError("Native reviewer returned unknown or missing fields.")
        rows = review.pop("choiceFeedback")
        if type(rows) is not list:
            raise ProviderError("Native reviewer feedback must be an array.")
        feedback: dict[str, str] = {}
        for row in rows:
            if type(row) is not dict or set(row) != {"choice", "explanation"}:
                raise ProviderError("Native reviewer feedback row is malformed.")
            choice, explanation = row["choice"], row["explanation"]
            if type(choice) is not str or type(explanation) is not str or choice in feedback:
                raise ProviderError("Native reviewer feedback has invalid or duplicate choices.")
            feedback[choice] = explanation
        if review["valid"] is not True and (review["answer"] != "" or review["explanation"] != "" or rows):
            raise ProviderError("Native rejected review contains learner feedback or an answer.")
        review["choiceExplanations"] = feedback
    return json.dumps(adapted, ensure_ascii=False, allow_nan=False)


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON key")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ValueError(f"Invalid JSON constant: {value}")


def _validate_schema_value(value: Any, schema: dict[str, Any]) -> None:
    expected = schema.get("type")
    matches = {
        "object": type(value) is dict,
        "array": type(value) is list,
        "string": type(value) is str,
        "integer": type(value) is int,
        "boolean": type(value) is bool,
        "null": value is None,
    }.get(expected, False)
    if not matches or ("enum" in schema and value not in schema["enum"]):
        raise ValueError("Wrong native value type or enum.")
    if expected == "object":
        properties = schema["properties"]
        if not set(schema.get("required", [])).issubset(value):
            raise ValueError("Missing native field.")
        if schema.get("additionalProperties") is False and set(value) - set(properties):
            raise ValueError("Unknown native field.")
        for key, child in value.items():
            if key in properties:
                _validate_schema_value(child, properties[key])
    elif expected == "array":
        for child in value:
            _validate_schema_value(child, schema["items"])
