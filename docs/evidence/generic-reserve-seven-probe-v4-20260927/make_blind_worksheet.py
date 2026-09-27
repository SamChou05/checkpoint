"""Freeze a source-order-blind worksheet from the terminal five-row worker capture."""

import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import random
import secrets


HERE = Path(__file__).resolve().parent
CAPTURE = HERE / "capture.json"
WORKSHEET = HERE / "worksheet.json"
PRIVATE = Path("/private/tmp/checkpoint-generic-reserve-seven-probe-v4-20260927")
ANSWER_MAP = PRIVATE / "answer-map.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def secret_order(seed, capture_hash, source_ordinals):
    count = len(source_ordinals)
    for counter in range(1024):
        order = sorted(range(count), key=lambda position: hmac.new(
            seed, f"source:{capture_hash}:{counter}:{position}".encode(), hashlib.sha256,
        ).digest())
        if all(public != position and public + 1 != source_ordinals[position]
               for public, position in enumerate(order)):
            return order
    raise ValueError("Could not construct a source-blind public order.")


def create(expected_capture_hash, *, seed=None):
    if digest(CAPTURE) != expected_capture_hash:
        raise ValueError("Terminal capture differs from reviewed SHA-256.")
    if WORKSHEET.exists() or ANSWER_MAP.exists():
        raise FileExistsError("A worksheet or private answer map already exists.")
    capture = json.loads(CAPTURE.read_text())
    job = capture["jobs"][0]
    rows = job["returned"]
    source_ordinals = job["returned_source_ordinals"]
    if not (capture["summary"]["qualification"] == "pending_content_review"
            and capture["global_stop"] is None and job["status"] == "finished"
            and len(capture["calls"]) == len(capture["reservations"]) == 5
            and len(rows) == len(source_ordinals) == 5
            and source_ordinals == job["accepted_source_ordinals"][:5]
            and len(set(source_ordinals)) == 5):
        raise ValueError("Capture is not the five-question successful worker result.")
    seed = secrets.token_bytes(32) if seed is None else seed
    if type(seed) is not bytes or len(seed) != 32:
        raise ValueError("Worksheet seed must be exactly 32 secret bytes.")
    order = secret_order(seed, expected_capture_hash, source_ordinals)
    items = []
    answers = {}
    for public, position in enumerate(order):
        question = rows[position]
        choices = question["choices"]
        key = question["expectedAnswer"]
        if not (type(choices) is list and len(choices) == len(set(choices)) == 4
                and choices.count(key) == 1
                and question.get("verificationPolicyRevision") == 7):
            raise ValueError("Returned row lacks a unique offered key or policy seven.")
        scrambled = choices[:]
        choice_seed = int.from_bytes(hmac.new(
            seed, f"choice:{expected_capture_hash}:{position}".encode(), hashlib.sha256,
        ).digest(), "big")
        random.Random(choice_seed).shuffle(scrambled)
        labeled = dict(zip("ABCD", scrambled, strict=True))
        public_id = f"Q{public + 1:02d}"
        items.append({"id": public_id, "prompt": question["prompt"], "choices": labeled})
        answers[public_id] = {
            "source_ordinal": source_ordinals[position],
            "return_position": position,
            "key": next(letter for letter, text in labeled.items() if text == key),
        }
    PRIVATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(PRIVATE, 0o700)
    descriptor = os.open(ANSWER_MAP, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump({"capture_sha256": expected_capture_hash, "seed_hex": seed.hex(),
                   "answers": answers}, stream, indent=2)
        stream.write("\n")
    with WORKSHEET.open("x") as stream:
        json.dump({"status": "keyless_full_worker_pending_content_review",
                   "requestedDifficulty": 2, "items": items}, stream, indent=2)
        stream.write("\n")
    return digest(WORKSHEET)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-sha256", required=True)
    args = parser.parse_args()
    print(create(args.capture_sha256))


if __name__ == "__main__":
    main()
