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
from quantitative_authoring import (
    MIXED_AUTHOR_CONTRACT, MIXED_AUTHOR_INSTRUCTIONS, mixed_author_schema,
    CONSTRUCTED_AUTHOR_CONTRACT, CONSTRUCTED_AUTHOR_INSTRUCTIONS, constructed_author_schema,
)


Contract = Literal[
    "question_author_v1",
    "question_author_v2",
    "question_author_v3",
    "question_author_mixed_v1",
    "question_author_constructed_v1",
    "skill_map_inference_v1",
    "skill_map_evolution_v1",
    "complete_choice_solver_v1",
    "complete_choice_solver_v3",
    "default_reviewer_v1",
    "default_reviewer_v2",
    "authored_solution_reviewer_v1",
]

MAX_REVIEW_BATCH_COUNT = 40

# Match only the owned author example, never arbitrary JSON or subject content.
_LEGACY_AUTHOR_EXAMPLE = '{"questions":[{"prompt":"...","explanation":"...","expectedAnswer":"...","choices":["...","...","...","..."],"topic":"...","skillID":"...","objectiveID":"...","objective":"...","difficulty":3,"format":"Multiple Choice"}]}'
_SLOT_AUTHOR_EXAMPLE = '{"questions":[{"prompt":"...","choices":{"a":"...","b":"...","c":"...","d":"..."},"explanation":"...","correctChoice":"a","topic":"...","skillID":"...","objectiveID":"...","objective":"...","difficulty":3,"format":"Multiple Choice"}]}'


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


@dataclass(frozen=True)
class SolverSlotContract:
    """Bind solver identities to the actual validated, answer-blind batch."""

    count: int

    def __post_init__(self) -> None:
        if type(self.count) is not int or not 1 <= self.count <= MAX_REVIEW_BATCH_COUNT:
            raise ServiceConfigurationError("Native solver count must be an integer from 1 through 40.")

    @property
    def name(self) -> str:
        return f"complete_choice_solver_v5_n{self.count}"


@dataclass(frozen=True)
class AuthoredSolutionReviewContract:
    """Bind immutable-main audit identities to actual post-solver survivors."""

    count: int

    def __post_init__(self) -> None:
        if type(self.count) is not int or not 1 <= self.count <= MAX_REVIEW_BATCH_COUNT:
            raise ServiceConfigurationError("Native authored review count must be an integer from 1 through 40.")

    @property
    def name(self) -> str:
        return f"authored_solution_reviewer_v2_n{self.count}"


@dataclass(frozen=True)
class AuthoredSolutionFlagReviewContract:
    """Bound immutable audits with explicit defect flags, not free-text issues."""

    count: int

    def __post_init__(self) -> None:
        if type(self.count) is not int or not 1 <= self.count <= MAX_REVIEW_BATCH_COUNT:
            raise ServiceConfigurationError("Native authored review count must be an integer from 1 through 40.")

    @property
    def name(self) -> str:
        return f"authored_solution_reviewer_v3_n{self.count}"


AUTHORED_ISSUE_FLAGS = (
    "answer_or_ambiguity", "explanation", "distractors", "scope_assignment", "novelty", "other",
)

_COUNT_BOUND_CONTRACTS = (
    ReviewerSlotContract, SolverSlotContract, AuthoredSolutionReviewContract, AuthoredSolutionFlagReviewContract,
)
NativeContract = (
    Contract | ReviewerSlotContract | SolverSlotContract | AuthoredSolutionReviewContract | AuthoredSolutionFlagReviewContract
)

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
_SCHEMAS[MIXED_AUTHOR_CONTRACT] = mixed_author_schema(
    _SCHEMAS["question_author_v3"]["properties"]["questions"]["items"]
)
_SCHEMAS[CONSTRUCTED_AUTHOR_CONTRACT] = constructed_author_schema(
    _SCHEMAS["question_author_v3"]["properties"]["questions"]["items"]
)


