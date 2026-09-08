import copy
import json
import unittest

from evals.question_complete_solver import (
    CompleteSolutionFormatError,
    complete_solution_observation,
    solver_prompt,
    validate_complete_solution,
)
from question_verification import SOLUTION_SYSTEM_PROMPT
from service_errors import ProviderError


def case():
    return {
        "request": {
            "goal": {"title": "Compare signed integers"},
            "skillMap": None,
            "sourceDocuments": [{"name": "Notation", "text": 'Exact: "a  b"\n    x'}],
            "existingQuestionCoverage": [{"expectedAnswer": "PRIVATE HISTORY"}],
        },
        "question": {
            "prompt": "Which listed integer is greatest?",
            "choices": ["-9", "-1", "-6", "-3"],
            "expectedAnswer": "-1",
            "topic": "Signed integers",
            "difficulty": 2,
            "skillID": "order-integers",
            "objectiveID": "compare-negative-values",
            "explanation": "PRIVATE AUTHOR FEEDBACK",
        },
        "external_assessment": "PRIVATE EXPECTED JUDGMENTS",
    }


def payload(user):
    return json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])


def response(judgments, choices=None):
    return {
        "solutions": [
            {
                "index": 0,
                "choices": [
                    {
                        "choice": choice,
                        "judgment": judgment,
                        "reason": "Compare this value with the other listed integers.",
                    }
                    for choice, judgment in zip(
                        choices or case()["question"]["choices"], judgments, strict=True
                    )
                ],
            }
        ]
    }


class CompleteSolverContractTests(unittest.TestCase):
    def test_choices_restore_information_while_all_other_subject_data_stays_exact(self):
        original = case()
        snapshot = copy.deepcopy(original)
        baseline = solver_prompt(original, complete=False)
        complete = solver_prompt(original, complete=True)
        self.assertEqual(baseline[0], SOLUTION_SYSTEM_PROMPT)
        baseline_data, complete_data = payload(baseline[1]), payload(complete[1])
        offered = complete_data["items"][0].pop("choices")
        self.assertCountEqual(offered, original["question"]["choices"])
        self.assertEqual(complete_data, baseline_data)
        self.assertEqual(
            baseline_data["sourceDocuments"], original["request"]["sourceDocuments"]
        )
        self.assertEqual(original, snapshot)
        for prompt in (baseline[1], complete[1]):
            self.assertNotIn("PRIVATE", prompt)
            self.assertNotIn("expectedAnswer", prompt)
            self.assertNotIn("difficulty", prompt)

    def test_identical_stems_with_different_unique_answers_have_distinct_complete_inputs(
        self,
    ):
        first, second = case(), case()
        second["question"]["choices"] = ["-9", "2", "-6", "-3"]
        second["question"]["expectedAnswer"] = "2"
        self.assertEqual(solver_prompt(first, False), solver_prompt(second, False))
        self.assertNotEqual(solver_prompt(first, True), solver_prompt(second, True))
        self.assertIn('"2"', solver_prompt(second, True)[1])

    def test_author_key_and_feedback_changes_do_not_change_either_solver_input(self):
        first, second = case(), case()
        second["question"]["expectedAnswer"] = "-9"
        second["question"]["explanation"] = "DIFFERENT PRIVATE AUTHOR REASON"
        second["external_assessment"] = "DIFFERENT PRIVATE ASSESSMENT"
        for complete in (False, True):
            self.assertEqual(
                solver_prompt(first, complete), solver_prompt(second, complete)
            )

    def test_exact_choice_coverage_does_not_require_a_model_selected_order(self):
        choices = case()["question"]["choices"]
        parsed = response(["refuted", "supported", "refuted", "refuted"])
        parsed["solutions"][0]["choices"].reverse()
        raw = "```json\n" + json.dumps(parsed) + "\n```"
        self.assertEqual(validate_complete_solution(raw, choices), parsed)
        self.assertTrue(
            complete_solution_observation(parsed, "-1")["pre_review_eligibility"]
        )

    def test_derived_gate_blocks_zero_multiple_uncertain_and_key_disagreement(self):
        for statuses, key, expected in (
            (["refuted"] * 4, "-1", "zero_supported"),
            (
                ["supported", "supported", "refuted", "refuted"],
                "-1",
                "multiple_supported",
            ),
            (["uncertain", "supported", "refuted", "refuted"], "-1", "uncertain"),
            (["uncertain"] * 4, "-1", "uncertain"),
            (["supported", "refuted", "refuted", "refuted"], "-1", "key_disagreement"),
            (
                ["supported", "supported", "uncertain", "refuted"],
                "-1",
                "multiple_supported",
            ),
        ):
            with self.subTest(statuses=statuses):
                observation = complete_solution_observation(response(statuses), key)
                self.assertEqual(observation["disposition"], expected)
                self.assertFalse(observation["pre_review_eligibility"])

    def test_substantive_negative_answer_has_no_special_wording_or_keyword_gate(self):
        choices = ["No real number satisfies the equation.", "0", "1", "-1"]
        parsed = response(["supported", "refuted", "refuted", "refuted"], choices)
        validate_complete_solution(json.dumps(parsed), choices)
        self.assertTrue(
            complete_solution_observation(parsed, choices[0])["pre_review_eligibility"]
        )

    def test_incomplete_duplicate_or_rewritten_choices_are_format_failures(self):
        choices = case()["question"]["choices"]
        for mutated in (
            choices[:3],
            choices + ["7"],
            ["-9", "-9", "-6", "-3"],
            ["−9", "-1", "-6", "-3"],
        ):
            with self.subTest(choices=mutated):
                parsed = response(["refuted"] * len(mutated), mutated)
                with self.assertRaises(CompleteSolutionFormatError):
                    validate_complete_solution(json.dumps(parsed), choices)

    def test_malformed_contract_is_not_a_semantic_rejection(self):
        base = response(["refuted", "supported", "refuted", "refuted"])
        mutations = []
        for value in (True, -1, 1, "0", None):
            changed = copy.deepcopy(base)
            changed["solutions"][0]["index"] = value
            mutations.append(changed)
        for field, value in (
            ("reason", ""),
            ("reason", "x" * 601),
            ("judgment", "correct"),
            ("judgment", []),
            ("choice", 1),
        ):
            changed = copy.deepcopy(base)
            changed["solutions"][0]["choices"][0][field] = value
            mutations.append(changed)
        changed = copy.deepcopy(base)
        changed["solutions"][0]["answer"] = "-1"
        mutations.append(changed)
        for parsed in mutations:
            with self.subTest(parsed=parsed):
                with self.assertRaises(CompleteSolutionFormatError):
                    validate_complete_solution(
                        json.dumps(parsed), case()["question"]["choices"]
                    )
        with self.assertRaises(ProviderError):
            validate_complete_solution(
                '{"solutions":[],"solutions":[]}', case()["question"]["choices"]
            )
