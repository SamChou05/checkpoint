import Accessibility
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ScreenTimeAccessRecoveryQueue: Equatable {
    private(set) var isQueued = false
    private(set) var isScheduling = false

    mutating func enqueue(if shouldRecover: Bool) {
        guard shouldRecover else { return }
        isQueued = true
    }

    mutating func beginScheduling(
        shouldRecover: Bool,
        canPresent: Bool
    ) -> Bool {
        guard isQueued else { return false }
        guard shouldRecover else {
            isQueued = false
            isScheduling = false
            return false
        }
        guard canPresent, !isScheduling else { return false }

        isScheduling = true
        return true
    }

    mutating func finishScheduling(
        shouldRecover: Bool,
        canPresent: Bool
    ) -> Bool {
        isScheduling = false
        guard shouldRecover else {
            isQueued = false
            return false
        }
        guard canPresent else {
            return false
        }

        isQueued = false
        return true
    }
}

enum ScreenTimeAccessPresentationHost: Equatable {
    case root
    case onboarding
}

enum OnboardingScreenTimeAccessRouting {
    static func shouldPresentOnboarding(
        isRequested: Bool,
        isAuthorized: Bool,
        isAlreadyActive: Bool
    ) -> Bool {
        isRequested && (isAuthorized || isAlreadyActive)
    }

    static func recoveryHost(
        requiresRecovery: Bool,
        isOnboardingActive: Bool
    ) -> ScreenTimeAccessPresentationHost? {
        guard requiresRecovery else { return nil }
        return isOnboardingActive ? .onboarding : .root
    }
}

struct ScreenTimeAccessGateCoordinator: Equatable {
    enum Phase: Equatable {
        case hidden
        case required(ScreenTimeAccessPresentationHost)
        case connected(ScreenTimeAccessPresentationHost)
    }

    private(set) var phase: Phase = .hidden
    private(set) var presentedHost: ScreenTimeAccessPresentationHost?
    private(set) var visibleGateHost: ScreenTimeAccessPresentationHost?
    private(set) var dismissalHost: ScreenTimeAccessPresentationHost?

    var presentationHost: ScreenTimeAccessPresentationHost? {
        switch phase {
        case .hidden:
            nil
        case let .required(host), let .connected(host):
            host
        }
    }

    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    var blocksUnderlyingPresentations: Bool {
        phase != .hidden || presentedHost != nil || dismissalHost != nil
    }

    mutating func reconcile(
        isAuthorized: Bool,
        requiredHost: ScreenTimeAccessPresentationHost?
    ) {
        switch phase {
        case .hidden:
            guard !isAuthorized,
                  let host = dismissalHost ?? presentedHost ?? requiredHost else { return }
            phase = .required(host)
            dismissalHost = nil
        case let .required(host):
            guard isAuthorized else {
                rehomeRequiredGateIfPresented(at: requiredHost)
                return
            }
            if visibleGateHost == host, presentedHost == host {
                phase = .connected(host)
            } else {
                phase = .hidden
                visibleGateHost = nil
            }
        case let .connected(host):
            guard !isAuthorized else { return }
            phase = .required(host)
        }
    }

    mutating func presentationDidAppear(
        host: ScreenTimeAccessPresentationHost,
        isAuthorizationGateVisible: Bool
    ) {
        if presentedHost != host {
            visibleGateHost = nil
            if case .connected = phase {
                phase = .hidden
                dismissalHost = nil
            }
        }
        presentedHost = host
        updatePresentedContent(
            host: host,
            isAuthorizationGateVisible: isAuthorizationGateVisible
        )
    }

    mutating func updatePresentedContent(
        host: ScreenTimeAccessPresentationHost,
        isAuthorizationGateVisible: Bool
    ) {
        guard presentedHost == host else { return }
        if isAuthorizationGateVisible, presentationHost == host {
            visibleGateHost = host
        } else if visibleGateHost == host {
            visibleGateHost = nil
        }
    }

    @discardableResult
    mutating func continueAfterConnection() -> Bool {
        guard case let .connected(host) = phase else { return false }
        phase = .hidden
        dismissalHost = host
        return true
    }

    @discardableResult
    mutating func presentationDidDisappear(
        host: ScreenTimeAccessPresentationHost,
        requiredHost: ScreenTimeAccessPresentationHost? = nil
    ) -> Bool {
        guard presentedHost == host else { return false }
        rehomeRequiredGateIfPresented(at: requiredHost)
        presentedHost = nil
        if visibleGateHost == host { visibleGateHost = nil }
        guard dismissalHost == host else { return false }
        dismissalHost = nil
        return phase == .hidden
    }

    private mutating func rehomeRequiredGateIfPresented(
        at requiredHost: ScreenTimeAccessPresentationHost?
    ) {
        guard let requiredHost,
              presentedHost == requiredHost,
              case let .required(host) = phase,
              host != requiredHost else { return }

        phase = .required(requiredHost)
        visibleGateHost = nil
    }
}

private struct ProtectionReconciliationKey: Equatable {
    let goalID: Goal.ID?
    let goalTitle: String?
    let hasReadyCheckpoint: Bool
}

struct TabContentAnnouncementOwnership {
    static func isActive(
        isVisible: Bool,
        isSceneActive: Bool = true,
        isCoveredByParentPresentation: Bool,
        isCoveredByLocalPresentation: Bool
    ) -> Bool {
        isVisible
            && isSceneActive
            && !isCoveredByParentPresentation
            && !isCoveredByLocalPresentation
    }
}

struct CheckpointPresentationLifecycle {
    static func isActive(
        hasSession: Bool,
        isSheetActive: Bool
    ) -> Bool {
        hasSession || isSheetActive
    }
}

enum AccessibilityAnnouncementContext: Equatable {
    case goalReady(Goal.ID)
    case screenTimeError(String)
    case settingsProtectionState(SettingsProtectionState)
    case settingsMessage(String)
}

struct AccessibilityAnnouncementRequest: Equatable {
    let message: String
    let context: AccessibilityAnnouncementContext
}

struct AccessibilityAnnouncementDeliveryQueue: Equatable {
    private(set) var pendingRequest: AccessibilityAnnouncementRequest?

