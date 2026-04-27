import Foundation

enum GoalCategory: String, Codable, CaseIterable, Identifiable {
    case codingInterview = "Coding Interview"
    case examPrep = "Exam Prep"
    case languageLearning = "Language Learning"
    case fitness = "Fitness"
    case writing = "Writing"
    case custom = "Custom"

    var id: String { rawValue }
}

enum QuestionFormat: String, Codable, CaseIterable, Identifiable {
    case shortAnswer = "Short Answer"
    case multipleChoice = "Multiple Choice"
    case codeTrace = "Code Trace"
    case reflection = "Reflection"

    var id: String { rawValue }
}

enum QuestionStatus: String, Codable {
    case new
    case correct
    case incorrect
    case skipped
    case due
    case retired
}

enum AnswerResult: String, Codable, CaseIterable, Identifiable {
    case correct = "Correct"
    case partial = "Partial"
    case incorrect = "Incorrect"
    case unclear = "Unclear"

    var id: String { rawValue }
}

enum QuestionReportReason: String, Codable, CaseIterable, Identifiable {
    case tooEasy = "Too Easy"
    case tooHard = "Too Hard"
    case confusing = "Confusing"
    case wrongAnswer = "Wrong Answer"
    case irrelevant = "Irrelevant"

    var id: String { rawValue }
}

enum QuestionBatchState: String, Codable {
    case idle
    case generating
    case ready
    case failed
}

enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case appleFoundation = "Apple Foundation"
    case backend = "Backend"
    case localTemplates = "Local Templates"

    var id: String { rawValue }
}

struct Goal: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var deadline: Date
    var category: GoalCategory
    var currentLevel: String
    var focusAreas: String
    var preferredQuestionStyle: QuestionFormat
    var createdAt = Date()
}

struct CheckpointQuestion: Identifiable, Codable, Equatable {
    var id = UUID()
    var goalID: Goal.ID
    var prompt: String
    var expectedAnswer: String
    var choices: [String]
    var explanation: String
    var topic: String
    var difficulty: Int
    var format: QuestionFormat
    var status: QuestionStatus = .new
    var timesAsked: Int = 0
    var timesCorrect: Int = 0
    var lastAskedAt: Date?
    var nextReviewAt: Date?
    var sourcePrompt: String

    init(
        id: UUID = UUID(),
        goalID: Goal.ID,
        prompt: String,
        expectedAnswer: String,
        choices: [String] = [],
        explanation: String,
        topic: String,
        difficulty: Int,
        format: QuestionFormat,
        status: QuestionStatus = .new,
        timesAsked: Int = 0,
        timesCorrect: Int = 0,
        lastAskedAt: Date? = nil,
        nextReviewAt: Date? = nil,
        sourcePrompt: String
    ) {
        self.id = id
        self.goalID = goalID
        self.prompt = prompt
        self.expectedAnswer = expectedAnswer
        self.choices = choices
        self.explanation = explanation
        self.topic = topic
        self.difficulty = difficulty
        self.format = format
        self.status = status
        self.timesAsked = timesAsked
        self.timesCorrect = timesCorrect
        self.lastAskedAt = lastAskedAt
        self.nextReviewAt = nextReviewAt
        self.sourcePrompt = sourcePrompt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case goalID
        case prompt
        case expectedAnswer
        case choices
        case explanation
        case topic
        case difficulty
        case format
        case status
        case timesAsked
        case timesCorrect
        case lastAskedAt
        case nextReviewAt
        case sourcePrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        goalID = try container.decode(UUID.self, forKey: .goalID)
        prompt = try container.decode(String.self, forKey: .prompt)
        expectedAnswer = try container.decode(String.self, forKey: .expectedAnswer)
        choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
        explanation = try container.decode(String.self, forKey: .explanation)
        topic = try container.decode(String.self, forKey: .topic)
        difficulty = try container.decode(Int.self, forKey: .difficulty)
        format = try container.decode(QuestionFormat.self, forKey: .format)
        status = try container.decodeIfPresent(QuestionStatus.self, forKey: .status) ?? .new
        timesAsked = try container.decodeIfPresent(Int.self, forKey: .timesAsked) ?? 0
        timesCorrect = try container.decodeIfPresent(Int.self, forKey: .timesCorrect) ?? 0
        lastAskedAt = try container.decodeIfPresent(Date.self, forKey: .lastAskedAt)
        nextReviewAt = try container.decodeIfPresent(Date.self, forKey: .nextReviewAt)
        sourcePrompt = try container.decodeIfPresent(String.self, forKey: .sourcePrompt) ?? ""
    }
}

struct CheckpointAttempt: Identifiable, Codable, Equatable {
    var id = UUID()
    var questionID: CheckpointQuestion.ID
    var goalID: Goal.ID
    var prompt: String
    var answer: String
    var result: AnswerResult
    var unlockMinutes: Int
    var createdAt = Date()
}

struct QuestionQualityReport: Identifiable, Codable, Equatable {
    var id = UUID()
    var questionID: CheckpointQuestion.ID
    var goalID: Goal.ID
    var prompt: String
    var reason: QuestionReportReason
    var note: String
    var createdAt = Date()
}

