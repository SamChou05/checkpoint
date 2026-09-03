import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

struct RootView: View {
    @State private var appModel = CheckpointAppModel()
    @State private var selectedTab: AppTab = .home
    @State private var activeCheckpointSession: CheckpointSession?
    @State private var pendingShieldRetryTask: Task<Void, Never>?
    @State private var isSuggestedSkillMapReviewPresented = false
    @State private var lastPresentedSkillMapSignature: String?
    @State private var isFirstRunSetupPending = FirstRunSetupProgress.isPending()
    @State private var isOnboardingSheetActive = false
    @State private var isFirstRunAppSelectionQueued = false
    @State private var isFirstRunAppSelectionPresented = false
    @State private var suppressedSuggestedSkillMapGoalID: Goal.ID?
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

            CompetencyView(store: store)
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
            isPresented: $isFirstRunAppSelectionPresented,
            onDismiss: handleFirstRunAppSelectionDismissed
        ) {
            RestrictedAppsView(
                screenTime: screenTime,
                presentationMode: .firstRun,
                onStartProtection: finishFirstRunSetup,
                onContinueWithoutProtection: completeFirstRunSetup
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $isSuggestedSkillMapReviewPresented) {
            SkillMapReviewView(store: store)
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
                suppressedSuggestedSkillMapGoalID = nil
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
            store.updateMembershipTier(unlocked ? .member : .starter)
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
        guard !isFirstRunSetupPending,
              !store.isOnboardingPresented,
              !isOnboardingSheetActive,
              !isFirstRunAppSelectionPresented,
              activeCheckpointSession == nil,
              store.pendingMembershipFeature == nil,
              let goalID = store.goal?.id,
              goalID != suppressedSuggestedSkillMapGoalID,
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
        guard !isFirstRunSetupPending else { return }
        selectedTab = .home
    }

    private func beginFirstRunSetup() {
        FirstRunSetupProgress.begin()
        isFirstRunSetupPending = true
    }

    private func resumeFirstRunSetupIfNeeded() {
        guard
            FirstRunSetupProgress.shouldResumeAppSelection(
                isPending: isFirstRunSetupPending,
                hasGoal: store.goal != nil,
                isAuthorized: screenTime.hasRequiredScreenTimeAuthorization,
                isOnboardingPresented: store.isOnboardingPresented
            ),
            !isOnboardingSheetActive,
            !isFirstRunAppSelectionPresented,
            !isFirstRunAppSelectionQueued
        else {
            return
        }

        isFirstRunAppSelectionQueued = true
        Task { @MainActor in
            await Task.yield()
            guard
                FirstRunSetupProgress.shouldResumeAppSelection(
                    isPending: isFirstRunSetupPending,
                    hasGoal: store.goal != nil,
                    isAuthorized: screenTime.hasRequiredScreenTimeAuthorization,
                    isOnboardingPresented: store.isOnboardingPresented
                ),
                !isOnboardingSheetActive
            else {
                isFirstRunAppSelectionQueued = false
                return
            }
            isFirstRunAppSelectionPresented = true
            isFirstRunAppSelectionQueued = false
        }
    }

    private func finishFirstRunSetup() async -> String? {
        let preparationDeadline = Date().addingTimeInterval(45)
        while store.isPreparingActiveGoalQuestions, Date() < preparationDeadline {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return "Setup was interrupted. Try turning protection on again."
            }
        }

        if store.isPreparingActiveGoalQuestions {
            return "Your first checkpoint is still being prepared. Try again in a moment."
        }

        let didStartProtection = await FirstRunSetupProgress.completeAfterStartingProtection {
            await workflow.startProtection()
        }
        guard didStartProtection else {
            return store.checkpointNotice
                ?? screenTime.userFacingErrorMessage
                ?? "Protection could not turn on. Check your selections and try again."
        }

        isFirstRunSetupPending = false
        suppressedSuggestedSkillMapGoalID = store.goal?.id
        return nil
    }

    private func completeFirstRunSetup() {
        FirstRunSetupProgress.complete()
        isFirstRunSetupPending = false
        suppressedSuggestedSkillMapGoalID = store.goal?.id
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
        store.updateMembershipTier(unlocked ? .member : .starter)
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
