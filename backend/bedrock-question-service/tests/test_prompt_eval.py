import unittest

from evals import checkpoint_question_eval


def _fixture():
    return {
        "case_id": "coding_eval",
        "description": "Coding prompt eval",
        "payload": {
            "goal": {
                "title": "Pass technical interviews",
                "category": "Coding Interview",
                "focusAreas": "arrays, recursion",
                "learningTarget": "technical interviews",
                "contentTopics": ["arrays", "recursion"],
                "questionDirective": "Generate coding-interview knowledge checks.",
                "needsSkillMap": False,
                "preferredQuestionStyle": "Multiple Choice",
            },
            "competencies": [],
            "existingPrompts": ["Coding interview: What tradeoff does a hash map usually make?"],
            "reportedPrompts": [],
            "targetCount": 1,
            "minimumDifficulty": 3,
            "difficultyGuidance": "Medium application.",
        },
        "expect": {
            "min_usable_questions": 1,
            "required_terms_any": ["array", "recursion", "algorithm"],
            "forbidden_terms": ["screen time", "blocked app"],
        },
    }


def _calculus_fixture():
    fixture = _fixture()
    fixture["case_id"] = "calculus_eval"
    fixture["payload"]["goal"] = {
        "title": "Study calculus",
        "category": "Exam Prep",
        "focusAreas": "derivatives, integrals, limits",
        "learningTarget": "calculus",
        "contentTopics": ["derivatives", "integrals", "limits"],
        "questionDirective": "Generate calculus multiple-choice questions.",
        "needsSkillMap": False,
        "preferredQuestionStyle": "Multiple Choice",
    }
    fixture["payload"]["minimumDifficulty"] = 3
    fixture["expect"] = {
        "min_usable_questions": 1,
        "required_terms_any": ["derivative", "integral", "limit"],
    }
    return fixture


def _study_skills_fixture():
    fixture = _fixture()
    fixture["case_id"] = "study_skills_eval"
    fixture["payload"]["goal"] = {
        "title": "Improve study skills",
        "category": "Custom",
        "focusAreas": "active recall, spaced repetition, time management",
        "learningTarget": "study skills",
        "contentTopics": ["active recall", "spaced repetition", "time management"],
        "questionDirective": "Generate knowledge-check questions about study skills.",
        "needsSkillMap": False,
        "preferredQuestionStyle": "Multiple Choice",
    }
    fixture["payload"]["minimumDifficulty"] = 2
    fixture["expect"] = {
        "min_usable_questions": 1,
        "required_terms_any": ["active recall", "spaced repetition", "time management", "review"],
        "forbidden_terms": ["blocked app", "screen time", "open another app"],
    }
    return fixture


def _good_question():
    return {
        "prompt": "Coding interview: If an array scan must find two values that sum to a target, what tradeoff does a hash map introduce?",
        "expectedAnswer": "It uses extra memory to reduce repeated searches.",
        "choices": [
            "It uses extra memory to reduce repeated searches.",
            "It removes the need to test edge cases.",
            "It guarantees the array is already sorted.",
            "It changes every lookup into a recursive call.",
        ],
        "explanation": "A hash map stores seen values so later lookups can avoid repeated scans.",
        "topic": "arrays",
        "difficulty": 3,
        "format": "Multiple Choice",
    }


