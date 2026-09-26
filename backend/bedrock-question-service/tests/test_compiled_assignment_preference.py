"""Compiled preference changes local selection, never proof or release gates."""

import copy
from dataclasses import replace
import os
import socket
import unittest
from unittest.mock import Mock, patch

import boto3
import question_generation as generation
from lambda_test_support import _raw_question, _request_payload, _skill_map
from quantitative_authoring import (
    CONSTRUCTED_AUTHOR_CONTRACT, LEARNER_FIELDS, MIXED_AUTHOR_CONTRACT,
    QuantitativeAuthoringError, prepare_mixed_rows,
)
from question_quality import _sanitize_questions
from request_contract import _normalize_request
from service_errors import ProviderDeadlineExceededError
from test_constructed_quantitative_pipeline import row, task
from test_mixed_quantitative_pipeline import prose_row
from test_native_pipeline import MODEL, ScriptedNativeClient, authored_issue_flags, solver_map, solver_record, task_data
from test_quantitative_authoring import exact_task, quantitative_row


def learner(question):
    return {field: question[field] for field in LEARNER_FIELDS}


class CompiledAssignmentPreferenceTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "QUESTION_AUTHOR_MODE": "constructed_quantitative",
            "QUESTION_FEEDBACK_CONTRACT": "authored_solution", "BEDROCK_MODEL_ID": MODEL,
            "BEDROCK_VERIFICATION_MODEL_ID": MODEL, "BEDROCK_FALLBACK_MODEL_ID": "",
            "BEDROCK_CLAUDE_THINKING": "disabled", "GENERATION_ATTEMPTS": "1",
        }))
        for owner, name in ((socket.socket, "connect"), (boto3, "client"), (boto3.session.Session, "client")):
            self.enterContext(patch.object(owner, name, side_effect=AssertionError("No provider access")))
        raw = _request_payload(target_count=8, minimum_difficulty=2)
        raw["goal"].update(title="Arithmetic and reasoning", contentTopics=["Arithmetic", "Reasoning"])
        self.request = _normalize_request(raw)
        self.prose = _raw_question("Which conclusion follows from the supplied complete rule?", difficulty=2)

    def prepared(self, rows):
        prepared, sidecars, failures = prepare_mixed_rows({"questions": rows}, construct_choices=True)
        self.assertEqual(failures, [])
        return prepared, sidecars

    def sanitize(self, rows, sidecars, *, target=None, request=None, prefer=True):
        request = copy.deepcopy(request or self.request)
        if target is not None:
            request["targetCount"] = target
        output, metrics = {}, {}
        result = _sanitize_questions(rows, request, metrics, preserve_authored_explanation=True,
                                     compiled_candidates=sidecars, compiled_output=output,
                                     prefer_compiled_within_assignment=prefer)
        return result, output, metrics

    def mapped_request(self):
        request = copy.deepcopy(self.request)
        request["skillMap"] = _skill_map()
        a, b = request["skillMap"]["skills"]
        a["objectives"].append({"id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc", "name": "Apply a second stated rule"})
        request["requestedSkillAllocation"] = {a["id"]: 4, b["id"]: 2}
        request["requestedObjectiveAllocation"] = [
            {"skillID": skill["id"], "objectiveID": objective["id"], "count": 2}
            for skill in (a, b) for objective in skill["objectives"]
        ]
        return request

    def tag(self, question, request, skill_index=0, objective_index=0):
        skill = request["skillMap"]["skills"][skill_index]
        objective = skill["objectives"][objective_index]
        question.update(topic=skill["name"], skillID=skill["id"], objectiveID=objective["id"], objective=objective["name"])

    def test_same_bucket_both_orders_select_exact_compiled_fields_without_mutation(self):
        for reverse in (False, True):
            raw = [prose_row(self.prose), row()]
            if reverse:
                raw.reverse()
            rows, sidecars = self.prepared(raw)
            before = copy.deepcopy((rows, sidecars, self.request))
            result, output, metrics = self.sanitize(rows, sidecars, target=1)
            source = next(iter(sidecars))
            self.assertEqual([learner(q) for q in result], [sidecars[source].content()])
            self.assertIs(output[0], sidecars[source])
            self.assertEqual(metrics["QuestionQuality"]["sanitize"], {"accepted": 1, "surplus": 1})
            self.assertEqual((rows, sidecars, self.request), before)

    def test_stable_partition_keeps_every_skill_objective_position_and_tie_order(self):
        request = self.mapped_request()
        rows, sidecars = self.prepared([
            prose_row(_raw_question(f"Stated premises for scenario {i}. Which conclusion follows?", difficulty=2))
            for i in range(3)
        ] + [row(task(str(n))) for n in (8, 10, 12)])
        tags = [(0, 0), (1, 0), (0, 1)] * 2
        for question, (skill, objective) in zip(rows, tags, strict=True):
            self.tag(question, request, skill, objective)
        result, output, _ = self.sanitize(rows, sidecars, request=request)
        expected = [3, 4, 5, 0, 1, 2]
        self.assertEqual([q["prompt"] for q in result], [rows[i]["prompt"] for i in expected])
        self.assertEqual([(q["skillID"], q["objectiveID"]) for q in result],
                         [(q["skillID"], q["objectiveID"]) for q in rows])
        self.assertEqual(output, {i: sidecars[i + 3] for i in range(3)})
        # A second compiled candidate stays after the first: preference is stable.
        rows, sidecars = self.prepared([row(), prose_row(self.prose), row(task("12"))])
        result, _, _ = self.sanitize(rows, sidecars)
        self.assertEqual([q["prompt"] for q in result], [rows[i]["prompt"] for i in (0, 2, 1)])

    def test_objective_quota_unknown_tag_and_raw_holes_keep_dense_sidecar_alignment(self):
        request = self.mapped_request()
        request["requestedObjectiveAllocation"][1]["count"] = 0
        request["requestedObjectiveAllocation"].pop(1)
        request["requestedSkillAllocation"][request["skillMap"]["skills"][0]["id"]] = 2
        rows, sidecars = self.prepared([prose_row(self.prose), row(), row(task("10")), row(task("12"))])
        self.tag(rows[0], request, 0, 0)
        self.tag(rows[1], request, 0, 1)  # Supplied objective, no requested slots.
        self.tag(rows[2], request, 0, 0)
        rows[3].update(skillID="unknown", objectiveID="unknown")
        rows.insert(1, None)
        sidecars = {i + 1: value for i, value in sidecars.items()}
        result, output, metrics = self.sanitize(rows, sidecars, request=request)
        self.assertEqual([q["prompt"] for q in result], [rows[i]["prompt"] for i in (3, 0)])
        self.assertEqual(output, {0: sidecars[3]})
        self.assertEqual(metrics["QuestionQuality"]["sanitize"],
                         {"accepted": 2, "invalid_item": 1, "objective_quota": 1, "invalid_skill": 1})

    def test_target_cap_does_not_cross_an_earlier_different_bucket(self):
        request = self.mapped_request()
        request["requestedSkillAllocation"] = {key: 1 for key in request["requestedSkillAllocation"]}
        request["requestedObjectiveAllocation"] = [
            {**request["requestedObjectiveAllocation"][i], "count": 1} for i in (0, 2)
        ]
        rows, sidecars = self.prepared([prose_row(self.prose), prose_row(_raw_question(
            "A second supplied rule applies here. Which conclusion follows?", difficulty=2)), row()])
        self.tag(rows[0], request, 1, 0)
        self.tag(rows[1], request, 0, 0)
        self.tag(rows[2], request, 0, 0)
        result, output, _ = self.sanitize(rows, sidecars, target=2, request=request)
        self.assertEqual(result[0]["prompt"], self.prose["prompt"])
        self.assertEqual(result[1]["prompt"], rows[2]["prompt"])
        self.assertEqual(output, {1: sidecars[2]})

    def test_forged_metadata_invalid_proof_and_mutated_fields_never_gain_preference(self):
        rows, sidecars = self.prepared([prose_row(self.prose), row()])
        forged = copy.deepcopy(rows[0])
        forged.update(kind="quantitative", compiled=True, verificationPolicyRevision=8,
                      spec_json=sidecars[1].spec_json, learner_json=sidecars[1].learner_json)
        result, output, _ = self.sanitize([rows[0], forged], {}, target=1)
        self.assertEqual(result[0]["prompt"], rows[0]["prompt"])
        self.assertEqual(output, {})
        result, output, _ = self.sanitize([forged, rows[1]], sidecars, target=1)
        self.assertEqual(learner(result[0]), sidecars[1].content())
        self.assertEqual(output, {0: sidecars[1]})
        for malformed in (replace(sidecars[1], learner_json="{}"), replace(sidecars[1], spec_json="{}")):
            # No target cap: the original rejection still appears exactly once.
            result, output, metrics = self.sanitize(rows, {1: malformed})
            self.assertEqual([q["prompt"] for q in result], [rows[0]["prompt"]])
            self.assertEqual(output, {})
            self.assertEqual(metrics["QuestionQuality"]["sanitize"]["invalid_compiled_content"], 1)
        for field in LEARNER_FIELDS:
            changed = copy.deepcopy(rows)
            if field == "choices":
                changed[1][field].reverse()
            elif field == "choiceExplanations":
                changed[1][field][changed[1]["choices"][0]] = "A replacement teaching statement."
            else:
                changed[1][field] += " changed"
            with self.subTest(field=field):
                result, output, _ = self.sanitize(changed, sidecars, target=1)
                self.assertEqual(result[0]["prompt"], rows[0]["prompt"])
                self.assertEqual(output, {})
        for invalid in ({1: {"spec_json": sidecars[1].spec_json}}, {True: sidecars[1]}):
            with self.assertRaises(QuantitativeAuthoringError):
                self.sanitize(rows, invalid)

    def test_duplicates_and_all_existing_block_sources_still_reject(self):
        rows, sidecars = self.prepared([prose_row(self.prose), row(), row()])
        result, output, metrics = self.sanitize(rows, sidecars)
        self.assertEqual([q["prompt"] for q in result], [rows[i]["prompt"] for i in (1, 0)])
        self.assertEqual(output, {0: sidecars[1]})
        self.assertEqual(metrics["QuestionQuality"]["sanitize"]["duplicate_stem"], 1)
        shadow = {**self.prose, "prompt": rows[1]["prompt"]}
        result, output, metrics = self.sanitize([shadow, rows[1]], {1: sidecars[1]})
        self.assertEqual([learner(q) for q in result], [sidecars[1].content()])
        self.assertEqual(metrics["QuestionQuality"]["sanitize"]["duplicate_stem"], 1)
        self.assertEqual(output, {0: sidecars[1]})
        for field in ("existingPrompts", "reportedPrompts", "existingQuestionCoverage"):
            request = copy.deepcopy(self.request)
            request[field] = [{"prompt": rows[1]["prompt"]}] if field == "existingQuestionCoverage" else [rows[1]["prompt"]]
            result, output, _ = self.sanitize(rows, sidecars, request=request)
            self.assertEqual([q["prompt"] for q in result], [rows[0]["prompt"]])
            self.assertEqual(output, {})

    def test_compiled_difficulty_floor_and_adaptive_target_do_not_suppress_valid_prose(self):
        for adaptive in (False, True):
            rows, sidecars = self.prepared([prose_row(self.prose), row()])
            request = self.mapped_request() if adaptive else copy.deepcopy(self.request)
            if adaptive:
                for q in rows:
                    self.tag(q, request)
                request["requestedSkillAllocation"] = {rows[0]["skillID"]: 1}
                request["requestedObjectiveAllocation"] = [{**request["requestedObjectiveAllocation"][0], "count": 1}]
                rows[0]["difficulty"] = 3
                request["adaptiveSkillPlans"] = [{"skillID": rows[0]["skillID"], "targetDifficulty": 3}]
            else:
                rows[1]["difficulty"] = 1
            result, output, metrics = self.sanitize(rows, sidecars, target=1, request=request)
            self.assertEqual(result[0]["prompt"], rows[0]["prompt"])
            self.assertEqual(output, {})
            reason = "difficulty_target" if adaptive else "difficulty_floor"
            self.assertEqual(metrics["QuestionQuality"]["sanitize"][reason], 1)

    def pipeline_client(self, raw, *, construct=True, reject_audit=False):
        prepared, _, failures = prepare_mixed_rows({"questions": raw}, construct_choices=construct)
        self.assertEqual(failures, [])
        originals = {q["prompt"]: q for q in prepared if q}
        def solve(request):
            items = task_data(request, "question_solution_json")["items"]
            return solver_map(*(solver_record(item, originals[item["prompt"]]["expectedAnswer"]) for item in reversed(items)))
        def audit(request):
            items = task_data(request, "question_review_json")["items"]
            return {"reviews": {str(item["index"]): {
                "valid": not reject_audit, "answer": originals[item["prompt"]]["expectedAnswer"], "difficulty": 2,
                "explanationSupport": "unsupported" if reject_audit else "supported",
                "issueFlags": authored_issue_flags("explanation") if reject_audit else authored_issue_flags(),
            } for item in reversed(items)}}
        steps = [(CONSTRUCTED_AUTHOR_CONTRACT if construct else MIXED_AUTHOR_CONTRACT, {"questions": raw})]
        if not construct:
            steps.append(("complete_choice_solver_v5_n1", solve))
        steps.append(("authored_solution_reviewer_v3_n1", audit))
        return ScriptedNativeClient(*steps), prepared

    def test_actual_constructed_mode_prefers_compiled_surplus_but_final_audit_remains_binding(self):
        for reject in (False, True):
            client, prepared = self.pipeline_client([prose_row(self.prose), row()], reject_audit=reject)
            reserve = Mock()
            budget = generation.ProviderCallBudget(6, reserve_call=reserve)
            request = {**self.request, "targetCount": 1}
            result = generation._generate_sanitized_questions(request, client, budget)
            self.assertEqual((len(client.calls), budget.calls, reserve.call_count), (2, 2, 2))
            self.assertEqual(task_data(client.calls[1], "question_review_json")["items"][0]["prompt"], prepared[1]["prompt"])
            if reject:
                self.assertEqual(result, [])
            else:
                self.assertEqual([learner(q) for q in result], [learner(prepared[1])])
                self.assertEqual(result[0]["verificationPolicyRevision"], 8)

    def test_old_mixed_actual_route_and_default_sanitizer_retain_first_prose(self):
        rows, sidecars = self.prepared([prose_row(self.prose), row()])
        output = {}
        result = _sanitize_questions(rows, {**self.request, "targetCount": 1},
                                     preserve_authored_explanation=True, compiled_candidates=sidecars, compiled_output=output)
        self.assertEqual(result[0]["prompt"], rows[0]["prompt"])
        self.assertEqual(output, {})
        raw = [prose_row(self.prose), quantitative_row(exact_task())]
        client, _ = self.pipeline_client(raw, construct=False)
        with patch.dict(os.environ, {"QUESTION_AUTHOR_MODE": "mixed_quantitative"}):
            result = generation._generate_sanitized_questions({**self.request, "targetCount": 1}, client,
                                                               generation.ProviderCallBudget(6))
        self.assertEqual(result[0]["prompt"], self.prose["prompt"])
        self.assertEqual(result[0]["verificationPolicyRevision"], 7)
        self.assertEqual(len(client.calls), 3)

    def test_topups_share_six_call_budget_and_cannot_bypass_deadline_after_author(self):
        client = ScriptedNativeClient()
        for value in (8, 10, 12):
            next_client, _ = self.pipeline_client([row(task(str(value)))])
            client.steps.extend(next_client.steps)
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        with patch.dict(os.environ, {"GENERATION_ATTEMPTS": "5"}):
            result = generation._generate_sanitized_questions({**self.request, "targetCount": 5}, client, budget)
        # Two compiled passes leave two calls, below the unchanged three-call
        # admission minimum for an author that could return prose next time.
        self.assertEqual((len(result), budget.calls, reserve.call_count, len(client.calls)), (2, 4, 4, 4))
        for q in result:
            self.assertEqual(q["verificationPolicyRevision"], 8)
        context = Mock()
        context.get_remaining_time_in_millis.return_value = 240_000
        client, _ = self.pipeline_client([prose_row(self.prose), row()])
        original_converse = client.converse
        def expire(**request):
            response = original_converse(**request)
            context.get_remaining_time_in_millis.return_value = 0
            return response
        client.converse = expire
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, context=context, reserve_call=reserve)
        with self.assertRaises(ProviderDeadlineExceededError):
            generation._generate_sanitized_questions({**self.request, "targetCount": 1}, client, budget)
        self.assertEqual((budget.calls, len(client.calls), reserve.call_count), (1, 1, 1))


if __name__ == "__main__":
    unittest.main()
