import XCTest
@testable import Checkpoint

final class QuestionRefillTests: CheckpointWorkflowTestCase {
    // MARK: - Refill, Study Assist, and difficulty

    @MainActor
    func testMemberRefreshesAfterOldRefreshCounter() async throws {
        let goal = makeGoal()
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = [makeQuestion(goal: goal, index: 1)]
        store.questionRefreshesUsed = 2

        await store.refreshQuestionBatch()

        let request = try XCTUnwrap(appleEngine.receivedRequest)
        XCTAssertEqual(request.targetCount, ProductLimits.memberQuestionBankTargetCount)
        XCTAssertEqual(store.questionRefreshesUsed, 2 + 1)
        XCTAssertEqual(store.questions.count, 1 + UnlockPolicy.maximumQuestionsPerSession)
    }

    @MainActor
    func testMemberRefreshUsesLargerQuestionBankTarget() async throws {
        let goal = makeGoal()
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = [makeQuestion(goal: goal, index: 99)]
        store.questionRefreshesUsed = 2

        await store.refreshQuestionBatch()

        let request = try XCTUnwrap(appleEngine.receivedRequest)
        XCTAssertEqual(request.targetCount, ProductLimits.memberQuestionBankTargetCount)
        XCTAssertEqual(store.questionRefreshesUsed, 2 + 1)
        XCTAssertEqual(store.questions.count, 1 + UnlockPolicy.maximumQuestionsPerSession)
    }

    @MainActor
    func testMemberProactivelyRefreshesLowReadyQuestionBank() async throws {
        let goal = makeGoal()
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (1...store.unlockPolicy.questionsPerSession).map { makeQuestion(goal: goal, index: $0) }

        let didRefresh = await store.refreshQuestionBatchIfNeeded()

        XCTAssertTrue(didRefresh)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let request = try XCTUnwrap(appleEngine.receivedRequest)
        XCTAssertEqual(request.targetCount, ProductLimits.memberQuestionBankTargetCount - store.unlockPolicy.questionsPerSession)
        XCTAssertEqual(
            store.questions.count,
            store.unlockPolicy.questionsPerSession + UnlockPolicy.maximumQuestionsPerSession
        )
        XCTAssertEqual(store.questionRefreshesUsed, 1)
    }

