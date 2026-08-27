import Foundation

enum QuestionGenerationError: LocalizedError, Equatable, Sendable {
    case providerUnavailable
    case backendNotConfigured
    case serviceUnavailable
    case rateLimited
    case safetyIntervention
    case badResponse
    case noQuestionsGenerated

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "The selected AI provider is unavailable on this device."
        case .backendNotConfigured:
            return "No backend endpoint is configured."
        case .serviceUnavailable:
            return "The AI question service is unavailable."
        case .rateLimited:
            return "The AI question service rate limit was reached."
        case .safetyIntervention:
            return "The AI question service could not process this goal safely."
        case .badResponse:
            return "The question provider returned an invalid response."
        case .noQuestionsGenerated:
            return "No questions were generated."
        }
    }
}

enum QuestionGenerationFailureKind: String, Codable, Equatable, Sendable {
    case serviceUnavailable
    case transientProviderFailure
    case qualityRejected
    case safetyIntervention

    var title: String {
        switch self {
        case .serviceUnavailable:
            return "Practice is temporarily unavailable"
        case .transientProviderFailure:
            return "Couldn't connect"
        case .qualityRejected:
            return "Add a little more direction"
        case .safetyIntervention:
            return "Choose a different topic"
        }
    }

    var message: String {
        switch self {
        case .serviceUnavailable:
            return "Your goal is saved. Try preparing your checkpoint again in a little while."
        case .transientProviderFailure:
            return "Your goal is saved. Check your connection, then try again."
        case .qualityRejected:
            return "We couldn't prepare a focused checkpoint. Try again or add a few topics to your goal."
        case .safetyIntervention:
            return "Checkpoint can't create practice for this goal as written. Edit the goal or topics, then try again."
        }
    }

    var allowsEditingTopics: Bool {
        self == .qualityRejected || self == .safetyIntervention
    }

    var allowsRetryWithoutChanges: Bool {
        self != .safetyIntervention
    }
}

struct QuestionBatch: Sendable {
    var questions: [CheckpointQuestion]
    var provider: AIProviderKind
    var usedFallback: Bool
    var failure: QuestionGenerationFailureKind?
}

protocol QuestionGenerating: Sendable {
    var provider: AIProviderKind { get }
    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion]
}

protocol SkillMapInferring: Sendable {
    func inferSkillMap(for request: QuestionGenerationRequest) async throws -> GoalSkillMap
}

struct HybridQuestionEngine: Sendable {
    private let backendEngine: any QuestionGenerating
    private let appleFoundationEngine: any QuestionGenerating

    init(
        backendEngine: any QuestionGenerating = BackendQuestionEngine(),
        appleFoundationEngine: any QuestionGenerating = AppleFoundationQuestionEngine()
    ) {
        self.backendEngine = backendEngine
        self.appleFoundationEngine = appleFoundationEngine
    }

    var supportsDurableQuestionBanks: Bool {
        backendEngine is BackendQuestionEngine
    }

    func inferSkillMap(for request: QuestionGenerationRequest) async throws -> GoalSkillMap {
        do {
            guard let skillMapEngine = backendEngine as? any SkillMapInferring else {
                throw QuestionGenerationError.providerUnavailable
            }
            return try await skillMapEngine.inferSkillMap(for: request)
        } catch {
            let explicitTopics = GoalQuestionContext.meaningfulFocusTopics(from: request.goal.focusAreas)
            guard let validatedTopics = SkillMapTopic.validatedNames(explicitTopics) else {
                throw error
            }

            return GoalSkillMap(
                topics: validatedTopics.map { name in
                    SkillMapTopic(
                        name: name,
                        objectives: [SkillMapObjective(name: name)]
                    )
                },
                status: .reviewed,
                provenance: .explicitFocusAreas
            )
        }
    }

    func generateQuestionBatch(
        for request: QuestionGenerationRequest,
        preference: AIProviderKind
    ) async -> QuestionBatch {
        let providers = providerOrder(for: preference)
        let minimumAcceptedQuestionCount = min(
            request.targetCount,
            UnlockPolicy.maximumQuestionsPerSession
        )
        var failure: QuestionGenerationFailureKind = .serviceUnavailable

        for provider in providers {
            do {
                let questions = try await provider.generateQuestions(for: request)
                let sanitizedQuestions = QuestionBatchSanitizer.sanitize(questions, for: request)

                if sanitizedQuestions.count >= minimumAcceptedQuestionCount {
                    return QuestionBatch(
                        questions: sanitizedQuestions,
                        provider: provider.provider,
                        usedFallback: provider.provider != preference
                            && preference != .automatic,
                        failure: nil
                    )
                }

                failure = .qualityRejected
            } catch {
                failure = preferredFailure(failure, mappedFailure(from: error))
                continue
            }
        }

        return QuestionBatch(
            questions: [],
            provider: failureProvider(for: preference),
            usedFallback: false,
            failure: failure
        )
    }

    private func providerOrder(for preference: AIProviderKind) -> [any QuestionGenerating] {
        switch preference {
        case .automatic:
            return [backendEngine]
        case .appleFoundation:
            #if DEBUG
            return [appleFoundationEngine]
            #else
            return [backendEngine]
            #endif
        case .backend:
            return [backendEngine]
        case .localTemplates:
            return [backendEngine]
        }
    }

    private func mappedFailure(from error: Error) -> QuestionGenerationFailureKind {
        if error is URLError {
            return .transientProviderFailure
        }

        guard let generationError = error as? QuestionGenerationError else {
            return .transientProviderFailure
        }

        switch generationError {
        case .providerUnavailable, .backendNotConfigured, .serviceUnavailable:
            return .serviceUnavailable
        case .rateLimited:
            return .serviceUnavailable
        case .safetyIntervention:
            return .safetyIntervention
        case .badResponse, .noQuestionsGenerated:
            return .qualityRejected
        }
    }

    private func preferredFailure(
        _ current: QuestionGenerationFailureKind,
        _ candidate: QuestionGenerationFailureKind
    ) -> QuestionGenerationFailureKind {
        let priority: [QuestionGenerationFailureKind: Int] = [
            .serviceUnavailable: 0,
            .qualityRejected: 1,
            .transientProviderFailure: 2,
            .safetyIntervention: 3
        ]
        return (priority[candidate] ?? 0) >= (priority[current] ?? 0) ? candidate : current
    }

    private func failureProvider(for preference: AIProviderKind) -> AIProviderKind {
        if preference == .automatic || preference == .localTemplates {
            return .backend
        }

        #if !DEBUG
        if preference == .appleFoundation {
            return .backend
        }
        #endif

        return preference
    }
}
