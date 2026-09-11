import copy
import unittest
from unittest.mock import patch

from evals import checkpoint_delivery_check as delivery
from verification_policy import VERIFICATION_POLICY_REVISION


def captured_question(index=1):
    return {
        "prompt": f"A cart travels {index + 2} metres each second for 4 seconds. What distance does it travel?",
        "choices": [f"{4 * (index + 2)} m", f"{index + 6} m", f"{index + 2} m", f"{8 * (index + 2)} m"],
        "expectedAnswer": f"{4 * (index + 2)} m",
        "explanation": "\r\nDistance equals speed multiplied by time; preserve e\u0301 here.\t\r\n",
        "choiceExplanations": {f"{4 * (index + 2)} m": "\tMultiply the stated speed by four seconds.\r\n"},
        "verificationVersion": 1,
        "verificationPolicyRevision": VERIFICATION_POLICY_REVISION,
        "topic": "Speed and distance",
        "difficulty": 3,
        "format": "Multiple Choice",
    }


def captured_operation(questions):
    return {"questions": questions, "request": {
        "goal": {"title": "Interpret motion", "currentLevel": "Basic rates",
                 "category": "Custom", "focusAreas": "distance and speed"},
        "sourceDocuments": [{"name": "Rate definition", "text": "Distance is speed multiplied by elapsed time."}],
        "targetCount": 5, "minimumDifficulty": 3,
    }}


def complete_question(index=1):
    question = captured_question(index)
    question["verificationPolicyRevision"] = 4
    question["choiceExplanations"] = {
        choice: f"\tChoice {position} feedback retains exact e\u0301 and spacing.\r\n"
        for position, choice in enumerate(question["choices"])
    }
    return question


