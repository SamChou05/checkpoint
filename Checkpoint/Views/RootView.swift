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
            handlePendingShieldActivation()
            Task {
                await screenTime.requestInitialAuthorizationIfNeeded()
            }
            purchaseController.startListeningForTransactions()
            await purchaseController.loadProducts()
            let isProUnlocked = await purchaseController.refreshEntitlements()
            store.updateSubscriptionTier(isProUnlocked ? .pro : .free)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            screenTime.reconcileShieldState()
            handlePendingShieldActivation()
            Task {
                let isProUnlocked = await purchaseController.refreshEntitlements()
                store.updateSubscriptionTier(isProUnlocked ? .pro : .free)
            }
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
}

private enum AppTab: Hashable {
    case home
    case skill
    case settings
}
