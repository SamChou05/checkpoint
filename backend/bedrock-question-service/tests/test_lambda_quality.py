import json
import os
import unittest

import lambda_function
from question_bank_common import _stem_fingerprint
from lambda_test_support import (
    BackendTestCase,
    FakeBedrockClient,
    _event,
    _raw_question,
    _request_payload,
)


class LambdaQualityTests(BackendTestCase):
    def test_blocked_stem_fingerprint_contract_is_bounded_and_strict(self):
        valid = _stem_fingerprint("Which conclusion follows from the evidence?")
        payload = _request_payload(target_count=1)
        payload["blockedStemFingerprints"] = [valid, valid]

        normalized = lambda_function._normalize_request(payload)  # noqa: SLF001

        self.assertEqual(normalized["blockedStemFingerprints"], [valid])
        boundary_payload = _request_payload(target_count=1)
        boundary_payload["blockedStemFingerprints"] = [
            f"{index:016x}" for index in range(750)
        ]
        boundary = lambda_function._normalize_request(  # noqa: SLF001
            boundary_payload
        )
        self.assertEqual(len(boundary["blockedStemFingerprints"]), 750)
        invalid_values = [
            "not-an-array",
            ["A" * 16],
            ["0" * 15],
            [1],
            ["0" * 16] * 751,
        ]
        for invalid in invalid_values:
            with self.subTest(
                invalid=invalid if isinstance(invalid, str) else len(invalid)
            ):
                invalid_payload = _request_payload(target_count=1)
                invalid_payload["blockedStemFingerprints"] = invalid
                with self.assertRaises(ValueError):
                    lambda_function._normalize_request(invalid_payload)  # noqa: SLF001

    def test_blocked_stem_fingerprint_filters_without_reaching_provider_prompt(self):
        question = _raw_question(
            "LSAT Logical Reasoning: Which conclusion follows from the stated evidence?"
        )
        fingerprint = _stem_fingerprint(question["prompt"])
        payload = _request_payload(target_count=1)
        payload["blockedStemFingerprints"] = [fingerprint]
        request = lambda_function._normalize_request(payload)  # noqa: SLF001

        sanitized = lambda_function._sanitize_questions(  # noqa: SLF001
            [question],
            request,
        )
        initial_prompt = lambda_function._user_prompt(request)  # noqa: SLF001
        retry_prompt = lambda_function._json_retry_prompt(  # noqa: SLF001
            request,
            "malformed",
        )

        self.assertEqual(sanitized, [])
        for provider_prompt in (initial_prompt, retry_prompt):
            self.assertNotIn("blockedStemFingerprints", provider_prompt)
            self.assertNotIn(fingerprint, provider_prompt)

    def test_rejects_questions_below_requested_difficulty(self):
        client = FakeBedrockClient.returning_questions(
            _raw_question(
                "LSAT Logical Reasoning: Which assumption is required by the argument?",
                difficulty=2,
            ),
            _raw_question(
                "LSAT Logical Reasoning: Which flaw best describes the argument?",
                difficulty=4,
            ),
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=3, minimum_difficulty=4)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertEqual(len(body["questions"]), 1)
        self.assertEqual(body["questions"][0]["difficulty"], 4)
        self.assertIn("Which flaw", body["questions"][0]["prompt"])

    def test_accepts_provider_top_level_question_array(self):
        client = FakeBedrockClient(
            json.dumps(
                [
                    _raw_question(
                        "LSAT Logical Reasoning: If every credited claim requires evidence and Park's claim was credited, what follows?"
                    )
                ]
            )
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("LSAT Logical Reasoning", questions[0]["prompt"])

    def test_retries_once_when_provider_returns_non_json(self):
        client = FakeBedrockClient(
            [
                "Here are two LSAT questions in prose instead of JSON.",
                FakeBedrockClient.question_response(
                    _raw_question(
                        "LSAT Logical Reasoning: Which answer identifies the argument's required assumption?"
                    )
                ),
            ]
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(len(client.calls), 2)
        retry_prompt = client.calls[1]["messages"][0]["content"][0]["text"]
        self.assertIn("previous response could not be parsed", retry_prompt)
        self.assertIn("diagnostic data only", retry_prompt)
        self.assertEqual(len(json.loads(response["body"])["questions"]), 1)

    def test_tops_off_short_sanitized_batch(self):
        client = FakeBedrockClient(
            [
                FakeBedrockClient.question_response(
                    _raw_question(
                        "LSAT Logical Reasoning: Which assumption lets the conclusion follow?",
                        expected_answer=(
                            "The conclusion requires an unstated bridge between the evidence "
                            "and the claimed result."
                        ),
                        explanation=(
                            "Without that bridge, the premises do not establish the claimed result."
                        ),
                    ),
                    _raw_question(
                        "LSAT Logical Reasoning: Which flaw best describes the argument?",
                        expected_answer=(
                            "The argument treats a correlation as proof that one event caused the other."
                        ),
                        explanation=(
                            "The observed correlation does not rule out coincidence or a shared cause."
                        ),
                    ),
                ),
                FakeBedrockClient.question_response(
                    _raw_question(
                        "LSAT Reading Comprehension: Which answer captures the author's qualified view?",
                        expected_answer=(
                            "The author supports the proposal while reserving judgment about "
                            "its long-term effects."
                        ),
                        explanation=(
                            "The passage endorses the proposal but explicitly leaves its "
                            "long-term effects unresolved."
                        ),
                        topic="Reading Comprehension",
                    )
                ),
            ]
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 3)
        self.assertEqual(len(client.calls), 2)
        second_prompt = client.calls[1]["messages"][0]["content"][0]["text"]
        self.assertIn("Generate exactly 1 multiple-choice questions", second_prompt)
        self.assertIn("Use level 3 of 5 difficulty", second_prompt)

    def test_top_off_attempt_cannot_repeat_an_accepted_stem(self):
        first = _raw_question(
            "A policy applies to every licensed operator. Vega is licensed. What follows?",
            expected_answer="The policy applies to Vega.",
            explanation="Vega belongs to the stated set of licensed operators.",
        )
        repeated_stem = _raw_question(
            first["prompt"],
            expected_answer="Vega is governed by the policy.",
            explanation="The universal rule covers Vega under a different explanation.",
        )
        repeated_stem["choices"] = [
            repeated_stem["expectedAnswer"],
            "Vega is automatically exempt from the policy.",
            "The policy applies only to unlicensed operators.",
            "Nothing follows about any licensed operator.",
        ]
        novel = _raw_question(
            "A permit expires only after notice. No notice was sent. What follows?",
            expected_answer="The permit has not expired under the stated rule.",
            explanation="The necessary notice condition has not occurred.",
        )
        client = FakeBedrockClient(
            [
                FakeBedrockClient.question_response(first),
                FakeBedrockClient.question_response(repeated_stem, novel),
            ]
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=2)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(
            [question["prompt"] for question in questions],
            [first["prompt"], novel["prompt"]],
        )
        self.assertEqual(len(client.calls), 2)

    def test_existing_coverage_prompt_blocks_same_stem_without_prompt_list(self):
        repeated = _raw_question(
            "A cache entry is valid but absent from memory. What must happen next?"
        )
        request = lambda_function._normalize_request(  # noqa: SLF001
            _request_payload(target_count=1)
        )
        request["existingPrompts"] = []
        request["existingQuestionCoverage"] = [
            {
                "topic": "",
                "prompt": repeated["prompt"],
                "expectedAnswer": "",
                "choices": [],
                "difficulty": 3,
            }
        ]

        sanitized = lambda_function._sanitize_questions([repeated], request)  # noqa: SLF001

        self.assertEqual(sanitized, [])

    def test_uses_fallback_model_after_primary_json_failures(self):
        os.environ["BEDROCK_MODEL_ID"] = "google.gemma-3-4b-it"
        os.environ["BEDROCK_FALLBACK_MODEL_ID"] = "amazon.nova-micro-v1:0"
        client = FakeBedrockClient(
            [
                "Not JSON.",
                "Still not JSON.",
                FakeBedrockClient.question_response(
                    _raw_question(
                        "LSAT Logical Reasoning: Which assumption lets the conclusion follow?"
                    )
                ),
            ]
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            [call["modelId"] for call in client.calls],
            [
                "google.gemma-3-4b-it",
                "google.gemma-3-4b-it",
                "amazon.nova-micro-v1:0",
            ],
        )
        self.assertEqual(len(json.loads(response["body"])["questions"]), 1)

    def test_uses_fallback_model_after_primary_invocation_failure(self):
        os.environ["BEDROCK_MODEL_ID"] = "amazon.unsupported-model-v1:0"
        os.environ["BEDROCK_FALLBACK_MODEL_ID"] = "amazon.nova-lite-v1:0"
        client = FakeBedrockClient(
            [
                RuntimeError("Invocation of model ID is not supported."),
                FakeBedrockClient.question_response(
                    _raw_question(
                        "LSAT Logical Reasoning: Which assumption lets the conclusion follow?"
                    )
                ),
            ]
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            [call["modelId"] for call in client.calls],
            [
                "amazon.unsupported-model-v1:0",
                "amazon.nova-lite-v1:0",
            ],
        )
        self.assertEqual(len(json.loads(response["body"])["questions"]), 1)

    def test_default_configuration_does_not_silently_switch_models(self):
        client = FakeBedrockClient(RuntimeError("Primary model unavailable."))

        with self.assertLogs(lambda_function.LOGGER, level="ERROR"):
            response = lambda_function.handle_http_request(
                _event(_request_payload(target_count=1)),
                bedrock_client=client,
            )

        self.assertEqual(response["statusCode"], 502)
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(client.calls[0]["modelId"], "amazon.nova-lite-v1:0")

    def test_extracts_json_from_markdown_with_exact_answer_choice(self):
        client = FakeBedrockClient(
            """
```json
{
  "questions": [
    {
      "prompt": "LSAT Reading Comprehension: A critic calls a policy useful but incomplete. What is the critic's attitude?",
      "expectedAnswer": "Qualified approval.",
      "choices": ["Total rejection.", "Neutral description.", "Confusion about the policy.", "Qualified approval."],
      "explanation": "Useful is positive, while incomplete limits the approval.",
      "topic": "Reading Comprehension",
      "difficulty": 4,
      "format": "Multiple Choice"
    }
  ]
}
```
"""
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=4)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        question = json.loads(response["body"])["questions"][0]
        self.assertEqual(question["choices"][0], "Qualified approval.")
        self.assertEqual(question["difficulty"], 4)

    def test_filters_duplicates_and_study_strategy_prompts(self):
        client = FakeBedrockClient.returning_questions(
            {
                "prompt": "Existing prompt",
                "expectedAnswer": "A",
                "choices": ["A", "B", "C", "D"],
                "explanation": "Duplicate.",
                "topic": "Logical Reasoning",
                "difficulty": 3,
                "format": "Multiple Choice",
            },
            {
                "prompt": "How should you study for the LSAT after missing a flaw question?",
                "expectedAnswer": "Review the flaw type.",
                "choices": [
                    "Review the flaw type.",
                    "Open another app.",
                    "Stop reading.",
                    "Skip the topic.",
                ],
                "explanation": "Study advice.",
                "topic": "Study plan",
                "difficulty": 3,
                "format": "Multiple Choice",
            },
            {
                "prompt": "LSAT Logical Reasoning: An argument infers causation from a before-after change. What flaw is most likely?",
                "expectedAnswer": "It treats temporal order as sufficient proof of causation.",
                "choices": [
                    "It treats temporal order as sufficient proof of causation.",
                    "It defines the conclusion too narrowly.",
                    "It proves the opposite conclusion.",
                    "It relies on a mathematical calculation.",
                ],
                "explanation": "A before-after pattern alone does not prove causation.",
                "topic": "Logical Reasoning",
                "difficulty": 4,
                "format": "Multiple Choice",
            },
        )

        payload = _request_payload(target_count=3, minimum_difficulty=3)
        payload["existingPrompts"] = ["Existing prompt"]
        response = lambda_function.handle_http_request(
            _event(payload), bedrock_client=client
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("causation", questions[0]["prompt"])

    def test_study_strategy_goal_signal_matches_ios_title_and_focus_areas(self):
        payload = _request_payload(target_count=1)
        payload["goal"]["title"] = "Build stronger productivity habits"
        payload["goal"]["focusAreas"] = "time management"
        payload["goal"]["learningTarget"] = "Daily routines"
        request = lambda_function._normalize_request(payload)  # noqa: SLF001
        question = _raw_question(
            "When a distraction interrupts a work block, what should you do next?"
        )

        sanitized = lambda_function._sanitize_questions(  # noqa: SLF001
            [question],
            request,
        )

        self.assertEqual(len(sanitized), 1)

    def test_rejects_quoted_generic_meta_filler_question(self):
        request = lambda_function._normalize_request(  # noqa: SLF001
            {
                "goal": {
                    "title": "Study for LeetCode-style interviews",
                    "category": "Coding Interview",
                    "focusAreas": "hash maps",
                    "learningTarget": "LeetCode-style interviews",
                    "contentTopics": ["hash maps"],
                    "questionDirective": "Generate concrete coding-interview questions.",
                    "needsSkillMap": False,
                },
                "targetCount": 1,
                "minimumDifficulty": 4,
            }
        )
        question = {
            "prompt": "Level 4 advanced constraints: Which inference is best supported by the real world transfer evidence in hash maps? Pay close attention to qualifiers and edge cases.",
            "expectedAnswer": "The answer that follows from the stated facts and respects the topic's constraints.",
            "choices": [
                "The answer that follows from the stated facts and respects the topic's constraints.",
                "The answer that changes the topic to study planning.",
                "The answer that ignores qualifiers in the prompt.",
                "The answer that sounds familiar but adds unsupported assumptions.",
            ],
            "explanation": "Checkpoint should test the subject matter by rewarding constraint-aware reasoning, not broad study advice.",
            "topic": "hash maps",
            "difficulty": 4,
            "format": "Multiple Choice",
        }

        sanitized = lambda_function._sanitize_questions([question], request)  # noqa: SLF001

        self.assertEqual(sanitized, [])

    def test_rejects_generic_meta_choice_family_with_reworded_expected_answer(self):
        request = lambda_function._normalize_request(_request_payload(target_count=1))  # noqa: SLF001
        question = {
            "prompt": "A hash-map lookup is evaluated under a stated load-factor limit. Which conclusion follows?",
            "expectedAnswer": "The load-factor limit keeps the expected lookup cost bounded.",
            "choices": [
                "The load-factor limit keeps the expected lookup cost bounded.",
                "The answer that changes the topic to study planning.",
                "The answer that ignores qualifiers in the prompt.",
                "The answer that sounds familiar but adds unsupported assumptions.",
            ],
            "explanation": "The load-factor constraint controls expected bucket occupancy.",
            "topic": "hash maps",
            "difficulty": 3,
            "format": "Multiple Choice",
        }

        sanitized = lambda_function._sanitize_questions([question], request)  # noqa: SLF001

        self.assertEqual(sanitized, [])

    def test_generic_answer_is_not_exempted_from_coverage_deduplication(self):
        answer = "The answer that follows from the stated facts and respects the topic's constraints."

        keys = lambda_function._question_coverage_keys(  # noqa: SLF001
            answer,
            "hash maps",
        )

        topic_key = lambda_function._choice_uniqueness_key("hash maps")  # noqa: SLF001
        answer_key = lambda_function._choice_uniqueness_key(answer)  # noqa: SLF001
        self.assertIn(f"topic-answer:{len(topic_key.encode('utf-8'))}:{topic_key}{answer_key}", keys)

    def test_rejects_reused_choice_set_across_reworded_questions(self):
        request = lambda_function._normalize_request(  # noqa: SLF001
            _request_payload(target_count=2, minimum_difficulty=3)
        )
        choices = [
            "Store seen values in a hash map and check each complement.",
            "Sort the values and discard their original indices.",
            "Compare every possible pair without storing state.",
            "Push values onto a stack and compare adjacent entries.",
        ]
        first = {
            "prompt": "An array needs two original indices whose values sum to a target. Which approach gives expected linear time?",
            "expectedAnswer": choices[0],
            "choices": choices,
            "explanation": "Complement lookups avoid an inner scan while retaining indices.",
            "topic": "arrays",
            "difficulty": 3,
        }
        duplicate_mechanism = {
            **first,
            "prompt": "For two-sum on an unsorted array, which method avoids checking every pair?",
            "topic": "hash maps",
        }

        sanitized = lambda_function._sanitize_questions(  # noqa: SLF001
            [first, duplicate_mechanism],
            request,
        )

        self.assertEqual(
            [question["prompt"] for question in sanitized], [first["prompt"]]
        )

    def test_system_prompt_is_universal_instead_of_naming_special_case_domains(self):
        system_prompt = lambda_function._system_prompt()  # noqa: SLF001

        self.assertIn("for any learning goal", system_prompt)
        self.assertIn("Test the subject itself", system_prompt)
        self.assertIn("Each stem must be self-contained", system_prompt)
        self.assertIn("three plausible but demonstrably wrong answers", system_prompt)
        self.assertIn("Choose the assigned objective", system_prompt)
        for overfit_term in [
            "LeetCode",
            "system-design",
            "Spanish",
            "subjunctive",
            "calculus",
        ]:
            self.assertNotIn(overfit_term, system_prompt)

    def test_allows_similar_quoted_prompts_when_stems_differ(self):
        first = _raw_question(
            "Select the correct object pronoun for the sentence: 'Necesito encontrar el hotel antes de la noche.'"
        )
        second = _raw_question(
            "Choose the correct object pronoun to replace 'el hotel' in the sentence: 'Necesito encontrar el hotel antes de la noche.'"
        )
        third = _raw_question(
            "Spanish grammar: Complete the sentence with the subjunctive form of viajar: Espero que ellos ___ (viajar)."
        )
        client = FakeBedrockClient.returning_questions(first, second, third)

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=3, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 3)
        self.assertEqual(questions[0]["prompt"], first["prompt"])
        self.assertEqual(questions[1]["prompt"], second["prompt"])
        self.assertEqual(questions[2]["prompt"], third["prompt"])

    def test_allows_distinct_questions_about_the_same_quoted_passage(self):
        passage = "'The river rose overnight, covering the lower trail.'"
        meaning = _raw_question(
            f"According to {passage}, what changed?",
            expected_answer="The river level increased and covered the lower trail.",
            explanation="The passage says the river rose and then covered the lower trail.",
            topic="Reading Comprehension",
        )
        meaning["choices"] = [
            meaning["expectedAnswer"],
            "The river dried up and exposed the trail.",
            "The trail moved to higher ground.",
            "The passage describes no physical change.",
        ]
        timing = _raw_question(
            f"According to {passage}, when did the change occur?",
            expected_answer="It occurred overnight.",
            explanation="The passage explicitly places the river's rise overnight.",
            topic="Sequence and Timing",
        )
        timing["choices"] = [
            timing["expectedAnswer"],
            "It occurred at noon.",
            "It occurred one week earlier.",
            "The passage provides no timing information.",
        ]
        client = FakeBedrockClient.returning_questions(meaning, timing)

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=2, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(
            [question["prompt"] for question in questions],
            [meaning["prompt"], timing["prompt"]],
        )

    def test_rejects_exact_duplicate_answer_choices(self):
        client = FakeBedrockClient(
            json.dumps(
                {
                    "questions": [
                        {
                            "prompt": "Operating Systems: What does the MMU do during address translation?",
                            "expectedAnswer": "It translates virtual memory addresses to physical memory addresses.",
                            "choices": [
                                "It translates virtual memory addresses to physical memory addresses.",
                                "It translates virtual memory addresses to physical memory addresses.",
                                "It encrypts process memory before each context switch.",
                                "It schedules interrupts for blocked I/O devices.",
                            ],
                            "explanation": "The MMU translates virtual addresses into physical addresses.",
                            "topic": "Virtual Memory",
                            "difficulty": 3,
                            "format": "Multiple Choice",
                        },
                        _raw_question(
                            "LSAT Logical Reasoning: Which answer identifies the required assumption?"
                        ),
                    ]
                }
            )
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=2, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertNotIn("MMU", questions[0]["prompt"])

    def test_short_plural_choice_boundary_matches_client(self):
        question = _raw_question(
            "Animal vocabulary: Which option names one feline?",
            expected_answer="A cat",
            explanation="A cat names one feline.",
            topic="Animal vocabulary",
        )
        question["choices"] = ["A cat", "cats", "dogs", "birds"]
        request = lambda_function._normalize_request(  # noqa: SLF001
            _request_payload(target_count=1, minimum_difficulty=3)
        )

        sanitized = lambda_function._sanitize_questions(  # noqa: SLF001
            [question],
            request,
        )

        self.assertEqual(len(sanitized), 1)
        self.assertEqual(set(sanitized[0]["choices"]), set(question["choices"]))

    def test_rejects_same_topic_answer_as_existing_coverage(self):
        repeated = {
            "prompt": "Operating Systems: Which MMU behavior is central to virtual memory?",
            "expectedAnswer": "It translates virtual memory addresses to physical memory addresses.",
            "choices": [
                "It translates virtual memory addresses to physical memory addresses.",
                "It chooses the next process to run on the CPU.",
                "It stores every interrupt handler in user space.",
                "It compresses disk blocks before loading pages.",
            ],
            "explanation": "The MMU translates virtual addresses to physical addresses.",
            "topic": "Virtual Memory",
            "difficulty": 3,
            "format": "Multiple Choice",
        }
        novel = {
            "prompt": "Operating Systems: Why can a valid virtual address still cause a page fault?",
            "expectedAnswer": "The page is valid but not currently resident in physical memory.",
            "choices": [
                "The page is valid but not currently resident in physical memory.",
                "The process has no virtual address space.",
                "The CPU cannot execute after any interrupt.",
                "The stack pointer must equal the page-table base.",
            ],
            "explanation": "A valid virtual page can still require loading or remapping before access completes.",
            "topic": "Virtual Memory",
            "difficulty": 3,
            "format": "Multiple Choice",
        }
        payload = _request_payload(target_count=2, minimum_difficulty=3)
        payload["existingQuestionCoverage"] = [
            {
                "topic": "Virtual Memory",
                "prompt": "Operating Systems: What does the MMU do during address translation?",
                "expectedAnswer": "It translates virtual memory addresses to physical memory addresses.",
                "difficulty": 3,
            }
        ]
        client = FakeBedrockClient.returning_questions(repeated, novel)

        response = lambda_function.handle_http_request(
            _event(payload), bedrock_client=client
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("page fault", questions[0]["prompt"])

    def test_rejects_overlong_provider_prompts_before_clipping(self):
        long_prompt = "LSAT Logical Reasoning: " + ("This stimulus is too long. " * 20)
        client = FakeBedrockClient.returning_questions(
            _raw_question(long_prompt),
            _raw_question(
                "LSAT Logical Reasoning: Which answer identifies the required assumption?"
            ),
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("required assumption", questions[0]["prompt"])

    def test_rejects_explanations_that_admit_bad_answer(self):
        bad_question = _raw_question("Calculus: What is the value of this limit?")
        bad_question["explanation"] = (
            "The provided choices do not include the correct answer."
        )
        client = FakeBedrockClient.returning_questions(
            bad_question,
            _raw_question(
                "Calculus: Which answer correctly applies the derivative rule?"
            ),
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("derivative rule", questions[0]["prompt"])

    def test_rejects_answer_label_when_it_is_not_an_actual_choice(self):
        bad_question = _raw_question(
            "Calculus: Which option gives the derivative at x = 1?"
        )
        bad_question["expectedAnswer"] = "B"
        bad_question["choices"] = ["0", "1", "2", "4"]
        client = FakeBedrockClient.returning_questions(
            bad_question,
            _raw_question("Calculus: Which answer correctly applies the chain rule?"),
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("chain rule", questions[0]["prompt"])

    def test_accepts_verified_computation_without_coding_specific_shape_rules(self):
        question = _raw_question(
            "What is the time complexity of `function f(arr){ return arr.length ? f(arr.slice(1)) : 0; }`?"
        )
        question["expectedAnswer"] = "O(n^2)"
        question["choices"] = ["O(n^2)", "O(n)", "O(log n)", "O(1)"]
        question["explanation"] = (
            "The recursive calls copy slices of n, n-1, and smaller elements, so the total copied work is quadratic."
        )
        client = FakeBedrockClient.returning_questions(question)

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("time complexity", questions[0]["prompt"])

    def test_accepts_verified_quantitative_question_without_calculus_specific_rules(
        self,
    ):
        question = _raw_question(
            "Given f(x) = x^2, what is the definite integral from 0 to 2?"
        )
        question["expectedAnswer"] = "8/3"
        question["choices"] = ["8/3", "4", "2", "4/3"]
        question["explanation"] = (
            "An antiderivative is x^3/3; evaluating it from 0 to 2 gives 8/3."
        )
        client = FakeBedrockClient.returning_questions(question)

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("definite integral", questions[0]["prompt"])

    def test_accepts_valid_science_question_through_universal_sanitizer(self):
        question = _raw_question(
            "A cell is placed in a solution with a lower solute concentration than its cytoplasm. What happens next?"
        )
        question["expectedAnswer"] = "Water moves into the cell by osmosis."
        question["choices"] = [
            "Water moves into the cell by osmosis.",
            "Water moves out of the cell by osmosis.",
            "Solute leaves until both sides contain no water.",
            "The membrane stops all molecular movement.",
        ]
        question["explanation"] = (
            "Water moves toward the side with the higher solute concentration, so it enters the cell."
        )
        question["topic"] = "Osmosis"
        client = FakeBedrockClient.returning_questions(question)

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertEqual(questions[0]["topic"], "Osmosis")

    def test_accepts_verified_point_calculation_without_shape_filter(self):
        question = _raw_question(
            "Given the function f(x) = x^3 - 3x^2 + 2x, what is the sign of the derivative f'(x) when x = 1?"
        )
        question["expectedAnswer"] = "negative"
        question["choices"] = ["negative", "positive", "zero", "undefined"]
        question["explanation"] = (
            "The derivative is 3x^2 - 6x + 2, which equals -1 at x = 1."
        )
        client = FakeBedrockClient.returning_questions(question)

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("sign of the derivative", questions[0]["prompt"])

    def test_accepts_valid_method_question_without_limit_specific_filter(self):
        question = _raw_question(
            "For f(x) = (x^2 - 4)/(x - 2), which simplification is valid before evaluating the limit as x approaches 2?"
        )
        question["expectedAnswer"] = (
            "Cancel x - 2 to obtain x + 2 for x not equal to 2."
        )
        question["choices"] = [
            "Cancel x - 2 to obtain x + 2 for x not equal to 2.",
            "Cancel x + 2 to obtain x - 2 for every x.",
            "Replace x^2 - 4 with x - 4 before substitution.",
            "Set the denominator equal to 2 before factoring.",
        ]
        question["explanation"] = (
            "Factoring the numerator as (x - 2)(x + 2) permits cancellation away from x = 2."
        )
        client = FakeBedrockClient.returning_questions(question)

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("simplification", questions[0]["prompt"])

    def test_rejects_exact_duplicate_prompts_without_domain_semantics(self):
        first_question = _raw_question(
            "Consider the function f(x) = (x^2 - 4)/(x - 2). What does the right-hand limit show as x approaches 2 from the right?"
        )
        duplicate_question = _raw_question(first_question["prompt"])
        third_question = _raw_question(
            "Calculus: Which graph behavior indicates a jump discontinuity?"
        )
        client = FakeBedrockClient.returning_questions(
            first_question,
            duplicate_question,
            third_question,
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=2, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(
            [question["prompt"] for question in questions],
            [first_question["prompt"], third_question["prompt"]],
        )

    def test_rejects_explanation_supporting_different_choice(self):
        bad_question = _raw_question(
            "A computation gives -1. What is the sign of the result?"
        )
        bad_question["expectedAnswer"] = "positive"
        bad_question["choices"] = ["positive", "negative", "zero", "undefined"]
        bad_question["explanation"] = "The computed result is -1, which is negative."
        client = FakeBedrockClient.returning_questions(
            bad_question,
            _raw_question(
                "Math reasoning: Which statement follows from a negative computed result?"
            ),
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("negative computed result", questions[0]["prompt"])

    def test_rejects_prompts_with_embedded_answer_options(self):
        bad_question = _raw_question(
            "Choose the correct Spanish verb. Options: 1. llega 2. llegue 3. llego 4. llegar"
        )
        client = FakeBedrockClient.returning_questions(
            bad_question,
            _raw_question(
                "Spanish grammar: Complete the sentence with the subjunctive form of llegar: Espero que ellos ___ (llegar)."
            ),
        )

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("subjunctive", questions[0]["prompt"])

    def test_strips_redundant_line_delimited_choice_echo_from_prompt(self):
        question = _raw_question(
            "During an inspection, many bees have deformed wings. What is the most likely cause?"
        )
        question["expectedAnswer"] = "B. Varroa mites"
        question["choices"] = [
            "A. Poor nutrition",
            "B. Varroa mites",
            "C. Lack of space",
            "D. Insufficient queen activity",
        ]
        question["explanation"] = (
            "Varroa mites transmit viruses associated with deformed wings."
        )
        question["prompt"] += """

A. Poor nutrition
B. Varroa mites
C. Lack of space
D. Insufficient queen activity
"""
        request = lambda_function._normalize_request(  # noqa: SLF001
            _request_payload(target_count=1, minimum_difficulty=3)
        )

        sanitized = lambda_function._sanitize_questions(  # noqa: SLF001
            [question],
            request,
        )

        self.assertEqual(len(sanitized), 1)
        self.assertEqual(
            sanitized[0]["prompt"],
            "During an inspection, many bees have deformed wings. What is the most likely cause?",
        )

    def test_accepts_valid_language_question_without_language_specific_shape_filter(
        self,
    ):
        question = _raw_question(
            "Which sentence correctly uses the subjunctive mood to express a wish about traveling?"
        )
        question["expectedAnswer"] = "Espero que ellos viajen mañana."
        question["choices"] = [
            "Espero que ellos viajen mañana.",
            "Espero que ellos viajan mañana.",
            "Espero que ellos viajaron mañana.",
            "Espero que ellos viajar mañana.",
        ]
        question["explanation"] = (
            "Espero que expresses a wish and therefore takes the present subjunctive viajen."
        )
        question["topic"] = "Subjunctive mood"
        client = FakeBedrockClient.returning_questions(question)

        response = lambda_function.handle_http_request(
            _event(_request_payload(target_count=1, minimum_difficulty=3)),
            bedrock_client=client,
        )

        self.assertEqual(response["statusCode"], 200)
        questions = json.loads(response["body"])["questions"]
        self.assertEqual(len(questions), 1)
        self.assertIn("subjunctive mood", questions[0]["prompt"])


if __name__ == "__main__":
    unittest.main()
