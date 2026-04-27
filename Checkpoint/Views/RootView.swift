import SwiftUI

struct RootView: View {
    @State private var store = CheckpointStore()
    @State private var screenTime = ScreenTimeController()
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

            SettingsView(store: store, screenTime: screenTime)
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
        }
        .tint(CheckpointTheme.teal)
        .preferredColorScheme(.dark)
        .sheet(
            isPresented: Binding(
                get: { store.isOnboardingPresented },
                set: { store.isOnboardingPresented = $0 }
            )
        ) {
            OnboardingView(store: store)
                .interactiveDismissDisabled(store.goal == nil)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            screenTime.reconcileShieldState()
        }
    }
}
