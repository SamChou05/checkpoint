"""Exact teaching preservation and declared-review gates; no model execution."""

import copy
import json
import unittest

from question_difficulty import DIFFICULTY_RUBRIC
from question_teaching import (
    AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT,
    AuthoredTeachingFormatError,
    authored_review_rejection_reason,
    freeze_authored_question,
    validate_authored_reviews,
)


def question(index=0):
    return {
        "index": index, "prompt": "What is the sum of two and two?",
        "choices": ["4", "5", "3", "2"], "expectedAnswer": "4",
        "explanation": "Two objects joined to two more objects give four objects in total.",
        "topic": "Addition", "difficulty": 1,
    }


def item(index=0):
    return {k: v for k, v in question(index).items() if k not in {"expectedAnswer", "difficulty"}}


def review(index=0, **changes):
    return {"index": index, "valid": True, "answer": "4", "difficulty": 1,
            "explanationSupport": "supported", "issues": [], **changes}


def encoded(*records):
    return json.dumps({"reviews": list(records)}, ensure_ascii=False)


class AuthoredTeachingTests(unittest.TestCase):
    def test_freeze_preserves_exact_unicode_code_whitespace_and_nested_metadata(self):
        q = question()
        q.update(prompt='  s = "e\u0301  x"\r\nWhat exact string is stored?\t ',
                 choices=['"e\u0301  x"', '"e x"', '"E X"', '""'],
                 expectedAnswer='"e\u0301  x"',
                 explanation='  The string "e\u0301  x" keeps both spaces.\r\n    Its first letter and combining mark stay distinct.\t ',
                 metadata={"nested": ["keep", {"value": 1}]})
        original = copy.deepcopy(q)
        frozen = freeze_authored_question(q)
        self.assertEqual(frozen, original)
        self.assertEqual(len(q["choices"][0].strip('"')), 5)  # e, combining mark, two spaces, x
        for field in ("prompt", "explanation", "expectedAnswer"):
            self.assertEqual(frozen[field].encode(), q[field].encode())
        frozen["metadata"]["nested"][1]["value"] = 2
        frozen["choices"].reverse()
        self.assertEqual(q, original)
        self.assertNotIn("choiceExplanations", frozen)
        self.assertNotIn("verificationVersion", frozen)
        self.assertNotIn("verificationPolicyRevision", frozen)

    def test_full_raw_field_bounds_reject_without_clipping_or_whitespace_discount(self):
        for field, maximum in (("prompt", 320), ("explanation", 420)):
            for size in (12, maximum):
                q = {**question(), field: "é" * size}
                self.assertEqual(freeze_authored_question(q)[field], q[field])
            for bad in (None, True, 12, "x" * 11, " " * 30, "x" * (maximum + 1),
                        " " + "x" * maximum, " " * (maximum - 11) + "x" * 11):
                q = {**question(), field: bad}
                with self.subTest(field=field, bad=repr(bad)[:30]), self.assertRaises(AuthoredTeachingFormatError):
                    freeze_authored_question(q)
        q = {**question(), "explanation": " " + "x" * 12 + "\r\n"}
        self.assertEqual(freeze_authored_question(q)["explanation"], q["explanation"])

    def test_incoming_choice_teaching_is_never_silently_removed(self):
        for bad in ({"4": "Correct four follows."}, {"unexpected": ""}, None, [], "", True):
            q = {**question(), "choiceExplanations": bad}
            before = copy.deepcopy(q)
            with self.subTest(value=bad), self.assertRaises(AuthoredTeachingFormatError):
                freeze_authored_question(q)
            self.assertEqual(q, before)
        q = {**question(), "choiceExplanations": {}}
        self.assertEqual(freeze_authored_question(q), q)

    def test_ambiguous_choices_and_inexact_key_fail_without_folding_real_content(self):
        for choices in (["4", "4", "3", "2"], ["4", " 4 ", "3", "2"],
                        ['"é"', '"e\u0301"', '"x"', '"y"'], ["4", "", "3", "2"],
                        ["4", "x" * 141, "3", "2"], ["4", True, "3", "2"], ["4"]):
            with self.subTest(choices=choices), self.assertRaises(AuthoredTeachingFormatError):
                freeze_authored_question({**question(), "choices": choices, "expectedAnswer": choices[0]})
        q = {**question(), "choices": ['"e\u0301"', '"x"', '"y"', '"z"'], "expectedAnswer": '"é"'}
        with self.assertRaises(AuthoredTeachingFormatError):
            freeze_authored_question(q)
        q = {**question(), "choices": ["x+y", "x-y", "X+y", "x  y"], "expectedAnswer": "x+y"}
        self.assertEqual(freeze_authored_question(q)["choices"], q["choices"])

    def test_main_references_to_shuffled_answer_labels_are_rejected(self):
        for text in ("Choice A gives the correct result.", "The result is in option b.", "Answer D follows from the calculation."):
            with self.subTest(text=text), self.assertRaises(AuthoredTeachingFormatError):
                freeze_authored_question({**question(), "explanation": text})
        # Literal letters as subject answers remain valid; no subject allowlist.
        q = {**question(), "prompt": "Which letter comes first in the sequence A, B, C, D?",
             "choices": ["A", "B", "C", "D"], "expectedAnswer": "A",
             "explanation": "The letter A is the first symbol in the displayed sequence."}
        self.assertEqual(freeze_authored_question(q), q)

    def test_dense_reordered_reviews_preserve_exact_keys_and_diagnostic_text(self):
        items = [item(0), item(1)]
        items[1]["choices"] = ['"e\u0301  x"', '"x"', '"y"', '"z"']
        records = [review(1, answer=items[1]["choices"][0], valid=False,
                          explanationSupport="unsupported", issues=[" \tA material claim is not established.\r\n"]), review(0)]
        before = copy.deepcopy((items, records))
        parsed = validate_authored_reviews("```json\n" + encoded(*records) + "\n```", list(reversed(items)))
        self.assertEqual(parsed, list(reversed(records)))
        self.assertEqual(parsed[1]["answer"].encode(), items[1]["choices"][0].encode())
        parsed[1]["issues"].append("Changed copy")
        self.assertEqual((items, records), before)
        self.assertNotIn("expectedAnswer", items[0])

    def test_missing_extra_duplicate_or_wrong_index_invalidates_entire_batch(self):
        items = [item(0), item(1)]
        for records in ([review(0)], [review(0), review(1), review(2)], [review(0), review(0)],
                        [review(0), review(True)], [review(0), review("1")], [review(0), review(-1)],
                        [review(0), review(2)]):
            with self.subTest(records=records), self.assertRaises(AuthoredTeachingFormatError):
                validate_authored_reviews(encoded(*records), items)
        for bad_items in ([], [item(1)], [item(0), item(0)], [item(True)]):
            with self.assertRaises(AuthoredTeachingFormatError):
                validate_authored_reviews(encoded(review(0)), bad_items)

    def test_extra_replacement_or_verification_fields_and_duplicate_json_keys_fail(self):
        for key, value in (("explanation", "Replacement text"), ("choiceExplanations", {}),
                           ("verificationVersion", 1), ("verificationPolicyRevision", 99), ("prompt", "Rewrite")):
            with self.subTest(key=key), self.assertRaises(AuthoredTeachingFormatError):
                validate_authored_reviews(encoded(review(**{key: value})), [item()])
        for raw in ('{"reviews":[],"reviews":[]}', encoded(review()).replace('"valid": true', '"valid": true,"valid":false'),
                    '{"reviews":', json.dumps({"reviews": [review()], "replacement": {}}),
                    json.dumps([review()])):
            with self.subTest(raw=raw), self.assertRaises(AuthoredTeachingFormatError):
                validate_authored_reviews(raw, [item()])

    def test_response_types_outcomes_and_issue_limits_are_exact(self):
        changes = [{"valid": 1}, {"difficulty": True}, {"difficulty": 0}, {"difficulty": 6},
                   {"answer": None}, {"answer": " 4"}, {"answer": ""},
                   {"explanationSupport": None}, {"explanationSupport": "maybe"},
                   {"issues": "none"}, {"issues": [""]}, {"issues": [" \n"]},
                   {"issues": [True]}, {"issues": ["x" * 601]}, {"issues": ["issue"] * 9}]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(AuthoredTeachingFormatError):
                validate_authored_reviews(encoded(review(**change)), [item()])
        for key in review():
            malformed = review()
            malformed.pop(key)
            with self.assertRaises(AuthoredTeachingFormatError):
                validate_authored_reviews(encoded(malformed), [item()])
        r = review(issues=["é" * 600] * 8)
        self.assertEqual(validate_authored_reviews(encoded(r), [item()]), [r])

    def test_invalid_item_can_retain_known_key_but_never_becomes_eligible(self):
        for answer in ("4", ""):
            r = review(valid=False, answer=answer)
            self.assertEqual(validate_authored_reviews(encoded(r), [item()]), [r])
            self.assertEqual(authored_review_rejection_reason(r, question()), "rejected_by_model")
        with self.assertRaises(AuthoredTeachingFormatError):
            validate_authored_reviews(encoded(review(valid=False, answer="unoffered")), [item()])

    def test_support_and_issues_veto_even_when_model_sets_valid_true_and_right_key(self):
        for change, expected in (
            ({"explanationSupport": "unsupported"}, "unsupported_authored_explanation"),
            ({"explanationSupport": "uncertain"}, "uncertain_authored_explanation"),
            ({"issues": ["The calculation silently changes the stated quantity."]}, "reported_issues"),
            ({"answer": "5"}, "answer_disagreement"),
        ):
            r = review(**change)
            parsed = validate_authored_reviews(encoded(r), [item()])[0]
            self.assertEqual(authored_review_rejection_reason(parsed, question()), expected)
        # The pure gate does not impose the caller's requested challenge floor.
        self.assertIsNone(authored_review_rejection_reason(review(difficulty=1), question()))
        self.assertEqual(authored_review_rejection_reason(review(valid=False, issues=["Material issue"]), question()), "reported_issues")

    def test_gate_revalidates_direct_calls_and_prompt_defines_full_teaching_audit(self):
        with self.assertRaises(AuthoredTeachingFormatError):
            authored_review_rejection_reason(review(issues=None), question())
        with self.assertRaises(AuthoredTeachingFormatError):
            authored_review_rejection_reason(review(), {**question(), "explanation": "too short"})
        self.assertIn(DIFFICULTY_RUBRIC, AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT)
        for requirement in ("every material claim", "A correct answer alone", "all four exact choices",
                            "not a correctness certificate", "The main explanation can reveal"):
            self.assertIn(requirement, AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT)


if __name__ == "__main__":
    unittest.main()
