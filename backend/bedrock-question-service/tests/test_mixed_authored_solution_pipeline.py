"""Compiler feedback and authored prose share real gates; no model inference."""

import copy
from dataclasses import replace
import json
import os
import unittest
from unittest.mock import Mock, patch

import question_generation as generation
from lambda_test_support import _raw_question, _request_payload
from quantitative_authoring import CompiledCandidate, LEARNER_FIELDS, MIXED_AUTHOR_CONTRACT, prepare_mixed_rows
from question_quality import _sanitize_questions
from question_teaching import AuthoredTeachingFormatError, freeze_authored_question
from service_errors import DurableProviderCallBudgetExceededError, ProviderCallBudgetExceededError, ProviderError, ServiceConfigurationError
from request_contract import _normalize_request
from test_mixed_quantitative_pipeline import prose_row
from test_native_pipeline import MODEL, ScriptedNativeClient, authored_issue_flags, solver_map, solver_record, task_data
from test_quantitative_authoring import exact_task, quantitative_row, scalar_task


def learner(question):
    return {key: question[key] for key in LEARNER_FIELDS}


class MixedAuthoredSolutionPipelineTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "QUESTION_AUTHOR_MODE": "mixed_quantitative",
            "QUESTION_FEEDBACK_CONTRACT": "authored_solution", "BEDROCK_MODEL_ID": MODEL,
            "BEDROCK_VERIFICATION_MODEL_ID": MODEL, "BEDROCK_FALLBACK_MODEL_ID": "",
            "GENERATION_ATTEMPTS": "1", "BEDROCK_CLAUDE_THINKING": "disabled",
        }))
        self.prose = _raw_question("Which conclusion follows from these stated conditions?")
        self.prose["explanation"] = "  The stated conditions establish this result.\r\nThey supply every needed premise.  "

    def request(self, count):
        raw = _request_payload(target_count=count, minimum_difficulty=2)
        raw["goal"].update(title="Arithmetic and reasoning", contentTopics=["Arithmetic", "Reasoning"])
        return _normalize_request(raw)

    def client(self, rows, *, solver_count=None, solver_reject=(), review_change=None, pair_change=None):
        prepared, compiled, _ = prepare_mixed_rows({"questions": rows})
        by_prompt = {item["prompt"]: item for item in prepared if item}
        compiled_prompts = {value.content()["prompt"] for value in compiled.values()}
        solver_count = solver_count if solver_count is not None else len(set(by_prompt) - compiled_prompts)
        audit_count = len(compiled_prompts) + (0 if pair_change else solver_count - len(solver_reject))

        def solve(request):
            data = task_data(request, "question_solution_json")
            self.assertEqual(len(data["items"]), solver_count)
            for forbidden in ("expectedAnswer", "explanation", "choiceExplanations", "difficulty", "learner_json", "spec_json"):
                self.assertNotIn(forbidden, json.dumps(data))
            records = []
            for item in data["items"]:
                record = solver_record(item, by_prompt[item["prompt"]]["expectedAnswer"])
                if item["index"] in solver_reject:
                    for choice in record["choices"].values():
                        choice["judgment"] = "refuted"
                if pair_change:
                    pair_change(record)
                records.append(record)
            return solver_map(*records)

        def audit(request):
            data = task_data(request, "question_review_json")
            self.assertNotIn("independentSolutions", data)
            self.assertEqual([item["index"] for item in data["items"]], list(range(len(data["items"]))))
            reviews = {}
            for item in data["items"]:
                question = by_prompt[item["prompt"]]
                for forbidden in ("expectedAnswer", "difficulty", "choiceExplanations", "learner_json", "spec_json"):
                    self.assertNotIn(forbidden, item)
                self.assertEqual(item["explanation"].encode(), question["explanation"].encode())
                record = {"valid": True, "answer": question["expectedAnswer"], "difficulty": 2,
                          "explanationSupport": "supported", "issueFlags": authored_issue_flags()}
                if review_change:
                    review_change(record, item)
                reviews[str(item["index"])] = record
            return {"reviews": reviews}

        steps = [(MIXED_AUTHOR_CONTRACT, {"questions": rows})]
        if solver_count:
            steps.append((f"complete_choice_solver_v5_n{solver_count}", solve))
        if audit_count:
            steps.append((f"authored_solution_reviewer_v3_n{audit_count}", audit))
        return ScriptedNativeClient(*steps)

    def run_pipeline(self, rows, **kwargs):
        client = self.client(rows, **kwargs)
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        self.last_metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        result = generation._generate_sanitized_questions(self.request(len(rows)), client, budget, self.last_metrics)
        self.assertEqual(self.last_metrics["ProviderCalls"], budget.calls)
        self.assertEqual(len(self.last_metrics["ProviderObservations"]), len(client.calls))
        for observation, call in zip(self.last_metrics["ProviderObservations"], client.calls, strict=True):
            schema = call["outputConfig"]["textFormat"]["structure"]["jsonSchema"]
            self.assertEqual(observation["structuredOutput"]["name"], schema["name"])
            if schema["name"].startswith("authored_solution_reviewer_v3_n"):
                self.assertEqual(observation["structuredOutput"]["version"], "3")
        self.assertEqual(reserve.call_count, budget.calls)
        return result, client, budget

    def test_five_compiled_items_use_author_and_audit_only_but_preflight_remains_conservative(self):
        rows = [quantitative_row(exact_task(str(n), tuple(str(v) for v in (2*n, 2*n+1, 2*n+2, 2*n+3))))
                for n in range(2, 7)]
        result, client, budget = self.run_pipeline(rows)
        self.assertEqual((len(result), len(client.calls), budget.calls), (5, 2, 2))
        self.assertEqual([learner(q) for q in result], [CompiledCandidate.from_task(row["task"]).content() for row in rows])
        self.assertTrue(all(q["verificationPolicyRevision"] == 8 for q in result))
        reserve, client = Mock(), Mock()
        # Before the author runs, its variant mix is unknown and may need three stages.
        with self.assertRaises(ProviderCallBudgetExceededError):
            generation._generate_sanitized_questions(
                self.request(5), client, generation.ProviderCallBudget(2, reserve_call=reserve))
        reserve.assert_not_called()
        client.converse.assert_not_called()

    def test_compiled_five_fields_and_prose_main_remain_exact_after_three_stages(self):
        rows = [quantitative_row(), prose_row(self.prose)]
        before = copy.deepcopy(rows)
        result, _, budget = self.run_pipeline(rows)
        self.assertEqual(rows, before)
        self.assertEqual(learner(result[0]), CompiledCandidate.from_task(rows[0]["task"]).content())
        self.assertEqual(result[0]["verificationPolicyRevision"], 8)
        self.assertEqual(result[1]["explanation"].encode(), self.prose["explanation"].encode())
        self.assertEqual(result[1]["choiceExplanations"], {})
        self.assertEqual(result[1]["verificationPolicyRevision"], 7)
        self.assertEqual(budget.calls, 3)
        for question in result:
            self.assertFalse(set(question) & {"compiled", "task", "spec_json", "learner_json", "provenance"})

    def test_interleaved_invalid_duplicate_freeze_and_solver_drops_keep_source_sidecars(self):
        first = quantitative_row()
        rejected = prose_row({**self.prose, "prompt": "This prose candidate is rejected by the independent solver."})
        last = quantitative_row(exact_task("4", ("5", "6", "7", "8")))
        oversized = {**self.prose, "prompt": "An oversized explanation must be rejected before solver input.", "explanation": "x" * 421}
        ordinal = {**self.prose, "prompt": "A shuffled display position must be rejected before solver input.",
                   "explanation": "Only the first choice follows from these supplied facts."}
        vetoed = {**self.prose, "prompt": "This distinct prose candidate reaches the audit and is rejected there."}
        rows = [quantitative_row(scalar_task(False)), prose_row(oversized), first, copy.deepcopy(first),
                prose_row(ordinal), prose_row(self.prose), rejected, last, prose_row(vetoed)]
        def veto(record, item):
            if item["prompt"] == vetoed["prompt"]:
                record["valid"] = False
        result, client, budget = self.run_pipeline(rows, solver_count=3, solver_reject=(1,), review_change=veto)
        self.assertEqual([q["prompt"] for q in result], [CompiledCandidate.from_task(first["task"]).content()["prompt"],
                                                       self.prose["prompt"], CompiledCandidate.from_task(last["task"]).content()["prompt"]])
        for output, original in ((result[0], first), (result[2], last)):
            self.assertEqual(learner(output), CompiledCandidate.from_task(original["task"]).content())
            self.assertEqual(output["verificationPolicyRevision"], 8)
        self.assertEqual(result[1]["verificationPolicyRevision"], 7)
        self.assertEqual(result[1]["choiceExplanations"], {})
        self.assertEqual(len(task_data(client.calls[2], "question_review_json")["items"]), 4)
        self.assertEqual(budget.calls, 3)

    def test_tampered_compiled_fields_or_fake_sidecars_cannot_enter_frozen_teaching(self):
        raw, sidecars, _ = prepare_mixed_rows({"questions": [quantitative_row()]})
        for field in LEARNER_FIELDS:
            changed = copy.deepcopy(raw[0])
            if field == "choices":
                changed[field] = list(reversed(changed[field]))
            elif field == "choiceExplanations":
                changed[field][changed["choices"][0]] = "Invented feedback that the compiler never generated."
            else:
                changed[field] += " changed"
            with self.subTest(field=field):
                self.assertEqual(_sanitize_questions([changed], self.request(1), preserve_authored_explanation=True,
                                                    compiled_candidates=sidecars, compiled_output={}), [])
                with self.assertRaises(AuthoredTeachingFormatError):
                    freeze_authored_question(changed, compiled_candidate=sidecars[0])
        impostors = ({}, True, Mock(), replace(sidecars[0], learner_json="{}"),
                     CompiledCandidate.from_task(exact_task("3", ("4", "5", "6", "7"))))
        for impostor in impostors:
            with self.subTest(kind=type(impostor).__name__), self.assertRaises(AuthoredTeachingFormatError):
                freeze_authored_question(raw[0], compiled_candidate=impostor)
        with self.assertRaises(AuthoredTeachingFormatError):
            freeze_authored_question(raw[0])

    def test_frozen_compiler_content_is_deep_copied_without_losing_any_feedback(self):
        raw, sidecars, _ = prepare_mixed_rows({"questions": [quantitative_row()]})
        frozen = freeze_authored_question(raw[0], compiled_candidate=sidecars[0])
        raw[0]["choices"][0] = "tampered"
        raw[0]["choiceExplanations"].clear()
        self.assertEqual(learner(frozen), sidecars[0].content())

    def test_provider_cannot_supply_feedback_or_provenance_for_either_variant(self):
        for quantitative in (False, True):
            for field in ("choiceExplanations", "compiled", "verificationPolicyRevision", "provenance"):
                row = quantitative_row() if quantitative else prose_row(self.prose)
                target = row if quantitative else row["question"]
                target[field] = {"forged": "compiler"}
                client = ScriptedNativeClient((MIXED_AUTHOR_CONTRACT, {"questions": [row]}))
                with self.subTest(quantitative=quantitative, field=field), self.assertRaises(ProviderError):
                    generation._generate_sanitized_questions(self.request(1), client, generation.ProviderCallBudget(3))
                self.assertEqual(len(client.calls), 1)
        forged = {**self.prose, "choiceExplanations": {self.prose["choices"][0]: "Invented model feedback."},
                  "compiled": True, "verificationPolicyRevision": 6}
        self.assertEqual(_sanitize_questions([forged], self.request(1), preserve_authored_explanation=True), [])

    def test_all_audit_vetoes_apply_to_compiled_and_prose_without_replacement(self):
        for quantitative in (False, True):
            row = quantitative_row() if quantitative else prose_row(self.prose)
            for change in ({"valid": False}, {"answer": ""}, {"difficulty": 1}, {"explanationSupport": "unsupported"},
                           {"explanationSupport": "uncertain"}, *({"issueFlags": authored_issue_flags(flag)} for flag in authored_issue_flags())):
                def veto(record, _item):
                    record.update(change)
                    if "answer" in change:
                        record["answer"] = "3" if quantitative else self.prose["choices"][1]
                with self.subTest(quantitative=quantitative, change=change):
                    result, _, budget = self.run_pipeline([row], review_change=veto)
                    self.assertEqual(result, [])
                    self.assertEqual(budget.calls, 2 if quantitative else 3)
                    if "issueFlags" in change:
                        self.assertEqual(self.last_metrics["QuestionQuality"]["review"]["reported_issues"], 1)
            def replace_feedback(record, _item):
                record["explanation"] = "An unauthorized replacement from the final auditor."
            with self.assertRaises(ProviderError):
                self.run_pipeline([row], review_change=replace_feedback)

    def test_malformed_flags_fail_the_native_stage_with_diagnostics(self):
        for flags in ({}, {**authored_issue_flags(), "novelty": "false"}, {**authored_issue_flags(), "extra": False}):
            for quantitative in (False, True):
                row = quantitative_row() if quantitative else prose_row(self.prose)
                with self.subTest(flags=flags, quantitative=quantitative), self.assertRaises(ProviderError):
                    self.run_pipeline([row], review_change=lambda record, _item: record.update(issueFlags=flags))
                self.assertEqual(self.last_metrics["ProviderCalls"], 2 if quantitative else 3)
                self.assertEqual(self.last_metrics["QuestionQuality"]["provider"]["native_contract_invalid"], 1)
                self.assertEqual(self.last_metrics["ProviderObservations"][-1]["structuredOutput"]["name"],
                                 "authored_solution_reviewer_v3_n1")

    def test_every_prose_pair_veto_preserves_only_independently_proved_compiled_rows(self):
        for relation in ("equivalent", "uncertain"):
            for pair in ("ab", "ac", "ad", "bc", "bd", "cd"):
                with self.subTest(relation=relation, pair=pair):
                    result, client, budget = self.run_pipeline(
                        [quantitative_row(), prose_row(self.prose)],
                        pair_change=lambda record: record["choicePairs"][pair].update(relation=relation))
                    self.assertEqual(len(result), 1)
                    self.assertEqual(result[0]["verificationPolicyRevision"], 8)
                    self.assertEqual(learner(result[0]), CompiledCandidate.from_task(exact_task()).content())
                    self.assertEqual((len(client.calls), budget.calls), (3, 3))

    def test_partial_topup_preserves_each_mode_and_conservative_three_call_preflight(self):
        client = self.client([quantitative_row()])
        client.steps.extend(self.client([prose_row(self.prose)]).steps)
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "5"}):
            result = generation._generate_sanitized_questions(self.request(3), client, budget)
        self.assertEqual([q["verificationPolicyRevision"] for q in result], [8, 7])
        self.assertEqual(learner(result[0]), CompiledCandidate.from_task(exact_task()).content())
        self.assertEqual(result[1]["explanation"], self.prose["explanation"])
        self.assertEqual((len(client.calls), budget.calls, reserve.call_count), (5, 5, 5))
        topup = task_data(client.calls[2], "generation_request_json")
        self.assertEqual(topup["targetCount"], 2)
        self.assertIn(result[0]["prompt"], topup["existingPrompts"])

    def test_failed_topup_retains_partial_but_durable_refusal_still_propagates(self):
        client = self.client([quantitative_row()])
        client.steps.append((MIXED_AUTHOR_CONTRACT, RuntimeError("synthetic transport failure")))
        budget = generation.ProviderCallBudget(6)
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "2"}):
            result = generation._generate_sanitized_questions(self.request(2), client, budget)
        self.assertEqual(len(result), 1)
        self.assertEqual(learner(result[0]), CompiledCandidate.from_task(exact_task()).content())
        self.assertEqual(budget.calls, 3)
        client = self.client([quantitative_row()])
        reserve = Mock(side_effect=[None, None, DurableProviderCallBudgetExceededError("synthetic durable refusal")])
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "2"}), self.assertRaises(DurableProviderCallBudgetExceededError):
            generation._generate_sanitized_questions(self.request(2), client, generation.ProviderCallBudget(6, reserve_call=reserve))
        self.assertEqual((len(client.calls), reserve.call_count), (2, 3))

    def test_deadline_expiring_after_first_pass_retains_partial_without_new_reservation(self):
        client = self.client([quantitative_row()])
        context = Mock()
        context.get_remaining_time_in_millis.side_effect = lambda: 240_000 if len(client.calls) < 2 else 0
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, context=context, reserve_call=reserve)
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "2"}):
            result = generation._generate_sanitized_questions(self.request(2), client, budget)
        self.assertEqual(learner(result[0]), CompiledCandidate.from_task(exact_task()).content())
        self.assertEqual((len(client.calls), budget.calls, reserve.call_count), (2, 2, 2))

    def test_all_invalid_candidates_stop_after_author_without_minting_approval(self):
        oversized = {**self.prose, "explanation": "x" * 421}
        client = ScriptedNativeClient((MIXED_AUTHOR_CONTRACT, {
            "questions": [quantitative_row(scalar_task(False)), prose_row(oversized)]}))
        budget = generation.ProviderCallBudget(3)
        self.assertEqual(generation._generate_sanitized_questions(self.request(2), client, budget), [])
        self.assertEqual((len(client.calls), budget.calls), (1, 1))

    def test_legacy_combination_remains_invalid_before_provider_or_reservation(self):
        reserve, client = Mock(), Mock()
        with patch.dict(os.environ, {"BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"}), self.assertRaises(ServiceConfigurationError):
            generation._generate_sanitized_questions(self.request(1), client, generation.ProviderCallBudget(6, reserve_call=reserve))
        reserve.assert_not_called()
        client.converse.assert_not_called()


if __name__ == "__main__":
    unittest.main()
