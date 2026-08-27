import XCTest
@testable import Checkpoint

final class CheckpointWorkflowCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "CheckpointWorkflowCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        resetSharedProtectionState()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        resetSharedProtectionState()
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    // MARK: - Protection and break transitions

    @MainActor
    func testReadyProtectionStartAppliesShieldOnce() async {
        let store = makeStore(questionCount: 5)
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let started = await workflow.startProtection()

        XCTAssertTrue(started)
        XCTAssertEqual(protection.applyShieldCount, 1)
    }

    @MainActor
    func testUnreadyProtectionStartDoesNotApplyShield() async {
        let store = makeStore(questionCount: 0)
        store.questionBatchState = .generating
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let started = await workflow.startProtection()

        XCTAssertFalse(started)
        XCTAssertEqual(protection.applyShieldCount, 0)
    }

    @MainActor
    func testFailedBreakLeavesRunActiveAndDoesNotRecordUnlock() throws {
        let store = makeStore(questionCount: 5)
        let session = try XCTUnwrap(store.startManualCheckpointSession())
        let protection = FakeAppProtectionController()
        protection.shouldBeginBreak = false
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let errorMessage = workflow.finishPassed(session)

        XCTAssertNotNil(errorMessage)
        XCTAssertEqual(store.activeCheckpointRun?.sessionID, session.id)
        XCTAssertNil(store.unlockSession)
        XCTAssertTrue(store.unlockEvents.isEmpty)
    }

    @MainActor
    func testSuccessfulBreakRecordsUnlockAndResolvesRun() throws {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let store = makeStore(questionCount: 5)
        store.updateUnlockMinutes(10)
        let session = try XCTUnwrap(store.startManualCheckpointSession())
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: protection,
            now: { now }
        )

        let errorMessage = workflow.finishPassed(session)

        XCTAssertNil(errorMessage)
        XCTAssertNil(store.activeCheckpointRun)
        XCTAssertEqual(store.unlockSession?.expiresAt, now.addingTimeInterval(600))
        XCTAssertEqual(store.unlockEvents.count, 1)
        XCTAssertEqual(protection.beginBreakCount, 1)
    }

    @MainActor
    func testStaleSessionCannotChangeProtection() throws {
        let store = makeStore(questionCount: 5)
        let session = try XCTUnwrap(store.startManualCheckpointSession())
        store.discardCheckpointRunBeforePresentation(sessionID: session.id)
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let errorMessage = workflow.finishPassed(session)

        XCTAssertNotNil(errorMessage)
        XCTAssertEqual(protection.beginBreakCount, 0)
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    @MainActor
    func testOnlyOneNonPreviewRunCanBeActive() throws {
        let store = makeStore(questionCount: 20)
        let firstSession = try XCTUnwrap(store.startManualCheckpointSession())

        let secondSession = store.startStopBlockingSession()

        XCTAssertNil(secondSession)
        XCTAssertEqual(store.activeCheckpointRun?.sessionID, firstSession.id)
    }

    @MainActor
    func testReadinessLossDoesNotReconcileProtectionDuringActiveRun() throws {
        let store = makeStore(questionCount: 5)
        _ = try XCTUnwrap(store.startManualCheckpointSession())
        store.questions[0].status = .retired
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        workflow.reconcileProtectionState()

        XCTAssertFalse(store.hasReadyCheckpointSet)
        XCTAssertEqual(protection.applyShieldCount, 0)
        XCTAssertEqual(protection.clearShieldCount, 0)
        XCTAssertTrue(protection.isShieldingEnabled)
    }

    @MainActor
    func testEndingBreakRelocksBeforeClearingUnlockJournal() {
        let store = makeStore(questionCount: 5)
        store.startUnlockSession(minutes: 10)
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        workflow.endBreakEarly()

        XCTAssertEqual(protection.applyShieldCount, 1)
        XCTAssertTrue(protection.isShieldingEnabled)
        XCTAssertNil(store.unlockSession)
    }

    @MainActor
    func testStopReviewClearsProtectionAndUnlockJournal() throws {
        let store = makeStore(questionCount: 20)
        store.startUnlockSession(minutes: 10)
        let session = try XCTUnwrap(store.startStopBlockingSession())
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let errorMessage = workflow.finishPassed(session)

        XCTAssertNil(errorMessage)
        XCTAssertEqual(protection.clearShieldCount, 1)
        XCTAssertNil(store.unlockSession)
        XCTAssertNil(store.activeCheckpointRun)
    }

    @MainActor
    func testEndBreakTurnsProtectionOffWhenNoCheckpointRemains() {
        let store = makeStore(questionCount: 0)
        store.startUnlockSession(minutes: 10)
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        workflow.endBreakEarly()

        XCTAssertEqual(protection.applyShieldCount, 0)
        XCTAssertEqual(protection.clearShieldCount, 1)
        XCTAssertNil(store.unlockSession)
        XCTAssertTrue(store.checkpointNotice?.contains("turned off") ?? false)
    }

    @MainActor
    func testReadinessPublicationDoesNotRewriteProtectionSnapshot() {
        let selection = Data("protected selection".utf8)
        SharedAppGroup.publishScreenTimeSelectionData(selection)
        let protectionSnapshot = SharedAppGroup.currentProtectionSnapshot()

        SharedAppGroup.publishCheckpointReadiness(false)

        XCTAssertEqual(SharedAppGroup.currentProtectionSnapshot(), protectionSnapshot)
        XCTAssertEqual(SharedAppGroup.screenTimeSelectionData(), selection)
        XCTAssertEqual(SharedAppGroup.checkpointReady, false)
    }

    @MainActor
    func testProtectionPreflightPublishesTimeDerivedReadiness() async {
        let store = makeStore(questionCount: 5)
        for index in store.questions.indices {
            store.questions[index].status = .correct
            store.questions[index].nextReviewAt = Date().addingTimeInterval(60)
        }
        SharedAppGroup.publishCheckpointReadiness(false)
        XCTAssertFalse(store.hasReadyCheckpointSet)

        for index in store.questions.indices {
            store.questions[index].nextReviewAt = Date().addingTimeInterval(-1)
        }
        let isReady = await store.prepareQuestionsForProtectionStart()

        XCTAssertTrue(isReady)
        XCTAssertEqual(SharedAppGroup.checkpointReady, true)
    }

    @MainActor
    func testRelaunchRecoversCanonicalBreakAfterPlatformTransition() throws {
        let store = makeStore(questionCount: 5)
        _ = try XCTUnwrap(store.startManualCheckpointSession())
        let expiration = Date().addingTimeInterval(600)
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: expiration)

        let restoredStore = CheckpointStore(defaults: defaults)

        XCTAssertNil(restoredStore.activeCheckpointRun)
        XCTAssertEqual(restoredStore.unlockSession?.expiresAt, expiration)
        XCTAssertEqual(restoredStore.unlockEvents.count, 1)
        XCTAssertFalse(restoredStore.isCheckpointRetryCooldownActive)
    }

    @MainActor
    func testInterruptedRunRestoresPersistedMisses() throws {
        let store = makeStore(questionCount: 5)
        let session = try XCTUnwrap(store.startManualCheckpointSession())
        let missedQuestion = session.questions[0]
        store.submitAnswer(
            question: missedQuestion,
            answer: "wrong",
            result: .incorrect,
            grantsUnlock: false
        )
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)

        let restoredStore = CheckpointStore(defaults: defaults)
        let restoredQuestion = restoredStore.questions.first { $0.id == missedQuestion.id }

        XCTAssertNil(restoredStore.activeCheckpointRun)
        XCTAssertEqual(restoredQuestion?.status, .incorrect)
        XCTAssertNotNil(restoredQuestion?.nextReviewAt)
        XCTAssertTrue(restoredStore.isCheckpointRetryCooldownActive)
    }

    // MARK: - Goal edits

    @MainActor
    func testNoOpGoalEditPreservesIdentityHistoryAndQuestionBank() async throws {
        let store = makeStore(questionCount: 5)
        let goal = try XCTUnwrap(store.goal)
        let question = try XCTUnwrap(store.questions.first)
        store.submitAnswer(
            question: question,
            answer: question.expectedAnswer,
            result: .correct,
            grantsUnlock: false
        )
        let questionIDs = store.questions.map(\.id)

        await store.updateActiveGoal(
            title: goal.title,
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            sourceDocuments: goal.sourceDocuments,
            preferredQuestionStyle: goal.preferredQuestionStyle,
            minimumQuestionDifficulty: goal.minimumQuestionDifficulty
        )

        XCTAssertEqual(store.goal?.id, goal.id)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(store.questions.map(\.id), questionIDs)
    }

    @MainActor
    func testConsumedFreeGoalEditKeepsRemainingQuestionsWithoutPaywall() async throws {
        let store = makeStore(questionCount: 8)
        let goal = try XCTUnwrap(store.goal)
        let question = try XCTUnwrap(store.questions.first)
        store.submitAnswer(
            question: question,
            answer: question.expectedAnswer,
            result: .correct,
            grantsUnlock: false
        )
        let questionIDs = store.questions.map(\.id)

        await store.updateActiveGoal(
            title: "Updated goal",
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: "new focus",
            sourceDocuments: goal.sourceDocuments,
            preferredQuestionStyle: goal.preferredQuestionStyle,
            minimumQuestionDifficulty: goal.minimumQuestionDifficulty
        )

        XCTAssertEqual(store.goal?.id, goal.id)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(store.questions.map(\.id), questionIDs)
        XCTAssertFalse(store.questions.allSatisfy { $0.status == .retired })
        XCTAssertNil(store.pendingMembershipFeature)
        XCTAssertTrue(store.checkpointNotice?.contains("future questions") ?? false)
    }

    @MainActor
    func testUnpracticedFreeGoalCanBeEditedTwiceWithoutReplacingItsBank() async throws {
        let store = makeStore(questionCount: 8)
        let originalQuestionIDs = store.questions.map(\.id)
        let goal = try XCTUnwrap(store.goal)

        for title in ["Updated once", "Updated twice"] {
            await store.updateActiveGoal(
                title: title,
                deadline: goal.deadline,
                category: goal.category,
                currentLevel: goal.currentLevel,
                focusAreas: goal.focusAreas,
                sourceDocuments: goal.sourceDocuments,
                preferredQuestionStyle: goal.preferredQuestionStyle,
                minimumQuestionDifficulty: goal.minimumQuestionDifficulty
            )
        }

        XCTAssertEqual(store.questions.map(\.id), originalQuestionIDs)
        XCTAssertFalse(store.questions.contains { $0.status == .retired })
        XCTAssertNil(store.pendingMembershipFeature)
    }

    @MainActor
    func testFailedGoalEditGenerationPreservesExistingPartialBank() async throws {
        let goal = makeCoordinatorTestGoal()
        let engine = HybridQuestionEngine(
            backendEngine: FailingCoordinatorQuestionEngine(),
            appleFoundationEngine: FailingCoordinatorQuestionEngine()
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = (1...4).map {
            makeCoordinatorTestQuestion(goal: goal, index: $0)
        }
        let originalQuestionIDs = store.questions.map(\.id)

        await store.updateActiveGoal(
            title: "Updated goal",
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: "updated focus",
            preferredQuestionStyle: goal.preferredQuestionStyle,
            minimumQuestionDifficulty: goal.minimumQuestionDifficulty
        )

        XCTAssertEqual(store.questions.map(\.id), originalQuestionIDs)
        XCTAssertFalse(store.questions.contains { $0.status == .retired })
        XCTAssertEqual(store.questionBatchState, .failed)
    }

    @MainActor
    private func makeStore(questionCount: Int) -> CheckpointStore {
        let goal = makeCoordinatorTestGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = (0..<questionCount).map {
            makeCoordinatorTestQuestion(goal: goal, index: $0 + 1)
        }
        return store
    }
}

