"""Bounded, model-independent AgentCore Web Search observations.

This client requires an AWS_IAM Gateway supporting stateless MCP 2026-07-28
and the web-search 1.2 connector. It neither creates resources nor invokes an
LLM. Search snippets are external observations, not full pages, exact source
quotations, or factual certification. Source selection remains the caller's job.

The default HTTPS transport uses a trusted child only to bound DNS, connection,
and response time. Signed headers cross its stdin pipe, never argv or records.
No redirects, proxy environment, session negotiation, pagination, or retries.
"""

from __future__ import annotations

import base64
import copy
import hashlib
import http.client
import json
import os
import re
import subprocess
import sys
import time
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlsplit


PROTOCOL_VERSION = "2026-07-28"
SUPPORTED_REGIONS = frozenset({"us-east-1", "eu-west-1", "ap-northeast-1"})
_TOOL_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,100}___WebSearch\Z")
_DOMAIN = re.compile(r"(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\Z")


class WebSearchError(ValueError):
    """Unsupported input, protocol failure, or failed one-attempt transport."""


@dataclass(frozen=True)
class SearchLimits:
    maximum_searches: int = 3
    maximum_results: int = 5
    request_bytes: int = 32_768
    response_bytes: int = 131_072
    timeout_seconds: int = 15

    def __post_init__(self) -> None:
        for name, maximum in (
            ("maximum_searches", 10), ("maximum_results", 25),
            ("request_bytes", 65_536), ("response_bytes", 1_048_576),
            ("timeout_seconds", 60),
        ):
            value = getattr(self, name)
            if type(value) is not int or not 1 <= value <= maximum:
                raise WebSearchError(f"Invalid {name} limit")


@dataclass(frozen=True)
class TransportResponse:
    status: int
    headers: dict[str, str]
    body: bytes


def _canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def _digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise WebSearchError("Duplicate JSON key")
        result[key] = value
    return result


def _json(text: str) -> Any:
    def invalid_constant(_value: str) -> None:
        raise WebSearchError("Non-finite JSON number")
    try:
        return json.loads(text, object_pairs_hook=_object,
                          parse_constant=invalid_constant)
    except (ValueError, RecursionError) as error:
        raise WebSearchError("Invalid strict JSON") from error


def validate_endpoint(endpoint: str, region: str) -> str:
    """Validate the exact credential destination before loading or signing."""
    if not isinstance(region, str) or region not in SUPPORTED_REGIONS or not isinstance(endpoint, str):
        raise WebSearchError("Unsupported Web Search region or endpoint")
    pattern = (
        r"https://[a-z0-9][a-z0-9-]{0,109}"
        r"\.gateway\.bedrock-agentcore\." + re.escape(region)
        + r"\.amazonaws\.com/mcp\Z"
    )
    if not re.fullmatch(pattern, endpoint):
        raise WebSearchError("Expected exact regional AWS Gateway HTTPS /mcp endpoint")
    return endpoint


def _sigv4(endpoint: str, region: str, body: bytes,
           headers: dict[str, str]) -> dict[str, str]:
    # Optional runtime imports stay lazy for local tests and non-AWS consumers.
    import boto3
    from botocore.auth import SigV4Auth
    from botocore.awsrequest import AWSRequest

    credentials = boto3.Session().get_credentials()
    if credentials is None:
        raise WebSearchError("AWS credentials unavailable")
    request = AWSRequest(method="POST", url=endpoint, data=body, headers=headers)
    SigV4Auth(credentials.get_frozen_credentials(), "bedrock-agentcore", region).add_auth(request)
    return dict(request.headers.items())


