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

enum ProgressMomentumState: Equatable {
    case learning
    case checkpointOnly
    case empty
}

enum ProgressMomentumMetricKind: Hashable {
    case checkpointsCleared
    case questionsAnswered
    case accuracy
    case recoveredMisses
    case practiceDays
}

struct ProgressMomentumMetric: Identifiable, Equatable {
    let kind: ProgressMomentumMetricKind
    let valueText: String
    let labelText: String
    let detailText: String?
    let accessibilityText: String

    var id: ProgressMomentumMetricKind { kind }
}

struct ProgressMomentumRevealID: Hashable {
    let goalID: String
    let weekStart: Date?
}

struct ProgressMomentumPresentation: Equatable {
    let state: ProgressMomentumState
    let goalTitle: String
    let primaryMetric: ProgressMomentumMetric?
    let supportingMetrics: [ProgressMomentumMetric]
    let streakBadgeText: String?
    let trendText: String?
    let breakAccessText: String?
    let summaryText: String
    let footerText: String
    let days: [ProgressWeeklyImpactDayPresentation]
    let accessibilityValue: String
    let revealID: ProgressMomentumRevealID

    var hasActivity: Bool { state != .empty }

    init(
        metrics: WeeklyMetricsSummary,
        details: WeeklyImpactDetails,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) {
        goalTitle = metrics.title

        let questions = max(0, metrics.questionsAnswered)
        let correct = min(max(0, metrics.correctAnswers), questions)
        let accuracy = questions > 0
            ? Int(Double(correct) / Double(questions) * 100)
            : nil
        let clears = max(0, metrics.checkpointsCleared)
        let minutes = max(0, details.earnedBreakMinutes)
        let recovered = min(max(0, details.recoveredQuestions), correct)
        let practiceDays = min(max(0, details.activePracticeDays), 7)
        let streak = max(0, metrics.checkpointStreakDays)

        if questions > 0 {
            state = .learning
        } else if clears > 0 {
            state = .checkpointOnly
        } else {
            state = .empty
        }

        breakAccessText = clears > 0 && minutes > 0
            ? "Break access · \(details.earnedBreakTimeText) granted"
            : nil

        let dateLabelFormatter = WeeklyReviewDateLabelFormatter(
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let referenceDay = calendar.startOfDay(for: referenceDate)
        days = details.practiceDays.map { day in
            let normalizedDay = calendar.startOfDay(for: day.date)
            let dayState: ProgressWeeklyImpactDayState
            if normalizedDay > referenceDay {
                dayState = .future
            } else if day.questionsAnswered > 0 || day.checkpointsCleared > 0 {
                dayState = .active
            } else {
                dayState = .inactive
            }

            return ProgressWeeklyImpactDayPresentation(
                id: day.id,
                label: dateLabelFormatter.narrowWeekday(for: day.date)
                    .uppercased(with: locale),
                state: dayState,
                activityLevel: dayState == .active ? 1 : 0
            )
        }

        revealID = ProgressMomentumRevealID(
            goalID: metrics.id,
            weekStart: calendar.dateInterval(
                of: .weekOfYear,
                for: referenceDate
            )?.start
        )

        switch state {
        case .learning:
            primaryMetric = ProgressMomentumMetric(
                kind: .questionsAnswered,
                valueText: "\(questions)",
                labelText: questions == 1 ? "QUESTION ANSWERED" : "QUESTIONS ANSWERED",
                detailText: nil,
                accessibilityText: Self.questionAccessibilityText(questions)
            )
        case .checkpointOnly:
            let label = clears == 1 ? "CHECKPOINT CLEARED" : "CHECKPOINTS CLEARED"
            primaryMetric = ProgressMomentumMetric(
                kind: .checkpointsCleared,
                valueText: "\(clears)",
                labelText: label,
                detailText: nil,
                accessibilityText: Self.checkpointAccessibilityText(clears)
            )
        case .empty:
            primaryMetric = nil
        }

        var metricCandidates: [ProgressMomentumMetric] = []
        if let accuracy {
            metricCandidates.append(
                ProgressMomentumMetric(
                    kind: .accuracy,
                    valueText: "\(accuracy)%",
                    labelText: "ACCURACY",
                    detailText: "\(correct) of \(questions) correct",
                    accessibilityText: "\(accuracy) percent accuracy, \(correct) of \(questions) correct"
                )
            )
        }
        if recovered > 0 {
            let noun = recovered == 1 ? "question" : "questions"
            metricCandidates.append(
                ProgressMomentumMetric(
                    kind: .recoveredMisses,
                    valueText: "\(recovered)",
                    labelText: "RECOVERED",
                    detailText: nil,
                    accessibilityText: "\(recovered) previously missed \(noun) currently correct"
                )
            )
        }
        if clears > 0, primaryMetric?.kind != .checkpointsCleared {
            metricCandidates.append(
                ProgressMomentumMetric(
                    kind: .checkpointsCleared,
                    valueText: "\(clears)",
                    labelText: clears == 1 ? "CHECKPOINT CLEARED" : "CHECKPOINTS CLEARED",
                    detailText: nil,
                    accessibilityText: Self.checkpointAccessibilityText(clears)
                )
            )
        }
        if practiceDays > 0, questions > 0 {
            let noun = practiceDays == 1 ? "day" : "days"
            metricCandidates.append(
                ProgressMomentumMetric(
                    kind: .practiceDays,
                    valueText: "\(practiceDays)",
                    labelText: practiceDays == 1 ? "PRACTICE DAY" : "PRACTICE DAYS",
                    detailText: nil,
                    accessibilityText: "\(practiceDays) practice \(noun) this week"
                )
            )
        }
        supportingMetrics = Array(metricCandidates.prefix(3))

        streakBadgeText = streak > 1 && state != .empty
            ? "\(streak)d current streak"
            : nil
        trendText = questions > 0
            ? details.questionTrendText(currentQuestions: questions)
            : nil

        switch state {
        case .learning where clears > 0:
            let checkpointNoun = clears == 1 ? "checkpoint" : "checkpoints"
            summaryText = "\(questions) \(Self.questionNoun(questions)) answered · \(clears) \(checkpointNoun) cleared"
        case .learning:
            summaryText = "\(questions) \(Self.questionNoun(questions)) answered this week"
        case .checkpointOnly:
            summaryText = clears == 1
                ? "1 checkpoint cleared this week"
                : "\(clears) checkpoints cleared this week"
        case .empty:
            summaryText = "Your next checkpoint starts this week’s momentum."
        }

        var footerParts: [String] = []
        if let breakAccessText {
            footerParts.append(breakAccessText)
        }
        if let trendText {
            footerParts.append(trendText)
        }
        footerText = footerParts.isEmpty
            ? summaryText
            : footerParts.joined(separator: " · ")

        if state == .empty {
            accessibilityValue = "No checkpoint activity this week. " + summaryText
        } else {
            var accessibilityParts: [String] = []
            if let primaryMetric {
                accessibilityParts.append(primaryMetric.accessibilityText)
            }
            accessibilityParts.append(contentsOf: supportingMetrics.map(\.accessibilityText))
            if clears > 0, minutes > 0 {
                accessibilityParts.append(
                    weeklyAccessibleDurationText(minutes: minutes)
                        + " of break access granted this week"
                )
            }
            if streak > 1 {
                accessibilityParts.append(Self.streakAccessibilityText(streak))
            }
            if let trendText {
                accessibilityParts.append(trendText)
            }

            let activeDayDetails = zip(details.practiceDays, days).compactMap {
                day, presentation -> String? in
                guard presentation.state == .active else { return nil }
                let weekday = dateLabelFormatter.wideWeekday(for: day.date)
                var dayParts: [String] = []
                if day.questionsAnswered > 0 {
                    dayParts.append(
                        "\(day.questionsAnswered) "
                            + Self.questionNoun(day.questionsAnswered)
                    )
                }
                if day.checkpointsCleared > 0 {
                    let noun = day.checkpointsCleared == 1 ? "checkpoint" : "checkpoints"
                    dayParts.append("\(day.checkpointsCleared) \(noun) cleared")
                }
                if day.checkpointsCleared > 0, day.earnedBreakMinutes > 0 {
                    dayParts.append(
                        weeklyAccessibleDurationText(
                            minutes: day.earnedBreakMinutes
                        )
                            + " of break access granted"
                    )
                }
                guard !dayParts.isEmpty else { return nil }
                return "\(weekday), " + dayParts.joined(separator: ", ")
            }
            if !activeDayDetails.isEmpty {
                accessibilityParts.append(
                    "Activity by day: " + activeDayDetails.joined(separator: "; ")
                )
            }
            accessibilityValue = accessibilityParts.joined(separator: ". ") + "."
        }
    }

    private static func questionNoun(_ count: Int) -> String {
        count == 1 ? "question" : "questions"
    }

    private static func questionAccessibilityText(_ count: Int) -> String {
        "\(count) \(questionNoun(count)) answered this week"
    }

    private static func checkpointAccessibilityText(_ count: Int) -> String {
        let noun = count == 1 ? "checkpoint" : "checkpoints"
        return "\(count) \(noun) cleared this week"
    }

    private static func streakAccessibilityText(_ count: Int) -> String {
        "\(count)-day checkpoint streak"
    }
}

enum ProgressMomentumMotionStyle: Hashable {
    case animated
    case identity
}

struct ProgressMomentumMotionPolicy {
    static let dayStagger: TimeInterval = 0.045

