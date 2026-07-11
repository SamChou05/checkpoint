import unittest

from evals import checkpoint_question_eval


def _fixture():
    return {
        "case_id": "generic_eval",
        "description": "Domain-neutral scorer fixture",
        "payload": {
            "goal": {
                "title": "Learn a subject",
                "category": "Custom",
                "focusAreas": "target concept",
                "learningTarget": "target subject",
                "contentTopics": ["target concept"],
                "needsSkillMap": False,
                "preferredQuestionStyle": "Multiple Choice",
            },
            "competencies": [],
            "existingPrompts": [],
            "reportedPrompts": [],
            "targetCount": 1,
            "minimumDifficulty": 2,
            "difficultyGuidance": "Easy application.",
        },
        "expect": {
            "min_usable_questions": 1,
            "required_terms_any": ["target concept", "subject fact"],
            "forbidden_terms": ["screen time", "blocked app"],
        },
    }


def _study_skills_fixture():
    fixture = _fixture()
    fixture["case_id"] = "study_skills_eval"
    fixture["payload"]["goal"] = {
        "title": "Improve study skills",
        "category": "Custom",
        "focusAreas": "active recall, spaced repetition, time management",
        "learningTarget": "study skills",
        "contentTopics": ["active recall", "spaced repetition", "time management"],
        "needsSkillMap": False,
        "preferredQuestionStyle": "Multiple Choice",
    }
    fixture["expect"] = {
        "min_usable_questions": 1,
        "required_terms_any": ["active recall", "spaced repetition", "time management", "review"],
        "forbidden_terms": ["blocked app", "screen time", "open another app"],
    }
    return fixture


def _good_question():
    return {
        "prompt": "When a learner applies the target concept to this subject fact, which result follows?",
        "expectedAnswer": "The concept changes the stated result.",
        "choices": [
            "The concept changes the stated result.",
            "The concept removes every constraint.",
            "The concept makes the evidence irrelevant.",
            "The concept changes to another subject.",
        ],
        "explanation": "The subject fact states the condition needed for the target concept to change the result.",
        "topic": "target concept",
        "difficulty": 2,
        "format": "Multiple Choice",
    }


