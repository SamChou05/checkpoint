import Foundation

struct BackendQuestionEngine: QuestionGenerating, SkillMapInferring, @unchecked Sendable {
    let provider: AIProviderKind = .backend
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        guard let endpoint = request.backendEndpoint else {
            throw QuestionGenerationError.backendNotConfigured
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(BackendClientIdentity.installID, forHTTPHeaderField: "X-Checkpoint-Install-ID")
        if let token = request.backendAuthorizationToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.timeoutInterval = 45
        urlRequest.httpBody = try JSONEncoder().encode(BackendQuestionRequest(request: request))

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuestionGenerationError.serviceUnavailable
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.generationError(
                for: httpResponse.statusCode,
                responseBody: data
            )
        }

        let payload: BackendQuestionResponse
        do {
            payload = try JSONDecoder().decode(BackendQuestionResponse.self, from: data)
        } catch {
            throw QuestionGenerationError.badResponse
        }
        let sourcePrompt = request.sourcePrompt(provider: provider)
        let questions = payload.questions.map {
            $0.makeQuestion(goalID: request.goal.id, sourcePrompt: sourcePrompt)
        }

        guard !questions.isEmpty else {
            throw QuestionGenerationError.noQuestionsGenerated
        }

        return questions
    }

    func inferSkillMap(for request: QuestionGenerationRequest) async throws -> GoalSkillMap {
        guard let endpoint = request.backendEndpoint else {
            throw QuestionGenerationError.backendNotConfigured
        }

        var urlRequest = URLRequest(url: Self.skillMapEndpoint(generationEndpoint: endpoint))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(BackendClientIdentity.installID, forHTTPHeaderField: "X-Checkpoint-Install-ID")
        if let token = request.backendAuthorizationToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.timeoutInterval = 30
        urlRequest.httpBody = try JSONEncoder().encode(
            BackendSkillMapInferenceRequest(request: request)
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuestionGenerationError.serviceUnavailable
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.generationError(for: httpResponse.statusCode, responseBody: data)
        }

        let payload: BackendSkillMapInferenceResponse
        do {
            payload = try JSONDecoder().decode(BackendSkillMapInferenceResponse.self, from: data)
        } catch {
            throw QuestionGenerationError.badResponse
        }

        return try payload.skillMap.makeSkillMap(provenance: .backendInferred)
    }

    static func skillMapEndpoint(generationEndpoint: URL) -> URL {
        generationEndpoint
            .deletingLastPathComponent()
            .appendingPathComponent("skill-maps", isDirectory: true)
            .appendingPathComponent("infer", isDirectory: false)
    }

    static func generationError(
        for statusCode: Int,
        responseBody: Data
    ) -> QuestionGenerationError {
        switch statusCode {
        case 422:
            let response = try? JSONDecoder().decode(BackendErrorResponse.self, from: responseBody)
            return response?.code == "safety_intervention" ? .safetyIntervention : .badResponse
        case 429:
            return .rateLimited
        case 400, 401, 403, 404:
            return .serviceUnavailable
        case 500..<600:
            return .serviceUnavailable
        default:
            return .badResponse
        }
    }
}

enum QuestionBankAPIError: LocalizedError, Equatable, Sendable {
    case backendNotConfigured
    case invalidRequest
    case unauthorized
    case bankNotFound
    case contextConflict
    case claimConflict
    case rateLimited
    case serviceUnavailable
    case badResponse

    var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "No backend endpoint is configured."
        case .invalidRequest:
            return "The question bank request was invalid."
        case .unauthorized:
            return "The question bank service could not authorize this app."
        case .bankNotFound:
            return "The prepared question bank is no longer available."
        case .contextConflict:
            return "The prepared question bank no longer matches this goal."
        case .claimConflict:
            return "The prepared question bank changed while questions were being claimed."
        case .rateLimited:
            return "The question bank service rate limit was reached."
        case .serviceUnavailable:
            return "The question bank service is unavailable."
        case .badResponse:
            return "The question bank service returned an invalid response."
        }
    }
}

enum QuestionBankRemoteStatus: String, Codable, Equatable, Sendable {
    case queued
    case processing
    case ready
    case empty
}

struct QuestionBankPreparationReceipt: Equatable, Sendable {
    var bankID: String
    var status: QuestionBankRemoteStatus
    var readyCount: Int
    var targetCount: Int
}