class DeliveryCheckTests(unittest.TestCase):
    def test_complete_selector_binds_bank_and_claim_without_changing_teaching(self):
        operation = captured_operation([complete_question()])
        operation["request"]["feedbackContract"] = "authored_complete"
        actual_claim = delivery.question_bank.claim_questions

        def inspect_claim(payload, event, **kwargs):
            self.assertEqual(kwargs["dynamodb_client"].meta["feedbackContract"], {"S": "authored_complete"})
            self.assertEqual(payload["minimumVerificationPolicyRevision"], 4)
            return actual_claim(payload, event, **kwargs)

        with patch.object(delivery.question_bank, "claim_questions", side_effect=inspect_claim) as claim:
            result = delivery.check_capture({"operations": [operation]})
        self.assertEqual(claim.call_count, 2)
        self.assertTrue(result["passed"])
        observed = result["operations"][0]
        self.assertEqual(observed["request"], operation["request"])
        self.assertEqual(observed["bank_feedback_contract"], "authored_complete")
        self.assertEqual(observed["claim_request"]["minimumVerificationPolicyRevision"], 4)
        self.assertEqual(delivery._without_remote(observed["claim_response"]["questions"][0]), operation["questions"][0])

    def test_complete_bank_keeps_rejected_inventory_in_runtime_denominator(self):
        for damage in ("revision2", "revision3", "missingFeedback", "canonicalKeyMismatch"):
            question = complete_question()
            if damage.startswith("revision"):
                question["verificationPolicyRevision"] = int(damage[-1])
            elif damage == "missingFeedback":
                question["choiceExplanations"].pop(question["choices"][0])
            else:
                previous_choice = question["choices"][0]
                question["choices"][0] = "Cafe\u0301 reasoning"
                question["choiceExplanations"][question["choices"][0]] = question["choiceExplanations"].pop(previous_choice)
                question["expectedAnswer"] = "Caf\u00e9 reasoning"
            operation = captured_operation([question])
            operation["request"]["feedbackContract"] = "authored_complete"
            with self.subTest(damage=damage):
                result = delivery.check_capture({"operations": [operation]})
                self.assertFalse(result["passed"])
                self.assertEqual(result["runtime_returned_count"], 1)
                self.assertEqual(result["bank_claimable_count"], 0)
                self.assertEqual(result["operations"][0]["runtime_questions"], [question])

    def test_unknown_contract_revision_and_original_selector_mismatch_rejected(self):
        bad_contract = captured_operation([complete_question()])
        bad_contract["request"]["feedbackContract"] = "other"
        bad_revision = captured_operation([complete_question()])
        bad_revision["questions"][0]["verificationPolicyRevision"] = 5
        original = captured_operation([])["request"]
        original["feedbackContract"] = "authored_complete"
        mismatch = {"operations": [{"case_id": "motion", "questions": []}], "plan": {
            "operations": [{"request": captured_operation([])["request"]}],
            "origin": {"cases": [{"case_id": "motion", "payload": original}]},
        }}
        for capture in ({"operations": [bad_contract]}, {"operations": [bad_revision]}, mismatch):
            with self.subTest(capture=capture), self.assertRaises(ValueError):
                delivery.check_capture(capture)

    def test_real_prepare_and_atomic_claim_preserve_exact_payload_and_replay(self):
        questions = [captured_question(), captured_question(2)]
        questions[1]["choiceExplanations"] = {}
        capture = {"operations": [captured_operation(questions)]}
        before = copy.deepcopy(capture)
        result = delivery.check_capture(capture)
        self.assertTrue(result["passed"])
        self.assertEqual(capture, before)
        operation = result["operations"][0]
        self.assertIsNone(operation["bank_feedback_contract"])
        self.assertEqual(operation["claim_request"]["minimumVerificationPolicyRevision"], 2)
        self.assertEqual(operation["runtime_returned_count"], 2)
        self.assertEqual(operation["bank_claimable_count"], 2)
        self.assertEqual(operation["transaction_count"], 1)
        self.assertEqual(operation["claim_response"], operation["repeat_claim_response"])
        for original, claimed in zip(questions, operation["claim_response"]["questions"], strict=True):
            self.assertEqual(delivery._without_remote(original), delivery._without_remote(claimed))
        self.assertIsNone(result["client_retained_count"])

    def test_preparation_loss_is_retained_and_does_not_hide_later_operation(self):
        question = captured_question()
        changed = {**question, "explanation": "A changed explanation cannot rescue a duplicate stem."}
        capture = {"operations": [captured_operation([question, changed]),
                                  captured_operation([captured_question(2)])]}
        result = delivery.check_capture(capture)
        self.assertFalse(result["passed"])
        self.assertEqual(result["runtime_returned_count"], 3)
        self.assertEqual(result["bank_claimable_count"], 2)
        self.assertEqual(len(result["operations"][0]["runtime_questions"]), 2)
        self.assertTrue(result["operations"][1]["passed"])

    def test_original_case_context_is_exported_with_actual_target(self):
        original = captured_operation([])["request"]
        original["targetCount"] = 2
        normalized = {**original, "goal": {"title": "Normalized title"}, "targetCount": 5}
        capture = {"operations": [{"case_id": "motion", "questions": [captured_question()]}],
                   "plan": {"operations": [{"request": normalized}],
                            "origin": {"cases": [{"case_id": "motion", "payload": original}]}}}
        result = delivery.check_capture(capture)
        exported = result["operations"][0]["request"]
        self.assertEqual(exported["goal"], original["goal"])
        self.assertEqual(exported["sourceDocuments"], original["sourceDocuments"])
        self.assertEqual(exported["targetCount"], 5)
        self.assertEqual(exported["minimumDifficulty"], 3)

    def test_empty_operation_keeps_zero_denominator(self):
        result = delivery.check_capture({"operations": [captured_operation([])]})
        self.assertEqual(result["runtime_returned_count"], 0)
        self.assertEqual(result["bank_claimable_count"], 0)
        self.assertIsNone(result["client_retained_count"])


if __name__ == "__main__":
    unittest.main()
