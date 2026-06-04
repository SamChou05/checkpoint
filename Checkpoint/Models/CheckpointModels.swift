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

enum CheckpointSessionPurpose: String, Sendable {
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

struct Goal: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var deadline: Date
    var category: GoalCategory
    var currentLevel: String
    var focusAreas: String
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
            return "Level 1 of 5 (Basics)"
        case 2:
            return "Level 2 of 5 (Easy)"
        case 3:
            return "Level 3 of 5 (Medium)"
        case 4:
            return "Level 4 of 5 (Hard)"
        default:
            return "Level 5 of 5 (Expert)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case deadline
        case category
        case currentLevel
        case focusAreas
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
    var id: String
    var title: String
    var questionsAnswered: Int
    var correctAnswers: Int
    var masteryPercent: Int
    var trackedSkillCount: Int
    var isCurrentGoal: Bool = false

    var accuracyText: String {
        guard questionsAnswered > 0 else { return "0%" }
        return "\(Int((Double(correctAnswers) / Double(questionsAnswered)) * 100))%"
    }

    var skillProgressText: String {
        "\(masteryPercent)%"
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
        "\(goalID?.uuidString ?? "legacy")::\(topic)"
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
        goalID: Goal.ID? = nil
    ) -> TopicCompetency {
        TopicCompetency(
            goalID: goalID,
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

struct AppSnapshot: Codable, Sendable {
    var goal: Goal?
    var goalProfiles: [Goal]?
    var questions: [CheckpointQuestion]
    var attempts: [CheckpointAttempt]
    var competencies: [TopicCompetency]
    var questionReports: [QuestionQualityReport]?
    var issueReports: [UserIssueReport]?
    var questionGenerationTraces: [QuestionGenerationTrace]?
    var unlockPolicy: UnlockPolicy?
    var questionBatchState: QuestionBatchState?
    var aiProviderPreference: AIProviderKind?
    var lastQuestionProvider: AIProviderKind?
    var backendEndpoint: String?
    var unlockSession: UnlockSession?
    var membershipTier: MembershipTier?
    var questionRefreshesUsed: Int?
    var lastAutomaticQuestionRefreshAt: Date?
}

struct AnswerEvaluation: Equatable, Sendable {
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
        let answerKey = multipleChoiceKey(answer)
        let expectedKey = multipleChoiceKey(question.expectedAnswer)
        let indexedExpectedChoice = multipleChoiceIndex(from: question.expectedAnswer).flatMap { index in
            question.choices.indices.contains(index) ? question.choices[index] : nil
        }
        let matchingExpectedChoice = indexedExpectedChoice ?? question.choices.first {
            let choiceKey = multipleChoiceKey($0)
            return choiceKey == expectedKey || (choiceKey.count >= 12 && expectedKey.contains(choiceKey))
        }
        let explanationChoice = correctChoiceFromExplanation(question.explanation, choices: question.choices)
        let resolvedExpectedKey = (explanationChoice ?? matchingExpectedChoice).map(multipleChoiceKey) ?? expectedKey
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
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    private static func compact(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func multipleChoiceKey(_ text: String) -> String {
        var normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        normalized = strippedAnswerPrefix(from: normalized)
        normalized = strippedChoiceLabel(from: normalized)
        return compact(normalized)
    }

    private static func multipleChoiceIndex(from text: String) -> Int? {
        var normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = strippedAnswerPrefix(from: normalized)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let strippedLabel = strippedChoiceLabel(from: normalized)
        guard strippedLabel != normalized || normalized.count == 1 else { return nil }

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

    private static func correctChoiceFromExplanation(_ explanation: String, choices: [String]) -> String? {
        let explanationWords = explanation
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        guard explanationWords.contains("correct")
            || explanationWords.contains("best answer")
            || explanationWords.contains("right answer") else {
            return nil
        }

        let normalizedExplanation = multipleChoiceKey(explanation)
        let mentionedChoices = choices.filter { choice in
            let key = multipleChoiceKey(choice)
            return key.count >= 12 && normalizedExplanation.contains(key)
        }

        guard mentionedChoices.count == 1 else { return nil }
        return mentionedChoices[0]
    }

    private static func strippedAnswerPrefix(from text: String) -> String {
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

    private static func strippedChoiceLabel(from text: String) -> String {
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

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
        "in", "is", "it", "of", "on", "or", "that", "the", "to", "with"
    ]
}
