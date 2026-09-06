import copy
import unittest

from lambda_test_support import _request_payload, _skill_map, _raw_question
from question_generation import _user_prompt, _json_retry_prompt
from question_quality import _sanitize_questions
from question_bank_worker import _worker_objective_allocation
from request_contract import _normalize_request
from service_errors import BadRequestError


class AdaptiveLearningTests(unittest.TestCase):
    def payload(self):
        payload = _request_payload(target_count=2, minimum_difficulty=1)
        payload["skillMap"] = _skill_map()
        skill = payload["skillMap"]["skills"][0]
        payload["adaptiveSkillPlans"] = [
            {
                "skillID": skill["id"],
                "targetDifficulty": 4,
                "evidenceCount": 10,
                "recentAccuracyPercent": 90,
                "focusObjectiveIDs": [skill["objectives"][0]["id"]],
                "recentMistakes": [
                    {
                        "objectiveID": skill["objectives"][0]["id"],
                        "prompt": "A concrete prior scenario",
                        "selectedAnswer": "A tempting misconception",
                        "expectedAnswer": "The supported inference",
                    }
                ],
            }
        ]
        return payload

    def test_skill_targets_and_answer_evidence_reach_generation(self):
        request = _normalize_request(self.payload())
        prompt = _user_prompt(request)
        self.assertIn("targetDifficulty", prompt)
        self.assertIn("A tempting misconception", prompt)
        self.assertIn("goal minimum is only a lower bound", prompt)
        self.assertEqual(request["adaptiveSkillPlans"][0]["targetDifficulty"], 4)

    def test_plan_cannot_cross_skill_boundaries_or_override_floor(self):
        payload = self.payload()
        mutations = [
            ("targetDifficulty", 0),
            ("targetDifficulty", True),
            ("evidenceCount", 500),
            ("recentAccuracyPercent", 101),
            (
                "focusObjectiveIDs",
                [payload["skillMap"]["skills"][1]["objectives"][0]["id"]],
            ),
        ]
        for field, value in mutations:
            with self.subTest(field=field, value=value):
                invalid = copy.deepcopy(payload)
                invalid["adaptiveSkillPlans"][0][field] = value
                with self.assertRaises(BadRequestError):
                    _normalize_request(invalid)

    def test_advanced_skills_replace_stale_baseline_guidance_in_initial_and_retry_prompts(
        self,
    ):
        payload = self.payload()
        payload["difficultyGuidance"] = "OLD_BASELINE: only ask simple definitions."
        request = _normalize_request(payload)
        original = copy.deepcopy(request)
        skill = request["skillMap"]["skills"][0]
        for prompt in [
            _user_prompt(request),
            _json_retry_prompt(request, "invalid JSON"),
        ]:
            with self.subTest(prompt=prompt[:40]):
                self.assertNotIn("OLD_BASELINE", prompt)
                self.assertIn(
                    f"{skill['name']} ({skill['id']}), level 4: Hard reasoning", prompt
                )
                self.assertIn("goal minimum is only a lower bound", prompt)
        self.assertEqual(request, original)

    def test_guidance_keeps_unplanned_skills_at_the_goal_minimum(self):
        request = _normalize_request(self.payload())
        other_skill = request["skillMap"]["skills"][1]
        self.assertIn(
            f"{other_skill['name']} ({other_skill['id']}), level 1: Foundations",
            _user_prompt(request),
        )
        request["adaptiveSkillPlans"] = []
        request["difficultyGuidance"] = "Custom guidance for the initial goal."
        for prompt in [
            _user_prompt(request),
            _json_retry_prompt(request, "invalid JSON"),
        ]:
            self.assertIn("Custom guidance for the initial goal.", prompt)

    def test_question_difficulty_must_match_its_skill_plan(self):
        payload = self.payload()
        payload["targetCount"] = 1
        request = _normalize_request(payload)
        skill = request["skillMap"]["skills"][0]
        question = _raw_question(
            "Which conclusion follows from this argument?",
            difficulty=1,
            topic=skill["name"],
        )
        question.update(skillID=skill["id"], objectiveID=skill["objectives"][0]["id"])
        self.assertEqual(_sanitize_questions([question], request), [])
        question["difficulty"] = 4
        self.assertEqual(len(_sanitize_questions([question], request)), 1)

    def test_missed_objectives_receive_more_transfer_practice_with_breadth(self):
        request = _normalize_request(self.payload())
        skill = request["skillMap"]["skills"][0]
        skill["objectives"].append(
            {"id": "77777777-7777-4777-8777-777777777777", "name": "Other objective"}
        )
        request["desiredSkillAllocation"] = {skill["id"]: 1}
        allocation = _worker_objective_allocation(
            request,
            [],
            desired_count=8,
            low_watermark=0,
            requested_skill_allocation={skill["id"]: 8},
        )
        counts = {item["objectiveID"]: item["count"] for item in allocation}
        self.assertGreater(
            counts[skill["objectives"][0]["id"]], counts[skill["objectives"][1]["id"]]
        )
        self.assertGreater(counts[skill["objectives"][1]["id"]], 0)
