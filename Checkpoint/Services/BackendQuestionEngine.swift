import Foundation
import CryptoKit
import Security

struct BackendQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind = .backend

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
        urlRequest.httpBody = try BackendQuestionRequest(request: request).encodedData()

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw QuestionGenerationError.badResponse
        }

        let payload = try JSONDecoder().decode(BackendQuestionResponse.self, from: data)
        let plan = request.coveragePlan
        let questions = payload.questions.enumerated().map { index, payload in
            payload.makeQuestion(
                goalID: request.goal.id,
                sourcePrompt: request.sourcePrompt(provider: provider),
                coverageSlot: plan.indices.contains(index) ? plan[index] : nil
            )
        }

        guard !questions.isEmpty else {
            throw QuestionGenerationError.noQuestionsGenerated
        }

        return questions
    }
}

enum BackendClientIdentity {
    private static let installIDKey = "checkpoint.backend.install.id.v1"

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

    @discardableResult
    static func rotateInstallID(defaults: UserDefaults = .standard) -> String {
        let newID = UUID().uuidString
        defaults.set(newID, forKey: installIDKey)
        return newID
    }
}

struct QuestionReserveConfiguration: Equatable, Sendable {
    var endpoint: URL
    var authorizationToken: String?
}

enum QuestionReserveGoalRevision {
    static func value(for goal: Goal) -> String {
        let context = GoalQuestionContext(goal: goal)
        let components = [
            context.learningTarget,
            context.contentTopics.sorted().joined(separator: "\u{1f}"),
            context.questionDirective,
            goal.category.rawValue,
            goal.currentLevel,
            String(goal.minimumQuestionDifficulty),
            goal.preferredQuestionStyle.rawValue
        ]
        let normalized = components
            .map {
                $0.split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .lowercased()
            }
            .joined(separator: "\u{1e}")
        return SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct QuestionReserveDelivery: Sendable {
    var deliveryID: String
    var goalRevision: String
    var questions: [GeneratedQuestionPayload]
}

protocol QuestionReserveServing: Sendable {
    func sync(
        goalID: Goal.ID,
        goalRevision: String,
        desiredReserveCount: Int,
        generationRequest: QuestionGenerationRequest,
        configuration: QuestionReserveConfiguration
    ) async throws

    func pull(
        goalID: Goal.ID,
        goalRevision: String,
        configuration: QuestionReserveConfiguration
    ) async throws -> QuestionReserveDelivery?

    func acknowledge(
        goalID: Goal.ID,
        goalRevision: String,
        deliveryID: String,
        configuration: QuestionReserveConfiguration
    ) async throws

    func delete(
        goalIDs: [Goal.ID],
        configuration: QuestionReserveConfiguration
    ) async throws

    func resetCredentialsAndRotateIdentity() async
}

protocol QuestionReserveCredentialStoring: Sendable {
    func loadSecret() throws -> String?
    func saveSecret(_ secret: String) throws
    func clearSecret() throws
}

struct KeychainQuestionReserveCredentialStore: QuestionReserveCredentialStoring, Sendable {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.samchou.checkpoint",
        account: String = "question-reserve-install-secret.v1"
    ) {
        self.service = service
        self.account = account
    }

    func loadSecret() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw QuestionReserveCredentialError(status: status) }
        guard let data = result as? Data,
              let secret = String(data: data, encoding: .utf8),
              !secret.isEmpty else {
            return nil
        }
        return secret
    }

    func saveSecret(_ secret: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw QuestionReserveCredentialError(status: errSecParam)
        }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw QuestionReserveCredentialError(status: updateStatus)
        }

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw QuestionReserveCredentialError(status: addStatus)
        }
    }

    func clearSecret() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw QuestionReserveCredentialError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct QuestionReserveCredentialError: Error, Equatable, Sendable {
    var status: OSStatus
}

