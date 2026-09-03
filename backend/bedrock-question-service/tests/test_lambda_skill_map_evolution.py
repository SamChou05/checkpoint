import copy
import json
import os
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import lambda_function
from lambda_test_support import BackendTestCase, FakeBedrockClient, _event


TEMPLATE = Path(__file__).resolve().parents[1] / "template.yaml"


def _current_skill_map(version=7):
    return {
        "version": version,
        "skills": [
            {
                "id": "11111111-1111-4111-8111-111111111111",
                "name": "Argument Analysis",
                "objectives": [
                    {
                        "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                        "name": "Identify assumptions",
                    },
                    {
                        "id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
                        "name": "Test conclusions",
                    },
                ],
            },
            {
                "id": "22222222-2222-4222-8222-222222222222",
                "name": "Evidence Evaluation",
                "objectives": [
                    {
                        "id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                        "name": "Distinguish causation",
                    },
                    {
                        "id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
                        "name": "Assess samples",
                    },
                ],
            },
            {
                "id": "33333333-3333-4333-8333-333333333333",
                "name": "Reading Inference",
                "objectives": [
                    {
                        "id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
                        "name": "Infer author commitments",
                    },
                    {
                        "id": "ffffffff-ffff-4fff-8fff-ffffffffffff",
                        "name": "Resolve passage implications",
                    },
                ],
            },
        ],
    }


def _provider_change(predecessor_id, name, objectives):
    return {
        "action": "advance",
        "predecessorSkillID": predecessor_id,
        "successor": {
            "name": name,
            "objectives": [{"name": objective} for objective in objectives],
        },
    }


def _provider_response(mastered_ids):
    changes = [
        _provider_change(
            mastered_ids[0],
            "Argument Constraint Synthesis",
            [
                "Resolve competing logical constraints",
                "Evaluate counterfactual conclusion changes",
            ],
        )
    ]
    if len(mastered_ids) == 2:
        changes.append(
            _provider_change(
                mastered_ids[1],
                "Causal Evidence Diagnostics",
                [
                    "Diagnose confounding in study designs",
                    "Select evidence that distinguishes causal models",
                ],
            )
        )
    return {"changes": changes}


def _evolution_payload(mastered_count=1):
    skill_map = _current_skill_map()
    mastered_skills = skill_map["skills"][:mastered_count]
    now = datetime.now(timezone.utc)
    recent_attempts = []
    for skill_index, skill in enumerate(mastered_skills):
        for attempt_index in range(4):
            recent_attempts.append(
                {
                    "skillID": skill["id"],
                    "objectiveID": skill["objectives"][attempt_index % 2]["id"],
                    "difficulty": 4 if attempt_index == 0 else 3,
                    "result": "correct",
                    "occurredAt": (
                        now - timedelta(minutes=(skill_index * 10) + attempt_index + 1)
                    )
                    .isoformat()
                    .replace("+00:00", "Z"),
                }
            )
    return {
        "goal": {
            "id": "01234567-89ab-4cde-8fab-0123456789ab",
            "title": "Master LSAT reasoning",
            "learningTarget": "Apply rigorous LSAT reasoning under time pressure",
            "focusAreas": "logic and evidence",
            "contentTopics": ["Logical Reasoning", "Reading Comprehension"],
        },
        "baseMapFingerprint": lambda_function._skill_map_fingerprint(skill_map),
        "currentSkillMap": skill_map,
        "masteredSkillIDs": [skill["id"] for skill in mastered_skills],
        "competencies": [
            {
                "skillID": skill["id"],
                "topic": skill["name"],
                "estimatedLevel": 4.5,
                "masteryPercent": 90,
                "attempts": 12,
                "correct": 11,
                "partial": 1,
                "incorrect": 0,
                "currentStreak": 4,
            }
            for skill in mastered_skills
        ],
        "recentAttempts": recent_attempts,
        "archivedSkills": [
            {
                "id": "99999999-9999-4999-8999-999999999999",
                "name": "Formal Logic Basics",
            }
        ],
        "archivedSkillNameFingerprints": ["c229f5dbe43478b7"],
        "sourceDocuments": [],
    }


