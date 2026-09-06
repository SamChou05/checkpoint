import Foundation

enum AnswerResult: String, Codable, CaseIterable, Identifiable, Sendable {
    case correct = "Correct"
    case partial = "Partial"
    case incorrect = "Incorrect"
    case unclear = "Unclear"

    var id: String { rawValue }
}

enum CheckpointSessionSource: Sendable {
    case manual
    case blockedApp
}

enum CheckpointSessionPurpose: String, Codable, Sendable {
    case temporaryUnlock
    case preview
    case stopBlocking
}

struct CheckpointAttemptReviewSnapshot: Codable, Equatable, Sendable {
    let topic: String
    let format: QuestionFormat
    let referenceAnswer: String?
    let explanation: String
}

struct CheckpointAttempt: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var questionID: CheckpointQuestion.ID
    var goalID: Goal.ID
    var skillID: SkillMapTopic.ID? = nil
    var objectiveID: SkillMapObjective.ID? = nil
    var questionDifficulty: Int? = nil
    var questionVerificationVersion: Int? = nil
    var prompt: String
    var answer: String
    var result: AnswerResult
    var unlockMinutes: Int
    var reviewSnapshot: CheckpointAttemptReviewSnapshot? = nil
    var createdAt = Date()
}

struct FocusWin: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var goalID: Goal.ID
    var note: String
    var loggedAt: Date

    init(
        id: UUID = UUID(),
        goalID: Goal.ID,
        note: String,
        loggedAt: Date = Date()
    ) {
        self.id = id
        self.goalID = goalID
        self.note = note
        self.loggedAt = loggedAt
    }
}

struct WeeklyMetricsSummary: Identifiable, Equatable, Sendable {
    static let allGoalsID = "all-goals"

    var id: String
    var title: String
    var questionsAnswered: Int
    var correctAnswers: Int
    var missedAnswers: Int
    var checkpointStreakDays: Int
    var checkpointsCleared: Int
    var strongestSkill: String?
    var reviewSkill: String?
    var isCurrentGoal: Bool = false

    var accuracyText: String {
        guard questionsAnswered > 0 else { return "0%" }
        return "\(Int((Double(correctAnswers) / Double(questionsAnswered)) * 100))%"
    }

    var checkpointStreakText: String {
        checkpointStreakDays == 1 ? "1 day" : "\(checkpointStreakDays) days"
    }

    var hasWeeklyReviewActivity: Bool {
        questionsAnswered > 0 || checkpointsCleared > 0 || checkpointStreakDays > 0
    }

    var skillSnapshotSignals: [WeeklySignalInsight] {
        var signals: [WeeklySignalInsight] = []
        if let reviewSkill {
            signals.append(.lowestCurrentEstimate(reviewSkill))
        }
        if let strongestSkill {
            signals.append(.highestCurrentEstimate(strongestSkill))
        }
        return signals
    }

    var weeklySignalInsight: WeeklySignalInsight? {
        guard hasWeeklyReviewActivity else { return nil }

        if missedAnswers > 0, let reviewSkill {
            return .lowestCurrentEstimate(reviewSkill)
        }
        if let strongestSkill {
            return .highestCurrentEstimate(strongestSkill)
        }
        if checkpointsCleared > 0 {
            return .checkpointsCleared(checkpointsCleared)
        }
        if questionsAnswered > 0 {
            return .answersLogged
        }
        if checkpointStreakDays > 0 {
            return .checkpointStreak(checkpointStreakDays)
        }
        return nil
    }
}

enum WeeklySignalInsight: Equatable, Identifiable, Sendable {
    case lowestCurrentEstimate(String)
    case highestCurrentEstimate(String)
    case checkpointsCleared(Int)
    case answersLogged
    case checkpointStreak(Int)

    enum Role: String, Hashable, Sendable {
        case lowestCurrentEstimate
        case highestCurrentEstimate
        case checkpointsCleared
        case answersLogged
        case checkpointStreak
    }

    var id: Role { role }

    var role: Role {
        switch self {
        case .lowestCurrentEstimate:
            .lowestCurrentEstimate
        case .highestCurrentEstimate:
            .highestCurrentEstimate
        case .checkpointsCleared:
            .checkpointsCleared
        case .answersLogged:
            .answersLogged
        case .checkpointStreak:
            .checkpointStreak
        }
    }

    var text: String {
        switch self {
        case let .lowestCurrentEstimate(skill):
            "Lowest current estimate: \(skill)."
        case let .highestCurrentEstimate(skill):
            "Highest current estimate: \(skill)."
        case let .checkpointsCleared(count):
            "\(count) \(count == 1 ? "checkpoint" : "checkpoints") cleared this week."
        case .answersLogged:
            "Your answers are shaping the skill map."
        case let .checkpointStreak(days):
            "Your \(days)-day checkpoint streak is still going."
        }
    }

