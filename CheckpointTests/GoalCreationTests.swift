import XCTest
@testable import Checkpoint

final class GoalCreationTests: CheckpointWorkflowTestCase {
    // MARK: - Goal creation and initial question generation

    @MainActor
    func testInitialAvailabilityFailureCanRetryWithoutPresentingPaywall() async {
        let recoveryEngine = RecoveringQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: recoveryEngine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate on arrays, weak at recursion",
            focusAreas: "arrays, recursion, hash maps",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertEqual(store.questionBatchState, .failed)
        XCTAssertEqual(store.lastQuestionGenerationFailure, .serviceUnavailable)
        XCTAssertFalse(store.hasReadyCheckpointSet)
        XCTAssertTrue(store.activeQuestions.isEmpty)
        XCTAssertNil(store.pendingMembershipFeature)
        XCTAssertFalse(store.lastAIErrorMessage?.localizedCaseInsensitiveContains("pro") ?? false)

        let unavailableSession = await store.prepareManualCheckpointSession()
        XCTAssertNil(unavailableSession)
        XCTAssertNil(store.pendingMembershipFeature)

        await store.retryInitialQuestionGeneration()

        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertNil(store.lastQuestionGenerationFailure)
        XCTAssertGreaterThanOrEqual(store.activeQuestions.count, UnlockPolicy.default.questionsPerSession)
        XCTAssertTrue(store.hasReadyCheckpointSet)
        XCTAssertNil(store.pendingMembershipFeature)
    }

    @MainActor
    func testCachedReadyQuestionsSurviveRefreshAvailabilityFailure() async {
        let goal = makeGoal()
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: UnavailableQuestionEngine(provider: .backend),
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (1...UnlockPolicy.default.questionsPerSession).map {
            makeQuestion(goal: goal, index: $0)
        }
        let cachedQuestionIDs = Set(store.activeQuestions.map(\.id))

        await store.refreshQuestionBatch()

        XCTAssertEqual(Set(store.activeQuestions.map(\.id)), cachedQuestionIDs)
        XCTAssertTrue(store.hasReadyCheckpointSet)
        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertEqual(store.lastQuestionGenerationFailure, .serviceUnavailable)
        XCTAssertNil(store.pendingMembershipFeature)
    }

    @MainActor
    func testProtectionPreflightGeneratesAFullCheckpointBeforeAllowingStart() async {
        let appleEngine = TargetCountQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: appleEngine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)
        store.goal = makeGoal()

        let isReady = await store.prepareQuestionsForProtectionStart()

