"""Project the five offline-compiled author candidates into a keyless worksheet."""

import hashlib
import json
import os
from pathlib import Path
import secrets

HERE = Path(__file__).resolve().parent
REPLAY_SHA256 = "00e3d6638a6095bc0edddf668388f76ca893c1d51be23606d2f64a6254c99722"
CAPTURE_SHA256 = "17575d5a62b1fde235c3d43c7c9bc1d9e40385466e30b973fde1ca9cf1bbc9aa"
OUT = HERE / "blind-official"
PRIVATE = HERE / "blind-private.json"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def write_new(path, raw, *, private=False):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600 if private else 0o644)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    return sha(raw)


def project():
    raw = (HERE / "offline-replay.json").read_bytes()
    if sha(raw) != REPLAY_SHA256 or sha((HERE / "capture.json").read_bytes()) != CAPTURE_SHA256:
        raise ValueError("Frozen replay or capture changed")
    replay = json.loads(raw)
    if (replay["classification"] != "native_author_and_offline_compiler_pass_probe_bookkeeping_failed"
            or replay["sanitized_rows"] != 5 or len(replay["candidate_questions"]) != 5
            or OUT.exists() or PRIVATE.exists()):
        raise ValueError("One-shot five-candidate projection is unavailable")
    items, mapping = [], {}
    for slot, question in enumerate(replay["candidate_questions"]):
        choices = question["choices"]
        key = question["expectedAnswer"]
        if (len(choices) != 4 or len(set(choices)) != 4 or choices.count(key) != 1):
            raise ValueError("Question lacks one literal key and four distinct choices")
        identity = secrets.token_hex(12)
        while identity in mapping:
            identity = secrets.token_hex(12)
        indices = list(range(4))
        secrets.SystemRandom().shuffle(indices)
        display = {letter: choices[index] for letter, index in zip("ABCD", indices, strict=True)}
        items.append({"id": identity, "stem": question["prompt"], "choices": display})
        mapping[identity] = {
            "original_author_slot": slot, "display_to_source_index": indices,
            "correct_display_label": next(letter for letter, literal in display.items() if literal == key),
        }
    secrets.SystemRandom().shuffle(items)
    OUT.mkdir(exist_ok=False)
    worksheet = {"version": 1, "kind": "author_only_offline_compiled_candidate_review",
                 "candidate_count": 5, "items": items}
    rubric = (
        "# Blind content review of one native author response\n\n"
        "These five questions were compiled and sanitized offline from one live native author response. "
        "They were not returned by the full worker. IDs, item order and display choices are randomized. "
        "The source slots, answer keys, family labels, authored teaching and capture are withheld. "
        "Do not open the trial branch, capture or private map until both reviews lock.\n\n"
        "For each item, select its one correct letter or mark ambiguous/unsupported. Judge all six "
        "within-item choice pairs for meaningful distinctness, stem self-containment, objective visible "
        "from the stem, difficulty 1–5, and within-batch novelty. Record uncertainty. A separate "
        "teaching audit follows review lock.\n"
    )
    worksheet_sha = write_new(OUT / "worksheet.json",
                              (json.dumps(worksheet, indent=2, ensure_ascii=False) + "\n").encode())
    rubric_sha = write_new(OUT / "RUBRIC.md", rubric.encode())
    private_sha = write_new(PRIVATE,
                            (json.dumps({"version": 1, "capture_sha256": CAPTURE_SHA256,
                                         "replay_sha256": REPLAY_SHA256,
                                         "worksheet_sha256": worksheet_sha,
                                         "mapping": mapping}, indent=2) + "\n").encode(),
                            private=True)
    return {"worksheet_sha256": worksheet_sha, "rubric_sha256": rubric_sha,
            "private_map_sha256": private_sha, "readable": len(items), "unavailable": 0}


if __name__ == "__main__":
    print(json.dumps(project(), indent=2))
