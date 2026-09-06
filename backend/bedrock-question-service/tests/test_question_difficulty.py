import copy
import os
from pathlib import Path
import re
import unittest
from unittest.mock import patch

from lambda_test_support import _request_payload, _skill_map
from question_difficulty import DIFFICULTY_GUIDANCE, DIFFICULTY_RUBRIC
from question_generation import _json_retry_prompt, _system_prompt, _user_prompt
from request_contract import _normalize_request
from question_verification import REVIEW_SYSTEM_PROMPT
from service_errors import BadRequestError


class QuestionDifficultyTests(unittest.TestCase):
    def test_stale_request_prose_cannot_weaken_any_numeric_target(self):
        for level, guidance in enumerate(DIFFICULTY_GUIDANCE, 1):
            with self.subTest(level=level):
                payload = _request_payload(minimum_difficulty=level)
                payload["difficultyGuidance"] = "STALE: only ask simple definitions."
                request = _normalize_request(payload)
                self.assertEqual(request["difficultyGuidance"], guidance)
                # Also exercise already-normalized queue payloads from an older
                # release, which can bypass current request normalization.
                request["difficultyGuidance"] = payload["difficultyGuidance"]
                original = copy.deepcopy(request)
                for prompt in (
                    _user_prompt(request),
                    _json_retry_prompt(request, "malformed output"),
                ):
                    self.assertIn(guidance, prompt)
                    self.assertNotIn("STALE", prompt)
                    self.assertIn(f"Use level {level} of 5 difficulty.", prompt)
                self.assertEqual(request, original)

    def test_adaptive_skill_target_and_goal_floor_keep_distinct_guidance(self):
        payload = _request_payload(minimum_difficulty=3)
        payload["skillMap"] = _skill_map()
        advanced, baseline = payload["skillMap"]["skills"][:2]
        payload["adaptiveSkillPlans"] = [
            {"skillID": advanced["id"], "targetDifficulty": 5, "evidenceCount": 10}
        ]
        request = _normalize_request(payload)
        for prompt in (_user_prompt(request), _json_retry_prompt(request, "bad JSON")):
            self.assertIn(
                f"{advanced['name']} ({advanced['id']}), level 5: {DIFFICULTY_GUIDANCE[4]}",
                prompt,
            )
            self.assertIn(
                f"{baseline['name']} ({baseline['id']}), level 3: {DIFFICULTY_GUIDANCE[2]}",
                prompt,
            )
        self.assertEqual(request["minimumDifficulty"], 3)
        self.assertEqual(request["adaptiveSkillPlans"][0]["targetDifficulty"], 5)

    def test_author_includes_shared_cognitive_rubric(self):
        with patch.dict(os.environ, {"CHECKPOINT_PROMPT_VARIANT": "balanced"}):
            self.assertIn(DIFFICULTY_RUBRIC, _system_prompt())
        self.assertIn(DIFFICULTY_RUBRIC, REVIEW_SYSTEM_PROMPT)

    def test_legacy_guidance_field_still_obeys_request_shape_and_size_limits(self):
        for invalid in (17, "x" * 501):
            with self.subTest(guidance=invalid):
                payload = _request_payload()
                payload["difficultyGuidance"] = invalid
                with self.assertRaises(BadRequestError):
                    _normalize_request(payload)

    def test_client_guidance_matches_backend_for_all_five_levels(self):
        root = Path(__file__).resolve().parents[3]
        client = (root / "Checkpoint/Services/QuestionContext.swift").read_text()
        method = client.split("static func difficultyGuidance(for level: Int)", 1)[1]
        method = method.split("private static func currentLevelSummary", 1)[0]
        client_guidance = re.findall(r'return "([^"\n]+)"', method)
        self.assertEqual(client_guidance, list(DIFFICULTY_GUIDANCE))


if __name__ == "__main__":
    unittest.main()