    let style: ProgressMomentumMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var updateAnimation: Animation? {
        style == .identity ? nil : CheckpointMotion.change
    }

    func revealAnimation(dayIndex: Int) -> Animation? {
        guard style == .animated else { return nil }
        return CheckpointMotion.reveal.delay(revealDelay(dayIndex: dayIndex))
    }

    func revealDelay(dayIndex: Int) -> TimeInterval {
        Double(min(max(0, dayIndex), 6)) * Self.dayStagger
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

struct ProgressMomentumCard: View {
    let presentation: ProgressMomentumPresentation
    let reduceMotion: Bool
    let layoutReporter: (@MainActor (ProgressLayoutElement, CGRect) -> Void)?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var primaryMetricSize: CGFloat = 46

    private var motionPolicy: ProgressMomentumMotionPolicy {
        ProgressMomentumMotionPolicy(reduceMotion: reduceMotion)
    }

    init(
        presentation: ProgressMomentumPresentation,
        reduceMotion: Bool,
        layoutReporter: (@MainActor (ProgressLayoutElement, CGRect) -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.reduceMotion = reduceMotion
        self.layoutReporter = layoutReporter
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            CheckpointHeroSurface(
                glowColor: CheckpointTheme.heroSuccess,
                glowOpacity: 0.11,
                glowDiameter: 170,
                glowOffset: CGSize(width: 76, height: -92),
                contentPadding: 17
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    primaryOutcome
                    ProgressMomentumActivityRail(
                        days: presentation.days,
                        replayID: presentation.revealID,
                        reduceMotion: reduceMotion
                    )

                    if !presentation.supportingMetrics.isEmpty {
                        supportingMetrics
                    }

                    footer
                }
            }
        }
        .buttonStyle(CheckpointPressButtonStyle(role: .surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week for \(presentation.goalTitle)")
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint("Opens this goal’s current week and weekly archive.")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("THIS WEEK")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(CheckpointTheme.heroSuccess)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Spacer(minLength: 4)

            if let streakBadgeText = presentation.streakBadgeText {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Label(
                            compactStreakBadgeText(streakBadgeText),
                            systemImage: "flame.fill"
                        )
                    } else {
                        Text(streakBadgeText.uppercased())
                    }
                }
                .font(.caption2.weight(.bold))
                .tracking(0.45)
                .foregroundStyle(CheckpointTheme.heroSuccess)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    CheckpointTheme.heroSuccess.opacity(0.12),
                    in: Capsule()
                )
                .contentTransition(.numericText())
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroSuccess)
                .accessibilityHidden(true)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var primaryOutcome: some View {
        Group {
            if let metric = presentation.primaryMetric {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 3) {
                            primaryValue(metric)
                            primaryLabel(metric)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            primaryValue(metric)
                            primaryLabel(metric)
                        }
                    }
                }
                .animation(motionPolicy.updateAnimation, value: metric)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No checkpoint activity yet")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(CheckpointTheme.heroText)

                    Text("READY FOR THIS WEEK’S FIRST SIGNAL")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .background {
            if let layoutReporter {
                GeometryReader { proxy in
                    let frame = proxy.frame(
                        in: .named(progressLayoutCoordinateSpaceName)
                    )

                    Color.clear
                        .onAppear {
                            layoutReporter(.momentumPrimaryOutcome, frame)
                        }
                        .onChange(of: frame) { _, updatedFrame in
                            layoutReporter(.momentumPrimaryOutcome, updatedFrame)
                        }
                }
            }
        }
    }

