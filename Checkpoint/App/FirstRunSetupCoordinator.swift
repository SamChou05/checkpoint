import Foundation
import Observation

enum FirstRunSetupProgress {
    static let pendingKey = "checkpoint.firstRunSetup.pendingAppSelection.v1"

    static func isPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pendingKey)
    }

    static func begin(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingKey)
    }

    static func complete(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingKey)
    }

    static func shouldResumeAppSelection(
        isPending: Bool,
        hasGoal: Bool,
        isAuthorized: Bool,
        isOnboardingPresented: Bool
    ) -> Bool {
        isPending && hasGoal && isAuthorized && !isOnboardingPresented
    }

    @MainActor
    @discardableResult
    static func completeAfterStartingProtection(
        defaults: UserDefaults = .standard,
        startProtection: @MainActor () async -> Bool
    ) async -> Bool {
        guard await startProtection() else { return false }
        complete(defaults: defaults)
        return true
    }
}

struct FirstGoalSuccessHandoffToken: Equatable, Hashable, Identifiable {
    let deliveryID: UUID
    let goalID: UUID
    let goalTitle: String

    var id: UUID { deliveryID }

    init(
        deliveryID: UUID = UUID(),
        goalID: UUID,
        goalTitle: String
    ) {
        self.deliveryID = deliveryID
        self.goalID = goalID
        let normalizedTitle = goalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.goalTitle = normalizedTitle.isEmpty ? "Your goal" : normalizedTitle
    }

    var accessibilityAnnouncement: String {
        "Goal saved: \(goalTitle). Step 3 of 3. Now choose the apps and websites that should pause for a checkpoint."
    }
}

struct FirstGoalSuccessHandoffQueue: Equatable {
    private(set) var pendingToken: FirstGoalSuccessHandoffToken?
    private(set) var deliveredGoalIDs: Set<UUID> = []

    @discardableResult
    mutating func issue(
        goalID: UUID,
        goalTitle: String,
        isFirstRunSetupPending: Bool
    ) -> Bool {
        guard isFirstRunSetupPending,
              pendingToken?.goalID != goalID,
              !deliveredGoalIDs.contains(goalID) else {
            return false
        }

        pendingToken = FirstGoalSuccessHandoffToken(
            goalID: goalID,
            goalTitle: goalTitle
        )
        return true
    }

    @discardableResult
    mutating func consume(_ token: FirstGoalSuccessHandoffToken) -> Bool {
        guard pendingToken == token,
              !deliveredGoalIDs.contains(token.goalID) else {
            return false
        }

        pendingToken = nil
        deliveredGoalIDs.insert(token.goalID)
        return true
    }

    mutating func invalidate(unless currentGoalID: UUID?) {
        guard pendingToken?.goalID != currentGoalID else { return }
        pendingToken = nil
    }

    mutating func discardPending() {
        pendingToken = nil
    }
}

struct FirstGoalSuccessHandoffDeliveryEffect: Equatable {
    let token: FirstGoalSuccessHandoffToken

    var revealSequenceIncrement: Int { 1 }
    var successFeedbackSequenceIncrement: Int { 1 }
    var accessibilityAnnouncement: String { token.accessibilityAnnouncement }
}

struct FirstGoalSuccessHandoffDeliveryContext: Equatable, Hashable {
    let activeGoalID: UUID?
    let phase: FirstRunProtectionPhase
    let isAuthorized: Bool
    let errorMessage: String?
    let isExposed: Bool
}

enum FirstGoalSuccessHandoffExposure {
    static func allowsDelivery(
        isSceneActive: Bool,
        blocksUnderlyingPresentations: Bool
    ) -> Bool {
        isSceneActive && !blocksUnderlyingPresentations
    }
}

struct FirstGoalSuccessHandoffDeliveryState: Equatable {
    private(set) var pendingToken: FirstGoalSuccessHandoffToken?
    private(set) var presentedToken: FirstGoalSuccessHandoffToken?
    private(set) var resolvedDeliveryIDs: Set<UUID> = []

    init(token: FirstGoalSuccessHandoffToken? = nil) {
        pendingToken = token
    }

    mutating func receive(_ token: FirstGoalSuccessHandoffToken?) {
        guard let token else {
            pendingToken = nil
            return
        }
        guard !resolvedDeliveryIDs.contains(token.deliveryID) else {
            return
        }
        pendingToken = token
    }

    mutating func invalidate(unless currentGoalID: UUID?) {
        if let pendingToken,
           pendingToken.goalID != currentGoalID {
            resolvedDeliveryIDs.insert(pendingToken.deliveryID)
            self.pendingToken = nil
        }
        if presentedToken?.goalID != currentGoalID {
            presentedToken = nil
        }
    }

