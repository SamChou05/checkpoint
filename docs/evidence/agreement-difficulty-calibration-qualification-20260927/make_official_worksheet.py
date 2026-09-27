"""Create only the prespecified keyless returned-output review worksheet."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets

HERE = Path(__file__).resolve().parent
CAPTURE = HERE / "capture.json"
PLAN = HERE / "plan.json"
PRIVATE_MAP = HERE / "blind-private-returned_output.json"


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


def project(capture_sha, plan_sha, reviewer_dir):
    raw_capture, raw_plan = CAPTURE.read_bytes(), PLAN.read_bytes()
    if sha(raw_capture) != capture_sha or sha(raw_plan) != plan_sha:
        raise ValueError("Capture or plan digest mismatch.")
    capture, plan = strict_json(raw_capture), strict_json(raw_plan)
    if (plan.get("state") != "frozen" or capture.get("plan") != plan
            or capture.get("plan_sha256") != plan_sha
            or capture.get("status") != "completed_pending_review"
            or capture.get("summary", {}).get("planned_questions") != 5
            or capture["summary"].get("within_execute_deadline") is not True
            or capture["summary"].get("returned_questions") != 5
            or len(capture.get("original_jobs", [])) != 1
            or len(capture.get("jobs", [])) != 1
            or len(capture.get("calls", [])) > 6):
        raise ValueError("Capture is not the expected original five-slot return.")
    original, job = capture["original_jobs"][0], capture["jobs"][0]
    slots = job.get("returned_slot_ordinals")
    rows = job.get("returned")
    if (slots is None or rows is None or len(slots) != 5 or len(rows) != 5
            or sorted(slots) != list(range(5))
            or [item.get("ordinal") for item in original.get("slots", [])] != list(range(5))
            or [item.get("status") for item in original["slots"]] != ["returned"] * 5
            or len(job.get("passes", [])) != 1):
        raise ValueError("Original slots or one-pass association changed.")
    if reviewer_dir.exists() or PRIVATE_MAP.exists():
        raise ValueError("Reviewer surface or private map already exists.")
    by_slot = dict(zip(slots, rows, strict=True))
    items, mapping = [], {}
    for ordinal in range(5):
        opaque = secrets.token_hex(12)
        while opaque in mapping:
            opaque = secrets.token_hex(12)
        question = by_slot.get(ordinal)
        if question is None:
            items.append({"id": opaque, "requested_slot": True, "unavailable": True})
            mapping[opaque] = {"original_slot": ordinal, "status": "unavailable"}
            continue
        choices = question.get("choices")
        key = question.get("expectedAnswer")
        if (type(question.get("prompt")) is not str or not question["prompt"]
                or type(choices) is not list or len(choices) != 4
                or any(type(choice) is not str or not choice for choice in choices)
                or type(key) is not str or choices.count(key) != 1):
            raise ValueError("Question cannot be projected with one literal key.")
        indices = list(range(4))
        secrets.SystemRandom().shuffle(indices)
        display = {label: choices[index] for label, index in zip("ABCD", indices, strict=True)}
        items.append({"id": opaque, "requested_slot": True,
                      "stem": question["prompt"], "choices": display})
        mapping[opaque] = {"original_slot": ordinal,
                           "display_to_source_index": indices,
                           "correct_display_label": next(label for label, literal in display.items()
                                                         if literal == key)}
    secrets.SystemRandom().shuffle(items)
    reviewer_dir.mkdir(parents=True, exist_ok=False)
    rubric = (
        "# Blind review of the prespecified worker return\n\n"
        "This worksheet represents exactly five originally requested slots. "
        "Any unavailable placeholder counts as unfilled. IDs, item order and "
        "display choices are randomized. The answer key, source slot, model "
        "ratings, rejection reasons and authored teaching are withheld. Do not "
        "open the trial branch, capture or private map until both reviews lock.\n\n"
        "For each readable item, choose the single correct letter or mark it "
        "ambiguous/unsupported. Judge all six unordered choice pairs for "
        "meaningful distinctness, stem self-containment, difficulty from 1 to 5, "
        "visible objective fit and within-batch novelty. Record uncertainty. "
        "A separate teaching and feedback audit follows review lock.\n"
    )
    worksheet = {"version": 1, "kind": "prespecified_returned_output",
                 "requested_slots": 5, "items": items}
    worksheet_path, rubric_path = reviewer_dir / "worksheet.json", reviewer_dir / "RUBRIC.md"
    worksheet_sha = write_new(worksheet_path,
                              (json.dumps(worksheet, ensure_ascii=False, allow_nan=False, indent=2) + "\n").encode())
    rubric_sha = write_new(rubric_path, rubric.encode())
    private_sha = write_new(PRIVATE_MAP,
                            (json.dumps({"version": 1, "kind": "prespecified_returned_output",
                                "capture_sha256": capture_sha, "plan_sha256": plan_sha,
                                "worksheet_sha256": worksheet_sha, "mapping": mapping},
                                ensure_ascii=False, allow_nan=False, indent=2) + "\n").encode(),
                            private=True)
    if sha(CAPTURE.read_bytes()) != capture_sha or sha(PLAN.read_bytes()) != plan_sha:
        raise ValueError("Capture or plan changed during projection.")
    return {"worksheet": str(worksheet_path), "worksheet_sha256": worksheet_sha,
            "rubric": str(rubric_path), "rubric_sha256": rubric_sha,
            "private_map": str(PRIVATE_MAP), "private_map_sha256": private_sha,
            "readable": sum("stem" in item for item in items),
            "unavailable": sum(item.get("unavailable") is True for item in items)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-sha256", required=True)
    parser.add_argument("--plan-sha256", required=True)
    parser.add_argument("--reviewer-dir", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(project(args.capture_sha256, args.plan_sha256, args.reviewer_dir), indent=2))
