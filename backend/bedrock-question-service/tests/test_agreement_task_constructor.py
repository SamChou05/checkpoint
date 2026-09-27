"""Independent controls for the closed, offline English agreement prototype."""

from dataclasses import replace
import json
import unittest

from agreement_task_constructor import (
    AgreementTaskError, COMPOUND_SCENE, LEARNER_FIELDS, SUPPORTED_OBJECTIVE, SUPPORTED_TOPIC,
    TASK_KIND, compile_mapped_english_slots, compile_question, task_schema,
)
from native_output_contracts import AuthorSlotContract


# Manually reviewed present-tense forms and clause-order keys. This table is
# deliberately independent of the prototype's scene records and rendering.
EXPECTED = {
    "coach": ("checks", "practice"),
    "librarian": ("organizes", "sort"),
    "chef": ("plans", "prepare"),
    "curator": ("labels", "catalog"),
}


def task(scene="coach", order="singular_first"):
    return {"kind": TASK_KIND, "scene": scene, "order": order}


def contract():
    return AuthorSlotContract(
        5, "constructed_quantitative",
        (("math-id", "math-objective", "Exact arithmetic", "Evaluate an expression", 3),
         ("english-id", "english-objective", SUPPORTED_TOPIC, SUPPORTED_OBJECTIVE, 2)),
        "math-id", 2,
    )


