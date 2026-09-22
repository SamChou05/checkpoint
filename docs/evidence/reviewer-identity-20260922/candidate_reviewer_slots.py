"""Inactive count-bound review identity contract; no provider or runtime routing.

Only trusted batch cardinality selects the schema. All learner-feedback semantics
and admission checks remain separate. Existing reviewer v1/v2 bytes are untouched.
"""

import copy
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "backend/bedrock-question-service"))

from native_output_contracts import (  # noqa: E402
    _reject_duplicate_pairs, _reject_constant, _validate_schema_value,
    adapt_native_response, native_output_config,
)
from service_errors import ProviderError  # noqa: E402

MAX_COUNT = 20


def _count(count):
    if type(count) is not int or not 1 <= count <= MAX_COUNT:
        raise ValueError("Trusted review count must be an integer from 1 through 20.")
    return count


def schema(count):
    _count(count)
    legacy = json.loads(native_output_config("default_reviewer_v1")["textFormat"]["structure"]["jsonSchema"]["schema"])
    row = copy.deepcopy(legacy["properties"]["reviews"]["items"])
    del row["properties"]["index"]
    row["required"].remove("index")
    keys = [str(index) for index in range(count)]
    return {
        "type": "object", "properties": {"reviews": {
            "type": "object", "properties": {key: copy.deepcopy(row) for key in keys},
            "required": keys, "additionalProperties": False,
        }}, "required": ["reviews"], "additionalProperties": False,
    }


def output_config(count):
    encoded = json.dumps(schema(count), ensure_ascii=True, separators=(",", ":"))
    return {"textFormat": {"type": "json_schema", "structure": {"jsonSchema": {
        "name": f"experimental_reviewer_slots_v3_n{count}", "schema": encoded,
    }}}}


def metadata(count):
    configured = output_config(count)["textFormat"]["structure"]["jsonSchema"]
    return {"name": configured["name"], "version": "3-experimental", "count": count,
            "sha256": hashlib.sha256(configured["schema"].encode()).hexdigest()}


def prompt_override(count):
    keys = ", ".join(json.dumps(str(index)) for index in range(_count(count)))
    return (
        "EXPERIMENTAL REVIEW IDENTITY OVERRIDE: Return reviews as an object, not an array. "
        f"It must contain exactly these required keys: {keys}. Each key identifies the "
        "supplied item with that integer index. Return one review value at every key, "
        "including rejected items; never add an unknown key or an index field inside a value. "
        "This replaces all earlier output examples and index-field instructions. Keep "
        "the existing valid, answer, difficulty, explanation and choiceFeedback fields. "
        "Use answer:\"\", explanation:\"\" and choiceFeedback:[] for a rejected item; "
        "use difficulty:0 when rejecting without a difficulty assessment. Do not change "
        "the question, choices or key."
    )


def _finite_float(value):
    result = float(value)
    if not math.isfinite(result):
        raise ValueError("Nonfinite JSON number.")
    return result


def adapt(raw, count):
    expected = schema(count)
    try:
        payload = json.loads(raw, object_pairs_hook=_reject_duplicate_pairs,
                             parse_constant=_reject_constant, parse_float=_finite_float)
        _validate_schema_value(payload, expected)
    except (TypeError, ValueError) as error:
        raise ProviderError("Slot reviewer violated its exact identity contract.") from error
    # Model-written index fields have already been forbidden. Restore identities
    # solely from trusted required keys, with deterministic numeric ordering.
    restored = {"reviews": [
        {"index": index, **payload["reviews"][str(index)]} for index in range(count)
    ]}
    return adapt_native_response(json.dumps(restored, ensure_ascii=False, allow_nan=False), "default_reviewer_v1")
