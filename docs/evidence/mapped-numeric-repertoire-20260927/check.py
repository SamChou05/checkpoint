"""Replay the existing five-slot bank simulation against the expanded numeric inventory."""

from __future__ import annotations

from pathlib import Path
import runpy


HERE = Path(__file__).resolve().parent
BASELINE = HERE.parent / "mapped-bank-diversity-simulation-20260927" / "run.py"


def main() -> None:
    result = runpy.run_path(str(BASELINE))["simulate"]()
    checkpoints = result["checkpoints"]
    assert [(row["items"], row["uniqueExactStems"], row["sameSlotFamilyPairsTotal"])
            for row in checkpoints] == [(40, 40, 45), (80, 80, 217)]
    assert [row["sameSlotFamilyPairsBySlot"] for row in checkpoints] == [
        {"0": 7, "1": 7, "2": 7, "3": 12, "4": 12},
        {"0": 35, "1": 35, "2": 35, "3": 56, "4": 56},
    ]
    assert result["post80FailureReasons"] == ["agreement_novelty_exhausted"] * 2
    assert result["providerCalls"] == 0
    for row in checkpoints:
        print(f'{row["items"]} items: {row["uniqueExactStems"]} distinct exact stems, '
              f'{row["sameSlotFamilyPairsTotal"]} same-slot/family pairs')
    print("After 80 items: both English inventories exhausted; no provider calls")


if __name__ == "__main__":
    main()
