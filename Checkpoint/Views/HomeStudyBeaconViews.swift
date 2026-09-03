import SwiftUI

struct WeeklyImpactInsight {
    var text: String
    var systemImage: String
    var tint: Color
}

struct LightStudyBeaconSection: View {
    var metrics: WeeklyMetricsSummary
    var competencies: [TopicCompetency]
    var insight: WeeklyImpactInsight?
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var primaryMetricSize: CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            Button(action: action) {
                VStack(alignment: .leading, spacing: 16) {
                    if metrics.hasWeeklyReviewActivity {
                        activitySummary
                    } else {
                        emptySummary
                    }

                    if let insight {
                        Divider()
                            .overlay(Color.white.opacity(0.10))

                        insightRow(insight)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CheckpointTheme.ink)
                        .overlay(alignment: .topTrailing) {
                            Circle()
                                .fill(signalAccent.opacity(0.08))
                                .frame(width: 140, height: 140)
                                .blur(radius: 10)
                                .offset(x: 60, y: -78)
                                .allowsHitTesting(false)
                        }
                )
                .shadow(color: CheckpointTheme.ink.opacity(0.12), radius: 16, y: 8)
            }
            .buttonStyle(CheckpointPressButtonStyle())
            .accessibilityLabel(weeklySignalAccessibilityLabel)
            .accessibilityHint("Opens weekly impact")
        }
        .padding(.horizontal, 4)
    }

    private var sectionHeader: some View {
        HStack {
            Text("WEEKLY SIGNAL")
                .font(.caption2.weight(.bold))
                .tracking(0.95)
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            HStack(spacing: 5) {
                Text("View impact")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var activitySummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 18) {
                primaryMetric
                supportingMetrics
            }
        } else {
            HStack(alignment: .center, spacing: 18) {
                primaryMetric

                Rectangle()
                    .fill(Color.white.opacity(0.11))
                    .frame(width: 1, height: 70)
                    .accessibilityHidden(true)

                supportingMetrics
            }
        }
    }

    private var primaryMetric: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(metrics.questionsAnswered)")
                .font(.system(size: primaryMetricSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(signalText)
                .contentTransition(.numericText(value: Double(metrics.questionsAnswered)))
                .animation(
                    CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                    value: metrics.questionsAnswered
                )

            Text(metrics.questionsAnswered == 1 ? "QUESTION" : "QUESTIONS")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(signalSecondaryText)

            if practicedSkillCount > 0 {
                Text("\(practicedSkillCount) \(practicedSkillCount == 1 ? "skill" : "skills") tracked")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(signalSecondaryText)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var supportingMetrics: some View {
        VStack(alignment: .leading, spacing: 13) {
            compactMetric(
                value: metrics.questionsAnswered > 0 ? metrics.accuracyText : "—",
                label: "ACCURACY"
            )

            compactMetric(
                value: "\(metrics.checkpointsCleared)",
                label: metrics.checkpointsCleared == 1 ? "BREAK EARNED" : "BREAKS EARNED"
            )

            if metrics.checkpointStreakDays > 1 {
                compactMetric(
                    value: "\(metrics.checkpointStreakDays)d",
                    label: "CONSISTENCY"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMetric(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(signalAccent)

            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(0.55)
                .foregroundStyle(signalSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private func insightRow(_ insight: WeeklyImpactInsight) -> some View {
        HStack(spacing: 10) {
            Image(systemName: insight.systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(insight.tint)
                .frame(width: 30, height: 30)
                .background(insight.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            Text(insight.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(signalText)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(signalSecondaryText)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptySummary: some View {
        HStack(spacing: 13) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(signalAccent)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Signal ready")
                    .font(.headline)
                    .foregroundStyle(signalText)

                Text("Your first checkpoint will start this week's impact view.")
                    .font(.subheadline)
                    .foregroundStyle(signalSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var practicedSkillCount: Int {
        competencies.filter { $0.attempts > 0 }.count
    }

    private var weeklySignalAccessibilityLabel: String {
        guard metrics.hasWeeklyReviewActivity else {
            return "Weekly signal. No checkpoint activity yet."
        }

        let questionNoun = metrics.questionsAnswered == 1 ? "question" : "questions"
        let breakNoun = metrics.checkpointsCleared == 1 ? "break" : "breaks"
        let summary = "Weekly signal. \(metrics.questionsAnswered) \(questionNoun), \(metrics.accuracyText) accuracy, \(metrics.checkpointsCleared) \(breakNoun) earned."
        guard let insight else { return summary }
        return "\(summary) \(insight.text)"
    }

    private var signalText: Color { Color(red: 0.94, green: 0.98, blue: 0.96) }
    private var signalSecondaryText: Color { Color(red: 0.66, green: 0.75, blue: 0.71) }
    private var signalAccent: Color { CheckpointTheme.mint }
}