    mutating func submit(
        _ request: AccessibilityAnnouncementRequest,
        isOwner: Bool
    ) -> AccessibilityAnnouncementRequest? {
        guard !isOwner else {
            pendingRequest = nil
            return request
        }

        pendingRequest = request
        return nil
    }

    mutating func takePending(
        isOwner: Bool
    ) -> AccessibilityAnnouncementRequest? {
        guard isOwner,
              let pendingRequest else { return nil }
        self.pendingRequest = nil
        return pendingRequest
    }

    mutating func discard() {
        pendingRequest = nil
    }
}

struct ProtectionStartResultAnnouncement {
    static func message(for event: ProtectionStartResultEvent) -> String {
        if event.didStart {
            return "Protection is on. Selected apps pause at a goal-based checkpoint."
        }
        return event.checkpointNotice
            ?? event.protectionErrorMessage
            ?? "Protection could not start. Check your setup and try again."
    }

    static func isCurrent(
        _ event: ProtectionStartResultEvent,
        currentGoalID: Goal.ID?,
        isShieldingEnabled: Bool,
        protectionShouldRemainActive: Bool,
        checkpointNotice: String?,
        protectionErrorMessage: String?
    ) -> Bool {
        guard event.goalID == currentGoalID else { return false }
        if event.didStart {
            return isShieldingEnabled
        }

        guard !isShieldingEnabled,
              !protectionShouldRemainActive else { return false }
        if let eventNotice = event.checkpointNotice {
            return checkpointNotice == eventNotice
        }
        if let eventError = event.protectionErrorMessage {
            return protectionErrorMessage == eventError
        }
        return true
    }
}

struct ProtectionStartErrorFeedbackState: Equatable {
    private(set) var lastDeliveredStartError: String?

    mutating func recordDeliveredResult(_ result: ProtectionStartResultEvent) {
        lastDeliveredStartError = result.protectionErrorMessage
    }

    mutating func shouldDeliverPassiveError(
        _ message: String?,
        isStartFeedbackPending: Bool
    ) -> Bool {
        guard let message else {
            lastDeliveredStartError = nil
            return false
        }
        let matchesDeliveredStartError = lastDeliveredStartError == message
        if !matchesDeliveredStartError {
            lastDeliveredStartError = nil
        }
        guard !isStartFeedbackPending else { return false }
        if matchesDeliveredStartError {
            lastDeliveredStartError = nil
            return false
        }
        return true
    }
}

struct SettingsProtectionAnnouncementState: Equatable {
    private(set) var explicitlyDeliveredState: SettingsProtectionState?

    mutating func resetExplicitState() {
        explicitlyDeliveredState = nil
    }

    mutating func recordExplicitState(_ state: SettingsProtectionState) {
        explicitlyDeliveredState = state
    }

    mutating func shouldDeliverTransition(
        to state: SettingsProtectionState,
        isActionFeedbackPending: Bool
    ) -> Bool {
        let matchesExplicitState = explicitlyDeliveredState == state
        if !matchesExplicitState {
            explicitlyDeliveredState = nil
        }
        guard !isActionFeedbackPending else { return false }
        if matchesExplicitState {
            explicitlyDeliveredState = nil
            return false
        }
        return true
    }
}

@MainActor
struct ProtectionStartResultDelivery {
    static func takeCurrent(
        from workflow: CheckpointWorkflowCoordinator,
        isOwner: Bool,
        currentGoalID: Goal.ID?,
        isShieldingEnabled: Bool,
        protectionShouldRemainActive: Bool,
        checkpointNotice: String?,
        protectionErrorMessage: String?
    ) -> ProtectionStartResultEvent? {
        guard isOwner,
              let pendingResult = workflow.pendingProtectionStartResult,
              let result = workflow.takePendingProtectionStartResult(
                id: pendingResult.id
              ) else { return nil }

        guard ProtectionStartResultAnnouncement.isCurrent(
            result,
            currentGoalID: currentGoalID,
            isShieldingEnabled: isShieldingEnabled,
            protectionShouldRemainActive: protectionShouldRemainActive,
            checkpointNotice: checkpointNotice,
            protectionErrorMessage: protectionErrorMessage
        ) else { return nil }
        return result
    }
}

struct ProtectionStartReadinessAnnouncementPolicy {
    static func shouldSuppress(
        for goalID: Goal.ID?,
        locallySuppressedGoalID: Goal.ID?,
        parentPresentationOwnsReadiness: Bool,
        startingProtectionReadinessGoalID: Goal.ID?,
        pendingResult: ProtectionStartResultEvent?
    ) -> Bool {
        guard let goalID else { return false }
        if parentPresentationOwnsReadiness
            || locallySuppressedGoalID == goalID
            || startingProtectionReadinessGoalID == goalID {
            return true
        }
        return pendingResult?.goalID == goalID
            && pendingResult?.becameCheckpointReadyDuringStart == true
    }
}

enum GoalSwitchDismissalDrainStep: Equatable {
    case none
    case promoteQueuedConfirmation
    case drainDeferredPresentations
}

struct GoalSwitchDismissalRouting {
    static func nextStep(
        hasPresentedConfirmation: Bool,
        hasQueuedConfirmation: Bool
    ) -> GoalSwitchDismissalDrainStep {
        if hasPresentedConfirmation {
            return .none
        }
        if hasQueuedConfirmation {
            return .promoteQueuedConfirmation
        }
        return .drainDeferredPresentations
    }
}

private enum MembershipNextFocusResolutionPersistenceAction {
    case consume(goalID: Goal.ID)
    case returnToReceipt(goalID: Goal.ID)

    var goalID: Goal.ID {
        switch self {
        case let .consume(goalID), let .returnToReceipt(goalID):
            goalID
        }
    }
}