class AgreementTaskConstructorTests(unittest.TestCase):
    def test_every_closed_scene_and_order_has_one_exact_grammatical_pair(self):
        for scene, correct in EXPECTED.items():
            for order in ("singular_first", "plural_first"):
                expected = correct if order == "singular_first" else correct[::-1]
                for ordinal in (3, 4):
                    with self.subTest(scene=scene, order=order, ordinal=ordinal):
                        result = compile_question(task(scene, order), ordinal=ordinal)
                        self.assertEqual(set(result), set(LEARNER_FIELDS))
                        self.assertEqual(result["prompt"].count("___"), 2)
                        self.assertIn("Which ordered pair", result["prompt"])
                        self.assertEqual(len(result["choices"]), 4)
                        self.assertEqual(len(set(result["choices"])), 4)
                        self.assertEqual(result["expectedAnswer"], "; ".join(expected))
                        self.assertEqual(sum(choice == "; ".join(expected)
                                             for choice in result["choices"]), 1)
                        self.assertEqual(set(result["choiceExplanations"]), set(result["choices"]))
                        self.assertIn(expected[0], result["explanation"])
                        self.assertIn(expected[1], result["explanation"])
                        self.assertLessEqual(len(result["prompt"]), 320)
                        self.assertLessEqual(len(result["explanation"]), 420)
                        self.assertTrue(all(len(feedback) <= 280 for feedback in
                                            result["choiceExplanations"].values()))

    def test_each_wrong_pair_has_specific_feedback_for_its_agreement_errors(self):
        result = compile_question(task(), ordinal=3)
        feedback = result["choiceExplanations"]
        self.assertIn('"check" does not agree', feedback["check; practice"])
        self.assertIn('"practices" does not agree', feedback["checks; practices"])
        self.assertEqual(feedback["check; practices"].count("does not agree"), 2)
        self.assertNotIn("does not agree", feedback["checks; practice"])
        self.assertIn('head subject "the coach" is singular', result["explanation"])
        self.assertIn('head subject "the players" is plural', result["explanation"])
        self.assertIn('The form "checks" agrees.', result["explanation"])

    def test_compound_and_distributive_scene_is_distinct_and_unambiguous(self):
        for order in ("singular_first", "plural_first"):
            expected = ("prepare", "receives") if order == "singular_first" else (
                "receives", "prepare"
            )
            for ordinal in (3, 4):
                with self.subTest(order=order, ordinal=ordinal):
                    result = compile_question(task(COMPOUND_SCENE, order), ordinal=ordinal)
                    self.assertEqual(result["expectedAnswer"], "; ".join(expected))
                    self.assertEqual(len(set(result["choices"])), 4)
                    self.assertEqual(set(result["choiceExplanations"]), set(result["choices"]))
                    self.assertIn('"Maya and Theo" names two people joined by "and"',
                                  result["explanation"])
                    self.assertIn('"Every guest" is grammatically singular',
                                  result["explanation"])
                    self.assertLessEqual(len(result["explanation"]), 420)
                    self.assertTrue(all(len(text) <= 280 for text in
                                        result["choiceExplanations"].values()))
                    self.assertIn("Maya and Theo", result["prompt"])

    def test_model_cannot_write_answer_text_metadata_or_open_grammar(self):
        invalid = [
            {**task(), "correctChoice": "a"},
            {**task(), "skillID": "english-id"},
            {**task(), "explanation": "trust me"},
            {**task(), "choices": ["foo"]},
            {**task(), "scene": "invented"},
            {**task(), "order": "free_form"},
            {**task(), "kind": "prose"},
            {"kind": TASK_KIND, "scene": "chef"},
            [task()],
        ]
        for raw in invalid:
            with self.subTest(raw=raw), self.assertRaises(AgreementTaskError):
                compile_question(raw, ordinal=3)
        for ordinal in (0, 2, 5, True, "3"):
            with self.subTest(ordinal=ordinal), self.assertRaises(AgreementTaskError):
                compile_question(task(), ordinal=ordinal)
        schema = task_schema()
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(set(schema["required"]), {"kind", "scene", "order"})
        self.assertNotIn("answer", json.dumps(schema).lower())

    def test_exact_mapped_slots_preserve_original_ordinals_and_trusted_tags(self):
        candidates = compile_mapped_english_slots(
            {"3": task("coach"), "4": task(COMPOUND_SCENE, "plural_first")}, contract(),
        )
        self.assertEqual(set(candidates), {3, 4})
        first, second = candidates[3].content(), candidates[4].content()
        self.assertEqual(first["expectedAnswer"], "checks; practice")
        self.assertEqual(second["expectedAnswer"], "receives; prepare")
        for ordinal, question in ((3, first), (4, second)):
            self.assertEqual(candidates[ordinal].ordinal, ordinal)
            self.assertEqual(question["skillID"], "english-id")
            self.assertEqual(question["objectiveID"], "english-objective")
            self.assertEqual(question["topic"], SUPPORTED_TOPIC)
            self.assertEqual(question["objective"], SUPPORTED_OBJECTIVE)
            self.assertEqual(question["difficulty"], 2)
            self.assertEqual(question["format"], "Multiple Choice")
            self.assertEqual(candidates[ordinal].content(question), question)
        for changed in ({**first, "expectedAnswer": first["choices"][0]},
                        {**first, "skillID": "math-id"},
                        {**first, "choiceExplanations": {}},
                        {**first, "prompt": "other"},
                        {**first, "policyRevision": 8}):
            if changed == first:
                continue
            with self.assertRaises(AgreementTaskError):
                candidates[3].content(changed)
        with self.assertRaises(AgreementTaskError):
            replace(candidates[3], ordinal=4).content()

    def test_no_missing_extra_repeated_or_reassigned_mapped_slots(self):
        valid = {"3": task("coach"), "4": task(COMPOUND_SCENE)}
        for invalid in (
            {"3": task("coach")},
            {**valid, "5": task("curator")},
            {"0": task("coach"), "1": task("chef")},
            {"3": task("coach"), "4": task("coach", "plural_first")},
            {"3": task("coach"), "4": task("chef")},
            {"3": task(COMPOUND_SCENE), "4": task(COMPOUND_SCENE, "plural_first")},
            {"3": task(COMPOUND_SCENE), "4": task("coach")},
        ):
            with self.subTest(invalid=invalid), self.assertRaises(AgreementTaskError):
                compile_mapped_english_slots(invalid, contract())
        base = contract()
        bad_scope = replace(base, mapped_assignments=(
            base.mapped_assignments[0],
            ("english-id", "english-objective", SUPPORTED_TOPIC, "Resolve pronoun reference", 2),
        ))
        wrong_difficulty = replace(base, mapped_quantitative_difficulty=3)
        for invalid_contract in (bad_scope, wrong_difficulty,
                                 AuthorSlotContract(2, "prose")):
            with self.subTest(contract=invalid_contract), self.assertRaises(AgreementTaskError):
                compile_mapped_english_slots(valid, invalid_contract)


if __name__ == "__main__":
    unittest.main()
