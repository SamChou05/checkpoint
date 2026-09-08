"""Pure contract controls; no subject execution, provider or model calls."""

import copy
import json
import unittest

from evals.question_solution_construction import (
    ConstructionContentError,
    ConstructionFormatError,
    PROMPTS,
    build_question,
    prompt_for,
    review_observation,
    solution_eligible,
    validate_distractors,
    validate_solution,
    validate_task,
)


def raw(value):
    return json.dumps(value, ensure_ascii=False)


def task():
    return {
        "prompt": "Which real number has a square equal to minus one?",
        "topic": "Real numbers",
        "objective": "Distinguish existence from a candidate value",
        "difficulty": 3,
    }


def solution():
    return {
        "status": "answered",
        "answerText": "No real solution exists.",
        "support": "The square of every real number is nonnegative.",
        "assumptionsRequired": [],
    }


def distractors():
    return {
        "distractors": [
            {"text": text, "explanation": reason}
            for text, reason in (
                ("Zero.", "Squaring zero yields zero rather than minus one."),
                ("One.", "Squaring one yields positive one rather than minus one."),
                ("Minus one.", "The product of two negative ones is positive one."),
            )
        ],
        "explanation": "Real squares cannot be negative, so the requested real value does not exist.",
        "answerExplanation": "Nonnegativity rules out every real candidate.",
    }


def review(question, **changes):
    return raw(
        {
            "reviews": [
                {
                    "index": 0,
                    "valid": True,
                    "answer": question["expectedAnswer"],
                    "difficulty": 3,
                    "explanation": question["explanation"],
                    "choiceExplanations": question["choiceExplanations"],
                    **changes,
                }
            ]
        }
    )


def payload(user):
    return json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])


