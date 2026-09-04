import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @Environment(\.scenePhase) private var scenePhase

    private var store: CheckpointStore { appModel.store }
    private var screenTime: ScreenTimeController { appModel.screenTime }
    private var purchaseController: PurchaseController { appModel.purchaseController }
    private var workflow: CheckpointWorkflowCoordinator { appModel.workflow }

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
        .fullScreenCover(isPresented: screenTimeAuthorizationRequiredBinding) {
            RequiredScreenTimeAccessView(store: store, screenTime: screenTime)
                .interactiveDismissDisabled()
        }
        .sheet(item: $activeCheckpointSession, onDismiss: handlePendingShieldActivation) { session in
            CheckpointAttemptView(store: store, workflow: workflow, session: session)
        }
        .sheet(item: membershipFeatureBinding) { feature in
            MembershipView(feature: feature, store: store, purchaseController: purchaseController)
        }
        .sheet(
            isPresented: onboardingPresentationBinding,
            onDismiss: handleOnboardingDismissed
        ) {
            OnboardingView(store: store) {
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
            onDismiss: {
                isSuggestedSkillMapReviewActive = false
            }
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
            workflow.goalDidChange()
            presentSuggestedSkillMapReviewIfNeeded()
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
        .onChange(of: store.hasReadyCheckpointSet) { _, _ in
            guard activeCheckpointSession == nil else { return }
            reconcileProtectionAndHandlePendingAttempt()
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkpointShieldContextDidChange)) { _ in
            workflow.refreshProtectionConfiguration()
        }
    }

    private func bootstrap() async {
        if store.goal == nil {
            beginFirstRunSetup()
        }

        await screenTime.bootstrapAuthorizationIfNeeded()
        reconcileProtectionAndHandlePendingAttempt()

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
              !firstRunSetup.isAppSelectionPresented,
              activeCheckpointSession == nil,
              store.pendingMembershipFeature == nil,
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
        presentSuggestedSkillMapReviewIfNeeded()
    }

    private func handleFirstRunAppSelectionDismissed() {
        guard !firstRunSetup.isPending else { return }
        selectedTab = .home
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

    private var membershipFeatureBinding: Binding<MembershipFeature?> {
        Binding(
            get: { store.pendingMembershipFeature },
            set: { feature in
                if let feature {
                    store.pendingMembershipFeature = feature
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
}

private enum AppTab: Hashable {
    case home
    case skill
    case settings
}