// MARK: - Test support

@MainActor
private final class FakeAppProtectionController: AppProtectionControlling {
    let hasSelection = true
    var isShieldingEnabled = false
    var userFacingErrorMessage: String?
    var shouldBeginBreak = true
    private(set) var applyShieldCount = 0
    private(set) var clearShieldCount = 0
    private(set) var beginBreakCount = 0

    func applyShield() {
        applyShieldCount += 1
        isShieldingEnabled = true
    }

    func clearShield() {
        clearShieldCount += 1
        isShieldingEnabled = false
    }

    func temporarilyUnshield(until expiration: Date) -> Bool {
        beginBreakCount += 1
        guard shouldBeginBreak else {
            userFacingErrorMessage = "Break failed"
            return false
        }
        isShieldingEnabled = false
        return true
    }

    func reconcileShieldState(protectionShouldRemainActive: Bool?) {
        if protectionShouldRemainActive == true {
            applyShield()
        } else {
            clearShield()
        }
    }

    func refreshActiveShieldConfiguration() {}
}

private struct FailingCoordinatorQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind = .backend

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        throw QuestionGenerationError.providerUnavailable
    }
}

private func makeCoordinatorTestGoal() -> Goal {
    Goal(
        title: "Prepare for interviews",
        deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
        category: .codingInterview,
        currentLevel: "Intermediate",
        focusAreas: "arrays, recursion",
        preferredQuestionStyle: .multipleChoice
    )
}

