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