    @MainActor
    func testMemberQuietlyRefillsWhenQuestionsAreUsedUp() async throws {
        let goal = makeGoal()
        let backendEngine = TargetCountQuestionEngine(provider: .backend)
        let engine = HybridQuestionEngine(
            backendEngine: backendEngine,
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://example.com/ai")
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = [makeQuestion(goal: goal, index: 99, status: .retired)]
        store.questionRefreshesUsed = 2

        let preparedSession = await store.prepareManualCheckpointSession()
        let session = try XCTUnwrap(preparedSession)

        let request = try XCTUnwrap(backendEngine.receivedRequests.first)
        XCTAssertEqual(request.targetCount, store.unlockPolicy.questionsPerSession * 2)
        XCTAssertEqual(session.questions.count, store.unlockPolicy.questionsPerSession)
        XCTAssertEqual(store.questionRefreshesUsed, 2 + 1)
        XCTAssertNil(store.checkpointNotice)
    }

    @MainActor
    func testPendingShieldAttemptWithExhaustedCacheNeverWaitsForNetworkGeneration() async throws {
        let goal = makeGoal()
        let backendEngine = TargetCountQuestionEngine(provider: .backend)
        let engine = HybridQuestionEngine(
            backendEngine: backendEngine,
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://example.com/ai")
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (1...store.unlockPolicy.questionsPerSession).map { index in
            makeQuestion(
                goal: goal,
                index: index,
                status: .correct,
                timesCorrect: 1,
                lastAskedAt: Date(),
                nextReviewAt: Date().addingTimeInterval(60 * 60 * 24 * 3)
            )
        }

        XCTAssertFalse(store.hasReadyCheckpointSet)

        SharedAppGroup.markPendingShieldAttempt()
        let preparedSession = await store.preparePendingShieldSession()

        XCTAssertNil(preparedSession)
        XCTAssertTrue(backendEngine.receivedRequests.isEmpty)
        XCTAssertNotNil(SharedAppGroup.pendingShieldAttemptDate)
        XCTAssertTrue(store.checkpointNotice?.contains("cached checkpoint") ?? false)
    }

    @MainActor
    func testPendingShieldAttemptDoesNotStartPartialSessionWhenRefillIsShort() async throws {
        let goal = makeGoal()
        let appleEngine = CountSequenceQuestionEngine(provider: .appleFoundation, counts: [1, 0])
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (1...3).map { makeQuestion(goal: goal, index: $0) }

        SharedAppGroup.markPendingShieldAttempt()
        let preparedSession = await store.preparePendingShieldSession()

        XCTAssertNil(preparedSession)
        XCTAssertNotNil(SharedAppGroup.pendingShieldAttemptDate)
        XCTAssertFalse(store.checkpointNotice?.contains("3") ?? false)
        XCTAssertTrue(appleEngine.receivedRequests.isEmpty)
    }

    @MainActor
    func testPendingShieldAttemptUsesReadyCacheWithoutProviderRequest() async throws {
        let goal = makeGoal()
        let appleEngine = CountSequenceQuestionEngine(provider: .appleFoundation, counts: [1, 10])
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (1...store.unlockPolicy.questionsPerSession).map {
            makeQuestion(goal: goal, index: $0)
        }

        SharedAppGroup.markPendingShieldAttempt()
        let preparedSession = await store.preparePendingShieldSession()
        let session = try XCTUnwrap(preparedSession)

        XCTAssertEqual(session.questions.count, store.unlockPolicy.questionsPerSession)
        XCTAssertTrue(appleEngine.receivedRequests.isEmpty)
        XCTAssertNil(SharedAppGroup.pendingShieldAttemptDate)
    }

    @MainActor
    func testRelaunchRecoversPersistedGeneratingStateWithoutNetworkOnShieldPath() async throws {
        let goal = makeGoal()
        let seededStore = CheckpointStore(defaults: defaults)
        seededStore.updateAIProviderPreference(.backend)
        seededStore.updateBackendEndpoint("https://example.com/ai")
        seededStore.updateMembershipTier(.member)
        seededStore.goal = goal
        seededStore.questions = (1...UnlockPolicy.default.questionsPerSession).map {
            makeQuestion(
                goal: goal,
                index: $0,
                status: .correct,
                timesCorrect: 1,
                lastAskedAt: Date(),
                nextReviewAt: Date().addingTimeInterval(60 * 60 * 24 * 3)
            )
        }
        seededStore.lastQuestionProvider = .backend
        seededStore.questionBatchState = .generating
        seededStore.updateBackendEndpoint("https://example.com/ai")

        let backendEngine = TargetCountQuestionEngine(provider: .backend)
        let relaunchedStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )

        XCTAssertEqual(relaunchedStore.questionBatchState, .ready)
        XCTAssertFalse(relaunchedStore.hasReadyCheckpointSet)

        SharedAppGroup.markPendingShieldAttempt()
        let preparedSession = await relaunchedStore.preparePendingShieldSession()

        XCTAssertNil(preparedSession)
        XCTAssertTrue(backendEngine.receivedRequests.isEmpty)
        XCTAssertNotNil(SharedAppGroup.pendingShieldAttemptDate)
        XCTAssertTrue(relaunchedStore.checkpointNotice?.contains("cached checkpoint") ?? false)
    }

    @MainActor
    func testMemberRefillsWhenCorrectQuestionsAreStillCoolingDown() async throws {
        let goal = makeGoal()
        let appleEngine = TargetCountQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        let lastAskedAt = Date().addingTimeInterval(-60)
        store.questions = (1...store.unlockPolicy.questionsPerSession).map { index in
            makeQuestion(
                goal: goal,
                index: index,
                status: .correct,
                timesCorrect: 1,
                lastAskedAt: lastAskedAt,
                nextReviewAt: Date().addingTimeInterval(60 * 60 * 24 * 3)
            )
        }

        let preparedSession = await store.prepareManualCheckpointSession()
        let session = try XCTUnwrap(preparedSession)

        let request = try XCTUnwrap(appleEngine.receivedRequests.first)
        XCTAssertEqual(request.targetCount, store.unlockPolicy.questionsPerSession * 2)
        XCTAssertFalse(session.questions.contains { question in
            question.status == .correct && (question.nextReviewAt ?? .distantPast) > Date()
        })
    }

    @MainActor
    func testStudyAssistAutoRefreshesLowBankAndRespectsCooldown() async throws {
        let goal = makeGoal()
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (1...store.unlockPolicy.questionsPerSession).map {
            makeQuestion(goal: goal, index: $0)
        }

        let didRefresh = await store.refreshQuestionBatchIfNeeded()

        XCTAssertTrue(didRefresh)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let request = try XCTUnwrap(appleEngine.receivedRequest)
        XCTAssertEqual(request.targetCount, ProductLimits.memberQuestionBankTargetCount - store.unlockPolicy.questionsPerSession)
        XCTAssertEqual(
            store.questions.count,
            store.unlockPolicy.questionsPerSession + UnlockPolicy.maximumQuestionsPerSession
        )
        XCTAssertEqual(store.questionRefreshesUsed, 1)
        XCTAssertNotNil(store.lastAutomaticQuestionRefreshAt)

        let didRefreshAgain = await store.refreshQuestionBatchIfNeeded()

        XCTAssertFalse(didRefreshAgain)
        XCTAssertEqual(
            store.questions.count,
            store.unlockPolicy.questionsPerSession + UnlockPolicy.maximumQuestionsPerSession
        )
        XCTAssertEqual(store.questionRefreshesUsed, 1)
    }

    @MainActor
    func testLowQuestionBankResumesTopOffOnRelaunchEvenAfterRecentCoreRefill() async throws {
        let goal = makeGoal()
        let seededStore = CheckpointStore(defaults: defaults)
        seededStore.updateMembershipTier(.member)
        seededStore.goal = goal
        seededStore.questions = (1...UnlockPolicy.default.questionsPerSession).map {
            makeQuestion(goal: goal, index: $0)
        }
        seededStore.lastAutomaticQuestionRefreshAt = Date()
        seededStore.updateAIProviderPreference(.appleFoundation)

        let backendEngine = CapturingQuestionEngine(provider: .backend)
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let relaunchedStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: appleEngine
            ),
            defaults: defaults
        )
        XCTAssertEqual(relaunchedStore.goal?.id, goal.id)
        XCTAssertEqual(relaunchedStore.aiProviderPreference, .automatic)

