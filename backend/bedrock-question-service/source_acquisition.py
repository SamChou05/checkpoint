"""Bounded public HTTPS source capture, not factual or authority verification.

No model, browser, proxy, cookie jar, summary or credential handling is involved.
Blocking platform DNS cannot be interrupted here: its time counts toward the
budget and an overdue return fails, but DNS itself has no hard wall-time bound.
"""

from __future__ import annotations

import codecs
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from email.message import Message
import hashlib
from html.parser import HTMLParser
import http.client
import io
import ipaddress
import math
import socket
import ssl
import time
from urllib.parse import quote, urljoin, urlsplit, urlunsplit


@dataclass(frozen=True)
class SourceAcquisitionLimits:
    body_bytes: int = 1_048_576
    text_characters: int = 120_000
    redirects: int = 4
    socket_seconds: float = 10.0
    io_seconds: float = 30.0

    def __post_init__(self):
        for value, lower, upper in (
            (self.body_bytes, 1, 1_048_576), (self.text_characters, 1, 120_000),
            (self.redirects, 0, 4),
        ):
            if type(value) is not int or not lower <= value <= upper:
                raise ValueError("Invalid source acquisition size limit.")
        for value, upper in ((self.socket_seconds, 10), (self.io_seconds, 30)):
            if type(value) not in (int, float) or not math.isfinite(value) or not 0 < value <= upper:
                raise ValueError("Invalid source acquisition time limit.")


class _Failure(Exception):
    pass


def _remaining(deadline, wait, clock):
    left = deadline - clock()
    if left <= 0:
        raise _Failure("io_deadline")
    return min(wait, left)


def _url(value):
    if type(value) is not str or len(value) > 4096 or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in value):
        raise _Failure("invalid_url")
    try:
        parsed = urlsplit(value)
        if parsed.scheme.lower() != "https" or not parsed.hostname:
            raise _Failure("https_required")
        if parsed.username is not None or parsed.password is not None:
            raise _Failure("url_credentials_forbidden")
        if parsed.port not in (None, 443):
            raise _Failure("https_port_443_required")
        host = parsed.hostname.encode("idna").decode("ascii").lower()
        if "%" in host or not host or len(host) > 253:
            raise _Failure("invalid_hostname")
        authority = f"[{host}]" if ":" in host else host
        path = quote(parsed.path or "/", safe="/%:@!$&'()*+,;=-._~")
        query = quote(parsed.query, safe="/%?:@!$&'()*+,;=-._~")
        transport = urlunsplit(("https", authority, path, query, ""))
        return host, transport, path + ("?" + query if query else ""), parsed.fragment
    except (ValueError, UnicodeError) as error:
        raise _Failure("invalid_url") from error


