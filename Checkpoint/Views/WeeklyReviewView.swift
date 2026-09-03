import SwiftUI

struct WeeklyReviewView: View {
    let store: CheckpointStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedMetricsID = WeeklyMetricsSummary.allGoalsID
    @ScaledMetric(relativeTo: .largeTitle) private var heroMetricSize: CGFloat = 64

    init(
        store: CheckpointStore,
        initialMetricsID: String = WeeklyMetricsSummary.allGoalsID
    ) {
        self.store = store
        _selectedMetricsID = State(initialValue: initialMetricsID)
    }

    private var metricOptions: [WeeklyMetricsSummary] {
        [store.weeklyTotalMetrics] + store.weeklyGoalMetrics
    }

    private var selectedMetrics: WeeklyMetricsSummary {
        metricOptions.first { $0.id == selectedMetricsID } ?? store.weeklyTotalMetrics
    }

    private var selectedGoalID: Goal.ID? {
        guard selectedMetrics.id != WeeklyMetricsSummary.allGoalsID else { return nil }
        return UUID(uuidString: selectedMetrics.id)
    }

    private var impactDetails: WeeklyImpactDetails {
        WeeklyMetricsCalculator(
            attempts: store.attempts,
            unlockEvents: store.unlockEvents,
            competencies: store.competencies
        ).impactDetails(goalID: selectedGoalID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    reviewHeader
                    impactHero

                    if selectedMetrics.hasWeeklyReviewActivity {
                        signalGrid
                        learningFocus
                    } else {
                        emptyGuidance
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .checkpointScreenBackground()
            .navigationTitle("Weekly impact")
            .toolbarTitleDisplayMode(.inline)
            .onChange(of: metricOptions.map(\.id)) { _, availableIDs in
                if !availableIDs.contains(selectedMetricsID) {
                    selectedMetricsID = WeeklyMetricsSummary.allGoalsID
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CheckpointTheme.teal)
                }
            }
        }
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR WEEK")
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(CheckpointTheme.muted)

                    Text(weekRangeText)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(CheckpointTheme.text)
                }

                Spacer(minLength: 8)

