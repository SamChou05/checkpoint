import SwiftUI
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

        let isReady = await store.prepareQuestionsForProtectionStart(
            expectedGoalID: store.goal?.id
        )

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

        let isReady = await store.prepareQuestionsForProtectionStart(
            expectedGoalID: store.goal?.id
        )

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
    func testChangedEntitlementReconciliationUnlocksAndKeepsPaywallForConfirmation() {
        let store = CheckpointStore(defaults: defaults)
        store.pendingMembershipFeature = .adaptiveStudyAssist

        store.reconcileMembershipEntitlement(isUnlocked: true)

        XCTAssertEqual(store.membershipTier, .member)
        XCTAssertEqual(store.pendingMembershipFeature, .adaptiveStudyAssist)
        XCTAssertNil(store.completedMembershipActivationContinuation)
    }

    @MainActor
    func testGoalCreationMembershipContinuationStaysDurableUntilCompletionOrCancel() {
        let store = CheckpointStore(defaults: defaults)
        let sourceGoal = makeGoal()
        store.goal = sourceGoal
        store.goalProfiles = [sourceGoal]
        store.isOnboardingPresented = false

        store.presentGoalProfileCreator()

        let expectedContinuation = MembershipActivationContinuation.createGoalProfile(
            sourceGoalID: sourceGoal.id
        )
        XCTAssertEqual(store.pendingMembershipPresentation, .feature(.goalProfiles))
        XCTAssertEqual(store.pendingMembershipActivationContinuation, expectedContinuation)
        XCTAssertFalse(store.isOnboardingPresented)

        store.requestMembership(for: .freshQuestionGeneration)
        store.requestMembershipOverview()
        XCTAssertEqual(store.pendingMembershipPresentation, .feature(.goalProfiles))
        XCTAssertEqual(store.pendingMembershipActivationContinuation, expectedContinuation)

        XCTAssertTrue(store.membershipCheckoutStarted())
        store.reconcileMembershipEntitlement(isUnlocked: true)
        XCTAssertEqual(store.pendingMembershipPresentation, .feature(.goalProfiles))
        XCTAssertNil(store.pendingMembershipActivationContinuation)
        XCTAssertEqual(store.completedMembershipActivationContinuation, expectedContinuation)

        XCTAssertEqual(store.completeMembershipCheckout(), expectedContinuation)
        XCTAssertNil(store.pendingMembershipActivationContinuation)
        XCTAssertEqual(store.completedMembershipActivationContinuation, expectedContinuation)

        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        store.dismissMembershipPrompt()
        XCTAssertEqual(
            store.claimMembershipActivationContinuationForResume(),
            expectedContinuation
        )
        XCTAssertNil(store.claimMembershipActivationContinuationForResume())

        store.presentGoalProfileCreator()
        XCTAssertTrue(store.isCreatingGoalProfile)
        XCTAssertTrue(store.isOnboardingPresented)
        XCTAssertNil(store.pendingMembershipPresentation)
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .resumeRequested)

        XCTAssertTrue(store.cancelResumedMembershipGoalCreation())
        XCTAssertNil(store.membershipActivationHandoff)
    }

    @MainActor
    func testEntitlementConfirmationAtomicallyOwnsContinuationBeforeDismissal() {
        let store = CheckpointStore(defaults: defaults)
        let sourceGoal = makeGoal()
        store.goal = sourceGoal
        store.goalProfiles = [sourceGoal]
        store.isOnboardingPresented = false
        store.presentGoalProfileCreator()
        let expectedContinuation = MembershipActivationContinuation.createGoalProfile(
            sourceGoalID: sourceGoal.id
        )

        store.reconcileMembershipEntitlement(isUnlocked: true)
        store.requestMembership(for: .freshQuestionGeneration)
        XCTAssertEqual(store.pendingMembershipPresentation, .feature(.goalProfiles))
        XCTAssertEqual(store.completedMembershipActivationContinuation, expectedContinuation)
        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        store.dismissMembershipPrompt()

        XCTAssertEqual(
            store.claimMembershipActivationContinuationForResume(),
            expectedContinuation
        )
        XCTAssertNil(store.claimMembershipActivationContinuationForResume())
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .resumeRequested)
        XCTAssertTrue(store.cancelResumedMembershipGoalCreation())
    }

    @MainActor
    func testDismissingMembershipBeforeActivationDiscardsTheContinuation() {
        let store = CheckpointStore(defaults: defaults)
        let sourceGoal = makeGoal()
        store.goal = sourceGoal
        store.goalProfiles = [sourceGoal]

        store.presentGoalProfileCreator()
        store.dismissMembershipPrompt()

        XCTAssertNil(store.pendingMembershipActivationContinuation)
        XCTAssertNil(store.completeMembershipCheckout())
        XCTAssertNil(store.claimMembershipActivationContinuationForResume())
    }

    @MainActor
    func testPendingMembershipDismissalKeepsThePaidActionForLaterApproval() {
        let store = CheckpointStore(defaults: defaults)
        let sourceGoal = makeGoal()
        store.goal = sourceGoal
        store.goalProfiles = [sourceGoal]

        store.presentGoalProfileCreator()
        let continuation = store.pendingMembershipActivationContinuation
        XCTAssertTrue(store.membershipCheckoutStarted())
        store.membershipCheckoutFinished(hasUnresolvedPurchase: true)

        store.dismissMembershipPrompt(hasUnresolvedPurchase: true)

        XCTAssertNil(store.pendingMembershipPresentation)
        XCTAssertEqual(store.pendingMembershipActivationContinuation, continuation)
        XCTAssertNil(store.claimMembershipActivationContinuationForResume())

        store.reconcileMembershipEntitlement(
            isUnlocked: true,
            activationSource: .entitlementRefresh
        )

        XCTAssertNil(store.pendingMembershipActivationContinuation)
        XCTAssertEqual(store.completedMembershipActivationContinuation, continuation)
    }

    @MainActor
    func testMembershipActionCannotResumeBeforeActivationIsReady() {
        let store = CheckpointStore(defaults: defaults)
        let sourceGoal = makeGoal()
        store.goal = sourceGoal
        store.goalProfiles = [sourceGoal]

        store.presentGoalProfileCreator()
        store.updateMembershipTier(.member)

        XCTAssertEqual(store.membershipActivationHandoff?.phase, .offered)
        XCTAssertEqual(store.requestMembershipActivationResume(), .actionUnavailable)
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .offered)
    }

    @MainActor
    func testVerifiedActivationReceiptIsAvailableBeforeTheMembershipSheetRenders() throws {
        let store = CheckpointStore(defaults: defaults)
        let sourceGoal = makeGoal()
        store.goal = sourceGoal
        store.goalProfiles = [sourceGoal]
        store.presentGoalProfileCreator()

        XCTAssertNil(
            store.membershipActivationPresentationIfVerified(
                fallbackContext: .overview,
                fallbackSource: .entitlementRefresh
            )
        )

        store.reconcileMembershipEntitlement(
            isUnlocked: true,
            activationSource: .purchase
        )
        let presentation = try XCTUnwrap(
            store.membershipActivationPresentationIfVerified(
                fallbackContext: .overview,
                fallbackSource: .entitlementRefresh
            )
        )

        XCTAssertEqual(presentation.context, .feature(.goalProfiles))
        XCTAssertEqual(presentation.source, .purchase)
        XCTAssertEqual(
            presentation.continuation,
            .createGoalProfile(sourceGoalID: sourceGoal.id)
        )
    }

    @MainActor
    func testCompletedMembershipContinuationIsDiscardedWhenItsSourceGoalChanges() {
        let store = CheckpointStore(defaults: defaults)
        let sourceGoal = makeGoal()
        let replacementGoal = Goal(
            title: "Prepare a design portfolio",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "case studies, visual systems",
            preferredQuestionStyle: .shortAnswer
        )
        store.goal = sourceGoal
        store.goalProfiles = [sourceGoal, replacementGoal]

        store.presentGoalProfileCreator()
        store.reconcileMembershipEntitlement(isUnlocked: true)
        _ = store.completeMembershipCheckout()
        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        store.goal = replacementGoal

        XCTAssertNil(store.claimMembershipActivationContinuationForResume())
        XCTAssertNil(store.completedMembershipActivationContinuation)
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .activationReady)
        XCTAssertNil(
            store.membershipActivationPresentation(
                fallbackContext: .overview,
                fallbackSource: .entitlementRefresh
            ).continuation
        )
        XCTAssertTrue(store.dismissMembershipPrompt())
        XCTAssertNil(store.membershipActivationHandoff)
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

        XCTAssertEqual(
            activatePreparedGoal(in: store, to: secondGoal.id),
            .activated(from: firstGoal.id, to: secondGoal.id)
        )

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

