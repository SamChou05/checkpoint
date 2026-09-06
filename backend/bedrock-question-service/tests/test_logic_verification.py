import copy
import unittest

from logic_verification import proves_unique_answer


class LogicVerificationTests(unittest.TestCase):
    def setUp(self):
        self.proof = {
            "atoms": {"C": "completed course", "E": "eligible", "F": "five years"},
            "premises": [["implies", "C", "E"], ["implies", "C", "F"]],
            "choiceClaims": {
                "Eligibility requires tenure": ["implies", "E", "F"],
                "Eligibility requires completion": ["implies", "E", "C"],
                "Tenure guarantees eligibility": ["implies", "F", "E"],
                "No tenure prevents completion": [
                    "implies",
                    ["not", "F"],
                    ["not", "C"],
                ],
            },
        }

    def test_countermodel_rejects_converse_while_accepting_contrapositive(self):
        choices = list(self.proof["choiceClaims"])
        self.assertFalse(proves_unique_answer(self.proof, choices, choices[0]))
        self.assertTrue(proves_unique_answer(self.proof, choices, choices[3]))

    def test_wrapped_atom_is_only_a_syntactic_variant(self):
        self.proof["premises"].append(["C"])
        self.proof["choiceClaims"] = {
            "one": ["E"],
            "two": ["not", "F"],
            "three": ["not", "C"],
            "four": ["and", "C", ["not", "E"]],
        }
        self.assertTrue(
            proves_unique_answer(self.proof, list(self.proof["choiceClaims"]), "one")
        )

    def test_no_correct_choice_and_two_correct_choices_both_fail(self):
        for replacement in [["implies", "F", "C"], ["implies", "C", "E"]]:
            proof = copy.deepcopy(self.proof)
            proof["choiceClaims"]["No tenure prevents completion"] = replacement
            if replacement == ["implies", "C", "E"]:
                proof["choiceClaims"]["Eligibility requires tenure"] = [
                    "implies",
                    "C",
                    "F",
                ]
            self.assertFalse(
                proves_unique_answer(
                    proof, list(proof["choiceClaims"]), "No tenure prevents completion"
                )
            )

    def test_inconsistent_premises_do_not_vacuously_prove_an_answer(self):
        self.proof["premises"] += ["C", ["not", "C"]]
        self.assertFalse(
            proves_unique_answer(
                self.proof,
                list(self.proof["choiceClaims"]),
                "No tenure prevents completion",
            )
        )

    def test_malformed_unknown_and_excessively_nested_expressions_fail_closed(self):
        nested = "C"
        for _ in range(12):
            nested = ["not", nested]
        for bad in [None, "X", ["eval", "C"], ["not", "C", "E"], nested]:
            proof = copy.deepcopy(self.proof)
            proof["premises"] = [bad]
            self.assertFalse(
                proves_unique_answer(
                    proof, list(proof["choiceClaims"]), "No tenure prevents completion"
                )
            )
