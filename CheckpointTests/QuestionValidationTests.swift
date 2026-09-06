import XCTest
@testable import Checkpoint

// MARK: - Question validation

final class QuestionValidationTests: XCTestCase {
    private struct IdentityFixtures: Decodable {
        struct Question: Decodable {
            var prompt: String
            var choices: [String]
            var expectedAnswer: String
            var explanation: String
        }
        var equivalent: [[String]]
        var distinct: [[String]]
        var questions: [Question]
        var subject_prompts: [String]
        var coaching_prompts: [String]
    }

    private func identityFixtures() throws -> IdentityFixtures {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("backend/bedrock-question-service/tests/fixtures/choice_identity_contract.json")
        return try JSONDecoder().decode(IdentityFixtures.self, from: Data(contentsOf: url))
    }

    func testSharedUnicodeContentIdentityContract() throws {
        let fixtures = try identityFixtures()
        for pair in fixtures.equivalent {
            XCTAssertEqual(MultipleChoiceAnswerNormalizer.key(for: pair[0]), MultipleChoiceAnswerNormalizer.key(for: pair[1]))
        }
        for pair in fixtures.distinct {
            XCTAssertNotEqual(MultipleChoiceAnswerNormalizer.key(for: pair[0]), MultipleChoiceAnswerNormalizer.key(for: pair[1]))
        }
    }

    func testSharedQuestionsKeepEveryChoiceAndGradeOnlyTheExactKey() throws {
        let goal = makeGoal()
        for item in try identityFixtures().questions {
            for version in [0, 1] {
                let question = makeQuestion(
                    goal: goal, index: 1, topic: "Subject content", prompt: item.prompt,
                    expectedAnswer: item.expectedAnswer, choices: item.choices,
                    explanation: item.explanation, verificationVersion: version, difficulty: 3
                )
                let accepted = try XCTUnwrap(QuestionBatchSanitizer.sanitize([question], for: makeRequest(goal: goal)).first, item.prompt)
                XCTAssertEqual(Set(accepted.choices), Set(item.choices), item.prompt)
                XCTAssertEqual(accepted.expectedAnswer, item.expectedAnswer, item.prompt)
                for choice in accepted.choices {
                    XCTAssertEqual(AnswerGrader.evaluate(answer: choice, question: accepted).result,
                                   choice == item.expectedAnswer ? .correct : .incorrect, item.prompt)
                }
            }
        }
    }

    func testVerifiedAnswerUsesTheSameBoundaryWhitespaceIdentityAsSanitization() throws {
        let goal = makeGoal()
        let question = makeQuestion(goal: goal, index: 1, expectedAnswer: " salt ",
                                    choices: [" salt ", "sugar", "tea", "water"])
        let accepted = try XCTUnwrap(QuestionBatchSanitizer.sanitize([question], for: makeRequest(goal: goal)).first)
        for choice in accepted.choices {
            XCTAssertEqual(AnswerGrader.evaluate(answer: choice, question: accepted).result,
                           choice == " salt " ? .correct : .incorrect)
        }
    }

    func testLegacyGraderCannotTreatAnUnofferedRawExpectedAnswerAsCorrect() {
        let goal = makeGoal()
        let question = makeQuestion(goal: goal, index: 1, expectedAnswer: "Missing answer",
                                    choices: ["first", "second", "third", "fourth"], verificationVersion: 0)
        XCTAssertEqual(AnswerGrader.evaluate(answer: "Missing answer", question: question).result, .incorrect)
    }

    func testCanonicalDuplicatesAreRejected() {
        let goal = makeGoal()
        for choices in [["café", "cafe\u{301}", "tea", "water"], ["salt", " salt ", "sugar", "water"]] {
            let question = makeQuestion(goal: goal, index: 1, expectedAnswer: choices[0], choices: choices)
            XCTAssertTrue(QuestionBatchSanitizer.sanitize([question], for: makeRequest(goal: goal)).isEmpty)
        }
    }

    func testChoiceSetIdentityCannotCollideOnLiteralSeparators() {
        let goal = makeGoal()
        let first = makeQuestion(goal: goal, index: 1, prompt: "Which is the first pipe expression?",
                                 expectedAnswer: "a|b", choices: ["a|b", "c", "d", "e"])
        let second = makeQuestion(goal: goal, index: 2, prompt: "Which is the second pipe expression?",
                                  expectedAnswer: "b|c", choices: ["a", "b|c", "d", "e"])
        XCTAssertEqual(QuestionBatchSanitizer.sanitize([first, second], for: makeRequest(goal: goal)).count, 2)
    }

    func testSharedStudyCoachingIntentContract() throws {
        let goal = makeGoal()
        let fixtures = try identityFixtures()
        for prompt in fixtures.subject_prompts {
            let question = makeQuestion(goal: goal, index: 1, prompt: prompt)
            XCTAssertEqual(QuestionBatchSanitizer.sanitize([question], for: makeRequest(goal: goal)).count, 1, prompt)
        }
        for prompt in fixtures.coaching_prompts {
            let question = makeQuestion(goal: goal, index: 1, prompt: prompt)
            XCTAssertTrue(QuestionBatchSanitizer.sanitize([question], for: makeRequest(goal: goal)).isEmpty, prompt)
        }
    }

