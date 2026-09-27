"""Independent controls for the closed, offline English agreement prototype."""

from dataclasses import replace
import json
import unittest

from agreement_task_constructor import (
    AgreementTaskError, COMPOUND_SCENE, COMPOUND_SCENES, CORRELATIVE_SCENES, GERUND_SCENES,
    INVERSION_SCENES, LEARNER_FIELDS, NUMBER_SCENES, PARTITIVE_SCENES, RELATIVE_SCENES,
    SENTENCE_SELECTION_SCENES,
    SUPPORTED_OBJECTIVE,
    SUPPORTED_TOPIC,
    TASK_KIND, canonical_variant_identities, compile_mapped_english_slots,
    compile_question, task_schema,
)
from native_output_contracts import AuthorSlotContract
from native_output_contracts import adapt_native_response, native_output_config


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
        self.assertEqual(len(canonical_variant_identities()), 72)

    def test_sentence_selection_has_one_independent_key_and_rule_specific_feedback(self):
        # These full-sentence keys are independently read from the subject and
        # verb in each option, not from the constructor's selected-rule index.
        expected = {
            ("select_archive", "singular_first"): "Maya and Theo each prepare lunch.",
            ("select_archive", "plural_first"): "Neither the curator nor the assistants sort the records.",
            ("select_library", "singular_first"): "Each of the guides wears a badge.",
            ("select_library", "plural_first"): "Restoring the manuscripts takes time.",
            ("select_studio", "singular_first"): "Neither the director nor the actors move the props.",
            ("select_studio", "plural_first"): "Leah and Omar each close the doors.",
            ("select_lab", "singular_first"): "Drawing the maps requires accuracy.",
            ("select_lab", "plural_first"): "Each of the clerks keeps a copy.",
        }
        self.assertEqual({scene for scene, _ in expected}, set(SENTENCE_SELECTION_SCENES))
        answer_positions = []
        for (scene, order), key in expected.items():
            with self.subTest(scene=scene, order=order):
                result = compile_question(task(scene, order), ordinal=4)
                self.assertEqual(result["expectedAnswer"], key)
                self.assertEqual(result["choices"].count(key), 1)
                self.assertEqual(len(set(result["choices"])), 4)
                self.assertEqual(list(result["choiceExplanations"]), result["choices"])
                self.assertTrue(all(choice.endswith(".") for choice in result["choices"]))
                self.assertNotIn("___", result["prompt"])
                self.assertIn("Which sentence", result["prompt"])
                self.assertIn(key, result["explanation"])
                self.assertEqual(sum("This sentence agrees." in feedback for feedback
                                     in result["choiceExplanations"].values()), 1)
                self.assertTrue(all(len(feedback) <= 280 for feedback in
                                    result["choiceExplanations"].values()))
                answer_positions.append(result["choices"].index(key))
                with self.assertRaises(AgreementTaskError):
                    compile_question(task(scene, order), ordinal=3)
        self.assertEqual(sorted(answer_positions), [0, 0, 1, 1, 2, 2, 3, 3])

    def test_sentence_selection_reaches_complete_mapped_english_compiler(self):
        for scene in SENTENCE_SELECTION_SCENES:
            for order in ("singular_first", "plural_first"):
                source = {"3": task("partitive_mail"), "4": task(scene, order)}
                with self.subTest(scene=scene, order=order):
                    candidates = compile_mapped_english_slots(source, contract())
                    self.assertEqual(candidates[4].content()["expectedAnswer"],
                                     compile_question(source["4"], ordinal=4)["expectedAnswer"])
                    self.assertEqual(candidates[4].content()["difficulty"], 2)

    def test_partitive_mass_and_count_agreement_has_one_independent_key(self):
        # These keys follow the mass/count nouns in the written clauses; this
        # expected table is independent of the constructor's stored flags.
        expected = {
            "partitive_paint": ("covers", "rest", "paint", "brushes"),
            "partitive_rice": ("remains", "sit", "rice", "plates"),
            "partitive_water": ("flows", "stand", "water", "bottles"),
            "partitive_mail": ("arrives", "include", "mail", "letters"),
        }
        self.assertEqual(set(expected), set(PARTITIVE_SCENES))
        for scene, (singular, plural, mass_noun, count_noun) in expected.items():
            for order in ("singular_first", "plural_first"):
                with self.subTest(scene=scene, order=order):
                    result = compile_question(task(scene, order), ordinal=3)
                    key = (f"{singular}; {plural}" if order == "singular_first"
                           else f"{plural}; {singular}")
                    self.assertEqual(result["expectedAnswer"], key)
                    self.assertEqual(result["choices"].count(key), 1)
                    self.assertEqual(len(set(result["choices"])), 4)
                    self.assertEqual(set(result["choices"]), set(result["choiceExplanations"]))
                    self.assertIn(f"of the {mass_noun}", result["prompt"])
                    self.assertIn(f"of the {count_noun}", result["prompt"])
                    self.assertIn("uncountable material", result["explanation"])
                    self.assertIn("multiple countable items", result["explanation"])
                    for choice in result["choices"]:
                        wrong = sum(chosen != correct for chosen, correct in zip(
                            choice.split("; "), key.split("; "), strict=True))
                        self.assertEqual(result["choiceExplanations"][choice].count(
                            "does not agree"), wrong)
                    self.assertLessEqual(len(result["prompt"]), 320)
                    self.assertLessEqual(len(result["explanation"]), 420)
                    self.assertTrue(all(len(value) <= 280 for value in
                                        result["choiceExplanations"].values()))

    def test_partitive_scene_is_admitted_only_in_slot_three_and_compiles_after_adapter(self):
        mapped = replace(contract(), mapped_agreement_tasks=True,
                         mapped_quantitative_families=True)
        schema = json.loads(native_output_config(mapped)[
            "textFormat"]["structure"]["jsonSchema"]["schema"])
        slots = schema["properties"]["questions"]["properties"]
        self.assertIn("partitive_mail", slots["3"]["properties"]["scene"]["enum"])
        self.assertNotIn("partitive_mail", slots["4"]["properties"]["scene"]["enum"])
        source = {"questions": {
            "0": {"family": "fraction_evaluation", "a": 4, "b": 5},
            "1": {"family": "bounded_equation", "a": 6, "b": 8},
            "2": {"family": "bounded_ratio_threshold", "a": 3, "b": 7},
            "3": task("partitive_mail"), "4": task("compound_clerks"),
        }}
        adapted = json.loads(adapt_native_response(json.dumps(source), mapped))
        english = {str(slot): adapted["questions"][slot]["task"] for slot in (3, 4)}
        candidates = compile_mapped_english_slots(english, mapped)
        self.assertEqual(candidates[3].content()["expectedAnswer"], "arrives; include")
        self.assertEqual(candidates[3].content()["prompt"],
                         compile_question(task("partitive_mail"), ordinal=3)["prompt"])

    def test_gerund_subject_keys_and_nonmirror_frames(self):
        # Manually checked against the written clauses, independent of the
        # constructor's activity/subject fields and key calculation.
        expected = {
            "gerund_reports": ("requires; check", "review; demands"),
            "gerund_books": ("helps; update", "examine; takes"),
            "gerund_meals": ("requires; measure", "inspect; demands"),
            "gerund_maps": ("requires; trace", "record; takes"),
        }
        self.assertEqual(set(expected), set(GERUND_SCENES))
        answer_positions = []
        for scene, keys in expected.items():
            questions = []
            for order, key in zip(("singular_first", "plural_first"), keys, strict=True):
                with self.subTest(scene=scene, order=order):
                    result = compile_question(task(scene, order), ordinal=4)
                    questions.append(result)
                    self.assertEqual(result["expectedAnswer"], key)
                    answer_positions.append(result["choices"].index(key))
                    self.assertEqual(result["choices"].count(key), 1)
                    self.assertEqual(len(set(result["choices"])), 4)
                    self.assertEqual(set(result["choices"]), set(result["choiceExplanations"]))
                    self.assertEqual(result["prompt"].count("___"), 2)
                    self.assertIn("one singular subject", result["explanation"])
                    self.assertIn("is plural", result["explanation"])
                    self.assertIn(", and ", result["prompt"])
                    self.assertLessEqual(len(result["prompt"]), 320)
                    self.assertLessEqual(len(result["explanation"]), 420)
                    for choice, feedback in result["choiceExplanations"].items():
                        wrong = sum(selected != correct for selected, correct in zip(
                            choice.split("; "), key.split("; "), strict=True))
                        self.assertEqual(feedback.count("does not agree"), wrong)
                        self.assertLessEqual(len(feedback), 280)
            first, second = questions
            # The reversed-order question uses a separate scene frame; it is
            # not the same two clauses in the opposite order.
            def clauses(question):
                body = question["prompt"].split("English. ", 1)[1].split(
                    ". Which ordered pair", 1)[0]
                return {clause.casefold() for clause in body.split(", and ")}

            self.assertNotEqual(clauses(first), clauses(second))
        self.assertEqual(sorted(answer_positions), [0, 0, 1, 1, 2, 2, 3, 3])

    def test_every_gerund_source_passes_the_complete_mapped_english_route(self):
        # The provider schema admits these tasks; the final two-slot compiler
        # must admit the same closed families before worker sanitization.
        for scene in GERUND_SCENES:
            for order in ("singular_first", "plural_first"):
                source = {"3": task("coach"), "4": task(scene, order)}
                with self.subTest(scene=scene, order=order):
                    candidates = compile_mapped_english_slots(source, contract())
                    self.assertEqual(set(candidates), {3, 4})
                    self.assertEqual(json.loads(candidates[4].source_task_json), source["4"])
                    self.assertEqual(candidates[4].content()["expectedAnswer"],
                                     compile_question(source["4"], ordinal=4)["expectedAnswer"])

    def test_correlative_nearer_subject_has_independent_keys_and_choice_feedback(self):
        expected = {
            "or_archive": ("checks", "sort", "the curator", "the assistants"),
            "or_studio": ("reviews", "move", "the director", "the actors"),
            "or_library": ("examines", "arrange", "the librarian", "the volunteers"),
            "or_lab": ("inspects", "label", "the scientist", "the technicians"),
        }
        self.assertEqual(set(expected), set(CORRELATIVE_SCENES))
        for scene, (singular, plural, singular_subject, plural_subject) in expected.items():
            for order in ("singular_first", "plural_first"):
                with self.subTest(scene=scene, order=order):
                    result = compile_question(task(scene, order), ordinal=4)
                    key = (f"{singular}; {plural}" if order == "singular_first"
                           else f"{plural}; {singular}")
                    self.assertEqual(result["expectedAnswer"], key)
                    self.assertEqual(len(result["choices"]), 4)
                    self.assertEqual(len(set(result["choices"])), 4)
                    self.assertEqual(result["choices"].count(key), 1)
                    self.assertEqual(set(result["choices"]), set(result["choiceExplanations"]))
                    self.assertIn(f"either {plural_subject} or {singular_subject} ___",
                                  result["prompt"].lower())
                    self.assertIn(f"neither {singular_subject} nor {plural_subject} ___",
                                  result["prompt"].lower())
                    self.assertIn(f'nearer subject "{singular_subject}" is singular',
                                  result["explanation"])
                    self.assertIn(f'nearer subject "{plural_subject}" is plural',
                                  result["explanation"])
                    for choice in result["choices"]:
                        wrong = sum(chosen != correct for chosen, correct in zip(
                            choice.split("; "), key.split("; "), strict=True))
                        self.assertEqual(result["choiceExplanations"][choice].count(
                            "does not agree"), wrong)
                    self.assertLessEqual(len(result["prompt"]), 320)
                    self.assertLessEqual(len(result["explanation"]), 420)
                    self.assertTrue(all(len(value) <= 280 for value in
                                        result["choiceExplanations"].values()))

    def test_relative_clause_and_main_clause_have_independent_keys_and_feedback(self):
        facts = {
            "relative_guides": ("fold", "wears", "guides"),
            "relative_editors": ("check", "carries", "editors"),
            "relative_technicians": ("label", "keeps", "technicians"),
            "relative_clerks": ("sort", "holds", "clerks"),
        }
        self.assertEqual(set(facts), set(RELATIVE_SCENES))
        for scene, (relative, matrix, antecedent) in facts.items():
            for order in ("singular_first", "plural_first"):
                with self.subTest(scene=scene, order=order):
                    result = compile_question(task(scene, order), ordinal=3)
                    key = (f"{matrix}; {relative}" if order == "singular_first"
                           else f"{relative}; {matrix}")
                    self.assertEqual(result["expectedAnswer"], key)
                    self.assertEqual(result["choices"].count(key), 1)
                    self.assertEqual(len(set(result["choices"])), 4)
                    self.assertEqual(set(result["choices"]), set(result["choiceExplanations"]))
                    self.assertEqual(result["prompt"].count("___"), 2)
                    self.assertIn(f"The {antecedent} who ___", result["prompt"])
                    self.assertIn(f"One of the {antecedent} ___", result["prompt"])
                    self.assertIn(f'plural "{antecedent}"', result["explanation"])
                    self.assertIn('singular "One"', result["explanation"])
                    for choice in result["choices"]:
                        mismatches = sum(a != b for a, b in zip(
                            choice.split("; "), key.split("; "), strict=True))
                        self.assertEqual(result["choiceExplanations"][choice].count(
                            "does not agree"), mismatches)
                    self.assertLessEqual(len(result["prompt"]), 320)
                    self.assertLessEqual(len(result["explanation"]), 420)
                    self.assertTrue(all(len(text) <= 280 for text in
                                        result["choiceExplanations"].values()))

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
                    self.assertIn('"Maya and Theo" is a plural joined subject',
                                  result["explanation"])
                    self.assertIn('"Each of the guests" has singular "Each"',
                                  result["explanation"])
                    self.assertNotIn(" near ", result["prompt"])
                    self.assertLessEqual(len(result["explanation"]), 420)
                    self.assertTrue(all(len(text) <= 280 for text in
                                        result["choiceExplanations"].values()))
                    self.assertIn("Maya and Theo", result["prompt"])

    def test_captured_compound_task_keeps_exact_key_without_proximity_attractors(self):
        result = compile_question(task(COMPOUND_SCENE, "plural_first"), ordinal=4)
        self.assertEqual(result["expectedAnswer"], "receives; prepare")
        self.assertEqual(set(result["choices"]), {
            "receive; prepare", "receive; prepares", "receives; prepare", "receives; prepares",
        })
        self.assertIn("Each of the guests ___ a plate", result["prompt"])
        self.assertIn("Maya and Theo each ___ lunch", result["prompt"])

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
            COMPOUND_SCENE: ("Maya and Theo", "prepare", "prepares",
                             "Each of the guests", "receive", "receives"),
            "compound_guides": ("Nora and Eli", "fold", "folds",
                                "Each of the guides", "wear", "wears"),
            "compound_visitors": ("Leah and Omar", "close", "closes",
                                  "Each of the visitors", "hold", "holds"),
            "compound_clerks": ("Ava and Ben", "review", "reviews",
                                "Each of the clerks", "keep", "keeps"),
        }
        self.assertEqual(set(facts), set(COMPOUND_SCENES))
        for scene, (compound, base, third, distributive,
                    other_base, other_third) in facts.items():
            self.assertIn(" and ", compound)
            self.assertTrue(distributive.startswith("Each of "))
            self.assertNotEqual(base, third)
            self.assertNotEqual(other_base, other_third)
            for order in ("singular_first", "plural_first"):
                ordered = ((compound, base, third, False),
                           (distributive, other_base, other_third, True))
                if order == "plural_first":
                    ordered = ordered[::-1]
                expected_key = "; ".join(third if correct_third else bare
                                         for _, bare, third, correct_third in ordered)
                expected_choices = {
                    f"{first}; {second}"
                    for first in (ordered[0][1], ordered[0][2])
                    for second in (ordered[1][1], ordered[1][2])
                }
                for ordinal in (3, 4):
                    with self.subTest(scene=scene, order=order, ordinal=ordinal):
                        result = compile_question(task(scene, order), ordinal=ordinal)
                        self.assertEqual(result["expectedAnswer"], expected_key)
                        self.assertEqual(set(result["choices"]), expected_choices)
                        self.assertEqual(len(result["choices"]), 4)
                        self.assertEqual(sum(choice == expected_key for choice in result["choices"]), 1)
                        for subject, *_ in ordered:
                            self.assertIn(subject.casefold(), result["prompt"].casefold())
                        self.assertNotIn(" near ", result["prompt"])
                        for choice in reversed(result["choices"]):
                            selected = choice.split("; ")
                            wrong_count = sum(
                                chosen != (third if correct_third else bare)
                                for chosen, (_, bare, third, correct_third) in zip(
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
        self.assertIn(json.loads(candidates[4].task_json)["scene"],
                      {**NUMBER_SCENES, **GERUND_SCENES, **CORRELATIVE_SCENES})
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
        self.assertIn(json.loads(candidates[4].task_json)["scene"],
                      {**NUMBER_SCENES, **GERUND_SCENES, **CORRELATIVE_SCENES})
        self.assertTrue(all(candidate.content()["prompt"] not in history
                            for candidate in candidates.values()))

    def test_finite_inventory_exhaustion_keeps_original_task_for_item_filter(self):
        history = tuple(
            compile_question(task(scene, order), ordinal=4)["prompt"]
            for scene in (*COMPOUND_SCENES, *NUMBER_SCENES, *CORRELATIVE_SCENES,
                          *GERUND_SCENES, *SENTENCE_SELECTION_SCENES)
            for order in ("singular_first", "plural_first")
        )
        source = {"3": task("coach"), "4": task(COMPOUND_SCENE)}
        candidates = compile_mapped_english_slots(source, contract(), existing_prompts=history)
        self.assertTrue(candidates[4].novelty_exhausted)
        self.assertEqual(json.loads(candidates[4].task_json), source["4"])
        self.assertFalse(candidates[3].novelty_exhausted)

    def test_history_selection_yields_all_forty_slot_four_stems_before_exhaustion(self):
        source = {"3": task("coach"), "4": task(COMPOUND_SCENE)}
        history = []
        chosen_scenes = []
        for _ in range(40):
            candidate = compile_mapped_english_slots(
                source, contract(), existing_prompts=tuple(history),
            )[4]
            self.assertFalse(candidate.novelty_exhausted)
            prompt = candidate.content()["prompt"]
            self.assertNotIn(prompt, history)
            history.append(prompt)
            chosen_scenes.append(json.loads(candidate.task_json)["scene"])
        self.assertEqual(chosen_scenes[0], COMPOUND_SCENE)
        self.assertIn(chosen_scenes[1], {**NUMBER_SCENES, **GERUND_SCENES,
                                         **CORRELATIVE_SCENES})
        self.assertEqual(len(set(history)), 40)
        self.assertTrue(set(chosen_scenes) & set(NUMBER_SCENES))
        self.assertTrue(set(chosen_scenes) & set(CORRELATIVE_SCENES))
        self.assertTrue(set(chosen_scenes) & set(GERUND_SCENES))
        self.assertTrue(set(chosen_scenes) & set(SENTENCE_SELECTION_SCENES))
        exhausted = compile_mapped_english_slots(
            source, contract(), existing_prompts=tuple(history),
        )[4]
        self.assertTrue(exhausted.novelty_exhausted)

    def test_slot_three_balances_four_mechanisms_across_eighty_item_bank(self):
        source = {"3": task("coach"), "4": task(COMPOUND_SCENE)}
        history = []
        families = {"proximity": 0, "inversion": 0, "relative": 0, "partitive": 0}
        for _ in range(16):
            candidate = compile_mapped_english_slots(
                source, contract(), existing_prompts=tuple(history),
            )[3]
            self.assertFalse(candidate.novelty_exhausted)
            scene = json.loads(candidate.task_json)["scene"]
            family = ("partitive" if scene in PARTITIVE_SCENES else
                      "relative" if scene in RELATIVE_SCENES else
                      "inversion" if scene in INVERSION_SCENES else "proximity")
            families[family] += 1
            prompt = candidate.content()["prompt"]
            self.assertNotIn(prompt, history)
            history.append(prompt)
        self.assertEqual(len(set(history)), 16)
        self.assertEqual(sorted(families.values()), [4, 4, 4, 4])
        self.assertFalse(compile_mapped_english_slots(
            source, contract(), existing_prompts=tuple(history),
        )[3].novelty_exhausted)

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
