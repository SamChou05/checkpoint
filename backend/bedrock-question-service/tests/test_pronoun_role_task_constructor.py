"""Independent checks for the offline pronoun-role constructor prototype."""

import re
import unittest

from pronoun_role_task_constructor import (
    LEARNER_FIELDS, ORDERS, PronounRoleTaskError, SINGLE_SPEAKER_SCENES,
    SPEAKER_SHIFT_SCENES, TASK_KIND, compile_question, task_schema,
)


# Expected wording and keys are read from the intended dialogue, separately
# from the module's role-map tuples and choice-order calculation.
SINGLE_EXPECTED = {
    "catalog": ("Mara", "Nia", "catalog", "sketches", "photograph", "model"),
    "repair": ("Eli", "Ava", "repair", "bicycle", "inspect", "helmet"),
    "translate": ("Leah", "Theo", "translate", "notes", "review", "draft"),
    "frame": ("Sana", "Remy", "frame", "drawing", "measure", "canvas"),
}
SHIFT_EXPECTED = {
    "deliver": ("Iris", "Caleb", "deliver", "poster", "cart"),
    "move": ("Nora", "Omar", "move", "boxes", "trolley"),
    "hang": ("Aya", "Leo", "hang", "painting", "ladder"),
    "copy": ("Nina", "Eli", "copy", "notes", "printer"),
}


def task(scene: str, order: str = "forward") -> dict:
    return {"kind": TASK_KIND, "scene": scene, "order": order}


