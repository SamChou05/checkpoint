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
    private let detailDateFormatter: DateFormatter
    private let locale: Locale

    init(
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) {
        self.locale = locale
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

        let detailDateFormatter = DateFormatter()
        detailDateFormatter.calendar = calendar
        detailDateFormatter.locale = locale
        detailDateFormatter.timeZone = timeZone
        detailDateFormatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        self.detailDateFormatter = detailDateFormatter
    }

    func narrowWeekday(for date: Date) -> String {
        narrowWeekdayFormatter.string(from: date)
    }

    func wideWeekday(for date: Date) -> String {
        wideWeekdayFormatter.string(from: date)
    }

    func detailDate(for date: Date) -> String {
        detailDateFormatter.string(from: date)
    }

    func uppercaseDetailDate(for date: Date) -> String {
        detailDate(for: date).uppercased(with: locale)
    }
}

enum WeeklyReviewNavigationDirection: Equatable {
    case previous
    case next
}

enum WeeklyReviewPeriodMotionStyle: Equatable {
    case directional
    case identity
}

struct WeeklyReviewActivityPolicy {
    static func hasPeriodActivity(_ metrics: WeeklyMetricsSummary) -> Bool {
        metrics.questionsAnswered > 0 || metrics.checkpointsCleared > 0
    }

    static func showsStreakBadge(_ metrics: WeeklyMetricsSummary) -> Bool {
        hasPeriodActivity(metrics) && metrics.checkpointStreakDays > 0
    }
}

enum WeeklyReviewPrimaryMetricKind: Equatable {
    case questionsAnswered
    case checkpointsCleared
}

struct WeeklyReviewPrimaryMetricPresentation: Equatable {
    let kind: WeeklyReviewPrimaryMetricKind
    let eyebrowText: String
    let value: Int
    let nounText: String
    let accessibilityLabel: String

    init(metrics: WeeklyMetricsSummary, isCurrentWeek: Bool) {
        let questionsAnswered = max(0, metrics.questionsAnswered)
        let checkpointsCleared = max(0, metrics.checkpointsCleared)
        let periodText = isCurrentWeek ? "this week" : "that week"

        if questionsAnswered > 0 || checkpointsCleared == 0 {
            let noun = questionsAnswered == 1 ? "question" : "questions"
            kind = .questionsAnswered
            eyebrowText = "LEARNING OUTPUT"
            value = questionsAnswered
            nounText = noun
            accessibilityLabel = "\(questionsAnswered) \(noun) answered \(periodText)"
        } else {
            let noun = checkpointsCleared == 1
                ? "checkpoint cleared"
                : "checkpoints cleared"
            kind = .checkpointsCleared
            eyebrowText = "CHECKPOINT ACTIVITY"
            value = checkpointsCleared
            nounText = noun
            accessibilityLabel = "\(checkpointsCleared) \(noun) \(periodText)"
        }
    }
}

struct WeeklyReviewCheckpointMetricPresentation: Equatable {
    let label: String
    let value: String
    let detail: String?
    let accessibilityLabel: String

    init(
        checkpointsCleared: Int,
        earnedBreakMinutes: Int,
        earnedBreakTimeText: String,
        isCurrentWeek: Bool
    ) {
        let normalizedCheckpoints = max(0, checkpointsCleared)
        let normalizedMinutes = max(0, earnedBreakMinutes)
        let checkpointNoun = normalizedCheckpoints == 1 ? "checkpoint" : "checkpoints"
        let periodText = isCurrentWeek ? "this week" : "that week"
        let checkpointText = "\(normalizedCheckpoints) \(checkpointNoun) cleared \(periodText)"

        label = normalizedCheckpoints == 1 ? "Checkpoint cleared" : "Checkpoints cleared"
        value = "\(normalizedCheckpoints)"

        if normalizedCheckpoints > 0, normalizedMinutes > 0 {
            detail = WeeklyReviewImpactCopy.breakAccess(
                compactDuration: earnedBreakTimeText
            )
            accessibilityLabel = "\(checkpointText). \(WeeklyReviewImpactCopy.accessibleBreakAccess(minutes: normalizedMinutes))"
        } else if normalizedCheckpoints > 0 {
            detail = nil
            accessibilityLabel = checkpointText
        } else {
            detail = "No break access granted"
            accessibilityLabel = "\(checkpointText). No break access granted"
        }
    }
}

enum WeeklyReviewSignalMetricKind: Hashable {
    case accuracy
    case recoveredMisses
    case checkpointsCleared
    case practiceDays
}

struct WeeklyReviewSignalOrderPolicy {
    static func orderedKinds(
        primaryMetricKind: WeeklyReviewPrimaryMetricKind
    ) -> [WeeklyReviewSignalMetricKind] {
        switch primaryMetricKind {
        case .questionsAnswered:
            [.accuracy, .recoveredMisses, .checkpointsCleared, .practiceDays]
        case .checkpointsCleared:
            [.checkpointsCleared, .practiceDays, .accuracy, .recoveredMisses]
        }
    }
}

private enum WeeklyReviewImpactCopy {
    static func checkpointCount(_ count: Int) -> String {
        let normalizedCount = max(0, count)
        let noun = normalizedCount == 1 ? "checkpoint" : "checkpoints"
        return "\(normalizedCount) \(noun) cleared"
    }

    static func breakAccess(compactDuration: String) -> String {
        "Break access · \(compactDuration) granted"
    }

    static func accessibleBreakAccess(minutes: Int) -> String {
        "\(weeklyAccessibleDurationText(minutes: minutes)) of break access granted"
    }
}

struct WeeklyReviewReferenceDateState: Equatable {
    let referenceDate: Date
    let selectedWeekStart: Date
    let navigationDirection: WeeklyReviewNavigationDirection?
}

struct WeeklyReviewStateSnapshot: Equatable {
    let referenceDate: Date
    let selectedWeekStart: Date
    let isCurrentWeek: Bool
    let canGoNext: Bool
    let rangeText: String
    let emptyTitle: String
    let hasActivity: Bool
    let showsStreakBadge: Bool
    let navigationDirection: WeeklyReviewNavigationDirection
}

