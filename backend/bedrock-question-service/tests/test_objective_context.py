"""Checking stages retain objective scope; scripted replies do not prove accuracy."""

import copy
import json
import os
import socket
import unittest
from unittest.mock import patch

import boto3
import question_generation as generation
from complete_question_solution import (
    CompleteSolutionFormatError,
    build_solver_prompt,
)
from question_quality import _sanitize_questions
from question_verification import verify_questions
from request_contract import _normalize_request


MODEL = "us.anthropic.claude-sonnet-4-6"
SKILL_ID = "11111111-1111-4111-8111-111111111111"
OBJECTIVE_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
OBJECTIVE = "Apply a universal rule"


def request(*, mapped=False, count=1):
    return _normalize_request({
        "goal": {"title": "Interpret logical implications", "contentTopics": ["Reasoning"]},
        "skillMap": {"version": 1, "skills": [{
            "id": SKILL_ID, "name": "Reasoning",
            "objectives": [{"id": OBJECTIVE_ID, "name": OBJECTIVE}] if mapped else [],
        }]},
        "targetCount": count,
        "minimumDifficulty": 3,
    })


def question(color="red", property_name="round", objective=OBJECTIVE):
    answer = f"This token is {property_name}."
    return {
        "prompt": f"All {color} tokens are {property_name}. This token is {color}. Which statement follows?",
        "choices": [answer, f"No {color} token is {property_name}.",
                    f"Every {property_name} object is a {color} token.",
                    f"This token is not {color}."],
        "expectedAnswer": answer,
        "explanation": f"The stated rule applies to every {color} token, including this one, so it is {property_name}.",
        "topic": "Reasoning", "skillID": SKILL_ID, "objective": objective,
        "difficulty": 3, "format": "Multiple Choice",
    }


def payload(text, tag):
    return json.loads(text.split(f"<{tag}>\n", 1)[1].split(f"\n</{tag}>", 1)[0])


def solutions(items, answers, *, reject_first=False):
    return {"solutions": [{
        "index": item["index"],
        "choices": [{
            "choice": choice,
            "judgment": "supported" if choice == answers[item["prompt"]]
            and not (reject_first and item["index"] == 0) else "refuted",
            "reason": "Scripted declaration for checking payload correlation.",
        } for choice in item["choices"]],
    } for item in items]}


def reviews(items, answers, *, authored=False, native=False):
    records = []
    for item in items:
        record = {"index": item["index"], "valid": True,
                  "answer": answers[item["prompt"]], "difficulty": 3}
        if authored:
            record.update(explanationSupport="supported", issues=[])
        else:
            record["explanation"] = "The given universal rule applies to this token."
            feedback = {choice: "Compare this claim with the given implication and token." for choice in item["choices"]}
            if native:
                record["choiceFeedback"] = [{"choice": c, "explanation": e} for c, e in feedback.items()]
            else:
                record["choiceExplanations"] = feedback
        records.append(record)
    return {"reviews": records}


class ObjectiveContextTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_MODEL_ID": MODEL, "BEDROCK_VERIFICATION_MODEL_ID": MODEL,
            "BEDROCK_FALLBACK_MODEL_ID": "", "BEDROCK_CLAUDE_THINKING": "disabled",
            "GENERATION_ATTEMPTS": "1",
        }))
        for target, method in ((socket.socket, "connect"), (boto3, "client"),
                               (boto3.session.Session, "client")):
            self.enterContext(patch.object(target, method, side_effect=AssertionError("No network or SDK clients")))

    def test_normalized_and_sanitized_objectives_reach_actual_provider_transports(self):
        for mapped in (False, True):
            for mode in ("legacy", "native"):
                for authored in (False, True):
                    with self.subTest(mapped=mapped, mode=mode, authored=authored), patch.dict(os.environ, {
                        "BEDROCK_STRUCTURED_OUTPUT_MODE": mode,
                        "QUESTION_FEEDBACK_CONTRACT": "authored_solution" if authored else "reviewer_written",
                    }):
                        normalized, raw = request(mapped=mapped), question()
                        before = copy.deepcopy((normalized, raw))
                        candidate = _sanitize_questions([raw], normalized)[0]
                        self.assertEqual(candidate["objective"], OBJECTIVE)
                        self.assertIn("objectiveID", candidate)
                        self.assertNotIn("objectiveID", raw)
                        if mapped:
                            self.assertEqual(candidate["objectiveID"], normalized["skillMap"]["skills"][0]["objectives"][0]["id"])
                        else:
                            self.assertEqual(normalized["skillMap"]["skills"][0]["objectives"], [])
                        answers = {raw["prompt"]: raw["expectedAnswer"]}
                        observed = []
                        test = self

                        class Client:
                            def converse(self, **provider_request):
                                text = provider_request["messages"][0]["content"][0]["text"]
                                if "<generation_request_json>\n" in text:
                                    tag, contract = "generation_request_json", "question_author_v1"
                                    response = {"questions": [raw]}
                                elif "<question_solution_json>\n" in text:
                                    tag, contract = "question_solution_json", "complete_choice_solver_v1"
                                    data = payload(text, tag)
                                    response = solutions(data["items"], answers)
                                    test.assertNotIn("existingQuestions", data)
                                    test.assertNotIn("independentSolutions", data)
                                else:
                                    tag = "question_review_json"
                                    contract = "authored_solution_reviewer_v1" if authored else "default_reviewer_v1"
                                    data = payload(text, tag)
                                    response = reviews(data["items"], answers, authored=authored, native=mode == "native")
                                    test.assertEqual("independentSolutions" in data, not authored)
                                if tag != "generation_request_json":
                                    item = data["items"][0]
                                    for field in ("objective", "objectiveID", "skillID", "topic"):
                                        test.assertEqual(item[field], candidate[field])
                                    for hidden in ("expectedAnswer", "difficulty", "choiceExplanations", "verificationVersion"):
                                        test.assertNotIn(hidden, item)
                                    test.assertEqual("explanation" in item, authored and tag == "question_review_json")
                                    if "explanation" in item:
                                        test.assertEqual(item["explanation"], raw["explanation"])
                                if mode == "native":
                                    test.assertEqual(provider_request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"], contract)
                                else:
                                    test.assertNotIn("outputConfig", provider_request)
                                observed.append(tag)
                                return {"stopReason": "end_turn", "usage": {"inputTokens": 11, "outputTokens": 7},
                                        "output": {"message": {"content": [{"text": json.dumps(response)}]}}}

                        accepted = generation._generate_sanitized_questions(normalized, Client(), generation.ProviderCallBudget(3))
                        self.assertEqual(observed, ["generation_request_json", "question_solution_json", "question_review_json"])
                        self.assertEqual(len(accepted), 1)
                        self.assertEqual(accepted[0]["objective"], candidate["objective"])
                        self.assertEqual(accepted[0]["objectiveID"], candidate["objectiveID"])
                        self.assertEqual((normalized, raw), before)

    def test_dense_survivors_keep_their_own_objective_in_all_verification_contracts(self):
        normalized = request(count=3)
        raw = [question(), question("blue", "square", "Apply a shape implication"),
               question("gold", "heavy", "Apply a weight implication")]
        candidates = _sanitize_questions(raw, normalized)
        self.assertEqual(len(candidates), 3)
        answers = {q["prompt"]: q["expectedAnswer"] for q in candidates}
        before = copy.deepcopy(candidates)
        for solver_contract, authored in (("stem_only", False), ("complete_choices", False),
                                          ("complete_choices", True)):
            with self.subTest(solver=solver_contract, authored=authored):
                seen = []

                def solve(system, text):
                    data = payload(text, "question_solution_json")
                    self.assertEqual([q["objective"] for q in data["items"]], [q["objective"] for q in candidates])
                    if solver_contract == "complete_choices":
                        result = solutions(data["items"], answers, reject_first=True)
                    else:
                        self.assertTrue(all("choices" not in q for q in data["items"]))
                        result = {"solutions": [{"index": q["index"], "outcome": "uncertain" if q["index"] == 0 else "resolved",
                                                  "answer": answers[q["prompt"]], "assumptionsRequired": [], "limitations": ""}
                                                 for q in data["items"]]}
                    return json.dumps(result)

                def review(system, text):
                    data = payload(text, "question_review_json")
                    seen.append(data)
                    self.assertEqual([q["index"] for q in data["items"]], [0, 1])
                    self.assertEqual([(q["prompt"], q["objective"], q["objectiveID"]) for q in data["items"]],
                                     [(q["prompt"], q["objective"], q["objectiveID"]) for q in candidates[1:]])
                    return json.dumps(reviews(data["items"], answers, authored=authored))

                accepted = verify_questions(candidates, normalized, review, solve=solve,
                                            solver_contract=solver_contract,
                                            feedback_contract="authored_solution" if authored else "reviewer_written")
                self.assertEqual(len(seen), 1)
                self.assertEqual([q["objective"] for q in accepted], [q["objective"] for q in candidates[1:]])
                self.assertEqual(candidates, before)

    def test_optional_objective_is_typed_and_preserved_without_leaking_private_metadata(self):
        item = {"index": 0, **question()}
        label = 'Distinguish "e\u0301  x" from "é x"\nwithin this scope'
        item["objective"] = label
        item["choiceExplanations"] = {c: "Private choice feedback" for c in item["choices"]}
        item["history"] = "Private history"
        _, text = build_solver_prompt([item], {"existingQuestionCoverage": [item]})
        sent = payload(text, "question_solution_json")["items"][0]
        self.assertEqual(sent["objective"].encode(), label.encode())
        for field in ("expectedAnswer", "explanation", "choiceExplanations", "difficulty", "history"):
            self.assertNotIn(field, sent)
        changed = copy.deepcopy(item)
        changed.update(expectedAnswer=item["choices"][1], explanation="Changed private feedback", difficulty=1)
        self.assertEqual(build_solver_prompt([item], {}), build_solver_prompt([changed], {}))
        without = {k: v for k, v in item.items() if k != "objective"}
        _, text = build_solver_prompt([without], {})
        self.assertNotIn("objective", payload(text, "question_solution_json")["items"][0])
        observed = []
        verify_questions([without], request(), lambda _, text: observed.append(payload(text, "question_review_json")) or '{"reviews":[{"index":0,"valid":false,"answer":""}]}')
        self.assertNotIn("objective", observed[0]["items"][0])
        for value in (None, False, 7, ["scope"], {"scope": "text"}):
            with self.subTest(value=value), self.assertRaisesRegex(CompleteSolutionFormatError, "objective"):
                build_solver_prompt([{**item, "objective": value}], {})


if __name__ == "__main__":
    unittest.main()
