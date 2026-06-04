import SwiftUI

struct HomeView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController

    @Environment(\.scenePhase) private var scenePhase
    @State private var isRestrictedAppsPresented = false
    @State private var isInsightsPresented = false
    @State private var isAcceptingLevelIncrease = false
    @State private var lastActivationRefreshAt: Date?

    private static let activationRefreshDebounceInterval: TimeInterval = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    checkpointNoticePanel

                    if let goal = store.goal {
                        goalHero(goal)
                        weeklyStatsPanel
                        studyAssistPanel
                        screenTimePanel
                    } else {
                        emptyState
                    }
                }
                .padding(20)
                .padding(.bottom, 56)
            }
            .padding(.bottom, 48)
            .checkpointScreenBackground()
            .navigationTitle("Checkpoint")
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $isRestrictedAppsPresented) {
                RestrictedAppsView(screenTime: screenTime)
            }
            .sheet(isPresented: $isInsightsPresented) {
                InsightsView(store: store)
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
                Text("Consistency compounds")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)

                Text("Practice toward the goal you chose.")
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
                    currentGoalMenu(goal)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Deadline: \(goal.deadline.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits)))")
                        Text(Goal.deadlineDistanceText(until: goal.deadline))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)
                    .lineLimit(1)
                }

                Text("Goal: \(goal.title)")
                    .font(.title2.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if let focusText = store.activeGoalFocusText {
                    Text("Focus: \(focusText)")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                StatusBadge(text: goal.difficultyLabel, tint: CheckpointTheme.amber)

                if store.isPreparingActiveGoalQuestions {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(CheckpointTheme.teal)

                        Text(store.questionGenerationStatusText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                } else if store.questionBatchState == .failed {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CheckpointTheme.amber)

                        Text(store.questionGenerationStatusText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                }

                Text("Protected apps open after a short practice set: \(store.unlockPolicy.questionsPerSession) questions, \(store.unlockPolicy.requiredCorrectAnswers) correct to begin a break.")
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var studyAssistPanel: some View {
        let levelRecommendation = store.questionLevelRecommendation
        let focusRecommendation = store.studyFocusRecommendation

        if levelRecommendation != nil || focusRecommendation != nil {
            SectionPanel("Next step") {
                VStack(alignment: .leading, spacing: 12) {
                    if let levelRecommendation {
                        levelUpRecommendationCard(levelRecommendation)
                    }

                    if let focusRecommendation {
                        VStack(alignment: .leading, spacing: 10) {
                            StatusBadge(text: "Next focus", tint: CheckpointTheme.teal)

                            Text(focusRecommendation)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func levelUpRecommendationCard(_ recommendation: QuestionLevelRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBadge(text: "Ready for more depth", tint: CheckpointTheme.amber)

            Text("\(recommendation.accuracyPercent)% accuracy across \(recommendation.answeredCount) recent level \(recommendation.currentQuestionLevel) questions.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryActionButton(
                title: isAcceptingLevelIncrease ? "Preparing deeper questions" : "Raise question level",
                systemImage: "arrow.up.circle"
            ) {
                Task {
                    guard !isAcceptingLevelIncrease else { return }
                    isAcceptingLevelIncrease = true
                    await store.acceptQuestionLevelRecommendation()
                    isAcceptingLevelIncrease = false
                }
            }
            .disabled(isAcceptingLevelIncrease)
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
                    }
                }
            }
        }
    }

    private var weeklyStatsPanel: some View {
        SectionPanel("Weekly stats") {
            VStack(alignment: .leading, spacing: 12) {
                let weeklyMetrics = store.weeklyTotalMetrics

                Text("Across all goals this week.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(
                        title: "Questions answered",
                        value: "\(weeklyMetrics.questionsAnswered)",
                        tint: CheckpointTheme.teal,
                        systemImage: "checkmark.seal"
                    )

                    MetricTile(
                        title: "Question accuracy",
                        value: weeklyMetrics.accuracyText,
                        tint: CheckpointTheme.amber,
                        systemImage: "arrow.triangle.2.circlepath"
                    )

                    MetricTile(
                        title: "Skill progress",
                        value: weeklyMetrics.skillProgressText,
                        tint: CheckpointTheme.blue,
                        systemImage: "chart.line.uptrend.xyaxis"
                    )

                    MetricTile(
                        title: "Break remaining",
                        value: "\(store.activeUnlockMinutesRemaining)m",
                        tint: CheckpointTheme.coral,
                        systemImage: "timer"
                    )
                }

                SecondaryActionButton(title: "View insights", systemImage: "chart.bar.xaxis") {
                    isInsightsPresented = true
                }
            }
        }
    }

    private var screenTimePanel: some View {
        SectionPanel("Protected apps") {
            VStack(alignment: .leading, spacing: 12) {
                Text(screenTime.restrictedAppsSummary)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    HomeProtectionActionButton(title: "Choose apps", systemImage: "checklist") {
                        isRestrictedAppsPresented = true
                    }

                    if screenTime.isShieldingEnabled {
                        StatusBadge(text: "Protection active", tint: CheckpointTheme.teal)
                    } else if isTemporarilyUnblocked {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                StatusBadge(text: "Break in progress", tint: CheckpointTheme.amber)
                                Spacer()
                                Text("\(store.activeUnlockMinutesRemaining)m left")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.muted)
                            }

                            HomeProtectionActionButton(title: "End break early", systemImage: "shield") {
                                store.clearUnlockSession()
                                screenTime.applyShield()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HomeProtectionActionButton(title: "Start protection", systemImage: "shield") {
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
                Text("Begin with one goal.")
                    .font(.title2.bold())
                    .foregroundStyle(CheckpointTheme.text)

                    Text("Checkpoint will prepare short practice sets for that goal and place them before the apps you want to use more intentionally.")
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
    private func currentGoalMenu(_ goal: Goal) -> some View {
        Menu {
            goalSwitcherMenuContent
        } label: {
            HStack(spacing: 6) {
                Text("Current goal")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.teal)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current goal: \(goal.title)")
    }

    @ViewBuilder
    private var goalSwitcherMenuContent: some View {
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

        if store.isMember && store.hasReachedGoalProfileLimit {
            Button {
                store.presentGoalProfileCreator()
            } label: {
                Label("\(store.goalProfileLimit) goal limit reached", systemImage: "checkmark.seal")
            }
            .disabled(true)
        } else {
            Button {
                store.presentGoalProfileCreator()
            } label: {
                Label("New goal", systemImage: "plus")
            }
        }
    }

    private func handleQuestionRefreshOnActivation() {
        let now = Date()
        if let lastActivationRefreshAt,
           now.timeIntervalSince(lastActivationRefreshAt) < Self.activationRefreshDebounceInterval {
            return
        }
        lastActivationRefreshAt = now

        Task {
            _ = await store.refreshQuestionBatchIfNeeded()
            await store.prepareProtectionReviewQuestionBankIfNeeded()
        }
    }

    private var isTemporarilyUnblocked: Bool {
        screenTime.setupState == .temporarilyUnlocked || store.activeUnlockMinutesRemaining > 0
    }
}

private struct HomeProtectionActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 10)
            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct InsightsView: View {
    let store: CheckpointStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    totalStatsPanel
                    currentGoalPanel
                    goalBreakdownPanel
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Insights")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly insights")
                .font(.largeTitle.bold())
                .foregroundStyle(CheckpointTheme.text)

            Text("Totals show your full week. Goal rows show where the practice went.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var totalStatsPanel: some View {
        SectionPanel("All goals") {
            let metrics = store.weeklyTotalMetrics

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(
                    title: "Questions answered",
                    value: "\(metrics.questionsAnswered)",
                    tint: CheckpointTheme.teal,
                    systemImage: "checkmark.seal"
                )

                MetricTile(
                    title: "Question accuracy",
                    value: metrics.accuracyText,
                    tint: CheckpointTheme.amber,
                    systemImage: "arrow.triangle.2.circlepath"
                )

                MetricTile(
                    title: "Skill progress",
                    value: metrics.skillProgressText,
                    tint: CheckpointTheme.blue,
                    systemImage: "chart.line.uptrend.xyaxis"
                )

                MetricTile(
                    title: "Break remaining",
                    value: "\(store.activeUnlockMinutesRemaining)m",
                    tint: CheckpointTheme.coral,
                    systemImage: "timer"
                )
            }
        }
    }

    @ViewBuilder
    private var currentGoalPanel: some View {
        if let metrics = store.weeklyActiveGoalMetrics {
            SectionPanel("Current goal") {
                GoalInsightRow(metrics: metrics)
            }
        }
    }

    private var goalBreakdownPanel: some View {
        SectionPanel("Goal breakdown") {
            let goalMetrics = store.weeklyGoalMetrics

            if goalMetrics.isEmpty {
                Text("Create a goal and complete a few checkpoints to see per-goal metrics.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(goalMetrics) { metrics in
                        GoalInsightRow(metrics: metrics)

                        if metrics.id != goalMetrics.last?.id {
                            Divider()
                                .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
    }
}

private struct GoalInsightRow: View {
    var metrics: WeeklyMetricsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metrics.title)
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(metrics.trackedSkillCount) tracked skills")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)
                }

                Spacer(minLength: 10)

                if metrics.isCurrentGoal {
                    StatusBadge(text: "Current", tint: CheckpointTheme.teal)
                }
            }

            HStack(spacing: 10) {
                MiniInsightStat(title: "Answered", value: "\(metrics.questionsAnswered)")
                MiniInsightStat(title: "Accuracy", value: metrics.accuracyText)
                MiniInsightStat(title: "Progress", value: metrics.skillProgressText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MiniInsightStat: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .monospacedDigit()

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CheckpointTheme.panelRaised.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }
}
