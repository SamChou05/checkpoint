import SwiftUI

enum HomeStudyBeaconPresentation: Equatable {
    case firstCheckpointLaunchpad
    case weeklySignal

    var showsNextFocus: Bool {
        self == .weeklySignal
    }

    init(
        hasPracticeForActiveGoal: Bool,
        hasReadyCheckpointSet: Bool,
        isProtectionActive: Bool
    ) {
        self = !hasPracticeForActiveGoal && hasReadyCheckpointSet && isProtectionActive
            ? .firstCheckpointLaunchpad
            : .weeklySignal
    }
}

struct HomeFirstCheckpointLaunchpad: View {
    var requiredCorrectAnswers: Int
    var questionCount: Int
    var unlockMinutes: Int
    var protectedAppsSummary: String
    var reviewApps: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT STEP")
                .font(.caption2.weight(.bold))
                .tracking(0.95)
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityHidden(true)

            CheckpointHeroSurface(glowColor: CheckpointTheme.mint) {
                VStack(alignment: .leading, spacing: 18) {
                    launchIdentity

                    Text(instructionText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(instructionText)

                    Divider()
                        .overlay(CheckpointTheme.heroDivider)

                    protectionControls
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var launchIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                launchIcon
                launchTitle
            }
        } else {
            HStack(alignment: .center, spacing: 13) {
                launchIcon
                launchTitle
            }
        }
    }

    private var launchIcon: some View {
        Image(systemName: "flag.checkered")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(CheckpointTheme.ink)
            .frame(width: 46, height: 46)
            .background(CheckpointTheme.mint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var launchTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("FIRST CHECKPOINT")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(CheckpointTheme.heroSuccess)

            Text("This goal’s first checkpoint is ready")
                .font(.title3.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next step. This goal’s first checkpoint is ready")
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var protectionControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                protectionIdentity
                reviewAppsButton
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    protectionIdentity
                    Spacer(minLength: 8)
                    reviewAppsButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    protectionIdentity
                    reviewAppsButton
                }
            }
        }
    }

    private var protectionIdentity: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CheckpointTheme.heroSuccess)
                .frame(width: 30, height: 30)
                .background(CheckpointTheme.heroSubtleFill, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Protection on")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.heroText)

                Text(protectedAppsSummary)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protection on. \(protectedAppsSummary)")
    }

    private var reviewAppsButton: some View {
        Button(action: reviewApps) {
            HStack(spacing: 6) {
                Text("Review apps")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.heroSuccess)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .accessibilityHint("Opens your protected app selection")
    }

    private var instructionText: String {
        let questionNoun = questionCount == 1 ? "question" : "questions"
        return "Open any protected app. Clear \(requiredCorrectAnswers) of \(questionCount) \(questionNoun) to earn a \(unlockMinutes)-minute break."
    }
}

struct LightStudyBeaconSection: View {
    var metrics: WeeklyMetricsSummary
    var competencies: [TopicCompetency]
    var insight: WeeklySignalInsight?
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
                            .overlay(CheckpointTheme.heroDivider)

                        insightRow(insight)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CheckpointTheme.ink)
                        .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
                        .overlay(alignment: .topTrailing) {
                            Circle()
                                .fill(signalAccent.opacity(0.08))
                                .frame(width: 140, height: 140)
                                .blur(radius: 10)
                                .offset(x: 60, y: -78)
                                .allowsHitTesting(false)
                        }
                )
                .shadow(color: CheckpointTheme.shadowElevated, radius: 16, y: 8)
            }
            .buttonStyle(CheckpointPressButtonStyle())
            .accessibilityLabel(weeklySignalAccessibilityLabel)
            .accessibilityHint("Opens weekly impact")
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var sectionHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 5) {
                sectionHeaderLabel
                viewImpactLabel
            }
        } else {
            HStack {
                sectionHeaderLabel
                Spacer()
                viewImpactLabel
            }
        }
    }

    private var sectionHeaderLabel: some View {
        Text("WEEKLY SIGNAL")
            .font(.caption2.weight(.bold))
            .tracking(0.95)
            .foregroundStyle(CheckpointTheme.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private var viewImpactLabel: some View {
        HStack(spacing: 5) {
            Text("View impact")
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(CheckpointTheme.teal)
        .accessibilityHidden(true)
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
                    .fill(CheckpointTheme.heroDivider)
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

    private func insightRow(_ insight: WeeklySignalInsight) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    insightIcon(insight)
                    insightText(insight)
                }
            } else {
                HStack(spacing: 10) {
                    insightIcon(insight)
                    insightText(insight)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(signalSecondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(insight.accessibilityLabel)
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: insight
        )
    }

    private func insightIcon(_ insight: WeeklySignalInsight) -> some View {
        Image(systemName: insightSystemImage(for: insight))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(insightTint(for: insight))
            .frame(width: 30, height: 30)
            .background(
                insightTint(for: insight).opacity(0.14),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .accessibilityHidden(true)
    }

    private func insightText(_ insight: WeeklySignalInsight) -> some View {
        Text(insight.text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(signalText)
            .multilineTextAlignment(.leading)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
    }

    private func insightSystemImage(for insight: WeeklySignalInsight) -> String {
        switch insight.role {
        case .lowestCurrentEstimate:
            "chart.bar.fill"
        case .highestCurrentEstimate:
            "waveform.path.ecg"
        case .checkpointsCleared:
            "shield.checkered"
        case .answersLogged:
            "point.3.connected.trianglepath.dotted"
        case .checkpointStreak:
            "bolt.fill"
        }
    }

    private func insightTint(for insight: WeeklySignalInsight) -> Color {
        switch insight.role {
        case .lowestCurrentEstimate:
            CheckpointTheme.heroWarning
        case .highestCurrentEstimate:
            CheckpointTheme.heroInfo
        case .checkpointsCleared, .answersLogged, .checkpointStreak:
            CheckpointTheme.heroSuccess
        }
    }

    private var emptySummary: some View {
        HStack(spacing: 13) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(signalAccent)
                .frame(width: 40, height: 40)
                .background(CheckpointTheme.heroSubtleFill, in: RoundedRectangle(cornerRadius: 12))
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
            return "Weekly signal for \(metrics.title). No checkpoint activity yet."
        }

        let questionNoun = metrics.questionsAnswered == 1 ? "question" : "questions"
        let breakNoun = metrics.checkpointsCleared == 1 ? "break" : "breaks"
        let questionSummary = metrics.questionsAnswered > 0
            ? "\(metrics.questionsAnswered) \(questionNoun), \(metrics.accuracyText) accuracy"
            : "No questions answered this week"
        let summary = "Weekly signal for \(metrics.title). \(questionSummary), \(metrics.checkpointsCleared) \(breakNoun) earned."
        guard let insight else { return summary }
        return "\(summary) \(insight.accessibilityLabel)."
    }

    private var signalText: Color { CheckpointTheme.heroText }
    private var signalSecondaryText: Color { CheckpointTheme.heroMuted }
    private var signalAccent: Color { CheckpointTheme.heroSuccess }
}
