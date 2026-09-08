"""Bounded parent transport for the app-owned HTML observer; never model JS.

The caller must durably record the prepared job before calling. Local process
termination cannot prove browser cleanup; any unconfirmed cleanup blocks use.
"""

import base64
import copy
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import tempfile
import time

from evals.html_artifact_question import (
    OBSERVATION_PROTOCOL,
    OBSERVER,
    SETTINGS,
    canonical,
    digest,
)

PROCESS_TIMEOUT_SECONDS = 45
CAPTURE_BYTES = 32768
INPUT_BYTES = 16384
REAP_GRACE_SECONDS = 0.2


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate_json_key")
        result[key] = value
    return result


def _terminate(process):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=REAP_GRACE_SECONDS)
        except subprocess.TimeoutExpired:
            pass
    return process.returncode is not None


def _valid_envelope(envelope, job):
    """Validate transport evidence without requiring an offered answer match."""
    keys = {
        "protocol",
        "job_id",
        "artifact_sha256",
        "probe_sha256",
        "observer_source_sha256",
        "status",
        "reason",
        "browser",
        "settings",
        "values",
        "serialized_dom",
        "serialized_dom_sha256",
        "target_outer_html",
        "cleanup",
    }
    if (
        type(envelope) is not dict
        or set(envelope) != keys
        or envelope["protocol"] != OBSERVATION_PROTOCOL
        or any(
            envelope[k] != job[k]
            for k in (
                "job_id",
                "artifact_sha256",
                "probe_sha256",
                "observer_source_sha256",
            )
        )
        or canonical(envelope["settings"]) != canonical(SETTINGS)
        or type(envelope["reason"]) is not str
        or len(envelope["reason"]) > 160
        or type(envelope["browser"]) is not dict
        or set(envelope["browser"]) != {"name", "version"}
        or envelope["browser"]["name"] != "chromium"
        or type(envelope["browser"]["version"]) is not str
        or not 1 <= len(envelope["browser"]["version"].strip()) <= 80
        or len(envelope["browser"]["version"]) > 80
    ):
        return False
    if envelope["status"] == "unsupported":
        return (
            bool(envelope["reason"].strip())
            and all(
                envelope[k] == ""
                for k in (
                    "serialized_dom",
                    "serialized_dom_sha256",
                    "target_outer_html",
                )
            )
            and envelope["values"] is None
        )
    if envelope["status"] != "observed" or envelope["reason"] != "":
        return False
    return (
        type(envelope["values"]) is list
        and len(envelope["values"]) == len(job["spec"]["properties"])
        and all(type(v) is bool for v in envelope["values"])
        and all(
            type(envelope[k]) is str and 1 <= len(envelope[k]) <= 4096
            for k in ("serialized_dom", "target_outer_html")
        )
        and digest(envelope["serialized_dom"]) == envelope["serialized_dom_sha256"]
    )


