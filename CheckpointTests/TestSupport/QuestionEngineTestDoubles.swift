import Foundation
@testable import Checkpoint

// MARK: - Question engine doubles

private enum TestQuestionGenerationError: Error {
    case unavailable
}

struct StaticQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind
    let questions: [CheckpointQuestion]

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        questions
    }
}

struct GoalAwareQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        let resolvedTopics = request.questionContext.contentTopics

        return (1...6).map { index in
            makeQuestion(
                goal: request.goal,
                index: index,
                topic: resolvedTopics[(index - 1) % resolvedTopics.count],
                prompt: "\(request.goal.title) question \(index): Which choice best supports the active goal?",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

final class FirstClassSkillMapQuestionEngine: QuestionGenerating, SkillMapInferring, @unchecked Sendable {
    let provider: AIProviderKind = .backend
    let skillMap: GoalSkillMap
    private(set) var events: [String] = []
    private(set) var receivedRequests: [QuestionGenerationRequest] = []

    init(skillMap: GoalSkillMap) {
        self.skillMap = skillMap
    }

    func inferSkillMap(for request: QuestionGenerationRequest) async throws -> GoalSkillMap {
        events.append("inference")
        return skillMap
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        events.append("generation")
        receivedRequests.append(request)
        let requestSkills = request.goal.derivedSkillMap?.topics ?? skillMap.topics
        let allocatedSkills = requestSkills.flatMap { skill in
            Array(repeating: skill, count: request.desiredSkillAllocation[skill.id, default: 0])
        }
        let selectedSkills = allocatedSkills.isEmpty ? requestSkills : allocatedSkills

        return (0..<request.targetCount).map { index in
            let skill = selectedSkills[index % selectedSkills.count]
            let objective = skill.objectives.first
            return makeQuestion(
                goal: request.goal,
                index: index + 1,
                topic: skill.name,
                prompt: "First-class map question \(index + 1) for \(skill.name)",
                skillID: skill.id,
                objectiveID: objective?.id,
                objective: objective?.name,
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

final class SkillMapQuestionEngine: QuestionGenerating, @unchecked Sendable {
    let provider: AIProviderKind
    let topics: [String]
    let requestDelayNanoseconds: UInt64
    let largeRequestDelayNanoseconds: UInt64
    private(set) var receivedRequests: [QuestionGenerationRequest] = []

    init(
        provider: AIProviderKind,
        topics: [String],
        requestDelayNanoseconds: UInt64 = 0,
        largeRequestDelayNanoseconds: UInt64 = 0
    ) {
        self.provider = provider
        self.topics = topics
        self.requestDelayNanoseconds = requestDelayNanoseconds
        self.largeRequestDelayNanoseconds = largeRequestDelayNanoseconds
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        receivedRequests.append(request)

        if requestDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: requestDelayNanoseconds)
        } else if request.targetCount > UnlockPolicy.default.questionsPerSession,
           largeRequestDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: largeRequestDelayNanoseconds)
        }

        return (1...max(request.targetCount, topics.count)).map { index in
            let topic = topics[(index - 1) % topics.count]
            return makeQuestion(
                goal: request.goal,
                index: index,
                topic: topic,
                prompt: "\(request.goal.title) \(provider.rawValue) skill-map question \(index) for \(topic)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

final class PhasedSkillMapQuestionEngine: QuestionGenerating, @unchecked Sendable {
    let provider: AIProviderKind
    let topicsByRequest: [[String]]
    let largeRequestDelayNanoseconds: UInt64
    private(set) var receivedRequests: [QuestionGenerationRequest] = []

    init(
        provider: AIProviderKind,
        topicsByRequest: [[String]],
        largeRequestDelayNanoseconds: UInt64 = 0
    ) {
        self.provider = provider
        self.topicsByRequest = topicsByRequest
        self.largeRequestDelayNanoseconds = largeRequestDelayNanoseconds
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        receivedRequests.append(request)
        let requestIndex = receivedRequests.count - 1
        let topics = topicsByRequest.indices.contains(requestIndex)
            ? topicsByRequest[requestIndex]
            : (topicsByRequest.last ?? request.questionContext.contentTopics)

        if request.targetCount > UnlockPolicy.default.questionsPerSession,
           largeRequestDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: largeRequestDelayNanoseconds)
        }

        return (1...request.targetCount).map { index in
            let topic = topics[(index - 1) % topics.count]
            let uniqueIndex = (requestIndex + 1) * 1_000 + index
            return makeQuestion(
                goal: request.goal,
                index: uniqueIndex,
                topic: topic,
                prompt: "\(request.goal.title) phased skill-map question \(uniqueIndex) for \(topic)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

final class TargetCountQuestionEngine: QuestionGenerating, @unchecked Sendable {
    let provider: AIProviderKind
    let requestDelayNanoseconds: UInt64
    let largeRequestDelayNanoseconds: UInt64
    private(set) var receivedRequests: [QuestionGenerationRequest] = []

    init(
        provider: AIProviderKind,
        requestDelayNanoseconds: UInt64 = 0,
        largeRequestDelayNanoseconds: UInt64 = 0
    ) {
        self.provider = provider
        self.requestDelayNanoseconds = requestDelayNanoseconds
        self.largeRequestDelayNanoseconds = largeRequestDelayNanoseconds
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        receivedRequests.append(request)

        if requestDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: requestDelayNanoseconds)
        } else if request.targetCount > UnlockPolicy.default.questionsPerSession,
           largeRequestDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: largeRequestDelayNanoseconds)
        }

        let firstNewIndex = request.existingQuestions.count + 1
        let newQuestionIndices = firstNewIndex..<(firstNewIndex + request.targetCount)
        return newQuestionIndices.map { index in
            makeQuestion(
                goal: request.goal,
                index: index,
                topic: request.questionContext.contentTopics[(index - 1) % request.questionContext.contentTopics.count],
                prompt: "\(request.goal.title) \(provider.rawValue) target \(request.targetCount) question \(index)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

final class CountSequenceQuestionEngine: QuestionGenerating, @unchecked Sendable {
    let provider: AIProviderKind
    let counts: [Int]
    private(set) var receivedRequests: [QuestionGenerationRequest] = []

    init(provider: AIProviderKind, counts: [Int]) {
        self.provider = provider
        self.counts = counts
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        receivedRequests.append(request)
        let requestIndex = receivedRequests.count - 1
        let count = counts.indices.contains(requestIndex) ? counts[requestIndex] : (counts.last ?? request.targetCount)
        guard count > 0 else { return [] }

        return (1...count).map { index in
            makeQuestion(
                goal: request.goal,
                index: (requestIndex + 1) * 100 + index,
                topic: request.questionContext.contentTopics[(index - 1) % request.questionContext.contentTopics.count],
                prompt: "\(request.goal.title) \(provider.rawValue) sequence \(requestIndex + 1) question \(index)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

struct DelayedQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind
    let delayNanoseconds: UInt64

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return (1...6).map { index in
            makeQuestion(
                goal: request.goal,
                index: index,
                topic: "logical reasoning",
                prompt: "\(request.goal.title) delayed question \(index)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

struct ThrowingQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        throw TestQuestionGenerationError.unavailable
    }
}

struct UnavailableQuestionEngine: QuestionGenerating, SkillMapInferring {
    let provider: AIProviderKind

    func inferSkillMap(for request: QuestionGenerationRequest) async throws -> GoalSkillMap {
        throw QuestionGenerationError.providerUnavailable
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        throw QuestionGenerationError.providerUnavailable
    }
}

struct SafetyInterventionQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        throw QuestionGenerationError.safetyIntervention
    }
}

final class RecoveringQuestionEngine: QuestionGenerating, @unchecked Sendable {
    let provider: AIProviderKind
    private(set) var receivedRequests: [QuestionGenerationRequest] = []

    init(provider: AIProviderKind) {
        self.provider = provider
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        receivedRequests.append(request)
        guard receivedRequests.count > 1 else {
            throw QuestionGenerationError.providerUnavailable
        }

        let requestIndex = receivedRequests.count
        return (1...request.targetCount).map { index in
            makeQuestion(
                goal: request.goal,
                index: requestIndex * 1_000 + index,
                topic: request.questionContext.contentTopics[(index - 1) % request.questionContext.contentTopics.count],
                prompt: "\(request.goal.title) recovered AI question \(requestIndex)-\(index)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

final class CapturingQuestionEngine: QuestionGenerating, @unchecked Sendable {
    let provider: AIProviderKind
    private(set) var receivedRequests: [QuestionGenerationRequest] = []
    var receivedRequest: QuestionGenerationRequest? { receivedRequests.last }

    init(provider: AIProviderKind) {
        self.provider = provider
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        receivedRequests.append(request)
        let requestIndex = receivedRequests.count
        let acceptedCount = min(request.targetCount, UnlockPolicy.maximumQuestionsPerSession)
        guard acceptedCount > 0 else { return [] }
        return (1...acceptedCount).map { index in
            let newIndex = requestIndex * 1_000 + index
            let topics = request.questionContext.contentTopics
            let topic = topics[(index - 1) % topics.count]
            return makeQuestion(
                goal: request.goal,
                index: newIndex,
                topic: topic,
                prompt: "\(request.goal.title) \(provider.rawValue) question \(newIndex) about \(topic)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}
