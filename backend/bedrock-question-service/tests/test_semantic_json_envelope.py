"""Whole-response admission with fixed callbacks, not semantic correctness proof."""

import copy
import json
import unittest
from unittest.mock import Mock

from complete_question_solution import CompleteSolutionFormatError, validate_batch
from lambda_test_support import _complete_solution, _raw_question, _request_payload
from question_quality import _extract_json_object, _strict_json_object
from question_teaching import AuthoredTeachingFormatError, validate_authored_reviews
from question_verification import verify_questions
from request_contract import _normalize_request
from service_errors import ProviderError
from test_complete_question_solution import question, raw as encoded_solution, record
from test_question_teaching import encoded, item, review


def envelopes(text):
    return (text, " \t\r\n" + text + "\r\n ",
            "```json\n" + text + "\n```", "```\r\n" + text + "\r\n```")


def malformed(text):
    objection = "The premises do not establish the declared answer."
    return (objection + "\n" + text, text + "\n" + objection,
            objection + "\n```json\n" + text + "\n```",
            "```json\n" + text + "\n```\n" + objection,
            "```json\n" + text, text + "\n{}",
            text[:-1] + "," + text[1:])  # Duplicate the root property.


class SemanticJsonEnvelopeTests(unittest.TestCase):
    def test_whole_objects_and_sole_fences_preserve_exact_strings(self):
        value = {"reason": '  e\u0301 != é; "a  b"\r\n    ```json {literal}\t ',
                 "nested": {"NaN": "Infinity", "values": [True, None, 1.25]}}
        raw = json.dumps(value, ensure_ascii=False)
        for text in envelopes(raw):
            with self.subTest(text=text):
                parsed = _strict_json_object(text)
                self.assertEqual(parsed, value)
                self.assertEqual(parsed["reason"].encode(), value["reason"].encode())

    def test_ignored_prose_incomplete_multiple_and_nonobject_envelopes_fail(self):
        for text in (*malformed('{"reviews":[]}'), "", "[]", "null", "true", "1",
                     '"object"', None, {}, '\ufeff{"reviews":[]}',
                     '```python\n{"reviews":[]}\n```',
                     '```json{"reviews":[]}```',
                     '```json\n{"reviews":[]}\n```\n```json\n{}\n```'):
            with self.subTest(text=text), self.assertRaises(ProviderError):
                _strict_json_object(text)

    def test_duplicate_keys_and_nonfinite_numbers_fail_at_every_depth(self):
        invalid = ['{"x":1,"x":2}', '{"nested":[{"x":1,"\\u0078":2}]}']
        for number in ("NaN", "Infinity", "-Infinity", "1e999", "-1e999"):
            invalid.extend(('{"x":' + number + '}', '{"nested":[{"x":' + number + '}]}'))
        for raw in invalid:
            for text in envelopes(raw):
                with self.subTest(text=text), self.assertRaises(ProviderError):
                    _strict_json_object(text)

    def test_author_salvage_remains_separate_and_unchanged(self):
        for text in ('Author commentary. {"questions":[]} End.',
                     'Author commentary. [] End.'):
            self.assertEqual(_extract_json_object(text), {"questions": []})
            with self.assertRaises(ProviderError):
                _strict_json_object(text)

    def test_role_parsers_preserve_diagnostics_and_use_their_typed_errors(self):
        solution = record(question())
        reason = '  Keep e\u0301 and "a  b" exact.\r\n    ``` remains literal.  '
        solution["choices"][0]["reason"] = reason
        audited = review(issues=[reason])
        for parser, text, items, expected, error in (
            (validate_batch, encoded_solution(solution), [question()], [solution], CompleteSolutionFormatError),
            (validate_authored_reviews, encoded(audited), [item()], [audited], AuthoredTeachingFormatError),
        ):
            for whole in envelopes(text):
                self.assertEqual(parser(whole, items), expected)
            for broken in malformed(text):
                with self.subTest(parser=parser.__name__, text=broken), self.assertRaises(error):
                    parser(broken, items)


