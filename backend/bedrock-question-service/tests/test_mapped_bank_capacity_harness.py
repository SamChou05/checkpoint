"""The bank-capacity gate must see structural reuse despite unique stems."""

import unittest

from mapped_bank_capacity_harness import qualification_failures, simulate


class MappedBankCapacityHarnessTests(unittest.TestCase):
    def test_repeated_bank_uses_current_compilers_and_full_history(self):
        report = simulate((40, 80, 85))
        self.assertEqual(report["providerCalls"], 0)
        self.assertIsNone(report["exhaustion"])
        self.assertEqual([row["items"] for row in report["snapshots"]], [40, 80, 85])
        for snapshot in report["snapshots"]:
            self.assertEqual(snapshot["uniqueExactStems"], snapshot["items"])
            for row in snapshot["slots"].values():
                self.assertEqual(row["items"], snapshot["items"] // 5)
                self.assertEqual(sum(row["familyUses"].values()), row["items"])
                self.assertEqual(row["sameFamilyPairs"], sum(
                    count * (count - 1) // 2 for count in row["familyUses"].values()))
                self.assertEqual(row["remainingExactStems"],
                                 row["exactStemCapacity"] - row["items"])
        # This baseline is an upper bound: adding real families should reduce
        # reuse rather than require rewriting the test to preserve old counts.
        self.assertLessEqual(report["snapshots"][0]["sameSlotFamilyPairs"], 60)
        self.assertLessEqual(report["snapshots"][1]["sameSlotFamilyPairs"], 280)
        self.assertLessEqual(report["snapshots"][2]["sameSlotFamilyPairs"], 188)
        self.assertEqual(report["snapshots"][1]["slots"]["1"]["substantiveFamilyCapacity"], 5)
        self.assertEqual(report["snapshots"][1]["slots"]["1"]["sameFamilyPairs"], 18)
        for snapshot in report["snapshots"]:
            self.assertEqual(snapshot["slots"]["4"]["exactStemCapacity"], 32)
            self.assertIn("correlative", snapshot["slots"]["4"]["familyUses"])
            self.assertIn("gerund", snapshot["slots"]["4"]["familyUses"])
        self.assertEqual(report["snapshots"][2]["slots"]["4"]["remainingExactStems"], 15)

    def test_unique_stems_do_not_override_family_capacity_gate(self):
        report = {"targets": (40,), "exhaustion": None, "snapshots": [{
            "items": 40, "uniqueExactStems": 40,
            "slots": {"3": {
                "items": 8, "substantiveFamilyCapacity": 2,
                "exactStemCapacity": 16, "remainingExactStems": 8,
                "familyUses": {"proximity": 4, "inversion": 4},
                "sameFamilyPairs": 12,
            }},
        }]}
        failures = qualification_failures(report)
        self.assertEqual(len(failures), 3)
        self.assertIn("slot 3: only 2 substantive families for 8 items", failures[0])
        self.assertIn("need 8", failures[0])
        self.assertIn("proximity used 4 times", failures[1])
        self.assertIn("inversion used 4 times", failures[2])

    def test_exhausted_exact_stems_and_unavailable_target_fail_clearly(self):
        report = {"targets": (80, 85),
                  "exhaustion": {"atItems": 80,
                                 "failureReasons": ["agreement_novelty_exhausted"]},
                  "snapshots": [{"items": 80, "uniqueExactStems": 80,
                                 "slots": {"4": {
                                     "items": 16, "substantiveFamilyCapacity": 16,
                                     "exactStemCapacity": 16, "remainingExactStems": 0,
                                     "familyUses": {}, "sameFamilyPairs": 0,
                                 }}}]}
        failures = qualification_failures(report)
        self.assertEqual(len(failures), 2)
        self.assertIn("slot 4: only 0 unused exact stems", failures[0])
        self.assertIn("85 items unavailable", failures[1])
        self.assertIn("agreement_novelty_exhausted", failures[1])

    def test_capacity_alone_does_not_hide_overused_family(self):
        report = {"targets": (40,), "exhaustion": None, "snapshots": [{
            "items": 40, "uniqueExactStems": 40,
            "slots": {"0": {
                "items": 8, "substantiveFamilyCapacity": 8,
                "exactStemCapacity": 80, "remainingExactStems": 72,
                "familyUses": {"one_reused_family": 8}, "sameFamilyPairs": 28,
            }},
        }]}
        failures = qualification_failures(report)
        self.assertEqual(failures, [
            "40 items, slot 0: one_reused_family used 8 times; limit is 1",
        ])

    def test_full_bank_variant_exhaustion_is_visible_at_next_batch(self):
        report = simulate((160, 165))
        self.assertEqual(report["exhaustion"]["atItems"], 160)
        self.assertEqual(report["exhaustion"]["failureReasons"],
                         ["agreement_novelty_exhausted", "agreement_novelty_exhausted"])
        self.assertEqual(report["snapshots"][0]["slots"]["3"]["remainingExactStems"], 0)
        self.assertEqual(report["snapshots"][0]["slots"]["4"]["remainingExactStems"], 0)
        self.assertTrue(any("165 items unavailable" in failure for failure in
                            qualification_failures(report)))


if __name__ == "__main__":
    unittest.main()