class PromptEvalTests(unittest.TestCase):
    def score(self, question, fixture=None):
        fixture = fixture or _fixture()
        return checkpoint_question_eval.score_case_response(
            fixture,
            {
                "case_id": fixture["case_id"],
                "run": 1,
                "questions": [question],
            },
        )

    def question_failures(self, question, fixture=None):
        return self.score(question, fixture)["questions"][0]["failures"]

    def test_accepts_usable_question(self):
        result = self.score(_good_question())

        self.assertTrue(result["passed"], result)
        self.assertEqual(result["usable_count"], 1)

    def test_rejects_forbidden_cross_domain_or_app_leakage(self):
        question = {
            **_good_question(),
            "prompt": "Which blocked app should a learner open after reviewing the target concept?",
            "topic": "screen time",
        }

        failures = self.question_failures(question)

        self.assertTrue(any("Forbidden terms appeared" in failure for failure in failures))

    def test_rejects_generic_meta_filler_question(self):
        question = {
            "prompt": "Level 4 advanced constraints: Which inference is best supported by the real world transfer evidence in target concepts?",
            "expectedAnswer": "The answer that follows from the stated facts and respects the topic's constraints.",
            "choices": [
                "The answer that follows from the stated facts and respects the topic's constraints.",
                "The answer that changes the topic to study planning.",
                "The answer that ignores qualifiers in the prompt.",
                "The answer that sounds familiar but adds unsupported assumptions.",
            ],
            "explanation": "Checkpoint should test the subject matter by rewarding constraint-aware reasoning, not broad study advice.",
            "topic": "target concept",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        failures = self.question_failures(question)

        self.assertTrue(any("generic meta-reasoning filler" in failure for failure in failures))

    def test_rejects_free_response_artifact(self):
        question = {
            **_good_question(),
            "prompt": "Write a program that demonstrates the target concept for this subject fact.",
        }

        failures = self.question_failures(question)

        self.assertTrue(any("free-response artifact" in failure for failure in failures))

    def test_rejects_answer_labels_instead_of_answer_text(self):
        question = {
            **_good_question(),
            "expectedAnswer": "B",
            "choices": ["A", "B", "C", "D"],
        }

        failures = self.question_failures(question)

        self.assertTrue(any("answer label" in failure for failure in failures))

    def test_rejects_embedded_answer_options(self):
        question = {
            **_good_question(),
            "prompt": "Apply the target concept. Options: 1. first 2. second 3. third 4. fourth",
        }

        failures = self.question_failures(question)

        self.assertTrue(any("embeds answer options" in failure for failure in failures))

    def test_rejects_duplicate_choices_after_generic_normalization(self):
        question = {
            **_good_question(),
            "expectedAnswer": "The supported result",
            "choices": [
                "The supported result",
                "Choice B: the supported result!",
                "A contradictory result",
                "An unrelated result",
            ],
        }

        failures = self.question_failures(question)

        self.assertTrue(any("duplicates after case" in failure for failure in failures))

    def test_rejects_disallowed_all_or_none_choices(self):
        question = {
            **_good_question(),
            "choices": [
                _good_question()["expectedAnswer"],
                "The concept removes every constraint.",
                "The concept makes the evidence irrelevant.",
                "All of the above",
            ],
        }

        failures = self.question_failures(question)

        self.assertTrue(any("Disallowed choice text" in failure for failure in failures))

    def test_rejects_expected_answer_missing_from_choices(self):
        question = {
            **_good_question(),
            "expectedAnswer": "A result not listed in the choices.",
        }

        failures = self.question_failures(question)

        self.assertTrue(any("exactly match one choice" in failure for failure in failures))

    def test_rejects_question_below_requested_difficulty(self):
        fixture = _fixture()
        fixture["payload"]["minimumDifficulty"] = 4
        question = {**_good_question(), "difficulty": 2}

        failures = self.question_failures(question, fixture)

        self.assertTrue(any("below requested minimum" in failure for failure in failures))

    def test_rejects_existing_or_reported_prompt(self):
        fixture = _fixture()
        fixture["payload"]["reportedPrompts"] = [_good_question()["prompt"]]

        failures = self.question_failures(_good_question(), fixture)

        self.assertTrue(any("duplicates existing/reported prompt" in failure for failure in failures))

    def test_rejects_missing_fixture_subject_signal(self):
        question = {
            **_good_question(),
            "prompt": "When the evidence changes, which concrete result follows from the new condition?",
            "choices": [
                "The first result follows.",
                "The second result follows.",
                "The third result follows.",
                "The fourth result follows.",
            ],
            "expectedAnswer": "The first result follows.",
            "explanation": "The new condition supports the first result.",
            "topic": "unrelated material",
        }

        failures = self.question_failures(question)

        self.assertTrue(any("No required subject signal" in failure for failure in failures))

    def test_rejects_repeated_prompt_within_batch(self):
        fixture = _fixture()
        fixture["expect"]["min_usable_questions"] = 2

        result = checkpoint_question_eval.score_case_response(
            fixture,
            {
                "case_id": fixture["case_id"],
                "run": 1,
                "questions": [_good_question(), _good_question()],
            },
        )

        self.assertFalse(result["passed"])
        self.assertTrue(any("Duplicate or near-duplicate prompt" in failure for failure in result["failures"]))

    def test_rejects_explanation_supporting_another_choice(self):
        question = {
            **_good_question(),
            "prompt": "A measured value is -1. What is the sign of this subject fact?",
            "expectedAnswer": "positive",
            "choices": ["positive", "negative", "zero", "undefined"],
            "explanation": "The measured result is -1, which is negative.",
        }

        failures = self.question_failures(question)

        self.assertTrue(any("different answer choice" in failure for failure in failures))

    def test_allows_study_schedule_when_study_skills_are_the_goal(self):
        question = {
            "prompt": "Which benefit does spaced repetition add to a study schedule?",
            "expectedAnswer": "It reinforces memory over time.",
            "choices": [
                "It reinforces memory over time.",
                "It removes the need to review.",
                "It guarantees perfect recall immediately.",
                "It works only for one subject at a time.",
            ],
            "explanation": "Spaced repetition schedules review over time to strengthen memory.",
            "topic": "spaced repetition",
            "difficulty": 2,
            "format": "Multiple Choice",
        }

        result = self.score(question, _study_skills_fixture())

        self.assertTrue(result["passed"], result)

    def test_provider_capture_error_is_a_scoreable_failure(self):
        fixture = _fixture()
        result = checkpoint_question_eval.score_case_response(
            fixture,
            {
                "case_id": fixture["case_id"],
                "run": 1,
                "questions": [],
                "provider_error": {
                    "type": "LoginRefreshRequired",
                    "message": "Your session has expired.",
                },
            },
        )

        self.assertFalse(result["passed"])
        self.assertTrue(any("Provider error during capture" in failure for failure in result["failures"]))


if __name__ == "__main__":
    unittest.main()
