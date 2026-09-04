import Accessibility
import SwiftUI

struct WeeklyReviewScopeInteractionPolicy {
    static func reportsSelectionFeedback(
        selectedMetricsID: String,
        currentMetricsID: String
    ) -> Bool {
        selectedMetricsID != currentMetricsID
    }
}

struct WeeklyReviewDateLabelFormatter {
    private let narrowWeekdayFormatter: DateFormatter
    private let wideWeekdayFormatter: DateFormatter

    init(
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) {
        let narrowWeekdayFormatter = DateFormatter()
        narrowWeekdayFormatter.calendar = calendar
        narrowWeekdayFormatter.locale = locale
        narrowWeekdayFormatter.timeZone = timeZone
        narrowWeekdayFormatter.setLocalizedDateFormatFromTemplate("EEEEE")
        self.narrowWeekdayFormatter = narrowWeekdayFormatter

        let wideWeekdayFormatter = DateFormatter()
        wideWeekdayFormatter.calendar = calendar
        wideWeekdayFormatter.locale = locale
        wideWeekdayFormatter.timeZone = timeZone
        wideWeekdayFormatter.setLocalizedDateFormatFromTemplate("EEEE")
        self.wideWeekdayFormatter = wideWeekdayFormatter
    }

    func narrowWeekday(for date: Date) -> String {
        narrowWeekdayFormatter.string(from: date)
    }

    func wideWeekday(for date: Date) -> String {
        wideWeekdayFormatter.string(from: date)
    }
}

struct WeeklyGoalPulseItem: Identifiable, Equatable {
    let id: Goal.ID
    let metricsID: String
    let title: String
    let isCurrentGoal: Bool
    let questionsAnswered: Int
    let accuracyText: String?
    let checkpointStreakDays: Int
    let checkpointsCleared: Int
    let activePracticeDays: Int
    let earnedBreakTimeText: String
    let questionShare: Double
    let hasActivity: Bool

    var activityText: String {
        if questionsAnswered > 0 {
            let noun = questionsAnswered == 1 ? "question" : "questions"
            return "\(questionsAnswered) \(noun) · \(accuracyText ?? "—") correct"
        }
        if checkpointsCleared > 0 {
            let noun = checkpointsCleared == 1 ? "break" : "breaks"
            return "\(checkpointsCleared) \(noun) earned this week"
        }
        if checkpointStreakDays > 0 {
            let day = checkpointStreakDays == 1 ? "day" : "days"
            return "\(checkpointStreakDays) \(day) in your checkpoint streak"
        }
        return "No checkpoint activity this week"
    }

    var supportingText: String {
        guard hasActivity else { return "Ready for your next checkpoint" }

        var details: [String] = []
        if questionsAnswered > 0 {
            let noun = activePracticeDays == 1 ? "active day" : "active days"
            details.append("\(activePracticeDays) \(noun)")
        }
        if checkpointsCleared > 0 {
            details.append("\(earnedBreakTimeText) unlocked")
        }
        if details.isEmpty, checkpointStreakDays > 0 {
            details.append("Streak still active")
        }
        return details.joined(separator: " · ")
    }

