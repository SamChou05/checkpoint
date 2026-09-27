"""Build a keyless worksheet for the standalone pronoun-role constructor.

The answer map is written outside the repository. Do not hand it to a blind
reviewer until both independent reviews have been locked.
"""

import hashlib
import json
import os
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "backend/bedrock-question-service"))

from pronoun_role_task_constructor import (  # noqa: E402
    ORDERS, SINGLE_SPEAKER_SCENES, SPEAKER_SHIFT_SCENES, TASK_KIND,
    compile_question,
)


def dump(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=True) + "\n")


def main() -> None:
    private = Path("/private/tmp/checkpoint-pronoun-constructor-blind-20260927")
    private.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(private, 0o700)
    items = []
    answers = {}
    scenes = (*SINGLE_SPEAKER_SCENES, *SPEAKER_SHIFT_SCENES)
    for index, (scene, order) in enumerate(
        (pair for scene in scenes for pair in ((scene, ORDERS[0]), (scene, ORDERS[1])))
    ):
        question = compile_question(
            {"kind": TASK_KIND, "scene": scene, "order": order}, ordinal=index % 4,
        )
        label = f"Q{index + 1:02d}"
        choices = dict(zip("ABCD", question["choices"], strict=True))
        items.append({"id": label, "prompt": question["prompt"], "choices": choices})
        answers[label] = next(key for key, text in choices.items()
                              if text == question["expectedAnswer"])
    worksheet = {"status": "keyless", "targetDifficulty": 2, "items": items}
    dump(HERE / "worksheet.json", worksheet)
    answer_path = private / "answer-map.json"
    with answer_path.open("w") as stream:
        os.fchmod(stream.fileno(), 0o600)
        json.dump(answers, stream, indent=2)
        stream.write("\n")
    print(hashlib.sha256((HERE / "worksheet.json").read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
