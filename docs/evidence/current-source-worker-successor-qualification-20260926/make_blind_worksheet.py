"""One-shot keyless projection of a finalized 15-slot worker capture.

Preparation utility only. Invoke after the capture owner supplies its exact
SHA-256 and confirms execution has stopped. This never contacts AWS.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def strict_json(raw):
    def no_duplicates(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError("duplicate JSON member")
            value[key] = item
        return value
    return json.loads(raw, object_pairs_hook=no_duplicates,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))


def write_exclusive(path, value, *, private=False):
    raw = (json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode()
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600 if private else 0o644)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
    finally:
        descriptor = None
    parent = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(parent)
    finally:
        os.close(parent)
    return sha(raw)


def project(directory, expected_capture_sha, expected_plan_sha):
    capture_path, plan_path = directory / "capture.json", directory / "plan.json"
    worksheet_path, private_path = directory / "blind-worksheet.json", directory / "blind-private-map.json"
    if worksheet_path.exists() or private_path.exists():
        raise ValueError("projection outputs already exist")
    capture_raw, plan_raw = capture_path.read_bytes(), plan_path.read_bytes()
    if sha(capture_raw) != expected_capture_sha or sha(plan_raw) != expected_plan_sha:
        raise ValueError("out-of-band capture or plan digest mismatch")
    capture, plan = strict_json(capture_raw), strict_json(plan_raw)
    if capture.get("status") not in {"completed_pending_review", "globally_aborted"} or not isinstance(capture.get("summary"), dict):
        raise ValueError("capture has not finalized")
    if capture.get("plan") != plan or capture.get("plan_sha256") != expected_plan_sha:
        raise ValueError("capture does not bind the supplied frozen plan")
    jobs = plan.get("jobs")
    originals = capture.get("original_jobs")
    observed = capture.get("jobs")
    calls = capture.get("call_slots")
    if not isinstance(jobs, list) or len(jobs) != 3 or not isinstance(originals, list) or len(originals) != 3 or not isinstance(observed, list) or not isinstance(calls, list) or len(calls) != 18:
        raise ValueError("original denominator is not three jobs and eighteen call slots")
    if capture["summary"].get("planned_questions") != 15:
        raise ValueError("summary denominator changed")
    by_id = {row["id"]: row for row in observed}
    if len(by_id) != len(observed) or set(by_id) - {job["id"] for job in jobs}:
        raise ValueError("observed job identities changed")
    items, mapping = [], {}
    available, credited, late_diagnostic = 0, 0, 0
    for job, original in zip(jobs, originals, strict=True):
        if original.get("id") != job["id"] or job["request"].get("targetCount") != 5:
            raise ValueError("original job identities or targets changed")
        slots = original.get("slots")
        if not isinstance(slots, list) or len(slots) != 5 or [slot.get("ordinal") for slot in slots] != list(range(5)):
            raise ValueError("original slot ordinals changed")
        returned = by_id.get(job["id"], {}).get("returned", [])
        if not isinstance(returned, list) or len(returned) > 5:
            raise ValueError("returned list exceeds original job target")
        sources = by_id.get(job["id"], {}).get("returned_sources", [])
        if returned and (not isinstance(sources, list) or len(sources) != len(returned)):
            raise ValueError("returned source binding missing")
        for ordinal, slot in enumerate(slots):
            opaque = secrets.token_hex(12)
            while opaque in mapping:
                opaque = secrets.token_hex(12)
            projected = {"id": opaque}
            offset = None
            if ordinal < len(returned):
                question = returned[ordinal]
                if not isinstance(question, dict) or not isinstance(question.get("prompt"), str) or not question["prompt"] or not isinstance(question.get("choices"), list) or len(question["choices"]) != 4 or not all(isinstance(choice, str) and choice for choice in question["choices"]):
                    raise ValueError("returned question cannot be projected safely")
                offset = secrets.randbelow(4)
                indices = [(offset + step) % 4 for step in range(4)]
                projected.update(stem=question["prompt"], choices={label: question["choices"][index] for label, index in zip("ABCD", indices, strict=True)})
                available += 1
                if slot.get("status") == "returned":
                    credited += 1
                elif slot.get("status") == "late_uncredited":
                    late_diagnostic += 1
                else:
                    raise ValueError("returned question has inconsistent slot status")
            else:
                projected["unavailable"] = True
                if slot.get("status") not in {"unfilled", "unattempted"}:
                    raise ValueError("missing return has inconsistent slot status")
            items.append(projected)
            mapping[opaque] = {"job_id": job["id"], "original_slot_ordinal": ordinal,
                               "slot_status": slot["status"], "returned_source": sources[ordinal] if offset is not None else None,
                               "display_to_source_index": ([(offset + step) % 4 for step in range(4)] if offset is not None else None),
                               "expected_answer": returned[ordinal].get("expectedAnswer") if offset is not None else None,
                               "explanation": returned[ordinal].get("explanation") if offset is not None else None}
    if len(items) != 15 or len(mapping) != 15:
        raise ValueError("projection lost a requested slot")
    if capture["summary"].get("returned_questions") != credited:
        raise ValueError("credited return count disagrees with capture summary")
    secrets.SystemRandom().shuffle(items)
    if sha(capture_path.read_bytes()) != expected_capture_sha or sha(plan_path.read_bytes()) != expected_plan_sha:
        raise ValueError("capture or plan changed during projection")
    worksheet = {"version": 1, "capture_sha256": expected_capture_sha,
                 "plan_sha256": expected_plan_sha, "requested_slots": 15,
                 "items": items}
    worksheet_sha = write_exclusive(worksheet_path, worksheet)
    private = {"version": 1, "worksheet_sha256": worksheet_sha,
               "capture_sha256": expected_capture_sha, "mapping": mapping}
    private_sha = write_exclusive(private_path, private, private=True)
    if sha(capture_path.read_bytes()) != expected_capture_sha or sha(plan_path.read_bytes()) != expected_plan_sha:
        raise ValueError("capture or plan changed after projection")
    return {"worksheet": str(worksheet_path), "worksheet_sha256": worksheet_sha,
            "private_map": str(private_path), "private_map_sha256": private_sha,
            "requested_slots": 15, "readable_returns": available,
            "credited_returns": credited, "late_diagnostic_returns": late_diagnostic,
            "unavailable_slots": 15 - available}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--capture-sha256", required=True)
    parser.add_argument("--plan-sha256", required=True)
    arguments = parser.parse_args()
    print(json.dumps(project(arguments.directory, arguments.capture_sha256,
                             arguments.plan_sha256), indent=2))
