import Foundation

struct WeeklyPracticeDay: Identifiable, Equatable, Sendable {
    var date: Date
    var questionsAnswered: Int

    var id: Date { date }
}

struct WeeklyImpactDetails: Equatable, Sendable {
    var practiceDays: [WeeklyPracticeDay]
    var earnedBreakMinutes: Int
    var recoveredQuestions: Int
    var activePracticeDays: Int
    var previousWeekQuestions: Int

    var earnedBreakTimeText: String {
        let hours = earnedBreakMinutes / 60
        let minutes = earnedBreakMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    func questionTrendText(currentQuestions: Int) -> String? {
        guard currentQuestions > 0 || previousWeekQuestions > 0 else { return nil }

        let difference = currentQuestions - previousWeekQuestions
        if difference == 0 {
            return "Level with this point last week"
        }
        if previousWeekQuestions == 0 {
            return "A new weekly baseline"
        }

        let noun = abs(difference) == 1 ? "question" : "questions"
        return difference > 0
            ? "\(difference) more \(noun) than this point last week"
            : "\(abs(difference)) fewer \(noun) than this point last week"
    }
}

@MainActor
struct WeeklyMetricsCalculator {
    private let attempts: [CheckpointAttempt]
    private let unlockEvents: [UnlockEvent]
    private let competencies: [TopicCompetency]

    init(
        attempts: [CheckpointAttempt],
        unlockEvents: [UnlockEvent],
        competencies: [TopicCompetency]
    ) {
        self.attempts = attempts
        self.unlockEvents = unlockEvents
        self.competencies = competencies
    }

    private var attemptsThisWeek: [CheckpointAttempt] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return attempts.filter { week.contains($0.createdAt) }
    }

    func summary(
        id: String,
        title: String,
        goalID: Goal.ID?,
        isCurrentGoal: Bool
    ) -> WeeklyMetricsSummary {
        let weeklyAttempts = attemptsThisWeek.filter { attempt in
            guard let goalID else { return true }
            return attempt.goalID == goalID
        }
        let correctAnswers = weeklyAttempts.filter { $0.result == .correct }.count
        let missedAnswers = weeklyAttempts.filter { $0.result != .correct }.count
        let competencies = visibleCompetencies(for: goalID)
        let scopedUnlockEvents = unlockEvents.filter { event in
            guard let goalID else { return true }
            return event.goalID == goalID
        }
        let weeklyUnlockEvents = scopedUnlockEvents.filter { event in
            guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return false }
            return week.contains(event.createdAt)
        }
        let skillHighlights = skillHighlights(for: competencies)

        return WeeklyMetricsSummary(
            id: id,
            title: title,
            questionsAnswered: weeklyAttempts.count,
            correctAnswers: correctAnswers,
            missedAnswers: missedAnswers,
            checkpointStreakDays: checkpointStreakDays(for: scopedUnlockEvents),
            checkpointsCleared: weeklyUnlockEvents.count,
            strongestSkill: skillHighlights.strongest,
            reviewSkill: skillHighlights.review,
            isCurrentGoal: isCurrentGoal
        )
    }

    func impactDetails(
        goalID: Goal.ID?,
        asOf now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyImpactDetails {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
              let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start) else {
            return WeeklyImpactDetails(
                practiceDays: [],
                earnedBreakMinutes: 0,
                recoveredQuestions: 0,
                activePracticeDays: 0,
                previousWeekQuestions: 0
            )
        }

        let elapsedThisWeek = now.timeIntervalSince(week.start)
        let previousComparisonEnd = min(
            previousWeekStart.addingTimeInterval(elapsedThisWeek),
            week.start
        )
        let previousComparablePeriod = DateInterval(
            start: previousWeekStart,
            end: previousComparisonEnd
        )
        let scopedAttempts = attempts.filter { attempt in
            guard let goalID else { return true }
            return attempt.goalID == goalID
        }
        let weeklyAttempts = scopedAttempts.filter { week.contains($0.createdAt) }
        let weeklyUnlockEvents = unlockEvents.filter { event in
            week.contains(event.createdAt) && (goalID == nil || event.goalID == goalID)
        }
        let practiceDays = (0..<7).compactMap { offset -> WeeklyPracticeDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: week.start) else {
                return nil
            }
            let day = calendar.startOfDay(for: date)
            let count = weeklyAttempts.lazy.filter {
                calendar.isDate($0.createdAt, inSameDayAs: day)
            }.count
            return WeeklyPracticeDay(date: day, questionsAnswered: count)
        }

        return WeeklyImpactDetails(
            practiceDays: practiceDays,
            earnedBreakMinutes: weeklyUnlockEvents.reduce(0) { $0 + $1.minutes },
            recoveredQuestions: recoveredQuestionCount(
                in: scopedAttempts,
                during: week
            ),
            activePracticeDays: Set(
                weeklyAttempts.map { calendar.startOfDay(for: $0.createdAt) }
            ).count,
            previousWeekQuestions: scopedAttempts.lazy.filter {
                previousComparablePeriod.contains($0.createdAt)
            }.count
        )
    }

    private func recoveredQuestionCount(
        in attempts: [CheckpointAttempt],
        during interval: DateInterval
    ) -> Int {
        let orderedAttempts = attempts.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
        var unresolvedQuestionIDs = Set<CheckpointQuestion.ID>()
        var recoveredQuestionIDs = Set<CheckpointQuestion.ID>()

        for attempt in orderedAttempts {
            if attempt.result == .correct {
                if interval.contains(attempt.createdAt),
                   unresolvedQuestionIDs.contains(attempt.questionID) {
                    recoveredQuestionIDs.insert(attempt.questionID)
                }
                unresolvedQuestionIDs.remove(attempt.questionID)
            } else {
                unresolvedQuestionIDs.insert(attempt.questionID)
                recoveredQuestionIDs.remove(attempt.questionID)
            }
        }

        return recoveredQuestionIDs.count
    }

    private func checkpointStreakDays(for unlockEvents: [UnlockEvent]) -> Int {
        let calendar = Calendar.current
        let clearedDays = Set(unlockEvents.map { calendar.startOfDay(for: $0.createdAt) })
        guard !clearedDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        guard var cursor = clearedDays.contains(today) ? today : (clearedDays.contains(yesterday) ? yesterday : nil) else {
            return 0
        }

        var streak = 0
        while clearedDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }

        return streak
    }

    private func skillHighlights(
        for competencies: [TopicCompetency]
    ) -> (strongest: String?, review: String?) {
        let practicedCompetencies = competencies.filter { $0.attempts > 0 }
        guard practicedCompetencies.count > 1 else { return (nil, nil) }

        let sortedCompetencies = practicedCompetencies.sorted { lhs, rhs in
            if lhs.masteryPercent == rhs.masteryPercent {
                return lhs.topic.localizedCaseInsensitiveCompare(rhs.topic) == .orderedAscending
            }

            return lhs.masteryPercent < rhs.masteryPercent
        }

        guard let review = sortedCompetencies.first,
              let strongest = sortedCompetencies.last,
              review.masteryPercent < strongest.masteryPercent else {
            return (nil, nil)
        }

        return (strongest.topic, review.topic)
    }

    private func visibleCompetencies(for goalID: Goal.ID?) -> [TopicCompetency] {
        guard let goalID else {
            return SkillMapReconciler.mergedCompetenciesForDisplay(competencies)
        }

        return SkillMapReconciler.mergedCompetenciesForDisplay(
            competencies.filter { $0.goalID == goalID || $0.goalID == nil }
        )
    }
}
