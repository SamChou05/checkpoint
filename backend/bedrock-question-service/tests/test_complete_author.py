"""Pure author-boundary controls; no provider calls or factual qualification."""

import copy
import json
import unittest
from unittest.mock import patch

from evals.question_complete_author import (
    MAX_RAW_AUTHOR_CHARACTERS,
    author_prompt,
    parse_author,
)
from evals.question_immutable_review import (
    ImmutableReviewContentError,
    ImmutableReviewFormatError,
)
from question_difficulty import DIFFICULTY_RUBRIC
from question_verification import NEGATIVE_ANSWER_GUIDANCE


def question():
    choices = ["No real solution exists.", "Zero.", "One.", "Minus one."]
    return {
        "prompt": "Which real number has a square equal to minus one?",
        "choices": choices,
        "expectedAnswer": choices[0],
        "explanation": "Every real square is nonnegative, so the requested value does not exist.",
        "choiceExplanations": dict(
            zip(
                choices,
                [
                    "Nonnegativity excludes all real candidates.",
                    "Zero squared is zero rather than minus one.",
                    "One squared is positive one rather than minus one.",
                    "Minus one squared is positive one rather than minus one.",
                ],
                strict=True,
            )
        ),
        "topic": "Real numbers",
        "objective": "Infer whether a value exists",
        "difficulty": 3,
        "format": "Multiple Choice",
    }


def raw(question_value):
    return json.dumps({"question": question_value}, ensure_ascii=False)


def payload(user):
    return json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])


