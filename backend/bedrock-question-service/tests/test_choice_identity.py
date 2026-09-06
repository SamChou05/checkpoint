"""Shared content-preservation regressions, also read by the iOS test suite."""

import json
from pathlib import Path
import unittest

from question_quality import (
    _choice_set_key,
    _looks_like_study_strategy,
    _question_coverage_payload,
    _sanitize_questions,
)
from question_verification import _has_reviewable_choices
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
        item = FIXTURES["questions"][-1]
        payload = _request_payload(target_count=1)
        payload["existingQuestionCoverage"] = [item]
        history = _normalize_request(payload)["existingQuestionCoverage"][0]
        self.assertEqual(history["choices"], item["choices"])
        self.assertEqual(history["expectedAnswer"], item["expectedAnswer"])
        self.assertEqual(_question_coverage_payload(item)["choices"], item["choices"])

    def test_shared_study_coaching_intent_contract(self):
        goal = {"title": "Learn the subject", "learningTarget": "Subject content"}
        for prompt in FIXTURES["subject_prompts"]:
            self.assertFalse(_looks_like_study_strategy(prompt, goal), prompt)
        for prompt in FIXTURES["coaching_prompts"]:
            self.assertTrue(_looks_like_study_strategy(prompt, goal), prompt)
            self.assertFalse(
                _looks_like_study_strategy(prompt, {"title": "Study skills"}), prompt
            )