def _child_transport() -> None:
    """Private trusted child entry; never prints credentials or error text."""
    try:
        packet = _json(sys.stdin.buffer.read(131_073).decode("utf-8"))
        endpoint = validate_endpoint(packet["endpoint"], packet["region"])
        body = base64.b64decode(packet["body"], validate=True)
        maximum = packet["maximum_bytes"]
        connection = http.client.HTTPSConnection(
            urlsplit(endpoint).hostname, timeout=packet["timeout_seconds"]
        )
        try:
            connection.request("POST", "/mcp", body=body, headers=packet["headers"])
            response = connection.getresponse()
            raw = response.read(maximum + 1)
            if len(raw) > maximum:
                raise WebSearchError("Response body exceeds limit")
            # Only protocol headers are observable; no server cookies or secrets.
            headers = {}
            for name, value in response.getheaders():
                name = name.lower()
                if name in {"content-type", "content-encoding", "mcp-session-id"}:
                    if name in headers:
                        raise WebSearchError("Duplicate protocol header")
                    headers[name] = value
            output = {"status": response.status, "headers": headers,
                      "body": base64.b64encode(raw).decode("ascii")}
        finally:
            connection.close()
    except Exception as error:
        output = {"error_type": type(error).__name__}
    sys.stdout.buffer.write(_canonical(output))


def _https_transport(endpoint: str, region: str, body: bytes,
                     headers: dict[str, str], limits: SearchLimits) -> TransportResponse:
    validate_endpoint(endpoint, region)
    packet = _canonical({"endpoint": endpoint, "region": region,
                         "body": base64.b64encode(body).decode("ascii"),
                         "headers": headers, "maximum_bytes": limits.response_bytes,
                         "timeout_seconds": limits.timeout_seconds})
    if len(packet) > 131_072:
        raise WebSearchError("Signed transport request exceeds limit")
    # Direct http.client does not use proxy variables. Also keep the child env
    # free of credentials, proxy overrides, and Python startup customization.
    process = subprocess.Popen(
        [sys.executable, "-I", str(Path(__file__).resolve()), "--https-transport"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        env={"PATH": os.defpath},
    )
    try:
        raw, _ = process.communicate(packet, timeout=limits.timeout_seconds)
    except BaseException as error:
        process.kill()
        try:
            process.communicate(timeout=2)
        except subprocess.TimeoutExpired as cleanup_error:
            raise WebSearchError("Transport cleanup unconfirmed") from cleanup_error
        if isinstance(error, subprocess.TimeoutExpired):
            raise WebSearchError("Transport deadline exceeded") from error
        raise
    if process.returncode != 0 or len(raw) > limits.response_bytes * 2 + 8192:
        raise WebSearchError("Transport child failed or output exceeded limit")
    output = _json(raw.decode("utf-8"))
    if not isinstance(output, dict) or set(output) != {"status", "headers", "body"}:
        raise WebSearchError("HTTPS transport failed")
    return TransportResponse(output["status"], output["headers"],
                             base64.b64decode(output["body"], validate=True))


def _parse_response(response: TransportResponse, expected_id: str,
                    maximum_bytes: int) -> dict[str, Any]:
    if type(response.status) is not int or response.status != 200:
        raise WebSearchError("Expected HTTP 200; redirects and retries are unsupported")
    if not isinstance(response.headers, dict) or any(
        not isinstance(k, str) or not isinstance(v, str)
        for k, v in response.headers.items()
    ):
        raise WebSearchError("Invalid HTTP headers")
    headers = {key.lower(): value for key, value in response.headers.items()}
    if len(headers) != len(response.headers):
        raise WebSearchError("Duplicate protocol headers")
    if "mcp-session-id" in headers or headers.get("content-encoding", "identity") != "identity":
        raise WebSearchError("Sessions and compressed responses are unsupported")
    if not isinstance(response.body, bytes) or len(response.body) > maximum_bytes:
        raise WebSearchError("Invalid or oversized response body")
    try:
        text = response.body.decode("utf-8")
    except UnicodeError as error:
        raise WebSearchError("Response is not UTF-8") from error
    content_type = headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if content_type == "application/json":
        message = _json(text)
    elif content_type == "text/event-stream":
        # Accept exactly one complete data event, with optional SSE comments.
        # Progress, logging, elicitation, resumable event IDs and extra results
        # intentionally fail closed instead of being silently discarded.
        messages, data, event = [], [], None
        lines = text.replace("\r\n", "\n").split("\n")
        if lines[-1] == "":
            lines.pop()  # EOF after one newline is not itself a blank SSE line.
        for line in lines:
            if not line:
                if data:
                    messages.append(_json("\n".join(data)))
                elif event is not None:
                    raise WebSearchError("Empty SSE event")
                data, event = [], None
            elif line.startswith(":"):
                continue
            else:
                field, separator, value = line.partition(":")
                if value.startswith(" "):
                    value = value[1:]
                if field == "data" and separator:
                    data.append(value)
                elif field == "event" and value == "message" and event is None:
                    event = value
                else:
                    raise WebSearchError("Unsupported SSE field or continuation")
        if data or event is not None or len(messages) != 1:
            raise WebSearchError("Expected one complete SSE result")
        message = messages[0]
    else:
        raise WebSearchError("Unsupported response content type")
    if (not isinstance(message, dict) or set(message) != {"jsonrpc", "id", "result"}
            or message["jsonrpc"] != "2.0" or type(message["id"]) is not str
            or message["id"] != expected_id or not isinstance(message["result"], dict)):
        raise WebSearchError("Expected one correlated JSON-RPC result")
    return message["result"]


def _validate_filters(value: Any) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict) or set(value) - {"domainFilter", "publishedDateFilter"}:
        raise WebSearchError("Invalid search filters")
    for name, entry in value.items():
        if not isinstance(entry, dict):
            raise WebSearchError("Invalid filter object")
        if name == "domainFilter":
            if set(entry) - {"include", "exclude"}:
                raise WebSearchError("Invalid domain filter")
            for domains in entry.values():
                if (not isinstance(domains, list) or len(domains) > 100
                        or any(not isinstance(d, str) or not _DOMAIN.fullmatch(d) for d in domains)
                        or len(set(domains)) != len(domains)):
                    raise WebSearchError("Expected distinct lowercase domain names")
        else:
            if set(entry) - {"from", "to"}:
                raise WebSearchError("Invalid date filter")
            dates = {}
            for bound, date in entry.items():
                if not isinstance(date, str) or not re.fullmatch(
                    r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z", date
                ):
                    raise WebSearchError("Expected ISO-8601 UTC date bound")
                try:
                    dates[bound] = datetime.fromisoformat(date.replace("Z", "+00:00"))
                except ValueError as error:
                    raise WebSearchError("Invalid calendar date") from error
            if "from" in dates and "to" in dates and dates["from"] > dates["to"]:
                raise WebSearchError("Reversed date bounds")
    return copy.deepcopy(value)


