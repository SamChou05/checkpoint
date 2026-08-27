import SwiftUI

struct WeeklyImpactInsight {
    var text: String
    var systemImage: String
    var tint: Color
}

private struct StudyBeaconStat: Identifiable {
    var id: String { label }
    var value: String
    var label: String
    var tint: Color
}

struct LightStudyBeaconSection: View {
    var metrics: WeeklyMetricsSummary
    var competencies: [TopicCompetency]
    var insight: WeeklyImpactInsight?
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 14) {
            HStack {
                Text("THIS WEEK")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(CheckpointTheme.muted)

                Spacer()

                if metrics.hasWeeklyReviewActivity {
                    Button(action: action) {
                        HStack(spacing: 5) {
                            Text("Review")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens weekly review")
                }
            }

            LightStudyBeacon(
                competencies: Array(competencies.prefix(6)),
                size: dynamicTypeSize.isAccessibilitySize ? 122 : 160
            )

            primaryMetric

            if !supportingStats.isEmpty {
                impactStats
            }

            if let insight {
                Button(action: action) {
                    HStack(spacing: 11) {
                        Image(systemName: insight.systemImage)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(insight.tint)
                            .frame(width: 36, height: 36)
                            .background(insight.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("WEEKLY INSIGHT")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.65)
                                .foregroundStyle(insight.tint)

                            Text(insight.text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .multilineTextAlignment(.leading)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CheckpointTheme.muted)
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .background(
                        CheckpointTheme.panelRaised.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens weekly review")
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var primaryMetric: some View {
        if let headline {
            VStack(spacing: 1) {
                Text(headline.value)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundStyle(CheckpointTheme.text)
                    .monospacedDigit()

                Text(headline.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.85)
                    .foregroundStyle(CheckpointTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 3) {
                Text("Ready")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(CheckpointTheme.text)

                Text("YOUR FIRST CHECKPOINT LIGHTS THE BEACON")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.75)
                    .foregroundStyle(CheckpointTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var impactStats: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(supportingStats) { stat in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(stat.value)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(stat.tint)
                            .monospacedDigit()

                        Text(stat.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(CheckpointTheme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 14) {
                ForEach(Array(supportingStats.enumerated()), id: \.element.id) { index, stat in
                    if index > 0 {
                        Rectangle()
                            .fill(CheckpointTheme.hairline)
                            .frame(width: 1, height: 38)
                            .accessibilityHidden(true)
                    }

                    VStack(spacing: 2) {
                        Text(stat.value)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(stat.tint)
                            .monospacedDigit()

                        Text(stat.label.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.45)
                            .foregroundStyle(CheckpointTheme.muted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var headline: (value: String, label: String)? {
        if metrics.questionsAnswered > 0 {
            return (
                "\(metrics.questionsAnswered)",
                metrics.questionsAnswered == 1 ? "question this week" : "questions this week"
            )
        }

        if metrics.checkpointsCleared > 0 {
            return (
                "\(metrics.checkpointsCleared)",
                metrics.checkpointsCleared == 1 ? "checkpoint this week" : "checkpoints this week"
            )
        }

        if metrics.checkpointStreakDays > 0 {
            return (metrics.checkpointStreakText, "checkpoint streak")
        }

        return nil
    }

    private var supportingStats: [StudyBeaconStat] {
        var stats: [StudyBeaconStat] = []

        if metrics.questionsAnswered > 0 {
            stats.append(
                StudyBeaconStat(
                    value: metrics.questionsAnswered >= 5
                        ? metrics.accuracyText
                        : "\(metrics.correctAnswers) of \(metrics.questionsAnswered)",
                    label: "correct",
                    tint: CheckpointTheme.teal
                )
            )
        }

        if metrics.checkpointsCleared > 0 {
            stats.append(
                StudyBeaconStat(
                    value: "\(metrics.checkpointsCleared)",
                    label: metrics.checkpointsCleared == 1 ? "checkpoint" : "checkpoints",
                    tint: CheckpointTheme.blue
                )
            )
        }

        if metrics.checkpointStreakDays > 0 {
            stats.append(
                StudyBeaconStat(
                    value: "\(metrics.checkpointStreakDays)-day",
                    label: "streak",
                    tint: CheckpointTheme.coral
                )
            )
        }

        return Array(stats.prefix(3))
    }
}

private struct LightStudyBeacon: View {
    var competencies: [TopicCompetency]
    var size: CGFloat

    private let petalColors: [Color] = [
        Color(red: 0.20, green: 0.62, blue: 0.56),
        Color(red: 0.31, green: 0.49, blue: 0.73),
        Color(red: 0.88, green: 0.61, blue: 0.31),
        Color(red: 0.76, green: 0.37, blue: 0.34),
        Color(red: 0.40, green: 0.55, blue: 0.78),
        Color(red: 0.24, green: 0.66, blue: 0.60)
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CheckpointTheme.teal.opacity(0.13),
                            CheckpointTheme.blue.opacity(0.06),
                            .clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: size * 0.63
                    )
                )
                .frame(width: size * 1.18, height: size * 1.18)
                .blur(radius: 9)

            Circle()
                .stroke(CheckpointTheme.amber.opacity(0.18), lineWidth: 1)
                .frame(width: size * 0.94, height: size * 0.94)

            ForEach(0..<6, id: \.self) { index in
                beaconPetal(at: index)
            }

            Circle()
                .stroke(
                    CheckpointTheme.teal.opacity(0.14),
                    style: StrokeStyle(lineWidth: 1, dash: [1, 7])
                )
                .frame(width: size * 0.82, height: size * 0.82)

            Circle()
                .fill(CheckpointTheme.panel)
                .frame(width: size * 0.39, height: size * 0.39)
                .overlay(Circle().stroke(CheckpointTheme.teal.opacity(0.12), lineWidth: 1))
                .shadow(color: CheckpointTheme.teal.opacity(0.10), radius: 10, y: 6)

            Image(systemName: "scope")
                .font(.system(size: size * 0.16, weight: .medium))
                .foregroundStyle(CheckpointTheme.teal)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func beaconPetal(at index: Int) -> some View {
        let competency = competencies.indices.contains(index) ? competencies[index] : nil
        let opacity: Double

        if let competency {
            opacity = competency.attempts == 0
                ? 0.20
                : 0.42 + (Double(competency.masteryPercent) / 100 * 0.34)
        } else {
            opacity = 0.10
        }

        return Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        petalColors[index].opacity(opacity),
                        petalColors[index].opacity(opacity * 0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size * 0.18, height: size * 0.48)
            .offset(y: -size * 0.19)
            .rotationEffect(.degrees(Double(index) * 60))
            .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        guard !competencies.isEmpty else {
            return "Learning beacon. Skill map is being prepared."
        }

        let practiced = competencies.filter { $0.attempts > 0 }
        guard let strongest = practiced.max(by: { $0.masteryPercent < $1.masteryPercent }),
              let review = practiced.min(by: { $0.masteryPercent < $1.masteryPercent }) else {
            return "Learning beacon. \(competencies.count) skill areas ready for practice."
        }

        return "Learning beacon. \(competencies.count) skill areas. Strongest: \(strongest.topic). Review next: \(review.topic)."
    }
}
