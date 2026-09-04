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

enum CheckpointFailureProtectionOutcome: Equatable {
    case activeBreakContinues
    case protectionRemainsOn
    case protectionTurnedOffForUnavailableCheckpoint
    case protectionIsOff
}

enum GoalSwitchProtectionImpact: Hashable, Sendable {
    case turnsOffImmediately
    case preventsRelockAfterBreak
}

struct GoalSwitchConfirmation: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let sourceGoalID: Goal.ID?
        let targetGoalID: Goal.ID
        let impact: GoalSwitchProtectionImpact
    }

    let sourceGoalID: Goal.ID?
    let sourceTitle: String?
    let targetGoalID: Goal.ID
    let targetTitle: String
    let readiness: GoalCheckpointReadiness
    let impact: GoalSwitchProtectionImpact

    var id: ID {
        ID(
            sourceGoalID: sourceGoalID,
            targetGoalID: targetGoalID,
            impact: impact
        )
    }
}

enum GoalSwitchAuthorization: Equatable, Sendable {
    case none
    case confirmed(GoalSwitchConfirmation)
}

enum GoalSwitchOutcome: Equatable, Sendable {
    case switched(from: Goal.ID?, to: Goal.ID)
    case confirmationRequired(GoalSwitchConfirmation)
    case alreadyActive
    case targetNotFound
    case membershipRequired
    case staleRequest
    case persistenceFailed
}

enum GoalProfileMutationConsent: Equatable, Sendable {
    case deletion
    case protection(GoalSwitchProtectionImpact)
    case deletionAndProtection(GoalSwitchProtectionImpact)
}

struct GoalProfileMutationConfirmation: Identifiable, Equatable, Sendable {
    let plan: GoalProfileMutationPlan
    let consent: GoalProfileMutationConsent
    let activeBreakAtRequest: Bool

    var id: GoalProfileMutationRequest.ID {
        plan.request.id
    }
}

enum GoalProfileMutationAuthorization: Equatable, Sendable {
    case none
    case confirmed(GoalProfileMutationConfirmation)
}

enum GoalProfileMutationOutcome: Equatable, Sendable {
    case committed(resultingGoalID: Goal.ID?)
    case confirmationRequired(GoalProfileMutationConfirmation)
    case alreadyCommitted
    case invalidTitle
    case membershipRequired
    case profileLimitReached
    case targetNotFound
    case staleRequest
    case persistenceFailed
}

struct ProtectionStartResultEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let goalID: Goal.ID?
    let becameCheckpointReadyDuringStart: Bool
    let didStart: Bool
    let checkpointNotice: String?
    let protectionErrorMessage: String?
}

@MainActor
@Observable
final class CheckpointWorkflowCoordinator {
    enum Operation: Equatable {
        case startingProtection
        case claimingShieldAttempt
    }

    private(set) var operation: Operation?
    private(set) var pendingProtectionStartResult: ProtectionStartResultEvent?
    private(set) var startingProtectionReadinessGoalID: Goal.ID?

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

    func requestGoalSwitch(
        to targetGoalID: Goal.ID,
        authorization: GoalSwitchAuthorization = .none
    ) -> GoalSwitchOutcome {
        if case let .confirmed(confirmation) = authorization,
           (confirmation.targetGoalID != targetGoalID
            || confirmation.sourceGoalID != store.goal?.id) {
            return .staleRequest
        }

        switch store.prepareGoalActivation(to: targetGoalID) {
        case let .eligible(plan):
            let impact = goalTransitionProtectionImpact(for: plan.readiness)

            switch authorization {
            case .none:
                if let impact {
                    return .confirmationRequired(
                        goalSwitchConfirmation(for: plan, impact: impact)
                    )
                }
            case let .confirmed(confirmation):
                if let impact,
                   confirmation.impact != impact
                    || confirmation.readiness != plan.readiness {
                    return .confirmationRequired(
                        goalSwitchConfirmation(for: plan, impact: impact)
                    )
                }
            }

            return activationOutcome(for: store.activateGoal(using: plan))
        case .alreadyActive:
            return .alreadyActive
        case .targetNotFound:
            return .targetNotFound
        case .membershipRequired:
            store.requestMembership(for: .goalProfiles)
            return .membershipRequired
        }
    }