def _discovered_tool(result: dict[str, Any]) -> dict[str, Any]:
    if set(result) != {"tools"} or not isinstance(result["tools"], list):
        raise WebSearchError("Expected unpaginated tool list")
    if not 1 <= len(result["tools"]) <= 20:
        raise WebSearchError("Unexpected tool count")
    matches, names = [], set()
    for tool in result["tools"]:
        if (not isinstance(tool, dict) or set(tool) - {
            "name", "description", "inputSchema", "outputSchema", "annotations", "title"
        } or not isinstance(tool.get("name"), str) or tool["name"] in names
                or not isinstance(tool.get("inputSchema"), dict)):
            raise WebSearchError("Malformed or duplicate tool declaration")
        names.add(tool["name"])
        if _TOOL_NAME.fullmatch(tool["name"]):
            matches.append(tool)
    if len(matches) != 1:
        raise WebSearchError("Expected exactly one namespaced WebSearch tool")
    tool = matches[0]
    schema = tool["inputSchema"]
    properties = schema.get("properties")
    if (schema.get("type") != "object" or schema.get("required") != ["query"]
            or not isinstance(properties, dict)
            or set(properties) != {"query", "maxResults", "filters"}
            or any(not isinstance(properties[key], dict) or properties[key].get("type") != kind
                   for key, kind in (("query", "string"), ("maxResults", "integer"), ("filters", "object")))):
        raise WebSearchError("WebSearch schema does not expose the supported 1.2 contract")
    filters = properties["filters"]
    nested = filters.get("properties")
    if not isinstance(nested, dict) or set(nested) != {"domainFilter", "publishedDateFilter"}:
        raise WebSearchError("Unsupported nested filter schema")
    for name, children, leaf_type in (
        ("domainFilter", {"include", "exclude"}, "array"),
        ("publishedDateFilter", {"from", "to"}, "string"),
    ):
        node = nested[name]
        fields = node.get("properties") if isinstance(node, dict) else None
        if (not isinstance(node, dict) or node.get("type") != "object"
                or not isinstance(fields, dict) or set(fields) != children):
            raise WebSearchError("Unsupported nested filter schema")
        for field in fields.values():
            if not isinstance(field, dict) or field.get("type") != leaf_type:
                raise WebSearchError("Unsupported nested filter type")
            if leaf_type == "array" and field.get("items") != {"type": "string"}:
                raise WebSearchError("Unsupported domain-list item type")
    return copy.deepcopy(tool)


