import SwiftUI

struct HomeView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController

    @Environment(\.scenePhase) private var scenePhase
    @State private var isRestrictedAppsPresented = false
    @State private var isWeeklyReviewPresented = false
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
                        weeklyReviewPanel
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
            .sheet(isPresented: $isWeeklyReviewPresented) {
                WeeklyReviewView(store: store)
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

    @ViewBuilder
    private var weeklyReviewPanel: some View {
        let weeklyMetrics = store.weeklyTotalMetrics

        if weeklyMetrics.hasWeeklyReviewActivity {
            SectionPanel("Weekly review") {
                VStack(alignment: .leading, spacing: 14) {
                    Text(homeWeeklyReviewHeadline(for: weeklyMetrics))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CheckpointTheme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        CompactReviewStat(
                            title: "Reps",
                            value: "\(weeklyMetrics.questionsAnswered)",
                            systemImage: "checkmark.seal",
                            tint: CheckpointTheme.teal
                        )

                        CompactReviewStat(
                            title: "Accuracy",
                            value: weeklyMetrics.accuracyText,
                            systemImage: "target",
                            tint: CheckpointTheme.amber
                        )

                        CompactReviewStat(
                            title: "Streak",
                            value: "\(weeklyMetrics.checkpointStreakDays)",
                            systemImage: "flame",
                            tint: CheckpointTheme.coral
                        )
                    }

                    SecondaryActionButton(title: "Open weekly review", systemImage: "chart.line.uptrend.xyaxis") {
                        isWeeklyReviewPresented = true
                    }
                }
            }
        }
    }

    private func homeWeeklyReviewHeadline(for metrics: WeeklyMetricsSummary) -> String {
        if metrics.questionsAnswered == 0, metrics.checkpointStreakDays > 0 {
            return "\(metrics.checkpointStreakText) checkpoint streak is still alive."
        }

        if metrics.checkpointStreakDays > 0 {
            return "\(metrics.questionsAnswered) reps toward your goals this week. \(metrics.checkpointStreakText) checkpoint streak."
        }

        return "\(metrics.questionsAnswered) reps toward your goals this week."
    }

    private var screenTimePanel: some View {
        SectionPanel("Protected apps") {
            VStack(alignment: .leading, spacing: 12) {
                Text(screenTime.restrictedAppsSummary)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if isTemporarilyUnblocked {
                    BreakRemainingStat(expiresAt: store.unlockSession?.expiresAt)

                    HStack(spacing: 10) {
                        HomeProtectionActionButton(title: "Choose apps", systemImage: "checklist") {
                            isRestrictedAppsPresented = true
                        }

                        HomeProtectionActionButton(title: "End break early", systemImage: "shield") {
                            store.clearUnlockSession()
                            screenTime.applyShield()
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        HomeProtectionActionButton(title: "Choose apps", systemImage: "checklist") {
                            isRestrictedAppsPresented = true
                        }

                        if screenTime.isShieldingEnabled {
                            StatusBadge(text: "Protection active", tint: CheckpointTheme.teal)
                        } else {
                            HomeProtectionActionButton(title: "Start protection", systemImage: "shield") {
                                screenTime.applyShield()
                            }
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

private struct BreakRemainingStat: View {
    var expiresAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.amber)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Break remaining")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)

                    Text("Protection restarts automatically when this ends.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(valueText(at: context.date))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(12)
            .background(CheckpointTheme.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func valueText(at date: Date) -> String {
        guard let expiresAt else { return "Ending" }

        let minutesRemaining = max(0, Int(ceil(expiresAt.timeIntervalSince(date) / 60)))
        guard minutesRemaining > 0 else { return "Ending" }
        return "\(minutesRemaining)m"
    }
}

private struct WeeklyReviewView: View {
    let store: CheckpointStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMetricsID = WeeklyMetricsSummary.allGoalsID

    private var metricOptions: [WeeklyMetricsSummary] {
        [store.weeklyTotalMetrics] + store.weeklyGoalMetrics
    }

    private var selectedMetrics: WeeklyMetricsSummary {
        metricOptions.first { $0.id == selectedMetricsID } ?? store.weeklyTotalMetrics
    }

    private var isAllGoalsSelected: Bool {
        selectedMetrics.id == WeeklyMetricsSummary.allGoalsID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if metricOptions.count > 2 {
                        scopeSelector
                    }
                    reviewHero
                    signalPanel
                    skillFocusPanel
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Weekly Review")
            .toolbarTitleDisplayMode(.inline)
            .onChange(of: metricOptions.map(\.id)) { _, availableIDs in
                if !availableIDs.contains(selectedMetricsID) {
                    selectedMetricsID = WeeklyMetricsSummary.allGoalsID
                }
            }
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
            Text("Weekly review")
                .font(.largeTitle.bold())
                .foregroundStyle(CheckpointTheme.text)

            Text("A short read on the practice your protected apps created this week.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scopeSelector: some View {
        SectionPanel("Scope") {
            Menu {
                Button {
                    selectedMetricsID = WeeklyMetricsSummary.allGoalsID
                } label: {
                    Label(
                        "All goals",
                        systemImage: selectedMetricsID == WeeklyMetricsSummary.allGoalsID ? "checkmark.circle.fill" : "circle"
                    )
                }

                if !store.weeklyGoalMetrics.isEmpty {
                    Divider()
                }

                ForEach(store.weeklyGoalMetrics) { metrics in
                    Button {
                        selectedMetricsID = metrics.id
                    } label: {
                        Label(
                            metrics.title,
                            systemImage: selectedMetricsID == metrics.id ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Viewing")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)

                        Text(selectedMetrics.title)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CheckpointTheme.teal)
                }
                .padding(14)
                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewHero: some View {
        SectionPanel {
            let metrics = selectedMetrics

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    StatusBadge(text: isAllGoalsSelected ? "All goals" : "Goal", tint: CheckpointTheme.teal)

                    if metrics.checkpointStreakDays > 0 {
                        StatusBadge(text: "\(metrics.checkpointStreakText) streak", tint: CheckpointTheme.coral)
                    }
                }

                Text(heroTitle(for: metrics))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(heroDetail(for: metrics))
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var signalPanel: some View {
        SectionPanel("Signals") {
            let metrics = selectedMetrics

            VStack(spacing: 10) {
                WeeklySignalRow(
                    title: "Learning reps",
                    value: "\(metrics.questionsAnswered)",
                    detail: "Questions answered this week",
                    systemImage: "checkmark.seal",
                    tint: CheckpointTheme.teal
                )

                WeeklySignalRow(
                    title: "Accuracy",
                    value: metrics.accuracyText,
                    detail: metrics.questionsAnswered > 0 ? "\(metrics.correctAnswers) correct, \(metrics.missedAnswers) to review" : "No answered questions yet",
                    systemImage: "target",
                    tint: CheckpointTheme.amber
                )

                WeeklySignalRow(
                    title: "Checkpoint streak",
                    value: metrics.checkpointStreakText,
                    detail: "Consecutive days with a cleared checkpoint",
                    systemImage: "flame",
                    tint: CheckpointTheme.coral
                )

                WeeklySignalRow(
                    title: "Protected-app moments",
                    value: "\(metrics.checkpointsCleared)",
                    detail: "Successful checkpoints before an app break",
                    systemImage: "shield.lefthalf.filled",
                    tint: CheckpointTheme.blue
                )
            }
        }
    }

    @ViewBuilder
    private var skillFocusPanel: some View {
        let metrics = selectedMetrics

        if metrics.strongestSkill != nil || metrics.reviewSkill != nil {
            SectionPanel("Skill focus") {
                VStack(spacing: 10) {
                    if let strongestSkill = metrics.strongestSkill {
                        WeeklySignalRow(
                            title: "Strengthening",
                            value: strongestSkill,
                            detail: "Your best-performing skill signal",
                            systemImage: "star",
                            tint: CheckpointTheme.blue
                        )
                    }

                    if let reviewSkill = metrics.reviewSkill {
                        WeeklySignalRow(
                            title: "Review next",
                            value: reviewSkill,
                            detail: "The next skill worth another pass",
                            systemImage: "bookmark",
                            tint: CheckpointTheme.amber
                        )
                    }
                }
            }
        }
    }

    private func heroTitle(for metrics: WeeklyMetricsSummary) -> String {
        if metrics.questionsAnswered > 0 {
            return "\(metrics.questionsAnswered) focused reps completed this week."
        }

        if metrics.checkpointStreakDays > 0 {
            return "\(metrics.checkpointStreakText) checkpoint streak is still alive."
        }

        return "No weekly review yet."
    }

    private func heroDetail(for metrics: WeeklyMetricsSummary) -> String {
        if metrics.checkpointsCleared > 0 {
            let checkpointText = metrics.checkpointsCleared == 1 ? "1 protected-app moment" : "\(metrics.checkpointsCleared) protected-app moments"
            return "\(checkpointText) became practice before a break."
        }

        if metrics.questionsAnswered > 0 {
            return "Keep protection active to connect more app opens with practice."
        }

        if metrics.checkpointStreakDays > 0 {
            return "Clear a checkpoint this week to keep the streak moving."
        }

        return "Clear a checkpoint this week and your review will begin to fill in."
    }
}

private struct WeeklySignalRow: View {
    var title: String
    var value: String
    var detail: String?
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let detail {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .padding(12)
        .background(CheckpointTheme.panelRaised.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CompactReviewStat: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)

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
        .padding(12)
        .background(CheckpointTheme.panelRaised.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }
}
