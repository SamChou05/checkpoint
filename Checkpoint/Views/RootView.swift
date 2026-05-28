import SwiftUI

struct RootView: View {
    @State private var store = CheckpointStore()
    @State private var screenTime = ScreenTimeController()
    @State private var purchaseController = PurchaseController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeView(store: store, screenTime: screenTime)
                .tabItem {
                    Label("Home", systemImage: "target")
                }

            HistoryView(store: store)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            CompetencyView(store: store)
                .tabItem {
                    Label("Skill", systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView(store: store, screenTime: screenTime, purchaseController: purchaseController)
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
        }
        .tint(CheckpointTheme.teal)
        .preferredColorScheme(.light)
        .sheet(
            isPresented: Binding(
                get: { store.isOnboardingPresented },
                set: { store.isOnboardingPresented = $0 }
            )
        ) {
            OnboardingView(store: store)
                .interactiveDismissDisabled(store.goal == nil)
        }
        .task {
            purchaseController.startListeningForTransactions()
            await purchaseController.loadProducts()
            let isProUnlocked = await purchaseController.refreshEntitlements()
            store.updateSubscriptionTier(isProUnlocked ? .pro : .free)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            screenTime.reconcileShieldState()
            Task {
                let isProUnlocked = await purchaseController.refreshEntitlements()
                store.updateSubscriptionTier(isProUnlocked ? .pro : .free)
            }
        }
    }
}