    var candidateForDelivery: FirstGoalSuccessHandoffToken? {
        guard let pendingToken,
              !resolvedDeliveryIDs.contains(pendingToken.deliveryID) else {
            return nil
        }
        return pendingToken
    }

    mutating func attemptDelivery(
        in context: FirstGoalSuccessHandoffDeliveryContext,
        authoritativeConsume: (FirstGoalSuccessHandoffToken) -> Bool
    ) -> FirstGoalSuccessHandoffDeliveryEffect? {
        guard let candidate = candidateForDelivery else { return nil }

        if let activeGoalID = context.activeGoalID,
           candidate.goalID != activeGoalID {
            pendingToken = nil
            resolvedDeliveryIDs.insert(candidate.deliveryID)
            return nil
        }

        guard context.isExposed,
              case .selecting = context.phase,
              context.isAuthorized,
              context.errorMessage == nil,
              context.activeGoalID != nil else {
            return nil
        }

        pendingToken = nil
        resolvedDeliveryIDs.insert(candidate.deliveryID)
        guard authoritativeConsume(candidate) else {
            return nil
        }
        presentedToken = candidate
        return FirstGoalSuccessHandoffDeliveryEffect(token: candidate)
    }
}

enum FirstRunProtectionStartResult: Equatable {
    case failed(message: String)
    case protected(selectionSummary: String)
}

@MainActor
@Observable
final class FirstRunSetupCoordinator {
    private(set) var isPending: Bool
    private(set) var isAppSelectionPresented = false
    private(set) var suppressedSuggestedSkillMapGoalID: UUID?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preparationTimeout: TimeInterval
    @ObservationIgnored private let preparationPollInterval: Duration
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void

    init(
        defaults: UserDefaults = .standard,
        preparationTimeout: TimeInterval = 45,
        preparationPollInterval: Duration = .milliseconds(250),
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @MainActor (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.defaults = defaults
        self.preparationTimeout = preparationTimeout
        self.preparationPollInterval = preparationPollInterval
        self.now = now
        self.sleep = sleep
        isPending = FirstRunSetupProgress.isPending(defaults: defaults)
    }

    func begin() {
        FirstRunSetupProgress.begin(defaults: defaults)
        isPending = true
        suppressedSuggestedSkillMapGoalID = nil
    }

    func presentAppSelection() {
        isAppSelectionPresented = true
    }

    func setAppSelectionPresented(_ isPresented: Bool) {
        isAppSelectionPresented = isPresented
    }

    func startProtection(
        isPreparingQuestions: @MainActor () -> Bool,
        startProtection: @MainActor () async -> Bool,
        checkpointNotice: @MainActor () -> String?,
        screenTimeErrorMessage: @MainActor () -> String?,
        selectionSummary: @MainActor () -> String,
        currentGoalID: @MainActor () -> UUID?
    ) async -> FirstRunProtectionStartResult {
        let preparationDeadline = now().addingTimeInterval(preparationTimeout)
        while isPreparingQuestions(), now() < preparationDeadline {
            do {
                try await sleep(preparationPollInterval)
            } catch {
                return .failed(
                    message: "Setup was interrupted. Try turning protection on again."
                )
            }
        }

        guard !isPreparingQuestions() else {
            return .failed(
                message: "Your first checkpoint is still being prepared. Try again in a moment."
            )
        }

        let didStartProtection = await FirstRunSetupProgress.completeAfterStartingProtection(
            defaults: defaults,
            startProtection: startProtection
        )
        guard didStartProtection else {
            return .failed(
                message: checkpointNotice()
                    ?? screenTimeErrorMessage()
                    ?? "Protection could not turn on. Check your selections and try again."
            )
        }

        isPending = false
        suppressedSuggestedSkillMapGoalID = currentGoalID()
        return .protected(selectionSummary: selectionSummary())
    }

    func finishProtectedSetup() {
        isAppSelectionPresented = false
    }

    func protectionDidBecomeUnavailable() {
        FirstRunSetupProgress.begin(defaults: defaults)
        isPending = true
        isAppSelectionPresented = true
        suppressedSuggestedSkillMapGoalID = nil
    }

    func continueWithoutProtection(
        currentGoalID: UUID?,
        stopProtection: @MainActor () -> Void
    ) {
        stopProtection()
        FirstRunSetupProgress.complete(defaults: defaults)
        isPending = false
        suppressedSuggestedSkillMapGoalID = currentGoalID
        isAppSelectionPresented = false
    }
}
