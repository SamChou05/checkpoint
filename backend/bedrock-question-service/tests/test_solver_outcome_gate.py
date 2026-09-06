"""Explicit solver outcomes constrain review without interpreting answer keywords."""

import copy
import json
import unittest
from unittest.mock import Mock

from lambda_test_support import _request_payload
from question_verification import verify_questions
from request_contract import _normalize_request


# Literal prospective contract, deliberately independent of implementation constants.
NEGATIVE_CASES = (
    (
        "no_solution",
        "Which real number x satisfies x² = -1?",
        "No real x satisfies the equation.",
        "No solution exists under the stated conditions.",
    ),
    (
        "underdetermined",
        "What is y if only x = 2 is known?",
        "The value of y is not determined.",
        "Cannot be determined from the information given.",
    ),
    (
        "inconsistent_premises",
        "One real x equals both 1 and 2. What can be concluded about these premises?",
        "These premises cannot hold simultaneously.",
        "The stated premises are inconsistent.",
    ),
)


def question(prompt, answer, choices=None):
    return {
        "prompt": prompt,
        "expectedAnswer": answer,
        "choices": choices
        or [answer, "The value is 1.", "The value is 2.", "The value is 3."],
        "topic": "reasoning",
        "difficulty": 3,
        "format": "Multiple Choice",
        "explanation": "The author believes this answer follows from the question.",
    }


def solution(outcome, answer, *, index=0, assumptions=None):
    return {
        "index": index,
        "outcome": outcome,
        "answer": answer,
        "limitations": "",
        "assumptionsRequired": assumptions or [],
    }


def positive_review(item, *, index=0):
    return {
        "index": index,
        "valid": True,
        "answer": item["expectedAnswer"],
        "difficulty": 3,
        "explanation": "The stated premises support exactly this conclusion.",
        "choiceExplanations": {
            choice: "Check this conclusion against every stated premise."
            for choice in item["choices"]
        },
    }


def payload(prompt):
    return json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])


