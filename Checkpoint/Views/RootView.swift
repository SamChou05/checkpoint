import SwiftUI

struct RootView: View {
    @State private var store = CheckpointStore()
    @State private var screenTime = ScreenTimeController()
    @State private var purchaseController = PurchaseController()
    @State private var selectedTab: AppTab = .home
    @State private var activeShieldSession: CheckpointSession?
    @State private var isPreparingShieldSession = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(store: store, screenTime: screenTime)
                .tabItem {
                    Label("Home", systemImage: "target")
                }
                .tag(AppTab.home)

            CompetencyView(store: store)
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppTab.skill)

            SettingsView(store: store, screenTime: screenTime, purchaseController: purchaseController)
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(AppTab.settings)
        }
        .tint(CheckpointTheme.teal)
        .preferredColorScheme(.light)
        .sheet(item: $activeShieldSession) { session in
            CheckpointAttemptView(store: store, screenTime: screenTime, session: session)
        }
        .sheet(item: membershipFeatureBinding) { feature in
            MembershipView(feature: feature, store: store, purchaseController: purchaseController)
        }
        .sheet(
            isPresented: Binding(
                get: { store.isOnboardingPresented },
                set: { isPresented in
                    store.isOnboardingPresented = isPresented
                    if !isPresented {
                        store.isCreatingGoalProfile = false
                    }
                }
            )
        ) {
            OnboardingView(store: store)
                .interactiveDismissDisabled(store.goal == nil)
        }
        .task {
            reconcileProtectionState()
            handlePendingShieldActivation()
            purchaseController.onMembershipEntitlementChange = { unlocked in
                store.updateMembershipTier(unlocked ? .member : .starter)
            }
            purchaseController.startListeningForTransactions()
            await refreshPlanAccessFromEntitlements()
            await purchaseController.loadProducts()
            reconcileProtectionState()
            handlePendingShieldActivation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            reconcileProtectionState()
            Task {
                await refreshPlanAccessFromEntitlements()
            }
            handlePendingShieldActivation()
        }
        .onChange(of: store.goal) { _, newGoal in
            if newGoal == nil {
                store.clearUnlockSession()
                screenTime.clearShield()
            } else {
                reconcileProtectionState()
                screenTime.refreshActiveShieldConfiguration()
            }
        }
        .onChange(of: screenTime.hasSelection) { _, hasSelection in
            if !hasSelection {
                store.clearUnlockSession()
            }
        }
        .onChange(of: screenTime.setupState) { _, setupState in
            if setupState == .shieldActive,
               store.unlockSession != nil,
               store.unlockSession?.isActive != true {
                store.clearUnlockSession()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkpointShieldContextDidChange)) { _ in
            screenTime.refreshActiveShieldConfiguration()
        }
    }

    private func handlePendingShieldActivation() {
        guard activeShieldSession == nil else { return }
        guard !isPreparingShieldSession else { return }
        guard let pendingAttempt = SharedAppGroup.currentPendingShieldAttempt else { return }
        let protectionSnapshot = SharedAppGroup.currentProtectionSnapshot()
        guard protectionSnapshot.acceptsPendingShieldAttempt(
            configurationRevision: pendingAttempt.protectionConfigurationRevision,
            hasSelection: screenTime.hasSelection
        )
        else {
            _ = SharedAppGroup.consumePendingShieldAttempt(matchingID: pendingAttempt.id)
            return
        }
        let pendingProtectionRevision = pendingAttempt.protectionConfigurationRevision
            ?? protectionSnapshot.configurationRevision

        selectedTab = .home
        isPreparingShieldSession = true

        Task {
            let preparedSession = await store.preparePendingShieldSession(
                pendingAttemptID: pendingAttempt.id
            )
            let latestProtectionSnapshot = SharedAppGroup.currentProtectionSnapshot()
            let pendingAttemptAfterPreparation = SharedAppGroup.currentPendingShieldAttempt
            let newerPendingAttemptExists = pendingAttemptAfterPreparation.map {
                $0.id != pendingAttempt.id
            } ?? false
            if pendingAttemptAfterPreparation == nil,
               latestProtectionSnapshot.acceptsPendingShieldAttempt(
                configurationRevision: pendingProtectionRevision,
                hasSelection: screenTime.hasSelection
            ) {
                activeShieldSession = preparedSession
            }
            isPreparingShieldSession = false
            if newerPendingAttemptExists {
                handlePendingShieldActivation()
            }
        }
    }

    private func reconcileProtectionState() {
        guard store.goal != nil else {
            if store.unlockSession != nil {
                store.clearUnlockSession()
            }
            screenTime.clearShield()
            return
        }

        let protectionSnapshot = SharedAppGroup.currentProtectionSnapshot()
        screenTime.reconcileShieldState(
            protectionShouldRemainActive: protectionSnapshot.desiredShieldActive
        )

        let reconciledProtectionSnapshot = SharedAppGroup.currentProtectionSnapshot()
        let canonicalBreakIsActive = reconciledProtectionSnapshot.unlockExpiration.map {
            $0 > Date()
        } ?? false
        if store.unlockSession != nil,
           (!reconciledProtectionSnapshot.desiredShieldActive ||
            !canonicalBreakIsActive ||
            store.unlockSession?.isActive != true) {
            store.clearUnlockSession()
        }
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
}

private enum AppTab: Hashable {
    case home
    case skill
    case settings
}
