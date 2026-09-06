import SwiftUI
import XCTest
@testable import Checkpoint

#if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
import ManagedSettings
#endif

final class ScreenTimeAccessRenderingTests: CheckpointWorkflowTestCase {
    func testContextResolutionSeparatesInitialResumeRestoreAndEraseJourneys() {
        XCTAssertEqual(
            ScreenTimeAccessContext.resolve(
                requiresEraseRecovery: true,
                isFirstRunPending: true,
                hasGoal: false
            ),
            .eraseRecovery
        )
        XCTAssertEqual(
            ScreenTimeAccessContext.resolve(
                requiresEraseRecovery: false,
                isFirstRunPending: false,
                hasGoal: false
            ),
            .initialSetup
        )
        XCTAssertEqual(
            ScreenTimeAccessContext.resolve(
                requiresEraseRecovery: false,
                isFirstRunPending: true,
                hasGoal: true
            ),
            .resumeSetup
        )
        XCTAssertEqual(
            ScreenTimeAccessContext.resolve(
                requiresEraseRecovery: false,
                isFirstRunPending: false,
                hasGoal: true
            ),
            .restoreProtection
        )
    }

    func testFirstRunAccessFollowsTheGoalAndSkillMapAsStepThree() {
        let initial = ScreenTimeAccessPresentation(
            context: .initialSetup,
            authorizationState: .notDetermined,
            requiresProtectedAppReselection: false
        )

        XCTAssertEqual(initial.stage, "Protection")
        XCTAssertEqual(initial.step, 3)
        XCTAssertEqual(initial.state, .permissionRequired)
        XCTAssertEqual(initial.state.status, "Permission needed")
        XCTAssertEqual(initial.state.systemImage, "checkmark.shield")
        XCTAssertEqual(initial.state.tone, .informational)
        XCTAssertEqual(initial.heading, "Let’s protect your focus")
        XCTAssertTrue(initial.detail.contains("Screen Time lets Checkpoint pause distracting apps"))
        XCTAssertEqual(initial.primaryAction, .request)
        XCTAssertEqual(initial.primaryTitle, "Allow Screen Time")
        XCTAssertEqual(initial.primarySystemImage, "checkmark.shield")
        XCTAssertFalse(initial.isWorking)
        XCTAssertTrue(initial.showsPrivacyProofInHero)
        XCTAssertNil(initial.recoveryTitle)
        XCTAssertNil(initial.statusMessage)

        let resumed = ScreenTimeAccessPresentation(
            context: .resumeSetup,
            authorizationState: .notDetermined,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(resumed.step, 3)
        XCTAssertEqual(resumed.stage, "Protection")
        XCTAssertEqual(resumed.detail, initial.detail)

        for context in [ScreenTimeAccessContext.restoreProtection, .eraseRecovery] {
            let presentation = ScreenTimeAccessPresentation(
                context: context,
                authorizationState: .notDetermined,
                requiresProtectedAppReselection: false
            )
            XCTAssertNil(presentation.step, "\(context) must not claim a numbered first-run step")
        }
    }

    func testAuthorizationStatesResolveToHonestPrimaryActions() {
        let requesting = ScreenTimeAccessPresentation(
            context: .initialSetup,
            authorizationState: .requesting,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(requesting.primaryAction, .request)
        XCTAssertEqual(requesting.primaryTitle, "Requesting access")
        XCTAssertEqual(requesting.state, .requesting)
        XCTAssertEqual(requesting.state.status, "Requesting")
        XCTAssertEqual(requesting.state.systemImage, "hourglass")
        XCTAssertEqual(requesting.state.tone, .working)
        XCTAssertTrue(requesting.isWorking)
        XCTAssertNil(requesting.statusMessage)

        let denied = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .denied,
            requiresProtectedAppReselection: true
        )
        XCTAssertEqual(denied.primaryAction, .openSettings)
        XCTAssertEqual(denied.primaryTitle, "Open iPhone Settings")
        XCTAssertEqual(denied.primarySystemImage, "gear")
        XCTAssertEqual(denied.state, .accessOff)
        XCTAssertEqual(denied.state.status, "Access off")
        XCTAssertEqual(denied.state.tone, .warning)
        XCTAssertNotNil(denied.statusMessage)

        let failed = ScreenTimeAccessPresentation(
            context: .resumeSetup,
            authorizationState: .failed,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(failed.primaryAction, .retry)
        XCTAssertEqual(failed.primaryTitle, "Try Screen Time access again")
        XCTAssertEqual(failed.primarySystemImage, "arrow.clockwise")
        XCTAssertEqual(failed.state, .requestFailed)
        XCTAssertEqual(failed.state.status, "Request failed")
        XCTAssertEqual(failed.state.tone, .failure)
        XCTAssertEqual(
            failed.statusMessage,
            "Checkpoint couldn’t complete the Screen Time request. Try again."
        )

        let unavailable = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .unavailable,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(unavailable.primaryAction, .none)
        XCTAssertEqual(unavailable.state, .unavailable)
        XCTAssertEqual(unavailable.state.status, "iPhone required")
        XCTAssertEqual(unavailable.state.systemImage, "iphone.slash")
        XCTAssertEqual(unavailable.heading, "Screen Time access needs an iPhone")
        XCTAssertFalse(unavailable.showsPrivacyProofInHero)
        XCTAssertNil(unavailable.primaryTitle)
        XCTAssertNil(unavailable.primarySystemImage)

        let initialUnavailable = ScreenTimeAccessPresentation(
            context: .initialSetup,
            authorizationState: .unavailable,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(initialUnavailable.heading, "Screen Time access needs an iPhone")
        XCTAssertTrue(initialUnavailable.showsPrivacyProofInHero)

        for approvedState in [
            ScreenTimeController.AuthorizationState.approved,
            .approvedWithDataAccess
        ] {
            let approved = ScreenTimeAccessPresentation(
                context: .restoreProtection,
                authorizationState: approvedState,
                requiresProtectedAppReselection: true
            )
            XCTAssertEqual(approved.primaryAction, .continueAfterConnection)
            XCTAssertEqual(approved.primaryTitle, "Choose apps again")
            XCTAssertEqual(approved.primarySystemImage, "square.grid.2x2")
            XCTAssertEqual(approved.state, .connected)
            XCTAssertEqual(approved.state.status, "Connected")
            XCTAssertEqual(approved.state.tone, .success)
            XCTAssertFalse(approved.isWorking)
            XCTAssertNil(approved.statusMessage)
        }
    }

    func testConnectedPresentationUsesContextAwareHandoffCopyAndActions() {
        let initial = ScreenTimeAccessPresentation(
            context: .initialSetup,
            authorizationState: .approved,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(initial.heading, "Screen Time connected")
        XCTAssertEqual(
            initial.detail,
            "Choose apps to pause, or skip for now. You can change this later."
        )
        XCTAssertEqual(initial.primaryAction, .continueAfterConnection)
        XCTAssertEqual(initial.primaryTitle, "Continue setup")
        XCTAssertEqual(initial.primarySystemImage, "arrow.right")

        let resume = ScreenTimeAccessPresentation(
            context: .resumeSetup,
            authorizationState: .approvedWithDataAccess,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(resume.heading, "Screen Time connected")
        XCTAssertEqual(
            resume.detail,
            "Choose apps to pause, or skip for now. You can change this later."
        )
        XCTAssertEqual(resume.primaryAction, .continueAfterConnection)
        XCTAssertEqual(resume.primaryTitle, "Continue setup")
        XCTAssertEqual(resume.primarySystemImage, "arrow.right")

        let selectionRecovery = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .approved,
            requiresProtectedAppReselection: true
        )
        XCTAssertEqual(selectionRecovery.heading, "Screen Time reconnected")
        XCTAssertEqual(
            selectionRecovery.detail,
            "Choose apps again to restore app protection."
        )
        XCTAssertEqual(selectionRecovery.primaryAction, .continueAfterConnection)
        XCTAssertEqual(selectionRecovery.primaryTitle, "Choose apps again")
        XCTAssertEqual(selectionRecovery.primarySystemImage, "square.grid.2x2")

        let returnToCheckpoint = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .approved,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(returnToCheckpoint.heading, "Screen Time connected")
        XCTAssertEqual(
            returnToCheckpoint.detail,
            "Return to Checkpoint when you're ready."
        )
        XCTAssertEqual(returnToCheckpoint.primaryAction, .continueAfterConnection)
        XCTAssertEqual(returnToCheckpoint.primaryTitle, "Return to Checkpoint")
        XCTAssertEqual(returnToCheckpoint.primarySystemImage, "arrow.right")

        let returnToOnboarding = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .approved,
            requiresProtectedAppReselection: true,
            continuesOnboardingAfterDismissal: true
        )
        XCTAssertEqual(returnToOnboarding.heading, "Screen Time connected")
        XCTAssertEqual(
            returnToOnboarding.detail,
            "Continue setup. Choose apps again after you finish your goal."
        )
        XCTAssertEqual(returnToOnboarding.primaryAction, .continueAfterConnection)
        XCTAssertEqual(returnToOnboarding.primaryTitle, "Continue setup")
        XCTAssertEqual(returnToOnboarding.primarySystemImage, "arrow.right")
    }

    func testRestorePresentationStaysNeutralWithoutASelectionRecovery() {
        let denied = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .denied,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(denied.stage, "Screen Time")
        XCTAssertEqual(denied.heading, "Reconnect Screen Time")
        XCTAssertFalse(denied.heading.localizedCaseInsensitiveContains("protection"))
        XCTAssertFalse(denied.detail.localizedCaseInsensitiveContains("protection"))
        XCTAssertFalse(denied.recoveryDetail?.localizedCaseInsensitiveContains("protection") == true)

        let connected = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .approved,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(connected.stage, "Screen Time")
        XCTAssertEqual(connected.heading, "Screen Time connected")
        XCTAssertEqual(connected.detail, "Return to Checkpoint when you're ready.")
        XCTAssertFalse(connected.detail.localizedCaseInsensitiveContains("protection"))
        XCTAssertEqual(connected.primaryTitle, "Return to Checkpoint")
    }

    func testRecoveryPresentationExplainsSelectionLossWithoutLosingLearningData() {
        let selectionRecovery = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .approved,
            requiresProtectedAppReselection: true
        )

        XCTAssertEqual(selectionRecovery.stage, "Protection paused")
        XCTAssertNil(selectionRecovery.step)
        XCTAssertEqual(selectionRecovery.recoveryTitle, "Your learning data is safe")
        XCTAssertEqual(selectionRecovery.recoverySystemImage, "lock.shield.fill")
        XCTAssertTrue(selectionRecovery.detail.localizedCaseInsensitiveContains("choose apps again"))
        XCTAssertTrue(selectionRecovery.recoveryDetail?.localizedCaseInsensitiveContains("progress") == true)
        XCTAssertTrue(selectionRecovery.recoveryDetail?.localizedCaseInsensitiveContains("stayed saved") == true)

        let reconnectOnly = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .approved,
            requiresProtectedAppReselection: false
        )
        XCTAssertFalse(reconnectOnly.detail.localizedCaseInsensitiveContains("selected again"))
        XCTAssertTrue(reconnectOnly.detail.localizedCaseInsensitiveContains("Return to Checkpoint") == true)
        XCTAssertTrue(reconnectOnly.recoveryDetail?.localizedCaseInsensitiveContains("stayed saved") == true)

        let eraseRecovery = ScreenTimeAccessPresentation(
            context: .eraseRecovery,
            authorizationState: .denied,
            requiresProtectedAppReselection: true
        )
        XCTAssertEqual(eraseRecovery.primaryAction, .erase)
        XCTAssertEqual(eraseRecovery.state, .eraseRecovery)
        XCTAssertEqual(eraseRecovery.state.status, "Recovery needed")
        XCTAssertEqual(eraseRecovery.state.systemImage, "trash")
        XCTAssertEqual(eraseRecovery.primaryTitle, "Retry data erasure")
        XCTAssertEqual(eraseRecovery.primarySystemImage, "trash")
        XCTAssertNil(eraseRecovery.recoveryTitle)
        XCTAssertNil(eraseRecovery.statusMessage)
    }

    func testAccessMotionPolicyKeepsWorkingStatePurposefulAndReduceMotionStatic() {
        let standard = ScreenTimeAccessMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .animated)
        XCTAssertNotNil(standard.animation)
        XCTAssertTrue(standard.permitsWorkingPulse)
        XCTAssertTrue(standard.permitsSuccessEffect)

        let reduced = ScreenTimeAccessMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
        XCTAssertFalse(reduced.permitsWorkingPulse)
        XCTAssertFalse(reduced.permitsSuccessEffect)
    }

