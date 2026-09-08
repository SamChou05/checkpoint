"""Offline structural controls, not evidence that a model judges facts correctly."""

import copy
import json
import unittest

from evals.question_immutable_review import (
    ImmutableReviewContentError,
    ImmutableReviewFormatError,
    freeze_question,
    observe_review,
    review_prompt,
)


def question():
    choices = ["No real solution exists.", "Zero.", "One.", "Minus one."]
    return {
        "prompt": "Which real number has a square equal to minus one?",
        "choices": choices,
        "expectedAnswer": choices[0],
        "explanation": "The square of a real number is nonnegative, so no real value works.",
        "choiceExplanations": dict(
            zip(
                choices,
                [
                    "Nonnegativity rules out every real candidate.",
                    "Zero squared is zero, not minus one.",
                    "One squared is one, not minus one.",
                    "Minus one squared is positive one, not minus one.",
                ],
                strict=True,
            )
        ),
        "topic": "Real numbers",
        "objective": "Reason about possible values",
        "difficulty": 3,
        "format": "Multiple Choice",
    }


def review(item, **changes):
    return {
        "review": {
            "valid": True,
            "answer": item["expectedAnswer"],
            "difficulty": 3,
            "mainExplanation": "supported",
            "choiceExplanations": {choice: "supported" for choice in item["choices"]},
            "issues": [],
            **changes,
        }
    }


def raw(value):
    return json.dumps(value, ensure_ascii=False)


def payload(user):
    return json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])