final class GoalSetupPresentationTests: XCTestCase {
    func testHeroPresentationCoversModesAndStates() {
        let firstEmpty = GoalSetupHeroPresentation(
            mode: .firstGoal,
            hasGoalTitle: false,
            isWorking: false
        )
        XCTAssertEqual(firstEmpty.state, .awaitingGoal)
        XCTAssertEqual(firstEmpty.status, "Goal needed")
        XCTAssertEqual(firstEmpty.eyebrow, "SETUP · STEP 1 OF 3")
        XCTAssertEqual(firstEmpty.title, "Set your outcome.")
        XCTAssertEqual(firstEmpty.guidance, "Enter one outcome to continue.")
        XCTAssertEqual(firstEmpty.accessibilityContext, "Checkpoint setup, step 1 of 3")

        let firstReady = GoalSetupHeroPresentation(
            mode: .firstGoal,
            hasGoalTitle: true,
            isWorking: false
        )
        XCTAssertEqual(firstReady.state, .ready)
        XCTAssertEqual(firstReady.status, "Ready")

        let newReady = GoalSetupHeroPresentation(
            mode: .newGoal,
            hasGoalTitle: true,
            isWorking: false
        )
        XCTAssertEqual(newReady.state, .ready)
        XCTAssertEqual(newReady.title, "Add another outcome.")
        XCTAssertEqual(
            newReady.guidance,
            "This goal becomes active. Your other goals stay available."
        )

        let editSaved = GoalSetupHeroPresentation(
            mode: .editGoal,
            hasGoalTitle: true,
            editImpact: .none,
            isWorking: false
        )
        XCTAssertEqual(editSaved.state, .upToDate)
        XCTAssertEqual(editSaved.status, "Up to date")
        XCTAssertEqual(editSaved.title, "Refine this outcome.")
        XCTAssertEqual(editSaved.guidance, "Your current goal is saved.")

        let editDeadline = GoalSetupHeroPresentation(
            mode: .editGoal,
            hasGoalTitle: true,
            editImpact: .deadlineOnly,
            isWorking: false
        )
        XCTAssertEqual(editDeadline.state, .unsavedChanges)
        XCTAssertEqual(editDeadline.status, "Unsaved changes")
        XCTAssertEqual(editDeadline.guidance, "Only the target date will change.")

        let editPractice = GoalSetupHeroPresentation(
            mode: .editGoal,
            hasGoalTitle: true,
            editImpact: .practiceSetup,
            isWorking: false
        )
        XCTAssertEqual(editPractice.state, .unsavedChanges)
        XCTAssertEqual(
            editPractice.guidance,
            "Future questions will use the updated practice setup."
        )

        let editBlank = GoalSetupHeroPresentation(
            mode: .editGoal,
            hasGoalTitle: false,
            editImpact: .practiceSetup,
            isWorking: false
        )
        XCTAssertEqual(editBlank.state, .awaitingGoal)
        XCTAssertEqual(editBlank.status, "Goal needed")
        XCTAssertEqual(editBlank.guidance, "Enter a goal before saving.")

        let firstWorking = GoalSetupHeroPresentation(
            mode: .firstGoal,
            hasGoalTitle: true,
            isWorking: true
        )
        XCTAssertEqual(firstWorking.state, .working)
        XCTAssertEqual(firstWorking.status, "Preparing…")

        let editWorking = GoalSetupHeroPresentation(
            mode: .editGoal,
            hasGoalTitle: true,
            editImpact: .practiceSetup,
            isWorking: true
        )
        XCTAssertEqual(editWorking.state, .working)
        XCTAssertEqual(editWorking.status, "Saving…")
    }

