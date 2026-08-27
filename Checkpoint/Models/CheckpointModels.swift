import Foundation

enum GoalCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case codingInterview = "Coding Interview"
    case examPrep = "Exam Prep"
    case languageLearning = "Language Learning"
    case fitness = "Fitness"
    case writing = "Writing"
    case custom = "Custom"

    var id: String { rawValue }
}

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

enum AnswerResult: String, Codable, CaseIterable, Identifiable, Sendable {
    case correct = "Correct"
    case partial = "Partial"
    case incorrect = "Incorrect"
    case unclear = "Unclear"

    var id: String { rawValue }
}

enum QuestionReportReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case tooEasy = "Too Easy"
    case tooHard = "Too Hard"
    case confusing = "Confusing"
    case wrongAnswer = "Wrong Answer"
    case irrelevant = "Irrelevant"

    var id: String { rawValue }
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

enum CheckpointSessionSource: Sendable {
    case manual
    case blockedApp
}

enum CheckpointSessionPurpose: String, Codable, Sendable {
    case temporaryUnlock
    case preview
    case stopBlocking
}

enum AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic = "Automatic"
    case appleFoundation = "Apple Foundation"
    case backend = "Backend"
    case localTemplates = "Local Templates"

    var id: String { rawValue }
}

enum MembershipTier: String, Codable, Sendable {
    case starter
    case member

    var displayName: String {
        switch self {
        case .starter:
            return "Free"
        case .member:
            return "Pro"
        }
    }
}

enum MembershipFeature: String, CaseIterable, Identifiable, Sendable {
    case goalProfiles
    case freshQuestionGeneration
    case largerQuestionBank
    case adaptiveStudyAssist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goalProfiles:
            return "Multiple goals"
        case .freshQuestionGeneration:
            return "Ongoing practice"
        case .largerQuestionBank:
            return "More variety"
        case .adaptiveStudyAssist:
            return "Guided review"
        }
    }

    var detail: String {
        switch self {
        case .goalProfiles:
            return "Keep separate goals organized without blending their progress, focus areas, or question levels."
        case .freshQuestionGeneration:
            return "Continue getting new goal-aligned checkpoints after your first Free set has done its job."
        case .largerQuestionBank:
            return "See a broader range of questions so practice stays useful instead of repetitive."
        case .adaptiveStudyAssist:
            return "Bring weak spots back into review so progress stays steady over time."
        }
    }

    static var launchFeatures: [MembershipFeature] {
        [
            .freshQuestionGeneration,
            .goalProfiles,
            .largerQuestionBank,
            .adaptiveStudyAssist
        ]
    }
}

enum MembershipProductID {
    static let monthly = "checkpoint.membership.monthly"
    static let yearly = "checkpoint.membership.yearly"
    static let all = [monthly, yearly]
}

enum ProductLimits {
    static let starterGoalProfileLimit = 1
    static let memberGoalProfileLimit = 5
    static let starterQuestionBankTargetCount = 40
    static let memberQuestionBankTargetCount = 80
    static let autoRefreshThreshold = 10
    static let autoRefreshCooldown: TimeInterval = 6 * 60 * 60
}

enum SkillMapStatus: String, Codable, Equatable, Sendable {
    case suggested
    case reviewed
}

enum SkillMapProvenance: String, Codable, Equatable, Sendable {
    case backendInferred
    case explicitFocusAreas
    case questionTopics
    case userEdited
}

struct SkillMapObjective: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String

    init(
        id: UUID = UUID(),
        name: String
    ) {
        self.id = id
        self.name = SkillMapTopic.normalizedName(name)
    }
}

