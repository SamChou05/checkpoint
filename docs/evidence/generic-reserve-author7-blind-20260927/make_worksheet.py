"""Make an answer-blind seven-row worksheet from terminal trial 02."""

import hashlib
import json
import os
from pathlib import Path
import random


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CAPTURE = ROOT / "docs/evidence/generic-reserve-seven-probe-v2-20260927/capture.json"
CAPTURE_SHA256 = "680d6fd8939a2fbc99eda4d0b523cd890a96399140fb6e91d222f62298c85ea4"


def main() -> None:
    assert hashlib.sha256(CAPTURE.read_bytes()).hexdigest() == CAPTURE_SHA256
    capture = json.loads(CAPTURE.read_text())
    assert len(capture["original_rows"]) == 7
    worksheet = []
    answer_map = {}
    for row in capture["original_rows"]:
        ordinal = row["ordinal"]
        question = row["sanitized_question"]
        choices = list(question["choices"])
        assert len(choices) == len(set(choices)) == 4
        key = question["expectedAnswer"]
        assert choices.count(key) == 1
        seed = int.from_bytes(hashlib.sha256(
            ("generic-seven-blind-v1:" + question["prompt"]).encode()
        ).digest()[:8], "big")
        random.Random(seed).shuffle(choices)
        letters = dict(zip("ABCD", choices, strict=True))
        label = f"G{ordinal + 1:02d}"
        worksheet.append({"id": label, "prompt": question["prompt"],
                          "choices": letters})
        answer_map[label] = {"ordinal": ordinal, "key": next(
            letter for letter, text in letters.items() if text == key
        )}
    output = HERE / "worksheet.json"
    output.write_text(json.dumps({"status": "keyless_author_only",
                                  "requestedDifficulty": 2,
                                  "items": worksheet}, indent=2) + "\n")
    private = Path("/private/tmp/checkpoint-generic-reserve-author7-blind-20260927")
    private.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(private, 0o700)
    with (private / "answer-map.json").open("w") as stream:
        os.fchmod(stream.fileno(), 0o600)
        json.dump(answer_map, stream, indent=2)
        stream.write("\n")
    print(hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
