"""Project the locked worker capture into separate keyless review surfaces."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets

HERE = Path(__file__).resolve().parent


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def strict_json(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON member.")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Nonfinite JSON.")))


def write_new(path, data, *, private=False):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600 if private else 0o644)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    parent = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(parent)
    finally:
        os.close(parent)
    return sha(data)


def public_item(question, opaque):
    if (type(question) is not dict or type(question.get("prompt")) is not str
            or not question["prompt"] or type(question.get("choices")) is not list
            or len(question["choices"]) != 4
            or any(type(choice) is not str or not choice for choice in question["choices"])
            or type(question.get("expectedAnswer")) is not str
            or question["choices"].count(question["expectedAnswer"]) != 1):
        raise ValueError("Question cannot be projected without a unique literal key.")
    indices = list(range(4))
    secrets.SystemRandom().shuffle(indices)
    choices = {label: question["choices"][index]
               for label, index in zip("ABCD", indices, strict=True)}
    key = next(label for label, literal in choices.items()
               if literal == question["expectedAnswer"])
    return {"id": opaque, "requested_slot": True, "stem": question["prompt"],
            "choices": choices}, indices, key


def rubric(kind):
    extra = ("This is the prespecified full-worker returned output. Unavailable entries "
             "are original requested slots that the worker did not return."
             if kind == "returned_output" else
             "This is a post-hoc diagnostic view of the pre-review sanitized "
             "candidates. Its presence does not mean the worker returned an item.")
    return ("# Blind multiple-choice audit\n\n" + extra + "\n\n"
            "The five IDs and display choice positions are randomized. No answer key, "
            "source slot, teaching, model decision, or rejection reason is supplied. "
            "Do not inspect the trial branch, capture, plan, or private maps before "
            "locking your review. For every readable item, independently select "
            "the single best letter or mark ambiguous/unsupported. Judge all six "
            "unordered choice pairs for meaning, whether all necessary stem facts "
            "are shown, objective fit, and actual cognitive difficulty from 1 to 5. "
            "Note repeated mechanisms and any uncertainty. Mark unavailable entries "
            "unavailable. The author explanations are intentionally hidden; teaching "
            "is audited only after blind answer reviews lock.\n")


def project(expected_capture_sha, expected_plan_sha, returned_dir, diagnostic_dir):
    capture_path, plan_path = HERE / "capture.json", HERE / "plan.json"
    capture_raw, plan_raw = capture_path.read_bytes(), plan_path.read_bytes()
    if sha(capture_raw) != expected_capture_sha or sha(plan_raw) != expected_plan_sha:
        raise ValueError("Capture or plan digest mismatch.")
    capture, plan = strict_json(capture_raw), strict_json(plan_raw)
    if (plan.get("state") != "frozen" or capture.get("status") != "completed_pending_review"
            or capture.get("plan_sha256") != expected_plan_sha
            or capture.get("plan") != plan or capture.get("summary", {}).get("planned_questions") != 5
            or len(plan.get("jobs", [])) != 1 or len(capture.get("jobs", [])) != 1
            or len(capture.get("original_jobs", [])) != 1):
        raise ValueError("Capture is not one finalized original five-slot worker job.")
    job, original = capture["jobs"][0], capture["original_jobs"][0]
    if (job.get("id") != "mixed" or original.get("id") != "mixed"
            or len(original.get("slots", [])) != 5
            or [slot.get("ordinal") for slot in original["slots"]] != list(range(5))
            or len(capture.get("call_slots", [])) != 6
            or job.get("provider_calls") != len(capture.get("reservations", []))
            or job.get("provider_calls") > 6):
        raise ValueError("Original slot or provider-call denominator changed.")
    returned = job.get("returned", [])
    returned_slots = job.get("returned_slot_ordinals", [])
    if (type(returned) is not list or type(returned_slots) is not list
            or len(returned) != len(returned_slots) <= 5
            or any(type(slot) is not int or not 0 <= slot < 5 for slot in returned_slots)
            or len(set(returned_slots)) != len(returned_slots)
            or capture["summary"].get("returned_questions") != len(returned)):
        raise ValueError("Returned questions lack unique original-slot bindings.")
    returned_by_slot = dict(zip(returned_slots, returned, strict=True))
    passes = job.get("passes", [])
    if len(passes) != 1 or passes[0].get("ordinal") != 0:
        raise ValueError("Expected exactly one original author pass.")
    sanitized = passes[0].get("sanitized", [])
    if type(sanitized) is not list or len(sanitized) > 5:
        raise ValueError("Sanitized candidate denominator changed.")
    sanitized_by_slot = {}
    for entry in sanitized:
        slots = entry.get("original_slot_ordinals")
        if (type(slots) is not list or len(slots) != 1 or type(slots[0]) is not int
                or not 0 <= slots[0] < 5 or slots[0] in sanitized_by_slot):
            raise ValueError("Sanitized row lacks one unique original slot.")
        sanitized_by_slot[slots[0]] = entry["question"]
    if set(returned_by_slot) - set(sanitized_by_slot):
        raise ValueError("Returned row has no sanitized source.")
    private_paths = {kind: HERE / f"blind-private-{kind}.json"
                     for kind in ("returned_output", "pre_review_diagnostic")}
    if (returned_dir.exists() or diagnostic_dir.exists()
            or any(path.exists() for path in private_paths.values())):
        raise ValueError("A reviewer surface or private map already exists.")
    results = {}
    for kind, directory, source in (
        ("returned_output", returned_dir, returned_by_slot),
        ("pre_review_diagnostic", diagnostic_dir, sanitized_by_slot),
    ):
        items, mapping = [], {}
        for ordinal in range(5):
            opaque = secrets.token_hex(12)
            while opaque in mapping:
                opaque = secrets.token_hex(12)
            if ordinal in source:
                item, indices, key = public_item(source[ordinal], opaque)
                mapping[opaque] = {"original_slot": ordinal, "source": kind,
                                   "display_to_source_index": indices,
                                   "correct_display_label": key,
                                   "returned_by_worker": ordinal in returned_by_slot}
            else:
                item = {"id": opaque, "requested_slot": True, "unavailable": True}
                mapping[opaque] = {"original_slot": ordinal, "source": kind,
                                   "status": "unavailable",
                                   "returned_by_worker": False}
            items.append(item)
        secrets.SystemRandom().shuffle(items)
        directory.mkdir(parents=True, exist_ok=False)
        worksheet = {"version": 1, "kind": kind, "requested_slots": 5, "items": items}
        worksheet_path, rubric_path = directory / "worksheet.json", directory / "RUBRIC.md"
        worksheet_sha = write_new(worksheet_path,
                                  (json.dumps(worksheet, ensure_ascii=False, allow_nan=False, indent=2) + "\n").encode())
        rubric_sha = write_new(rubric_path, rubric(kind).encode())
        private_sha = write_new(private_paths[kind],
                                (json.dumps({"version": 1, "kind": kind,
                                    "capture_sha256": expected_capture_sha,
                                    "plan_sha256": expected_plan_sha,
                                    "worksheet_sha256": worksheet_sha,
                                    "mapping": mapping}, ensure_ascii=False,
                                    allow_nan=False, indent=2) + "\n").encode(), private=True)
        results[kind] = {"worksheet": str(worksheet_path), "worksheet_sha256": worksheet_sha,
                         "rubric": str(rubric_path), "rubric_sha256": rubric_sha,
                         "private_map": str(private_paths[kind]), "private_map_sha256": private_sha,
                         "readable": sum("stem" in item for item in items),
                         "unavailable": sum(item.get("unavailable") is True for item in items)}
    if sha(capture_path.read_bytes()) != expected_capture_sha or sha(plan_path.read_bytes()) != expected_plan_sha:
        raise ValueError("Capture or plan changed during projection.")
    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-sha256", required=True)
    parser.add_argument("--plan-sha256", required=True)
    parser.add_argument("--returned-dir", required=True, type=Path)
    parser.add_argument("--diagnostic-dir", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(project(args.capture_sha256, args.plan_sha256,
                             args.returned_dir, args.diagnostic_dir), indent=2))
