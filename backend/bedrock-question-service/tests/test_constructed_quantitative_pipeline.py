"""Task-only native authoring reaches existing proof/audit gates; no inference."""

import copy
import hashlib
import json
import os
from typing import get_args
import unittest
from unittest.mock import Mock, patch

import native_output_contracts as native
import quantitative_authoring as author
import question_generation as generation
from lambda_test_support import _raw_question, _request_payload
from quantitative_choice_construction import construct_quantitative_spec
from quantitative_task_compiler import compile_question
from question_teaching import AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT
from request_contract import _normalize_request
from service_errors import DurableProviderCallBudgetExceededError, ProviderError, ServiceConfigurationError
from test_mixed_quantitative_pipeline import prose_row
from test_native_pipeline import MODEL, ScriptedNativeClient, authored_issue_flags, solver_map, solver_record, task_data
from test_quantitative_authoring import exact_task, quantitative_row, scalar_task
from verification_policy import VERIFICATION_POLICY_REVISION


CONTRACT = author.CONSTRUCTED_AUTHOR_CONTRACT


def task(left="8", right="3"):
    return {"kind": "exact_value", "unit": "unitless", "nodes": [
        {"kind": "literal", "value": left}, {"kind": "literal", "value": right},
        {"kind": "binary", "op": "sub", "left": 0, "right": 1}], "root": 2}


def row(spec=None):
    return quantitative_row(spec or task())


def learner(question):
    return {key: question[key] for key in author.LEARNER_FIELDS}


class ConstructedQuantitativePipelineTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "QUESTION_AUTHOR_MODE": "constructed_quantitative",
            "QUESTION_FEEDBACK_CONTRACT": "authored_solution", "BEDROCK_MODEL_ID": MODEL,
            "BEDROCK_VERIFICATION_MODEL_ID": MODEL, "BEDROCK_FALLBACK_MODEL_ID": "",
            "BEDROCK_CLAUDE_THINKING": "disabled", "GENERATION_ATTEMPTS": "1",
        }))
        self.prose = _raw_question("Which conclusion follows from the supplied premises?")
        self.prose["explanation"] = "  These conditions establish the stated result.\r\nThe supplied rule applies here.  "

    def request(self, count):
        raw = _request_payload(target_count=count, minimum_difficulty=2)
        raw["goal"].update(title="Arithmetic and reasoning", contentTopics=["Arithmetic", "Reasoning"])
        return _normalize_request(raw)

    def client(self, rows, *, solver_count=0, audit_count=None, reject=(), audit_change=None):
        prepared, compiled, _ = author.prepare_mixed_rows({"questions": rows}, construct_choices=True)
        originals = {q["prompt"]: q for q in prepared if q}
        audit_count = len(compiled) + solver_count - len(reject) if audit_count is None else audit_count

        def solve(request):
            data = task_data(request, "question_solution_json")
            self.assertEqual(len(data["items"]), solver_count)
            for field in ("expectedAnswer", "explanation", "difficulty", "spec_json", "learner_json"):
                self.assertNotIn(field, json.dumps(data))
            records = []
            for item in data["items"]:
                solution = solver_record(item, originals[item["prompt"]]["expectedAnswer"])
                if item["index"] in reject:
                    for choice in solution["choices"].values():
                        choice["judgment"] = "refuted"
                records.append(solution)
            return solver_map(*reversed(records))

        def audit(request):
            data = task_data(request, "question_review_json")
            self.assertEqual([q["index"] for q in data["items"]], list(range(audit_count)))
            self.assertNotIn("independentSolutions", data)
            reviews = {}
            for item in reversed(data["items"]):
                original = originals[item["prompt"]]
                self.assertEqual(item["explanation"].encode(), original["explanation"].encode())
                for hidden in ("expectedAnswer", "difficulty", "choiceExplanations", "spec_json", "learner_json"):
                    self.assertNotIn(hidden, item)
                review = {"valid": True, "answer": original["expectedAnswer"], "difficulty": 2,
                          "explanationSupport": "supported", "issueFlags": authored_issue_flags()}
                if audit_change:
                    audit_change(review, item)
                reviews[str(item["index"])] = review
            return {"reviews": reviews}

        steps = [(CONTRACT, {"questions": rows})]
        if solver_count:
            steps.append((f"complete_choice_solver_v5_n{solver_count}", solve))
        if audit_count:
            steps.append((f"authored_solution_reviewer_v3_n{audit_count}", audit))
        return ScriptedNativeClient(*steps)

    def run_pipeline(self, rows, **kwargs):
        client = self.client(rows, **kwargs)
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        result = generation._generate_sanitized_questions(self.request(len(rows)), client, budget, metrics)
        self.assertEqual((budget.calls, reserve.call_count, metrics["ProviderCalls"]), (len(client.calls),) * 3)
        self.assertEqual(metrics["ProviderObservations"][0]["structuredOutput"]["name"], CONTRACT)
        return result, client, budget, metrics

    def test_task_only_native_author_produces_five_exact_compiled_items_in_two_calls(self):
        rows = [row(task(str(value))) for value in range(8, 13)]
        original = copy.deepcopy(rows)
        result, client, budget, _ = self.run_pipeline(rows)
        self.assertEqual((len(result), budget.calls), (5, 2))
        prepared, sidecars, _ = author.prepare_mixed_rows({"questions": rows}, construct_choices=True)
        self.assertEqual([learner(q) for q in result], [sidecars[i].content() for i in range(5)])
        self.assertEqual([learner(q) for q in result], [learner(q) for q in prepared])
        self.assertTrue(all(q["verificationPolicyRevision"] == 8 for q in result))
        self.assertEqual(rows, original)
        self.assertEqual(VERIFICATION_POLICY_REVISION, 4)
        self.assertNotIn('"choices"', json.dumps(rows))
        self.assertIn("Code constructs quantitative choices", client.calls[0]["system"][0]["text"])
        self.assertNotIn('"expectedAnswer"', client.calls[0]["system"][0]["text"])

    def test_placeholders_only_validate_graph_and_never_enter_constructor_or_provenance(self):
        seen = []
        def construct(spec):
            seen.append(copy.deepcopy(spec))
            self.assertNotIn("choices", spec)
            return construct_quantitative_spec(spec)
        with patch.object(author, "construct_quantitative_spec", side_effect=construct):
            questions, sidecars, failures = author.prepare_mixed_rows({"questions": [row()]}, construct_choices=True)
        self.assertEqual(failures, [])
        self.assertEqual(seen, [{"kind": "exact_value", "unit": "unitless", "expression": {
            "op": "sub", "left": {"value": "8"}, "right": {"value": "3"}}}])
        spec = json.loads(sidecars[0].spec_json)
        self.assertEqual(learner(questions[0]), compile_question(spec))
        self.assertEqual(spec, construct_quantitative_spec(seen[0]))
        self.assertNotEqual(set(spec["choices"]), {"0", "1", "2", "3"})

    def test_integer_domain_choices_satisfy_the_literal_selection_without_hidden_restrictions(self):
        for selection in ("any_satisfying", "minimum", "maximum"):
            scalar = scalar_task(nonnegative=False)
            scalar.pop("choices")
            scalar["selection"] = selection
            result, _, budget, _ = self.run_pipeline([row(scalar)])
            self.assertEqual(budget.calls, 2)
            self.assertEqual(len(result), 1)
            offered = [int(value) for value in result[0]["choices"]]
            expected = 7 if selection == "maximum" else -7
            self.assertEqual(int(result[0]["expectedAnswer"]), expected)
            self.assertTrue(all(-10 <= value <= 10 for value in offered))
            if selection == "any_satisfying":
                self.assertEqual([value for value in offered if value * value == 49], [expected])

    def test_supplied_choices_offered_domains_feedback_flags_and_foreign_fields_fail_native_author(self):
        bad_tasks = [exact_task(), {**task(), "expectedAnswer": "5"}, {**task(), "root": True}]
        offered = scalar_task()
        offered.pop("choices")
        offered["domain"] = {"kind": "offered"}
        bad_tasks.append(offered)
        bad_rows = [row(value) for value in bad_tasks]
        bad_rows.extend({**row(), field: "model supplied"} for field in ("choices", "explanation", "verificationPolicyRevision", "compiled"))
        for value in bad_rows:
            client = ScriptedNativeClient((CONTRACT, {"questions": [value]}))
            with self.subTest(row=value), self.assertRaises(ProviderError):
                generation._generate_sanitized_questions(self.request(1), client, generation.ProviderCallBudget(3))
            self.assertEqual(len(client.calls), 1)

    def test_invalid_graph_and_insufficient_pool_reject_without_repair_or_final_audit(self):
        forward = task()
        forward["nodes"][2]["right"] = 3
        unused = task()
        unused["nodes"].append({"kind": "literal", "value": "7"})
        leaf = {"kind": "exact_value", "unit": "unitless", "nodes": [{"kind": "literal", "value": "7"}], "root": 0}
        rows = [row(forward), row(unused), row(leaf)]
        result, _, budget, metrics = self.run_pipeline(rows)
        self.assertEqual(result, [])
        self.assertEqual(budget.calls, 1)
        self.assertEqual(metrics["QuestionQuality"]["compile"]["invalid_spec"], 2)
        self.assertEqual(metrics["QuestionQuality"]["compile"]["insufficient_distractors"], 1)

    def test_insufficient_pool_diagnostic_preserves_valid_sibling_with_real_metrics(self):
        insufficient = {"kind": "exact_value", "unit": "unitless", "nodes": [{"kind": "literal", "value": "7"}], "root": 0}
        result, _, budget, metrics = self.run_pipeline([row(insufficient), row()])
        self.assertEqual((len(result), budget.calls), (1, 2))
        self.assertEqual(result[0]["verificationPolicyRevision"], 8)
        self.assertEqual(metrics["QuestionQuality"]["compile"]["insufficient_distractors"], 1)
        self.assertEqual(metrics["QuestionQuality"]["compile"]["accepted"], 1)

    def test_interleaved_rejections_and_duplicates_preserve_dense_prose_and_compiler_sources(self):
        malformed = task()
        malformed["nodes"][2]["left"] = 99
        rejected = {**self.prose, "prompt": "This separate prose candidate is rejected by the solver."}
        rows = [row(malformed), row(), prose_row(rejected), copy.deepcopy(row()), prose_row(self.prose), row(task("12"))]
        result, client, budget, _ = self.run_pipeline(rows, solver_count=2, reject=(0,), audit_count=3)
        self.assertEqual((len(result), budget.calls), (3, 3))
        self.assertEqual([q["verificationPolicyRevision"] for q in result], [8, 7, 8])
        self.assertEqual(result[1]["explanation"].encode(), self.prose["explanation"].encode())
        self.assertEqual(result[1]["choiceExplanations"], {})
        _, sidecars, _ = author.prepare_mixed_rows({"questions": [rows[1], rows[5]]}, construct_choices=True)
        self.assertEqual([learner(result[i]) for i in (0, 2)], [sidecars[i].content() for i in (0, 1)])
        self.assertEqual(len(task_data(client.calls[1], "question_solution_json")["items"]), 2)
        self.assertEqual(len(task_data(client.calls[2], "question_review_json")["items"]), 3)

    def test_final_vetoes_and_replacement_prohibition_still_apply_to_constructed_content(self):
        for change in ({"valid": False}, {"explanationSupport": "unsupported"}, {"explanationSupport": "uncertain"},
                       {"difficulty": 1}, {"answer": "not the exact key"},
                       *({"issueFlags": authored_issue_flags(flag)} for flag in authored_issue_flags())):
            with self.subTest(change=change):
                result, _, budget, _ = self.run_pipeline([row()], audit_change=lambda review, _: review.update(change))
                self.assertEqual((result, budget.calls), ([], 2))
        with self.assertRaises(ProviderError):
            self.run_pipeline([row()], audit_change=lambda review, _: review.update(explanation="Replacement teaching"))

    def test_preflight_rejects_legacy_or_mutable_feedback_before_provider_or_reservation(self):
        for mode, feedback in (("legacy", "authored_solution"), ("native", "reviewer_written")):
            client, reserve = Mock(), Mock()
            with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": mode, "QUESTION_FEEDBACK_CONTRACT": feedback}), self.assertRaises(ServiceConfigurationError):
                generation._generate_sanitized_questions(self.request(1), client, generation.ProviderCallBudget(6, reserve_call=reserve))
            client.converse.assert_not_called()
            reserve.assert_not_called()

    def test_partial_topup_preserves_compiled_then_prose_and_durable_refusal_propagates(self):
        client = self.client([row()])
        client.steps.extend(self.client([prose_row(self.prose)], solver_count=1).steps)
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "3"}):
            result = generation._generate_sanitized_questions(self.request(3), client, budget)
        self.assertEqual([q["verificationPolicyRevision"] for q in result], [8, 7])
        self.assertEqual((budget.calls, reserve.call_count), (5, 5))
        self.assertIn(result[0]["prompt"], task_data(client.calls[2], "generation_request_json")["existingPrompts"])
        client = self.client([row()])
        reserve = Mock(side_effect=[None, None, DurableProviderCallBudgetExceededError("synthetic refusal")])
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "2"}), self.assertRaises(DurableProviderCallBudgetExceededError):
            generation._generate_sanitized_questions(self.request(2), client, generation.ProviderCallBudget(6, reserve_call=reserve))
        self.assertEqual((len(client.calls), reserve.call_count), (2, 3))

    def test_new_schema_keeps_ordered_prose_and_expands_to_the_same_closed_local_shape(self):
        schema = json.loads(native.native_output_config(CONTRACT)["textFormat"]["structure"]["jsonSchema"]["schema"])
        prose = json.loads(native.native_output_config("question_author_v3")["textFormat"]["structure"]["jsonSchema"]["schema"])
        self.assertEqual(json.dumps(schema["$defs"]["proseQuestion"]), json.dumps(prose["properties"]["questions"]["items"]))
        def expand(value):
            if isinstance(value, list):
                return [expand(child) for child in value]
            if not isinstance(value, dict):
                return value
            if "$ref" in value:
                return expand(schema["$defs"][value["$ref"].split("/")[-1]])
            return {key: expand(child) for key, child in value.items() if key != "$defs"}
        self.assertEqual(expand(schema), native._contract_schema(CONTRACT))
        for variant in schema["$defs"]["task"]["anyOf"]:
            self.assertNotIn("choices", variant["properties"])
            self.assertNotIn("choices", variant["required"])
        self.assertEqual(schema["$defs"]["task"]["anyOf"][1]["properties"]["domain"]["properties"]["kind"]["enum"], ["integer_interval"])
        valid = json.dumps({"questions": [row()]})
        for raw in (valid.replace('"root": 2', '"root": 2,"root": 1'), valid.replace('"root": 2', '"root": NaN')):
            with self.assertRaises(ProviderError):
                native.adapt_native_response(raw, CONTRACT)

    def test_all_171_historical_schemas_metadata_and_prompts_are_byte_identical(self):
        contracts = (*(c for c in get_args(native.Contract) if c != CONTRACT),
                     *(kind(count) for kind in (native.ReviewerSlotContract, native.SolverSlotContract,
                                                native.AuthoredSolutionReviewContract, native.AuthoredSolutionFlagReviewContract)
                       for count in range(1, 41)))
        values = [(native.contract_metadata(c), native.native_output_config(c), native.native_prompt(AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT, c)) for c in contracts]
        self.assertEqual(len(contracts), 171)
        self.assertEqual(hashlib.sha256(json.dumps(values, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest(),
                         "46684d3eb35884db8a165d0aef648b8afa9bbc8b37c8874238369642d5975ce9")


if __name__ == "__main__":
    unittest.main()
