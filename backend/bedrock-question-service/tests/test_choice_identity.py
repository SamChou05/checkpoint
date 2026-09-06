"""Shared content-preservation regressions, also read by the iOS test suite."""

import ast
import json
from pathlib import Path
import unittest

from question_quality import (
    _choice_set_key,
    _looks_like_study_strategy,
    _question_coverage_payload,
    _question_coverage_keys,
    _sanitize_questions,
)
from question_verification import _has_reviewable_choices, verify_questions
from request_contract import _choice_uniqueness_key, _normalize_request
from lambda_test_support import _request_payload

FIXTURES = json.loads(
    (Path(__file__).parent / "fixtures/choice_identity_contract.json").read_text()
)


class ChoiceIdentityTests(unittest.TestCase):
    def test_shared_unicode_content_identity_contract(self):
        for first, second in FIXTURES["equivalent"]:
            self.assertEqual(
                _choice_uniqueness_key(first), _choice_uniqueness_key(second)
            )
        for first, second in FIXTURES["distinct"]:
            self.assertNotEqual(
                _choice_uniqueness_key(first), _choice_uniqueness_key(second)
            )

    def test_shared_questions_keep_every_choice_and_exact_key(self):
        request = _normalize_request(_request_payload(target_count=1))
        for item in FIXTURES["questions"]:
            question = {
                **item,
                "topic": "Subject content",
                "difficulty": 3,
                "format": "Multiple Choice",
            }
            with self.subTest(prompt=item["prompt"]):
                accepted = _sanitize_questions([question], request)
                self.assertEqual(len(accepted), 1)
                self.assertCountEqual(accepted[0]["choices"], item["choices"])
                self.assertEqual(accepted[0]["expectedAnswer"], item["expectedAnswer"])
                self.assertTrue(_has_reviewable_choices(accepted[0]))

    def test_canonical_duplicates_and_missing_key_are_rejected_without_repair(self):
        request = _normalize_request(_request_payload(target_count=1))
        for choices, answer in [
            (["café", "cafe\u0301", "tea", "water"], "café"),
            (["salt", " salt ", "sugar", "water"], "salt"),
            (["salt", "sugar", "tea", "water"], "missing"),
        ]:
            question = {
                **FIXTURES["questions"][0],
                "choices": choices,
                "expectedAnswer": answer,
                "difficulty": 3,
            }
            self.assertEqual(_sanitize_questions([question], request), [])
            self.assertFalse(_has_reviewable_choices(question))

    def test_choice_set_identity_cannot_collide_on_literal_separators(self):
        first = ["a|b", "c", "d", "e"]
        second = ["a", "b|c", "d", "e"]
        self.assertNotEqual(_choice_set_key(first), _choice_set_key(second))
        self.assertEqual(_choice_set_key(first), _choice_set_key(list(reversed(first))))

    def test_history_keeps_significant_internal_whitespace(self):
        item = FIXTURES["questions"][7]
        payload = _request_payload(target_count=1)
        payload["existingQuestionCoverage"] = [item]
        history = _normalize_request(payload)["existingQuestionCoverage"][0]
        self.assertEqual(history["choices"], item["choices"])
        self.assertEqual(history["expectedAnswer"], item["expectedAnswer"])
        self.assertEqual(_question_coverage_payload(item)["choices"], item["choices"])

    def test_unicode_literal_retains_the_independently_counted_correct_answer(self):
        request = _normalize_request(_request_payload(target_count=1))
        question = {
            **FIXTURES["questions"][-1],
            "difficulty": 3,
            "topic": "Python strings",
        }
        accepted = _sanitize_questions([question], request)[0]
        # literal_eval reads only a literal; this independently verifies its
        # value, not just equality of implementation-generated keys.
        self.assertEqual(len(ast.literal_eval(accepted["expectedAnswer"])), 2)
        self.assertEqual(
            [len(ast.literal_eval(choice)) for choice in accepted["choices"]],
            [2, 1, 1, 1],
        )

        def review(_system, prompt):
            data = json.loads(
                prompt.split("<question_review_json>\n")[1].split(
                    "\n</question_review_json>"
                )[0]
            )
            self.assertIn(question["expectedAnswer"], data["items"][0]["choices"])
            return json.dumps(
                {
                    "reviews": [
                        {
                            "index": 0,
                            "valid": True,
                            "answer": question["expectedAnswer"],
                            "difficulty": 3,
                            "explanation": question["explanation"],
                            "choiceExplanations": {
                                choice: "This literal has the displayed Unicode sequence."
                                for choice in question["choices"]
                            },
                        }
                    ]
                }
            )

        reviewed = verify_questions([accepted], request, review)[0]
        restored = json.loads(json.dumps(reviewed))
        self.assertEqual(len(ast.literal_eval(restored["expectedAnswer"])), 2)
        self.assertIn(question["expectedAnswer"], restored["choiceExplanations"])
        self.assertNotIn('"é"', restored["choiceExplanations"])

    def test_composition_cannot_supply_a_missing_key_or_relabel_review_feedback(self):
        request = _normalize_request(_request_payload(target_count=1))
        question = {
            **FIXTURES["questions"][-1],
            "difficulty": 3,
            "topic": "Python strings",
        }
        wrong_key = {**question, "expectedAnswer": '"é"'}
        self.assertEqual(_sanitize_questions([wrong_key], request), [])
        self.assertFalse(_has_reviewable_choices(wrong_key))
        for wrong_answer in (True, False):
            feedback = {
                choice: "This literal has the displayed Unicode sequence."
                for choice in question["choices"]
            }
            if not wrong_answer:
                feedback['"é"'] = feedback.pop(question["expectedAnswer"])
            verdict = {
                "index": 0,
                "valid": True,
                "answer": '"é"' if wrong_answer else question["expectedAnswer"],
                "difficulty": 3,
                "explanation": question["explanation"],
                "choiceExplanations": feedback,
            }
            self.assertEqual(
                verify_questions(
                    [question], request, lambda *_: json.dumps({"reviews": [verdict]})
                ),
                [],
            )

    def test_canonical_alternatives_are_rejected_without_content_mutation(self):
        request = _normalize_request(_request_payload(target_count=1))
        for choices in FIXTURES["unrepresentable_choices"]:
            question = {
                **FIXTURES["questions"][-1],
                "choices": choices,
                "expectedAnswer": choices[0],
                "difficulty": 3,
            }
            before = json.dumps(question)
            self.assertEqual(_sanitize_questions([question], request), [])
            self.assertFalse(_has_reviewable_choices(question))
            self.assertEqual(json.dumps(question), before)

    def test_unicode_choice_and_answer_history_remain_distinct(self):
        questions = [
            {**item, "topic": "Python strings", "difficulty": 3}
            for item in FIXTURES["unicode_history_questions"]
        ]
        request = _normalize_request(_request_payload(target_count=2))
        self.assertEqual(len(_sanitize_questions(questions, request)), 2)
        payload = _request_payload(target_count=1)
        payload["existingQuestionCoverage"] = [questions[0]]
        request = _normalize_request(payload)
        self.assertEqual(
            request["existingQuestionCoverage"][0]["expectedAnswer"],
            questions[0]["expectedAnswer"],
        )
        self.assertEqual(
            _sanitize_questions(questions, request)[0]["expectedAnswer"],
            questions[1]["expectedAnswer"],
        )
        self.assertNotEqual(*[_choice_set_key(q["choices"]) for q in questions])
        self.assertNotEqual(
            *[
                _question_coverage_keys(q["expectedAnswer"], q["topic"])
                for q in questions
            ]
        )

    def test_shared_study_coaching_intent_contract(self):
        goal = {"title": "Learn the subject", "learningTarget": "Subject content"}
        for prompt in FIXTURES["subject_prompts"]:
            self.assertFalse(_looks_like_study_strategy(prompt, goal), prompt)
        for prompt in FIXTURES["coaching_prompts"]:
            self.assertTrue(_looks_like_study_strategy(prompt, goal), prompt)
            self.assertFalse(
                _looks_like_study_strategy(prompt, {"title": "Study skills"}), prompt
            )