private func makeCoordinatorTestQuestion(goal: Goal, index: Int) -> CheckpointQuestion {
    CheckpointQuestion(
        goalID: goal.id,
        prompt: "Question \(index)",
        expectedAnswer: "Answer \(index)",
        choices: ["Answer \(index)", "A", "B", "C"],
        explanation: "Explanation \(index)",
        topic: "arrays",
        difficulty: 2,
        format: .multipleChoice,
        sourcePrompt: "test"
    )
}

private func resetSharedProtectionState() {
    let defaults = SharedAppGroup.defaults
    SharedAppGroup.removeAllPendingShieldAttempts()
    [
        SharedAppGroup.lastUnlockExpirationKey,
        SharedAppGroup.desiredShieldActiveKey,
        SharedAppGroup.checkpointReadyKey,
        SharedAppGroup.screenTimeSelectionKey,
        SharedAppGroup.screenTimeSelectionSemanticsVersionKey,
        SharedAppGroup.protectionConfigurationRevisionKey,
        SharedAppGroup.protectionRevisionKey,
        SharedAppGroup.protectionUpdatedAtKey
    ].forEach { defaults.removeObject(forKey: $0) }
    defaults.synchronize()
    SharedAppGroup.removeScreenTimeSelectionFile()
    SharedAppGroup.removeProtectionSnapshotFile()
}
