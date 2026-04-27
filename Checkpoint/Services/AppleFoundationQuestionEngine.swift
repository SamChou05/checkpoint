import Foundation

#if os(iOS) && canImport(FoundationModels)
import FoundationModels
#endif

struct AppleFoundationQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind = .appleFoundation

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        #if os(iOS) && canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await AppleFoundationQuestionEngineImpl().generateQuestions(for: request)
        } else {
            throw QuestionGenerationError.providerUnavailable
        }
        #else
        throw QuestionGenerationError.providerUnavailable
        #endif
    }
}

#if os(iOS) && canImport(FoundationModels)
@available(iOS 26.0, *)
private struct AppleFoundationQuestionEngineImpl: QuestionGenerating {
    let provider: AIProviderKind = .appleFoundation

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw QuestionGenerationError.providerUnavailable
        }

        let instructions = """
        Generate multiple-choice checkpoint questions for a focus app.
        Return only valid JSON with this exact shape:
        {"questions":[{"prompt":"...","expectedAnswer":"...","choices":["...","...","...","..."],"explanation":"...","topic":"...","difficulty":1,"format":"Multiple Choice"}]}
        Keep every question answerable in 30 seconds to 3 minutes.
        Each question must have 4 choices.
        expectedAnswer must exactly match one choice.
        Difficulty must be an integer from 1 to 5.
        Format must be Multiple Choice.
        Avoid repeating existing or reported prompts.
        """

        let prompt = """
        Goal: \(request.goal.title)
        Category: \(request.goal.category.rawValue)
        Current level: \(request.goal.currentLevel)
        Focus areas: \(request.goal.focusAreas)
        Preferred style: Multiple Choice
        Target count: \(request.targetCount)
        Competencies: \(competencySummary(request.competencies))
        Existing prompts: \(request.existingQuestions.map(\.prompt).prefix(10).joined(separator: " | "))
        Reported prompts to avoid: \(request.reportedQuestions.map(\.prompt).prefix(10).joined(separator: " | "))
        """

        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: 0.4, maximumResponseTokens: 1800)
        let response = try await session.respond(to: Prompt(prompt), options: options)
        let data = try extractJSONData(from: response.content)
        let payload = try JSONDecoder().decode(BackendQuestionResponse.self, from: data)
        let questions = payload.questions.map {
            $0.makeQuestion(goalID: request.goal.id, sourcePrompt: "apple foundation models")
        }

        guard !questions.isEmpty else {
            throw QuestionGenerationError.noQuestionsGenerated
        }

        return questions
    }

    private func competencySummary(_ competencies: [TopicCompetency]) -> String {
        competencies
            .map { "\($0.topic): level \($0.displayLevel), mastery \($0.masteryPercent)%" }
            .joined(separator: "; ")
    }

    private func extractJSONData(from text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = trimmed.data(using: .utf8),
           (try? JSONDecoder().decode(BackendQuestionResponse.self, from: data)) != nil {
            return data
        }

        guard
            let start = trimmed.firstIndex(of: "{"),
            let end = trimmed.lastIndex(of: "}")
        else {
            throw QuestionGenerationError.badResponse
        }

        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8) else {
            throw QuestionGenerationError.badResponse
        }

        return data
    }
}
#endif
