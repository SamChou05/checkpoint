import Foundation

struct BackendQuestionEngine: QuestionGenerating, SkillMapInferring, SkillMapEvolving, @unchecked Sendable {
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
            payload = try QuestionContentJSONDecoder.decode(BackendQuestionResponse.self, from: data)
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

    func evolveSkillMap(for request: SkillMapEvolutionRequest) async throws -> SkillMapEvolutionProposal {
        guard let endpoint = request.backendEndpoint else {
            throw QuestionGenerationError.backendNotConfigured
        }

        var urlRequest = BackendRequestFactory.post(
            to: Self.skillMapEvolutionEndpoint(generationEndpoint: endpoint),
            authorizationToken: request.backendAuthorizationToken,
            timeout: 30
        )
        urlRequest.httpBody = try JSONEncoder().encode(
            BackendSkillMapEvolutionRequest(request: request)
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuestionGenerationError.serviceUnavailable
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.skillMapEvolutionError(
                for: httpResponse.statusCode,
                responseBody: data
            )
        }

        do {
            return try JSONDecoder().decode(
                BackendSkillMapEvolutionResponse.self,
                from: data
            ).makeProposal()
        } catch let error as QuestionGenerationError {
            throw error
        } catch {
            throw QuestionGenerationError.badResponse
        }
    }

    static func skillMapEndpoint(generationEndpoint: URL) -> URL {
        generationEndpoint
            .deletingLastPathComponent()
            .appendingPathComponent("skill-maps", isDirectory: true)
            .appendingPathComponent("infer", isDirectory: false)
    }

    static func skillMapEvolutionEndpoint(generationEndpoint: URL) -> URL {
        generationEndpoint
            .deletingLastPathComponent()
            .appendingPathComponent("skill-maps", isDirectory: true)
            .appendingPathComponent("evolve", isDirectory: false)
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
            let response = try? JSONDecoder().decode(BackendErrorResponse.self, from: responseBody)
            if response?.code == "provider_invalid_response" {
                return .badResponse
            }
            if response?.code == "provider_failure" {
                return .providerFailure
            }
            return .serviceUnavailable
        default:
            return .badResponse
        }
    }

    static func skillMapEvolutionError(
        for statusCode: Int,
        responseBody: Data
    ) -> QuestionGenerationError {
        if statusCode == 400,
           let response = try? JSONDecoder().decode(BackendErrorResponse.self, from: responseBody),
           response.code == "invalid_request" {
            // The evolution request is versioned and deterministic. Repeating an
            // invalid request against the same map cannot heal, so route it through
            // the persisted malformed-response budget instead of retrying forever.
            return .badResponse
        }
        return generationError(for: statusCode, responseBody: responseBody)
    }
}