struct QuestionBankClaimReceipt: Equatable, Sendable {
    var questions: [CheckpointQuestion]
    var status: QuestionBankRemoteStatus
    var readyCount: Int
    var targetCount: Int
}

protocol QuestionBankSyncing: Sendable {
    func ensureQuestionBank(
        for request: QuestionGenerationRequest,
        contextRevision: String,
        desiredCount: Int,
        lowWatermark: Int
    ) async throws -> QuestionBankPreparationReceipt

    func claimQuestions(
        from bankID: String,
        claimID: String,
        limit: Int,
        for request: QuestionGenerationRequest
    ) async throws -> QuestionBankClaimReceipt
}

struct BackendQuestionBankClient: QuestionBankSyncing, @unchecked Sendable {
    static let maximumClaimCount = 20

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func ensureQuestionBank(
        for request: QuestionGenerationRequest,
        contextRevision: String,
        desiredCount: Int,
        lowWatermark: Int
    ) async throws -> QuestionBankPreparationReceipt {
        guard let endpoint = request.backendEndpoint else {
            throw QuestionBankAPIError.backendNotConfigured
        }
        let normalizedContextRevision = contextRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContextRevision.isEmpty,
              (1...100).contains(desiredCount),
              lowWatermark >= 0,
              lowWatermark < desiredCount else {
            throw QuestionBankAPIError.invalidRequest
        }

        let ensureEndpoint = Self.questionBankEndpoint(
            operation: "ensure",
            generationEndpoint: endpoint
        )
        var urlRequest = Self.authorizedRequest(
            url: ensureEndpoint,
            authorizationToken: request.backendAuthorizationToken
        )
        urlRequest.httpBody = try JSONEncoder().encode(
            BackendQuestionRequest(
                request: request,
                targetCountOverride: min(Self.maximumClaimCount, max(1, request.targetCount)),
                contextRevision: normalizedContextRevision,
                desiredCount: desiredCount,
                lowWatermark: lowWatermark
            )
        )

        let (data, response) = try await session.data(for: urlRequest)
        try Self.validate(response: response, data: data)

        let payload: BackendQuestionBankPreparationResponse
        do {
            payload = try JSONDecoder().decode(BackendQuestionBankPreparationResponse.self, from: data)
        } catch {
            throw QuestionBankAPIError.badResponse
        }

        let bankID = payload.bankID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bankID.isEmpty,
              payload.readyCount >= 0,
              payload.targetCount > 0 else {
            throw QuestionBankAPIError.badResponse
        }

        return QuestionBankPreparationReceipt(
            bankID: bankID,
            status: payload.status,
            readyCount: payload.readyCount,
            targetCount: payload.targetCount
        )
    }

    func claimQuestions(
        from bankID: String,
        claimID: String,
        limit: Int,
        for request: QuestionGenerationRequest
    ) async throws -> QuestionBankClaimReceipt {
        guard let endpoint = request.backendEndpoint else {
            throw QuestionBankAPIError.backendNotConfigured
        }
        let normalizedBankID = bankID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedClaimID = claimID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBankID.isEmpty,
              !normalizedClaimID.isEmpty,
              (1...Self.maximumClaimCount).contains(limit) else {
            throw QuestionBankAPIError.invalidRequest
        }

        let claimEndpoint = Self.questionBankEndpoint(
            operation: "claim",
            generationEndpoint: endpoint
        )
        var urlRequest = Self.authorizedRequest(
            url: claimEndpoint,
            authorizationToken: request.backendAuthorizationToken
        )
        urlRequest.httpBody = try JSONEncoder().encode(
            BackendQuestionBankClaimRequest(
                bankID: normalizedBankID,
                claimID: normalizedClaimID,
                limit: limit
            )
        )

        let (data, response) = try await session.data(for: urlRequest)
        try Self.validate(response: response, data: data)

        let payload: BackendQuestionBankClaimResponse
        do {
            payload = try JSONDecoder().decode(BackendQuestionBankClaimResponse.self, from: data)
        } catch {
            throw QuestionBankAPIError.badResponse
        }
        let remoteIDs = payload.questions.compactMap(\.remoteID)
        guard payload.readyCount >= 0,
              payload.targetCount > 0,
              payload.questions.count <= limit,
              remoteIDs.count == payload.questions.count,
              Set(remoteIDs).count == remoteIDs.count,
              remoteIDs.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw QuestionBankAPIError.badResponse
        }