    func requestGoalProfileMutation(
        _ request: GoalProfileMutationRequest,
        authorization: GoalProfileMutationAuthorization = .none
    ) -> GoalProfileMutationOutcome {
        if case let .confirmed(confirmation) = authorization,
           confirmation.plan.request != request {
            return .staleRequest
        }

        switch store.prepareGoalProfileMutation(request) {
        case let .eligible(plan):
            let confirmation = goalProfileMutationConfirmation(for: plan)

            switch authorization {
            case .none:
                if let confirmation {
                    return .confirmationRequired(confirmation)
                }
            case let .confirmed(previousConfirmation):
                guard mutationSourceIsCurrent(
                    previousConfirmation.plan.sourceGoal,
                    plan.sourceGoal
                ) else {
                    return .staleRequest
                }
                if let confirmation,
                   confirmation != previousConfirmation {
                    return .confirmationRequired(confirmation)
                }
            }

            return goalProfileMutationOutcome(
                for: store.commitGoalProfileMutation(using: plan)
            )

        case .alreadyCommitted:
            return .alreadyCommitted
        case .invalidTitle:
            return .invalidTitle
        case .membershipRequired:
            store.requestMembership(for: .goalProfiles)
            return .membershipRequired
        case .profileLimitReached:
            store.checkpointNotice = store.goalProfileLimitMessage
            return .profileLimitReached
        case .targetNotFound:
            return .targetNotFound
        case .staleRequest:
            return .staleRequest
        }
    }

    private func mutationSourceIsCurrent(
        _ authorizedSource: Goal?,
        _ currentSource: Goal?
    ) -> Bool {
        switch (authorizedSource, currentSource) {
        case (nil, nil):
            return true
        case let (authorizedSource?, currentSource?):
            return authorizedSource.id == currentSource.id
                && authorizedSource.title == currentSource.title
                && authorizedSource.deadline == currentSource.deadline
                && authorizedSource.category == currentSource.category
                && authorizedSource.currentLevel == currentSource.currentLevel
                && authorizedSource.focusAreas == currentSource.focusAreas
                && authorizedSource.sourceDocuments == currentSource.sourceDocuments
                && authorizedSource.preferredQuestionStyle == currentSource.preferredQuestionStyle
                && authorizedSource.minimumQuestionDifficulty == currentSource.minimumQuestionDifficulty
                && authorizedSource.createdAt == currentSource.createdAt
        case (.some, nil), (nil, .some):
            return false
        }
    }

    private func goalProfileMutationConfirmation(
        for plan: GoalProfileMutationPlan
    ) -> GoalProfileMutationConfirmation? {
        let protectionImpact = goalProfileMutationProtectionImpact(for: plan)
        let consent: GoalProfileMutationConsent?

        if plan.isDeletion {
            consent = protectionImpact.map {
                .deletionAndProtection($0)
            } ?? .deletion
        } else {
            consent = protectionImpact.map(GoalProfileMutationConsent.protection)
        }

        return consent.map {
            GoalProfileMutationConfirmation(
                plan: plan,
                consent: $0,
                activeBreakAtRequest: isCanonicalBreakActive
            )
        }
    }

    private func goalProfileMutationProtectionImpact(
        for plan: GoalProfileMutationPlan
    ) -> GoalSwitchProtectionImpact? {
        let affectsActiveGoal: Bool
        switch plan.request.operation {
        case .create:
            affectsActiveGoal = true
        case .edit:
            guard plan.sourceReadiness?.hasFullCheckpoint == true else {
                return nil
            }
            affectsActiveGoal = true
        case .delete:
            affectsActiveGoal = plan.sourceGoal?.id == plan.targetGoal.id
        }
        guard affectsActiveGoal else { return nil }

        if let readiness = plan.resultingReadiness {
            return goalTransitionProtectionImpact(for: readiness)
        }

        guard SharedAppGroup.desiredShieldActive || protection.isShieldingEnabled else {
            return nil
        }
        return .turnsOffImmediately
    }

