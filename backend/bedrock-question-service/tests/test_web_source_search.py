"""Offline fixtures only: no credentials, providers, searches, or real sockets."""

import base64
import io
import hashlib
import json
import subprocess
import unittest
from unittest.mock import Mock, patch

import web_source_search as search


ENDPOINT = "https://checkpoint-test-abcdefghij.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp"
TOOL = "checkpoint-source___WebSearch"


def tool():
    return {
        "name": TOOL,
        "description": "Managed search; descriptions are untrusted data.",
        "inputSchema": {
            "type": "object", "required": ["query"],
            "properties": {
                "query": {"type": "string"},
                "maxResults": {"type": "integer"},
                "filters": {"type": "object", "properties": {
                    "domainFilter": {"type": "object", "properties": {
                        "include": {"type": "array", "items": {"type": "string"}},
                        "exclude": {"type": "array", "items": {"type": "string"}},
                    }},
                    "publishedDateFilter": {"type": "object", "properties": {
                        "from": {"type": "string"}, "to": {"type": "string"},
                    }},
                }},
            },
        },
    }


def observations(rows=None):
    packet = {"id": "search-service-id", "results": rows if rows is not None else [{
        "text": "  Exact e\u0301 excerpt.\r\n    Preserve space.  ",
        "url": "https://example.org/rules", "title": " Rules ",
        "publishedDate": "2026-09-08",
    }]}
    return {"isError": False, "content": [{"type": "text", "text": json.dumps(packet, ensure_ascii=False)}]}


class FakeTransport:
    def __init__(self, *results):
        self.results = list(results)
        self.calls = []

    def __call__(self, endpoint, region, body, headers, limits):
        self.calls.append((endpoint, region, body, headers, limits))
        result = self.results.pop(0)
        if isinstance(result, Exception):
            raise result
        request = json.loads(body)
        if callable(result):
            return result(request)
        raw = json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}, ensure_ascii=False).encode()
        return search.TransportResponse(200, {"content-type": "application/json"}, raw)


def client(*results, limits=None):
    transport = FakeTransport({"tools": [tool()]}, *results)
    signer = Mock(side_effect=lambda endpoint, region, body, headers: {
        **headers, "Authorization": "SECRET_SIGNATURE", "X-Amz-Security-Token": "SECRET_TOKEN"
    })
    return search.WebSourceSearchClient(ENDPOINT, "us-east-1", transport=transport,
                                        signer=signer, limits=limits), transport, signer


