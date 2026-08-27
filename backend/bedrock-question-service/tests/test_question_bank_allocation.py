import copy
import json
import unittest
import uuid

import question_bank
from question_bank_test_support import (
    QuestionBankTestCase,
)


class QuestionBankAllocationTests(QuestionBankTestCase):
    def test_bank_response_distinguishes_retry_cooldown_from_finite_exhaustion(self):
        retrying = {
            "bankID": {"S": "a" * 64},
            "desiredCount": {"N": "40"},
            "readyCount": {"N": "0"},
            "state": {"S": "failed"},
            "refillAfter": {"N": str(int(question_bank.time.time()) + 60)},
        }
        exhausted = {
            **retrying,
            "state": {"S": "empty"},
            "initialFillComplete": {"BOOL": True},
        }

        self.assertEqual(question_bank._bank_response(retrying)["status"], "queued")  # noqa: SLF001
        self.assertEqual(question_bank._bank_response(exhausted)["status"], "empty")  # noqa: SLF001

    def test_prepared_question_ids_are_stable_uuid_and_deduplicated(self):
        raw = {
            "prompt": "Which statement follows?",
            "expectedAnswer": "The supported statement.",
            "choices": ["The supported statement.", "B", "C", "D"],
            "explanation": "The facts support it.",
            "topic": "Reasoning",
            "difficulty": 3,
            "format": "Multiple Choice",
        }
        first = question_bank._prepare_questions("a" * 64, [raw, raw], [])  # noqa: SLF001
        second = question_bank._prepare_questions("a" * 64, [raw], [])  # noqa: SLF001
        self.assertEqual(len(first), 1)
        self.assertEqual(first, second)
        uuid.UUID(first[0]["remoteID"])

        claimed_history = [
            {
                "remoteID": {"S": first[0]["remoteID"]},
                "state": {"S": "claimed"},
            }
        ]
        regenerated = question_bank._prepare_questions(  # noqa: SLF001
            "a" * 64,
            [raw],
            claimed_history,
        )
        self.assertEqual(regenerated, [])

    def test_worker_skill_allocation_honors_targets_with_batch_breadth(self):
        first_skill = "11111111-1111-4111-8111-111111111111"
        second_skill = "22222222-2222-4222-8222-222222222222"
        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {"id": first_skill, "name": "Reasoning", "objectives": []},
                    {"id": second_skill, "name": "Evidence", "objectives": []},
                ],
            },
            "desiredSkillAllocation": {first_skill: 6, second_skill: 2},
        }

        allocation = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [],
            desired_count=8,
            low_watermark=0,
            target_count=4,
        )

        self.assertEqual(allocation, {first_skill: 3, second_skill: 1})

    def test_worker_skill_allocation_does_not_starve_sixth_skill_across_chunks(self):
        skill_ids = [
            f"{index:08d}-1111-4111-8111-111111111111" for index in range(1, 7)
        ]
        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {"id": skill_id, "name": f"Skill {index}", "objectives": []}
                    for index, skill_id in enumerate(skill_ids, start=1)
                ],
            },
            "desiredSkillAllocation": {skill_id: 1 for skill_id in skill_ids},
        }

        first = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [],
            desired_count=40,
            low_watermark=0,
            target_count=5,
        )
        first_items = [
            {
                "state": {"S": "ready"},
                "questionJSON": {"S": json.dumps({"skillID": skill_id})},
            }
            for skill_id, count in first.items()
            for _ in range(count)
        ]
        second = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            first_items,
            desired_count=40,
            low_watermark=0,
            target_count=5,
        )

        self.assertEqual(sum(first.values()), 5)
        self.assertEqual(sum(second.values()), 5)
        self.assertNotIn(skill_ids[-1], first)
        self.assertEqual(second[skill_ids[-1]], 1)

    def test_worker_skill_allocation_counts_claimed_history_only_for_finite_bank(self):
        first_skill = "11111111-1111-4111-8111-111111111111"
        second_skill = "22222222-2222-4222-8222-222222222222"
        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {"id": first_skill, "name": "Reasoning", "objectives": []},
                    {"id": second_skill, "name": "Evidence", "objectives": []},
                ],
            },
            "desiredSkillAllocation": {},
        }
        claimed = {
            "state": {"S": "claimed"},
            "questionJSON": {"S": json.dumps({"skillID": first_skill})},
        }

        finite = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [claimed],
            desired_count=4,
            low_watermark=0,
            target_count=3,
        )
        replenishing = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [claimed],
            desired_count=4,
            low_watermark=1,
            target_count=3,
        )

        self.assertEqual(finite, {first_skill: 1, second_skill: 2})
        self.assertEqual(replenishing, {first_skill: 2, second_skill: 1})

    def test_imbalanced_stable_weights_keep_minor_skill_through_refill(self):
        major_skill = "11111111-1111-4111-8111-111111111111"
        maintenance_skill = "22222222-2222-4222-8222-222222222222"
        request = {
            "skillMap": {
                "version": 3,
                "skills": [
                    {"id": major_skill, "name": "Core", "objectives": []},
                    {
                        "id": maintenance_skill,
                        "name": "Maintenance",
                        "objectives": [],
                    },
                ],
            },
            "desiredSkillAllocation": {major_skill: 99, maintenance_skill: 1},
        }

        targets = question_bank._apportion_skill_counts(  # noqa: SLF001
            [major_skill, maintenance_skill],
            request["desiredSkillAllocation"],
            40,
        )
        initial_batch = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [],
            desired_count=40,
            low_watermark=10,
            target_count=5,
        )
        ready_major = [
            {
                "state": {"S": "ready"},
                "questionJSON": {"S": json.dumps({"skillID": major_skill})},
            }
            for _ in range(9)
        ]
        claimed_maintenance = {
            "state": {"S": "claimed"},
            "questionJSON": {"S": json.dumps({"skillID": maintenance_skill})},
        }
        refill_batch = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            ready_major + [claimed_maintenance],
            desired_count=40,
            low_watermark=10,
            target_count=5,
        )

        self.assertEqual(targets, {major_skill: 39, maintenance_skill: 1})
        self.assertEqual(initial_batch, {major_skill: 4, maintenance_skill: 1})
        self.assertEqual(refill_batch, {major_skill: 4, maintenance_skill: 1})

    def test_durable_weight_map_requires_room_and_stays_fixed_per_revision(self):
        first_skill = "11111111-1111-4111-8111-111111111111"
        second_skill = "22222222-2222-4222-8222-222222222222"
        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {"id": first_skill, "name": "Core", "objectives": []},
                    {"id": second_skill, "name": "Review", "objectives": []},
                ],
            },
            "desiredSkillAllocation": {first_skill: 99, second_skill: 1},
        }

        with self.assertRaises(question_bank.QuestionBankError) as raised:
            question_bank._validate_durable_skill_allocation(request, 1)  # noqa: SLF001
        changed = copy.deepcopy(request)
        changed["desiredSkillAllocation"] = {first_skill: 1, second_skill: 99}

        self.assertEqual(raised.exception.status_code, 400)
        self.assertNotEqual(
            question_bank._skill_allocation_key(request),  # noqa: SLF001
            question_bank._skill_allocation_key(changed),  # noqa: SLF001
        )

    def test_prepared_questions_retain_skill_and_objective_tags(self):
        question = {
            "prompt": "Which conclusion follows?",
            "expectedAnswer": "The supported conclusion.",
            "choices": ["The supported conclusion.", "B", "C", "D"],
            "explanation": "The evidence supports it.",
            "topic": "Reasoning",
            "skillID": "11111111-1111-4111-8111-111111111111",
            "objectiveID": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "objective": "Draw supported conclusions",
            "difficulty": 3,
            "format": "Multiple Choice",
        }

        prepared = question_bank._prepare_questions(  # noqa: SLF001
            "a" * 64,
            [question],
            [],
        )

        self.assertEqual(prepared[0]["skillID"], question["skillID"])
        self.assertEqual(prepared[0]["objectiveID"], question["objectiveID"])
        self.assertEqual(prepared[0]["objective"], question["objective"])


if __name__ == "__main__":
    unittest.main()
