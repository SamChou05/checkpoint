"""Build a source-ordinal-blind worksheet from this probe's terminal capture.

The answer mapping and permutation seed live only under /private/tmp, mode 0600.
This script makes no network calls and refuses to overwrite existing artifacts.
"""

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
PRIVATE = Path("/private/tmp/checkpoint-generic-author-no-thinking-directive-probe-20260927")
SEED = PRIVATE / "worksheet-seed.bin"
ANSWER_MAP = PRIVATE / "answer-map.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def private_bytes(path, data):
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        path.unlink(missing_ok=True)
        raise


def secret_source_order(seed, capture_sha256):
    """Bind public IDs to a secret, reproducible source derangement."""
    for attempt in range(1024):
        order = sorted(range(7), key=lambda ordinal: hmac.digest(
            seed, f"author-only-row-order-v1:{capture_sha256}:{attempt}:{ordinal}".encode(),
            "sha256"))
        if all(public_index != ordinal for public_index, ordinal in enumerate(order)):
            return order
    raise ValueError("Could not create a source-ordinal-blind permutation.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-sha256", required=True)
    args = parser.parse_args()
    if not CAPTURE.is_file() or sha(CAPTURE) != args.capture_sha256:
        raise ValueError("Terminal capture hash differs from the reviewed input.")
    if WORKSHEET.exists() or ANSWER_MAP.exists() or SEED.exists():
        raise ValueError("Worksheet or private map already exists.")
    capture = json.loads(CAPTURE.read_text(encoding="utf-8"))
    rows = capture.get("author_rows")
    if (capture.get("status") != "completed"
            or capture.get("author_outcome") != "seven_native_rows"
            or capture.get("worker_qualified") is not False
            or not isinstance(rows, list) or len(rows) != 7):
        raise ValueError("Capture does not contain seven complete native author rows.")
    for source in rows:
        choices = source.get("choices")
        key = source.get("expectedAnswer")
        if not isinstance(choices, list) or len(choices) != 4 or len(set(choices)) != 4:
            raise ValueError("Author row lacks four distinct choices.")
        if choices.count(key) != 1 or not isinstance(source.get("prompt"), str):
            raise ValueError("Author row has no unique model-selected answer.")
    PRIVATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(PRIVATE, 0o700)
    seed = secrets.token_bytes(32)
    private_bytes(SEED, seed)
    order = secret_source_order(seed, args.capture_sha256)
    worksheet = []
    answers = {}
    for displayed_index, source_ordinal in enumerate(order, start=1):
        source = rows[source_ordinal]
        choices = source.get("choices")
        key = source.get("expectedAnswer")
        shuffled = choices[:]
        choice_random = int.from_bytes(hmac.digest(
            seed, f"author-only-choice-order-v1:{source_ordinal}".encode(), "sha256"), "big")
        random.Random(choice_random).shuffle(shuffled)
        choice_map = dict(zip("ABCD", shuffled, strict=True))
        item_id = f"Q{displayed_index:02d}"
        worksheet.append({"id": item_id, "prompt": source["prompt"],
                          "choices": choice_map})
        answers[item_id] = {"source_ordinal": source_ordinal,
                            "key": next(letter for letter, text in choice_map.items()
                                        if text == key)}
    private_bytes(ANSWER_MAP, (json.dumps({"capture_sha256": args.capture_sha256,
                                           "answers": answers}, indent=2) + "\n").encode())
    with WORKSHEET.open("x", encoding="utf-8") as stream:
        json.dump({"status": "keyless_author_only", "requested_difficulty": 2,
                   "items": worksheet}, stream, indent=2)
        stream.write("\n")
    print(json.dumps({"worksheet_sha256": sha(WORKSHEET), "items": len(worksheet),
                      "author_only": True}, sort_keys=True))


if __name__ == "__main__":
    main()
