"""Literal goal text survives real orchestration and both provider transports."""

import copy
import json
import os
import socket
import unittest
from unittest.mock import patch

import boto3
import question_generation as generation
import skill_maps
from lambda_test_support import _complete_solution, _raw_question, _request_payload
from request_contract import (
    _normalize_request,
    _normalize_skill_map_evolution_request,
    _normalize_skill_map_inference_request,
)
from test_lambda_skill_map_evolution import (
    _current_skill_map,
    _evolution_payload,
    _provider_response,
)


MODEL = "us.anthropic.claude-sonnet-4-6"
RAW_GOAL_TEXT = {
    "title": "\r\nDistinguish 'a  b'\r\nfrom 'a b'.\x00\r\n",
    "focusAreas": "\r\n    def f(x):\r\n\treturn x  + 1\x00\r\n\r\n",
    "learningTarget": "\rCompare 'a  b' with 'a b'.\rC++ != C#; cafe\u0301.\r",
    "questionDirective": "\nKeep columns:\nA\tB\n1\t2\x07\n\nTwo  spaces.\n",
    "currentLevel": "\r\nI can trace:\r\n    print('a  b')\x00\r\n",
    "contentTopics": ["'a  b'", "'a b'", "C++ != C#"],
}
EXPECTED_GOAL_TEXT = {
    "title": "Distinguish 'a  b'\nfrom 'a b'. ",
    "focusAreas": "    def f(x):\n\treturn x  + 1 ",
    "learningTarget": "Compare 'a  b' with 'a b'.\nC++ != C#; cafe\u0301.",
    "questionDirective": "Keep columns:\nA\tB\n1\t2 \n\nTwo  spaces.",
    "currentLevel": "I can trace:\n    print('a  b') ",
    "contentTopics": ["'a  b'", "'a b'", "C++ != C#"],
}


class _ScriptedClient:
    def __init__(self, check_request, steps):
        self.check_request = check_request
        self.steps = list(steps)
        self.calls = []

    def converse(self, **request):
        if not self.steps:
            raise AssertionError("Unexpected provider attempt")
        tag, contract, response = self.steps.pop(0)
        data = self.check_request(request, tag, contract)
        self.calls.append(copy.deepcopy(request))
        if callable(response):
            response = response(data)
        return {
            "stopReason": "end_turn",
            "output": {"message": {"content": [{
                "text": response if isinstance(response, str)
                else json.dumps(response, ensure_ascii=False),
            }]}},
            "usage": {"inputTokens": 11, "outputTokens": 7},
        }


class GoalContextProviderBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_MODEL_ID": MODEL,
            "BEDROCK_VERIFICATION_MODEL_ID": MODEL,
            "BEDROCK_FALLBACK_MODEL_ID": "",
            "SKILL_MAP_MODEL_ID": MODEL,
            "BEDROCK_CLAUDE_THINKING": "disabled",
            "QUESTION_FEEDBACK_CONTRACT": "reviewer_written",
            "GENERATION_ATTEMPTS": "1",
        }))
        for target in (socket.socket, boto3, boto3.session.Session):
            method = "connect" if target is socket.socket else "client"
            self.enterContext(patch.object(
                target, method, side_effect=AssertionError("Network/SDK clients forbidden"),
            ))

    def check_request(self, request, tag, contract):
        self.assertEqual(request["modelId"], MODEL)
        if self.mode == "native":
            self.assertEqual(
                request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"],
                contract,
            )
        else:
            self.assertNotIn("outputConfig", request)
        text = request["messages"][0]["content"][0]["text"]
        data = json.loads(text.split(f"<{tag}>\n", 1)[1].split(f"\n</{tag}>", 1)[0])
        for field, expected in EXPECTED_GOAL_TEXT.items():
            self.assertEqual(data["goal"][field], expected, (tag, self.mode, field))
        if tag == "generation_request_json" and "<malformed_response_excerpt>" not in text:
            self.assertIn("Current learner level: " + EXPECTED_GOAL_TEXT["currentLevel"], text)
        return data

    def test_generation_preserves_goal_through_author_repair_solver_and_review(self):
        for mode in ("legacy", "native"):
            with self.subTest(mode=mode), patch.dict(
                os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": mode},
            ):
                self.mode = mode
                payload = _request_payload(target_count=1)
                payload["goal"].update(RAW_GOAL_TEXT)
                original = copy.deepcopy(payload)
                request = _normalize_request(payload)
                question = _raw_question("Which conclusion follows from the stated conditions?")

                def solve(data):
                    return {"solutions": [
                        _complete_solution(item, question["expectedAnswer"])
                        for item in data["items"]
                    ]}

                def review(data):
                    item = data["items"][0]
                    feedback = {
                        choice: "The stated conditions determine whether this answer follows."
                        for choice in item["choices"]
                    }
                    result = {
                        "index": item["index"], "valid": True,
                        "answer": question["expectedAnswer"], "difficulty": 3,
                        "explanation": "The stated conditions establish the indicated conclusion.",
                    }
                    if mode == "native":
                        result["choiceFeedback"] = [
                            {"choice": choice, "explanation": value}
                            for choice, value in feedback.items()
                        ]
                    else:
                        result["choiceExplanations"] = feedback
                    return {"reviews": [result]}

                steps = []
                if mode == "legacy":
                    # Native malformed JSON fails adaptation before this repair branch.
                    steps.append(("generation_request_json", "question_author_v1", "not JSON"))
                steps.extend([
                    ("generation_request_json", "question_author_v1", {"questions": [question]}),
                    ("question_solution_json", "complete_choice_solver_v1", solve),
                    ("question_review_json", "default_reviewer_v1", review),
                ])
                client = _ScriptedClient(self.check_request, steps)
                result = generation._generate_sanitized_questions(
                    request, client, generation.ProviderCallBudget(len(steps)),
                )
                self.assertEqual(len(result), 1)
                self.assertEqual(result[0]["expectedAnswer"], question["expectedAnswer"])
                self.assertEqual(len(client.calls), 4 if mode == "legacy" else 3)
                self.assertFalse(client.steps)
                self.assertEqual(payload, original)

    def test_skill_inference_and_retry_preserve_normalized_goal(self):
        for mode in ("legacy", "native"):
            with self.subTest(mode=mode), patch.dict(
                os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": mode},
            ):
                self.mode = mode
                payload = {"goal": {"title": "Interpret literal content", **RAW_GOAL_TEXT}}
                original = copy.deepcopy(payload)
                request = _normalize_skill_map_inference_request(payload)
                response = {"skills": [
                    {"name": skill["name"], "objectives": [
                        {"name": objective["name"]} for objective in skill["objectives"]
                    ]} for skill in _current_skill_map()["skills"]
                ]}
                client = _ScriptedClient(self.check_request, [
                    ("skill_map_request_json", "skill_map_inference_v1", {"skills": []}),
                    ("skill_map_request_json", "skill_map_inference_v1", response),
                ])
                result = skill_maps._infer_skill_map(
                    request, client, call_budget=generation.ProviderCallBudget(2),
                )
                self.assertEqual(len(result["skills"]), len(response["skills"]))
                self.assertEqual(len(client.calls), 2)
                self.assertFalse(client.steps)
                self.assertEqual(payload, original)

    def test_skill_evolution_and_retry_preserve_normalized_goal(self):
        for mode in ("legacy", "native"):
            with self.subTest(mode=mode), patch.dict(
                os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": mode},
            ):
                self.mode = mode
                payload = _evolution_payload()
                payload["goal"].update(RAW_GOAL_TEXT)
                original = copy.deepcopy(payload)
                request = _normalize_skill_map_evolution_request(payload)
                client = _ScriptedClient(self.check_request, [
                    ("skill_map_evolution_request_json", "skill_map_evolution_v1", {"changes": []}),
                    ("skill_map_evolution_request_json", "skill_map_evolution_v1",
                     _provider_response(request["masteredSkillIDs"])),
                ])
                result = skill_maps._evolve_skill_map(
                    request, client, call_budget=generation.ProviderCallBudget(2),
                )
                self.assertTrue(result["replacements"])
                self.assertEqual(result["skillMap"]["version"], payload["currentSkillMap"]["version"] + 1)
                self.assertEqual(len(client.calls), 2)
                self.assertFalse(client.steps)
                self.assertEqual(payload, original)
