import Foundation

struct BackendQuestionRequest: Encodable {
    private var goal: GoalPayload
    private var competencies: [CompetencyPayload]
    private var existingPrompts: [String]
    private var existingQuestionCoverage: [QuestionCoveragePayload]
    private var reportedPrompts: [String]
    private var blockedStemFingerprints: [String]
    private var sourceDocuments: [SourceDocumentPayload]
    private var targetCount: Int
    private var minimumDifficulty: Int
    private var difficultyGuidance: String
    private var skillMap: BackendSkillMapPayload?
    private var desiredSkillAllocation: [DesiredSkillAllocationPayload]?
    private var contextRevision: String?
    private var desiredCount: Int?
    private var lowWatermark: Int?
    private var requiresFullObjectiveCoverage: Bool?

    init(
        request: QuestionGenerationRequest,
        targetCountOverride: Int? = nil,
        contextRevision: String? = nil,
        desiredCount: Int? = nil,
        lowWatermark: Int? = nil
    ) {
        goal = GoalPayload(goal: request.goal, questionContext: request.questionContext)
        competencies = request.competencies.prefix(20).map(CompetencyPayload.init)
        let recentQuestions = request.existingQuestions.suffix(30)
        existingPrompts = recentQuestions.map(\.prompt)
        existingQuestionCoverage = recentQuestions.map(QuestionCoveragePayload.init)
        reportedPrompts = request.reportedQuestions.prefix(30).map(\.prompt)
        blockedStemFingerprints = BackendQuestionHistory.blockedStemFingerprints(for: request)
        sourceDocuments = request.goal.sourceDocuments.map(SourceDocumentPayload.init)
        targetCount = targetCountOverride ?? request.targetCount
        minimumDifficulty = request.minimumDifficulty
        difficultyGuidance = request.difficultyGuidance
        skillMap = request.goal.derivedSkillMap.map(BackendSkillMapPayload.init)
        let allocation = request.desiredSkillAllocation
            .filter { $0.value >= 0 }
            .map { DesiredSkillAllocationPayload(skillID: $0.key, count: $0.value) }
            .sorted { $0.skillID.uuidString < $1.skillID.uuidString }
        desiredSkillAllocation = allocation.isEmpty ? nil : allocation
        self.contextRevision = contextRevision
        self.desiredCount = desiredCount
        self.lowWatermark = lowWatermark
        requiresFullObjectiveCoverage = desiredCount == nil ? nil : true
    }
}

enum BackendQuestionHistory {
    static let maximumBlockedStemFingerprintCount = 750

    static func blockedStemFingerprints(for request: QuestionGenerationRequest) -> [String] {
        let fingerprints = request.existingQuestions.compactMap {
            QuestionBatchSanitizer.questionStemFingerprint($0.prompt)
        } + request.reportedQuestions.compactMap {
            QuestionBatchSanitizer.questionStemFingerprint($0.prompt)
        }
        return Array(Set(fingerprints))
            .sorted()
            .prefix(maximumBlockedStemFingerprintCount)
            .map { $0 }
    }
}

enum BackendSkillMapEvolutionHistory {
    static let maximumArchivedSkillNameFingerprintCount = 750

    static func archivedSkillNameFingerprints(for skillMap: GoalSkillMap?) -> [String] {
        let fingerprints = skillMap?.archivedTopics.compactMap {
            skillNameFingerprint($0.topic.name)
        } ?? []
        return Array(Set(fingerprints))
            .sorted()
            .prefix(maximumArchivedSkillNameFingerprintCount)
            .map { $0 }
    }