    func testVerifiedQuestionKeepsExactNumericAnswerAndTeachingFeedback() throws {
        let goal = makeGoal()
        var question = makeQuestion(goal: goal, index: 2)
        question.choiceExplanations = [question.choices[1]: "This choice reverses the relationship."]
        var request = makeRequest(goal: goal)
        request.requiresVerifiedQuestions = true
        let accepted = try XCTUnwrap(QuestionBatchSanitizer.sanitize([question], for: request).first)
        XCTAssertEqual(accepted.expectedAnswer, "Correct answer 2")
        for choice in accepted.choices {
            XCTAssertEqual(AnswerGrader.evaluate(answer: choice, question: accepted).result,
                           choice == accepted.expectedAnswer ? .correct : .incorrect)
        }
        XCTAssertEqual(accepted.choiceExplanations, question.choiceExplanations)
        XCTAssertEqual(accepted.feedbackExplanation(for: question.choices[1]),
                       "This choice reverses the relationship.\n\nExplanation 2")
        var legacy = question
        legacy.verificationVersion = 0
        XCTAssertTrue(QuestionBatchSanitizer.sanitize([legacy], for: request).isEmpty)
    }

    func testVerificationAndChoiceFeedbackSurviveWireAndPersistenceWhileLegacyIsUnverified() throws {
        let goal = makeGoal()
        var question = makeQuestion(goal: goal, index: 1)
        question.choiceExplanations = [question.choices[1]: "This option omits a required condition."]
        let encoded = try JSONEncoder().encode(question)
        let payload = try JSONDecoder().decode(GeneratedQuestionPayload.self, from: encoded)
        let received = payload.makeQuestion(goalID: goal.id, sourcePrompt: "reviewed service")
        XCTAssertEqual(received.verificationVersion, 1)
        XCTAssertEqual(received.choiceExplanations, question.choiceExplanations)
        let restored = try JSONDecoder().decode(CheckpointQuestion.self, from: encoded)
        XCTAssertEqual(restored.choiceExplanations, question.choiceExplanations)
        var oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        oldJSON.removeValue(forKey: "verificationVersion")
        oldJSON.removeValue(forKey: "choiceExplanations")
        let legacy = try JSONDecoder().decode(CheckpointQuestion.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        XCTAssertEqual(legacy.verificationVersion, 0)
        XCTAssertTrue(legacy.choiceExplanations.isEmpty)
    }

    func testExactStemNormalizationDoesNotEraseLeadingMeaningfulPunctuation() {
        XCTAssertFalse(
            QuestionBatchSanitizer.hasSameQuestionStem(
                "?What does this operator mean?",
                "What does this operator mean?"
            )
        )
    }

    func testExactStemNormalizationPreservesSuperscriptAndSubscriptMeaning() {
        XCTAssertFalse(
            QuestionBatchSanitizer.hasSameQuestionStem(
                "What is x²?",
                "What is x2?"
            )
        )
        XCTAssertFalse(
            QuestionBatchSanitizer.hasSameQuestionStem(
                "What is x₁?",
                "What is x1?"
            )
        )
    }

    func testExactStemNormalizationIgnoresWhitespaceAroundMathOperators() {
        for mathOperator in [
            "<=", ">=", "!=", "==", "+", "-", "−", "×", "÷", "=", "<", ">",
            "≤", "≥", "≠", "±", "∓", "⋅", "·", "*", "/", "^", "%"
        ] {
            XCTAssertTrue(
                QuestionBatchSanitizer.hasSameQuestionStem(
                    "What is x \(mathOperator) 1?",
                    "What is x\(mathOperator)1?"
                ),
                "Expected operator-spacing parity for \(mathOperator)"
            )
        }
        XCTAssertFalse(
            QuestionBatchSanitizer.hasSameQuestionStem(
                "What is x + 1?",
                "What is x - 1?"
            )
        )
    }

    func testStemFingerprintTracksExactNormalizedIdentity() throws {
        let spaced = try XCTUnwrap(
            QuestionBatchSanitizer.questionStemFingerprint("What is x + 1?")
        )
        let compact = try XCTUnwrap(
            QuestionBatchSanitizer.questionStemFingerprint("WHAT is x+1!")
        )
        let superscript = try XCTUnwrap(
            QuestionBatchSanitizer.questionStemFingerprint("What is x²?")
        )
        let plainDigit = try XCTUnwrap(
            QuestionBatchSanitizer.questionStemFingerprint("What is x2?")
        )

        XCTAssertEqual(spaced, compact)
        XCTAssertEqual(spaced, "66a0e917835b1b99")
        XCTAssertNotEqual(superscript, plainDigit)
        XCTAssertTrue(spaced.range(of: #"^[0-9a-f]{16}$"#, options: .regularExpression) != nil)
    }

    func testSanitizerRejectsDuplicateReportedAndInvalidProviderQuestions() {
        let goal = makeGoal()
        let existingQuestion = makeQuestion(goal: goal, index: 1, prompt: "Already stored prompt")
        let reportedQuestion = QuestionQualityReport(
            questionID: UUID(),
            goalID: goal.id,
            prompt: "Reported prompt",
            reason: .irrelevant,
            note: ""
        )
        let request = makeRequest(
            goal: goal,
            existingQuestions: [existingQuestion],
            reportedQuestions: [reportedQuestion],
            targetCount: 2
        )

        let duplicateExisting = makeQuestion(goal: goal, index: 2, prompt: "Already stored prompt")
        let duplicateReported = makeQuestion(goal: goal, index: 3, prompt: "Reported prompt")
        let invalidQuestion = makeQuestion(
            goal: goal,
            index: 4,
            expectedAnswer: "",
            choices: ["A", "B", "C"]
        )
        let validQuestion = makeQuestion(
            goal: goal,
            index: 5,
            prompt: "Which answer proves this provider payload is usable?",
            difficulty: 99
        )

        let sanitized = QuestionBatchSanitizer.sanitize(
            [duplicateExisting, duplicateReported, invalidQuestion, validQuestion],
            for: request
        )

        XCTAssertEqual(sanitized.map(\.prompt), [validQuestion.prompt])
        XCTAssertEqual(sanitized.first?.difficulty, 5)
        XCTAssertEqual(sanitized.first?.format, .multipleChoice)
    }

    func testSanitizerRejectsQuestionsBelowMinimumDifficulty() {
        let goal = makeGoal()
        let lowQuestion = makeQuestion(goal: goal, index: 1, difficulty: 2)
        let highQuestion = makeQuestion(goal: goal, index: 2, difficulty: 4)
        let request = makeRequest(goal: goal, minimumDifficulty: 3)

        let sanitized = QuestionBatchSanitizer.sanitize([lowQuestion, highQuestion], for: request)

        XCTAssertEqual(sanitized.map(\.id), [highQuestion.id])
    }

    func testSanitizerResolvesExpectedAnswerLabelToVisibleChoice() throws {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which labeled answer should be treated as correct?",
            expectedAnswer: "B",
            choices: [
                "A. The incorrect distractor",
                "B. The correct labeled answer",
                "C. Another distractor",
                "D. Final distractor"
            ],
            verificationVersion: 0,
            difficulty: 2
        )

        let sanitizedQuestion = try XCTUnwrap(QuestionBatchSanitizer.sanitize([question], for: request).first)

        XCTAssertEqual(sanitizedQuestion.expectedAnswer, "B. The correct labeled answer")
        XCTAssertEqual(sanitizedQuestion.choices.count, 4)
        XCTAssertTrue(hasUniqueTestChoices(sanitizedQuestion.choices))
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "B. The correct labeled answer", question: sanitizedQuestion).result,
            .correct
        )
    }

