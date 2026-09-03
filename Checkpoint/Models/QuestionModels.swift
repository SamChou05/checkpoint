import Foundation

enum QuestionFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case shortAnswer = "Short Answer"
    case multipleChoice = "Multiple Choice"
    case codeTrace = "Code Trace"
    case reflection = "Reflection"

    var id: String { rawValue }
}

enum QuestionStatus: String, Codable, Sendable {
    case new
    case correct
    case incorrect
    case skipped
    case due
    case retired
}

enum QuestionReportReason: String, Codable, Sendable {
    case tooEasy = "Too Easy"
    case tooHard = "Too Hard"
    case confusing = "Confusing"
    case wrongAnswer = "Wrong Answer"
    case irrelevant = "Irrelevant"
}

enum IssueReportCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case generalFeedback = "General feedback"
    case questionIssue = "Question issue"
    case appBlocking = "App protection"
    case goalSetup = "Goal setup"
    case membership = "Plan and billing"

    var id: String { rawValue }
}

enum QuestionBatchState: String, Codable, Sendable {
    case idle
    case generating
    case ready
    case failed
}

enum AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic = "Automatic"
    case appleFoundation = "Apple Foundation"
    case backend = "Backend"
    case localTemplates = "Local Templates"

    var id: String { rawValue }
}

struct CheckpointQuestion: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var remoteID: String?
    var goalID: Goal.ID
    var prompt: String
    var expectedAnswer: String
    var choices: [String]
    var explanation: String
    var topic: String
    var skillID: SkillMapTopic.ID?
    var objectiveID: SkillMapObjective.ID?
    var objective: String?
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
        remoteID: String? = nil,
        goalID: Goal.ID,
        prompt: String,
        expectedAnswer: String,
        choices: [String] = [],
        explanation: String,
        topic: String,
        skillID: SkillMapTopic.ID? = nil,
        objectiveID: SkillMapObjective.ID? = nil,
        objective: String? = nil,
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
        self.remoteID = remoteID
        self.goalID = goalID
        self.prompt = prompt
        self.expectedAnswer = expectedAnswer
        self.choices = choices
        self.explanation = explanation
        self.topic = topic
        self.skillID = skillID
        self.objectiveID = objectiveID
        self.objective = objective
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
        case remoteID
        case goalID
        case prompt
        case expectedAnswer
        case choices
        case explanation
        case topic
        case skillID
        case objectiveID
        case objective
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
        remoteID = try container.decodeIfPresent(String.self, forKey: .remoteID)
        goalID = try container.decode(UUID.self, forKey: .goalID)
        prompt = try container.decode(String.self, forKey: .prompt)
        expectedAnswer = try container.decode(String.self, forKey: .expectedAnswer)
        choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
        explanation = try container.decode(String.self, forKey: .explanation)
        topic = try container.decode(String.self, forKey: .topic)
        skillID = try container.decodeIfPresent(SkillMapTopic.ID.self, forKey: .skillID)
        objectiveID = try container.decodeIfPresent(SkillMapObjective.ID.self, forKey: .objectiveID)
        objective = try container.decodeIfPresent(String.self, forKey: .objective)
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

struct QuestionBankSyncIntent: Identifiable, Codable, Equatable, Sendable {
    var goalID: Goal.ID
    /// Stable local content/weight revision used for stale-context checks.
    var contextRevision: String
    /// Per-fill-cycle revision sent to the server so an exhausted finite bank
    /// is never reopened when the same local context later needs inventory.
    var bankContextRevision: String?
    var bankID: String?
    var claimID: String
    var desiredCount: Int
    var lowWatermark: Int
    /// A server-side terminal reason for this exact bank cycle. The intent stays
    /// persisted but dormant until its generation context changes or the user retries.
    var generationBlockedReason: String?
    /// Counts consecutive completed server banks that produced no locally usable
    /// inventory. Optional so snapshots written by older builds continue to decode.
    var emptyFillCycleRetryCount: Int?
    var createdAt: Date
    var lastAttemptAt: Date?

    var id: Goal.ID { goalID }

    init(
        goalID: Goal.ID,
        contextRevision: String,
        bankContextRevision: String? = nil,
        bankID: String? = nil,
        claimID: String = UUID().uuidString,
        desiredCount: Int,
        lowWatermark: Int,
        generationBlockedReason: String? = nil,
        emptyFillCycleRetryCount: Int? = 0,
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil
    ) {
        self.goalID = goalID
        self.contextRevision = contextRevision
        self.bankContextRevision = bankContextRevision ?? contextRevision
        self.bankID = bankID
        self.claimID = claimID
        self.desiredCount = desiredCount
        self.lowWatermark = lowWatermark
        self.generationBlockedReason = generationBlockedReason
        self.emptyFillCycleRetryCount = emptyFillCycleRetryCount
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
    }
}

struct QuestionQualityReport: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var questionID: CheckpointQuestion.ID
    var goalID: Goal.ID
    var prompt: String
    var reason: QuestionReportReason
    var note: String
    var createdAt = Date()
}

struct UserIssueReport: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var goalID: Goal.ID?
    var goalTitle: String
    var category: IssueReportCategory
    var message: String
    var contact: String
    var createdAt = Date()
}

struct QuestionGenerationTrace: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var phase: String
    var goalID: Goal.ID?
    var goalTitle: String
    var providerPreference: AIProviderKind
    var resolvedProvider: AIProviderKind
    var usedFallback: Bool
    var targetCount: Int
    var existingQuestionCount: Int
    var reportedQuestionCount: Int
    var competencyCount: Int
    var minimumDifficulty: Int
    var generatedQuestionCount: Int
    var addedQuestionCount: Int
    var retiredQuestionCount: Int
    var duration: TimeInterval
    var sourcePrompt: String
    var failure: QuestionGenerationFailureKind?
    var errorMessage: String?
    var questions: [QuestionGenerationQuestionPreview]
}

struct QuestionGenerationQuestionPreview: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var prompt: String
    var expectedAnswer: String
    var choices: [String]
    var explanation: String
    var topic: String
    var difficulty: Int
}
