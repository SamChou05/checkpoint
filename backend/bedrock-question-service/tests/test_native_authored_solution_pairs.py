"""Opt-in immutable main + current pair/identity gates; synthetic responses only."""

import copy
import hashlib
import json
import os
from typing import get_args
import unittest
from unittest.mock import Mock, patch

import native_output_contracts as native
import question_generation as generation
from lambda_test_support import _raw_question, _request_payload, _skill_map
from question_teaching import AuthoredTeachingFormatError, freeze_authored_question
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import ProviderError, ServiceConfigurationError
from test_native_pipeline import AUTHOR, MODEL, ScriptedNativeClient, author_payload, solver_map, solver_record, task_data
from verification_policy import AUTHORED_PAIR_VERIFICATION_POLICY_REVISION, VERIFICATION_POLICY_REVISION


def audit(question, **changes):
    return {"valid": True, "answer": question["expectedAnswer"], "difficulty": 3,
            "explanationSupport": "supported", "issues": [], **changes}


class NativeAuthoredSolutionPairTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "QUESTION_AUTHOR_MODE": "prose",
            "QUESTION_FEEDBACK_CONTRACT": "authored_solution", "BEDROCK_MODEL_ID": MODEL,
            "BEDROCK_VERIFICATION_MODEL_ID": MODEL, "BEDROCK_FALLBACK_MODEL_ID": "",
            "GENERATION_ATTEMPTS": "1", "BEDROCK_CLAUDE_THINKING": "disabled",
        }))
        self.questions = []
        for index in range(5):
            question = _raw_question(f"Situation {index} supplies a distinct set of stated conditions. What follows?")
            question["explanation"] = f"  Worked solution {index}: the stated rule applies.\r\nIts conditions establish this conclusion.  "
            self.questions.append(question)

    def request(self, count):
        return _normalize_request(_request_payload(target_count=count, minimum_difficulty=3))

    def client(self, questions, *, rejected=(), pair_change=None, review_change=None):
        by_prompt = {q["prompt"]: q for q in questions}

        def solve(request):
            data = task_data(request, "question_solution_json")
            self.assertEqual(len(data["items"]), len(questions))
            for item in data["items"]:
                self.assertNotIn("expectedAnswer", item)
                self.assertNotIn("difficulty", item)
                self.assertNotIn("explanation", item)
            rows = []
            for item in data["items"]:
                row = solver_record(item, by_prompt[item["prompt"]]["expectedAnswer"])
                if item["index"] in rejected:
                    for choice in row["choices"].values():
                        choice["judgment"] = "refuted"
                if pair_change:
                    pair_change(row)
                rows.append(row)
            return solver_map(*rows)

        def review(request):
            data = task_data(request, "question_review_json")
            self.assertNotIn("independentSolutions", data)
            rows = {}
            for item in data["items"]:
                original = by_prompt[item["prompt"]]
                self.assertNotIn("expectedAnswer", item)
                self.assertNotIn("difficulty", item)
                self.assertNotIn("choiceExplanations", item)
                self.assertEqual(item["explanation"].encode(), original["explanation"].encode())
                rows[str(item["index"])] = audit(original)
            response = {"reviews": rows}
            return review_change(response) if review_change else response

        count = len(questions)
        return ScriptedNativeClient(
            (AUTHOR, author_payload(*questions)),
            (native.SolverSlotContract(count).name, solve),
            (native.AuthoredSolutionReviewContract(count - len(rejected)).name, review),
        )

    def run_pipeline(self, questions=None, **kwargs):
        questions = questions or self.questions[:1]
        client = self.client(questions, **kwargs)
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        result = generation._generate_sanitized_questions(self.request(len(questions)), client, budget)
        self.assertEqual(reserve.call_count, budget.calls)
        return result, client, budget

    def test_dense_survivors_keep_the_exact_main_and_hide_teaching_from_solver(self):
        result, client, budget = self.run_pipeline(self.questions, rejected=(0, 2))
        self.assertEqual(budget.calls, 3)
        self.assertEqual([q["prompt"] for q in result], [self.questions[i]["prompt"] for i in (1, 3, 4)])
        self.assertEqual([q["explanation"].encode() for q in result], [self.questions[i]["explanation"].encode() for i in (1, 3, 4)])
        self.assertTrue(all(q["choiceExplanations"] == {} and q["verificationPolicyRevision"] == 7 for q in result))
        reviewed = task_data(client.calls[-1], "question_review_json")["items"]
        self.assertEqual([item["index"] for item in reviewed], [0, 1, 2])
        self.assertEqual(VERIFICATION_POLICY_REVISION, 4)
        self.assertEqual(AUTHORED_PAIR_VERIFICATION_POLICY_REVISION, 7)

    def test_every_equivalent_or_uncertain_pair_vetoes_before_main_audit(self):
        for pair in ("ab", "ac", "ad", "bc", "bd", "cd"):
            for relation in ("equivalent", "uncertain"):
                with self.subTest(pair=pair, relation=relation):
                    result, client, budget = self.run_pipeline(
                        pair_change=lambda row: row["choicePairs"][pair].update(relation=relation))
                    self.assertEqual(result, [])
                    self.assertEqual((len(client.calls), budget.calls), (2, 2))

    def test_scoped_context_and_keyless_history_follow_dense_survivors(self):
        raw = _request_payload(target_count=5, minimum_difficulty=3)
        raw["skillMap"] = _skill_map()
        request = _normalize_request(raw)
        skill = request["skillMap"]["skills"][0]
        objective = skill["objectives"][0]
        request["requestedSkillAllocation"] = {skill["id"]: 5}
        request["sourceDocuments"] = [{"name": "Rules", "text": "Use these explicit subject rules.", "truncated": True}]
        request["existingQuestionCoverage"] = [
            {"prompt": f"Historical question {i}.", "topic": skill["name"], "skillID": skill["id"],
             "objectiveID": objective["id"], "objective": objective["name"],
             "expectedAnswer": "HIDDEN HISTORY KEY", "explanation": "HIDDEN HISTORY TEACHING", "difficulty": 5}
            for i in range(45)
        ]
        questions = [{**q, "topic": skill["name"], "skillID": skill["id"],
                      "objectiveID": objective["id"], "objective": objective["name"]} for q in self.questions]
        original = copy.deepcopy((questions, request))
        client = self.client(questions, rejected=(0, 2))
        result = generation._generate_sanitized_questions(request, client, generation.ProviderCallBudget(3))
        self.assertEqual((questions, request), original)
        self.assertEqual(len(result), 3)
        data = task_data(client.calls[2], "question_review_json")
        for field in ("goal", "skillMap", "sourceDocuments"):
            self.assertEqual(data[field], request[field])
        allowed = {"prompt", "topic", "skillID", "objectiveID", "objective"}
        self.assertEqual(data["existingQuestions"], [
            {key: value for key, value in item.items() if key in allowed}
            for item in request["existingQuestionCoverage"][-30:]
        ])
        self.assertNotIn("HIDDEN", json.dumps(data))
        for item, original_index in zip(data["items"], (1, 3, 4), strict=True):
            for field in ("skillID", "objectiveID", "objective", "topic", "explanation", "prompt"):
                self.assertEqual(item[field], questions[original_index][field])
        self.assertIn("assigned skill", client.calls[2]["system"][0]["text"])
        self.assertIn("cosmetic repeats", client.calls[2]["system"][0]["text"])

    def test_main_audit_support_key_difficulty_issues_and_verdict_still_veto(self):
        for change in ({"valid": False}, {"answer": self.questions[0]["choices"][1]}, {"difficulty": 2},
                       {"explanationSupport": "unsupported"}, {"explanationSupport": "uncertain"},
                       {"issues": ["The explanation assumes a missing condition."]}):
            def amend(payload):
                payload["reviews"]["0"].update(change)
                return payload
            with self.subTest(change=change):
                result, _, budget = self.run_pipeline(review_change=amend)
                self.assertEqual(result, [])
                self.assertEqual(budget.calls, 3)

    def test_replacement_teaching_and_forged_provenance_fail_whole_native_audit(self):
        for field in ("explanation", "choiceExplanations", "verificationPolicyRevision"):
            def amend(payload):
                payload["reviews"]["0"][field] = "unauthorized replacement"
                return payload
            with self.subTest(field=field), self.assertRaises(ProviderError):
                self.run_pipeline(self.questions[:2], review_change=amend)

    def test_pair_mode_cannot_mint_revision_seven_without_both_count_callbacks(self):
        for solve_count, review_count in ((None, None), (Mock(), None), (None, Mock())):
            with self.assertRaises(ValueError):
                verify_questions(self.questions[:1], self.request(1), Mock(), solve=Mock(),
                                 solve_with_count=solve_count, review_with_count=review_count,
                                 solver_contract="complete_choices", feedback_contract="authored_solution",
                                 choice_slots=True, audit_choice_pairs=True)

    def test_two_native_authored_passes_share_six_reservations_without_new_teaching(self):
        first, second = self.client(self.questions[:1]), self.client(self.questions[1:2])
        first.steps.extend(second.steps)
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "2"}):
            result = generation._generate_sanitized_questions(self.request(2), first, budget)
        self.assertEqual((budget.calls, reserve.call_count), (6, 6))
        self.assertEqual([q["explanation"] for q in result], [q["explanation"] for q in self.questions[:2]])
        self.assertTrue(all(q["choiceExplanations"] == {} for q in result))

    def test_shared_position_guard_rejects_ordinals_but_keeps_bound_literals_and_values(self):
        for text in ("Only the first choice follows from the supplied rule.",
                     "The option 2 follows from the stated conditions.",
                     'The phrase "first choice" names the correct display position.'):
            with self.subTest(text=text), self.assertRaises(AuthoredTeachingFormatError):
                freeze_authored_question({**self.questions[0], "explanation": text})
        for text in ("The answer -1 follows from subtracting the supplied integers.",
                     "The answer 1/2 follows from halving the supplied value.",
                     "The answer 2% follows from the supplied probability."):
            self.assertEqual(freeze_authored_question({**self.questions[0], "explanation": text})["explanation"], text)
        literal = {**self.questions[0], "prompt": 'Which quoted phrase matches "first choice" exactly?',
                   "choices": ["first choice", "second task", "final step", "earlier event"], "expectedAnswer": "first choice",
                   "explanation": 'The phrase "first choice" exactly matches the quoted source text.'}
        self.assertEqual(freeze_authored_question(literal), literal)

    def test_all_count_schemas_expand_exactly_with_strict_trusted_keys(self):
        for count in range(1, 41):
            contract = native.AuthoredSolutionReviewContract(count)
            config = native.native_output_config(contract)
            schema = json.loads(config["textFormat"]["structure"]["jsonSchema"]["schema"])
            def expand(value):
                if isinstance(value, list):
                    return [expand(child) for child in value]
                if not isinstance(value, dict):
                    return value
                if "$ref" in value:
                    self.assertEqual(set(value), {"$ref"})
                    return expand(schema["$defs"][value["$ref"].removeprefix("#/$defs/")])
                return {key: expand(child) for key, child in value.items() if key != "$defs"}
            self.assertEqual(expand(schema), native._contract_schema(contract))
            rows = {str(index): audit(self.questions[0]) for index in reversed(range(count))}
            decoded = json.loads(native.adapt_native_response(json.dumps({"reviews": rows}), contract))
            self.assertEqual([row["index"] for row in decoded["reviews"]], list(range(count)))
            self.assertEqual(native.contract_metadata(contract)["version"], "2")
            for changed in ({**rows, str(count): audit(self.questions[0])}, {k: v for k, v in rows.items() if k != "0"}):
                with self.assertRaises(ProviderError):
                    native.adapt_native_response(json.dumps({"reviews": changed}), contract)
        for count in (0, 41, -1, True, 1.0, "1", None):
            with self.assertRaises(ServiceConfigurationError):
                native.AuthoredSolutionReviewContract(count)

    def test_new_native_audit_rejects_duplicates_types_and_foreign_fields(self):
        contract = native.AuthoredSolutionReviewContract(1)
        valid = {"reviews": {"0": audit(self.questions[0])}}
        encoded = json.dumps(valid)
        for raw in (encoded.replace('"0":', '"0":{},"0":', 1), encoded.replace('true', '1', 1),
                    encoded.replace('"difficulty": 3', '"difficulty": true'),
                    encoded.replace('"supported"', '"maybe"'), encoded.replace('"issues": []', '"issues": [NaN]')):
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                native.adapt_native_response(raw, contract)
        extra = copy.deepcopy(valid)
        extra["reviews"]["0"]["index"] = 0
        with self.assertRaises(ProviderError):
            native.adapt_native_response(json.dumps(extra), contract)

    def test_all_historical_native_schemas_metadata_and_prompt_overrides_are_unchanged(self):
        # Digest from cea3570, before this opt-in route changed. Includes every
        # static contract and all forty existing solver/reviewer cardinalities.
        contracts = (*get_args(native.Contract), *(native.SolverSlotContract(n) for n in range(1, 41)),
                     *(native.ReviewerSlotContract(n) for n in range(1, 41)))
        values = [{"config": native.native_output_config(c), "metadata": native.contract_metadata(c),
                   "prompt": native.native_prompt("UNCHANGED SYSTEM", c)} for c in contracts]
        digest = hashlib.sha256(json.dumps(values, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        self.assertEqual(digest, "dc2b600ef9205b221479080c1d036068feebf4591f7dd660d54b18486e0f40a4")


if __name__ == "__main__":
    unittest.main()