        let sourcePrompt = request.sourcePrompt(provider: .backend)
        return QuestionBankClaimReceipt(
            questions: payload.questions.map {
                $0.makeQuestion(goalID: request.goal.id, sourcePrompt: sourcePrompt)
            },
            status: payload.status,
            readyCount: payload.readyCount,
            targetCount: payload.targetCount
        )
    }

    static func questionBankEndpoint(operation: String, generationEndpoint: URL) -> URL {
        generationEndpoint
            .deletingLastPathComponent()
            .appendingPathComponent("question-banks", isDirectory: true)
            .appendingPathComponent(operation, isDirectory: false)
    }

    private static func authorizedRequest(
        url: URL,
        authorizationToken: String?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BackendClientIdentity.installID, forHTTPHeaderField: "X-Checkpoint-Install-ID")
        if let token = authorizationToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15
        return request
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuestionBankAPIError.serviceUnavailable
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 400, 422:
                throw QuestionBankAPIError.invalidRequest
            case 401, 403:
                throw QuestionBankAPIError.unauthorized
            case 404:
                throw QuestionBankAPIError.bankNotFound
            case 409:
                let response = try? JSONDecoder().decode(BackendErrorResponse.self, from: data)
                throw response?.code == "stale_bank"
                    ? QuestionBankAPIError.contextConflict
                    : QuestionBankAPIError.claimConflict
            case 410:
                throw QuestionBankAPIError.contextConflict
            case 429:
                throw QuestionBankAPIError.rateLimited
            case 500..<600:
                throw QuestionBankAPIError.serviceUnavailable
            default:
                throw QuestionBankAPIError.badResponse
            }
        }
    }
}

private struct BackendQuestionBankPreparationResponse: Decodable {
    var bankID: String
    var status: QuestionBankRemoteStatus
    var readyCount: Int
    var targetCount: Int
}

struct BackendQuestionBankClaimRequest: Encodable {
    var bankID: String
    var claimID: String
    var limit: Int
}

private struct BackendQuestionBankClaimResponse: Decodable {
    var questions: [GeneratedQuestionPayload]
    var status: QuestionBankRemoteStatus
    var readyCount: Int
    var targetCount: Int
}

private struct BackendErrorResponse: Decodable {
    var code: String?
}

enum BackendClientIdentity {
    static let installIDKey = "checkpoint.backend.install.id.v1"

    static var installID: String {
        installID(defaults: .standard)
    }

    static func installID(defaults: UserDefaults) -> String {
        if let existingID = defaults.string(forKey: installIDKey),
           UUID(uuidString: existingID) != nil {
            return existingID
        }

        let newID = UUID().uuidString
        defaults.set(newID, forKey: installIDKey)
        return newID
    }

    static func clearInstallID(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: installIDKey)
    }
}

struct BackendQuestionRequest: Encodable {
    private var goal: GoalPayload
    private var competencies: [CompetencyPayload]
    private var existingPrompts: [String]
    private var existingQuestionCoverage: [QuestionCoveragePayload]
    private var reportedPrompts: [String]
    private var sourceDocuments: [SourceDocumentPayload]
    private var targetCount: Int
    private var minimumDifficulty: Int
    private var difficultyGuidance: String
    private var skillMap: BackendSkillMapPayload?
    private var desiredSkillAllocation: [DesiredSkillAllocationPayload]?
    private var contextRevision: String?
    private var desiredCount: Int?
    private var lowWatermark: Int?

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

    func makeSkillMap(provenance: SkillMapProvenance) throws -> GoalSkillMap {
        let normalizedNames = skills.map { SkillMapTopic.normalizedName($0.name) }
        guard version == 1,
              let validatedNames = SkillMapTopic.validatedNames(normalizedNames),
              Set(skills.map(\.id)).count == skills.count else {
            throw QuestionGenerationError.badResponse
        }

        var allObjectiveIDs: Set<SkillMapObjective.ID> = []
        let topics = try zip(skills, validatedNames).map { skill, normalizedName in
            guard (1...8).contains(skill.objectives.count) else {
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
        objectives = skill.objectives.map(BackendObjectivePayload.init)
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