def output_mode() -> str:
    mode = os.getenv("BEDROCK_STRUCTURED_OUTPUT_MODE", "legacy").strip().lower()
    if mode not in {"legacy", "native"}:
        raise ServiceConfigurationError(
            "BEDROCK_STRUCTURED_OUTPUT_MODE must be legacy or native."
        )
    return mode


def _contract_schema(contract: NativeContract) -> dict[str, Any]:
    if isinstance(contract, AuthoredSolutionFlagReviewContract):
        row = _object({
            "valid": _BOOLEAN, "answer": _STRING,
            "difficulty": {"type": "integer", "enum": [1, 2, 3, 4, 5]},
            "explanationSupport": {"type": "string", "enum": ["supported", "unsupported", "uncertain"]},
            "issueFlags": _object({flag: _BOOLEAN for flag in AUTHORED_ISSUE_FLAGS}),
        })
        return _object({"reviews": _object({
            str(index): copy.deepcopy(row) for index in range(contract.count)
        })})
    if isinstance(contract, AuthoredSolutionReviewContract):
        legacy = json.loads(json.dumps(_SCHEMAS["authored_solution_reviewer_v1"], sort_keys=True))
        row = legacy["properties"]["reviews"]["items"]
        del row["properties"]["index"]
        row["required"].remove("index")
        return _object({"reviews": _object({
            str(index): copy.deepcopy(row) for index in range(contract.count)
        })})
    if isinstance(contract, SolverSlotContract):
        row = copy.deepcopy(_SCHEMAS["complete_choice_solver_v3"]["properties"]["solutions"]["items"])
        del row["properties"]["index"]
        row["required"].remove("index")
        return _object({"solutions": _object({
            str(index): copy.deepcopy(row) for index in range(contract.count)
        })})
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


def _solver_slot_transport_schema(contract: SolverSlotContract) -> dict[str, Any]:
    """Share repeated grammar definitions without relaxing the logical schema.

    The strict local validator continues to use the expanded owned contract.
    Only the provider representation uses internal references; neither external
    references nor arbitrary user-supplied schema definitions are interpreted.
    """
    row = copy.deepcopy(_contract_schema(SolverSlotContract(1))["properties"]["solutions"]["properties"]["0"])
    choice = copy.deepcopy(row["properties"]["choices"]["properties"]["a"])
    pair = copy.deepcopy(row["properties"]["choicePairs"]["properties"]["ab"])
    row["properties"]["choices"]["properties"] = {
        slot: {"$ref": "#/$defs/choiceJudgment"} for slot in ("a", "b", "c", "d")
    }
    row["properties"]["choicePairs"]["properties"] = {
        slot: {"$ref": "#/$defs/pairRelation"} for slot in ("ab", "ac", "ad", "bc", "bd", "cd")
    }
    schema = _object({"solutions": _object({
        str(index): {"$ref": "#/$defs/solution"} for index in range(contract.count)
    })})
    schema["$defs"] = {"choiceJudgment": choice, "pairRelation": pair, "solution": row}
    return schema


def native_output_config(contract: NativeContract) -> dict[str, Any]:
    """Return an independent wrapper with stable schema serialization."""
    schema = json.dumps(_contract_schema(contract), sort_keys=not isinstance(contract, _COUNT_BOUND_CONTRACTS),
                        separators=(",", ":"))
    if isinstance(contract, SolverSlotContract):
        schema = json.dumps(_solver_slot_transport_schema(contract), separators=(",", ":"))
    if isinstance(contract, (AuthoredSolutionReviewContract, AuthoredSolutionFlagReviewContract)):
        # Share the closed row definition so larger batches do not multiply the
        # provider grammar. The local validator uses the exact expanded schema.
        row = _contract_schema(type(contract)(1))["properties"]["reviews"]["properties"]["0"]
        shared = _object({"reviews": _object({
            str(index): {"$ref": "#/$defs/review"} for index in range(contract.count)
        })})
        shared["$defs"] = {"review": row}
        schema = json.dumps(shared, separators=(",", ":"))
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
    if contract == MIXED_AUTHOR_CONTRACT:
        # Reuse the existing ordered prose row; flat nodes have one shared,
        # nonrecursive definition regardless of expanded expression depth.
        prose = json.loads(native_output_config("question_author_v3")["textFormat"]["structure"]["jsonSchema"]["schema"])
        schema = json.dumps(mixed_author_schema(prose["properties"]["questions"]["items"], shared=True),
                            separators=(",", ":"))
    if contract == CONSTRUCTED_AUTHOR_CONTRACT:
        prose = json.loads(native_output_config("question_author_v3")["textFormat"]["structure"]["jsonSchema"]["schema"])
        schema = json.dumps(constructed_author_schema(prose["properties"]["questions"]["items"], shared=True),
                            separators=(",", ":"))
    return {"textFormat": {"type": "json_schema", "structure": {"jsonSchema": {
        "name": contract.name if isinstance(contract, _COUNT_BOUND_CONTRACTS) else contract, "schema": schema,
    }}}}


