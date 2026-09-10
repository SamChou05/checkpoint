"""Complete-choice production gate integration; model responses are fixed mocks."""

import copy
import hashlib
import json
import unittest
from unittest.mock import Mock

from complete_question_solution import COMPLETE_SOLUTION_SYSTEM_PROMPT
from lambda_test_support import (
    FakeBedrockClient,
    _complete_solution,
    _raw_question,
    _request_payload,
)
from question_generation import ProviderCallBudget, _generate_sanitized_questions
from question_verification import (
    COMPLETE_REVIEW_SYSTEM_PROMPT,
    NEGATIVE_ANSWER_GUIDANCE,
    REVIEW_SYSTEM_PROMPT,
    SOLUTION_SYSTEM_PROMPT,
    verify_questions,
)
from request_contract import _normalize_request
from verification_policy import VERIFICATION_POLICY_REVISION


def payload(prompt):
    return json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])


def solution(item, judgments=None):
    result = _complete_solution(item, item["choices"][0])
    if judgments is not None:
        for row, judgment in zip(result["choices"], judgments, strict=True):
            row["judgment"] = judgment
    return result


def approved(question, index=0, **changes):
    return {
        "index": index,
        "valid": True,
        "answer": question["expectedAnswer"],
        "difficulty": 3,
        "explanation": "The stated conditions establish the indicated result.",
        "choiceExplanations": {
            c: "The specific facts determine whether this choice answers the question."
            for c in question["choices"]
        },
        **changes,
    }


def encoded(*records):
    return json.dumps({"solutions": list(records)}, ensure_ascii=False)


