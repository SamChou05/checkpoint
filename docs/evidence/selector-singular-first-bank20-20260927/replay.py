"""Replay the chronological 3:2 constructor bank at source 1eff0a2 offline.

The baseline replay supplies the accepted deterministic author task, recent-30
prompt history, durable full-bank variant history, actual selectors and
compilers, and 20/40/80 structural snapshots. Only the first 20 are rendered
as a keyless worksheet; the author key map stays outside the worktree.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REFERENCE = ROOT / "docs/evidence/selector-balanced-bank20-20260927/replay.py"
CORE_REFERENCE = ROOT / "docs/evidence/combined-current-bank-replay-20260927/replay.py"
SOURCE_SEED = ROOT / "docs/evidence/current-20-bank-blind-20260927/seed.json"
SOURCE_COMMIT = "1eff0a24c5177c0df7c57284dbc724385637214d"

spec = importlib.util.spec_from_file_location("balanced_bank_replay", REFERENCE)
assert spec and spec.loader
balanced = importlib.util.module_from_spec(spec)
spec.loader.exec_module(balanced)
balanced.SOURCE_COMMIT = SOURCE_COMMIT


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _render(value: object) -> str:
    return json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def _freeze(path: Path, value: object) -> None:
    rendered = _render(value)
    if path.exists() and path.read_text() != rendered:
        raise AssertionError(f"Frozen output changed: {path}")
    if not path.exists():
        path.write_text(rendered)


def simulate() -> tuple[dict, dict, dict]:
    summary, worksheet, private = balanced.simulate()
    if summary["sourceCommit"] != SOURCE_COMMIT or len(worksheet["items"]) != 20:
        raise AssertionError("Source pin or chronological worksheet changed")

    ordered = sorted(private["mapping"].values(), key=lambda item: (item["batch"], item["slot"]))
    if [(item["batch"], item["slot"]) for item in ordered] != [
        (batch, slot) for batch in range(1, 5) for slot in range(5)
    ]:
        raise AssertionError("First-20 chronological roster changed")
    english = [
        {"batch": item["batch"], "slot": item["slot"],
         "scene": item["task"]["scene"], "order": item["task"]["order"],
         "responseFormat": (
             "full_sentence_selection" if item["task"]["scene"] in
             balanced.replay.agreement.SENTENCE_SELECTION_SCENES else "two_blank_agreement"
         )}
        for item in ordered if item["slot"] in (3, 4)
    ]
    summary = {
        **summary,
        "methodologyReferenceSha256": _sha(REFERENCE.read_bytes()),
        "coreMethodologyReferenceSha256": _sha(CORE_REFERENCE.read_bytes()),
        "sourceTaskSeedFileSha256": _sha(SOURCE_SEED.read_bytes()),
        "englishFirst20Chronological": english,
        "fullSentenceFirst20Chronological": [
            item for item in english if item["responseFormat"] == "full_sentence_selection"
        ],
    }
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
    print(_render({"sourceCommit": summary["sourceCommit"],
                   "worksheetSha256": summary["worksheetSha256"],
                   "snapshots": [snapshot["items"] for snapshot in summary["snapshots"]],
                   "fullSentenceFirst20Chronological": summary["fullSentenceFirst20Chronological"],
                   "privateMap": str(private_file), "providerCalls": 0}))


if __name__ == "__main__":
    main()
