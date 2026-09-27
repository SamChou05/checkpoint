"""Build a keyless, deterministic worksheet from all five sanitized candidates.

The private key/slot map lives outside Git. This script makes no provider calls.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat


HERE = Path(__file__).resolve().parent
CAPTURE = HERE.parent / "capture.json"
CAPTURE_SHA256 = "fe66f66fe9bc1b8eefa62c167447e73a62d41cf362850a3db8cbc912298af31d"
WORKSHEET = HERE / "worksheet.json"
PRIVATE_DIR = Path("/private/tmp/checkpoint-v12-full-worker-private-20260927")
PRIVATE_MAP = PRIVATE_DIR / "answer-map.json"
ITEM_SEED = b"checkpoint-v12-worker-all-five-item-order-20260927-v1"
CHOICE_SEED = b"checkpoint-v12-worker-all-five-choice-order-20260927-v1"
LABELS = "ABCD"


def _digest(seed: bytes, number: int, secondary: int = 0) -> bytes:
    return hashlib.sha256(
        seed + number.to_bytes(2, "big") + secondary.to_bytes(2, "big")
    ).digest()


def _encoded(value: dict) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def build() -> tuple[bytes, bytes]:
    raw = CAPTURE.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == CAPTURE_SHA256, "Capture SHA-256 changed"
    capture = json.loads(raw)
    assert len(capture["jobs"]) == 1
    job = capture["jobs"][0]
    assert len(job["passes"]) == 1
    sanitized = job["passes"][0]["sanitized"]
    assert len(sanitized) == 5
    by_slot = {}
    for candidate in sanitized:
        assert candidate["original_slot_ordinals"] == [candidate["index"]]
        slot = candidate["index"]
        assert type(slot) is int and slot not in by_slot
        question = candidate["question"]
        assert type(question["prompt"]) is str and question["prompt"]
        choices = question["choices"]
        assert (type(choices) is list and len(choices) == 4
                and all(type(value) is str and value for value in choices)
                and len(set(choices)) == 4)
        assert choices.count(question["expectedAnswer"]) == 1
        by_slot[slot] = question
    assert set(by_slot) == set(range(5))
    # This must be the all-candidate view, including the slot omitted from the
    # four returned questions. No review decision is copied to the worksheet.
    assert set(job["returned_slot_ordinals"]) == {0, 1, 2, 3}

    item_order = sorted(by_slot, key=lambda slot: _digest(ITEM_SEED, slot))
    public_items = []
    private_mapping = {}
    for index, slot in enumerate(item_order, start=1):
        question = by_slot[slot]
        choice_order = sorted(range(4), key=lambda choice: _digest(CHOICE_SEED, slot, choice))
        displayed = {
            label: question["choices"][choice_index]
            for label, choice_index in zip(LABELS, choice_order, strict=True)
        }
        item_id = f"Q{index:02d}"
        public_items.append({
            "id": item_id,
            "prompt": question["prompt"],
            "choices": displayed,
        })
        key = next(label for label, text in displayed.items()
                   if text == question["expectedAnswer"])
        private_mapping[item_id] = {
            "originalSlot": slot,
            "key": key,
            "expectedAnswer": question["expectedAnswer"],
            "displayedChoices": displayed,
        }
    worksheet_bytes = _encoded({"items": public_items})
    worksheet_sha256 = hashlib.sha256(worksheet_bytes).hexdigest()
    private_bytes = _encoded({
        "captureSha256": CAPTURE_SHA256,
        "worksheetSha256": worksheet_sha256,
        "mapping": private_mapping,
    })
    return worksheet_bytes, private_bytes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="Compare existing outputs without writing")
    args = parser.parse_args()
    worksheet_bytes, private_bytes = build()
    if args.verify:
        assert WORKSHEET.read_bytes() == worksheet_bytes, "Worksheet differs from deterministic build"
        assert PRIVATE_MAP.read_bytes() == private_bytes, "Private map differs from deterministic build"
        assert stat.S_IMODE(PRIVATE_MAP.stat().st_mode) == 0o600, "Private map mode is not 0600"
    else:
        WORKSHEET.write_bytes(worksheet_bytes)
        PRIVATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
        PRIVATE_DIR.chmod(0o700)
        descriptor = os.open(PRIVATE_MAP, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(private_bytes)
        finally:
            PRIVATE_MAP.chmod(0o600)
    print(json.dumps({
        "captureSha256": CAPTURE_SHA256,
        "worksheetSha256": hashlib.sha256(worksheet_bytes).hexdigest(),
        "itemCount": 5,
        "worksheet": str(WORKSHEET),
        "privateMap": str(PRIVATE_MAP),
        "verified": args.verify,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
