"""One-shot keyless projection of all five sanitized candidate questions.

This script makes no provider calls. Keep its private answer map outside Git and
withhold it, the capture, and source tasks until both blind reviews are locked.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets


HERE = Path(__file__).resolve().parent
CAPTURE = HERE.parent / "capture.json"
PLAN_SHA256 = "7e8c98159f28e0dfd8269fee708731377f1d4cf7b76898340fefa04ecc8d106d"
WORKSHEET = HERE / "worksheet.json"
PRIVATE_DIR = Path("/private/tmp/checkpoint-v12-explained-worker-private-20260927")
PRIVATE_MAP = PRIVATE_DIR / "answer-map.json"
LABELS = "ABCD"


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _strict_json(raw: bytes) -> dict:
    def unique(pairs: list[tuple[str, object]]) -> dict:
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON member.")
            result[key] = value
        return result

    result = json.loads(
        raw, object_pairs_hook=unique,
        parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Nonfinite JSON.")),
    )
    if type(result) is not dict:
        raise ValueError("Capture must be a JSON object.")
    return result


def _encoded(value: dict) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode()


def _write_new(path: Path, data: bytes, *, mode: int) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, mode)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    parent = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(parent)
    finally:
        os.close(parent)


def project(capture_sha256: str) -> dict:
    if (len(capture_sha256) != 64
            or any(character not in "0123456789abcdef" for character in capture_sha256)):
        raise ValueError("Supply the independently recorded lowercase capture SHA-256.")
    if WORKSHEET.exists() or PRIVATE_DIR.exists() or PRIVATE_MAP.exists():
        raise ValueError("Blind worksheet or private mapping already exists.")
    raw = CAPTURE.read_bytes()
    if _sha(raw) != capture_sha256:
        raise ValueError("Immutable capture hash differs from the supplied value.")
    capture = _strict_json(raw)
    if (capture.get("status") != "completed_pending_review"
            or capture.get("plan_sha256") != PLAN_SHA256
            or capture.get("plan", {}).get("state") != "frozen"
            or capture.get("summary", {}).get("planned_questions") != 5
            or len(capture.get("jobs", [])) != 1
            or len(capture.get("original_jobs", [])) != 1
            or len(capture.get("calls", [])) > 6):
        raise ValueError("Capture is outside this frozen one-job trial.")
    job = capture["jobs"][0]
    if len(job.get("passes", [])) != 1:
        raise ValueError("Expected exactly one immutable worker pass.")
    original = capture["original_jobs"][0]
    if [slot.get("ordinal") for slot in original.get("slots", [])] != list(range(5)):
        raise ValueError("Original five-slot denominator changed.")
    sanitized = job["passes"][0].get("sanitized")
    if type(sanitized) is not list or len(sanitized) != 5:
        raise ValueError("Five sanitized candidates are required for blind review.")
    by_slot = {}
    for candidate in sanitized:
        slot = candidate.get("index")
        if (type(slot) is not int or slot not in range(5) or slot in by_slot
                or candidate.get("original_slot_ordinals") != [slot]):
            raise ValueError("Candidate source-slot mapping changed.")
        question = candidate.get("question")
        if type(question) is not dict:
            raise ValueError("Candidate has no question.")
        prompt, choices, key = (question.get(name) for name in
                                ("prompt", "choices", "expectedAnswer"))
        if (type(prompt) is not str or not prompt
                or type(choices) is not list or len(choices) != 4
                or any(type(choice) is not str or not choice for choice in choices)
                or len(set(choices)) != 4
                or type(key) is not str or choices.count(key) != 1):
            raise ValueError("Candidate cannot be projected with one literal key.")
        by_slot[slot] = question
    if set(by_slot) != set(range(5)):
        raise ValueError("A sanitized original slot is missing.")

    random = secrets.SystemRandom()
    item_order = list(range(5))
    random.shuffle(item_order)
    public_items, private_mapping = [], {}
    for number, slot in enumerate(item_order, start=1):
        question = by_slot[slot]
        choice_order = list(range(4))
        random.shuffle(choice_order)
        display = {label: question["choices"][index]
                   for label, index in zip(LABELS, choice_order, strict=True)}
        item_id = f"Q{number:02d}"
        public_items.append({"id": item_id, "prompt": question["prompt"], "choices": display})
        private_mapping[item_id] = {
            "originalSlot": slot,
            "displayToSourceIndex": choice_order,
            "key": next(label for label, text in display.items()
                        if text == question["expectedAnswer"]),
            "expectedAnswer": question["expectedAnswer"],
        }
    worksheet_bytes = _encoded({"items": public_items})
    worksheet_sha256 = _sha(worksheet_bytes)
    private_bytes = _encoded({
        "captureSha256": capture_sha256,
        "planSha256": PLAN_SHA256,
        "worksheetSha256": worksheet_sha256,
        "mapping": private_mapping,
    })
    if _sha(CAPTURE.read_bytes()) != capture_sha256:
        raise ValueError("Capture changed during projection.")
    PRIVATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=False)
    _write_new(PRIVATE_MAP, private_bytes, mode=0o600)
    _write_new(WORKSHEET, worksheet_bytes, mode=0o644)
    return {
        "captureSha256": capture_sha256,
        "worksheetSha256": worksheet_sha256,
        "privateMapSha256": _sha(private_bytes),
        "itemCount": 5,
        "worksheet": str(WORKSHEET),
        "privateMap": str(PRIVATE_MAP),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-sha256", required=True)
    args = parser.parse_args()
    print(json.dumps(project(args.capture_sha256), indent=2))


if __name__ == "__main__":
    main()
