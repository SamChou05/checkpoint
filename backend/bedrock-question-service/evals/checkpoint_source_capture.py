#!/usr/bin/env python3
"""Capture up to five public references for evaluation; no model calls.

Dry by default. Captures may include copyrighted source text: keep full output
local unless redistribution is permitted. Fetching is not source endorsement.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from source_acquisition import SourceAcquisitionLimits, acquire_source  # noqa: E402


def _now():
    return datetime.now(timezone.utc).isoformat()


def _sync_directory(path):
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _save(path, record):
    temporary = path.with_name(path.name + ".writing")
    with temporary.open("x", encoding="utf-8") as handle:
        json.dump(record, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(path)
    _sync_directory(path)


def capture_sources(urls, output, *, fetch=acquire_source):
    """Persist dispatch before each call; never retry or overwrite prior output.

    A process interruption leaves an explicit dispatched row, not a claim that
    retrieval failed. Such a capture is not resumable by this helper.
    """
    if (type(urls) is not list or not 1 <= len(urls) <= 5
            or any(type(url) is not str or not url for url in urls)
            or len(set(urls)) != len(urls)):
        raise ValueError("Provide one to five distinct URLs.")
    output = Path(output)
    limits = SourceAcquisitionLimits()
    record = {
        "experiment": "public-source-acquisition-v1",
        "created_at_utc": _now(),
        "status": "running",
        "source_acquisition_sha256": hashlib.sha256(
            (SERVICE_DIR / "source_acquisition.py").read_bytes()
        ).hexdigest(),
        "maximum_acquisitions": len(urls),
        "limits_per_acquisition": asdict(limits),
        "model_calls": 0,
        "scope": "Explicit URLs selected by caller; no automated discovery or correctness certification.",
        "records": [{"url": url, "status": "unattempted"} for url in urls],
    }
    # Reserve before any external action. Refuse to clobber previous evidence.
    with output.open("x", encoding="utf-8") as handle:
        json.dump(record, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    _sync_directory(output)
    for row in record["records"]:
        row.update(status="dispatched", dispatched_at_utc=_now())
        _save(output, record)
        try:
            acquisition = fetch(row["url"], limits=limits)
        except Exception as error:
            # Avoid storing exception text that could expose local paths/config.
            row.update(status="exception", error_type=type(error).__name__)
            record.update(status="stopped", finished_at_utc=_now())
            _save(output, record)
            raise
        row.update(status="observed", observed_at_utc=_now(), acquisition=acquisition)
        _save(output, record)
    record.update(status="completed", finished_at_utc=_now())
    _save(output, record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", action="append", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    if not 1 <= len(args.url) <= 5 or len(set(args.url)) != len(args.url):
        parser.error("Provide one to five distinct URLs.")
    if not args.live:
        print(json.dumps({"dry_run": True, "urls": args.url, "model_calls": 0}))
        return
    if args.output is None:
        parser.error("Live capture requires a new --output file.")
    result = capture_sources(args.url, args.output)
    print(json.dumps({"status": result["status"], "output": str(args.output),
                      "sources": [{"url": row["url"],
                                   "status": row["acquisition"]["status"],
                                   "failure_reason": row["acquisition"].get("failure_reason"),
                                   "text_characters": row["acquisition"].get("text_characters"),
                                   "truncated": row["acquisition"].get("truncated")}
                                  for row in result["records"]]}))


if __name__ == "__main__":
    main()
