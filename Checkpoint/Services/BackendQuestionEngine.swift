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

        var urlRequest = BackendRequestFactory.post(
            to: endpoint,
            authorizationToken: request.backendAuthorizationToken,
            timeout: 45
        )
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

        var urlRequest = BackendRequestFactory.post(
            to: Self.skillMapEndpoint(generationEndpoint: endpoint),
            authorizationToken: request.backendAuthorizationToken,
            timeout: 30
        )
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