    var accessibilityLabel: String {
        switch self {
        case let .lowestCurrentEstimate(skill):
            "Lowest current mastery estimate, \(skill)"
        case let .highestCurrentEstimate(skill):
            "Highest current mastery estimate, \(skill)"
        case let .checkpointsCleared(count):
            "\(count) \(count == 1 ? "checkpoint" : "checkpoints") cleared this week"
        case .answersLogged:
            "Answers are shaping the skill map"
        case let .checkpointStreak(days):
            "\(days)-day checkpoint streak"
        }
    }
}

struct CheckpointSession: Identifiable, Equatable, Sendable {
    var id = UUID()
    var questions: [CheckpointQuestion]
    var requiredCorrectAnswers: Int
    var purpose: CheckpointSessionPurpose = .temporaryUnlock

    var unlockThreshold: Int {
        min(questions.count, max(1, requiredCorrectAnswers))
    }

    func hasMetUnlockThreshold(correctAnswerCount: Int) -> Bool {
        correctAnswerCount >= unlockThreshold
    }

    func canStillMeetUnlockThreshold(correctAnswerCount: Int, answeredQuestionCount: Int) -> Bool {
        let remainingQuestions = max(0, questions.count - answeredQuestionCount)
        return correctAnswerCount + remainingQuestions >= unlockThreshold
    }
}

struct ActiveCheckpointRun: Codable, Equatable, Sendable {
    var sessionID: CheckpointSession.ID
    var goalID: Goal.ID
    var questionIDs: [CheckpointQuestion.ID]
    var missedQuestionIDs: Set<CheckpointQuestion.ID>?
    var purpose: CheckpointSessionPurpose
    var startedAt: Date

    init?(session: CheckpointSession, startedAt: Date = Date()) {
        guard let goalID = session.questions.first?.goalID else { return nil }
        sessionID = session.id
        self.goalID = goalID
        questionIDs = session.questions.map(\.id)
        missedQuestionIDs = []
        purpose = session.purpose
        self.startedAt = startedAt
    }
}

struct QuestionLevelRecommendation: Equatable, Sendable {
    var currentQuestionLevel: Int
    var nextLevel: Int
    var accuracyPercent: Int
    var answeredCount: Int
}

enum StopBlockingPolicy {
    static let questionsPerSession = 20
    static let requiredCorrectAnswers = 18
}

enum CheckpointRetryPolicy {
    static let cooldownDuration: TimeInterval = 5 * 60

    static var cooldownDurationText: String {
        formattedDuration(cooldownDuration)
    }

    static func formattedDuration(_ duration: TimeInterval) -> String {
        let remainingSeconds = max(0, Int(ceil(duration)))
        if remainingSeconds >= 60 {
            let minutes = Int(ceil(Double(remainingSeconds) / 60.0))
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }

        return remainingSeconds == 1 ? "1 second" : "\(remainingSeconds) seconds"
    }
}

struct UnlockPolicy: Codable, Equatable, Sendable {
    static let correctAnswerUnlockMinuteOptions = [5, 10, 15, 30]
    static let minimumQuestionsPerSession = 5
    static let maximumQuestionsPerSession = 10
    static let minimumRequiredCorrectAnswers = 4

    var unlockMinutes: Int
    var partialUnlockMinutes: Int
    var unlockOnPartial: Bool
    var questionsPerSession: Int
    var requiredCorrectAnswers: Int
    var minimumQuestionDifficulty: Int

    init(
        unlockMinutes: Int,
        partialUnlockMinutes: Int,
        unlockOnPartial: Bool,
        questionsPerSession: Int,
        requiredCorrectAnswers: Int,
        minimumQuestionDifficulty: Int
    ) {
        self.unlockMinutes = Self.normalizedCorrectAnswerUnlockMinutes(unlockMinutes)
        self.partialUnlockMinutes = Self.normalizedCorrectAnswerUnlockMinutes(partialUnlockMinutes)
        self.unlockOnPartial = unlockOnPartial
        self.questionsPerSession = Self.normalizedQuestionsPerSession(questionsPerSession)
        self.requiredCorrectAnswers = Self.normalizedRequiredCorrectAnswers(
            requiredCorrectAnswers,
            questionsPerSession: self.questionsPerSession
        )
        self.minimumQuestionDifficulty = Self.normalizedQuestionDifficulty(minimumQuestionDifficulty)
    }

    static let `default` = UnlockPolicy(
        unlockMinutes: 30,
        partialUnlockMinutes: 15,
        unlockOnPartial: true,
        questionsPerSession: 5,
        requiredCorrectAnswers: 4,
        minimumQuestionDifficulty: 1
    )