    func testSanitizerRejectsAnswerLabelMissingFromVisibleChoices() {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which labeled answer should be rejected?",
            expectedAnswer: "B",
            choices: ["first", "second", "third", "fourth"],
            difficulty: 2
        )

        let sanitized = QuestionBatchSanitizer.sanitize([question], for: request)

        XCTAssertTrue(sanitized.isEmpty)
    }

    func testSanitizerRejectsExplanationSupportingDifferentChoice() {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            topic: "signed quantities",
            prompt: "A computation gives -1. What is the sign of the result?",
            expectedAnswer: "positive",
            choices: ["positive", "negative", "zero", "undefined"],
            explanation: "The computed result is -1, which is negative.",
            verificationVersion: 0,
            difficulty: 4
        )

        let sanitized = QuestionBatchSanitizer.sanitize([question], for: request)

        XCTAssertTrue(sanitized.isEmpty)
    }

    func testSanitizerRejectsPromptWithEmbeddedAnswerOptions() {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Choose the correct verb. Options: 1. llega 2. llegue 3. llego 4. llegar",
            expectedAnswer: "llegue",
            choices: ["llegue", "llega", "llego", "llegar"],
            difficulty: 2
        )

        let sanitized = QuestionBatchSanitizer.sanitize([question], for: request)

        XCTAssertTrue(sanitized.isEmpty)
    }

    func testSanitizerAllowsSimilarQuotedPromptsWhenStemsDiffer() {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let first = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Select the correct object pronoun for the sentence: 'Necesito encontrar el hotel antes de la noche.'"
        )
        let second = makeQuestion(
            goal: goal,
            index: 2,
            prompt: "Choose the correct object pronoun to replace 'el hotel' in the sentence: 'Necesito encontrar el hotel antes de la noche.'"
        )

        let sanitized = QuestionBatchSanitizer.sanitize([first, second], for: request)

        XCTAssertEqual(sanitized.map(\.id), [first.id, second.id])
    }

    func testSanitizerAllowsDifferentQuestionsAboutTheSameQuotedPassage() {
        let goal = makeGoal()
        let request = makeRequest(goal: goal, targetCount: 2)
        let meaningQuestion = makeQuestion(
            goal: goal,
            index: 1,
            topic: "reading comprehension",
            prompt: "In the passage 'The river rose overnight,' what changed?",
            expectedAnswer: "The river level increased.",
            choices: [
                "The river level increased.",
                "The river completely dried up.",
                "A bridge moved upstream.",
                "The weather became warmer."
            ],
            explanation: "The word rose describes an increase in the river level."
        )
        let timingQuestion = makeQuestion(
            goal: goal,
            index: 2,
            topic: "sequence and timing",
            prompt: "In the passage 'The river rose overnight,' when did the change happen?",
            expectedAnswer: "During the night.",
            choices: [
                "During the night.",
                "At noon the next day.",
                "Before sunset a week earlier.",
                "The passage gives no timing."
            ],
            explanation: "Overnight directly identifies when the river rose."
        )

        let sanitized = QuestionBatchSanitizer.sanitize(
            [meaningQuestion, timingQuestion],
            for: request
        )

        XCTAssertEqual(sanitized.map(\.id), [meaningQuestion.id, timingQuestion.id])
    }

    func testSanitizerRejectsDuplicateMultipleChoiceAnswers() {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which answer choice should be rejected for duplicate options?",
            expectedAnswer: "The same answer",
            choices: [
                "The same answer",
                "The same answer",
                "B. A different answer",
                "C. Another different answer"
            ],
            difficulty: 2
        )

        let sanitized = QuestionBatchSanitizer.sanitize([question], for: request)

        XCTAssertTrue(sanitized.isEmpty)
    }

    func testSanitizerKeepsShortPluralChoiceBoundaryDistinct() {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which option names one feline?",
            expectedAnswer: "A cat",
            choices: ["A cat", "cats", "dogs", "birds"],
            explanation: "A cat names one feline.",
            difficulty: 2
        )

        XCTAssertEqual(
            QuestionBatchSanitizer.sanitize([question], for: request).map(\.id),
            [question.id]
        )
    }

    func testSanitizerDoesNotTreatDomainDependentVerbsAsGlobalSynonyms() {
        let goal = Goal(
            title: "Learn precise English vocabulary",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "word meaning in context",
            preferredQuestionStyle: .multipleChoice
        )
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            topic: "word meaning in context",
            prompt: "Which verb best completes this sentence? The mediator helped the neighbors ___ their dispute.",
            expectedAnswer: "resolve",
            choices: [
                "resolve",
                "map",
                "translate",
                "convert"
            ],
            explanation: "Resolve means to settle or find a solution to a dispute.",
            difficulty: 2
        )

        let sanitized = QuestionBatchSanitizer.sanitize([question], for: request)

        XCTAssertEqual(sanitized.map(\.id), [question.id])
    }

    func testSanitizerRejectsSameTopicAndAnswerAsExistingQuestion() {
        let goal = makeGoal()
        let existingQuestion = makeQuestion(
            goal: goal,
            index: 1,
            topic: "Virtual Memory",
            prompt: "Operating Systems: What does the MMU do during address translation?",
            expectedAnswer: "It translates virtual memory addresses to physical memory addresses.",
            choices: [
                "It translates virtual memory addresses to physical memory addresses.",
                "It encrypts process memory before each context switch.",
                "It schedules interrupts for blocked I/O devices.",
                "It flushes all process pages on every cache miss."
            ],
            explanation: "The MMU translates virtual addresses into physical addresses.",
            difficulty: 3
        )
        let request = makeRequest(goal: goal, existingQuestions: [existingQuestion])
        let repeatedMechanism = makeQuestion(
            goal: goal,
            index: 2,
            topic: "Virtual Memory",
            prompt: "Operating Systems: Which MMU behavior is central to virtual memory?",
            expectedAnswer: "It translates virtual memory addresses to physical memory addresses.",
            choices: [
                "It translates virtual memory addresses to physical memory addresses.",
                "It chooses the next process to run on the CPU.",
                "It stores every interrupt handler in user space.",
                "It compresses disk blocks before loading pages."
            ],
            explanation: "The MMU translates virtual addresses to physical addresses.",
            difficulty: 3
        )
        let newAngle = makeQuestion(
            goal: goal,
            index: 3,
            topic: "Virtual Memory",
            prompt: "Operating Systems: Why might a process page fault even when the virtual address is valid?",
            expectedAnswer: "The referenced page is not currently resident in physical memory.",
            choices: [
                "The referenced page is not currently resident in physical memory.",
                "The process has no virtual address space.",
                "The CPU cannot execute code after any interrupt.",
                "The stack pointer must always equal the page-table base."
            ],
            explanation: "A valid virtual address can still fault if the page must be fetched or mapped into memory.",
            difficulty: 3
        )

        let sanitized = QuestionBatchSanitizer.sanitize([repeatedMechanism, newAngle], for: request)

        XCTAssertEqual(sanitized.map(\.id), [newAngle.id])
    }

    func testSanitizerRejectsQuestionsWithFewerThanFourUniqueAnswers() {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which answer choice should be rejected for too few unique options?",
            expectedAnswer: "The only supported answer",
            choices: [
                "The only supported answer",
                "A plausible distractor",
                "A plausible distractor",
                "A second distractor"
            ],
            difficulty: 2
        )

        let sanitized = QuestionBatchSanitizer.sanitize([question], for: request)

        XCTAssertTrue(sanitized.isEmpty)
    }

    func testSanitizerUsesExplanationWhenItContradictsExpectedAnswer() throws {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which answer matches the explanation?",
            expectedAnswer: "The tempting but wrong answer",
            choices: [
                "The tempting but wrong answer",
                "The answer supported by the argument",
                "An unrelated answer",
                "A too-broad answer"
            ],
            explanation: "The answer supported by the argument is correct because it follows from the stated evidence.",
            verificationVersion: 0,
            difficulty: 2
        )

        let sanitizedQuestion = try XCTUnwrap(QuestionBatchSanitizer.sanitize([question], for: request).first)

        XCTAssertEqual(sanitizedQuestion.expectedAnswer, "The answer supported by the argument")
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "The answer supported by the argument", question: sanitizedQuestion).result,
            .correct
        )
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "The tempting but wrong answer", question: sanitizedQuestion).result,
            .incorrect
        )
    }

    func testSanitizerCollapsesWhitespaceWhenReadingExplanationAnswerCue() throws {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which answer matches the explanation?",
            expectedAnswer: "The tempting but wrong answer",
            choices: [
                "The tempting but wrong answer",
                "The answer supported by the argument",
                "An unrelated answer",
                "A too-broad answer"
            ],
            explanation: "The answer supported by the argument is the best\nanswer because it follows from the evidence.",
            verificationVersion: 0,
            difficulty: 2
        )

        let sanitizedQuestion = try XCTUnwrap(QuestionBatchSanitizer.sanitize([question], for: request).first)

        XCTAssertEqual(sanitizedQuestion.expectedAnswer, "The answer supported by the argument")
    }

    func testMultipleChoiceGraderUsesExplanationForPersistedAnswerMismatch() {
        let goal = makeGoal()
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which persisted answer should the grader trust?",
            expectedAnswer: "The tempting but wrong answer",
            choices: [
                "The tempting but wrong answer",
                "The answer supported by the argument",
                "An unrelated answer",
                "A too-broad answer"
            ],
            explanation: "The answer supported by the argument is correct because it follows from the stated evidence.",
            verificationVersion: 0,
            difficulty: 2
        )

        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "The answer supported by the argument", question: question).result,
            .correct
        )
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "The tempting but wrong answer", question: question).result,
            .incorrect
        )
        XCTAssertEqual(
            AnswerGrader.correctAnswerText(for: question, after: .incorrect),
            "The answer supported by the argument"
        )
    }

    func testAnswerReviewResolvesCanonicalVisibleChoiceForEveryNonCorrectResult() {
        let goal = makeGoal()
        let choices = [
            "A. Remove the first element",
            "B. Remove the most recently added element",
            "C. Remove a random element",
            "D. Remove every element"
        ]
        let question = makeQuestion(
            goal: goal,
            index: 1,
            expectedAnswer: "B",
            choices: choices,
            verificationVersion: 0
        )

        for result in [AnswerResult.partial, .incorrect, .unclear] {
            XCTAssertEqual(
                AnswerGrader.correctAnswerText(for: question, after: result),
                choices[1]
            )
        }
        XCTAssertNil(AnswerGrader.correctAnswerText(for: question, after: .correct))
    }

    func testAnswerReviewFallsBackForMalformedMultipleChoiceQuestions() {
        let goal = makeGoal()
        let malformedQuestions = [
            makeQuestion(
                goal: goal,
                index: 1,
                expectedAnswer: "Stored answer",
                choices: []
            ),
            makeQuestion(
                goal: goal,
                index: 2,
                expectedAnswer: "Stored answer",
                choices: ["One", "Two", "Three", "Four"]
            ),
            makeQuestion(
                goal: goal,
                index: 3,
                expectedAnswer: "D",
                choices: ["One", "Two", "Three"]
            ),
            makeQuestion(
                goal: goal,
                index: 4,
                expectedAnswer: "A",
                choices: ["Repeated answer", "Repeated answer", "Three", "Four"]
            )
        ]
        let expectedFallbacks = ["Stored answer", "Stored answer", "D", "A"]

        for (question, expectedFallback) in zip(malformedQuestions, expectedFallbacks) {
            XCTAssertEqual(
                AnswerGrader.correctAnswerText(for: question, after: .incorrect),
                expectedFallback
            )
        }
    }

    func testAnswerReviewPreservesTypedExpectedAnswerExactly() {
        let goal = makeGoal()
        let expectedAnswer = "  [2, 4, 6]\nPreserve this formatting.  "
        var question = makeQuestion(
            goal: goal,
            index: 1,
            expectedAnswer: expectedAnswer,
            choices: []
        )

        for format in [QuestionFormat.shortAnswer, .codeTrace, .reflection] {
            question.format = format
            XCTAssertEqual(
                AnswerGrader.correctAnswerText(for: question, after: .incorrect),
                expectedAnswer
            )
        }

        question.expectedAnswer = "  \n "
        XCTAssertNil(AnswerGrader.correctAnswerText(for: question, after: .incorrect))
    }

    func testMultipleChoiceGraderKeepsStrictAnswerCueWhitespaceMatching() {
        let goal = makeGoal()
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which persisted answer should the grader trust?",
            expectedAnswer: "The persisted expected answer",
            choices: [
                "The persisted expected answer",
                "The answer supported by the argument",
                "An unrelated answer",
                "A too-broad answer"
            ],
            explanation: "The answer supported by the argument is the best\nanswer because it follows from the evidence.",
            verificationVersion: 0,
            difficulty: 2
        )

        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "The persisted expected answer", question: question).result,
            .correct
        )
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "The answer supported by the argument", question: question).result,
            .incorrect
        )
    }

    func testMultipleChoiceGraderDoesNotTreatLeadingArticleAsChoiceLabel() {
        let goal = makeGoal()
        let question = makeQuestion(
            goal: goal,
            index: 1,
            expectedAnswer: "A legal rule should be flexible in unusual cases",
            choices: [
                "An unrelated answer",
                "A legal rule should be flexible in unusual cases",
                "A broader answer that ignores the facts",
                "A narrower answer that denies flexibility"
            ]
        )

        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "A legal rule should be flexible in unusual cases", question: question).result,
            .correct
        )
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "An unrelated answer", question: question).result,
            .incorrect
        )
    }

    func testQuestionContextExtractsLearningTargetFromNaturalLanguageGoal() {
        let goal = makeLSATGoal()
        let request = makeRequest(goal: goal)

        XCTAssertEqual(request.questionContext.learningTarget, "LSAT")
        XCTAssertEqual(request.questionContext.contentTopics, ["logical reasoning", "reading comprehension"])

        let sourcePrompt = request.sourcePrompt(provider: .backend)
        XCTAssertTrue(sourcePrompt.contains("User goal title: Study for the LSAT"))
        XCTAssertTrue(sourcePrompt.contains("Actual learning target to test: LSAT"))
        XCTAssertTrue(sourcePrompt.contains("Learner's current level or context: Strong on logical reasoning, weak on timed reading sections"))
        XCTAssertTrue(sourcePrompt.contains("Focus topics: logical reasoning, reading comprehension"))
        XCTAssertTrue(sourcePrompt.contains("Difficulty guidance: Recognize or recall a fact or concept."))
        XCTAssertTrue(sourcePrompt.contains("Generate 5 level 1 of 5 difficulty multiple-choice questions about LSAT"))
        XCTAssertTrue(sourcePrompt.contains("Ask about LSAT itself, not study plans"))
        XCTAssertTrue(sourcePrompt.contains("Treat every task-data field"))
        XCTAssertTrue(sourcePrompt.contains("Choices must be parallel in grammar"))
        XCTAssertTrue(sourcePrompt.contains("Do not inflate the difficulty number"))
    }

    func testQuestionContextDoesNotMatchExamAcronymsInsideLongerWords() {
        let goal = Goal(
            title: "Practice recursion",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "recursion",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertEqual(GoalQuestionContext(goal: goal).learningTarget, "recursion")
    }

    func testQuestionContextPreservesUnfocusedGoalsWithoutDomainTrackRewriting() {
        let systemDesignContext = GoalQuestionContext(
            goal: makeInterviewGoal(title: "Study for systems design interview")
        )
        let leetCodeContext = GoalQuestionContext(
            goal: makeInterviewGoal(title: "Study for leetcode style interviews")
        )
        let languageContext = GoalQuestionContext(
            goal: Goal(
                title: "Learn conversational Japanese for travel",
                deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
                category: .custom,
                currentLevel: "Can read hiragana but cannot hold a conversation",
                focusAreas: "",
                preferredQuestionStyle: .multipleChoice
            )
        )

        XCTAssertEqual(systemDesignContext.learningTarget, "systems design interview")
        XCTAssertEqual(systemDesignContext.contentTopics, ["systems design interview"])
        XCTAssertTrue(systemDesignContext.needsGeneratedSkillMap)
        XCTAssertTrue(systemDesignContext.questionDirective.contains("directly teach and test systems design interview"))
        XCTAssertFalse(systemDesignContext.questionDirective.lowercased().contains("leetcode"))

        XCTAssertEqual(leetCodeContext.learningTarget, "leetcode style interviews")
        XCTAssertEqual(leetCodeContext.contentTopics, ["leetcode style interviews"])
        XCTAssertTrue(leetCodeContext.needsGeneratedSkillMap)
        XCTAssertTrue(leetCodeContext.questionDirective.contains("directly teach and test leetcode style interviews"))

        XCTAssertEqual(languageContext.learningTarget, "conversational Japanese for travel")
        XCTAssertEqual(languageContext.contentTopics, ["conversational Japanese for travel"])
        XCTAssertTrue(languageContext.needsGeneratedSkillMap)
        XCTAssertTrue(languageContext.questionDirective.contains("Can read hiragana but cannot hold a conversation"))
    }

    func testGoalSetupGuidanceUsesSameGenericInferenceForAnyUnfocusedGoal() {
        let broadGuidance = GoalSetupGuidance(title: "Study for interviews", focusAreas: "")
        let systemDesignGuidance = GoalSetupGuidance(
            title: "Study for systems design interview",
            focusAreas: ""
        )
        let leetCodeGuidance = GoalSetupGuidance(
            title: "Study for leetcode style interviews",
            focusAreas: ""
        )

        let mcatGuidance = GoalSetupGuidance(title: "Prepare for the MCAT", focusAreas: "")

        XCTAssertEqual(broadGuidance.interpretation, "questions about interviews")
        XCTAssertEqual(systemDesignGuidance.interpretation, "questions about systems design interview")
        XCTAssertEqual(leetCodeGuidance.interpretation, "questions about leetcode style interviews")
        XCTAssertEqual(mcatGuidance.interpretation, "questions about MCAT")
    }

    func testSanitizerRejectsGenericMetaFillerForAnyLearningGoal() {
        let goal = Goal(
            title: "Learn cellular respiration",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .custom,
            currentLevel: "Introductory biology",
            focusAreas: "ATP production",
            preferredQuestionStyle: .multipleChoice
        )
        let request = makeRequest(goal: goal, minimumDifficulty: 4)
        let genericMetaQuestion = makeQuestion(
            goal: goal,
            index: 1,
            topic: "ATP production",
            prompt: "Level 4 advanced constraints: Which inference is best supported by the real-world transfer evidence in ATP production? Pay close attention to qualifiers and edge cases.",
            expectedAnswer: "The answer that follows from the stated facts and respects the topic's constraints.",
            choices: [
                "The answer that follows from the stated facts and respects the topic's constraints.",
                "The answer that changes the topic to study planning.",
                "The answer that ignores qualifiers in the prompt.",
                "The answer that sounds familiar but adds unsupported assumptions."
            ],
            explanation: "The correct choice follows the stated facts and respects the topic's constraints.",
            difficulty: 4
        )

        let sanitized = QuestionBatchSanitizer.sanitize([genericMetaQuestion], for: request)

        XCTAssertTrue(sanitized.isEmpty)
    }

    func testSanitizerRejectsStudyStrategyQuestionsForAcademicTargets() {
        let goal = makeLSATGoal()
        let request = makeRequest(goal: goal)
        let studyStrategyQuestion = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which 10-minute study rep would create the clearest progress on LSAT logical reasoning?",
            difficulty: 3
        )
        let contentQuestion = makeQuestion(
            goal: goal,
            index: 2,
            prompt: "LSAT Logical Reasoning: Which answer identifies the flaw in the argument?",
            difficulty: 3
        )

        let sanitized = QuestionBatchSanitizer.sanitize(
            [studyStrategyQuestion, contentQuestion],
            for: request
        )

        XCTAssertEqual(sanitized.map(\.prompt), [contentQuestion.prompt])
    }

    func testSanitizerUsesTheSameStructuralQualityRulesAcrossEducationDomains() {
        let cases: [(Goal, CheckpointQuestion)] = [
            {
                let goal = Goal(
                    title: "Prepare for the MCAT",
                    deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
                    category: .custom,
                    currentLevel: "Comfortable with biology fundamentals",
                    focusAreas: "cellular respiration",
                    preferredQuestionStyle: .multipleChoice
                )
                return (
                    goal,
                    makeQuestion(
                        goal: goal,
                        index: 1,
                        topic: "cellular respiration",
                        prompt: "Which mitochondrial process directly uses a proton gradient to produce ATP?",
                        expectedAnswer: "Chemiosmosis through ATP synthase",
                        choices: [
                            "Chemiosmosis through ATP synthase",
                            "DNA replication in the matrix",
                            "Glycolysis in the cytosol",
                            "Lactate fermentation in muscle"
                        ],
                        explanation: "ATP synthase uses the proton gradient during chemiosmosis.",
                        difficulty: 2
                    )
                )
            }(),
            {
                let goal = Goal(
                    title: "Learn conversational French",
                    deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
                    category: .custom,
                    currentLevel: "Beginner",
                    focusAreas: "future tense",
                    preferredQuestionStyle: .multipleChoice
                )
                return (
                    goal,
                    makeQuestion(
                        goal: goal,
                        index: 2,
                        topic: "future tense",
                        prompt: "Which sentence correctly says that I will visit Paris tomorrow?",
                        expectedAnswer: "Je visiterai Paris demain.",
                        choices: [
                            "Je visiterai Paris demain.",
                            "Je visitais Paris demain.",
                            "Je visite Paris hier.",
                            "J'ai visiter Paris demain."
                        ],
                        explanation: "Visiterai is the first-person singular simple future form of visiter.",
                        difficulty: 2
                    )
                )
            }(),
            {
                let goal = Goal(
                    title: "Study Renaissance art history",
                    deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
                    category: .custom,
                    currentLevel: "Introductory survey course",
                    focusAreas: "perspective",
                    preferredQuestionStyle: .multipleChoice
                )
                return (
                    goal,
                    makeQuestion(
                        goal: goal,
                        index: 3,
                        topic: "perspective",
                        prompt: "Which technique most directly creates the illusion of spatial depth on a flat surface?",
                        expectedAnswer: "Linear perspective with a vanishing point",
                        choices: [
                            "Linear perspective with a vanishing point",
                            "Uniform sizing of every figure",
                            "Elimination of all horizon lines",
                            "Identical brightness across the canvas"
                        ],
                        explanation: "Linear perspective organizes receding forms around a vanishing point.",
                        difficulty: 2
                    )
                )
            }()
        ]

        for (goal, question) in cases {
            let sanitized = QuestionBatchSanitizer.sanitize([question], for: makeRequest(goal: goal))
            XCTAssertEqual(sanitized.map(\.id), [question.id], "Rejected valid question for \(goal.title)")
        }
    }

}

