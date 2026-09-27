"""Bounded family variety in one pinned mapped 3:2 author pass."""

import copy
import hashlib
import json
import os
import unittest
from unittest.mock import Mock, patch

from botocore.session import get_session
from botocore.validate import validate_parameters
from jsonschema import Draft202012Validator

import native_output_contracts as native
import question_generation as generation
from agreement_task_constructor import (
    COMPOUND_SCENE, COMPOUND_SCENES, LEARNER_FIELDS,
    blocked_fingerprint_variant_identities, compile_question,
    prepare_mapped_agreement_rows,
)
from lambda_test_support import _request_payload
from mapped_quantitative_families import (
    BOUNDARIES, FAMILIES, OPERANDS, SUPPORTED_OBJECTIVE, SUPPORTED_TOPIC,
    MappedQuantitativeFamilyError, flat_task,
)
from native_output_contracts import AuthorSlotContract
from quantitative_authoring import _constructed_candidate
from question_bank_common import _stem_fingerprint
from request_contract import _normalize_request
from service_errors import ProviderError, ServiceConfigurationError
from test_mapped_agreement_route import ENGLISH, ENGLISH_OBJECTIVE, MATH, MATH_OBJECTIVE
from test_native_pipeline import (
    MODEL, ScriptedNativeClient, authored_issue_flags, solver_map,
    solver_record, task_data,
)


def _agreement(scene, order="singular_first"):
    return {"kind": "agreement_pair_v1", "scene": scene, "order": order}


class MappedQuantitativeFamilyTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
            "QUESTION_AUTHOR_MODE": "constructed_quantitative",
            "QUESTION_AUTHOR_CARDINALITY_CONTRACT": "array",
            "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
            "QUESTION_MAPPED_AGREEMENT_TASKS": "enabled",
            "QUESTION_MAPPED_QUANTITATIVE_FAMILIES": "enabled",
            "BEDROCK_MODEL_ID": MODEL, "BEDROCK_VERIFICATION_MODEL_ID": MODEL,
            "BEDROCK_FALLBACK_MODEL_ID": "", "GENERATION_ATTEMPTS": "1",
        }))
        request = _normalize_request(_request_payload(target_count=5, minimum_difficulty=2))
        request["goal"].update(title="Arithmetic and English application practice",
                               contentTopics=[SUPPORTED_TOPIC, "Standard written English"])
        request["skillMap"] = {"version": 1, "skills": [
            {"id": MATH, "name": SUPPORTED_TOPIC, "objectives": [
                {"id": MATH_OBJECTIVE, "name": SUPPORTED_OBJECTIVE}]},
            {"id": ENGLISH, "name": "Standard written English", "objectives": [
                {"id": ENGLISH_OBJECTIVE, "name":
                 "Apply subject-verb agreement or unambiguous pronoun reference"}]},
        ]}
        request["requestedSkillAllocation"] = {MATH: 3, ENGLISH: 2}
        self.request = request
        goal_digest = hashlib.sha256(json.dumps(
            request["goal"], sort_keys=True, separators=(",", ":"),
            ensure_ascii=True, allow_nan=False,
        ).encode()).hexdigest()
        self.enterContext(patch.dict(os.environ, {
            "QUESTION_MAPPED_FIXED_FIVE_GOAL_SHA256": goal_digest,
            "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256": generation._mapped_author_scope_sha256(request),
        }))
        self.assignments = (
            (MATH, MATH_OBJECTIVE, SUPPORTED_TOPIC, SUPPORTED_OBJECTIVE, 3),
            (ENGLISH, ENGLISH_OBJECTIVE, "Standard written English",
             "Apply subject-verb agreement or unambiguous pronoun reference", 2),
        )

    def contract(self, families=True):
        return AuthorSlotContract(5, "constructed_quantitative", self.assignments,
                                  MATH, 2, True, families)

    def raw(self):
        return {"questions": {
            "0": {"family": FAMILIES[0], "a": 4, "b": 5},
            "1": {"family": FAMILIES[1], "a": 6, "b": 8},
            "2": {"family": FAMILIES[2], "a": 3, "b": 7},
            "3": _agreement("coach"),
            "4": _agreement(COMPOUND_SCENE, "plural_first"),
        }}

    def prepared(self):
        adapted = json.loads(native.adapt_native_response(json.dumps(self.raw()), self.contract()))
        rows, math_proof, english_proof, failures = prepare_mapped_agreement_rows(
            adapted, self.contract(),
        )
        self.assertEqual(failures, [])
        self.assertEqual(set(math_proof), {0, 1, 2})
        self.assertEqual(set(english_proof), {3, 4})
        return rows, math_proof, english_proof

    def test_all_allowed_parameters_compile_with_four_distinct_choices(self):
        checked = 0
        for slot in range(3):
            for a in OPERANDS:
                for b in OPERANDS if slot == 0 else BOUNDARIES:
                    task = flat_task(slot, {"family": FAMILIES[slot], "a": a, "b": b})
                    proof = _constructed_candidate(task)
                    learner = proof.content()
                    self.assertEqual(len(set(learner["choices"])), 4)
                    self.assertEqual(learner["choices"].count(learner["expectedAnswer"]), 1)
                    self.assertEqual(set(learner["choiceExplanations"]), set(learner["choices"]))
                    self.assertEqual(proof.content(learner), learner)
                    if slot in (1, 2):
                        self.assertEqual(learner["expectedAnswer"], str(b))
                    if slot == 2:
                        self.assertIn("The smaller domain values fail:", learner["explanation"])
                        self.assertIn(" / (x + ", learner["prompt"])
                    checked += 1
        self.assertEqual(checked, 208)

    def test_family_schema_is_small_closed_and_old_route_unchanged(self):
        schema_json = native.native_output_config(self.contract())["textFormat"]["structure"]["jsonSchema"]["schema"]
        schema = json.loads(schema_json)
        Draft202012Validator.check_schema(schema)
        self.assertLess(len(schema_json.encode()), 3000)
        self.assertEqual(len(schema_json.encode()), 1578)
        self.assertEqual([schema["properties"]["questions"]["properties"][str(i)]
                          ["properties"]["family"]["enum"][0] for i in range(3)], list(FAMILIES))
        self.assertNotIn("correctChoice", schema_json)
        self.assertNotIn("explanation", schema_json)
        self.assertEqual(native.contract_metadata(self.contract())["version"], "3")
        old = self.contract(False)
        old_schema = native.native_output_config(old)["textFormat"]["structure"]["jsonSchema"]["schema"]
        self.assertEqual(len(old_schema.encode()), 2757)
        self.assertEqual(hashlib.sha256(old_schema.encode()).hexdigest(),
                         "2a11817d040fe0fb34a413604b9b8ee3118fb631944c2bbf038c54076a95156d")
        self.assertEqual(hashlib.sha256(native.native_prompt(
            generation._system_prompt(), old,
        ).encode()).hexdigest(),
                         "016e595b20d7b2b1a6c8b94880ea4f3800de9105a740b35263a1521f380bed5a")
        family_prompt = native.native_prompt(generation._system_prompt(), self.contract())
        self.assertTrue(all(scene in family_prompt for scene in COMPOUND_SCENES))
        shape = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        validate_parameters({
            "modelId": MODEL,
            "messages": [{"role": "user", "content": [{"text": "task"}]}],
            "system": [{"text": native.native_prompt(generation._system_prompt(), self.contract())}],
            "inferenceConfig": {"maxTokens": 6000},
            "outputConfig": native.native_output_config(self.contract()),
        }, shape)

    def test_adapter_rejects_cross_family_and_forged_payloads(self):
        adapted = json.loads(native.adapt_native_response(json.dumps(self.raw()), self.contract()))
        self.assertEqual([row["kind"] for row in adapted["questions"]],
                         ["quantitative"] * 3 + ["agreement"] * 2)
        for i in range(3):
            self.assertEqual(adapted["questions"][i]["task"],
                             flat_task(i, self.raw()["questions"][str(i)]))
            self.assertEqual(adapted["questions"][i]["objectiveID"], MATH_OBJECTIVE)
        for slot, field, value in ((0, "family", FAMILIES[1]), (1, "a", True),
                                   (2, "b", 100), (0, "expectedAnswer", "0"),
                                   (1, "nodes", [])):
            bad = copy.deepcopy(self.raw())
            bad["questions"][str(slot)][field] = value
            with self.subTest(slot=slot, field=field), self.assertRaises(ProviderError):
                native.adapt_native_response(json.dumps(bad), self.contract())
        bad = copy.deepcopy(self.raw())
        del bad["questions"]["2"]
        with self.assertRaises(ProviderError):
            native.adapt_native_response(json.dumps(bad), self.contract())
        with self.assertRaises(MappedQuantitativeFamilyError):
            flat_task(0, self.raw()["questions"]["1"])

    def test_one_fake_provider_pass_retains_solver_reviewer_and_proof_boundaries(self):
        prepared, math_proof, english_proof = self.prepared()
        by_prompt = {row["prompt"]: row for row in prepared}

        def solver(request):
            items = task_data(request, "question_solution_json")["items"]
            self.assertEqual(len(items), 2)
            self.assertEqual({item["prompt"] for item in items},
                             {prepared[3]["prompt"], prepared[4]["prompt"]})
            return solver_map(*(solver_record(item, by_prompt[item["prompt"]]["expectedAnswer"])
                                for item in items))

        def audit(request):
            items = task_data(request, "question_review_json")["items"]
            self.assertEqual(len(items), 5)
            return {"reviews": {str(item["index"]): {
                "valid": True, "answer": by_prompt[item["prompt"]]["expectedAnswer"],
                "difficulty": 2, "explanationSupport": "supported",
                "issueFlags": authored_issue_flags(),
            } for item in items}}

        client = ScriptedNativeClient(
            (self.contract().name, self.raw()),
            ("complete_choice_solver_v5_n2", solver),
            ("authored_solution_reviewer_v3_n5", audit),
        )
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        result = generation._generate_sanitized_questions(
            copy.deepcopy(self.request), client, budget,
        )
        self.assertEqual((len(result), budget.calls, reserve.call_count), (5, 3, 3))
        self.assertEqual([row["verificationPolicyRevision"] for row in result], [8, 8, 8, 10, 10])
        self.assertEqual([row["skillID"] for row in result], [MATH] * 3 + [ENGLISH] * 2)
        for index, question in enumerate(result):
            proof = math_proof[index] if index < 3 else english_proof[index]
            self.assertEqual({field: question[field] for field in LEARNER_FIELDS},
                             {field: proof.content()[field] for field in LEARNER_FIELDS})
        self.assertEqual(client.steps, [])

    def test_family_pass_keeps_full_history_and_fingerprint_selection(self):
        source = self.raw()
        old_three = compile_question(source["questions"]["3"], ordinal=3)["prompt"]
        old_four = compile_question(source["questions"]["4"], ordinal=4)["prompt"]
        request = copy.deepcopy(self.request)
        request["existingPrompts"] = [old_three]
        request["blockedStemFingerprints"] = [_stem_fingerprint(old_four, version=2)]
        request["stemFingerprintVersion"] = 2
        adapted = json.loads(native.adapt_native_response(json.dumps(source), self.contract()))
        prepared, math_proof, english_proof, failures = prepare_mapped_agreement_rows(
            adapted, self.contract(), existing_prompts=(old_three,),
            blocked_variant_identities=tuple(sorted(blocked_fingerprint_variant_identities(
                request["blockedStemFingerprints"], 2,
            ))),
        )
        self.assertEqual(failures, [])
        self.assertNotIn(prepared[3]["prompt"], (old_three, old_four))
        self.assertNotIn(prepared[4]["prompt"], (old_three, old_four))
        by_prompt = {row["prompt"]: row for row in prepared}

        def solver(provider_request):
            items = task_data(provider_request, "question_solution_json")["items"]
            return solver_map(*(solver_record(item, by_prompt[item["prompt"]]["expectedAnswer"])
                                for item in items))

        def audit(provider_request):
            items = task_data(provider_request, "question_review_json")["items"]
            return {"reviews": {str(item["index"]): {
                "valid": True, "answer": by_prompt[item["prompt"]]["expectedAnswer"],
                "difficulty": 2, "explanationSupport": "supported",
                "issueFlags": authored_issue_flags(),
            } for item in items}}

        client = ScriptedNativeClient(
            (self.contract().name, source),
            ("complete_choice_solver_v5_n2", solver),
            ("authored_solution_reviewer_v3_n5", audit),
        )
        with patch.dict(os.environ, {
            "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256": generation._mapped_author_scope_sha256(request),
        }):
            result = generation._generate_sanitized_questions(
                request, client, generation.ProviderCallBudget(6),
            )
        self.assertEqual(len(result), 5)
        self.assertEqual([row["prompt"] for row in result],
                         [row["prompt"] for row in prepared])
        for slot, proof in {**math_proof, **english_proof}.items():
            self.assertEqual({field: result[slot][field] for field in LEARNER_FIELDS},
                             {field: proof.content()[field] for field in LEARNER_FIELDS})
        self.assertEqual(client.steps, [])

    def test_flag_requires_exact_scope_and_is_disabled_by_default(self):
        assignments = generation._mapped_fixed_slot_assignments(
            self.request, "constructed_quantitative", "array",
        )
        self.assertTrue(generation._mapped_quantitative_family_route(self.request, assignments, True))
        with patch.dict(os.environ, {"QUESTION_MAPPED_QUANTITATIVE_FAMILIES": "disabled"}):
            self.assertFalse(generation._mapped_quantitative_family_route(self.request, assignments, True))
        with patch.dict(os.environ, {"QUESTION_MAPPED_QUANTITATIVE_FAMILIES": "maybe"}):
            with self.assertRaises(ServiceConfigurationError):
                generation._mapped_quantitative_family_route(self.request, assignments, True)
        with self.assertRaises(ServiceConfigurationError):
            generation._mapped_quantitative_family_route(self.request, assignments, False)
        changed_assignments = copy.deepcopy(assignments)
        first_key = next(iter(changed_assignments))
        old = changed_assignments[first_key]
        changed_assignments[first_key] = (old[0], old[1] + " changed", old[2])
        with self.assertRaises(ServiceConfigurationError):
            generation._mapped_quantitative_family_route(
                self.request, changed_assignments,
                True,
            )


if __name__ == "__main__":
    unittest.main()
