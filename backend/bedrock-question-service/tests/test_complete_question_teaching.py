"""Immutable full-display contracts and independent declared vetoes; no models."""

import copy
import json
import unittest

from complete_question_teaching import (
    COMPLETE_TEACHING_REVIEW_SYSTEM_PROMPT,
    CompleteTeachingFormatError,
    complete_teaching_rejection_reason,
    compose_feedback_displays,
    freeze_complete_question,
    validate_complete_teaching_reviews,
)
from question_difficulty import DIFFICULTY_RUBRIC
from question_source_guidance import SOURCE_EVIDENCE_GUIDANCE


def question():
    return {
        "prompt": "What is the sum of two and two?",
        "choices": ["4", "5", "3", "2"],
        "expectedAnswer": "4",
        "explanation": "Two objects joined to two more give four objects in total.",
        "choiceExplanations": {
            "4": "Four follows by adding both pairs of objects.",
            "5": "Five exceeds the total supplied by the two pairs.",
            "3": "Three leaves out one of the four supplied objects.",
            "2": "Two counts only one of the two pairs of objects.",
        },
        "topic": "Addition",
        "difficulty": 1,
        "metadata": {"nested": [{"value": "preserve"}]},
    }


def audit_item(index=0, q=None):
    item = copy.deepcopy(question() if q is None else q)
    item.pop("expectedAnswer")
    item.pop("difficulty", None)
    item["index"] = index
    item["feedbackDisplays"] = compose_feedback_displays(item)
    return item


def review(index=0, q=None, **changes):
    q = question() if q is None else q
    return {
        "index": index,
        "valid": True,
        "answer": q["expectedAnswer"],
        "difficulty": 1,
        "explanationSupport": "supported",
        "choiceFeedbackSupport": [
            {"choice": choice, "feedbackSupport": "supported", "displaySupport": "supported"}
            for choice in q["choices"]
        ],
        "issues": [],
        **changes,
    }


def encoded(*records):
    return json.dumps({"reviews": list(records)}, ensure_ascii=False)


