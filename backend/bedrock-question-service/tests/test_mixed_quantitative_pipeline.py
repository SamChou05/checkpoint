"""Real native orchestration with fake provider judgments, never model evidence."""

import copy
from dataclasses import replace
import json
import os
import unittest
from unittest.mock import Mock, patch

import question_generation as generation
from lambda_test_support import _raw_question, _request_payload, _skill_map
from quantitative_authoring import (
    CompiledCandidate, LEARNER_FIELDS, MIXED_AUTHOR_CONTRACT, QuantitativeAuthoringError, prepare_mixed_rows,
)
from question_quality import _sanitize_questions
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import ProviderError, ServiceConfigurationError
from test_native_pipeline import (
    AUTHOR, MODEL, ScriptedNativeClient, author_payload, review, review_map,
    solver_map, solver_record, task_data,
)
from test_quantitative_authoring import exact_task, quantitative_row, scalar_task
from verification_policy import (
    COMPILED_QUANTITATIVE_VERIFICATION_POLICY_REVISION,
    MAX_SUPPORTED_VERIFICATION_POLICY_REVISION, VERIFICATION_POLICY_REVISION,
)


def prose_row(question):
    return {"kind": "prose", "question": author_payload(question)["questions"][0]}


class MixedQuantitativePipelineTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "QUESTION_AUTHOR_MODE": "mixed_quantitative",
            "QUESTION_FEEDBACK_CONTRACT": "reviewer_written", "BEDROCK_MODEL_ID": MODEL,
            "BEDROCK_VERIFICATION_MODEL_ID": MODEL, "BEDROCK_FALLBACK_MODEL_ID": "",
            "GENERATION_ATTEMPTS": "1", "BEDROCK_CLAUDE_THINKING": "disabled",
        })
        environment.start()
        self.addCleanup(environment.stop)
        self.prose = _raw_question("Which conclusion follows from these stated conditions?")

    def request(self, target):
        payload = _request_payload(target_count=target, minimum_difficulty=2)
        payload["goal"].update(title="Arithmetic and reasoning", contentTopics=["Arithmetic", "Reasoning"],
                               questionDirective="Practice complete arithmetic and reasoning tasks.")
        return _normalize_request(payload)

    def client(self, rows, *, solver_reject=(), reviewer_change=None, expected_after_sanitize=None):
        prepared, _, _ = prepare_mixed_rows({"questions": rows})
        ground_truth = {row["prompt"]: row for row in prepared if row}
        if expected_after_sanitize is None:
            expected_after_sanitize = len(ground_truth)

        def solver(request):
            data = task_data(request, "question_solution_json")
            self.assertEqual(len(data["items"]), expected_after_sanitize)
            self.assertNotIn("expectedAnswer", json.dumps(data))
            self.assertNotIn("choiceExplanations", json.dumps(data))
            return solver_map(*(solver_record(item, ground_truth[item["prompt"]]["expectedAnswer"],
                                             (lambda record: [row.update(judgment="refuted") for row in record["choices"]])
                                             if item["index"] in solver_reject else None)
                                for item in data["items"]))

        def reviewer(request):
            data = task_data(request, "question_review_json")
            self.assertEqual([item["index"] for item in data["items"]], list(range(len(data["items"]))))
            records = []
            for item in data["items"]:
                record = review(ground_truth[item["prompt"]], item["index"], difficulty=2,
                                explanation="This is deliberately untrusted reviewer teaching: all calculations equal zero.")
                record["choiceFeedback"] = [{"choice": choice, "explanation": "The untrusted reviewer claims this value is zero."}
                                            for choice in ground_truth[item["prompt"]]["choices"]]
                if reviewer_change:
                    reviewer_change(record)
                records.append(record)
            return review_map(*records)

        survivors = expected_after_sanitize - len(solver_reject)
        return ScriptedNativeClient(
            (MIXED_AUTHOR_CONTRACT, {"questions": rows}),
            (f"complete_choice_solver_v5_n{expected_after_sanitize}", solver),
            (f"default_reviewer_v3_n{survivors}", reviewer),
        )

    def run_pipeline(self, rows, *, target=None, **kwargs):
        client = self.client(rows, **kwargs)
        budget = generation.ProviderCallBudget(6)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        result = generation._generate_sanitized_questions(self.request(target or len(rows)), client, budget, metrics)
        return result, client, budget, metrics

    def test_mixed_prose_and_compiled_items_use_three_calls_and_distinct_provenance(self):
        task = exact_task()
        compiled = CompiledCandidate.from_task(task).content()
        results, client, budget, _ = self.run_pipeline([quantitative_row(task), prose_row(self.prose)])
        self.assertEqual(len(results), 2)
        self.assertEqual({key: results[0][key] for key in LEARNER_FIELDS}, compiled)
        self.assertEqual(results[0]["verificationPolicyRevision"], 6)
        self.assertEqual(results[1]["verificationPolicyRevision"], 4)
        self.assertIn("untrusted reviewer", results[1]["explanation"])
        self.assertEqual(results[0]["difficulty"], 2)
        self.assertEqual(budget.calls, 3)
        self.assertEqual(len(client.calls), 3)
        for question in results:
            self.assertFalse(set(question) & {"spec_json", "learner_json", "compiled", "task", "nodes"})

    def test_compiled_scalar_and_rational_teaching_survives_real_pipeline(self):
        tasks = [scalar_task(), exact_task("1/3", ("1/3", "2/3", "1", "4/3"))]
        for relation, selection, choices in (("gt", "minimum", ("6", "7", "8", "9")),
                                              ("le", "maximum", ("6", "7", "8", "9")),
                                              ("ne", "minimum", ("0", "1", "7", "8"))):
            task = scalar_task()
            task.update(selection=selection, choices=dict(zip("abcd", choices, strict=True)))
            task["condition"]["relation"] = relation
            tasks.append(task)
        for task in tasks:
            with self.subTest(kind=task["kind"], condition=task.get("condition")):
                result, _, budget, _ = self.run_pipeline([quantitative_row(task)])
                self.assertEqual(len(result), 1)
                self.assertEqual({key: result[0][key] for key in LEARNER_FIELDS}, CompiledCandidate.from_task(task).content())
                self.assertEqual(result[0]["verificationPolicyRevision"], 6)
                self.assertEqual(budget.calls, 3)

    def test_sanitizer_duplicate_removal_and_solver_reindex_keep_exact_source_binding(self):
        first = quantitative_row()
        second = quantitative_row(exact_task("3", ("4", "5", "6", "7")))
        rows = [prose_row(self.prose), first, copy.deepcopy(first), second]
        results, client, budget, _ = self.run_pipeline(rows, solver_reject=(0,), expected_after_sanitize=3)
        self.assertEqual(len(results), 2)
        for row, result in zip((first, second), results, strict=True):
            self.assertEqual({key: result[key] for key in LEARNER_FIELDS}, CompiledCandidate.from_task(row["task"]).content())
            self.assertEqual(result["verificationPolicyRevision"], 6)
        self.assertEqual([item["index"] for item in task_data(client.calls[2], "question_review_json")["items"]], [0, 1])
        self.assertEqual(budget.calls, 3)

    def test_invalid_spec_cannot_fall_through_to_prose_but_other_subject_survives(self):
        results, _, budget, metrics = self.run_pipeline(
            [quantitative_row(scalar_task(False)), prose_row(self.prose)])
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["prompt"], self.prose["prompt"])
        self.assertEqual(results[0]["verificationPolicyRevision"], 4)
        self.assertEqual(metrics["QuestionQuality"]["compile"]["multiple_answers"], 1)
        self.assertEqual(budget.calls, 3)

    def test_every_invalid_compiled_item_stops_after_author_without_stamp(self):
        client = ScriptedNativeClient((MIXED_AUTHOR_CONTRACT, {"questions": [quantitative_row(scalar_task(False))]}))
        budget = generation.ProviderCallBudget(3)
        self.assertEqual(generation._generate_sanitized_questions(self.request(1), client, budget), [])
        self.assertEqual(budget.calls, 1)

    def test_reviewer_veto_key_disagreement_and_difficulty_still_reject_compiled(self):
        for changes in ({"valid": False}, {"answer": "3"}, {"difficulty": 1}):
            with self.subTest(changes=changes):
                result, _, budget, _ = self.run_pipeline([quantitative_row()], reviewer_change=lambda row: row.update(changes))
                self.assertEqual(result, [])
                self.assertEqual(budget.calls, 3)

    def test_author_cannot_mint_provenance_or_policy_with_extra_fields(self):
        for field in ("verificationPolicyRevision", "compiled", "provenance", "expectedAnswer"):
            row = quantitative_row()
            row[field] = 6
            client = ScriptedNativeClient((MIXED_AUTHOR_CONTRACT, {"questions": [row]}))
            with self.assertRaises(ProviderError):
                generation._generate_sanitized_questions(self.request(1), client, generation.ProviderCallBudget(3))
            self.assertEqual(len(client.calls), 1)

    def test_prose_cannot_mint_compiled_policy_in_legacy_sanitization(self):
        forged = {**self.prose, "verificationPolicyRevision": 6, "compiled": True, "compilerHash": "fake"}
        sanitized = _sanitize_questions([forged], self.request(1))
        self.assertFalse(set(sanitized[0]) & {"verificationPolicyRevision", "compiled", "compilerHash"})

    def test_content_mutation_before_sanitization_and_before_release_fails_closed(self):
        raw, provenance, _ = prepare_mixed_rows({"questions": [quantitative_row()]})
        changed = copy.deepcopy(raw)
        changed[0]["explanation"] = "Tampered teaching which the compiler never produced."
        self.assertEqual(_sanitize_questions(changed, self.request(1), compiled_candidates=provenance, compiled_output={}), [])
        output = {}
        sanitized = _sanitize_questions(raw, self.request(1), compiled_candidates=provenance, compiled_output=output)

        def solve(_system, prompt):
            data = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])
            return json.dumps({"solutions": [solver_record(data["items"][0], "4")]})

        def review_then_mutate(_system, _prompt):
            response = review(sanitized[0], difficulty=2)
            response["choiceExplanations"] = {r["choice"]: r["explanation"] for r in response.pop("choiceFeedback")}
            sanitized[0]["choiceExplanations"]["3"] = "Tampered after the independent solver completed."
            return json.dumps({"reviews": [response]})

        result = verify_questions(sanitized, self.request(1), review_then_mutate, solve=solve,
                                  solver_contract="complete_choices", choice_slots=True, audit_choice_pairs=True,
                                  compiled_questions=output)
        self.assertEqual(result, [])
        sidecar = {0: replace(output[0], learner_json=json.dumps({}))}
        with self.assertRaises(QuantitativeAuthoringError):
            sidecar[0].content()

    def test_skill_objective_metadata_remains_bound_after_compilation(self):
        payload = _request_payload(target_count=1, minimum_difficulty=2)
        payload["skillMap"] = _skill_map()
        request = _normalize_request(payload)
        skill = payload["skillMap"]["skills"][0]
        objective = skill["objectives"][0]
        row = quantitative_row(skillID=skill["id"], objectiveID=objective["id"], objective=objective["name"], topic=skill["name"])
        client = self.client([row])
        result = generation._generate_sanitized_questions(request, client, generation.ProviderCallBudget(3))
        self.assertEqual(result[0]["skillID"].lower(), skill["id"].lower())
        item = task_data(client.calls[2], "question_review_json")["items"][0]
        self.assertEqual(item["objective"], objective["name"])

    def test_two_full_passes_share_existing_six_call_and_durable_reservation_budget(self):
        first, second = quantitative_row(), quantitative_row(exact_task("3", ("4", "5", "6", "7")))
        client = self.client([first])
        client.steps.extend(self.client([second]).steps)
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "2"}):
            result = generation._generate_sanitized_questions(self.request(2), client, budget)
        self.assertEqual(len(result), 2)
        self.assertEqual(budget.calls, 6)
        self.assertEqual(reserve.call_count, 6)
        topup = task_data(client.calls[3], "generation_request_json")
        self.assertIn(result[0]["prompt"], topup["existingPrompts"])

    def test_default_mode_and_legacy_contract_remain_separate(self):
        with patch.dict(os.environ, {"QUESTION_AUTHOR_MODE": "prose"}):
            client = ScriptedNativeClient((AUTHOR, author_payload(self.prose)))
            generation._generate_provider_payload(self.request(1), client, generation.ProviderCallBudget(1))
            self.assertNotIn(MIXED_AUTHOR_CONTRACT, client.calls[0]["system"][0]["text"])
        for settings in ({"BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"},
                         {"QUESTION_AUTHOR_MODE": "unknown"}):
            with patch.dict(os.environ, settings):
                client = Mock()
                with self.assertRaises(ServiceConfigurationError):
                    generation._generate_sanitized_questions(self.request(1), client, generation.ProviderCallBudget(3))
                client.converse.assert_not_called()

    def test_default_policy_and_maximum_are_not_conflated(self):
        self.assertEqual(VERIFICATION_POLICY_REVISION, 4)
        self.assertGreaterEqual(MAX_SUPPORTED_VERIFICATION_POLICY_REVISION, 6)
        self.assertEqual(COMPILED_QUANTITATIVE_VERIFICATION_POLICY_REVISION, 6)


if __name__ == "__main__":
    unittest.main()
