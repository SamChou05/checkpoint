import hashlib
import json
import os
import socket
import ssl
import unittest
from unittest.mock import Mock, patch

import source_acquisition as source


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


class WireSocket:
    """Inert TLS-transport seam: real http.client parsing, no network socket."""
    def __init__(self, data, *, clock=None, read_delay=0, chunk_size=8192):
        self.data = bytearray(data)
        self.clock, self.read_delay, self.chunk_size = clock, read_delay, chunk_size
        self.sent, self.timeouts, self.connected, self.closed = [], [], None, False

    def settimeout(self, timeout):
        if self.closed:
            raise OSError("Synthetic socket is closed")
        self.timeouts.append(timeout)

    def connect(self, address):
        self.connected = address

    def sendall(self, data):
        if self.closed:
            raise OSError("Synthetic socket is closed")
        self.sent.append(data)

    def recv_into(self, buffer):
        if self.closed:
            raise OSError("Synthetic socket is closed")
        if self.clock:
            self.clock.now += self.read_delay
        count = min(len(buffer), len(self.data), self.chunk_size)
        buffer[:count] = self.data[:count]
        del self.data[:count]
        return count

    def close(self):
        self.closed = True


def public(ip="93.184.216.34"):
    family = socket.AF_INET6 if ":" in ip else socket.AF_INET
    return [(family, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", (ip, 443))]


def reply(body=b"A public document.", *, status=200, mime="text/plain; charset=utf-8",
          headers=(), length=True):
    pairs = [("Content-Type", mime), *headers]
    if length:
        pairs.append(("Content-Length", str(len(body))))
    return (f"HTTP/1.1 {status} Response\r\n" + "".join(f"{k}: {v}\r\n" for k, v in pairs)
            + "\r\n").encode() + body


class SourceAcquisitionTests(unittest.TestCase):
    def fetch(self, responses, *, url="https://example.test/page#part", resolver=None,
              limits=None, clock=None):
        clock = clock or Clock()
        wires = [r if isinstance(r, WireSocket) else WireSocket(r) for r in responses]
        tls = Mock()
        tls.wrap_socket.side_effect = lambda raw, **_kwargs: raw
        resolver = resolver or Mock(return_value=public())
        with patch.object(source.socket, "socket", side_effect=wires) as sockets, \
             patch.object(source.ssl, "create_default_context", return_value=tls):
            result = source.acquire_source(url, resolver=resolver, limits=limits, clock=clock)
        return result, wires, resolver, tls, sockets

    def assert_failed_without_text(self, result):
        self.assertEqual(result["status"], "failed")
        self.assertIsNone(result["source_text"])
        self.assertIsNone(result["text_sha256"])
        self.assertEqual(result["verification"], "unverified_source_material")

    def test_real_http_parser_preserves_plain_unicode_and_literal_whitespace(self):
        text = '\ufeffé e\u0301\r\n    x = "a  b"\t \n'
        body = text.encode()
        result, wires, _, tls, _ = self.fetch([reply(body)])
        self.assertEqual(result["status"], "acquired")
        self.assertEqual(result["source_text"].encode(), body)
        self.assertEqual(result["raw_content_sha256"], hashlib.sha256(body).hexdigest())
        self.assertEqual(result["text_sha256"], hashlib.sha256(body).hexdigest())
        self.assertEqual(result["requested_url"], "https://example.test/page#part")
        self.assertEqual(result["request_fragment"], "part")
        self.assertEqual(result["final_url"], "https://example.test/page")
        self.assertTrue(result["source_text_complete"])
        self.assertFalse(result["truncated"])
        self.assertIn("retrieved_at_utc", result)
        sent = b"".join(wires[0].sent)
        self.assertIn(b"GET /page HTTP/1.1", sent)
        self.assertNotIn(b"#part", sent)
        self.assertIn(b"Host: example.test", sent)
        tls.wrap_socket.assert_called_once_with(wires[0], server_hostname="example.test")
        self.assertTrue(wires[0].closed)

    def test_redirects_resolve_each_host_and_never_forward_cookie_auth_or_proxy(self):
        resolver = Mock(side_effect=[public(), public("1.1.1.1")])
        with patch.dict(os.environ, {"HTTPS_PROXY": "https://user:secret@127.0.0.1:1234", "HTTP_PROXY": "http://127.0.0.1"}):
            result, wires, _, tls, _ = self.fetch([
                reply(status=302, headers=[("Location", "https://second.test/next?q=1#new"), ("Set-Cookie", "private=secret")]),
                reply(b"Final page"),
            ], resolver=resolver)
        self.assertEqual(result["status"], "acquired")
        self.assertEqual([c.args[0] for c in resolver.call_args_list], ["example.test", "second.test"])
        self.assertEqual([w.connected for w in wires], [("93.184.216.34", 443), ("1.1.1.1", 443)])
        self.assertEqual([c.kwargs["server_hostname"] for c in tls.wrap_socket.call_args_list], ["example.test", "second.test"])
        self.assertEqual(result["final_url"], "https://second.test/next?q=1")
        for wire in wires:
            sent = b"".join(wire.sent).lower()
            for forbidden in (b"cookie", b"authorization", b"private", b"proxy", b"secret", b"referer"):
                self.assertNotIn(forbidden, sent)
            self.assertTrue(wire.closed)

    def test_connection_close_body_remains_readable_until_response_releases_reader(self):
        for status, mime, expected in ((200, "text/plain", "acquired"),
                                       (200, "application/pdf", "failed"), (500, "text/plain", "failed")):
            with self.subTest(status=status, mime=mime):
                body = b"Exact body after the connection owner closes."
                wire = WireSocket(reply(body, status=status, mime=mime, headers=[("Connection", "close")]), chunk_size=3)
                result, _, _, _, _ = self.fetch([wire])
                self.assertEqual(result["status"], expected)
                if expected == "acquired":
                    self.assertEqual(result["source_text"], body.decode())
                    self.assertEqual(result["raw_content_sha256"], hashlib.sha256(body).hexdigest())
                self.assertTrue(wire.closed, "Response and connection ownership must both be released.")
        result, wires, _, _, _ = self.fetch([
            reply(status=302, headers=[("Location", "/next"), ("Connection", "close")]),
            reply(b"final", headers=[("Connection", "close")]),
        ])
        self.assertEqual(result["source_text"], "final")
        self.assertTrue(all(w.closed for w in wires))

    def test_dns_rebinding_cannot_resolve_again_between_validation_and_connect(self):
        resolver = Mock(side_effect=[public(), public("127.0.0.1")])
        result, wires, _, _, _ = self.fetch([reply()], resolver=resolver)
        self.assertEqual(result["status"], "acquired")
        resolver.assert_called_once_with("example.test", 443, type=socket.SOCK_STREAM, proto=socket.IPPROTO_TCP)
        self.assertEqual(wires[0].connected, ("93.184.216.34", 443))
        self.assertEqual(result["trace"][0]["pinned_address"], "93.184.216.34")

    def test_private_and_mixed_dns_answers_reject_before_any_connect(self):
        for ips in (("127.0.0.1",), ("10.0.0.1",), ("169.254.169.254",), ("::1",),
                    ("fc00::1",), ("224.0.0.1",), ("93.184.216.34", "192.168.1.1")):
            with self.subTest(ips=ips):
                answers = [entry for ip in ips for entry in public(ip)]
                result, _, _, _, factory = self.fetch([], resolver=Mock(return_value=answers))
                self.assert_failed_without_text(result)
                self.assertEqual(result["failure_reason"], "nonpublic_address")
                factory.assert_not_called()

    def test_private_redirect_and_https_credentials_port_rules_are_enforced(self):
        for url in ("http://example.test", "https://user:secret@example.test", "https://example.test:8443", "https://example.test/\nother"):
            with self.subTest(url=url):
                result, _, resolver, _, factory = self.fetch([], url=url)
                self.assert_failed_without_text(result)
                resolver.assert_not_called()
                factory.assert_not_called()
                self.assertNotIn("secret", json.dumps(result))
        for target in ("http://second.test", "https://127.0.0.1/internal", "https://user:secret@second.test", "https://[::1]/"):
            with self.subTest(target=target):
                result, wires, _, _, factory = self.fetch([reply(status=302, headers=[("Location", target)])])
                self.assert_failed_without_text(result)
                self.assertEqual(factory.call_count, 1)
                self.assertTrue(wires[0].closed)
                self.assertNotIn("secret", json.dumps(result))

    def test_redirect_hop_limit_loop_and_relative_resolution(self):
        result, _, _, _, _ = self.fetch([reply(status=302, headers=[("Location", "../done")]), reply()], url="https://example.test/a/b")
        self.assertEqual(result["final_url"], "https://example.test/done")
        for location, limits, reason in (("/page", None, "redirect_loop"),
                ("/next", source.SourceAcquisitionLimits(redirects=0), "redirect_limit_or_missing_location")):
            result, _, _, _, _ = self.fetch([reply(status=302, headers=[("Location", location)])], limits=limits)
            self.assert_failed_without_text(result)
            self.assertEqual(result["failure_reason"], reason)

    def test_tls_uses_the_normal_hostname_verifying_context(self):
        connection = source._PinnedHTTPSConnection("example.test", (socket.AF_INET, "93.184.216.34"), 30, source.SourceAcquisitionLimits(), Clock())
        self.assertTrue(connection._context.check_hostname)
        self.assertEqual(connection._context.verify_mode, ssl.CERT_REQUIRED)
        connection.close()
        wire = WireSocket(reply())
        with patch.object(source.socket, "socket", return_value=wire), \
             patch.object(source.ssl, "create_default_context") as factory:
            factory.return_value.wrap_socket.side_effect = ssl.SSLCertVerificationError("secret certificate detail")
            result = source.acquire_source("https://example.test", resolver=Mock(return_value=public()), clock=Clock())
        self.assert_failed_without_text(result)
        self.assertTrue(wire.closed)
        self.assertNotIn("secret certificate", json.dumps(result))

    def test_html_omits_inactive_content_and_preserves_pre_tables_and_unicode(self):
        html = '<html><head><title>OMIT</title><style>OMIT</style></head><body><p>Café &amp; tea</p><pre>if True:\n    print("a  b")\n</pre><table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table><script>OMIT</script><template>OMIT</template><noscript>OMIT</noscript><p hidden>OMIT</p><p>e\u0301</p></body></html>'
        result, _, _, _, _ = self.fetch([reply(html.encode(), mime="text/html; charset=utf-8")])
        self.assertEqual(result["source_text"], 'Café & tea\nif True:\n    print("a  b")\nA\tB\n1\t2\ne\u0301\n')
        self.assertNotIn("OMIT", result["source_text"])
        self.assertTrue(any("not browser rendering" in x for x in result["representation_limits"]))
        self.assertEqual(result["raw_content_sha256"], hashlib.sha256(html.encode()).hexdigest())
        self.assertEqual(result["text_sha256"], hashlib.sha256(result["source_text"].encode()).hexdigest())

    def test_extracted_prefix_truncation_is_explicit_and_raw_hash_is_complete(self):
        for mime, body in (("text/plain", 'é e\u0301  spaced\n'.encode()), ("text/html", b"<p>first</p><pre>  second\n</pre>")):
            with self.subTest(mime=mime):
                complete, _, _, _, _ = self.fetch([reply(body, mime=mime)])
                short, _, _, _, _ = self.fetch([reply(body, mime=mime)], limits=source.SourceAcquisitionLimits(text_characters=5))
                self.assertEqual(short["source_text"], complete["source_text"][:5])
                self.assertTrue(short["truncated"])
                self.assertFalse(short["source_text_complete"])
                self.assertEqual(short["raw_content_sha256"], complete["raw_content_sha256"])
                self.assertNotEqual(short["text_sha256"], complete["text_sha256"])

    def test_supported_charsets_and_bad_decode_never_silently_replace_characters(self):
        for body, mime, expected, charset in (
            (b'<meta charset="windows-1252"><p>\x80</p>', "text/html", "€\n", "cp1252"),
            (b"<p>\x80</p>", "text/html; charset=iso-8859-1", "€\n", "cp1252"),
            (b"\x80", "text/plain; charset=iso-8859-1", "\x80", "iso8859-1"),
            ("literal  text".encode("utf-16"), "text/plain; charset=utf-16", "literal  text", "utf-16"),
        ):
            result, _, _, _, _ = self.fetch([reply(body, mime=mime)])
            self.assertEqual(result["source_text"], expected)
            self.assertEqual(result["charset"], charset)
        for body, mime in ((b"\xff", "text/plain; charset=utf-8"), (b"\\u0041", "text/plain; charset=unicode_escape")):
            result, _, _, _, _ = self.fetch([reply(body, mime=mime)])
            self.assert_failed_without_text(result)
            self.assertIsNotNone(result["raw_content_sha256"], "Full body retrieval is distinct from failed text decoding.")

    def test_unsupported_media_compression_and_partial_status_are_not_evidence(self):
        for mime, headers, status in (("application/pdf", (), 200), ("not-a-type", (), 200),
                ("text/html", [("Content-Encoding", "gzip")], 200),
                ("text/plain", [("Content-Encoding", "br")], 200), ("text/plain", (), 206)):
            with self.subTest(mime=mime, headers=headers, status=status):
                result, _, _, _, _ = self.fetch([reply(mime=mime, headers=headers, status=status)])
                self.assert_failed_without_text(result)
                self.assertIsNone(result["raw_content_sha256"])

    def test_oversized_and_incomplete_bodies_never_become_text_evidence(self):
        limits = source.SourceAcquisitionLimits(body_bytes=16)
        for wire in (reply(b"x" * 17), reply(b"x" * 17, length=False),
                     reply(b"short", headers=[("Content-Length", "12")], length=False)):
            result, _, _, _, _ = self.fetch([wire], limits=limits)
            self.assert_failed_without_text(result)
            self.assertIsNone(result["raw_content_sha256"])
        for headers in ([('Content-Length', '5'), ('Content-Length', '5')],
                        [('Content-Length', '5'), ('Transfer-Encoding', 'chunked')]):
            result, _, _, _, _ = self.fetch([reply(b"short", headers=headers, length=False)])
            self.assert_failed_without_text(result)

    def test_chunked_hash_is_entity_body_and_truncated_chunk_is_failure(self):
        for body, success in ((b"2\r\nhi\r\n0\r\n\r\n", True), (b"5\r\nhi", False),
                              (b"2\r\nhi\r\n0", False), (b"2\r\nhi\r\n0\r\n", False),
                              (b"2\r\nhi\r\n0\r\nX-Trace: final\r\n", False),
                              (b"2\r\nhi\r\n0\r\nX-Trace: final\r\n\r\n", True)):
            result, _, _, _, _ = self.fetch([reply(body, headers=[("Transfer-Encoding", "chunked")], length=False)])
            if success:
                self.assertEqual(result["source_text"], "hi")
                self.assertEqual(result["raw_content_sha256"], hashlib.sha256(b"hi").hexdigest())
            else:
                self.assert_failed_without_text(result)
                self.assertIsNone(result["raw_content_sha256"])

    def test_total_deadline_bounds_trickling_headers_not_just_each_read(self):
        clock = Clock()
        wire = WireSocket(reply(), clock=clock, read_delay=0.6, chunk_size=1)
        result, _, _, _, _ = self.fetch([wire], clock=clock,
            limits=source.SourceAcquisitionLimits(socket_seconds=1, io_seconds=2))
        self.assert_failed_without_text(result)
        self.assertEqual(result["failure_reason"], "io_deadline")
        self.assertAlmostEqual(result["elapsed_seconds"], 2.4)
        self.assertLess(wire.timeouts[-1], 0.21)
        self.assertTrue(wire.closed)

    def test_overdue_blocking_dns_is_reported_honestly_and_never_connects(self):
        clock = Clock()

        def slow_dns(*_args, **_kwargs):
            clock.now = 6
            return public()

        result, _, _, _, factory = self.fetch([], resolver=slow_dns, clock=clock,
            limits=source.SourceAcquisitionLimits(io_seconds=5))
        self.assert_failed_without_text(result)
        self.assertEqual(result["failure_reason"], "io_deadline")
        self.assertEqual(result["elapsed_seconds"], 6)
        self.assertIn("cannot be interrupted", result["deadline_scope"])
        factory.assert_not_called()

    def test_limits_and_empty_script_only_document(self):
        for kwargs in ({"body_bytes":True}, {"body_bytes":1_048_577}, {"redirects":5},
                       {"io_seconds":float("inf")}, {"socket_seconds":0}):
            with self.assertRaises(ValueError):
                source.SourceAcquisitionLimits(**kwargs)
        result, _, _, _, _ = self.fetch([reply(b"<script>only code</script>", mime="text/html")])
        self.assert_failed_without_text(result)
        self.assertEqual(result["failure_reason"], "no_extracted_text")
        result, _, _, _, _ = self.fetch([reply(b"<meta http-equiv><p>ordinary text</p>", mime="text/html")])
        self.assertEqual(result["source_text"], "ordinary text\n")
        result, _, _, _, _ = self.fetch([reply(b"<![not-valid]><p>text</p>", mime="text/html")])
        self.assert_failed_without_text(result)
        self.assertEqual(result["failure_reason"], "html_parse_failed")


if __name__ == "__main__":
    unittest.main()