final class QuestionContentPreservationTests: XCTestCase {
    private struct Fixtures: Decodable {
        struct Case: Decodable { var raw: String; var expected: String }
        struct Question: Decodable {
            var prompt: String
            var choices: [String]
            var expectedAnswer: String
            var explanation: String
            var topic: String
            var difficulty: Int
        }
        var question: Question
        var source: String
        var cases: [Case]
    }

    private func fixtures() throws -> Fixtures {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("backend/bedrock-question-service/tests/fixtures/subject_content_contract.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    func testSharedLayoutControlAndUnicodeContract() throws {
        for item in try fixtures().cases {
            // Compare bytes so canonical Unicode equivalence cannot conceal a
            // change to code strings whose code-point count is being tested.
            XCTAssertEqual(Data(QuestionText.subjectContent(item.raw).utf8), Data(item.expected.utf8))
            let document = GoalSourceDocument(name: "sample.txt", text: item.raw)
            XCTAssertEqual(Data(document.text.utf8), Data(item.expected.utf8))
        }
    }

    func testImportedCodeSurvivesPersistenceAndBackendRequest() throws {
        let source = try fixtures().source
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("sample.py")
        try source.write(to: path, atomically: true, encoding: .utf8)
        let imported = try GoalSourceDocumentImporter.loadDocument(from: path)
        XCTAssertEqual(imported.text, source)
        var goal = makeGoal()
        goal.sourceDocuments = [imported]
        let restored = try JSONDecoder().decode(Goal.self, from: JSONEncoder().encode(goal))
        let request = makeRequest(goal: restored)
        let data = try JSONEncoder().encode(BackendQuestionRequest(request: request))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sources = try XCTUnwrap(payload["sourceDocuments"] as? [[String: Any]])
        XCTAssertEqual(sources[0]["text"] as? String, source)
    }

    func testGeneratedCodeAndHistoryKeepTheirLayout() throws {
        let item = try fixtures().question
        let goal = makeGoal()
        let question = makeQuestion(goal: goal, index: 1, topic: item.topic, prompt: item.prompt,
                                    expectedAnswer: item.expectedAnswer, choices: item.choices,
                                    explanation: item.explanation, difficulty: item.difficulty)
        let decoded = try JSONDecoder().decode(GeneratedQuestionPayload.self, from: JSONEncoder().encode(question))
        let received = decoded.makeQuestion(goalID: goal.id, sourcePrompt: "service")
        let sanitized = try XCTUnwrap(QuestionBatchSanitizer.sanitize([received], for: makeRequest(goal: goal)).first)
        XCTAssertEqual(sanitized.prompt, item.prompt)
        for choice in sanitized.choices {
            XCTAssertEqual(AnswerGrader.evaluate(answer: choice, question: sanitized).result,
                           choice == item.expectedAnswer ? .correct : .incorrect)
        }
        let request = makeRequest(goal: goal, existingQuestions: [sanitized])
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(BackendQuestionRequest(request: request))) as? [String: Any])
        XCTAssertEqual(payload["existingPrompts"] as? [String], [item.prompt])
        let history = try XCTUnwrap(payload["existingQuestionCoverage"] as? [[String: Any]])
        XCTAssertEqual(history[0]["prompt"] as? String, item.prompt)
    }

    func testChoiceEchoRemovalPreservesTheStemAndLiteralDifferences() throws {
        let item = try fixtures().question
        for labeled in [false, true] {
            let echo = item.choices.enumerated().map { index, choice in
                (labeled ? ["A", "B", "C", "D"][index] + ". " : "") + choice
            }.joined(separator: "\n")
            XCTAssertEqual(QuestionBatchSanitizer.promptWithoutTrailingChoiceEcho(item.prompt + "\n\n" + echo, choices: item.choices), item.prompt)
        }
        let choices = ["\"a  b\"", "\"one\"", "\"two\"", "\"three\""]
        let nonEcho = "Preserve the exact quoted lines below:\n\"a b\"\n\"one\"\n\"two\"\n\"three\""
        XCTAssertEqual(QuestionBatchSanitizer.promptWithoutTrailingChoiceEcho(nonEcho, choices: choices), nonEcho)
    }

    func testOverlongStemIsRejectedInsteadOfCuttingSubjectContent() {
        let goal = makeGoal()
        let question = makeQuestion(goal: goal, index: 1, prompt: String(repeating: "print(1)\n", count: 50))
        XCTAssertTrue(QuestionBatchSanitizer.sanitize([question], for: makeRequest(goal: goal)).isEmpty)
    }

    func testSourceDeduplicationPreservesDifferentCaseAndQuotedSpacing() {
        let preface = "These examples distinguish literal case and spacing.\n"
        let sources = ["print(True)", "print(true)", "print(\"a b\")", "print(\"a  b\")", "print(True)"].map {
            GoalSourceDocument(name: "Example.py", text: preface + $0)
        }
        XCTAssertEqual(GoalSourceDocument.normalizedDocuments(sources).count, 4)
    }
}