    private func primaryValue(_ metric: ProgressMomentumMetric) -> some View {
        Text(metric.valueText)
            .font(.system(size: primaryMetricSize, weight: .bold, design: .rounded))
            .foregroundStyle(CheckpointTheme.heroText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .contentTransition(.numericText())
    }

    private func primaryLabel(_ metric: ProgressMomentumMetric) -> some View {
        Text(metric.labelText)
            .font(.caption.weight(.bold))
            .tracking(0.75)
            .foregroundStyle(CheckpointTheme.heroMuted)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var supportingMetrics: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(
                        Array(presentation.supportingMetrics.enumerated()),
                        id: \.element.id
                    ) { index, metric in
                        if index > 0 {
                            Divider()
                                .overlay(CheckpointTheme.heroDivider)
                        }

                        accessibilityMetricRow(metric)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(
                        Array(presentation.supportingMetrics.enumerated()),
                        id: \.element.id
                    ) { index, metric in
                        if index > 0 {
                            Rectangle()
                                .fill(CheckpointTheme.heroDivider)
                                .frame(width: 1, height: 40)
                                .accessibilityHidden(true)
                        }

                        compactMetric(metric)
                    }
                }
            }
        }
        .padding(.top, 1)
        .animation(motionPolicy.updateAnimation, value: presentation.supportingMetrics)
    }

