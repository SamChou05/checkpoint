"""Freeze a keyless 20-item replay for the two roles of ``each``.

The private answer map is written only to CHECKPOINT_PRIVATE_MAP_DIR. Once
written, worksheet and summary bytes are immutable; reruns verify them.
No provider, queue, bank, or AWS operation occurs.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ORIGINAL = ROOT / "docs/evidence/current-20-bank-blind-20260927/prepare.py"
PRIVATE = Path(os.environ["CHECKPOINT_PRIVATE_MAP_DIR"])
spec = importlib.util.spec_from_file_location("original_bank_sample", ORIGINAL)
assert spec and spec.loader
original = importlib.util.module_from_spec(spec)
spec.loader.exec_module(original)


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _check_source(seed: dict) -> None:
    if seed["batchCount"] != 4 or seed["providerCalls"] != 0:
        raise AssertionError("Unexpected sample design")
    capture = ROOT / seed["sourceEvidence"]
    raw = json.loads(json.loads(capture.read_text())["author_response"]
                     ["output"]["message"]["content"][0]["text"])
    if raw["questions"] != seed["sourceTaskSeed"]:
        raise AssertionError("Frozen author task differs from capture")


def _locked(path: Path, rendered: str) -> None:
    if path.exists():
        if path.read_text() != rendered:
            raise AssertionError(f"Frozen output changed: {path}")
    else:
        path.write_text(rendered)


def main() -> None:
    original._check_source = _check_source
    classify = original._english_family
    original._english_family = (
        lambda scene: "partitive" if scene in original.agreement.PARTITIVE_SCENES
        else classify(scene)
    )
    worksheet, answer_map, summary = original.prepare()
    seed = ORIGINAL.parent / "seed.json"
    if summary["seedSha256"] != _sha(seed):
        raise AssertionError("Seed changed")
    _locked(HERE / "worksheet.json", original._render(worksheet))
    _locked(HERE / "summary.json", original._render(summary))
    PRIVATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    private_path = PRIVATE / "answer-map.json"
    _locked(private_path, original._render(answer_map))
    private_path.chmod(0o600)
    print(json.dumps({"items": summary["items"],
                      "worksheetSha256": summary["worksheetSha256"],
                      "providerCalls": summary["providerCalls"]}))


if __name__ == "__main__":
    main()