    static func skillNameFingerprint(_ name: String) -> String? {
        let identity = SkillMapTopic.canonicalIdentityKey(name)
        guard !identity.isEmpty else { return nil }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identity.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

struct BackendSkillMapInferenceRequest: Encodable {
    private var goal: GoalPayload
    private var suggestedSkills: [String]
    private var competencies: [CompetencyPayload]
    private var sourceDocuments: [SourceDocumentPayload]

    init(request: QuestionGenerationRequest) {
        goal = GoalPayload(goal: request.goal, questionContext: request.questionContext)
        let suggestions = request.goal.derivedSkillMap?.topicNames
            ?? GoalQuestionContext.meaningfulFocusTopics(from: request.goal.focusAreas)
        suggestedSkills = Array(suggestions.prefix(6))
        competencies = request.competencies.prefix(20).map(CompetencyPayload.init)
        sourceDocuments = request.goal.sourceDocuments.map(SourceDocumentPayload.init)
    }
}

struct BackendSkillMapEvolutionRequest: Encodable {
    private var goal: GoalPayload
    private var baseMapFingerprint: String
    private var currentSkillMap: BackendSkillMapPayload
    private var masteredSkillIDs: [SkillMapTopic.ID]
    private var competencies: [EvolutionCompetencyPayload]
    private var recentAttempts: [EvolutionAttemptPayload]
    private var archivedSkills: [ArchivedSkillPayload]
    private var archivedSkillNameFingerprints: [String]
    private var sourceDocuments: [SourceDocumentPayload]

    init(request: SkillMapEvolutionRequest) {
        goal = GoalPayload(
            goal: request.goal,
            questionContext: GoalQuestionContext(goal: request.goal)
        )
        baseMapFingerprint = request.baseMapFingerprint
        currentSkillMap = BackendSkillMapPayload(
            skillMap: request.goal.derivedSkillMap ?? GoalSkillMap(topics: [])
        )
        masteredSkillIDs = request.masteredSkillIDs
        competencies = request.competencies
            .filter { competency in
                competency.skillID.map(request.masteredSkillIDs.contains) == true
            }
            .map(EvolutionCompetencyPayload.init)
        recentAttempts = request.recentAttempts.prefix(30).map(EvolutionAttemptPayload.init)
        archivedSkills = (request.goal.derivedSkillMap?.archivedTopics.suffix(48) ?? []).map {
            ArchivedSkillPayload(id: $0.topic.id, name: $0.topic.name)
        }
        archivedSkillNameFingerprints = BackendSkillMapEvolutionHistory
            .archivedSkillNameFingerprints(for: request.goal.derivedSkillMap)
        sourceDocuments = request.goal.sourceDocuments.map(SourceDocumentPayload.init)
    }
}

private struct DesiredSkillAllocationPayload: Encodable {
    var skillID: SkillMapTopic.ID
    var count: Int
}

struct BackendSkillMapPayload: Codable {
    var version: Int
    var skills: [BackendSkillPayload]

    init(skillMap: GoalSkillMap) {
        version = skillMap.version
        skills = skillMap.topics.map(BackendSkillPayload.init)
    }

    func makeSkillMap(
        provenance: SkillMapProvenance,
        expectedVersion: Int = 1
    ) throws -> GoalSkillMap {
        let normalizedNames = skills.map { SkillMapTopic.normalizedName($0.name) }
        guard version == expectedVersion,
              let validatedNames = SkillMapTopic.validatedNames(normalizedNames),
              Set(skills.map(\.id)).count == skills.count else {
            throw QuestionGenerationError.badResponse
        }

        var allObjectiveIDs: Set<SkillMapObjective.ID> = []
        let topics = try zip(skills, validatedNames).map { skill, normalizedName in
            guard (1...SkillMapTopic.maximumActiveObjectiveCount).contains(skill.objectives.count) else {
                throw QuestionGenerationError.badResponse
            }

            let objectives = try skill.objectives.map { objective in
                let name = SkillMapTopic.normalizedName(objective.name)
                guard (1...80).contains(name.count),
                      allObjectiveIDs.insert(objective.id).inserted else {
                    throw QuestionGenerationError.badResponse
                }
                return SkillMapObjective(id: objective.id, name: name)
            }
            let objectiveNames = objectives.map { $0.name.lowercased() }
            guard Set(objectiveNames).count == objectiveNames.count else {
                throw QuestionGenerationError.badResponse
            }

            return SkillMapTopic(
                id: skill.id,
                name: normalizedName,
                objectives: objectives
            )
        }

        return GoalSkillMap(
            topics: topics,
            version: version,
            provenance: provenance
        )
    }
}

struct BackendSkillPayload: Codable {
    var id: SkillMapTopic.ID
    var name: String
    var objectives: [BackendObjectivePayload]

    init(skill: SkillMapTopic) {
        id = skill.id
        name = skill.name
        objectives = skill.objectives
            .prefix(SkillMapTopic.maximumActiveObjectiveCount)
            .map(BackendObjectivePayload.init)
    }
}

struct BackendObjectivePayload: Codable {
    var id: SkillMapObjective.ID
    var name: String

    init(objective: SkillMapObjective) {
        id = objective.id
        name = objective.name
    }
}

struct BackendSkillMapInferenceResponse: Decodable {
    var skillMap: BackendSkillMapPayload
}

struct BackendSkillMapEvolutionResponse: Decodable {
    var baseMapFingerprint: String
    var baseVersion: Int
    var skillMap: BackendSkillMapPayload
    var replacements: [BackendSkillMapEvolutionReplacement]

    func makeProposal() throws -> SkillMapEvolutionProposal {
        let fingerprint = baseMapFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fingerprint.isEmpty,
              fingerprint.count <= 128,
              baseVersion >= 1,
              (1...2).contains(replacements.count),
              Set(replacements.map(\.predecessorSkillID)).count == replacements.count,
              Set(replacements.map(\.successorSkillID)).count == replacements.count else {
            throw QuestionGenerationError.badResponse
        }
        let evolvedMap = try skillMap.makeSkillMap(
            provenance: .adaptiveEvolution,
            expectedVersion: baseVersion + 1
        )
        let returnedByID = Dictionary(uniqueKeysWithValues: evolvedMap.topics.map { ($0.id, $0) })
        guard replacements.allSatisfy({ replacement in
            guard let successor = returnedByID[replacement.successorSkillID] else { return false }
            return (2...5).contains(successor.objectives.count)
        }) else {
            throw QuestionGenerationError.badResponse
        }
        return SkillMapEvolutionProposal(
            baseMapFingerprint: fingerprint,
            baseVersion: baseVersion,
            topics: evolvedMap.topics,
            replacements: replacements.map {
                SkillMapEvolutionReplacement(
                    predecessorSkillID: $0.predecessorSkillID,
                    successorSkillID: $0.successorSkillID
                )
            }
        )
    }
}

struct BackendSkillMapEvolutionReplacement: Decodable {
    var predecessorSkillID: SkillMapTopic.ID
    var successorSkillID: SkillMapTopic.ID
}

private struct EvolutionCompetencyPayload: Encodable {
    var skillID: SkillMapTopic.ID?
    var topic: String
    var estimatedLevel: Double
    var masteryPercent: Int
    var attempts: Int
    var correct: Int
    var partial: Int
    var incorrect: Int
    var currentStreak: Int

    init(competency: TopicCompetency) {
        skillID = competency.skillID
        topic = competency.topic
        estimatedLevel = competency.estimatedLevel
        masteryPercent = competency.masteryPercent
        attempts = competency.attempts
        correct = competency.correct
        partial = competency.partial
        incorrect = competency.incorrect
        currentStreak = competency.currentStreak
    }
}

private struct EvolutionAttemptPayload: Encodable {
    var skillID: SkillMapTopic.ID?
    var objectiveID: SkillMapObjective.ID?
    var difficulty: Int
    var result: String
    var occurredAt: String

    init(attempt: CheckpointAttempt) {
        skillID = attempt.skillID
        objectiveID = attempt.objectiveID
        difficulty = UnlockPolicy.normalizedQuestionDifficulty(attempt.questionDifficulty ?? 1)
        result = attempt.result.rawValue.lowercased()
        occurredAt = attempt.createdAt.ISO8601Format()
    }
}

private struct ArchivedSkillPayload: Encodable {
    var id: SkillMapTopic.ID
    var name: String
}

private struct SourceDocumentPayload: Encodable {
    var name: String
    var text: String

    init(document: GoalSourceDocument) {
        name = document.name
        text = document.text
    }
}

private struct GoalPayload: Encodable {
    var id: Goal.ID
    var title: String
    var deadline: Date
    var category: String
    var currentLevel: String
    var focusAreas: String
    var learningTarget: String
    var contentTopics: [String]
    var questionDirective: String
    var needsSkillMap: Bool
    var preferredQuestionStyle: String

    init(goal: Goal, questionContext: GoalQuestionContext) {
        id = goal.id
        title = goal.title
        deadline = goal.deadline
        category = goal.category.rawValue
        currentLevel = goal.currentLevel
        focusAreas = questionContext.hasDerivedSkillMap ? "" : goal.focusAreas
        learningTarget = questionContext.learningTarget
        contentTopics = questionContext.contentTopics
        questionDirective = questionContext.questionDirective
        needsSkillMap = questionContext.needsGeneratedSkillMap
        preferredQuestionStyle = QuestionFormat.multipleChoice.rawValue
    }
}

private struct QuestionCoveragePayload: Encodable {
    var skillID: SkillMapTopic.ID?
    var objectiveID: SkillMapObjective.ID?
    var objective: String?
    var topic: String
    var prompt: String
    var expectedAnswer: String
    var choices: [String]
    var difficulty: Int

    init(question: CheckpointQuestion) {
        skillID = question.skillID
        objectiveID = question.objectiveID
        objective = question.objective
        topic = question.topic
        prompt = question.prompt
        expectedAnswer = question.expectedAnswer
        choices = question.choices
        difficulty = question.difficulty
    }
}

private struct CompetencyPayload: Encodable {
    var skillID: SkillMapTopic.ID?
    var topic: String
    var estimatedLevel: Double
    var masteryPercent: Int
    var attempts: Int
    var correct: Int
    var partial: Int
    var incorrect: Int

    init(competency: TopicCompetency) {
        skillID = competency.skillID
        topic = competency.topic
        estimatedLevel = competency.estimatedLevel
        masteryPercent = competency.masteryPercent
        attempts = competency.attempts
        correct = competency.correct
        partial = competency.partial
        incorrect = competency.incorrect
    }
}

struct BackendQuestionResponse: Decodable {
    var questions: [GeneratedQuestionPayload]
}

struct GeneratedQuestionPayload: Decodable {
    var remoteID: String?
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

    enum CodingKeys: String, CodingKey {
        case id
        case remoteID
        case questionID
        case prompt
        case expectedAnswer
        case choices
        case explanation
        case topic
        case skillID
        case objectiveID
        case objective
        case objectiveName
        case difficulty
        case format
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remoteID = try container.decodeIfPresent(String.self, forKey: .remoteID)
            ?? container.decodeIfPresent(String.self, forKey: .questionID)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        expectedAnswer = try container.decodeIfPresent(String.self, forKey: .expectedAnswer) ?? ""
        choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        topic = try container.decodeIfPresent(String.self, forKey: .topic) ?? ""
        skillID = try container.decodeIfPresent(String.self, forKey: .skillID)
            .flatMap(SkillMapTopic.ID.init(uuidString:))
        objectiveID = try container.decodeIfPresent(String.self, forKey: .objectiveID)
            .flatMap(SkillMapObjective.ID.init(uuidString:))
        objective = try container.decodeIfPresent(String.self, forKey: .objective)
            ?? container.decodeIfPresent(String.self, forKey: .objectiveName)
        difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1

        let rawFormat = try container.decodeIfPresent(String.self, forKey: .format) ?? ""
        format = QuestionFormat.providerValue(rawFormat) ?? .multipleChoice
    }

    func makeQuestion(goalID: Goal.ID, sourcePrompt: String) -> CheckpointQuestion {
        CheckpointQuestion(
            id: remoteID.flatMap(UUID.init(uuidString:)) ?? UUID(),
            remoteID: remoteID,
            goalID: goalID,
            prompt: prompt,
            expectedAnswer: expectedAnswer,
            choices: choices,
            explanation: explanation,
            topic: topic,
            skillID: skillID,
            objectiveID: objectiveID,
            objective: objective,
            difficulty: min(5, max(1, difficulty)),
            format: .multipleChoice,
            sourcePrompt: sourcePrompt
        )
    }
}

private extension QuestionFormat {
    static func providerValue(_ rawValue: String) -> QuestionFormat? {
        let normalized = rawValue
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .joined()
            .lowercased()

        return allCases.first { format in
            format.rawValue
                .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
                .joined()
                .lowercased() == normalized
        }
    }
}
