import copy
import itertools
import json
import unittest

from complete_question_solution import (
    COMPLETE_SOLUTION_PAIR_AUDIT_SYSTEM_PROMPT,
    COMPLETE_SOLUTION_SYSTEM_PROMPT,
    CompleteSolutionFormatError,
    build_solver_prompt,
    rejection_reason,
    validate_batch,
)


def question(index=0, choices=None):
    choices = choices or ["2", "4", "Four", "8"]
    return {
        "index": index,
        "prompt": "What is 1 + 1?",
        "choices": choices,
        "expectedAnswer": choices[0],
        "explanation": "PRIVATE AUTHOR FEEDBACK",
    }


def record(item, *, pair_relation="distinct", judgments=None):
    judgments = judgments or ["supported", "refuted", "refuted", "refuted"]
    return {
        "index": item["index"],
        "choices": [
            {"choice": choice, "judgment": judgment, "reason": f"Judgment {index}."}
            for index, (choice, judgment) in enumerate(zip(item["choices"], judgments, strict=True))
        ],
        "choicePairs": [
            {
                "leftChoice": left, "rightChoice": right,
                "relation": pair_relation, "reason": f"Comparison {index}.",
            }
            for index, (left, right) in enumerate(itertools.combinations(item["choices"], 2))
        ],
    }


def raw(*records):
    return json.dumps({"solutions": list(records)}, ensure_ascii=False)


