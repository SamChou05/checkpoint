"""Regress the archived cross-slot structural audit at its pinned source."""

import unittest

from audit import audit


class CrossSlotMechanismAuditTests(unittest.TestCase):
    def test_replayed_counts_and_capacity_proof(self):
        result = audit()
        snapshots = result["snapshots"]
        self.assertEqual(result["providerCalls"], 0)
        self.assertEqual([row["items"] for row in snapshots], [15, 40, 80])
        self.assertEqual([row["uniqueExactStems"] for row in snapshots], [15, 40, 80])
        self.assertEqual(
            [row["sameSlotFamilyPairs"] for row in snapshots], [0, 35, 175]
        )
        self.assertEqual(
            [row["reviewedPatternHeuristics"]["total"] for row in snapshots],
            [2, 18, 76],
        )
        self.assertEqual(
            [row["slot2SameDecisionPairs"] for row in snapshots], [1, 13, 60]
        )
        self.assertEqual(
            result["capacityProof"]["alternativeEnglishStems"],
            {
                "slot3WithoutProximity": 16,
                "slot4WithoutCompound": 16,
            },
        )
        self.assertTrue(
            result["capacityProof"]["proximityAndCompoundUnavoidableAt80WithReserve"]
        )


if __name__ == "__main__":
    unittest.main()
