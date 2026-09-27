"""Create a keyless seven-row author worksheet after a pinned successful capture."""

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
PRIVATE = Path("/private/tmp/checkpoint-generic-probability-directive-author-probe-20260927")


def _secret_source_order(seed, capture_sha256):
    """Assign public positions with a keyed, reproducible derangement."""
    for counter in range(1024):
        order = sorted(range(7), key=lambda ordinal: hmac.new(
            seed, f"source:{capture_sha256}:{counter}:{ordinal}".encode(),
            hashlib.sha256,
        ).digest())
        if all(public_index != ordinal for public_index, ordinal in enumerate(order)):
            return order
    raise ValueError("Could not create a provenance-blind source permutation.")


def create(capture_path, expected_sha256, worksheet_path, private_directory, *, seed=None):
    actual_sha256 = hashlib.sha256(capture_path.read_bytes()).hexdigest()
    if actual_sha256 != expected_sha256:
        raise ValueError("Capture bytes differ from the reviewed SHA-256.")
    capture = json.loads(capture_path.read_text())
    rows = capture.get("original_rows")
    if (capture.get("summary", {}).get("qualification") != "pending_author_content_review"
            or capture.get("summary", {}).get("worker_qualified") is not False
            or type(rows) is not list or len(rows) != 7
            or [row.get("ordinal") for row in rows] != list(range(7))
            or any(row.get("status") != "sanitized" for row in rows)):
        raise ValueError("Capture is not a complete seven-row author-only result.")
    if worksheet_path.exists():
        raise FileExistsError("Keyless worksheet already exists.")
    private_directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(private_directory, 0o700)
    private_map = private_directory / "answer-map.json"
    if private_map.exists():
        raise FileExistsError("Private answer map already exists.")
    seed = secrets.token_bytes(32) if seed is None else seed
    if type(seed) is not bytes or len(seed) != 32:
        raise ValueError("Worksheet seed must contain 32 secret bytes.")
    items = []
    keys = {}
    for public_index, ordinal in enumerate(_secret_source_order(seed, expected_sha256)):
        row = rows[ordinal]
        ordinal = row["ordinal"]
        question = row["sanitized_question"]
        choices = list(question["choices"])
        if len(choices) != 4 or len(set(choices)) != 4:
            raise ValueError("An authored item has non-distinct choices.")
        answer = question["expectedAnswer"]
        if choices.count(answer) != 1:
            raise ValueError("An authored item lacks one offered key.")
        choice_seed = int.from_bytes(hmac.new(
            seed, f"choices:{expected_sha256}:{ordinal}".encode(),
            hashlib.sha256,
        ).digest(), "big")
        random.Random(choice_seed).shuffle(choices)
        letter_choices = dict(zip("ABCD", choices, strict=True))
        label = f"P{public_index + 1:02d}"
        items.append({"id": label, "prompt": question["prompt"],
                      "choices": letter_choices})
        keys[label] = {"ordinal": ordinal, "key": next(
            letter for letter, text in letter_choices.items() if text == answer
        )}
    with private_map.open("x") as stream:
        os.fchmod(stream.fileno(), 0o600)
        json.dump({"capture_sha256": expected_sha256, "seed_hex": seed.hex(),
                   "items": keys}, stream, indent=2)
        stream.write("\n")
    with worksheet_path.open("x") as stream:
        json.dump({"status": "keyless_author_only", "requestedDifficulty": 2,
                   "items": items}, stream, indent=2)
        stream.write("\n")
    return hashlib.sha256(worksheet_path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-sha256", required=True)
    args = parser.parse_args()
    print(create(CAPTURE, args.capture_sha256, WORKSHEET, PRIVATE))


if __name__ == "__main__":
    main()
