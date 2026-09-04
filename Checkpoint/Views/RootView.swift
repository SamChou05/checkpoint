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

private struct ProtectionReconciliationKey: Equatable {
    let goalID: Goal.ID?
    let goalTitle: String?
    let hasReadyCheckpoint: Bool
}

struct RootView: View {
    @State private var appModel = CheckpointAppModel()
    @State private var selectedTab: AppTab = .home
    @State private var activeCheckpointSession: CheckpointSession?
    @State private var pendingShieldRetryTask: Task<Void, Never>?
    @State private var isSuggestedSkillMapReviewPresented = false
    @State private var isSuggestedSkillMapReviewActive = false
    @State private var lastPresentedSkillMapSignature: String?
    @State private var firstRunSetup = FirstRunSetupCoordinator()
    @State private var isOnboardingSheetActive = false
    @State private var isFirstRunAppSelectionQueued = false
    @State private var isAuthorizationRecoveryAppSelectionPresented = false
    @State private var authorizationRecoveryQueue = ScreenTimeAccessRecoveryQueue()
    @State private var pendingGoalSwitchConfirmation: GoalSwitchConfirmation?
    @State private var queuedGoalSwitchConfirmation: GoalSwitchConfirmation?
    @State private var goalSwitchFeedbackSequence = 0
    @Environment(\.scenePhase) private var scenePhase

