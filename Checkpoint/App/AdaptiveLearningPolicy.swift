import Foundation

struct AdaptiveMistake: Encodable, Equatable, Sendable {
    let objectiveID: SkillMapObjective.ID
    let prompt: String
    let selectedAnswer: String
    let expectedAnswer: String
}

struct AdaptiveSkillPlan: Encodable, Equatable, Sendable {
    let skillID: SkillMapTopic.ID
    let targetDifficulty: Int
    let evidenceCount: Int
    let recentAccuracyPercent: Int?
    let focusObjectiveIDs: [SkillMapObjective.ID]
    let recentMistakes: [AdaptiveMistake]

    // New answer text does not rotate a bank on every tap. A changed teaching
    // priority or difficulty does; replenishment still receives recent evidence.
    var revisionKey: String {
        "\(skillID.uuidString):\(targetDifficulty):"
            + focusObjectiveIDs.map(\.uuidString).sorted().joined(separator: ",")
    }
}

enum AdaptiveLearningPolicy {
    static let evidenceMaximumAge: TimeInterval = 30 * 24 * 60 * 60

    static func distinctAttempts(
        for skill: SkillMapTopic,
        goalID: Goal.ID,
        attempts: [CheckpointAttempt],
        now: Date = Date()
    ) -> [CheckpointAttempt] {
        let objectiveIDs = Set(skill.objectives.map(\.id))
        var seenQuestions = Set<CheckpointQuestion.ID>()
        return attempts
            .filter {
                $0.goalID == goalID && $0.skillID == skill.id
                    && $0.questionVerificationVersion == 1
                    && $0.createdAt <= now
                    && $0.createdAt >= now.addingTimeInterval(-evidenceMaximumAge)
            }
            .sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.createdAt < $1.createdAt
            }
            .compactMap { attempt in
                var normalized = attempt
                if normalized.objectiveID == nil, skill.objectives.count == 1 {
                    normalized.objectiveID = skill.objectives.first?.id
                }
                guard let objectiveID = normalized.objectiveID,
                      objectiveIDs.contains(objectiveID),
                      seenQuestions.insert(attempt.questionID).inserted else { return nil }
                // The first answer to each question is evidence of transfer.
                // Memorizing its revealed answer must not advance the learner.
                return normalized
            }
            .suffix(60)
            .map { $0 }
    }

    static func plans(
        for goal: Goal,
        attempts: [CheckpointAttempt],
        now: Date = Date()
    ) -> [AdaptiveSkillPlan] {
        (goal.derivedSkillMap?.topics ?? []).map { skill in
            let evidence = distinctAttempts(for: skill, goalID: goal.id, attempts: attempts, now: now)
            let floor = goal.minimumQuestionDifficulty
            var target = max(floor, evidence.first?.questionDifficulty ?? floor)
            var window: [CheckpointAttempt] = []
            for attempt in evidence {
                guard (attempt.questionDifficulty ?? floor) >= target else { continue }
                window.append(attempt)
                window = Array(window.suffix(5))
                let recentFour = window.suffix(4)
                if recentFour.count == 4,
                   recentFour.filter({ $0.result != .correct }).count >= 3 {
                    target = max(floor, target - 1)
                    window = []
                } else if window.count == 5,
                          window.filter({ $0.result == .correct }).count >= 4,
                          Set(window.compactMap(\.objectiveID)).count >= min(2, skill.objectives.count) {
                    target = min(5, target + 1)
                    window = []
                }
            }

            let recent = Array(evidence.suffix(12))
            let accuracy = recent.isEmpty ? nil : Int(
                (Double(recent.filter { $0.result == .correct }.count) / Double(recent.count) * 100).rounded()
            )
            // One latest first-answer result per objective identifies what still
            // needs teaching, independently of the lifetime accuracy counter.
            var seenObjectives = Set<SkillMapObjective.ID>()
            let mistakes = recent.reversed().compactMap { attempt -> AdaptiveMistake? in
                guard let objectiveID = attempt.objectiveID,
                      seenObjectives.insert(objectiveID).inserted,
                      attempt.result != .correct else { return nil }
                return AdaptiveMistake(
                    objectiveID: objectiveID,
                    prompt: QuestionText.clipped(attempt.prompt, maxLength: 360),
                    selectedAnswer: QuestionText.clipped(attempt.answer, maxLength: 280),
                    expectedAnswer: QuestionText.clipped(attempt.reviewSnapshot?.referenceAnswer ?? "", maxLength: 280)
                )
            }
            return AdaptiveSkillPlan(
                skillID: skill.id,
                targetDifficulty: min(5, max(floor, target)),
                evidenceCount: recent.count,
                recentAccuracyPercent: accuracy,
                focusObjectiveIDs: mistakes.map(\.objectiveID),
                recentMistakes: Array(mistakes.prefix(3))
            )
        }
    }
}
