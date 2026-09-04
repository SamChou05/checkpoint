import Foundation
import SwiftUI

enum ProgressWeeklyImpactDayState: Equatable {
    case active
    case inactive
    case future
}

struct ProgressWeeklyImpactDayPresentation: Identifiable, Equatable {
    let id: Date
    let label: String
    let state: ProgressWeeklyImpactDayState
    let activityLevel: Double
}

struct ProgressWeeklyImpactPresentation: Equatable {
    let goalTitle: String
    let days: [ProgressWeeklyImpactDayPresentation]
    let summaryText: String
    let accessibilityValue: String
    let hasActivity: Bool

    init(
        metrics: WeeklyMetricsSummary,
        details: WeeklyImpactDetails,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) {
        goalTitle = metrics.title

        let dateLabelFormatter = WeeklyReviewDateLabelFormatter(
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let peakQuestionCount = details.practiceDays.lazy
            .filter { calendar.startOfDay(for: $0.date) <= referenceDay }
            .map(\.questionsAnswered)
            .max() ?? 0

        days = details.practiceDays.map { day in
            let normalizedDay = calendar.startOfDay(for: day.date)
            let state: ProgressWeeklyImpactDayState
            if normalizedDay > referenceDay {
                state = .future
            } else if day.hasActivity {
                state = .active
            } else {
                state = .inactive
            }
            let activityLevel: Double
            if state == .active, day.questionsAnswered > 0, peakQuestionCount > 0 {
                activityLevel = min(
                    1,
                    Double(day.questionsAnswered) / Double(peakQuestionCount)
                )
            } else if state == .active {
                activityLevel = 0.45
            } else {
                activityLevel = 0
            }
            return ProgressWeeklyImpactDayPresentation(
                id: day.id,
                label: dateLabelFormatter.narrowWeekday(for: day.date)
                    .uppercased(with: locale),
                state: state,
                activityLevel: activityLevel
            )
        }

        let activeDayCount = days.lazy.filter { $0.state == .active }.count
        hasActivity = activeDayCount > 0

        guard hasActivity else {
            summaryText = "Your next checkpoint will start this week’s timeline."
            accessibilityValue = "No checkpoint activity this week."
            return
        }

        let questionNoun = metrics.questionsAnswered == 1 ? "question" : "questions"
        let earnedBreakSummary = metrics.checkpointsCleared == 1
            ? "1 break earned"
            : "\(metrics.checkpointsCleared) breaks earned"
        if metrics.questionsAnswered > 0 {
            var summaryParts = ["\(metrics.questionsAnswered) \(questionNoun)"]
            summaryParts.append("\(metrics.accuracyText) correct")
            summaryParts.append(earnedBreakSummary)
            summaryText = summaryParts.joined(separator: " · ")
        } else {
            summaryText = "\(earnedBreakSummary) this week"
        }

        let dayNoun = activeDayCount == 1 ? "active day" : "active days"
        let accuracySummary = metrics.questionsAnswered > 0
            ? "\(metrics.accuracyText) correct"
            : "no accuracy yet"
        let aggregateAccessibilityValue = [
            "\(metrics.questionsAnswered) \(questionNoun)",
            accuracySummary,
            earnedBreakSummary,
            "across \(activeDayCount) \(dayNoun)."
        ].joined(separator: ", ")
        let activeDayDetails = zip(details.practiceDays, days).compactMap {
            day, presentation -> String? in
            guard presentation.state == .active else { return nil }
            let weekday = dateLabelFormatter.wideWeekday(for: day.date)
            if day.questionsAnswered > 0 {
                let noun = day.questionsAnswered == 1 ? "question" : "questions"
                return "\(weekday), \(day.questionsAnswered) \(noun)"
            }
            if day.checkpointsCleared > 0 {
                let breakSummary = day.checkpointsCleared == 1
                    ? "1 break earned"
                    : "\(day.checkpointsCleared) breaks earned"
                return "\(weekday), \(breakSummary)"
            }
            return "\(weekday), \(day.earnedBreakTimeText) earned"
        }
        accessibilityValue = "\(aggregateAccessibilityValue) Activity by day: "
            + activeDayDetails.joined(separator: "; ")
            + "."
    }
}

enum ProgressWeeklyImpactMotionStyle: Equatable {
    case animated
    case identity
}

struct ProgressWeeklyImpactMotionPolicy {
    let style: ProgressWeeklyImpactMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var animation: Animation? {
        style == .identity ? nil : CheckpointMotion.change
    }
}

struct ProgressWeeklyImpactRoutingPolicy {
    static func destinationGoalID(
        activeGoalID: Goal.ID?,
        hasReviewedSkillMap: Bool
    ) -> Goal.ID? {
        guard hasReviewedSkillMap else { return nil }
        return activeGoalID
    }
}

struct ProgressWeeklyImpactCard: View {
    let presentation: ProgressWeeklyImpactPresentation
    let reduceMotion: Bool
    let action: () -> Void

    private var motionPolicy: ProgressWeeklyImpactMotionPolicy {
        ProgressWeeklyImpactMotionPolicy(reduceMotion: reduceMotion)
    }

    var body: some View {
        Button(action: action) {
            SectionPanel {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    activityRail

                    Text(presentation.summaryText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .animation(motionPolicy.animation, value: presentation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly impact for \(presentation.goalTitle)")
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint("Opens this goal’s current week and weekly archive.")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THIS WEEK")
                    .font(.caption2.weight(.bold))
                    .tracking(0.85)
                    .foregroundStyle(CheckpointTheme.teal)

                Text("Weekly impact")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.teal)
                .accessibilityHidden(true)
        }
    }

    private var activityRail: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(presentation.days) { day in
                VStack(spacing: 4) {
                    Text(day.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(dayLabelColor(for: day.state))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Capsule()
                        .fill(dayMarkColor(for: day.state))
                        .frame(height: activityMarkHeight(for: day))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func activityMarkHeight(
        for day: ProgressWeeklyImpactDayPresentation
    ) -> CGFloat {
        guard day.state == .active else { return 4 }
        return 4 + (4 * CGFloat(day.activityLevel))
    }

    private func dayLabelColor(for state: ProgressWeeklyImpactDayState) -> Color {
        switch state {
        case .active:
            CheckpointTheme.text
        case .inactive:
            CheckpointTheme.muted
        case .future:
            CheckpointTheme.muted.opacity(0.52)
        }
    }

    private func dayMarkColor(for state: ProgressWeeklyImpactDayState) -> Color {
        switch state {
        case .active:
            CheckpointTheme.teal
        case .inactive:
            CheckpointTheme.controlStroke
        case .future:
            CheckpointTheme.controlStroke.opacity(0.45)
        }
    }
}