def observe_html_job(job, *, node, playwright_module, browsers_path):
    """Return bounded raw transport evidence; caller separately prepares/binds."""
    started = time.monotonic()
    stdin_text = canonical(job) + "\n"
    data = stdin_text.encode("utf-8")
    record = {
        "request": copy.deepcopy(job),
        "stdin_text": stdin_text,
        "stdin_sha256": digest(stdin_text),
        "stdin_bytes": len(data),
        "observer_path": str(OBSERVER),
        "node": str(Path(node).resolve()),
        "status": "operational_failure",
        "reason": "",
        "returncode": None,
        "process_deadline_seconds": PROCESS_TIMEOUT_SECONDS,
        "capture_limit_bytes_per_stream": CAPTURE_BYTES,
        "cleanup_grace_seconds": REAP_GRACE_SECONDS * 3,
        "envelope": None,
        "child_started": False,
    }
    buffers = {name: bytearray() for name in ("stdout", "stderr")}
    seen = {name: 0 for name in buffers}
    process, failure, sent, terminated = None, "", 0, False
    selector = selectors.DefaultSelector()
    try:
        if len(data) > INPUT_BYTES:
            raise ValueError("input_byte_limit_exceeded")
        with tempfile.TemporaryDirectory(prefix="checkpoint-html-transport-") as temp:
            env = {
                "PATH": os.defpath,
                "TMPDIR": temp,
                "LANG": "C",
                "CHECKPOINT_PLAYWRIGHT_MODULE": str(Path(playwright_module).resolve()),
                "PLAYWRIGHT_BROWSERS_PATH": str(Path(browsers_path).resolve()),
            }
            if "HOME" in os.environ:
                env["HOME"] = os.environ["HOME"]
            record["environment"] = env
            process = subprocess.Popen(
                [record["node"], str(OBSERVER)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                cwd=temp,
                start_new_session=True,
            )
            record["child_started"] = True
            record["pid"] = process.pid
            for name in ("stdin", "stdout", "stderr"):
                stream = getattr(process, name)
                os.set_blocking(stream.fileno(), False)
                selector.register(
                    stream,
                    selectors.EVENT_WRITE if name == "stdin" else selectors.EVENT_READ,
                    name,
                )
            deadline = started + PROCESS_TIMEOUT_SECONDS
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    failure = "process_deadline"
                    break
                for key, _ in selector.select(min(remaining, 0.05)):
                    if key.data == "stdin":
                        try:
                            sent += os.write(key.fd, data[sent : sent + 4096])
                        except BrokenPipeError:
                            selector.unregister(key.fileobj)
                            key.fileobj.close()
                            continue
                        if sent == len(data):
                            selector.unregister(key.fileobj)
                            key.fileobj.close()
                        continue
                    chunk = os.read(key.fd, 8192)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        key.fileobj.close()
                        continue
                    name = key.data
                    seen[name] += len(chunk)
                    buffers[name].extend(
                        chunk[: max(0, CAPTURE_BYTES - len(buffers[name]))]
                    )
                    if seen[name] > CAPTURE_BYTES:
                        failure = name + "_capture_limit"
                        break
                if failure:
                    break
            if not failure:
                try:
                    process.wait(timeout=max(0, deadline - time.monotonic()))
                except subprocess.TimeoutExpired:
                    failure = "process_deadline"
            if failure:
                terminated = True
                _terminate(process)
            # Drain remaining buffered output without retaining excess bytes or
            # waiting indefinitely on a descendant that inherited a pipe.
            drain_deadline = time.monotonic() + REAP_GRACE_SECONDS
            while selector.get_map() and time.monotonic() < drain_deadline:
                for key, _ in selector.select(0.01):
                    if key.data == "stdin":
                        selector.unregister(key.fileobj)
                        key.fileobj.close()
                        continue
                    chunk = os.read(key.fd, 8192)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        key.fileobj.close()
                        continue
                    seen[key.data] += len(chunk)
                    buffers[key.data].extend(
                        chunk[: max(0, CAPTURE_BYTES - len(buffers[key.data]))]
                    )
    except (OSError, ValueError) as error:
        failure = (
            str(error)
            if str(error) == "input_byte_limit_exceeded"
            else type(error).__name__
        )
        if process is not None:
            terminated = True
            _terminate(process)
    finally:
        for key in list(selector.get_map().values()):
            key.fileobj.close()
        selector.close()
        if process is not None:
            record["returncode"] = process.returncode
        record["stdin_bytes_sent"] = sent
        record["cleanup"] = {
            "child_reaped": process is not None and process.returncode is not None,
            "termination_attempted": terminated,
            "browser_cleanup_confirmed": False,
        }
        record["elapsed_seconds"] = round(time.monotonic() - started, 6)
    for name, buffer in buffers.items():
        raw = bytes(buffer)
        record[name + "_base64"] = base64.b64encode(raw).decode("ascii")
        record[name + "_bytes_seen"] = seen[name]
        record[name + "_retained_bytes"] = len(raw)
        try:
            record[name] = raw.decode("utf-8")
        except UnicodeDecodeError:
            record[name] = None
            failure = failure or "invalid_output_utf8"
    try:
        envelope = json.loads(record["stdout"] or "", object_pairs_hook=_unique)
        record["envelope"] = envelope
        valid = _valid_envelope(envelope, job)
        closed = valid and envelope.get("cleanup") == {
            "context": "closed",
            "browser": "closed",
        }
        record["cleanup"]["browser_cleanup_confirmed"] = bool(closed and not terminated)
        if not failure and sent == len(data) and closed:
            if (
                record["returncode"] == 0
                and envelope.get("status") == "observed"
                and envelope.get("reason") == ""
            ):
                record["status"] = "completed"
            elif record["returncode"] == 1 and envelope.get("status") == "unsupported":
                record["status"] = "unsupported"
            else:
                failure = "observer_failed"
        else:
            failure = failure or "incomplete_or_mismatched_observation"
    except (ValueError, TypeError, KeyError, RecursionError):
        failure = failure or "malformed_observer_output"
    record["reason"] = failure
    return record
