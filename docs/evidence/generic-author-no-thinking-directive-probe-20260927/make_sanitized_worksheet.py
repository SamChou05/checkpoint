"""Freeze a keyless worksheet from the six sanitized author-only candidates."""

import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import random
import secrets

from question_quality import _sanitize_questions


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CAPTURE = HERE / "capture.json"
PLAN = HERE / "plan.json"
WORKSHEET = HERE / "worksheet.json"
PRIVATE = Path("/private/tmp/checkpoint-generic-author-no-thinking-directive-probe-20260927")
ANSWER_MAP = PRIVATE / "answer-map.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_order(seed, capture_hash, ordinals):
    for counter in range(1024):
        order = sorted(range(len(ordinals)), key=lambda position: hmac.new(
            seed, f"source:{capture_hash}:{counter}:{position}".encode(), hashlib.sha256,
        ).digest())
        if all(public != position and public + 1 != ordinals[position]
               for public, position in enumerate(order)):
            return order
    raise ValueError("Could not construct a source-blind public order.")


def create(capture_hash, *, seed=None):
    if digest(CAPTURE) != capture_hash:
        raise ValueError("Capture SHA-256 differs from reviewed input.")
    if WORKSHEET.exists() or ANSWER_MAP.exists():
        raise FileExistsError("Worksheet or private map already exists.")
    capture = json.loads(CAPTURE.read_text())
    plan = json.loads(PLAN.read_text())
    relative = "backend/bedrock-question-service/question_quality.py"
    if digest(ROOT / relative) != plan["source_hashes"][relative]:
        raise ValueError("Sanitizer source differs from frozen author source.")
    rows = capture.get("author_rows")
    if (capture.get("status") != "completed"
            or capture.get("author_outcome") != "seven_native_rows"
            or type(rows) is not list or len(rows) != 7):
        raise ValueError("Capture has no complete seven-row native author object.")
    request = {**plan["request"], "targetCount": 7}
    metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
    sanitized = _sanitize_questions(
        rows, request, metrics, preserve_authored_explanation=True,
    )
    if not (len(sanitized) == 6 and metrics.get("QuestionQuality", {}).get("sanitize")
            == {"accepted": 6, "duplicate_choices": 1}):
        raise ValueError("Unexpected sanitizer result for this frozen author output.")
    prior = []
    bound = []
    for ordinal in range(7):
        prefix = _sanitize_questions(
            rows[:ordinal + 1], request, None, preserve_authored_explanation=True,
        )
        if not (prefix[:len(prior)] == prior
                and len(prefix) in (len(prior), len(prior) + 1)):
            raise ValueError("Sanitizer prefix replay was not monotone.")
        if len(prefix) == len(prior) + 1:
            bound.append((ordinal, prefix[-1]))
        prior = prefix
    if prior != sanitized or len(bound) != 6:
        raise ValueError("Sanitizer prefix replay differs from the complete pass.")
    seed = secrets.token_bytes(32) if seed is None else seed
    if type(seed) is not bytes or len(seed) != 32:
        raise ValueError("Worksheet seed must contain 32 private bytes.")
    ordinals = [ordinal for ordinal, _ in bound]
    order = source_order(seed, capture_hash, ordinals)
    items = []
    answers = {}
    for public, position in enumerate(order):
        ordinal, question = bound[position]
        choices = question["choices"]
        answer = question["expectedAnswer"]
        if not (len(choices) == len(set(choices)) == 4 and choices.count(answer) == 1):
            raise ValueError("Sanitized question has no unique listed key.")
        scrambled = choices[:]
        random.Random(int.from_bytes(hmac.new(
            seed, f"choices:{capture_hash}:{ordinal}".encode(), hashlib.sha256,
        ).digest(), "big")).shuffle(scrambled)
        labeled = dict(zip("ABCD", scrambled, strict=True))
        public_id = f"P{public + 1:02d}"
        items.append({"id": public_id, "prompt": question["prompt"], "choices": labeled})
        answers[public_id] = {"source_ordinal": ordinal, "sanitized_position": position,
                              "key": next(letter for letter, text in labeled.items()
                                          if text == answer)}
    PRIVATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(PRIVATE, 0o700)
    descriptor = os.open(ANSWER_MAP, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump({"capture_sha256": capture_hash, "seed_hex": seed.hex(),
                   "answers": answers}, stream, indent=2)
        stream.write("\n")
    with WORKSHEET.open("x") as stream:
        json.dump({"status": "keyless_author_sanitized_six", "requestedDifficulty": 2,
                   "items": items}, stream, indent=2)
        stream.write("\n")
    return digest(WORKSHEET)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-sha256", required=True)
    args = parser.parse_args()
    print(create(args.capture_sha256))


if __name__ == "__main__":
    main()
