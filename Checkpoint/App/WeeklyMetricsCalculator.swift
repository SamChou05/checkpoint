import Foundation

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
        guard !practicedCompetencies.isEmpty else { return (nil, nil) }

        let sortedCompetencies = practicedCompetencies.sorted { lhs, rhs in
            if lhs.masteryPercent == rhs.masteryPercent {
                return lhs.topic.localizedCaseInsensitiveCompare(rhs.topic) == .orderedAscending
            }

            return lhs.masteryPercent < rhs.masteryPercent
        }

        return (sortedCompetencies.last?.topic, sortedCompetencies.first?.topic)
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