class ImmutableReviewTests(unittest.TestCase):
    def setUp(self):
        self.item = question()
        self.context = {
            "goal": {"title": "Reason from stated constraints"},
            "sourceDocuments": [
                {"name": "Exact source", "text": 'Keep "red  blue"\n    indented'}
            ],
            "minimumDifficulty": 3,
        }

    def observe(self, value, item=None, minimum=1):
        return observe_review(raw(value), self.item if item is None else item, minimum)

    def test_valid_and_substantive_negative_keys_survive_without_stamps(self):
        for answer in (
            "No real solution exists.",
            "Cannot be determined from the stated facts.",
            "Zero.",
        ):
            with self.subTest(answer=answer):
                item = question()
                if answer not in item["choices"]:
                    old = item["choices"][0]
                    item["choices"][0] = answer
                    item["choiceExplanations"][answer] = item["choiceExplanations"].pop(
                        old
                    )
                item["expectedAnswer"] = answer
                item["verificationVersion"] = 99
                item["verificationPolicyRevision"] = 99
                expected = freeze_question(item)
                observed = self.observe(review(item, difficulty=4), item, minimum=3)
                self.assertTrue(observed["eligible"])
                self.assertEqual(observed["question"], {**expected, "difficulty": 4})
                self.assertNotIn("verificationVersion", observed["question"])
                self.assertNotIn("verificationPolicyRevision", observed["question"])
        # These mocks exercise binding, not the truth of a changed answer.

    def test_false_approval_cannot_override_any_declared_feedback_defect(self):
        for disposition, reason in (
            ("unsupported", "unsupported_feedback"),
            ("uncertain", "uncertain_feedback"),
        ):
            for field in ["main", *self.item["choices"]]:
                value = review(self.item)
                if field == "main":
                    value["review"]["mainExplanation"] = disposition
                else:
                    value["review"]["choiceExplanations"][field] = disposition
                observed = self.observe(value)
                self.assertEqual(
                    observed, {"eligible": False, "reason": reason, "question": None}
                )
        self.assertEqual(
            self.observe(
                review(self.item, issues=["One claim needs an unstated condition."])
            )["reason"],
            "reported_issues",
        )

    def test_replacement_injection_at_every_output_layer_is_malformed(self):
        for field in (
            "explanation",
            "prompt",
            "choices",
            "expectedAnswer",
            "question",
            "verificationPolicyRevision",
        ):
            value = review(self.item)
            value["review"][field] = "replacement"
            self.assertEqual(self.observe(value)["reason"], "invalid_review")
        value = review(self.item)
        value["replacement"] = self.item
        self.assertEqual(self.observe(value)["reason"], "invalid_review")
        value = review(self.item)
        value["review"]["choiceExplanations"][self.item["choices"][0]] = {
            "status": "supported",
            "explanation": "Replacement teaching text.",
        }
        self.assertEqual(self.observe(value)["reason"], "invalid_review")

    def test_choice_bindings_are_exact_complete_and_not_positional(self):
        value = review(self.item)
        value["review"]["choiceExplanations"] = dict(
            reversed(list(value["review"]["choiceExplanations"].items()))
        )
        self.assertTrue(self.observe(value)["eligible"])
        for changed in ("missing", "unknown", "trimmed", "list"):
            value = review(self.item)
            feedback = value["review"]["choiceExplanations"]
            if changed == "missing":
                feedback.pop(self.item["choices"][0])
            elif changed in {"unknown", "trimmed"}:
                key = self.item["choices"][0]
                feedback[key + (" replacement" if changed == "unknown" else " ")] = (
                    feedback.pop(key)
                )
            else:
                value["review"]["choiceExplanations"] = ["supported"] * 4
            self.assertEqual(self.observe(value)["reason"], "invalid_review")
        swapped = question()
        first, second = swapped["choices"][:2]
        swapped["choiceExplanations"][first], swapped["choiceExplanations"][second] = (
            swapped["choiceExplanations"][second],
            swapped["choiceExplanations"][first],
        )
        data = payload(review_prompt(swapped, self.context)[1])
        self.assertEqual(
            data["question"]["choiceExplanations"], swapped["choiceExplanations"]
        )
        value = review(swapped)
        value["review"]["choiceExplanations"][first] = "unsupported"
        self.assertFalse(self.observe(value, swapped)["eligible"])
        # A pure contract cannot detect a semantic swap by itself; it exposes
        # the exact swap to the auditor and enforces that field's judgment.

    def test_key_disagreement_rejection_and_difficulty_are_separate(self):
        for answer in ("", *self.item["choices"][1:]):
            self.assertEqual(
                self.observe(review(self.item, answer=answer))["reason"],
                "answer_disagreement",
            )
        self.assertEqual(
            self.observe(review(self.item, valid=False))["reason"], "rejected_by_model"
        )
        self.assertEqual(
            self.observe(review(self.item, difficulty=2), minimum=3)["reason"],
            "difficulty_floor",
        )
        self.assertEqual(
            self.observe(review(self.item, answer=" Zero."))["reason"], "invalid_review"
        )

    def test_stem_rotation_matches_feedback_variants_without_mutating_content(self):
        frozen = freeze_question(self.item)
        changed = copy.deepcopy(frozen)
        changed["explanation"] = "Different proposed teaching text with the same stem."
        changed["choiceExplanations"][changed["choices"][0]] = (
            "A different proposed reason for this exact choice."
        )
        first = payload(review_prompt(frozen, self.context)[1])["question"]
        second = payload(review_prompt(changed, self.context)[1])["question"]
        # This fixture's SHA256 prefix modulo four is two.
        expected_order = self.item["choices"][2:] + self.item["choices"][:2]
        self.assertEqual(first["choices"], expected_order)
        self.assertEqual(second["choices"], expected_order)
        self.assertNotEqual(first["choices"], frozen["choices"])
        self.assertEqual(first["choiceExplanations"], frozen["choiceExplanations"])
        self.assertEqual(second["choiceExplanations"], changed["choiceExplanations"])
        self.assertEqual(frozen, self.item)
        for item in (frozen, changed):
            observed = self.observe(review(item), item)
            self.assertEqual(observed["question"], item)

    def test_exact_content_preservation_and_no_shared_mutable_state(self):
        original = question()
        original["prompt"] = (
            'In Python, what is returned?\ndef f():\n    return "red  blue"\nf()\n'
        )
        original["explanation"] = (
            "\n  Literal e\u0301 is preserved, with  two spaces.  \n"
        )
        original["choiceExplanations"][original["choices"][1]] = (
            '  Retain "red  blue" literally.\n'
        )
        frozen = freeze_question(original)
        expected = copy.deepcopy(frozen)
        original["choices"][0] = "MUTATED"
        original["choiceExplanations"].clear()
        self.assertEqual(frozen, expected)
        observed = self.observe(review(frozen), frozen)
        self.assertEqual(observed["question"], expected)
        observed["question"]["choices"].reverse()
        observed["question"]["choiceExplanations"].clear()
        self.assertEqual(frozen, expected)
        self.assertEqual(
            payload(review_prompt(frozen, self.context)[1])["question"]["prompt"],
            expected["prompt"],
        )

    def test_context_and_question_metadata_do_not_leak(self):
        item = {
            **self.item,
            "policy": "KEY_CANARY",
            "independentSolutions": "SOLVER_CANARY",
        }
        context = copy.deepcopy(self.context)
        context.update(
            {
                "expected_accept": "LABEL_CANARY",
                "existingQuestions": "HISTORY_CANARY",
                "independentSolutions": "SUMMARY_CANARY",
            }
        )
        context["goal"]["assessment"] = "GOAL_CANARY"
        context["sourceDocuments"][0]["rationale"] = "SOURCE_CANARY"
        system, user = review_prompt(item, context)
        data = payload(user)
        self.assertEqual(set(data), {"goal", "sourceDocuments", "question"})
        self.assertNotIn("expectedAnswer", data["question"])
        self.assertNotIn("difficulty", data["question"])
        self.assertEqual(data["question"]["explanation"], self.item["explanation"])
        for canary in (
            "KEY",
            "SOLVER",
            "LABEL",
            "HISTORY",
            "SUMMARY",
            "GOAL",
            "SOURCE",
        ):
            self.assertNotIn(canary + "_CANARY", user)
        self.assertIn("Proposed explanations can reveal the intended answer", system)
        self.assertEqual(
            data["sourceDocuments"][0]["text"],
            self.context["sourceDocuments"][0]["text"],
        )
        self.assertEqual(
            review_prompt(item, context),
            review_prompt(
                json.loads(json.dumps(item, sort_keys=True)),
                json.loads(json.dumps(context, sort_keys=True)),
            ),
        )

    def test_all_content_bounds_reject_without_clipping(self):
        for field, maximum in (
            ("prompt", 320),
            ("topic", 140),
            ("objective", 140),
            ("explanation", 420),
        ):
            at_limit = {**self.item, field: "x" * maximum}
            self.assertEqual(freeze_question(at_limit)[field], "x" * maximum)
            with self.assertRaises(ImmutableReviewContentError):
                freeze_question({**at_limit, field: "x" * (maximum + 1)})
        for limit, value in ((280, "x" * 281), (140, "x" * 141)):
            item = question()
            if limit == 280:
                item["choiceExplanations"][item["choices"][0]] = value
            else:
                item["choices"][0] = value
            with self.assertRaises(ImmutableReviewContentError):
                freeze_question(item)
        for field in ("prompt", "explanation"):
            with self.assertRaises(ImmutableReviewContentError):
                freeze_question({**self.item, field: "\n" * 20 + "short"})

    def test_duplicates_and_missing_exact_authored_key_reject(self):
        for a, b in (("same", "same"), ("same", " same\t"), ("é", "e\u0301")):
            item = {**self.item, "choices": [a, b, "third", "fourth"]}
            with self.assertRaises(ImmutableReviewContentError):
                freeze_question(item)
        with self.assertRaises(ImmutableReviewContentError):
            freeze_question(
                {**self.item, "expectedAnswer": self.item["expectedAnswer"] + " "}
            )
        item = question()
        item["choiceExplanations"].pop(item["choices"][0])
        with self.assertRaises(ImmutableReviewFormatError):
            freeze_question(item)

    def test_strict_model_types_envelope_enums_and_issue_bounds(self):
        changes = [
            {"valid": 1},
            {"valid": "true"},
            {"difficulty": True},
            {"difficulty": 3.0},
            {"difficulty": 0},
            {"difficulty": 6},
            {"answer": None},
            {"mainExplanation": "unknown"},
            {"mainExplanation": True},
            {"issues": "none"},
            {"issues": [""]},
            {"issues": [" " * 20]},
            {"issues": ["x" * 281]},
            {"issues": ["issue"] * 9},
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assertEqual(
                    self.observe(review(self.item, **change))["reason"],
                    "invalid_review",
                )
        for field in review(self.item)["review"]:
            value = review(self.item)
            del value["review"][field]
            self.assertEqual(self.observe(value)["reason"], "invalid_review")
        for value in ({}, [], {"reviews": []}, {"review": []}):
            self.assertEqual(self.observe(value)["reason"], "invalid_review")
        for invalid in (None, "not JSON", '{"review":{},"review":{}}'):
            self.assertEqual(
                observe_review(invalid, self.item)["reason"], "invalid_review"
            )
        self.assertTrue(
            observe_review("```json\n" + raw(review(self.item)) + "\n```", self.item)[
                "eligible"
            ]
        )

    def test_caller_types_optional_objective_and_safe_representation(self):
        item = question()
        del item["objective"]
        self.assertNotIn("objective", freeze_question(item))
        for change in (
            {"difficulty": True},
            {"format": "Short Answer"},
            {"prompt": None},
            {"prompt": "bad\ud800unicode string"},
        ):
            with self.assertRaises(ImmutableReviewFormatError):
                freeze_question({**self.item, **change})
        with self.assertRaises(ImmutableReviewFormatError):
            observe_review(raw(review(self.item)), self.item, True)
        with self.assertRaises(ImmutableReviewContentError):
            freeze_question(
                {
                    **self.item,
                    "explanation": "The correct answer is option B in this question.",
                }
            )


if __name__ == "__main__":
    unittest.main()
