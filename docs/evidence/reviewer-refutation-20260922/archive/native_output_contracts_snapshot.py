"""Versioned Bedrock structured-output contracts for production model stages.

Schemas describe transport shape only.  Correlation, counts, semantic quality,
and answer agreement remain the responsibility of the existing stage validators.
"""

import copy
from dataclasses import dataclass
import hashlib
import json
import os
from typing import Any, Literal

from service_errors import ProviderError, ServiceConfigurationError


Contract = Literal[
    "question_author_v1",
    "question_author_v2",
    "question_author_v3",
    "skill_map_inference_v1",
    "skill_map_evolution_v1",
    "complete_choice_solver_v1",
    "complete_choice_solver_v3",
    "default_reviewer_v1",
    "default_reviewer_v2",
    "authored_solution_reviewer_v1",
]

MAX_REVIEW_BATCH_COUNT = 40


@dataclass(frozen=True)
class ReviewerSlotContract:
    """Bind reviewer identities to the trusted post-solver batch cardinality."""

    count: int

    def __post_init__(self) -> None:
        if type(self.count) is not int or not 1 <= self.count <= MAX_REVIEW_BATCH_COUNT:
            raise ServiceConfigurationError("Native review count must be an integer from 1 through 40.")

    @property
    def name(self) -> str:
        return f"default_reviewer_v3_n{self.count}"


