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

    func testInitialSetupPresentationUsesTheOnlyNumberedAccessStep() {
        let initial = ScreenTimeAccessPresentation(
            context: .initialSetup,
            authorizationState: .notDetermined,
            requiresProtectedAppReselection: false
        )

        XCTAssertEqual(initial.stage, "Screen Time")
        XCTAssertEqual(initial.step, 1)
        XCTAssertEqual(initial.state, .permissionRequired)
        XCTAssertEqual(initial.state.status, "Permission needed")
        XCTAssertEqual(initial.state.systemImage, "checkmark.shield")
        XCTAssertEqual(initial.state.tone, .informational)
        XCTAssertEqual(initial.heading, "Practice before you scroll.")
        XCTAssertEqual(initial.primaryAction, .request)
        XCTAssertEqual(initial.primaryTitle, "Allow Screen Time")
        XCTAssertEqual(initial.primarySystemImage, "checkmark.shield")
        XCTAssertFalse(initial.isWorking)
        XCTAssertTrue(initial.showsSetupSequence)
        XCTAssertTrue(initial.showsPrivacyProofInHero)
        XCTAssertNil(initial.recoveryTitle)
        XCTAssertNil(initial.statusMessage)

        for context in [
            ScreenTimeAccessContext.resumeSetup,
            .restoreProtection,
            .eraseRecovery
        ] {
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
        XCTAssertEqual(unavailable.heading, "App protection needs an iPhone")
        XCTAssertFalse(unavailable.showsSetupSequence)
        XCTAssertFalse(unavailable.showsPrivacyProofInHero)
        XCTAssertNil(unavailable.primaryTitle)
        XCTAssertNil(unavailable.primarySystemImage)

        let initialUnavailable = ScreenTimeAccessPresentation(
            context: .initialSetup,
            authorizationState: .unavailable,
            requiresProtectedAppReselection: false
        )
        XCTAssertEqual(initialUnavailable.heading, "Screen Time access needs an iPhone")
        XCTAssertFalse(initialUnavailable.showsSetupSequence)
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
            XCTAssertEqual(approved.primaryAction, .none)
            XCTAssertEqual(approved.state, .connected)
            XCTAssertEqual(approved.state.status, "Connected")
            XCTAssertEqual(approved.state.tone, .success)
            XCTAssertFalse(approved.isWorking)
            XCTAssertNil(approved.statusMessage)
        }
    }

    func testRecoveryPresentationExplainsSelectionLossWithoutLosingLearningData() {
        let selectionRecovery = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .approved,
            requiresProtectedAppReselection: true
        )

        XCTAssertEqual(selectionRecovery.stage, "Protection paused")
        XCTAssertNil(selectionRecovery.step)
        XCTAssertFalse(selectionRecovery.showsSetupSequence)
        XCTAssertEqual(selectionRecovery.recoveryTitle, "Your learning data is safe")
        XCTAssertEqual(selectionRecovery.recoverySystemImage, "lock.shield.fill")
        XCTAssertTrue(selectionRecovery.detail.localizedCaseInsensitiveContains("selected again"))
        XCTAssertTrue(selectionRecovery.recoveryDetail?.localizedCaseInsensitiveContains("progress") == true)
        XCTAssertTrue(selectionRecovery.recoveryDetail?.localizedCaseInsensitiveContains("choose apps again") == true)

        let reconnectOnly = ScreenTimeAccessPresentation(
            context: .restoreProtection,
            authorizationState: .approved,
            requiresProtectedAppReselection: false
        )
        XCTAssertFalse(reconnectOnly.detail.localizedCaseInsensitiveContains("selected again"))
        XCTAssertTrue(reconnectOnly.recoveryDetail?.localizedCaseInsensitiveContains("practice data") == true)

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
        XCTAssertFalse(eraseRecovery.showsSetupSequence)
        XCTAssertNil(eraseRecovery.recoveryTitle)
        XCTAssertNil(eraseRecovery.statusMessage)
    }

    func testAccessMotionPolicyKeepsWorkingStatePurposefulAndReduceMotionStatic() {
        let standard = ScreenTimeAccessMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .animated)
        XCTAssertNotNil(standard.animation)
        XCTAssertTrue(standard.permitsWorkingPulse)

        let reduced = ScreenTimeAccessMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
        XCTAssertFalse(reduced.permitsWorkingPulse)
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
                name: "screen-time-access-erase-recovery-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                context: .eraseRecovery,
                controllerState: .status(.approved),
                hasGoal: true
            )
        ]

        for fixture in fixtures {
            resetSharedAppGroupState()
            defaults.removePersistentDomain(forName: defaultsSuiteName)

            let store = CheckpointStore(defaults: defaults)
            if fixture.hasGoal {
                let goal = makeGoal()
                store.goal = goal
                store.goalProfiles = [goal]
            }

            let initialStatus: ScreenTimeAuthorizationStatus
            switch fixture.controllerState {
            case let .status(status):
                initialStatus = status
            case .requesting, .failed:
                initialStatus = .notDetermined
            case .selectionLost:
                initialStatus = .approved
            }

            let authorizer = ScreenTimeAccessRenderAuthorizer(
                authorizationStatus: initialStatus,
                suspendsRequests: fixture.controllerState == .requesting,
                failsRequests: fixture.controllerState == .failed
            )
            let screenTime = ScreenTimeController(
                defaults: defaults,
                authorizer: authorizer
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
            case .status:
                break
            }

            let image = HostedViewRenderer.image(
                for: RequiredScreenTimeAccessView(
                    store: store,
                    screenTime: screenTime,
                    context: fixture.context,
                    reduceMotionOverride: fixture.reduceMotion
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
}

private enum ScreenTimeAccessRenderControllerState: Equatable {
    case status(ScreenTimeAuthorizationStatus)
    case requesting
    case failed
    case selectionLost
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
}
