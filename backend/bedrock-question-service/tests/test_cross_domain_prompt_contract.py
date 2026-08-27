import unittest

import lambda_function
from evals import checkpoint_question_eval


CROSS_DOMAIN_CASE_IDS = (
    "lsat_logical_reasoning_medium",
    "mcat_science_passage_reasoning",
    "spanish_subjunctive_easy_application",
    "modern_world_history_source_reasoning",
    "backyard_beekeeping_raw_goal",
)


REPRESENTATIVE_QUESTIONS = {
    "lsat_logical_reasoning_medium": {
        "prompt": "An argument claims that adding late-night buses raised restaurant revenue because both occurred in the same districts. Which flaw most weakens the conclusion?",
        "expectedAnswer": "It overlooks other district changes that could have increased restaurant revenue.",
        "choices": [
            "It overlooks other district changes that could have increased restaurant revenue.",
            "It assumes that every restaurant remained open during the same hours.",
            "It reports district revenue instead of the revenue of one restaurant.",
            "It compares districts that all introduced the same bus schedule.",
        ],
        "explanation": "The timing alone does not establish causation because another district-level change could explain the increase.",
        "topic": "Logical Reasoning",
        "difficulty": 3,
        "format": "Multiple Choice",
    },
    "mcat_science_passage_reasoning": {
        "prompt": "Researchers observed that an enzyme reaction slowed after the substrate concentration was doubled while pH moved far from the enzyme's optimum. Which explanation best fits the result?",
        "expectedAnswer": "The pH change reduced the enzyme's catalytic activity despite the added substrate.",
        "choices": [
            "The pH change reduced the enzyme's catalytic activity despite the added substrate.",
            "The added substrate converted every enzyme molecule into a lipid.",
            "The reaction stopped because substrate concentration can never exceed enzyme concentration.",
            "The pH change increased the activation energy supplied by each substrate molecule.",
        ],
        "explanation": "Moving far from an enzyme's optimal pH can disrupt interactions needed for catalysis, so more substrate need not increase the rate.",
        "topic": "enzyme activity",
        "difficulty": 3,
        "format": "Multiple Choice",
    },
    "spanish_subjunctive_easy_application": {
        "prompt": "Complete the Spanish sentence: 'Espero que Ana ___ (llegar) al aeropuerto antes de las ocho.' Which verb form fits the sentence?",
        "expectedAnswer": "llegue",
        "choices": ["llegue", "llega", "llegó", "llegar"],
        "explanation": "Espero que expresses a wish and triggers the present subjunctive form llegue.",
        "topic": "subjunctive mood",
        "difficulty": 2,
        "format": "Multiple Choice",
    },
    "modern_world_history_source_reasoning": {
        "prompt": "A primary source from an anticolonial movement demands local control of taxation and law. Which development most directly reflects that demand?",
        "expectedAnswer": "The transfer of political authority from an empire to an independent national government.",
        "choices": [
            "The transfer of political authority from an empire to an independent national government.",
            "The expansion of direct colonial administration into additional provinces.",
            "The replacement of local legislatures with officials appointed overseas.",
            "The creation of new tariffs designed solely by the imperial government.",
        ],
        "explanation": "The source calls for sovereignty, which is most directly realized through decolonization and independent government.",
        "topic": "decolonization",
        "difficulty": 3,
        "format": "Multiple Choice",
    },
    "backyard_beekeeping_raw_goal": {
        "prompt": "During a colony inspection, a beekeeper finds several capped queen cells near the lower edges of crowded brood frames. Which response best addresses the likely condition?",
        "expectedAnswer": "Create space and use an appropriate swarm-control method before the colony issues a swarm.",
        "choices": [
            "Create space and use an appropriate swarm-control method before the colony issues a swarm.",
            "Seal every hive entrance so no worker bees can leave the colony.",
            "Remove all brood frames and replace them with empty honey supers.",
            "Stop inspecting the hive until every queen cell has naturally disappeared.",
        ],
        "explanation": "Crowding plus capped queen cells near brood-frame edges are common swarm-preparation signals that call for timely management.",
        "topic": "swarm prevention",
        "difficulty": 2,
        "format": "Multiple Choice",
    },
}


class CrossDomainPromptContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixtures = checkpoint_question_eval.load_jsonl(
            checkpoint_question_eval.DEFAULT_FIXTURE_PATH
        )
        cls.fixtures = {fixture["case_id"]: fixture for fixture in fixtures}

    def score_single_question(self, case_id, question):
        fixture = self.fixtures[case_id]
        return checkpoint_question_eval.score_case_response(
            {
                **fixture,
                "expect": {**fixture["expect"], "min_usable_questions": 1},
            },
            {"case_id": case_id, "run": 1, "questions": [question]},
        )

    def test_default_release_suite_covers_cross_domain_and_raw_goals(self):
        for case_id in CROSS_DOMAIN_CASE_IDS:
            with self.subTest(case_id=case_id):
                fixture = self.fixtures[case_id]
                self.assertTrue(fixture["expect"]["required_grounding_terms_any"])

        raw_goal = self.fixtures["backyard_beekeeping_raw_goal"]["payload"]["goal"]
        self.assertNotIn("learningTarget", raw_goal)
        self.assertNotIn("contentTopics", raw_goal)
        self.assertNotIn("questionDirective", raw_goal)
        self.assertEqual(raw_goal["currentLevel"], "Beginner")

    def test_user_prompt_preserves_goal_focus_and_optional_level_for_every_domain(self):
        for case_id in CROSS_DOMAIN_CASE_IDS:
            with self.subTest(case_id=case_id):
                payload = self.fixtures[case_id]["payload"]
                normalized = lambda_function._normalize_request(payload)  # noqa: SLF001
                prompt = lambda_function._user_prompt(normalized)  # noqa: SLF001
                goal = payload["goal"]

                self.assertIn(goal["title"], prompt)
                if goal.get("focusAreas"):
                    self.assertIn(goal["focusAreas"], prompt)
                if goal.get("currentLevel"):
                    self.assertIn(goal["currentLevel"], prompt)

    def test_raw_goal_derives_target_and_topics_without_domain_logic(self):
        payload = self.fixtures["backyard_beekeeping_raw_goal"]["payload"]
        normalized = lambda_function._normalize_request(payload)  # noqa: SLF001

        self.assertEqual(normalized["goal"]["learningTarget"], "Learn backyard beekeeping")
        self.assertEqual(
            normalized["goal"]["contentTopics"],
            ["colony inspections", "swarm prevention", "Varroa monitoring"],
        )
        self.assertFalse(normalized["goal"]["needsSkillMap"])

    def test_system_prompt_contains_no_named_domain_playbooks(self):
        system_prompt = lambda_function._system_prompt().casefold()  # noqa: SLF001

        for domain_term in [
            "lsat",
            "mcat",
            "spanish",
            "calculus",
            "leetcode",
            "system-design interview",
            "beekeeping",
        ]:
            with self.subTest(domain_term=domain_term):
                self.assertNotIn(domain_term, system_prompt)

    def test_representative_items_from_each_domain_pass_the_same_quality_gate(self):
        for case_id, question in REPRESENTATIVE_QUESTIONS.items():
            with self.subTest(case_id=case_id):
                result = self.score_single_question(case_id, question)

                self.assertTrue(result["passed"], result)

    def test_mcat_grounding_accepts_valid_variation_across_supplied_focus_areas(self):
        questions = [
            {
                "prompt": "A researcher disrupts the mitotic spindle in a dividing cell. Which process is most directly prevented?",
                "expectedAnswer": "Separation of duplicated chromosomes into daughter cells.",
                "choices": [
                    "Separation of duplicated chromosomes into daughter cells.",
                    "Transcription of DNA into messenger RNA.",
                    "Diffusion of oxygen across the cell membrane.",
                    "Hydrolysis of proteins inside lysosomes.",
                ],
                "explanation": "The mitotic spindle moves duplicated chromosomes during cell division.",
                "topic": "cell biology",
                "difficulty": 3,
                "format": "Multiple Choice",
            },
            {
                "prompt": "During a titration, the pH rises sharply near the endpoint after base is added to an acid. What does this region indicate?",
                "expectedAnswer": "A small added volume now changes the hydrogen-ion concentration substantially.",
                "choices": [
                    "A small added volume now changes the hydrogen-ion concentration substantially.",
                    "The solution has stopped containing any charged particles.",
                    "The indicator has converted all solvent molecules into solute.",
                    "The acid concentration is increasing as more base is added.",
                ],
                "explanation": "Near the titration endpoint, the remaining acid is nearly neutralized, so added base causes a steep pH change.",
                "topic": "general chemistry",
                "difficulty": 3,
                "format": "Multiple Choice",
            },
            {
                "prompt": "A mutation prevents a ribosome from joining amino acids during protein synthesis. Which cellular product decreases most directly?",
                "expectedAnswer": "Polypeptide chains translated from messenger RNA.",
                "choices": [
                    "Polypeptide chains translated from messenger RNA.",
                    "DNA strands copied during genome replication.",
                    "Lipids assembled in the smooth endoplasmic reticulum.",
                    "ATP generated by the mitochondrial electron transport chain.",
                ],
                "explanation": "Ribosomes translate messenger RNA by linking amino acids into polypeptides.",
                "topic": "protein synthesis",
                "difficulty": 3,
                "format": "Multiple Choice",
            },
        ]

        for question in questions:
            with self.subTest(topic=question["topic"]):
                result = self.score_single_question(
                    "mcat_science_passage_reasoning", question
                )
                self.assertTrue(result["passed"], result)

    def test_spanish_grounding_accepts_travel_vocabulary_variation(self):
        question = {
            "prompt": "Before an international flight, Ana says: 'Necesito _____ para mostrarlo en inmigración.' Which Spanish word completes the sentence?",
            "expectedAnswer": "el pasaporte",
            "choices": ["el pasaporte", "la maleta", "el hotel", "el boleto de metro"],
            "explanation": "A traveler shows el pasaporte at immigration before traveling internationally.",
            "topic": "travel vocabulary",
            "difficulty": 2,
            "format": "Multiple Choice",
        }

        result = self.score_single_question(
            "spanish_subjunctive_easy_application", question
        )

        self.assertTrue(result["passed"], result)

    def test_history_grounding_accepts_valid_variation_across_supplied_focus_areas(self):
        questions = [
            {
                "prompt": "A factory replaces skilled hand production with steam-powered machinery. Which social change is most directly associated with this industrial shift?",
                "expectedAnswer": "Rapid urbanization as workers move toward manufacturing centers.",
                "choices": [
                    "Rapid urbanization as workers move toward manufacturing centers.",
                    "A universal return to rural household production.",
                    "The immediate disappearance of wage labor.",
                    "An end to long-distance trade in manufactured goods.",
                ],
                "explanation": "Industrial factories concentrated employment in towns and cities, accelerating urbanization.",
                "topic": "industrialization",
                "difficulty": 3,
                "format": "Multiple Choice",
            },
            {
                "prompt": "An anticolonial leader invokes self-determination to oppose rule by an overseas empire. Which political outcome best matches that claim?",
                "expectedAnswer": "Sovereignty for an independent government chosen by the local population.",
                "choices": [
                    "Sovereignty for an independent government chosen by the local population.",
                    "Permanent appointment of governors by the imperial capital.",
                    "Expansion of colonial taxation without local representation.",
                    "Transfer of local courts to direct military administration.",
                ],
                "explanation": "Self-determination supports decolonization by locating political authority in the governed population.",
                "topic": "decolonization",
                "difficulty": 3,
                "format": "Multiple Choice",
            },
        ]

        for question in questions:
            with self.subTest(topic=question["topic"]):
                result = self.score_single_question(
                    "modern_world_history_source_reasoning", question
                )
                self.assertTrue(result["passed"], result)

    def test_topic_label_or_explanation_alone_cannot_fake_goal_grounding(self):
        for case_id in CROSS_DOMAIN_CASE_IDS:
            with self.subTest(case_id=case_id):
                fixture = self.fixtures[case_id]
                grounding_term = fixture["expect"]["required_grounding_terms_any"][0]
                generic_question = {
                    "prompt": "A learner reviews four unlabeled claims. Which claim should be selected?",
                    "expectedAnswer": "The first statement is selected.",
                    "choices": [
                        "The first statement is selected.",
                        "The second statement is rejected.",
                        "The third statement requires revision.",
                        "The fourth statement addresses another issue.",
                    ],
                    "explanation": f"The hidden subject label is {grounding_term}.",
                    "topic": fixture["payload"]["goal"].get("learningTarget", fixture["payload"]["goal"]["title"]),
                    "difficulty": fixture["payload"]["minimumDifficulty"],
                    "format": "Multiple Choice",
                }

                result = self.score_single_question(case_id, generic_question)

                self.assertFalse(result["passed"])
                self.assertTrue(
                    any(
                        "not visibly grounded" in failure
                        for failure in result["questions"][0]["failures"]
                    ),
                    result,
                )


if __name__ == "__main__":
    unittest.main()