struct UnlockPolicy: Codable, Equatable {
    var unlockMinutes: Int
    var partialUnlockMinutes: Int
    var emergencyUnlockMinutes: Int
    var unlockOnPartial: Bool

    static let `default` = UnlockPolicy(
        unlockMinutes: 5,
        partialUnlockMinutes: 2,
        emergencyUnlockMinutes: 3,
        unlockOnPartial: true
    )
}

struct TopicCompetency: Identifiable, Codable, Equatable {
    var topic: String
    var estimatedLevel: Double
    var attempts: Int
    var correct: Int
    var partial: Int
    var incorrect: Int
    var currentStreak: Int
    var lastResult: AnswerResult?
    var lastPracticedAt: Date?

    var id: String { topic }

    var masteryPercent: Int {
        guard attempts > 0 else { return 0 }
        let weightedScore = Double(correct) + (Double(partial) * 0.5)
        return min(100, max(0, Int((weightedScore / Double(attempts)) * 100)))
    }

    var displayLevel: String {
        String(format: "%.1f", estimatedLevel)
    }

    static func initial(topic: String, estimatedLevel: Double = 1.5) -> TopicCompetency {
        TopicCompetency(
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

struct UnlockSession: Codable, Equatable {
    var startedAt: Date
    var expiresAt: Date

    var isActive: Bool {
        Date() < expiresAt
    }
}

struct AppSnapshot: Codable {
    var goal: Goal?
    var questions: [CheckpointQuestion]
    var attempts: [CheckpointAttempt]
    var competencies: [TopicCompetency]
    var questionReports: [QuestionQualityReport]?
    var unlockPolicy: UnlockPolicy?
    var questionBatchState: QuestionBatchState?
    var aiProviderPreference: AIProviderKind?
    var lastQuestionProvider: AIProviderKind?
    var backendEndpoint: String?
    var unlockSession: UnlockSession?
    var emergencyPassesRemaining: Int
}

struct AnswerEvaluation: Equatable {
    var result: AnswerResult
    var feedback: String
}

enum AnswerGrader {
    static func evaluate(answer: String, question: CheckpointQuestion) -> AnswerEvaluation {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAnswer.isEmpty else {
            return AnswerEvaluation(result: .unclear, feedback: "No answer entered yet.")
        }

        switch question.format {
        case .reflection:
            return evaluateReflection(trimmedAnswer)
        case .multipleChoice:
            return evaluateMultipleChoice(answer: trimmedAnswer, expectedAnswer: question.expectedAnswer)
        case .shortAnswer, .codeTrace:
            return evaluateObjective(answer: trimmedAnswer, expectedAnswer: question.expectedAnswer)
        }
    }

    private static func evaluateReflection(_ answer: String) -> AnswerEvaluation {
        let wordCount = tokens(in: answer).count

        if wordCount >= 8 {
            return AnswerEvaluation(result: .correct, feedback: "Specific enough to count as progress.")
        }

        if wordCount >= 4 {
            return AnswerEvaluation(result: .partial, feedback: "Close, but it needs a clearer next step.")
        }

        return AnswerEvaluation(result: .incorrect, feedback: "Too vague to count yet.")
    }

    private static func evaluateMultipleChoice(answer: String, expectedAnswer: String) -> AnswerEvaluation {
        if compact(answer) == compact(expectedAnswer) {
            return AnswerEvaluation(result: .correct, feedback: "Correct choice.")
        }

        return AnswerEvaluation(result: .incorrect, feedback: "That choice is not correct yet.")
    }

    private static func evaluateObjective(answer: String, expectedAnswer: String) -> AnswerEvaluation {
        let compactAnswer = compact(answer)
        let compactExpected = compact(expectedAnswer)

        if !compactExpected.isEmpty,
           (compactAnswer == compactExpected || compactAnswer.contains(compactExpected)) {
            return AnswerEvaluation(result: .correct, feedback: "Matches the expected answer.")
        }

        let answerTokens = Set(tokens(in: answer))
        let expectedTokens = Set(tokens(in: expectedAnswer))

        guard !answerTokens.isEmpty, !expectedTokens.isEmpty else {
            return AnswerEvaluation(result: .unclear, feedback: "Not enough signal to grade.")
        }

        let overlap = Double(answerTokens.intersection(expectedTokens).count) / Double(expectedTokens.count)

        if overlap >= 0.65 {
            return AnswerEvaluation(result: .correct, feedback: "Close enough to the expected answer.")
        }

        if overlap >= 0.35 {
            return AnswerEvaluation(result: .partial, feedback: "Partially matches, but misses key details.")
        }

        return AnswerEvaluation(result: .incorrect, feedback: "Does not match the expected answer yet.")
    }

    private static func tokens(in text: String) -> [String] {
        let cleaned = text
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : " "
            }

        return String(cleaned)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    private static func compact(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
        "in", "is", "it", "of", "on", "or", "that", "the", "to", "with"
    ]
}