class CompleteChoicePairsTests(unittest.TestCase):
    def assert_invalid(self, changed, item=None):
        item = item or question()
        with self.assertRaises(CompleteSolutionFormatError):
            validate_batch(raw(changed), [item], audit_choice_pairs=True)
        with self.assertRaises(CompleteSolutionFormatError):
            rejection_reason(changed, item, audit_choice_pairs=True)

    def test_opt_in_prompt_is_answer_blind_and_leaves_default_unchanged(self):
        item = question()
        baseline = build_solver_prompt([item], {})
        self.assertEqual(baseline, build_solver_prompt([item], {}, audit_choice_pairs=False))
        self.assertEqual(baseline[0], COMPLETE_SOLUTION_SYSTEM_PROMPT)
        self.assertNotIn("choicePairs", baseline[0])
        system, user = build_solver_prompt([item], {}, audit_choice_pairs=True)
        self.assertEqual(system, COMPLETE_SOLUTION_PAIR_AUDIT_SYSTEM_PROMPT)
        self.assertEqual(user, baseline[1])
        self.assertNotIn("PRIVATE", user)
        self.assertNotIn("expectedAnswer", user)
        self.assertIn("AS AN ANSWER IN THE FORM THE STEM REQUESTS", system)
        self.assertIn("Do not equate options merely because both are false", system)
        self.assertIn("exactly six pair rows", system)
        changed = {**item, "expectedAnswer": item["choices"][1], "explanation": "CHANGED"}
        self.assertEqual(
            build_solver_prompt([changed], {}, audit_choice_pairs=True), (system, user)
        )

    def test_default_and_opt_in_contracts_do_not_silently_accept_each_other(self):
        item = question()
        audited = record(item)
        baseline = {key: value for key, value in audited.items() if key != "choicePairs"}
        self.assertEqual(validate_batch(raw(baseline), [item]), [baseline])
        self.assertIsNone(rejection_reason(baseline, item))
        self.assertEqual(
            validate_batch(raw(baseline), [item], audit_choice_pairs=False), [baseline]
        )
        self.assert_invalid(baseline)
        with self.assertRaises(CompleteSolutionFormatError):
            validate_batch(raw(audited), [item])
        with self.assertRaises(CompleteSolutionFormatError):
            rejection_reason(audited, item)

    def test_all_unordered_pairs_canonicalize_without_changing_text_or_input(self):
        choices = [' "e\u0301" ', '"a  b"', "−1", "four"]
        items = [question(0, choices), question(1, list(reversed(choices)))]
        records = [record(item) for item in items]
        reason = " \t" + "e" + "\u0301" * 235 + "\n "
        self.assertEqual(len(reason), 240)
        records[0]["choicePairs"][0]["reason"] = reason
        records[0]["choices"][0]["reason"] = "x" * 600
        expected = copy.deepcopy(records)
        for result in records:
            result["choices"].reverse()
            result["choicePairs"].reverse()
            for pair in result["choicePairs"]:
                pair["leftChoice"], pair["rightChoice"] = pair["rightChoice"], pair["leftChoice"]
        records.reverse()
        original = copy.deepcopy((items, records))
        actual = validate_batch(raw(*records), list(reversed(items)), audit_choice_pairs=True)
        self.assertEqual(actual, expected)
        self.assertEqual(actual[0]["choicePairs"][0]["reason"].encode(), reason.encode())
        self.assertEqual((items, records), original)
        actual[0]["choicePairs"][0]["reason"] = "Changed copy"
        self.assertEqual((items, records), original)

    def test_missing_extra_self_duplicate_and_reversed_duplicate_pairs_fail(self):
        base = record(question())
        mutations = [
            {**base, "choicePairs": base["choicePairs"][:5]},
            {**base, "choicePairs": base["choicePairs"] + [base["choicePairs"][0]]},
        ]
        for replacement in (
            base["choicePairs"][0],
            {**base["choicePairs"][0], "leftChoice": "4", "rightChoice": "2"},
            {**base["choicePairs"][1], "leftChoice": "Four", "rightChoice": "Four"},
        ):
            changed = copy.deepcopy(base)
            changed["choicePairs"][1] = replacement
            mutations.append(changed)
        for changed in mutations:
            with self.subTest(pairs=changed["choicePairs"]):
                self.assert_invalid(changed)

    def test_foreign_normalized_or_trimmed_choice_text_fails(self):
        item = question(choices=[' "e\u0301" ', '"a  b"', "−1", "four"])
        for field in ("leftChoice", "rightChoice"):
            for text in ('"e\u0301"', ' "é" ', '"a b"', "-1", "FOREIGN"):
                changed = record(item)
                changed["choicePairs"][0][field] = text
                with self.subTest(field=field, text=text):
                    self.assert_invalid(changed, item)

    def test_pair_fields_have_strict_shapes_types_and_reason_bounds(self):
        base = record(question())
        mutations = []
        for value in (None, {}, (), "pairs", 6, True):
            mutations.append({**base, "choicePairs": value})
        for value in (None, [], "pair", 6, True):
            changed = copy.deepcopy(base)
            changed["choicePairs"][0] = value
            mutations.append(changed)
        for field in ("leftChoice", "rightChoice", "relation", "reason"):
            changed = copy.deepcopy(base)
            del changed["choicePairs"][0][field]
            mutations.append(changed)
            for value in (None, [], {}, True, 1, 1.0):
                changed = copy.deepcopy(base)
                changed["choicePairs"][0][field] = value
                mutations.append(changed)
        for field, value in (
            ("relation", "Distinct"), ("relation", "supported"),
            ("relation", "distinct "), ("relation", ""),
            ("reason", " \r\n\t"), ("reason", ""), ("reason", "x" * 241),
            ("answer", "PRIVATE"),
        ):
            changed = copy.deepcopy(base)
            changed["choicePairs"][0][field] = value
            mutations.append(changed)
        for changed in mutations:
            with self.subTest(pairs=changed["choicePairs"]):
                self.assert_invalid(changed)

    def test_pair_audit_keeps_existing_record_choice_and_batch_strictness(self):
        base = record(question())
        mutations = [{**base, "extra": True}]
        for index in (True, False, "0", 0.0, -1, None):
            mutations.append({**base, "index": index})
        for field in ("index", "choices"):
            changed = copy.deepcopy(base)
            del changed[field]
            mutations.append(changed)
        for field, value in (("judgment", "correct"), ("reason", ""), ("extra", True)):
            changed = copy.deepcopy(base)
            changed["choices"][0][field] = value
            mutations.append(changed)
        mutations.append({**base, "choices": base["choices"][:3]})
        for changed in mutations:
            with self.subTest(record=changed):
                self.assert_invalid(changed)
        second = record(question(1))
        for records in ([base], [base, base], [base, {**second, "index": 2}]):
            with self.subTest(records=records):
                with self.assertRaises(CompleteSolutionFormatError):
                    validate_batch(raw(*records), [question(), question(1)], audit_choice_pairs=True)

    def test_duplicate_json_keys_and_malformed_envelopes_still_fail(self):
        valid = raw(record(question()))
        for malformed in (
            "[]", "{}", "broken", '{"solutions":[]}',
            valid.replace('"relation": "distinct"', '"relation": "distinct", "relation": "equivalent"', 1),
            valid.replace('"choicePairs":', '"extra": true, "choicePairs":', 1),
            valid.replace('"relation": "distinct"', '"relation": NaN', 1),
            valid.replace('"relation": "distinct"', '"relation": Infinity', 1),
        ):
            with self.subTest(raw=malformed):
                with self.assertRaises(CompleteSolutionFormatError):
                    validate_batch(malformed, [question()], audit_choice_pairs=True)

    def test_pair_vetoes_apply_to_declared_relations_after_original_judgments(self):
        item = question()
        for relation, expected in (
            ("distinct", None), ("equivalent", "solver_equivalent_choices"),
            ("uncertain", "solver_pair_uncertain"),
        ):
            with self.subTest(relation=relation):
                solution = record(item)
                solution["choicePairs"][3]["relation"] = relation
                validated = validate_batch(raw(solution), [item], audit_choice_pairs=True)
                self.assertEqual(rejection_reason(validated[0], item, audit_choice_pairs=True), expected)
        solution = record(item, pair_relation="uncertain")
        solution["choicePairs"][-1]["relation"] = "equivalent"
        self.assertEqual(
            rejection_reason(solution, item, audit_choice_pairs=True), "solver_equivalent_choices"
        )
        for judgments, expected in (
            (["refuted"] * 4, "solver_zero_supported"),
            (["supported", "supported", "uncertain", "refuted"], "solver_multiple_supported"),
            (["supported", "uncertain", "refuted", "refuted"], "solver_uncertain"),
            (["refuted", "supported", "refuted", "refuted"], "answer_disagreement"),
        ):
            with self.subTest(judgments=judgments):
                self.assertEqual(
                    rejection_reason(record(item, pair_relation="equivalent", judgments=judgments),
                                     item, audit_choice_pairs=True),
                    expected,
                )

    def test_pair_claims_are_fallible_and_cannot_be_treated_as_semantic_proof(self):
        item = question()
        # "4" and "Four" are equivalent wrong answers. A confident wrong pair
        # declaration remains eligible: this boundary verifies model claims,
        # not their truth, and does not make this experiment production-ready.
        solution = record(item, pair_relation="distinct")
        solution["choicePairs"][3]["reason"] = "Four is the same value as 4."
        self.assertIsNone(rejection_reason(solution, item, audit_choice_pairs=True))
        self.assertNotIn("verificationVersion", solution)


