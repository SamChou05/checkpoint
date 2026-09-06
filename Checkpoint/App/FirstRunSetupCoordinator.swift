import Foundation
import Observation

enum FirstRunSetupProgress {
    static let pendingKey = "checkpoint.firstRunSetup.pendingAppSelection.v1"
    static let approvedSkillMapGoalKey = "checkpoint.firstRunSetup.approvedSkillMapGoal.v1"

    static func isPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pendingKey)
    }

    static func begin(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingKey)
    }

    static func complete(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingKey)
        defaults.removeObject(forKey: approvedSkillMapGoalKey)
    }

    static func approveSkillMap(
        goalID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(goalID.uuidString, forKey: approvedSkillMapGoalKey)
    }

    static func isSkillMapApproved(
        goalID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.string(forKey: approvedSkillMapGoalKey) == goalID.uuidString
    }

    static func shouldReviewSkillMap(
        isPending: Bool,
        goalID: UUID?,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard isPending, let goalID else { return false }
        return !isSkillMapApproved(goalID: goalID, defaults: defaults)
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

struct FirstRunGoalContext: Equatable, Hashable {
    let goalID: Goal.ID
    let title: String

    init(goalID: Goal.ID, title: String) {
        self.goalID = goalID
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = normalizedTitle.isEmpty ? "Your goal" : normalizedTitle
    }

    init?(goal: Goal?) {
        guard let goal else { return nil }
        self.init(goalID: goal.id, title: goal.title)
    }

    var accessibilityLabel: String {
        "Current goal: \(title)."
    }

    var savedGoalAccessibilityAnnouncement: String {
        "Goal saved: \(title). Step 3 of 3. Now choose the apps and websites that should pause for a checkpoint."
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

    mutating func consume(
        _ token: FirstGoalSuccessHandoffToken,
        currentGoalContext: FirstRunGoalContext?
    ) -> FirstRunGoalContext? {
        guard let currentGoalContext,
              currentGoalContext.goalID == token.goalID else {
            invalidate(unless: currentGoalContext?.goalID)
            return nil
        }
        guard consume(token) else { return nil }
        return currentGoalContext
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
    let goalContext: FirstRunGoalContext

    init(
        token: FirstGoalSuccessHandoffToken,
        goalContext: FirstRunGoalContext
    ) {
        self.token = token
        self.goalContext = goalContext
    }

    var revealSequenceIncrement: Int { 1 }
    var successFeedbackSequenceIncrement: Int { 1 }
    var accessibilityAnnouncement: String {
        goalContext.savedGoalAccessibilityAnnouncement
    }
}

struct FirstGoalSuccessHandoffDeliveryContext: Equatable, Hashable {
    let goalContext: FirstRunGoalContext?
    let phase: FirstRunProtectionPhase
    let isAuthorized: Bool
    let errorMessage: String?
    let isExposed: Bool

    init(
        goalContext: FirstRunGoalContext?,
        phase: FirstRunProtectionPhase,
        isAuthorized: Bool,
        errorMessage: String?,
        isExposed: Bool
    ) {
        self.goalContext = goalContext
        self.phase = phase
        self.isAuthorized = isAuthorized
        self.errorMessage = errorMessage
        self.isExposed = isExposed
    }
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
        authoritativeConsumeAndResolveContext:
            (FirstGoalSuccessHandoffToken) -> FirstRunGoalContext?
    ) -> FirstGoalSuccessHandoffDeliveryEffect? {
        guard let candidate = candidateForDelivery else { return nil }

        if let goalContext = context.goalContext,
           candidate.goalID != goalContext.goalID {
            pendingToken = nil
            resolvedDeliveryIDs.insert(candidate.deliveryID)
            return nil
        }

        guard context.isExposed,
              case .selecting = context.phase,
              context.isAuthorized,
              context.errorMessage == nil,
              context.goalContext != nil else {
            return nil
        }

        pendingToken = nil
        resolvedDeliveryIDs.insert(candidate.deliveryID)
        guard let authoritativeGoalContext = authoritativeConsumeAndResolveContext(candidate),
              authoritativeGoalContext.goalID == candidate.goalID else {
            return nil
        }
        presentedToken = candidate
        return FirstGoalSuccessHandoffDeliveryEffect(
            token: candidate,
            goalContext: authoritativeGoalContext
        )
    }
}

enum FirstRunProtectionStartResult: Equatable {
    case failed(message: String)
    case protected(selectionSummary: String)
}

@MainActor
@Observable
final class FirstRunSetupCoordinator {
    static let goalChangedMessage =
        "Your goal changed during setup. Review the current goal, then try turning protection on again."

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
        currentGoalID: @MainActor () -> UUID?,
        expectedGoalID: UUID? = nil
    ) async -> FirstRunProtectionStartResult {
        guard expectedGoalID == nil || currentGoalID() == expectedGoalID else {
            return .failed(message: Self.goalChangedMessage)
        }

        let preparationDeadline = now().addingTimeInterval(preparationTimeout)
        while isPreparingQuestions(), now() < preparationDeadline {
            do {
                try await sleep(preparationPollInterval)
            } catch {
                return .failed(
                    message: "Setup was interrupted. Try turning protection on again."
                )
            }
            guard expectedGoalID == nil || currentGoalID() == expectedGoalID else {
                return .failed(message: Self.goalChangedMessage)
            }
        }

        guard !isPreparingQuestions() else {
            return .failed(
                message: "Your first checkpoint is still being prepared. Try again in a moment."
            )
        }

        guard expectedGoalID == nil || currentGoalID() == expectedGoalID else {
            return .failed(message: Self.goalChangedMessage)
        }

        let didStartProtection = await startProtection()
        guard !Task.isCancelled else {
            return .failed(
                message: "Setup was interrupted. Try turning protection on again."
            )
        }
        guard expectedGoalID == nil || currentGoalID() == expectedGoalID else {
            return .failed(message: Self.goalChangedMessage)
        }
        guard didStartProtection else {
            return .failed(
                message: checkpointNotice()
                    ?? screenTimeErrorMessage()
                    ?? "Protection could not turn on. Check your selections and try again."
            )
        }

        FirstRunSetupProgress.complete(defaults: defaults)
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