struct SkillMapTopic: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var aliases: [String]
    var objectives: [SkillMapObjective]

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        objectives: [SkillMapObjective] = []
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.objectives = objectives
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case aliases
        case objectives
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        objectives = try container.decodeIfPresent([SkillMapObjective].self, forKey: .objectives) ?? []
    }

    static func normalizedName(_ rawName: String) -> String {
        rawName
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .:-"))
    }

    static func validatedNames(
        _ rawNames: [String],
        allowedCount: ClosedRange<Int> = 3...6
    ) -> [String]? {
        guard allowedCount.contains(rawNames.count) else { return nil }

        let unsupportedSeparators = CharacterSet(charactersIn: ",;\n")
        let names = rawNames.map(normalizedName)
        guard names.allSatisfy({ name in
            (1...48).contains(name.count) &&
                name.rangeOfCharacter(from: unsupportedSeparators) == nil
        }) else {
            return nil
        }

        let keys = names.map { $0.lowercased() }
        guard Set(keys).count == keys.count else { return nil }
        return names
    }
}

struct GoalSkillMap: Codable, Equatable, Sendable {
    var version: Int
    var provenance: SkillMapProvenance
    var topics: [SkillMapTopic]
    var status: SkillMapStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        topics: [SkillMapTopic],
        status: SkillMapStatus = .suggested,
        version: Int = 1,
        provenance: SkillMapProvenance = .questionTopics,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.version = max(1, version)
        self.provenance = provenance
        self.topics = topics
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case version
        case provenance
        case topics
        case status
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = max(1, try container.decodeIfPresent(Int.self, forKey: .version) ?? 1)
        provenance = try container.decodeIfPresent(SkillMapProvenance.self, forKey: .provenance)
            ?? .questionTopics
        topics = try container.decode([SkillMapTopic].self, forKey: .topics)
        status = try container.decodeIfPresent(SkillMapStatus.self, forKey: .status) ?? .suggested
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var topicNames: [String] {
        topics.map(\.name)
    }
}

enum GoalContextLimits {
    static let maximumDocumentCount = 5
    static let maximumDocumentNameLength = 80
    static let maximumCharactersPerDocument = 12_000
    static let maximumTotalDocumentCharacters = 24_000
    static let minimumUsefulDocumentCharacters = 40
    static let maximumImportFileBytes = 20 * 1_024 * 1_024
}

