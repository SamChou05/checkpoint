"""Replay the closed mapped bank and count reviewed mechanism-pattern collisions.

These counts are structural heuristics extrapolated from the archived blind
consensus. They are not judgments that every counted pair is a semantic duplicate.
"""

from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[3]
TESTS = ROOT / "backend/bedrock-question-service/tests"
sys.path.insert(0, str(TESTS))

from mapped_bank_capacity_harness import _catalog, simulate  # noqa: E402


TARGETS = (15, 40, 80)


def _pairs(count: int) -> int:
    return count * (count - 1) // 2


def audit() -> dict:
    """Return reproducible counts from the current code-owned compilers."""
    replay = simulate(TARGETS)
    if replay["exhaustion"] is not None or len(replay["snapshots"]) != len(TARGETS):
        raise ValueError("The mapped bank cannot reach every audit target.")
    catalog = {slot: dict(Counter(_catalog()[slot].values())) for slot in (2, 3, 4)}
    if catalog[3] != {"proximity": 8, "inversion": 8, "relative": 8} or catalog[4] != {
        "compound": 8,
        "number": 8,
        "correlative": 8,
    }:
        raise ValueError("English repertoire changed; revisit the capacity proof.")
    if set(catalog[2]) != {
        "bounded_ratio_threshold",
        "bounded_quadratic_maximum",
        "bounded_linear_budget_maximum",
    }:
        raise ValueError("Numeric mechanisms changed; revisit the pair classification.")

    snapshots = []
    for snapshot in replay["snapshots"]:
        slot2 = snapshot["slots"]["2"]["familyUses"]
        slot3 = snapshot["slots"]["3"]["familyUses"]
        slot4 = snapshot["slots"]["4"]["familyUses"]
        proximity = slot3.get("proximity", 0)
        compound = slot4.get("compound", 0)
        quadratic_maximum = slot2.get("bounded_quadratic_maximum", 0)
        linear_maximum = slot2.get("bounded_linear_budget_maximum", 0)
        minimum = slot2.get("bounded_ratio_threshold", 0)
        maximum = quadratic_maximum + linear_maximum
        if snapshot["uniqueExactStems"] != snapshot["items"]:
            raise ValueError("The mapped bank replay repeated an exact stem.")
        snapshots.append(
            {
                "items": snapshot["items"],
                "uniqueExactStems": snapshot["uniqueExactStems"],
                "sameSlotFamilyPairs": snapshot["sameSlotFamilyPairs"],
                "slot3Proximity": proximity,
                "slot4Compound": compound,
                "slot2QuadraticMaximum": quadratic_maximum,
                "slot2LinearMaximum": linear_maximum,
                "slot2RatioMinimum": minimum,
                "reviewedPatternHeuristics": {
                    "proximityVsCompound": proximity * compound,
                    "compoundVsCompound": _pairs(compound),
                    "quadraticMaxVsLinearMax": quadratic_maximum * linear_maximum,
                    "total": proximity * compound
                    + _pairs(compound)
                    + quadratic_maximum * linear_maximum,
                },
                "slot2SameDecisionPairs": _pairs(maximum) + _pairs(minimum),
            }
        )

    # Each English family has four scenes and two orders. At 80 items there
    # are 16 rows per English slot. Excluding either reviewed-overlap family
    # leaves exactly 16 stems, so retaining one spare forces both to appear.
    alternative_stems = {
        "slot3WithoutProximity": catalog[3]["inversion"] + catalog[3]["relative"],
        "slot4WithoutCompound": catalog[4]["number"] + catalog[4]["correlative"],
    }
    items_per_slot = 80 // 5
    spare_stems = 1
    if any(
        items_per_slot + spare_stems <= count for count in alternative_stems.values()
    ):
        raise ValueError("The 80-item capacity proof no longer holds.")
    return {
        "status": "offline_structural_heuristic_not_blind_review_or_worker_qualification",
        "targets": list(TARGETS),
        "snapshots": snapshots,
        "capacityProof": {
            "slot2SubstantiveDecisions": 2,
            "slot2FirstThreeMinimumSameDecisionPairs": 1,
            "englishItemsPerSlotAt80": items_per_slot,
            "englishSpareStemsPerSlot": spare_stems,
            "alternativeEnglishStems": alternative_stems,
            "proximityAndCompoundUnavoidableAt80WithReserve": True,
        },
        "providerCalls": replay["providerCalls"],
    }


if __name__ == "__main__":
    print(json.dumps(audit(), indent=2))
