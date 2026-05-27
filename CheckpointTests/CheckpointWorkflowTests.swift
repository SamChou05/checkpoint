import XCTest
@testable import Checkpoint

final class CheckpointWorkflowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "CheckpointTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        resetSharedAppGroupState()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        resetSharedAppGroupState()
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    @MainActor
    func testLocalTemplatesCreateUsableNoCostQuestionBank() async {
        let store = CheckpointStore(defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate on arrays, weak at recursion",
            focusAreas: "arrays, recursion, hash maps",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertEqual(store.lastQuestionProvider, .localTemplates)
        XCTAssertGreaterThanOrEqual(store.questions.count, 5)
        XCTAssertTrue(store.backendEndpoint.isEmpty)
        XCTAssertTrue(store.questions.allSatisfy { question in
            question.format == .multipleChoice
                && question.choices.count >= 2
                && question.choices.contains(question.expectedAnswer)
                && !question.explanation.isEmpty
                && !question.topic.isEmpty
        })
    }

    @MainActor
    func testCheckpointSessionUsesFiveDistinctQuestionsByDefault() throws {
        let store = makeSeededStore(questionCount: 7)

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(session.unlockThreshold, 4)
        XCTAssertEqual(Set(session.questions.map(\.id)).count, 5)
    }

    @MainActor
    func testCheckpointSessionPrioritizesMissedAndDueQuestionsBeforeNewQuestions() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.updateQuestionsPerSession(3)

        let missed = makeQuestion(
            goal: goal,
            index: 1,
            topic: "recursion",
            status: .incorrect,
            nextReviewAt: Date().addingTimeInterval(-60)
        )
        let due = makeQuestion(
            goal: goal,
            index: 2,
            topic: "arrays",
            status: .correct,
            nextReviewAt: Date().addingTimeInterval(-30)
        )
        let new = makeQuestion(goal: goal, index: 3, topic: "hash maps")
        store.questions = [new, due, missed]

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.map(\.id), [missed.id, due.id, new.id])
    }

    @MainActor
    func testCheckpointSessionRespectsMinimumQuestionDifficultyWhenPossible() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.updateQuestionsPerSession(2)
        store.updateMinimumQuestionDifficulty(3)

        let lowDue = makeQuestion(
            goal: goal,
            index: 1,
            status: .incorrect,
            nextReviewAt: Date().addingTimeInterval(-60),
            difficulty: 1
        )
        let highNew = makeQuestion(goal: goal, index: 2, difficulty: 3)
        let higherNew = makeQuestion(goal: goal, index: 3, topic: "recursion", difficulty: 4)
        store.questions = [lowDue, highNew, higherNew]

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 2)
        XCTAssertTrue(session.questions.allSatisfy { $0.difficulty >= 3 })
    }

    @MainActor
    func testUnlockAllowsOneMissInDefaultFiveQuestionSession() throws {
        let store = makeSeededStore(questionCount: 5)
        let session = try XCTUnwrap(store.nextCheckpointSession())
        var correctAnswerCount = 0

        for (index, question) in session.questions.enumerated() {
            let isFinalQuestion = index == session.questions.indices.last
            let result: AnswerResult = isFinalQuestion ? .incorrect : .correct
            if result == .correct {
                correctAnswerCount += 1
            }
            let shouldUnlock = isFinalQuestion && session.hasMetUnlockThreshold(correctAnswerCount: correctAnswerCount)
            let unlockMinutes = store.submitAnswer(
                question: question,
                answer: result == .correct ? question.expectedAnswer : "Wrong answer",
                result: result,
                grantsUnlock: false,
                unlockMinutesOverride: shouldUnlock ? store.unlockPolicy.unlockMinutes : nil
            )

            if isFinalQuestion {
                XCTAssertTrue(shouldUnlock)
                XCTAssertEqual(unlockMinutes, store.unlockPolicy.unlockMinutes)
                XCTAssertEqual(store.activeUnlockMinutesRemaining, store.unlockPolicy.unlockMinutes)
                XCTAssertNotNil(store.unlockSession)
            } else {
                XCTAssertEqual(unlockMinutes, 0)
                XCTAssertNil(store.unlockSession)
            }
        }

        XCTAssertEqual(store.attempts.count, 5)
        XCTAssertEqual(store.attempts.filter { $0.unlockMinutes > 0 }.count, 1)
    }

    @MainActor
    func testCheckpointSessionKnowsWhenThresholdIsImpossible() throws {
        let store = makeSeededStore(questionCount: 5)
        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertTrue(session.canStillMeetUnlockThreshold(correctAnswerCount: 2, answeredQuestionCount: 3))
        XCTAssertFalse(session.canStillMeetUnlockThreshold(correctAnswerCount: 1, answeredQuestionCount: 3))
    }

    @MainActor
    func testIncorrectAnswerKeepsLockedAndSchedulesReview() throws {
        let store = makeSeededStore(questionCount: 5)
        let question = try XCTUnwrap(store.questions.first)

        let unlockMinutes = store.submitAnswer(
            question: question,
            answer: "Wrong answer",
            result: .incorrect,
            grantsUnlock: true
        )

        let updatedQuestion = try XCTUnwrap(store.questions.first { $0.id == question.id })
        let updatedCompetency = try XCTUnwrap(store.competencies.first { $0.topic == question.topic })

        XCTAssertEqual(unlockMinutes, 0)
        XCTAssertNil(store.unlockSession)
        XCTAssertEqual(updatedQuestion.status, .incorrect)
        XCTAssertGreaterThan(updatedQuestion.nextReviewAt ?? .distantPast, Date())
        XCTAssertEqual(updatedCompetency.incorrect, 1)
    }

    @MainActor
    func testFailedSessionMakesMissedQuestionsDueForNextAttempt() throws {
        let store = makeSeededStore(questionCount: 6)
        let missedQuestions = Array(store.questions.prefix(2))
        let missedQuestionIDs = Set(missedQuestions.map(\.id))

        for question in missedQuestions {
            store.submitAnswer(
                question: question,
                answer: "Wrong answer",
                result: .incorrect,
                grantsUnlock: false
            )
        }

        XCTAssertTrue(missedQuestions.allSatisfy { question in
            let updatedQuestion = store.questions.first { $0.id == question.id }
            return (updatedQuestion?.nextReviewAt ?? .distantPast) > Date()
        })

        store.makeMissedQuestionsDueNow(missedQuestionIDs)

        let nextSession = try XCTUnwrap(store.nextCheckpointSession())
        XCTAssertEqual(Set(nextSession.questions.prefix(2).map(\.id)), missedQuestionIDs)
        XCTAssertTrue(missedQuestionIDs.allSatisfy { questionID in
            let updatedQuestion = store.questions.first { $0.id == questionID }
            return (updatedQuestion?.nextReviewAt ?? .distantFuture) <= Date()
        })
    }

    @MainActor
    func testPendingShieldAttemptCreatesOneCheckpointSessionThenClears() throws {
        let store = makeSeededStore(questionCount: 6)

        SharedAppGroup.markPendingShieldAttempt()

        let session = try XCTUnwrap(store.takePendingShieldSession())
        XCTAssertEqual(session.questions.count, 5)
        XCTAssertNil(store.takePendingShieldSession())
    }

    @MainActor
    private func makeSeededStore(questionCount: Int) -> CheckpointStore {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.questions = (1...questionCount).map { makeQuestion(goal: goal, index: $0) }
        store.competencies = [
            .initial(topic: "arrays", estimatedLevel: 1.2),
            .initial(topic: "recursion", estimatedLevel: 2.0),
            .initial(topic: "hash maps", estimatedLevel: 1.6)
        ]
        return store
    }
}