    func testDraftSnapshotAndDismissalPolicyProtectOnlyMeaningfulChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let baselineDeadline = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 8))
        )
        let baseline = GoalSetupDraftSnapshot(
            title: "  Pass the bar exam  ",
            deadline: baselineDeadline,
            currentLevel: " Intermediate ",
            focusAreas: " contracts, evidence ",
            sourceDocuments: [],
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        let normalizedMatch = GoalSetupDraftSnapshot(
            title: "Pass the bar exam",
            deadline: baselineDeadline.addingTimeInterval(60 * 60 * 10),
            currentLevel: "Intermediate",
            focusAreas: "contracts, evidence",
            sourceDocuments: [],
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        XCTAssertFalse(
            normalizedMatch.hasMeaningfulChanges(from: baseline, calendar: calendar)
        )

        let changed = GoalSetupDraftSnapshot(
            title: "Pass the California bar exam",
            deadline: baselineDeadline,
            currentLevel: "Intermediate",
            focusAreas: "contracts, evidence",
            sourceDocuments: [],
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        XCTAssertTrue(changed.hasMeaningfulChanges(from: baseline, calendar: calendar))

        let firstGoalPolicy = GoalSetupDismissalPolicy(
            mode: .firstGoal,
            hasUnsavedDraft: false
        )
        XCTAssertFalse(firstGoalPolicy.requiresDiscardConfirmation)
        XCTAssertTrue(firstGoalPolicy.preventsInteractiveDismissal)

        let cleanNewGoalPolicy = GoalSetupDismissalPolicy(
            mode: .newGoal,
            hasUnsavedDraft: false
        )
        XCTAssertFalse(cleanNewGoalPolicy.requiresDiscardConfirmation)
        XCTAssertFalse(cleanNewGoalPolicy.preventsInteractiveDismissal)

        let dirtyEditPolicy = GoalSetupDismissalPolicy(
            mode: .editGoal,
            hasUnsavedDraft: true
        )
        XCTAssertTrue(dirtyEditPolicy.requiresDiscardConfirmation)
        XCTAssertTrue(dirtyEditPolicy.preventsInteractiveDismissal)

        let importingIntoCleanEditPolicy = GoalSetupDismissalPolicy(
            mode: .editGoal,
            hasUnsavedDraft: false,
            hasPendingImport: true
        )
        XCTAssertTrue(importingIntoCleanEditPolicy.requiresDiscardConfirmation)
        XCTAssertTrue(importingIntoCleanEditPolicy.preventsInteractiveDismissal)
    }

    func testPrimaryActionDistinguishesDoneFromSavingChanges() {
        let unchanged = GoalSetupPrimaryActionPresentation(
            mode: .editGoal,
            editImpact: .none,
            isWorking: false
        )
        XCTAssertEqual(unchanged.title, "Done")
        XCTAssertEqual(unchanged.intent, .dismiss)

        let changed = GoalSetupPrimaryActionPresentation(
            mode: .editGoal,
            editImpact: .practiceSetup,
            isWorking: false
        )
        XCTAssertEqual(changed.title, "Save changes")
        XCTAssertEqual(changed.intent, .save)

        let firstGoal = GoalSetupPrimaryActionPresentation(
            mode: .firstGoal,
            editImpact: .none,
            isWorking: false
        )
        XCTAssertEqual(firstGoal.title, "Build my map")
        XCTAssertEqual(firstGoal.intent, .save)
        XCTAssertEqual(
            firstGoal.displayTitle(isAccessibilitySize: true),
            "Build map"
        )

        let firstGoalWorking = GoalSetupPrimaryActionPresentation(
            mode: .firstGoal,
            editImpact: .none,
            isWorking: true
        )
        XCTAssertEqual(
            firstGoalWorking.displayTitle(isAccessibilitySize: true),
            "Build map",
            "The accessibility-size action bar should not resize while saving."
        )
        XCTAssertEqual(
            firstGoalWorking.displayTitle(
                isAccessibilitySize: true,
                isImportingSources: true
            ),
            "Reading files"
        )
    }

    func testPersistenceAnnouncementsRepeatForEachFailedSaveAttempt() {
        let recoveryMessage = "Checkpoint could not save the latest local changes."

        XCTAssertNil(
            GoalSetupPersistenceAnnouncementPolicy.message(
                for: .recoveryMessageChanged,
                recoveryMessage: recoveryMessage,
                previouslyAnnouncedMessage: recoveryMessage
            ),
            "An unchanged passive recovery banner should not announce twice."
        )
        XCTAssertEqual(
            GoalSetupPersistenceAnnouncementPolicy.message(
                for: .saveFailed,
                recoveryMessage: recoveryMessage,
                previouslyAnnouncedMessage: recoveryMessage
            ),
            recoveryMessage,
            "Every explicit failed save needs feedback, even when its message is unchanged."
        )
        XCTAssertEqual(
            GoalSetupPersistenceAnnouncementPolicy.message(
                for: .saveFailed,
                recoveryMessage: nil,
                previouslyAnnouncedMessage: nil
            ),
            GoalSetupPersistenceAnnouncementPolicy.fallbackMessage
        )
    }

    func testCreateProtectionConfirmationPresentationUsesExactCopy() {
        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        let sourceGoal = Goal(
            title: "Prepare for interviews",
            deadline: deadline,
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "systems",
            preferredQuestionStyle: .multipleChoice
        )
        let draft = GoalProfileDraft(
            title: "Learn Japanese",
            deadline: deadline,
            currentLevel: "Beginner",
            focusAreas: "conversation",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        let targetGoal = Goal(
            title: draft.title,
            deadline: draft.deadline,
            category: draft.category,
            currentLevel: draft.currentLevel,
            focusAreas: draft.focusAreas,
            preferredQuestionStyle: draft.preferredQuestionStyle,
            minimumQuestionDifficulty: draft.minimumQuestionDifficulty
        )
        let request = GoalProfileMutationRequest(
            id: UUID(uuidString: "70F110D8-289B-4C84-82D2-D73CEFC6E038")!,
            createdAt: deadline,
            operation: .create(draft)
        )
        let immediatePlan = GoalProfileMutationPlan(
            request: request,
            sourceGoal: sourceGoal,
            sourceReadiness: .ready(selectableCount: 5, requiredCount: 5),
            targetGoal: targetGoal,
            resultingActiveGoal: targetGoal,
            resultingReadiness: .incomplete(selectableCount: 2, requiredCount: 5)
        )
        let breakPlan = GoalProfileMutationPlan(
            request: request,
            sourceGoal: sourceGoal,
            sourceReadiness: .ready(selectableCount: 5, requiredCount: 5),
            targetGoal: targetGoal,
            resultingActiveGoal: targetGoal,
            resultingReadiness: .incomplete(selectableCount: 4, requiredCount: 5)
        )

        let immediate = GoalSetupProtectionConfirmationPresentation(
            confirmation: GoalProfileMutationConfirmation(
                plan: immediatePlan,
                consent: .protection(.turnsOffImmediately),
                activeBreakAtRequest: false
            )
        )
        XCTAssertEqual(immediate.title, "Create goal and turn off protection?")
        XCTAssertEqual(
            immediate.message,
            "The new goal has 2 of 5 checkpoint questions ready. Creating it now makes it current and turns off app protection. Start protection again after a full checkpoint is ready."
        )
        XCTAssertEqual(immediate.confirmationButtonTitle, "Create and turn off")
        XCTAssertEqual(immediate.cancelButtonTitle, "Keep editing")

        let duringBreak = GoalSetupProtectionConfirmationPresentation(
            confirmation: GoalProfileMutationConfirmation(
                plan: breakPlan,
                consent: .protection(.preventsRelockAfterBreak),
                activeBreakAtRequest: true
            )
        )
        XCTAssertEqual(duringBreak.title, "Create goal before this break ends?")
        XCTAssertEqual(
            duringBreak.message,
            "Your current break will continue. Protection will return when it ends only if the new goal has a full checkpoint ready; otherwise it will turn off and you'll need to start it again. Right now, it has 4 of 5 checkpoint questions ready."
        )
        XCTAssertEqual(duringBreak.confirmationButtonTitle, "Create goal")
        XCTAssertEqual(duringBreak.cancelButtonTitle, "Keep editing")
    }

    func testEditProtectionConfirmationPresentationUsesExactCopy() {
        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        let sourceGoal = Goal(
            title: "Prepare for interviews",
            deadline: deadline,
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "systems",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        let draft = GoalProfileDraft(
            title: sourceGoal.title,
            deadline: sourceGoal.deadline,
            category: sourceGoal.category,
            currentLevel: sourceGoal.currentLevel,
            focusAreas: sourceGoal.focusAreas,
            preferredQuestionStyle: sourceGoal.preferredQuestionStyle,
            minimumQuestionDifficulty: 4
        )
        let targetGoal = Goal(
            id: sourceGoal.id,
            title: draft.title,
            deadline: draft.deadline,
            category: draft.category,
            currentLevel: draft.currentLevel,
            focusAreas: draft.focusAreas,
            preferredQuestionStyle: draft.preferredQuestionStyle,
            minimumQuestionDifficulty: draft.minimumQuestionDifficulty,
            createdAt: sourceGoal.createdAt
        )
        let request = GoalProfileMutationRequest(
            id: UUID(uuidString: "31EB2AAA-E8AA-4DBA-932A-832E378EF4A3")!,
            createdAt: deadline,
            operation: .edit(expectedGoalID: sourceGoal.id, draft: draft)
        )
        let immediatePlan = GoalProfileMutationPlan(
            request: request,
            sourceGoal: sourceGoal,
            sourceReadiness: .ready(selectableCount: 5, requiredCount: 5),
            targetGoal: targetGoal,
            resultingActiveGoal: targetGoal,
            resultingReadiness: .incomplete(selectableCount: 1, requiredCount: 5)
        )
        let breakPlan = GoalProfileMutationPlan(
            request: request,
            sourceGoal: sourceGoal,
            sourceReadiness: .ready(selectableCount: 5, requiredCount: 5),
            targetGoal: targetGoal,
            resultingActiveGoal: targetGoal,
            resultingReadiness: .incomplete(selectableCount: 4, requiredCount: 5)
        )

        let immediate = GoalSetupProtectionConfirmationPresentation(
            confirmation: GoalProfileMutationConfirmation(
                plan: immediatePlan,
                consent: .protection(.turnsOffImmediately),
                activeBreakAtRequest: false
            )
        )
        XCTAssertEqual(immediate.title, "Save changes and turn off protection?")
        XCTAssertEqual(
            immediate.message,
            "These changes leave 1 of 5 checkpoint questions ready. Saving now turns off app protection. Start protection again after a full checkpoint is ready."
        )
        XCTAssertEqual(immediate.confirmationButtonTitle, "Save and turn off")
        XCTAssertEqual(immediate.cancelButtonTitle, "Keep editing")

        let duringBreak = GoalSetupProtectionConfirmationPresentation(
            confirmation: GoalProfileMutationConfirmation(
                plan: breakPlan,
                consent: .protection(.preventsRelockAfterBreak),
                activeBreakAtRequest: true
            )
        )
        XCTAssertEqual(duringBreak.title, "Save changes before this break ends?")
        XCTAssertEqual(
            duringBreak.message,
            "Your current break will continue. Protection will return when it ends only if this goal has a full checkpoint ready; otherwise it will turn off and you'll need to start it again. These changes leave 4 of 5 checkpoint questions ready."
        )
        XCTAssertEqual(duringBreak.confirmationButtonTitle, "Save changes")
        XCTAssertEqual(duringBreak.cancelButtonTitle, "Keep editing")
    }

    func testEditImpactMatchesSavedDraftSemantics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let deadline = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))
        )
        let source = GoalSourceDocument(
            id: UUID(uuidString: "755A6153-315B-46E5-8751-321431B22B12")!,
            name: "Architecture notes.txt",
            text: "These architecture notes cover queues, caching, consistency, and tradeoffs.",
            importedAt: deadline
        )
        let goal = Goal(
            title: "Pass system design interviews",
            deadline: deadline,
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "queues, caching",
            sourceDocuments: [source],
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        let baseline = GoalSetupEditBaseline(goal: goal)

        func impact(
            title: String? = nil,
            deadline overrideDeadline: Date? = nil,
            currentLevel: String? = nil,
            focusAreas: String? = nil,
            sourceDocuments: [GoalSourceDocument]? = nil,
            preferredQuestionStyle: QuestionFormat? = nil,
            minimumQuestionDifficulty: Int? = nil
        ) -> GoalSetupEditImpact {
            GoalSetupEditImpact(
                baseline: baseline,
                title: title ?? goal.title,
                deadline: overrideDeadline ?? goal.deadline,
                currentLevel: currentLevel ?? goal.currentLevel,
                focusAreas: focusAreas ?? goal.focusAreas,
                sourceDocuments: sourceDocuments ?? goal.sourceDocuments,
                preferredQuestionStyle: preferredQuestionStyle ?? goal.preferredQuestionStyle,
                minimumQuestionDifficulty: minimumQuestionDifficulty ?? goal.minimumQuestionDifficulty,
                calendar: calendar
            )
        }

        XCTAssertEqual(
            impact(
                title: "  Pass system design interviews  ",
                deadline: deadline.addingTimeInterval(60 * 60 * 8),
                currentLevel: " Intermediate ",
                focusAreas: " queues, caching "
            ),
            .none
        )
        XCTAssertEqual(
            impact(deadline: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: deadline))),
            .deadlineOnly
        )
        XCTAssertEqual(impact(title: "Lead system design interviews"), .practiceSetup)
        XCTAssertEqual(impact(currentLevel: "Advanced"), .practiceSetup)
        XCTAssertEqual(impact(focusAreas: "queues, consistency"), .practiceSetup)
        XCTAssertEqual(impact(sourceDocuments: []), .practiceSetup)
        XCTAssertEqual(impact(preferredQuestionStyle: .shortAnswer), .practiceSetup)
        XCTAssertEqual(impact(minimumQuestionDifficulty: 3), .practiceSetup)

        let expiredDeadline = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -1, to: deadline)
        )
        let expiredGoal = Goal(
            title: goal.title,
            deadline: expiredDeadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            sourceDocuments: goal.sourceDocuments,
            preferredQuestionStyle: goal.preferredQuestionStyle,
            minimumQuestionDifficulty: goal.minimumQuestionDifficulty
        )
        XCTAssertEqual(
            GoalSetupEditImpact(
                baseline: GoalSetupEditBaseline(goal: expiredGoal),
                title: expiredGoal.title,
                deadline: deadline,
                currentLevel: expiredGoal.currentLevel,
                focusAreas: expiredGoal.focusAreas,
                sourceDocuments: expiredGoal.sourceDocuments,
                preferredQuestionStyle: expiredGoal.preferredQuestionStyle,
                minimumQuestionDifficulty: expiredGoal.minimumQuestionDifficulty,
                calendar: calendar
            ),
            .deadlineOnly
        )
    }

    func testDirectionUsesMeaningfulTopicsAndDeduplicatesAnnouncements() throws {
        XCTAssertNil(GoalSetupDirectionPresentation(goalTitle: "   ", focusAreas: "arrays"))

        let inferred = try XCTUnwrap(
            GoalSetupDirectionPresentation(
                goalTitle: "Study for systems design interview",
                focusAreas: "none"
            )
        )
        XCTAssertEqual(inferred.title, "Starting with “systems design interview”")
        XCTAssertTrue(inferred.topics.isEmpty)
        XCTAssertEqual(
            inferred.detail,
            "Checkpoint will use this as the starting direction for an editable skill map."
        )

        let explicit = try XCTUnwrap(
            GoalSetupDirectionPresentation(
                goalTitle: "Pass technical interviews",
                focusAreas: "arrays, ARRAYs, none, ???, graph traversal"
            )
        )
        XCTAssertEqual(explicit.title, "Using 2 topics you chose")
        XCTAssertEqual(explicit.topics, ["arrays", "graph traversal"])

        let acronym = try XCTUnwrap(
            GoalSetupDirectionPresentation(goalTitle: "Prepare for the MCAT", focusAreas: "")
        )
        XCTAssertEqual(acronym.title, "Starting with “MCAT”")
        XCTAssertTrue(acronym.accessibilityAnnouncement.contains("MCAT"))

        var previewState = GoalSetupDirectionPreviewState()
        let firstAnnouncement = previewState.commit(
            goalTitle: "Prepare for the MCAT",
            focusAreas: ""
        )
        XCTAssertNotNil(firstAnnouncement)
        XCTAssertNil(
            previewState.commit(goalTitle: "Prepare for the MCAT", focusAreas: "")
        )
        XCTAssertNil(previewState.commit(goalTitle: "", focusAreas: ""))
        XCTAssertNotNil(
            previewState.commit(goalTitle: "Prepare for the MCAT", focusAreas: "")
        )

        var livePreviewState = GoalSetupDirectionPreviewState()
        livePreviewState.preview(
            goalTitle: "Prepare for the MCAT",
            focusAreas: "biology, chemistry"
        )
        XCTAssertEqual(livePreviewState.presentation?.topics, ["biology", "chemistry"])
        XCTAssertNil(livePreviewState.lastAnnouncement)
        XCTAssertNotNil(
            livePreviewState.commit(
                goalTitle: "Prepare for the MCAT",
                focusAreas: "biology, chemistry"
            ),
            "A silent live preview must not consume the later VoiceOver announcement."
        )

        let committedPresentation = try XCTUnwrap(livePreviewState.presentation)
        var existingGoalPreviewState = GoalSetupDirectionPreviewState(
            initialPresentation: committedPresentation,
            initialPresentationIsCommitted: true
        )
        XCTAssertEqual(
            existingGoalPreviewState.lastAnnouncement,
            committedPresentation.accessibilityAnnouncement
        )
        XCTAssertNil(
            existingGoalPreviewState.commit(
                goalTitle: "Prepare for the MCAT",
                focusAreas: "biology, chemistry"
            ),
            "Leaving an unchanged edit field must not announce a false update."
        )
    }

    func testCustomizationSummaryIsCompactAndCanonical() {
        XCTAssertEqual(
            GoalSetupCustomizationSummary(
                focusAreas: "none, asdf, ???",
                hasCurrentLevel: false,
                sourceDocumentCount: 0,
                minimumQuestionDifficulty: UnlockPolicy.default.minimumQuestionDifficulty
            ).text,
            "Automatic"
        )
        XCTAssertEqual(
            GoalSetupCustomizationSummary(
                focusAreas: "arrays, recursion, communication",
                hasCurrentLevel: false,
                sourceDocumentCount: 1,
                minimumQuestionDifficulty: 2
            ).text,
            "3 topics · 1 source · Level 2"
        )
        XCTAssertEqual(
            GoalSetupCustomizationSummary(
                focusAreas: "contracts",
                hasCurrentLevel: true,
                sourceDocumentCount: 2,
                minimumQuestionDifficulty: 1
            ).text,
            "1 topic · Experience noted · 2 sources"
        )
    }

    func testGoalSetupMotionPolicyHonorsReduceMotion() {
        let standard = GoalSetupMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .animated)
        XCTAssertNotNil(standard.animation)
        XCTAssertNotNil(standard.revealAnimation)

        let reduced = GoalSetupMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
        XCTAssertNil(reduced.revealAnimation)
        XCTAssertNil(reduced.previewAnimation(wasVisible: false, isVisible: true))

        XCTAssertNotNil(standard.previewAnimation(wasVisible: false, isVisible: true))
        XCTAssertNotNil(standard.previewAnimation(wasVisible: true, isVisible: true))

        let input = GoalSetupDirectionInput(
            goalTitle: "Prepare for the MCAT",
            focusAreas: "biology"
        )
        XCTAssertNotEqual(
            GoalSetupDirectionPreviewTaskID(input: input, reduceMotion: false),
            GoalSetupDirectionPreviewTaskID(input: input, reduceMotion: true),
            "Changing Reduce Motion must cancel and re-key a pending preview."
        )
    }

    func testEditModePreservesAnExistingQuestionStyle() {
        let legacyGoal = Goal(
            title: "Practice code tracing",
            deadline: Date().addingTimeInterval(86_400 * 30),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "loops, state mutation",
            preferredQuestionStyle: .codeTrace
        )

        XCTAssertEqual(
            GoalSetupMode.editGoal.preferredQuestionStyle(from: legacyGoal),
            .codeTrace
        )
        XCTAssertEqual(
            GoalSetupMode.firstGoal.preferredQuestionStyle(from: legacyGoal),
            .multipleChoice
        )
        XCTAssertEqual(
            GoalSetupMode.newGoal.preferredQuestionStyle(from: legacyGoal),
            .multipleChoice
        )

        let baseline = GoalSetupEditBaseline(goal: legacyGoal)
        XCTAssertEqual(
            GoalSetupEditImpact(
                baseline: baseline,
                title: legacyGoal.title,
                deadline: legacyGoal.deadline,
                currentLevel: legacyGoal.currentLevel,
                focusAreas: legacyGoal.focusAreas,
                sourceDocuments: legacyGoal.sourceDocuments,
                preferredQuestionStyle: GoalSetupMode.editGoal.preferredQuestionStyle(
                    from: legacyGoal
                ),
                minimumQuestionDifficulty: legacyGoal.minimumQuestionDifficulty
            ),
            .none
        )
    }

    @MainActor
    func testGoalSetupKeepsPrimaryInputInTheFirstFold() throws {
        let fixtures = [
            GoalSetupFirstFoldFixture(
                name: "goal-setup-first-fold-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                requiresFullyVisibleField: true,
                persistenceRecoveryMessage: "Checkpoint recovered an earlier version after the latest saved app data could not be read. Review the goal before continuing."
            ),
            GoalSetupFirstFoldFixture(
                name: "goal-setup-first-fold-accessibility5",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                requiresFullyVisibleField: false
            ),
            GoalSetupFirstFoldFixture(
                name: "goal-setup-first-fold-accessibility5-working",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                requiresFullyVisibleField: false,
                workingStateOverride: true
            ),
        ]

        for fixture in fixtures {
            let suiteName = "GoalSetupFirstFold.\(fixture.name).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = CheckpointStore(defaults: defaults)
            store.persistenceRecoveryMessage = fixture.persistenceRecoveryMessage
            let workflow = CheckpointWorkflowCoordinator(
                store: store,
                protection: InertGoalSetupProtectionController()
            )
            let capture = GoalSetupLayoutCapture()
            let image = HostedViewRenderer.image(
                for: OnboardingView(
                    store: store,
                    workflow: workflow,
                    reduceMotionOverride: true,
                    workingStateOverride: fixture.workingStateOverride,
                    layoutReporter: { element, frame in
                        capture.frames[element] = frame
                    }
                )
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: 0.15,
                renderScale: 1
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)

            let viewport = try XCTUnwrap(capture.frames[.viewport], fixture.name)
            let hero = try XCTUnwrap(capture.frames[.hero], fixture.name)
            let goalPanel = try XCTUnwrap(capture.frames[.goalPanel], fixture.name)
            let titleLabel = try XCTUnwrap(capture.frames[.titleLabel], fixture.name)
            let titleField = try XCTUnwrap(capture.frames[.titleField], fixture.name)
            let actionBar = try XCTUnwrap(capture.frames[.actionBar], fixture.name)
            let contentFrames = [hero, goalPanel, titleLabel, titleField]
            let canvas = CGRect(
                x: 0,
                y: 0,
                width: fixture.width,
                height: fixture.height
            )

            for frame in [viewport, actionBar] + contentFrames {
                XCTAssertFalse(frame.isNull, fixture.name)
                XCTAssertFalse(frame.isInfinite, fixture.name)
                XCTAssertGreaterThan(frame.width, 0, fixture.name)
                XCTAssertGreaterThan(frame.height, 0, fixture.name)
            }
            for frame in contentFrames {
                XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 0.5, fixture.name)
                XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 0.5, fixture.name)
            }
            XCTAssertTrue(
                canvas.insetBy(dx: -0.5, dy: -0.5).contains(actionBar),
                "\(fixture.name) action bar escaped the rendered screen"
            )
            XCTAssertGreaterThanOrEqual(titleField.height, 43.5, fixture.name)
            XCTAssertGreaterThanOrEqual(actionBar.height, 43.5, fixture.name)
            XCTAssertLessThanOrEqual(hero.maxY, goalPanel.minY + 0.5, fixture.name)
            XCTAssertTrue(
                goalPanel.insetBy(dx: -0.5, dy: -0.5).contains(titleLabel),
                "\(fixture.name) title label escaped the goal panel"
            )
            XCTAssertTrue(
                goalPanel.insetBy(dx: -0.5, dy: -0.5).contains(titleField),
                "\(fixture.name) title field escaped the goal panel"
            )
            XCTAssertLessThanOrEqual(titleLabel.maxY, titleField.minY + 0.5, fixture.name)

            let visibleBottom = min(viewport.maxY, actionBar.minY)
            let visibleViewport = CGRect(
                x: viewport.minX,
                y: viewport.minY,
                width: viewport.width,
                height: max(0, visibleBottom - viewport.minY)
            )
            XCTAssertGreaterThan(visibleViewport.height, 0, fixture.name)

            if fixture.requiresFullyVisibleField {
                XCTAssertTrue(
                    visibleViewport.insetBy(dx: -0.5, dy: -0.5).contains(titleField),
                    "\(fixture.name) pushed the primary input below the first fold"
                )
                let optionalDetails = try XCTUnwrap(capture.frames[.optionalDetails], fixture.name)
                XCTAssertTrue(
                    visibleViewport.insetBy(dx: -0.5, dy: -0.5).contains(optionalDetails),
                    "\(fixture.name) hid the optional context/file entry below the first fold"
                )
            } else {
                let visibleTitleField = titleField.intersection(visibleViewport)
                XCTAssertFalse(visibleTitleField.isNull, fixture.name)
                XCTAssertGreaterThanOrEqual(
                    visibleTitleField.height,
                    44,
                    "\(fixture.name) left less than one accessible tap row of the input visible"
                )
            }

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = XCTAttachment.Lifetime.keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testGoalSetupSurfacesRenderAcrossPremiumLayouts() throws {
        var defaultsSuites: [String] = []
        defer {
            for suite in defaultsSuites {
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
        }

        func makeStore(_ suffix: String) throws -> CheckpointStore {
            let suite = "GoalSetupPresentationTests.\(suffix).\(UUID().uuidString)"
            defaultsSuites.append(suite)
            return CheckpointStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        }

        let firstStore = try makeStore("first")

        let newStore = try makeStore("new")
        let existingGoal = Goal(
            title: "Build a reliable morning routine",
            deadline: Date().addingTimeInterval(86_400 * 60),
            category: .custom,
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice
        )
        newStore.goal = existingGoal
        newStore.goalProfiles = [existingGoal]
        newStore.isCreatingGoalProfile = true

        let editStore = try makeStore("edit")
        let source = GoalSourceDocument(
            name: "Interview rubric.txt",
            text: "The rubric emphasizes clear tradeoffs, capacity estimates, reliability, and concise communication."
        )
        let editGoal = Goal(
            title: "Lead a senior distributed systems design interview with clear tradeoff reasoning",
            deadline: Date().addingTimeInterval(86_400 * 45),
            category: .codingInterview,
            currentLevel: "Comfortable with APIs; still building confidence with distributed systems",
            focusAreas: "capacity planning, none, data consistency, failure recovery",
            sourceDocuments: [source],
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        editStore.goal = editGoal
        editStore.goalProfiles = [editGoal]

        let firstWorkflow = CheckpointWorkflowCoordinator(
            store: firstStore,
            protection: InertGoalSetupProtectionController()
        )
        let newWorkflow = CheckpointWorkflowCoordinator(
            store: newStore,
            protection: InertGoalSetupProtectionController()
        )
        let editWorkflow = CheckpointWorkflowCoordinator(
            store: editStore,
            protection: InertGoalSetupProtectionController()
        )

        let fixtures = [
            GoalSetupRenderFixture(
                name: "goal-setup-first-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    OnboardingView(
                        store: firstStore,
                        workflow: firstWorkflow,
                        reduceMotionOverride: true
                    )
                )
            ),
            GoalSetupRenderFixture(
                name: "goal-setup-new-standard-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    OnboardingView(
                        store: newStore,
                        workflow: newWorkflow,
                        reduceMotionOverride: true
                    )
                )
            ),
            GoalSetupRenderFixture(
                name: "goal-setup-edit-customized-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    OnboardingView(
                        store: editStore,
                        workflow: editWorkflow,
                        reduceMotionOverride: true
                    )
                )
            ),
            GoalSetupRenderFixture(
                name: "goal-setup-edit-customized-ax2-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    OnboardingView(
                        store: editStore,
                        workflow: editWorkflow,
                        reduceMotionOverride: true
                    )
                )
            ),
            GoalSetupRenderFixture(
                name: "goal-setup-edit-customized-ax5-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    OnboardingView(
                        store: editStore,
                        workflow: editWorkflow,
                        reduceMotionOverride: true
                    )
                )
            ),
            GoalSetupRenderFixture(
                name: "goal-setup-ready-ax5-reduced-motion",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    GoalSetupHeroScene(
                        presentation: GoalSetupHeroPresentation(
                            mode: .firstGoal,
                            hasGoalTitle: true,
                            isWorking: false
                        )
                    )
                )
            ),
            GoalSetupRenderFixture(
                name: "goal-setup-inferred-direction-ax5-reduced-motion",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                content: AnyView(GoalSetupInferredDirectionScene())
            ),
            GoalSetupRenderFixture(
                name: "goal-setup-explicit-topics-ax5-reduced-motion",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                content: AnyView(GoalSetupExplicitTopicsScene())
            ),
            GoalSetupRenderFixture(
                name: "goal-setup-unsaved-ax5-reduced-motion",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    GoalSetupHeroScene(
                        presentation: GoalSetupHeroPresentation(
                            mode: .editGoal,
                            hasGoalTitle: true,
                            editImpact: .practiceSetup,
                            isWorking: false
                        )
                    )
                )
            ),
            GoalSetupRenderFixture(
                name: "goal-setup-working-ax5-reduced-motion",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    GoalSetupHeroScene(
                        presentation: GoalSetupHeroPresentation(
                            mode: .newGoal,
                            hasGoalTitle: true,
                            isWorking: true
                        )
                    )
                )
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: fixture.content
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                renderScale: 1
            )
            XCTAssertEqual(image.size.width, fixture.width)
            XCTAssertEqual(image.size.height, fixture.height)

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = XCTAttachment.Lifetime.keepAlways
            add(attachment)
        }
    }
}

