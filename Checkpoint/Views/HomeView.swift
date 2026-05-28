import SwiftUI

struct HomeView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController

    @Environment(\.scenePhase) private var scenePhase
    @State private var activeSession: CheckpointSession?
    @State private var isRestrictedAppsPresented = false
    @State private var isPreparingCheckpoint = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    checkpointNoticePanel

                    if let goal = store.goal {
                        goalHero(goal)
                        metricsGrid
                        proAssistPanel
                        screenTimePanel
                    } else {
                        emptyState
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Checkpoint")
            .toolbarTitleDisplayMode(.inline)
            .sheet(item: $activeSession) { session in
                CheckpointAttemptView(store: store, screenTime: screenTime, session: session)
            }
            .sheet(isPresented: $isRestrictedAppsPresented) {
                RestrictedAppsView(screenTime: screenTime)
            }
            .onAppear {
                handleQuestionRefreshOnActivation()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    handleQuestionRefreshOnActivation()
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Study before distraction")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)

                Text("Clear a checkpoint before you scroll.")
                    .font(.largeTitle.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(CheckpointTheme.blue)
                .frame(width: 48, height: 48)
                .background(CheckpointTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.top, 8)
    }

    private func goalHero(_ goal: Goal) -> some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    StatusBadge(text: goal.category.rawValue, tint: CheckpointTheme.teal)
                    Spacer()
                    goalSwitcher
                    Text(goal.deadline, style: .date)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)
                }

                Text(goal.title)
                    .font(.title2.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Focus: \(goal.focusAreas.isEmpty ? "next meaningful rep" : goal.focusAreas)")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                StatusBadge(text: goal.difficultyLabel, tint: CheckpointTheme.amber)

                Text("A blocked app asks \(store.unlockPolicy.questionsPerSession) questions. \(store.unlockPolicy.requiredCorrectAnswers) correct starts the unlock timer.")
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryActionButton(title: isPreparingCheckpoint ? "Preparing checkpoint" : "Start a checkpoint", systemImage: "play.fill") {
                    startCheckpoint()
                }
                .disabled(isPreparingCheckpoint)
            }
        }
    }

    @ViewBuilder
    private var proAssistPanel: some View {
        if store.isPro, let focus = store.proFocusRecommendation {
            SectionPanel("Study Assist") {
                VStack(alignment: .leading, spacing: 10) {
                    StatusBadge(text: "Adaptive focus", tint: CheckpointTheme.teal)

                    Text(focus)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var checkpointNoticePanel: some View {
        if let notice = store.checkpointNotice {
            SectionPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CheckpointTheme.amber)

                        Text(notice)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        SecondaryActionButton(title: "Dismiss", systemImage: "xmark") {
                            store.clearCheckpointNotice()
                        }

                        if store.goal != nil {
                            SecondaryActionButton(title: "Try checkpoint", systemImage: "play.fill") {
                                startCheckpoint()
                            }
                            .disabled(isPreparingCheckpoint)
                        }
                    }
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(
                title: "Answers today",
                value: "\(store.completedTodayCount)",
                tint: CheckpointTheme.teal,
                systemImage: "checkmark.seal"
            )

            MetricTile(
                title: "Conversion rate",
                value: store.conversionRateText,
                tint: CheckpointTheme.amber,
                systemImage: "arrow.triangle.2.circlepath"
            )

            MetricTile(
                title: "Average mastery",
                value: store.averageMasteryText,
                tint: CheckpointTheme.blue,
                systemImage: "chart.line.uptrend.xyaxis"
            )

            MetricTile(
                title: "Unlock remaining",
                value: "\(store.activeUnlockMinutesRemaining)m",
                tint: CheckpointTheme.coral,
                systemImage: "timer"
            )
        }
    }

    private var screenTimePanel: some View {
        SectionPanel("Blocked apps") {
            VStack(alignment: .leading, spacing: 12) {
                Text(screenTime.restrictedAppsSummary)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.text)

                HStack(spacing: 10) {
                    SecondaryActionButton(title: "Choose blocked apps", systemImage: "checklist") {
                        isRestrictedAppsPresented = true
                    }

                    SecondaryActionButton(title: screenTime.isShieldingEnabled ? "Unlock with checkpoint" : "Start blocking", systemImage: screenTime.isShieldingEnabled ? "lock.open" : "shield") {
                        if screenTime.isShieldingEnabled {
                            startCheckpoint()
                        } else {
                            screenTime.applyShield()
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Set one goal first.")
                    .font(.title2.bold())
                    .foregroundStyle(CheckpointTheme.text)

                    Text("Checkpoint will prepare multiple-choice questions, then ask the right ones when a blocked app is opened.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryActionButton(title: "Create goal", systemImage: "plus") {
                    store.presentGoalProfileCreator()
                }
            }
        }
    }

    @ViewBuilder
    private var goalSwitcher: some View {
        if store.isPro, store.availableGoalProfiles.count > 1 {
            Menu {
                ForEach(store.availableGoalProfiles) { profile in
                    Button {
                        store.switchActiveGoal(to: profile.id)
                    } label: {
                        Label(
                            profile.title,
                            systemImage: profile.id == store.goal?.id ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }

                Divider()

                Button {
                    store.presentGoalProfileCreator()
                } label: {
                    Label("New profile", systemImage: "plus")
                }
            } label: {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 32, height: 32)
                    .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private func handleQuestionRefreshOnActivation() {
        guard activeSession == nil else { return }

        Task {
            let didRefresh = await store.refreshQuestionBatchIfNeeded()
            if didRefresh,
               activeSession == nil,
               store.checkpointNotice != nil {
                activeSession = await store.prepareManualCheckpointSession()
            }
        }
    }

    private func startCheckpoint() {
        guard !isPreparingCheckpoint else { return }
        isPreparingCheckpoint = true

        Task {
            activeSession = await store.prepareManualCheckpointSession()
            isPreparingCheckpoint = false
        }
    }
}
