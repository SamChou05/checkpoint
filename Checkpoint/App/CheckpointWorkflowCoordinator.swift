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

enum CheckpointPassResolution: Equatable, Sendable {
    case failed(message: String)
    case completed(earnedBreak: EarnedBreakHandoffToken?)
}

struct EarnedBreakHandoffToken: Identifiable, Equatable, Hashable, Sendable {
    let deliveryID: UUID
    let checkpointSessionID: CheckpointSession.ID
    let goalID: Goal.ID
    let startedAt: Date
    let expiresAt: Date
    let unlockMinutes: Int

    var id: UUID { deliveryID }

    init(
        deliveryID: UUID = UUID(),
        checkpointSessionID: CheckpointSession.ID,
        goalID: Goal.ID,
        startedAt: Date,
        expiresAt: Date,
        unlockMinutes: Int
    ) {
        self.deliveryID = deliveryID
        self.checkpointSessionID = checkpointSessionID
        self.goalID = goalID
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.unlockMinutes = unlockMinutes
    }

    var accessibilityAnnouncement: String {
        let duration = unlockMinutes == 1 ? "1-minute" : "\(unlockMinutes)-minute"
        return "Checkpoint passed. You earned a \(duration) break, and it is active now."
    }

    fileprivate var hasValidUnlockWindow: Bool {
        unlockMinutes > 0 && startedAt < expiresAt
    }
}

enum EarnedBreakHandoffDiscardReason: Equatable, Hashable, Sendable {
    case activeGoalMismatch
    case canonicalUnlockMismatch
    case temporaryUnlockUnavailable
    case expired
}

enum EarnedBreakHandoffDisposition: Equatable, Hashable, Sendable {
    case delivered
    case discarded(EarnedBreakHandoffDiscardReason)
}

struct EarnedBreakHandoffQueue: Equatable, Sendable {
    private(set) var pendingToken: EarnedBreakHandoffToken?
    private(set) var resolvedDeliveryIDs: Set<UUID> = []

    @discardableResult
    mutating func issue(_ token: EarnedBreakHandoffToken) -> Bool {
        guard token.hasValidUnlockWindow,
              !resolvedDeliveryIDs.contains(token.deliveryID),
              pendingToken?.deliveryID != token.deliveryID else {
            return false
        }

        if let pendingToken {
            resolvedDeliveryIDs.insert(pendingToken.deliveryID)
        }
        pendingToken = token
        return true
    }

    @discardableResult
    mutating func resolve(
        _ token: EarnedBreakHandoffToken,
        as disposition: EarnedBreakHandoffDisposition
    ) -> Bool {
        guard pendingToken == token,
              !resolvedDeliveryIDs.contains(token.deliveryID) else {
            return false
        }

        pendingToken = nil
        resolvedDeliveryIDs.insert(token.deliveryID)
        return true
    }

    mutating func discardPending() {
        guard let pendingToken else { return }
        self.pendingToken = nil
        resolvedDeliveryIDs.insert(pendingToken.deliveryID)
    }
}

struct EarnedBreakHandoffDeliveryContext: Equatable, Hashable, Sendable {
    let activeGoalID: Goal.ID?
    let canonicalUnlockStartedAt: Date?
    let canonicalUnlockExpiresAt: Date?
    let isTemporaryUnlockAvailable: Bool
    let isExposed: Bool
    let now: Date
}

struct EarnedBreakHandoffDeliveryEffect: Equatable, Sendable {
    let token: EarnedBreakHandoffToken

    var revealSequenceIncrement: Int { 1 }
    var celebrationSequenceIncrement: Int { 1 }
    var accessibilityAnnouncement: String { token.accessibilityAnnouncement }
}

struct EarnedBreakHandoffDeliveryState: Equatable, Sendable {
    private(set) var pendingToken: EarnedBreakHandoffToken?
    private(set) var presentedToken: EarnedBreakHandoffToken?
    private(set) var resolvedDeliveryIDs: Set<UUID> = []

    init(token: EarnedBreakHandoffToken? = nil) {
        pendingToken = token
    }

    mutating func receive(_ token: EarnedBreakHandoffToken?) {
        guard let token else {
            pendingToken = nil
            return
        }
        guard !resolvedDeliveryIDs.contains(token.deliveryID),
              pendingToken?.deliveryID != token.deliveryID else {
            return
        }

        if let pendingToken {
            resolvedDeliveryIDs.insert(pendingToken.deliveryID)
        }
        pendingToken = token
    }

    var candidateForDelivery: EarnedBreakHandoffToken? {
        guard let pendingToken,
              !resolvedDeliveryIDs.contains(pendingToken.deliveryID) else {
            return nil
        }
        return pendingToken
    }

    mutating func attemptDelivery(
        in context: EarnedBreakHandoffDeliveryContext,
        authoritativeResolve: (
            EarnedBreakHandoffToken,
            EarnedBreakHandoffDisposition
        ) -> Bool
    ) -> EarnedBreakHandoffDeliveryEffect? {
        guard let candidate = candidateForDelivery else { return nil }
        guard context.isExposed else { return nil }

        let disposition = disposition(for: candidate, in: context)
        pendingToken = nil
        resolvedDeliveryIDs.insert(candidate.deliveryID)

        guard authoritativeResolve(candidate, disposition) else {
            return nil
        }
        guard disposition == .delivered else {
            return nil
        }

        presentedToken = candidate
        return EarnedBreakHandoffDeliveryEffect(token: candidate)
    }