class CompleteTeachingTests(unittest.TestCase):
    def test_freeze_preserves_exact_content_metadata_and_snapshot_independence(self):
        q = question()
        q.update(
            prompt='  s = "e\u0301  x"\r\nWhat exact string is stored?\t ',
            choices=['"e\u0301  x"', '"e x"', '"E X"', '""'],
            expectedAnswer='"e\u0301  x"',
            explanation='  The string "e\u0301  x" keeps both spaces.\r\n    Preserve each symbol.\t ',
        )
        q["choiceExplanations"] = {
            choice: f"  The exact proposed string is {choice}.\r\n    Preserve its bytes.\t "
            for choice in reversed(q["choices"])
        }
        before = copy.deepcopy(q)
        frozen = freeze_complete_question(q)
        self.assertEqual(frozen, before)
        self.assertEqual(list(frozen["choiceExplanations"]), list(q["choiceExplanations"]))
        for field in ("prompt", "expectedAnswer", "explanation"):
            self.assertEqual(frozen[field].encode(), q[field].encode())
        frozen["metadata"]["nested"][0]["value"] = "changed"
        frozen["choices"].reverse()
        frozen["choiceExplanations"][q["choices"][0]] = "Changed feedback text."
        self.assertEqual(q, before)
        q["metadata"]["nested"].append("new caller data")
        self.assertEqual(len(frozen["metadata"]["nested"]), 1)
        self.assertNotIn("verificationVersion", frozen)
        self.assertNotIn("verificationPolicyRevision", frozen)

    def test_existing_provenance_is_preserved_as_data_not_assigned_or_upgraded(self):
        q = question()
        q.update(verificationVersion=999, verificationPolicyRevision=999, custom={"keep": [1]})
        self.assertEqual(freeze_complete_question(q), q)
        self.assertIsNone(complete_teaching_rejection_reason(review(), q))
        self.assertEqual(q["verificationPolicyRevision"], 999)

    def test_raw_bounds_count_stored_characters_without_clipping(self):
        for field, maximum in (("prompt", 320), ("explanation", 420)):
            for text in ("é" * 12, "é" * maximum, "\t" + "x" * 12 + "\r\n"):
                q = {**question(), field: text}
                self.assertEqual(freeze_complete_question(q)[field], text)
            for bad in (None, True, 12, "x" * 11, " " * 12, "x" * (maximum + 1),
                        " " + "x" * maximum, " " + "x" * 11,
                        " " * (maximum - 11) + "x" * 11, "x" * 12 + "\ud800"):
                q = {**question(), field: bad}
                before = copy.deepcopy(q)
                with self.subTest(field=field, bad=repr(bad)[:40]), self.assertRaises(CompleteTeachingFormatError):
                    freeze_complete_question(q)
                self.assertEqual(q, before)
        q = question()
        q["choiceExplanations"]["4"] = "é" * 280
        q["explanation"] = "x" * 420
        display = compose_feedback_displays(q)[0]["display"]
        self.assertEqual(len(display), 702)
        self.assertEqual(display, "é" * 280 + "\n\n" + "x" * 420)

    def test_all_choice_feedback_is_required_and_never_repaired(self):
        for value in (None, [], {}, {"4": "Correct four follows."},
                      {**question()["choiceExplanations"], "unexpected": "Extra feedback supplied."}):
            q = {**question(), "choiceExplanations": value}
            before = copy.deepcopy(q)
            with self.subTest(value=value), self.assertRaises(CompleteTeachingFormatError):
                freeze_complete_question(q)
            self.assertEqual(q, before)
        for choice in question()["choices"]:
            for value in (None, True, " ", "x" * 11, " " * 269 + "x" * 11,
                          "x" * 281, " " + "x" * 280, "x" * 12 + "\ud800"):
                q = question()
                q["choiceExplanations"][choice] = value
                with self.subTest(choice=choice, value=repr(value)[:30]), self.assertRaises(CompleteTeachingFormatError):
                    freeze_complete_question(q)
        missing = question()
        missing.pop("choiceExplanations")
        with self.assertRaises(CompleteTeachingFormatError):
            freeze_complete_question(missing)

    def test_choices_require_exact_key_and_safe_distinct_representations(self):
        for choices in (["4", "4", "3", "2"], ["4", " 4 ", "3", "2"],
                        ['"é"', '"e\u0301"', '"x"', '"y"'], ["4", "", "3", "2"],
                        ["4", "x" * 141, "3", "2"], ["4", True, "3", "2"], ["4"],
                        ["4", "x\ud800", "3", "2"], ("4", "5", "3", "2")):
            q = {**question(), "choices": choices}
            with self.subTest(choices=choices), self.assertRaises(CompleteTeachingFormatError):
                freeze_complete_question(q)
        for key in (None, 4, " 4", "unoffered"):
            with self.subTest(key=key), self.assertRaises(CompleteTeachingFormatError):
                freeze_complete_question({**question(), "expectedAnswer": key})
        q = question()
        q["choices"] = ['"e\u0301"', "x+y", "X+y", "x  y"]
        q["expectedAnswer"] = q["choices"][0]
        q["choiceExplanations"] = {c: "Exact offered text is preserved." for c in q["choices"]}
        self.assertEqual(freeze_complete_question(q), q)
        q["expectedAnswer"] = '"é"'
        with self.assertRaises(CompleteTeachingFormatError):
            freeze_complete_question(q)

    def test_feedback_key_canonical_equivalence_does_not_establish_exact_membership(self):
        q = question()
        q["choices"][0] = '"e\u0301"'
        q["expectedAnswer"] = q["choices"][0]
        q["choiceExplanations"]['"é"'] = q["choiceExplanations"].pop("4")
        with self.assertRaises(CompleteTeachingFormatError):
            freeze_complete_question(q)

    def test_all_teaching_fields_reject_shuffled_labels_without_forbidding_literal_answers(self):
        for text in ("Choice A gives the correct result.", "The result is in option b.",
                     "Answer D follows from the calculation."):
            for field in ("main", *question()["choices"]):
                q = question()
                if field == "main":
                    q["explanation"] = text
                else:
                    q["choiceExplanations"][field] = text
                with self.subTest(field=field, text=text), self.assertRaises(CompleteTeachingFormatError):
                    freeze_complete_question(q)
        q = question()
        q.update(choices=["A", "B", "C", "D"], expectedAnswer="A",
                 prompt="Which letter comes first in the sequence A, B, C, D?",
                 explanation="The letter A is first in the supplied sequence.")
        q["choiceExplanations"] = {c: f"The letter {c} has its shown position in the sequence." for c in q["choices"]}
        self.assertEqual(freeze_complete_question(q), q)

    def test_composition_uses_choice_order_and_preserves_every_character(self):
        q = question()
        q["choices"] = ["2", "4", "3", "5"]
        q["explanation"] = "  The exact main text has trailing spaces.  "
        q["choiceExplanations"]["2"] = "\tThe exact feedback ends with a newline.\r\n"
        before = copy.deepcopy(q)
        displays = compose_feedback_displays(q)
        self.assertEqual([row["choice"] for row in displays], q["choices"])
        for row in displays:
            self.assertEqual(row["display"], q["choiceExplanations"][row["choice"]] + "\n\n" + q["explanation"])
        displays[0]["display"] = "Changed returned copy."
        self.assertEqual(q, before)
        keyless = copy.deepcopy(q)
        keyless.pop("expectedAnswer")
        self.assertEqual(compose_feedback_displays(keyless), compose_feedback_displays(q))
        with self.assertRaises(CompleteTeachingFormatError):
            freeze_complete_question(keyless)

    def test_identical_feedback_uses_swift_main_only_fallback(self):
        q = question()
        q["choiceExplanations"]["4"] = q["explanation"]
        self.assertEqual(compose_feedback_displays(q)[0]["display"], q["explanation"])
        # Whitespace is preserved and participates in equality; no trimming here.
        q["choiceExplanations"]["4"] = " " + q["explanation"]
        self.assertEqual(compose_feedback_displays(q)[0]["display"],
                         " " + q["explanation"] + "\n\n" + q["explanation"])

    def test_canonical_equality_selects_main_without_rewriting_either_string(self):
        q = question()
        q["explanation"] = 'The literal "e\u0301" retains its original Unicode sequence.'
        q["choiceExplanations"]["4"] = 'The literal "é" retains its original Unicode sequence.'
        self.assertNotEqual(q["explanation"].encode(), q["choiceExplanations"]["4"].encode())
        before = copy.deepcopy(q)
        frozen = freeze_complete_question(q)
        display = compose_feedback_displays(frozen)[0]["display"]
        self.assertEqual(display.encode(), before["explanation"].encode())
        self.assertEqual(frozen, before)
        item = audit_item(q=q)
        self.assertEqual(validate_complete_teaching_reviews(encoded(review()), [item]), [review()])
        item["feedbackDisplays"][0]["display"] = q["choiceExplanations"]["4"]
        with self.assertRaises(CompleteTeachingFormatError):
            validate_complete_teaching_reviews(encoded(review()), [item])

    def test_display_input_must_be_complete_exact_and_in_actual_choice_order(self):
        valid = audit_item()
        changes = [None, [], valid["feedbackDisplays"][:-1], list(reversed(valid["feedbackDisplays"]))]
        duplicate = copy.deepcopy(valid["feedbackDisplays"])
        duplicate[3] = copy.deepcopy(duplicate[0])
        changes.append(duplicate)
        extra = copy.deepcopy(valid["feedbackDisplays"])
        extra[0]["replacement"] = "Unexpected competing text."
        changes.append(extra)
        shortened = copy.deepcopy(valid["feedbackDisplays"])
        shortened[0]["display"] = shortened[0]["display"][:-1]
        changes.append(shortened)
        for displays in changes:
            item = {**valid, "feedbackDisplays": displays}
            before = copy.deepcopy(item)
            with self.subTest(displays=displays), self.assertRaises(CompleteTeachingFormatError):
                validate_complete_teaching_reviews(encoded(review()), [item])
            self.assertEqual(item, before)
        item = copy.deepcopy(valid)
        item.pop("feedbackDisplays")
        with self.assertRaises(CompleteTeachingFormatError):
            validate_complete_teaching_reviews(encoded(review()), [item])
        item = copy.deepcopy(valid)
        item["explanation"] += " Changed afterward."
        with self.assertRaises(CompleteTeachingFormatError):
            validate_complete_teaching_reviews(encoded(review()), [item])

    def test_optional_stored_displays_are_validated_and_preserved_by_freeze(self):
        q = question()
        q["feedbackDisplays"] = compose_feedback_displays(q)
        self.assertEqual(freeze_complete_question(q), q)
        q["feedbackDisplays"][0]["display"] = "Stale content must not silently survive."
        for operation in (freeze_complete_question, compose_feedback_displays):
            with self.assertRaises(CompleteTeachingFormatError):
                operation(q)

    def test_dense_reordered_reviews_and_support_rows_are_correlated_without_mutation(self):
        items = [audit_item(1), audit_item(0)]
        first = review(0)
        first["choiceFeedbackSupport"].reverse()
        second = review(1, valid=False, issues=[" \tA material claim is not established.\r\n"])
        records = [second, first]
        before = copy.deepcopy((items, records))
        result = validate_complete_teaching_reviews("```json\n" + encoded(*records) + "\n```", items)
        self.assertEqual(result, [review(0), second])
        result[1]["issues"].append("Changed independent result.")
        result[0]["choiceFeedbackSupport"][0]["feedbackSupport"] = "unsupported"
        self.assertEqual((items, records), before)

    def test_missing_duplicate_unexpected_or_ill_typed_review_indices_fail_whole_batch(self):
        items = [audit_item(0), audit_item(1)]
        for records in ([review(0)], [review(0), review(1), review(2)], [review(0), review(0)],
                        [review(0), review(True)], [review(0), review("1")],
                        [review(0), review(-1)], [review(0), review(2)]):
            with self.subTest(records=records), self.assertRaises(CompleteTeachingFormatError):
                validate_complete_teaching_reviews(encoded(*records), items)
        for items in ([], [audit_item(1)], [audit_item(0), audit_item(0)], [audit_item(True)], (), None):
            with self.subTest(items=items), self.assertRaises(CompleteTeachingFormatError):
                validate_complete_teaching_reviews(encoded(review()), items)
        item = audit_item()
        item["expectedAnswer"] = "4"
        with self.assertRaises(CompleteTeachingFormatError):
            validate_complete_teaching_reviews(encoded(review()), [item])

    def test_missing_duplicate_or_inexact_choice_support_fails_even_on_invalid_review(self):
        good = review()["choiceFeedbackSupport"]
        cases = [None, {}, good[:-1], good + [good[0]], [good[0], good[0], *good[2:]]]
        wrong = copy.deepcopy(good)
        wrong[0]["choice"] = " 4"
        cases.append(wrong)
        wrong_type = copy.deepcopy(good)
        wrong_type[0]["choice"] = 4
        cases.append(wrong_type)
        for rows in cases:
            for valid in (True, False):
                r = review(valid=valid, choiceFeedbackSupport=rows)
                with self.subTest(rows=rows, valid=valid), self.assertRaises(CompleteTeachingFormatError):
                    validate_complete_teaching_reviews(encoded(r), [audit_item()])

    def test_strict_json_rejects_conflicting_envelopes_and_replacement_fields(self):
        for key, value in (("explanation", "Replacement text"), ("choiceExplanations", {}),
                           ("verificationVersion", 1), ("verificationPolicyRevision", 99),
                           ("prompt", "Rewrite"), ("feedbackDisplays", [])):
            with self.subTest(key=key), self.assertRaises(CompleteTeachingFormatError):
                validate_complete_teaching_reviews(encoded(review(**{key: value})), [audit_item()])
        for raw in ('{"reviews":[],"reviews":[]}',
                    encoded(review()).replace('"valid": true', '"valid": true,"valid":false'),
                    encoded(review()).replace('"feedbackSupport": "supported"',
                                              '"feedbackSupport": "supported","feedbackSupport":"unsupported"', 1),
                    encoded(review()) + " Reject this item.",
                    "Reject this item. " + encoded(review()),
                    json.dumps({"reviews": [review()], "replacement": {}}),
                    encoded(review(difficulty=float("nan"))),
                    encoded(review(difficulty=float("inf"))),
                    json.dumps([review()]), '{"reviews":', None, 12):
            with self.subTest(raw=repr(raw)[:70]), self.assertRaises(CompleteTeachingFormatError):
                validate_complete_teaching_reviews(raw, [audit_item()])

    def test_review_fields_types_and_issue_limits_are_exact(self):
        for field in review():
            r = review()
            r.pop(field)
            with self.subTest(field=field), self.assertRaises(CompleteTeachingFormatError):
                validate_complete_teaching_reviews(encoded(r), [audit_item()])
        changes = [{"valid": 1}, {"difficulty": True}, {"difficulty": 0}, {"difficulty": 6},
                   {"answer": None}, {"answer": " 4"}, {"answer": ""},
                   {"explanationSupport": None}, {"explanationSupport": "maybe"},
                   {"issues": "none"}, {"issues": [""]}, {"issues": [" \n"]},
                   {"issues": [True]}, {"issues": ["x" * 601]}, {"issues": ["issue"] * 9},
                   {"issues": ["unpaired \ud800"]}]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(CompleteTeachingFormatError):
                validate_complete_teaching_reviews(encoded(review(**change)), [audit_item()])
        r = review(issues=["é" * 600] * 8)
        self.assertEqual(validate_complete_teaching_reviews(encoded(r), [audit_item()]), [r])

    def test_support_fields_are_exact_and_cannot_carry_replacement_teaching(self):
        for field in ("choice", "feedbackSupport", "displaySupport"):
            r = review()
            r["choiceFeedbackSupport"][0].pop(field)
            with self.subTest(field=field), self.assertRaises(CompleteTeachingFormatError):
                validate_complete_teaching_reviews(encoded(r), [audit_item()])
        for field in ("feedbackSupport", "displaySupport"):
            for value in (None, True, 1, "refuted", "SUPPORTED", [], {}):
                r = review()
                r["choiceFeedbackSupport"][0][field] = value
                with self.subTest(field=field, value=value), self.assertRaises(CompleteTeachingFormatError):
                    validate_complete_teaching_reviews(encoded(r), [audit_item()])
        r = review()
        r["choiceFeedbackSupport"][0]["explanation"] = "Replacement feedback is prohibited."
        with self.assertRaises(CompleteTeachingFormatError):
            validate_complete_teaching_reviews(encoded(r), [audit_item()])

    def test_each_reported_support_objection_vetoes_valid_true_and_matching_key(self):
        for status in ("unsupported", "uncertain"):
            r = review(explanationSupport=status)
            self.assertEqual(complete_teaching_rejection_reason(r, question()), f"{status}_main_explanation")
            for index in range(4):
                for field, suffix in (("feedbackSupport", "choice_feedback"), ("displaySupport", "feedback_display")):
                    r = review()
                    r["choiceFeedbackSupport"][index][field] = status
                    parsed = validate_complete_teaching_reviews(encoded(r), [audit_item()])[0]
                    self.assertEqual(complete_teaching_rejection_reason(parsed, question()), f"{status}_{suffix}")

    def test_composition_only_defect_and_reported_contradiction_are_independent_vetoes(self):
        r = review()
        r["choiceFeedbackSupport"][2]["displaySupport"] = "unsupported"
        self.assertEqual(complete_teaching_rejection_reason(r, question()), "unsupported_feedback_display")
        r = review(issues=["The feedback and main make contradictory claims in combination."])
        self.assertEqual(complete_teaching_rejection_reason(r, question()), "reported_issues")
        r = review(valid=False, issues=["The stated conditions contradict the explanation."])
        self.assertEqual(complete_teaching_rejection_reason(r, question()), "reported_issues")
        r = review(explanationSupport="uncertain")
        r["choiceFeedbackSupport"][0]["displaySupport"] = "unsupported"
        self.assertEqual(complete_teaching_rejection_reason(r, question()), "unsupported_feedback_display")

    def test_invalid_or_wrong_key_reviews_never_receive_approval(self):
        for answer in ("4", ""):
            r = review(valid=False, answer=answer)
            self.assertEqual(validate_complete_teaching_reviews(encoded(r), [audit_item()]), [r])
            self.assertEqual(complete_teaching_rejection_reason(r, question()), "rejected_by_model")
        with self.assertRaises(CompleteTeachingFormatError):
            validate_complete_teaching_reviews(encoded(review(valid=False, answer="unoffered")), [audit_item()])
        r = review(answer="5")
        self.assertEqual(validate_complete_teaching_reviews(encoded(r), [audit_item()]), [r])
        self.assertEqual(complete_teaching_rejection_reason(r, question()), "answer_disagreement")

    def test_valid_cannot_determine_answer_is_preserved_without_an_extra_premise_gate(self):
        q = question()
        q.update(prompt="A positive integer is unknown. What is its exact value?",
                 choices=["1", "2", "3", "Its value cannot be determined from these facts."],
                 expectedAnswer="Its value cannot be determined from these facts.",
                 explanation="Both one and two meet the stated condition, so no single value is determined.")
        q["choiceExplanations"] = {c: "Several positive integers satisfy the condition, so no unique value is fixed."
                                  for c in q["choices"]}
        frozen = freeze_complete_question(q)
        r = review(q=q)
        parsed = validate_complete_teaching_reviews(encoded(r), [audit_item(q=frozen)])[0]
        self.assertIsNone(complete_teaching_rejection_reason(parsed, frozen))
        self.assertEqual(frozen, q)

    def test_gate_revalidates_direct_calls_and_does_not_mutate_inputs(self):
        q, r = question(), review()
        before = copy.deepcopy((q, r))
        self.assertIsNone(complete_teaching_rejection_reason(r, q))
        self.assertEqual((q, r), before)
        for invalid in (review(issues=None), review(choiceFeedbackSupport=[]), review(valid=1)):
            with self.assertRaises(CompleteTeachingFormatError):
                complete_teaching_rejection_reason(invalid, q)
        with self.assertRaises(CompleteTeachingFormatError):
            complete_teaching_rejection_reason(r, {**q, "explanation": "too short"})

    def test_supported_declarations_are_not_a_semantic_truth_or_difficulty_oracle(self):
        q = question()
        q["explanation"] = "Two plus two equals five, although the keyed answer is four."
        # This deliberately false content passes a falsely supported declaration.
        # The pure boundary enforces declared support, not unstated factual truth.
        self.assertIsNone(complete_teaching_rejection_reason(review(difficulty=1), q))
        r = review(explanationSupport="unsupported", issues=["The arithmetic contradicts the claimed key."])
        self.assertEqual(complete_teaching_rejection_reason(r, q), "unsupported_main_explanation")

    def test_prompt_covers_full_displays_and_discloses_its_information_boundary(self):
        prompt = COMPLETE_TEACHING_REVIEW_SYSTEM_PROMPT
        self.assertIn(SOURCE_EVIDENCE_GUIDANCE, prompt)
        self.assertIn(DIFFICULTY_RUBRIC, prompt)
        for requirement in ("not answer-blind", "every material claim", "EACH supplied feedbackDisplays",
                            "supported components", "Never rewrite", "not a correctness certificate",
                            "Missing values", "independently of valid and key agreement"):
            self.assertIn(requirement, prompt)


if __name__ == "__main__":
    unittest.main()
