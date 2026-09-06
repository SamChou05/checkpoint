import Foundation

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
    var generationBlockedReason: String? = nil
}

struct QuestionBankClaimReceipt: Equatable, Sendable {
    var questions: [CheckpointQuestion]
    var status: QuestionBankRemoteStatus
    var readyCount: Int
    var targetCount: Int
    var generationBlockedReason: String? = nil
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
        var urlRequest = BackendRequestFactory.post(
            to: ensureEndpoint,
            authorizationToken: request.backendAuthorizationToken,
            timeout: 15
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
            targetCount: payload.targetCount,
            generationBlockedReason: payload.generationBlockedReason
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
        var urlRequest = BackendRequestFactory.post(
            to: claimEndpoint,
            authorizationToken: request.backendAuthorizationToken,
            timeout: 15
        )
        urlRequest.httpBody = try JSONEncoder().encode(
            BackendQuestionBankClaimRequest(
                bankID: normalizedBankID,
                claimID: normalizedClaimID,
                limit: limit,
                request: request
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
            targetCount: payload.targetCount,
            generationBlockedReason: payload.generationBlockedReason
        )
    }

    static func questionBankEndpoint(operation: String, generationEndpoint: URL) -> URL {
        generationEndpoint
            .deletingLastPathComponent()
            .appendingPathComponent("question-banks", isDirectory: true)
            .appendingPathComponent(operation, isDirectory: false)
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
    var generationBlockedReason: String?
}

struct BackendQuestionBankClaimRequest: Encodable {
    var bankID: String
    var claimID: String
    var limit: Int
    var blockedStemFingerprints: [String]
    var minimumVerificationVersion: Int

    init(
        bankID: String,
        claimID: String,
        limit: Int,
        request: QuestionGenerationRequest? = nil
    ) {
        self.bankID = bankID
        self.claimID = claimID
        self.limit = limit
        minimumVerificationVersion = request?.requiresVerifiedQuestions == true ? 1 : 0
        blockedStemFingerprints = request.map {
            BackendQuestionHistory.blockedStemFingerprints(for: $0)
        } ?? []
    }
}

private struct BackendQuestionBankClaimResponse: Decodable {
    var questions: [GeneratedQuestionPayload]
    var status: QuestionBankRemoteStatus
    var readyCount: Int
    var targetCount: Int
    var generationBlockedReason: String?
}
