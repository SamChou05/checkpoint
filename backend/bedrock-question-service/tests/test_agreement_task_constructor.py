"""Independent controls for the closed, offline English agreement prototype."""

from dataclasses import replace
import json
import unittest

from agreement_task_constructor import (
    AgreementTaskError, COMPOUND_SCENE, COMPOUND_SCENES, INVERSION_SCENES,
    LEARNER_FIELDS, NUMBER_SCENES, SUPPORTED_OBJECTIVE, SUPPORTED_TOPIC,
    TASK_KIND, canonical_variant_identities, compile_mapped_english_slots,
    compile_question, task_schema,
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
    def test_all_slot_variants_have_distinct_canonical_stems(self):
        self.assertEqual(len(canonical_variant_identities()), 32)

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
                    self.assertIn('subject "Maya and Theo" is plural ("and" joins two)',
                                  result["explanation"])
                    self.assertIn('subject "Every guest" is singular', result["explanation"])
                    self.assertIn('"near the cook" does not change it', result["explanation"])
                    self.assertIn('"near the servers" does not change it', result["explanation"])
                    self.assertLessEqual(len(result["explanation"]), 420)
                    self.assertTrue(all(len(text) <= 280 for text in
                                        result["choiceExplanations"].values()))
                    self.assertIn("Maya and Theo", result["prompt"])

    def test_captured_compound_task_keeps_exact_key_with_opposing_attractors(self):
        result = compile_question(task(COMPOUND_SCENE, "plural_first"), ordinal=4)
        self.assertEqual(result["expectedAnswer"], "receives; prepare")
        self.assertEqual(set(result["choices"]), {
            "receive; prepare", "receive; prepares", "receives; prepare", "receives; prepares",
        })
        self.assertIn("Every guest near the servers ___ a plate", result["prompt"])
        self.assertIn("Maya and Theo near the cook ___ lunch", result["prompt"])

    def test_expanded_compound_scenes_have_exact_keys_and_bounded_teaching(self):
        expected = {
            "compound_guides": ("fold", "wears"),
            "compound_visitors": ("close", "holds"),
            "compound_clerks": ("review", "keeps"),
        }
        for scene, forms in expected.items():
            for order in ("singular_first", "plural_first"):
                result = compile_question(task(scene, order), ordinal=4)
                key = forms if order == "singular_first" else forms[::-1]
                self.assertEqual(result["expectedAnswer"], "; ".join(key))
                self.assertEqual(len(set(result["choices"])), 4)
                self.assertLessEqual(len(result["prompt"]), 320)
                self.assertLessEqual(len(result["explanation"]), 420)
                self.assertTrue(all(len(value) <= 280 for value in result["choiceExplanations"].values()))

    def test_alternate_agreement_structures_have_exact_keys_and_feedback(self):
        for scenes, slot, initial_key, explanation_signal in (
            (INVERSION_SCENES, 3, "is; are", "follows the blank"),
            (NUMBER_SCENES, 4, "are; is", 'singular head "number"'),
        ):
            for scene in scenes:
                for order in ("singular_first", "plural_first"):
                    with self.subTest(scene=scene, order=order):
                        result = compile_question(task(scene, order), ordinal=slot)
                        expected = initial_key if order == "singular_first" else "; ".join(
                            reversed(initial_key.split("; ")))
                        self.assertEqual(result["expectedAnswer"], expected)
                        self.assertEqual(len(result["choices"]), 4)
                        self.assertEqual(len(set(result["choices"])), 4)
                        self.assertEqual(set(result["choiceExplanations"]), set(result["choices"]))
                        self.assertEqual(result["prompt"].count("___"), 2)
                        self.assertIn(explanation_signal, result["explanation"])
                        self.assertLessEqual(len(result["prompt"]), 320)
                        self.assertLessEqual(len(result["explanation"]), 420)
                        self.assertTrue(all(len(value) <= 280 for value in
                                            result["choiceExplanations"].values()))
                        for choice in result["choices"]:
                            self.assertEqual(result["choiceExplanations"][choice].count(
                                "does not agree"), sum(
                                    selected != correct for selected, correct in zip(
                                        choice.split("; "), expected.split("; "), strict=True)))

    def test_exhaustive_compound_choices_and_feedback_survive_choice_shuffle(self):
        facts = {
            COMPOUND_SCENE: ("Maya and Theo", "the cook", "prepare", "prepares",
                             "Every guest", "the servers", "receive", "receives"),
            "compound_guides": ("Nora and Eli", "the guide", "fold", "folds",
                                "Every guide", "the hikers", "wear", "wears"),
            "compound_visitors": ("Leah and Omar", "the visitor", "close", "closes",
                                  "Every visitor", "the guides", "hold", "holds"),
            "compound_clerks": ("Ava and Ben", "the clerk", "review", "reviews",
                                "Every clerk", "the visitors", "keep", "keeps"),
        }
        self.assertEqual(set(facts), set(COMPOUND_SCENES))
        for scene, (compound, singular_attractor, base, third, distributive,
                    plural_attractor, other_base, other_third) in facts.items():
            self.assertIn(" and ", compound)
            self.assertTrue(distributive.startswith("Every "))
            self.assertNotEqual(base, third)
            self.assertNotEqual(other_base, other_third)
            for order in ("singular_first", "plural_first"):
                ordered = ((compound, singular_attractor, base, third, False),
                           (distributive, plural_attractor, other_base, other_third, True))
                if order == "plural_first":
                    ordered = ordered[::-1]
                expected_key = "; ".join(third if correct_third else bare
                                         for _, _, bare, third, correct_third in ordered)
                expected_choices = {
                    f"{first}; {second}"
                    for first in (ordered[0][2], ordered[0][3])
                    for second in (ordered[1][2], ordered[1][3])
                }
                for ordinal in (3, 4):
                    with self.subTest(scene=scene, order=order, ordinal=ordinal):
                        result = compile_question(task(scene, order), ordinal=ordinal)
                        self.assertEqual(result["expectedAnswer"], expected_key)
                        self.assertEqual(set(result["choices"]), expected_choices)
                        self.assertEqual(len(result["choices"]), 4)
                        self.assertEqual(sum(choice == expected_key for choice in result["choices"]), 1)
                        for subject, attractor, *_ in ordered:
                            self.assertIn(subject.casefold(), result["prompt"].casefold())
                            self.assertIn("near " + attractor, result["prompt"])
                        for choice in reversed(result["choices"]):
                            selected = choice.split("; ")
                            wrong_count = sum(
                                chosen != (third if correct_third else bare)
                                for chosen, (_, _, bare, third, correct_third) in zip(
                                    selected, ordered, strict=True,
                                )
                            )
                            feedback = result["choiceExplanations"][choice]
                            self.assertEqual(feedback.count("does not agree"), wrong_count)
                            self.assertIn(ordered[0][0], feedback)
                            self.assertIn(ordered[1][0], feedback)
                        self.assertLessEqual(len(result["prompt"]), 320)
                        self.assertLessEqual(len(result["explanation"]), 420)
                        self.assertTrue(all(len(value) <= 280 for value in result["choiceExplanations"].values()))

    def test_history_selection_prefers_new_scene_and_preserves_source_provenance(self):
        source = {"3": task("coach"), "4": task(COMPOUND_SCENE)}
        prior = tuple(
            compile_question(task(scene, order), ordinal=slot)["prompt"]
            for slot, scene in ((3, "coach"), (4, COMPOUND_SCENE))
            for order in ("singular_first", "plural_first")
        )
        candidates = compile_mapped_english_slots(source, contract(), existing_prompts=prior)
        self.assertEqual(json.loads(candidates[3].source_task_json), source["3"])
        self.assertEqual(json.loads(candidates[4].source_task_json), source["4"])
        self.assertNotEqual(json.loads(candidates[3].task_json)["scene"], "coach")
        self.assertNotEqual(json.loads(candidates[4].task_json)["scene"], COMPOUND_SCENE)
        self.assertIn(json.loads(candidates[3].task_json)["scene"], INVERSION_SCENES)
        self.assertIn(json.loads(candidates[4].task_json)["scene"], NUMBER_SCENES)
        self.assertTrue(all(candidate.content()["prompt"] not in prior for candidate in candidates.values()))
        self.assertTrue(all(not candidate.novelty_exhausted for candidate in candidates.values()))
        with self.assertRaises(AgreementTaskError):
            replace(candidates[4], source_task_json=json.dumps(task("compound_guides"))).content()
        with self.assertRaises(AgreementTaskError):
            replace(candidates[4], task_json=json.dumps(source["4"])).content()

    def test_first_refill_switches_both_english_solve_mechanisms(self):
        source = {"3": task("coach"), "4": task(COMPOUND_SCENE)}
        history = tuple(compile_question(source[str(slot)], ordinal=slot)["prompt"]
                        for slot in (3, 4))
        candidates = compile_mapped_english_slots(
            source, contract(), existing_prompts=history)
        self.assertIn(json.loads(candidates[3].task_json)["scene"], INVERSION_SCENES)
        self.assertIn(json.loads(candidates[4].task_json)["scene"], NUMBER_SCENES)
        self.assertTrue(all(candidate.content()["prompt"] not in history
                            for candidate in candidates.values()))

    def test_finite_inventory_exhaustion_keeps_original_task_for_item_filter(self):
        history = tuple(
            compile_question(task(scene, order), ordinal=4)["prompt"]
            for scene in (*COMPOUND_SCENES, *NUMBER_SCENES)
            for order in ("singular_first", "plural_first")
        )
        source = {"3": task("coach"), "4": task(COMPOUND_SCENE)}
        candidates = compile_mapped_english_slots(source, contract(), existing_prompts=history)
        self.assertTrue(candidates[4].novelty_exhausted)
        self.assertEqual(json.loads(candidates[4].task_json), source["4"])
        self.assertFalse(candidates[3].novelty_exhausted)

    def test_history_selection_yields_all_sixteen_slot_four_stems_before_exhaustion(self):
        source = {"3": task("coach"), "4": task(COMPOUND_SCENE)}
        history = []
        chosen_scenes = []
        for _ in range(16):
            candidate = compile_mapped_english_slots(
                source, contract(), existing_prompts=tuple(history),
            )[4]
            self.assertFalse(candidate.novelty_exhausted)
            prompt = candidate.content()["prompt"]
            self.assertNotIn(prompt, history)
            history.append(prompt)
            chosen_scenes.append(json.loads(candidate.task_json)["scene"])
        self.assertEqual(chosen_scenes[0], COMPOUND_SCENE)
        self.assertIn(chosen_scenes[1], NUMBER_SCENES)
        self.assertEqual(len(set(history)), 16)
        exhausted = compile_mapped_english_slots(
            source, contract(), existing_prompts=tuple(history),
        )[4]
        self.assertTrue(exhausted.novelty_exhausted)

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