    func testConnectedFeedbackIsOneShotAndRearmsAfterAuthorizationDrops() {
        var feedback = ScreenTimeAccessFeedbackCoordinator()

        XCTAssertFalse(feedback.consumeConnectedTransition(state: .permissionRequired))
        XCTAssertTrue(feedback.consumeConnectedTransition(state: .connected))
        XCTAssertFalse(feedback.consumeConnectedTransition(state: .connected))

        XCTAssertFalse(feedback.consumeConnectedTransition(state: .accessOff))
        XCTAssertTrue(feedback.consumeConnectedTransition(state: .connected))
    }

    func testRecoveryRoutingOnlyOpensProtectedAppsForCompletedReturningRecovery() {
        XCTAssertTrue(
            ScreenTimeAccessRecoveryRouting.shouldPresentProtectedApps(
                context: .restoreProtection,
                authorizationBecameAvailable: true,
                requiresProtectedAppReselection: true
            )
        )

        for context in [
            ScreenTimeAccessContext.initialSetup,
            .resumeSetup,
            .eraseRecovery
        ] {
            XCTAssertFalse(
                ScreenTimeAccessRecoveryRouting.shouldPresentProtectedApps(
                    context: context,
                    authorizationBecameAvailable: true,
                    requiresProtectedAppReselection: true
                )
            )
        }

        XCTAssertFalse(
            ScreenTimeAccessRecoveryRouting.shouldPresentProtectedApps(
                context: .restoreProtection,
                authorizationBecameAvailable: false,
                requiresProtectedAppReselection: true
            )
        )
        XCTAssertFalse(
            ScreenTimeAccessRecoveryRouting.shouldPresentProtectedApps(
                context: .restoreProtection,
                authorizationBecameAvailable: true,
                requiresProtectedAppReselection: false
            )
        )
    }