struct RootView: View {
    @State private var appModel = CheckpointAppModel()
    @State private var selectedTab: AppTab = .home
    @State private var activeCheckpointSession: CheckpointSession?
    @State private var isCheckpointSheetActive = false
    @State private var earnedBreakHandoff = EarnedBreakHandoffQueue()
    @State private var pendingShieldRetryTask: Task<Void, Never>?
    @State private var suggestedSkillMapReviewPresentation = SkillMapReviewPresentationState()
    @State private var lastPresentedSkillMapReviewRevision: SkillMapReviewContext.Revision?
    @State private var firstRunSetup = FirstRunSetupCoordinator()
    @State private var firstGoalSuccessHandoff = FirstGoalSuccessHandoffQueue()
    @State private var isOnboardingSheetActive = false
    @State private var isFirstRunAppSelectionQueued = false
    @State private var isAuthorizationRecoveryAppSelectionPresented = false
    @State private var authorizationRecoveryQueue = ScreenTimeAccessRecoveryQueue()
    @State private var screenTimeAccessGate = ScreenTimeAccessGateCoordinator()
    @State private var pendingGoalSwitchConfirmation: GoalSwitchConfirmation?
    @State private var queuedGoalSwitchConfirmation: GoalSwitchConfirmation?
    @State private var goalSwitchFeedbackSequence = 0
    @State private var progressSkillEvidenceRequest: ProgressSkillEvidenceRequest?
    @Environment(\.scenePhase) private var scenePhase

    private var store: CheckpointStore { appModel.store }
    private var screenTime: ScreenTimeController { appModel.screenTime }
    private var purchaseController: PurchaseController { appModel.purchaseController }
    private var workflow: CheckpointWorkflowCoordinator { appModel.workflow }
    private var isCheckpointPresentationActive: Bool {
        CheckpointPresentationLifecycle.isActive(
            hasSession: activeCheckpointSession != nil,
            isSheetActive: isCheckpointSheetActive
        )
    }
    private var suggestedSkillMapReviewBinding: Binding<SkillMapReviewContext?> {
        Binding(
            get: { suggestedSkillMapReviewPresentation.destination },
            set: { destination in
                guard destination == nil else { return }
                suggestedSkillMapReviewPresentation.presentationRequestedDismissal()
            }
        )
    }
    private var protectionReconciliationKey: ProtectionReconciliationKey {
        ProtectionReconciliationKey(
            goalID: store.goal?.id,
            goalTitle: store.goal?.title,
            hasReadyCheckpoint: store.hasReadyCheckpointSet
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                store: store,
                screenTime: screenTime,
                workflow: workflow,
                isVisible: selectedTab == .home,
                isSceneActive: scenePhase == .active,
                isCoveredByParentModal: isTabContentCoveredByParentPresentation,
                parentModalOwnsQuestionReadiness: firstRunSetup.isAppSelectionPresented,
                parentModalOwnsProtectionErrors: parentPresentationOwnsProtectionErrors,
                earnedBreakHandoff: earnedBreakHandoff.pendingToken,
                resolveEarnedBreakHandoff: resolveEarnedBreakHandoff
            )
                .tabItem {
                    Label("Home", systemImage: "target")
                }
                .tag(AppTab.home)

            CompetencyView(
                store: store,
                isVisible: selectedTab == .skill,
                isSceneActive: scenePhase == .active,
                isCoveredByParentModal: isTabContentCoveredByParentPresentation,
                workflow: workflow,
                screenTime: screenTime,
                protectionErrorMessage: screenTime.userFacingErrorMessage,
                parentModalOwnsProtectionErrors: parentPresentationOwnsProtectionErrors,
                skillEvidenceRequest: $progressSkillEvidenceRequest,
                skillEvidenceResolution: handleProgressSkillEvidenceResolution
            )
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppTab.skill)

