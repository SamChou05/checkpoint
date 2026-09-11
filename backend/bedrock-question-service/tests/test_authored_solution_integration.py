"""Opt-in production path: immutable teaching ownership, not factual proof."""

import copy
import json
import unittest
from unittest.mock import Mock, patch

import question_generation as generation
from lambda_test_support import FakeBedrockClient, _complete_solution, _raw_question, _request_payload
from question_quality import _sanitize_questions
from question_teaching import AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import ServiceConfigurationError
from verification_policy import VERIFICATION_POLICY_REVISION


def payload(text):
    return json.loads(text.split("\n", 1)[1].rsplit("\n", 1)[0])


def audit(question, index=0, **changes):
    return {"index": index, "valid": True, "answer": question["expectedAnswer"],
            "difficulty": 3, "explanationSupport": "supported", "issues": [], **changes}


def encoded(reviews):
    return json.dumps({"reviews": reviews}, ensure_ascii=False)


class AuthoredSolutionIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.question = _raw_question("Which conclusion follows from these stated conditions?")
        self.question["explanation"] = "  The stated rule applies here.\r\nIts conditions establish this conclusion.  "
        self.request = _normalize_request(_request_payload(target_count=1))

    def run_authored(self, questions, solver, reviewer, metrics=None, request=None):
        return verify_questions(questions, request or self.request, reviewer, metrics,
                                solve=solver, solver_contract="complete_choices",
                                feedback_contract="authored_solution")

    def solver(self, _system, prompt):
        return json.dumps({"solutions": [
            _complete_solution(item, self.question["expectedAnswer"])
            for item in payload(prompt)["items"]
        ]})

    def test_actual_generation_owns_exact_teaching_and_three_call_provenance(self):
        authored = copy.deepcopy(self.question)
        authored["verificationPolicyRevision"] = 99
        calls = []

        class Client:
            def converse(client, **request):
                calls.append(copy.deepcopy(request))
                text = request["messages"][0]["content"][0]["text"]
                if text.startswith("<question_solution_json>"):
                    self.assertNotIn(authored["explanation"], text)
                    result = json.loads(self.solver("", text))
                elif text.startswith("<question_review_json>"):
                    self.assertEqual(request["system"], [{"text": AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT}])
                    data = payload(text)
                    self.assertEqual(data["items"][0]["explanation"], authored["explanation"])
                    self.assertNotIn("independentSolutions", data)
                    result = {"reviews": [audit(authored)]}
                else:
                    self.assertIn("complete worked solution", request["system"][0]["text"])
                    result = {"questions": [authored]}
                return {"output": {"message": {"role": "assistant", "content": [
                    {"text": json.dumps(result, ensure_ascii=False)},
                ]}}, "stopReason": "end_turn", "usage": {"inputTokens": 10, "outputTokens": 20}}

        with patch.dict("os.environ", {"QUESTION_FEEDBACK_CONTRACT": "authored_solution", "GENERATION_ATTEMPTS": "1"}):
            budget = generation.ProviderCallBudget(3)
            result = generation._generate_sanitized_questions(self.request, Client(), budget)
        self.assertEqual(len(calls), 3)
        self.assertEqual(budget.calls, 3)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["explanation"].encode(), authored["explanation"].encode())
        self.assertEqual(result[0]["choiceExplanations"], {})
        self.assertEqual(result[0]["verificationPolicyRevision"], 3)
        self.assertEqual(result[0]["verificationVersion"], 1)
        self.assertEqual(VERIFICATION_POLICY_REVISION, 2)
        self.assertEqual(json.loads(json.dumps(result)), result)

    def test_configuration_and_solver_contract_cannot_be_inferred_or_downgraded(self):
        with patch.dict("os.environ", {"QUESTION_FEEDBACK_CONTRACT": "unrecognized"}):
            client = Mock()
            with self.assertRaises(ServiceConfigurationError):
                generation._generate_sanitized_questions(self.request, client)
            client.converse.assert_not_called()
        reviewer = Mock()
        with self.assertRaises(ValueError):
            verify_questions([self.question], self.request, reviewer,
                             feedback_contract="authored_solution", solve=self.solver)
        self.assertEqual(self.run_authored([self.question], None, reviewer), [])
        reviewer.assert_not_called()
        with self.assertRaises(ValueError):
            verify_questions([self.question], self.request, reviewer, feedback_contract="unknown")
        request = {**self.request, "feedbackContract": "authored_solution"}
        with patch.dict("os.environ", {"QUESTION_FEEDBACK_CONTRACT": "reviewer_written"}):
            # A supplied application selector now has an explicit contract;
            # unsupported values cannot silently become reviewer-written text.
            with self.assertRaises(ServiceConfigurationError):
                generation._generate_sanitized_questions(
                    request, FakeBedrockClient.returning_questions(self.question),
                    generation.ProviderCallBudget(3),
                )

    def test_incoming_teaching_is_rejected_before_sanitization_can_drop_or_clip_it(self):
        for changes in (
            {"choiceExplanations": {self.question["choices"][0]: "Existing teaching cannot disappear."}},
            {"choiceExplanations": None}, {"choiceExplanations": []},
            {"explanation": "x" * 421}, {"explanation": 123}, {"explanation": "Too short"},
        ):
            with self.subTest(changes=changes):
                value = {**self.question, **changes}
                self.assertEqual(_sanitize_questions([value], self.request, preserve_authored_explanation=True), [])
                solver, reviewer = Mock(), Mock()
                self.assertEqual(self.run_authored([value], solver, reviewer), [])
                solver.assert_not_called()
                reviewer.assert_not_called()
        value = _sanitize_questions([self.question], self.request, preserve_authored_explanation=True)[0]
        self.assertEqual(value["explanation"], self.question["explanation"])

    def test_all_solver_vetoes_still_prevent_any_teaching_audit(self):
        for state in ("zero", "multiple", "uncertain", "different"):
            def solver(_system, prompt):
                item = payload(prompt)["items"][0]
                record = _complete_solution(item, self.question["expectedAnswer"])
                if state == "zero":
                    for row in record["choices"]:
                        row["judgment"] = "refuted"
                else:
                    wrong = next(row for row in record["choices"] if row["judgment"] == "refuted")
                    wrong["judgment"] = "uncertain" if state == "uncertain" else "supported"
                    if state == "different":
                        next(row for row in record["choices"] if row["choice"] == self.question["expectedAnswer"])["judgment"] = "refuted"
                return json.dumps({"solutions": [record]})
            reviewer = Mock(return_value=encoded([audit(self.question)]))
            with self.subTest(state=state):
                self.assertEqual(self.run_authored([self.question], solver, reviewer), [])
                reviewer.assert_not_called()

    def test_audit_cannot_introduce_teaching_or_waive_support_issues_or_difficulty(self):
        for change in (
            {"explanation": "An unaudited replacement explanation."},
            {"choiceExplanations": {}}, {"verificationPolicyRevision": 3},
            {"explanationSupport": "unsupported"}, {"explanationSupport": "uncertain"},
            {"issues": ["A stated condition does not establish this result."]},
            {"difficulty": 2}, {"answer": self.question["choices"][1]},
        ):
            metrics = {}
            reviewer = Mock(return_value=encoded([audit(self.question, **change)]))
            with self.subTest(change=change):
                self.assertEqual(self.run_authored([self.question], self.solver, reviewer, metrics), [])
                self.assertNotIn("accepted", metrics["QuestionQuality"]["review"])

    def test_dense_survivors_keep_exact_main_context_and_hide_solver_and_history(self):
        questions = [{**copy.deepcopy(self.question),
                      "prompt": f"Observation {i} supplies a different set of stated conditions. What follows?",
                      "explanation": f"  AUTHORED MAIN {i} applies the stated rule.\nIts conditions support the result.  "}
                     for i in range(4)]
        initial = copy.deepcopy(questions)
        request = copy.deepcopy(self.request)
        request["sourceDocuments"] = [{"name": "rules", "text": "Use the stipulated subject rules.",
                                        "url": "https://example.org/rules", "truncated": True}]
        request["existingQuestionCoverage"] = [{"prompt": "Earlier subject question.",
            "expectedAnswer": "HIDDEN HISTORY KEY", "explanation": "HIDDEN HISTORY TEACHING"}]

        def solver(_system, prompt):
            self.assertNotIn("AUTHORED MAIN", prompt)
            data = payload(prompt)
            rows = []
            for item in data["items"]:
                record = _complete_solution(item, self.question["expectedAnswer"])
                for row in record["choices"]:
                    row["reason"] = "HIDDEN SOLVER REASON"
                    if item["index"] in (0, 2):
                        row["judgment"] = "refuted"
                rows.append(record)
            questions[1]["explanation"] = "MUTATED EXTERNAL CONTENT"
            return json.dumps({"solutions": list(reversed(rows))})

        def reviewer(_system, prompt):
            self.assertNotIn("HIDDEN", prompt)
            self.assertNotIn("MUTATED", prompt)
            data = payload(prompt)
            self.assertEqual(data["sourceDocuments"], request["sourceDocuments"])
            self.assertEqual([i["index"] for i in data["items"]], [0, 1])
            self.assertEqual([i["explanation"] for i in data["items"]], [initial[i]["explanation"] for i in (1, 3)])
            for item in data["items"]:
                self.assertNotIn("expectedAnswer", item)
                self.assertNotIn("difficulty", item)
            return encoded([audit(initial[3], 1), audit(initial[1], 0)])

        result = self.run_authored(questions, solver, reviewer, request=request)
        self.assertEqual([q["explanation"] for q in result], [initial[i]["explanation"] for i in (1, 3)])
        self.assertTrue(all(q["verificationPolicyRevision"] == 3 for q in result))

    def test_assessed_difficulty_respects_an_exact_adaptive_target(self):
        question = {**self.question, "skillID": "skill", "difficulty": 4}
        request = {**self.request, "adaptiveSkillPlans": [{"skillID": "skill", "targetDifficulty": 4}]}
        reviewer = Mock(return_value=encoded([audit(question, difficulty=3)]))
        self.assertEqual(self.run_authored([question], self.solver, reviewer, request=request), [])
        reviewer.return_value = encoded([audit(question, difficulty=4)])
        result = self.run_authored([question], self.solver, reviewer, request=request)
        self.assertEqual(result[0]["difficulty"], 4)

    def test_agreement_does_not_turn_false_authored_teaching_into_semantic_proof(self):
        question = {**self.question, "prompt": "What is the sum of two and two?",
                    "choices": ["5", "4", "3", "2"], "expectedAnswer": "5",
                    "explanation": "Adding two and two gives the value five."}
        def solver(_system, prompt):
            return json.dumps({"solutions": [_complete_solution(payload(prompt)["items"][0], "5")]})
        result = self.run_authored([question], solver, Mock(return_value=encoded([audit(question)])))
        self.assertEqual(result[0]["explanation"], question["explanation"])
        # Content ownership is enforced; two wrong model judgments are not a truth oracle.
        self.assertEqual(result[0]["expectedAnswer"], "5")


if __name__ == "__main__":
    unittest.main()
