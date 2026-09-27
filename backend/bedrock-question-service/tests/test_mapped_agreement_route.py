"""Fake-provider qualification of the exact 3:2 agreement-task route."""

import copy
from dataclasses import replace
import hashlib
from itertools import permutations
import json
import os
import unittest
from unittest.mock import Mock, patch

from botocore.session import get_session
from botocore.validate import validate_parameters
from jsonschema import Draft202012Validator

import native_output_contracts as native
import question_bank
import question_generation as generation
from agreement_task_constructor import (
    AgreementTaskError, COMPOUND_SCENE, COMPOUND_SCENES, GERUND_SCENES, INVERSION_SCENES,
    NUMBER_SCENES, CORRELATIVE_SCENES, PARTITIVE_SCENES, RELATIVE_SCENES, SCENES,
    SENTENCE_SELECTION_SCENES,
    LEARNER_FIELDS,
    SUPPORTED_OBJECTIVE, SUPPORTED_TOPIC,
    blocked_fingerprint_variant_identities, checked_agreement_provenance,
    compile_mapped_english_slots, compile_question, prepare_mapped_agreement_rows,
)
from lambda_test_support import _request_payload
from native_output_contracts import AuthorSlotContract
from question_quality import _sanitize_questions
from question_bank_common import _stem_fingerprint
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import ProviderError, ServiceConfigurationError
from test_native_pipeline import (
    MODEL, ScriptedNativeClient, authored_issue_flags, solver_map,
    solver_record, task_data,
)
from test_quantitative_authoring import exact_task


MATH = "11111111-1111-4111-8111-111111111111"
ENGLISH = "22222222-2222-4222-8222-222222222222"
MATH_OBJECTIVE = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
ENGLISH_OBJECTIVE = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"


def agreement(scene, order="singular_first"):
    return {"kind": "agreement_pair_v1", "scene": scene, "order": order}


class MappedAgreementRouteTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
            "QUESTION_AUTHOR_MODE": "constructed_quantitative",
            "QUESTION_AUTHOR_CARDINALITY_CONTRACT": "array",
            "QUESTION_FEEDBACK_CONTRACT": "authored_solution",
            "QUESTION_MAPPED_AGREEMENT_TASKS": "enabled",
            "BEDROCK_MODEL_ID": MODEL, "BEDROCK_VERIFICATION_MODEL_ID": MODEL,
            "BEDROCK_FALLBACK_MODEL_ID": "", "GENERATION_ATTEMPTS": "1",
        }))
        request = _normalize_request(_request_payload(target_count=5, minimum_difficulty=2))
        request["goal"].update(title="Arithmetic and English application practice",
                               contentTopics=["Exact arithmetic", SUPPORTED_TOPIC])
        request["skillMap"] = {"version": 1, "skills": [
            {"id": MATH, "name": "Exact arithmetic", "objectives": [
                {"id": MATH_OBJECTIVE, "name": "Evaluate exact expressions"}]},
            {"id": ENGLISH, "name": SUPPORTED_TOPIC, "objectives": [
                {"id": ENGLISH_OBJECTIVE, "name": SUPPORTED_OBJECTIVE}]},
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
            (MATH, MATH_OBJECTIVE, "Exact arithmetic", "Evaluate exact expressions", 3),
            (ENGLISH, ENGLISH_OBJECTIVE, SUPPORTED_TOPIC, SUPPORTED_OBJECTIVE, 2),
        )

    def contract(self, agreement_tasks=True):
        return AuthorSlotContract(5, "constructed_quantitative", self.assignments, MATH, 2,
                                  agreement_tasks)

    def raw(self):
        rows = {}
        for ordinal, value in enumerate(("8", "10", "12")):
            task = exact_task(value)
            del task["choices"]
            rows[str(ordinal)] = task
        rows["3"] = agreement("coach")
        rows["4"] = agreement(COMPOUND_SCENE, "plural_first")
        return {"questions": rows}

    def prepared(self):
        adapted = json.loads(native.adapt_native_response(json.dumps(self.raw()), self.contract()))
        rows, math_proof, agreement_proof, failures = prepare_mapped_agreement_rows(
            adapted, self.contract(),
        )
        self.assertEqual(failures, [])
        self.assertEqual(set(math_proof), {0, 1, 2})
        self.assertEqual(set(agreement_proof), {3, 4})
        return rows, math_proof, agreement_proof

    def test_level_two_first_sentence_selection_from_other_authored_family(self):
        raw = self.raw()
        raw["questions"]["4"] = agreement("gerund_meals")
        adapted = json.loads(native.adapt_native_response(json.dumps(raw), self.contract()))
        rows, math_proof, english_proof, failures = prepare_mapped_agreement_rows(
            adapted, self.contract(),
        )
        self.assertEqual(failures, [])
        self.assertEqual(json.loads(english_proof[4].task_json),
                         agreement("select_archive", "singular_first"))
        self.assertEqual(rows[4]["difficulty"], 2)
        self.assertEqual(rows[4]["expectedAnswer"], "Maya and Theo each prepare lunch.")
        english_output = {}
        sanitized = _sanitize_questions(
            rows, self.request, compiled_candidates=math_proof, compiled_output={},
            agreement_candidates=english_proof, agreement_output=english_output,
            preserve_authored_explanation=True,
        )
        self.assertEqual(len(sanitized), 5)
        self.assertEqual(english_output[4].content(sanitized[4]), sanitized[4])

    def test_new_schema_is_closed_bounded_and_old_v1_bytes_unchanged(self):
        new = self.contract()
        schema_json = native.native_output_config(new)["textFormat"]["structure"]["jsonSchema"]["schema"]
        schema = json.loads(schema_json)
        Draft202012Validator.check_schema(schema)
        self.assertLess(len(schema_json.encode()), 3200)
        self.assertEqual(set(schema["$defs"]), {"node", "task", "slot3", "slot4"})
        self.assertEqual(schema["$defs"]["slot3"]["properties"]["scene"]["enum"],
                         sorted((*SCENES, *INVERSION_SCENES, *RELATIVE_SCENES,
                                 *PARTITIVE_SCENES)))
        self.assertEqual(schema["$defs"]["slot4"]["properties"]["scene"]["enum"],
                         sorted((*COMPOUND_SCENES, *NUMBER_SCENES, *CORRELATIVE_SCENES,
                                 *GERUND_SCENES, *SENTENCE_SELECTION_SCENES)))
        self.assertNotIn("correctChoice", schema_json)
        self.assertNotIn("explanation", schema_json)
        self.assertEqual(native.contract_metadata(new)["version"], "7")
        old = self.contract(False)
        self.assertEqual(native.contract_metadata(old)["version"], "1")
        old_schema = native.native_output_config(old)["textFormat"]["structure"]["jsonSchema"]["schema"]
        self.assertEqual(hashlib.sha256(old_schema.encode()).hexdigest(),
                         "eee8c873b7892a8b96e510777fe9ffbbc8d10cf70846644ea0993946c9c2bb3c")
        old_prompt = native.native_prompt(generation._system_prompt(), old)
        self.assertEqual(hashlib.sha256(old_prompt.encode()).hexdigest(),
                         "83f9fd3a544fb76ea833a3bcac6addafbcbc55dd33073c0765ad934c0c878108")
        # The independent previous route stays selected when the new flag is off.
        with patch.dict(os.environ, {"QUESTION_MAPPED_AGREEMENT_TASKS": "disabled"}):
            self.assertFalse(generation._mapped_agreement_route(self.request,
                generation._mapped_fixed_slot_assignments(self.request, "constructed_quantitative", "array")))
        request_shape = {
            "modelId": MODEL,
            "messages": [{"role": "user", "content": [{"text": "task"}]}],
            "system": [{"text": native.native_prompt(generation._system_prompt(), new)}],
            "inferenceConfig": {"maxTokens": 6000},
            "outputConfig": native.native_output_config(new),
        }
        shape = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        validate_parameters(request_shape, shape)

    def test_adapter_rejects_missing_extra_swapped_or_forged_slots(self):
        raw = self.raw()
        adapted = json.loads(native.adapt_native_response(json.dumps(raw), self.contract()))
        self.assertEqual([row["kind"] for row in adapted["questions"]],
                         ["quantitative"] * 3 + ["agreement"] * 2)
        for ordinal, row in enumerate(adapted["questions"]):
            self.assertEqual(row["skillID"], MATH if ordinal < 3 else ENGLISH)
            self.assertEqual(row["objectiveID"], MATH_OBJECTIVE if ordinal < 3 else ENGLISH_OBJECTIVE)
        invalid = []
        missing = copy.deepcopy(raw)
        del missing["questions"]["4"]
        invalid.append(missing)
        extra = copy.deepcopy(raw)
        extra["questions"]["5"] = agreement(COMPOUND_SCENE)
        invalid.append(extra)
        swapped = copy.deepcopy(raw)
        swapped["questions"]["3"], swapped["questions"]["4"] = (
            swapped["questions"]["4"], swapped["questions"]["3"]
        )
        invalid.append(swapped)
        forged = copy.deepcopy(raw)
        forged["questions"]["3"]["expectedAnswer"] = "check; practice"
        invalid.append(forged)
        forged = copy.deepcopy(raw)
        forged["questions"]["4"]["skillID"] = ENGLISH
        invalid.append(forged)
        same_mechanism = copy.deepcopy(raw)
        same_mechanism["questions"]["4"] = agreement("chef")
        invalid.append(same_mechanism)
        for case in invalid:
            with self.subTest(case=case), self.assertRaises(ProviderError):
                native.adapt_native_response(json.dumps(case), self.contract())
        with self.assertRaises(ProviderError):
            native.adapt_native_response('{"questions":{"3":{},"3":{}}}', self.contract())

    def test_one_actual_fake_provider_pass_keeps_exact_math_and_english_proof(self):
        prepared, math_proof, english_proof = self.prepared()
        by_prompt = {row["prompt"]: row for row in prepared}

        def solver(request):
            items = task_data(request, "question_solution_json")["items"]
            self.assertEqual(len(items), 2)
            self.assertEqual({item["prompt"] for item in items},
                             {prepared[3]["prompt"], prepared[4]["prompt"]})
            self.assertNotIn("expectedAnswer", json.dumps(items))
            self.assertNotIn("explanation", json.dumps(items))
            return solver_map(*(solver_record(item, by_prompt[item["prompt"]]["expectedAnswer"])
                                for item in items))

        def audit(request):
            items = task_data(request, "question_review_json")["items"]
            self.assertEqual(len(items), 5)
            return {"reviews": {str(item["index"]): {
                "valid": True, "answer": by_prompt[item["prompt"]]["expectedAnswer"],
                # Both proven English items are admitted at their code-owned
                # calibrated level even when the reviewer estimates level 3.
                "difficulty": 3 if item["prompt"] in {
                    prepared[3]["prompt"], prepared[4]["prompt"]
                } else 2, "explanationSupport": "supported",
                "issueFlags": authored_issue_flags(),
            } for item in items}}

        client = ScriptedNativeClient(
            (self.contract().transport_name, self.raw()),
            ("complete_choice_solver_v5_n2", solver),
            ("authored_solution_reviewer_v3_n5", audit),
        )
        reserve = Mock()
        budget = generation.ProviderCallBudget(6, reserve_call=reserve)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        result = generation._generate_sanitized_questions(
            copy.deepcopy(self.request), client, budget, metrics,
        )
        self.assertEqual((len(result), budget.calls, reserve.call_count), (5, 3, 3))
        self.assertEqual([row["verificationPolicyRevision"] for row in result], [8, 8, 8, 10, 10])
        self.assertEqual([row["difficulty"] for row in result], [2] * 5)
        self.assertEqual(metrics["QuestionQuality"]["review"]["agreement_difficulty_disagreement"], 2)
        for index, question in enumerate(result):
            proof = math_proof[index] if index < 3 else english_proof[index]
            if index >= 3:
                self.assertEqual(proof.content(), {key: question[key] for key in proof.content()})
                self.assertEqual(proof.ordinal, index)
                for displayed in permutations(question["choices"]):
                    self.assertEqual(displayed.count(question["expectedAnswer"]), 1)
                    self.assertEqual(set(displayed), set(question["choiceExplanations"]))
                    self.assertEqual(question["choiceExplanations"][question["expectedAnswer"]],
                                     proof.content()["choiceExplanations"][question["expectedAnswer"]])
            self.assertEqual({field: question[field] for field in LEARNER_FIELDS},
                             {field: proof.content()[field] for field in LEARNER_FIELDS})
        self.assertEqual([row["skillID"] for row in result], [MATH] * 3 + [ENGLISH] * 2)
        self.assertEqual(client.steps, [])

    def test_bank_history_keeps_thirty_two_unique_pairs_beyond_recent_thirty(self):
        source = {"3": agreement("coach"), "4": agreement(COMPOUND_SCENE)}
        bank_id = "a" * 64
        existing_items = []
        chosen = {3: [], 4: []}
        for batch in range(32):
            recent = question_bank._recent_question_items(existing_items, 30)
            recent_prompts = tuple(
                question_bank._question_from_item(item)["prompt"] for item in recent
            )
            full_identities = tuple(question_bank._agreement_variant_history(existing_items))
            self.assertLessEqual(len(full_identities), 72)
            if batch == 7:
                self.assertEqual(len(existing_items), 35)
                self.assertEqual(len(recent), 30)
                # The first pair has dropped out of prompt feedback, but its
                # exact identities still belong to bank deduplication history.
                self.assertNotIn(chosen[3][0], recent_prompts)
                self.assertNotIn(chosen[4][0], recent_prompts)
                without_full_history = compile_mapped_english_slots(
                    source, self.contract(), existing_prompts=recent_prompts,
                )
                self.assertIn(without_full_history[3].content()["prompt"], chosen[3])
                self.assertIn(without_full_history[4].content()["prompt"], chosen[4])

            candidates = compile_mapped_english_slots(
                source, self.contract(), existing_prompts=recent_prompts,
                blocked_variant_identities=full_identities,
            )
            generated = [{"prompt": f"Unique quantitative batch {batch} slot {slot}"}
                         for slot in range(3)]
            generated += [candidates[slot].content() for slot in (3, 4)]
            prepared = question_bank._prepare_questions(bank_id, generated, existing_items)
            self.assertEqual(len(prepared), 5)
            for slot in (3, 4):
                self.assertFalse(candidates[slot].novelty_exhausted)
                self.assertEqual(candidates[slot].content(), generated[slot])
                chosen[slot].append(prepared[slot]["prompt"])
            existing_items.extend({
                "sk": {"S": f"QUESTION#{batch:02d}#{slot}"},
                "createdAt": {"N": str(batch)},
                "remoteID": {"S": question["remoteID"]},
                "questionJSON": {"S": json.dumps(question)},
            } for slot, question in enumerate(prepared))

        self.assertEqual(len(set(chosen[3])), 32)
        self.assertEqual(len(set(chosen[4])), 32)
        exhausted = compile_mapped_english_slots(
            source, self.contract(),
            blocked_variant_identities=tuple(question_bank._agreement_variant_history(existing_items)),
        )
        self.assertTrue(exhausted[3].novelty_exhausted)
        self.assertFalse(exhausted[4].novelty_exhausted)
        remaining = [exhausted[4].content()["prompt"]]
        for _ in range(7):
            next_item = compile_mapped_english_slots(
                source, self.contract(),
                blocked_variant_identities=tuple(question_bank._agreement_variant_history(existing_items)),
                existing_prompts=tuple(remaining),
            )[4]
            self.assertFalse(next_item.novelty_exhausted)
            remaining.append(next_item.content()["prompt"])
        exhausted = compile_mapped_english_slots(
            source, self.contract(),
            blocked_variant_identities=tuple(question_bank._agreement_variant_history(existing_items)),
            existing_prompts=tuple(remaining),
        )
        self.assertTrue(exhausted[4].novelty_exhausted)
        self.assertEqual(len(question_bank._prepare_questions(
            bank_id, [exhausted[4].content()], existing_items,
        )), 0)

    def test_fingerprint_only_block_and_private_history_preserve_scope_and_prompt(self):
        source = {"3": agreement("coach"), "4": agreement(COMPOUND_SCENE)}
        blocked_prompt = compile_question(source["3"], ordinal=3)["prompt"]
        for version in (1, 2):
            with self.subTest(version=version):
                fingerprint = _stem_fingerprint(blocked_prompt, version=version)
                identities = tuple(sorted(blocked_fingerprint_variant_identities(
                    [fingerprint], version,
                )))
                self.assertIn(blocked_prompt, identities)
                candidates = compile_mapped_english_slots(
                    source, self.contract(), blocked_variant_identities=identities,
                )
                self.assertNotEqual(candidates[3].content()["prompt"], blocked_prompt)
                request = {**self.request, "_agreementVariantIdentities": list(identities)}
                self.assertEqual(
                    generation._mapped_author_scope_sha256(request),
                    generation._mapped_author_scope_sha256(self.request),
                )
                self.assertEqual(
                    generation._provider_visible_request(request),
                    generation._provider_visible_request(self.request),
                )
                with self.assertRaises(AgreementTaskError):
                    replace(candidates[3], blocked_variant_identities=()).content()

    def test_generation_passes_full_history_and_fingerprint_blocks_to_selector(self):
        request = copy.deepcopy(self.request)
        source = {"3": agreement("coach"), "4": agreement(COMPOUND_SCENE, "plural_first")}
        history_prompt = compile_question(source["3"], ordinal=3)["prompt"]
        fingerprint_prompt = compile_question(source["4"], ordinal=4)["prompt"]
        request["_agreementVariantIdentities"] = [history_prompt]
        request["blockedStemFingerprints"] = [_stem_fingerprint(fingerprint_prompt, version=2)]
        request["stemFingerprintVersion"] = 2
        # The fingerprint is already part of the normalized scoped request;
        # repin that exact request before adding the private bank sidecar.
        scoped = {key: value for key, value in request.items()
                  if key != "_agreementVariantIdentities"}
        adapted = json.loads(native.adapt_native_response(json.dumps(self.raw()), self.contract()))
        with (
            patch.dict(os.environ, {
                "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256": generation._mapped_author_scope_sha256(scoped),
            }),
            patch.object(generation, "_generate_provider_payload", return_value=adapted),
            patch.object(generation, "verify_questions", side_effect=lambda candidates, *_args, **_kwargs: candidates),
        ):
            generated = generation._generate_sanitized_questions(request, None)
        self.assertEqual(len(generated), 5)
        self.assertNotEqual(generated[3]["prompt"], history_prompt)
        self.assertNotEqual(generated[4]["prompt"], fingerprint_prompt)

    def test_missing_or_forged_proof_and_tampered_learner_content_fail_closed(self):
        rows, math_proof, english_proof = self.prepared()
        forged = {3: {"ordinal": 3}}
        with self.assertRaises(AgreementTaskError):
            checked_agreement_provenance(forged, 5, original_ordinals=True)
        with self.assertRaises(AgreementTaskError):
            _sanitize_questions(rows, self.request, compiled_candidates=math_proof,
                                compiled_output={}, agreement_candidates=forged,
                                agreement_output={}, preserve_authored_explanation=True)
        changed = copy.deepcopy(rows)
        changed[3]["expectedAnswer"] = changed[3]["choices"][0]
        changed[4]["explanation"] = "Model-authored replacement teaching."
        output, english_output = {}, {}
        accepted = _sanitize_questions(changed, self.request, compiled_candidates=math_proof,
                                       compiled_output=output, agreement_candidates=english_proof,
                                       agreement_output=english_output,
                                       preserve_authored_explanation=True)
        self.assertEqual(len(accepted), 3)
        self.assertEqual(set(english_output), set())
        no_english_proof = _sanitize_questions(
            rows, self.request, compiled_candidates=math_proof, compiled_output={},
            preserve_authored_explanation=True,
        )
        self.assertEqual(len(no_english_proof), 3)
        first_bad = copy.deepcopy(rows)
        first_bad[3]["choiceExplanations"] = {}
        output, english_output = {}, {}
        survivors = _sanitize_questions(
            first_bad, self.request, compiled_candidates=math_proof, compiled_output=output,
            agreement_candidates=english_proof, agreement_output=english_output,
            preserve_authored_explanation=True,
        )
        self.assertEqual(len(survivors), 4)
        self.assertEqual(set(english_output), {3})
        self.assertEqual(english_output[3].ordinal, 4)
        self.assertEqual(english_output[3].content(survivors[3]), survivors[3])
        changed_difficulty = copy.deepcopy(rows)
        changed_difficulty[3]["difficulty"] = 3
        difficulty_output = {}
        difficulty_survivors = _sanitize_questions(
            changed_difficulty, self.request, compiled_candidates=math_proof,
            compiled_output={}, agreement_candidates=english_proof,
            agreement_output=difficulty_output, preserve_authored_explanation=True,
        )
        self.assertEqual(len(difficulty_survivors), 4)
        self.assertEqual(set(difficulty_output), {3})
        self.assertEqual(difficulty_output[3].ordinal, 4)
        # A sidecar for a different original slot cannot be reattached to a
        # surviving question after sanitizer filtering.
        with self.assertRaises(AgreementTaskError):
            checked_agreement_provenance({0: english_proof[3]}, 5, original_ordinals=True)
        with self.assertRaises(AgreementTaskError):
            verify_questions(rows, self.request, lambda *_: "{}", solve=lambda *_: "{}",
                             review_with_count=lambda *_: "{}", solve_with_count=lambda *_: "{}",
                             feedback_contract="authored_solution", solver_contract="complete_choices",
                             audit_choice_pairs=True, choice_slots=True,
                             compiled_questions={3: math_proof[0]},
                             agreement_questions={3: english_proof[3]})

    def test_without_private_agreement_proof_only_ordinary_policy_is_possible(self):
        rows, math_proof, _ = self.prepared()
        ordinary = copy.deepcopy(rows)
        for index in (3, 4):
            ordinary[index].pop("choiceExplanations")
        math_output = {}
        sanitized = _sanitize_questions(
            ordinary, self.request, compiled_candidates=math_proof, compiled_output=math_output,
            preserve_authored_explanation=True,
        )
        self.assertEqual(len(sanitized), 5)
        by_prompt = {item["prompt"]: item for item in sanitized}

        def body(prompt, tag):
            return json.loads(prompt.split(f"<{tag}>\n", 1)[1].split(f"\n</{tag}>", 1)[0])

        def solver(_system, prompt, count):
            items = body(prompt, "question_solution_json")["items"]
            self.assertEqual((count, len(items)), (2, 2))
            return json.dumps({"solutions": [
                solver_record(item, by_prompt[item["prompt"]]["expectedAnswer"])
                for item in items
            ]})

        def audit(_system, prompt, count):
            items = body(prompt, "question_review_json")["items"]
            self.assertEqual((count, len(items)), (5, 5))
            return json.dumps({"reviews": [{
                "index": item["index"], "valid": True,
                "answer": by_prompt[item["prompt"]]["expectedAnswer"],
                "difficulty": 3 if item["prompt"] in {
                    rows[3]["prompt"], rows[4]["prompt"]
                } else 2, "explanationSupport": "supported", "issues": [],
            } for item in items]})

        accepted = verify_questions(
            sanitized, self.request, audit, review_with_count=audit,
            solve=solver, solve_with_count=solver,
            feedback_contract="authored_solution", solver_contract="complete_choices",
            audit_choice_pairs=True, choice_slots=True, compiled_questions=math_output,
        )
        self.assertEqual([row["verificationPolicyRevision"] for row in accepted],
                         [8, 8, 8, 7, 7])
        self.assertEqual([row["difficulty"] for row in accepted], [2, 2, 2, 3, 3])
        self.assertEqual([row["choiceExplanations"] for row in accepted[3:]], [{}, {}])
        targeted = copy.deepcopy(self.request)
        targeted["adaptiveSkillPlans"] = [{"skillID": ENGLISH, "targetDifficulty": 2}]
        target_survivors = verify_questions(
            sanitized, targeted, audit, review_with_count=audit,
            solve=solver, solve_with_count=solver,
            feedback_contract="authored_solution", solver_contract="complete_choices",
            audit_choice_pairs=True, choice_slots=True, compiled_questions=math_output,
        )
        self.assertEqual([row["verificationPolicyRevision"] for row in target_survivors],
                         [8, 8, 8])

    def test_solver_or_reviewer_key_disagreement_cannot_rewrite_agreement_question(self):
        prepared, _, english_proof = self.prepared()
        by_prompt = {row["prompt"]: row for row in prepared}
        for bad_stage in ("solver", "reviewer"):
            def wrong(prompt):
                expected = by_prompt[prompt]["expectedAnswer"]
                return next(choice for choice in by_prompt[prompt]["choices"] if choice != expected)

            def solver(request):
                items = task_data(request, "question_solution_json")["items"]
                return solver_map(*(solver_record(
                    item, wrong(item["prompt"]) if bad_stage == "solver" and
                    item["prompt"] == prepared[3]["prompt"] else
                    by_prompt[item["prompt"]]["expectedAnswer"],
                ) for item in items))

            def audit(request):
                items = task_data(request, "question_review_json")["items"]
                self.assertEqual(len(items), 4 if bad_stage == "solver" else 5)
                return {"reviews": {str(item["index"]): {
                    "valid": True,
                    "answer": wrong(item["prompt"]) if bad_stage == "reviewer" and
                    item["prompt"] == prepared[3]["prompt"] else
                    by_prompt[item["prompt"]]["expectedAnswer"],
                    "difficulty": 2, "explanationSupport": "supported",
                    "issueFlags": authored_issue_flags(),
                } for item in items}}

            client = ScriptedNativeClient(
                (self.contract().transport_name, self.raw()),
                ("complete_choice_solver_v5_n2", solver),
                ("authored_solution_reviewer_v3_n4" if bad_stage == "solver"
                 else "authored_solution_reviewer_v3_n5", audit),
            )
            with self.subTest(bad_stage=bad_stage):
                accepted = generation._generate_sanitized_questions(
                    copy.deepcopy(self.request), client, generation.ProviderCallBudget(6),
                )
                self.assertEqual(len(accepted), 4)
                self.assertEqual([row["verificationPolicyRevision"] for row in accepted],
                                 [8, 8, 8, 10])
                self.assertEqual(english_proof[4].content(),
                                 {key: accepted[3][key] for key in english_proof[4].content()})

    def test_other_reviewer_difficulty_disagreements_still_veto_proven_agreement(self):
        rows, math_proof, english_proof = self.prepared()
        by_prompt = {row["prompt"]: row for row in rows}

        def body(prompt, tag):
            return json.loads(prompt.split(f"<{tag}>\n", 1)[1].split(f"\n</{tag}>", 1)[0])

        def solver(_system, prompt, count):
            items = body(prompt, "question_solution_json")["items"]
            self.assertEqual((count, len(items)), (2, 2))
            return json.dumps({"solutions": [
                solver_record(item, by_prompt[item["prompt"]]["expectedAnswer"])
                for item in items
            ]})

        for rating in (1, 4, 5, "3"):
            def audit(_system, prompt, count):
                items = body(prompt, "question_review_json")["items"]
                self.assertEqual((count, len(items)), (5, 5))
                return json.dumps({"reviews": [{
                    "index": item["index"], "valid": True,
                    "answer": by_prompt[item["prompt"]]["expectedAnswer"],
                    "difficulty": rating if item["prompt"] == rows[3]["prompt"] else 2,
                    "explanationSupport": "supported", "issues": [],
                } for item in items]})

            metrics = {}
            with self.subTest(rating=rating):
                accepted = verify_questions(
                    rows, self.request, audit, review_with_count=audit,
                    solve=solver, solve_with_count=solver, request_metrics=metrics,
                    feedback_contract="authored_solution", solver_contract="complete_choices",
                    audit_choice_pairs=True, choice_slots=True,
                    compiled_questions=math_proof, agreement_questions=english_proof,
                )
                if rating == "3":
                    self.assertEqual(accepted, [])
                    self.assertEqual(metrics["QuestionQuality"]["review"]["invalid_authored_review"], 5)
                else:
                    self.assertEqual([row["verificationPolicyRevision"] for row in accepted],
                                     [8, 8, 8, 10])
                    self.assertEqual(accepted[3]["difficulty"], 2)
                    self.assertEqual(metrics["QuestionQuality"]["review"]["difficulty_target"], 1)
                    self.assertNotIn("agreement_difficulty_disagreement",
                                     metrics["QuestionQuality"]["review"])

    def test_opt_in_requires_full_exact_scope_and_level_two(self):
        assignments = generation._mapped_fixed_slot_assignments(
            self.request, "constructed_quantitative", "array",
        )
        self.assertTrue(generation._mapped_agreement_route(self.request, assignments))
        with patch.dict(os.environ, {"QUESTION_MAPPED_AGREEMENT_TASKS": "disabled"}):
            self.assertFalse(generation._mapped_agreement_route(self.request, assignments))
        with patch.dict(os.environ, {"QUESTION_MAPPED_AGREEMENT_TASKS": "maybe"}):
            with self.assertRaises(ServiceConfigurationError):
                generation._mapped_agreement_route(self.request, assignments)
        changed = copy.deepcopy(self.request)
        changed["goal"]["title"] += " changed"
        self.assertIsNone(generation._mapped_fixed_slot_assignments(
            changed, "constructed_quantitative", "array",
        ))
        self.assertFalse(generation._mapped_agreement_route(changed, None))
        level_three = copy.deepcopy(self.request)
        level_three["minimumDifficulty"] = 3
        with self.assertRaises(ServiceConfigurationError):
            generation._mapped_agreement_route(level_three, assignments)


if __name__ == "__main__":
    unittest.main()
