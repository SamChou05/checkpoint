"""Freeze a chronological, answer-blind 20-item sample after selector balancing.

This reuses the pinned 80-item constructor replay without changing its frozen
artifacts. The answer map is written only to CHECKPOINT_PRIVATE_MAP_DIR.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import random
import subprocess


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE_COMMIT = "01439703d647ab17246c4f9c821a4dd05b5b2a99"
PRIOR = ROOT / "docs/evidence/combined-current-bank-replay-20260927/replay.py"
spec = importlib.util.spec_from_file_location("pinned_bank_replay", PRIOR)
assert spec and spec.loader
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)


def _render(value: object) -> str:
    return json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _freeze(path: Path, value: object) -> None:
    rendered = _render(value)
    if path.exists():
        if path.read_text() != rendered:
            raise AssertionError(f"Frozen output changed: {path}")
    else:
        path.write_text(rendered)


def _source_tasks() -> dict:
    changed = subprocess.run(
        ("git", "diff", "--quiet", SOURCE_COMMIT, "--", "backend/bedrock-question-service"),
        cwd=ROOT, check=False,
    )
    if changed.returncode:
        raise AssertionError("Backend source changed after pinned selector commit")
    if _sha(replay.SOURCE_CAPTURE.read_bytes()) != replay.CAPTURE_SHA256:
        raise AssertionError("Accepted author capture changed")
    source = json.loads(json.loads(replay.SOURCE_CAPTURE.read_text())
                        ["author_response"]["output"]["message"]["content"][0]
                        ["text"])["questions"]
    if source != json.loads(replay.SOURCE_SEED.read_text())["sourceTaskSeed"]:
        raise AssertionError("Source tasks differ from accepted capture")
    return source


def simulate() -> tuple[dict, dict, dict]:
    captured: list[tuple[list, dict, dict, list]] = []
    original_prepare = replay.agreement.prepare_mapped_agreement_rows
    original_source = replay._source_tasks  # noqa: SLF001

    def record(*args, **kwargs):
        result = original_prepare(*args, **kwargs)
        if len(captured) < 16:
            captured.append(result)
        return result

    replay._source_tasks = _source_tasks  # noqa: SLF001
    replay.agreement.prepare_mapped_agreement_rows = record
    try:
        prior_summary, _, _ = replay.simulate()
    finally:
        replay.agreement.prepare_mapped_agreement_rows = original_prepare
        replay._source_tasks = original_source  # noqa: SLF001

    if len(captured) != 16:
        raise AssertionError("Expected 16 complete five-item batches")
    first20 = []
    for batch, (rows, numeric, english, failures) in enumerate(captured[:4], 1):
        if failures or len(rows) != 5 or set(numeric) != {0, 1, 2} or set(english) != {3, 4}:
            raise AssertionError(f"Batch {batch} was incomplete")
        for slot, row in enumerate(rows):
            task = (numeric if slot < 3 else english)[slot]
            task.content(row)
            first20.append({"batch": batch, "slot": slot, "row": row,
                            "task": json.loads(task.task_json) if slot >= 3 else None})

    order = list(range(20))
    random.Random(2026092704).shuffle(order)
    worksheet_items = []
    private_map = {}
    for index, position in enumerate(order, 1):
        item = first20[position]
        row = item["row"]
        choices = list(row["choices"])
        random.Random(int(_sha(f'2026092705:{row["prompt"]}'.encode())[:16], 16)).shuffle(
            choices)
        displayed = dict(zip("ABCD", choices, strict=True))
        key = next(label for label, value in displayed.items()
                   if value == row["expectedAnswer"])
        question_id = f"Q{index:02d}"
        worksheet_items.append({"id": question_id, "prompt": row["prompt"],
                                "choices": displayed})
        private_map[question_id] = {**item, "key": key, "displayedChoices": displayed}

    worksheet = {"status": "offline_code_owned_candidates_not_worker_verified",
                 "targetDifficulty": "2–3", "items": worksheet_items}
    private = {"worksheetSha256": _sha(_render(worksheet).encode()),
               "mapping": private_map}
    summary = {"sourceCommit": SOURCE_COMMIT,
               "sourceCaptureSha256": replay.CAPTURE_SHA256,
               "worksheetSha256": private["worksheetSha256"],
               "worksheetSampling": "first 20 chronological items, shuffled with fixed seeds",
               "snapshots": prior_summary["snapshots"],
               "providerCalls": 0, "workerCalls": 0, "bankWrites": 0}
    return summary, worksheet, private


def main() -> None:
    summary, worksheet, private = simulate()
    _freeze(HERE / "summary.json", summary)
    _freeze(HERE / "worksheet.json", worksheet)
    private_dir = Path(os.environ["CHECKPOINT_PRIVATE_MAP_DIR"])
    private_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    private_file = private_dir / "answer-map.json"
    _freeze(private_file, private)
    private_file.chmod(0o600)
    print(_render({"worksheetSha256": summary["worksheetSha256"],
                   "items": [snapshot["items"] for snapshot in summary["snapshots"]],
                   "privateMap": str(private_file), "providerCalls": 0}))


if __name__ == "__main__":
    main()