final class InMemoryQuestionReserveCredentialStore: QuestionReserveCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSecret: String?

    init(secret: String? = nil) {
        storedSecret = secret
    }

    func loadSecret() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedSecret
    }

    func saveSecret(_ secret: String) throws {
        lock.lock()
        storedSecret = secret
        lock.unlock()
    }

    func clearSecret() throws {
        lock.lock()
        storedSecret = nil
        lock.unlock()
    }
}

actor BackendQuestionReserveClient: QuestionReserveServing {
    private struct Credential: Sendable {
        var installID: String
        var secret: String
    }

    private static let syncSequenceKey = "checkpoint.questionReserve.syncSequence.v1"
    private static let generationRequestBudget = 112 * 1_024

    private let session: URLSession
    private let credentialStore: any QuestionReserveCredentialStoring
    private let defaults: UserDefaults
    private let secretGenerator: @Sendable () throws -> String
    private var registeredCredential: Credential?

    init(
        session: URLSession = .shared,
        credentialStore: any QuestionReserveCredentialStoring = KeychainQuestionReserveCredentialStore(),
        defaults: UserDefaults = .standard,
        secretGenerator: @escaping @Sendable () throws -> String = BackendQuestionReserveClient.randomSecret
    ) {
        self.session = session
        self.credentialStore = credentialStore
        self.defaults = defaults
        self.secretGenerator = secretGenerator
    }

    init(
        session: URLSession,
        credentialStore: any QuestionReserveCredentialStoring,
        defaultsSuiteName: String,
        secretGenerator: @escaping @Sendable () throws -> String
    ) {
        self.session = session
        self.credentialStore = credentialStore
        self.defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
        self.secretGenerator = secretGenerator
    }

    func sync(
        goalID: Goal.ID,
        goalRevision: String,
        desiredReserveCount: Int,
        generationRequest: QuestionGenerationRequest,
        configuration: QuestionReserveConfiguration
    ) async throws {
        _ = try await ensureRegistered(configuration: configuration)
        let syncSequence = nextSyncSequence()
        let boundedRequest = try BackendQuestionRequest(request: generationRequest).bounded(
            maximumByteCount: Self.generationRequestBudget
        )
        let body = ReserveSyncRequest(
            goalID: goalID,
            goalRevision: goalRevision,
            desiredReserveCount: max(0, min(20, desiredReserveCount)),
            syncSequence: syncSequence,
            generationRequest: boundedRequest
        )
        let bodyData = try JSONEncoder().encode(body)
        _ = try await performAuthenticated(
            path: "reserve/sync",
            body: bodyData,
            configuration: configuration,
            retriesUnauthorizedOnce: true
        )
    }

    func pull(
        goalID: Goal.ID,
        goalRevision: String,
        configuration: QuestionReserveConfiguration
    ) async throws -> QuestionReserveDelivery? {
        let bodyData = try JSONEncoder().encode(
            ReserveGoalRequest(goalID: goalID, goalRevision: goalRevision)
        )
        let data = try await performAuthenticated(
            path: "reserve/pull",
            body: bodyData,
            configuration: configuration,
            retriesUnauthorizedOnce: true
        )
        return try JSONDecoder().decode(ReservePullResponse.self, from: data).delivery.map {
            QuestionReserveDelivery(
                deliveryID: $0.deliveryID,
                goalRevision: $0.goalRevision,
                questions: $0.questions
            )
        }
    }

    func acknowledge(
        goalID: Goal.ID,
        goalRevision: String,
        deliveryID: String,
        configuration: QuestionReserveConfiguration
    ) async throws {
        let bodyData = try JSONEncoder().encode(
            ReserveAcknowledgeRequest(
                goalID: goalID,
                goalRevision: goalRevision,
                deliveryID: deliveryID
            )
        )
        _ = try await performAuthenticated(
            path: "reserve/ack",
            body: bodyData,
            configuration: configuration,
            retriesUnauthorizedOnce: true
        )
    }

    func delete(
        goalIDs: [Goal.ID],
        configuration: QuestionReserveConfiguration
    ) async throws {
        guard !goalIDs.isEmpty,
              let secret = try credentialStore.loadSecret(),
              Self.isValidSecret(secret) else {
            return
        }
        let bodyData = try JSONEncoder().encode(ReserveDeleteRequest(goalIDs: Array(goalIDs.prefix(5))))
        _ = try await performAuthenticated(
            path: "reserve/delete",
            body: bodyData,
            configuration: configuration,
            retriesUnauthorizedOnce: false
        )
    }

    func resetCredentialsAndRotateIdentity() async {
        try? credentialStore.clearSecret()
        registeredCredential = nil
        _ = BackendClientIdentity.rotateInstallID(defaults: defaults)
        defaults.set(0, forKey: Self.syncSequenceKey)
    }

    private func performAuthenticated(
        path: String,
        body: Data,
        configuration: QuestionReserveConfiguration,
        retriesUnauthorizedOnce: Bool
    ) async throws -> Data {
        var credential = try await ensureRegistered(configuration: configuration)
        do {
            return try await send(
                path: path,
                body: body,
                configuration: configuration,
                credential: credential
            )
        } catch QuestionReserveClientError.unauthorized where retriesUnauthorizedOnce {
            credential = try await rotateCredentialAndRegister(configuration: configuration)
            return try await send(
                path: path,
                body: body,
                configuration: configuration,
                credential: credential
            )
        }
    }

    private func ensureRegistered(
        configuration: QuestionReserveConfiguration
    ) async throws -> Credential {
        if let registeredCredential { return registeredCredential }

        let credential: Credential
        if let secret = try credentialStore.loadSecret(), Self.isValidSecret(secret) {
            credential = Credential(
                installID: BackendClientIdentity.installID(defaults: defaults),
                secret: secret
            )
        } else {
            let installID = BackendClientIdentity.rotateInstallID(defaults: defaults)
            let secret = try secretGenerator()
            try credentialStore.saveSecret(secret)
            credential = Credential(
                installID: installID,
                secret: secret
            )
            defaults.set(0, forKey: Self.syncSequenceKey)
        }

        do {
            try await register(credential, configuration: configuration)
            registeredCredential = credential
            return credential
        } catch QuestionReserveClientError.httpStatus(409) {
            return try await rotateCredentialAndRegister(configuration: configuration)
        }
    }

    private func rotateCredentialAndRegister(
        configuration: QuestionReserveConfiguration
    ) async throws -> Credential {
        try credentialStore.clearSecret()
        let installID = BackendClientIdentity.rotateInstallID(defaults: defaults)
        let secret = try secretGenerator()
        try credentialStore.saveSecret(secret)
        let credential = Credential(
            installID: installID,
            secret: secret
        )
        try await register(credential, configuration: configuration)
        registeredCredential = credential
        return credential
    }

    private func register(
        _ credential: Credential,
        configuration: QuestionReserveConfiguration
    ) async throws {
        _ = try await send(
            path: "reserve/register",
            body: Data("{}".utf8),
            configuration: configuration,
            credential: credential
        )
    }

    private func send(
        path: String,
        body: Data,
        configuration: QuestionReserveConfiguration,
        credential: Credential
    ) async throws -> Data {
        var request = URLRequest(url: reserveURL(base: configuration.endpoint, path: path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credential.installID, forHTTPHeaderField: "X-Checkpoint-Install-ID")
        request.setValue(credential.secret, forHTTPHeaderField: "X-Checkpoint-Install-Secret")
        if let token = configuration.authorizationToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuestionReserveClientError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw QuestionReserveClientError.unauthorized
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw QuestionReserveClientError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    private func reserveURL(base: URL, path: String) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        components?.path = "/" + [basePath, path]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return components?.url ?? base.appendingPathComponent(path)
    }

    private func nextSyncSequence() -> Int64 {
        let previous = (defaults.object(forKey: Self.syncSequenceKey) as? NSNumber)?.int64Value ?? 0
        let next = previous == Int64.max ? Int64.max : previous + 1
        defaults.set(NSNumber(value: next), forKey: Self.syncSequenceKey)
        return next
    }

    private static func randomSecret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw QuestionReserveCredentialError(status: status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func isValidSecret(_ secret: String) -> Bool {
        (32...256).contains(secret.count)
    }
}

enum QuestionReserveClientError: Error, Equatable, Sendable {
    case unauthorized
    case invalidResponse
    case httpStatus(Int)
}

private struct ReserveSyncRequest: Encodable {
    var goalID: Goal.ID
    var goalRevision: String
    var desiredReserveCount: Int
    var syncSequence: Int64
    var generationRequest: BackendQuestionRequest
}

private struct ReserveGoalRequest: Encodable {
    var goalID: Goal.ID
    var goalRevision: String
}

private struct ReserveAcknowledgeRequest: Encodable {
    var goalID: Goal.ID
    var goalRevision: String
    var deliveryID: String
}

private struct ReserveDeleteRequest: Encodable {
    var goalIDs: [Goal.ID]
}

private struct ReservePullResponse: Decodable {
    var state: String?
    var preparedCount: Int?
    var delivery: ReserveDeliveryResponse?
}

private struct ReserveDeliveryResponse: Decodable {
    var deliveryID: String
    var goalRevision: String
    var questions: [GeneratedQuestionPayload]
}

private enum BackendPayloadBounds {
    // Counts are deliberately below server list maxima so even four-byte Unicode
    // content stays comfortably under API Gateway's 256 KiB request limit.
    static let existingHistoryCount = 16
    static let reportedHistoryCount = 8

    static func text(_ value: String, maximumLength: Int) -> String {
        let characterClipped = String(value.prefix(max(0, maximumLength)))
        let maximumByteCount = max(0, maximumLength) * 4
        guard characterClipped.utf8.count > maximumByteCount else {
            return characterClipped
        }

        var byteCount = 0
        var bounded = ""
        for character in characterClipped {
            let characterText = String(character)
            let characterByteCount = characterText.utf8.count
            guard byteCount + characterByteCount <= maximumByteCount else { break }
            bounded.append(character)
            byteCount += characterByteCount
        }
        return bounded
    }
}

struct BackendQuestionRequest: Encodable {
    private var goal: GoalPayload
    private var competencies: [CompetencyPayload]
    private var existingPrompts: [String]
    private var existingQuestionCoverage: [QuestionCoveragePayload]
    private var coveragePlan: [CoveragePlanPayload]
    private var reportedPrompts: [String]
    private var reportedQuestionFeedback: [ReportedQuestionFeedbackPayload]
    private var targetCount: Int
    private var minimumDifficulty: Int
    private var difficultyGuidance: String

    init(request: QuestionGenerationRequest) {
        goal = GoalPayload(goal: request.goal, questionContext: request.questionContext)
        competencies = request.competencies.prefix(20).map(CompetencyPayload.init)
        let recentQuestions = request.existingQuestions.suffix(BackendPayloadBounds.existingHistoryCount)
        existingPrompts = recentQuestions.map {
            BackendPayloadBounds.text($0.prompt, maximumLength: 280)
        }
        existingQuestionCoverage = recentQuestions.map(QuestionCoveragePayload.init)
        coveragePlan = request.coveragePlan.map(CoveragePlanPayload.init)
        let recentReports = request.reportedQuestions.prefix(BackendPayloadBounds.reportedHistoryCount).reversed()
        reportedPrompts = recentReports.map {
            BackendPayloadBounds.text($0.prompt, maximumLength: 280)
        }
        reportedQuestionFeedback = request.reportedQuestions
            .prefix(BackendPayloadBounds.reportedHistoryCount)
            .reversed()
            .map(ReportedQuestionFeedbackPayload.init)
        targetCount = min(20, max(1, request.targetCount))
        minimumDifficulty = min(5, max(1, request.minimumDifficulty))
        difficultyGuidance = BackendPayloadBounds.text(request.difficultyGuidance, maximumLength: 600)
    }

    func encodedData(maximumByteCount: Int = 240 * 1_024) throws -> Data {
        try JSONEncoder().encode(bounded(maximumByteCount: maximumByteCount))
    }

    func bounded(maximumByteCount: Int) throws -> BackendQuestionRequest {
        var boundedRequest = self
        var data = try JSONEncoder().encode(boundedRequest)

        while data.count > maximumByteCount {
            if !boundedRequest.existingPrompts.isEmpty {
                boundedRequest.existingPrompts.removeFirst()
                if !boundedRequest.existingQuestionCoverage.isEmpty {
                    boundedRequest.existingQuestionCoverage.removeFirst()
                }
            } else if !boundedRequest.reportedPrompts.isEmpty {
                boundedRequest.reportedPrompts.removeFirst()
                if !boundedRequest.reportedQuestionFeedback.isEmpty {
                    boundedRequest.reportedQuestionFeedback.removeFirst()
                }
            } else {
                throw BackendRequestEncodingError.payloadTooLarge
            }
            data = try JSONEncoder().encode(boundedRequest)
        }

        return boundedRequest
    }
}

private enum BackendRequestEncodingError: Error {
    case payloadTooLarge
}

private struct ReportedQuestionFeedbackPayload: Encodable {
    var prompt: String
    var reason: String
    var note: String
    var expectedAnswer: String?
    var choices: [String]?
    var explanation: String?
    var topic: String?
    var subtopic: String?
    var avenue: String?
    var difficulty: Int?

    init(report: QuestionQualityReport) {
        prompt = BackendPayloadBounds.text(report.prompt, maximumLength: 280)
        reason = report.reason.rawValue
        note = BackendPayloadBounds.text(report.note, maximumLength: 280)
        expectedAnswer = report.expectedAnswer.map {
            BackendPayloadBounds.text($0, maximumLength: 280)
        }
        choices = report.choices.map { choices in
            Array(choices.prefix(4)).map {
                BackendPayloadBounds.text($0, maximumLength: 140)
            }
        }
        explanation = report.explanation.map {
            BackendPayloadBounds.text($0, maximumLength: 420)
        }
        topic = report.topic.map { BackendPayloadBounds.text($0, maximumLength: 80) }
        subtopic = report.subtopic.map { BackendPayloadBounds.text($0, maximumLength: 72) }
        avenue = report.avenue?.rawValue
        difficulty = report.difficulty
    }
}

private struct GoalPayload: Encodable {
    var title: String
    var deadline: Date
    var category: String
    var focusAreas: String
    var learningTarget: String
    var contentTopics: [String]
    var questionDirective: String
    var needsSkillMap: Bool
    var preferredQuestionStyle: String

    init(goal: Goal, questionContext: GoalQuestionContext) {
        title = BackendPayloadBounds.text(goal.title, maximumLength: 160)
        deadline = goal.deadline
        category = goal.category.rawValue
        focusAreas = BackendPayloadBounds.text(goal.focusAreas, maximumLength: 800)
        learningTarget = BackendPayloadBounds.text(questionContext.learningTarget, maximumLength: 240)
        contentTopics = questionContext.contentTopics.prefix(24).map {
            BackendPayloadBounds.text($0, maximumLength: 80)
        }
        questionDirective = BackendPayloadBounds.text(questionContext.questionDirective, maximumLength: 1_200)
        needsSkillMap = questionContext.needsGeneratedSkillMap
        preferredQuestionStyle = QuestionFormat.multipleChoice.rawValue
    }
}

private struct QuestionCoveragePayload: Encodable {
    var topic: String
    var subtopic: String
    var avenue: String
    var prompt: String
    var expectedAnswer: String
    var difficulty: Int

    init(question: CheckpointQuestion) {
        topic = BackendPayloadBounds.text(question.topic, maximumLength: 80)
        subtopic = BackendPayloadBounds.text(question.subtopic, maximumLength: 72)
        avenue = question.avenue.rawValue
        prompt = BackendPayloadBounds.text(question.prompt, maximumLength: 280)
        expectedAnswer = BackendPayloadBounds.text(question.expectedAnswer, maximumLength: 280)
        difficulty = question.difficulty
    }
}

private struct CoveragePlanPayload: Encodable {
    var topic: String
    var avenue: String

    init(slot: QuestionCoverageSlot) {
        topic = BackendPayloadBounds.text(slot.topic, maximumLength: 80)
        avenue = slot.avenue.rawValue
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
        topic = BackendPayloadBounds.text(competency.topic, maximumLength: 80)
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

struct GeneratedQuestionPayload: Decodable, Sendable {
    var reserveQuestionID: String?
    var prompt: String
    var expectedAnswer: String
    var choices: [String]
    var explanation: String
    var topic: String
    var subtopic: String
    var avenue: QuestionAvenue?
    var difficulty: Int
    var format: QuestionFormat

    enum CodingKeys: String, CodingKey {
        case reserveQuestionID
        case prompt
        case expectedAnswer
        case choices
        case explanation
        case topic
        case subtopic
        case avenue
        case difficulty
        case format
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reserveQuestionID = try container.decodeIfPresent(String.self, forKey: .reserveQuestionID)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        expectedAnswer = try container.decodeIfPresent(String.self, forKey: .expectedAnswer) ?? ""
        choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        topic = try container.decodeIfPresent(String.self, forKey: .topic) ?? ""
        subtopic = try container.decodeIfPresent(String.self, forKey: .subtopic) ?? ""
        let rawAvenue = try container.decodeIfPresent(String.self, forKey: .avenue) ?? ""
        avenue = QuestionAvenue.providerValue(rawAvenue)
        difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1

        let rawFormat = try container.decodeIfPresent(String.self, forKey: .format) ?? ""
        format = QuestionFormat.providerValue(rawFormat) ?? .multipleChoice
    }

    func makeQuestion(
        goalID: Goal.ID,
        sourcePrompt: String,
        coverageSlot: QuestionCoverageSlot? = nil
    ) -> CheckpointQuestion {
        let resolvedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? coverageSlot?.topic ?? ""
            : topic
        let resolvedAvenue = avenue ?? coverageSlot?.avenue ?? .application
        let resolvedSubtopic: String
        if subtopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedSubtopic = coverageSlot == nil
                ? resolvedTopic
                : "\(resolvedTopic) — \(resolvedAvenue.rawValue)"
        } else {
            resolvedSubtopic = subtopic
        }

        return CheckpointQuestion(
            id: stableReserveQuestionID ?? UUID(),
            goalID: goalID,
            prompt: prompt,
            expectedAnswer: expectedAnswer,
            choices: choices,
            explanation: explanation,
            topic: resolvedTopic,
            subtopic: resolvedSubtopic,
            avenue: resolvedAvenue,
            difficulty: min(5, max(1, difficulty)),
            format: .multipleChoice,
            sourcePrompt: sourcePrompt
        )
    }

    private var stableReserveQuestionID: UUID? {
        guard let reserveQuestionID = reserveQuestionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reserveQuestionID.isEmpty else {
            return nil
        }
        if let uuid = UUID(uuidString: reserveQuestionID) {
            return uuid
        }

        let digest = SHA256.hash(data: Data(reserveQuestionID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let start = digest.startIndex
        let i8 = digest.index(start, offsetBy: 8)
        let i12 = digest.index(start, offsetBy: 12)
        let i16 = digest.index(start, offsetBy: 16)
        let i20 = digest.index(start, offsetBy: 20)
        let i32 = digest.index(start, offsetBy: 32)
        return UUID(
            uuidString: "\(digest[start..<i8])-\(digest[i8..<i12])-\(digest[i12..<i16])-\(digest[i16..<i20])-\(digest[i20..<i32])"
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