                if metricOptions.count > 2 {
                    goalMenu
                } else if selectedMetrics.id != WeeklyMetricsSummary.allGoalsID {
                    Text(selectedMetrics.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)
                        .lineLimit(1)
                }
            }

            Text("A quiet read on what your checkpoints turned into.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var goalMenu: some View {
        Menu {
            Button {
                selectedMetricsID = WeeklyMetricsSummary.allGoalsID
            } label: {
                Label(
                    "All goals",
                    systemImage: selectedMetricsID == WeeklyMetricsSummary.allGoalsID
                        ? "checkmark.circle.fill"
                        : "circle"
                )
            }

            Divider()

            ForEach(store.weeklyGoalMetrics) { metrics in
                Button {
                    selectedMetricsID = metrics.id
                } label: {
                    Label(
                        metrics.title,
                        systemImage: selectedMetricsID == metrics.id
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedMetrics.title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Viewing \(selectedMetrics.title)")
    }

    private var impactHero: some View {
        VStack(alignment: .leading, spacing: 22) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    learningOutputMetric
                    streakBadge
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    learningOutputMetric
                    Spacer(minLength: 0)
                    streakBadge
                }
            }

            if let trend = impactDetails.questionTrendText(
                currentQuestions: selectedMetrics.questionsAnswered
            ) {
                Text(trend)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(heroSecondaryText)
            }

            WeeklyPracticeBars(days: impactDetails.practiceDays)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CheckpointTheme.ink)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(heroAccent.opacity(0.09))
                        .frame(width: 180, height: 180)
                        .blur(radius: 12)
                        .offset(x: 78, y: -94)
                        .allowsHitTesting(false)
                }
        )
        .shadow(color: CheckpointTheme.ink.opacity(0.14), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
    }

    private var learningOutputMetric: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("LEARNING OUTPUT")
                .font(.caption2.weight(.bold))
                .tracking(1.05)
                .foregroundStyle(heroSecondaryText)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    learningOutputValue
                    learningOutputNoun
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    learningOutputValue
                    learningOutputNoun
                }
            }
        }
    }

    private var learningOutputValue: some View {
        Text("\(selectedMetrics.questionsAnswered)")
            .font(.system(size: heroMetricSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(heroText)
            .contentTransition(.numericText(value: Double(selectedMetrics.questionsAnswered)))
            .animation(
                CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                value: selectedMetrics.questionsAnswered
            )
    }

    private var learningOutputNoun: some View {
        Text(selectedMetrics.questionsAnswered == 1 ? "question" : "questions")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(heroSecondaryText)
    }

    @ViewBuilder
    private var streakBadge: some View {
        if selectedMetrics.checkpointStreakDays > 0 {
            Label("\(selectedMetrics.checkpointStreakDays)d", systemImage: "bolt.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(heroAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(heroAccent.opacity(0.11), in: Capsule())
                .accessibilityLabel("\(selectedMetrics.checkpointStreakText) checkpoint streak")
        }
    }

    private var signalGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("SIGNALS")

            LazyVGrid(
                columns: signalGridColumns,
                spacing: 10
            ) {
                ImpactMetricTile(
                    label: "Accuracy",
                    value: selectedMetrics.accuracyText,
                    detail: "\(selectedMetrics.correctAnswers) of \(selectedMetrics.questionsAnswered) correct",
                    systemImage: "scope"
                )

                ImpactMetricTile(
                    label: "Breaks earned",
                    value: "\(selectedMetrics.checkpointsCleared)",
                    detail: "\(impactDetails.earnedBreakTimeText) unlocked",
                    systemImage: "lock.open"
                )

                ImpactMetricTile(
                    label: "Misses recovered",
                    value: "\(impactDetails.recoveredQuestions)",
                    detail: "Previously missed, currently correct",
                    systemImage: "arrow.triangle.2.circlepath"
                )

                ImpactMetricTile(
                    label: "Active days",
                    value: "\(impactDetails.activePracticeDays) / 7",
                    detail: "Days with goal practice",
                    systemImage: "calendar"
                )
            }
        }
    }

    @ViewBuilder
    private var learningFocus: some View {
        if selectedMetrics.reviewSkill != nil || selectedMetrics.strongestSkill != nil {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("NEXT SIGNAL")

                VStack(spacing: 0) {
                    if let reviewSkill = selectedMetrics.reviewSkill {
                        FocusSignalRow(
                            eyebrow: "REVIEW NEXT",
                            title: reviewSkill,
                            systemImage: "arrow.up.right",
                            tint: CheckpointTheme.amber
                        )
                    }

                    if selectedMetrics.reviewSkill != nil,
                       selectedMetrics.strongestSkill != nil {
                        Divider()
                            .overlay(CheckpointTheme.hairline)
                            .padding(.leading, 52)
                    }

                    if let strongestSkill = selectedMetrics.strongestSkill {
                        FocusSignalRow(
                            eyebrow: "BUILDING",
                            title: strongestSkill,
                            systemImage: "waveform.path.ecg",
                            tint: CheckpointTheme.blue
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CheckpointTheme.panel.opacity(0.88))
                        .stroke(CheckpointTheme.hairline, lineWidth: 1)
                )
            }
        }
    }

    private var emptyGuidance: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 38, height: 38)
                .background(CheckpointTheme.teal.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Your signal starts with one checkpoint")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)

                Text("Questions, recovered misses, and earned breaks will collect here without any extra setup.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.95)
            .foregroundStyle(CheckpointTheme.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private var weekRangeText: String {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()),
              let finalDay = Calendar.current.date(byAdding: .day, value: -1, to: week.end) else {
            return "This week"
        }

        if Calendar.current.component(.month, from: week.start) == Calendar.current.component(.month, from: finalDay) {
            return "\(week.start.formatted(.dateTime.month(.abbreviated).day()))–\(finalDay.formatted(.dateTime.day()))"
        }
        return "\(week.start.formatted(.dateTime.month(.abbreviated).day()))–\(finalDay.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var signalGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 142), spacing: 10)]
    }

    private var heroText: Color { Color(red: 0.94, green: 0.98, blue: 0.96) }
    private var heroSecondaryText: Color { Color(red: 0.66, green: 0.75, blue: 0.71) }
    private var heroAccent: Color { CheckpointTheme.mint }
}

private struct WeeklyPracticeBars: View {
    var days: [WeeklyPracticeDay]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maximumCount: Int {
        max(1, days.map(\.questionsAnswered).max() ?? 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                VStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barColor(for: day))
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 4,
                            maxHeight: barHeight(for: day)
                        )
                        .animation(
                            CheckpointMotion.animation(CheckpointMotion.reveal, reduceMotion: reduceMotion),
                            value: day.questionsAnswered
                        )

                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(labelColor(for: day))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: day))
            }
        }
        .frame(height: 74, alignment: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Questions answered by day")
    }

    private func barHeight(for day: WeeklyPracticeDay) -> CGFloat {
        guard day.questionsAnswered > 0 else { return 4 }
        return 12 + (42 * CGFloat(day.questionsAnswered) / CGFloat(maximumCount))
    }

    private func barColor(for day: WeeklyPracticeDay) -> Color {
        if day.questionsAnswered > 0 {
            return CheckpointTheme.mint
        }
        return Color.white.opacity(day.date > Date() ? 0.07 : 0.14)
    }

    private func labelColor(for day: WeeklyPracticeDay) -> Color {
        Color.white.opacity(day.date > Date() ? 0.50 : 0.62)
    }

    private func accessibilityLabel(for day: WeeklyPracticeDay) -> String {
        let weekday = day.date.formatted(.dateTime.weekday(.wide))
        if day.date > Date() {
            return "\(weekday), not yet"
        }

        let noun = day.questionsAnswered == 1 ? "question" : "questions"
        return "\(weekday), \(day.questionsAnswered) \(noun)"
    }
}

private struct ImpactMetricTile: View {
    var label: String
    var value: String
    var detail: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.65)
                    .foregroundStyle(CheckpointTheme.muted)

                Spacer(minLength: 6)

                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .accessibilityHidden(true)
            }

            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .monospacedDigit()

            Text(detail)
                .font(.caption)
                .foregroundStyle(CheckpointTheme.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CheckpointTheme.panel.opacity(0.88))
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct FocusSignalRow: View {
    var eyebrow: String
    var title: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(0.65)
                    .foregroundStyle(CheckpointTheme.muted)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}