final class AIProviderPolicyTests: XCTestCase {
    func testAutomaticProviderPrefersNoCostLocalBeforeConfiguredBackend() async {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            localEngine: StaticQuestionEngine(
                provider: .localTemplates,
                questions: [makeQuestion(goal: goal, index: 1, sourcePrompt: "local")]
            ),
            backendEngine: StaticQuestionEngine(
                provider: .backend,
                questions: [makeQuestion(goal: goal, index: 2, sourcePrompt: "backend")]
            ),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .automatic
        )

        XCTAssertEqual(batch.provider, .localTemplates)
        XCTAssertEqual(batch.questions.first?.sourcePrompt, "local")
    }

    func testExplicitBackendPreferenceCanUseBackendWhenConfigured() async {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            localEngine: StaticQuestionEngine(
                provider: .localTemplates,
                questions: [makeQuestion(goal: goal, index: 1, sourcePrompt: "local")]
            ),
            backendEngine: StaticQuestionEngine(
                provider: .backend,
                questions: [makeQuestion(goal: goal, index: 2, sourcePrompt: "backend")]
            ),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .backend
        )

        XCTAssertEqual(batch.provider, .backend)
        XCTAssertEqual(batch.questions.first?.sourcePrompt, "backend")
    }

    func testBackendPreferenceWithoutEndpointFallsBackToLocalTemplates() async {
        let goal = makeGoal()
        let batch = await HybridQuestionEngine().generateQuestionBatch(
            for: makeRequest(goal: goal, targetCount: 5),
            preference: .backend
        )

        XCTAssertEqual(batch.provider, .localTemplates)
        XCTAssertTrue(batch.usedFallback)
        XCTAssertGreaterThanOrEqual(batch.questions.count, 5)
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

    func testLocalTemplatesRespectMinimumDifficulty() async throws {
        let goal = makeGoal()
        let request = makeRequest(goal: goal, minimumDifficulty: 4)

        let questions = try await LocalDraftQuestionEngine().generateQuestions(for: request)

        XCTAssertFalse(questions.isEmpty)
        XCTAssertTrue(questions.allSatisfy { $0.difficulty >= 4 })
    }
}