    enum CodingKeys: String, CodingKey {
        case unlockMinutes
        case partialUnlockMinutes
        case unlockOnPartial
        case questionsPerSession
        case requiredCorrectAnswers
        case minimumQuestionDifficulty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedUnlockMinutes = try container.decodeIfPresent(Int.self, forKey: .unlockMinutes) ?? Self.default.unlockMinutes
        unlockMinutes = Self.normalizedCorrectAnswerUnlockMinutes(decodedUnlockMinutes)
        partialUnlockMinutes = Self.normalizedCorrectAnswerUnlockMinutes(
            try container.decodeIfPresent(Int.self, forKey: .partialUnlockMinutes) ?? Self.default.partialUnlockMinutes
        )
        unlockOnPartial = try container.decodeIfPresent(Bool.self, forKey: .unlockOnPartial) ?? Self.default.unlockOnPartial

        let decodedQuestionsPerSession = try container.decodeIfPresent(Int.self, forKey: .questionsPerSession)
        let decodedRequiredCorrectAnswers = try container.decodeIfPresent(Int.self, forKey: .requiredCorrectAnswers)
        questionsPerSession = Self.normalizedQuestionsPerSession(
            decodedQuestionsPerSession ?? decodedRequiredCorrectAnswers ?? Self.default.questionsPerSession
        )

        if decodedQuestionsPerSession == nil {
            requiredCorrectAnswers = Self.normalizedRequiredCorrectAnswers(
                Self.default.requiredCorrectAnswers,
                questionsPerSession: questionsPerSession
            )
        } else {
            requiredCorrectAnswers = Self.normalizedRequiredCorrectAnswers(
                decodedRequiredCorrectAnswers ?? Self.default.requiredCorrectAnswers,
                questionsPerSession: questionsPerSession
            )
        }

        minimumQuestionDifficulty = Self.normalizedQuestionDifficulty(
            try container.decodeIfPresent(Int.self, forKey: .minimumQuestionDifficulty) ?? Self.default.minimumQuestionDifficulty
        )
    }

    static func normalizedCorrectAnswerUnlockMinutes(_ minutes: Int) -> Int {
        if correctAnswerUnlockMinuteOptions.contains(minutes) {
            return minutes
        }

        if let nextOption = correctAnswerUnlockMinuteOptions.first(where: { $0 >= minutes }) {
            return nextOption
        }

        return correctAnswerUnlockMinuteOptions.last ?? minutes
    }

    static func normalizedQuestionsPerSession(_ count: Int) -> Int {
        min(maximumQuestionsPerSession, max(minimumQuestionsPerSession, count))
    }

    static func normalizedRequiredCorrectAnswers(
        _ count: Int,
        questionsPerSession: Int
    ) -> Int {
        let normalizedQuestionCount = normalizedQuestionsPerSession(questionsPerSession)
        return min(
            normalizedQuestionCount,
            max(minimumRequiredCorrectAnswers, count)
        )
    }

    static func normalizedQuestionDifficulty(_ difficulty: Int) -> Int {
        min(5, max(1, difficulty))
    }
}

struct TopicCompetency: Identifiable, Codable, Equatable, Sendable {
    var goalID: Goal.ID?
    var skillID: SkillMapTopic.ID? = nil
    var topic: String
    var estimatedLevel: Double
    var attempts: Int
    var correct: Int
    var partial: Int
    var incorrect: Int
    var currentStreak: Int
    var lastResult: AnswerResult?
    var lastPracticedAt: Date?

    var id: String {
        if let skillID {
            return "\(goalID?.uuidString ?? "legacy")::skill::\(skillID.uuidString)"
        }

        return "\(goalID?.uuidString ?? "legacy")::topic::\(topic.lowercased())"
    }

    var masteryPercent: Int {
        guard attempts > 0 else { return 0 }
        let weightedScore = Double(correct) + (Double(partial) * 0.5)
        let accuracyScore = weightedScore / Double(attempts)
        let levelScore = (estimatedLevel - 1.0) / 4.0
        let confidence = min(1.0, Double(attempts) / 10.0)
        let mastery = ((accuracyScore * 0.70) + (levelScore * 0.30)) * confidence
        return min(100, max(0, Int(mastery * 100)))
    }

    var displayLevel: String {
        String(format: "%.1f", estimatedLevel)
    }

    static func initial(
        topic: String,
        estimatedLevel: Double = 1.5,
        goalID: Goal.ID? = nil,
        skillID: SkillMapTopic.ID? = nil
    ) -> TopicCompetency {
        TopicCompetency(
            goalID: goalID,
            skillID: skillID,
            topic: topic,
            estimatedLevel: min(5.0, max(1.0, estimatedLevel)),
            attempts: 0,
            correct: 0,
            partial: 0,
            incorrect: 0,
            currentStreak: 0,
            lastResult: nil,
            lastPracticedAt: nil
        )
    }
}

struct UnlockSession: Codable, Equatable, Sendable {
    var startedAt: Date
    var expiresAt: Date

    var isActive: Bool {
        Date() < expiresAt
    }
}

struct UnlockEvent: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var goalID: Goal.ID
    var minutes: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        goalID: Goal.ID,
        minutes: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.goalID = goalID
        self.minutes = minutes
        self.createdAt = createdAt
    }
}
