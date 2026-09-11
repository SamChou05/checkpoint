"""Real orchestration with scripted declarations, not a factual-quality eval."""

import copy
import contextlib
import io
import json
import os
import unittest
from unittest.mock import Mock, patch

import lambda_function
import question_generation as generation
from complete_question_teaching import compose_feedback_displays
from generation_diagnostics import quality_summary
from lambda_test_support import _complete_solution, _event, _request_payload
from question_quality import _sanitize_questions
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import BadRequestError, ServiceConfigurationError
from test_native_pipeline import ScriptedNativeClient, task_data
from verification_policy import VERIFICATION_POLICY_REVISION


AUTHOR = "question_author_complete_v1"
SOLVER = "complete_choice_solver_v1"
REVIEWER = "complete_teaching_reviewer_v1"


def question():
    return {
        "prompt": "Evaluate this expression in ordinary arithmetic:\n2 + 2\nWhat is its value?",
        "explanation": "  Adding two and two gives four.\r\nTwo pairs contain four objects.  ",
        "expectedAnswer": "4",
        "choices": ["3", "4", "5", "6"],
        "choiceExplanations": {
            "3": "Three is one less than the stated sum.  ",
            "4": "Two pairs contain four objects.\nThe sum is four.",
            "5": "Five is one greater than the stated sum.",
            "6": "Six counts an additional pair not present in the expression.",
        },
        "topic": "Arithmetic", "difficulty": 1, "format": "Multiple Choice",
    }


def wire_author(item):
    result = copy.deepcopy(item)
    feedback = result.pop("choiceExplanations")
    result["choiceFeedback"] = [
        {"choice": c, "explanation": feedback[c]} for c in reversed(result["choices"])
    ]
    return {"questions": [result]}


def audit(item, index=0, **changes):
    return {
        "index": index, "valid": True, "answer": item["expectedAnswer"],
        "difficulty": item["difficulty"], "explanationSupport": "supported",
        "choiceFeedbackSupport": [
            {"choice": c, "feedbackSupport": "supported", "displaySupport": "supported"}
            for c in reversed(item["choices"])
        ], "issues": [], **changes,
    }


def tagged(text):
    return json.loads(text.split("\n", 1)[1].rsplit("\n", 1)[0])


class CompleteTeachingIntegrationTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
            "BEDROCK_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
            "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
            "BEDROCK_FALLBACK_MODEL_ID": "", "QUESTION_FEEDBACK_CONTRACT": "reviewer_written",
            "GENERATION_ATTEMPTS": "1", "ALLOW_UNAUTHENTICATED_BACKEND": "true",
            "REQUIRE_RATE_LIMITING": "false", "RATE_LIMIT_TABLE_NAME": "",
            "SERVICE_MODE": "enabled", "EMIT_STRUCTURED_METRICS": "false",
        })
        environment.start()
        self.addCleanup(environment.stop)
        self.item = question()
        self.payload = {**_request_payload(target_count=1, minimum_difficulty=1),
                        "feedbackContract": "authored_complete"}
        self.payload["goal"] = {"title": "Understand ordinary arithmetic", "category": "Custom",
                                "focusAreas": "Adding small whole numbers", "needsSkillMap": False}
        self.request = _normalize_request(self.payload)
        self.metrics = {}

    def solve(self, _system, prompt):
        data = tagged(prompt)
        self.assertNotIn("expectedAnswer", prompt)
        for content in [self.item["explanation"], *self.item["choiceExplanations"].values()]:
            self.assertNotIn(content, prompt)
        return json.dumps({"solutions": [
            _complete_solution(row, self.item["expectedAnswer"]) for row in data["items"]
        ]})

    def verify(self, review, questions=None, request=None, solve=None):
        return verify_questions(
            questions or [self.item], request or self.request,
            Mock(return_value=json.dumps({"reviews": [review]})),
            request_metrics=self.metrics,
            solve=solve or self.solve, solver_contract="complete_choices",
            feedback_contract="authored_complete",
        )

    def client(self, *, review=None, solver=None):
        def solve(wire):
            data = task_data(wire, "question_solution_json")
            self.assertTrue(all("expectedAnswer" not in row and "explanation" not in row for row in data["items"]))
            self.assertNotIn("choiceExplanations", json.dumps(data))
            return {"solutions": [_complete_solution(row, self.item["expectedAnswer"]) for row in data["items"]]}

        def check(wire):
            data = task_data(wire, "question_review_json")
            self.assertNotIn("independentSolutions", data)
            row = data["items"][0]
            self.assertNotIn("expectedAnswer", row)
            self.assertNotIn("difficulty", row)
            self.assertEqual(row["explanation"], self.item["explanation"])
            self.assertEqual(row["choiceExplanations"], self.item["choiceExplanations"])
            self.assertEqual(row["feedbackDisplays"], compose_feedback_displays(row))
            return {"reviews": [review or audit(self.item)]}

        return ScriptedNativeClient((AUTHOR, wire_author(self.item)), (SOLVER, solver or solve), (REVIEWER, check))

    def test_http_explicit_contract_owns_all_exact_teaching_and_three_call_provenance(self):
        client = self.client()
        response = lambda_function.handle_http_request(_event(self.payload), bedrock_client=client)
        self.assertEqual(response["statusCode"], 200)
        returned = json.loads(response["body"])["questions"][0]
        for field in ("prompt", "expectedAnswer", "choices", "explanation", "choiceExplanations"):
            self.assertEqual(returned[field], self.item[field])
        self.assertEqual(returned["verificationPolicyRevision"], 4)
        self.assertEqual(returned["verificationVersion"], 1)
        self.assertEqual(len(client.calls), 3)
        self.assertEqual(VERIFICATION_POLICY_REVISION, 2)
        authored_request = task_data(client.calls[0], "generation_request_json")
        self.assertEqual(authored_request["feedbackContract"], "authored_complete")
        self.assertIn("complete teaching item now", client.calls[0]["system"][0]["text"])

    def test_no_missing_or_oversized_teaching_can_be_dropped_by_sanitization(self):
        cases = [{"choiceExplanations": {}}, {"choiceExplanations": None},
                 {"explanation": "x" * 421}, {"prompt": "x" * 321},
                 {"choices": ["3", " 4", "5", "6"]}, {"expectedAnswer": " 4"}]
        cases.append({"choiceExplanations": {**self.item["choiceExplanations"], "3": "x" * 281}})
        for change in cases:
            with self.subTest(change=change):
                self.assertEqual(_sanitize_questions([{**self.item, **change}], self.request,
                                                    self.metrics, preserve_complete_teaching=True), [])
        cleaned = _sanitize_questions([self.item], self.request, preserve_complete_teaching=True)
        self.assertEqual(cleaned[0]["choices"], self.item["choices"])
        self.assertEqual(cleaned[0]["choiceExplanations"], self.item["choiceExplanations"])

    def test_http_component_rejections_keep_valid_neighbor_and_emit_content_free_metrics(self):
        neighbor = {
            **copy.deepcopy(self.item),
            "prompt": "Four pairs contain how many objects in total?",
            "expectedAnswer": "8", "choices": ["7", "8", "9", "10"],
            "explanation": "Four pairs each contain two objects, giving eight objects in total.",
            "choiceExplanations": {
                "7": "Seven is one less than the total number of objects.",
                "8": "Four groups of two contain eight objects in total.",
                "9": "Nine includes one object beyond the four complete pairs.",
                "10": "Ten counts five pairs, but only four pairs were supplied.",
            },
        }
        self.item["prompt"] += " private-question-marker"
        self.item["explanation"] += " private-explanation-marker"
        self.item["choiceExplanations"]["3"] += " private-feedback-marker"
        payload = copy.deepcopy(self.payload)
        payload["targetCount"] = 2
        payload["goal"]["title"] = "private-goal-marker arithmetic"
        by_prompt = {item["prompt"]: item for item in (self.item, neighbor)}
        authored = {"questions": [wire_author(item)["questions"][0] for item in (self.item, neighbor)]}

        def solve(wire):
            return {"solutions": [
                _complete_solution(row, by_prompt[row["prompt"]]["expectedAnswer"])
                for row in task_data(wire, "question_solution_json")["items"]
            ]}

        for field, component in (("explanationSupport", "main_explanation"),
                                 ("feedbackSupport", "choice_feedback"),
                                 ("displaySupport", "feedback_display")):
            for status in ("unsupported", "uncertain"):
                with self.subTest(field=field, status=status):
                    def review(wire):
                        reviews = []
                        for row in task_data(wire, "question_review_json")["items"]:
                            verdict = audit(by_prompt[row["prompt"]], row["index"])
                            if row["prompt"] == self.item["prompt"]:
                                if field == "explanationSupport":
                                    verdict[field] = status
                                else:
                                    verdict["choiceFeedbackSupport"][0][field] = status
                            reviews.append(verdict)
                        return {"reviews": reviews}

                    client = ScriptedNativeClient((AUTHOR, authored), (SOLVER, solve), (REVIEWER, review))
                    output = io.StringIO()
                    with patch.dict(os.environ, {"EMIT_STRUCTURED_METRICS": "true"}), contextlib.redirect_stdout(output):
                        response = lambda_function.handle_http_request(_event(payload), bedrock_client=client)
                    self.assertEqual(response["statusCode"], 200)
                    returned = json.loads(response["body"])["questions"]
                    self.assertEqual(len(returned), 1)
                    for key in ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations"):
                        self.assertEqual(returned[0][key], neighbor[key])
                    self.assertEqual(returned[0]["verificationPolicyRevision"], 4)
                    metrics = json.loads(output.getvalue())
                    self.assertEqual(metrics["ProviderCalls"], 3)
                    self.assertEqual(metrics["QuestionsReturned"], 1)
                    self.assertEqual(metrics["QuestionQuality"], {
                        "sanitize": {"accepted": 2}, "review": {f"{status}_{component}": 1, "accepted": 1},
                    })
                    for content in ("private-question-marker", "private-explanation-marker", "private-feedback-marker", "private-goal-marker"):
                        self.assertNotIn(content, output.getvalue())

    def test_invalid_complete_teaching_sanitization_records_loss_and_keeps_valid_neighbor(self):
        invalid = {**copy.deepcopy(self.item), "explanation": "private-malformed-teaching" * 30}
        metrics = {}
        retained = _sanitize_questions([invalid, self.item], self.request, metrics, preserve_complete_teaching=True)
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0]["explanation"], self.item["explanation"])
        self.assertEqual(quality_summary(metrics), {"sanitize": {"invalid_complete_teaching": 1, "accepted": 1}})
        self.assertNotIn("private-malformed-teaching", json.dumps(metrics))

    def test_malformed_complete_audit_records_bounded_reason_with_metrics(self):
        malformed = audit(self.item)
        malformed["issues"] = ["private-review-marker " * 31]
        self.assertEqual(self.verify(malformed), [])
        self.assertEqual(quality_summary(self.metrics), {"review": {"invalid_complete_teaching_review": 1}})
        self.assertNotIn("private-review-marker", json.dumps(self.metrics))

    def test_every_reported_objection_and_rewrite_blocks_even_an_approving_review(self):
        changes = [{"explanationSupport": "unsupported"}, {"explanationSupport": "uncertain"},
                   {"issues": ["A condition required by this explanation is not supplied."]},
                   {"explanation": "New unaudited prose must never replace the author's text."},
                   {"choiceExplanations": self.item["choiceExplanations"]},
                   {"answer": "3"}, {"valid": False}, {"verificationPolicyRevision": 4}]
        for field in ("feedbackSupport", "displaySupport"):
            for status in ("unsupported", "uncertain"):
                rows = audit(self.item)["choiceFeedbackSupport"]
                rows[0][field] = status
                changes.append({"choiceFeedbackSupport": rows})
        for change in changes:
            with self.subTest(change=change):
                self.assertEqual(self.verify(audit(self.item, **change)), [])

    def test_solver_disagreement_prevents_teaching_review(self):
        reviewer = Mock()
        def different(_system, prompt):
            return json.dumps({"solutions": [_complete_solution(tagged(prompt)["items"][0], "3")]})
        self.assertEqual(verify_questions([self.item], self.request, reviewer,
                         solve=different, solver_contract="complete_choices", feedback_contract="authored_complete"), [])
        reviewer.assert_not_called()

    def test_snapshot_is_immutable_across_callbacks_and_forged_stamps(self):
        before = copy.deepcopy(self.item)
        self.item["verificationPolicyRevision"] = 99
        def solve(system, prompt):
            response = self.solve(system, prompt)
            self.item["explanation"] = "A later caller mutation must not reach the learner."
            self.item["choiceExplanations"]["3"] = "Another caller mutation after the item was frozen."
            return response
        returned = self.verify(audit(before), solve=solve)[0]
        self.assertEqual(returned["explanation"], before["explanation"])
        self.assertEqual(returned["choiceExplanations"], before["choiceExplanations"])
        self.assertEqual(returned["verificationPolicyRevision"], 4)

    def test_request_context_and_serialized_payloads_are_isolated_across_callbacks(self):
        self.request["sourceDocuments"] = [{"name": "Study notes", "text": "Two pairs contain four objects."}]
        self.request["skillMap"] = {"version": 1, "skills": [{
            "id": "skill", "name": "Arithmetic", "detail": "Adding whole numbers",
            "objectives": [{"id": "objective", "name": "Add pairs", "detail": "Combine two pairs"}],
        }]}
        self.request["existingQuestionCoverage"] = [{"prompt": "An earlier addition question", "topic": "Arithmetic"}]
        before = copy.deepcopy(self.request)
        original_question = copy.deepcopy(self.item)

        def solve(system, prompt):
            data = tagged(prompt)
            self.assertEqual(data["sourceDocuments"], before["sourceDocuments"])
            response = self.solve(system, prompt)
            self.request["goal"]["contentTopics"].append("Changed subject")
            self.request["sourceDocuments"][0]["text"] = "Changed after solving."
            self.request["skillMap"]["skills"][0]["objectives"][0]["detail"] = "Changed objective."
            self.request["existingQuestionCoverage"][0]["prompt"] = "Changed history."
            # The actual callback input is serialized. Mutating its decoded
            # payload cannot expose an alias to the verifier's private snapshot.
            data["goal"]["contentTopics"].append("Changed local payload")
            data["sourceDocuments"][0]["text"] = "Changed local source."
            data["items"][0]["prompt"] = "Changed local question."
            return response

        def review(_system, prompt):
            data = tagged(prompt)
            for field in ("goal", "skillMap", "sourceDocuments"):
                self.assertEqual(data[field], before[field])
            self.assertEqual(data["existingQuestions"], before["existingQuestionCoverage"])
            self.assertEqual(data["items"][0]["prompt"], original_question["prompt"])
            self.request["sourceDocuments"][0]["text"] = "Changed after auditing."
            data["items"][0]["explanation"] = "Changed local main after auditing."
            data["items"][0]["choiceExplanations"]["3"] = "Changed local feedback after auditing."
            data["items"][0]["feedbackDisplays"][0]["display"] = "Changed local display after auditing."
            return json.dumps({"reviews": [audit(original_question)]})

        returned = verify_questions(
            [self.item], self.request, review, solve=solve,
            solver_contract="complete_choices", feedback_contract="authored_complete",
        )[0]
        for field in ("prompt", "expectedAnswer", "choices", "explanation", "choiceExplanations"):
            self.assertEqual(returned[field], original_question[field])
        self.assertEqual(returned["verificationPolicyRevision"], 4)

    def test_callbacks_cannot_lower_frozen_difficulty_requirements(self):
        self.item["skillID"] = "skill"
        for stage in ("solve", "review"):
            for gate in ("minimumDifficulty", "adaptiveSkillPlans"):
                with self.subTest(stage=stage, gate=gate):
                    request = copy.deepcopy(self.request)
                    if gate == "minimumDifficulty":
                        request[gate] = 4
                    else:
                        request[gate] = [{"skillID": "skill", "targetDifficulty": 4}]

                    def mutate():
                        if gate == "minimumDifficulty":
                            request[gate] = 1
                        else:
                            request[gate][0]["targetDifficulty"] = 1

                    def solve(system, prompt):
                        if stage == "solve":
                            mutate()
                        return self.solve(system, prompt)

                    def review(_system, _prompt):
                        if stage == "review":
                            mutate()
                        return json.dumps({"reviews": [audit(self.item)]})

                    self.assertEqual(verify_questions(
                        [self.item], request, review, solve=solve,
                        solver_contract="complete_choices", feedback_contract="authored_complete",
                    ), [])

    def test_legitimate_negative_teaching_reaches_full_audit_and_is_preserved(self):
        answer = "Cannot be determined from the information given."
        self.item = {
            "prompt": "A real number x is greater than 2. What is its exact value?",
            "expectedAnswer": answer, "choices": ["3", "4", "5", answer],
            "explanation": "The answer is not determined because every real number greater than 2 satisfies the stated condition.",
            "choiceExplanations": {
                "3": "Three is possible, but other values also satisfy the inequality.",
                "4": "Four is possible, but other values also satisfy the inequality.",
                "5": "Five is possible, but other values also satisfy the inequality.",
                answer: "The inequality allows many distinct values and does not identify a unique number.",
            },
            "topic": "Arithmetic", "difficulty": 1, "format": "Multiple Choice",
        }
        # Existing modes retain their legacy phrase gate.
        self.assertEqual(_sanitize_questions([self.item], self.request), [])
        client = self.client()
        response = lambda_function.handle_http_request(_event(self.payload), bedrock_client=client)
        self.assertEqual(response["statusCode"], 200)
        returned = json.loads(response["body"])["questions"][0]
        for field in ("prompt", "expectedAnswer", "choices", "explanation", "choiceExplanations"):
            self.assertEqual(returned[field], self.item[field])
        self.assertEqual(returned["verificationPolicyRevision"], 4)
        self.assertEqual(len(client.calls), 3)

    def test_request_selector_cannot_be_ignored_or_inferred_from_model_fields(self):
        for value in (None, True, {}, "", "authored_solution", "reviewer_written", "AUTHORED_COMPLETE"):
            with self.subTest(value=value), self.assertRaises(BadRequestError):
                _normalize_request({**self.payload, "feedbackContract": value})
        self.assertEqual(generation._feedback_contract(self.request), "authored_complete")
        with self.assertRaises(ServiceConfigurationError):
            generation._feedback_contract({**self.request, "feedbackContract": "unknown"})
        omitted = copy.deepcopy(self.payload)
        del omitted["feedbackContract"]
        self.assertNotIn("feedbackContract", _normalize_request(omitted))
        self.assertEqual(generation._feedback_contract(_normalize_request(omitted)), "reviewer_written")

    def test_partial_replacement_failure_retains_only_fully_audited_items(self):
        request = {**self.request, "targetCount": 2}
        client = self.client()
        client.steps.append((AUTHOR, RuntimeError("simulated second-pass failure")))
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "2"}):
            result = generation._generate_sanitized_questions(request, client, generation.ProviderCallBudget(6))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["verificationPolicyRevision"], 4)
        self.assertEqual(result[0]["choiceExplanations"], self.item["choiceExplanations"])
        self.assertEqual(len(client.calls), 4)
        self.assertEqual(task_data(client.calls[3], "generation_request_json")["feedbackContract"], "authored_complete")

    def test_adaptive_target_remains_binding_and_false_model_agreement_is_not_proof(self):
        request = {**self.request, "adaptiveSkillPlans": [{"skillID": "skill", "targetDifficulty": 4}]}
        self.item["skillID"] = "skill"
        self.assertEqual(self.verify(audit(self.item, difficulty=3), request=request), [])
        # Deliberately false declarations document the semantic limitation.
        self.item["expectedAnswer"] = "5"
        self.item["explanation"] = "Adding two and two gives the value five."
        result = self.verify(audit(self.item))
        self.assertEqual(result[0]["expectedAnswer"], "5")
        self.assertEqual(result[0]["verificationPolicyRevision"], 4)


if __name__ == "__main__":
    unittest.main()