class LambdaSkillMapEvolutionTests(BackendTestCase):
    def test_fingerprint_matches_swift_fnv1a_wire_signature(self):
        skill_map = _current_skill_map()
        skill_map["skills"] = skill_map["skills"][:2]

        self.assertEqual(
            lambda_function._skill_map_fingerprint(skill_map),
            "381b64c118505a42",
        )

    def test_archived_name_fingerprint_matches_swift_canonical_identity(self):
        self.assertEqual(
            lambda_function._skill_name_fingerprint("Formal-Logic Basics"),  # noqa: SLF001
            "c229f5dbe43478b7",
        )

    def test_archived_name_fingerprint_contract_is_optional_validated_and_bounded(self):
        legacy_payload = _evolution_payload()
        legacy_payload.pop("archivedSkillNameFingerprints")
        legacy = lambda_function._normalize_skill_map_evolution_request(  # noqa: SLF001
            legacy_payload
        )
        self.assertEqual(legacy["archivedSkillNameFingerprints"], [])

        for invalid in ("c229f5dbe43478b7", ["C229F5DBE43478B7"], [1]):
            payload = _evolution_payload()
            payload["archivedSkillNameFingerprints"] = invalid
            with self.subTest(invalid=invalid), self.assertRaisesRegex(
                lambda_function.BadRequestError,
                "archivedSkillNameFingerprints",
            ):
                lambda_function._normalize_skill_map_evolution_request(  # noqa: SLF001
                    payload
                )

        oversized = _evolution_payload()
        oversized["archivedSkillNameFingerprints"] = [
            "c229f5dbe43478b7"
        ] * (lambda_function.MAX_ARCHIVED_SKILL_NAME_FINGERPRINTS + 1)
        with self.assertRaisesRegex(
            lambda_function.BadRequestError,
            "must contain at most 750 items",
        ):
            lambda_function._normalize_skill_map_evolution_request(  # noqa: SLF001
                oversized
            )

    def test_endpoint_atomically_replaces_every_mastered_skill(self):
        payload = _evolution_payload(mastered_count=2)
        provider_payload = _provider_response(payload["masteredSkillIDs"])
        first_client = FakeBedrockClient(json.dumps(provider_payload))
        event = _event(payload)
        event["rawPath"] = "/v1/skill-maps/evolve"

        first_response = lambda_function.handle_http_request(
            event,
            bedrock_client=first_client,
        )
        second_response = lambda_function.handle_http_request(
            event,
            bedrock_client=FakeBedrockClient(json.dumps(provider_payload)),
        )

        self.assertEqual(first_response["statusCode"], 200)
        self.assertEqual(first_response["body"], second_response["body"])
        body = json.loads(first_response["body"])
        self.assertEqual(body["baseMapFingerprint"], payload["baseMapFingerprint"])
        self.assertEqual(body["baseVersion"], 7)
        self.assertEqual(body["skillMap"]["version"], 8)
        self.assertEqual(len(body["skillMap"]["skills"]), 3)
        self.assertEqual(
            body["skillMap"]["skills"][2],
            payload["currentSkillMap"]["skills"][2],
        )
        self.assertEqual(
            {replacement["predecessorSkillID"] for replacement in body["replacements"]},
            set(payload["masteredSkillIDs"]),
        )
        successor_ids = {
            replacement["successorSkillID"] for replacement in body["replacements"]
        }
        self.assertEqual(len(successor_ids), 2)
        self.assertTrue(successor_ids.isdisjoint(payload["masteredSkillIDs"]))
        for successor_id in successor_ids:
            uuid.UUID(successor_id)
        for successor in body["skillMap"]["skills"][:2]:
            self.assertIn(successor["id"], successor_ids)
            for objective in successor["objectives"]:
                uuid.UUID(objective["id"])

        prompt = first_client.calls[0]["messages"][0]["content"][0]["text"]
        system_prompt = first_client.calls[0]["system"][0]["text"]
        self.assertIn("every eligible mastered skill", prompt)
        self.assertIn("Formal Logic Basics", prompt)
        self.assertNotIn("archivedSkillNameFingerprints", prompt)
        self.assertNotIn("c229f5dbe43478b7", prompt)
        self.assertIn("exactly one change for every ID", system_prompt)

    def test_provider_subset_is_retried_and_never_partially_applied(self):
        payload = _evolution_payload(mastered_count=2)
        invalid = _provider_response(payload["masteredSkillIDs"])
        invalid["changes"] = invalid["changes"][:1]
        valid = _provider_response(payload["masteredSkillIDs"])
        client = FakeBedrockClient([json.dumps(invalid), json.dumps(valid)])
        event = _event(payload)
        event["rawPath"] = "/v1/skill-maps/evolve"

        response = lambda_function.handle_http_request(event, bedrock_client=client)

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(len(client.calls), 2)
        self.assertEqual(len(json.loads(response["body"])["replacements"]), 2)

    def test_exhausted_invalid_provider_outputs_are_distinct_from_transient_failure(self):
        payload = _evolution_payload()
        invalid = json.dumps({"changes": []})
        client = FakeBedrockClient([invalid, invalid])
        event = _event(payload)
        event["rawPath"] = "/v1/skill-maps/evolve"

        response = lambda_function.handle_http_request(event, bedrock_client=client)

        self.assertEqual(response["statusCode"], 502)
        self.assertEqual(json.loads(response["body"])["code"], "provider_invalid_response")
        self.assertEqual(len(client.calls), 2)

    def test_provider_actions_ids_and_reused_names_are_rejected(self):
        payload = _evolution_payload()
        request = lambda_function._normalize_skill_map_evolution_request(payload)
        valid = _provider_response(payload["masteredSkillIDs"])
        invalid_payloads = []

        wrong_action = copy.deepcopy(valid)
        wrong_action["changes"][0]["action"] = "replace"
        invalid_payloads.append(wrong_action)

        unmastered = copy.deepcopy(valid)
        unmastered["changes"][0]["predecessorSkillID"] = payload["currentSkillMap"][
            "skills"
        ][1]["id"]
        invalid_payloads.append(unmastered)

        active_name = copy.deepcopy(valid)
        active_name["changes"][0]["successor"]["name"] = "Evidence Evaluation"
        invalid_payloads.append(active_name)

        archived_name = copy.deepcopy(valid)
        archived_name["changes"][0]["successor"]["name"] = "Formal Logic Basics"
        invalid_payloads.append(archived_name)

        cosmetic_name = copy.deepcopy(valid)
        cosmetic_name["changes"][0]["successor"]["name"] = "Advanced Argument Analysis"
        invalid_payloads.append(cosmetic_name)

        provider_id = copy.deepcopy(valid)
        provider_id["changes"][0]["successor"]["id"] = str(uuid.uuid4())
        invalid_payloads.append(provider_id)

        repeated_objective = copy.deepcopy(valid)
        repeated_objective["changes"][0]["successor"]["objectives"][0][
            "name"
        ] = "Identify assumptions"
        invalid_payloads.append(repeated_objective)

        for invalid_payload in invalid_payloads:
            with self.subTest(payload=invalid_payload):
                self.assertIsNone(
                    lambda_function._sanitize_skill_map_evolution(
                        invalid_payload,
                        request,
                    )
                )

    def test_full_archived_name_fingerprint_rejects_name_omitted_from_prompt_history(
        self,
    ):
        payload = _evolution_payload()
        payload["archivedSkillNameFingerprints"] = [
            lambda_function._skill_name_fingerprint(  # noqa: SLF001
                "Retired Diagnostic Reasoning"
            )
        ]
        request = lambda_function._normalize_skill_map_evolution_request(  # noqa: SLF001
            payload
        )
        provider_payload = _provider_response(payload["masteredSkillIDs"])
        provider_payload["changes"][0]["successor"]["name"] = (
            "Retired-Diagnostic Reasoning"
        )

        self.assertIsNone(
            lambda_function._sanitize_skill_map_evolution(  # noqa: SLF001
                provider_payload,
                request,
            )
        )
        initial_prompt = lambda_function._skill_map_evolution_user_prompt(  # noqa: SLF001
            request
        )
        retry_prompt = lambda_function._skill_map_evolution_retry_prompt(  # noqa: SLF001
            request,
            "invalid",
        )
        self.assertNotIn("820406795df9b8bb", initial_prompt)
        self.assertNotIn("820406795df9b8bb", retry_prompt)

    def test_version_fingerprint_and_eligibility_fail_before_provider(self):
        base_payload = _evolution_payload()
        mutations = [
            ("fingerprint", lambda payload: payload.update(baseMapFingerprint="0" * 16)),
            (
                "attempts",
                lambda payload: payload["competencies"][0].update(attempts=9),
            ),
            (
                "mastery",
                lambda payload: payload["competencies"][0].update(masteryPercent=84),
            ),
            (
                "streak",
                lambda payload: payload["competencies"][0].update(currentStreak=2),
            ),
        ]

        for label, mutate in mutations:
            with self.subTest(label=label):
                payload = copy.deepcopy(base_payload)
                mutate(payload)
                client = FakeBedrockClient(json.dumps(_provider_response(payload["masteredSkillIDs"])))
                event = _event(payload)
                event["rawPath"] = "/v1/skill-maps/evolve"

                response = lambda_function.handle_http_request(
                    event,
                    bedrock_client=client,
                )

                self.assertEqual(response["statusCode"], 400)
                self.assertEqual(client.calls, [])

    def test_every_objective_requires_recent_evidence(self):
        payload = _evolution_payload()
        first_objective_id = payload["currentSkillMap"]["skills"][0]["objectives"][0][
            "id"
        ]
        for attempt in payload["recentAttempts"]:
            attempt["objectiveID"] = first_objective_id
        client = FakeBedrockClient(json.dumps(_provider_response(payload["masteredSkillIDs"])))
        event = _event(payload)
        event["rawPath"] = "/v1/skill-maps/evolve"

        response = lambda_function.handle_http_request(event, bedrock_client=client)

        self.assertEqual(response["statusCode"], 400)
        self.assertIn("Every objective", response["body"])
        self.assertEqual(client.calls, [])

    def test_every_objective_requires_seventy_five_percent_recent_mastery(self):
        payload = _evolution_payload()
        skill = payload["currentSkillMap"]["skills"][0]
        second_objective_id = skill["objectives"][1]["id"]
        matching_second = [
            attempt
            for attempt in payload["recentAttempts"]
            if attempt["objectiveID"] == second_objective_id
        ]
        matching_second[0]["result"] = "incorrect"
        now = datetime.now(timezone.utc)
        for index in range(4):
            payload["recentAttempts"].append(
                {
                    "skillID": skill["id"],
                    "objectiveID": skill["objectives"][0]["id"],
                    "difficulty": 4,
                    "result": "correct",
                    "occurredAt": (now - timedelta(seconds=index + 1))
                    .isoformat()
                    .replace("+00:00", "Z"),
                }
            )
        client = FakeBedrockClient(json.dumps(_provider_response(payload["masteredSkillIDs"])))
        event = _event(payload)
        event["rawPath"] = "/v1/skill-maps/evolve"

        response = lambda_function.handle_http_request(event, bedrock_client=client)

        self.assertEqual(response["statusCode"], 400)
        self.assertIn("75% recent mastery", response["body"])
        self.assertEqual(client.calls, [])

    def test_multi_objective_attempt_requires_an_objective_id(self):
        payload = _evolution_payload()
        payload["recentAttempts"][0].pop("objectiveID")
        client = FakeBedrockClient(json.dumps(_provider_response(payload["masteredSkillIDs"])))
        event = _event(payload)
        event["rawPath"] = "/v1/skill-maps/evolve"

        response = lambda_function.handle_http_request(event, bedrock_client=client)

        self.assertEqual(response["statusCode"], 400)
        self.assertIn("multi-objective skill", response["body"])
        self.assertEqual(client.calls, [])

    def test_archived_and_active_history_cannot_reuse_ids_or_names(self):
        payload = _evolution_payload()
        payload["archivedSkills"][0]["name"] = payload["currentSkillMap"]["skills"][1][
            "name"
        ]
        client = FakeBedrockClient(json.dumps(_provider_response(payload["masteredSkillIDs"])))
        event = _event(payload)
        event["rawPath"] = "/v1/skill-maps/evolve"

        response = lambda_function.handle_http_request(event, bedrock_client=client)

        self.assertEqual(response["statusCode"], 400)
        self.assertIn("distinct IDs and names", response["body"])
        self.assertEqual(client.calls, [])

    def test_evolution_route_requires_authentication(self):
        os.environ["CHECKPOINT_BACKEND_TOKEN"] = "configured-token"
        payload = _evolution_payload()
        client = FakeBedrockClient(json.dumps(_provider_response(payload["masteredSkillIDs"])))
        event = _event(payload)
        event["rawPath"] = "/v1/skill-maps/evolve"

        response = lambda_function.handle_http_request(event, bedrock_client=client)

        self.assertEqual(response["statusCode"], 401)
        self.assertEqual(client.calls, [])

    def test_successor_id_is_stable_for_reordered_objectives_and_scoped_to_goal(self):
        goal_id = "01234567-89ab-4cde-8fab-0123456789ab"
        predecessor_id = "11111111-1111-4111-8111-111111111111"
        objectives = ["Resolve competing constraints", "Test a counterfactual"]

        first = lambda_function._deterministic_evolved_skill_id(
            goal_id,
            predecessor_id,
            "Argument Constraint Synthesis",
            objectives,
        )
        reordered = lambda_function._deterministic_evolved_skill_id(
            goal_id,
            predecessor_id,
            "Argument Constraint Synthesis",
            list(reversed(objectives)),
        )
        other_goal = lambda_function._deterministic_evolved_skill_id(
            "76543210-abcd-4fed-8cba-9876543210ab",
            predecessor_id,
            "Argument Constraint Synthesis",
            objectives,
        )

        self.assertEqual(first, reordered)
        self.assertNotEqual(first, other_goal)
        self.assertEqual(uuid.UUID(first).version, 5)

    def test_sam_template_deploys_evolution_route_and_output(self):
        template = TEMPLATE.read_text(encoding="utf-8")

        self.assertIn("Path: /v1/skill-maps/evolve", template)
        self.assertIn("SkillMapEvolutionEndpoint:", template)


if __name__ == "__main__":
    unittest.main()