NativeContract = Contract | ReviewerSlotContract

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
    # Fixed slots constrain the choice count and key membership without schema
    # array bounds or a model-authored answer string. Distinctness and factual
    # correctness still require application admission checks. Retain v2's sorted
    # serialization for explicit compatibility and frozen comparison replays.
    "question_author_v2": _object({
        "questions": {"type": "array", "items": _object({
            "prompt": _STRING,
            "choices": _object(dict.fromkeys(("a", "b", "c", "d"), _STRING)),
            "correctChoice": {"type": "string", "enum": ["a", "b", "c", "d"]},
            "explanation": _STRING, "topic": _STRING, "difficulty": _INTEGER,
            "format": {"type": "string", "enum": ["Multiple Choice"]},
            "skillID": _STRING, "objectiveID": _STRING, "objective": _STRING,
        }, ["prompt", "choices", "correctChoice", "explanation", "topic", "difficulty", "format"])}
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
    # Fixed identifiers bind every judgment and unordered pair to input slots.
    # No model-authored choice text or array length can create self/extra pairs.
    # Exact batch/index coverage and semantic truth still require local checks.
    "complete_choice_solver_v3": _object({
        "solutions": {"type": "array", "items": _object({
            "index": _INTEGER,
            "choices": _object({slot: _object({
                "reason": _STRING,
                "judgment": {"type": "string", "enum": ["supported", "refuted", "uncertain"]},
            }) for slot in ("a", "b", "c", "d")}),
            "choicePairs": _object({slot: _object({
                "reason": _STRING,
                "relation": {"type": "string", "enum": ["equivalent", "distinct", "uncertain"]},
            }) for slot in ("ab", "ac", "ad", "bc", "bd", "cd")}),
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
    # Experimental only: production does not select this union. Closed branches
    # exclude learner feedback on rejections, but live qualification rejected
    # valid controls too. Do not promote schema validity as useful-output proof.
    "default_reviewer_v2": _object({
        "reviews": {"type": "array", "items": {"anyOf": [
            _object({
                "index": _INTEGER, "valid": {"type": "boolean", "enum": [True]},
                "answer": _STRING, "difficulty": _INTEGER, "explanation": _STRING,
                "choiceFeedback": {"type": "array", "items": _object({
                    "choice": _STRING, "explanation": _STRING,
                })},
            }),
            _object({
                "index": _INTEGER, "valid": {"type": "boolean", "enum": [False]},
            }),
        ]}}
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

# V3 has the same semantic shape as v2. Only its serialized question-property
# order changes, matching the qualified ordering experiment byte for byte.
_SCHEMAS["question_author_v3"] = copy.deepcopy(_SCHEMAS["question_author_v2"])
_AUTHOR_V3_PROPERTY_ORDER = (
    "prompt", "choices", "explanation", "correctChoice", "topic", "difficulty",
    "format", "skillID", "objectiveID", "objective",
)


def output_mode() -> str:
    mode = os.getenv("BEDROCK_STRUCTURED_OUTPUT_MODE", "legacy").strip().lower()
    if mode not in {"legacy", "native"}:
        raise ServiceConfigurationError(
            "BEDROCK_STRUCTURED_OUTPUT_MODE must be legacy or native."
        )
    return mode


def _contract_schema(contract: NativeContract) -> dict[str, Any]:
    if not isinstance(contract, ReviewerSlotContract):
        return _SCHEMAS[contract]
    # Retain the exact count-five grammar qualified live: canonical v1 row
    # properties, no model-written index, and required trusted outer identities.
    legacy = json.loads(json.dumps(_SCHEMAS["default_reviewer_v1"], sort_keys=True))
    row = legacy["properties"]["reviews"]["items"]
    del row["properties"]["index"]
    row["required"].remove("index")
    return _object({"reviews": _object({
        str(index): copy.deepcopy(row) for index in range(contract.count)
    })})


def native_output_config(contract: NativeContract) -> dict[str, Any]:
    """Return an independent wrapper with stable schema serialization."""
    schema = json.dumps(_contract_schema(contract), sort_keys=not isinstance(contract, ReviewerSlotContract),
                        separators=(",", ":"))
    if contract == "complete_choice_solver_v3":
        # V3 intentionally declares reason before the final judgment/relation.
        # Scope insertion-order serialization to this new contract so all
        # historical schema bytes and author-v3 qualified ordering stay intact.
        schema = json.dumps(_SCHEMAS[contract], separators=(",", ":"))
    if contract == "question_author_v3":
        # Preserve the canonical ordering of every other mapping and required
        # array. This changes exactly the property-order treatment tested live;
        # a global sort removal would also rewrite historical schema hashes.
        ordered = json.loads(schema)
        question = ordered["properties"]["questions"]["items"]
        properties = question["properties"]
        if set(properties) != set(_AUTHOR_V3_PROPERTY_ORDER):
            raise ServiceConfigurationError("Author v3 property ordering needs qualification.")
        question["properties"] = {key: properties[key] for key in _AUTHOR_V3_PROPERTY_ORDER}
        schema = json.dumps(ordered, separators=(",", ":"))
    return {"textFormat": {"type": "json_schema", "structure": {"jsonSchema": {
        "name": contract.name if isinstance(contract, ReviewerSlotContract) else contract, "schema": schema,
    }}}}


def contract_metadata(contract: NativeContract) -> dict[str, str]:
    config = native_output_config(contract)
    schema = config["textFormat"]["structure"]["jsonSchema"]["schema"]
    return {"name": contract.name if isinstance(contract, ReviewerSlotContract) else contract,
            "version": "3" if isinstance(contract, ReviewerSlotContract) else contract.rsplit("_v", 1)[1],
            "sha256": hashlib.sha256(schema.encode()).hexdigest()}


def ensure_supported_model(model_id: str) -> None:
    normalized = model_id.lower()
    if not any(value in normalized for value in ("moonshotai.kimi-k2.5", "anthropic.claude-sonnet-4-6")):
        raise ServiceConfigurationError(
            "Configured model is outside the native structured-output support allowlist."
        )


def native_prompt(system_prompt: str, contract: NativeContract) -> str:
    if isinstance(contract, ReviewerSlotContract):
        keys = ", ".join(json.dumps(str(index)) for index in range(contract.count))
        # Preserve the live-qualified override wording, including its original
        # experiment label. This label does not select routing or relax checks.
        return native_prompt(system_prompt, "default_reviewer_v1") + "\n\n" + (
            "EXPERIMENTAL REVIEW IDENTITY OVERRIDE: Return reviews as an object, not an array. "
            f"It must contain exactly these required keys: {keys}. Each key identifies the "
            "supplied item with that integer index. Return one review value at every key, "
            "including rejected items; never add an unknown key or an index field inside a value. "
            "This replaces all earlier output examples and index-field instructions. Keep "
            "the existing valid, answer, difficulty, explanation and choiceFeedback fields. "
            'Use answer:"", explanation:"" and choiceFeedback:[] for a rejected item; '
            "use difficulty:0 when rejecting without a difficulty assessment. Do not change "
            "the question, choices or key."
        )
    if contract in {"question_author_v2", "question_author_v3"}:
        # Keep the tested slot-transport wording byte-identical. The v2 label
        # identifies this representation; v3 changes ordering, not these rules.
        return system_prompt + """

NATIVE TRANSPORT OVERRIDE (question_author_v2): Return choices as an object
with exactly four string slots named a, b, c, and d. Return correctChoice as
exactly one of "a", "b", "c", or "d", identifying the slot containing the
correct answer. Do not return expectedAnswer or a choices array. Slot names
are transport fields only; do not add slot labels to the choice text. Preserve
the requested question content and all other required and optional metadata.
This replaces the earlier output example's choices and answer representation.
Do not add fields. The application derives the answer text from the selected
slot; the explanation must not select or replace that answer.
"""
    if contract == "default_reviewer_v2":
        return system_prompt + """

NATIVE TRANSPORT OVERRIDE: For an accepted review return index, valid:true,
answer, difficulty, explanation, and the schema's choiceFeedback array instead
of choiceExplanations. Include exactly one feedback row for every offered
choice, preserving exact choice bytes. For a rejected review return only
index and valid:false. Do not include answer, difficulty, explanation, or
choiceFeedback on a rejection. This replaces the earlier output example and
minimal negative response shape. Do not add fields.
"""
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


def adapt_native_response(raw: str, contract: NativeContract) -> str:
    """Validate native JSON before any provider-only shape is adapted."""
    try:
        payload = json.loads(raw, object_pairs_hook=_reject_duplicate_pairs, parse_constant=_reject_constant)
    except (TypeError, ValueError) as error:
        raise ProviderError("Native stage returned malformed JSON.") from error
    try:
        _validate_schema_value(payload, _contract_schema(contract))
    except ValueError as error:
        raise ProviderError("Native stage response violates its contract.") from error
    if isinstance(contract, ReviewerSlotContract):
        # Validate the complete map first. Do not drop, fill, or renumber invalid
        # model records. Only trusted required keys can supply internal indexes.
        restored = {"reviews": [
            {"index": index, **payload["reviews"][str(index)]}
            for index in range(contract.count)
        ]}
        return adapt_native_response(json.dumps(restored, ensure_ascii=False, allow_nan=False),
                                     "default_reviewer_v1")
    if contract in {"question_author_v2", "question_author_v3"}:
        adapted = copy.deepcopy(payload)
        for question in adapted["questions"]:
            slots = question["choices"]
            question["choices"] = [slots[key] for key in ("a", "b", "c", "d")]
            question["expectedAnswer"] = slots[question.pop("correctChoice")]
        return json.dumps(adapted, ensure_ascii=False, allow_nan=False)
    if contract not in {"default_reviewer_v1", "default_reviewer_v2"}:
        return raw
    if type(payload) is not dict or set(payload) != {"reviews"} or type(payload["reviews"]) is not list:
        raise ProviderError("Native reviewer returned an invalid envelope.")
    adapted = copy.deepcopy(payload)
    for review in adapted["reviews"]:
        if review["valid"] is False:
            # Full JSON/schema validation has already checked this row. A typed
            # false verdict irrevocably rejects the item, so discard its unused
            # v1 feedback instead of failing otherwise valid sibling reviews.
            # Keep the exact index for downstream coverage/correlation checks.
            index = review["index"]
            review.clear()
            review.update(index=index, valid=False)
            continue
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
    if "anyOf" in schema:
        branches = schema["anyOf"]
        # Support only standalone unions used by these owned contracts. Never
        # silently ignore sibling constraints or accept an invalid union shape.
        if (set(schema) != {"anyOf"} or type(branches) is not list or not branches
                or any(type(branch) is not dict for branch in branches)):
            raise ValueError("Unsupported native union schema.")
        for branch in branches:
            try:
                _validate_schema_value(value, branch)
            except ValueError:
                continue
            return
        raise ValueError("No native union branch matched.")
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
