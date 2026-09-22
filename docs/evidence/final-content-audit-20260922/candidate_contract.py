"""Inactive final-content gate prototype. No provider access or runtime routing."""

import copy
import hashlib
import json

MAX_COUNT = 40
MAX_REASON = 600
VERDICTS = ("accepted", "rejected", "uncertain")


def checked_count(count):
    if type(count) is not int or not 1 <= count <= MAX_COUNT:
        raise ValueError("Trusted audit count must be an integer from 1 through 40.")
    return count


def _object(properties):
    return {"type": "object", "properties": properties,
            "required": list(properties), "additionalProperties": False}


def schema(count):
    return _object({"audits": _object({str(index): _object({
        "reason": {"type": "string"},
        "verdict": {"type": "string", "enum": list(VERDICTS)},
    }) for index in range(checked_count(count))})})


def output_config(count):
    encoded = json.dumps(schema(count), ensure_ascii=True, separators=(",", ":"))
    return {"textFormat": {"type": "json_schema", "structure": {"jsonSchema": {
        "name": f"final_content_audit_v1_n{count}", "schema": encoded,
    }}}}


def metadata(count):
    configured = output_config(count)["textFormat"]["structure"]["jsonSchema"]
    return {"name": configured["name"], "version": "1",
            "sha256": hashlib.sha256(configured["schema"].encode()).hexdigest()}


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON key.")
        result[key] = value
    return result


def _not_constant(value):
    raise ValueError("Nonstandard JSON number.")


def validate(raw, count):
    count = checked_count(count)
    value = json.loads(raw, object_pairs_hook=_unique, parse_constant=_not_constant)
    if type(value) is not dict or set(value) != {"audits"}:
        raise ValueError("Audit envelope must contain only audits.")
    rows = value["audits"]
    if type(rows) is not dict or set(rows) != {str(index) for index in range(count)}:
        raise ValueError("Audit identities must exactly cover the trusted batch.")
    for row in rows.values():
        if type(row) is not dict or set(row) != {"reason", "verdict"}:
            raise ValueError("Audit record has missing or extra fields.")
        if (type(row["reason"]) is not str or not row["reason"].strip()
                or len(row["reason"]) > MAX_REASON):
            raise ValueError("Audit reason must be nonblank and at most 600 codepoints.")
        if type(row["verdict"]) is not str or row["verdict"] not in VERDICTS:
            raise ValueError("Unknown audit verdict.")
    return {str(index): rows[str(index)] for index in range(count)}


def content_digest(payload):
    encoded = json.dumps(payload, sort_keys=True, ensure_ascii=False,
                         allow_nan=False, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def select_accepted(raw, original_payloads):
    """Release only exact originals; never salvage a malformed audit batch."""
    rows = validate(raw, len(original_payloads))
    accepted = []
    for index, original in enumerate(original_payloads):
        if rows[str(index)]["verdict"] == "accepted":
            selected = copy.deepcopy(original)
            if content_digest(selected) != content_digest(original):
                raise ValueError("Final audit cannot change learner content.")
            accepted.append(selected)
    return accepted