    private func disposition(
        for token: EarnedBreakHandoffToken,
        in context: EarnedBreakHandoffDeliveryContext
    ) -> EarnedBreakHandoffDisposition {
        guard token.hasValidUnlockWindow else {
            return .discarded(.canonicalUnlockMismatch)
        }
        guard context.activeGoalID == token.goalID else {
            return .discarded(.activeGoalMismatch)
        }
        guard context.canonicalUnlockStartedAt == token.startedAt,
              context.canonicalUnlockExpiresAt == token.expiresAt else {
            return .discarded(.canonicalUnlockMismatch)
        }
        guard context.isTemporaryUnlockAvailable else {
            return .discarded(.temporaryUnlockUnavailable)
        }
        guard context.now >= token.startedAt,
              context.now < token.expiresAt else {
            return .discarded(.expired)
        }
        return .delivered
    }
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

            return activationOutcome(
                for: store.activateGoal(using: plan),
                targetGoalID: targetGoalID
            )
        case .alreadyActive:
            return .alreadyActive
        case .targetNotFound:
            return .targetNotFound
        case .membershipRequired:
            requestGoalSwitchMembership(for: targetGoalID)
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
        for result: GoalActivationResult,
        targetGoalID: Goal.ID
    ) -> GoalSwitchOutcome {
        switch result {
        case let .activated(from, to):
            return .switched(from: from, to: to)
        case .alreadyActive:
            return .alreadyActive
        case .targetNotFound:
            return .targetNotFound
        case .membershipRequired:
            requestGoalSwitchMembership(for: targetGoalID)
            return .membershipRequired
        case .stalePlan:
            return .staleRequest
        case .persistenceFailed:
            return .persistenceFailed
        }
    }

    private func requestGoalSwitchMembership(for targetGoalID: Goal.ID) {
        store.requestMembership(
            for: .goalProfiles,
            continuation: .activateGoal(
                sourceGoalID: store.goal?.id,
                targetGoalID: targetGoalID
            )
        )
    }

    @discardableResult
    func startProtection(expectedGoalID: Goal.ID? = nil) async -> Bool {
        guard operation == nil,
              !Task.isCancelled else { return false }
        let goalID = store.goal?.id
        if let expectedGoalID,
           expectedGoalID != goalID {
            return false
        }

        operation = .startingProtection
        let beganWithoutReadyCheckpoint = !store.hasReadyCheckpointSet
        startingProtectionReadinessGoalID = beganWithoutReadyCheckpoint
            ? goalID
            : nil
        defer {
            startingProtectionReadinessGoalID = nil
            operation = nil
        }

        let didPrepare = await store.prepareQuestionsForProtectionStart(
            expectedGoalID: goalID
        )
        guard !Task.isCancelled,
              store.goal?.id == goalID else {
            return false
        }
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

    func finishPassed(_ session: CheckpointSession) -> CheckpointPassResolution {
        if session.purpose != .preview,
           (store.activeCheckpointRun?.sessionID != session.id
            || store.activeCheckpointRun?.purpose != session.purpose) {
            return .failed(
                message: "This checkpoint is no longer active. Start a new checkpoint to change protection."
            )
        }

        switch session.purpose {
        case .temporaryUnlock:
            guard let activeRun = store.activeCheckpointRun,
                  activeRun.sessionID == session.id else {
                return .failed(
                    message: "This checkpoint is no longer active. Start a new checkpoint to change protection."
                )
            }
            let unlockMinutes = store.unlockPolicy.unlockMinutes
            let expiration = now().addingTimeInterval(TimeInterval(unlockMinutes * 60))
            guard protection.temporarilyUnshield(until: expiration) else {
                return .failed(
                    message: protection.userFacingErrorMessage
                        ?? "The break could not start. Protection is still on; try again."
                )
            }
            store.startUnlockSession(
                minutes: unlockMinutes,
                expiresAt: expiration,
                goalID: activeRun.goalID
            )
            guard let committedUnlock = store.unlockSession,
                  committedUnlock.expiresAt == expiration,
                  committedUnlock.startedAt < committedUnlock.expiresAt,
                  committedUnlock.isActive,
                  let committedEvent = store.unlockEvents.first,
                  committedEvent.goalID == activeRun.goalID,
                  committedEvent.minutes == unlockMinutes,
                  committedEvent.createdAt == committedUnlock.startedAt,
                  store.resolveCheckpointRun(sessionID: session.id, didPass: true),
                  store.unlockSession == committedUnlock else {
                return .failed(
                    message: "The break started, but Checkpoint could not confirm it. Reopen Checkpoint before changing protection again."
                )
            }
            return .completed(
                earnedBreak: EarnedBreakHandoffToken(
                    checkpointSessionID: session.id,
                    goalID: activeRun.goalID,
                    startedAt: committedUnlock.startedAt,
                    expiresAt: committedUnlock.expiresAt,
                    unlockMinutes: committedEvent.minutes
                )
            )
        case .stopBlocking:
            protection.clearShield()
            store.clearUnlockSession()
            guard store.resolveCheckpointRun(sessionID: session.id, didPass: true) else {
                return .failed(
                    message: "This checkpoint is no longer active. Start a new checkpoint to change protection."
                )
            }
            return .completed(earnedBreak: nil)
        case .preview:
            return .completed(earnedBreak: nil)
        }
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
