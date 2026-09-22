"""Pair declarations add a veto; they cannot waive correctness or rewrite keys."""

import copy
import itertools
import json
import unittest

from lambda_test_support import _complete_solution, _raw_question
from question_verification import verify_questions


def data(prompt):
    return json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])


class ChoicePairAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.questions = [
            _raw_question(f"Which conclusion follows from the stated conditions in case {index}?")
            for index in range(4)
        ]
        self.answers = {q["prompt"]: q["expectedAnswer"] for q in self.questions}
        self.metrics = {}
        self.review_inputs = []
        self.solver_inputs = []

    def solver(self, system, prompt, *, relations=None, mutate=None):
        payload = data(prompt)
        self.solver_inputs.append((system, copy.deepcopy(payload)))
        records = []
        for item in payload["items"]:
            record = _complete_solution(item, self.answers[item["prompt"]])
            record["choicePairs"] = [
                {"leftChoice": left, "rightChoice": right,
                 "relation": (relations or {}).get(item["index"], "distinct")
                 if position == 0 else "distinct", "reason": "Explicit fixture comparison."}
                for position, (left, right) in enumerate(itertools.combinations(item["choices"], 2))
            ]
            records.append(record)
        if mutate:
            mutate(records)
        return json.dumps({"solutions": records})

    def reviewer(self, _system, prompt):
        payload = data(prompt)
        self.review_inputs.append(copy.deepcopy(payload))
        return json.dumps({"reviews": [
            {"index": item["index"], "valid": True, "answer": self.answers[item["prompt"]],
             "difficulty": 3, "explanation": "The stated conditions support this exact answer.",
             "choiceExplanations": {choice: "A concise explanation of this offered choice."
                                    for choice in item["choices"]}}
            for item in payload["items"]
        ]})

    def slot_solver(self, system, prompt, *, mutate=None):
        payload = data(prompt)
        self.solver_inputs.append((system, copy.deepcopy(payload)))
        solutions = []
        for item in payload["items"]:
            row = {
                "index": item["index"],
                "choices": {
                    slot: {"reason": "Explicit fixture support or refutation.",
                           "judgment": "supported" if choice == self.answers[item["prompt"]] else "refuted"}
                    for slot, choice in item["choices"].items()
                },
                "choicePairs": {
                    pair: {"reason": "Different proposed answers in this fixture.", "relation": "distinct"}
                    for pair in ("ab", "ac", "ad", "bc", "bd", "cd")
                },
            }
            solutions.append(row)
        if mutate:
            mutate(solutions)
        return json.dumps({"solutions": solutions})

    def run_gate(self, solve=None, **options):
        return verify_questions(
            self.questions, {"minimumDifficulty": 1}, self.reviewer, self.metrics,
            solve=solve or self.solver, solver_contract="complete_choices",
            audit_choice_pairs=True, preserve_reviewed_text=True, **options,
        )

    def test_equivalence_and_uncertainty_veto_before_review_with_dense_survivor_indexes(self):
        accepted = self.run_gate(lambda system, prompt: self.solver(
            system, prompt, relations={1: "equivalent", 2: "uncertain"},
        ))
        self.assertEqual([q["prompt"] for q in accepted],
                         [self.questions[0]["prompt"], self.questions[3]["prompt"]])
        reviewed = self.review_inputs[0]
        self.assertEqual([item["index"] for item in reviewed["items"]], [0, 1])
        self.assertEqual([item["index"] for item in reviewed["independentSolutions"]], [0, 1])
        self.assertTrue(all(set(item) == {"index", "choices"}
                            for item in reviewed["independentSolutions"]))
        self.assertEqual(self.metrics["QuestionQuality"]["review"]["solver_equivalent_choices"], 1)
        self.assertEqual(self.metrics["QuestionQuality"]["review"]["solver_pair_uncertain"], 1)
        # This still satisfies baseline complete-choice policy. It must never
        # claim the unrelated authored-teaching policy by incrementing a number.
        self.assertEqual([q["verificationPolicyRevision"] for q in accepted], [2, 2])
        for question in accepted:
            self.assertEqual(question["expectedAnswer"], self.answers[question["prompt"]])
            self.assertNotIn("choicePairs", question)

    def test_all_equivalent_or_uncertain_questions_never_reach_reviewer(self):
        for relation in ("equivalent", "uncertain"):
            with self.subTest(relation=relation):
                self.review_inputs.clear()
                accepted = self.run_gate(lambda system, prompt: self.solver(
                    system, prompt, relations=dict.fromkeys(range(4), relation),
                ))
                self.assertEqual(accepted, [])
                self.assertEqual(self.review_inputs, [])

    def test_malformed_pair_coverage_invalidates_batch_without_review_or_veto_credit(self):
        mutations = (
            lambda rows: rows[0].pop("choicePairs"),
            lambda rows: rows[0]["choicePairs"].pop(),
            lambda rows: rows[0]["choicePairs"].__setitem__(1, rows[0]["choicePairs"][0]),
            lambda rows: rows[0]["choicePairs"][0].update(leftChoice="not an offered choice"),
        )
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                self.metrics.clear()
                self.review_inputs.clear()
                self.assertEqual(self.run_gate(lambda system, prompt: self.solver(
                    system, prompt, mutate=mutate,
                )), [])
                self.assertEqual(self.review_inputs, [])
                self.assertEqual(self.metrics["QuestionQuality"]["review"], {"invalid_solution": 4})

    def test_original_choice_correctness_veto_takes_precedence_over_pair_veto(self):
        def multiple(rows):
            for row in rows:
                for choice in row["choices"]:
                    choice["judgment"] = "supported"

        self.assertEqual(self.run_gate(lambda system, prompt: self.solver(
            system, prompt, relations=dict.fromkeys(range(4), "equivalent"), mutate=multiple,
        )), [])
        self.assertEqual(self.review_inputs, [])
        self.assertEqual(self.metrics["QuestionQuality"]["review"], {"solver_multiple_supported": 4})

    def test_pair_solver_stays_answer_and_feedback_blind(self):
        before = copy.deepcopy(self.questions)
        self.run_gate()
        _system, payload = self.solver_inputs[0]
        for item in payload["items"]:
            self.assertNotIn("expectedAnswer", item)
            self.assertNotIn("explanation", item)
            self.assertNotIn("choiceExplanations", item)
        self.assertEqual(self.questions, before)

    def test_fixed_slots_earn_distinct_choice_policy_only_after_final_review(self):
        accepted = self.run_gate(self.slot_solver, choice_slots=True)
        self.assertEqual(len(accepted), 4)
        self.assertEqual([q["verificationPolicyRevision"] for q in accepted], [4] * 4)
        self.assertTrue(all(q["expectedAnswer"] == self.answers[q["prompt"]] for q in accepted))
        self.assertTrue(all(set(row) == {"index", "choices"}
                            for row in self.review_inputs[0]["independentSolutions"]))

    def test_fixed_slot_vetoes_and_malformed_shape_cannot_acquire_policy_stamp(self):
        for mutate, reason in (
            (lambda rows: rows[0]["choicePairs"]["ab"].update(relation="equivalent"), "solver_equivalent_choices"),
            (lambda rows: rows[0]["choices"]["a"].update(judgment="uncertain"), "solver_uncertain"),
            (lambda rows: rows[0]["choicePairs"].pop("cd"), "invalid_solution"),
        ):
            with self.subTest(reason=reason):
                self.metrics.clear()
                self.review_inputs.clear()
                accepted = self.run_gate(lambda system, prompt: self.slot_solver(
                    system, prompt, mutate=mutate,
                ), choice_slots=True)
                self.assertEqual(len(accepted), 0 if reason == "invalid_solution" else 3)
                self.assertIn(reason, self.metrics["QuestionQuality"]["review"])

    def test_slot_input_does_not_reveal_sanitizer_key_first_order(self):
        self.run_gate(self.slot_solver, choice_slots=True)
        original = self.solver_inputs[-1]
        for question in self.questions:
            question["expectedAnswer"] = next(c for c in question["choices"] if c != question["expectedAnswer"])
            question["choices"] = [question["expectedAnswer"]] + [
                c for c in reversed(question["choices"]) if c != question["expectedAnswer"]
            ]
        self.assertEqual(self.run_gate(self.slot_solver, choice_slots=True), [])
        self.assertEqual(self.solver_inputs[-1], original)
        self.assertEqual(self.metrics["QuestionQuality"]["review"]["answer_disagreement"], 4)

    def test_slots_cannot_claim_the_policy_without_pair_audit(self):
        with self.assertRaises(ValueError):
            verify_questions(self.questions, {}, self.reviewer, solve=self.slot_solver,
                             solver_contract="complete_choices", choice_slots=True)

    def test_pair_audit_cannot_claim_unexecuted_or_incompatible_verification(self):
        variants = (
            {"solver_contract": "stem_only", "solve": self.solver},
            {"solver_contract": "complete_choices", "solve": None},
            {"solver_contract": "complete_choices", "solve": self.solver,
             "feedback_contract": "authored_solution"},
        )
        for options in variants:
            with self.subTest(options=options), self.assertRaises(ValueError):
                verify_questions(self.questions, {}, self.reviewer,
                                 audit_choice_pairs=True, **options)

    def test_default_v1_input_and_decisions_remain_unchanged(self):
        def v1_solver(system, prompt):
            payload = json.loads(self.solver(system, prompt))
            for row in payload["solutions"]:
                del row["choicePairs"]
            return json.dumps(payload)

        accepted = verify_questions(
            self.questions, {"minimumDifficulty": 1}, self.reviewer,
            solve=v1_solver, solver_contract="complete_choices",
        )
        self.assertEqual(len(accepted), 4)
        self.assertTrue(all(set(item) == {"index", "choices"}
                            for item in self.review_inputs[0]["independentSolutions"]))


if __name__ == "__main__":
    unittest.main()