def _observations(result: dict[str, Any], maximum: int) -> list[dict[str, Any]]:
    if set(result) - {"isError", "content", "structuredContent"}:
        raise WebSearchError("Unexpected tool-result fields")
    if type(result.get("isError")) is not bool or result["isError"]:
        raise WebSearchError("WebSearch tool failed or omitted status")
    content = result.get("content")
    if (not isinstance(content, list) or len(content) != 1
            or not isinstance(content[0], dict) or set(content[0]) != {"type", "text"}
            or content[0]["type"] != "text" or not isinstance(content[0]["text"], str)):
        raise WebSearchError("Expected one serialized search-result text block")
    packet = _json(content[0]["text"])
    if (not isinstance(packet, dict) or set(packet) != {"id", "results"}
            or not isinstance(packet["id"], str) or not packet["id"]
            or not isinstance(packet["results"], list) or len(packet["results"]) > maximum):
        raise WebSearchError("Unexpected search-result schema or count")
    if "structuredContent" in result and _canonical(result["structuredContent"]) != _canonical(packet):
        raise WebSearchError("Structured/text result disagreement")
    for observation in packet["results"]:
        if (not isinstance(observation, dict)
                or set(observation) - {"text", "url", "title", "publishedDate"}
                or not isinstance(observation.get("text"), str) or not observation["text"].strip()
                or any(observation.get(key) is not None and not isinstance(observation[key], str)
                       for key in ("url", "title", "publishedDate"))):
            raise WebSearchError("Invalid external observation")
        # No source fetch occurs here. Null URL/title knowledge-graph results
        # remain explicit and cannot be mistaken for fetched page evidence.
    return copy.deepcopy(packet["results"])


