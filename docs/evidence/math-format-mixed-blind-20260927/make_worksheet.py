"""Build a keyless comparison/worked/legacy math format worksheet."""

import hashlib
import json
import os
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "backend/bedrock-question-service"))

from math_comparison_task_constructor import TASK_KIND as COMPARISON_KIND  # noqa: E402
from math_comparison_task_constructor import compile_question as comparison  # noqa: E402
from math_reasoning_task_constructor import TASK_KIND as REASONING_KIND  # noqa: E402
from math_reasoning_task_constructor import compile_question as reasoning  # noqa: E402


def main() -> None:
    old_folder = ROOT / "docs/evidence/level2-quarantine-bank20-20260927"
    old_items = {item["id"]: item for item in json.loads(
        (old_folder / "worksheet.json").read_text())["items"]}
    old_map = json.loads(Path(
        "/private/tmp/checkpoint-level2-quarantine-bank20-private-20260927/answer-map.json"
    ).read_text())["mapping"]
    schedule = (
        ("old", "Q03"), ("comparison", "crossed_sums", "2_3", "forward"),
        ("reasoning", "multiply_a"), ("old", "Q06"),
        ("comparison", "crossed_products", "5_3", "reverse"),
        ("reasoning", "divide_b"), ("old", "Q08"),
        ("comparison", "crossed_sums", "4_5", "forward"),
        ("reasoning", "multiply_c"), ("old", "Q13"),
        ("old", "Q17"), ("old", "Q20"),
    )
    worksheet = []
    answers = {}
    source = {}
    for index, spec in enumerate(schedule):
        label = f"M{index + 1:02d}"
        if spec[0] == "old":
            prior = old_items[spec[1]]
            prompt, choices = prior["prompt"], prior["choices"]
            key = old_map[spec[1]]["key"]
        else:
            task = ({"kind": COMPARISON_KIND, "family": spec[1],
                     "pair": spec[2], "order": spec[3]}
                    if spec[0] == "comparison" else
                    {"kind": REASONING_KIND, "scene": spec[1]})
            question = (comparison(task, ordinal=index % 4)
                        if spec[0] == "comparison" else
                        reasoning(task, ordinal=index % 4))
            prompt = question["prompt"]
            choices = dict(zip("ABCD", question["choices"], strict=True))
            key = next(letter for letter, text in choices.items()
                       if text == question["expectedAnswer"])
        assert len(choices) == 4 and key in choices
        worksheet.append({"id": label, "prompt": prompt, "choices": choices})
        answers[label] = key
        source[label] = spec
    output = HERE / "worksheet.json"
    output.write_text(json.dumps({"status": "keyless", "targetDifficulty": 2,
                                  "items": worksheet}, indent=2) + "\n")
    private = Path("/private/tmp/checkpoint-math-format-mixed-blind-20260927")
    private.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(private, 0o700)
    with (private / "answer-map.json").open("w") as stream:
        os.fchmod(stream.fileno(), 0o600)
        json.dump({"answers": answers, "source": source}, stream, indent=2)
        stream.write("\n")
    print(hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
