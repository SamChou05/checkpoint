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
                    Label("Skill", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppTab.skill)

            SettingsView(store: store, screenTime: screenTime)
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
            purchaseController.startListeningForTransactions()
            #if DEBUG
            store.updateMembershipTier(.member)
            await purchaseController.loadProducts()
            #else
            await refreshPlanAccessFromEntitlements()
            await purchaseController.loadProducts()
            #endif
            handlePendingShieldActivation()
            Task {
                await screenTime.requestInitialAuthorizationIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            screenTime.reconcileShieldState()
            #if !DEBUG
            Task {
                await refreshPlanAccessFromEntitlements()
            }
            #endif
            handlePendingShieldActivation()
        }
        .onChange(of: store.goal) { _, _ in
            screenTime.refreshActiveShieldConfiguration()
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkpointShieldContextDidChange)) { _ in
            screenTime.refreshActiveShieldConfiguration()
        }
    }

    private func handlePendingShieldActivation() {
        guard activeShieldSession == nil else { return }
        guard !isPreparingShieldSession else { return }
        guard SharedAppGroup.pendingShieldAttemptDate != nil else { return }

        selectedTab = .home
        isPreparingShieldSession = true

        Task {
            activeShieldSession = await store.preparePendingShieldSession()
            isPreparingShieldSession = false
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