    private func goalProfileMutationOutcome(
        for result: GoalProfileMutationCommitResult
    ) -> GoalProfileMutationOutcome {
        switch result {
        case let .committed(resultingGoalID):
            return .committed(resultingGoalID: resultingGoalID)
        case .alreadyCommitted:
            return .alreadyCommitted
        case .invalidTitle:
            return .invalidTitle
        case .membershipRequired:
            store.requestMembership(for: .goalProfiles)
            return .membershipRequired
        case .profileLimitReached:
            store.checkpointNotice = store.goalProfileLimitMessage
            return .profileLimitReached
        case .targetNotFound:
            return .targetNotFound
        case .stalePlan:
            return .staleRequest
        case .persistenceFailed:
            return .persistenceFailed
        }
    }

    func goalTransitionProtectionImpact(
        for readiness: GoalCheckpointReadiness
    ) -> GoalSwitchProtectionImpact? {
        guard !readiness.hasFullCheckpoint,
              SharedAppGroup.desiredShieldActive || protection.isShieldingEnabled else {
            return nil
        }

        if isCanonicalBreakActive {
            return .preventsRelockAfterBreak
        }
        return .turnsOffImmediately
    }

    private func goalSwitchConfirmation(
        for plan: GoalActivationPlan,
        impact: GoalSwitchProtectionImpact
    ) -> GoalSwitchConfirmation {
        let sourceTitle = store.availableGoalProfiles.first {
            $0.id == plan.sourceGoalID
        }?.title
        return GoalSwitchConfirmation(
            sourceGoalID: plan.sourceGoalID,
            sourceTitle: sourceTitle,
            targetGoalID: plan.targetGoalID,
            targetTitle: plan.targetTitle,
            readiness: plan.readiness,
            impact: impact
        )
    }

    private func activationOutcome(
        for result: GoalActivationResult
    ) -> GoalSwitchOutcome {
        switch result {
        case let .activated(from, to):
            return .switched(from: from, to: to)
        case .alreadyActive:
            return .alreadyActive
        case .targetNotFound:
            return .targetNotFound
        case .membershipRequired:
            store.requestMembership(for: .goalProfiles)
            return .membershipRequired
        case .stalePlan:
            return .staleRequest
        case .persistenceFailed:
            return .persistenceFailed
        }
    }

    @discardableResult
    func startProtection() async -> Bool {
        guard operation == nil else { return false }
        operation = .startingProtection
        let goalID = store.goal?.id
        let beganWithoutReadyCheckpoint = !store.hasReadyCheckpointSet
        startingProtectionReadinessGoalID = beganWithoutReadyCheckpoint
            ? goalID
            : nil
        let didPrepare = await store.prepareQuestionsForProtectionStart()
        if didPrepare {
            protection.applyShield()
        }
        let didStart = didPrepare && protection.isShieldingEnabled
        pendingProtectionStartResult = ProtectionStartResultEvent(
            id: UUID(),
            goalID: goalID,
            becameCheckpointReadyDuringStart: beganWithoutReadyCheckpoint
                && store.hasReadyCheckpointSet,
            didStart: didStart,
            checkpointNotice: didStart ? nil : store.checkpointNotice,
            protectionErrorMessage: didStart ? nil : protection.userFacingErrorMessage
        )
        startingProtectionReadinessGoalID = nil
        operation = nil
        return didStart
    }

    func takePendingProtectionStartResult(
        id: ProtectionStartResultEvent.ID
    ) -> ProtectionStartResultEvent? {
        guard pendingProtectionStartResult?.id == id else { return nil }
        defer { pendingProtectionStartResult = nil }
        return pendingProtectionStartResult
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
           !isCanonicalBreakActive {
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

    private var isCanonicalBreakActive: Bool {
        guard SharedAppGroup.desiredShieldActive else { return false }
        let expiration = SharedAppGroup.unlockExpiration
            ?? store.unlockSession?.expiresAt
        return expiration.map { $0 > now() } == true
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

    @discardableResult
    func resolveFailed(_ session: CheckpointSession) -> CheckpointFailureProtectionOutcome? {
        guard session.purpose != .preview else { return nil }
        guard store.resolveCheckpointRun(
            sessionID: session.id,
            didPass: false
        ) else { return nil }
        reconcileProtectionState()

        if store.unlockSession?.isActive == true {
            return .activeBreakContinues
        }
        if protection.isShieldingEnabled {
            return .protectionRemainsOn
        }
        return store.hasReadyCheckpointSet
            ? .protectionIsOff
            : .protectionTurnedOffForUnavailableCheckpoint
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