class WebSourceSearchClient:
    """One discovery plus bounded searches; any dispatched failure closes it.

    Injectable signer(endpoint,region,body,headers)->headers and
    transport(endpoint,region,body,signed_headers,limits)->TransportResponse
    are trusted test/application dependencies, not model-supplied callbacks.
    """

    def __init__(self, endpoint: str, region: str, *, limits: SearchLimits | None = None,
                 signer: Callable[..., dict[str, str]] | None = None,
                 transport: Callable[..., TransportResponse] | None = None):
        self.endpoint = validate_endpoint(endpoint, region)
        self.region = region
        self.limits = limits or SearchLimits()
        if not isinstance(self.limits, SearchLimits):
            raise WebSearchError("Expected validated SearchLimits")
        self._signer = signer or _sigv4
        self._transport = transport or _https_transport
        self._tool: dict[str, Any] | None = None
        self._records: list[dict[str, Any]] = []
        self._failed = False
        self._searches = 0

    @property
    def records(self) -> list[dict[str, Any]]:
        """Unsigned request and raw response bindings; never signed headers."""
        return copy.deepcopy(self._records)

    def _exchange(self, method: str, params: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
        if self._failed:
            raise WebSearchError("Client stopped after previous failure; no retry")
        if (method == "tools/list" and (params or self._records)) or (
            method == "tools/call" and (
                self._tool is None or set(params) != {"name", "arguments"}
                or params["name"] != self._tool["name"]
            )
        ) or method not in {"tools/list", "tools/call"}:
            raise WebSearchError("Only one discovery and its WebSearch tool are supported")
        validate_endpoint(self.endpoint, self.region)
        request_id = str(uuid.uuid4())
        params = copy.deepcopy(params)
        params["_meta"] = {
            "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
            "io.modelcontextprotocol/clientInfo": {"name": "checkpoint-source-search", "version": "1"},
            "io.modelcontextprotocol/clientCapabilities": {},
        }
        request = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
        body = _canonical(request)
        if len(body) > self.limits.request_bytes:
            raise WebSearchError("Request exceeds byte limit")
        headers = {"Content-Type": "application/json", "Accept": "application/json",
                   "MCP-Protocol-Version": PROTOCOL_VERSION, "Mcp-Method": method}
        if method == "tools/call":
            headers["Mcp-Name"] = params["name"]
        record = {"endpoint": self.endpoint, "region": self.region, "request": request,
                  "request_body_sha256": _digest(body), "request_bytes": len(body),
                  "limits": asdict(self.limits), "transport_attempts": 0, "status": "prepared"}
        self._records.append(record)
        started = time.monotonic()
        try:
            signed = self._signer(self.endpoint, self.region, body, headers.copy())
            record["transport_attempts"] = 1
            response = self._transport(self.endpoint, self.region, body, signed, self.limits)
            if isinstance(response.body, bytes) and len(response.body) <= self.limits.response_bytes:
                record["response_body_sha256"] = _digest(response.body)
                record["response_body_base64"] = base64.b64encode(response.body).decode("ascii")
                record["response_bytes"] = len(response.body)
            result = _parse_response(response, request_id, self.limits.response_bytes)
            record["status"] = "received"
            return result, record
        except Exception as error:
            self._failed = True
            record.update(status="failed", error_type=type(error).__name__)
            # Provider/credential exceptions can contain request material. Keep
            # only their type in diagnostics, never forward arbitrary messages.
            raise WebSearchError("Managed search request failed; inspect bounded records") from None
        finally:
            record["elapsed_seconds"] = round(time.monotonic() - started, 6)

    def discover(self) -> dict[str, Any]:
        if self._records or self._tool is not None:
            raise WebSearchError("Discovery is allowed once")
        result, record = self._exchange("tools/list", {})
        try:
            self._tool = _discovered_tool(result)
        except WebSearchError:
            self._failed = True
            record["status"] = "rejected_response"
            raise
        record["status"] = "completed"
        return copy.deepcopy(self._tool)

    def search(self, query: str, *, max_results: int | None = None,
               filters: dict[str, Any] | None = None) -> dict[str, Any]:
        if self._tool is None or self._failed:
            raise WebSearchError("Successful discovery is required")
        if self._searches >= self.limits.maximum_searches:
            raise WebSearchError("Search-call limit reached")
        if not isinstance(query, str) or not query.strip() or len(query) > 200:
            raise WebSearchError("Expected nonempty query of at most 200 characters")
        count = self.limits.maximum_results if max_results is None else max_results
        if type(count) is not int or not 1 <= count <= self.limits.maximum_results:
            raise WebSearchError("Invalid maxResults")
        arguments = {"query": query, "maxResults": count}
        if filters is not None:
            arguments["filters"] = _validate_filters(filters)
        self._searches += 1
        result, record = self._exchange("tools/call", {"name": self._tool["name"], "arguments": arguments})
        try:
            observations = _observations(result, count)
        except WebSearchError:
            self._failed = True
            record["status"] = "rejected_response"
            raise
        record["status"] = "completed"
        return {"kind": "external_search_observations", "observations": observations,
                "request_binding": copy.deepcopy(record),
                "discovery_response_sha256": self._records[0]["response_body_sha256"],
                "scope": "Search snippets only; no full-page, verbatim-source, or truth certification."}


if __name__ == "__main__" and sys.argv[1:] == ["--https-transport"]:
    _child_transport()
