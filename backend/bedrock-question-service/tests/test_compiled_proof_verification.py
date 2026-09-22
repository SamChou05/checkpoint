"""Only private mathematical proof skips solving; final review remains mandatory."""

import copy
from dataclasses import replace
import itertools
import json
import unittest
from unittest.mock import Mock

import native_output_contracts as native
from lambda_test_support import _raw_question, _request_payload, _skill_map
from quantitative_authoring import LEARNER_FIELDS, QuantitativeAuthoringError, prepare_mixed_rows
from question_quality import _sanitize_questions
from question_teaching import AuthoredTeachingFormatError
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import DurableProviderCallBudgetExceededError, ProviderError, ServiceConfigurationError
from test_native_pipeline import authored_issue_flags, solver_map, solver_record
from test_quantitative_authoring import exact_task, quantitative_row
from verification_policy import COMPILED_PROOF_VERIFICATION_POLICY_REVISION, VERIFICATION_POLICY_REVISION


def unpack(prompt, tag):
    return json.loads(prompt.split(f"<{tag}>\n", 1)[1].split(f"\n</{tag}>", 1)[0])


def learner(question):
    return {key: question[key] for key in LEARNER_FIELDS}


class CompiledProofVerificationTests(unittest.TestCase):
    def setUp(self):
        self.request = _normalize_request(_request_payload(target_count=5, minimum_difficulty=2))
        self.compiled, self.sidecars, _ = prepare_mixed_rows({"questions": [
            quantitative_row(exact_task(str(value), tuple(str(n) for n in (value * 2, value * 2 + 1, value * 2 + 2, value * 2 + 3))))
            for value in range(2, 7)
        ]})
        self.prose = [_raw_question(f"Situation {i} supplies distinct stated premises. Which conclusion follows?") for i in range(3)]
        self.calls = []

    def run_verify(self, questions, sidecars, *, reject=(), solve_result=None, audit_hook=None, request=None):
        originals = {question["prompt"]: question for question in questions}

        def solve(_system, prompt, count):
            data = unpack(prompt, "question_solution_json")
            self.calls.append(("solver", count, copy.deepcopy(data)))
            self.assertEqual([item["index"] for item in data["items"]], list(range(count)))
            if isinstance(solve_result, Exception):
                raise solve_result
            if solve_result is not None:
                return solve_result
            records = []
            for item in data["items"]:
                row = solver_record(item, originals[item["prompt"]]["expectedAnswer"])
                if item["index"] in reject:
                    for choice in row["choices"].values():
                        choice["judgment"] = "refuted"
                records.append(row)
            # Object insertion order is not identity.
            return native.adapt_native_response(json.dumps(solver_map(*reversed(records))), native.SolverSlotContract(count))

        def audit(_system, prompt, count):
            data = unpack(prompt, "question_review_json")
            self.calls.append(("audit", count, copy.deepcopy(data)))
            self.assertEqual([item["index"] for item in data["items"]], list(range(count)))
            self.assertNotIn("independentSolutions", data)
            for item in data["items"]:
                for hidden in ("expectedAnswer", "difficulty", "choiceExplanations", "spec_json", "learner_json"):
                    self.assertNotIn(hidden, item)
            rows = {str(item["index"]): {
                "valid": True, "answer": originals[item["prompt"]]["expectedAnswer"], "difficulty": 2,
                "explanationSupport": "supported", "issueFlags": authored_issue_flags(),
            } for item in reversed(data["items"])}
            if audit_hook:
                audit_hook(rows, data)
            return native.adapt_native_response(json.dumps({"reviews": rows}), native.AuthoredSolutionFlagReviewContract(count))

        return verify_questions(questions, request or self.request, Mock(side_effect=AssertionError("uncounted review")),
                                solve=Mock(side_effect=AssertionError("uncounted solver")), solve_with_count=solve,
                                review_with_count=audit, solver_contract="complete_choices", feedback_contract="authored_solution",
                                audit_choice_pairs=True, choice_slots=True, compiled_questions=sidecars)

    def test_five_proved_rows_skip_solver_and_preserve_every_field_through_one_final_audit(self):
        before = copy.deepcopy(self.compiled)
        result = self.run_verify(self.compiled, self.sidecars)
        self.assertEqual([(stage, count) for stage, count, _ in self.calls], [("audit", 5)])
        self.assertEqual([learner(q) for q in result], [sidecar.content() for sidecar in self.sidecars.values()])
        self.assertEqual(self.compiled, before)
        self.assertTrue(all(q["verificationPolicyRevision"] == 8 for q in result))
        self.assertEqual((COMPILED_PROOF_VERIFICATION_POLICY_REVISION, VERIFICATION_POLICY_REVISION), (8, 4))

    def test_all_twenty_four_source_orders_and_key_positions_survive_sanitizer_audit_rotation(self):
        positions = set()
        for order in itertools.permutations(("3", "4", "5", "6")):
            rows, sidecars, _ = prepare_mixed_rows({"questions": [quantitative_row(exact_task(choices=order))]})
            exact = sidecars[0].content()
            sanitized_sidecars = {}
            sanitized = _sanitize_questions(rows, self.request, preserve_authored_explanation=True,
                                            compiled_candidates=sidecars, compiled_output=sanitized_sidecars)
            with self.subTest(order=order):
                result = self.run_verify(sanitized, sanitized_sidecars)
                self.assertEqual(len(result), 1)
                self.assertEqual(learner(result[0]), exact)
                self.assertEqual(result[0]["choices"], list(order))
                self.assertEqual(set(self.calls[-1][2]["items"][0]["choices"]), set(order))
                positions.add(result[0]["choices"].index(result[0]["expectedAnswer"]))
        self.assertEqual(positions, {0, 1, 2, 3})
        self.assertTrue(all(stage == "audit" for stage, _, _ in self.calls))

    def test_dense_prose_to_original_to_audit_associations_preserve_scope_and_history(self):
        request = copy.deepcopy(self.request)
        request["skillMap"] = _skill_map()
        request["sourceDocuments"] = [{"name": "Arithmetic", "text": "Use the stated rules.", "truncated": False}]
        request["existingQuestionCoverage"] = [{"prompt": f"Historical exercise {i}", "topic": "Arithmetic",
                                                "expectedAnswer": "HIDDEN KEY", "explanation": "HIDDEN TEACHING", "difficulty": 4}
                                               for i in range(40)]
        originals = [self.compiled[0], self.prose[0], self.compiled[1], self.prose[1], self.prose[2]]
        questions = [{**q, "skillID": f"skill-{i}", "objectiveID": f"objective-{i}", "objective": f"Assigned objective {i}"}
                     for i, q in enumerate(originals)]
        before = copy.deepcopy((questions, request))
        result = self.run_verify(questions, {0: self.sidecars[0], 2: self.sidecars[1]}, reject=(0, 2), request=request)
        self.assertEqual([(stage, count) for stage, count, _ in self.calls], [("solver", 3), ("audit", 3)])
        self.assertEqual([q["prompt"] for q in result], [questions[i]["prompt"] for i in (0, 2, 3)])
        self.assertEqual([q["verificationPolicyRevision"] for q in result], [8, 8, 7])
        solved, audited = self.calls[0][2], self.calls[1][2]
        self.assertEqual([item["prompt"] for item in solved["items"]], [questions[i]["prompt"] for i in (1, 3, 4)])
        for hidden in ("explanation", "expectedAnswer", "difficulty", "choiceExplanations", "HIDDEN"):
            self.assertNotIn(hidden, json.dumps(solved))
        for item, original_index in zip(audited["items"], (0, 2, 3), strict=True):
            for field in ("prompt", "skillID", "objectiveID", "objective", "explanation"):
                self.assertEqual(item[field], questions[original_index][field])
        self.assertEqual(audited["existingQuestions"], [{"prompt": f"Historical exercise {i}", "topic": "Arithmetic"} for i in range(10, 40)])
        self.assertNotIn("HIDDEN", json.dumps(audited))
        for field in ("goal", "skillMap", "sourceDocuments"):
            self.assertEqual(audited[field], request[field])
        self.assertEqual((questions, request), before)

    def test_every_malformed_or_mutated_compiled_input_loses_proof_before_any_callback(self):
        original, sidecar = self.compiled[0], self.sidecars[0]
        for field in LEARNER_FIELDS:
            changed = copy.deepcopy(original)
            if field == "choices":
                changed[field].reverse()
            elif field == "choiceExplanations":
                changed[field][changed["choices"][0]] = "The compiler did not write this replacement."
            else:
                changed[field] += " changed"
            with self.subTest(field=field):
                self.assertEqual(self.run_verify([changed], {0: sidecar}), [])
        for malformed in (replace(sidecar, learner_json="{}"), replace(sidecar, spec_json="{}"), self.sidecars[1]):
            self.assertEqual(self.run_verify([original], {0: malformed}), [])
        # Compiler feedback does not itself confer proof when the sidecar is absent.
        self.assertEqual(self.run_verify([original], {}), [])
        for malformed in ({0: True}, {True: sidecar}, {1: sidecar}, {0: {"spec_json": sidecar.spec_json}}, []):
            with self.subTest(mapping=malformed), self.assertRaises(QuantitativeAuthoringError):
                self.run_verify([original], malformed)
        self.assertEqual(self.calls, [])

    def test_recompilation_after_audit_detects_sidecar_corruption_before_stamping(self):
        sidecar = self.sidecars[0]
        def corrupt(_rows, _data):
            object.__setattr__(sidecar, "learner_json", "{}")
        # Deliberately defeat the frozen dataclass to simulate internal corruption.
        # The existing re-freeze gate fails the call before any revision is minted.
        with self.assertRaises(AuthoredTeachingFormatError):
            self.run_verify(self.compiled[:1], {0: sidecar}, audit_hook=corrupt)
        self.assertEqual([(stage, count) for stage, count, _ in self.calls], [("audit", 1)])

    def test_whole_malformed_local_solver_text_cannot_veto_private_proof_or_credit_prose(self):
        for raw in ("{}", "not json", '{"solutions":[]}'):
            self.calls.clear()
            result = self.run_verify([self.prose[0], self.compiled[0]], {1: self.sidecars[0]}, solve_result=raw)
            self.assertEqual([learner(q) for q in result], [self.sidecars[0].content()])
            self.assertEqual([(stage, count) for stage, count, _ in self.calls], [("solver", 1), ("audit", 1)])
        self.calls.clear()
        self.assertEqual(self.run_verify(self.prose[:1], {}, solve_result="{}"), [])
        self.assertEqual([(stage, count) for stage, count, _ in self.calls], [("solver", 1)])

    def test_provider_configuration_and_durable_failures_keep_existing_propagation(self):
        for error in (ProviderError("synthetic transport"), ServiceConfigurationError("synthetic configuration"),
                      DurableProviderCallBudgetExceededError("synthetic refusal")):
            self.calls.clear()
            with self.subTest(type=type(error).__name__), self.assertRaises(type(error)):
                self.run_verify([self.compiled[0], self.prose[0]], {0: self.sidecars[0]}, solve_result=error)
            self.assertEqual([(stage, count) for stage, count, _ in self.calls], [("solver", 1)])

    def test_final_audit_is_still_whole_count_bound_and_independent_difficulty_applies(self):
        for mutate in (lambda rows: rows.pop("1"), lambda rows: rows.update({"2": rows["0"]}),
                       lambda rows: rows["0"].update(verificationPolicyRevision=8)):
            with self.subTest(mutate=mutate), self.assertRaises(ProviderError):
                self.run_verify(self.compiled[:2], {i: self.sidecars[i] for i in (0, 1)},
                                audit_hook=lambda rows, _: mutate(rows))
        request = {**self.request, "minimumDifficulty": 3}
        self.assertEqual(self.run_verify(self.compiled[:2], {i: self.sidecars[i] for i in (0, 1)}, request=request), [])


if __name__ == "__main__":
    unittest.main()