def contract_metadata(contract: NativeContract) -> dict[str, str]:
    config = native_output_config(contract)
    schema = config["textFormat"]["structure"]["jsonSchema"]["schema"]
    return {"name": contract.name if isinstance(contract, _COUNT_BOUND_CONTRACTS) else contract,
            "version": ("3" if isinstance(contract, AuthoredSolutionFlagReviewContract) else
                        "2" if isinstance(contract, AuthoredSolutionReviewContract) else
                        "5" if isinstance(contract, SolverSlotContract) else "3"
                        if isinstance(contract, ReviewerSlotContract) else contract.rsplit("_v", 1)[1]),
            "sha256": hashlib.sha256(schema.encode()).hexdigest()}


def ensure_supported_model(model_id: str) -> None:
    normalized = model_id.lower()
    if not any(value in normalized for value in ("moonshotai.kimi-k2.5", "anthropic.claude-sonnet-4-6")):
        raise ServiceConfigurationError(
            "Configured model is outside the native structured-output support allowlist."
        )


_LEGACY_AUTHORED_REVIEW_OUTPUT = """Report material defects or unresolved
obstacles as concise issues. Aim for at most 240 characters per issue; the hard
limit is 600, with at most 8 issues. Do not add issues merely to praise an item.

Return only {"reviews":[{"index":0,"valid":true,"answer":"exact offered choice",
"difficulty":3,"explanationSupport":"supported|unsupported|uncertain","issues":[]}]}.
Return exactly one record for every supplied index, with those exact fields and
no others. Never rewrite the stem, choices or explanation, produce replacement
teaching, or assign verification metadata. This is a fallible review declaration,
not a correctness certificate. The application rejects any unsupported/uncertain
explanation or reported issue even if valid is true."""


def _authored_flag_review_prompt(system_prompt: str, contract: AuthoredSolutionFlagReviewContract) -> str:
    row = {"valid": True, "answer": "exact offered choice", "difficulty": 3,
           "explanationSupport": "supported", "issueFlags": dict.fromkeys(AUTHORED_ISSUE_FLAGS, False)}
    example = json.dumps({"reviews": {str(index): row for index in range(contract.count)}}, separators=(",", ":"))
    instructions = (
        "Report material defects or unresolved obstacles using issueFlags. Set each flag to true "
        "when its category applies: answer_or_ambiguity for an incorrect, nonunique or unresolved answer; "
        "explanation for unsupported or unresolved teaching; distractors for inadequate alternatives; "
        "scope_assignment for goal, source, topic, assigned skill or objective mismatch; novelty for "
        "an exact or cosmetic repeat; other for any remaining material defect or unresolved obstacle. "
        "Set a flag to false only when that category has no defect or unresolved obstacle. "
        "Multiple flags may be true. Do not flag an item merely to praise it. "
        "Return valid:true only when the item fits its supplied topic, assigned skill and objective "
        "within the goal and provided source scope. Do not invent an assignment or missing premises. "
        "Compare the supplied existingQuestions descriptors: reject exact or cosmetic repeats, "
        "while allowing a fresh application of the same objective. Never rewrite an item to fix it.\n\n"
        f"NATIVE IMMUTABLE AUDIT ({contract.name}). Return only this JSON shape: {example}.\n"
        "Return exactly the shown required reviews keys, each bound to the supplied item with that "
        "integer index, including rejected items. Never add an unknown key or an index field inside "
        "a review. Keep exactly valid, answer, difficulty, explanationSupport and issueFlags; include "
        "all six boolean issueFlags and no other fields. Use the rubric to choose an integer difficulty "
        "from 1 through 5. explanationSupport must be supported, unsupported or uncertain. The example "
        "illustrates shape, not the verdicts for the supplied items. Never rewrite the stem, choices "
        "or explanation, produce replacement teaching, or assign verification metadata. This is a "
        "fallible review declaration, not a correctness certificate. The application rejects any "
        "unsupported/uncertain explanation or true issue flag even if valid is true."
    )
    if system_prompt.count(_LEGACY_AUTHORED_REVIEW_OUTPUT) != 1:
        raise ServiceConfigurationError("Native authored flag review requires its owned output instructions.")
    return system_prompt.replace(_LEGACY_AUTHORED_REVIEW_OUTPUT, instructions, 1)


