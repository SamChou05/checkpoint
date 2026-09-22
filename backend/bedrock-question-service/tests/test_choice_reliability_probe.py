"""Keep the offline semantic probe's ground truth and accounting reproducible."""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "evals"))
from checkpoint_choice_reliability_probe import (
    controls, historical_pipeline_assessment, historical_solver_replay, synthetic_probe,
)


class ChoiceReliabilityProbeTests(unittest.TestCase):
    def test_faithful_solver_blocks_wrong_keys_but_not_equivalent_wrong_options(self):
        result = synthetic_probe()
        rows = {row["id"]: row for row in result["rows"]}
        self.assertEqual(result["counts"]["controls"], 10)
        self.assertEqual(result["counts"]["bad_key_controls_blocked_with_truthful_solver"], 4)
        self.assertEqual(result["counts"]["equivalent_wrong_options_eligible"], 2)
        self.assertEqual(rows["exact_duplicate_wrong"]["truthful_solver_gate"], "invalid_choices")
        self.assertEqual(rows["equivalent_correct"]["truthful_solver_gate"], "solver_multiple_supported")
        self.assertEqual(rows["zero_correct"]["truthful_solver_gate"], "solver_zero_supported")
        self.assertEqual(rows["wrong_author_key"]["truthful_solver_gate"], "answer_disagreement")

    def test_diversity_is_contextual_not_case_or_punctuation_folding(self):
        rows = {row["id"]: row for row in synthetic_probe()["rows"]}
        for case in ("case_sensitive_valid", "operator_sensitive_valid"):
            self.assertTrue(rows[case]["diverse_options"])
            self.assertIsNone(rows[case]["truthful_solver_gate"])
        numeric = next(row for row in controls() if row["id"] == "equivalent_numeric_wrong")
        left, right = numeric["equivalent_pairs"][0]
        self.assertEqual(float(left), float(right))
        self.assertNotEqual(left, right)

    def test_saved_complete_solver_preserves_zero_and_multiple_answer_controls(self):
        result = historical_solver_replay()
        self.assertEqual(result["counts"], {"items": 5, "correct_cardinality": 5})
        self.assertEqual([len(row["declared_supported"]) for row in result["rows"]], [1, 0, 0, 2, 1])

    def test_saved_assessment_join_has_no_denominator_loss(self):
        result = historical_pipeline_assessment()
        self.assertEqual(result["counts"]["raw_candidates"], 12)
        self.assertEqual(result["counts"]["returned"], 6)
        self.assertEqual(result["counts"]["returned_unsupported_keys"], 2)
        self.assertEqual({row["candidate_id"] for row in result["rows"] if row["historical_returned"] and not row["historical_unique_key_assessment"]}, {"q05", "q08"})


if __name__ == "__main__":
    unittest.main()