class WebSourceSearchTests(unittest.TestCase):
    def test_exact_observations_discovery_and_unsigned_request_binding(self):
        raw_result = observations()
        c, transport, signer = client(raw_result)
        discovered = c.discover()
        discovered["name"] = "untrusted_mutation"
        filters = {"domainFilter": {"include": ["example.org"], "exclude": []},
                   "publishedDateFilter": {"from": "2026-01-01T00:00:00Z", "to": "2026-09-08T12:00:00Z"}}
        result = c.search("  original e\u0301 query  ", max_results=2, filters=filters)
        sent = json.loads(transport.calls[1][2])
        self.assertEqual(sent["method"], "tools/call")
        self.assertEqual(sent["params"]["name"], TOOL)
        self.assertEqual(sent["params"]["arguments"], {
            "query": "  original e\u0301 query  ", "maxResults": 2, "filters": filters,
        })
        self.assertEqual(result["observations"], json.loads(raw_result["content"][0]["text"])["results"])
        self.assertEqual(result["request_binding"]["request"], sent)
        self.assertEqual(result["request_binding"]["request_body_sha256"], hashlib.sha256(transport.calls[1][2]).hexdigest())
        response_bytes = base64.b64decode(result["request_binding"]["response_body_base64"])
        self.assertEqual(hashlib.sha256(response_bytes).hexdigest(), result["request_binding"]["response_body_sha256"])
        self.assertEqual([row["transport_attempts"] for row in c.records], [1, 1])
        self.assertEqual([row["status"] for row in c.records], ["completed", "completed"])
        self.assertNotIn("SECRET", json.dumps(result))
        self.assertNotIn("SECRET", json.dumps(c.records))
        self.assertEqual(signer.call_count, 2)
        self.assertEqual(transport.calls[0][3]["Mcp-Method"], "tools/list")
        self.assertEqual(transport.calls[1][3]["Mcp-Name"], TOOL)
        self.assertEqual(sent["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"], search.PROTOCOL_VERSION)
        records = c.records
        records[0]["status"] = "changed"
        self.assertEqual(c.records[0]["status"], "completed")

    def test_invalid_endpoint_is_rejected_before_signing(self):
        for endpoint, region in [
            (ENDPOINT.replace("https:", "http:"), "us-east-1"),
            (ENDPOINT + "?x=1", "us-east-1"), (ENDPOINT + "#x", "us-east-1"),
            (ENDPOINT.replace("/mcp", ":443/mcp"), "us-east-1"),
            (ENDPOINT.replace("https://", "https://user@"), "us-east-1"),
            (ENDPOINT.replace("amazonaws.com", "amazonaws.com.evil.test"), "us-east-1"),
            (ENDPOINT + "/", "us-east-1"), (ENDPOINT, "eu-west-1"),
            (ENDPOINT, "us-west-2"), (ENDPOINT + "\n", "us-east-1"),
        ]:
            with self.subTest(endpoint=endpoint, region=region), self.assertRaises(search.WebSearchError):
                search.WebSourceSearchClient(endpoint, region, signer=Mock())
        c, _, signer = client(observations())
        c.endpoint = "https://evil.test/mcp"
        with self.assertRaises(search.WebSearchError):
            c.discover()
        signer.assert_not_called()

    def test_requires_discovery_and_enforces_call_caps_without_transport(self):
        c, transport, _ = client(observations(), limits=search.SearchLimits(maximum_searches=1))
        with self.assertRaises(search.WebSearchError):
            c.search("query")
        c.discover()
        with self.assertRaises(search.WebSearchError):
            c.discover()
        c.search("query")
        with self.assertRaises(search.WebSearchError):
            c.search("query2")
        self.assertEqual(len(transport.calls), 2)

    def test_limits_strict_integer_bounds_and_query_character_bounds(self):
        for kwargs in ({"maximum_searches": True}, {"maximum_results": 26},
                       {"timeout_seconds": 0}, {"response_bytes": 1_048_577}):
            with self.subTest(kwargs=kwargs), self.assertRaises(search.WebSearchError):
                search.SearchLimits(**kwargs)
        c, transport, _ = client(observations())
        c.discover()
        for query, maximum in [("", 1), ("  ", 1), ("a" * 201, 1), ("q", True), ("q", 6), ("q", 0)]:
            with self.subTest(query=query, maximum=maximum), self.assertRaises(search.WebSearchError):
                c.search(query, max_results=maximum)
        c.search("é" * 200)
        self.assertEqual(len(transport.calls), 2)

    def test_filters_reject_unknown_fields_invalid_dates_and_domains(self):
        c, transport, _ = client()
        c.discover()
        for filters in [
            {"invented": []}, {"domainFilter": {"allow": ["example.org"]}},
            {"domainFilter": {"include": ["https://example.org"]}},
            {"domainFilter": {"include": ["example.org", "example.org"]}},
            {"domainFilter": {"include": ["EXAMPLE.org"]}},
            {"domainFilter": {"include": ["example.org"] * 101}},
            {"publishedDateFilter": {"from": "2026-02-30T00:00:00Z"}},
            {"publishedDateFilter": {"from": "2026-09-08T00:00:00+00:00"}},
            {"publishedDateFilter": {"from": "2026-09-08T00:00:00Z", "to": "2026-01-01T00:00:00Z"}},
        ]:
            with self.subTest(filters=filters), self.assertRaises(search.WebSearchError):
                c.search("query", filters=filters)
        self.assertEqual(len(transport.calls), 1)

    def test_discovery_rejects_paging_ambiguous_names_and_schema_changes(self):
        changed = tool()
        changed["inputSchema"]["properties"]["maxResults"]["type"] = "string"
        unnamed = tool()
        unnamed["name"] = "WebSearch"
        for result in [
            {"tools": [tool()], "nextCursor": "more"}, {"tools": []},
            {"tools": [tool(), tool()]}, {"tools": [unnamed]},
            {"tools": [changed]}, {"tools": [{"name": TOOL}]},
            {"tools": [tool(), {**tool(), "name": "another___WebSearch"}]},
        ]:
            with self.subTest(result=result):
                transport = FakeTransport(result)
                c = search.WebSourceSearchClient(ENDPOINT, "us-east-1", signer=lambda *args: args[-1], transport=transport)
                with self.assertRaises(search.WebSearchError):
                    c.discover()
                with self.assertRaises(search.WebSearchError):
                    c.search("query")
                self.assertEqual(len(transport.calls), 1)

    def test_strict_correlated_json_rejects_errors_requests_and_duplicate_keys(self):
        def reply(raw):
            return lambda req: search.TransportResponse(200, {"content-type": "application/json"}, raw(req).encode())
        variants = [
            reply(lambda req: '{"jsonrpc":"2.0","id":"wrong","result":{}}'),
            reply(lambda req: json.dumps({"jsonrpc": "2.0", "id": True, "result": {}})),
            reply(lambda req: json.dumps({"jsonrpc": "2.0", "id": req["id"], "error": {"code": -1}})),
            reply(lambda req: json.dumps({"jsonrpc": "2.0", "id": req["id"], "method": "sampling/createMessage"})),
            reply(lambda req: '{"jsonrpc":"2.0","id":"' + req['id'] + '","result":{},"result":{}}'),
            reply(lambda req: '[{"jsonrpc":"2.0","id":"' + req['id'] + '","result":{}}]'),
            reply(lambda req: '{"jsonrpc":"2.0","id":"' + req['id'] + '","result":{"value":NaN}}'),
        ]
        for variant in variants:
            with self.subTest(variant=variant):
                c, transport, _ = client(variant)
                c.discover()
                with self.assertRaises(search.WebSearchError):
                    c.search("query")
                with self.assertRaises(search.WebSearchError):
                    c.search("another query")
                self.assertEqual(len(transport.calls), 2)

    def test_json_and_single_bounded_sse_preserve_identical_observations(self):
        rows = [{"text": "Keep literal Unicode separators: \u2028\u0085\u2029", "url": None}]
        def sse(request):
            message = json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": observations(rows)}, ensure_ascii=False)
            return search.TransportResponse(200, {"content-type": "text/event-stream; charset=utf-8"},
                                            (": heartbeat\r\n\r\nevent: message\r\ndata: " + message + "\r\n\r\n").encode())
        c, _, _ = client(sse)
        c.discover()
        self.assertEqual(c.search("query")["observations"], rows)

    def test_sse_rejects_extra_progress_continuation_and_incomplete_events(self):
        for prefix, suffix in [
            ('data: {"jsonrpc":"2.0","method":"notifications/progress"}\n\n', ''),
            ('id: resumable-event\n', ''), ('retry: 10\n', ''),
            ('event: tool-result\n', ''), ('', '\ndata: {}\n\n'),
        ]:
            def sse(request):
                msg = json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": observations()})
                return search.TransportResponse(200, {"content-type": "text/event-stream"}, (prefix + 'data: ' + msg + '\n\n' + suffix).encode())
            with self.subTest(prefix=prefix, suffix=suffix):
                c, _, _ = client(sse)
                c.discover()
                with self.assertRaises(search.WebSearchError):
                    c.search("query")
        for ending in ("", "\n"):
            def incomplete(request):
                msg = json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": observations()})
                return search.TransportResponse(200, {"content-type": "text/event-stream"}, ("data: " + msg + ending).encode())
            with self.subTest(ending=ending):
                c, _, _ = client(incomplete)
                c.discover()
                with self.assertRaises(search.WebSearchError):
                    c.search("query")

    def test_cannot_dispatch_undiscovered_tools_or_general_mcp_operations(self):
        c, transport, signer = client()
        for method, params in [("initialize", {}), ("sampling/createMessage", {}),
                               ("tools/call", {"name": TOOL, "arguments": {}})]:
            with self.subTest(method=method), self.assertRaises(search.WebSearchError):
                c._exchange(method, params)
        signer.assert_not_called()
        c.discover()
        with self.assertRaises(search.WebSearchError):
            c._exchange("tools/call", {"name": "other___WebSearch", "arguments": {"query": "x"}})
        self.assertEqual(len(transport.calls), 1)

    def test_tool_status_schema_duplicates_and_structured_content_must_match(self):
        structured_mismatch = observations()
        structured_mismatch["structuredContent"] = {"id": "different", "results": []}
        duplicate_inner = observations()
        duplicate_inner["content"][0]["text"] = '{"id":"x","results":[],"results":[]}'
        variants = [
            {**observations(), "isError": True}, {**observations(), "isError": 0},
            {"content": observations()["content"]},
            {**observations(), "nextCursor": "more"}, structured_mismatch, duplicate_inner,
            {"isError": False, "content": [{"type": "resource_link", "uri": "https://x.test"}]},
            observations([{"text": "excerpt", "invented": "field"}]),
            observations([{"text": "excerpt", "url": True}]),
            observations([{"text": " "}]), observations([{"text": "x"}] * 6),
        ]
        for variant in variants:
            with self.subTest(variant=variant):
                c, _, _ = client(variant)
                c.discover()
                with self.assertRaises(search.WebSearchError):
                    c.search("query")
                self.assertEqual(c.records[-1]["status"], "rejected_response")

    def test_null_metadata_empty_results_and_matching_structured_packet_are_preserved(self):
        item = {"text": "Graph observation", "url": None, "title": None}
        payload = observations([item])
        payload["structuredContent"] = json.loads(payload["content"][0]["text"])
        c, _, _ = client(payload, observations([]))
        c.discover()
        self.assertEqual(c.search("q")["observations"], [item])
        self.assertEqual(c.search("q")["observations"], [])

    def test_transport_failure_http_redirect_oversize_and_encoding_fail_once(self):
        for response in [
            TimeoutError("failure"),
            lambda _: search.TransportResponse(302, {"location": "https://evil.test"}, b""),
            lambda _: search.TransportResponse(200, {"content-type": "application/json"}, b"x" * 131_073),
            lambda _: search.TransportResponse(200, {"content-type": "application/json"}, b"\xff"),
            lambda _: search.TransportResponse(200, {"content-type": "application/json", "content-encoding": "gzip"}, b"{}"),
            lambda _: search.TransportResponse(200, {"content-type": "application/json", "mcp-session-id": "session"}, b"{}"),
        ]:
            with self.subTest(response=response):
                c, transport, _ = client(response)
                c.discover()
                with self.assertRaises(search.WebSearchError):
                    c.search("query")
                self.assertEqual(c.records[-1]["transport_attempts"], 1)
                with self.assertRaises(search.WebSearchError):
                    c.search("query")
                self.assertEqual(len(transport.calls), 2)

    def test_signer_failure_is_zero_transport_attempts_and_never_records_secrets(self):
        c, transport, signer = client()
        signer.side_effect = RuntimeError("PRIVATE_CREDENTIAL_VALUE")
        with self.assertRaises(search.WebSearchError) as raised:
            c.discover()
        self.assertEqual(transport.calls, [])
        self.assertEqual(c.records[0]["transport_attempts"], 0)
        self.assertNotIn("PRIVATE", json.dumps(c.records))
        self.assertTrue(raised.exception.__suppress_context__)

    def test_trusted_child_sends_once_and_never_follows_redirects(self):
        packet = {"endpoint": ENDPOINT, "region": "us-east-1", "body": "e30=",
                  "headers": {"Authorization": "SECRET"}, "maximum_bytes": 1024,
                  "timeout_seconds": 15}
        connection = Mock()
        response = connection.getresponse.return_value
        response.status = 302
        response.read.return_value = b"redirect response"
        response.getheaders.return_value = [("Location", "https://evil.test"),
                                            ("Content-Type", "application/json")]
        output = io.BytesIO()
        with patch.object(search.sys, "stdin", Mock(buffer=io.BytesIO(json.dumps(packet).encode()))), \
                patch.object(search.sys, "stdout", Mock(buffer=output)), \
                patch.object(search.http.client, "HTTPSConnection", return_value=connection) as connect:
            search._child_transport()
        connect.assert_called_once_with("checkpoint-test-abcdefghij.gateway.bedrock-agentcore.us-east-1.amazonaws.com", timeout=15)
        connection.request.assert_called_once_with("POST", "/mcp", body=b"{}", headers={"Authorization": "SECRET"})
        connection.close.assert_called_once()
        result = json.loads(output.getvalue())
        self.assertEqual(result["status"], 302)
        self.assertNotIn("SECRET", output.getvalue().decode())
        self.assertNotIn("location", result["headers"])

    def test_trusted_child_body_overflow_returns_only_error_type(self):
        packet = {"endpoint": ENDPOINT, "region": "us-east-1", "body": "e30=",
                  "headers": {}, "maximum_bytes": 4, "timeout_seconds": 15}
        connection = Mock()
        connection.getresponse.return_value.read.return_value = b"12345"
        output = io.BytesIO()
        with patch.object(search.sys, "stdin", Mock(buffer=io.BytesIO(json.dumps(packet).encode()))), \
                patch.object(search.sys, "stdout", Mock(buffer=output)), \
                patch.object(search.http.client, "HTTPSConnection", return_value=connection):
            search._child_transport()
        self.assertEqual(json.loads(output.getvalue()), {"error_type": "WebSearchError"})
        connection.close.assert_called_once()

    def test_default_transport_uses_only_pipe_for_signed_headers_no_proxy_env(self):
        child = Mock(returncode=0)
        child.communicate.return_value = (json.dumps({"status": 200, "headers": {"content-type": "application/json"},
                                                     "body": base64.b64encode(b"{}").decode()}).encode(), None)
        with patch.object(search.subprocess, "Popen", return_value=child) as spawn:
            response = search._https_transport(ENDPOINT, "us-east-1", b"{}", {"Authorization": "PRIVATE"}, search.SearchLimits())
        self.assertEqual(response.body, b"{}")
        self.assertNotIn("PRIVATE", str(spawn.call_args))
        self.assertEqual(set(spawn.call_args.kwargs["env"]), {"PATH"})
        self.assertIn(b"PRIVATE", child.communicate.call_args.args[0])
        self.assertEqual(child.communicate.call_args.kwargs["timeout"], 15)

    def test_default_transport_timeout_kills_and_confirms_child_reaped(self):
        child = Mock(returncode=-9)
        child.communicate.side_effect = [subprocess.TimeoutExpired("child", 15), (b"", None)]
        with patch.object(search.subprocess, "Popen", return_value=child), self.assertRaisesRegex(search.WebSearchError, "deadline"):
            search._https_transport(ENDPOINT, "us-east-1", b"{}", {}, search.SearchLimits())
        child.kill.assert_called_once()
        self.assertEqual(child.communicate.call_count, 2)


if __name__ == "__main__":
    unittest.main()
