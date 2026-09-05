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

    // MARK: - First-run setup durability

    func testAppUsesOneSceneForSingleOwnerWorkflowHandoffs() throws {
        let sceneManifest = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest")
                as? [String: Any]
        )

        XCTAssertEqual(
            sceneManifest["UIApplicationSupportsMultipleScenes"] as? Bool,
            false
        )
    }

    func testPendingFirstRunAppSelectionSurvivesRelaunchAndResumesRouting() throws {
        FirstRunSetupProgress.begin(defaults: defaults)

        let relaunchedDefaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        let isPendingAfterRelaunch = FirstRunSetupProgress.isPending(defaults: relaunchedDefaults)

        XCTAssertTrue(isPendingAfterRelaunch)
        XCTAssertTrue(
            FirstRunSetupProgress.shouldResumeAppSelection(
                isPending: isPendingAfterRelaunch,
                hasGoal: true,
                isAuthorized: true,
                isOnboardingPresented: false
            )
        )
    }

    func testFirstGoalSuccessHandoffIssuesAndConsumesAnExactGoalOnce() throws {
        let goalID = UUID()
        var queue = FirstGoalSuccessHandoffQueue()

        XCTAssertFalse(
            queue.issue(
                goalID: goalID,
                goalTitle: "Pass the bar exam",
                isFirstRunSetupPending: false
            ),
            "An ephemeral cue must never precede durable first-run setup."
        )
        XCTAssertTrue(
            queue.issue(
                goalID: goalID,
                goalTitle: "  Pass the bar exam  ",
                isFirstRunSetupPending: true
            )
        )
        let token = try XCTUnwrap(queue.pendingToken)
        XCTAssertEqual(token.id, token.deliveryID)
        XCTAssertEqual(token.goalID, goalID)
        XCTAssertEqual(token.goalTitle, "Pass the bar exam")
        XCTAssertTrue(token.accessibilityAnnouncement.contains("Step 3 of 3"))

        XCTAssertFalse(
            queue.issue(
                goalID: goalID,
                goalTitle: "Duplicate callback",
                isFirstRunSetupPending: true
            )
        )

        let abandonedGoalID = UUID()
        var abandonedQueue = FirstGoalSuccessHandoffQueue()
        XCTAssertTrue(
            abandonedQueue.issue(
                goalID: abandonedGoalID,
                goalTitle: "Try meditation",
                isFirstRunSetupPending: true
            )
        )
        abandonedQueue.discardPending()
        XCTAssertNil(abandonedQueue.pendingToken)
        XCTAssertTrue(abandonedQueue.deliveredGoalIDs.isEmpty)
        XCTAssertTrue(
            abandonedQueue.issue(
                goalID: abandonedGoalID,
                goalTitle: "Try meditation",
                isFirstRunSetupPending: true
            ),
            "Terminal cleanup discards an unseen cue without falsely marking it delivered."
        )
        XCTAssertEqual(queue.pendingToken, token)

        let wrongToken = FirstGoalSuccessHandoffToken(
            goalID: UUID(),
            goalTitle: "A different goal"
        )
        XCTAssertFalse(queue.consume(wrongToken))
        XCTAssertEqual(queue.pendingToken, token)
        let wrongRevision = FirstGoalSuccessHandoffToken(
            goalID: goalID,
            goalTitle: token.goalTitle
        )
        XCTAssertNotEqual(wrongRevision.deliveryID, token.deliveryID)
        XCTAssertFalse(queue.consume(wrongRevision))
        XCTAssertEqual(queue.pendingToken, token)

        XCTAssertTrue(queue.consume(token))
        XCTAssertNil(queue.pendingToken)
        XCTAssertTrue(queue.deliveredGoalIDs.contains(goalID))
        XCTAssertFalse(queue.consume(token))
        XCTAssertFalse(
            queue.issue(
                goalID: goalID,
                goalTitle: token.goalTitle,
                isFirstRunSetupPending: true
            )
        )
    }

    func testFirstGoalSuccessHandoffInvalidatesWhenTheCurrentGoalChanges() throws {
        let originalGoalID = UUID()
        let replacementGoalID = UUID()
        var queue = FirstGoalSuccessHandoffQueue()

        XCTAssertTrue(
            queue.issue(
                goalID: originalGoalID,
                goalTitle: "Learn Swift",
                isFirstRunSetupPending: true
            )
        )
        queue.invalidate(unless: originalGoalID)
        XCTAssertEqual(queue.pendingToken?.goalID, originalGoalID)

        queue.invalidate(unless: replacementGoalID)
        XCTAssertNil(queue.pendingToken)

        XCTAssertTrue(
            queue.issue(
                goalID: replacementGoalID,
                goalTitle: "Learn Rust",
                isFirstRunSetupPending: true
            )
        )
        queue.invalidate(unless: nil)
        XCTAssertNil(queue.pendingToken)
    }

    func testFirstGoalSuccessHandoffDeliverySurvivesParentConsumptionWithoutReplaying() throws {
        let firstToken = FirstGoalSuccessHandoffToken(
            goalID: UUID(),
            goalTitle: "Prepare for the MCAT"
        )
        var delivery = FirstGoalSuccessHandoffDeliveryState(token: firstToken)
        let firstContext = FirstGoalSuccessHandoffDeliveryContext(
            activeGoalID: firstToken.goalID,
            phase: .selecting,
            isAuthorized: true,
            errorMessage: nil,
            isExposed: true
        )

        XCTAssertEqual(delivery.candidateForDelivery, firstToken)
        XCTAssertNil(delivery.presentedToken)
        let firstEffect = try XCTUnwrap(
            delivery.attemptDelivery(in: firstContext) { $0 == firstToken }
        )
        XCTAssertEqual(firstEffect.token, firstToken)
        XCTAssertEqual(firstEffect.revealSequenceIncrement, 1)
        XCTAssertEqual(firstEffect.successFeedbackSequenceIncrement, 1)
        XCTAssertEqual(
            firstEffect.accessibilityAnnouncement,
            firstToken.accessibilityAnnouncement
        )
        XCTAssertNil(delivery.pendingToken)
        XCTAssertEqual(delivery.presentedToken, firstToken)
        XCTAssertNil(delivery.candidateForDelivery)

        delivery.receive(nil)
        XCTAssertEqual(
            delivery.presentedToken,
            firstToken,
            "Clearing the parent queue must not erase the destination's visible success copy."
        )
        delivery.receive(firstToken)
        XCTAssertNil(delivery.candidateForDelivery)

        let nextToken = FirstGoalSuccessHandoffToken(
            goalID: UUID(),
            goalTitle: "Build a morning routine"
        )
        delivery.receive(nextToken)
        XCTAssertEqual(delivery.candidateForDelivery, nextToken)
        XCTAssertEqual(
            delivery.attemptDelivery(
                in: FirstGoalSuccessHandoffDeliveryContext(
                    activeGoalID: nextToken.goalID,
                    phase: .selecting,
                    isAuthorized: true,
                    errorMessage: nil,
                    isExposed: true
                ),
                authoritativeConsume: { $0 == nextToken }
            )?.token,
            nextToken
        )
        XCTAssertEqual(delivery.presentedToken, nextToken)
        XCTAssertNil(delivery.candidateForDelivery)

        let staleToken = FirstGoalSuccessHandoffToken(
            goalID: UUID(),
            goalTitle: "A stale goal"
        )
        var rejectedDelivery = FirstGoalSuccessHandoffDeliveryState(token: staleToken)
        XCTAssertNil(
            rejectedDelivery.attemptDelivery(
                in: FirstGoalSuccessHandoffDeliveryContext(
                    activeGoalID: staleToken.goalID,
                    phase: .selecting,
                    isAuthorized: true,
                    errorMessage: nil,
                    isExposed: true
                ),
                authoritativeConsume: { _ in false }
            )
        )
        XCTAssertNil(rejectedDelivery.pendingToken)
        XCTAssertNil(rejectedDelivery.presentedToken)
        XCTAssertNil(rejectedDelivery.candidateForDelivery)
        rejectedDelivery.receive(staleToken)
        XCTAssertNil(
            rejectedDelivery.candidateForDelivery,
            "An authoritative rejection resolves the stale token without retrying it."
        )
        let correctedToken = FirstGoalSuccessHandoffToken(
            goalID: staleToken.goalID,
            goalTitle: "A corrected handoff"
        )
        rejectedDelivery.receive(correctedToken)
        XCTAssertEqual(
            rejectedDelivery.attemptDelivery(
                in: FirstGoalSuccessHandoffDeliveryContext(
                    activeGoalID: correctedToken.goalID,
                    phase: .selecting,
                    isAuthorized: true,
                    errorMessage: nil,
                    isExposed: true
                ),
                authoritativeConsume: { $0 == correctedToken }
            )?.token,
            correctedToken,
            "A rejected delivery identity must not poison a corrected cue for the same goal."
        )

        var mismatchedDelivery = FirstGoalSuccessHandoffDeliveryState(token: staleToken)
        var mismatchedConsumptionAttempts = 0
        XCTAssertNil(
            mismatchedDelivery.attemptDelivery(
                in: FirstGoalSuccessHandoffDeliveryContext(
                    activeGoalID: UUID(),
                    phase: .selecting,
                    isAuthorized: true,
                    errorMessage: nil,
                    isExposed: true
                ),
                authoritativeConsume: { _ in
                    mismatchedConsumptionAttempts += 1
                    return true
                }
            )
        )
        XCTAssertNil(mismatchedDelivery.pendingToken)
        XCTAssertNil(mismatchedDelivery.presentedToken)
        XCTAssertNil(mismatchedDelivery.candidateForDelivery)
        XCTAssertEqual(mismatchedConsumptionAttempts, 0)
        mismatchedDelivery.receive(staleToken)
        XCTAssertNil(
            mismatchedDelivery.attemptDelivery(
                in: FirstGoalSuccessHandoffDeliveryContext(
                    activeGoalID: staleToken.goalID,
                    phase: .selecting,
                    isAuthorized: true,
                    errorMessage: nil,
                    isExposed: true
                ),
                authoritativeConsume: { _ in
                    mismatchedConsumptionAttempts += 1
                    return true
                }
            ),
            "A token first seen against another goal must not become deliverable later."
        )
        XCTAssertEqual(mismatchedConsumptionAttempts, 0)
    }

    func testFirstGoalSuccessHandoffEmitsOneCompleteEffectAfterEligibilityRekeys() throws {
        let token = FirstGoalSuccessHandoffToken(
            goalID: UUID(),
            goalTitle: "Ship the portfolio"
        )

        for reduceMotion in [false, true] {
            var delivery = FirstGoalSuccessHandoffDeliveryState(token: token)
            var effects: [FirstGoalSuccessHandoffDeliveryEffect] = []
            var consumptionAttempts = 0

            XCTAssertNil(
                delivery.attemptDelivery(
                    in: FirstGoalSuccessHandoffDeliveryContext(
                        activeGoalID: nil,
                        phase: .selecting,
                        isAuthorized: true,
                        errorMessage: nil,
                        isExposed: true
                    ),
                    authoritativeConsume: { _ in
                        consumptionAttempts += 1
                        return true
                    }
                ),
                "A temporarily unavailable goal identity should defer delivery."
            )
            XCTAssertNil(
                delivery.attemptDelivery(
                    in: FirstGoalSuccessHandoffDeliveryContext(
                        activeGoalID: token.goalID,
                        phase: .selecting,
                        isAuthorized: false,
                        errorMessage: nil,
                        isExposed: true
                    ),
                    authoritativeConsume: { _ in
                        consumptionAttempts += 1
                        return true
                    }
                )
            )
            XCTAssertNil(
                delivery.attemptDelivery(
                    in: FirstGoalSuccessHandoffDeliveryContext(
                        activeGoalID: token.goalID,
                        phase: .selecting,
                        isAuthorized: true,
                        errorMessage: "Screen Time access changed.",
                        isExposed: true
                    ),
                    authoritativeConsume: { _ in
                        consumptionAttempts += 1
                        return true
                    }
                )
            )
            XCTAssertNil(
                delivery.attemptDelivery(
                    in: FirstGoalSuccessHandoffDeliveryContext(
                        activeGoalID: token.goalID,
                        phase: .preparing(selectionSummary: "1 app selected"),
                        isAuthorized: true,
                        errorMessage: nil,
                        isExposed: true
                    ),
                    authoritativeConsume: { _ in
                        consumptionAttempts += 1
                        return true
                    }
                )
            )
            XCTAssertNil(
                delivery.attemptDelivery(
                    in: FirstGoalSuccessHandoffDeliveryContext(
                        activeGoalID: token.goalID,
                        phase: .selecting,
                        isAuthorized: true,
                        errorMessage: nil,
                        isExposed: false
                    ),
                    authoritativeConsume: { _ in
                        consumptionAttempts += 1
                        return true
                    }
                ),
                "A covered destination should preserve its one visible effect until exposure."
            )

            if let effect = delivery.attemptDelivery(
                in: FirstGoalSuccessHandoffDeliveryContext(
                    activeGoalID: token.goalID,
                    phase: .selecting,
                    isAuthorized: true,
                    errorMessage: nil,
                    isExposed: true
                ),
                authoritativeConsume: { candidate in
                    consumptionAttempts += 1
                    return candidate == token
                }
            ) {
                effects.append(effect)
            }

            delivery.receive(nil)
            delivery.receive(token)
            if let repeatedEffect = delivery.attemptDelivery(
                in: FirstGoalSuccessHandoffDeliveryContext(
                    activeGoalID: token.goalID,
                    phase: .selecting,
                    isAuthorized: true,
                    errorMessage: nil,
                    isExposed: true
                ),
                authoritativeConsume: { _ in
                    consumptionAttempts += 1
                    return true
                }
            ) {
                effects.append(repeatedEffect)
            }

            XCTAssertEqual(consumptionAttempts, 1)
            XCTAssertEqual(effects.count, 1)
            XCTAssertEqual(effects.first?.token, token)
            XCTAssertEqual(effects.first?.revealSequenceIncrement, 1)
            XCTAssertEqual(effects.first?.successFeedbackSequenceIncrement, 1)
            XCTAssertEqual(
                effects.first?.accessibilityAnnouncement,
                token.accessibilityAnnouncement
            )
            XCTAssertEqual(
                FirstGoalSuccessHandoffMotionPolicy(reduceMotion: reduceMotion).style,
                reduceMotion ? .identity : .reveal,
                "Reduce Motion changes animation style, not delivery-effect cardinality."
            )
        }
    }

    func testFirstGoalSuccessHandoffWaitsForActiveUncoveredSceneAndNeverReplays() throws {
        let token = FirstGoalSuccessHandoffToken(
            goalID: UUID(),
            goalTitle: "Finish the portfolio"
        )
        var delivery = FirstGoalSuccessHandoffDeliveryState(token: token)
        var consumptionAttempts = 0
        var effects: [FirstGoalSuccessHandoffDeliveryEffect] = []

        func context(isSceneActive: Bool) -> FirstGoalSuccessHandoffDeliveryContext {
            FirstGoalSuccessHandoffDeliveryContext(
                activeGoalID: token.goalID,
                phase: .selecting,
                isAuthorized: true,
                errorMessage: nil,
                isExposed: FirstGoalSuccessHandoffExposure.allowsDelivery(
                    isSceneActive: isSceneActive,
                    blocksUnderlyingPresentations: false
                )
            )
        }

        XCTAssertFalse(
            FirstGoalSuccessHandoffExposure.allowsDelivery(
                isSceneActive: true,
                blocksUnderlyingPresentations: true
            )
        )
        XCTAssertNil(
            delivery.attemptDelivery(in: context(isSceneActive: false)) { _ in
                consumptionAttempts += 1
                return true
            },
            "An inactive but otherwise uncovered scene must preserve the one-shot effect."
        )

        if let effect = delivery.attemptDelivery(in: context(isSceneActive: true)) { candidate in
            consumptionAttempts += 1
            return candidate == token
        } {
            effects.append(effect)
        }

        XCTAssertNil(
            delivery.attemptDelivery(in: context(isSceneActive: false)) { _ in
                consumptionAttempts += 1
                return true
            }
        )
        XCTAssertNil(
            delivery.attemptDelivery(in: context(isSceneActive: true)) { _ in
                consumptionAttempts += 1
                return true
            },
            "A second background/foreground cycle must not replay the delivered effect."
        )
        XCTAssertEqual(consumptionAttempts, 1)
        XCTAssertEqual(effects, [FirstGoalSuccessHandoffDeliveryEffect(token: token)])
    }

    func testDurableResumeDoesNotInventAnEphemeralSuccessHandoff() {
        FirstRunSetupProgress.begin(defaults: defaults)
        let relaunchedQueue = FirstGoalSuccessHandoffQueue()

        XCTAssertTrue(FirstRunSetupProgress.isPending(defaults: defaults))
        XCTAssertNil(relaunchedQueue.pendingToken)
    }

    @MainActor
    func testFailedFirstRunProtectionStartKeepsSetupPending() async {
        FirstRunSetupProgress.begin(defaults: defaults)

        let didComplete = await FirstRunSetupProgress.completeAfterStartingProtection(
            defaults: defaults,
            startProtection: { false }
        )

        XCTAssertFalse(didComplete)
        XCTAssertTrue(FirstRunSetupProgress.isPending(defaults: defaults))
    }

    @MainActor
    func testSuccessfulFirstRunProtectionStartClearsPendingStateAcrossRelaunch() async throws {
        FirstRunSetupProgress.begin(defaults: defaults)

        let didComplete = await FirstRunSetupProgress.completeAfterStartingProtection(
            defaults: defaults,
            startProtection: { true }
        )
        let relaunchedDefaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))

        XCTAssertTrue(didComplete)
        XCTAssertFalse(FirstRunSetupProgress.isPending(defaults: relaunchedDefaults))
    }

    // MARK: - Protection and break transitions

    @MainActor
    func testReadyProtectionStartAppliesShieldOnce() async throws {
        let store = makeStore(questionCount: 5)
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let started = await workflow.startProtection()

        XCTAssertTrue(started)
        XCTAssertEqual(protection.applyShieldCount, 1)
        let result = try XCTUnwrap(workflow.pendingProtectionStartResult)
        XCTAssertEqual(result.goalID, store.goal?.id)
        XCTAssertFalse(result.becameCheckpointReadyDuringStart)
        XCTAssertTrue(result.didStart)
        XCTAssertNil(result.checkpointNotice)
        XCTAssertNil(result.protectionErrorMessage)
        XCTAssertNil(workflow.takePendingProtectionStartResult(id: UUID()))
        XCTAssertEqual(
            workflow.takePendingProtectionStartResult(id: result.id),
            result
        )
        XCTAssertNil(workflow.pendingProtectionStartResult)
        XCTAssertNil(workflow.takePendingProtectionStartResult(id: result.id))
    }

    @MainActor
    func testUnreadyProtectionStartDoesNotApplyShield() async throws {
        let store = makeStore(questionCount: 0)
        store.questionBatchState = .generating
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let started = await workflow.startProtection()

        XCTAssertFalse(started)
        XCTAssertEqual(protection.applyShieldCount, 0)
        let result = try XCTUnwrap(workflow.pendingProtectionStartResult)
        XCTAssertEqual(result.goalID, store.goal?.id)
        XCTAssertFalse(result.becameCheckpointReadyDuringStart)
        XCTAssertFalse(result.didStart)
        XCTAssertEqual(result.checkpointNotice, store.checkpointNotice)
        XCTAssertNil(result.protectionErrorMessage)
    }

    @MainActor
    func testProtectionStartRecordsWhenItGeneratesCheckpointReadiness() async throws {
        let appleEngine = TargetCountQuestionEngine(provider: .appleFoundation)
        let store = makeStore(
            questionCount: 0,
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: appleEngine
            )
        )
        store.updateAIProviderPreference(.appleFoundation)
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let started = await workflow.startProtection()

        XCTAssertTrue(started)
        XCTAssertTrue(store.hasReadyCheckpointSet)
        XCTAssertEqual(protection.applyShieldCount, 1)
        let result = try XCTUnwrap(workflow.pendingProtectionStartResult)
        XCTAssertEqual(result.goalID, store.goal?.id)
        XCTAssertTrue(result.becameCheckpointReadyDuringStart)
        XCTAssertTrue(result.didStart)
        XCTAssertNil(workflow.startingProtectionReadinessGoalID)
        XCTAssertFalse(appleEngine.receivedRequests.isEmpty)
    }

    @MainActor
    func testRepeatedIdenticalStartFailuresPublishDistinctLatestResult() async throws {
        let store = makeStore(questionCount: 0)
        store.questionBatchState = .generating
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let firstDidStart = await workflow.startProtection()
        XCTAssertFalse(firstDidStart)
        let firstResult = try XCTUnwrap(workflow.pendingProtectionStartResult)
        let secondDidStart = await workflow.startProtection()
        XCTAssertFalse(secondDidStart)
        let secondResult = try XCTUnwrap(workflow.pendingProtectionStartResult)

        XCTAssertNotEqual(firstResult.id, secondResult.id)
        XCTAssertEqual(firstResult.checkpointNotice, secondResult.checkpointNotice)
        XCTAssertNil(workflow.takePendingProtectionStartResult(id: firstResult.id))
        XCTAssertEqual(
            workflow.takePendingProtectionStartResult(id: secondResult.id),
            secondResult
        )
    }

    @MainActor
    func testProtectionStartResultDeliveryClaimsOnceForEveryOwnerOrder() async throws {
        let surfaceNames = ["Home", "Settings", "Progress"]

        for ownerIndex in surfaceNames.indices {
            let store = makeStore(questionCount: 5)
            let protection = FakeAppProtectionController()
            let workflow = CheckpointWorkflowCoordinator(
                store: store,
                protection: protection
            )
            let didStart = await workflow.startProtection()
            XCTAssertTrue(didStart)
            var claimedResults: [ProtectionStartResultEvent] = []

            for callbackIndex in surfaceNames.indices {
                if let result = ProtectionStartResultDelivery.takeCurrent(
                    from: workflow,
                    isOwner: callbackIndex == ownerIndex,
                    currentGoalID: store.goal?.id,
                    isShieldingEnabled: protection.isShieldingEnabled,
                    protectionShouldRemainActive: true,
                    checkpointNotice: store.checkpointNotice,
                    protectionErrorMessage: protection.userFacingErrorMessage
                ) {
                    claimedResults.append(result)
                }
            }

            XCTAssertEqual(
                claimedResults.count,
                1,
                "Expected exactly one claim when \(surfaceNames[ownerIndex]) owns feedback."
            )
            XCTAssertNil(workflow.pendingProtectionStartResult)
            XCTAssertNil(
                ProtectionStartResultDelivery.takeCurrent(
                    from: workflow,
                    isOwner: true,
                    currentGoalID: store.goal?.id,
                    isShieldingEnabled: protection.isShieldingEnabled,
                    protectionShouldRemainActive: true,
                    checkpointNotice: store.checkpointNotice,
                    protectionErrorMessage: protection.userFacingErrorMessage
                )
            )
        }
    }

    @MainActor
    func testSequentialIdenticalStartFailuresAreEachClaimedOnce() async throws {
        let store = makeStore(questionCount: 0)
        store.questionBatchState = .generating
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)
        var claimedIDs: [UUID] = []

        for _ in 0..<2 {
            let didStart = await workflow.startProtection()
            XCTAssertFalse(didStart)
            let result = try XCTUnwrap(
                ProtectionStartResultDelivery.takeCurrent(
                    from: workflow,
                    isOwner: true,
                    currentGoalID: store.goal?.id,
                    isShieldingEnabled: protection.isShieldingEnabled,
                    protectionShouldRemainActive: false,
                    checkpointNotice: store.checkpointNotice,
                    protectionErrorMessage: protection.userFacingErrorMessage
                )
            )
            XCTAssertFalse(result.didStart)
            claimedIDs.append(result.id)
            XCTAssertNil(
                ProtectionStartResultDelivery.takeCurrent(
                    from: workflow,
                    isOwner: true,
                    currentGoalID: store.goal?.id,
                    isShieldingEnabled: protection.isShieldingEnabled,
                    protectionShouldRemainActive: false,
                    checkpointNotice: store.checkpointNotice,
                    protectionErrorMessage: protection.userFacingErrorMessage
                )
            )
        }

        XCTAssertEqual(Set(claimedIDs).count, 2)
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
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        workflow.reconcileProtectionState()

        XCTAssertFalse(store.hasReadyCheckpointSet)
        XCTAssertEqual(protection.applyShieldCount, 0)
        XCTAssertEqual(protection.clearShieldCount, 0)
        XCTAssertTrue(protection.isShieldingEnabled)
    }

    @MainActor
    func testConfirmedExitAbandonsRunAndStartsCooldown() throws {
        let store = makeStore(questionCount: 6)
        let session = try XCTUnwrap(store.startManualCheckpointSession())
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        XCTAssertTrue(workflow.abandon(session))

        XCTAssertNil(store.activeCheckpointRun)
        XCTAssertTrue(store.isCheckpointRetryCooldownActive)
        XCTAssertTrue(protection.isShieldingEnabled)
        XCTAssertEqual(protection.applyShieldCount, 1)
    }

    @MainActor
    func testConfirmedExitTurnsProtectionOffWhenNoFullRetryIsReady() throws {
        let store = makeStore(questionCount: 5)
        let session = try XCTUnwrap(store.startManualCheckpointSession())
        store.questions[0].status = .retired
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        XCTAssertFalse(store.hasReadyCheckpointSet)
        XCTAssertTrue(workflow.abandon(session))

        XCTAssertNil(store.activeCheckpointRun)
        XCTAssertTrue(store.isCheckpointRetryCooldownActive)
        XCTAssertFalse(protection.isShieldingEnabled)
        XCTAssertEqual(protection.clearShieldCount, 1)
        XCTAssertTrue(store.checkpointNotice?.contains("turned off") ?? false)
    }

    @MainActor
    func testFailedResolutionReturnsStableProtectionOutcomeWhenRetrySetRemainsReady() throws {
        let store = makeStore(questionCount: 10)
        let session = try XCTUnwrap(store.startManualCheckpointSession())
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let outcome = workflow.resolveFailed(session)

        XCTAssertEqual(outcome, .protectionRemainsOn)
        XCTAssertTrue(protection.isShieldingEnabled)
        XCTAssertNil(store.activeCheckpointRun)
    }

    @MainActor
    func testFailedResolutionReportsWhenUnavailableRetryTurnsProtectionOff() throws {
        let store = makeStore(questionCount: 5)
        let session = try XCTUnwrap(store.startManualCheckpointSession())
        store.questions[0].status = .retired
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let outcome = workflow.resolveFailed(session)

        XCTAssertEqual(outcome, .protectionTurnedOffForUnavailableCheckpoint)
        XCTAssertFalse(protection.isShieldingEnabled)
        XCTAssertEqual(protection.clearShieldCount, 1)
        XCTAssertNil(store.activeCheckpointRun)
    }

    @MainActor
    func testFailedStopReviewReportsThatActiveBreakContinues() throws {
        let store = makeStore(questionCount: StopBlockingPolicy.questionsPerSession)
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        store.startUnlockSession(minutes: 10)
        let session = try XCTUnwrap(store.startStopBlockingSession())
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let outcome = workflow.resolveFailed(session)

        XCTAssertEqual(outcome, .activeBreakContinues)
        XCTAssertEqual(protection.applyShieldCount, 1)
        XCTAssertTrue(store.unlockSession?.isActive == true)
        XCTAssertNil(store.activeCheckpointRun)
    }

    @MainActor
    func testPreviewExitDoesNotStartCooldownOrChangeProtection() throws {
        let store = makeStore(questionCount: 5)
        let session = try XCTUnwrap(store.startPreviewCheckpointSession())
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        XCTAssertFalse(workflow.abandon(session))

        XCTAssertFalse(store.isCheckpointRetryCooldownActive)
        XCTAssertTrue(protection.isShieldingEnabled)
        XCTAssertEqual(protection.applyShieldCount, 0)
        XCTAssertEqual(protection.clearShieldCount, 0)
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

    // MARK: - Goal switching

    func testGoalSwitchDismissalRoutingPromotesBeforeDrainingDeferredPresentations() {
        XCTAssertEqual(
            GoalSwitchDismissalRouting.nextStep(
                hasPresentedConfirmation: true,
                hasQueuedConfirmation: true
            ),
            .none
        )
        XCTAssertEqual(
            GoalSwitchDismissalRouting.nextStep(
                hasPresentedConfirmation: false,
                hasQueuedConfirmation: true
            ),
            .promoteQueuedConfirmation
        )
        XCTAssertEqual(
            GoalSwitchDismissalRouting.nextStep(
                hasPresentedConfirmation: false,
                hasQueuedConfirmation: false
            ),
            .drainDeferredPresentations
        )
    }

    @MainActor
    func testLapsedGoalSwitchContinuesOnceAfterVerifiedMembershipActivation() throws {
        let store = makeStore(questionCount: 5)
        let sourceGoalID = try XCTUnwrap(store.goal?.id)
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 5)
        store.membershipTier = .starter
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: FakeAppProtectionController()
        )

        XCTAssertEqual(workflow.requestGoalSwitch(to: targetGoal.id), .membershipRequired)
        let expectedContinuation = MembershipActivationContinuation.activateGoal(
            sourceGoalID: sourceGoalID,
            targetGoalID: targetGoal.id
        )
        XCTAssertEqual(store.pendingMembershipPresentation, .feature(.goalProfiles))
        XCTAssertEqual(store.pendingMembershipActivationContinuation, expectedContinuation)

        store.requestMembership(for: .freshQuestionGeneration)
        XCTAssertEqual(store.pendingMembershipPresentation, .feature(.goalProfiles))
        XCTAssertEqual(store.pendingMembershipActivationContinuation, expectedContinuation)

        XCTAssertTrue(store.membershipCheckoutStarted())
        store.reconcileMembershipEntitlement(
            isUnlocked: true,
            activationSource: .purchase
        )
        XCTAssertEqual(store.completeMembershipCheckout(source: .purchase), expectedContinuation)
        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        store.dismissMembershipPrompt()
        let continuation = try XCTUnwrap(
            store.claimMembershipActivationContinuationForResume()
        )
        guard case let .activateGoal(_, targetGoalID) = continuation else {
            return XCTFail("Expected the exact goal switch continuation")
        }

        XCTAssertEqual(
            workflow.requestGoalSwitch(to: targetGoalID),
            .switched(from: sourceGoalID, to: targetGoal.id)
        )
        XCTAssertEqual(store.goal?.id, targetGoal.id)
        XCTAssertNil(store.claimMembershipActivationContinuationForResume())
    }

    @MainActor
    func testPaidGoalCreationClearsItsHandoffOnlyWithTheCommittedGoal() throws {
        let store = makeStore(questionCount: 5)
        let sourceGoalID = try XCTUnwrap(store.goal?.id)
        store.membershipTier = .starter
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: FakeAppProtectionController()
        )

        store.presentGoalProfileCreator()
        store.reconcileMembershipEntitlement(isUnlocked: true)
        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        XCTAssertEqual(
            store.claimMembershipActivationContinuationForResume(),
            .createGoalProfile(sourceGoalID: sourceGoalID)
        )
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .resumeRequested)

        let request = GoalProfileMutationRequest(
            operation: .create(
                makeCoordinatorDraft(title: "Build a durable launch plan")
            )
        )
        XCTAssertEqual(
            workflow.requestGoalProfileMutation(request),
            .committed(resultingGoalID: request.id)
        )
        XCTAssertEqual(store.goal?.id, request.id)
        XCTAssertNil(store.membershipActivationHandoff)
    }

    @MainActor
    func testMembershipGoalSwitchContinuationRejectsARemovedTarget() {
        let store = makeStore(questionCount: 5)
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 5)
        store.membershipTier = .starter
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: FakeAppProtectionController()
        )

        XCTAssertEqual(workflow.requestGoalSwitch(to: targetGoal.id), .membershipRequired)
        store.reconcileMembershipEntitlement(isUnlocked: true)
        store.goalProfiles.removeAll { $0.id == targetGoal.id }

        let stalePresentation = store.membershipActivationPresentation(
            fallbackContext: .overview,
            fallbackSource: .entitlementRefresh
        )
        XCTAssertNil(stalePresentation.continuation)
        XCTAssertEqual(stalePresentation.actionTitle, "Done")
        XCTAssertEqual(store.requestMembershipActivationResume(), .actionUnavailable)
        store.dismissMembershipPrompt()
        XCTAssertNil(store.claimMembershipActivationContinuationForResume())
        XCTAssertNil(store.completedMembershipActivationContinuation)
    }

    @MainActor
    func testMembershipGoalSwitchActivationUsesTheCurrentDestinationTitle() throws {
        let store = makeStore(questionCount: 5)
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 5)
        store.membershipTier = .starter
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: FakeAppProtectionController()
        )
        XCTAssertEqual(workflow.requestGoalSwitch(to: targetGoal.id), .membershipRequired)

        let renamedTitle = "Publish the revised design portfolio"
        let index = try XCTUnwrap(
            store.goalProfiles.firstIndex { $0.id == targetGoal.id }
        )
        store.goalProfiles[index].title = renamedTitle
        store.reconcileMembershipEntitlement(
            isUnlocked: true,
            activationSource: .restore
        )

        let presentation = store.membershipActivationPresentation(
            fallbackContext: .overview,
            fallbackSource: .entitlementRefresh
        )
        XCTAssertEqual(presentation.source, .restore)
        XCTAssertEqual(presentation.destinationTitle, renamedTitle)
        XCTAssertTrue(presentation.detail.contains(renamedTitle))
    }

    @MainActor
    func testPostUpgradeProtectedGoalSwitchStillRequiresFreshConfirmation() throws {
        let store = makeStore(questionCount: 5)
        let sourceGoalID = try XCTUnwrap(store.goal?.id)
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 4)
        store.membershipTier = .starter
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        XCTAssertEqual(workflow.requestGoalSwitch(to: targetGoal.id), .membershipRequired)
        store.reconcileMembershipEntitlement(isUnlocked: true)
        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        let continuation = try XCTUnwrap(
            store.claimMembershipActivationContinuationForResume()
        )
        guard case let .activateGoal(_, targetGoalID) = continuation else {
            return XCTFail("Expected the goal-switch continuation")
        }

        let resumedOutcome = workflow.requestGoalSwitch(to: targetGoalID)
        guard case let .confirmationRequired(confirmation) = resumedOutcome else {
            return XCTFail("Expected a fresh protection-impact confirmation")
        }
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .resumeRequested)
        XCTAssertEqual(store.goal?.id, sourceGoalID)
        XCTAssertEqual(confirmation.sourceGoalID, sourceGoalID)
        XCTAssertEqual(confirmation.targetGoalID, targetGoal.id)
        XCTAssertEqual(
            confirmation.readiness,
            .incomplete(selectableCount: 4, requiredCount: 5)
        )

        XCTAssertEqual(
            workflow.requestGoalSwitch(
                to: targetGoal.id,
                authorization: .confirmed(confirmation)
            ),
            .switched(from: sourceGoalID, to: targetGoal.id)
        )
        XCTAssertEqual(store.goal?.id, targetGoal.id)
        XCTAssertEqual(protection.clearShieldCount, 0)
        XCTAssertNil(store.membershipActivationHandoff)
    }

    @MainActor
    func testProtectedUnreadyGoalRequiresConfirmationWithoutMutatingState() {
        let store = makeStore(questionCount: 5)
        let sourceGoalID = store.goal?.id
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 4)
        store.questionBatchState = .failed
        store.checkpointNotice = "Keep this recovery context."
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let outcome = workflow.requestGoalSwitch(to: targetGoal.id)

        guard case let .confirmationRequired(confirmation) = outcome else {
            return XCTFail("Expected a protection-impact confirmation, got \(outcome)")
        }
        XCTAssertEqual(confirmation.sourceGoalID, sourceGoalID)
        XCTAssertEqual(confirmation.targetGoalID, targetGoal.id)
        XCTAssertEqual(
            confirmation.readiness,
            .incomplete(selectableCount: 4, requiredCount: 5)
        )
        XCTAssertEqual(confirmation.impact, .turnsOffImmediately)
        XCTAssertEqual(store.goal?.id, sourceGoalID)
        XCTAssertEqual(store.questionBatchState, .failed)
        XCTAssertEqual(store.checkpointNotice, "Keep this recovery context.")
        XCTAssertEqual(protection.clearShieldCount, 0)
        XCTAssertTrue(protection.isShieldingEnabled)
    }

    @MainActor
    func testProtectedLegacyLocalTargetWarnsUsingPostCommitReadiness() {
        let store = makeStore(questionCount: 5)
        let sourceGoalID = store.goal?.id
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 5)
        store.lastQuestionProvider = .localTemplates
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let outcome = workflow.requestGoalSwitch(to: targetGoal.id)

        guard case let .confirmationRequired(confirmation) = outcome else {
            return XCTFail("Expected a legacy-bank protection warning, got \(outcome)")
        }
        XCTAssertEqual(
            confirmation.readiness,
            .incomplete(selectableCount: 0, requiredCount: 5)
        )
        XCTAssertEqual(confirmation.impact, .turnsOffImmediately)
        XCTAssertEqual(store.goal?.id, sourceGoalID)
        XCTAssertEqual(
            store.questions.filter { $0.goalID == targetGoal.id }.count,
            5,
            "Preflight must describe the post-commit bank without mutating the cached legacy questions."
        )
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    @MainActor
    func testConfirmedUnreadyGoalSwitchCommitsBeforeRootReconciliationClearsProtection() {
        let store = makeStore(questionCount: 5)
        let sourceGoalID = store.goal?.id
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 4)
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)
        let initialOutcome = workflow.requestGoalSwitch(to: targetGoal.id)
        guard case let .confirmationRequired(confirmation) = initialOutcome else {
            return XCTFail("Expected a protection-impact confirmation, got \(initialOutcome)")
        }

        let confirmedOutcome = workflow.requestGoalSwitch(
            to: targetGoal.id,
            authorization: .confirmed(confirmation)
        )

        XCTAssertEqual(
            confirmedOutcome,
            .switched(from: sourceGoalID, to: targetGoal.id)
        )
        XCTAssertEqual(store.goal?.id, targetGoal.id)
        XCTAssertEqual(protection.clearShieldCount, 0)

        workflow.goalDidChange()

        XCTAssertEqual(protection.clearShieldCount, 1)
        XCTAssertFalse(protection.isShieldingEnabled)
    }

    @MainActor
    func testReadyGoalSwitchNeedsNoConfirmationAndPreservesDesiredProtection() {
        let store = makeStore(questionCount: 5)
        let sourceGoalID = store.goal?.id
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 5)
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)

        let outcome = workflow.requestGoalSwitch(to: targetGoal.id)

        XCTAssertEqual(outcome, .switched(from: sourceGoalID, to: targetGoal.id))
        XCTAssertEqual(store.goal?.id, targetGoal.id)
        workflow.goalDidChange()
        XCTAssertTrue(SharedAppGroup.desiredShieldActive)
        XCTAssertTrue(protection.isShieldingEnabled)
        XCTAssertEqual(protection.clearShieldCount, 0)
        XCTAssertEqual(protection.applyShieldCount, 1)
    }

    @MainActor
    func testUnreadyGoalDuringActiveBreakWarnsThatProtectionWillNotRelock() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let store = makeStore(questionCount: 5)
        let sourceGoalID = store.goal?.id
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 4)
        let breakExpiration = now.addingTimeInterval(600)
        store.unlockSession = UnlockSession(startedAt: now, expiresAt: breakExpiration)
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: breakExpiration
        )
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: protection,
            now: { now }
        )

        let outcome = workflow.requestGoalSwitch(to: targetGoal.id)

        guard case let .confirmationRequired(confirmation) = outcome else {
            return XCTFail("Expected an active-break confirmation, got \(outcome)")
        }
        XCTAssertEqual(confirmation.impact, .preventsRelockAfterBreak)
        XCTAssertEqual(store.goal?.id, sourceGoalID)
        XCTAssertEqual(store.unlockSession?.expiresAt, breakExpiration)
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    @MainActor
    func testSharedOnlyBreakSurvivesConfirmedUnreadyGoalSwitchAndReconciliation() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let store = makeStore(questionCount: 5)
        let sourceGoalID = store.goal?.id
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 4)
        XCTAssertNil(store.unlockSession)
        let breakExpiration = now.addingTimeInterval(600)
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: breakExpiration
        )
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: protection,
            now: { now }
        )
        let initialOutcome = workflow.requestGoalSwitch(to: targetGoal.id)
        guard case let .confirmationRequired(confirmation) = initialOutcome else {
            return XCTFail("Expected a shared-break confirmation, got \(initialOutcome)")
        }
        XCTAssertEqual(confirmation.impact, .preventsRelockAfterBreak)

        let confirmedOutcome = workflow.requestGoalSwitch(
            to: targetGoal.id,
            authorization: .confirmed(confirmation)
        )
        XCTAssertEqual(
            confirmedOutcome,
            .switched(from: sourceGoalID, to: targetGoal.id)
        )

        workflow.goalDidChange()

        XCTAssertEqual(protection.clearShieldCount, 0)
        XCTAssertTrue(SharedAppGroup.desiredShieldActive)
        XCTAssertEqual(SharedAppGroup.unlockExpiration, breakExpiration)
        XCTAssertNil(store.unlockSession)
    }

    @MainActor
    func testGoalSwitchConfirmationBecomesStaleWhenSourceGoalChanges() {
        let store = makeStore(questionCount: 5)
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 4)
        let replacementSource = makeCoordinatorTargetGoal(title: "A different current goal")
        store.goalProfiles.append(replacementSource)
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)
        let initialOutcome = workflow.requestGoalSwitch(to: targetGoal.id)
        guard case let .confirmationRequired(confirmation) = initialOutcome else {
            return XCTFail("Expected a protection-impact confirmation, got \(initialOutcome)")
        }
        store.goal = replacementSource

        let confirmedOutcome = workflow.requestGoalSwitch(
            to: targetGoal.id,
            authorization: .confirmed(confirmation)
        )

        XCTAssertEqual(confirmedOutcome, .staleRequest)
        XCTAssertEqual(store.goal?.id, replacementSource.id)
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    @MainActor
    func testConfirmedGoalSwitchRevalidatesTargetThatBecameReady() {
        let store = makeStore(questionCount: 5)
        let sourceGoalID = store.goal?.id
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 4)
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)
        let initialOutcome = workflow.requestGoalSwitch(to: targetGoal.id)
        guard case let .confirmationRequired(confirmation) = initialOutcome else {
            return XCTFail("Expected a protection-impact confirmation, got \(initialOutcome)")
        }
        store.questions.append(
            makeCoordinatorTestQuestion(goal: targetGoal, index: 105)
        )

        let confirmedOutcome = workflow.requestGoalSwitch(
            to: targetGoal.id,
            authorization: .confirmed(confirmation)
        )

        XCTAssertEqual(
            confirmedOutcome,
            .switched(from: sourceGoalID, to: targetGoal.id)
        )
        XCTAssertEqual(store.goal?.id, targetGoal.id)
        XCTAssertTrue(store.hasReadyCheckpointSet)
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    @MainActor
    func testGoalSwitchReadinessDegradationReturnsRefreshedConfirmation() {
        let store = makeStore(questionCount: 5)
        let sourceGoalID = store.goal?.id
        let targetGoal = addGoalSwitchTarget(to: store, questionCount: 4)
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)
        let initialOutcome = workflow.requestGoalSwitch(to: targetGoal.id)
        guard case let .confirmationRequired(initialConfirmation) = initialOutcome else {
            return XCTFail("Expected an initial protection warning, got \(initialOutcome)")
        }
        guard let degradedIndex = store.questions.lastIndex(where: {
            $0.goalID == targetGoal.id
        }) else {
            return XCTFail("Expected a target question to degrade")
        }
        store.questions[degradedIndex].status = .retired

        let refreshedOutcome = workflow.requestGoalSwitch(
            to: targetGoal.id,
            authorization: .confirmed(initialConfirmation)
        )

        guard case let .confirmationRequired(refreshedConfirmation) = refreshedOutcome else {
            return XCTFail("Expected refreshed confirmation, got \(refreshedOutcome)")
        }
        XCTAssertEqual(
            initialConfirmation.readiness,
            .incomplete(selectableCount: 4, requiredCount: 5)
        )
        XCTAssertEqual(
            refreshedConfirmation.readiness,
            .incomplete(selectableCount: 3, requiredCount: 5)
        )
        XCTAssertNotEqual(refreshedConfirmation, initialConfirmation)
        XCTAssertEqual(refreshedConfirmation.impact, .turnsOffImmediately)
        XCTAssertEqual(store.goal?.id, sourceGoalID)
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    // MARK: - Goal profile mutations

    @MainActor
    func testProtectedGoalCreationPreflightIsPureAndConfirmedRequestCommitsOnce() async {
        let capturingEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let store = makeStore(
            questionCount: 5,
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: capturingEngine
            )
        )
        store.membershipTier = .member
        store.aiProviderPreference = .appleFoundation
        store.questionBatchState = .failed
        store.checkpointNotice = "Keep this recovery context."
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)
        let request = GoalProfileMutationRequest(
            id: UUID(uuidString: "F107750C-3304-498B-BF23-6B11D0DFAB5B")!,
            createdAt: Date(timeIntervalSinceReferenceDate: 20_000),
            operation: .create(makeCoordinatorDraft())
        )
        let originalGoal = store.goal
        let originalProfiles = store.goalProfiles
        let originalQuestions = store.questions

        let initialOutcome = workflow.requestGoalProfileMutation(request)

        guard case let .confirmationRequired(confirmation) = initialOutcome else {
            return XCTFail("Expected a protection confirmation, got \(initialOutcome)")
        }
        XCTAssertEqual(confirmation.consent, .protection(.turnsOffImmediately))
        XCTAssertEqual(
            confirmation.plan.resultingReadiness,
            .incomplete(selectableCount: 0, requiredCount: 5)
        )
        XCTAssertEqual(store.goal, originalGoal)
        XCTAssertEqual(store.goalProfiles, originalProfiles)
        XCTAssertEqual(store.questions, originalQuestions)
        XCTAssertEqual(store.questionBatchState, .failed)
        XCTAssertEqual(store.checkpointNotice, "Keep this recovery context.")
        XCTAssertEqual(protection.clearShieldCount, 0)

        let confirmedOutcome = workflow.requestGoalProfileMutation(
            request,
            authorization: .confirmed(confirmation)
        )
        let replayOutcome = workflow.requestGoalProfileMutation(
            request,
            authorization: .confirmed(confirmation)
        )

        XCTAssertEqual(confirmedOutcome, .committed(resultingGoalID: request.id))
        XCTAssertEqual(replayOutcome, .alreadyCommitted)
        XCTAssertEqual(store.goal?.id, request.id)
        XCTAssertEqual(
            store.availableGoalProfiles.filter { $0.id == request.id }.count,
            1
        )

        for _ in 0..<20 where capturingEngine.receivedRequests.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(
            capturingEngine.receivedRequests.filter {
                $0.goal.id == request.id
                    && $0.targetCount == store.unlockPolicy.questionsPerSession
            }.count,
            1,
            "Replaying a committed creation must not start a second initial generation."
        )

        let collidingRequest = GoalProfileMutationRequest(
            id: request.id,
            createdAt: request.createdAt,
            operation: .create(
                makeCoordinatorDraft(title: "A different goal using the same token")
            )
        )
        XCTAssertEqual(
            workflow.requestGoalProfileMutation(collidingRequest),
            .staleRequest
        )

        store.goal = originalGoal
        XCTAssertEqual(
            workflow.requestGoalProfileMutation(
                request,
                authorization: .confirmed(confirmation)
            ),
            .staleRequest,
            "A creation replay is only idempotent while its committed goal remains current."
        )
    }

    @MainActor
    func testGoalCreationDuringActiveBreakPreservesLocalAndSharedExpiration() {
        let now = Date()
        let breakExpiration = now.addingTimeInterval(600)
        let store = makeStore(
            questionCount: 5,
            questionEngine: HybridQuestionEngine(
                backendEngine: FailingCoordinatorQuestionEngine(),
                appleFoundationEngine: FailingCoordinatorQuestionEngine()
            )
        )
        store.membershipTier = .member
        store.unlockSession = UnlockSession(startedAt: now, expiresAt: breakExpiration)
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: breakExpiration
        )
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: protection,
            now: { now }
        )
        let request = GoalProfileMutationRequest(
            id: UUID(uuidString: "01427050-03C2-4A88-A104-B068EABAE465")!,
            createdAt: now,
            operation: .create(makeCoordinatorDraft())
        )

        let initialOutcome = workflow.requestGoalProfileMutation(request)
        guard case let .confirmationRequired(confirmation) = initialOutcome else {
            return XCTFail("Expected an active-break confirmation, got \(initialOutcome)")
        }
        XCTAssertEqual(
            confirmation.consent,
            .protection(.preventsRelockAfterBreak)
        )
        XCTAssertTrue(confirmation.activeBreakAtRequest)

        XCTAssertEqual(
            workflow.requestGoalProfileMutation(
                request,
                authorization: .confirmed(confirmation)
            ),
            .committed(resultingGoalID: request.id)
        )
        workflow.goalDidChange()

        XCTAssertEqual(store.unlockSession?.expiresAt, breakExpiration)
        XCTAssertEqual(SharedAppGroup.unlockExpiration, breakExpiration)
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    @MainActor
    func testRaisingMinimumDifficultyUsesExactReadinessAndChangedActiveGoalIsStale() throws {
        let store = makeStore(questionCount: 0)
        store.membershipTier = .member
        let sourceGoal = try XCTUnwrap(store.goal)
        store.questions = (1...5).map { index in
            makeCoordinatorTestQuestion(
                goal: sourceGoal,
                index: index,
                difficulty: index == 5 ? 3 : 4
            )
        }
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)
        let request = GoalProfileMutationRequest(
            id: UUID(uuidString: "9B18EA1B-E089-46CC-AC40-C3705AC93623")!,
            createdAt: Date(timeIntervalSinceReferenceDate: 40_000),
            operation: .edit(
                expectedGoalID: sourceGoal.id,
                draft: makeCoordinatorEditDraft(
                    from: sourceGoal,
                    minimumQuestionDifficulty: 4
                )
            )
        )

        let initialOutcome = workflow.requestGoalProfileMutation(request)

        guard case let .confirmationRequired(confirmation) = initialOutcome else {
            return XCTFail("Expected an exact-readiness warning, got \(initialOutcome)")
        }
        XCTAssertEqual(
            confirmation.plan.sourceReadiness,
            .ready(selectableCount: 5, requiredCount: 5)
        )
        XCTAssertEqual(
            confirmation.plan.resultingReadiness,
            .incomplete(selectableCount: 4, requiredCount: 5)
        )
        XCTAssertEqual(confirmation.consent, .protection(.turnsOffImmediately))
        XCTAssertEqual(store.goal?.minimumQuestionDifficulty, sourceGoal.minimumQuestionDifficulty)

        let replacementSource = makeCoordinatorTargetGoal(
            title: "A different current goal",
            createdAt: Date(timeIntervalSinceReferenceDate: 50_000)
        )
        store.goalProfiles.append(replacementSource)
        store.goal = replacementSource

        XCTAssertEqual(
            workflow.requestGoalProfileMutation(
                request,
                authorization: .confirmed(confirmation)
            ),
            .staleRequest
        )
        XCTAssertEqual(store.goal?.id, replacementSource.id)
        XCTAssertEqual(
            store.goalProfiles.first { $0.id == sourceGoal.id }?.minimumQuestionDifficulty,
            sourceGoal.minimumQuestionDifficulty
        )
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    @MainActor
    func testConfirmedProtectedEditRejectsInterveningUserEditEvenWhenNowSafe() throws {
        let store = makeStore(questionCount: 0)
        store.membershipTier = .member
        let sourceGoal = try XCTUnwrap(store.goal)
        store.questions = (1...5).map { index in
            makeCoordinatorTestQuestion(
                goal: sourceGoal,
                index: index,
                difficulty: index == 5 ? 3 : 4
            )
        }
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)
        let request = GoalProfileMutationRequest(
            id: UUID(uuidString: "5AD7FC77-EB00-48A4-9D61-6BFC9F7A734A")!,
            createdAt: Date(timeIntervalSinceReferenceDate: 110_000),
            operation: .edit(
                expectedGoalID: sourceGoal.id,
                draft: makeCoordinatorEditDraft(
                    from: sourceGoal,
                    minimumQuestionDifficulty: 4
                )
            )
        )
        let initialOutcome = workflow.requestGoalProfileMutation(request)
        guard case let .confirmationRequired(confirmation) = initialOutcome else {
            return XCTFail("Expected an initial protection warning, got \(initialOutcome)")
        }
        XCTAssertEqual(
            confirmation.plan.resultingReadiness,
            .incomplete(selectableCount: 4, requiredCount: 5)
        )

        var interveningGoal = sourceGoal
        interveningGoal.focusAreas = "queues, caching, and incident response"
        store.goal = interveningGoal
        store.questions.append(
            makeCoordinatorTestQuestion(
                goal: interveningGoal,
                index: 6,
                difficulty: 4
            )
        )
        guard case let .eligible(currentPlan) = store.prepareGoalProfileMutation(request) else {
            return XCTFail("Expected the original request to remain structurally eligible")
        }
        XCTAssertEqual(
            currentPlan.resultingReadiness,
            .ready(selectableCount: 5, requiredCount: 5),
            "Readiness alone is now safe and must not be the reason confirmation is rejected."
        )

        let confirmedOutcome = workflow.requestGoalProfileMutation(
            request,
            authorization: .confirmed(confirmation)
        )

        XCTAssertEqual(confirmedOutcome, .staleRequest)
        XCTAssertEqual(store.goal, interveningGoal)
        XCTAssertEqual(
            store.goalProfiles.first { $0.id == sourceGoal.id }?.focusAreas,
            interveningGoal.focusAreas
        )
        XCTAssertEqual(
            store.goal?.minimumQuestionDifficulty,
            sourceGoal.minimumQuestionDifficulty
        )
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    @MainActor
    func testDeletingActiveGoalWithReadyReplacementNeedsDeletionOnlyAndPreservesBreak() throws {
        let now = Date()
        let breakExpiration = now.addingTimeInterval(600)
        let store = makeStore(questionCount: 5)
        store.membershipTier = .member
        let sourceGoal = try XCTUnwrap(store.goal)
        let replacementGoal = makeCoordinatorTargetGoal(
            createdAt: Date(timeIntervalSinceReferenceDate: 70_000)
        )
        store.goalProfiles.append(replacementGoal)
        store.questions += (1...5).map {
            makeCoordinatorTestQuestion(goal: replacementGoal, index: $0 + 100)
        }
        store.unlockSession = UnlockSession(startedAt: now, expiresAt: breakExpiration)
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: breakExpiration
        )
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: protection,
            now: { now }
        )
        let request = GoalProfileMutationRequest(
            operation: .delete(goalID: sourceGoal.id)
        )

        let initialOutcome = workflow.requestGoalProfileMutation(request)
        guard case let .confirmationRequired(confirmation) = initialOutcome else {
            return XCTFail("Expected deletion consent, got \(initialOutcome)")
        }
        XCTAssertEqual(confirmation.consent, .deletion)
        XCTAssertEqual(confirmation.plan.resultingActiveGoal?.id, replacementGoal.id)
        XCTAssertEqual(
            confirmation.plan.resultingReadiness,
            .ready(selectableCount: 5, requiredCount: 5)
        )
        XCTAssertTrue(store.availableGoalProfiles.contains { $0.id == sourceGoal.id })

        XCTAssertEqual(
            workflow.requestGoalProfileMutation(
                request,
                authorization: .confirmed(confirmation)
            ),
            .committed(resultingGoalID: replacementGoal.id)
        )
        workflow.goalDidChange()

        XCTAssertEqual(store.goal?.id, replacementGoal.id)
        XCTAssertFalse(store.availableGoalProfiles.contains { $0.id == sourceGoal.id })
        XCTAssertTrue(store.questions.allSatisfy { $0.goalID == replacementGoal.id })
        XCTAssertEqual(store.unlockSession?.expiresAt, breakExpiration)
        XCTAssertEqual(SharedAppGroup.unlockExpiration, breakExpiration)
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    @MainActor
    func testDeletingActiveGoalRefreshesCombinedConsentWhenReplacementChanges() throws {
        let store = makeStore(questionCount: 5)
        store.membershipTier = .member
        let sourceGoal = try XCTUnwrap(store.goal)
        let firstReplacement = makeCoordinatorTargetGoal(
            title: "First replacement",
            createdAt: Date(timeIntervalSinceReferenceDate: 80_000)
        )
        store.goalProfiles.append(firstReplacement)
        store.questions += (1...4).map {
            makeCoordinatorTestQuestion(goal: firstReplacement, index: $0 + 100)
        }
        let protection = FakeAppProtectionController()
        protection.isShieldingEnabled = true
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: protection)
        let request = GoalProfileMutationRequest(
            operation: .delete(goalID: sourceGoal.id)
        )

        let initialOutcome = workflow.requestGoalProfileMutation(request)
        guard case let .confirmationRequired(initialConfirmation) = initialOutcome else {
            return XCTFail("Expected combined deletion consent, got \(initialOutcome)")
        }
        XCTAssertEqual(
            initialConfirmation.consent,
            .deletionAndProtection(.turnsOffImmediately)
        )
        XCTAssertEqual(initialConfirmation.plan.resultingActiveGoal?.id, firstReplacement.id)
        XCTAssertEqual(
            initialConfirmation.plan.resultingReadiness,
            .incomplete(selectableCount: 4, requiredCount: 5)
        )

        let newerReplacement = makeCoordinatorTargetGoal(
            title: "Newer replacement",
            createdAt: Date(timeIntervalSinceReferenceDate: 90_000)
        )
        store.goalProfiles.append(newerReplacement)
        store.questions += (1...3).map {
            makeCoordinatorTestQuestion(goal: newerReplacement, index: $0 + 200)
        }

        let refreshedOutcome = workflow.requestGoalProfileMutation(
            request,
            authorization: .confirmed(initialConfirmation)
        )

        guard case let .confirmationRequired(refreshedConfirmation) = refreshedOutcome else {
            return XCTFail("Expected refreshed combined consent, got \(refreshedOutcome)")
        }
        XCTAssertEqual(
            refreshedConfirmation.consent,
            .deletionAndProtection(.turnsOffImmediately)
        )
        XCTAssertEqual(refreshedConfirmation.plan.resultingActiveGoal?.id, newerReplacement.id)
        XCTAssertEqual(
            refreshedConfirmation.plan.resultingReadiness,
            .incomplete(selectableCount: 3, requiredCount: 5)
        )
        XCTAssertNotEqual(refreshedConfirmation, initialConfirmation)
        XCTAssertEqual(store.goal?.id, sourceGoal.id)
        XCTAssertTrue(store.availableGoalProfiles.contains { $0.id == sourceGoal.id })
        XCTAssertEqual(store.questions.filter { $0.goalID == sourceGoal.id }.count, 5)
        XCTAssertEqual(store.questions.filter { $0.goalID == firstReplacement.id }.count, 4)
        XCTAssertEqual(store.questions.filter { $0.goalID == newerReplacement.id }.count, 3)
        XCTAssertEqual(protection.clearShieldCount, 0)
    }

    @MainActor
    func testDeletingFinalGoalRequiresCombinedConsentAndEndsBreakAfterReconciliation() throws {
        let now = Date()
        let breakExpiration = now.addingTimeInterval(600)
        let store = makeStore(questionCount: 5)
        let sourceGoal = try XCTUnwrap(store.goal)
        store.unlockSession = UnlockSession(startedAt: now, expiresAt: breakExpiration)
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: breakExpiration
        )
        let protection = FakeAppProtectionController()
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: protection,
            now: { now }
        )
        let request = GoalProfileMutationRequest(
            operation: .delete(goalID: sourceGoal.id)
        )

        let initialOutcome = workflow.requestGoalProfileMutation(request)
        guard case let .confirmationRequired(confirmation) = initialOutcome else {
            return XCTFail("Expected combined deletion consent, got \(initialOutcome)")
        }
        XCTAssertEqual(
            confirmation.consent,
            .deletionAndProtection(.turnsOffImmediately)
        )
        XCTAssertTrue(confirmation.activeBreakAtRequest)
        XCTAssertNil(confirmation.plan.resultingActiveGoal)
        XCTAssertEqual(store.unlockSession?.expiresAt, breakExpiration)
        XCTAssertEqual(SharedAppGroup.unlockExpiration, breakExpiration)

        XCTAssertEqual(
            workflow.requestGoalProfileMutation(
                request,
                authorization: .confirmed(confirmation)
            ),
            .committed(resultingGoalID: nil)
        )
        workflow.goalDidChange()

        XCTAssertNil(store.goal)
        XCTAssertTrue(store.availableGoalProfiles.isEmpty)
        XCTAssertTrue(store.questions.isEmpty)
        XCTAssertNil(store.unlockSession)
        XCTAssertNil(SharedAppGroup.unlockExpiration)
        XCTAssertFalse(protection.isShieldingEnabled)
        XCTAssertEqual(protection.clearShieldCount, 1)
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
    private func makeStore(
        questionCount: Int,
        questionEngine: HybridQuestionEngine = HybridQuestionEngine()
    ) -> CheckpointStore {
        let goal = makeCoordinatorTestGoal()
        let store = CheckpointStore(
            questionEngine: questionEngine,
            defaults: defaults
        )
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = (0..<questionCount).map {
            makeCoordinatorTestQuestion(goal: goal, index: $0 + 1)
        }
        return store
    }

    @MainActor
    private func addGoalSwitchTarget(
        to store: CheckpointStore,
        questionCount: Int
    ) -> Goal {
        let targetGoal = makeCoordinatorTargetGoal()
        store.membershipTier = .member
        store.goalProfiles.append(targetGoal)
        store.questions += (0..<questionCount).map { index in
            makeCoordinatorTestQuestion(goal: targetGoal, index: index + 101)
        }
        return targetGoal
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

private func makeCoordinatorTargetGoal(
    title: String = "Prepare for calculus final",
    createdAt: Date = Date()
) -> Goal {
    Goal(
        title: title,
        deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
        category: .examPrep,
        currentLevel: "Intermediate",
        focusAreas: "derivatives, integrals",
        preferredQuestionStyle: .multipleChoice,
        createdAt: createdAt
    )
}

private func makeCoordinatorDraft(
    title: String = "Learn conversational Japanese"
) -> GoalProfileDraft {
    GoalProfileDraft(
        title: title,
        deadline: Date(timeIntervalSinceReferenceDate: 2_000_000),
        category: .custom,
        currentLevel: "Beginner",
        focusAreas: "conversation, listening",
        preferredQuestionStyle: .multipleChoice,
        minimumQuestionDifficulty: 2
    )
}

private func makeCoordinatorEditDraft(
    from goal: Goal,
    minimumQuestionDifficulty: Int
) -> GoalProfileDraft {
    GoalProfileDraft(
        title: goal.title,
        deadline: goal.deadline,
        category: goal.category,
        currentLevel: goal.currentLevel,
        focusAreas: goal.focusAreas,
        sourceDocuments: goal.sourceDocuments,
        preferredQuestionStyle: goal.preferredQuestionStyle,
        minimumQuestionDifficulty: minimumQuestionDifficulty
    )
}

private func makeCoordinatorTestQuestion(
    goal: Goal,
    index: Int,
    difficulty: Int = 2
) -> CheckpointQuestion {
    CheckpointQuestion(
        goalID: goal.id,
        prompt: "Question \(index)",
        expectedAnswer: "Answer \(index)",
        choices: ["Answer \(index)", "A", "B", "C"],
        explanation: "Explanation \(index)",
        topic: "arrays",
        difficulty: difficulty,
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