private struct GoalSetupRenderFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let content: AnyView
}

private struct GoalSetupFirstFoldFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let requiresFullyVisibleField: Bool
    let persistenceRecoveryMessage: String?
    let workingStateOverride: Bool?

    init(
        name: String,
        width: CGFloat,
        height: CGFloat,
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize,
        requiresFullyVisibleField: Bool,
        persistenceRecoveryMessage: String? = nil,
        workingStateOverride: Bool? = nil
    ) {
        self.name = name
        self.width = width
        self.height = height
        self.colorScheme = colorScheme
        self.dynamicTypeSize = dynamicTypeSize
        self.requiresFullyVisibleField = requiresFullyVisibleField
        self.persistenceRecoveryMessage = persistenceRecoveryMessage
        self.workingStateOverride = workingStateOverride
    }
}

@MainActor
private final class GoalSetupLayoutCapture {
    var frames: [GoalSetupLayoutElement: CGRect] = [:]
}

@MainActor
private final class InertGoalSetupProtectionController: AppProtectionControlling {
    let hasSelection = false
    let isShieldingEnabled = false
    let userFacingErrorMessage: String? = nil

    func applyShield() {}

    func clearShield() {}

    func temporarilyUnshield(until expiration: Date) -> Bool {
        true
    }

    func reconcileShieldState(protectionShouldRemainActive: Bool?) {}