        try? await Task.sleep(nanoseconds: 100_000_000)

        let request = try XCTUnwrap(backendEngine.receivedRequest)
        XCTAssertEqual(request.targetCount, ProductLimits.memberQuestionBankTargetCount - UnlockPolicy.default.questionsPerSession)
        XCTAssertTrue(appleEngine.receivedRequests.isEmpty)
    }

    @MainActor
    func testStudyAssistRecommendationUsesWeakestTopic() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.updateMembershipTier(.member)
        store.goal = goal
        var arrays = TopicCompetency.initial(topic: "arrays", estimatedLevel: 1.4)
        arrays.attempts = 4
        arrays.correct = 1
        arrays.incorrect = 3
        var recursion = TopicCompetency.initial(topic: "recursion", estimatedLevel: 2.8)
        recursion.attempts = 4
        recursion.correct = 4
        store.competencies = [recursion, arrays]

        let recommendation = try XCTUnwrap(store.studyFocusRecommendation)
        XCTAssertTrue(recommendation.contains("arrays"))
        XCTAssertTrue(recommendation.contains("another pass"))
        XCTAssertFalse(recommendation.contains("%"))
    }

    @MainActor
    func testQuestionBankReadinessWarningHidesHealthyCounts() {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.questions = (1...store.unlockPolicy.questionsPerSession).map {
            makeQuestion(goal: goal, index: $0)
        }

        XCTAssertNil(store.questionBankReadinessWarning(for: goal))
    }

    @MainActor
    func testQuestionBankReadinessWarningUsesGenericLowState() {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.questions = (1..<store.unlockPolicy.questionsPerSession).map {
            makeQuestion(goal: goal, index: $0)
        }

        XCTAssertEqual(store.questionBankReadinessWarning(for: goal), "Practice set low")

        store.questions = []

        XCTAssertEqual(store.questionBankReadinessWarning(for: goal), "No practice ready yet")
    }

    @MainActor
    func testQuestionLevelRecommendationAppearsAfterStrongRecentAccuracy() throws {
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 2
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0, difficulty: 2) }

        for question in store.questions {
            store.submitAnswer(
                question: question,
                answer: question.expectedAnswer,
                result: .correct,
                grantsUnlock: false
            )
        }

        let recommendation = try XCTUnwrap(store.questionLevelRecommendation)
        XCTAssertEqual(recommendation.currentQuestionLevel, 2)
        XCTAssertEqual(recommendation.nextLevel, 3)
        XCTAssertEqual(recommendation.accuracyPercent, 100)
        XCTAssertEqual(recommendation.answeredCount, 5)
    }

    @MainActor
    func testAcceptingQuestionLevelRecommendationRegeneratesHarderQuestions() async throws {
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 2
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questionRefreshesUsed = 2
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0, difficulty: 2) }
        let originalQuestionIDs = Set(store.questions.map(\.id))

        for question in store.questions {
            store.submitAnswer(
                question: question,
                answer: question.expectedAnswer,
                result: .correct,
                grantsUnlock: false
            )
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        await store.acceptQuestionLevelRecommendation()

        let request = try XCTUnwrap(appleEngine.receivedRequests.first { $0.minimumDifficulty == 3 })
        XCTAssertEqual(store.goal?.minimumQuestionDifficulty, 3)
        XCTAssertEqual(request.minimumDifficulty, 3)
        XCTAssertTrue(store.questions.filter { originalQuestionIDs.contains($0.id) }.allSatisfy { $0.status == .retired })
        XCTAssertTrue(store.activeQuestions.contains { $0.difficulty >= 3 && !originalQuestionIDs.contains($0.id) })
        XCTAssertEqual(store.questionRefreshesUsed, 2)
    }

    @MainActor
    func testManualQuestionDifficultyIncreaseRegeneratesHarderQuestions() async throws {
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 2
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questionRefreshesUsed = 1
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0, difficulty: 2) }
        let originalQuestionIDs = Set(store.questions.map(\.id))

        await store.updateMinimumQuestionDifficultyAndRegenerate(4)

        let request = try XCTUnwrap(appleEngine.receivedRequest)
        XCTAssertEqual(store.goal?.minimumQuestionDifficulty, 4)
        XCTAssertEqual(request.minimumDifficulty, 4)
        XCTAssertTrue(request.sourcePrompt(provider: .appleFoundation).contains("Hard reasoning"))
        XCTAssertTrue(store.questions.filter { originalQuestionIDs.contains($0.id) }.allSatisfy { $0.status == .retired })
        XCTAssertTrue(store.activeQuestions.contains { $0.difficulty >= 4 && !originalQuestionIDs.contains($0.id) })
        XCTAssertEqual(store.questionRefreshesUsed, 1)
    }

    @MainActor
    func testManualQuestionDifficultyDecreaseKeepsExistingHarderQuestions() async throws {
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 4
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0, difficulty: 4) }

        await store.updateMinimumQuestionDifficultyAndRegenerate(2)

        XCTAssertNil(appleEngine.receivedRequest)
        XCTAssertEqual(store.goal?.minimumQuestionDifficulty, 2)
        XCTAssertTrue(store.activeQuestions.allSatisfy { $0.status != .retired })
    }

    @MainActor
    func testStarterLevelRecommendationRequestsMembershipBeforeChangingDifficulty() async throws {
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 2
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.goal = goal
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0, difficulty: 2) }

        for question in store.questions {
            store.submitAnswer(
                question: question,
                answer: question.expectedAnswer,
                result: .correct,
                grantsUnlock: false
            )
        }

        await store.acceptQuestionLevelRecommendation()

        XCTAssertNil(appleEngine.receivedRequest)
        XCTAssertEqual(store.goal?.minimumQuestionDifficulty, 2)
        XCTAssertEqual(store.pendingMembershipFeature, .freshQuestionGeneration)
        XCTAssertTrue(store.checkpointNotice?.contains("Pro") ?? false)
    }

}