    var accessibilityLabel: String {
        [
            title,
            isCurrentGoal ? "current goal" : nil,
            activityText,
            supportingText
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

@MainActor
struct WeeklyGoalPulsePresentation: Equatable {
    let items: [WeeklyGoalPulseItem]

    init(
        goals: [Goal],
        metrics: [WeeklyMetricsSummary],
        attempts: [CheckpointAttempt],
        unlockEvents: [UnlockEvent],
        activeGoalID: Goal.ID?,
        asOf: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let metricsByID = Dictionary(
            metrics.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let resolver = GoalDisplayTitleResolver(
            goals: goals,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let calculator = WeeklyMetricsCalculator(
            attempts: attempts,
            unlockEvents: unlockEvents,
            asOf: asOf,
            calendar: calendar
        )
        let totalQuestions = metrics.reduce(0) { $0 + $1.questionsAnswered }

        let indexedItems: [(index: Int, item: WeeklyGoalPulseItem)] = goals.enumerated().compactMap { pair in
            let (index, goal) = pair
            guard let metric = metricsByID[goal.id.uuidString] else { return nil }
            let details = calculator.impactDetails(goalID: goal.id)
            let share = totalQuestions > 0
                ? Double(metric.questionsAnswered) / Double(totalQuestions)
                : 0
            let item = WeeklyGoalPulseItem(
                id: goal.id,
                metricsID: metric.id,
                title: resolver.title(for: goal),
                isCurrentGoal: goal.id == activeGoalID,
                questionsAnswered: metric.questionsAnswered,
                accuracyText: metric.questionsAnswered > 0 ? metric.accuracyText : nil,
                checkpointStreakDays: metric.checkpointStreakDays,
                checkpointsCleared: metric.checkpointsCleared,
                activePracticeDays: details.activePracticeDays,
                earnedBreakTimeText: details.earnedBreakTimeText,
                questionShare: share,
                hasActivity: metric.hasWeeklyReviewActivity
            )
            return (index: index, item: item)
        }

        items = indexedItems
        .sorted { lhs, rhs in
            if lhs.item.isCurrentGoal != rhs.item.isCurrentGoal {
                return lhs.item.isCurrentGoal
            }
            if lhs.item.hasActivity != rhs.item.hasActivity {
                return lhs.item.hasActivity
            }
            return lhs.index < rhs.index
        }
        .map(\.item)
    }
}

struct WeeklyReviewView: View {
    let store: CheckpointStore
    private let referenceDate: Date
    private let displayCalendar: Calendar
    private let displayLocale: Locale
    private let displayTimeZone: TimeZone
    private let reduceMotionOverride: Bool?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selectedMetricsID = WeeklyMetricsSummary.allGoalsID
    @State private var scopeSelectionFeedbackSequence = 0
    @ScaledMetric(relativeTo: .largeTitle) private var heroMetricSize: CGFloat = 64

    init(
        store: CheckpointStore,
        initialMetricsID: String = WeeklyMetricsSummary.allGoalsID,
        referenceDate: Date = Date(),
        displayCalendar: Calendar = .current,
        displayLocale: Locale = .current,
        displayTimeZone: TimeZone = .current,
        reduceMotionOverride: Bool? = nil
    ) {
        self.store = store
        self.referenceDate = referenceDate
        self.displayCalendar = displayCalendar
        self.displayLocale = displayLocale
        self.displayTimeZone = displayTimeZone
        self.reduceMotionOverride = reduceMotionOverride
        _selectedMetricsID = State(initialValue: initialMetricsID)
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var totalMetrics: WeeklyMetricsSummary {
        store.weeklyTotalMetrics(asOf: referenceDate, calendar: displayCalendar)
    }

    private var goalMetrics: [WeeklyMetricsSummary] {
        let resolver = GoalDisplayTitleResolver(
            goals: store.availableGoalProfiles,
            calendar: displayCalendar,
            locale: displayLocale,
            timeZone: displayTimeZone
        )

        return store.weeklyGoalMetrics(
            asOf: referenceDate,
            calendar: displayCalendar
        ).map { metrics in
            guard let goalID = UUID(uuidString: metrics.id),
                  let goal = store.availableGoalProfiles.first(where: { $0.id == goalID }) else {
                return metrics
            }
            var resolved = metrics
            resolved.title = resolver.title(for: goal)
            return resolved
        }
    }

    private var metricOptions: [WeeklyMetricsSummary] {
        [totalMetrics] + goalMetrics
    }

    private var selectedMetrics: WeeklyMetricsSummary {
        metricOptions.first { $0.id == selectedMetricsID } ?? totalMetrics
    }

    private var selectedGoalID: Goal.ID? {
        guard selectedMetrics.id != WeeklyMetricsSummary.allGoalsID else { return nil }
        return UUID(uuidString: selectedMetrics.id)
    }

    private var impactDetails: WeeklyImpactDetails {
        WeeklyMetricsCalculator(
            attempts: store.attempts,
            unlockEvents: store.unlockEvents,
            asOf: referenceDate,
            calendar: displayCalendar
        ).impactDetails(goalID: selectedGoalID)
    }

    private var goalPulsePresentation: WeeklyGoalPulsePresentation {
        WeeklyGoalPulsePresentation(
            goals: store.availableGoalProfiles,
            metrics: goalMetrics,
            attempts: store.attempts,
            unlockEvents: store.unlockEvents,
            activeGoalID: store.goal?.id,
            asOf: referenceDate,
            calendar: displayCalendar,
            locale: displayLocale,
            timeZone: displayTimeZone
        )
    }

    var body: some View {
        let pulsePresentation: WeeklyGoalPulsePresentation? =
            selectedMetrics.id == WeeklyMetricsSummary.allGoalsID
            ? goalPulsePresentation
            : nil
        let displaysGoalPulse = (pulsePresentation?.items.count ?? 0) > 1

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    reviewHeader
                    impactHero
                        .id("impact-\(selectedMetrics.id)")
                        .transition(scopeChangeTransition)

                    if selectedMetrics.hasWeeklyReviewActivity {
                        if let pulsePresentation, displaysGoalPulse {
                            goalPulse(pulsePresentation)
                                .transition(scopeChangeTransition)
                        }
                        signalGrid
                            .id("signals-\(selectedMetricsID)")
                            .transition(scopeChangeTransition)
                        if !displaysGoalPulse {
                            skillSnapshot
                        }
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
        .sensoryFeedback(.selection, trigger: scopeSelectionFeedbackSequence)
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    weekIdentity
                    selectedScope
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    weekIdentity

                    Spacer(minLength: 8)

                    selectedScope
                }
            }

            if selectedMetrics.id != WeeklyMetricsSummary.allGoalsID,
               metricOptions.count > 2 {
                Text(selectedMetrics.title)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
            }

            Text("A quiet read on what your checkpoints turned into.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var weekIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR WEEK")
                .font(.caption2.weight(.bold))
                .tracking(1.0)
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityAddTraits(.isHeader)

            Text(weekRangeText)
                .font(.title2.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var selectedScope: some View {
        if metricOptions.count > 2 {
            goalMenu
        } else if selectedMetrics.id != WeeklyMetricsSummary.allGoalsID {
            Text(selectedMetrics.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(scopeChangeAnimation, value: selectedMetricsID)
                .accessibilityLabel("Weekly impact for \(selectedMetrics.title)")
        }
    }

    private var goalMenu: some View {
        Menu {
            Button {
                selectMetrics(WeeklyMetricsSummary.allGoalsID)
            } label: {
                Label(
                    "All goals",
                    systemImage: selectedMetricsID == WeeklyMetricsSummary.allGoalsID
                        ? "checkmark.circle.fill"
                        : "circle"
                )
            }

            Divider()

            ForEach(goalMetrics) { metrics in
                Button {
                    selectMetrics(metrics.id)
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
            .background {
                if dynamicTypeSize.isAccessibilitySize {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CheckpointTheme.teal.opacity(0.10))
                } else {
                    Capsule()
                        .fill(CheckpointTheme.teal.opacity(0.10))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(scopeChangeAnimation, value: selectedMetricsID)
        .accessibilityLabel("Weekly impact scope")
        .accessibilityValue(selectedMetrics.title)
        .accessibilityHint("Choose which goal's weekly impact to view.")
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

            WeeklyPracticeBars(
                days: impactDetails.practiceDays,
                referenceDate: referenceDate,
                reduceMotion: reduceMotion,
                dateLabelFormatter: WeeklyReviewDateLabelFormatter(
                    calendar: displayCalendar,
                    locale: displayLocale,
                    timeZone: displayTimeZone
                )
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CheckpointTheme.ink)
                .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(heroAccent.opacity(0.09))
                        .frame(width: 180, height: 180)
                        .blur(radius: 12)
                        .offset(x: 78, y: -94)
                        .allowsHitTesting(false)
                }
        )
        .shadow(color: CheckpointTheme.shadowElevated, radius: 18, y: 10)
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

    private func goalPulse(
        _ presentation: WeeklyGoalPulsePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("GOAL PULSE")

            Text("Bars compare each goal's share of this week's questions. Choose one to inspect its own signals.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(
                    Array(presentation.items.enumerated()),
                    id: \.element.id
                ) { index, item in
                    Button {
                        selectMetrics(item.metricsID)
                    } label: {
                        WeeklyGoalPulseRow(
                            item: item,
                            tint: goalPulseTint(at: index),
                            revealDelay: Double(index) * 0.045,
                            reduceMotion: reduceMotion
                        )
                    }
                    .buttonStyle(CheckpointPressButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.accessibilityLabel)
                    .accessibilityHint("Shows this goal's weekly impact.")

                    if index < presentation.items.count - 1 {
                        Divider()
                            .overlay(CheckpointTheme.hairline)
                            .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 62)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(CheckpointTheme.panel.opacity(0.90))
                    .stroke(CheckpointTheme.hairline, lineWidth: 1)
            )
        }
        .animation(scopeChangeAnimation, value: presentation)
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
                    value: selectedMetrics.questionsAnswered > 0 ? selectedMetrics.accuracyText : "—",
                    detail: selectedMetrics.questionsAnswered > 0
                        ? "\(selectedMetrics.correctAnswers) of \(selectedMetrics.questionsAnswered) correct"
                        : "No questions answered this week",
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

    private var skillSnapshot: some View {
        Group {
            if !selectedMetrics.skillSnapshotSignals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("SKILL SNAPSHOT")

                    Text("Current mastery estimates reflect all checkpoint evidence, not just this week.")
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        ForEach(
                            Array(selectedMetrics.skillSnapshotSignals.enumerated()),
                            id: \.element.id
                        ) { index, signal in
                            SkillSnapshotSignalRow(signal: signal)
                                .transition(scopeChangeTransition)

                            if index < selectedMetrics.skillSnapshotSignals.count - 1 {
                                Divider()
                                    .overlay(CheckpointTheme.hairline)
                                    .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 52)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(CheckpointTheme.panel.opacity(0.88))
                            .stroke(CheckpointTheme.hairline, lineWidth: 1)
                    )
                }
                .transition(scopeChangeTransition)
            }
        }
        .animation(scopeChangeAnimation, value: selectedMetricsID)
        .animation(scopeChangeAnimation, value: selectedMetrics.skillSnapshotSignals)
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

    private func selectMetrics(_ metricsID: String) {
        guard WeeklyReviewScopeInteractionPolicy.reportsSelectionFeedback(
            selectedMetricsID: metricsID,
            currentMetricsID: selectedMetricsID
        ), let metrics = metricOptions.first(where: { $0.id == metricsID }) else {
            return
        }

        withAnimation(scopeChangeAnimation) {
            selectedMetricsID = metricsID
        }
        scopeSelectionFeedbackSequence += 1
        AccessibilityNotification.Announcement(
            "Showing weekly impact for \(metrics.title)."
        ).post()
    }

    private func goalPulseTint(at index: Int) -> Color {
        let tints = [
            CheckpointTheme.teal,
            CheckpointTheme.blue,
            CheckpointTheme.amber,
            CheckpointTheme.coral
        ]
        return tints[index % tints.count]
    }

    private var weekRangeText: String {
        guard let week = displayCalendar.dateInterval(of: .weekOfYear, for: referenceDate),
              let finalDay = displayCalendar.date(byAdding: .day, value: -1, to: week.end) else {
            return "This week"
        }

        if displayCalendar.component(.month, from: week.start) == displayCalendar.component(.month, from: finalDay) {
            return "\(formattedWeekDate(week.start, includesMonth: true))–\(formattedWeekDate(finalDay, includesMonth: false))"
        }
        return "\(formattedWeekDate(week.start, includesMonth: true))–\(formattedWeekDate(finalDay, includesMonth: true))"
    }

    private func formattedWeekDate(_ date: Date, includesMonth: Bool) -> String {
        let formatter = DateFormatter()
        formatter.calendar = displayCalendar
        formatter.locale = displayLocale
        formatter.timeZone = displayTimeZone
        formatter.setLocalizedDateFormatFromTemplate(includesMonth ? "MMMd" : "d")
        return formatter.string(from: date)
    }

    private var signalGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 142), spacing: 10)]
    }

    private var scopeChangeAnimation: Animation? {
        CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)
    }

    private var scopeChangeTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.99, anchor: .top))
    }

    private var heroText: Color { CheckpointTheme.heroText }
    private var heroSecondaryText: Color { CheckpointTheme.heroMuted }
    private var heroAccent: Color { CheckpointTheme.heroSuccess }
}

private struct WeeklyGoalPulseRow: View {
    let item: WeeklyGoalPulseItem
    let tint: Color
    let revealDelay: TimeInterval
    let reduceMotion: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                inlineLayout
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var inlineLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            goalIcon

            VStack(alignment: .leading, spacing: 7) {
                goalTitle
                activityCopy
                questionShareBar
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.muted.opacity(0.72))
                .padding(.top, 3)
                .accessibilityHidden(true)
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                goalIcon
                goalTitle
            }

            activityCopy
            questionShareBar

            HStack(spacing: 5) {
                Text("View impact")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
        }
    }

