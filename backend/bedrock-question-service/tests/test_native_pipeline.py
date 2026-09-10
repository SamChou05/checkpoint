"""Native transport through real orchestration, with synthetic provider responses."""

import copy
import json
import os
import unittest
from unittest.mock import Mock, patch

import lambda_function
import question_generation as generation
from lambda_test_support import (
    FakeBedrockClient,
    FakeLambdaContext,
    _complete_solution,
    _event,
    _raw_question,
    _request_payload,
    _skill_map,
)
from request_contract import (
    _normalize_request,
    _normalize_skill_map_evolution_request,
    _normalize_skill_map_inference_request,
)
from service_errors import ProviderError, ServiceConfigurationError
from skill_maps import _evolve_skill_map, _infer_skill_map
from test_lambda_skill_map_evolution import _evolution_payload, _provider_response


AUTHOR = "question_author_v1"
SOLVER = "complete_choice_solver_v1"
REVIEWER = "default_reviewer_v1"
AUTHORED_REVIEWER = "authored_solution_reviewer_v1"
MODEL = "us.anthropic.claude-sonnet-4-6"
FALLBACK = "moonshotai.kimi-k2.5"


def task_data(request, tag):
    prompt = request["messages"][0]["content"][0]["text"]
    return json.loads(prompt.split(f"<{tag}>\n", 1)[1].split(f"\n</{tag}>", 1)[0])


def review(question, index=0, **changes):
    return {
        "index": index,
        "valid": True,
        "answer": question["expectedAnswer"],
        "difficulty": 3,
        "explanation": "The stated conditions establish the indicated conclusion.",
        "choiceFeedback": [
            {"choice": choice, "explanation": f"  The stated facts determine this result: {choice}\n"}
            for choice in reversed(question["choices"])
        ],
        **changes,
    }


class ScriptedNativeClient:
    """Fail immediately if a real stage loses or selects the wrong contract."""

    def __init__(self, *steps):
        self.steps = list(steps)
        self.calls = []

    def converse(self, **request):
        self.calls.append(copy.deepcopy(request))
        if not self.steps:
            raise AssertionError("Unexpected provider attempt")
        contract, result = self.steps.pop(0)
        assert request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"] == contract
        system = request["system"][0]["text"]
        if contract == REVIEWER:
            assert "NATIVE TRANSPORT OVERRIDE" in system
            assert "choiceFeedback" in system
        else:
            assert contract in system
        if isinstance(result, Exception):
            raise result
        if callable(result):
            result = result(request)
        return {
            "stopReason": "end_turn",
            "output": {"message": {"content": [{
                "text": result if isinstance(result, str) else json.dumps(result, ensure_ascii=False),
            }]}},
            "usage": {"inputTokens": 11, "outputTokens": 7},
        }


class NativePipelineTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
            "BEDROCK_MODEL_ID": MODEL,
            "BEDROCK_VERIFICATION_MODEL_ID": MODEL,
            "BEDROCK_FALLBACK_MODEL_ID": "",
            "SKILL_MAP_MODEL_ID": FALLBACK,
            "QUESTION_FEEDBACK_CONTRACT": "reviewer_written",
            "GENERATION_ATTEMPTS": "1",
            "ALLOW_UNAUTHENTICATED_BACKEND": "true",
            "REQUIRE_RATE_LIMITING": "false",
            "RATE_LIMIT_TABLE_NAME": "",
            "SERVICE_MODE": "enabled",
            "EMIT_STRUCTURED_METRICS": "false",
        })
        environment.start()
        self.addCleanup(environment.stop)
        self.question = _raw_question("Which conclusion follows from these stated conditions?")
        self.request = _normalize_request(_request_payload(target_count=1))

    def solver(self, question, mutate=None):
        def respond(request):
            data = task_data(request, "question_solution_json")
            item = data["items"][0]
            self.assertEqual(set(item), {"index", "prompt", "choices", "skillID", "objectiveID", "topic"})
            self.assertNotIn("expectedAnswer", json.dumps(data))
            self.assertNotIn(question["explanation"], json.dumps(data))
            result = _complete_solution(item, question["expectedAnswer"])
            if mutate:
                mutate(result)
            return {"solutions": [result]}
        return respond

    def pipeline(self, question=None, reviewer=None, mutate_solver=None):
        question = question or self.question
        return ScriptedNativeClient(
            (AUTHOR, {"questions": [question]}),
            (SOLVER, self.solver(question, mutate_solver)),
            (REVIEWER, {"reviews": [reviewer or review(question)]}),
        )

    def test_http_preserves_wire_feedback_and_independent_verification(self):
        client = self.pipeline()
        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1)), bedrock_client=client,
        )
        self.assertEqual(response["statusCode"], 200)
        question = json.loads(response["body"])["questions"][0]
        self.assertEqual(question["verificationVersion"], 1)
        self.assertEqual(question["verificationPolicyRevision"], 2)
        self.assertEqual(question["expectedAnswer"], self.question["expectedAnswer"])
        self.assertCountEqual(question["choices"], self.question["choices"])
        self.assertEqual(question["choiceExplanations"], {
            row["choice"]: row["explanation"] for row in review(self.question)["choiceFeedback"]
        })
        self.assertNotIn("choiceFeedback", question)
        data = task_data(client.calls[2], "question_review_json")
        self.assertNotIn("expectedAnswer", data["items"][0])
        self.assertNotIn("explanation", data["items"][0])
        self.assertIn("independentSolutions", data)
        self.assertEqual(len(client.calls), 3)

    def test_author_preserves_supplied_map_tags_and_uses_same_static_schema(self):
        payload = _request_payload(target_count=1)
        payload["skillMap"] = _skill_map()
        request = _normalize_request(payload)
        skill = payload["skillMap"]["skills"][0]
        objective = skill["objectives"][0]
        question = {**self.question, "topic": skill["name"], "skillID": skill["id"],
                    "objectiveID": objective["id"], "objective": objective["name"]}
        client = self.pipeline(question)
        accepted = generation._generate_sanitized_questions(request, client, generation.ProviderCallBudget(3))
        self.assertEqual(len(accepted), 1)
        self.assertEqual(accepted[0]["skillID"].lower(), skill["id"].lower())
        self.assertEqual(accepted[0]["objectiveID"].lower(), objective["id"].lower())
        schema = client.calls[0]["outputConfig"]
        self.assertNotIn(skill["id"], json.dumps(schema))
        self.assertNotIn(question["prompt"], json.dumps(schema))
        self.assertIn("skillMap", task_data(client.calls[0], "generation_request_json"))

    def test_top_up_keeps_stage_schemas_and_accepted_work_after_invalid_native_output(self):
        request = _normalize_request(_request_payload(target_count=2))
        client = self.pipeline()
        client.steps.append((AUTHOR, '{"questions":[],"unknown":true}'))
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "2"}):
            accepted = generation._generate_sanitized_questions(request, client, budget, metrics)
        self.assertEqual([q["prompt"] for q in accepted], [self.question["prompt"]])
        top_up = task_data(client.calls[3], "generation_request_json")
        self.assertEqual(top_up["targetCount"], 1)
        self.assertIn(self.question["prompt"], top_up["existingPrompts"])
        self.assertEqual(client.calls[0]["outputConfig"], client.calls[3]["outputConfig"])
        self.assertEqual(metrics["ProviderCalls"], 4)
        self.assertEqual(budget.calls, 4)
        self.assertEqual(reserve.call_count, 4)
        self.assertEqual(metrics["BedrockInputTokens"], 44)
        self.assertEqual(metrics["BedrockOutputTokens"], 28)
        self.assertNotIn(self.question["expectedAnswer"], json.dumps(metrics))

    def test_configured_transient_fallback_retains_author_constraints(self):
        secret = "private-learner-secret-in-transient-error"
        client = ScriptedNativeClient(
            (AUTHOR, RuntimeError(secret)),
            (AUTHOR, {"questions": [self.question]}),
        )
        budget = generation.ProviderCallBudget(2)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {"BEDROCK_FALLBACK_MODEL_ID": FALLBACK}):
            result = generation._generate_provider_payload(self.request, client, budget, metrics)
        self.assertEqual(metrics["ProviderCalls"], 2)
        self.assert_failed_observation(metrics, "request_failed", secret, index=0)
        self.assertEqual(result, {"questions": [self.question]})
        self.assertEqual([call["modelId"] for call in client.calls], [MODEL, FALLBACK])
        self.assertEqual(client.calls[0]["outputConfig"], client.calls[1]["outputConfig"])
        self.assertEqual(budget.calls, 2)
        self.assertEqual(client.calls[1]["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})

    def test_service_schema_rejection_does_not_switch_models_or_retry_unconstrained(self):
        from botocore.exceptions import ClientError

        error = ClientError({"Error": {"Code": "ValidationException", "Message": "Synthetic invalid schema"}}, "Converse")
        client = ScriptedNativeClient((AUTHOR, error), (AUTHOR, {"questions": []}))
        reserve = Mock()
        budget = generation.ProviderCallBudget(2, reserve_call=reserve)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {"BEDROCK_FALLBACK_MODEL_ID": FALLBACK}):
            with self.assertRaises((ProviderError, ServiceConfigurationError)):
                generation._generate_provider_payload(self.request, client, budget, metrics)
        self.assertEqual([call["modelId"] for call in client.calls], [MODEL])
        self.assertEqual(budget.calls, 1)
        self.assertEqual(reserve.call_count, 1)
        self.assertEqual(metrics["ProviderCalls"], 1)

    def test_native_schema_error_preserves_verified_top_up_work_without_fallback(self):
        from botocore.exceptions import ClientError

        secret = "private-learner-secret-from-provider-error"
        error = ClientError({"Error": {"Code": "ValidationException", "Message": secret}}, "Converse")
        client = self.pipeline()
        client.steps.extend([(AUTHOR, error), (AUTHOR, {"questions": []})])
        request = _normalize_request(_request_payload(target_count=2))
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "2", "BEDROCK_FALLBACK_MODEL_ID": FALLBACK}):
            result = generation._generate_sanitized_questions(request, client, budget, metrics)
        self.assertEqual([question["prompt"] for question in result], [self.question["prompt"]])
        self.assertEqual(result[0]["verificationPolicyRevision"], 2)
        self.assertEqual([call["modelId"] for call in client.calls], [MODEL] * 4)
        self.assertEqual(len(client.steps), 1)
        self.assertEqual(budget.calls, 4)
        self.assertEqual(reserve.call_count, 4)
        self.assertEqual(metrics["ProviderCalls"], 4)
        self.assertEqual(metrics["BedrockInputTokens"], 33)
        self.assertEqual(metrics["BedrockOutputTokens"], 21)
        self.assertEqual(len(metrics["ProviderObservations"]), 4)
        self.assert_failed_observation(metrics, "request_invalid", secret)

    def test_initial_native_schema_error_remains_an_accounted_failure(self):
        from botocore.exceptions import ClientError

        secret = "private-schema-error-before-any-accepted-item"
        error = ClientError({"Error": {"Code": "ValidationException", "Message": secret}}, "Converse")
        client = ScriptedNativeClient((AUTHOR, error), (AUTHOR, {"questions": []}))
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "2", "BEDROCK_FALLBACK_MODEL_ID": FALLBACK}):
            with self.assertRaises(ServiceConfigurationError):
                generation._generate_sanitized_questions(self.request, client, budget, metrics)
        self.assertEqual([call["modelId"] for call in client.calls], [MODEL])
        self.assertEqual(len(client.steps), 1)
        self.assertEqual(budget.calls, 1)
        self.assertEqual(reserve.call_count, 1)
        self.assertEqual(metrics["ProviderCalls"], 1)
        self.assertEqual(metrics["BedrockInputTokens"], 0)
        self.assertEqual(metrics["BedrockOutputTokens"], 0)
        self.assertEqual(len(metrics["ProviderObservations"]), 1)
        self.assert_failed_observation(metrics, "request_invalid", secret)

    def assert_failed_observation(self, metrics, outcome, secret, index=-1):
        observation = metrics["ProviderObservations"][index]
        self.assertEqual(set(observation), {"model", "elapsedSeconds", "outcome", "structuredOutput"})
        self.assertEqual(observation["outcome"], outcome)
        self.assertEqual(observation["model"], MODEL)
        self.assertGreaterEqual(observation["elapsedSeconds"], 0)
        structure = observation["structuredOutput"]
        self.assertEqual(set(structure), {"mode", "name", "version", "sha256"})
        self.assertEqual(structure["mode"], "native")
        self.assertEqual(structure["name"], AUTHOR)
        self.assertEqual(structure["version"], "1")
        self.assertRegex(structure["sha256"], r"^[0-9a-f]{64}$")
        self.assertNotIn(secret, json.dumps(metrics))
        self.assertNotIn(self.question["expectedAnswer"], json.dumps(metrics))

    def test_malformed_native_author_fails_once_without_lenient_json_repair(self):
        for raw in ('{"questions":', '{"questions":[],"questions":[]}',
                    '{"questions":[{"difficulty":1e309}]}', '```json\n{"questions":[]}\n```'):
            with self.subTest(raw=raw):
                client = ScriptedNativeClient((AUTHOR, raw))
                budget = generation.ProviderCallBudget(3)
                with self.assertRaises(ProviderError):
                    generation._generate_provider_payload(self.request, client, budget)
                self.assertEqual(len(client.calls), 1)
                self.assertEqual(budget.calls, 1)

    def test_native_solver_vetoes_still_prevent_reviewer_call(self):
        for state in ("zero", "multiple", "uncertain", "different"):
            with self.subTest(state=state):
                def mutate(result):
                    correct = next(r for r in result["choices"] if r["judgment"] == "supported")
                    wrong = next(r for r in result["choices"] if r["judgment"] == "refuted")
                    if state in {"zero", "different"}:
                        correct["judgment"] = "refuted"
                    if state in {"multiple", "different"}:
                        wrong["judgment"] = "supported"
                    if state == "uncertain":
                        wrong["judgment"] = "uncertain"
                client = self.pipeline(mutate_solver=mutate)
                result = generation._generate_sanitized_questions(self.request, client, generation.ProviderCallBudget(3))
                self.assertEqual(result, [])
                self.assertEqual(len(client.calls), 2)

    def test_native_feedback_requires_exact_choice_coverage_and_answer_agreement(self):
        for state in ("missing", "foreign", "answer", "rejected", "index"):
            with self.subTest(state=state):
                record = review(self.question)
                if state == "missing":
                    record["choiceFeedback"].pop()
                elif state == "foreign":
                    record["choiceFeedback"][0]["choice"] += " foreign"
                elif state == "answer":
                    record["answer"] = self.question["choices"][1]
                elif state == "rejected":
                    record.update(valid=False, answer="", explanation="", choiceFeedback=[])
                else:
                    record["index"] = 1
                client = self.pipeline(reviewer=record)
                self.assertEqual(generation._generate_sanitized_questions(
                    self.request, client, generation.ProviderCallBudget(3),
                ), [])
                self.assertEqual(len(client.calls), 3)

    def test_authored_native_audit_preserves_immutable_explanation(self):
        question = {**self.question, "explanation": "  The stated rule applies here.\r\nIts conditions establish this conclusion.  "}
        def audit(request):
            data = task_data(request, "question_review_json")
            self.assertEqual(data["items"][0]["explanation"], question["explanation"])
            self.assertNotIn("expectedAnswer", data["items"][0])
            self.assertNotIn("independentSolutions", data)
            return {"reviews": [{"index": 0, "valid": True, "answer": question["expectedAnswer"],
                                  "difficulty": 3, "explanationSupport": "supported", "issues": []}]}
        client = ScriptedNativeClient((AUTHOR, {"questions": [question]}),
                                      (SOLVER, self.solver(question)), (AUTHORED_REVIEWER, audit))
        with patch.dict(os.environ, {"QUESTION_FEEDBACK_CONTRACT": "authored_solution"}):
            result = generation._generate_sanitized_questions(self.request, client, generation.ProviderCallBudget(3))
        self.assertEqual(result[0]["explanation"].encode(), question["explanation"].encode())
        self.assertEqual(result[0]["choiceExplanations"], {})
        self.assertEqual(result[0]["verificationPolicyRevision"], 3)
        self.assertEqual(result[0]["verificationVersion"], 1)

    def test_authored_native_audit_cannot_approve_uncertain_or_issue_bearing_teaching(self):
        for changes in ({"explanationSupport": "uncertain"}, {"explanationSupport": "unsupported"},
                        {"valid": False, "answer": ""}, {"issues": ["The explanation assumes unstated facts."]}):
            with self.subTest(changes=changes):
                record = {"index": 0, "valid": True, "answer": self.question["expectedAnswer"],
                          "difficulty": 3, "explanationSupport": "supported", "issues": [], **changes}
                client = ScriptedNativeClient((AUTHOR, {"questions": [self.question]}),
                    (SOLVER, self.solver(self.question)), (AUTHORED_REVIEWER, {"reviews": [record]}))
                with patch.dict(os.environ, {"QUESTION_FEEDBACK_CONTRACT": "authored_solution"}):
                    self.assertEqual(generation._generate_sanitized_questions(
                        self.request, client, generation.ProviderCallBudget(3),
                    ), [])

    def test_worker_callback_uses_native_common_path_and_reserves_each_stage(self):
        client = self.pipeline()
        reserve = Mock()
        generated = []
        def process(_event, _context, generate_questions, **_kwargs):
            generated.extend(generate_questions(self.request, reserve))
            return {"batchItemFailures": []}
        with patch("lambda_function.question_bank.handle_worker_event", side_effect=process), \
                patch("question_generation._bedrock_client", return_value=client):
            response = lambda_function.question_bank_worker_handler({"Records": []}, FakeLambdaContext(240_000))
        self.assertEqual(response, {"batchItemFailures": []})
        self.assertEqual(len(generated), 1)
        self.assertEqual(reserve.call_count, 3)
        self.assertEqual(len(client.calls), 3)

    def test_map_inference_retry_retains_schema_and_server_owned_ids(self):
        provider = {"skills": [
            {"name": name, "objectives": [{"name": first}, {"name": second}]}
            for name, first, second in (
                ("Algebraic reasoning", "Solve linear equations", "Interpret variable relationships"),
                ("Geometry", "Apply triangle properties", "Reason about coordinate geometry"),
                ("Data analysis", "Interpret distributions", "Compare statistical summaries"),
            )
        ]}
        request = _normalize_skill_map_inference_request({"goal": {"title": "Improve high-school mathematics"}})
        client = ScriptedNativeClient(("skill_map_inference_v1", {"skills": provider["skills"][:2]}),
                                      ("skill_map_inference_v1", provider))
        budget = generation.ProviderCallBudget(2)
        result = _infer_skill_map(request, client, call_budget=budget)
        self.assertEqual(result["version"], 1)
        self.assertEqual(len(result["skills"]), 3)
        self.assertTrue(all(skill["id"] and all(o["id"] for o in skill["objectives"]) for skill in result["skills"]))
        self.assertEqual(client.calls[0]["outputConfig"], client.calls[1]["outputConfig"])
        self.assertNotEqual(client.calls[0]["messages"], client.calls[1]["messages"])
        self.assertEqual([call["modelId"] for call in client.calls], [FALLBACK, FALLBACK])
        self.assertEqual(budget.calls, 2)

    def test_map_evolution_retry_retains_schema_and_exact_predecessor_coverage(self):
        request = _normalize_skill_map_evolution_request(_evolution_payload(mastered_count=2))
        provider = _provider_response(request["masteredSkillIDs"])
        client = ScriptedNativeClient(("skill_map_evolution_v1", {"changes": provider["changes"][:1]}),
                                      ("skill_map_evolution_v1", provider))
        budget = generation.ProviderCallBudget(2)
        result = _evolve_skill_map(request, client, call_budget=budget)
        self.assertEqual(result["skillMap"]["version"], request["currentSkillMap"]["version"] + 1)
        self.assertEqual(len(result["replacements"]), 2)
        self.assertCountEqual([r["predecessorSkillID"] for r in result["replacements"]], request["masteredSkillIDs"])
        self.assertEqual(client.calls[0]["outputConfig"], client.calls[1]["outputConfig"])
        self.assertNotEqual(client.calls[0]["messages"], client.calls[1]["messages"])
        self.assertEqual(budget.calls, 2)


    def test_oversized_padded_native_feedback_is_rejected_without_trimming_to_fit(self):
        for field, limit in (("explanation", 420), ("choiceFeedback", 280)):
            with self.subTest(field=field):
                record = review(self.question)
                padded = " " * limit + "This explanation follows from the stated conditions."
                if field == "explanation":
                    record[field] = padded
                else:
                    record[field][0]["explanation"] = padded
                client = self.pipeline(reviewer=record)
                self.assertEqual(generation._generate_sanitized_questions(
                    self.request, client, generation.ProviderCallBudget(3),
                ), [])

    def test_historical_stem_only_evaluation_explicitly_retains_legacy_transport(self):
        from evals.checkpoint_learning_eval import evaluate_review
        from question_verification import REVIEW_SYSTEM_PROMPT, SOLUTION_SYSTEM_PROMPT

        client = FakeBedrockClient.returning_questions(self.question)
        client.last_questions = [self.question]
        case = {"case_id": "native-rollout-legacy-eval", "goal": self.request["goal"],
                "question": self.question, "expected_accept": True,
                "rationale": "Synthetic fixture establishes only historical path compatibility."}
        result = evaluate_review(case, client)
        self.assertTrue(result["passed"], result)
        self.assertEqual(result["provider_calls"], 2)
        calls = client.solution_calls + client.review_calls
        self.assertEqual([call["system"][0]["text"] for call in calls],
                         [SOLUTION_SYSTEM_PROMPT, REVIEW_SYSTEM_PROMPT])
        self.assertTrue(all("outputConfig" not in call for call in calls))
        self.assertNotIn("choices", task_data(calls[0], "question_solution_json")["items"][0])
        observations = result["metrics"]["ProviderObservations"]
        self.assertTrue(all(o["structuredOutput"]["mode"] == "legacy" for o in observations))

    def test_legacy_transport_cannot_be_combined_with_a_native_stage_contract(self):
        client = Mock()
        with self.assertRaises(ServiceConfigurationError):
            generation._generate_with_bedrock(self.request, client, MODEL,
                contract=AUTHOR, legacy_transport=True)
        client.converse.assert_not_called()


if __name__ == "__main__":
    unittest.main()