struct GoalSourceDocument: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var text: String
    var importedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        text: String,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.text = Self.normalizedText(text, limit: GoalContextLimits.maximumCharactersPerDocument)
        self.importedAt = importedAt
    }

    var characterCount: Int {
        text.count
    }

    static func normalizedDocuments(_ documents: [GoalSourceDocument]) -> [GoalSourceDocument] {
        var seenText: Set<String> = []
        var candidates: [GoalSourceDocument] = []

        for document in documents {
            let normalized = GoalSourceDocument(
                id: document.id,
                name: document.name,
                text: document.text,
                importedAt: document.importedAt
            )
            guard normalized.text.count >= GoalContextLimits.minimumUsefulDocumentCharacters else { continue }

            let duplicateKey = normalized.text.lowercased()
            guard seenText.insert(duplicateKey).inserted else { continue }
            candidates.append(normalized)
            if candidates.count >= GoalContextLimits.maximumDocumentCount { break }
        }

        let allocations = fairCharacterAllocations(
            for: candidates.map(\.characterCount),
            totalLimit: GoalContextLimits.maximumTotalDocumentCharacters
        )
        return zip(candidates, allocations).compactMap { document, allocation in
            let text = normalizedText(document.text, limit: allocation)
            guard text.count >= GoalContextLimits.minimumUsefulDocumentCharacters else { return nil }
            return GoalSourceDocument(
                id: document.id,
                name: document.name,
                text: text,
                importedAt: document.importedAt
            )
        }
    }

    private static func normalizedName(_ rawName: String) -> String {
        let collapsed = rawName
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = collapsed.isEmpty ? "Study material" : collapsed
        return String(resolved.prefix(GoalContextLimits.maximumDocumentNameLength))
    }

    private static func normalizedText(_ rawText: String, limit: Int) -> String {
        guard limit > 0 else { return "" }

        let normalizedLineEndings = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        var previousLineWasEmpty = false

        for rawLine in normalizedLineEndings.components(separatedBy: "\n") {
            let line = rawLine
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isEmpty = line.isEmpty
            if isEmpty && previousLineWasEmpty {
                continue
            }
            lines.append(line)
            previousLineWasEmpty = isEmpty
        }

        let normalized = lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }

        let marker = "\n[…truncated…]\n"
        guard limit > marker.count + 2 else {
            return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let availableCharacters = limit - marker.count
        let prefixCount = (availableCharacters * 3) / 5
        let suffixCount = availableCharacters - prefixCount
        return String(normalized.prefix(prefixCount)).trimmingCharacters(in: .whitespacesAndNewlines)
            + marker
            + String(normalized.suffix(suffixCount)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fairCharacterAllocations(for lengths: [Int], totalLimit: Int) -> [Int] {
        guard !lengths.isEmpty else { return [] }
        guard lengths.reduce(0, +) > totalLimit else { return lengths }

        var allocations = Array(repeating: 0, count: lengths.count)
        var unresolved = Set(lengths.indices)
        var remaining = totalLimit

        while !unresolved.isEmpty {
            let share = remaining / unresolved.count
            let smallDocuments = unresolved.filter { lengths[$0] <= share }
            if smallDocuments.isEmpty {
                let orderedIndices = unresolved.sorted()
                let remainder = remaining % orderedIndices.count
                for (offset, index) in orderedIndices.enumerated() {
                    allocations[index] = share + (offset < remainder ? 1 : 0)
                }
                break
            }

            for index in smallDocuments {
                allocations[index] = lengths[index]
                remaining -= lengths[index]
                unresolved.remove(index)
            }
        }

        return allocations
    }
}

struct Goal: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var deadline: Date
    var category: GoalCategory
    var currentLevel: String
    var focusAreas: String
    var sourceDocuments: [GoalSourceDocument]
    var derivedSkillMap: GoalSkillMap?
    var preferredQuestionStyle: QuestionFormat
    var minimumQuestionDifficulty: Int
    var createdAt = Date()

    init(
        id: UUID = UUID(),
        title: String,
        deadline: Date,
        category: GoalCategory,
        currentLevel: String,
        focusAreas: String,
        sourceDocuments: [GoalSourceDocument] = [],
        derivedSkillMap: GoalSkillMap? = nil,
        preferredQuestionStyle: QuestionFormat,
        minimumQuestionDifficulty: Int = UnlockPolicy.default.minimumQuestionDifficulty,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.deadline = deadline
        self.category = category
        self.currentLevel = currentLevel
        self.focusAreas = focusAreas
        self.sourceDocuments = GoalSourceDocument.normalizedDocuments(sourceDocuments)
        self.derivedSkillMap = derivedSkillMap
        self.preferredQuestionStyle = preferredQuestionStyle
        self.minimumQuestionDifficulty = UnlockPolicy.normalizedQuestionDifficulty(minimumQuestionDifficulty)
        self.createdAt = createdAt
    }

    var difficultyLabel: String {
        Self.difficultyLabel(for: minimumQuestionDifficulty)
    }

    static func deadlineDistanceText(until deadline: Date, from now: Date = Date()) -> String {
        let secondsRemaining = Int(deadline.timeIntervalSince(now))
        guard secondsRemaining > 0 else { return "due now" }

        let days = secondsRemaining / (60 * 60 * 24)
        let hours = (secondsRemaining % (60 * 60 * 24)) / (60 * 60)

        if days > 0 {
            return "\(days)d \(hours)h left"
        }

        if hours > 0 {
            return "\(hours)h left"
        }

        return "<1h left"
    }

    static func difficultyLabel(for level: Int) -> String {
        switch UnlockPolicy.normalizedQuestionDifficulty(level) {
        case 1:
            return "Basics"
        case 2:
            return "Foundational"
        case 3:
            return "Intermediate"
        case 4:
            return "Advanced"
        default:
            return "Expert"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case deadline
        case category
        case currentLevel
        case focusAreas
        case sourceDocuments
        case derivedSkillMap
        case preferredQuestionStyle
        case minimumQuestionDifficulty
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        deadline = try container.decode(Date.self, forKey: .deadline)
        category = try container.decode(GoalCategory.self, forKey: .category)
        currentLevel = try container.decode(String.self, forKey: .currentLevel)
        focusAreas = try container.decode(String.self, forKey: .focusAreas)
        sourceDocuments = GoalSourceDocument.normalizedDocuments(
            try container.decodeIfPresent([GoalSourceDocument].self, forKey: .sourceDocuments) ?? []
        )
        derivedSkillMap = try container.decodeIfPresent(GoalSkillMap.self, forKey: .derivedSkillMap)
        preferredQuestionStyle = try container.decode(QuestionFormat.self, forKey: .preferredQuestionStyle)
        minimumQuestionDifficulty = UnlockPolicy.normalizedQuestionDifficulty(
            try container.decodeIfPresent(Int.self, forKey: .minimumQuestionDifficulty)
                ?? UnlockPolicy.default.minimumQuestionDifficulty
        )
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
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
    var contextRevision: String
    var bankID: String?
    var claimID: String
    var desiredCount: Int
    var lowWatermark: Int
    var createdAt: Date
    var lastAttemptAt: Date?

    var id: Goal.ID { goalID }

    init(
        goalID: Goal.ID,
        contextRevision: String,
        bankID: String? = nil,
        claimID: String = UUID().uuidString,
        desiredCount: Int,
        lowWatermark: Int,
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil
    ) {
        self.goalID = goalID
        self.contextRevision = contextRevision
        self.bankID = bankID
        self.claimID = claimID
        self.desiredCount = desiredCount
        self.lowWatermark = lowWatermark
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
    }
}

struct CheckpointAttempt: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var questionID: CheckpointQuestion.ID
    var goalID: Goal.ID
    var prompt: String
    var answer: String
    var result: AnswerResult
    var unlockMinutes: Int
    var createdAt = Date()
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

struct AppSnapshot: Codable, Sendable {
    var goal: Goal?
    var goalProfiles: [Goal]?
    var questions: [CheckpointQuestion]
    var attempts: [CheckpointAttempt]
    var competencies: [TopicCompetency]
    var unlockEvents: [UnlockEvent]?
    var questionReports: [QuestionQualityReport]?
    var issueReports: [UserIssueReport]?
    var questionGenerationTraces: [QuestionGenerationTrace]?
    var unlockPolicy: UnlockPolicy?
    var questionBatchState: QuestionBatchState?
    var lastAIErrorMessage: String?
    var lastQuestionGenerationFailure: QuestionGenerationFailureKind?
    var aiProviderPreference: AIProviderKind?
    var lastQuestionProvider: AIProviderKind?
    var backendEndpoint: String?
    var unlockSession: UnlockSession?
    var activeCheckpointRun: ActiveCheckpointRun?
    var checkpointRetryCooldownUntil: Date?
    var membershipTier: MembershipTier?
    var questionRefreshesUsed: Int?
    var lastAutomaticQuestionRefreshAt: Date?
    var questionBankSyncIntents: [QuestionBankSyncIntent]?
}

struct AnswerEvaluation: Equatable, Sendable {
    var result: AnswerResult
    var feedback: String
}

enum MultipleChoiceAnswerNormalizer {
    static func key(for text: String) -> String {
        let normalized = normalizedText(text)
        return compact(
            strippingChoiceLabel(
                from: strippingAnswerPrefix(from: normalized)
            )
        )
    }

    static func choiceIndex(from text: String) -> Int? {
        let normalized = strippingAnswerPrefix(from: normalizedText(text))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let textWithoutLabel = strippingChoiceLabel(from: normalized)
        guard textWithoutLabel != normalized || normalized.count == 1 else { return nil }

        let characters = Array(normalized)
        let first = characters.count >= 3 && (characters[0] == "(" || characters[0] == "[")
            ? characters[1]
            : characters[0]

        switch first {
        case "a", "1": return 0
        case "b", "2": return 1
        case "c", "3": return 2
        case "d", "4": return 3
        default: return nil
        }
    }

    static func choiceMentionedAsCorrect(
        in explanation: String,
        choices: [String],
        collapsingWhitespaceForPhraseMatching: Bool = false
    ) -> String? {
        let phraseMatchingText = collapsingWhitespaceForPhraseMatching
            ? explanation.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            : explanation
        let explanationWords = normalizedText(phraseMatchingText)
        guard explanationWords.contains("correct")
            || explanationWords.contains("best answer")
            || explanationWords.contains("right answer") else {
            return nil
        }

        let normalizedExplanation = key(for: explanation)
        let mentionedChoices = choices.filter { choice in
            let choiceKey = key(for: choice)
            return choiceKey.count >= 12 && normalizedExplanation.contains(choiceKey)
        }

        guard mentionedChoices.count == 1 else { return nil }
        return mentionedChoices[0]
    }

    static func strippingAnswerPrefix(from text: String) -> String {
        let prefixes = [
            "correct answer",
            "correct choice",
            "correct option",
            "answer",
            "choice",
            "option"
        ]

        for prefix in prefixes where text.hasPrefix(prefix) {
            let remainder = String(text.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n:-."))
            guard !remainder.isEmpty else { return text }
            return remainder
        }

        return text
    }

    static func strippingChoiceLabel(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(trimmed)
        let labels = Set("abcd1234")

        if characters.count >= 3,
           (characters[0] == "(" || characters[0] == "["),
           labels.contains(characters[1]),
           (characters[2] == ")" || characters[2] == "]") {
            return String(characters.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if characters.count >= 2,
           labels.contains(characters[0]),
           [".", ")", ":", "]"].contains(String(characters[1])) {
            return String(characters.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compact(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
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
            return evaluateMultipleChoice(answer: trimmedAnswer, question: question)
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

    private static func evaluateMultipleChoice(answer: String, question: CheckpointQuestion) -> AnswerEvaluation {
        let answerKey = MultipleChoiceAnswerNormalizer.key(for: answer)
        let expectedKey = MultipleChoiceAnswerNormalizer.key(for: question.expectedAnswer)
        let indexedExpectedChoice = MultipleChoiceAnswerNormalizer.choiceIndex(
            from: question.expectedAnswer
        ).flatMap { index in
            question.choices.indices.contains(index) ? question.choices[index] : nil
        }
        let matchingExpectedChoice = indexedExpectedChoice ?? question.choices.first {
            let choiceKey = MultipleChoiceAnswerNormalizer.key(for: $0)
            return choiceKey == expectedKey || (choiceKey.count >= 12 && expectedKey.contains(choiceKey))
        }
        let explanationChoice = MultipleChoiceAnswerNormalizer.choiceMentionedAsCorrect(
            in: question.explanation,
            choices: question.choices
        )
        let resolvedExpectedKey = (explanationChoice ?? matchingExpectedChoice).map {
            MultipleChoiceAnswerNormalizer.key(for: $0)
        } ?? expectedKey
        let allowsRawExpectedFallback = explanationChoice == nil

        if answerKey == resolvedExpectedKey || (allowsRawExpectedFallback && answerKey == expectedKey) {
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
            .filter { !stopWords.contains($0) }
    }

    private static func compact(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
        "in", "is", "it", "of", "on", "or", "that", "the", "to", "with"
    ]
}