    private var goalIcon: some View {
        Image(systemName: item.isCurrentGoal ? "scope" : "circle.hexagongrid.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            .accessibilityHidden(true)
    }

    private var goalTitle: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                goalTitleText
                currentBadge
            }

            VStack(alignment: .leading, spacing: 6) {
                goalTitleText
                currentBadge
            }
        }
    }

    private var goalTitleText: some View {
        Text(item.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var currentBadge: some View {
        if item.isCurrentGoal {
            Text("CURRENT")
                .font(.caption2.weight(.bold))
                .tracking(0.65)
                .foregroundStyle(CheckpointTheme.teal)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
        }
    }

    private var activityCopy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.activityText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(item.hasActivity ? CheckpointTheme.text : CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.supportingText)
                .font(.caption)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var questionShareBar: some View {
        WeeklyGoalPulseBar(
            fraction: item.questionShare,
            tint: tint,
            revealDelay: revealDelay,
            reduceMotion: reduceMotion
        )
        .padding(.top, 2)
    }
}

private struct WeeklyGoalPulseBar: View {
    let fraction: Double
    let tint: Color
    let revealDelay: TimeInterval
    let reduceMotion: Bool

    @State private var renderedFraction = 0.0

    private var normalizedFraction: Double {
        min(max(fraction, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CheckpointTheme.hairline.opacity(0.72))

                Capsule()
                    .fill(tint.opacity(0.88))
                    .frame(width: proxy.size.width * renderedFraction)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
        .task(id: normalizedFraction) {
            if reduceMotion {
                renderedFraction = normalizedFraction
                return
            }

            renderedFraction = 0
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(CheckpointMotion.reveal.delay(revealDelay)) {
                renderedFraction = normalizedFraction
            }
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                renderedFraction = normalizedFraction
            }
        }
    }
}

private struct WeeklyPracticeBars: View {
    var days: [WeeklyPracticeDay]
    var referenceDate: Date
    var reduceMotion: Bool
    var dateLabelFormatter: WeeklyReviewDateLabelFormatter

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

                    Text(dateLabelFormatter.narrowWeekday(for: day.date))
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
            return CheckpointTheme.heroSuccess
        }
        return CheckpointTheme.heroTrack.opacity(day.date > referenceDate ? 0.45 : 1)
    }

    private func labelColor(for day: WeeklyPracticeDay) -> Color {
        CheckpointTheme.heroMuted.opacity(day.date > referenceDate ? 0.72 : 1)
    }

    private func accessibilityLabel(for day: WeeklyPracticeDay) -> String {
        let weekday = dateLabelFormatter.wideWeekday(for: day.date)
        if day.date > referenceDate {
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

private struct SkillSnapshotSignalRow: View {
    var signal: WeeklySignalInsight

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    signalIcon
                    signalCopy
                }
            } else {
                HStack(spacing: 12) {
                    signalIcon
                    signalCopy
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(signal.accessibilityLabel)
    }

    private var signalIcon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    private var signalCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(0.65)
                .foregroundStyle(CheckpointTheme.muted)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
    }

    private var eyebrow: String {
        switch signal.role {
        case .lowestCurrentEstimate:
            "LOWEST CURRENT ESTIMATE"
        case .highestCurrentEstimate:
            "HIGHEST CURRENT ESTIMATE"
        case .checkpointsCleared:
            "CHECKPOINTS CLEARED"
        case .answersLogged:
            "SKILL MAP"
        case .checkpointStreak:
            "CHECKPOINT STREAK"
        }
    }

    private var title: String {
        switch signal {
        case let .lowestCurrentEstimate(skill),
             let .highestCurrentEstimate(skill):
            skill
        case .checkpointsCleared, .answersLogged, .checkpointStreak:
            signal.text
        }
    }

    private var systemImage: String {
        switch signal.role {
        case .lowestCurrentEstimate:
            "chart.bar.fill"
        case .highestCurrentEstimate:
            "waveform.path.ecg"
        case .checkpointsCleared:
            "shield.checkered"
        case .answersLogged:
            "point.3.connected.trianglepath.dotted"
        case .checkpointStreak:
            "flame.fill"
        }
    }

    private var tint: Color {
        switch signal.role {
        case .lowestCurrentEstimate:
            CheckpointTheme.amber
        case .highestCurrentEstimate, .checkpointsCleared:
            CheckpointTheme.blue
        case .answersLogged:
            CheckpointTheme.teal
        case .checkpointStreak:
            CheckpointTheme.coral
        }
    }
}