    private var store: CheckpointStore { appModel.store }
    private var screenTime: ScreenTimeController { appModel.screenTime }
    private var purchaseController: PurchaseController { appModel.purchaseController }
    private var workflow: CheckpointWorkflowCoordinator { appModel.workflow }
    private var protectionReconciliationKey: ProtectionReconciliationKey {
        ProtectionReconciliationKey(
            goalID: store.goal?.id,
            goalTitle: store.goal?.title,
            hasReadyCheckpoint: store.hasReadyCheckpointSet
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(store: store, screenTime: screenTime, workflow: workflow)
                .tabItem {
                    Label("Home", systemImage: "target")
                }
                .tag(AppTab.home)

            CompetencyView(
                store: store,
                isVisible: selectedTab == .skill,
                isCoveredByParentModal: isOnboardingSheetActive
                    || isSuggestedSkillMapReviewPresented
                    || isSuggestedSkillMapReviewActive
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
                presentCheckpoint: presentCheckpoint
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
                queuedGoalSwitchConfirmation = nil
                pendingGoalSwitchConfirmation = nil
            }
        } message: { confirmation in
            Text(goalSwitchConfirmationPresentation(for: confirmation).message)
        }
        .fullScreenCover(
            isPresented: screenTimeAuthorizationRequiredBinding,
            onDismiss: handleScreenTimeAccessDismissed
        ) {
            RequiredScreenTimeAccessView(
                store: store,
                screenTime: screenTime,
                context: screenTimeAccessContext
            )
                .interactiveDismissDisabled()
        }
        .sheet(
            isPresented: $isAuthorizationRecoveryAppSelectionPresented,
            onDismiss: presentSuggestedSkillMapReviewIfNeeded
        ) {
            RestrictedAppsView(screenTime: screenTime)
        }
        .sheet(item: $activeCheckpointSession, onDismiss: handleCheckpointDismissed) { session in
            CheckpointAttemptView(store: store, workflow: workflow, session: session)
        }
        .sheet(item: membershipPresentationBinding, onDismiss: handleMembershipDismissed) { context in
            MembershipView(context: context, store: store, purchaseController: purchaseController)
        }
        .sheet(
            isPresented: onboardingPresentationBinding,
            onDismiss: handleOnboardingDismissed
        ) {
            OnboardingView(store: store, workflow: workflow) {
                beginFirstRunSetup()
            }
                .onAppear {
                    isOnboardingSheetActive = true
                }
                .interactiveDismissDisabled(store.goal == nil)
        }
        .sheet(
            isPresented: firstRunAppSelectionPresentationBinding,
            onDismiss: handleFirstRunAppSelectionDismissed
        ) {
            RestrictedAppsView(
                screenTime: screenTime,
                onStartProtection: startFirstRunProtection,
                onFinishProtectedSetup: {
                    firstRunSetup.finishProtectedSetup()
                },
                onContinueWithoutProtection: {
                    firstRunSetup.continueWithoutProtection(
                        currentGoalID: store.goal?.id,
                        stopProtection: workflow.stopProtectionWithoutReview
                    )
                },
                onProtectionUnavailable: {
                    firstRunSetup.protectionDidBecomeUnavailable()
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(
            isPresented: $isSuggestedSkillMapReviewPresented,
            onDismiss: handleSuggestedSkillMapReviewDismissed
        ) {
            SkillMapReviewView(store: store)
                .onAppear {
                    isSuggestedSkillMapReviewActive = true
                }
        }
        .task {
            await bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            handleAppActivation()
        }
        .onChange(of: screenTime.hasRequiredScreenTimeAuthorization) { _, isAuthorized in
            guard isAuthorized else { return }
            reconcileProtectionAndHandlePendingAttempt()
            resumeFirstRunSetupIfNeeded()
        }
        .onChange(of: store.goal) { _, _ in
            if store.goal == nil {
                beginFirstRunSetup()
            }
            presentSuggestedSkillMapReviewIfNeeded()
        }
        .onChange(of: protectionReconciliationKey) { _, _ in
            guard activeCheckpointSession == nil else { return }
            reconcileProtectionAndHandlePendingAttempt()
        }
        .onChange(of: store.activeDerivedSkillMap) { _, _ in
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

    private var goalSwitchConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingGoalSwitchConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingGoalSwitchConfirmation = nil
                    promoteQueuedGoalSwitchConfirmationAfterDismissal()
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
        case let .confirmationRequired(confirmation):
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = confirmation
        case .alreadyActive, .membershipRequired:
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = nil
        case .targetNotFound, .staleRequest:
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = nil
            AccessibilityNotification.Announcement(
                "That goal changed. Choose it again."
            ).post()
        case .persistenceFailed:
            queuedGoalSwitchConfirmation = nil
            pendingGoalSwitchConfirmation = nil
            AccessibilityNotification.Announcement(
                "Checkpoint couldn't save the goal change. Your current goal is unchanged."
            ).post()
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
        reconcileProtectionAndHandlePendingAttempt()
        queueAuthorizationRecoveryAppSelectionIfNeeded()

        purchaseController.onMembershipEntitlementChange = { unlocked in
            store.reconcileMembershipEntitlement(isUnlocked: unlocked)
        }
        purchaseController.startListeningForTransactions()
        await refreshPlanAccessFromEntitlements()
        await purchaseController.loadProducts()

        reconcileProtectionAndHandlePendingAttempt()
        resumeFirstRunSetupIfNeeded()
        presentSuggestedSkillMapReviewIfNeeded()
    }

    private func handleAppActivation() {
        screenTime.refreshAuthorizationStatus()
        workflow.reconcileProtectionState()
        Task {
            await refreshPlanAccessFromEntitlements()
        }
        handlePendingShieldActivation()
        resumeFirstRunSetupIfNeeded()
    }

    private func reconcileProtectionAndHandlePendingAttempt() {
        workflow.reconcileProtectionState()
        handlePendingShieldActivation()
    }

    private func handlePendingShieldActivation() {
        guard activeCheckpointSession == nil else { return }
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
        guard !firstRunSetup.isPending,
              !store.isOnboardingPresented,
              !isOnboardingSheetActive,
              !isAuthorizationRecoveryAppSelectionPresented,
              !authorizationRecoveryQueue.isQueued,
              !authorizationRecoveryQueue.isScheduling,
              !firstRunSetup.isAppSelectionPresented,
              activeCheckpointSession == nil,
              store.pendingMembershipPresentation == nil,
              let goalID = store.goal?.id,
              goalID != firstRunSetup.suppressedSuggestedSkillMapGoalID,
              let skillMap = store.activeDerivedSkillMap,
              skillMap.status == .suggested else {
            return
        }

        let signature = "\(goalID.uuidString):\(skillMap.version):\(skillMap.updatedAt.timeIntervalSince1970)"
        guard signature != lastPresentedSkillMapSignature else { return }
        lastPresentedSkillMapSignature = signature
        isSuggestedSkillMapReviewPresented = true
    }

    private func handleOnboardingDismissed() {
        isOnboardingSheetActive = false
        resumeFirstRunSetupIfNeeded()
        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
        presentSuggestedSkillMapReviewIfNeeded()
    }

    private func handleFirstRunAppSelectionDismissed() {
        guard !firstRunSetup.isPending else { return }
        selectedTab = .home
        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
    }

    private func handleCheckpointDismissed() {
        handlePendingShieldActivation()
        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
    }

    private func handleMembershipDismissed() {
        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
        presentSuggestedSkillMapReviewIfNeeded()
    }

    private func handleSuggestedSkillMapReviewDismissed() {
        isSuggestedSkillMapReviewActive = false
        presentQueuedAuthorizationRecoveryAppSelectionIfPossible()
    }

    private func handleScreenTimeAccessDismissed() {
        queueAuthorizationRecoveryAppSelectionIfNeeded()
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
            activeCheckpointSession == nil &&
            store.pendingMembershipPresentation == nil &&
            !store.isOnboardingPresented &&
            !isOnboardingSheetActive &&
            !firstRunSetup.isAppSelectionPresented &&
            !isSuggestedSkillMapReviewPresented &&
            !isSuggestedSkillMapReviewActive
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
                activeCheckpointSession == nil &&
                store.pendingMembershipPresentation == nil &&
                !store.isOnboardingPresented &&
                !isOnboardingSheetActive &&
                !firstRunSetup.isAppSelectionPresented &&
                !isSuggestedSkillMapReviewPresented &&
                !isSuggestedSkillMapReviewActive
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
        await firstRunSetup.startProtection(
            isPreparingQuestions: { store.isPreparingActiveGoalQuestions },
            startProtection: { await workflow.startProtection() },
            checkpointNotice: { store.checkpointNotice },
            screenTimeErrorMessage: { screenTime.userFacingErrorMessage },
            selectionSummary: { screenTime.restrictedAppsSummary },
            currentGoalID: { store.goal?.id }
        )
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
        guard activeCheckpointSession == nil, workflow.operation == nil else {
            store.discardCheckpointRunBeforePresentation(sessionID: session.id)
            return false
        }
        activeCheckpointSession = session
        return true
    }

    @MainActor
    private func refreshPlanAccessFromEntitlements() async {
        let unlocked = await purchaseController.refreshEntitlements()
        store.reconcileMembershipEntitlement(isUnlocked: unlocked)
    }

    private var membershipPresentationBinding: Binding<MembershipPresentationContext?> {
        Binding(
            get: { store.pendingMembershipPresentation },
            set: { context in
                if let context {
                    store.pendingMembershipPresentation = context
                } else {
                    store.dismissMembershipPrompt()
                }
            }
        )
    }

    private var onboardingPresentationBinding: Binding<Bool> {
        Binding(
            get: {
                store.isOnboardingPresented
                    && screenTime.hasRequiredScreenTimeAuthorization
            },
            set: { isPresented in
                store.isOnboardingPresented = isPresented
                if !isPresented {
                    store.isCreatingGoalProfile = false
                }
            }
        )
    }

    private var screenTimeAuthorizationRequiredBinding: Binding<Bool> {
        Binding(
            get: {
                screenTime.requiresScreenTimeAuthorization
                    || screenTime.requiresSharedDataEraseRecovery
                    || store.requiresPersistenceEraseRecovery
            },
            set: { _ in }
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
}

private enum AppTab: Hashable {
    case home
    case skill
    case settings
}