class SolverOutcomeGateTests(unittest.TestCase):
    def setUp(self):
        self.request = _normalize_request(_request_payload(target_count=1))

    def verify(self, item, record, *, review_record=None):
        reviewer = Mock(
            return_value=json.dumps(
                {
                    "reviews": [
                        positive_review(item)
                        if review_record is None
                        else review_record
                    ]
                }
            )
        )
        solver = Mock(return_value=json.dumps({"solutions": [record]}))
        metrics = {}
        accepted = verify_questions(
            [item], self.request, reviewer, metrics, solve=solver
        )
        return accepted, reviewer, metrics

    def assert_blocked(self, item, record, reason):
        # This reviewer would rubber-stamp the authored positive key if invoked.
        accepted, reviewer, metrics = self.verify(item, record)
        self.assertEqual(accepted, [])
        reviewer.assert_not_called()
        self.assertEqual(metrics["QuestionQuality"]["review"], {reason: 1})

    def test_impossibility_cannot_be_overridden_by_a_positive_reviewer(self):
        for outcome, prompt, independent_answer, _ in NEGATIVE_CASES:
            with self.subTest(outcome=outcome):
                item = question(prompt, "The value is 0.")
                self.assert_blocked(
                    item,
                    solution(outcome, independent_answer),
                    "solver_outcome_mismatch",
                )

    def test_each_exceptional_outcome_allows_its_unique_canonical_negative(self):
        for outcome, prompt, independent_answer, canonical_answer in NEGATIVE_CASES:
            with self.subTest(outcome=outcome):
                item = question(prompt, canonical_answer)
                original = copy.deepcopy(item)
                record = solution(outcome, independent_answer)
                accepted, reviewer, metrics = self.verify(item, record)
                reviewer.assert_called_once()
                self.assertEqual(
                    [q["expectedAnswer"] for q in accepted], [canonical_answer]
                )
                self.assertEqual(item, original)
                self.assertEqual(accepted[0]["prompt"], original["prompt"])
                self.assertEqual(accepted[0]["choices"], original["choices"])
                reviewed = payload(reviewer.call_args.args[1])
                self.assertEqual(reviewed["independentSolutions"], [record])
                self.assertCountEqual(
                    reviewed["items"][0]["choices"], original["choices"]
                )
                self.assertEqual(metrics["QuestionQuality"]["review"], {"accepted": 1})

    def test_exact_solver_answer_cannot_authorize_a_noncanonical_key(self):
        for outcome, prompt, independent_answer, _ in NEGATIVE_CASES:
            with self.subTest(outcome=outcome):
                self.assert_blocked(
                    question(prompt, independent_answer),
                    solution(outcome, independent_answer),
                    "solver_outcome_mismatch",
                )
        # A self-contradictory summary must not reopen the positive-answer route.
        self.assert_blocked(
            question(
                "Which procedure satisfies this impossible bound?", "Use a hash set."
            ),
            solution("no_solution", "Use a hash set."),
            "solver_outcome_mismatch",
        )

    def test_canonical_answer_equal_to_solver_answer_is_only_one_offered_choice(self):
        for outcome, prompt, _, canonical_answer in NEGATIVE_CASES:
            with self.subTest(outcome=outcome):
                item = question(prompt, canonical_answer)
                accepted, reviewer, _ = self.verify(
                    item, solution(outcome, canonical_answer)
                )
                reviewer.assert_called_once()
                self.assertEqual(len(accepted), 1)

    def test_canonical_and_distinct_exact_solver_answer_choices_are_ambiguous(self):
        for outcome, prompt, independent_answer, canonical_answer in NEGATIVE_CASES:
            with self.subTest(outcome=outcome):
                item = question(
                    prompt,
                    canonical_answer,
                    [
                        canonical_answer,
                        independent_answer,
                        "The value is 1.",
                        "The value is 2.",
                    ],
                )
                self.assert_blocked(
                    item,
                    solution(outcome, independent_answer),
                    "solver_outcome_mismatch",
                )

    def test_author_key_must_name_the_unique_authorized_negative(self):
        for outcome, prompt, independent_answer, canonical_answer in NEGATIVE_CASES:
            with self.subTest(outcome=outcome):
                item = question(prompt, canonical_answer)
                item["expectedAnswer"] = item["choices"][1]
                self.assert_blocked(
                    item,
                    solution(outcome, independent_answer),
                    "solver_outcome_mismatch",
                )

    def test_unrecognized_paraphrases_and_nonexact_text_do_not_authorize_review(self):
        for offered, independent_answer in (
            ("There is no possible answer.", "No real x satisfies the equation."),
            ("no real x satisfies the equation.", "No real x satisfies the equation."),
            ('No solution prints "a b".', 'No solution prints "a  b".'),
            ('No solution prints "é".', 'No solution prints "e\u0301".'),
        ):
            with self.subTest(offered=offered):
                self.assert_blocked(
                    question("What does the exact stated condition permit?", offered),
                    solution("no_solution", independent_answer),
                    "solver_outcome_mismatch",
                )

    def test_missing_unknown_and_nonstring_outcomes_are_invalid_without_a_default(self):
        item = question("Which value follows?", "The value is 0.")
        for outcome in (
            None,
            "",
            "unsupported",
            "Resolved",
            "resolved ",
            True,
            0,
            [],
            {},
        ):
            with self.subTest(outcome=outcome):
                self.assert_blocked(
                    item, solution(outcome, "The value is 0."), "invalid_solution"
                )
        missing = solution("resolved", "The value is 0.")
        del missing["outcome"]
        self.assert_blocked(item, missing, "invalid_solution")

    def test_epistemic_uncertainty_cannot_be_a_valid_cannot_determine_answer(self):
        canonical_answer = "Cannot be determined from the information given."
        item = question("What does this evidence establish?", canonical_answer)
        for assumptions in ([], ["The solver cannot verify an additional premise."]):
            with self.subTest(assumptions=assumptions):
                self.assert_blocked(
                    item,
                    solution("uncertain", canonical_answer, assumptions=assumptions),
                    "solver_uncertain",
                )

    def test_missing_assumptions_still_block_an_exact_negative_answer(self):
        outcome, prompt, independent_answer, canonical_answer = NEGATIVE_CASES[0]
        item = question(prompt, canonical_answer)
        self.assert_blocked(
            item,
            solution(
                outcome,
                independent_answer,
                assumptions=["An unstated domain restriction."],
            ),
            "unsupported_solution",
        )

    def test_resolved_zero_and_negative_words_keep_the_ordinary_review_route(self):
        for item in (
            question(
                "How many real roots does x² = -1 have?",
                "0",
                ["0", "1", "2", "Infinitely many"],
            ),
            question(
                "What does the quoted phrase 'no solution' describe?",
                "The phrase 'no solution' describes an empty solution set.",
            ),
        ):
            with self.subTest(prompt=item["prompt"]):
                accepted, reviewer, _ = self.verify(
                    item, solution("resolved", item["expectedAnswer"])
                )
                reviewer.assert_called_once()
                self.assertEqual(len(accepted), 1)

    def test_matching_negative_still_requires_reviewer_verdict_key_feedback_and_difficulty(
        self,
    ):
        outcome, prompt, independent_answer, canonical_answer = NEGATIVE_CASES[0]
        item = question(prompt, canonical_answer)
        changes = (
            ({"valid": False, "answer": ""}, "rejected_by_model"),
            ({"answer": item["choices"][1]}, "answer_disagreement"),
            ({"choiceExplanations": {}}, "invalid_feedback"),
            ({"difficulty": 2}, "difficulty_floor"),
        )
        for change, reason in changes:
            with self.subTest(reason=reason):
                review = {**positive_review(item), **change}
                accepted, reviewer, metrics = self.verify(
                    item, solution(outcome, independent_answer), review_record=review
                )
                reviewer.assert_called_once()
                self.assertEqual(accepted, [])
                self.assertEqual(metrics["QuestionQuality"]["review"], {reason: 1})

    def test_mixed_batch_joins_shuffled_solver_rows_after_all_outcome_filters(self):
        rejected = question("Which real root does x² = -1 have?", "The value is 0.")
        resolved = question(
            "How many real roots does x² = -1 have?",
            "0",
            ["0", "1", "2", "Infinitely many"],
        )
        negative = question(NEGATIVE_CASES[1][1], NEGATIVE_CASES[1][3])
        uncertain = question("What result does the solver not know?", "The value is 4.")
        conditional = question(
            "What follows with an added premise?", NEGATIVE_CASES[0][3]
        )
        questions = [rejected, resolved, uncertain, negative, conditional]
        records = [
            solution("no_solution", NEGATIVE_CASES[0][2], index=0),
            solution("resolved", "0", index=1),
            solution("uncertain", "The value is 4.", index=2),
            solution("underdetermined", NEGATIVE_CASES[1][2], index=3),
            solution(
                "no_solution",
                NEGATIVE_CASES[0][2],
                index=4,
                assumptions=["An extra premise."],
            ),
        ]

        def review(_system, prompt):
            reviewed = payload(prompt)
            self.assertEqual(
                [item["prompt"] for item in reviewed["items"]],
                [resolved["prompt"], negative["prompt"]],
            )
            self.assertEqual([item["index"] for item in reviewed["items"]], [0, 1])
            self.assertEqual(
                reviewed["independentSolutions"],
                [{**records[1], "index": 0}, {**records[3], "index": 1}],
            )
            # The reviewer may also return its rows out of order.
            return json.dumps(
                {
                    "reviews": [
                        positive_review(negative, index=1),
                        positive_review(resolved, index=0),
                    ]
                }
            )

        metrics = {}
        accepted = verify_questions(
            questions,
            self.request,
            review,
            metrics,
            solve=lambda *_: json.dumps({"solutions": list(reversed(records))}),
        )
        self.assertEqual(
            [item["prompt"] for item in accepted],
            [resolved["prompt"], negative["prompt"]],
        )
        self.assertEqual(
            metrics["QuestionQuality"]["review"],
            {
                "solver_outcome_mismatch": 1,
                "solver_uncertain": 1,
                "unsupported_solution": 1,
                "accepted": 2,
            },
        )


if __name__ == "__main__":
    unittest.main()