    func testReturningUserGoalCreationStillRoutesAccessRecoveryFromRoot() {
        XCTAssertFalse(
            OnboardingScreenTimeAccessRouting.shouldPresentOnboarding(
                isRequested: true,
                isAuthorized: false,
                isAlreadyActive: false
            )
        )
        XCTAssertEqual(
            OnboardingScreenTimeAccessRouting.recoveryHost(
                requiresRecovery: true,
                isOnboardingActive: false
            ),
            .root
        )
    }

    func testFirstLaunchPresentsGoalWalkthroughBeforeScreenTimeAuthorization() {
        let defersAuthorization = OnboardingScreenTimeAccessRouting.shouldDeferAuthorization(
            hasGoal: false,
            isFirstRunPending: false,
            needsSkillMapReview: false,
            isOnboardingRequested: true,
            isOnboardingActive: false
        )
        XCTAssertTrue(defersAuthorization, "The first render precedes persisted setup initialization")
        XCTAssertTrue(OnboardingScreenTimeAccessRouting.shouldPresentOnboarding(
            isRequested: true,
            isAuthorized: false,
            isAlreadyActive: false,
            isInitialGoalSetup: defersAuthorization
        ))

        var gate = ScreenTimeAccessGateCoordinator()
        gate.reconcile(
            isAuthorized: false,
            requiredHost: nil,
            defersAuthorization: defersAuthorization
        )
        XCTAssertEqual(gate.phase, .hidden)
        XCTAssertFalse(gate.blocksUnderlyingPresentations)
    }

    func testSavedUnapprovedSkillMapDefersAuthorizationBeforeReviewResumes() {
        XCTAssertTrue(OnboardingScreenTimeAccessRouting.shouldDeferAuthorization(
            hasGoal: true,
            isFirstRunPending: true,
            needsSkillMapReview: true,
            isOnboardingRequested: false,
            isOnboardingActive: false
        ))
    }

    func testFirstGoalWalkthroughWaitsForDataEraseRecoveryButKeepsAnActiveDraft() {
        XCTAssertFalse(OnboardingScreenTimeAccessRouting.shouldPresentOnboarding(
            isRequested: true,
            isAuthorized: false,
            isAlreadyActive: false,
            isInitialGoalSetup: true,
            requiresDataEraseRecovery: true
        ))
        XCTAssertTrue(OnboardingScreenTimeAccessRouting.shouldPresentOnboarding(
            isRequested: true,
            isAuthorized: false,
            isAlreadyActive: true,
            isInitialGoalSetup: true,
            requiresDataEraseRecovery: true
        ))
    }