    func refreshActiveShieldConfiguration() {}
}

private struct GoalSetupInferredDirectionScene: View {
    var body: some View {
        ScrollView {
            if let direction = GoalSetupDirectionPresentation(
                goalTitle: "Prepare for an advanced systems design interview with thoughtful tradeoff analysis",
                focusAreas: ""
            ) {
                GoalSetupDirectionCard(
                    presentation: direction,
                    reduceMotionOverride: true
                )
                    .padding(16)
            }
        }
        .checkpointScreenBackground()
    }
}

private struct GoalSetupExplicitTopicsScene: View {
    var body: some View {
        ScrollView {
            if let direction = GoalSetupDirectionPresentation(
                goalTitle: "Pass technical interviews",
                focusAreas: "capacity planning, data consistency, graceful failure recovery"
            ) {
                GoalSetupDirectionCard(
                    presentation: direction,
                    reduceMotionOverride: true
                )
                    .padding(16)
            }
        }
        .checkpointScreenBackground()
    }
}

private struct GoalSetupHeroScene: View {
    let presentation: GoalSetupHeroPresentation

    var body: some View {
        ScrollView {
            GoalSetupHero(presentation: presentation, reduceMotion: true)
                .padding(16)
        }
        .checkpointScreenBackground()
    }
}
