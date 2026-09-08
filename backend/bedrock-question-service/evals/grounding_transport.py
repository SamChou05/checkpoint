"""Native Nova grounding observations through the existing bounded worker.

The inherited response.text slot transports explicitly tagged observation JSON,
not assistant prose. Native citations are URL leads, not fetched page contents or
factual verification. Generated text and native sourceContent remain distinct.
"""

import copy
import json

from evals import checkpoint_author_latency_probe as caller

SCHEMA = "checkpoint.nova-grounding-observation.v1"
MODEL = "us.amazon.nova-2-lite-v1:0"
MAX_INPUT_BYTES = 32_000
MAX_PROJECTED_BYTES = 120_000  # Also allows JSON escaping inside the 256 KiB IPC frame.
TRANSPORT_SETTINGS = {"BEDROCK_REGION": "us-east-1", "BEDROCK_READ_TIMEOUT_SECONDS": "75",
                      "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3"}


def grounding_request(system, user):
    """Build the previously observed Converse system-tool shape, without a call."""
    if any(type(text) is not str or not text.strip() for text in (system, user)):
        raise ValueError("Grounding prompts must be nonempty text.")
    request = {
        "modelId": MODEL, "system": [{"text": system}],
        "messages": [{"role": "user", "content": [{"text": user}]}],
        "toolConfig": {"tools": [{"systemTool": {"name": "nova_grounding"}}]},
        "inferenceConfig": {"maxTokens": 2048},
        "additionalModelRequestFields": {"reasoningConfig": {"type": "disabled"}},
    }
    if len(caller.shared.canonical(request).encode()) > MAX_INPUT_BYTES:
        raise ValueError("Grounding request exceeds the input allowance.")
    return request


def _text_blocks(value):
    if type(value) is not list or any(
        type(block) is not dict or set(block) != {"text"} or type(block["text"]) is not str
        for block in value
    ):
        raise ValueError("Unsupported native text content.")


def _native_content(blocks):
    """Validate the narrow observed native types; never salvage unknown blocks."""
    if type(blocks) is not list or not blocks:
        raise ValueError("Missing native content.")
    for block in blocks:
        if type(block) is not dict or len(block) != 1:
            raise ValueError("Unsupported native content block.")
        kind, value = next(iter(block.items()))
        if kind == "text":
            if type(value) is not str:
                raise ValueError("Malformed generated text.")
        elif kind == "citationsContent":
            if type(value) is not dict or set(value) - {"content", "citations"}:
                raise ValueError("Unsupported citation content.")
            if "content" in value:
                _text_blocks(value["content"])
            if type(value.get("citations")) is not list:
                raise ValueError("Missing native citations.")
            for citation in value["citations"]:
                if type(citation) is not dict or set(citation) - {"title", "source", "sourceContent", "location"}:
                    raise ValueError("Unsupported native citation.")
                for key in ("title", "source"):
                    if key in citation and type(citation[key]) is not str:
                        raise ValueError("Malformed citation metadata.")
                if "sourceContent" in citation:
                    _text_blocks(citation["sourceContent"])
                location = citation.get("location")
                web = location.get("web") if type(location) is dict else None
                if (type(location) is not dict or set(location) != {"web"}
                        or type(web) is not dict or set(web) - {"url", "domain"}
                        or type(web.get("url")) is not str or not web["url"].strip()
                        or ("domain" in web and type(web["domain"]) is not str)):
                    raise ValueError("Unsupported native citation location.")
        elif kind in ("toolUse", "toolResult"):
            allowed = {"toolUseId", "name", "input", "type"} if kind == "toolUse" else {
                "toolUseId", "content", "status", "type"}
            if (type(value) is not dict or set(value) - allowed
                    or type(value.get("toolUseId")) is not str or not value["toolUseId"]
                    or ("type" in value and type(value["type"]) is not str)):
                raise ValueError("Malformed native tool observation.")
            if kind == "toolUse":
                if value.get("name") != "nova_grounding" or type(value.get("input")) is not dict:
                    raise ValueError("Unsupported native tool.")
            else:
                if value.get("status") not in ("success", "error"):
                    raise ValueError("Malformed native tool result.")
                _text_blocks(value.get("content"))
        else:
            raise ValueError("Unsupported native content block.")
    # Also rejects non-JSON values and nonfinite numbers in tool inputs.
    caller.shared.canonical(blocks)


def project_grounding_response(response):
    """Remove private reasoning/metadata and encode explicitly tagged native data."""
    projected = caller.recorded._response(response)
    output = response.get("output") if type(response) is dict else None
    message = output.get("message", {}) if type(output) is dict else {}
    blocks = message.get("content") if type(message) is dict else None
    native = [block for block in blocks if type(block) is not dict or set(block) != {"reasoningContent"}] \
        if type(blocks) is list else None
    error = None
    try:
        if type(message) is not dict or message.get("role") != "assistant":
            raise ValueError("Missing assistant response.")
        _native_content(native)
    except (ValueError, TypeError):
        native, error = [], "unsupported_native_content"
    payload = {"schema": SCHEMA, "content": native, "projection_error": error}
    text = caller.shared.canonical(payload)
    if len(text.encode()) > MAX_PROJECTED_BYTES:
        raise ValueError("GroundingProjectionLimit")
    projected.update(text=text, content_valid=error is None)
    return projected


def decode_grounding_response(response):
    """Decode native observation JSON; never extract URLs from generated prose."""
    caller.recorded._validate_response_record(response)
    if not response["content_valid"] or response["stopReason"] != "end_turn":
        raise ValueError("Grounding response did not complete with supported content.")
    text = response["text"]
    if len(text.encode()) > MAX_PROJECTED_BYTES:
        raise ValueError("GroundingProjectionLimit")
    payload = json.loads(text)
    if (type(payload) is not dict or set(payload) != {"schema", "content", "projection_error"}
            or payload["schema"] != SCHEMA or payload["projection_error"] is not None
            or caller.shared.canonical(payload) != text):
        raise ValueError("Exact tagged grounding observation required.")
    _native_content(payload["content"])
    generated, urls = [], []
    for block_index, block in enumerate(payload["content"]):
        if "text" in block:
            generated.append(block["text"])
        if "citationsContent" in block:
            value = block["citationsContent"]
            generated.extend(row["text"] for row in value.get("content", []))
            urls.extend({"block_index": block_index, "citation_index": index,
                         "url": citation["location"]["web"]["url"]}
                        for index, citation in enumerate(value["citations"]))
    return {**copy.deepcopy(payload), "generated_text": "".join(generated), "citation_urls": urls}


def grounding_worker(connection, request, settings, cli_credentials, deadline):
    """Use the inherited readiness/deadline/cleanup protocol with local settings."""
    if request != grounding_request(request["system"][0]["text"], request["messages"][0]["content"][0]["text"]):
        raise ValueError("Unexpected grounding request shape.")
    caller._worker(connection, request, {**settings, **TRANSPORT_SETTINGS}, cli_credentials, deadline,
                   response_projector=project_grounding_response)