def slot_input(item):
    _, user = build_solver_prompt([item], {}, audit_choice_pairs=True, choice_slots=True)
    return json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])["items"][0]["choices"]


def slot_record(item):
    offered = slot_input(item)
    return {
        "index": item["index"],
        "choices": {slot: {"reason": f"Assessment of {text}.",
                           "judgment": "supported" if text == item["expectedAnswer"] else "refuted"}
                    for slot, text in offered.items()},
        "choicePairs": {left + right: {"reason": f"Compare {offered[left]} with {offered[right]}.",
                                      "relation": "distinct"}
                        for left, right in itertools.combinations(offered, 2)},
    }


class CompleteChoiceSlotTests(unittest.TestCase):
    def validate(self, result, item=None):
        return validate_batch(raw(result), [item or question()], audit_choice_pairs=True, choice_slots=True)

    def test_slots_require_pair_audit_and_default_payload_stays_list(self):
        item = question()
        with self.assertRaises(CompleteSolutionFormatError):
            build_solver_prompt([item], {}, choice_slots=True)
        with self.assertRaises(CompleteSolutionFormatError):
            validate_batch(raw(slot_record(item)), [item], choice_slots=True)
        for audit in (False, True):
            original = build_solver_prompt([item], {}, audit_choice_pairs=audit)
            self.assertEqual(original, build_solver_prompt([item], {}, audit_choice_pairs=audit, choice_slots=False))
            self.assertIn('"choices": [', original[1])

    def test_key_and_input_position_cannot_leak_into_canonical_slots(self):
        item = question()
        original = copy.deepcopy(item)
        expected = build_solver_prompt([item], {}, audit_choice_pairs=True, choice_slots=True)
        for values in itertools.permutations(item["choices"]):
            for answer in values:
                changed = {**item, "choices": list(values), "expectedAnswer": answer,
                           "explanation": "SECRET", "difficulty": 3, "answerHistory": [answer]}
                self.assertEqual(expected, build_solver_prompt([changed], {}, audit_choice_pairs=True, choice_slots=True))
        self.assertEqual(item, original)
        self.assertNotIn("expectedAnswer", expected[1])
        self.assertNotIn("SECRET", expected[1])

    def test_decoding_maps_trusted_exact_bytes_and_preserves_subject_literals(self):
        item = question(choices=[' "e\u0301" ', '"a  b"', "−1", "four"])
        result = slot_record(item)
        offered = slot_input(item)
        self.assertEqual(set(offered.values()), set(item["choices"]))
        selected = next(slot for slot, text in offered.items() if text == item["expectedAnswer"])
        result["choices"][selected]["reason"] = " \t" + "x" * 596 + "\n "
        result["choicePairs"]["ab"]["reason"] = "x" * 240
        original = copy.deepcopy((item, result))
        decoded = self.validate(result, item)[0]
        self.assertEqual([row["choice"] for row in decoded["choices"]], item["choices"])
        self.assertEqual(decoded["choices"][0]["reason"], result["choices"][selected]["reason"])
        self.assertEqual(len(decoded["choicePairs"]), 6)
        self.assertIsNone(rejection_reason(decoded, item, audit_choice_pairs=True))
        self.assertEqual((item, result), original)
        changed = {**item, "choices": list(reversed(item["choices"]))}
        again = self.validate(result, changed)[0]
        self.assertEqual({row["choice"]: row["judgment"] for row in again["choices"]},
                         {row["choice"]: row["judgment"] for row in decoded["choices"]})

    def test_missing_extra_self_reversed_pair_slots_cannot_decode(self):
        item = question()
        base = slot_record(item)
        mutations = []
        for field in ("choices", "choicePairs"):
            for value in (None, [], "slots", True, 1):
                mutations.append({**base, field: value})
            for slot in base[field]:
                changed = copy.deepcopy(base)
                del changed[field][slot]
                mutations.append(changed)
        for field, slot in (("choices", "e"), ("choices", "A"), ("choicePairs", "aa"),
                            ("choicePairs", "ba"), ("choicePairs", "da"), ("choicePairs", "de")):
            changed = copy.deepcopy(base)
            changed[field][slot] = copy.deepcopy(next(iter(base[field].values())))
            mutations.append(changed)
        for changed in mutations:
            with self.subTest(changed=changed):
                with self.assertRaises(CompleteSolutionFormatError):
                    self.validate(changed)

    def test_slot_rows_reject_echoed_text_unknown_fields_and_bad_types(self):
        base = slot_record(question())
        mutations = []
        for field, slot, verdict in (("choices", "a", "judgment"), ("choicePairs", "ab", "relation")):
            for value in (None, [], "row", True, 1):
                changed = copy.deepcopy(base)
                changed[field][slot] = value
                mutations.append(changed)
            for key, value in (("choice", "2"), ("leftChoice", "2"), ("rightChoice", "2"),
                               (verdict, True), (verdict, "supported "), ("reason", ""),
                               ("reason", " \n"), ("reason", 1),
                               ("reason", "x" * (601 if field == "choices" else 241))):
                changed = copy.deepcopy(base)
                changed[field][slot][key] = value
                mutations.append(changed)
            for key in (verdict, "reason"):
                changed = copy.deepcopy(base)
                del changed[field][slot][key]
                mutations.append(changed)
        for changed in mutations:
            with self.subTest(changed=changed):
                with self.assertRaises(CompleteSolutionFormatError):
                    self.validate(changed)

    def test_json_duplicates_and_index_batch_correlation_remain_strict(self):
        item = question()
        result = slot_record(item)
        value = raw(result)
        for invalid in (
            value.replace('"a": {', '"a": {}, "a": {', 1),
            value.replace('"ab": {', '"ab": {}, "ab": {', 1),
            value.replace('"index": 0', '"index": true', 1),
            value.replace('"index": 0', '"index": 1', 1),
            value.replace('"judgment": "supported"', '"judgment": NaN', 1),
            raw(result, result), raw(),
        ):
            with self.subTest(value=invalid):
                with self.assertRaises(CompleteSolutionFormatError):
                    validate_batch(invalid, [item], audit_choice_pairs=True, choice_slots=True)
        second = {**item, "index": 1}
        valid = validate_batch(raw({**result, "index": 1}, result), [second, item],
                               audit_choice_pairs=True, choice_slots=True)
        self.assertEqual([row["index"] for row in valid], [0, 1])

    def test_vetoes_use_decoded_text_and_keep_duplicate_and_uncertain_fail_closed(self):
        item = question()
        for relation, reason in (("equivalent", "solver_equivalent_choices"),
                                 ("uncertain", "solver_pair_uncertain")):
            result = slot_record(item)
            result["choicePairs"]["ab"]["relation"] = relation
            decoded = self.validate(result)[0]
            self.assertEqual(rejection_reason(decoded, item, audit_choice_pairs=True), reason)
        result = slot_record(item)
        decoded = self.validate(result)[0]
        changed = {**item, "expectedAnswer": item["choices"][1]}
        self.assertEqual(rejection_reason(decoded, changed, audit_choice_pairs=True), "answer_disagreement")

    def test_input_pair_endpoints_are_trusted_exact_text_and_ignore_authored_pair_metadata(self):
        item = question(choices=[' "e\u0301" ', '\"a  b\"', "−1", "four"])
        item["choicePairs"] = {"ab": {"leftChoice": "PRIVATE", "rightChoice": "ANSWER"}}
        system, user = build_solver_prompt([item], {}, audit_choice_pairs=True, choice_slots=True)
        payload = json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])["items"][0]
        self.assertEqual(set(payload["choicePairs"]), {"ab", "ac", "ad", "bc", "bd", "cd"})
        for pair, endpoints in payload["choicePairs"].items():
            self.assertEqual(endpoints, {"leftChoice": payload["choices"][pair[0]],
                                         "rightChoice": payload["choices"][pair[1]]})
        self.assertEqual(set(payload["choices"].values()), set(item["choices"]))
        self.assertNotIn("PRIVATE", user)
        self.assertNotIn("ANSWER", user)
        self.assertIn("Assess those two endpoints for that pair field", system)
        changed = {**item, "expectedAnswer": item["choices"][2], "choices": list(reversed(item["choices"]))}
        self.assertEqual((system, user), build_solver_prompt([changed], {}, audit_choice_pairs=True, choice_slots=True))

    def test_representation_exception_requires_explicit_written_form_task(self):
        system, _ = build_solver_prompt([question()], {}, audit_choice_pairs=True, choice_slots=True)
        self.assertIn("Merely specifying how to read", system)
        self.assertIn("does not make equivalent proposed answers distinct", system)
        self.assertIn("stem explicitly asks the learner to distinguish", system)
        self.assertIn("Do not equate options merely because both are false", system)
        # Historical array-mode prompt remains frozen and separately addressable.
        legacy, _ = build_solver_prompt([question()], {}, audit_choice_pairs=True)
        self.assertNotIn("Merely specifying how to read", legacy)

    def test_native_schema_fixed_slots_and_reason_order_are_enforced(self):
        from native_output_contracts import adapt_native_response, native_output_config
        from service_errors import ProviderError
        schema = json.loads(native_output_config("complete_choice_solver_v3")["textFormat"]["structure"]["jsonSchema"]["schema"])
        item = schema["properties"]["solutions"]["items"]
        self.assertEqual(list(item["properties"]), ["index", "choices", "choicePairs"])
        for field, slots, verdict in (("choices", ["a", "b", "c", "d"], "judgment"),
                                      ("choicePairs", ["ab", "ac", "ad", "bc", "bd", "cd"], "relation")):
            container = item["properties"][field]
            self.assertEqual(container["required"], slots)
            self.assertEqual(list(container["properties"]), slots)
            self.assertFalse(container["additionalProperties"])
            for row in container["properties"].values():
                self.assertEqual(list(row["properties"]), ["reason", verdict])
                self.assertEqual(row["required"], ["reason", verdict])
        result = slot_record(question())
        self.assertEqual(adapt_native_response(raw(result), "complete_choice_solver_v3"), raw(result))
        for mutate in (lambda row: row["choices"].pop("a"),
                       lambda row: row["choicePairs"].pop("ab"),
                       lambda row: row["choicePairs"].update(aa={"reason": "self", "relation": "equivalent"})):
            changed = copy.deepcopy(result)
            mutate(changed)
            with self.assertRaises(ProviderError):
                adapt_native_response(raw(changed), "complete_choice_solver_v3")


if __name__ == "__main__":
    unittest.main()