class SemanticEnvelopeAdmissionTests(unittest.TestCase):
    modes = (
        ("stem_only", "reviewer_written"),
        ("complete_choices", "reviewer_written"),
        ("complete_choices", "authored_solution"),
    )

    def setUp(self):
        self.questions = [
            _raw_question("Which conclusion follows from these stated conditions?"),
            _raw_question("Which second conclusion follows from these stated conditions?"),
        ]
        self.request = _normalize_request(_request_payload(target_count=2))

    def solutions(self, contract, prompt):
        items = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])["items"]
        return json.dumps({"solutions": [
            _complete_solution(item, q["expectedAnswer"]) if contract == "complete_choices" else {
                "index": item["index"], "outcome": "resolved", "answer": q["expectedAnswer"],
                "limitations": "", "assumptionsRequired": [],
            }
            for item, q in zip(items, self.questions, strict=True)
        ]})

    def reviews(self, feedback):
        return json.dumps({"reviews": [
            {"index": index, "valid": True, "answer": q["expectedAnswer"], "difficulty": 3,
             **({"explanationSupport": "supported", "issues": []}
                if feedback == "authored_solution" else {
                    "explanation": q["explanation"],
                    "choiceExplanations": {c: "The fixture premises determine this answer's adequacy."
                                           for c in q["choices"]},
                })}
            for index, q in enumerate(self.questions)
        ]})

    def test_valid_whole_and_fenced_responses_keep_existing_admission_and_stamps(self):
        for contract, feedback in self.modes:
            for wrap in range(4):
                solver = Mock(side_effect=lambda _s, p: envelopes(self.solutions(contract, p))[wrap])
                reviewer = Mock(return_value=envelopes(self.reviews(feedback))[wrap])
                original = copy.deepcopy(self.questions)
                result = verify_questions(self.questions, self.request, reviewer, solve=solver,
                                          solver_contract=contract, feedback_contract=feedback)
                self.assertEqual(len(result), 2)
                self.assertEqual(self.questions, original)
                solver.assert_called_once()
                reviewer.assert_called_once()
                revision = 3 if feedback == "authored_solution" else (2 if contract == "complete_choices" else 1)
                for q, accepted in zip(original, result, strict=True):
                    self.assertEqual(accepted["verificationVersion"], 1)
                    self.assertEqual(accepted["verificationPolicyRevision"], revision)
                    self.assertEqual(accepted["explanation"], q["explanation"])

    def test_entire_solver_batch_failure_prevents_final_review_in_every_contract(self):
        for contract, feedback in self.modes:
            for mutation in range(7):
                with self.subTest(contract=contract, feedback=feedback, mutation=mutation):
                    solver = Mock(side_effect=lambda _s, p: malformed(self.solutions(contract, p))[mutation])
                    reviewer, metrics = Mock(), {}
                    before = copy.deepcopy(self.questions)
                    result = verify_questions(self.questions, self.request, reviewer, metrics, solve=solver,
                                              solver_contract=contract, feedback_contract=feedback)
                    self.assertEqual(result, [])
                    solver.assert_called_once()
                    reviewer.assert_not_called()
                    self.assertEqual(self.questions, before)
                    self.assertEqual(metrics["QuestionQuality"]["review"], {"invalid_solution": 2})

    def test_entire_review_batch_failure_prevents_stamping_in_every_contract(self):
        for contract, feedback in (*self.modes, (None, "reviewer_written")):
            for text in malformed(self.reviews(feedback)):
                with self.subTest(contract=contract, feedback=feedback, text=text):
                    solver = Mock(side_effect=lambda _s, p: self.solutions(contract, p)) if contract else None
                    reviewer, metrics = Mock(return_value=text), {}
                    before = copy.deepcopy(self.questions)
                    result = verify_questions(self.questions, self.request, reviewer, metrics, solve=solver,
                                              solver_contract=contract or "stem_only", feedback_contract=feedback)
                    self.assertEqual(result, [])
                    reviewer.assert_called_once()
                    if solver:
                        solver.assert_called_once()
                    self.assertEqual(self.questions, before)
                    reason = "invalid_authored_review" if feedback == "authored_solution" else "invalid_json"
                    self.assertEqual(metrics["QuestionQuality"]["review"], {reason: 2})


if __name__ == "__main__":
    unittest.main()
