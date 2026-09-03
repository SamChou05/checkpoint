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
        self.assertEqual(
            first[0]["remoteID"],
            str(
                uuid.uuid5(
                    uuid.NAMESPACE_URL,
                    "checkpoint:"
                    + ("a" * 64)
                    + ":stem:"
                    + question_bank._normalized_stem_identity(raw["prompt"]),  # noqa: SLF001
                )
            ),
        )

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

    def test_preparation_rejects_same_stem_when_other_fields_change(self):
        original = {
            "prompt": "Which conclusion follows from the stated evidence?",
            "expectedAnswer": "The supported conclusion.",
            "choices": ["The supported conclusion.", "B", "C", "D"],
            "explanation": "The evidence supports it.",
            "topic": "Reasoning",
            "difficulty": 3,
            "format": "Multiple Choice",
        }
        stored = question_bank._prepare_questions("a" * 64, [original], [])[0]  # noqa: SLF001
        history = [
            {
                "remoteID": {"S": stored["remoteID"]},
                "state": {"S": "claimed"},
                "questionJSON": {"S": json.dumps(stored)},
            }
        ]
        changed = {
            **original,
            "prompt": (
                "Choose the correct answer to this question: " + original["prompt"]
            ),
            "expectedAnswer": "A differently phrased supported conclusion.",
            "choices": [
                "A differently phrased supported conclusion.",
                "Different distractor D",
                "Different distractor C",
                "Different distractor B",
            ],
            "explanation": "A new explanation reaches the same question stem.",
            "difficulty": 4,
        }

        regenerated = question_bank._prepare_questions(  # noqa: SLF001
            "a" * 64,
            [changed],
            history,
        )

        self.assertEqual(regenerated, [])

    def test_preparation_checks_stems_across_full_history_not_feedback_window(self):
        bank_id = "a" * 64
        raw_questions = [
            {
                "prompt": f"Historical question number {index}: what follows?",
                "expectedAnswer": f"Historical answer number {index}.",
                "choices": [
                    f"Historical answer number {index}.",
                    f"Distractor B {index}",
                    f"Distractor C {index}",
                    f"Distractor D {index}",
                ],
                "explanation": f"Historical explanation number {index}.",
                "topic": "Reasoning",
                "difficulty": 3,
                "format": "Multiple Choice",
            }
            for index in range(31)
        ]
        stored_questions = [
            question_bank._prepare_questions(bank_id, [question], [])[0]  # noqa: SLF001
            for question in raw_questions
        ]
        history = [
            {
                "remoteID": {"S": question["remoteID"]},
                "state": {"S": "claimed"},
                "questionJSON": {"S": json.dumps(question)},
            }
            for question in stored_questions
        ]
        repeated_oldest = {
            **raw_questions[0],
            "explanation": "Changed after the original fell outside provider feedback.",
        }

        regenerated = question_bank._prepare_questions(  # noqa: SLF001
            bank_id,
            [repeated_oldest],
            history,
        )

        self.assertEqual(len(history), 31)
        self.assertEqual(regenerated, [])

    def test_preparation_recognizes_legacy_full_question_remote_id(self):
        bank_id = "a" * 64
        raw = {
            "prompt": "Which statement follows from the legacy evidence?",
            "expectedAnswer": "The supported statement.",
            "choices": ["The supported statement.", "B", "C", "D"],
            "explanation": "The evidence supports it.",
            "topic": "Reasoning",
            "difficulty": 3,
            "format": "Multiple Choice",
        }
        legacy_remote_id = str(
            uuid.uuid5(
                uuid.NAMESPACE_URL,
                f"checkpoint:{bank_id}:{question_bank._json(raw)}",  # noqa: SLF001
            )
        )

        regenerated = question_bank._prepare_questions(  # noqa: SLF001
            bank_id,
            [raw],
            [{"remoteID": {"S": legacy_remote_id}, "state": {"S": "claimed"}}],
        )

        self.assertEqual(regenerated, [])

    def test_stem_identity_preserves_meaningful_math_operators(self):
        plus = question_bank._normalized_stem_identity("What is x + 1?")  # noqa: SLF001
        compact_plus = question_bank._normalized_stem_identity(  # noqa: SLF001
            "What is x+1?"
        )
        minus = question_bank._normalized_stem_identity("What is x - 1?")  # noqa: SLF001
        superscript = question_bank._normalized_stem_identity(  # noqa: SLF001
            "What is x²?"
        )
        plain_digit = question_bank._normalized_stem_identity(  # noqa: SLF001
            "What is x2?"
        )
        cosmetic_variant = question_bank._normalized_stem_identity(  # noqa: SLF001
            "  WHAT   is x + 1 !  "
        )

        self.assertEqual(plus, compact_plus)
        self.assertNotEqual(plus, minus)
        self.assertNotEqual(superscript, plain_digit)
        self.assertEqual(plus, cosmetic_variant)
        self.assertEqual(
            question_bank._stem_fingerprint("What is x + 1?"),  # noqa: SLF001
            "66a0e917835b1b99",
        )
        self.assertEqual(  # Same normalized identity has the same wire fingerprint.
            question_bank._stem_fingerprint("What is x+1?"),  # noqa: SLF001
            "66a0e917835b1b99",
        )
        self.assertNotEqual(
            question_bank._stem_fingerprint("What is x²?"),  # noqa: SLF001
            question_bank._stem_fingerprint("What is x2?"),  # noqa: SLF001
        )

        for operator in (
            "!=",
            "==",
            "<=",
            ">=",
            "+",
            "-",
            "−",
            "×",
            "÷",
            "=",
            "<",
            ">",
            "≤",
            "≥",
            "≠",
            "±",
            "∓",
            "⋅",
            "·",
            "*",
            "/",
            "^",
            "%",
        ):
            with self.subTest(operator=operator):
                spaced = question_bank._normalized_stem_identity(  # noqa: SLF001
                    f"What is x {operator} 1?"
                )
                compact = question_bank._normalized_stem_identity(  # noqa: SLF001
                    f"What is x{operator}1?"
                )
                self.assertEqual(spaced, compact)

    def test_stem_identity_does_not_erase_leading_meaningful_punctuation(self):
        leading_punctuation = question_bank._normalized_stem_identity(  # noqa: SLF001
            "?What does this operator mean?"
        )
        ordinary = question_bank._normalized_stem_identity(  # noqa: SLF001
            "What does this operator mean?"
        )

        self.assertNotEqual(leading_punctuation, ordinary)

    def test_stem_identity_removes_only_exact_presentation_wrappers(self):
        bare = question_bank._normalized_stem_identity(  # noqa: SLF001
            "What does the evidence establish?"
        )
        wrapped = question_bank._normalized_stem_identity(  # noqa: SLF001
            "Choose the correct answer to this question: What does the evidence establish?"
        )
        first_shared_passage_question = question_bank._normalized_stem_identity(  # noqa: SLF001
            "A passage says 'Demand increased.' What caused the change?"
        )
        second_shared_passage_question = question_bank._normalized_stem_identity(  # noqa: SLF001
            "A passage says 'Demand increased.' What evidence supports the claim?"
        )

        self.assertEqual(bare, wrapped)
        self.assertNotEqual(
            first_shared_passage_question,
            second_shared_passage_question,
        )

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
        discarded = {
            "state": {"S": "discarded"},
            "questionJSON": {"S": json.dumps({"skillID": first_skill})},
        }

        finite = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [claimed, discarded],
            desired_count=4,
            low_watermark=0,
            target_count=3,
        )
        replenishing = question_bank._worker_skill_allocation(  # noqa: SLF001
            request,
            [claimed, discarded],
            desired_count=4,
            low_watermark=1,
            target_count=3,
        )

        self.assertEqual(finite, {first_skill: 1, second_skill: 2})
        self.assertEqual(replenishing, {first_skill: 2, second_skill: 1})

    def test_worker_objective_allocation_expands_finite_bank_breadth_across_chunks(
        self,
    ):
        skill_id = "11111111-1111-4111-8111-111111111111"
        objective_ids = [
            f"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa{index}"
            for index in range(1, 6)
        ]
        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {
                        "id": skill_id,
                        "name": "Reasoning",
                        "objectives": [
                            {"id": objective_id, "name": f"Objective {index}"}
                            for index, objective_id in enumerate(
                                objective_ids,
                                start=1,
                            )
                        ],
                    }
                ],
            },
            "desiredSkillAllocation": {skill_id: 1},
        }
        history = []
        generated_objective_ids = []

        for target_count in (2, 2, 1):
            skill_allocation = question_bank._worker_skill_allocation(  # noqa: SLF001
                request,
                history,
                desired_count=5,
                low_watermark=0,
                target_count=target_count,
            )
            objective_allocation = question_bank._worker_objective_allocation(  # noqa: SLF001
                request,
                history,
                desired_count=5,
                low_watermark=0,
                requested_skill_allocation=skill_allocation,
            )
            self.assertEqual(sum(item["count"] for item in objective_allocation), target_count)
            for item in objective_allocation:
                self.assertEqual(item["skillID"], skill_id)
                generated_objective_ids.extend([item["objectiveID"]] * item["count"])
                history.extend(
                    {
                        "state": {
                            "S": "ready" if len(history) % 2 == 0 else "claimed"
                        },
                        "questionJSON": {
                            "S": json.dumps(
                                {
                                    "skillID": skill_id,
                                    "objectiveID": item["objectiveID"],
                                }
                            )
                        },
                    }
                    for _ in range(item["count"])
                )

        self.assertEqual(generated_objective_ids, objective_ids)

    def test_worker_objective_allocation_counts_claimed_only_for_finite_bank(self):
        skill_id = "11111111-1111-4111-8111-111111111111"
        first_objective = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        second_objective = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {
                        "id": skill_id,
                        "name": "Reasoning",
                        "objectives": [
                            {"id": first_objective, "name": "First"},
                            {"id": second_objective, "name": "Second"},
                        ],
                    }
                ],
            },
            "desiredSkillAllocation": {skill_id: 1},
        }
        claimed = {
            "state": {"S": "claimed"},
            "questionJSON": {
                "S": json.dumps(
                    {"skillID": skill_id, "objectiveID": first_objective}
                )
            },
        }

        finite = question_bank._worker_objective_allocation(  # noqa: SLF001
            request,
            [claimed],
            desired_count=2,
            low_watermark=0,
            requested_skill_allocation={skill_id: 1},
        )
        replenishing = question_bank._worker_objective_allocation(  # noqa: SLF001
            request,
            [claimed],
            desired_count=2,
            low_watermark=1,
            requested_skill_allocation={skill_id: 1},
        )

        self.assertEqual(finite[0]["objectiveID"], second_objective)
        self.assertEqual(replenishing[0]["objectiveID"], first_objective)

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

    def test_durable_weighting_gates_full_objective_coverage_by_capability(
        self,
    ):
        major_skill = "11111111-1111-4111-8111-111111111111"
        minor_skill = "22222222-2222-4222-8222-222222222222"

        def objectives(prefix, count):
            return [
                {
                    "id": f"{prefix * 8}-{prefix * 4}-4{prefix * 3}-8{prefix * 3}-{prefix * 11}{index}",
                    "name": f"Objective {index}",
                }
                for index in range(1, count + 1)
            ]

        request = {
            "skillMap": {
                "version": 1,
                "skills": [
                    {
                        "id": major_skill,
                        "name": "Major",
                        "objectives": objectives("a", 4),
                    },
                    {
                        "id": minor_skill,
                        "name": "Minor",
                        "objectives": objectives("b", 2),
                    },
                ],
            },
            "desiredSkillAllocation": {major_skill: 99, minor_skill: 1},
        }

        question_bank._validate_durable_skill_allocation(request, 8)  # noqa: SLF001

        opted_in = copy.deepcopy(request)
        opted_in["requiresFullObjectiveCoverage"] = True
        with self.assertRaises(question_bank.QuestionBankError) as raised:
            question_bank._validate_durable_skill_allocation(opted_in, 8)  # noqa: SLF001

        self.assertEqual(raised.exception.status_code, 400)
        self.assertEqual(raised.exception.code, "invalid_request")

        feasible = copy.deepcopy(opted_in)
        feasible["desiredSkillAllocation"] = {major_skill: 3, minor_skill: 1}
        question_bank._validate_durable_skill_allocation(feasible, 8)  # noqa: SLF001

        ignored = copy.deepcopy(opted_in)
        ignored["desiredSkillAllocation"] = {major_skill: 1, minor_skill: 0}
        question_bank._validate_durable_skill_allocation(ignored, 4)  # noqa: SLF001

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
