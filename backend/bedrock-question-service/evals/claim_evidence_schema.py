"""Static Converse output shape for the eval-only claim evidence reviewer.

This constrains the response envelope, not the truth of any judgment. Exact
choices, index coverage, citation bindings, lengths and cardinalities remain
the responsibility of claim_evidence_review.observe_review. No question data,
provider calls or native citation configuration belongs in this schema.
"""

import json


def _object(properties):
    return {
        "type": "object",
        "properties": properties,
        "required": list(properties),
        "additionalProperties": False,
    }


def _citations():
    return {
        "type": "array",
        "items": _object(
            {"source_id": {"type": "string"}, "quote": {"type": "string"}}
        ),
    }


_SCHEMA = _object(
    {
        "reviews": {
            "type": "array",
            "items": _object(
                {
                    "index": {"type": "integer"},
                    "valid": {"type": "boolean"},
                    "answer": {"type": "string"},
                    "difficulty": {"type": "integer", "enum": [1, 2, 3, 4, 5]},
                    "explanationSupport": {
                        "type": "string",
                        "enum": ["supported", "unsupported", "uncertain"],
                    },
                    "issues": {"type": "array", "items": {"type": "string"}},
                }
            ),
        },
        "evidence": _object(
            {
                "item": _citations(),
                "mainExplanation": _citations(),
                "target": _object(
                    {
                        "field": {
                            "type": "string",
                            "enum": ["prompt", "choice", "explanation"],
                        },
                        "choice": {"anyOf": [{"type": "string"}, {"type": "null"}]},
                        "quote": {"type": "string"},
                        "relation": {
                            "type": "string",
                            "enum": ["supported", "contradicted", "unresolved"],
                        },
                        "citations": _citations(),
                    }
                ),
            }
        ),
    }
)
# Serialize once: callers can mutate their returned wrapper without changing
# later requests or introducing per-question grammar compilation.
_SCHEMA_JSON = json.dumps(_SCHEMA, ensure_ascii=False, separators=(",", ":"))


def output_config():
    """Return the Converse request's outputConfig value; no request is sent."""
    return {
        "textFormat": {
            "type": "json_schema",
            "structure": {
                "jsonSchema": {
                    "name": "checkpoint_claim_evidence_review_v1",
                    "schema": _SCHEMA_JSON,
                }
            },
        }
    }
