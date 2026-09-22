"""Feedback must survive display reordering without losing literal subject text."""

import copy
import json
from pathlib import Path
import unittest

from native_output_contracts import adapt_native_response
from question_verification import verify_questions


ROOT = Path(__file__).resolve().parents[3]


def question():
    return {
        "prompt": "What is the sum of two and two?",
        "expectedAnswer": "4", "choices": ["4", "5", "6", "7"],
        "explanation": "Adding the two stated quantities gives four.",
        "topic": "Arithmetic", "difficulty": 2,
    }


def review(item, explanation):
    return {
        "index": 0, "valid": True, "answer": item["expectedAnswer"],
        "difficulty": 2, "explanation": explanation,
        "choiceExplanations": {
            choice: "Compare this proposed value with the stated calculation."
            for choice in item["choices"]
        },
    }


class ReviewAnswerReferenceTests(unittest.TestCase):
    def admit(self, item, result):
        before = copy.deepcopy((item, result))
        metrics = {}
        accepted = verify_questions(
            [item], {"minimumDifficulty": 2},
            lambda *_: json.dumps({"reviews": [result]}, ensure_ascii=False),
            metrics, preserve_reviewed_text=True,
        )
        self.assertEqual((item, result), before)
        return accepted, metrics

    def test_main_and_each_choice_feedback_reject_display_position_references(self):
        item = question()
        references = [
            "Only the first choice gives the computed total.",
            "The second option gives a different total.",
            "The THIRD ANSWER gives a different total.",
            "The fourth-choice total is too large.",
            "The last option gives a different total.",
            "The 1st answer gives the computed total.",
            "The first two choices give different totals.",
            "Option 2 gives a different total.",
            "Choice #3 gives a different total.",
            "Answer number 4 gives a different total.",
            "Answer number two gives a different total.",
            "Option two gives a different total.",
            "Choice 2nd gives a different total.",
            "The choice\nnumber 5 gives a different total.",
            "Option#42 names a nonexistent displayed option.",
            "Choice no. 5 names a nonexistent displayed choice.",
            "Option A gives the computed total.",
        ]
        for text in references:
            for location in [None, *item["choices"]]:
                with self.subTest(text=text, location=location):
                    result = review(item, item["explanation"])
                    if location is None:
                        result["explanation"] = text
                    else:
                        result["choiceExplanations"][location] = text
                    accepted, metrics = self.admit(item, result)
                    self.assertEqual(accepted, [])
                    self.assertEqual(metrics["QuestionQuality"]["review"]["answer_labels"], 1)

    def test_ordinary_subject_positions_are_not_display_references(self):
        item = question()
        for text in (
            "The first bus arrives before the second bus.",
            "The second array element contains the requested value.",
            "The word 'first' names a rank rather than a quantity.",
            "First compute the total, then compare the proposed values.",
            "The fourth power of two is sixteen, a different result.",
            "The answer 42 follows from multiplying six by seven.",
            "The answer 1500 follows from multiplying fifteen by one hundred.",
            "The answer 1,500 follows from multiplying fifteen by one hundred.",
            "The answer 2.5 follows from dividing five by two.",
            "The answer -1 follows from subtracting two from one.",
            "The answer 1/2 follows from dividing one by two.",
            "The answer 2% is the percentage represented by 0.02.",
            "The 99th answer received by the survey is retained in its data.",
        ):
            with self.subTest(text=text):
                accepted, _ = self.admit(item, review(item, text))
                self.assertEqual(accepted[0]["explanation"], text)

    def test_bare_numbers_are_limited_to_the_four_display_positions(self):
        item = question()
        for noun in ("choice", "option", "answer"):
            for position in range(1, 5):
                text = f"The {noun} {position} gives the expected total."
                with self.subTest(text=text):
                    self.assertEqual(self.admit(item, review(item, text))[0], [])

    def test_complete_quoted_offered_literals_remain_exact(self):
        item = {**question(), "prompt": "Which phrase names the preferred selection?",
                "expectedAnswer": "first choice",
                "choices": ["first choice", "bus stop", "array index", "unit price"]}
        for left, right in (("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’"), ("`", "`")):
            text = f"The phrase {left}first choice{right} names the preferred selection."
            with self.subTest(text=text):
                accepted, _ = self.admit(item, review(item, text))
                self.assertEqual(accepted[0]["explanation"], text)

    def test_explicit_quoted_stem_literals_remain_exact(self):
        item = {**question(), "prompt": 'In the phrase "first choice", which word names a rank?',
                "expectedAnswer": "first", "choices": ["first", "choice", "both", "neither"]}
        text = 'In "first choice", the word first names a rank.'
        accepted, _ = self.admit(item, review(item, text))
        self.assertEqual(accepted[0]["explanation"], text)

    def test_quoting_an_unbound_display_reference_does_not_exempt_it(self):
        item = question()
        for text in (
            'Only the "first choice" gives the computed total.',
            "Only the 'second option' gives the computed total.",
            "Only the `answer number 2` gives the computed total.",
        ):
            with self.subTest(text=text):
                self.assertEqual(self.admit(item, review(item, text))[0], [])

    def test_quoted_literal_exemption_is_exact_and_local_to_the_bound_span(self):
        item = {**question(), "choices": ["First Choice", "bus stop", "array index", "unit price"],
                "expectedAnswer": "First Choice"}
        for text in (
            'The phrase "first choice" names the preferred selection.',
            'The phrase "First  Choice" names the preferred selection.',
            'The phrase "First Choice" is correct because it is the first option.',
        ):
            with self.subTest(text=text):
                self.assertEqual(self.admit(item, review(item, text))[0], [])

    def test_exact_live_feedback_replay_rejects_ordinal_item_without_losing_peers(self):
        path = ROOT / "docs/evidence/question-reliability-release-20260922/pipeline-capture-v2.json"
        capture = json.loads(path.read_text())
        call = capture["calls"][8]
        raw = "\n".join(block["text"] for block in call["response"]["output"]["message"]["content"] if "text" in block)
        adapted = adapt_native_response(raw, "default_reviewer_v1")
        prompt = call["request"]["messages"][0]["content"][0]["text"]
        inputs = json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])["items"]
        original = next(job for job in capture["jobs"] if job["index"] == 2)["accepted"]
        by_prompt = {item["prompt"]: item for item in original}
        questions = [copy.deepcopy(by_prompt[item["prompt"]]) for item in inputs]
        metrics = {}
        accepted = verify_questions(
            questions, {"minimumDifficulty": 2}, lambda *_: adapted,
            metrics, preserve_reviewed_text=True,
        )
        self.assertEqual([item["prompt"] for item in accepted], [item["prompt"] for index, item in enumerate(questions) if index != 1])
        self.assertEqual(metrics["QuestionQuality"]["review"]["answer_labels"], 1)
        self.assertEqual(accepted[0]["explanation"], questions[0]["explanation"])
        # Remaining semantic defects in this old capture are not repaired or
        # claimed to be caught by a narrow display-reference guard.


if __name__ == "__main__":
    unittest.main()