final class UnlockPolicyTests: XCTestCase {
    func testCorrectAnswerUnlockOptionsAreLongEnoughToMatter() {
        XCTAssertEqual(UnlockPolicy.default.unlockMinutes, 30)
        XCTAssertEqual(UnlockPolicy.correctAnswerUnlockMinuteOptions, [15, 30, 45, 60])
        XCTAssertTrue(UnlockPolicy.correctAnswerUnlockMinuteOptions.allSatisfy { $0 >= 15 })
        XCTAssertTrue(UnlockPolicy.correctAnswerUnlockMinuteOptions.contains(30))
    }

    func testLegacyTinyUnlockDurationsNormalizeToCurrentOptions() throws {
        let data = Data(
            """
            {
              "unlockMinutes": 3,
              "partialUnlockMinutes": 2,
              "emergencyUnlockMinutes": 3,
              "unlockOnPartial": true,
              "questionsPerSession": 5,
              "requiredCorrectAnswers": 4
            }
            """.utf8
        )

        let policy = try JSONDecoder().decode(UnlockPolicy.self, from: data)

        XCTAssertEqual(policy.unlockMinutes, 15)
        XCTAssertEqual(policy.partialUnlockMinutes, 15)
        XCTAssertEqual(policy.emergencyUnlockMinutes, 15)
    }

    @MainActor
    func testEmergencyPassReturnsUnlockDurationAndCreatesSession() {
        let suiteName = "UnlockPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            resetSharedAppGroupState()
        }
        resetSharedAppGroupState()
        let store = CheckpointStore(defaults: defaults)

        let unlockMinutes = store.useEmergencyPass()

        XCTAssertEqual(unlockMinutes, UnlockPolicy.default.emergencyUnlockMinutes)
        XCTAssertEqual(store.emergencyPassesRemaining, 0)
        XCTAssertEqual(store.activeUnlockMinutesRemaining, UnlockPolicy.default.emergencyUnlockMinutes)
        XCTAssertNotNil(store.unlockSession)
    }
}

private enum TestQuestionGenerationError: Error {
    case unavailable
}

private struct StaticQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind
    let questions: [CheckpointQuestion]

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        questions
    }
}

private struct ThrowingQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        throw TestQuestionGenerationError.unavailable
    }
}

private func makeGoal() -> Goal {
    Goal(
        title: "Pass technical interviews",
        deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
        category: .codingInterview,
        currentLevel: "Intermediate, but shaky on recursion",
        focusAreas: "arrays, recursion, hash maps",
        preferredQuestionStyle: .multipleChoice
    )
}

private func makeQuestion(
    goal: Goal,
    index: Int,
    topic: String = "arrays",
    prompt: String? = nil,
    expectedAnswer: String? = nil,
    choices: [String]? = nil,
    status: QuestionStatus = .new,
    nextReviewAt: Date? = nil,
    difficulty: Int = 2,
    sourcePrompt: String = "test"
) -> CheckpointQuestion {
    let correctAnswer = expectedAnswer ?? "Correct answer \(index)"
    return CheckpointQuestion(
        goalID: goal.id,
        prompt: prompt ?? "Question \(index): Which option best supports the goal?",
        expectedAnswer: correctAnswer,
        choices: choices ?? [
            correctAnswer,
            "Distractor \(index)A",
            "Distractor \(index)B",
            "Distractor \(index)C"
        ],
        explanation: "Explanation \(index)",
        topic: topic,
        difficulty: difficulty,
        format: .multipleChoice,
        status: status,
        nextReviewAt: nextReviewAt,
        sourcePrompt: sourcePrompt
    )
}

private func makeRequest(
    goal: Goal,
    existingQuestions: [CheckpointQuestion] = [],
    reportedQuestions: [QuestionQualityReport] = [],
    targetCount: Int = 5,
    minimumDifficulty: Int = 1,
    backendEndpoint: URL? = nil
) -> QuestionGenerationRequest {
    QuestionGenerationRequest(
        goal: goal,
        existingQuestions: existingQuestions,
        competencies: [],
        reportedQuestions: reportedQuestions,
        targetCount: targetCount,
        minimumDifficulty: minimumDifficulty,
        backendEndpoint: backendEndpoint
    )
}

private func resetSharedAppGroupState() {
    let defaults = SharedAppGroup.defaults
    [
        SharedAppGroup.pendingShieldAttemptDateKey,
        SharedAppGroup.shieldGoalTitleKey,
        SharedAppGroup.shieldPromptPreviewKey,
        SharedAppGroup.shieldAttemptCountKey,
        SharedAppGroup.lastUnlockExpirationKey,
        SharedAppGroup.desiredShieldActiveKey,
        SharedAppGroup.screenTimeSelectionKey
    ].forEach { defaults.removeObject(forKey: $0) }
}