class PronounRoleTaskConstructorTests(unittest.TestCase):
    def test_single_speaker_prompt_does_not_ascribe_a_plan_to_the_addressee(self):
        for scene in SINGLE_EXPECTED:
            for order in ORDERS:
                with self.subTest(scene=scene, order=order):
                    question = compile_question(task(scene, order))
                    self.assertTrue(question["prompt"].endswith(
                        "If the actions occur, who would do each, and who owns the two objects?"))
                    self.assertNotIn("two proposed actions", question["prompt"])
                    self.assertNotRegex(question["prompt"], r"\b(?:plans|promises|commits)\b")
                    self.assertIn(" would ", question["expectedAnswer"])

    def test_closed_task_contract_rejects_extensions_and_wrong_types(self):
        schema = task_schema()
        self.assertEqual(schema["additionalProperties"], False)
        self.assertEqual(set(schema["properties"]["scene"]["enum"]),
                         {*SINGLE_EXPECTED, *SHIFT_EXPECTED})
        self.assertEqual(schema["properties"]["order"]["enum"], list(ORDERS))
        invalid = (
            None, [], "catalog", {},
            {"kind": TASK_KIND, "scene": "catalog"},
            {**task("catalog"), "answer": "A"},
            {**task("catalog"), "kind": "agreement_pair_v1"},
            {**task("catalog"), "scene": "invented"},
            {**task("catalog"), "order": "invented"},
            {**task("catalog"), "scene": True},
            {**task("catalog"), "order": 1},
        )
        for raw in invalid:
            with self.subTest(raw=raw), self.assertRaises(PronounRoleTaskError):
                compile_question(raw)
        for ordinal in (-1, 0.5, True, "1"):
            with self.subTest(ordinal=ordinal), self.assertRaises(PronounRoleTaskError):
                compile_question(task("catalog"), ordinal=ordinal)

    def test_every_single_speaker_variant_has_exact_key_and_four_role_maps(self):
        self.assertEqual(set(SINGLE_EXPECTED), set(SINGLE_SPEAKER_SCENES))
        role_maps = {("speaker", "addressee", "addressee", "speaker"),
                     ("addressee", "speaker", "speaker", "addressee"),
                     ("speaker", "speaker", "addressee", "addressee"),
                     ("addressee", "addressee", "speaker", "speaker")}
        for scene, (speaker, addressee, verb1, object1, verb2, object2) in SINGLE_EXPECTED.items():
            key = (f"{speaker} would {verb1} {addressee}'s {object1}; "
                   f"{addressee} would {verb2} {speaker}'s {object2}.")
            for order in ORDERS:
                for ordinal in range(4):
                    with self.subTest(scene=scene, order=order, ordinal=ordinal):
                        question = compile_question(task(scene, order), ordinal=ordinal)
                        self.assertEqual(question["expectedAnswer"], key)
                        self.assertEqual(question["choices"].count(key), 1)
                        self.assertEqual(question["choices"].index(key), (-ordinal) % 4)
                        observed = set()
                        for choice in question["choices"]:
                            match = re.fullmatch(
                                rf"(\w+) would {verb1} (\w+)'s {object1}; "
                                rf"(\w+) would {verb2} (\w+)'s {object2}\.", choice)
                            self.assertIsNotNone(match, choice)
                            names = {speaker: "speaker", addressee: "addressee"}
                            observed.add(tuple(names[name] for name in match.groups()))
                        self.assertEqual(observed, role_maps)
                        self.assertIn(f'"I/my" mean {speaker}', question["explanation"])
                        self.assertIn(f'"you/your" mean {addressee}', question["explanation"])
                        self.assertIn("reverses both actors", question["explanation"])
                        self.assertIn("reverses both object owners", question["explanation"])

    def test_every_speaker_shift_variant_has_exact_key_and_four_role_maps(self):
        self.assertEqual(set(SHIFT_EXPECTED), set(SPEAKER_SHIFT_SCENES))
        role_maps = {("planner", "offerer", "offerer"),
                     ("offerer", "planner", "planner"),
                     ("planner", "planner", "offerer"),
                     ("planner", "offerer", "planner")}
        for scene, (planner, offerer, verb, obj, tool) in SHIFT_EXPECTED.items():
            key = (f"{planner} plans to {verb} {offerer}'s {obj}; "
                   f"{offerer} offers {offerer}'s {tool}.")
            for order in ORDERS:
                for ordinal in range(4):
                    with self.subTest(scene=scene, order=order, ordinal=ordinal):
                        question = compile_question(task(scene, order), ordinal=ordinal)
                        self.assertEqual(question["expectedAnswer"], key)
                        self.assertEqual(question["choices"].count(key), 1)
                        self.assertEqual(question["choices"].index(key), (-ordinal) % 4)
                        observed = set()
                        for choice in question["choices"]:
                            match = re.fullmatch(
                                rf"(\w+) plans to {verb} (\w+)'s {obj}; "
                                rf"{offerer} offers (\w+)'s {tool}\.", choice)
                            self.assertIsNotNone(match, choice)
                            names = {planner: "planner", offerer: "offerer"}
                            observed.add(tuple(names[name] for name in match.groups()))
                        self.assertEqual(observed, role_maps)
                        self.assertIn(f'In {planner}\'s turn, "I" means {planner}',
                                      question["explanation"])
                        self.assertIn(f'In {offerer}\'s turn, "my" means {offerer}',
                                      question["explanation"])
                        self.assertIn(f"assigns the {obj} to {planner} instead of {offerer}",
                                      question["explanation"])
                        self.assertIn(f"assigns the {tool} to {planner} instead of {offerer}",
                                      question["explanation"])

    def test_all_sixteen_variants_are_distinct_bounded_and_make_no_completion_claim(self):
        prompts = []
        for scene in (*SINGLE_EXPECTED, *SHIFT_EXPECTED):
            for order in ORDERS:
                with self.subTest(scene=scene, order=order):
                    question = compile_question(task(scene, order))
                    self.assertEqual(set(question), set(LEARNER_FIELDS))
                    self.assertEqual(len(question["choices"]), 4)
                    self.assertEqual(len(set(question["choices"])), 4)
                    self.assertEqual(list(question["choiceExplanations"]), question["choices"])
                    self.assertEqual(sum(value.startswith("Correct.") for value in
                                         question["choiceExplanations"].values()), 1)
                    self.assertEqual(sum(value.startswith("Incorrect:") for value in
                                         question["choiceExplanations"].values()), 3)
                    self.assertTrue(12 <= len(question["prompt"]) <= 320)
                    self.assertTrue(all(1 <= len(choice) <= 140 for choice in question["choices"]))
                    self.assertTrue(12 <= len(question["explanation"]) <= 420)
                    self.assertTrue(all(1 <= len(text) <= 280 for text in
                                        question["choiceExplanations"].values()))
                    self.assertTrue(all(not re.match(r"^[A-D][.)] ", choice)
                                        for choice in question["choices"]))
                    self.assertEqual(question["prompt"].count('"'), 2 if scene in SINGLE_EXPECTED else 4)
                    self.assertIn("would" if scene in SINGLE_EXPECTED else "plans to",
                                  question["expectedAnswer"])
                    self.assertNotRegex(" ".join((question["prompt"], *question["choices"])),
                                        r"\b(?:completed|already|did|has delivered|was delivered)\b")
                    prompts.append(question["prompt"])
        self.assertEqual(len(prompts), 16)
        self.assertEqual(len(set(prompts)), 16)

    def test_main_teaching_and_literal_choice_feedback_survive_choice_rotation(self):
        for scene in (*SINGLE_EXPECTED, *SHIFT_EXPECTED):
            for order in ORDERS:
                with self.subTest(scene=scene, order=order):
                    first = compile_question(task(scene, order), ordinal=0)
                    for ordinal in range(1, 4):
                        rotated = compile_question(task(scene, order), ordinal=ordinal)
                        self.assertEqual(rotated["explanation"], first["explanation"])
                        self.assertEqual(rotated["choiceExplanations"],
                                         first["choiceExplanations"])
                        self.assertEqual(rotated["expectedAnswer"], first["expectedAnswer"])
                        self.assertNotRegex(rotated["explanation"], r"\b[A-D][.)] ")


if __name__ == "__main__":
    unittest.main()