            SettingsView(
                store: store,
                screenTime: screenTime,
                purchaseController: purchaseController,
                workflow: workflow,
                presentCheckpoint: presentCheckpoint,
                isVisible: selectedTab == .settings,
                isSceneActive: scenePhase == .active,
                isCoveredByParentModal: isTabContentCoveredByParentPresentation,
                parentModalOwnsProtectionErrors: parentPresentationOwnsProtectionErrors
            )
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(AppTab.settings)
        }
        .tint(CheckpointTheme.teal)
        .environment(
            \.checkpointGoalSelection,
            GoalSelectionAction { requestGoalSwitch(to: $0) }
        )
        .environment(
            \.checkpointProgressSkillEvidenceNavigation,
            ProgressSkillEvidenceNavigationAction { target in
                progressSkillEvidenceRequest = ProgressSkillEvidenceRequest(target: target)
                selectedTab = .skill
            }
        )
        .sensoryFeedback(.selection, trigger: goalSwitchFeedbackSequence)
        .alert(
            pendingGoalSwitchAlertTitle,
            isPresented: goalSwitchConfirmationIsPresented,
            presenting: pendingGoalSwitchConfirmation
        ) { confirmation in
            let presentation = goalSwitchConfirmationPresentation(for: confirmation)

            Button(presentation.confirmationButtonTitle, role: .destructive) {
                confirmGoalSwitch(confirmation)
            }
            Button(presentation.cancelButtonTitle, role: .cancel) {
                cancelGoalSwitch(confirmation)
            }
        } message: { confirmation in
            Text(goalSwitchConfirmationPresentation(for: confirmation).message)
        }
        .fullScreenCover(
            isPresented: screenTimeAuthorizationRequiredBinding,
            onDismiss: {
                handleScreenTimeAccessDismissed(host: .root)
            }
        ) {
            screenTimeAccessContent(host: .root)
        }
        .sheet(
            isPresented: $isAuthorizationRecoveryAppSelectionPresented,
            onDismiss: handleAuthorizationRecoveryAppSelectionDismissed
        ) {
            RestrictedAppsView(screenTime: screenTime)
        }
        .sheet(item: $activeCheckpointSession, onDismiss: handleCheckpointDismissed) { session in
            CheckpointAttemptView(
                store: store,
                workflow: workflow,
                session: session,
                onEarnedBreak: queueEarnedBreakHandoff
            )
        }
        .sheet(item: membershipPresentationBinding, onDismiss: handleMembershipDismissed) { context in
            MembershipView(context: context, store: store, purchaseController: purchaseController)
        }
        .sheet(
            isPresented: onboardingPresentationBinding,
            onDismiss: handleOnboardingDismissed
        ) {
            onboardingSheetContent
        }
        .sheet(
            isPresented: firstRunAppSelectionPresentationBinding,
            onDismiss: handleFirstRunAppSelectionDismissed
        ) {
            RestrictedAppsView(
                screenTime: screenTime,
                onStartProtection: startFirstRunProtection,
                onFinishProtectedSetup: {
                    firstGoalSuccessHandoff.discardPending()
                    firstRunSetup.finishProtectedSetup()
                },
                onContinueWithoutProtection: {
                    firstGoalSuccessHandoff.discardPending()
                    firstRunSetup.continueWithoutProtection(
                        currentGoalID: store.goal?.id,
                        stopProtection: workflow.stopProtectionWithoutReview
                    )
                },
                onProtectionUnavailable: {
                    firstRunSetup.protectionDidBecomeUnavailable()
                },
                activeGoalID: store.goal?.id,
                allowsFirstGoalHandoffDelivery: FirstGoalSuccessHandoffExposure.allowsDelivery(
                    isSceneActive: scenePhase == .active,
                    blocksUnderlyingPresentations: screenTimeAccessGate.blocksUnderlyingPresentations
                ),
                firstGoalHandoff: firstGoalSuccessHandoff.pendingToken,
                onFirstGoalHandoffConsumed: { token in
                    firstGoalSuccessHandoff.consume(token)
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(
            item: suggestedSkillMapReviewBinding,
            onDismiss: handleSuggestedSkillMapReviewDismissed
        ) { reviewContext in
            SkillMapReviewView(store: store, reviewContext: reviewContext)
                .onAppear {
                    suggestedSkillMapReviewPresentation.presentationDidAppear()
                }
        }
        .task {
            await bootstrap()
        }
        .onAppear {
            reconcileScreenTimeAccessGate()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            handleAppActivation()
        }
        .onChange(of: screenTime.hasRequiredScreenTimeAuthorization) { _, isAuthorized in
            reconcileScreenTimeAccessGate()
            guard isAuthorized else { return }
            guard !screenTimeAccessGate.blocksUnderlyingPresentations else { return }
            reconcileProtectionAndHandlePendingAttempt()
            resumeFirstRunSetupIfNeeded()
        }
        .onChange(of: store.goal) { _, goal in
            firstGoalSuccessHandoff.invalidate(unless: goal?.id)
            if goal == nil {
                beginFirstRunSetup()
            }
            guard !invalidateSuggestedSkillMapReviewIfStale(for: goal) else { return }
            presentSuggestedSkillMapReviewIfNeeded()
        }
        .onChange(of: protectionReconciliationKey) { _, _ in
            guard !isCheckpointPresentationActive else { return }
            reconcileProtectionAndHandlePendingAttempt()
        }
        .onChange(of: store.activeDerivedSkillMap) { _, _ in
            guard !invalidateSuggestedSkillMapReviewIfStale(for: store.goal) else { return }
            presentSuggestedSkillMapReviewIfNeeded()
        }
        .onChange(of: store.isOnboardingPresented) { _, _ in
            presentSuggestedSkillMapReviewIfNeeded()
        }
        .onChange(of: screenTime.hasSelection) { _, hasSelection in
            workflow.selectionDidChange(hasSelection: hasSelection)
        }
        .onChange(of: screenTime.setupState) { _, setupState in
            if setupState == .shieldActive {
                workflow.protectionDidRelock()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkpointShieldContextDidChange)) { _ in
            workflow.refreshProtectionConfiguration()
        }
    }

    private var onboardingSheetContent: some View {
        OnboardingView(store: store, workflow: workflow, onFirstGoalCreated: {
            beginFirstRunSetup()
            if let goal = store.goal {
                firstGoalSuccessHandoff.issue(
                    goalID: goal.id,
                    goalTitle: goal.title,
                    isFirstRunSetupPending: firstRunSetup.isPending
                )
            }
        })
        .onAppear {
            isOnboardingSheetActive = true
        }
        .fullScreenCover(
            isPresented: onboardingScreenTimeAuthorizationRequiredBinding,
            onDismiss: {
                handleScreenTimeAccessDismissed(host: .onboarding)
            }
        ) {
            screenTimeAccessContent(host: .onboarding)
        }
    }

    private func screenTimeAccessContent(
        host: ScreenTimeAccessPresentationHost
    ) -> some View {
        RequiredScreenTimeAccessView(
            store: store,
            screenTime: screenTime,
            purchaseController: purchaseController,
            context: screenTimeAccessContext,
            onContinue: continueAfterScreenTimeAccessConnection,
            continuesOnboardingAfterDismissal: host == .onboarding
        )
        .interactiveDismissDisabled()
        .onAppear {
            updateScreenTimeAccessPresentationState(host: host, didAppear: true)
        }
        .onChange(of: dataEraseRecoveryHost) { _, _ in
            updateScreenTimeAccessPresentationState(host: host, didAppear: false)
        }
    }

    private func updateScreenTimeAccessPresentationState(
        host: ScreenTimeAccessPresentationHost,
        didAppear: Bool
    ) {
        reconcileScreenTimeAccessGate()
        let isAuthorizationGateVisible = dataEraseRecoveryHost == nil
            && screenTimeAccessGate.presentationHost == host
        if didAppear {
            screenTimeAccessGate.presentationDidAppear(
                host: host,
                isAuthorizationGateVisible: isAuthorizationGateVisible
            )
        } else {
            screenTimeAccessGate.updatePresentedContent(
                host: host,
                isAuthorizationGateVisible: isAuthorizationGateVisible
            )
        }
    }

    private var goalSwitchConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingGoalSwitchConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingGoalSwitchConfirmation = nil
                    schedulePostGoalSwitchPresentationDrain()
                }
            }
        )
    }

    private var pendingGoalSwitchAlertTitle: String {
        guard let pendingGoalSwitchConfirmation else {
            return "Switch goal?"
        }
        return goalSwitchConfirmationPresentation(
            for: pendingGoalSwitchConfirmation
        ).title
    }

    private func goalSwitchConfirmationPresentation(
        for confirmation: GoalSwitchConfirmation
    ) -> GoalSwitchConfirmationPresentation {
        GoalSwitchConfirmationPresentation(
            confirmation: confirmation,
            goals: store.availableGoalProfiles
        )
    }

    private func requestGoalSwitch(to targetGoalID: Goal.ID) {
        handleGoalSwitchOutcome(
            workflow.requestGoalSwitch(to: targetGoalID)
        )
    }

    private func confirmGoalSwitch(_ confirmation: GoalSwitchConfirmation) {
        let outcome = workflow.requestGoalSwitch(
            to: confirmation.targetGoalID,
            authorization: .confirmed(confirmation)
        )
        if case let .confirmationRequired(refreshedConfirmation) = outcome {
            queuedGoalSwitchConfirmation = refreshedConfirmation
        } else {
            handleGoalSwitchOutcome(outcome)
        }
    }

    private func cancelGoalSwitch(_ confirmation: GoalSwitchConfirmation) {
        if store.cancelResumedMembershipGoalSwitch(to: confirmation.targetGoalID) {
            queuedGoalSwitchConfirmation = nil
        } else {
            queuedGoalSwitchConfirmation = confirmation
        }
        pendingGoalSwitchConfirmation = nil
        schedulePostGoalSwitchPresentationDrain()
    }

    private func handleGoalSwitchOutcome(_ outcome: GoalSwitchOutcome) {
        switch outcome {
        case let .switched(_, targetGoalID):
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = nil
            goalSwitchFeedbackSequence += 1
            let goals = store.availableGoalProfiles
            let resolver = GoalDisplayTitleResolver(goals: goals)
            let targetTitle = goals.first {
                $0.id == targetGoalID
            }.map(resolver.title(for:)) ?? "the selected goal"
            AccessibilityNotification.Announcement(
                "Switched to \(targetTitle)."
            ).post()
            schedulePostGoalSwitchPresentationDrain()
        case let .confirmationRequired(confirmation):
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = confirmation
        case .alreadyActive:
            if let activeGoalID = store.goal?.id {
                _ = store.completeResumedMembershipGoalSwitch(to: activeGoalID)
            }
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = nil
            schedulePostGoalSwitchPresentationDrain()
        case .membershipRequired:
            _ = store.returnMembershipActivationResumeToReceipt()
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = nil
            schedulePostGoalSwitchPresentationDrain()
        case .targetNotFound, .staleRequest:
            _ = store.returnMembershipActivationResumeToReceipt()
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = nil
            AccessibilityNotification.Announcement(
                "That goal changed. Choose it again."
            ).post()
            schedulePostGoalSwitchPresentationDrain()
        case .persistenceFailed:
            _ = store.returnMembershipActivationResumeToReceipt()
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = nil
            AccessibilityNotification.Announcement(
                "Checkpoint couldn't save the goal change. Your current goal is unchanged."
            ).post()
            schedulePostGoalSwitchPresentationDrain()
        }
    }

    private func schedulePostGoalSwitchPresentationDrain() {
        Task { @MainActor in
            await Task.yield()
            switch GoalSwitchDismissalRouting.nextStep(
                hasPresentedConfirmation: pendingGoalSwitchConfirmation != nil,
                hasQueuedConfirmation: queuedGoalSwitchConfirmation != nil
            ) {
            case .none:
                return
            case .promoteQueuedConfirmation:
                promoteQueuedGoalSwitchConfirmationAfterDismissal()
            case .drainDeferredPresentations:
                presentDeferredMembershipActivationIfPossible()
                presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
                presentSuggestedSkillMapReviewIfNeeded()
            }
        }
    }

    private func promoteQueuedGoalSwitchConfirmationAfterDismissal() {
        guard let queuedConfirmation = queuedGoalSwitchConfirmation else { return }

        Task { @MainActor in
            await Task.yield()
            guard pendingGoalSwitchConfirmation == nil,
                  queuedGoalSwitchConfirmation == queuedConfirmation else {
                return
            }
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = queuedConfirmation
        }
    }

    private func bootstrap() async {
        if store.goal == nil {
            beginFirstRunSetup()
        }

        await screenTime.bootstrapAuthorizationIfNeeded()
        reconcileScreenTimeAccessGate()
        reconcileProtectionAndHandlePendingAttempt()
        queueAuthorizationRecoveryAppSelectionIfNeeded()

        purchaseController.onMembershipEntitlementChange = { unlocked in
            store.reconcileMembershipEntitlement(
                isUnlocked: unlocked,
                activationSource: membershipActivationSourceForCurrentStoreOperation
            )
            if unlocked {
                presentDeferredMembershipActivationIfPossible()
            }
        }
        purchaseController.startListeningForTransactions()
        let isMembershipUnlocked = await refreshPlanAccessFromEntitlements()
        store.reconcileMembershipActivationAfterLaunch(
            isUnlocked: isMembershipUnlocked,
            hasUnresolvedPurchase: purchaseController.hasUnresolvedPurchase
        )
        await purchaseController.loadProducts()

        reconcileProtectionAndHandlePendingAttempt()
        resumeFirstRunSetupIfNeeded()
        presentDeferredMembershipActivationIfPossible()
        presentSuggestedSkillMapReviewIfNeeded()
    }

    private func handleAppActivation() {
        screenTime.refreshAuthorizationStatus()
        reconcileScreenTimeAccessGate()
        reconcileProtectionAndHandlePendingAttempt()
        Task {
            _ = await refreshPlanAccessFromEntitlements()
            presentDeferredMembershipActivationIfPossible()
        }
        resumeFirstRunSetupIfNeeded()
    }

    private func reconcileProtectionAndHandlePendingAttempt() {
        guard !screenTimeAccessGate.blocksUnderlyingPresentations else { return }
        workflow.reconcileProtectionState()
        handlePendingShieldActivation()
    }

    private func handlePendingShieldActivation() {
        guard !screenTimeAccessGate.blocksUnderlyingPresentations else { return }
        guard !isCheckpointPresentationActive else { return }
        guard workflow.operation == nil else { return }
        guard SharedAppGroup.currentPendingShieldAttempt != nil else {
            pendingShieldRetryTask?.cancel()
            pendingShieldRetryTask = nil
            return
        }

        selectedTab = .home

        Task {
            if let session = await workflow.preparePendingShieldSession(),
               presentCheckpoint(session) {
                pendingShieldRetryTask?.cancel()
                pendingShieldRetryTask = nil
            } else {
                schedulePendingShieldRetryIfNeeded()
            }
        }
    }

    private func presentSuggestedSkillMapReviewIfNeeded() {
        guard !suggestedSkillMapReviewPresentation.blocksUnderlyingPresentations,
              !firstRunSetup.isPending,
              !screenTimeAccessGate.blocksUnderlyingPresentations,
              !store.isOnboardingPresented,
              !isOnboardingSheetActive,
              !isAuthorizationRecoveryAppSelectionPresented,
              !authorizationRecoveryQueue.isQueued,
              !authorizationRecoveryQueue.isScheduling,
              !firstRunSetup.isAppSelectionPresented,
              !isCheckpointPresentationActive,
              store.pendingMembershipPresentation == nil,
              !store.hasDeferredMembershipActivationPresentation,
              pendingGoalSwitchConfirmation == nil,
              let goal = store.goal,
              goal.id != firstRunSetup.suppressedSuggestedSkillMapGoalID,
              let reviewContext = SkillMapReviewContext(goal: goal),
              reviewContext.skillMap.status == .suggested else {
            return
        }

        guard reviewContext.revision != lastPresentedSkillMapReviewRevision else { return }
        guard suggestedSkillMapReviewPresentation.request(
            reviewContext,
            currentGoal: store.goal
        ) else { return }
        lastPresentedSkillMapReviewRevision = reviewContext.revision
    }

    @discardableResult
    private func invalidateSuggestedSkillMapReviewIfStale(for goal: Goal?) -> Bool {
        suggestedSkillMapReviewPresentation.invalidateIfStale(for: goal)
    }

    private func handleOnboardingDismissed() {
        isOnboardingSheetActive = false
        reconcileScreenTimeAccessGate()
        resumeFirstRunSetupIfNeeded()
        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
        presentDeferredMembershipActivationIfPossible()
        presentSuggestedSkillMapReviewIfNeeded()
    }

    private func handleFirstRunAppSelectionDismissed() {
        guard !firstRunSetup.isPending else { return }
        firstGoalSuccessHandoff.discardPending()
        selectedTab = .home
        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
        presentDeferredMembershipActivationIfPossible()
    }

    private func handleCheckpointDismissed() {
        isCheckpointSheetActive = false
        handlePendingShieldActivation()
        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
        presentDeferredMembershipActivationIfPossible()
    }

    private func queueEarnedBreakHandoff(_ handoff: EarnedBreakHandoffToken) {
        guard earnedBreakHandoff.issue(handoff) else { return }
        selectedTab = .home
    }

    private func resolveEarnedBreakHandoff(
        _ handoff: EarnedBreakHandoffToken,
        as disposition: EarnedBreakHandoffDisposition
    ) -> Bool {
        earnedBreakHandoff.resolve(handoff, as: disposition)
    }

    private func handleMembershipDismissed() {
        if let continuation = store.claimMembershipActivationContinuationForResume() {
            resumeMembershipActivation(continuation)
        }
        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
        presentSuggestedSkillMapReviewIfNeeded()
    }

    private func resumeMembershipActivation(
        _ continuation: MembershipActivationContinuation
    ) {
        switch continuation {
        case .createGoalProfile:
            store.presentGoalProfileCreator()
        case let .activateGoal(_, targetGoalID):
            requestGoalSwitch(to: targetGoalID)
        case let .revealNextFocus(sourceGoalID):
            guard store.goal?.id == sourceGoalID else {
                _ = store.returnMembershipActivationResumeToReceipt()
                presentDeferredMembershipActivationIfPossible()
                return
            }

            progressSkillEvidenceRequest = ProgressSkillEvidenceRequest(
                currentNextFocusFor: sourceGoalID
            )
            selectedTab = .skill
        }
    }

    private func handleProgressSkillEvidenceResolution(
        _ request: ProgressSkillEvidenceRequest,
        _ resolution: ProgressSkillEvidenceResolution
    ) {
        guard case let .currentNextFocus(sourceGoalID) = request.destination else {
            return
        }

        let persistenceAction: MembershipNextFocusResolutionPersistenceAction
        switch resolution {
        case .revealed:
            persistenceAction = .consume(goalID: sourceGoalID)
        case .unavailable:
            persistenceAction = .returnToReceipt(goalID: sourceGoalID)
        }

        guard !persistMembershipNextFocusResolution(persistenceAction) else {
            return
        }
        retryMembershipNextFocusResolutionPersistence(persistenceAction)
    }

    private func persistMembershipNextFocusResolution(
        _ action: MembershipNextFocusResolutionPersistenceAction
    ) -> Bool {
        guard let handoff = store.membershipActivationHandoff,
              handoff.phase == .resumeRequested,
              case let .revealNextFocus(sourceGoalID) = handoff.request.continuation,
              sourceGoalID == action.goalID else {
            return true
        }

        switch action {
        case let .consume(goalID):
            return store.completeResumedMembershipNextFocusReveal(for: goalID)
        case .returnToReceipt:
            guard store.returnMembershipActivationResumeToReceipt() else {
                return false
            }
            presentDeferredMembershipActivationIfPossible()
            return true
        }
    }

    private func retryMembershipNextFocusResolutionPersistence(
        _ action: MembershipNextFocusResolutionPersistenceAction
    ) {
        Task { @MainActor in
            for delay in [Duration.milliseconds(250), .seconds(1), .seconds(2)] {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if persistMembershipNextFocusResolution(action) {
                    return
                }
            }
        }
    }

    private func handleSuggestedSkillMapReviewDismissed() {
        suggestedSkillMapReviewPresentation.presentationDidDismiss()
        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
        presentDeferredMembershipActivationIfPossible()
        presentSuggestedSkillMapReviewIfNeeded()
    }

    private func handleScreenTimeAccessDismissed(
        host: ScreenTimeAccessPresentationHost
    ) {
        let completedConnectedHandoff = screenTimeAccessGate.presentationDidDisappear(
            host: host,
            requiredHost: requiredScreenTimeAuthorizationHost
        )
        queueAuthorizationRecoveryAppSelectionIfNeeded()
        guard completedConnectedHandoff else { return }

        reconcileProtectionAndHandlePendingAttempt()
        resumeFirstRunSetupIfNeeded()
        presentDeferredMembershipActivationIfPossible()
        presentSuggestedSkillMapReviewIfNeeded()
    }

    private func handleAuthorizationRecoveryAppSelectionDismissed() {
        presentDeferredMembershipActivationIfPossible()
        presentSuggestedSkillMapReviewIfNeeded()
    }

    private func presentDeferredMembershipActivationIfPossible() {
        guard store.hasDeferredMembershipActivationPresentation,
              !screenTimeAccessGate.blocksUnderlyingPresentations,
              !firstRunSetup.isPending,
              !store.isOnboardingPresented,
              !isOnboardingSheetActive,
              !isAuthorizationRecoveryAppSelectionPresented,
              !authorizationRecoveryQueue.isQueued,
              !authorizationRecoveryQueue.isScheduling,
              !firstRunSetup.isAppSelectionPresented,
              !isCheckpointPresentationActive,
              store.pendingMembershipPresentation == nil,
              pendingGoalSwitchConfirmation == nil,
              queuedGoalSwitchConfirmation == nil,
              !suggestedSkillMapReviewPresentation.blocksUnderlyingPresentations else {
            return
        }

        if store.hasMembershipActivationResumeRequest {
            if let continuation = store.claimMembershipActivationContinuationForResume() {
                resumeMembershipActivation(continuation)
            } else {
                _ = store.presentMembershipActivationHandoffIfAvailable()
            }
            return
        }
        _ = store.presentMembershipActivationHandoffIfAvailable()
    }

    private func continueAfterScreenTimeAccessConnection() {
        _ = screenTimeAccessGate.continueAfterConnection()
    }

    private func reconcileScreenTimeAccessGate() {
        screenTimeAccessGate.reconcile(
            isAuthorized: screenTime.hasRequiredScreenTimeAuthorization,
            requiredHost: requiredScreenTimeAuthorizationHost
        )
    }

    private func queueAuthorizationRecoveryAppSelectionIfNeeded() {
        let shouldRecover = ScreenTimeAccessRecoveryRouting.shouldPresentProtectedApps(
            context: screenTimeAccessContext,
            authorizationBecameAvailable: screenTime.hasRequiredScreenTimeAuthorization,
            requiresProtectedAppReselection: screenTime.requiresProtectedAppReselection
        )
        authorizationRecoveryQueue.enqueue(if: shouldRecover)

        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
    }

    private func presentQueuedAuthorizationRecoveryAppSelectionIfPossible() {
        let shouldRecover = ScreenTimeAccessRecoveryRouting.shouldPresentProtectedApps(
            context: screenTimeAccessContext,
            authorizationBecameAvailable: screenTime.hasRequiredScreenTimeAuthorization,
            requiresProtectedAppReselection: screenTime.requiresProtectedAppReselection
        )
        let canPresent = !isAuthorizationRecoveryAppSelectionPresented &&
            !screenTimeAccessGate.blocksUnderlyingPresentations &&
            !isCheckpointPresentationActive &&
            store.pendingMembershipPresentation == nil &&
            !store.isOnboardingPresented &&
            !isOnboardingSheetActive &&
            !firstRunSetup.isAppSelectionPresented &&
            pendingGoalSwitchConfirmation == nil &&
            !suggestedSkillMapReviewPresentation.blocksUnderlyingPresentations
        guard authorizationRecoveryQueue.beginScheduling(
            shouldRecover: shouldRecover,
            canPresent: canPresent
        ) else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            let shouldRecover = ScreenTimeAccessRecoveryRouting.shouldPresentProtectedApps(
                context: screenTimeAccessContext,
                authorizationBecameAvailable: screenTime.hasRequiredScreenTimeAuthorization,
                requiresProtectedAppReselection: screenTime.requiresProtectedAppReselection
            )
            let canPresent = !isAuthorizationRecoveryAppSelectionPresented &&
                !screenTimeAccessGate.blocksUnderlyingPresentations &&
                !isCheckpointPresentationActive &&
                store.pendingMembershipPresentation == nil &&
                !store.isOnboardingPresented &&
                !isOnboardingSheetActive &&
                !firstRunSetup.isAppSelectionPresented &&
                pendingGoalSwitchConfirmation == nil &&
                !suggestedSkillMapReviewPresentation.blocksUnderlyingPresentations
            guard authorizationRecoveryQueue.finishScheduling(
                shouldRecover: shouldRecover,
                canPresent: canPresent
            ) else {
                return
            }

            selectedTab = .home
            isAuthorizationRecoveryAppSelectionPresented = true
        }
    }

    private func beginFirstRunSetup() {
        firstRunSetup.begin()
    }

    private func resumeFirstRunSetupIfNeeded() {
        guard
            !screenTimeAccessGate.blocksUnderlyingPresentations,
            FirstRunSetupProgress.shouldResumeAppSelection(
                isPending: firstRunSetup.isPending,
                hasGoal: store.goal != nil,
                isAuthorized: screenTime.hasRequiredScreenTimeAuthorization,
                isOnboardingPresented: store.isOnboardingPresented
            ),
            !isOnboardingSheetActive,
            !firstRunSetup.isAppSelectionPresented,
            !isFirstRunAppSelectionQueued
        else {
            return
        }

        isFirstRunAppSelectionQueued = true
        Task { @MainActor in
            await Task.yield()
            guard
                !screenTimeAccessGate.blocksUnderlyingPresentations,
                FirstRunSetupProgress.shouldResumeAppSelection(
                    isPending: firstRunSetup.isPending,
                    hasGoal: store.goal != nil,
                    isAuthorized: screenTime.hasRequiredScreenTimeAuthorization,
                    isOnboardingPresented: store.isOnboardingPresented
                ),
                !isOnboardingSheetActive
            else {
                isFirstRunAppSelectionQueued = false
                return
            }
            firstRunSetup.presentAppSelection()
            isFirstRunAppSelectionQueued = false
        }
    }

    private func startFirstRunProtection() async -> FirstRunProtectionStartResult {
        let previousResultID = workflow.pendingProtectionStartResult?.id
        let result = await firstRunSetup.startProtection(
            isPreparingQuestions: { store.isPreparingActiveGoalQuestions },
            startProtection: { await workflow.startProtection() },
            checkpointNotice: { store.checkpointNotice },
            screenTimeErrorMessage: { screenTime.userFacingErrorMessage },
            selectionSummary: { screenTime.restrictedAppsSummary },
            currentGoalID: { store.goal?.id }
        )
        if let pendingResult = workflow.pendingProtectionStartResult,
           pendingResult.id != previousResultID {
            _ = workflow.takePendingProtectionStartResult(id: pendingResult.id)
        }
        return result
    }

    private var firstRunAppSelectionPresentationBinding: Binding<Bool> {
        Binding(
            get: { firstRunSetup.isAppSelectionPresented },
            set: { firstRunSetup.setAppSelectionPresented($0) }
        )
    }

    private func schedulePendingShieldRetryIfNeeded() {
        guard pendingShieldRetryTask == nil,
              SharedAppGroup.currentPendingShieldAttempt != nil,
              let retryAt = store.checkpointRetryCooldownUntil else {
            return
        }

        let delay = min(60, max(1, retryAt.timeIntervalSinceNow))
        pendingShieldRetryTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            pendingShieldRetryTask = nil
            handlePendingShieldActivation()
        }
    }

    @discardableResult
    private func presentCheckpoint(_ session: CheckpointSession) -> Bool {
        guard !isCheckpointPresentationActive,
              workflow.operation == nil else {
            store.discardCheckpointRunBeforePresentation(sessionID: session.id)
            return false
        }
        activeCheckpointSession = session
        isCheckpointSheetActive = true
        return true
    }

    @MainActor
    private func refreshPlanAccessFromEntitlements() async -> Bool {
        _ = await purchaseController.refreshEntitlements()
        return purchaseController.isMembershipUnlocked
    }

    private var membershipActivationSourceForCurrentStoreOperation: MembershipActivationSource {
        if purchaseController.purchasingProductID != nil {
            return .purchase
        }
        if purchaseController.isRestoringPurchases {
            return .restore
        }
        if purchaseController.isCheckingPurchaseStatus {
            return .purchase
        }
        return .entitlementRefresh
    }

    private var membershipPresentationBinding: Binding<MembershipPresentationContext?> {
        Binding(
            get: { store.pendingMembershipPresentation },
            set: { context in
                if let context {
                    store.pendingMembershipPresentation = context
                } else {
                    store.dismissMembershipPrompt(
                        hasUnresolvedPurchase: purchaseController.hasUnresolvedCheckout
                    )
                }
            }
        )
    }

    private var onboardingPresentationBinding: Binding<Bool> {
        Binding(
            get: {
                let shouldPresent = OnboardingScreenTimeAccessRouting.shouldPresentOnboarding(
                    isRequested: store.isOnboardingPresented,
                    isAuthorized: screenTime.hasRequiredScreenTimeAuthorization,
                    isAlreadyActive: isOnboardingSheetActive
                )
                return shouldPresent && (
                    isOnboardingSheetActive ||
                        !screenTimeAccessGate.blocksUnderlyingPresentations
                )
            },
            set: { isPresented in
                if isPresented {
                    store.isOnboardingPresented = true
                } else if store.cancelResumedMembershipGoalCreation() {
                    store.isOnboardingPresented = false
                    store.isCreatingGoalProfile = false
                } else {
                    store.isOnboardingPresented = true
                }
            }
        )
    }

    private var screenTimeAuthorizationRequiredBinding: Binding<Bool> {
        Binding(
            get: {
                screenTimeAccessRecoveryHost == .root
            },
            set: { _ in }
        )
    }

    private var onboardingScreenTimeAuthorizationRequiredBinding: Binding<Bool> {
        Binding(
            get: {
                screenTimeAccessRecoveryHost == .onboarding
            },
            set: { _ in }
        )
    }

    private var screenTimeAccessRecoveryHost: ScreenTimeAccessPresentationHost? {
        dataEraseRecoveryHost ?? screenTimeAccessGate.presentationHost
    }

    private var requiredScreenTimeAuthorizationHost: ScreenTimeAccessPresentationHost? {
        OnboardingScreenTimeAccessRouting.recoveryHost(
            requiresRecovery: screenTime.requiresScreenTimeAuthorization,
            isOnboardingActive: isOnboardingSheetActive
        )
    }

    private var dataEraseRecoveryHost: ScreenTimeAccessPresentationHost? {
        OnboardingScreenTimeAccessRouting.recoveryHost(
            requiresRecovery: screenTime.requiresSharedDataEraseRecovery
                || store.requiresPersistenceEraseRecovery,
            isOnboardingActive: isOnboardingSheetActive
        )
    }

    private var screenTimeAccessContext: ScreenTimeAccessContext {
        ScreenTimeAccessContext.resolve(
            requiresEraseRecovery: screenTime.requiresSharedDataEraseRecovery
                || store.requiresPersistenceEraseRecovery,
            isFirstRunPending: firstRunSetup.isPending,
            hasGoal: store.goal != nil
        )
    }

    private var isTabContentCoveredByParentPresentation: Bool {
        screenTime.requiresScreenTimeAuthorization
            || screenTime.requiresSharedDataEraseRecovery
            || store.requiresPersistenceEraseRecovery
            || screenTimeAccessGate.blocksUnderlyingPresentations
            || isAuthorizationRecoveryAppSelectionPresented
            || isCheckpointPresentationActive
            || store.pendingMembershipPresentation != nil
            || (store.isOnboardingPresented
                && screenTime.hasRequiredScreenTimeAuthorization)
            || isOnboardingSheetActive
            || firstRunSetup.isAppSelectionPresented
            || suggestedSkillMapReviewPresentation.blocksUnderlyingPresentations
            || pendingGoalSwitchConfirmation != nil
    }

    private var parentPresentationOwnsProtectionErrors: Bool {
        screenTime.requiresScreenTimeAuthorization
            || screenTime.requiresSharedDataEraseRecovery
            || store.requiresPersistenceEraseRecovery
            || screenTimeAccessGate.blocksUnderlyingPresentations
            || isAuthorizationRecoveryAppSelectionPresented
            || firstRunSetup.isAppSelectionPresented
    }
}

private enum AppTab: Hashable {
    case home
    case skill
    case settings
}