struct WeeklyReviewReferenceDateRefreshPolicy {
    static func refreshedState(
        referenceDate: Date,
        selectedWeekReferenceDate: Date,
        refreshedReferenceDate: Date,
        calendar: Calendar
    ) -> WeeklyReviewReferenceDateState {
        let previousCurrentWeekStart = weekStart(
            containing: referenceDate,
            calendar: calendar
        )
        let refreshedCurrentWeekStart = weekStart(
            containing: refreshedReferenceDate,
            calendar: calendar
        )
        let normalizedSelectedWeekStart = weekStart(
            containing: selectedWeekReferenceDate,
            calendar: calendar
        )
        let wasShowingCurrentWeek = normalizedSelectedWeekStart == previousCurrentWeekStart
        let refreshedSelectedWeekStart = wasShowingCurrentWeek
            ? refreshedCurrentWeekStart
            : min(normalizedSelectedWeekStart, refreshedCurrentWeekStart)
        let navigationDirection: WeeklyReviewNavigationDirection?
        if refreshedSelectedWeekStart > normalizedSelectedWeekStart {
            navigationDirection = .next
        } else if refreshedSelectedWeekStart < normalizedSelectedWeekStart {
            navigationDirection = .previous
        } else {
            navigationDirection = nil
        }

        return WeeklyReviewReferenceDateState(
            referenceDate: refreshedReferenceDate,
            selectedWeekStart: refreshedSelectedWeekStart,
            navigationDirection: navigationDirection
        )
    }

    private static func weekStart(
        containing date: Date,
        calendar: Calendar
    ) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }
}

struct WeeklyReviewPeriodPolicy {
    let referenceDate: Date
    let selectedWeekStart: Date
    let currentWeekStart: Date
    let earliestWeekStart: Date
    let effectiveAsOf: Date
    let isCurrentWeek: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let motionStyle: WeeklyReviewPeriodMotionStyle

    private let calendar: Calendar

    init(
        referenceDate: Date,
        selectedWeekReferenceDate: Date,
        attempts: [CheckpointAttempt],
        unlockEvents: [UnlockEvent],
        calendar: Calendar,
        reduceMotion: Bool
    ) {
        self.referenceDate = referenceDate
        self.calendar = calendar

        let currentWeekStart = Self.weekStart(
            containing: referenceDate,
            calendar: calendar
        )
        self.currentWeekStart = currentWeekStart

        let earliestActivityDate = (
            attempts.map(\.createdAt) + unlockEvents.map(\.createdAt)
        )
        .filter { $0 <= referenceDate }
        .min()
        let unboundedEarliestWeekStart = earliestActivityDate.map {
            Self.weekStart(containing: $0, calendar: calendar)
        } ?? currentWeekStart
        let earliestWeekStart = min(unboundedEarliestWeekStart, currentWeekStart)
        self.earliestWeekStart = earliestWeekStart

        let requestedWeekStart = Self.weekStart(
            containing: selectedWeekReferenceDate,
            calendar: calendar
        )
        let selectedWeekStart = min(
            max(requestedWeekStart, earliestWeekStart),
            currentWeekStart
        )
        self.selectedWeekStart = selectedWeekStart
        isCurrentWeek = selectedWeekStart == currentWeekStart
        canGoPrevious = selectedWeekStart > earliestWeekStart
        canGoNext = selectedWeekStart < currentWeekStart
        motionStyle = reduceMotion ? .identity : .directional

        if selectedWeekStart == currentWeekStart {
            effectiveAsOf = referenceDate
        } else if let followingWeekStart = calendar.date(
            byAdding: .weekOfYear,
            value: 1,
            to: selectedWeekStart
        ) {
            effectiveAsOf = Date(
                timeIntervalSinceReferenceDate:
                    followingWeekStart.timeIntervalSinceReferenceDate.nextDown
            )
        } else {
            effectiveAsOf = selectedWeekStart
        }
    }

    func destination(for direction: WeeklyReviewNavigationDirection) -> Date? {
        let offset: Int
        switch direction {
        case .previous:
            guard canGoPrevious else { return nil }
            offset = -1
        case .next:
            guard canGoNext else { return nil }
            offset = 1
        }

        guard let candidate = calendar.date(
            byAdding: .weekOfYear,
            value: offset,
            to: selectedWeekStart
        ) else {
            return nil
        }

        return min(max(candidate, earliestWeekStart), currentWeekStart)
    }

    func reportsSelectionFeedback(
        for direction: WeeklyReviewNavigationDirection
    ) -> Bool {
        destination(for: direction) != nil
    }

    private static func weekStart(
        containing date: Date,
        calendar: Calendar
    ) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }
}

struct WeeklyReviewPeriodPresentation: Equatable {
    let eyebrowText: String
    let rangeText: String
    let accessibilityLabel: String
    let summaryText: String
    let emptyTitle: String
    let emptyDetail: String

