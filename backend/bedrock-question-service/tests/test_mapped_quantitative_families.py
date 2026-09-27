"""Bounded family variety in one pinned mapped 3:2 author pass."""

import copy
from collections import Counter
import hashlib
import json
import os
import unittest
from fractions import Fraction
from unittest.mock import Mock, patch

from botocore.session import get_session
from botocore.validate import validate_parameters
from jsonschema import Draft202012Validator

import native_output_contracts as native
import question_bank
import question_generation as generation
from agreement_task_constructor import (
    AgreementTaskError, COMPOUND_SCENE, COMPOUND_SCENES, LEARNER_FIELDS,
    blocked_fingerprint_variant_identities, canonical_variant_identities, compile_question,
    prepare_mapped_agreement_rows,
)
from lambda_test_support import _request_payload
from mapped_quantitative_families import (
    BOUNDARIES, FAMILIES, OPERANDS, SLOT_FAMILIES, SUPPORTED_OBJECTIVE, SUPPORTED_TOPIC,
    MappedQuantitativeFamilyError, canonical_variant_identities as numeric_variant_identities,
    flat_task, historical_variant_identity_map, select_novel_task,
)
from native_output_contracts import AuthorSlotContract
from quantitative_authoring import _constructed_candidate
from question_bank_common import _normalized_stem_identity, _stem_fingerprint
from question_quality import _sanitize_questions
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
            for family in SLOT_FAMILIES[slot]:
                for a in OPERANDS:
                    for b in OPERANDS if slot == 0 else BOUNDARIES:
                        task = flat_task(slot, {"family": family, "a": a, "b": b})
                        proof = _constructed_candidate(task)
                        learner = proof.content()
                        self.assertEqual(len(set(learner["choices"])), 4)
                        self.assertEqual(learner["choices"].count(learner["expectedAnswer"]), 1)
                        self.assertEqual(set(learner["choiceExplanations"]), set(learner["choices"]))
                        self.assertEqual(proof.content(learner), learner)
                        if slot in (1, 2):
                            self.assertEqual(learner["expectedAnswer"], str(b))
                        if family == "bounded_equation":
                            self.assertGreaterEqual(learner["prompt"].count("x"), 2)
                        if slot == 2 and family == FAMILIES[slot]:
                            self.assertIn("The smaller domain values fail:", learner["explanation"])
                            self.assertIn(" / (x + ", learner["prompt"])
                        if family == "bounded_quadratic_maximum":
                            self.assertIn("The larger domain values fail:", learner["explanation"])
                        if family == "bounded_two_root_minimum":
                            self.assertIn(str(b + a), learner["choices"])
                            self.assertIn("minimum", learner["choiceExplanations"][str(b + a)])
                        checked += 1
        self.assertEqual(checked, 696)
        self.assertEqual(len(numeric_variant_identities()), 696)

    def test_every_bounded_rational_equation_teaches_its_verified_linear_solution(self):
        for a in OPERANDS:
            for b in BOUNDARIES:
                with self.subTest(a=a, b=b):
                    task = flat_task(1, {"family": "bounded_rational_equation", "a": a, "b": b})
                    proof = _constructed_candidate(task)
                    learner = proof.content()
                    target = Fraction(b + a, b + 1)
                    p, q = target.numerator, target.denominator
                    explanation = learner["explanation"]
                    self.assertIn(f"{q}(x + {a}) = {p}(x + 1)", explanation)
                    self.assertIn(f"{q}x + {q * a} = {p}x + {p}", explanation)
                    self.assertIn(f"{q * a - p} = {p - q}x", explanation)
                    self.assertIn(f"Divide by {p - q} to get x = {b}.", explanation)
                    self.assertIn("only solution in the domain", explanation)
                    self.assertEqual((q * a - p) / (p - q), b)
                    self.assertEqual(learner["expectedAnswer"], str(b))
                    self.assertEqual(proof.content(learner), learner)
                    tampered = {**learner, "explanation": "Substitute the answer and guess."}
                    with self.assertRaisesRegex(Exception, "Compiled learner content changed"):
                        proof.content(tampered)

        sample = _constructed_candidate(flat_task(1, {
            "family": "bounded_rational_equation", "a": 5, "b": 8,
        })).content()
        self.assertIn("9(x + 5) = 13(x + 1)", sample["explanation"])
        self.assertIn("32 = 4x", sample["explanation"])

    def test_family_schema_is_small_closed_and_agreement_route_matches_current_contract(self):
        schema_json = native.native_output_config(self.contract())["textFormat"]["structure"]["jsonSchema"]["schema"]
        schema = json.loads(schema_json)
        Draft202012Validator.check_schema(schema)
        self.assertEqual(len(schema_json.encode()), 2040)
        self.assertEqual(hashlib.sha256(schema_json.encode()).hexdigest(),
                         "4cb4a9f845c5553f141bb684360f7a086529814b465271d55ca13900e9932d5e")
        self.assertEqual([schema["properties"]["questions"]["properties"][str(i)]
                          ["properties"]["family"]["enum"] for i in range(3)],
                         [list(families) for families in SLOT_FAMILIES])
        self.assertNotIn("correctChoice", schema_json)
        self.assertNotIn("explanation", schema_json)
        self.assertEqual(native.contract_metadata(self.contract())["version"], "8")
        agreement = self.contract(False)
        agreement_schema = native.native_output_config(agreement)["textFormat"]["structure"]["jsonSchema"]["schema"]
        self.assertEqual(len(agreement_schema.encode()), 2999)
        self.assertEqual(hashlib.sha256(agreement_schema.encode()).hexdigest(),
                         "d9d26fd3b54af91ff2aeac048924f4098e3382d2f8a6062634804c884d221ab2")
        self.assertEqual(hashlib.sha256(native.native_prompt(
            generation._system_prompt(), agreement,
        ).encode()).hexdigest(),
                         "2c12c19d1bacafdaae5a1950d63d292526d7aa95357e77c70f7340edc64e65be")
        family_prompt = native.native_prompt(generation._system_prompt(), self.contract())
        self.assertTrue(all(family in family_prompt for families in SLOT_FAMILIES
                            for family in families))
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
            (self.contract().transport_name, self.raw()),
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
            (self.contract().transport_name, source),
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

    def test_repeated_numeric_source_selects_unused_structure_with_proof(self):
        source = self.raw()
        original = copy.deepcopy(source)
        adapted = json.loads(native.adapt_native_response(json.dumps(source), self.contract()))
        before, before_proof, _, failures = prepare_mapped_agreement_rows(adapted, self.contract())
        self.assertEqual(failures, [])
        blocked_prompt = before[0]["prompt"]
        rows, math_proof, english_proof, failures = prepare_mapped_agreement_rows(
            adapted, self.contract(), existing_prompts=(blocked_prompt,),
        )
        self.assertEqual(failures, [])
        self.assertNotEqual(rows[0]["prompt"], blocked_prompt)
        self.assertEqual([rows[i]["prompt"] for i in (1, 2)],
                         [before[i]["prompt"] for i in (1, 2)])
        self.assertEqual([math_proof[i] for i in (1, 2)], [before_proof[i] for i in (1, 2)])
        self.assertEqual(source, original)
        for ordinal, proof in math_proof.items():
            self.assertEqual(proof.content(rows[ordinal]),
                             {field: rows[ordinal][field] for field in proof.content()})

        request = copy.deepcopy(self.request)
        request["existingPrompts"] = [blocked_prompt]
        math_output, english_output = {}, {}
        selected = _sanitize_questions(
            rows, request, compiled_candidates=math_proof, compiled_output=math_output,
            agreement_candidates=english_proof, agreement_output=english_output,
            preserve_authored_explanation=True,
        )
        self.assertEqual(len(selected), 5)
        self.assertEqual(math_output, math_proof)
        self.assertEqual(english_output, english_proof)

        client = ScriptedNativeClient((self.contract().transport_name, source))
        with (patch.dict(os.environ, {
            "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256": generation._mapped_author_scope_sha256(request),
        }), patch.object(generation, "verify_questions", side_effect=lambda items, *_a, **_k: items)):
            piped = generation._generate_sanitized_questions(
                request, client, generation.ProviderCallBudget(6),
            )
        self.assertEqual([row["prompt"] for row in piped], [row["prompt"] for row in rows])
        self.assertEqual(len(client.calls), 1)

    def test_released_linear_stem_survives_template_upgrade_outside_recent_window(self):
        # This exact stem was returned in the archived mapped-family live seed
        # before f48440e changed the linear frame to distribute on both sides.
        old_linear_prompt = (
            "Let x be a unitless number. Its domain is integers from 0 through 15, "
            "inclusive. Condition: ((4 * x) + 7) = 35. Which offered value of x "
            "satisfies the condition?"
        )
        old_identity = _normalized_stem_identity(old_linear_prompt)
        current_task = flat_task(1, {"family": FAMILIES[1], "a": 4, "b": 7})
        current_prompt = _constructed_candidate(current_task).content()["prompt"]
        current_identity = _normalized_stem_identity(current_prompt)
        self.assertNotEqual(old_identity, current_identity)
        historical = historical_variant_identity_map()
        self.assertEqual(len(historical), len(OPERANDS) * len(BOUNDARIES))
        self.assertEqual(len(set(historical.values())), len(historical))
        self.assertFalse(set(historical) & numeric_variant_identities())
        self.assertTrue(set(historical.values()) <= numeric_variant_identities())
        self.assertEqual(historical[old_identity], current_identity)

        items = [{"questionJSON": {"S": json.dumps({"prompt": old_linear_prompt})}}]
        items.extend({"questionJSON": {"S": json.dumps({
            "prompt": f"Other bank question {index}"})}}
                     for index in range(30))
        other_seed_prompts = [
            _constructed_candidate(flat_task(slot, row)).content()["prompt"]
            for slot, row in ((0, {"family": FAMILIES[0], "a": 5, "b": 3}),
                              (2, {"family": FAMILIES[2], "a": 3, "b": 8}))
        ]
        items.extend({"questionJSON": {"S": json.dumps({"prompt": prompt})}}
                     for prompt in other_seed_prompts)
        projected = question_bank._mapped_quantitative_variant_history(items)
        self.assertEqual(set(projected), {current_identity, *map(
            _normalized_stem_identity, other_seed_prompts,
        )})
        selected = select_novel_task(
            1, current_task, existing_prompts=(), blocked_fingerprints=(),
            fingerprint_version=1, blocked_variant_identities=tuple(projected),
        )
        self.assertNotEqual(selected, current_task)
        self.assertIn(selected, [flat_task(1, {
            "family": "bounded_quadratic_equation", "a": a, "b": b,
        }) for a in OPERANDS for b in BOUNDARIES])

    def test_first_refill_rotates_all_three_solve_structures_and_keeps_five_slots(self):
        source = self.raw()
        adapted = json.loads(native.adapt_native_response(json.dumps(source), self.contract()))
        original, _, _, failures = prepare_mapped_agreement_rows(adapted, self.contract())
        self.assertEqual(failures, [])
        history = tuple(item["prompt"] for item in original)
        rows, math_proof, english_proof, failures = prepare_mapped_agreement_rows(
            adapted, self.contract(), existing_prompts=history,
        )
        self.assertEqual(failures, [])
        self.assertEqual(len(rows), 5)
        for slot in range(3):
            source_row = source["questions"][str(slot)]
            allowed_b = OPERANDS if slot == 0 else BOUNDARIES
            next_b = allowed_b[(allowed_b.index(source_row["b"]) + 1) % len(allowed_b)]
            alternate = flat_task(slot, {**source_row, "family": SLOT_FAMILIES[slot][1],
                                         "b": next_b})
            expected = _constructed_candidate(alternate).content()
            self.assertEqual({field: rows[slot][field] for field in LEARNER_FIELDS}, expected)
            self.assertNotEqual(rows[slot]["prompt"], original[slot]["prompt"])
            self.assertEqual(rows[slot]["expectedAnswer"], expected["expectedAnswer"])
            self.assertEqual(math_proof[slot].content(rows[slot]), expected)
        self.assertEqual([row["skillID"] for row in rows], [MATH] * 3 + [ENGLISH] * 2)
        self.assertEqual({field: rows[3][field] for field in LEARNER_FIELDS},
                         {field: english_proof[3].content()[field] for field in LEARNER_FIELDS})
        self.assertEqual({field: rows[4][field] for field in LEARNER_FIELDS},
                         {field: english_proof[4].content()[field] for field in LEARNER_FIELDS})

        request = copy.deepcopy(self.request)
        request["existingPrompts"] = list(history)
        by_prompt = {row["prompt"]: row for row in rows}

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
            (self.contract().transport_name, source),
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
        self.assertEqual([row["prompt"] for row in result], [row["prompt"] for row in rows])
        self.assertEqual(len(client.calls), 3)
        self.assertEqual(client.steps, [])

    def test_durable_numeric_history_prevents_exact_reuse_after_recent_window(self):
        source = [flat_task(slot, self.raw()["questions"][str(slot)])
                  for slot in range(3)]
        existing_items = []
        chosen = {slot: [] for slot in range(3)}
        chosen_families = {slot: [] for slot in range(3)}
        pair_counts = {}
        for batch in range(16):
            recent = question_bank._recent_question_items(existing_items, 30)
            recent_prompts = tuple(question_bank._question_from_item(item)["prompt"]
                                   for item in recent)
            full_identities = tuple(question_bank._mapped_quantitative_variant_history(
                existing_items,
            ))
            self.assertLessEqual(len(full_identities), 3 * batch)
            self.assertTrue(set(full_identities) <= numeric_variant_identities())
            if batch == 7:
                self.assertEqual(len(existing_items), 35)
                self.assertEqual(len(recent), 30)
                self.assertTrue(all(chosen[slot][0] not in recent_prompts
                                    for slot in range(3)))
            generated = []
            for slot in range(3):
                task = select_novel_task(
                    slot, source[slot], existing_prompts=recent_prompts,
                    blocked_fingerprints=(), fingerprint_version=2,
                    blocked_variant_identities=full_identities,
                )
                question = _constructed_candidate(task).content()
                chosen_families[slot].append(next(
                    family for family in SLOT_FAMILIES[slot]
                    for a in OPERANDS
                    for b in (OPERANDS if slot == 0 else BOUNDARIES)
                    if flat_task(slot, {"family": family, "a": a, "b": b}) == task
                ))
                self.assertNotIn(question["prompt"], chosen[slot])
                self.assertEqual(len(set(question["choices"])), 4)
                self.assertEqual(set(question["choiceExplanations"]), set(question["choices"]))
                chosen[slot].append(question["prompt"])
                generated.append(question)
            generated.extend({"prompt": f"English marker {batch} slot {slot}"}
                             for slot in (3, 4))
            existing_items.extend({
                "sk": {"S": f"QUESTION#{batch:02d}#{slot}"},
                "createdAt": {"N": str(batch * 5 + slot)},
                "questionJSON": {"S": json.dumps(question)},
            } for slot, question in enumerate(generated))
            if batch + 1 in (8, 16):
                pair_counts[batch + 1] = sum(
                    count * (count - 1) // 2
                    for slot in range(3)
                    for count in Counter(chosen_families[slot]).values()
                )
        self.assertEqual([len(set(chosen[slot])) for slot in range(3)], [16] * 3)
        for slot in range(3):
            self.assertEqual(chosen_families[slot], [
                SLOT_FAMILIES[slot][index % len(SLOT_FAMILIES[slot])]
                for index in range(16)
            ])
        # The two-root minimum family reduces slot-one structural reuse;
        # all exact stems remain unique across the full simulated history.
        self.assertEqual(pair_counts, {8: 18, 16: 94})
        request = {**self.request,
                   "_mappedQuantitativeVariantIdentities": list(full_identities)}
        self.assertEqual(generation._mapped_author_scope_sha256(request),
                         generation._mapped_author_scope_sha256(self.request))
        self.assertEqual(generation._provider_visible_request(request),
                         generation._provider_visible_request(self.request))
        with self.assertRaises(MappedQuantitativeFamilyError):
            select_novel_task(
                0, source[0], existing_prompts=(), blocked_fingerprints=(),
                fingerprint_version=2, blocked_variant_identities=("forged identity",),
            )

    def test_numeric_fingerprint_block_uses_requested_version(self):
        source = self.raw()
        adapted = json.loads(native.adapt_native_response(json.dumps(source), self.contract()))
        original, _, _, _ = prepare_mapped_agreement_rows(adapted, self.contract())
        for version in (1, 2):
            with self.subTest(version=version):
                blocked = _stem_fingerprint(original[1]["prompt"], version=version)
                rows, math_proof, english_proof, failures = prepare_mapped_agreement_rows(
                    adapted, self.contract(), blocked_stem_fingerprints=(blocked,),
                    stem_fingerprint_version=version,
                )
                self.assertEqual(failures, [])
                self.assertNotEqual(rows[1]["prompt"], original[1]["prompt"])
                self.assertEqual([rows[i]["prompt"] for i in (0, 2)],
                                 [original[i]["prompt"] for i in (0, 2)])
                request = copy.deepcopy(self.request)
                request["blockedStemFingerprints"] = [blocked]
                request["stemFingerprintVersion"] = version
                selected = _sanitize_questions(
                    rows, request, compiled_candidates=math_proof, compiled_output={},
                    agreement_candidates=english_proof, agreement_output={},
                    preserve_authored_explanation=True,
                )
                self.assertEqual(len(selected), 5)
                client = ScriptedNativeClient((self.contract().transport_name, source))
                with (patch.dict(os.environ, {
                    "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256": generation._mapped_author_scope_sha256(request),
                }), patch.object(generation, "verify_questions", side_effect=lambda items, *_a, **_k: items)):
                    piped = generation._generate_sanitized_questions(
                        request, client, generation.ProviderCallBudget(6),
                    )
                self.assertEqual([item["prompt"] for item in piped],
                                 [item["prompt"] for item in rows])
                self.assertEqual(len(client.calls), 1)

    def test_reported_and_coverage_history_reuse_numeric_selector(self):
        source = self.raw()
        adapted = json.loads(native.adapt_native_response(json.dumps(source), self.contract()))
        original, _, _, _ = prepare_mapped_agreement_rows(adapted, self.contract())
        blocked_prompt = original[0]["prompt"]
        for field, value in (("reportedPrompts", [blocked_prompt]),
                             ("existingQuestionCoverage", [{"prompt": blocked_prompt}])):
            with self.subTest(field=field):
                request = copy.deepcopy(self.request)
                request[field] = value
                client = ScriptedNativeClient((self.contract().transport_name, source))
                with (patch.dict(os.environ, {
                    "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256": generation._mapped_author_scope_sha256(request),
                }), patch.object(generation, "verify_questions", side_effect=lambda items, *_a, **_k: items)):
                    result = generation._generate_sanitized_questions(
                        request, client, generation.ProviderCallBudget(6),
                    )
                self.assertEqual(len(result), 5)
                self.assertNotEqual(result[0]["prompt"], blocked_prompt)
                self.assertEqual(len(client.calls), 1)

    def test_exhausted_numeric_family_fails_explicitly_without_extra_calls(self):
        source = self.raw()
        adapted = json.loads(native.adapt_native_response(json.dumps(source), self.contract()))
        prompts = tuple(_constructed_candidate(flat_task(0, {
            "family": family, "a": a, "b": b,
        })).content()["prompt"] for family in SLOT_FAMILIES[0]
            for a in OPERANDS for b in OPERANDS)
        blocked = tuple(_stem_fingerprint(prompt, version=2) for prompt in prompts)
        self.assertEqual(len(set(blocked)), len(SLOT_FAMILIES[0]) * len(OPERANDS) ** 2)
        with self.assertRaisesRegex(AgreementTaskError, "inventory exhausted") as caught:
            prepare_mapped_agreement_rows(
                adapted, self.contract(), blocked_stem_fingerprints=blocked,
                stem_fingerprint_version=2,
            )
        self.assertIsInstance(caught.exception.__cause__, MappedQuantitativeFamilyError)

        request = copy.deepcopy(self.request)
        request["blockedStemFingerprints"] = list(blocked)
        request["stemFingerprintVersion"] = 2
        client = ScriptedNativeClient((self.contract().transport_name, source))
        with (patch.dict(os.environ, {
            "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256": generation._mapped_author_scope_sha256(request),
        }), patch.object(generation, "verify_questions") as verify,
              self.assertRaises(ProviderError)):
            generation._generate_sanitized_questions(
                request, client, generation.ProviderCallBudget(6),
            )
        self.assertEqual(len(client.calls), 1)
        verify.assert_not_called()

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

    def test_refill_scope_reaches_both_closed_family_selectors(self):
        refill = copy.deepcopy(self.request)
        refill["existingPrompts"] = ["Earlier exact expression"]
        refill["existingQuestionCoverage"] = [{"prompt": "Earlier agreement item"}]
        refill["blockedStemFingerprints"] = ["a" * 16]
        refill["_agreementVariantIdentities"] = [sorted(canonical_variant_identities())[0]]
        with patch.dict(os.environ, {
            "QUESTION_MAPPED_FIXED_FIVE_SCOPE_MODE": "refill_history",
            "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256":
                generation._mapped_author_refill_scope_sha256(self.request),
        }):
            assignments = generation._mapped_fixed_slot_assignments(
                refill, "constructed_quantitative", "array")
            self.assertIsNotNone(assignments)
            self.assertTrue(generation._mapped_agreement_route(refill, assignments))
            self.assertTrue(generation._mapped_quantitative_family_route(
                refill, assignments, True))

    def test_normalized_worker_refill_keeps_pinned_closed_family_route(self):
        payload = _request_payload(target_count=5, minimum_difficulty=2)
        payload["goal"]["title"] = self.request["goal"]["title"]
        payload["skillMap"] = self.request["skillMap"]
        payload["desiredSkillAllocation"] = {MATH: 3, ENGLISH: 2}

        stored = []
        for index in range(5):
            if index < 3:
                question = {"prompt": f"Earlier arithmetic {index}",
                            "skillID": MATH, "objectiveID": MATH_OBJECTIVE}
            else:
                scene = "coach" if index == 3 else COMPOUND_SCENE
                question = compile_question(_agreement(scene), ordinal=index)
                question.update(skillID=ENGLISH, objectiveID=ENGLISH_OBJECTIVE)
            stored.append({
                "state": {"S": "ready"},
                "questionJSON": {"S": json.dumps(question)},
                "createdAt": {"N": str(index)},
                "sk": {"S": f"QUESTION#{index}"},
            })

        def worker_request(wire, prior):
            request = _normalize_request(wire)
            request["targetCount"] = 5
            request["requestedSkillAllocation"] = question_bank._worker_skill_allocation(
                request, prior, desired_count=11, low_watermark=0, target_count=5)
            request["requestedObjectiveAllocation"] = question_bank._worker_objective_allocation(
                request, prior, desired_count=11, low_watermark=0,
                requested_skill_allocation=request["requestedSkillAllocation"])
            recent = [question_bank._question_from_item(item)
                      for item in question_bank._recent_question_items(prior, 30)]
            request["existingPrompts"] = list(dict.fromkeys(
                request["existingPrompts"] + [item.get("prompt", "") for item in recent]))[-30:]
            request["existingQuestionCoverage"] = (
                request["existingQuestionCoverage"] + [
                    {"topic": item.get("topic", ""),
                     "skillID": item.get("skillID", ""),
                     "objectiveID": item.get("objectiveID", ""),
                     "objective": item.get("objective", ""),
                     "prompt": item.get("prompt", ""),
                     "expectedAnswer": item.get("expectedAnswer", ""),
                     "choices": item.get("choices", []),
                     "difficulty": item.get("difficulty", 1)} for item in recent])[-30:]
            request["_agreementVariantIdentities"] = question_bank._agreement_variant_history(prior)
            request["_mappedQuantitativeVariantIdentities"] = (
                question_bank._mapped_quantitative_variant_history(prior)
            )
            return request

        initial = worker_request(payload, [])
        refill_wire = copy.deepcopy(payload)
        refill_wire["reportedPrompts"] = ["Earlier learner report"]
        refill_wire["blockedStemFingerprints"] = ["a" * 16]
        refill = worker_request(refill_wire, stored)
        self.assertEqual(refill["requestedSkillAllocation"], {MATH: 3, ENGLISH: 2})
        self.assertEqual(len(refill["_agreementVariantIdentities"]), 2)
        self.assertEqual(generation._mapped_author_refill_scope_sha256(initial),
                         generation._mapped_author_refill_scope_sha256(refill))
        with patch.dict(os.environ, {
            "QUESTION_MAPPED_FIXED_FIVE_SCOPE_MODE": "refill_history",
            "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256":
                generation._mapped_author_refill_scope_sha256(initial),
            "QUESTION_MAPPED_FIXED_FIVE_GOAL_SHA256": hashlib.sha256(json.dumps(
                initial["goal"], sort_keys=True, separators=(",", ":"),
                ensure_ascii=True, allow_nan=False).encode()).hexdigest(),
        }):
            assignments = generation._mapped_fixed_slot_assignments(
                refill, "constructed_quantitative", "array")
            self.assertIsNotNone(assignments)
            self.assertTrue(generation._mapped_agreement_route(refill, assignments))
            self.assertTrue(generation._mapped_quantitative_family_route(
                refill, assignments, True))


if __name__ == "__main__":
    unittest.main()