    func testApprovedSkillMapWaitsForOnboardingDismissalThenRequiresScreenTime() {
        var gate = ScreenTimeAccessGateCoordinator()
        let duringDismissal = OnboardingScreenTimeAccessRouting.shouldDeferAuthorization(
            hasGoal: true,
            isFirstRunPending: true,
            needsSkillMapReview: false,
            isOnboardingRequested: false,
            isOnboardingActive: true
        )
        XCTAssertTrue(duringDismissal)
        gate.reconcile(
            isAuthorized: false,
            requiredHost: nil,
            defersAuthorization: duringDismissal
        )
        XCTAssertEqual(gate.phase, .hidden)

        let afterDismissal = OnboardingScreenTimeAccessRouting.shouldDeferAuthorization(
            hasGoal: true,
            isFirstRunPending: true,
            needsSkillMapReview: false,
            isOnboardingRequested: false,
            isOnboardingActive: false
        )
        XCTAssertFalse(afterDismissal)
        gate.reconcile(
            isAuthorized: false,
            requiredHost: .root,
            defersAuthorization: afterDismissal
        )
        XCTAssertEqual(gate.phase, .required(.root))
        XCTAssertTrue(gate.blocksUnderlyingPresentations)
        XCTAssertFalse(FirstRunSetupProgress.shouldResumeAppSelection(
            isPending: true,
            hasGoal: true,
            isAuthorized: false,
            isOnboardingPresented: false
        ))

        gate.presentationDidAppear(host: .root, isAuthorizationGateVisible: true)
        gate.reconcile(isAuthorized: true, requiredHost: nil)
        XCTAssertTrue(gate.continueAfterConnection())
        XCTAssertTrue(gate.blocksUnderlyingPresentations)
        XCTAssertTrue(gate.presentationDidDisappear(host: .root))
        XCTAssertFalse(gate.blocksUnderlyingPresentations)
        XCTAssertTrue(FirstRunSetupProgress.shouldResumeAppSelection(
            isPending: true,
            hasGoal: true,
            isAuthorized: true,
            isOnboardingPresented: false
        ))
    }

    func testReturningGoalEditorCannotDeferPermissionRecovery() {
        XCTAssertFalse(OnboardingScreenTimeAccessRouting.shouldDeferAuthorization(
            hasGoal: true,
            isFirstRunPending: false,
            needsSkillMapReview: false,
            isOnboardingRequested: true,
            isOnboardingActive: true
        ))
    }

    func testRestartingGoalSetupDismissesPriorGateWithoutConnectedSuccess() {
        var gate = ScreenTimeAccessGateCoordinator()
        gate.reconcile(isAuthorized: false, requiredHost: .root)
        gate.presentationDidAppear(host: .root, isAuthorizationGateVisible: true)

        gate.reconcile(
            isAuthorized: false,
            requiredHost: nil,
            defersAuthorization: true
        )

        XCTAssertEqual(gate.phase, .hidden)
        XCTAssertFalse(gate.isConnected)
        XCTAssertFalse(gate.continueAfterConnection())
        XCTAssertTrue(gate.blocksUnderlyingPresentations, "The old cover must finish dismissing")
        XCTAssertFalse(gate.presentationDidDisappear(host: .root))
        XCTAssertFalse(gate.blocksUnderlyingPresentations)
        XCTAssertEqual(
            OnboardingScreenTimeAccessRouting.recoveryHost(
                requiresRecovery: true,
                isOnboardingActive: false
            ),
            .root,
            "Data erase recovery remains separately presentable during the walkthrough"
        )
    }

    func testAuthorizationLossKeepsActiveOnboardingAndHostsRecoveryAboveItsDraft() {
        XCTAssertTrue(
            OnboardingScreenTimeAccessRouting.shouldPresentOnboarding(
                isRequested: true,
                isAuthorized: false,
                isAlreadyActive: true
            )
        )
        XCTAssertEqual(
            OnboardingScreenTimeAccessRouting.recoveryHost(
                requiresRecovery: true,
                isOnboardingActive: true
            ),
            .onboarding
        )
    }

    func testOnboardingRequestStillControlsDismissalDuringAuthorizationLoss() {
        XCTAssertFalse(
            OnboardingScreenTimeAccessRouting.shouldPresentOnboarding(
                isRequested: false,
                isAuthorized: false,
                isAlreadyActive: true
            )
        )
    }

    func testAuthorizedOnboardingUsesNormalSheetRoutingWithoutRecovery() {
        XCTAssertTrue(
            OnboardingScreenTimeAccessRouting.shouldPresentOnboarding(
                isRequested: true,
                isAuthorized: true,
                isAlreadyActive: false
            )
        )
        XCTAssertNil(
            OnboardingScreenTimeAccessRouting.recoveryHost(
                requiresRecovery: false,
                isOnboardingActive: false
            )
        )
    }