class CompleteAuthorTests(unittest.TestCase):
    def test_prompt_is_deterministic_and_excludes_all_evaluator_and_stage_metadata(
        self,
    ):
        context = {
            "goal": {"title": "Reason about constraints", "assessment": "GOAL_CANARY"},
            "sourceDocuments": [
                {
                    "name": "Definitions",
                    "text": 'Literal "a  b"\n    indented',
                    "rationale": "SOURCE_CANARY",
                }
            ],
            "minimumDifficulty": 1,
            "question": {"prompt": "ITEM_CANARY"},
            "expectedAnswer": "KEY_CANARY",
            "expected_accept": "EXPECTATION_CANARY",
            "independentSolutions": "SOLVER_CANARY",
            "existingQuestionCoverage": "HISTORY_CANARY",
            "examples": "EXAMPLE_CANARY",
        }
        original = copy.deepcopy(context)
        system, user = author_prompt(context, 3)
        data = payload(user)
        self.assertEqual(set(data), {"goal", "sourceDocuments", "minimumDifficulty"})
        self.assertEqual(data["minimumDifficulty"], 3)
        self.assertEqual(data["goal"], {"title": "Reason about constraints"})
        self.assertEqual(
            data["sourceDocuments"],
            [{"name": "Definitions", "text": context["sourceDocuments"][0]["text"]}],
        )
        for marker in (
            "GOAL",
            "SOURCE",
            "ITEM",
            "KEY",
            "EXPECTATION",
            "SOLVER",
            "HISTORY",
            "EXAMPLE",
        ):
            self.assertNotIn(marker + "_CANARY", user)
        self.assertIn(DIFFICULTY_RUBRIC, system)
        self.assertIn(NEGATIVE_ANSWER_GUIDANCE, system)
        self.assertEqual(
            author_prompt(json.loads(json.dumps(context, sort_keys=True)), 3),
            (system, user),
        )
        self.assertEqual(context, original)

    def test_complete_exact_content_survives_without_provenance_or_normalization(self):
        item = question()
        item["prompt"] = (
            'In Python, what is returned?\ndef f():\n    return "red  blue"\nf()\n'
        )
        item["explanation"] = '  Preserve "red  blue" and e\u0301 exactly.\n'
        item["choiceExplanations"][item["choices"][0]] = (
            "  Preserve this explanation and its final newline.\n"
        )
        parsed = parse_author(raw(item))
        self.assertEqual(parsed, item)
        parsed["choices"].reverse()
        parsed["choiceExplanations"].clear()
        self.assertEqual(parse_author(raw(item)), item)
        self.assertNotIn("verificationVersion", parse_author(raw(item)))
        self.assertNotIn("verificationPolicyRevision", parse_author(raw(item)))
        no_objective = question()
        del no_objective["objective"]
        self.assertEqual(parse_author(raw(no_objective)), no_objective)
        self.assertEqual(parse_author("```json\n" + raw(item) + "\n```"), item)

    def test_extra_envelope_question_or_feedback_fields_cannot_supply_replacements(
        self,
    ):
        for key in (
            "question",
            "expectedAnswer",
            "replacement",
            "verificationPolicyRevision",
            "skillID",
            "review",
        ):
            with self.subTest(key=key), self.assertRaises(ImmutableReviewFormatError):
                parse_author(
                    json.dumps(
                        {
                            "question": question(),
                            key if key != "question" else "extra": {
                                "prompt": "replacement"
                            },
                        }
                    )
                )
        for key in (
            "replacement",
            "verificationVersion",
            "verificationPolicyRevision",
            "skillID",
            "independentSolutions",
            "valid",
        ):
            with self.subTest(key=key), self.assertRaises(ImmutableReviewFormatError):
                parse_author(raw({**question(), key: "replacement"}))
        item = question()
        item["choiceExplanations"][item["choices"][0]] = {
            "text": "Replacement text",
            "status": "supported",
        }
        with self.assertRaises(ImmutableReviewFormatError):
            parse_author(raw(item))

    def test_every_required_field_and_exact_key_feedback_coverage_are_enforced(self):
        for field in set(question()) - {"objective"}:
            item = question()
            del item[field]
            with (
                self.subTest(field=field),
                self.assertRaises(ImmutableReviewFormatError),
            ):
                parse_author(raw(item))
        for change in ("missing", "new_key", "normalized_key"):
            item = question()
            explanation = item["choiceExplanations"].pop(item["choices"][0])
            if change != "missing":
                key = "replacement" if change == "new_key" else item["choices"][0] + " "
                item["choiceExplanations"][key] = explanation
            with self.assertRaises(ImmutableReviewFormatError):
                parse_author(raw(item))
        with self.assertRaises(ImmutableReviewContentError):
            parse_author(
                raw({**question(), "expectedAnswer": " No real solution exists."})
            )
        for a, b in (("x", "x"), ("x", " x "), ("é", "e\u0301")):
            with self.assertRaises(ImmutableReviewContentError):
                parse_author(raw({**question(), "choices": [a, b, "z", "q"]}))

    def test_inherited_display_bounds_reject_without_repair(self):
        for field, limit in (
            ("prompt", 320),
            ("topic", 140),
            ("objective", 140),
            ("explanation", 420),
        ):
            item = {**question(), field: "x" * limit}
            self.assertEqual(parse_author(raw(item))[field], "x" * limit)
            with self.assertRaises(ImmutableReviewContentError):
                parse_author(raw({**item, field: "x" * (limit + 1)}))
        for length in (280, 281):
            item = question()
            item["choiceExplanations"][item["choices"][0]] = "x" * length
            if length == 280:
                self.assertEqual(parse_author(raw(item)), item)
            else:
                with self.assertRaises(ImmutableReviewContentError):
                    parse_author(raw(item))
        for length in (140, 141):
            item = question()
            answer = "x" * length
            feedback = item["choiceExplanations"].pop(item["choices"][0])
            item["choices"][0] = item["expectedAnswer"] = answer
            item["choiceExplanations"][answer] = feedback
            if length == 140:
                self.assertEqual(parse_author(raw(item)), item)
            else:
                with self.assertRaises(ImmutableReviewContentError):
                    parse_author(raw(item))
        with self.assertRaises(ImmutableReviewContentError):
            parse_author(raw({**question(), "prompt": "\n" * 50 + "short"}))

    def test_types_raw_envelope_and_duplicate_json_keys_are_strict(self):
        for invalid in (None, "not JSON", "[]", "{}", '{"question":{},"question":{}}'):
            with (
                self.subTest(invalid=invalid),
                self.assertRaises(ImmutableReviewFormatError),
            ):
                parse_author(invalid)
        for changes in (
            {"difficulty": True},
            {"difficulty": 3.0},
            {"choices": "four choices"},
            {"format": "Essay"},
            {"topic": None},
        ):
            with self.assertRaises(ImmutableReviewFormatError):
                parse_author(raw({**question(), **changes}))
        valid = raw(question())
        at_limit = valid + " " * (MAX_RAW_AUTHOR_CHARACTERS - len(valid))
        self.assertEqual(parse_author(at_limit), question())
        with patch("evals.question_complete_author._extract_json_object") as parser:
            with self.assertRaises(ImmutableReviewFormatError):
                parse_author(at_limit + " ")
            parser.assert_not_called()

    def test_requested_difficulty_and_context_are_validated_not_inferred(self):
        context = {"goal": {"title": "Any ordinary learning goal"}}
        for value in (True, 3.0, "3", None):
            with self.assertRaises(ImmutableReviewFormatError):
                author_prompt(context, value)
        for value in (0, 6):
            with self.assertRaises(ImmutableReviewContentError):
                author_prompt(context, value)
        self.assertEqual(payload(author_prompt(context)[1])["minimumDifficulty"], 3)
        for invalid in (
            {},
            {"goal": {"title": " "}},
            {**context, "sourceDocuments": "not a list"},
        ):
            with self.assertRaises(ImmutableReviewFormatError):
                author_prompt(invalid)
        # The author label remains a proposal; parser does not relabel it to
        # the request's minimum. The later auditor assesses actual challenge.
        item = {**question(), "difficulty": 2}
        self.assertEqual(parse_author(raw(item))["difficulty"], 2)


if __name__ == "__main__":
    unittest.main()
