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
        The user goal may include verbs such as study, prepare, pass, or learn; treat those as intent, not as the tested subject.
        Use the Learning target and Content topics from the prompt as the actual subject matter.
        Ask exam-style, knowledge-check, or skill-check questions about the subject itself.
        Do not ask about study plans, productivity, motivation, app blocking, or next steps unless the learning target is explicitly study skills.
        For LSAT, use original Logical Reasoning or Reading Comprehension style questions.
        Keep every question answerable in 30 seconds to 3 minutes.
        Each question must have exactly 4 choices.
        All 4 choices must be meaningfully distinct in wording and substance; do not include paraphrases of the same answer.
        Distractors should test different misconceptions, not restate the same mechanism with synonyms.
        expectedAnswer must exactly match one visible choice.
        Difficulty must be an integer from 1 to 5.
        Do not return questions below the requested minimum difficulty.
        Format must be Multiple Choice.
        Avoid repeating existing or reported prompts.
        """

        let prompt = request.sourcePrompt(provider: provider)

        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: 0.4, maximumResponseTokens: 1800)
        let response = try await session.respond(to: Prompt(prompt), options: options)
        let data = try extractJSONData(from: response.content)
        let payload = try JSONDecoder().decode(BackendQuestionResponse.self, from: data)
        let questions = payload.questions.map {
            $0.makeQuestion(goalID: request.goal.id, sourcePrompt: request.sourcePrompt(provider: provider))
        }

        guard !questions.isEmpty else {
            throw QuestionGenerationError.noQuestionsGenerated
        }

        return questions
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
