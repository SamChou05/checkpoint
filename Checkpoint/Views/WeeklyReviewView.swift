import SwiftUI

struct WeeklyReviewView: View {
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

            Text("A quick look at this week's questions, breaks, and progress.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scopeSelector: some View {
        SectionPanel("Goal") {
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
        SectionPanel("This week") {
            let metrics = selectedMetrics

            VStack(spacing: 10) {
                WeeklySignalRow(
                    title: "Questions answered",
                    value: "\(metrics.questionsAnswered)",
                    detail: nil,
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
                    title: "App breaks",
                    value: "\(metrics.checkpointsCleared)",
                    detail: "Breaks earned by passing a checkpoint",
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
                            detail: "Your strongest topic this week",
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
            return "\(metrics.questionsAnswered) questions answered this week."
        }

        if metrics.checkpointStreakDays > 0 {
            return "\(metrics.checkpointStreakText) checkpoint streak is still alive."
        }

        return "No weekly review yet."
    }

    private func heroDetail(for metrics: WeeklyMetricsSummary) -> String {
        if metrics.checkpointsCleared > 0 {
            let checkpointText = metrics.checkpointsCleared == 1 ? "1 app break" : "\(metrics.checkpointsCleared) app breaks"
            return "You earned \(checkpointText) by passing a checkpoint."
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