        XCTAssertTrue(isReady)
        XCTAssertTrue(store.hasReadyCheckpointSet)
        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertNil(store.checkpointNotice)
    }

    @MainActor
    func testProtectionPreflightKeepsProtectionOffWhenGenerationFails() async {
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: UnavailableQuestionEngine(provider: .backend),
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)
        store.goal = makeGoal()

        let isReady = await store.prepareQuestionsForProtectionStart()

        XCTAssertFalse(isReady)
        XCTAssertFalse(store.hasReadyCheckpointSet)
        XCTAssertEqual(store.questionBatchState, .failed)
        XCTAssertTrue(store.checkpointNotice?.contains("Protection stayed off") ?? false)
        XCTAssertFalse(SharedAppGroup.desiredShieldActive)
    }

    @MainActor
    func testCreateGoalRejectsBlankTitle() async {
        let store = CheckpointStore(defaults: defaults)

        await store.createGoal(
            title: "   ",
            deadline: Date().addingTimeInterval(-60),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertNil(store.goal)
        XCTAssertEqual(store.questionBatchState, .failed)
        XCTAssertEqual(store.lastAIErrorMessage, "Enter a goal before generating questions.")
    }

    @MainActor
    func testStarterCanCreateFirstGoalAndStarterQuestionBank() async throws {
        let appleEngine = TargetCountQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: appleEngine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)

        await store.createGoal(
            title: "Pass the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate logical reasoning",
            focusAreas: "logical reasoning",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertEqual(store.membershipTier, .starter)
        XCTAssertFalse(store.isMember)
        XCTAssertEqual(store.questionBankTargetCount, ProductLimits.starterQuestionBankTargetCount)
        XCTAssertNotNil(store.goal)
        XCTAssertGreaterThanOrEqual(store.activeQuestions.count, 5)
        XCTAssertNil(store.pendingMembershipFeature)
    }

    @MainActor
    func testStarterRequestsMembershipForSecondGoal() async throws {
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: TargetCountQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays",
            preferredQuestionStyle: .multipleChoice
        )
        let firstGoal = try XCTUnwrap(store.goal)

        await store.createGoal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "integrals",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertEqual(store.goal?.id, firstGoal.id)
        XCTAssertEqual(store.availableGoalProfiles.count, 1)
        XCTAssertEqual(store.pendingMembershipFeature, .goalProfiles)
        XCTAssertTrue(store.checkpointNotice?.contains("Free includes one goal") ?? false)
    }

    @MainActor
    func testStarterCanEditItsExistingGoalWithSourceDocuments() async throws {
        let appleEngine = TargetCountQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: appleEngine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays",
            preferredQuestionStyle: .multipleChoice
        )

        let source = GoalSourceDocument(
            name: "Course notes.txt",
            text: "The interview rubric emphasizes recursion, graph traversal, complexity analysis, and explaining tradeoffs aloud."
        )
        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Comfortable with arrays; new to graph traversal",
            focusAreas: "recursion, graph traversal",
            sourceDocuments: [source],
            preferredQuestionStyle: .multipleChoice,
            createsNewProfile: false
        )

        XCTAssertEqual(store.availableGoalProfiles.count, 1)
        XCTAssertEqual(store.goal?.currentLevel, "Comfortable with arrays; new to graph traversal")
        XCTAssertEqual(store.goal?.sourceDocuments.map(\.name), ["Course notes.txt"])
        XCTAssertNil(store.pendingMembershipFeature)
        XCTAssertTrue(store.hasReadyCheckpointSet)
    }

    @MainActor
    func testStarterRequestsMembershipWhenCoreQuestionsAreUsedUp() async throws {
        let goal = makeGoal()
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.goal = goal
        store.questions = [makeQuestion(goal: goal, index: 1, status: .retired)]

        let session = await store.prepareManualCheckpointSession()

        XCTAssertNil(session)
        XCTAssertNil(appleEngine.receivedRequest)
        XCTAssertEqual(store.pendingMembershipFeature, .freshQuestionGeneration)
        XCTAssertTrue(store.checkpointNotice?.contains("Pro keeps new checkpoints") ?? false)
    }

    @MainActor
    func testSameMembershipTierUpdateDoesNotKickOffRefreshAgain() async throws {
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
        store.pendingMembershipFeature = .freshQuestionGeneration

        store.updateMembershipTier(.member)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(store.pendingMembershipFeature)
        XCTAssertTrue(appleEngine.receivedRequests.isEmpty)
    }

    @MainActor
    func testUnchangedEntitlementReconciliationKeepsContextualPaywallPresented() {
        let store = CheckpointStore(defaults: defaults)
        store.pendingMembershipFeature = .adaptiveStudyAssist

        store.reconcileMembershipEntitlement(isUnlocked: false)

        XCTAssertEqual(store.membershipTier, .starter)
        XCTAssertEqual(store.pendingMembershipFeature, .adaptiveStudyAssist)
    }

    @MainActor
    func testChangedEntitlementReconciliationUnlocksAndDismissesPaywall() {
        let store = CheckpointStore(defaults: defaults)
        store.pendingMembershipFeature = .adaptiveStudyAssist

        store.reconcileMembershipEntitlement(isUnlocked: true)

        XCTAssertEqual(store.membershipTier, .member)
        XCTAssertNil(store.pendingMembershipFeature)
    }

    @MainActor
    func testCreateGoalCanReturnBeforeInitialQuestionsFinish() async {
        let delayedEngine = DelayedQuestionEngine(
            provider: .appleFoundation,
            delayNanoseconds: 150_000_000
        )
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: delayedEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)

        await store.createGoal(
            title: "Pass the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate logical reasoning",
            focusAreas: "logical reasoning",
            preferredQuestionStyle: .multipleChoice,
            waitForQuestionGeneration: false
        )

        XCTAssertNotNil(store.goal)
        XCTAssertFalse(store.isOnboardingPresented)
        XCTAssertEqual(store.questionBatchState, .generating)
        XCTAssertTrue(store.questionGenerationStatusText.contains("Getting your first checkpoint ready"))
        XCTAssertTrue(store.questionGenerationStatusText.contains("you can leave this screen"))
        XCTAssertTrue(store.questions.isEmpty)

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertGreaterThanOrEqual(store.questions.count, 5)
        XCTAssertNotNil(store.lastQuestionGenerationDuration)
    }

    @MainActor
    func testCreateGoalPreparesFiveAIQuestionsThenTopsOffRemainder() async throws {
        let goal = makeGoal()
        let backendEngine = TargetCountQuestionEngine(
            provider: .backend,
            largeRequestDelayNanoseconds: 500_000_000
        )
        let engine = HybridQuestionEngine(
            backendEngine: backendEngine,
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.automatic)
        store.updateBackendEndpoint("https://example.com/ai")

        await store.createGoal(
            title: goal.title,
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            preferredQuestionStyle: goal.preferredQuestionStyle,
            waitForQuestionGeneration: false
        )

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertTrue(store.isQuestionBankTopOffInProgress)
        XCTAssertEqual(store.activeQuestions.count, 5)
        XCTAssertEqual(backendEngine.receivedRequests.first?.targetCount, 5)
        XCTAssertFalse(store.isPreparingActiveGoalQuestions)
        XCTAssertEqual(store.questionGenerationStatusText, "Practice is ready.")

        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertFalse(store.isQuestionBankTopOffInProgress)
        XCTAssertEqual(store.activeQuestions.count, ProductLimits.starterQuestionBankTargetCount)
        XCTAssertEqual(store.activeQuestions.filter { $0.status == .retired }.count, 0)
        XCTAssertEqual(backendEngine.receivedRequests.map(\.targetCount), [5, 35])
        XCTAssertEqual(backendEngine.receivedRequests.last?.existingQuestions.count, 5)
        XCTAssertNotNil(store.lastQuestionGenerationDuration)
        XCTAssertNotNil(store.lastQuestionBankTopOffDuration)
    }

    @MainActor
    func testConfiguredBackendRegeneratesCachedLocalTemplateBankOnLaunch() async throws {
        let goal = makeGoal()
        let seededStore = CheckpointStore(defaults: defaults)
        seededStore.goal = goal
        seededStore.goalProfiles = [goal]
        seededStore.questions = (1...5).map { makeQuestion(goal: goal, index: $0) }
        seededStore.lastQuestionProvider = .localTemplates
        seededStore.updateAIProviderPreference(.localTemplates)
        seededStore.updateBackendEndpoint("https://example.com/ai")

        let backendEngine = TargetCountQuestionEngine(
            provider: .backend,
            requestDelayNanoseconds: 100_000_000
        )
        let relaunchedStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )

        XCTAssertTrue(relaunchedStore.activeQuestions.isEmpty)
        XCTAssertEqual(relaunchedStore.questionBatchState, .generating)

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(backendEngine.receivedRequests.first?.targetCount, 5)
        XCTAssertEqual(relaunchedStore.activeQuestions.count, ProductLimits.starterQuestionBankTargetCount)
        XCTAssertEqual(relaunchedStore.lastQuestionProvider, .backend)
    }

    @MainActor
    func testSwitchingToGoalWithoutQuestionsStartsBackgroundPreparation() async {
        let delayedEngine = DelayedQuestionEngine(
            provider: .appleFoundation,
            delayNanoseconds: 150_000_000
        )
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: delayedEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        let firstGoal = makeGoal()
        let secondGoal = Goal(
            title: "Pass operating systems exam",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 21),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "interrupts, system calls",
            preferredQuestionStyle: .multipleChoice
        )
        store.goal = firstGoal
        store.goalProfiles = [firstGoal, secondGoal]

        XCTAssertTrue(store.switchActiveGoal(to: secondGoal.id))

        XCTAssertEqual(store.goal?.id, secondGoal.id)
        XCTAssertEqual(store.questionBatchState, .generating)
        XCTAssertTrue(store.questionGenerationStatusText.contains("Getting your first checkpoint ready"))
        XCTAssertTrue(store.questionGenerationStatusText.contains("you can leave this screen"))
        XCTAssertTrue(store.activeQuestions.isEmpty)

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertGreaterThanOrEqual(store.activeQuestions.count, 5)
        XCTAssertNotNil(store.lastQuestionGenerationDuration)
    }

    @MainActor
    func testCreateGoalKeepsUnspecifiedLegacyCategoryDomainNeutral() async throws {
        let store = CheckpointStore(defaults: defaults)

        await store.createGoal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            currentLevel: "Strong on logic games, weak on timed reading sections",
            focusAreas: "logical reasoning, reading comprehension",
            preferredQuestionStyle: .multipleChoice
        )

        let goal = try XCTUnwrap(store.goal)
        XCTAssertEqual(goal.category, .custom)
    }

    @MainActor
    func testGoalWithoutFocusAreasUsesProviderQuestionTopicsForInitialSkillMap() async throws {
        let backendEngine = SkillMapQuestionEngine(
            provider: .backend,
            topics: ["argument flaws", "conditional logic", "inference", "reading structure"]
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.backend)

        await store.createGoal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice,
            waitForQuestionGeneration: true
        )

        let initialRequest = try XCTUnwrap(backendEngine.receivedRequests.first)
        XCTAssertTrue(initialRequest.questionContext.needsGeneratedSkillMap)
        XCTAssertEqual(initialRequest.targetCount, 5)
        let storedGoal = try XCTUnwrap(store.goal)
        let inferredMap = try XCTUnwrap(storedGoal.derivedSkillMap)
        XCTAssertEqual(inferredMap.status, .suggested)
        XCTAssertEqual(
            Set(inferredMap.topicNames),
            ["argument flaws", "conditional logic", "inference", "reading structure"]
        )
        XCTAssertFalse(GoalQuestionContext(goal: storedGoal).needsGeneratedSkillMap)
        XCTAssertEqual(
            Set(store.sortedCompetencies.map(\.topic)),
            ["argument flaws", "conditional logic", "inference", "reading structure"]
        )
        XCTAssertEqual(
            Set(store.sortedCompetencies.compactMap(\.skillID)),
            Set(inferredMap.topics.map(\.id))
        )
        XCTAssertEqual(store.activeGoalFocusText, "argument flaws")
    }

}