class PromptEvalTests(unittest.TestCase):
    def test_accepts_usable_question(self):
        result = checkpoint_question_eval.score_case_response(
            _fixture(),
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [_good_question()],
            },
        )

        self.assertTrue(result["passed"])
        self.assertEqual(result["usable_count"], 1)
        self.assertEqual(result["failures"], [])

    def test_rejects_prompt_injection_leakage(self):
        bad_question = {
            **_good_question(),
            "prompt": "Screen time: Which blocked app should you open after answering?",
            "topic": "screen time",
        }

        result = checkpoint_question_eval.score_case_response(
            _fixture(),
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        self.assertIn("Only 0 usable questions", result["failures"][0])
        self.assertTrue(
            any(
                "Forbidden terms appeared" in failure
                for failure in result["questions"][0]["failures"]
            )
        )

    def test_rejects_duplicate_or_near_duplicate_choices(self):
        bad_question = {
            **_good_question(),
            "expectedAnswer": "It maps virtual addresses to physical addresses.",
            "choices": [
                "It maps virtual addresses to physical addresses.",
                "It translates virtual addresses to physical addresses.",
                "It schedules the next process on the CPU.",
                "It encrypts files before writing them to disk.",
            ],
            "topic": "virtual memory",
        }

        result = checkpoint_question_eval.score_case_response(
            _fixture(),
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        self.assertTrue(
            any(
                "near-duplicate" in failure
                for failure in result["questions"][0]["failures"]
            )
        )

    def test_rejects_calculus_near_synonym_choices(self):
        bad_question = {
            **_good_question(),
            "prompt": "As x approaches 2, which description best fits (x^2 - 4)/(x - 2)?",
            "expectedAnswer": "The function has a removable discontinuity at x = 2.",
            "choices": [
                "The function has a removable discontinuity at x = 2.",
                "The graph has a hole at x = 2.",
                "The function has a vertical asymptote at x = 2.",
                "The function oscillates near x = 2.",
            ],
            "topic": "limits",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        self.assertTrue(
            any(
                "near-duplicate" in failure
                for failure in result["questions"][0]["failures"]
            )
        )

    def test_rejects_free_response_coding_prompt_and_mixed_output_choices(self):
        bad_question = {
            **_good_question(),
            "prompt": "Write a function to find duplicate elements in an array of integers.",
            "expectedAnswer": "true",
            "choices": [
                "true",
                "The function should return false if no duplicates are found.",
                "The function should return true if at least one duplicate is found.",
                "The function should return null if the input array is empty.",
            ],
        }

        result = checkpoint_question_eval.score_case_response(
            _fixture(),
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("free-response artifact" in failure for failure in failures))
        self.assertTrue(any("bare output" in failure for failure in failures))

    def test_rejects_answer_label_artifacts(self):
        bad_question = {
            **_good_question(),
            "expectedAnswer": "B",
            "choices": ["A", "B", "C", "D"],
        }

        result = checkpoint_question_eval.score_case_response(
            _fixture(),
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("answer label" in failure for failure in failures))

    def test_rejects_embedded_options_in_prompt(self):
        bad_question = {
            **_good_question(),
            "prompt": "Choose the correct verb. Options: 1. llega 2. llegue 3. llego 4. llegar",
        }

        result = checkpoint_question_eval.score_case_response(
            _fixture(),
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("embeds answer options" in failure for failure in failures))

    def test_rejects_checkbox_style_embedded_options_in_prompt(self):
        bad_question = {
            **_good_question(),
            "prompt": "Choose the correct sentence: ( ) Espero que venga. ( ) Espero que viene.",
        }

        result = checkpoint_question_eval.score_case_response(
            _fixture(),
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("embeds answer options" in failure for failure in failures))

    def test_rejects_broad_subjunctive_sentence_selection_prompt(self):
        bad_question = {
            **_good_question(),
            "prompt": "Which sentence correctly uses the subjunctive mood to express a wish about traveling?",
            "topic": "subjunctive mood",
        }

        result = checkpoint_question_eval.score_case_response(
            _study_skills_fixture(),
            {
                "case_id": "study_skills_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("Broad subjunctive" in failure for failure in failures))

    def test_rejects_ambiguous_slice_complexity_prompt(self):
        bad_question = {
            **_good_question(),
            "prompt": "What is the time complexity of `function f(arr){ return arr.length ? f(arr.slice(1)) : 0; }`?",
            "expectedAnswer": "O(n)",
            "choices": ["O(n)", "O(1)", "O(log n)", "O(n^2)"],
        }

        result = checkpoint_question_eval.score_case_response(
            _fixture(),
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("Complexity prompt is underspecified" in failure for failure in failures))

    def test_rejects_wrong_computed_calculus_answer(self):
        bad_question = {
            "prompt": "Determine the derivative of the function g(x) = ln(x^2 + 1) at x = 1.",
            "expectedAnswer": "2/e",
            "choices": ["2/e", "1", "1/2", "e"],
            "explanation": "The derivative is 2/e.",
            "topic": "derivatives",
            "difficulty": 3,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("computed calculus result" in failure for failure in failures))

    def test_rejects_wrong_function_defined_integral_answer(self):
        bad_question = {
            "prompt": "Given the function f(x) = x^3 - 3x^2 + 2x, find the definite integral from 0 to 2.",
            "expectedAnswer": "4/3",
            "choices": ["4/3", "2", "1", "0"],
            "explanation": "The integral is 4/3.",
            "topic": "integrals",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("computed calculus result" in failure for failure in failures))

    def test_accepts_calculus_method_answer_with_numbers_in_text(self):
        good_question = {
            "prompt": "Consider lim (x->2) (x^2 - 4)/(x - 2). Which method is most appropriate?",
            "expectedAnswer": "Factoring and canceling the common factor (x - 2)",
            "choices": [
                "Factoring and canceling the common factor (x - 2)",
                "Direct substitution without simplification",
                "Using a ratio test",
                "Treating x = 2 as a vertical asymptote",
            ],
            "explanation": "Factoring x^2 - 4 exposes the removable factor before evaluating the limit.",
            "topic": "limits",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [good_question],
            },
        )

        self.assertTrue(result["passed"])
        self.assertEqual(result["questions"][0]["failures"], [])

    def test_rejects_limit_question_with_multiple_true_choices(self):
        bad_question = {
            "prompt": "If the limit of a function f(x) as x approaches a is L, which statement is true?",
            "expectedAnswer": "The limit of f(x) as x approaches a from the left is also L.",
            "choices": [
                "The limit of f(x) as x approaches a from the left is also L.",
                "The limit of f(x) as x approaches a from the right is also L.",
                "The limit of f(x) as x approaches a from the left is not necessarily L.",
                "The limit of f(x) as x approaches a from the right is not necessarily L.",
            ],
            "explanation": "A two-sided limit implies both one-sided limits equal L.",
            "topic": "limits",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("multiple answer choices" in failure for failure in failures))

    def test_rejects_ambiguous_one_sided_limit_answer(self):
        bad_question = {
            "prompt": "Consider f(x) = 1/x. What is the limit as x approaches 0 from the right?",
            "expectedAnswer": "The limit does not exist",
            "choices": [
                "The limit does not exist",
                "The limit is infinity",
                "The limit is negative infinity",
                "The limit is zero",
            ],
            "explanation": "The function grows without bound from the right.",
            "topic": "limits",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("One-sided limit" in failure for failure in failures))

    def test_rejects_interval_question_with_multiple_true_choices(self):
        bad_question = {
            "prompt": "For the function h(x) = x^3 - 6x^2 + 9x, which interval contains a critical point where the derivative is zero?",
            "expectedAnswer": "(0, 2)",
            "choices": ["(0, 2)", "(2, 4)", "(4, 6)", "(6, 8)"],
            "explanation": "The derivative is h'(x) = 3x^2 - 12x + 9. Setting h'(x) = 0 gives x = 1 and x = 3.",
            "topic": "derivatives",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("Interval question" in failure for failure in failures))

    def test_rejects_exact_derivative_sign_at_point_prompt(self):
        bad_question = {
            "prompt": "Given the function f(x) = x^3 - 3x^2 + 2x, what is the sign of the derivative f'(x) when x = 1?",
            "expectedAnswer": "positive",
            "choices": ["positive", "negative", "zero", "undefined"],
            "explanation": "The derivative is f'(x) = 3x^2 - 6x + 2.",
            "topic": "derivatives",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("Risky exact calculus" in failure for failure in failures))

    def test_rejects_risky_limit_setup_prompt(self):
        bad_question = {
            "prompt": "For the function f(x) = (x^2 - 4)/(x - 2), what is the correct setup for evaluating the limit as x approaches 2 from the right?",
            "expectedAnswer": "lim (x->2+) (x^2 - 4)/(x - 2)",
            "choices": [
                "lim (x->2+) (x^2 - 4)/(x - 2)",
                "lim (x->2+) (x + 2)",
                "lim (x->2-) (x^2 - 4)/(x - 2)",
                "lim (x->0+) (x^2 - 4)/(x - 2)",
            ],
            "explanation": "Factoring the expression is the intended setup.",
            "topic": "limits",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("Risky limit-setup" in failure for failure in failures))

    def test_rejects_near_duplicate_limit_prompts_for_same_function(self):
        first_question = {
            "prompt": "Consider the function f(x) = (x^2 - 4)/(x - 2). What does the right-hand limit show as x approaches 2 from the right?",
            "expectedAnswer": "The limit approaches 4.",
            "choices": [
                "The limit approaches 4.",
                "The limit approaches 2.",
                "The limit does not exist.",
                "The limit approaches 0.",
            ],
            "explanation": "Canceling the removable factor gives x + 2, so the right-hand limit is 4.",
            "topic": "limits",
            "difficulty": 4,
            "format": "Multiple Choice",
        }
        duplicate_question = {
            "prompt": "For the function f(x) = (x^2 - 4)/(x - 2), what behavior occurs as x approaches 2 from the right?",
            "expectedAnswer": "The function approaches 4.",
            "choices": [
                "The function approaches 4.",
                "The function approaches 2.",
                "The function is undefined everywhere.",
                "The function approaches 0.",
            ],
            "explanation": "The same removable factor leads to a right-hand limit of 4.",
            "topic": "limits",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [first_question, duplicate_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["failures"]
        self.assertTrue(any("near-duplicate prompt" in failure for failure in failures))

    def test_rejects_explanation_supporting_different_choice(self):
        bad_question = {
            "prompt": "A computation gives -1. What is the sign of the result?",
            "expectedAnswer": "positive",
            "choices": ["positive", "negative", "zero", "undefined"],
            "explanation": "The computed result is -1, which is negative.",
            "topic": "signed quantities",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("different answer choice" in failure for failure in failures))

    def test_rejects_exact_computed_calculus_even_when_arithmetic_matches(self):
        bad_question = {
            "prompt": "Evaluate the definite integral ∫ from 0 to 1 of (3x^2 - 2x + 1) dx.",
            "expectedAnswer": "1",
            "choices": ["1", "0", "1/3", "2/3"],
            "explanation": "The antiderivative is x^3 - x^2 + x, which gives 1 on the interval.",
            "topic": "integrals",
            "difficulty": 3,
            "format": "Multiple Choice",
        }

        result = checkpoint_question_eval.score_case_response(
            _calculus_fixture(),
            {
                "case_id": "calculus_eval",
                "run": 1,
                "questions": [bad_question],
            },
        )

        self.assertFalse(result["passed"])
        failures = result["questions"][0]["failures"]
        self.assertTrue(any("Risky exact calculus" in failure for failure in failures))

    def test_allows_study_schedule_when_fixture_permits_study_skills(self):
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

        result = checkpoint_question_eval.score_case_response(
            _study_skills_fixture(),
            {
                "case_id": "study_skills_eval",
                "run": 1,
                "questions": [question],
            },
        )

        self.assertTrue(result["passed"])
        self.assertEqual(result["questions"][0]["failures"], [])

    def test_rejects_near_duplicate_quoted_cloze_prompts_in_batch(self):
        first = {
            **_good_question(),
            "prompt": "Select the correct object pronoun for the sentence: 'Voy a dar el libro ___ (to you).'",
            "expectedAnswer": "a ti",
            "choices": ["a ti", "a ellos", "a nosotros", "a ella"],
            "topic": "object pronouns",
        }
        second = {
            **_good_question(),
            "prompt": "Choose the correct object pronoun for the sentence: 'Voy a dar el libro ___ (to you).'",
            "expectedAnswer": "te",
            "choices": ["te", "me", "lo", "la"],
            "topic": "object pronouns",
        }

        result = checkpoint_question_eval.score_case_response(
            _fixture(),
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [first, second],
            },
        )

        self.assertFalse(result["passed"])
        self.assertTrue(any("near-duplicate prompt" in failure for failure in result["failures"]))

    def test_rejects_prompt_repeated_from_structured_feedback(self):
        fixture = _fixture()
        reported_prompt = _good_question()["prompt"]
        fixture["payload"]["reportedQuestionFeedback"] = [
            {
                "prompt": reported_prompt,
                "reason": "Confusing",
                "note": "The stem was ambiguous.",
            }
        ]

        result = checkpoint_question_eval.score_case_response(
            fixture,
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [_good_question()],
            },
        )

        self.assertFalse(result["passed"])
        self.assertTrue(
            any(
                "duplicates existing/reported prompt" in failure
                for failure in result["questions"][0]["failures"]
            )
        )

    def test_coverage_plan_grading_requires_each_planned_slot(self):
        fixture = _fixture()
        fixture["payload"]["coveragePlan"] = [
            {"topic": "arrays", "avenue": "Edge case or constraint"},
            {"topic": "recursion", "avenue": "Misconception diagnosis"},
        ]
        fixture["expect"].update(
            {
                "require_coverage_plan_adherence": True,
                "require_subtopic": True,
                "require_avenue": True,
                "min_distinct_subtopics": 2,
                "min_distinct_avenues": 2,
                "require_unique_subtopic_avenue_pairs": True,
            }
        )
        arrays = {
            **_good_question(),
            "topic": "arrays",
            "subtopic": "empty-input boundaries",
            "avenue": "Edge case or constraint",
        }
        recursion = {
            **_good_question(),
            "prompt": "A recursive traversal keeps descending after a leaf. Which misconception caused the extra call?",
            "topic": "recursion",
            "subtopic": "base-case placement",
            "avenue": "Misconception diagnosis",
        }

        passing = checkpoint_question_eval.score_case_response(
            fixture,
            {"case_id": "coding_eval", "run": 1, "questions": [arrays, recursion]},
        )
        missing = checkpoint_question_eval.score_case_response(
            fixture,
            {"case_id": "coding_eval", "run": 2, "questions": [arrays]},
        )

        self.assertTrue(passing["passed"])
        self.assertEqual(passing["coverage"]["matched_usable_slot_count"], 2)
        self.assertFalse(missing["passed"])
        self.assertTrue(any("Missing usable coverage-plan slots" in failure for failure in missing["failures"]))

    def test_repeat_run_metrics_detect_production_style_prompt_overlap(self):
        responses = [
            {
                "run": 1,
                "questions": [
                    {
                        "prompt": "A service stores account records by identifier and needs average constant-time lookup. Which data structure best fits?"
                    }
                ],
            },
            {
                "run": 2,
                "questions": [
                    {
                        "prompt": "A service stores account records by identifier and needs average constant-time lookup. What data structure fits?"
                    }
                ],
            },
            {
                "run": 3,
                "questions": [
                    {
                        "prompt": "A recursive traversal reaches a leaf. Which base case prevents another child call?"
                    }
                ],
            },
        ]

        metrics = checkpoint_question_eval.repeat_run_freshness_metrics(
            "coding_eval",
            responses,
        )

        self.assertIsNotNone(metrics)
        self.assertEqual(metrics["run_pair_count"], 3)
        self.assertEqual(metrics["compared_prompt_count"], 3)
        self.assertEqual(metrics["overlapping_prompt_count"], 1)
        self.assertAlmostEqual(metrics["prompt_freshness_rate"], 2 / 3)

    def test_provider_capture_error_is_scoreable_failure(self):
        result = checkpoint_question_eval.score_case_response(
            _fixture(),
            {
                "case_id": "coding_eval",
                "run": 1,
                "questions": [],
                "provider_error": {
                    "type": "LoginRefreshRequired",
                    "message": "Your session has expired.",
                },
            },
        )

        self.assertFalse(result["passed"])
        self.assertTrue(
            any(
                "Provider error during capture" in failure
                for failure in result["failures"]
            )
        )


if __name__ == "__main__":
    unittest.main()