class CompleteQuestionVerificationTests(unittest.TestCase):
    def setUp(self):
        self.question = _raw_question("Which conclusion follows from the given conditions?")
        self.request = _normalize_request(_request_payload(target_count=1))

    def run_complete(self, questions, solve, review, metrics=None, request=None):
        return verify_questions(
            questions, request or self.request, review, metrics,
            solve=solve, solver_contract="complete_choices",
        )

    def matching_solver(self, system, prompt):
        self.assertEqual(system, COMPLETE_SOLUTION_SYSTEM_PROMPT)
        return encoded(*[
            _complete_solution(item, self.question["expectedAnswer"])
            for item in payload(prompt)["items"]
        ])

    def test_generation_selects_complete_contract_and_current_stamp_in_three_calls(self):
        client = FakeBedrockClient.returning_questions(self.question)
        budget = ProviderCallBudget(3)
        accepted = _generate_sanitized_questions(self.request, client, budget)
        self.assertEqual(len(accepted), 1)
        self.assertEqual(budget.calls, 3)
        self.assertEqual(VERIFICATION_POLICY_REVISION, 2)
        self.assertEqual(accepted[0]["verificationVersion"], 1)
        self.assertEqual(accepted[0]["verificationPolicyRevision"], 2)
        self.assertEqual(client.solution_calls[0]["system"][0]["text"], COMPLETE_SOLUTION_SYSTEM_PROMPT)
        self.assertEqual(client.review_calls[0]["system"][0]["text"], COMPLETE_REVIEW_SYSTEM_PROMPT)
        solver_data = payload(client.solution_calls[0]["messages"][0]["content"][0]["text"])
        self.assertCountEqual(solver_data["items"][0]["choices"], self.question["choices"])

    def test_legacy_prompts_and_default_path_stay_explicitly_revision_one(self):
        for value, digest in (
            (SOLUTION_SYSTEM_PROMPT, "a951e9a6f4f9f078d0f98db47aebe77fdd8c318d9d840fc44ec8d5154b436441"),
            (REVIEW_SYSTEM_PROMPT, "c7acbe0b94e8cc9b80f78ec084ed393a3b1d2b2245f5c86cbc0b3d7416be1cb3"),
            (NEGATIVE_ANSWER_GUIDANCE, "c86475eae7c9f1fcfa54535326972f4588c7b27c1344c0bd3be440132689bf01"),
        ):
            self.assertEqual(hashlib.sha256(value.encode()).hexdigest(), digest)

        def legacy_solver(system, prompt):
            self.assertEqual(system, SOLUTION_SYSTEM_PROMPT)
            self.assertNotIn("choices", payload(prompt)["items"][0])
            return encoded({
                "index": 0, "outcome": "resolved", "answer": "A concise solution.",
                "limitations": "", "assumptionsRequired": [],
            })

        reviewer = Mock(return_value=json.dumps({"reviews": [approved(self.question)]}))
        accepted = verify_questions(
            [{**self.question, "verificationPolicyRevision": 99}],
            self.request, reviewer, solve=legacy_solver,
        )
        self.assertEqual(accepted[0]["verificationPolicyRevision"], 1)
        self.assertEqual(reviewer.call_args.args[0], REVIEW_SYSTEM_PROMPT)

    def test_missing_solver_unknown_contract_and_legacy_response_cannot_earn_two(self):
        reviewer = Mock(return_value=json.dumps({"reviews": [approved(self.question)]}))
        self.assertEqual(self.run_complete([self.question], None, reviewer), [])
        legacy = {
            "index": 0, "outcome": "resolved", "answer": self.question["expectedAnswer"],
            "limitations": "", "assumptionsRequired": [],
        }
        self.assertEqual(
            self.run_complete([self.question], lambda *_: encoded(legacy), reviewer), []
        )
        reviewer.assert_not_called()
        for contract in ("unknown", True, None):
            with self.assertRaises(ValueError):
                verify_questions([self.question], self.request, reviewer, solver_contract=contract)
        reviewer.assert_not_called()

    def test_solver_input_excludes_structured_keys_feedback_difficulty_and_history(self):
        question = {
            **self.question,
            "explanation": "PRIVATE AUTHOR FEEDBACK",
            "choiceExplanations": {"irrelevant": "PRIVATE CHOICE FEEDBACK"},
            "verificationPolicyRevision": 99,
        }
        request = copy.deepcopy(self.request)
        request["existingQuestionCoverage"] = [{"expectedAnswer": "PRIVATE HISTORY"}]
        request["goal"]["expectedAnswer"] = "PRIVATE NESTED KEY"
        original = copy.deepcopy((question, request))

        def solver(system, prompt):
            self.assertNotIn("PRIVATE", prompt)
            self.assertEqual(system, COMPLETE_SOLUTION_SYSTEM_PROMPT)
            data = payload(prompt)
            self.assertNotIn("existingQuestions", data)
            for field in ("expectedAnswer", "explanation", "choiceExplanations", "difficulty", "verificationPolicyRevision"):
                self.assertNotIn(field, data["items"][0])
            return encoded(_complete_solution(data["items"][0], question["expectedAnswer"]))

        def reviewer(system, prompt):
            self.assertEqual(system, COMPLETE_REVIEW_SYSTEM_PROMPT)
            item = payload(prompt)["items"][0]
            self.assertEqual(set(item), {"index", "prompt", "choices", "skillID", "objectiveID", "topic"})
            return json.dumps({"reviews": [approved(question)]})

        accepted = self.run_complete([question], solver, reviewer, request=request)
        self.assertEqual(accepted[0]["verificationPolicyRevision"], 2)
        self.assertEqual((question, request), original)

    def test_all_declared_vetoes_prevent_an_approving_reviewer_from_running(self):
        for state, expected in (
            ("zero", "solver_zero_supported"),
            ("multiple", "solver_multiple_supported"),
            ("uncertain", "solver_uncertain"),
            ("different", "answer_disagreement"),
        ):
            with self.subTest(state=state):
                def solver(_system, prompt):
                    item = payload(prompt)["items"][0]
                    result = _complete_solution(item, self.question["expectedAnswer"])
                    if state == "zero":
                        for row in result["choices"]:
                            row["judgment"] = "refuted"
                    else:
                        wrong = next(r for r in result["choices"] if r["judgment"] == "refuted")
                        wrong["judgment"] = "uncertain" if state == "uncertain" else "supported"
                        if state == "different":
                            next(r for r in result["choices"] if r["choice"] == self.question["expectedAnswer"])["judgment"] = "refuted"
                    return encoded(result)

                reviewer = Mock(return_value=json.dumps({"reviews": [approved(self.question)]}))
                metrics = {}
                self.assertEqual(self.run_complete([self.question], solver, reviewer, metrics), [])
                reviewer.assert_not_called()
                self.assertEqual(metrics["QuestionQuality"]["review"], {expected: 1})

    def test_reordered_mixed_batch_keeps_nonadjacent_duplicate_stem_survivors_exact(self):
        first = {
            **self.question, "prompt": "Which sentence is not in the past tense?",
            "choices": ["She walks.", "She walked.", "She visited.", "She studied."],
            "expectedAnswer": "She walks.", "caseTag": "first",
        }
        last = {
            **first, "choices": ["She walked.", "She visited.", "She will walk.", "She studied."],
            "expectedAnswer": "She will walk.", "caseTag": "last",
        }
        middle = [{**first, "prompt": f"Rejected case {i}?", "caseTag": f"rejected-{i}"} for i in range(4)]
        invalid = {**first, "choices": ["x", "x", "y", "z"], "expectedAnswer": "x"}
        questions = [invalid, first, middle[0], middle[1], last, middle[2], middle[3]]
        original = copy.deepcopy(questions)
        records_by_index = {}
        offered_by_index = {}

        def solver(_system, prompt):
            items = payload(prompt)["items"]
            self.assertEqual([item["index"] for item in items], list(range(6)))
            for item in items:
                index = item["index"]
                expected = last["expectedAnswer"] if index == 3 else first["expectedAnswer"]
                result = _complete_solution(item, expected)
                if index == 1:
                    for row in result["choices"]:
                        row["judgment"] = "refuted"
                elif index in (2, 4, 5):
                    wrong = next(r for r in result["choices"] if r["judgment"] == "refuted")
                    wrong["judgment"] = "uncertain" if index == 4 else "supported"
                    if index == 5:
                        next(r for r in result["choices"] if r["choice"] == expected)["judgment"] = "refuted"
                for row in result["choices"]:
                    row["reason"] = f"  Original item {index}: {row['choice']}\n"
                records_by_index[index] = copy.deepcopy(result)
                offered_by_index[index] = copy.deepcopy(item)
            for record in records_by_index.values():
                record["choices"].reverse()
            return encoded(*reversed(list(records_by_index.values())))

        def reviewer(_system, prompt):
            data = payload(prompt)
            self.assertEqual([q["index"] for q in data["items"]], [0, 1])
            for new_index, old_index in enumerate((0, 3)):
                self.assertEqual(data["items"][new_index], {**offered_by_index[old_index], "index": new_index})
                expected_rows = {r["choice"]: r for r in records_by_index[old_index]["choices"]}
                self.assertEqual(data["independentSolutions"][new_index], {
                    "index": new_index,
                    "choices": [expected_rows[c] for c in offered_by_index[old_index]["choices"]],
                })
            return json.dumps({"reviews": [approved(last, 1), approved(first, 0)]})

        metrics = {}
        accepted = self.run_complete(questions, solver, reviewer, metrics)
        self.assertEqual([q["caseTag"] for q in accepted], ["first", "last"])
        self.assertEqual([q["expectedAnswer"] for q in accepted], [first["expectedAnswer"], last["expectedAnswer"]])
        self.assertTrue(all(q["verificationPolicyRevision"] == 2 for q in accepted))
        self.assertEqual(questions, original)
        self.assertEqual(metrics["QuestionQuality"]["review"], {
            "invalid_choices": 1, "solver_zero_supported": 1,
            "solver_multiple_supported": 1, "solver_uncertain": 1,
            "answer_disagreement": 1, "accepted": 2,
        })

    def test_malformed_partial_batch_is_not_salvaged_or_sent_to_review(self):
        questions = [self.question, {**self.question, "prompt": "A different complete question?"}]
        for mutation in ("missing", "duplicate", "extra", "boolean", "rewritten", "missing_choice", "metadata"):
            with self.subTest(mutation=mutation):
                def solver(_system, prompt):
                    records = [_complete_solution(item, self.question["expectedAnswer"]) for item in payload(prompt)["items"]]
                    if mutation == "missing":
                        records.pop()
                    elif mutation == "duplicate":
                        records[1]["index"] = 0
                    elif mutation == "extra":
                        records.append(copy.deepcopy(records[0]))
                    elif mutation == "boolean":
                        records[1]["index"] = True
                    elif mutation == "rewritten":
                        records[1]["choices"][0]["choice"] += " "
                    elif mutation == "missing_choice":
                        records[1]["choices"].pop()
                    else:
                        records[1]["verificationPolicyRevision"] = 2
                    return encoded(*records)

                reviewer = Mock()
                metrics = {}
                self.assertEqual(self.run_complete(questions, solver, reviewer, metrics), [])
                reviewer.assert_not_called()
                self.assertEqual(metrics["QuestionQuality"]["review"], {"invalid_solution": 2})

    def test_reviewer_cannot_reinsert_an_excluded_item_with_extra_or_old_indexes(self):
        second = {**self.question, "prompt": "A second complete question?"}

        def solver(_system, prompt):
            first_item, second_item = payload(prompt)["items"]
            return encoded(solution(first_item, ["refuted"] * 4), _complete_solution(second_item, second["expectedAnswer"]))

        for reviews in ([approved(self.question, 0), approved(second, 1)], [approved(second, 1)]):
            reviewer = Mock(return_value=json.dumps({"reviews": reviews}))
            self.assertEqual(self.run_complete([self.question, second], solver, reviewer), [])
            data = payload(reviewer.call_args.args[1])
            self.assertEqual([q["prompt"] for q in data["items"]], [second["prompt"]])
            self.assertEqual(data["items"][0]["index"], 0)

    def test_natural_negative_and_zero_answers_survive_only_with_matching_final_review(self):
        for stem, choices in (
            ("Which real number x satisfies x² = -1?", ["No real number satisfies it.", "0", "1", "-1"]),
            ("A pump fills 10 L at an unspecified constant rate. How many minutes are needed?", ["The rate is needed to determine the duration.", "1", "5", "10"]),
            ("How many integers are strictly between 2 and 3?", ["0", "1", "2", "3"]),
        ):
            question = {**self.question, "prompt": stem, "choices": choices, "expectedAnswer": choices[0]}
            def solver(_system, prompt):
                return encoded(_complete_solution(payload(prompt)["items"][0], choices[0]))
            for valid in (True, False):
                accepted = self.run_complete(
                    [question], solver,
                    lambda *_: json.dumps({"reviews": [approved(question, valid=valid)]}),
                )
                self.assertEqual(len(accepted), int(valid))
                if accepted:
                    self.assertEqual(accepted[0]["expectedAnswer"], choices[0])

    def test_complete_path_still_requires_final_key_difficulty_and_all_feedback(self):
        changes = [
            {"valid": False}, {"answer": self.question["choices"][1]},
            {"difficulty": True}, {"difficulty": 1}, {"choiceExplanations": {}},
            {"explanation": "x" * 421}, {"explanation": "Answer A supplies the result."},
            {"choiceExplanations": {c: "x" * 281 for c in self.question["choices"]}},
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assertEqual(self.run_complete(
                    [self.question], self.matching_solver,
                    lambda *_: json.dumps({"reviews": [approved(self.question, **change)]}),
                ), [])

    def test_only_complete_success_overwrites_authored_policy_with_revision_two(self):
        for forged in (None, True, 1, 2, 99, "2"):
            question = {**self.question, "verificationPolicyRevision": forged}
            accepted = self.run_complete(
                [question], self.matching_solver,
                lambda *_: json.dumps({"reviews": [approved(question)]}),
            )
            self.assertEqual(accepted[0]["verificationVersion"], 1)
            self.assertIs(type(accepted[0]["verificationPolicyRevision"]), int)
            self.assertEqual(accepted[0]["verificationPolicyRevision"], 2)
            self.assertEqual(question["verificationPolicyRevision"], forged)

    def test_confident_wrong_judgments_and_approving_review_remain_a_semantic_limit(self):
        question = {
            **self.question, "prompt": "What is 2 + 2?", "choices": ["5", "4", "3", "2"],
            "expectedAnswer": "5",
        }
        def solver(_system, prompt):
            result = _complete_solution(payload(prompt)["items"][0], "5")
            next(r for r in result["choices"] if r["choice"] == "5")["reason"] = "The sum is 4, so the offered 5 cannot answer the question."
            return encoded(result)
        accepted = self.run_complete(
            [question], solver,
            lambda *_: json.dumps({"reviews": [approved(question)]}),
        )
        # A policy revision records the executed path, not arithmetic truth or
        # semantic consistency of a fallible model's declared labels and prose.
        self.assertEqual(accepted[0]["expectedAnswer"], "5")
        self.assertEqual(accepted[0]["verificationPolicyRevision"], 2)


if __name__ == "__main__":
    unittest.main()
