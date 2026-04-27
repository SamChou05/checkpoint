import Foundation

struct BackendQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind = .backend

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        guard let endpoint = request.backendEndpoint else {
            throw QuestionGenerationError.backendNotConfigured
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 20
        urlRequest.httpBody = try JSONEncoder().encode(BackendQuestionRequest(request: request))

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw QuestionGenerationError.badResponse
        }

        let payload = try JSONDecoder().decode(BackendQuestionResponse.self, from: data)
        let questions = payload.questions.map { $0.makeQuestion(goalID: request.goal.id, sourcePrompt: "backend") }

        guard !questions.isEmpty else {
            throw QuestionGenerationError.noQuestionsGenerated
        }

        return questions
    }
}

private struct BackendQuestionRequest: Encodable {
    var goal: GoalPayload
    var competencies: [CompetencyPayload]
    var existingPrompts: [String]
    var reportedPrompts: [String]
    var targetCount: Int

    init(request: QuestionGenerationRequest) {
        goal = GoalPayload(goal: request.goal)
        competencies = request.competencies.map(CompetencyPayload.init)
        existingPrompts = request.existingQuestions.map(\.prompt)
        reportedPrompts = request.reportedQuestions.map(\.prompt)
        targetCount = request.targetCount
    }
}

private struct GoalPayload: Encodable {
    var title: String
    var deadline: Date
    var category: String
    var currentLevel: String
    var focusAreas: String
    var preferredQuestionStyle: String

    init(goal: Goal) {
        title = goal.title
        deadline = goal.deadline
        category = goal.category.rawValue
        currentLevel = goal.currentLevel
        focusAreas = goal.focusAreas
        preferredQuestionStyle = QuestionFormat.multipleChoice.rawValue
    }
}

private struct CompetencyPayload: Encodable {
    var topic: String
    var estimatedLevel: Double
    var masteryPercent: Int
    var attempts: Int
    var correct: Int
    var partial: Int
    var incorrect: Int

    init(competency: TopicCompetency) {
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
    var prompt: String
    var expectedAnswer: String
    var choices: [String]
    var explanation: String
    var topic: String
    var difficulty: Int
    var format: QuestionFormat

    enum CodingKeys: String, CodingKey {
        case prompt
        case expectedAnswer
        case choices
        case explanation
        case topic
        case difficulty
        case format
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        expectedAnswer = try container.decodeIfPresent(String.self, forKey: .expectedAnswer) ?? ""
        choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        topic = try container.decodeIfPresent(String.self, forKey: .topic) ?? ""
        difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1

        let rawFormat = try container.decodeIfPresent(String.self, forKey: .format) ?? ""
        format = QuestionFormat.providerValue(rawFormat) ?? .multipleChoice
    }

    func makeQuestion(goalID: Goal.ID, sourcePrompt: String) -> CheckpointQuestion {
        CheckpointQuestion(
            goalID: goalID,
            prompt: prompt,
            expectedAnswer: expectedAnswer,
            choices: choices,
            explanation: explanation,
            topic: topic,
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