class SolutionConstructionTests(unittest.TestCase):
    def setUp(self):
        self.context = {
            "goal": {
                "title": "Reason from constraints",
                "focusAreas": "Scope and possibility",
            },
            "sourceDocuments": [
                {
                    "name": "Notation",
                    "text": 'Literal "red  blue"\n    exact indentation',
                }
            ],
            "minimumDifficulty": 3,
        }

    def test_legitimate_negative_answer_is_frozen_and_never_replaced_by_positive_key(
        self,
    ):
        solved = validate_solution(raw({"solution": solution()}))
        self.assertTrue(solution_eligible(solved))
        question = build_question(task(), solved, distractors())
        self.assertEqual(question["expectedAnswer"], solved["answerText"])
        for positive in question["choices"][1:]:
            observed = review_observation(
                review(question, answer=positive), question, 3
            )
            self.assertEqual(
                observed,
                {
                    "eligible": False,
                    "disposition": "answer_disagreement",
                    "question": None,
                },
            )
        observed = review_observation(review(question), question, 3)
        self.assertTrue(observed["eligible"])
        self.assertEqual(observed["question"]["expectedAnswer"], solved["answerText"])
        self.assertNotIn("verificationVersion", observed["question"])
        self.assertNotIn("verificationPolicyRevision", observed["question"])

    def test_unknown_missing_or_required_assumptions_cannot_construct(self):
        for status in ("uncertain", "invalid_task"):
            solved = {**solution(), "status": status, "answerText": ""}
            self.assertFalse(
                solution_eligible(validate_solution(raw({"solution": solved})))
            )
            with self.assertRaises(ConstructionContentError):
                build_question(task(), solved, distractors())
        solved = {
            **solution(),
            "assumptionsRequired": ["An additional unstated restriction holds."],
        }
        self.assertFalse(solution_eligible(solved))
        with self.assertRaises(ConstructionContentError):
            prompt_for("distractor", self.context, task=task(), solution=solved)
        for missing in SOLUTION_KEYS:
            solved = solution()
            del solved[missing]
            with self.assertRaises(ConstructionFormatError):
                validate_solution(raw({"solution": solved}))
        for invalid in (None, "unknown", False, [None]):
            with self.assertRaises(ConstructionFormatError):
                validate_solution(
                    raw({"solution": {**solution(), "assumptionsRequired": invalid}})
                )
        with self.assertRaises(ConstructionFormatError):
            validate_solution(raw({"solution": {**solution(), "status": "resolved"}}))

    def test_nonidentifiability_is_an_answer_not_model_uncertainty(self):
        solved = {
            **solution(),
            "answerText": "Cannot be determined from the stated facts.",
            "support": "Two different values satisfy the given constraints.",
        }
        question = build_question(task(), solved, distractors())
        self.assertEqual(question["expectedAnswer"], solved["answerText"])
        # The constructor checks the boundary, not whether this proof fits task().
        self.assertTrue(solution_eligible(solved))
        with self.assertRaises(ConstructionFormatError):
            validate_solution(raw({"solution": {**solved, "status": "uncertain"}}))

    def test_forged_author_key_task_and_provenance_fields_reject(self):
        for field in (
            "expectedAnswer",
            "choices",
            "explanation",
            "verificationVersion",
            "verificationPolicyRevision",
        ):
            with self.subTest(field=field), self.assertRaises(ConstructionFormatError):
                validate_task(raw({"task": {**task(), field: "forged"}}))
        for field in (
            "prompt",
            "task",
            "solution",
            "answerText",
            "expectedAnswer",
            "verificationPolicyRevision",
        ):
            with self.subTest(field=field), self.assertRaises(ConstructionFormatError):
                validate_distractors(
                    raw({**distractors(), field: "replacement"}),
                    solution()["answerText"],
                )
        changed_row = distractors()
        changed_row["distractors"][0]["correct"] = True
        with self.assertRaises(ConstructionFormatError):
            build_question(task(), solution(), changed_row)
        with self.assertRaises(ConstructionFormatError):
            validate_solution(
                raw({"solution": {**solution(), "verificationPolicyRevision": 1}})
            )

    def test_preserves_exact_code_answer_unicode_and_feedback_without_clipping(self):
        authored = {
            **task(),
            "prompt": 'In Python 3, what is returned?\ndef f():\n    return "red  blue"\nf()\n',
            "objective": "Count e\u0301 literally",
        }
        solved = {
            **solution(),
            "answerText": '"red  blue"',
            "support": "Return preserves both spaces inside the string.",
        }
        proposed = distractors()
        proposed["explanation"] = "  The literal preserves both spaces.\n"
        original = copy.deepcopy((authored, solved, proposed))
        question = build_question(
            validate_task(raw({"task": authored})),
            validate_solution(raw({"solution": solved})),
            validate_distractors(raw(proposed), solved["answerText"]),
        )
        self.assertEqual(question["prompt"].encode(), authored["prompt"].encode())
        self.assertEqual(
            question["expectedAnswer"].encode(), solved["answerText"].encode()
        )
        self.assertEqual(question["objective"].encode(), authored["objective"].encode())
        self.assertEqual(question["explanation"], proposed["explanation"])
        observed = review_observation(review(question), question, 3)
        self.assertEqual(observed["question"]["prompt"], authored["prompt"])
        self.assertEqual(observed["question"]["explanation"], proposed["explanation"])
        self.assertEqual((authored, solved, proposed), original)

    def test_full_field_boundaries_reject_without_repair(self):
        for field, maximum in (("prompt", 320), ("topic", 140), ("objective", 140)):
            value = {**task(), field: "x" * maximum}
            self.assertEqual(validate_task(raw({"task": value}))[field], value[field])
            with self.assertRaises(ConstructionContentError):
                validate_task(raw({"task": {**value, field: value[field] + "x"}}))
        for field, maximum in (("answerText", 140), ("support", 600)):
            value = {**solution(), field: "x" * maximum}
            self.assertEqual(
                validate_solution(raw({"solution": value}))[field], value[field]
            )
            with self.assertRaises(ConstructionContentError):
                validate_solution(
                    raw({"solution": {**value, field: value[field] + "x"}})
                )
        for field, maximum in (("explanation", 420), ("answerExplanation", 280)):
            value = {**distractors(), field: "x" * maximum}
            self.assertEqual(
                validate_distractors(raw(value), solution()["answerText"])[field],
                value[field],
            )
            with self.assertRaises(ConstructionContentError):
                validate_distractors(
                    raw({**value, field: value[field] + "x"}), solution()["answerText"]
                )
        for field, maximum in (("text", 140), ("explanation", 280)):
            value = distractors()
            value["distractors"][0][field] = "x" * (maximum + 1)
            with self.assertRaises(ConstructionContentError):
                validate_distractors(raw(value), solution()["answerText"])
        with self.assertRaises(ConstructionContentError):
            validate_task(raw({"task": {**task(), "prompt": "\n" * 50 + "short"}}))
        with self.assertRaises(ConstructionContentError):
            validate_solution(raw({"solution": {**solution(), "answerText": "   "}}))

    def test_backend_choice_identity_rejects_boundary_and_unicode_collisions_only(self):
        for answer, rival in (("value", " value\t"), ("é", "e\u0301")):
            proposed = distractors()
            proposed["distractors"][0]["text"] = rival
            with self.assertRaises(ConstructionContentError):
                validate_distractors(raw(proposed), answer)
        proposed = distractors()
        proposed["distractors"][0]["text"] = '"red blue"'
        self.assertEqual(validate_distractors(raw(proposed), '"red  blue"'), proposed)
        proposed["distractors"][1]["text"] = proposed["distractors"][0]["text"]
        with self.assertRaises(ConstructionContentError):
            validate_distractors(raw(proposed), '"red  blue"')

    def test_prompts_use_allowlisted_context_and_reviewer_hides_every_prior_answer_field(
        self,
    ):
        context = copy.deepcopy(self.context)
        context.update(
            assessment="PRIVATE OUTCOME",
            source_provenance="PRIVATE PROVENANCE",
            expectedAnswer="PRIVATE KEY",
            existingQuestions=[{"answer": "PRIVATE HISTORY"}],
        )
        context["goal"]["assessment"] = "PRIVATE GOAL"
        context["sourceDocuments"][0]["assessment"] = "PRIVATE SOURCE"
        authored = {**task(), "difficulty": 5}
        solved = {
            **solution(),
            "support": "PRIVATE SOLVER SUPPORT",
            "answerText": "Frozen exact answer.",
        }
        proposed = distractors()
        proposed["explanation"] = "PRIVATE DISTRACTOR MAIN"
        proposed["answerExplanation"] = "PRIVATE ANSWER EXPLANATION"
        question = build_question(authored, solved, proposed)
        before = copy.deepcopy((context, authored, solved, question))
        for role in PROMPTS:
            system, user = prompt_for(
                role, context, task=authored, solution=solved, question=question
            )
            self.assertEqual(system, PROMPTS[role])
            data = payload(user)
            for marker in (
                "PRIVATE OUTCOME",
                "PRIVATE PROVENANCE",
                "PRIVATE KEY",
                "PRIVATE HISTORY",
                "PRIVATE GOAL",
                "PRIVATE SOURCE",
            ):
                self.assertNotIn(marker, user)
            if role == "author":
                self.assertEqual(
                    set(data), {"goal", "sourceDocuments", "minimumDifficulty"}
                )
                self.assertNotIn(solved["answerText"], user)
            if role == "solver":
                self.assertNotIn("choices", data["task"])
                self.assertNotIn("difficulty", data["task"])
                self.assertNotIn(solved["answerText"], user)
            if role == "reviewer":
                self.assertEqual(
                    set(data), {"goal", "sourceDocuments", "minimumDifficulty", "items"}
                )
                self.assertEqual(
                    set(data["items"][0]),
                    {"index", "prompt", "choices", "topic", "objective"},
                )
                self.assertCountEqual(data["items"][0]["choices"], question["choices"])
                self.assertNotIn("PRIVATE", user)
                self.assertEqual(
                    prompt_for(role, context, question=question), (system, user)
                )
            self.assertEqual(data["sourceDocuments"], self.context["sourceDocuments"])
        self.assertEqual((context, authored, solved, question), before)

    def test_review_requires_full_exact_feedback_and_rejects_disagreement_or_easy_content(
        self,
    ):
        question = build_question(task(), solution(), distractors())
        missing = dict(question["choiceExplanations"])
        missing.pop(question["choices"][0])
        with self.assertRaises(ConstructionContentError):
            review_observation(
                review(question, choiceExplanations=missing), question, 3
            )
        with self.assertRaises(ConstructionContentError):
            review_observation(review(question, explanation="x" * 421), question, 3)
        with self.assertRaises(ConstructionFormatError):
            review_observation(
                review(question, verificationPolicyRevision=1), question, 3
            )
        with self.assertRaises(ConstructionFormatError):
            review_observation(review(question, index=True), question, 3)
        for changes, expected in (
            ({"difficulty": 2}, "difficulty_floor"),
            ({"answer": "Not one of the offered values."}, "answer_disagreement"),
            (
                {
                    "explanation": "Option A is correct because no real square is negative."
                },
                "answer_labels",
            ),
            (
                {"valid": False, "answer": "", "choiceExplanations": {}},
                "rejected_by_model",
            ),
        ):
            result = review_observation(review(question, **changes), question, 3)
            self.assertEqual(result["disposition"], expected)
            self.assertFalse(result["eligible"])
            self.assertIsNone(result["question"])

    def test_malformed_and_fenced_raw_use_runtime_json_parser(self):
        self.assertEqual(
            validate_task("```json\n" + raw({"task": task()}) + "\n```"), task()
        )
        for value in (
            "not json",
            "[]",
            '{"task":{},"task":{}}',
            raw({"task": task(), "key": "forged"}),
        ):
            with self.assertRaises(ConstructionFormatError):
                validate_task(value)
        for value in (True, 3.0, "3"):
            with self.assertRaises(ConstructionFormatError):
                validate_task(raw({"task": {**task(), "difficulty": value}}))
        with self.assertRaises(ConstructionFormatError):
            prompt_for("unknown", self.context)
        with self.assertRaises(ConstructionFormatError):
            prompt_for("author", {"goal": {"title": "Missing minimum"}})


SOLUTION_KEYS = ("status", "answerText", "support", "assumptionsRequired")


if __name__ == "__main__":
    unittest.main()