def native_prompt(system_prompt: str, contract: NativeContract) -> str:
    if isinstance(contract, AuthoredSolutionFlagReviewContract):
        return _authored_flag_review_prompt(system_prompt, contract)
    if isinstance(contract, AuthoredSolutionReviewContract):
        keys = ", ".join(json.dumps(str(index)) for index in range(contract.count))
        return system_prompt + "\n\n" + (
            f"NATIVE IMMUTABLE AUDIT IDENTITY OVERRIDE ({contract.name}): Return reviews as an object, not an array. "
            f"It must contain exactly these required keys: {keys}. Each key identifies the "
            "supplied item with that integer index. Return one review value at every key, "
            "including rejected items; never add an unknown key or an index field inside a value. "
            "This replaces earlier output examples and index-field instructions. Keep exactly "
            "valid, answer, difficulty, explanationSupport and issues. Never produce replacement "
            "teaching or verification metadata. Preserve every unchanged question and explanation. "
            "Return valid:true only when the item fits its supplied topic, assigned skill and "
            "objective within the goal and provided source scope. Do not invent an assignment "
            "or missing premises. Compare the supplied existingQuestions descriptors: reject "
            "exact or cosmetic repeats, while allowing a fresh application of the same objective. "
            "Report a scope or novelty defect in issues; do not rewrite the item to fix it."
        )
    if contract == CONSTRUCTED_AUTHOR_CONTRACT:
        prose_example = json.loads(_SLOT_AUTHOR_EXAMPLE)["questions"][0]
        example = json.dumps({"questions": [
            {"kind": "prose", "question": prose_example},
            {"kind": "quantitative", "task": {"kind": "exact_value", "unit": "unitless",
                "nodes": [{"kind": "literal", "value": "8"}, {"kind": "literal", "value": "3"},
                          {"kind": "binary", "op": "sub", "left": 0, "right": 1}], "root": 2},
             "topic": "Arithmetic", "difficulty": 2},
        ]}, separators=(",", ":"))
        system_prompt = system_prompt.replace(_LEGACY_AUTHOR_EXAMPLE, example).replace(
            "Exactly four distinct choices; expectedAnswer exactly equals one of them.",
            "Prose rows have four distinct choices and correctChoice. Code constructs quantitative choices and the exact key.",
        )
        return system_prompt + "\n\n" + CONSTRUCTED_AUTHOR_INSTRUCTIONS
    if contract == MIXED_AUTHOR_CONTRACT:
        prose_example = json.loads(_SLOT_AUTHOR_EXAMPLE)["questions"][0]
        example = json.dumps({"questions": [
            {"kind": "prose", "question": prose_example},
            {"kind": "quantitative", "task": {
                "kind": "exact_value", "unit": "unitless",
                "nodes": [{"kind": "literal", "value": "2"},
                          {"kind": "binary", "op": "add", "left": 0, "right": 0}],
                "root": 1, "choices": {"a": "4", "b": "3", "c": "5", "d": "6"}},
             "topic": "Arithmetic", "difficulty": 2},
        ]}, separators=(",", ":"))
        system_prompt = system_prompt.replace(_LEGACY_AUTHOR_EXAMPLE, example).replace(
            "Exactly four distinct choices; expectedAnswer exactly equals one of them.",
            "Exactly four distinct choices. Prose rows use correctChoice; quantitative rows have no authored key.",
        )
        return system_prompt + "\n\n" + MIXED_AUTHOR_INSTRUCTIONS
    if isinstance(contract, SolverSlotContract):
        keys = ", ".join(json.dumps(str(index)) for index in range(contract.count))
        return native_prompt(system_prompt, "complete_choice_solver_v3") + "\n\n" + (
            f"NATIVE SOLVER IDENTITY OVERRIDE ({contract.name}): Return solutions as an object, not an array. "
            f"It must contain exactly these required keys: {keys}. Each key identifies the "
            "supplied item with that integer index. Return one solution value at every key; "
            "never add an unknown key or an index field inside a value. This replaces earlier "
            "output examples and index-field instructions. Keep exactly the existing four "
            "choices slots and six choicePairs slots, with their unchanged reason, judgment "
            "and relation fields. Do not alter the choice bindings, omit rejected or uncertain "
            "items, or infer a preferred answer."
        )
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
        # Give the author one consistent representation. A later override
        # should not have to contradict the example and answer requirement.
        # Historical wire schemas and legacy prompts remain unchanged.
        system_prompt = system_prompt.replace(_LEGACY_AUTHOR_EXAMPLE, _SLOT_AUTHOR_EXAMPLE).replace(
            "Exactly four distinct choices; expectedAnswer exactly equals one of them.",
            "Exactly four distinct choices; correctChoice identifies exactly one of them.",
        )
        return system_prompt + """

NATIVE TRANSPORT OVERRIDE (question_author_v2): Return choices as an object
with exactly four string slots named a, b, c, and d. Return correctChoice as
exactly one of "a", "b", "c", or "d", identifying the slot containing the
correct answer. Do not return expectedAnswer or a choices array. Slot names
are transport fields only; do not add slot labels to the choice text. Preserve
the requested question content and all other required and optional metadata.
The output example and native schema use this same representation.
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
    if isinstance(contract, SolverSlotContract):
        # Only required trusted keys can become indexes. Validate the complete
        # map before adapting; malformed or unbound records are never salvaged.
        restored = {"solutions": [
            {"index": index, **payload["solutions"][str(index)]}
            for index in range(contract.count)
        ]}
        return adapt_native_response(json.dumps(restored, ensure_ascii=False, allow_nan=False),
                                     "complete_choice_solver_v3")
    if isinstance(contract, AuthoredSolutionFlagReviewContract):
        # Validate every flag and identity before mapping declarations to the
        # unchanged local issue veto. False flags never bypass other gates.
        reviews = []
        for index in range(contract.count):
            row = payload["reviews"][str(index)]
            flags = row.pop("issueFlags")
            reviews.append({"index": index, **row,
                            "issues": [flag for flag in AUTHORED_ISSUE_FLAGS if flags[flag]]})
        return adapt_native_response(json.dumps({"reviews": reviews}, ensure_ascii=False, allow_nan=False),
                                     "authored_solution_reviewer_v1")
    if isinstance(contract, (ReviewerSlotContract, AuthoredSolutionReviewContract)):
        # Validate the complete map first. Do not drop, fill, or renumber invalid
        # model records. Only trusted required keys can supply internal indexes.
        restored = {"reviews": [
            {"index": index, **payload["reviews"][str(index)]}
            for index in range(contract.count)
        ]}
        return adapt_native_response(json.dumps(restored, ensure_ascii=False, allow_nan=False),
                                     "authored_solution_reviewer_v1" if isinstance(contract, AuthoredSolutionReviewContract)
                                     else "default_reviewer_v1")
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
