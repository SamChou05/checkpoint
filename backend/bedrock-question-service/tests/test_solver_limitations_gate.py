"""A resolved label cannot conceal an explicitly unresolved solver limitation."""

import copy
import json
import unittest
from unittest.mock import Mock

from lambda_test_support import _request_payload
from question_verification import verify_questions
from request_contract import _normalize_request


def question(prompt, answer, choices=None, *, topic="reasoning"):
    return {
        "prompt": prompt,
        "expectedAnswer": answer,
        "choices": choices
        or [answer, "The value is 1.", "The value is 2.", "The value is 3."],
        "topic": topic,
        "difficulty": 3,
        "format": "Multiple Choice",
        "explanation": "The author claims this conclusion follows from the premises.",
    }


def solution(answer, limitations="", *, outcome="resolved", index=0, assumptions=None):
    return {
        "index": index,
        "outcome": outcome,
        "answer": answer,
        "limitations": limitations,
        "assumptionsRequired": assumptions or [],
    }


def approving_review(item, index=0):
    return {
        "index": index,
        "valid": True,
        "answer": item["expectedAnswer"],
        "difficulty": 3,
        "explanation": "Reviewed conclusion: " + item["expectedAnswer"],
        "choiceExplanations": {
            choice: f"Compare {choice} with the stated premises for {item['topic']}."
            for choice in item["choices"]
        },
    }


def payload(prompt):
    return json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])


def conditional_question():
    return question(
        "For any real x, y = 2x. What follows if x = 3?",
        "y = 6 when x = 3.",
        [
            "y = 6 when x = 3.",
            "y = 3 when x = 3.",
            "y = 6 for every x.",
            "y = 2 when x = 3.",
        ],
        topic="conditional calculation",
    )