    init(
        policy: WeeklyReviewPeriodPolicy,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) {
        let start = policy.selectedWeekStart
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let rangeCrossesYear = calendar.component(.year, from: start)
            != calendar.component(.year, from: end)
        let fullDateTemplate = policy.isCurrentWeek && !rangeCrossesYear
            ? "EEEEMMMMd"
            : "EEEEMMMMdyyyy"

        eyebrowText = policy.isCurrentWeek ? "THIS WEEK" : "WEEKLY ARCHIVE"
        rangeText = Self.rangeText(
            start: start,
            end: end,
            includesYear: !policy.isCurrentWeek,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let fullStart = Self.formatted(
            start,
            template: fullDateTemplate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let fullEnd = Self.formatted(
            end,
            template: fullDateTemplate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        accessibilityLabel = "Week of \(fullStart) through \(fullEnd)"

        if policy.isCurrentWeek {
            summaryText = "A quiet read on what your checkpoints turned into."
            emptyTitle = "Your signal starts with one checkpoint"
            emptyDetail = "Questions, recovered misses, and cleared checkpoints will collect here without any extra setup."
        } else {
            summaryText = "A complete read on what your checkpoints turned into that week."
            emptyTitle = "No checkpoint activity that week"
            emptyDetail = "Try another week or goal to keep exploring your history."
        }
    }

    private static func rangeText(
        start: Date,
        end: Date,
        includesYear: Bool,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let sameYear = calendar.component(.year, from: start)
            == calendar.component(.year, from: end)
        let sameMonth = sameYear && calendar.component(.month, from: start)
            == calendar.component(.month, from: end)

        if !sameYear {
            let startText = formatted(
                start,
                template: "MMMdy",
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
            let endText = formatted(
                end,
                template: "MMMdy",
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
            return "\(startText)–\(endText)"
        }

        let startText = formatted(
            start,
            template: "MMMd",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let endText = formatted(
            end,
            template: sameMonth ? "d" : "MMMd",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let range = "\(startText)–\(endText)"
        guard includesYear else { return range }

        let yearText = formatted(
            end,
            template: "y",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        return "\(range), \(yearText)"
    }

    private static func formatted(
        _ date: Date,
        template: String,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

struct WeeklyPracticeSelectionPolicy {
    static func canSelect(day: WeeklyPracticeDay, referenceDate: Date) -> Bool {
        day.date <= referenceDate
    }

    static func reconciledSelection(
        preferredDayID: WeeklyPracticeDay.ID?,
        days: [WeeklyPracticeDay],
        referenceDate: Date
    ) -> WeeklyPracticeDay.ID? {
        let selectableDays = days.filter { canSelect(day: $0, referenceDate: referenceDate) }
        if let preferredDayID,
           selectableDays.contains(where: { $0.id == preferredDayID }) {
            return preferredDayID
        }

        return selectableDays.last(where: \.hasActivity)?.id ?? selectableDays.last?.id
    }

    static func reportsSelectionFeedback(
        selectedDayID: WeeklyPracticeDay.ID,
        currentDayID: WeeklyPracticeDay.ID?
    ) -> Bool {
        selectedDayID != currentDayID
    }
}

enum WeeklyPracticeSelectionMotionStyle: Equatable {
    case animated
    case identity
}

struct WeeklyPracticeSelectionMotionPolicy {
    let style: WeeklyPracticeSelectionMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }
}

struct WeeklyPracticeChartLayoutPolicy {
    static let minimumDayWidth: CGFloat = 44

    enum OverflowTreatment: Equatable {
        case fitted
        case horizontalScrollWithCue
    }

    static func overflowTreatment(
        availableWidth: CGFloat,
        dayCount: Int
    ) -> OverflowTreatment {
        requiresHorizontalScrolling(availableWidth: availableWidth, dayCount: dayCount)
            ? .horizontalScrollWithCue
            : .fitted
    }

    static func requiresHorizontalScrolling(
        availableWidth: CGFloat,
        dayCount: Int
    ) -> Bool {
        guard dayCount > 0 else { return false }
        return availableWidth < minimumDayWidth * CGFloat(dayCount)
    }
}

enum WeeklyPracticeBarState: Equatable {
    case learning
    case checkpointOnly
    case inactive
    case future
}

struct WeeklyPracticeBarPresentation: Equatable {
    let state: WeeklyPracticeBarState
    let activityCount: Int

    init(day: WeeklyPracticeDay, referenceDate: Date) {
        if day.date > referenceDate {
            state = .future
            activityCount = 0
        } else if day.questionsAnswered > 0 {
            state = .learning
            activityCount = day.questionsAnswered
        } else if day.checkpointsCleared > 0 {
            state = .checkpointOnly
            activityCount = day.checkpointsCleared
        } else {
            state = .inactive
            activityCount = 0
        }
    }

    static func maximumCount(
        for days: [WeeklyPracticeDay],
        referenceDate: Date
    ) -> Int {
        max(
            1,
            days.lazy.map {
                WeeklyPracticeBarPresentation(
                    day: $0,
                    referenceDate: referenceDate
                ).activityCount
            }.max() ?? 1
        )
    }

    func height(maximumCount: Int) -> CGFloat {
        guard activityCount > 0 else { return 4 }
        let normalizedMaximum = max(1, maximumCount)
        let normalizedCount = min(activityCount, normalizedMaximum)
        return 12 + (42 * CGFloat(normalizedCount) / CGFloat(normalizedMaximum))
    }
}

struct WeeklyReviewResponsiveLayoutPolicy: Equatable {
    static let compactWidth: CGFloat = 320
    static let regularInsetWidth: CGFloat = 360

    let viewportWidth: CGFloat
    let dynamicTypeSize: DynamicTypeSize

    var usesCompactWidth: Bool {
        viewportWidth < Self.regularInsetWidth
    }

    private var compactFraction: CGFloat {
        let range = Self.regularInsetWidth - Self.compactWidth
        guard range > 0 else { return 0 }
        return min(max((Self.regularInsetWidth - viewportWidth) / range, 0), 1)
    }

    var screenHorizontalPadding: CGFloat {
        20 - (8 * compactFraction)
    }

    var heroHorizontalPadding: CGFloat {
        20 - (8 * compactFraction)
    }

    var dayDetailHorizontalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? 14 - (4 * compactFraction)
            : 14
    }

    var practiceChartAvailableWidth: CGFloat {
        max(
            0,
            viewportWidth
                - (screenHorizontalPadding * 2)
                - (heroHorizontalPadding * 2)
        )
    }

    var dayDetailCopyAvailableWidth: CGFloat {
        max(0, practiceChartAvailableWidth - (dayDetailHorizontalPadding * 2))
    }
}

struct WeeklyPracticeDayDetailPresentation: Equatable {
    let id: WeeklyPracticeDay.ID
    let dateText: String
    let dateEyebrowText: String
    let activityText: String
    let checkpointText: String?
    let accessibilityLabel: String
    let isFuture: Bool
    let hasActivity: Bool

    init(
        day: WeeklyPracticeDay,
        referenceDate: Date,
        dateLabelFormatter: WeeklyReviewDateLabelFormatter
    ) {
        id = day.id
        dateText = dateLabelFormatter.detailDate(for: day.date)
        dateEyebrowText = dateLabelFormatter.uppercaseDetailDate(for: day.date)
        isFuture = day.date > referenceDate
        hasActivity = day.hasActivity

        if isFuture {
            activityText = "Not yet"
            checkpointText = "This day is still ahead."
            accessibilityLabel = "\(dateText). Not yet. This day is still ahead."
        } else {
            let accessibilityActivityText: String
            if let accuracyPercent = day.accuracyPercent {
                let questionNoun = day.questionsAnswered == 1 ? "question" : "questions"
                activityText = "\(day.questionsAnswered) \(questionNoun) · \(accuracyPercent)% correct"
                accessibilityActivityText = "\(day.questionsAnswered) \(questionNoun), \(accuracyPercent) percent correct"
            } else if day.checkpointsCleared > 0 {
                let checkpointText = WeeklyReviewImpactCopy.checkpointCount(
                    day.checkpointsCleared
                )
                activityText = checkpointText
                accessibilityActivityText = checkpointText
            } else {
                activityText = "No questions answered"
                accessibilityActivityText = activityText
            }

            if day.checkpointsCleared > 0 {
                let checkpointText = WeeklyReviewImpactCopy.checkpointCount(
                    day.checkpointsCleared
                )
                if day.questionsAnswered > 0, day.earnedBreakMinutes > 0 {
                    self.checkpointText = "\(checkpointText) · \(day.earnedBreakTimeText) break access granted"
                    accessibilityLabel = [
                        dateText,
                        accessibilityActivityText,
                        checkpointText,
                        WeeklyReviewImpactCopy.accessibleBreakAccess(
                            minutes: day.earnedBreakMinutes
                        )
                    ]
                    .joined(separator: ". ")
                } else if day.questionsAnswered > 0 {
                    self.checkpointText = checkpointText
                    accessibilityLabel = [
                        dateText,
                        accessibilityActivityText,
                        checkpointText
                    ]
                    .joined(separator: ". ")
                } else if day.earnedBreakMinutes > 0 {
                    self.checkpointText = WeeklyReviewImpactCopy.breakAccess(
                        compactDuration: day.earnedBreakTimeText
                    )
                    accessibilityLabel = [
                        dateText,
                        accessibilityActivityText,
                        WeeklyReviewImpactCopy.accessibleBreakAccess(
                            minutes: day.earnedBreakMinutes
                        )
                    ]
                    .joined(separator: ". ")
                } else {
                    self.checkpointText = nil
                    accessibilityLabel = [
                        dateText,
                        accessibilityActivityText
                    ]
                    .joined(separator: ". ")
                }
            } else {
                let noCheckpointText = "No checkpoint cleared"
                checkpointText = noCheckpointText
                accessibilityLabel = [
                    dateText,
                    accessibilityActivityText,
                    noCheckpointText
                ]
                .joined(separator: ". ")
            }
        }
    }
}

enum WeeklyGoalPulseShareBasis: Equatable {
    case questionsAnswered
    case checkpointsCleared
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
    let earnedBreakMinutes: Int
    let earnedBreakTimeText: String
    let impactShare: Double
    let hasActivity: Bool
    let isCurrentWeek: Bool

    var activityText: String {
        guard hasActivity else {
            return isCurrentWeek
                ? "No checkpoint activity this week"
                : "No checkpoint activity that week"
        }

        if questionsAnswered > 0 {
            let noun = questionsAnswered == 1 ? "question" : "questions"
            return "\(questionsAnswered) \(noun) · \(accuracyText ?? "—") correct"
        }

        let period = isCurrentWeek ? "this week" : "that week"
        return "\(WeeklyReviewImpactCopy.checkpointCount(checkpointsCleared)) \(period)"
    }

    var supportingText: String {
        guard hasActivity else {
            return isCurrentWeek ? "Ready for your next checkpoint" : "No activity recorded"
        }

        var details: [String] = []
        if activePracticeDays > 0 {
            let noun = activePracticeDays == 1 ? "practice day" : "practice days"
            details.append("\(activePracticeDays) \(noun)")
        }
        if questionsAnswered > 0, checkpointsCleared > 0 {
            details.append(WeeklyReviewImpactCopy.checkpointCount(checkpointsCleared))
        }
        if checkpointsCleared > 0, earnedBreakMinutes > 0 {
            details.append(
                WeeklyReviewImpactCopy.breakAccess(
                    compactDuration: earnedBreakTimeText
                )
            )
        }
        if checkpointStreakDays > 0 {
            details.append("\(checkpointStreakDays)-day checkpoint streak")
        }
        return details.joined(separator: " · ")
    }

    var accessibilityLabel: String {
        guard hasActivity else {
            return [
                title,
                isCurrentGoal ? "current goal" : nil,
                activityText,
                supportingText
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }

        let accessibilityActivityText: String
        if questionsAnswered > 0 {
            let noun = questionsAnswered == 1 ? "question" : "questions"
            let accuracy = accuracyText?
                .replacingOccurrences(of: "%", with: " percent")
                ?? "accuracy unavailable"
            accessibilityActivityText = "\(questionsAnswered) \(noun), \(accuracy) correct"
        } else {
            accessibilityActivityText = activityText
        }

        var accessibilityDetails: [String] = []
        if activePracticeDays > 0 {
            let noun = activePracticeDays == 1 ? "practice day" : "practice days"
            accessibilityDetails.append("\(activePracticeDays) \(noun)")
        }
        if questionsAnswered > 0, checkpointsCleared > 0 {
            accessibilityDetails.append(
                WeeklyReviewImpactCopy.checkpointCount(checkpointsCleared)
            )
        }
        if checkpointsCleared > 0, earnedBreakMinutes > 0 {
            accessibilityDetails.append(
                WeeklyReviewImpactCopy.accessibleBreakAccess(
                    minutes: earnedBreakMinutes
                )
            )
        }
        if checkpointStreakDays > 0 {
            accessibilityDetails.append("\(checkpointStreakDays)-day checkpoint streak")
        }

        return [
            title,
            isCurrentGoal ? "current goal" : nil,
            accessibilityActivityText,
            accessibilityDetails.isEmpty
                ? nil
                : accessibilityDetails.joined(separator: ", ")
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

@MainActor
struct WeeklyGoalPulsePresentation: Equatable {
    let items: [WeeklyGoalPulseItem]
    let shareBasis: WeeklyGoalPulseShareBasis
    let shareDescription: String

    init(
        goals: [Goal],
        metrics: [WeeklyMetricsSummary],
        attempts: [CheckpointAttempt],
        unlockEvents: [UnlockEvent],
        activeGoalID: Goal.ID?,
        asOf: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        isCurrentWeek: Bool = true
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
        let totalCheckpoints = metrics.reduce(0) { $0 + $1.checkpointsCleared }
        let periodText = isCurrentWeek ? "this week's" : "that week's"

        if totalQuestions > 0 {
            shareBasis = .questionsAnswered
            shareDescription = "Bars compare each goal's share of \(periodText) questions. Choose one to inspect its own signals."
        } else {
            shareBasis = .checkpointsCleared
            shareDescription = "Bars compare each goal's share of \(periodText) cleared checkpoints. Choose one to inspect its own signals."
        }

        let indexedItems: [(index: Int, item: WeeklyGoalPulseItem)] = goals.enumerated().compactMap { pair in
            let (index, goal) = pair
            guard let metric = metricsByID[goal.id.uuidString] else { return nil }
            let details = calculator.impactDetails(goalID: goal.id)
            let share: Double
            if totalQuestions > 0 {
                share = Double(metric.questionsAnswered) / Double(totalQuestions)
            } else if totalCheckpoints > 0 {
                share = Double(metric.checkpointsCleared) / Double(totalCheckpoints)
            } else {
                share = 0
            }
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
                earnedBreakMinutes: details.earnedBreakMinutes,
                earnedBreakTimeText: details.earnedBreakTimeText,
                impactShare: share,
                hasActivity: WeeklyReviewActivityPolicy.hasPeriodActivity(metric),
                isCurrentWeek: isCurrentWeek
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
    private let currentDate: @MainActor () -> Date
    private let displayCalendar: Calendar
    private let displayLocale: Locale
    private let displayTimeZone: TimeZone
    private let reduceMotionOverride: Bool?
    private let stateReporter: (@MainActor (WeeklyReviewStateSnapshot) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var referenceDate: Date
    @State private var selectedMetricsID = WeeklyMetricsSummary.allGoalsID
    @State private var selectedWeekStart: Date
    @State private var selectedPracticeDayID: WeeklyPracticeDay.ID?
    @State private var weekNavigationDirection = WeeklyReviewNavigationDirection.previous
    @State private var scopeSelectionFeedbackSequence = 0
    @State private var practiceDaySelectionFeedbackSequence = 0
    @State private var weekSelectionFeedbackSequence = 0
    @ScaledMetric(relativeTo: .largeTitle) private var heroMetricSize: CGFloat = 64

    init(
        store: CheckpointStore,
        initialMetricsID: String = WeeklyMetricsSummary.allGoalsID,
        referenceDate: Date = Date(),
        displayCalendar: Calendar = .current,
        displayLocale: Locale = .current,
        displayTimeZone: TimeZone = .current,
        reduceMotionOverride: Bool? = nil,
        initialSelectedPracticeDate: Date? = nil,
        initialWeekReferenceDate: Date? = nil,
        currentDate: @escaping @MainActor () -> Date = { Date() },
        stateReporter: (@MainActor (WeeklyReviewStateSnapshot) -> Void)? = nil
    ) {
        var normalizedDisplayCalendar = displayCalendar
        normalizedDisplayCalendar.timeZone = displayTimeZone
        self.store = store
        self.currentDate = currentDate
        self.displayCalendar = normalizedDisplayCalendar
        self.displayLocale = displayLocale
        self.displayTimeZone = displayTimeZone
        self.reduceMotionOverride = reduceMotionOverride
        self.stateReporter = stateReporter
        _referenceDate = State(initialValue: referenceDate)
        _selectedMetricsID = State(initialValue: initialMetricsID)
        let initialPeriod = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: initialWeekReferenceDate ?? referenceDate,
            attempts: store.attempts,
            unlockEvents: store.unlockEvents,
            calendar: normalizedDisplayCalendar,
            reduceMotion: reduceMotionOverride ?? false
        )
        _selectedWeekStart = State(initialValue: initialPeriod.selectedWeekStart)
        _selectedPracticeDayID = State(
            initialValue: initialSelectedPracticeDate.map {
                normalizedDisplayCalendar.startOfDay(for: $0)
            }
        )
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var periodPolicy: WeeklyReviewPeriodPolicy {
        WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: selectedWeekStart,
            attempts: store.attempts,
            unlockEvents: store.unlockEvents,
            calendar: displayCalendar,
            reduceMotion: reduceMotion
        )
    }

    private var periodPresentation: WeeklyReviewPeriodPresentation {
        WeeklyReviewPeriodPresentation(
            policy: periodPolicy,
            calendar: displayCalendar,
            locale: displayLocale,
            timeZone: displayTimeZone
        )
    }

    private var periodReferenceDate: Date {
        periodPolicy.effectiveAsOf
    }

    private var totalMetrics: WeeklyMetricsSummary {
        store.weeklyTotalMetrics(asOf: periodReferenceDate, calendar: displayCalendar)
    }

    private var goalMetrics: [WeeklyMetricsSummary] {
        let resolver = GoalDisplayTitleResolver(
            goals: store.availableGoalProfiles,
            calendar: displayCalendar,
            locale: displayLocale,
            timeZone: displayTimeZone
        )

        return store.weeklyGoalMetrics(
            asOf: periodReferenceDate,
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
            asOf: periodReferenceDate,
            calendar: displayCalendar
        ).impactDetails(goalID: selectedGoalID)
    }

    private var primaryMetricPresentation: WeeklyReviewPrimaryMetricPresentation {
        WeeklyReviewPrimaryMetricPresentation(
            metrics: selectedMetrics,
            isCurrentWeek: periodPolicy.isCurrentWeek
        )
    }

    private var checkpointMetricPresentation: WeeklyReviewCheckpointMetricPresentation {
        WeeklyReviewCheckpointMetricPresentation(
            checkpointsCleared: selectedMetrics.checkpointsCleared,
            earnedBreakMinutes: impactDetails.earnedBreakMinutes,
            earnedBreakTimeText: impactDetails.earnedBreakTimeText,
            isCurrentWeek: periodPolicy.isCurrentWeek
        )
    }

    private var dateLabelFormatter: WeeklyReviewDateLabelFormatter {
        WeeklyReviewDateLabelFormatter(
            calendar: displayCalendar,
            locale: displayLocale,
            timeZone: displayTimeZone
        )
    }

    private var resolvedPracticeDayID: WeeklyPracticeDay.ID? {
        WeeklyPracticeSelectionPolicy.reconciledSelection(
            preferredDayID: selectedPracticeDayID,
            days: impactDetails.practiceDays,
            referenceDate: periodReferenceDate
        )
    }

    private var selectedPracticeDay: WeeklyPracticeDay? {
        guard let resolvedPracticeDayID else { return nil }
        return impactDetails.practiceDays.first { $0.id == resolvedPracticeDayID }
    }

    private var selectedPracticeDayPresentation: WeeklyPracticeDayDetailPresentation? {
        guard let selectedPracticeDay else { return nil }
        return WeeklyPracticeDayDetailPresentation(
            day: selectedPracticeDay,
            referenceDate: periodReferenceDate,
            dateLabelFormatter: dateLabelFormatter
        )
    }

    private var goalPulsePresentation: WeeklyGoalPulsePresentation {
        WeeklyGoalPulsePresentation(
            goals: store.availableGoalProfiles,
            metrics: goalMetrics,
            attempts: store.attempts,
            unlockEvents: store.unlockEvents,
            activeGoalID: store.goal?.id,
            asOf: periodReferenceDate,
            calendar: displayCalendar,
            locale: displayLocale,
            timeZone: displayTimeZone,
            isCurrentWeek: periodPolicy.isCurrentWeek
        )
    }

    private var stateSnapshot: WeeklyReviewStateSnapshot {
        WeeklyReviewStateSnapshot(
            referenceDate: referenceDate,
            selectedWeekStart: periodPolicy.selectedWeekStart,
            isCurrentWeek: periodPolicy.isCurrentWeek,
            canGoNext: periodPolicy.canGoNext,
            rangeText: periodPresentation.rangeText,
            emptyTitle: periodPresentation.emptyTitle,
            hasActivity: WeeklyReviewActivityPolicy.hasPeriodActivity(selectedMetrics),
            showsStreakBadge: WeeklyReviewActivityPolicy.showsStreakBadge(selectedMetrics),
            navigationDirection: weekNavigationDirection
        )
    }

    var body: some View {
        GeometryReader { proxy in
            weeklyReviewContent(
                layoutPolicy: WeeklyReviewResponsiveLayoutPolicy(
                    viewportWidth: proxy.size.width,
                    dynamicTypeSize: dynamicTypeSize
                )
            )
        }
    }

    private func weeklyReviewContent(
        layoutPolicy: WeeklyReviewResponsiveLayoutPolicy
    ) -> some View {
        let pulsePresentation: WeeklyGoalPulsePresentation? =
            selectedMetrics.id == WeeklyMetricsSummary.allGoalsID
            ? goalPulsePresentation
            : nil
        let displaysGoalPulse = (pulsePresentation?.items.count ?? 0) > 1

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    reviewHeader
                    VStack(alignment: .leading, spacing: 20) {
                        impactHero(layoutPolicy: layoutPolicy)
                            .id("impact-\(selectedMetrics.id)")
                            .transition(scopeChangeTransition)

                        if WeeklyReviewActivityPolicy.hasPeriodActivity(selectedMetrics) {
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
                    .id("week-\(periodPolicy.selectedWeekStart.timeIntervalSinceReferenceDate)")
                    .transition(periodChangeTransition)
                }
                .animation(periodChangeAnimation, value: periodPolicy.selectedWeekStart)
                .padding(.horizontal, layoutPolicy.screenHorizontalPadding)
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
            .onChange(of: selectedMetricsID) { _, _ in
                selectedPracticeDayID = nil
            }
            .onChange(of: selectedWeekStart) { _, _ in
                selectedPracticeDayID = nil
            }
            .onChange(of: periodPolicy.selectedWeekStart) { _, reconciledWeekStart in
                guard selectedWeekStart != reconciledWeekStart else { return }
                selectedWeekStart = reconciledWeekStart
                selectedPracticeDayID = nil
            }
            .onAppear {
                refreshReferenceDate()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshReferenceDate()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            ) { _ in
                refreshReferenceDate()
            }
            .onChange(of: stateSnapshot, initial: true) { _, snapshot in
                stateReporter?(snapshot)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CheckpointTheme.teal)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: scopeSelectionFeedbackSequence)
        .sensoryFeedback(.selection, trigger: practiceDaySelectionFeedbackSequence)
        .sensoryFeedback(.selection, trigger: weekSelectionFeedbackSequence)
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    weekEyebrow
                    selectedScope
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    weekEyebrow

                    Spacer(minLength: 8)

                    selectedScope
                }
            }

            weekNavigationRow

            if selectedMetrics.id != WeeklyMetricsSummary.allGoalsID,
               metricOptions.count > 2 {
                Text(selectedMetrics.title)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(periodPresentation.summaryText)
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
    }

    private var weekEyebrow: some View {
        Text(periodPresentation.eyebrowText)
            .font(.caption2.weight(.bold))
            .tracking(1.0)
            .foregroundStyle(CheckpointTheme.muted)
            .contentTransition(.opacity)
            .accessibilityHidden(true)
    }

    private var weekNavigationRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                weekRangeHeading
                Spacer(minLength: 8)
                weekNavigationControls
            }

            VStack(alignment: .leading, spacing: 10) {
                weekRangeHeading
                weekNavigationControls
            }
        }
    }

    private var weekRangeHeading: some View {
        Text(periodPresentation.rangeText)
            .font(.title2.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .accessibilityLabel(periodPresentation.accessibilityLabel)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var weekNavigationControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                weekNavigationButton(for: .previous, fillsAvailableWidth: true)
                weekNavigationButton(for: .next, fillsAvailableWidth: true)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 8) {
                weekNavigationButton(for: .previous)
                weekNavigationButton(for: .next)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func weekNavigationButton(
        for direction: WeeklyReviewNavigationDirection,
        fillsAvailableWidth: Bool = false
    ) -> some View {
        let isEnabled = direction == .previous
            ? periodPolicy.canGoPrevious
            : periodPolicy.canGoNext
        let title = direction == .previous ? "Previous" : "Next"
        let systemImage = direction == .previous ? "chevron.left" : "chevron.right"

        return Button {
            navigateWeek(direction)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isEnabled ? CheckpointTheme.teal : CheckpointTheme.muted)
                .frame(
                    maxWidth: fillsAvailableWidth ? .infinity : nil,
                    minHeight: 44
                )
                .padding(.horizontal, 10)
                .background(
                    CheckpointTheme.panelRaised.opacity(isEnabled ? 0.78 : 0.45),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(CheckpointTheme.hairline.opacity(0.82), lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel("\(title) week")
        .accessibilityHint(
            isEnabled
                ? "Shows the \(direction == .previous ? "previous" : "next") weekly impact."
                : (direction == .previous
                    ? "This is the earliest week with retained activity."
                    : "This is the current week.")
        )
    }

    @ViewBuilder
    private var selectedScope: some View {
        if metricOptions.count > 2 {
            goalMenu
        } else if selectedMetrics.id != WeeklyMetricsSummary.allGoalsID {
            Text(selectedMetrics.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
                .multilineTextAlignment(
                    dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
                )
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
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

    private func impactHero(
        layoutPolicy: WeeklyReviewResponsiveLayoutPolicy
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    primaryImpactMetric
                    streakBadge
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    primaryImpactMetric
                    Spacer(minLength: 0)
                    streakBadge
                }
            }

            if let trend = impactDetails.questionTrendText(
                currentQuestions: selectedMetrics.questionsAnswered,
                isCurrentWeek: periodPolicy.isCurrentWeek
            ) {
                Text(trend)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(heroSecondaryText)
            }

            WeeklyPracticeBars(
                days: impactDetails.practiceDays,
                referenceDate: periodReferenceDate,
                reduceMotion: reduceMotion,
                dateLabelFormatter: dateLabelFormatter,
                selectedDayID: resolvedPracticeDayID,
                availableWidth: layoutPolicy.practiceChartAvailableWidth,
                selectDay: selectPracticeDay
            )

            if let selectedPracticeDayPresentation {
                Divider()
                    .overlay(CheckpointTheme.heroDivider)

                WeeklyPracticeDayDetail(
                    presentation: selectedPracticeDayPresentation,
                    horizontalPadding: layoutPolicy.dayDetailHorizontalPadding
                )
                .id("\(selectedMetrics.id)-\(selectedPracticeDayPresentation.id.timeIntervalSinceReferenceDate)")
                .transition(practiceDayDetailTransition)
            }
        }
        .padding(.horizontal, layoutPolicy.heroHorizontalPadding)
        .padding(.vertical, 20)
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

    private var primaryImpactMetric: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(primaryMetricPresentation.eyebrowText)
                .font(.caption2.weight(.bold))
                .tracking(1.05)
                .foregroundStyle(heroSecondaryText)
                .contentTransition(.opacity)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    primaryImpactValue
                    primaryImpactNoun
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    primaryImpactValue
                    primaryImpactNoun
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(primaryMetricPresentation.accessibilityLabel)
    }

    private var primaryImpactValue: some View {
        Text("\(primaryMetricPresentation.value)")
            .font(.system(size: heroMetricSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(heroText)
            .contentTransition(.numericText(value: Double(primaryMetricPresentation.value)))
            .animation(
                CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                value: primaryMetricPresentation.value
            )
    }

    private var primaryImpactNoun: some View {
        Text(primaryMetricPresentation.nounText)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(heroSecondaryText)
            .contentTransition(.opacity)
    }

    @ViewBuilder
    private var streakBadge: some View {
        if WeeklyReviewActivityPolicy.showsStreakBadge(selectedMetrics) {
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

            Text(
                presentation.shareDescription
            )
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
                    .buttonStyle(CheckpointPressButtonStyle(role: .surface))
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
                ForEach(
                    WeeklyReviewSignalOrderPolicy.orderedKinds(
                        primaryMetricKind: primaryMetricPresentation.kind
                    ),
                    id: \.self
                ) { signalKind in
                    signalTile(for: signalKind)
                }
            }
        }
    }

    @ViewBuilder
    private func signalTile(
        for kind: WeeklyReviewSignalMetricKind
    ) -> some View {
        switch kind {
        case .accuracy:
            ImpactMetricTile(
                label: "Accuracy",
                value: selectedMetrics.questionsAnswered > 0
                    ? selectedMetrics.accuracyText
                    : "—",
                detail: selectedMetrics.questionsAnswered > 0
                    ? "\(selectedMetrics.correctAnswers) of \(selectedMetrics.questionsAnswered) correct"
                    : (periodPolicy.isCurrentWeek
                        ? "No questions answered this week"
                        : "No questions answered that week"),
                systemImage: "scope"
            )
        case .recoveredMisses:
            ImpactMetricTile(
                label: "Misses recovered",
                value: "\(impactDetails.recoveredQuestions)",
                detail: periodPolicy.isCurrentWeek
                    ? "Previously missed, currently correct"
                    : "Previously missed, correct by week's end",
                systemImage: "arrow.triangle.2.circlepath"
            )
        case .checkpointsCleared:
            ImpactMetricTile(
                label: checkpointMetricPresentation.label,
                value: checkpointMetricPresentation.value,
                detail: checkpointMetricPresentation.detail,
                systemImage: "shield.checkered",
                accessibilityLabel: checkpointMetricPresentation.accessibilityLabel
            )
        case .practiceDays:
            ImpactMetricTile(
                label: "Practice days",
                value: "\(impactDetails.activePracticeDays) / 7",
                detail: "Days with goal practice",
                systemImage: "calendar"
            )
        }
    }

    private var skillSnapshot: some View {
        Group {
            if !selectedMetrics.skillSnapshotSignals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("SKILL SNAPSHOT")

                    Text(
                        periodPolicy.isCurrentWeek
                            ? "Current mastery estimates reflect all checkpoint evidence, not just this week."
                            : "Current mastery estimates reflect all checkpoint evidence, not only the selected week."
                    )
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
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(periodPresentation.emptyTitle)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)

                Text(periodPresentation.emptyDetail)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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

    private func selectPracticeDay(_ day: WeeklyPracticeDay) {
        guard WeeklyPracticeSelectionPolicy.canSelect(
            day: day,
            referenceDate: referenceDate
        ), WeeklyPracticeSelectionPolicy.reportsSelectionFeedback(
            selectedDayID: day.id,
            currentDayID: resolvedPracticeDayID
        ) else {
            return
        }

        let presentation = WeeklyPracticeDayDetailPresentation(
            day: day,
            referenceDate: periodReferenceDate,
            dateLabelFormatter: dateLabelFormatter
        )
        withAnimation(practiceDaySelectionAnimation) {
            selectedPracticeDayID = day.id
        }
        practiceDaySelectionFeedbackSequence += 1
        AccessibilityNotification.Announcement(
            "Showing \(presentation.dateText)."
        ).post()
    }

    private func navigateWeek(_ direction: WeeklyReviewNavigationDirection) {
        guard periodPolicy.reportsSelectionFeedback(for: direction),
              let destination = periodPolicy.destination(for: direction) else {
            return
        }

        weekNavigationDirection = direction
        withAnimation(periodChangeAnimation) {
            selectedWeekStart = destination
            selectedPracticeDayID = nil
        }
        weekSelectionFeedbackSequence += 1

        let destinationPolicy = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: destination,
            attempts: store.attempts,
            unlockEvents: store.unlockEvents,
            calendar: displayCalendar,
            reduceMotion: reduceMotion
        )
        let destinationPresentation = WeeklyReviewPeriodPresentation(
            policy: destinationPolicy,
            calendar: displayCalendar,
            locale: displayLocale,
            timeZone: displayTimeZone
        )
        AccessibilityNotification.Announcement(
            "Showing \(destinationPresentation.accessibilityLabel)."
        ).post()
    }

    private func refreshReferenceDate() {
        let refreshedState = WeeklyReviewReferenceDateRefreshPolicy.refreshedState(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: selectedWeekStart,
            refreshedReferenceDate: currentDate(),
            calendar: displayCalendar
        )
        let didChangeSelectedWeek = selectedWeekStart != refreshedState.selectedWeekStart

        if let navigationDirection = refreshedState.navigationDirection {
            weekNavigationDirection = navigationDirection
        }
        referenceDate = refreshedState.referenceDate
        selectedWeekStart = refreshedState.selectedWeekStart
        if didChangeSelectedWeek {
            selectedPracticeDayID = nil
        }
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

    private var signalGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 142), spacing: 10)]
    }

    private var scopeChangeAnimation: Animation? {
        CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)
    }

    private var periodChangeAnimation: Animation? {
        periodPolicy.motionStyle == .directional ? CheckpointMotion.change : nil
    }

    private var periodChangeTransition: AnyTransition {
        guard periodPolicy.motionStyle == .directional else { return .identity }

        let insertionEdge: Edge = weekNavigationDirection == .previous ? .leading : .trailing
        let removalEdge: Edge = weekNavigationDirection == .previous ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var practiceDaySelectionAnimation: Animation? {
        switch WeeklyPracticeSelectionMotionPolicy(reduceMotion: reduceMotion).style {
        case .animated:
            CheckpointMotion.change
        case .identity:
            nil
        }
    }

    private var practiceDayDetailTransition: AnyTransition {
        switch WeeklyPracticeSelectionMotionPolicy(reduceMotion: reduceMotion).style {
        case .animated:
            .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
        case .identity:
            .identity
        }
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
                impactShareBar
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
            impactShareBar

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

    private var impactShareBar: some View {
        WeeklyGoalPulseBar(
            fraction: item.impactShare,
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
    var selectedDayID: WeeklyPracticeDay.ID?
    var availableWidth: CGFloat
    var selectDay: (WeeklyPracticeDay) -> Void

    @Namespace private var selectionNamespace

    private var maximumCount: Int {
        WeeklyPracticeBarPresentation.maximumCount(
            for: days,
            referenceDate: referenceDate
        )
    }

    private var overflowTreatment: WeeklyPracticeChartLayoutPolicy.OverflowTreatment {
        WeeklyPracticeChartLayoutPolicy.overflowTreatment(
            availableWidth: availableWidth,
            dayCount: days.count
        )
    }

    var body: some View {
        Group {
            switch overflowTreatment {
            case .horizontalScrollWithCue:
                VStack(alignment: .leading, spacing: 6) {
                    overflowAffordance
                    scrollableDayStrip
                }
            case .fitted:
                dayStrip(fillsAvailableWidth: true)
            }
        }
        .frame(height: overflowTreatment == .horizontalScrollWithCue ? 108 : 86)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily practice")
        .accessibilityHint(
            overflowTreatment == .horizontalScrollWithCue
                ? "Seven-day view. Swipe horizontally to explore every day."
                : "Choose a day to show its details."
        )
    }

    private var scrollableDayStrip: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal) {
                dayStrip(fillsAvailableWidth: false)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .onAppear {
                scrollToSelectedDay(using: scrollProxy, animated: false)
            }
            .onChange(of: selectedDayID) { _, _ in
                scrollToSelectedDay(using: scrollProxy, animated: !reduceMotion)
            }
            .overlay {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [CheckpointTheme.ink, CheckpointTheme.ink.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 10)

                    Spacer(minLength: 0)

                    LinearGradient(
                        colors: [CheckpointTheme.ink.opacity(0), CheckpointTheme.ink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 10)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private var overflowAffordance: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left.and.right")
                .accessibilityHidden(true)

            Text("ALL 7 DAYS")
                .tracking(0.65)

            Spacer(minLength: 8)

            if let firstDay = days.first,
               let lastDay = days.last {
                Text(
                    "\(dateLabelFormatter.narrowWeekday(for: firstDay.date))"
                        + "–\(dateLabelFormatter.narrowWeekday(for: lastDay.date))"
                )
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(CheckpointTheme.heroMuted)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }

    private func dayStrip(fillsAvailableWidth: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(days) { day in
                dayButton(for: day, fillsAvailableWidth: fillsAvailableWidth)
            }
        }
        .frame(
            minWidth: fillsAvailableWidth ? 0 : nil,
            maxWidth: fillsAvailableWidth ? .infinity : nil,
            alignment: .leading
        )
    }

    private func dayButton(
        for day: WeeklyPracticeDay,
        fillsAvailableWidth: Bool
    ) -> some View {
        let isSelected = day.id == selectedDayID
        let isSelectable = WeeklyPracticeSelectionPolicy.canSelect(
            day: day,
            referenceDate: referenceDate
        )
        let presentation = WeeklyPracticeDayDetailPresentation(
            day: day,
            referenceDate: referenceDate,
            dateLabelFormatter: dateLabelFormatter
        )
        let barPresentation = WeeklyPracticeBarPresentation(
            day: day,
            referenceDate: referenceDate
        )

        return Button {
            selectDay(day)
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CheckpointTheme.heroSuccess.opacity(0.12))
                        .matchedGeometryEffect(
                            id: "weekly-practice-selection",
                            in: selectionNamespace
                        )
                }

                VStack(spacing: 7) {
                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(CheckpointTheme.heroTrack.opacity(isSelectable ? 0.54 : 0.22))
                            .frame(width: 8, height: 54)

                        Capsule()
                            .fill(
                                barColor(
                                    for: barPresentation,
                                    isSelected: isSelected
                                )
                            )
                            .frame(
                                width: 8,
                                height: barPresentation.height(
                                    maximumCount: maximumCount
                                )
                            )
                            .animation(
                                CheckpointMotion.animation(
                                    CheckpointMotion.reveal,
                                    reduceMotion: reduceMotion
                                ),
                                value: barPresentation
                            )
                    }
                    .frame(height: 54, alignment: .bottom)

                    Text(dateLabelFormatter.narrowWeekday(for: day.date))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(labelColor(for: day, isSelected: isSelected))
                }
                .padding(.vertical, 4)
            }
            .frame(
                minWidth: WeeklyPracticeChartLayoutPolicy.minimumDayWidth,
                maxWidth: fillsAvailableWidth ? .infinity : WeeklyPracticeChartLayoutPolicy.minimumDayWidth,
                minHeight: 82
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .disabled(!isSelectable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint(
            isSelectable
                ? (isSelected ? "Selected day." : "Shows this day's details.")
                : "This day is still ahead."
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(day.id)
    }

    private func scrollToSelectedDay(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let selectedDayID else { return }
        if animated {
            withAnimation(CheckpointMotion.change) {
                proxy.scrollTo(selectedDayID, anchor: .center)
            }
        } else {
            proxy.scrollTo(selectedDayID, anchor: .center)
        }
    }

    private func barColor(
        for presentation: WeeklyPracticeBarPresentation,
        isSelected: Bool
    ) -> Color {
        switch presentation.state {
        case .learning, .checkpointOnly:
            return isSelected ? CheckpointTheme.heroText : CheckpointTheme.heroSuccess
        case .inactive:
            return CheckpointTheme.heroTrack.opacity(0.72)
        case .future:
            return CheckpointTheme.heroTrack.opacity(0.28)
        }
    }

    private func labelColor(
        for day: WeeklyPracticeDay,
        isSelected: Bool
    ) -> Color {
        if isSelected {
            return CheckpointTheme.heroText
        }
        return CheckpointTheme.heroMuted.opacity(day.date > referenceDate ? 0.62 : 1)
    }
}

private struct WeeklyPracticeDayDetail: View {
    let presentation: WeeklyPracticeDayDetailPresentation
    let horizontalPadding: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    detailIcon
                    detailCopy
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    detailIcon
                    detailCopy
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CheckpointTheme.heroText.opacity(0.055))
                .stroke(CheckpointTheme.heroDivider, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var detailIcon: some View {
        Image(systemName: presentation.hasActivity ? "chart.bar.fill" : "circle.dashed")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(
                presentation.hasActivity
                    ? CheckpointTheme.heroSuccess
                    : CheckpointTheme.heroMuted
            )
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(CheckpointTheme.heroText.opacity(0.07))
            )
            .accessibilityHidden(true)
    }

    private var detailCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.dateEyebrowText)
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(CheckpointTheme.heroMuted)

            Text(presentation.activityText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)

            if let checkpointText = presentation.checkpointText {
                Text(checkpointText)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ImpactMetricTile: View {
    var label: String
    var value: String
    var detail: String?
    var systemImage: String
    var accessibilityLabel: String? = nil

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

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CheckpointTheme.panel.opacity(0.88))
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            accessibilityLabel
                ?? [label, value, detail]
                    .compactMap { $0 }
                    .joined(separator: ", ")
        )
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
