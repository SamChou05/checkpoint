import SwiftUI

struct RootView: View {
    let store: CheckpointStore
    @State private var screenTime = ScreenTimeController()
    @State private var purchaseController = PurchaseController()
    @State private var selectedTab: AppTab = .home
    @State private var activeShieldSession: CheckpointSession?
    @State private var isPreparingShieldSession = false
    @Environment(\.scenePhase) private var scenePhase

    init(store: CheckpointStore) {
        self.store = store
    }

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
        .sheet(item: membershipFeatureBinding) { feature in
            MembershipView(feature: feature, store: store, purchaseController: purchaseController)
        }
        .sheet(isPresented: proCloudConsentBinding) {
            ProCloudGenerationConsentView(store: store)
                .interactiveDismissDisabled()
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
            purchaseController.onMembershipEntitlementChange = { unlocked in
                store.updateMembershipTier(unlocked ? .member : .starter)
            }
            purchaseController.startListeningForTransactions()
            await refreshPlanAccessFromEntitlements()
            reconcileProtectionState()
            handlePendingShieldActivation()
            Task {
                await screenTime.requestInitialAuthorizationIfNeeded()
            }
            Task {
                await store.prepareQuestionMaintenanceAfterLaunch()
                QuestionBankBackgroundScheduler.schedule()
            }
            Task {
                await purchaseController.loadProducts()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                reconcileProtectionState()
                Task {
                    await refreshPlanAccessFromEntitlements()
                    _ = await store.performBackgroundQuestionMaintenance(maximumBatchCount: 1)
                }
                handlePendingShieldActivation()
            } else if newPhase == .background {
                store.scheduleServerQuestionReserveMaintenance()
                QuestionBankBackgroundScheduler.schedule()
            }
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

    private func reconcileProtectionState() {
        screenTime.reconcileShieldState(
            protectionShouldRemainActive: SharedAppGroup.desiredShieldActive || store.unlockSession != nil,
            fallbackUnlockExpiration: store.unlockSession?.expiresAt
        )
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

    private var proCloudConsentBinding: Binding<Bool> {
        Binding(
            get: {
                store.shouldPresentProCloudGenerationConsent
                    && SharedAppGroup.pendingShieldAttemptDate == nil
                    && !isPreparingShieldSession
                    && activeShieldSession == nil
            },
            set: { _ in }
        )
    }
}

private struct ProCloudGenerationConsentView: View {
    let store: CheckpointStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(CheckpointTheme.teal)

                        Text("Use Pro cloud questions?")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Cloud generation creates more varied questions ahead of time. If the service is unavailable, Checkpoint keeps practice ready with local questions.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("What is shared") {
                        Text("Checkpoint sends your goal title and deadline, current level, focus areas, skill progress, recent question coverage, and any question-report notes to its AWS question service.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Pro can keep up to 20 prepared questions per goal in a background reserve. Inactive cloud data expires after 30 days, and turning cloud generation off requests deletion.")
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let privacyPolicyURL = AppResourceURL.configuredHTTPSValue(
                        forInfoDictionaryKey: "CheckpointPrivacyPolicyURL"
                    ) {
                        Link("Read the Privacy Policy", destination: privacyPolicyURL)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.teal)
                    }

                    PrimaryActionButton(
                        title: "Use Pro cloud questions",
                        systemImage: "cloud.fill"
                    ) {
                        store.updateBackendQuestionGenerationConsent(true)
                    }

                    SecondaryActionButton(
                        title: "Keep questions on this device",
                        systemImage: "iphone"
                    ) {
                        store.declineProCloudQuestionGeneration()
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Question generation")
            .toolbarTitleDisplayMode(.inline)
        }
    }
}

private enum AppTab: Hashable {
    case home
    case skill
    case settings
}
