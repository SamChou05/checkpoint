import Foundation
import Observation

@MainActor
protocol AppProtectionControlling: AnyObject {
    var hasSelection: Bool { get }
    var isShieldingEnabled: Bool { get }
    var userFacingErrorMessage: String? { get }

    func applyShield()
    func clearShield()
    func temporarilyUnshield(until expiration: Date) -> Bool
    func reconcileShieldState(protectionShouldRemainActive: Bool?)
    func refreshActiveShieldConfiguration()
}

extension ScreenTimeController: AppProtectionControlling {}

@MainActor
@Observable
final class CheckpointWorkflowCoordinator {
    enum Operation: Equatable {
        case startingProtection
        case claimingShieldAttempt
    }

    private(set) var operation: Operation?

    @ObservationIgnored private let store: CheckpointStore
    @ObservationIgnored private let protection: any AppProtectionControlling
    @ObservationIgnored private let now: () -> Date

    init(
        store: CheckpointStore,
        protection: any AppProtectionControlling,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.protection = protection
        self.now = now
    }

    var isStartingProtection: Bool {
        operation == .startingProtection
    }

    @discardableResult
    func startProtection() async -> Bool {
        guard operation == nil else { return false }
        operation = .startingProtection
        defer { operation = nil }

        guard await store.prepareQuestionsForProtectionStart() else { return false }
        protection.applyShield()
        return protection.isShieldingEnabled
    }

    func endBreakEarly() {
        guard store.hasReadyCheckpointSet else {
            stopProtectionWithoutReview()
            store.checkpointNotice = Self.unavailableCheckpointMessage
            return
        }
        protection.applyShield()
        if protection.isShieldingEnabled || !SharedAppGroup.desiredShieldActive {
            store.clearUnlockSession()
        }
    }

    func stopProtectionWithoutReview() {
        protection.clearShield()
        store.clearUnlockSession()
    }

    func reconcileProtectionState() {
        guard store.goal != nil else {
            reconcileEmptyGoalState()
            return
        }
        guard store.activeCheckpointRun == nil else { return }

        if SharedAppGroup.desiredShieldActive,
           !store.hasReadyCheckpointSet,
           store.unlockSession?.isActive != true {
            protection.clearShield()
            store.checkpointNotice = Self.unavailableCheckpointMessage
            return
        }

        let snapshot = SharedAppGroup.currentProtectionSnapshot()
        protection.reconcileShieldState(
            protectionShouldRemainActive: snapshot.desiredShieldActive
        )

        let reconciledSnapshot = SharedAppGroup.currentProtectionSnapshot()
        let canonicalBreakIsActive = reconciledSnapshot.unlockExpiration.map {
            $0 > now()
        } ?? false
        if store.unlockSession != nil,
           (!reconciledSnapshot.desiredShieldActive ||
            !canonicalBreakIsActive ||
            store.unlockSession?.isActive != true) {
            store.clearUnlockSession()
        }
    }

    func reconcileEmptyGoalState() {
        // Erase already removed shared state; do not recreate empty snapshots.
        guard !store.hasNoPersistedAppData else { return }
        stopProtectionWithoutReview()
    }

    func goalDidChange() {
        reconcileProtectionState()
    }

    func selectionDidChange(hasSelection: Bool) {
        if !hasSelection {
            store.clearUnlockSession()
        }
    }

    func protectionDidRelock() {
        if store.unlockSession?.isActive != true {
            store.clearUnlockSession()
        }
    }

    func refreshProtectionConfiguration() {
        protection.refreshActiveShieldConfiguration()
    }

    func preparePendingShieldSession() async -> CheckpointSession? {
        guard operation == nil else { return nil }
        operation = .claimingShieldAttempt
        defer { operation = nil }

        while let pendingAttempt = SharedAppGroup.currentPendingShieldAttempt {
            let snapshot = SharedAppGroup.currentProtectionSnapshot()
            guard snapshot.acceptsPendingShieldAttempt(
                configurationRevision: pendingAttempt.protectionConfigurationRevision,
                hasSelection: protection.hasSelection
            ) else {
                _ = SharedAppGroup.consumePendingShieldAttempt(matchingID: pendingAttempt.id)
                continue
            }

            let expectedRevision = pendingAttempt.protectionConfigurationRevision
                ?? snapshot.configurationRevision
            guard let session = await store.preparePendingShieldSession(
                pendingAttemptID: pendingAttempt.id
            ) else {
                if SharedAppGroup.currentPendingShieldAttempt?.id != pendingAttempt.id {
                    continue
                }
                return nil
            }

            let latestSnapshot = SharedAppGroup.currentProtectionSnapshot()
            let remainingAttempt = SharedAppGroup.currentPendingShieldAttempt
            if remainingAttempt == nil,
               latestSnapshot.acceptsPendingShieldAttempt(
                   configurationRevision: expectedRevision,
                   hasSelection: protection.hasSelection
               ) {
                return session
            }

            store.discardCheckpointRunBeforePresentation(sessionID: session.id)
            if remainingAttempt?.id == pendingAttempt.id {
                return nil
            }
        }

        return nil
    }

    func resolveFailed(_ session: CheckpointSession) {
        guard session.purpose != .preview else { return }
        guard store.resolveCheckpointRun(
            sessionID: session.id,
            didPass: false
        ) else { return }
        reconcileProtectionState()
    }

    @discardableResult
    func abandon(_ session: CheckpointSession) -> Bool {
        guard session.purpose != .preview else { return false }
        guard store.abandonCheckpointRun(sessionID: session.id) else { return false }
        reconcileProtectionState()
        return true
    }

    func finishPassed(_ session: CheckpointSession) -> String? {
        if session.purpose != .preview,
           store.activeCheckpointRun?.sessionID != session.id {
            return "This checkpoint is no longer active. Start a new checkpoint to change protection."
        }

        switch session.purpose {
        case .temporaryUnlock:
            let unlockMinutes = store.unlockPolicy.unlockMinutes
            let expiration = now().addingTimeInterval(TimeInterval(unlockMinutes * 60))
            guard protection.temporarilyUnshield(until: expiration) else {
                return protection.userFacingErrorMessage
                    ?? "The break could not start. Protection is still on; try again."
            }
            store.startUnlockSession(
                minutes: unlockMinutes,
                expiresAt: expiration,
                goalID: session.questions.first?.goalID
            )
            store.resolveCheckpointRun(sessionID: session.id, didPass: true)
        case .stopBlocking:
            protection.clearShield()
            store.clearUnlockSession()
            store.resolveCheckpointRun(sessionID: session.id, didPass: true)
        case .preview:
            break
        }

        return nil
    }

    private static let unavailableCheckpointMessage =
        "Protection was turned off because a full checkpoint is not ready. Prepare your questions, then start protection again."
}

@MainActor
final class CheckpointAppModel {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let purchaseController: PurchaseController
    let workflow: CheckpointWorkflowCoordinator

    init(
        store: CheckpointStore = CheckpointStore(),
        screenTime: ScreenTimeController = ScreenTimeController(),
        purchaseController: PurchaseController = PurchaseController()
    ) {
        self.store = store
        self.screenTime = screenTime
        self.purchaseController = purchaseController
        workflow = CheckpointWorkflowCoordinator(store: store, protection: screenTime)
    }
}