    func testAccessGateNeverShowsConnectedForAnAuthorizedColdLaunch() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: true, requiredHost: nil)

        XCTAssertEqual(gate.phase, .hidden)
        XCTAssertNil(gate.presentationHost)
        XCTAssertFalse(gate.isConnected)
        XCTAssertFalse(gate.blocksUnderlyingPresentations)
    }

    func testAccessGateOnlyConnectsAfterItsRequiredCoverAppears() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: false, requiredHost: .root)
        XCTAssertEqual(gate.phase, .required(.root))
        XCTAssertTrue(gate.blocksUnderlyingPresentations)

        gate.reconcile(isAuthorized: true, requiredHost: nil)

        XCTAssertEqual(gate.phase, .hidden)
        XCTAssertNil(gate.presentationHost)
        XCTAssertFalse(gate.isConnected)
        XCTAssertFalse(gate.blocksUnderlyingPresentations)
    }

    func testAccessGatePreservesItsHostUntilConnectedDismissalFinishes() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: false, requiredHost: .onboarding)
        gate.presentationDidAppear(
            host: .onboarding,
            isAuthorizationGateVisible: true
        )
        gate.reconcile(isAuthorized: false, requiredHost: .root)
        XCTAssertEqual(gate.phase, .required(.onboarding))

        gate.reconcile(isAuthorized: true, requiredHost: nil)
        XCTAssertEqual(gate.phase, .connected(.onboarding))
        XCTAssertEqual(gate.presentationHost, .onboarding)
        XCTAssertTrue(gate.isConnected)

        XCTAssertTrue(gate.continueAfterConnection())
        XCTAssertFalse(gate.continueAfterConnection(), "Continue must be idempotent")
        XCTAssertEqual(gate.phase, .hidden)
        XCTAssertNil(gate.presentationHost)
        XCTAssertEqual(gate.dismissalHost, .onboarding)
        XCTAssertTrue(
            gate.blocksUnderlyingPresentations,
            "Underlying handoffs must wait for the connected cover to finish dismissing"
        )

        XCTAssertFalse(gate.presentationDidDisappear(host: .root))
        XCTAssertTrue(gate.blocksUnderlyingPresentations)
        XCTAssertTrue(gate.presentationDidDisappear(host: .onboarding))
        XCTAssertFalse(gate.blocksUnderlyingPresentations)
    }

    func testAccessGateReturnsToRequiredOnAuthorizationLoss() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: false, requiredHost: .root)
        gate.presentationDidAppear(
            host: .root,
            isAuthorizationGateVisible: true
        )
        gate.reconcile(isAuthorized: true, requiredHost: nil)
        XCTAssertEqual(gate.phase, .connected(.root))

        gate.reconcile(isAuthorized: false, requiredHost: .onboarding)

        XCTAssertEqual(gate.phase, .required(.root))
        XCTAssertEqual(gate.presentationHost, .root)
        XCTAssertFalse(gate.isConnected)
        XCTAssertFalse(gate.continueAfterConnection())
        XCTAssertTrue(gate.blocksUnderlyingPresentations)
    }

    func testAnyAccessCoverBlocksUnderlyingRoutesWithoutEarningConnected() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: false, requiredHost: .root)
        gate.presentationDidAppear(
            host: .root,
            isAuthorizationGateVisible: false
        )
        XCTAssertEqual(gate.presentedHost, .root)
        XCTAssertNil(gate.visibleGateHost)
        XCTAssertTrue(gate.blocksUnderlyingPresentations)

        gate.reconcile(isAuthorized: true, requiredHost: nil)

        XCTAssertEqual(gate.phase, .hidden)
        XCTAssertFalse(gate.isConnected, "An erase-only cover must not earn success")
        XCTAssertFalse(gate.presentationDidDisappear(host: .onboarding))
        XCTAssertTrue(gate.blocksUnderlyingPresentations)
        XCTAssertFalse(gate.presentationDidDisappear(host: .root))
        XCTAssertFalse(gate.blocksUnderlyingPresentations)
    }

    func testAccessGateCanBecomeVisibleAfterEraseRecoveryFinishes() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: false, requiredHost: .root)
        gate.presentationDidAppear(
            host: .root,
            isAuthorizationGateVisible: false
        )
        gate.updatePresentedContent(
            host: .root,
            isAuthorizationGateVisible: true
        )
        gate.reconcile(isAuthorized: true, requiredHost: nil)

        XCTAssertEqual(gate.phase, .connected(.root))
        XCTAssertEqual(gate.visibleGateHost, .root)
    }

    func testAccessGateRehomesOnlyToThePresentedEraseRecoveryHost() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: false, requiredHost: .onboarding)
        gate.presentationDidAppear(
            host: .onboarding,
            isAuthorizationGateVisible: true
        )

        gate.reconcile(isAuthorized: false, requiredHost: .root)
        XCTAssertEqual(
            gate.phase,
            .required(.onboarding),
            "A routing preference alone must not move a visible gate"
        )

        gate.presentationDidAppear(
            host: .root,
            isAuthorizationGateVisible: false
        )
        gate.reconcile(isAuthorized: false, requiredHost: .root)

        XCTAssertEqual(gate.phase, .required(.root))
        XCTAssertEqual(gate.presentedHost, .root)
        XCTAssertNil(gate.visibleGateHost)
        XCTAssertTrue(gate.blocksUnderlyingPresentations)

        gate.updatePresentedContent(
            host: .root,
            isAuthorizationGateVisible: true
        )
        XCTAssertEqual(gate.visibleGateHost, .root)

        gate.reconcile(isAuthorized: true, requiredHost: nil)
        XCTAssertEqual(gate.phase, .connected(.root))
    }

    func testAccessGateRehomesIfEraseOverrideDismissesBeforeReconcile() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: false, requiredHost: .onboarding)
        gate.presentationDidAppear(
            host: .onboarding,
            isAuthorizationGateVisible: true
        )
        gate.presentationDidAppear(
            host: .root,
            isAuthorizationGateVisible: false
        )

        XCTAssertFalse(
            gate.presentationDidDisappear(host: .root, requiredHost: .root)
        )
        XCTAssertEqual(gate.phase, .required(.root))
        XCTAssertNil(gate.presentedHost)
        XCTAssertTrue(gate.blocksUnderlyingPresentations)

        gate.presentationDidAppear(
            host: .root,
            isAuthorizationGateVisible: true
        )
        gate.reconcile(isAuthorized: true, requiredHost: nil)
        XCTAssertEqual(gate.phase, .connected(.root))
    }

    func testAccessGateDoesNotConnectFromStaleCrossHostVisibility() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: false, requiredHost: .onboarding)
        gate.presentationDidAppear(
            host: .onboarding,
            isAuthorizationGateVisible: true
        )
        XCTAssertEqual(gate.visibleGateHost, .onboarding)

        gate.presentationDidAppear(
            host: .root,
            isAuthorizationGateVisible: false
        )
        XCTAssertEqual(gate.presentedHost, .root)
        XCTAssertNil(gate.visibleGateHost)

        gate.reconcile(isAuthorized: true, requiredHost: nil)

        XCTAssertEqual(gate.phase, .hidden)
        XCTAssertFalse(gate.isConnected)
        XCTAssertTrue(
            gate.blocksUnderlyingPresentations,
            "The root erase cover still owns routing until its dismissal"
        )
        XCTAssertFalse(gate.presentationDidDisappear(host: .root))
        XCTAssertFalse(gate.blocksUnderlyingPresentations)
    }

    func testCrossHostEraseOverrideCancelsAnExistingConnectedHandoff() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: false, requiredHost: .onboarding)
        gate.presentationDidAppear(
            host: .onboarding,
            isAuthorizationGateVisible: true
        )
        gate.reconcile(isAuthorized: true, requiredHost: nil)
        XCTAssertEqual(gate.phase, .connected(.onboarding))

        gate.presentationDidAppear(
            host: .root,
            isAuthorizationGateVisible: false
        )

        XCTAssertEqual(gate.phase, .hidden)
        XCTAssertNil(gate.visibleGateHost)
        XCTAssertEqual(gate.presentedHost, .root)
        XCTAssertTrue(gate.blocksUnderlyingPresentations)

        XCTAssertFalse(gate.presentationDidDisappear(host: .root))
        XCTAssertFalse(gate.blocksUnderlyingPresentations)
    }

    func testAuthorizationLossDuringConnectedDismissalRestoresRequiredGate() {
        var gate = ScreenTimeAccessGateCoordinator()

        gate.reconcile(isAuthorized: false, requiredHost: .root)
        gate.presentationDidAppear(
            host: .root,
            isAuthorizationGateVisible: true
        )
        gate.reconcile(isAuthorized: true, requiredHost: nil)
        XCTAssertTrue(gate.continueAfterConnection())

        gate.reconcile(isAuthorized: false, requiredHost: .onboarding)

        XCTAssertEqual(gate.phase, .required(.root))
        XCTAssertEqual(gate.presentationHost, .root)
        XCTAssertTrue(gate.blocksUnderlyingPresentations)
        XCTAssertFalse(gate.presentationDidDisappear(host: .root))
        XCTAssertEqual(gate.phase, .required(.root))
        XCTAssertTrue(gate.blocksUnderlyingPresentations)

        gate.presentationDidAppear(
            host: .root,
            isAuthorizationGateVisible: true
        )
        gate.reconcile(isAuthorized: true, requiredHost: nil)
        XCTAssertEqual(gate.phase, .connected(.root))
    }

    func testRecoveryQueueRetriesAfterACompetingModalDismisses() {
        var queue = ScreenTimeAccessRecoveryQueue()

        queue.enqueue(if: true)
        XCTAssertTrue(queue.isQueued)
        XCTAssertFalse(
            queue.beginScheduling(shouldRecover: true, canPresent: false)
        )
        XCTAssertTrue(queue.isQueued)
        XCTAssertFalse(queue.isScheduling)

        XCTAssertTrue(
            queue.beginScheduling(shouldRecover: true, canPresent: true)
        )
        XCTAssertTrue(queue.isScheduling)
        XCTAssertFalse(
            queue.finishScheduling(shouldRecover: true, canPresent: false)
        )
        XCTAssertTrue(queue.isQueued)
        XCTAssertFalse(queue.isScheduling)

        XCTAssertTrue(
            queue.beginScheduling(shouldRecover: true, canPresent: true)
        )
        XCTAssertTrue(
            queue.finishScheduling(shouldRecover: true, canPresent: true)
        )
        XCTAssertFalse(queue.isQueued)
        XCTAssertFalse(queue.isScheduling)
    }

    func testRecoveryQueueCancelsWhenRecoveryIsNoLongerNeeded() {
        var queue = ScreenTimeAccessRecoveryQueue()
        queue.enqueue(if: true)

        XCTAssertFalse(
            queue.beginScheduling(shouldRecover: false, canPresent: true)
        )
        XCTAssertFalse(queue.isQueued)
        XCTAssertFalse(queue.isScheduling)
    }

    @MainActor
    func testScreenTimeAccessStatesRenderAcrossRecoveryMatrix() async throws {
        UserDefaults.standard.removeObject(
            forKey: ScreenTimeController.sharedDataEraseIncompleteKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: ScreenTimeController.sharedDataEraseIncompleteKey
            )
        }

        let fixtures = [
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-initial-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                context: .initialSetup,
                controllerState: .status(.notDetermined),
                hasGoal: false
            ),
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-connected-initial-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                context: .initialSetup,
                controllerState: .status(.approved),
                hasGoal: false
            ),
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-requesting-standard-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                reduceMotion: false,
                context: .initialSetup,
                controllerState: .requesting,
                hasGoal: false
            ),
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-initial-accessibility5-dark-reduced",
                width: 393,
                height: 1_650,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                context: .initialSetup,
                controllerState: .status(.notDetermined),
                hasGoal: false
            ),
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-connected-resume-accessibility5-dark-reduced",
                width: 393,
                height: 1_650,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                context: .resumeSetup,
                controllerState: .status(.approvedWithDataAccess),
                hasGoal: true
            ),
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-resume-failed-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                context: .resumeSetup,
                controllerState: .failed,
                hasGoal: true
            ),
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-returning-denied-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                reduceMotion: false,
                context: .restoreProtection,
                controllerState: .status(.denied),
                hasGoal: true
            ),
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-unavailable-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                context: .initialSetup,
                controllerState: .status(.unavailable),
                hasGoal: false
            ),
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-selection-recovery-ax2-light-reduced",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                reduceMotion: true,
                context: .restoreProtection,
                controllerState: .selectionLost,
                hasGoal: true
            ),
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-connected-selection-recovery-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                reduceMotion: false,
                context: .restoreProtection,
                controllerState: .connectedSelectionRecovery,
                hasGoal: true
            ),
            ScreenTimeAccessRenderFixture(
                name: "screen-time-access-erase-recovery-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                context: .eraseRecovery,
                controllerState: .eraseRecoveryFailure,
                hasGoal: true
            )
        ]

        for fixture in fixtures {
            resetSharedAppGroupState()
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            UserDefaults.standard.removeObject(
                forKey: ScreenTimeController.sharedDataEraseIncompleteKey
            )

            let store = CheckpointStore(defaults: defaults)
            if fixture.hasGoal {
                let goal = makeGoal()
                store.goal = goal
                store.goalProfiles = [goal]
            }
            if fixture.controllerState == .connectedSelectionRecovery {
                defaults.set(
                    true,
                    forKey: SharedAppGroup.screenTimeSelectionRecoveryRequiredKey
                )
            }
            let simulatesEraseRecovery = fixture.controllerState == .eraseRecoveryFailure
            if simulatesEraseRecovery {
                UserDefaults.standard.set(
                    true,
                    forKey: ScreenTimeController.sharedDataEraseIncompleteKey
                )
            }

            let initialStatus: ScreenTimeAuthorizationStatus
            switch fixture.controllerState {
            case let .status(status):
                initialStatus = status
            case .requesting, .failed:
                initialStatus = .notDetermined
            case .selectionLost, .connectedSelectionRecovery, .eraseRecoveryFailure:
                initialStatus = .approved
            }

            let authorizer = ScreenTimeAccessRenderAuthorizer(
                authorizationStatus: initialStatus,
                suspendsRequests: fixture.controllerState == .requesting,
                failsRequests: fixture.controllerState == .failed
            )
            let screenTime = ScreenTimeController(
                defaults: defaults,
                authorizer: authorizer,
                sharedDataEraser: {
                    if simulatesEraseRecovery {
                        throw ScreenTimeAccessRenderError.sharedDataEraseFailed
                    }
                }
            )

            var requestTask: Task<Void, Never>?
            switch fixture.controllerState {
            case .requesting:
                requestTask = Task { @MainActor in
                    await screenTime.requestAuthorization()
                }
                for _ in 0..<20 where !authorizer.hasSuspendedRequest {
                    await Task.yield()
                }
                XCTAssertTrue(authorizer.hasSuspendedRequest, fixture.name)
                XCTAssertTrue(screenTime.isRequestingAuthorization, fixture.name)
            case .failed:
                await screenTime.requestAuthorization()
                XCTAssertEqual(screenTime.authorizationState, .failed, fixture.name)
            case .selectionLost:
                try configureSelectionLoss(
                    screenTime: screenTime,
                    authorizer: authorizer
                )
                XCTAssertTrue(screenTime.requiresProtectedAppReselection, fixture.name)
                XCTAssertFalse(screenTime.hasRequiredScreenTimeAuthorization, fixture.name)
            case .connectedSelectionRecovery:
                XCTAssertTrue(screenTime.requiresProtectedAppReselection, fixture.name)
                XCTAssertTrue(screenTime.hasRequiredScreenTimeAuthorization, fixture.name)
            case .eraseRecoveryFailure:
                XCTAssertTrue(screenTime.requiresSharedDataEraseRecovery, fixture.name)
                XCTAssertNotNil(screenTime.sharedDataEraseErrorMessage, fixture.name)
            case .status:
                break
            }

            let layoutCapture = ScreenTimeAccessLayoutCapture()
            let image = HostedViewRenderer.image(
                for: RequiredScreenTimeAccessView(
                    store: store,
                    screenTime: screenTime,
                    purchaseController: PurchaseController(
                        grantsDebugTesterEntitlement: false,
                        pendingPurchaseDefaults: nil
                    ),
                    context: fixture.context,
                    reduceMotionOverride: fixture.reduceMotion,
                    layoutReporter: { element, frame in
                        layoutCapture.frames[element] = frame
                    }
                )
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: fixture.reduceMotion ? 0.05 : 0.2,
                renderScale: 1
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)

            if fixture.expectsConnectedHandoff {
                let viewport = try XCTUnwrap(
                    layoutCapture.frames[.viewport],
                    fixture.name
                )
                let hero = try XCTUnwrap(layoutCapture.frames[.hero], fixture.name)
                let actionBar = try XCTUnwrap(
                    layoutCapture.frames[.actionBar],
                    fixture.name
                )
                let primaryAction = try XCTUnwrap(
                    layoutCapture.frames[.primaryAction],
                    fixture.name
                )
                let canvas = CGRect(
                    x: 0,
                    y: 0,
                    width: fixture.width,
                    height: fixture.height
                )

                for frame in [viewport, hero, actionBar, primaryAction] {
                    XCTAssertFalse(frame.isNull, fixture.name)
                    XCTAssertFalse(frame.isInfinite, fixture.name)
                    XCTAssertGreaterThan(frame.width, 0, fixture.name)
                    XCTAssertGreaterThan(frame.height, 0, fixture.name)
                }
                XCTAssertGreaterThanOrEqual(hero.minX, viewport.minX - 0.5, fixture.name)
                XCTAssertLessThanOrEqual(hero.maxX, viewport.maxX + 0.5, fixture.name)
                XCTAssertTrue(
                    canvas.insetBy(dx: -0.5, dy: -0.5).contains(actionBar),
                    "\(fixture.name) action bar escaped the rendered screen"
                )
                XCTAssertTrue(
                    actionBar.insetBy(dx: -0.5, dy: -0.5).contains(primaryAction),
                    "\(fixture.name) Continue action escaped its safe-area bar"
                )
                XCTAssertGreaterThanOrEqual(
                    primaryAction.height,
                    43.5,
                    "\(fixture.name) Continue action is smaller than an accessible tap target"
                )
            }

            if fixture.expectsEraseRecovery {
                let error = try XCTUnwrap(
                    layoutCapture.frames[.statusMessage],
                    fixture.name
                )
                let actionBar = try XCTUnwrap(
                    layoutCapture.frames[.actionBar],
                    fixture.name
                )
                let primaryAction = try XCTUnwrap(
                    layoutCapture.frames[.primaryAction],
                    fixture.name
                )
                XCTAssertNil(
                    layoutCapture.frames[.eraseLink],
                    "\(fixture.name) exposed the ordinary erase link during recovery"
                )
                XCTAssertLessThanOrEqual(
                    error.maxY,
                    actionBar.minY + 0.5,
                    "\(fixture.name) recovery error overlapped the retry action bar"
                )
                XCTAssertTrue(
                    actionBar.insetBy(dx: -0.5, dy: -0.5).contains(primaryAction),
                    "\(fixture.name) retry action escaped its safe-area bar"
                )
                XCTAssertGreaterThanOrEqual(primaryAction.height, 43.5, fixture.name)
            }

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = XCTAttachment.Lifetime.keepAlways
            add(attachment)

            if let requestTask {
                authorizer.completeSuspendedRequest(with: .notDetermined)
                await requestTask.value
            }
        }
    }

    @MainActor
    private func configureSelectionLoss(
        screenTime: ScreenTimeController,
        authorizer: ScreenTimeAccessRenderAuthorizer
    ) throws {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        let applicationToken = try JSONDecoder().decode(
            ManagedSettings.ApplicationToken.self,
            from: Data(#"{"data":"AQIDBA=="}"#.utf8)
        )
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        selection.applicationTokens = [applicationToken]
        XCTAssertTrue(screenTime.updateSelection(selection))
        XCTAssertTrue(screenTime.hasSelection)

        authorizer.authorizationStatus = .denied
        screenTime.refreshAuthorizationStatus()
        XCTAssertFalse(screenTime.hasSelection)
        #else
        XCTFail("Screen Time selection recovery renders require FamilyControls and ManagedSettings")
        #endif
    }
}

private struct ScreenTimeAccessRenderFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let reduceMotion: Bool
    let context: ScreenTimeAccessContext
    let controllerState: ScreenTimeAccessRenderControllerState
    let hasGoal: Bool

    var expectsConnectedHandoff: Bool {
        guard context != .eraseRecovery else { return false }
        switch controllerState {
        case .status(.approved), .status(.approvedWithDataAccess),
             .connectedSelectionRecovery:
            return true
        case .status, .requesting, .failed, .selectionLost, .eraseRecoveryFailure:
            return false
        }
    }

    var expectsEraseRecovery: Bool {
        controllerState == .eraseRecoveryFailure
    }
}

private enum ScreenTimeAccessRenderControllerState: Equatable {
    case status(ScreenTimeAuthorizationStatus)
    case requesting
    case failed
    case selectionLost
    case connectedSelectionRecovery
    case eraseRecoveryFailure
}

@MainActor
private final class ScreenTimeAccessLayoutCapture {
    var frames: [ScreenTimeAccessLayoutElement: CGRect] = [:]
}

@MainActor
private final class ScreenTimeAccessRenderAuthorizer: ScreenTimeAuthorizing {
    var authorizationStatus: ScreenTimeAuthorizationStatus
    private(set) var hasSuspendedRequest = false

    private var suspendsRequests: Bool
    private let failsRequests: Bool
    private var requestContinuation: CheckedContinuation<Void, Never>?

    init(
        authorizationStatus: ScreenTimeAuthorizationStatus,
        suspendsRequests: Bool = false,
        failsRequests: Bool = false
    ) {
        self.authorizationStatus = authorizationStatus
        self.suspendsRequests = suspendsRequests
        self.failsRequests = failsRequests
    }

    func requestAuthorization() async throws {
        if failsRequests {
            throw ScreenTimeAccessRenderError.authorizationFailed
        }
        guard suspendsRequests else { return }
        await withCheckedContinuation { continuation in
            hasSuspendedRequest = true
            requestContinuation = continuation
        }
    }

    func completeSuspendedRequest(with status: ScreenTimeAuthorizationStatus) {
        authorizationStatus = status
        suspendsRequests = false
        hasSuspendedRequest = false
        requestContinuation?.resume()
        requestContinuation = nil
    }
}

private enum ScreenTimeAccessRenderError: Error {
    case authorizationFailed
    case sharedDataEraseFailed
}