    private func compactMetric(_ metric: ProgressMomentumMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.valueText)
                .font(.headline.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())

            Text(metric.labelText)
                .font(.caption2.weight(.bold))
                .tracking(0.4)
                .foregroundStyle(CheckpointTheme.heroMuted)
                .lineLimit(metric.labelText.contains(" ") ? 2 : 1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
    }

    private func accessibilityMetricRow(_ metric: ProgressMomentumMetric) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(metric.valueText)
                .font(.title3.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.labelText)
                    .font(.caption.weight(.bold))
                    .tracking(0.45)
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if let detailText = metric.detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(presentation.footerText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.heroMuted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())

            Spacer(minLength: 0)
        }
        .padding(.top, 1)
        .animation(motionPolicy.updateAnimation, value: presentation.footerText)
    }

    private func compactStreakBadgeText(_ text: String) -> String {
        text.split(separator: " ").first.map(String.init)?.uppercased() ?? text
    }
}

struct ProgressMomentumActivityRail: View {
    let days: [ProgressWeeklyImpactDayPresentation]
    let replayID: ProgressMomentumRevealID
    let reduceMotion: Bool
    let renderStyleReporter: (@MainActor (ProgressMomentumMotionStyle) -> Void)?

    init(
        days: [ProgressWeeklyImpactDayPresentation],
        replayID: ProgressMomentumRevealID,
        reduceMotion: Bool,
        renderStyleReporter: (@MainActor (ProgressMomentumMotionStyle) -> Void)? = nil
    ) {
        self.days = days
        self.replayID = replayID
        self.reduceMotion = reduceMotion
        self.renderStyleReporter = renderStyleReporter
    }

    var body: some View {
        ProgressMomentumActivityRailScope(
            days: days,
            replayID: replayID,
            reduceMotion: reduceMotion,
            renderStyleReporter: renderStyleReporter
        )
        .id(replayID)
    }
}