class SolverLimitationsGateTests(unittest.TestCase):
    def setUp(self):
        self.request = _normalize_request(_request_payload(target_count=1))

    def verify(self, item, record):
        # The mock would rubber-stamp a bad answer if the gate let it through.
        reviewer = Mock(return_value=json.dumps({"reviews": [approving_review(item)]}))
        solver = Mock(return_value=json.dumps({"solutions": [record]}))
        metrics = {}
        accepted = verify_questions(
            [item], self.request, reviewer, metrics, solve=solver
        )
        solver.assert_called_once()
        return accepted, reviewer, metrics

    def assert_blocked(self, item, record, reason="solver_unresolved_limitations"):
        accepted, reviewer, metrics = self.verify(item, record)
        self.assertEqual([], accepted)
        reviewer.assert_not_called()
        self.assertEqual({reason: 1}, metrics["QuestionQuality"]["review"])

    def test_known_impossible_positive_key_cannot_override_resolved_limitations(self):
        item = question(
            "Which real number x satisfies x² = -1?", "0", ["0", "1", "-1", "2"]
        )
        # Every offered numeric key is independently wrong, not merely unfamiliar.
        self.assertTrue(all(float(value) ** 2 != -1 for value in item["choices"]))
        self.assert_blocked(
            item,
            solution(
                "0",
                "No real number satisfies this equation: a real square is nonnegative.",
            ),
        )

    def test_missing_ordinary_qualifier_is_vetoed_even_without_declared_assumptions(
        self,
    ):
        item = question(
            "A route is 10 km long. How long does the journey take?", "One hour."
        )
        self.assert_blocked(
            item,
            solution(
                "One hour.",
                "The travel speed is not provided, so the elapsed time is not fixed.",
            ),
        )

    def test_textual_none_or_reassurance_is_not_an_empty_limitations_field(self):
        item = conditional_question()
        for limitations in (
            "none",
            "None.",
            "N/A",
            "No limitations.",
            "There are no missing facts.",
            "  none  ",
        ):
            with self.subTest(limitations=limitations):
                self.assert_blocked(item, solution(item["expectedAnswer"], limitations))

    def test_empty_and_whitespace_limitations_allow_a_fully_stated_conditional_answer(
        self,
    ):
        item = conditional_question()
        original = copy.deepcopy(item)
        for limitations in ("", " ", "\t\r\n", " \u00a0\t "):
            with self.subTest(limitations=limitations):
                accepted, reviewer, metrics = self.verify(
                    item, solution(item["expectedAnswer"], limitations)
                )
                reviewer.assert_called_once()
                self.assertEqual(
                    [item["expectedAnswer"]], [q["expectedAnswer"] for q in accepted]
                )
                self.assertEqual(
                    "",
                    payload(reviewer.call_args.args[1])["independentSolutions"][0][
                        "limitations"
                    ],
                )
                self.assertEqual({"accepted": 1}, metrics["QuestionQuality"]["review"])
                self.assertEqual(original, item)

    def test_each_canonical_negative_keeps_its_explanatory_limitations(self):
        cases = (
            (
                "no_solution",
                "Which real number x satisfies x² = -1?",
                "No solution exists under the stated conditions.",
                "A real square cannot be negative; the requested real number does not exist.",
            ),
            (
                "underdetermined",
                "A route is 10 km long. How long does the journey take?",
                "Cannot be determined from the information given.",
                "Different speeds produce different times for the same distance.",
            ),
            (
                "inconsistent_premises",
                "One real x equals both 1 and 2. What follows about the premises?",
                "The stated premises are inconsistent.",
                "No single real x equals both distinct numbers simultaneously.",
            ),
        )
        for outcome, prompt, canonical, limitations in cases:
            with self.subTest(outcome=outcome):
                item = question(prompt, canonical)
                record = solution(canonical, limitations, outcome=outcome)
                accepted, reviewer, metrics = self.verify(item, record)
                reviewer.assert_called_once()
                self.assertEqual([canonical], [q["expectedAnswer"] for q in accepted])
                self.assertEqual(
                    [record],
                    payload(reviewer.call_args.args[1])["independentSolutions"],
                )
                self.assertEqual({"accepted": 1}, metrics["QuestionQuality"]["review"])

    def test_uncertainty_and_required_assumptions_keep_diagnostic_priority(self):
        item = conditional_question()
        for outcome, assumptions, reason in (
            ("uncertain", [], "solver_uncertain"),
            ("uncertain", ["An unprovided condition."], "solver_uncertain"),
            ("resolved", ["An unprovided condition."], "unsupported_solution"),
        ):
            with self.subTest(outcome=outcome, assumptions=assumptions):
                self.assert_blocked(
                    item,
                    solution(
                        item["expectedAnswer"],
                        "The result remains unresolved.",
                        outcome=outcome,
                        assumptions=assumptions,
                    ),
                    reason,
                )

    def test_mixed_batch_preserves_survivor_identity_and_reindexes_both_payloads(self):
        impossible = question("Which real root satisfies x² = -1?", "Zero.")
        conditional = conditional_question()
        missing = question("A route is 10 km. How long is the journey?", "One hour.")
        negative = question(
            "What is y when only x = 2 is known?",
            "Cannot be determined from the information given.",
            topic="missing value",
        )
        uncertain = question(
            "Which conclusion is the solver unable to establish?", "The first one."
        )
        items = [impossible, conditional, missing, negative, uncertain]
        records = [
            solution("Zero.", "No real root exists.", index=0),
            solution(conditional["expectedAnswer"], " \n ", index=1),
            solution("One hour.", "Speed is missing.", index=2),
            solution(
                negative["expectedAnswer"],
                "No relation constrains y.",
                outcome="underdetermined",
                index=3,
            ),
            solution(
                "The first one.", "I cannot establish it.", outcome="uncertain", index=4
            ),
        ]
        original = copy.deepcopy(items)

        def review(_system, prompt):
            data = payload(prompt)
            self.assertEqual(
                [conditional["prompt"], negative["prompt"]],
                [item["prompt"] for item in data["items"]],
            )
            self.assertEqual([0, 1], [item["index"] for item in data["items"]])
            self.assertEqual(
                [conditional["topic"], negative["topic"]],
                [item["topic"] for item in data["items"]],
            )
            self.assertEqual(
                [
                    {**records[1], "index": 0, "limitations": ""},
                    {**records[3], "index": 1},
                ],
                data["independentSolutions"],
            )
            for actual, expected in zip(
                data["items"], [conditional, negative], strict=True
            ):
                self.assertCountEqual(expected["choices"], actual["choices"])
            return json.dumps(
                {
                    "reviews": [
                        approving_review(negative, 1),
                        approving_review(conditional, 0),
                    ]
                }
            )

        reviewer = Mock(side_effect=review)
        metrics = {}
        accepted = verify_questions(
            items,
            self.request,
            reviewer,
            metrics,
            solve=lambda *_: json.dumps({"solutions": list(reversed(records))}),
        )
        reviewer.assert_called_once()
        self.assertEqual(
            [conditional["prompt"], negative["prompt"]], [q["prompt"] for q in accepted]
        )
        for actual, expected in zip(accepted, [conditional, negative], strict=True):
            self.assertEqual(expected["expectedAnswer"], actual["expectedAnswer"])
            self.assertEqual(
                approving_review(expected)["explanation"], actual["explanation"]
            )
            self.assertEqual(
                approving_review(expected)["choiceExplanations"],
                actual["choiceExplanations"],
            )
        self.assertEqual(original, items)
        self.assertEqual(
            {"solver_unresolved_limitations": 2, "solver_uncertain": 1, "accepted": 2},
            metrics["QuestionQuality"]["review"],
        )


if __name__ == "__main__":
    unittest.main()
