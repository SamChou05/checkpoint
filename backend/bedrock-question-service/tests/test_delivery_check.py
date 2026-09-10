import copy
import unittest

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


class DeliveryCheckTests(unittest.TestCase):
    def test_real_prepare_and_atomic_claim_preserve_exact_payload_and_replay(self):
        questions = [captured_question(), captured_question(2)]
        questions[1]["choiceExplanations"] = {}
        capture = {"operations": [captured_operation(questions)]}
        before = copy.deepcopy(capture)
        result = delivery.check_capture(capture)
        self.assertTrue(result["passed"])
        self.assertEqual(capture, before)
        operation = result["operations"][0]
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
