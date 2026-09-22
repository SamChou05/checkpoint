"""Bounded display-label cues preserve real literals, subparts and expressions."""

import copy
import json
import unittest

from answer_position_references import contains_answer_label_references
from question_teaching import AuthoredTeachingFormatError, freeze_authored_question
from question_verification import verify_questions


def question():
    # Exact fresh author content that exposed the missed display reference.
    return {
        "prompt": "Which sentence uses an unambiguous pronoun reference?",
        "choices": [
            "The crew finished the repairs, and they looked excellent afterward.",
            "David handed the package to Kevin, who signed for it immediately.",
            "When the lamp hit the vase, it shattered completely.",
            "Lena told her coworker that she needed to leave early.",
        ],
        "expectedAnswer": "David handed the package to Kevin, who signed for it immediately.",
        "explanation": "In (b), 'who' unambiguously refers to Kevin and 'it' unambiguously refers to the package. "
                       "In the other options, the pronoun could refer to either of two previously mentioned nouns.",
        "topic": "Standard written English", "difficulty": 2,
    }


class ParenthesizedAnswerReferenceTests(unittest.TestCase):
    def test_exact_observed_main_is_rejected_without_modification(self):
        item = question()
        original = copy.deepcopy(item)
        self.assertTrue(contains_answer_label_references(item["explanation"], item))
        with self.assertRaises(AuthoredTeachingFormatError):
            freeze_authored_question(item)
        self.assertEqual(item, original)

    def test_display_nouns_locations_and_direct_judgments_cover_four_slots(self):
        for slot in ("a", "B", "c", "D", "1", "2", "3", "4"):
            for text in (
                f"In ({slot}), the pronoun refers to the named person.",
                f"For ( {slot} ), the two nouns give competing antecedents.",
                f"The option ({slot}) contains an ambiguous pronoun.",
                f"Choice({slot}) contains an ambiguous pronoun.",
                f"Answer ({slot}) is supported by the supplied facts.",
                f"({slot}) is correct because its antecedent is explicit.",
                f"Thus ({slot}) is the best sentence for this task.",
                f"The antecedent is explicit. ({slot}) was incorrect for another reason.",
            ):
                with self.subTest(text=text):
                    self.assertTrue(contains_answer_label_references(text, question()))

    def test_reviewer_main_and_each_choice_feedback_share_the_guard(self):
        item = question()
        for location in (None, *item["choices"]):
            record = {
                "index": 0, "valid": True, "answer": item["expectedAnswer"], "difficulty": 2,
                "explanation": "The relative pronoun refers directly to the named recipient.",
                "choiceExplanations": {choice: "Check whether the pronoun has a unique antecedent."
                                       for choice in item["choices"]},
            }
            if location is None:
                record["explanation"] = item["explanation"]
            else:
                record["choiceExplanations"][location] = item["explanation"]
            metrics = {}
            with self.subTest(location=location):
                self.assertEqual(verify_questions(
                    [item], {"minimumDifficulty": 2},
                    lambda *_: json.dumps({"reviews": [record]}), metrics,
                    preserve_reviewed_text=True,
                ), [])
                self.assertEqual(metrics["QuestionQuality"]["review"]["answer_labels"], 1)

    def test_variables_code_and_larger_expressions_are_not_slots(self):
        for text in (
            "The expression (b) has the same value as the variable b.",
            "(b) is positive because the supplied bound is greater than zero.",
            "Evaluating f(b) is correct when b is the supplied argument.",
            "Evaluating f (b) is correct when b is the supplied argument.",
            "f(b) is correct for the given function and input.",
            "f (b) is correct for the given function and input.",
            "a + (b) is correct after collecting the two terms.",
            "The tuple (b,) contains one element, the value of b.",
            "The syntax print(b) prints the value bound to b.",
            "Multiplication gives (b) * (c), with both factors specified.",
        ):
            with self.subTest(text=text):
                self.assertFalse(contains_answer_label_references(text, question()))

    def test_explicit_named_or_enumerated_stem_subparts_remain_usable(self):
        for prompt, text in (
            ("Evaluate these statements: (a) Every square is a rectangle; (b) Every rectangle is a square.",
             "In (b), the converse need not follow from the original implication."),
            ("Evaluate:\n(1) Every square is a rectangle.\n(2) Every rectangle is a square.",
             "For (2), a rectangle need not have all four sides equal."),
            ("Consider part (b): explain why two and two gives four.",
             "In (b), joining the two quantities gives four objects."),
            ("Is statement (B) correct: every square has four equal sides?",
             "(B) is correct because equal sides are required by the definition."),
            ("Evaluate:\n(a): The sum of two and two is four.\n(b): The sum of two and three is five.",
             "Thus (b) is correct by addition of the stated integers."),
        ):
            item = {**question(), "prompt": prompt, "explanation": text}
            with self.subTest(prompt=prompt):
                self.assertFalse(contains_answer_label_references(text, item))
                self.assertEqual(freeze_authored_question(item), item)

    def test_stem_bindings_are_specific_and_do_not_exempt_explicit_display_nouns(self):
        for prompt, text in (
            ("Evaluate (a) + (b) for a = 2 and b = 3.", "In (b), the offered sentence is correct."),
            ("Consider part (a): compute two plus two.", "In (b), the offered sentence is correct."),
            ("Which word occurs in the quoted phrase 'part (b)'?", "In (b), the offered sentence is correct."),
            ("Consider part (b): compute two plus two.", "Option (b) gives the correct result."),
        ):
            with self.subTest(prompt=prompt, text=text):
                self.assertTrue(contains_answer_label_references(text, {**question(), "prompt": prompt}))

    def test_exact_quoted_subject_literals_are_preserved_locally(self):
        for literal in ("In (b), the pronoun refers to Kevin.", "option (B)", "(B) is correct"):
            for left, right in (('"', '"'), ("'", "'"), ("“", "”"), ("‘", "’"), ("`", "`")):
                text = f"The literal {left}{literal}{right} occurs in the supplied text."
                for item in (
                    {**question(), "choices": [literal, "another literal", "third literal", "fourth literal"]},
                    {**question(), "prompt": f"Which word occurs in {left}{literal}{right}?"},
                ):
                    with self.subTest(literal=literal, quotation=left):
                        self.assertFalse(contains_answer_label_references(text, item))
                        self.assertTrue(contains_answer_label_references(text + " In (b), the answer is clear.", item))

    def test_quotes_alone_do_not_bind_a_display_reference(self):
        for text in (
            'The explanation says "In (b), the pronoun refers to Kevin."',
            'The offered sentence is "option (B)" in the list.',
            '"(B) is correct" because its pronoun has an antecedent.',
        ):
            with self.subTest(text=text):
                self.assertTrue(contains_answer_label_references(text, question()))


if __name__ == "__main__":
    unittest.main()