private struct ProgressMomentumActivityRailScope: View {
    let days: [ProgressWeeklyImpactDayPresentation]
    let replayID: ProgressMomentumRevealID
    let reduceMotion: Bool
    let renderStyleReporter: (@MainActor (ProgressMomentumMotionStyle) -> Void)?

    @State private var suppressesRevealForScope: Bool

    init(
        days: [ProgressWeeklyImpactDayPresentation],
        replayID: ProgressMomentumRevealID,
        reduceMotion: Bool,
        renderStyleReporter: (@MainActor (ProgressMomentumMotionStyle) -> Void)?
    ) {
        self.days = days
        self.replayID = replayID
        self.reduceMotion = reduceMotion
        self.renderStyleReporter = renderStyleReporter
        _suppressesRevealForScope = State(initialValue: reduceMotion)
    }

    private var renderStyle: ProgressMomentumMotionStyle {
        suppressesRevealForScope ? .identity : .animated
    }

    var body: some View {
        ProgressMomentumActivityRailBars(
            days: days,
            replayID: replayID,
            reduceMotion: reduceMotion,
            startsRevealed: suppressesRevealForScope
        )
        .onAppear {
            renderStyleReporter?(renderStyle)
        }
        .id(renderStyle)
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            guard shouldReduceMotion, !suppressesRevealForScope else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                suppressesRevealForScope = true
            }
        }
    }
}

private struct ProgressMomentumActivityRailBars: View {
    let days: [ProgressWeeklyImpactDayPresentation]
    let replayID: ProgressMomentumRevealID
    let reduceMotion: Bool

    @State private var isRevealed: Bool

    init(
        days: [ProgressWeeklyImpactDayPresentation],
        replayID: ProgressMomentumRevealID,
        reduceMotion: Bool,
        startsRevealed: Bool
    ) {
        self.days = days
        self.replayID = replayID
        self.reduceMotion = reduceMotion
        _isRevealed = State(initialValue: startsRevealed || reduceMotion)
    }

    private var motionPolicy: ProgressMomentumMotionPolicy {
        ProgressMomentumMotionPolicy(reduceMotion: reduceMotion)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(trackColor(for: day.state))
                            .frame(height: 24)

                        Capsule()
                            .fill(fillColor(for: day.state))
                            .frame(height: renderedMarkHeight(for: day))
                            .animation(
                                motionPolicy.updateAnimation,
                                value: day.activityLevel
                            )
                            .animation(
                                motionPolicy.revealAnimation(dayIndex: index),
                                value: isRevealed
                            )
                    }
                    .frame(maxWidth: 8)

                    Text(day.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(dayLabelColor(for: day.state))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
        .task(id: replayID) {
            if reduceMotion {
                isRevealed = true
                return
            }

            isRevealed = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            isRevealed = true
        }
    }

    private func renderedMarkHeight(
        for day: ProgressWeeklyImpactDayPresentation
    ) -> CGFloat {
        guard day.state == .active else { return 3 }
        let revealFraction = reduceMotion || isRevealed ? 1.0 : 0.0
        return 3 + (21 * CGFloat(day.activityLevel) * revealFraction)
    }

    private func dayLabelColor(for state: ProgressWeeklyImpactDayState) -> Color {
        switch state {
        case .active:
            CheckpointTheme.heroText
        case .inactive:
            CheckpointTheme.heroMuted
        case .future:
            CheckpointTheme.heroMuted.opacity(0.7)
        }
    }

    private func trackColor(for state: ProgressWeeklyImpactDayState) -> Color {
        switch state {
        case .active, .inactive:
            CheckpointTheme.heroTrack.opacity(0.52)
        case .future:
            CheckpointTheme.heroTrack.opacity(0.22)
        }
    }

    private func fillColor(for state: ProgressWeeklyImpactDayState) -> Color {
        switch state {
        case .active:
            CheckpointTheme.heroSuccess
        case .inactive:
            CheckpointTheme.heroTrack.opacity(0.72)
        case .future:
            CheckpointTheme.heroTrack.opacity(0.28)
        }
    }
}
