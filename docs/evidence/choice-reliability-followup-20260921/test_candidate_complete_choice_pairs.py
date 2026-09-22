import copy
import itertools
import json
from pathlib import Path
import sys
import unittest

# Run directly or via unittest discovery without importing a production candidate.
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / "backend" / "bedrock-question-service"))
sys.path.insert(0, str(HERE))

from candidate_complete_question_solution import (  # noqa: E402
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


if __name__ == "__main__":
    unittest.main()