def _public_addresses(host, resolver):
    try:
        literal = ipaddress.ip_address(host)
    except ValueError:
        answers = resolver(host, 443, type=socket.SOCK_STREAM, proto=socket.IPPROTO_TCP)
    else:
        family = socket.AF_INET6 if literal.version == 6 else socket.AF_INET
        answers = [(family, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", (host, 443))]
    if not answers or len(answers) > 16:
        raise _Failure("dns_answer_count")
    addresses = []
    for family, kind, proto, _, sockaddr in answers:
        if family not in (socket.AF_INET, socket.AF_INET6) or kind != socket.SOCK_STREAM:
            raise _Failure("unsupported_dns_answer")
        address = ipaddress.ip_address(sockaddr[0])
        if not address.is_global or any((address.is_private, address.is_loopback,
                address.is_link_local, address.is_multicast, address.is_reserved,
                address.is_unspecified)):
            raise _Failure("nonpublic_address")
        normalized = (family, str(address))
        if normalized not in addresses:
            addresses.append(normalized)
    return addresses


class _DeadlineReader(io.RawIOBase):
    def __init__(self, stream):
        self.stream = stream

    def readable(self):
        return True

    def readinto(self, buffer):
        stream = self.stream
        stream.set_wait()
        size = min(len(buffer), stream.maximum_bytes - stream.received + 1)
        count = stream.socket.recv_into(memoryview(buffer)[:size])
        stream.received += count
        if stream.received > stream.maximum_bytes:
            raise _Failure("http_response_byte_limit")
        stream.set_wait()
        return count

    def close(self):
        if not self.closed:
            super().close()
            self.stream.release_reader()


class _DeadlineSocket:
    def __init__(self, sock, deadline, limits, clock):
        self.socket, self.deadline, self.limits, self.clock = sock, deadline, limits, clock
        self.received = 0
        self.readers, self.owner_closed = 0, False
        # Includes HTTP headers/chunk framing; TLS framing is below this layer.
        self.maximum_bytes = limits.body_bytes + 65_536

    def set_wait(self):
        self.socket.settimeout(_remaining(self.deadline, self.limits.socket_seconds, self.clock))

    def sendall(self, data):
        self.set_wait()
        self.socket.sendall(data)
        self.set_wait()

    def makefile(self, mode):
        if mode != "rb":
            raise ValueError("Only response reads are supported.")
        if self.owner_closed:
            raise OSError("Socket owner already closed.")
        self.readers += 1
        return io.BufferedReader(_DeadlineReader(self))

    def close(self):
        self.owner_closed = True
        if not self.readers:
            self.socket.close()

    def release_reader(self):
        self.readers -= 1
        if self.owner_closed and not self.readers:
            self.socket.close()


class _CompleteHTTPResponse(http.client.HTTPResponse):
    def _read_and_discard_trailer(self):
        # http.client tolerates EOF here. This adapter must not turn a missing
        # final chunk/trailer terminator into a complete source observation.
        while True:
            line = self.fp.readline(65_537)
            if len(line) > 65_536 or not line.endswith(b"\r\n"):
                raise _Failure("incomplete_chunk_trailer")
            if line == b"\r\n":
                return


class _PinnedHTTPSConnection(http.client.HTTPSConnection):
    response_class = _CompleteHTTPResponse

    def __init__(self, host, address, deadline, limits, clock):
        super().__init__(host, port=443, context=ssl.create_default_context())
        self.address, self.deadline, self.limits, self.clock = address, deadline, limits, clock

    def connect(self):
        family, ip = self.address
        raw = socket.socket(family, socket.SOCK_STREAM)
        try:
            raw.settimeout(_remaining(self.deadline, self.limits.socket_seconds, self.clock))
            # No hostname is resolved a second time at connect. TLS still checks
            # the requested hostname using the normal trusted CA context.
            raw.connect((ip, 443, 0, 0) if family == socket.AF_INET6 else (ip, 443))
            raw.settimeout(_remaining(self.deadline, self.limits.socket_seconds, self.clock))
            secured = self._context.wrap_socket(raw, server_hostname=self.host)
            self.sock = _DeadlineSocket(secured, self.deadline, self.limits, self.clock)
            self.sock.set_wait()
        except BaseException:
            raw.close()
            raise


_BLOCKS = frozenset("address article aside blockquote dd div dl dt fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre section table ul".split())
_OMIT = frozenset({"head", "script", "style", "template", "noscript"})
_VOID = frozenset("area base br col embed hr img input link meta param source track wbr".split())
_HEAD_CONTENT = frozenset({"base", "link", "meta", "title", "noscript", "noframes",
                           "script", "style", "template"})


class _HTMLText(HTMLParser):
    def __init__(self, maximum):
        super().__init__(convert_charrefs=True)
        self.maximum, self.parts, self.length, self.truncated = maximum, [], 0, False
        self.ignored, self.rows = [], []
        self.last = ""

    def append(self, value):
        if not value:
            return
        retained = value[:max(0, self.maximum - self.length)]
        if retained:
            self.parts.append(retained)
        self.length += len(retained)
        self.truncated |= len(retained) != len(value)
        self.last = value[-1]

    def boundary(self):
        if self.last and self.last != "\n":
            self.append("\n")

    def handle_starttag(self, tag, attrs):
        tag = tag.rsplit(":", 1)[-1]
        # HTML permits </head> and <body> to be omitted. HTMLParser reports
        # tokens rather than repairing the DOM, so recognize the ordinary body
        # boundary ourselves. Do not escape nested inert head content: a body
        # tag inside a template/noscript element is still ignored.
        if self.ignored == ["head"] and tag not in _HEAD_CONTENT:
            self.ignored.clear()
        if self.ignored or tag in _OMIT or any(k == "hidden" for k, _ in attrs):
            if tag not in _VOID:
                self.ignored.append(tag)
            return
        if tag in _BLOCKS:
            self.boundary()
        elif tag == "br":
            self.append("\n")
        elif tag == "tr":
            self.boundary()
            self.rows.append(0)
        elif tag in ("td", "th") and self.rows:
            if self.rows[-1]:
                self.append("\t")
            self.rows[-1] += 1

    def handle_endtag(self, tag):
        tag = tag.rsplit(":", 1)[-1]
        if self.ignored:
            if tag in self.ignored:
                self.ignored = self.ignored[:len(self.ignored) - 1 - self.ignored[::-1].index(tag)]
            return
        if tag in _BLOCKS or tag == "tr":
            self.boundary()
        if tag == "tr" and self.rows:
            self.rows.pop()

    def handle_data(self, data):
        if self.ignored == ["head"] and data.strip():
            self.ignored.clear()
        if not self.ignored:
            self.append(data)


class _MetaCharset(HTMLParser):
    def __init__(self):
        super().__init__()
        self.charset = None

    def handle_starttag(self, tag, attrs):
        if tag != "meta" or self.charset:
            return
        attrs = dict(attrs)
        if attrs.get("charset"):
            self.charset = attrs["charset"]
        elif (attrs.get("http-equiv") or "").lower() == "content-type":
            header = Message()
            header["content-type"] = attrs.get("content") or ""
            self.charset = header.get_content_charset()


def _decode(body, media, declared):
    selected, origin = declared, "http_header"
    if not selected and media != "text/plain":
        parser = _MetaCharset()
        parser.feed(body[:1024].decode("latin-1"))
        selected, origin = parser.charset, "html_meta_first_1024_bytes"
    if not selected:
        selected, origin = "utf-8", "assumed_utf8"
    try:
        encoding = codecs.lookup(selected).name
    except LookupError as error:
        raise _Failure("unsupported_charset") from error
    if encoding not in {"utf-8", "ascii", "iso8859-1", "cp1252", "utf-16", "utf-16-le", "utf-16-be"}:
        raise _Failure("unsupported_charset")
    # HTML's legacy ASCII/Latin-1 labels represent Windows-1252; plain-text
    # declarations retain their actual codec instead of this HTML convention.
    if media != "text/plain" and encoding in {"ascii", "iso8859-1"}:
        encoding = "cp1252"
    return body.decode(encoding, errors="strict"), encoding, origin


def acquire_source(url, *, limits=None, resolver=socket.getaddrinfo,
                   connection_factory=_PinnedHTTPSConnection, clock=time.monotonic):
    """Fetch once per redirect hop; failed/partial retrieval yields no source text.

    Injection seams are for trusted tests, never supplied by a model. No headers
    or arbitrary code can be supplied by the caller. Successful text may be an
    explicitly truncated prefix; it is not a verification certificate.
    """
    limits = limits or SourceAcquisitionLimits()
    started = clock()
    deadline = started + limits.io_seconds
    result = {"status": "failed", "requested_url": None, "request_fragment": None,
              "final_url": None, "retrieved_at_utc": None, "source_text": None,
              "raw_content_sha256": None, "text_sha256": None, "trace": [],
              "limits": asdict(limits), "truncated": False,
              "verification": "unverified_source_material",
              "deadline_scope": "Network reads/connect/TLS use remaining total time; blocking system DNS cannot be interrupted. An overdue DNS return fails before connect. Local extraction/persistence is not a hard real-time operation.",
              "representation_limits": ["HTTPS port 443 only; no proxy, credentials, cookies or active content execution.", "HTTP transfer framing is removed before the raw-content hash; content encoding must be identity. Per-hop HTTP bytes including headers/chunk framing are capped at body_bytes + 65536 (excluding TLS framing).", "Only UTF-8, ASCII, Latin-1, Windows-1252 and explicit UTF-16 variants are decoded strictly; HTML legacy ASCII/Latin-1 labels map to Windows-1252. Absent charset defaults to UTF-8, not full browser charset sniffing."]}
    connection = response = None
    try:
        host, transport, target, fragment = _url(url)
        result.update(requested_url=url, request_fragment=fragment)
        visited = set()
        for hop in range(limits.redirects + 1):
            if transport in visited:
                raise _Failure("redirect_loop")
            visited.add(transport)
            _remaining(deadline, limits.socket_seconds, clock)
            addresses = _public_addresses(host, resolver)
            _remaining(deadline, limits.socket_seconds, clock)
            trace = {"url": transport, "resolved_public_addresses": [ip for _, ip in addresses],
                     "pinned_address": addresses[0][1]}
            result["trace"].append(trace)
            connection = connection_factory(host, addresses[0], deadline, limits, clock)
            connection.request("GET", target, headers={"Accept": "text/html, application/xhtml+xml, text/plain",
                "Accept-Encoding": "identity", "User-Agent": "CheckpointSourceAcquisition/1", "Connection": "close"})
            response = connection.getresponse()
            _remaining(deadline, limits.socket_seconds, clock)
            trace["connected_address"] = addresses[0][1]
            trace["http_status"] = response.status
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader("Location")
                if not location or hop == limits.redirects:
                    raise _Failure("redirect_limit_or_missing_location")
                if any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in location):
                    raise _Failure("invalid_redirect_url")
                next_url = urljoin(transport, location)
                host, transport, target, _ = _url(next_url)
                response.close()
                connection.close()
                connection = response = None
                continue
            if response.status != 200:
                raise _Failure("http_status_not_complete_200")
            headers = response.getheaders()
            for name in ("content-type", "content-length", "content-encoding", "transfer-encoding"):
                if sum(k.lower() == name for k, _ in headers) > 1:
                    raise _Failure("ambiguous_response_headers")
            if response.getheader("Content-Encoding", "identity").strip().lower() != "identity":
                raise _Failure("unsupported_content_encoding")
            transfer, length = response.getheader("Transfer-Encoding"), response.getheader("Content-Length")
            if transfer and (transfer.strip().lower() != "chunked" or length is not None):
                raise _Failure("unsupported_or_ambiguous_transfer_encoding")
            if length is not None and (not length.isascii() or not length.isdecimal() or int(length) > limits.body_bytes):
                raise _Failure("body_byte_limit_or_invalid_length")
            content_type = response.getheader("Content-Type")
            if not content_type:
                raise _Failure("missing_content_type")
            header = Message()
            header["content-type"] = content_type
            media = content_type.split(";", 1)[0].strip().lower()
            if media not in {"text/html", "application/xhtml+xml", "text/plain"}:
                raise _Failure("unsupported_media_type")
            body = bytearray()
            while True:
                _remaining(deadline, limits.socket_seconds, clock)
                chunk = response.read(min(65_536, limits.body_bytes + 1 - len(body)))
                _remaining(deadline, limits.socket_seconds, clock)
                if not chunk:
                    break
                body.extend(chunk)
                if len(body) > limits.body_bytes:
                    raise _Failure("body_byte_limit")
            if length is not None and len(body) != int(length):
                raise _Failure("incomplete_body")
            result.update(final_url=transport, retrieved_at_utc=datetime.now(timezone.utc).isoformat(),
                          media_type=media, declared_charset=header.get_content_charset(),
                          raw_content_bytes=len(body), raw_content_sha256=hashlib.sha256(body).hexdigest())
            decoded, charset, charset_origin = _decode(bytes(body), media, header.get_content_charset())
            if media == "text/plain":
                text = decoded[:limits.text_characters]
                truncated = len(text) != len(decoded)
            else:
                parser = _HTMLText(limits.text_characters)
                parser.feed(decoded)
                parser.close()
                text, truncated = "".join(parser.parts), parser.truncated
                result["representation_limits"].append("HTML text-node extraction, not browser rendering: entities decoded; block/pre/line/table separators retained or inserted; scripts, styles, head, templates, noscript and hidden attributes omitted. CSS visibility, layout, link targets, media/OCR and generated content are not represented; malformed markup may differ from browser DOM repair.")
            if not text.strip():
                raise _Failure("no_extracted_text")
            result.update(status="acquired", source_text=text, charset=charset, charset_origin=charset_origin,
                          text_sha256=hashlib.sha256(text.encode("utf-8")).hexdigest(), truncated=truncated,
                          text_characters=len(text), source_text_complete=not truncated)
            break
    except _Failure as error:
        result["failure_reason"] = str(error)
    except (UnicodeError, LookupError):
        result["failure_reason"] = "text_decode_failed"
    except AssertionError:
        result["failure_reason"] = "html_parse_failed"
    except socket.gaierror:
        result["failure_reason"] = "dns_failed"
    except TimeoutError:
        result["failure_reason"] = "io_deadline" if clock() >= deadline else "socket_timeout"
    except (OSError, http.client.HTTPException, ValueError):
        result["failure_reason"] = "transport_or_protocol_failure"
    finally:
        for resource in (response, connection):
            if resource is None:
                continue
            try:
                resource.close()
            except OSError:
                result.update(status="failed", failure_reason="connection_cleanup_failed",
                              source_text=None, text_sha256=None, source_text_complete=False)
        result["elapsed_seconds"] = max(0, clock() - started)
    return result
