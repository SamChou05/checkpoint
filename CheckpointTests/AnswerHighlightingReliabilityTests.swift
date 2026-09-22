import XCTest
@testable import Checkpoint

final class AnswerHighlightingReliabilityTests: XCTestCase {
    private let correctChoice = "Remove the most recently added element"
    private let distractor = "Remove the earliest added element"

    private var choices: [String] {
        [correctChoice, distractor, "Remove a random element", "Remove every stored element"]
    }

    func testLegacyExplanationCannotTurnAnExplicitlyWrongChoiceIntoTheAnswer() {
        for explanation in misleadingExplanations {
            let question = question(explanation: explanation, version: 0)
            XCTAssertEqual(AnswerGrader.evaluate(answer: correctChoice, question: question).result, .correct, explanation)
            XCTAssertEqual(AnswerGrader.evaluate(answer: distractor, question: question).result, .incorrect, explanation)
            XCTAssertEqual(AnswerGrader.correctAnswerText(for: question, after: .incorrect), correctChoice, explanation)
        }
    }

    func testSanitizerDoesNotRewriteAKeyBecauseTheExplanationRejectsADistractor() throws {
        for explanation in misleadingExplanations {
            let question = question(explanation: explanation, version: 0)
            let request = makeRequest(goal: makeGoal())
            let accepted = try XCTUnwrap(QuestionBatchSanitizer.sanitize([question], for: request).first, explanation)
            XCTAssertEqual(accepted.expectedAnswer, correctChoice, explanation)
            XCTAssertEqual(accepted.choices.filter { AnswerGrader.evaluate(answer: $0, question: accepted).result == .correct }, [correctChoice])
        }
    }

    func testAnExactLegacyKeyOutranksEvenAnAffirmativeContradictoryExplanation() {
        let question = question(explanation: "\(distractor) is correct because it was the first item pushed.", version: 0)
        XCTAssertEqual(AnswerGrader.evaluate(answer: correctChoice, question: question).result, .correct)
        XCTAssertEqual(AnswerGrader.evaluate(answer: distractor, question: question).result, .incorrect)
        XCTAssertEqual(AnswerGrader.correctAnswerText(for: question, after: .incorrect), correctChoice)
    }

    func testLegacyChoiceLabelSurvivesShuffleWithoutExplanationChangingIt() throws {
        var question = question(explanation: "\(distractor) is correct because this fixture deliberately contradicts the label.", version: 0)
        question.expectedAnswer = "A"
        XCTAssertEqual(AnswerGrader.evaluate(answer: correctChoice, question: question).result, .correct)
        XCTAssertEqual(AnswerGrader.evaluate(answer: distractor, question: question).result, .incorrect)
        let accepted = try XCTUnwrap(QuestionBatchSanitizer.sanitize([question], for: makeRequest(goal: makeGoal())).first)
        XCTAssertEqual(accepted.expectedAnswer, correctChoice)
        for order in permutations(accepted.choices) {
            var reordered = accepted
            reordered.choices = order
            XCTAssertEqual(order.filter { AnswerGrader.evaluate(answer: $0, question: reordered).result == .correct }, [correctChoice])
        }
    }

    func testExplanationCannotInventAKeyForMalformedLegacyContent() {
        var question = question(explanation: "\(distractor) is correct because this fixture deliberately supplies no valid key.", version: 0)
        question.expectedAnswer = "An answer that is not offered"
        XCTAssertTrue(question.choices.allSatisfy { AnswerGrader.evaluate(answer: $0, question: question).result == .incorrect })
        XCTAssertTrue(QuestionBatchSanitizer.sanitize([question], for: makeRequest(goal: makeGoal())).isEmpty)
    }

    func testVerifiedWirePersistenceAndReviewKeepOneAnswerAcrossAllChoiceOrders() throws {
        let fixtures: [(answer: String, choices: [String])] = [
            (correctChoice, choices),
            ("2", ["1", "2", "3", "4"]),
            ("True", ["True", "true", "False", "false"]),
            ("a - b", ["a + b", "a - b", "a * b", "a / b"])
        ]
        for fixture in fixtures {
            for order in permutations(fixture.choices) {
                var authored = question(explanation: "Evaluate the stated operation using the given operands.", version: 1)
                authored.choices = order
                authored.expectedAnswer = fixture.answer
                authored.choiceExplanations = [fixture.answer: "This value follows from the operation in the question."]
                let payload = try QuestionContentJSONDecoder.decode(GeneratedQuestionPayload.self, from: JSONEncoder().encode(authored))
                let received = payload.makeQuestion(goalID: authored.goalID, sourcePrompt: "wire test")
                var accepted = try XCTUnwrap(QuestionBatchSanitizer.sanitize([received], for: makeRequest(goal: makeGoal())).first)
                XCTAssertEqual(accepted.choices.filter { AnswerGrader.evaluate(answer: $0, question: accepted).result == .correct }, [fixture.answer])
                // Exercise every persisted/displayed order deterministically,
                // as well as the sanitizer's random order checked above.
                accepted.choices = order
                let restored = try QuestionContentJSONDecoder.decode(CheckpointQuestion.self, from: JSONEncoder().encode(accepted))

                XCTAssertEqual(restored.choices.filter { AnswerGrader.evaluate(answer: $0, question: restored).result == .correct }, [fixture.answer])
                XCTAssertEqual(restored.expectedAnswer, fixture.answer)
                XCTAssertEqual(restored.feedbackExplanation(for: fixture.answer), authored.choiceExplanations[fixture.answer]! + "\n\n" + authored.explanation)
                for result in [AnswerResult.incorrect, .partial, .unclear] {
                    XCTAssertEqual(CheckpointAnswerReviewPresentation(question: restored, result: result)?.answerText, fixture.answer)
                }
                XCTAssertNil(CheckpointAnswerReviewPresentation(question: restored, result: .correct))
            }
        }
    }

    func testVerifiedAnswerNeverChangesWhenExplanationDiscussesDistractors() {
        for explanation in misleadingExplanations + ["\(distractor) is correct because this fixture deliberately contradicts the key."] {
            let question = question(explanation: explanation, version: 1)
            XCTAssertEqual(question.choices.filter { AnswerGrader.evaluate(answer: $0, question: question).result == .correct }, [correctChoice])
        }
    }

    func testCompiledQuantitativePayloadsKeepAllTeachingAndOneHighlightAcrossEveryOrder() throws {
        // Python recomputes these exact fields with compile_question and carries
        // them through the real bank writer and claim/replay implementation.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("backend/bedrock-question-service/tests/fixtures/compiled_quantitative_roundtrip.json")
        let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let metadata = try XCTUnwrap(packet["trustedWireMetadata"] as? [String: Any])
        let cases = try XCTUnwrap(packet["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 3)
        let goal = makeGoal()
        var request = makeRequest(goal: goal)
        request.requiresVerifiedQuestions = true

        for fixture in cases {
            let name = try XCTUnwrap(fixture["id"] as? String)
            let compiled = try XCTUnwrap(fixture["compiled"] as? [String: Any])
            let original = try QuestionContentJSONDecoder.decode(
                GeneratedQuestionPayload.self, from: JSONSerialization.data(withJSONObject: compiled)
            )
            let orders = permutations(original.choices)
            XCTAssertEqual(orders.count, 24, name)
            for order in orders {
                // Test metadata is a trusted carrier fixture, not model-supplied
                // compiler approval. Production provenance is tested separately.
                var wire = compiled.merging(metadata) { _, metadataValue in metadataValue }
                wire["choices"] = order
                let payload = try QuestionContentJSONDecoder.decode(
                    GeneratedQuestionPayload.self, from: JSONSerialization.data(withJSONObject: wire)
                )
                let received = payload.makeQuestion(goalID: goal.id, sourcePrompt: name)
                assertCompiledLearnerFields(received, equal: original, context: name)
                XCTAssertEqual(received.choices.map { Data($0.utf8) }, order.map { Data($0.utf8) }, name)
                var accepted = try XCTUnwrap(QuestionBatchSanitizer.sanitize([received], for: request).first, name)
                assertCompiledLearnerFields(accepted, equal: original, context: name)
                XCTAssertEqual(accepted.choices.filter { AnswerGrader.evaluate(answer: $0, question: accepted).result == .correct }, [original.expectedAnswer], name)

                // In addition to the random admission shuffle above, persist
                // every display order deterministically and test its feedback.
                accepted.choices = order
                let restored = try QuestionContentJSONDecoder.decode(
                    CheckpointQuestion.self, from: JSONEncoder().encode(accepted)
                )
                assertCompiledLearnerFields(restored, equal: original, context: name)
                XCTAssertEqual(restored.choices.map { Data($0.utf8) }, order.map { Data($0.utf8) }, name)
                XCTAssertEqual(restored.choices.filter { AnswerGrader.evaluate(answer: $0, question: restored).result == .correct }, [original.expectedAnswer], name)
                for choice in order {
                    let choiceFeedback = try XCTUnwrap(original.choiceExplanations[choice], name)
                    XCTAssertEqual(Data(restored.feedbackExplanation(for: choice).utf8), Data((choiceFeedback + "\n\n" + original.explanation).utf8), name)
                }
                for result in [AnswerResult.incorrect, .partial, .unclear] {
                    XCTAssertEqual(CheckpointAnswerReviewPresentation(question: restored, result: result)?.answerText, original.expectedAnswer, name)
                }
                XCTAssertNil(CheckpointAnswerReviewPresentation(question: restored, result: .correct), name)
            }
        }
    }

    func testTerminalAndHistoryReviewUseTheSameAnswerAfterPersistence() throws {
        let question = question(explanation: "A stack removes the last item added before earlier items.", version: 1)
        let terminal = CheckpointTerminalAnswerReviewPresentation(question: question, answer: distractor, result: .incorrect)
        let attempt = CheckpointAttempt(
            questionID: question.id, goalID: question.goalID, prompt: question.prompt,
            answer: distractor, result: .incorrect, unlockMinutes: 0,
            reviewSnapshot: CheckpointAttemptReviewSnapshot(
                topic: question.topic, format: question.format,
                referenceAnswer: AnswerGrader.correctAnswerText(for: question, after: .incorrect),
                explanation: question.feedbackExplanation(for: distractor)
            )
        )
        let restored = try JSONDecoder().decode(CheckpointAttempt.self, from: JSONEncoder().encode(attempt))
        let history = PracticeHistoryReviewPresentation(attempt: restored)
        XCTAssertEqual(terminal.referenceAnswerText, correctChoice)
        XCTAssertEqual(history.referenceAnswer, terminal.referenceAnswerText)
        XCTAssertEqual(history.referenceLabel, "Correct answer")
        XCTAssertEqual(history.userAnswer, distractor)
    }

    func testDuplicateVisibleChoicesAreRejectedInsteadOfHighlightingTwoAnswers() {
        for duplicates in [["salt", " salt ", "sugar", "water"], ["café", "cafe\u{301}", "tea", "water"]] {
            var question = question(explanation: "This malformed fixture must not enter a practice session.", version: 1)
            question.choices = duplicates
            question.expectedAnswer = duplicates[0]
            XCTAssertTrue(QuestionBatchSanitizer.sanitize([question], for: makeRequest(goal: makeGoal())).isEmpty)
            XCTAssertTrue(question.choices.allSatisfy { AnswerGrader.evaluate(answer: $0, question: question).result == .unclear })
        }
    }

    private var misleadingExplanations: [String] {
        [
            "\(distractor) is incorrect because a stack uses last-in-first-out ordering.",
            "\(distractor) is not correct because a stack uses last-in-first-out ordering.",
            "The correct rule is last-in-first-out. \(distractor) violates that rule.",
            "It is false that \(distractor) is correct because stacks remove the newest item.",
            "\(distractor) is not the best answer because it describes a queue.",
            "\(distractor) would be the right answer for a queue, but this question asks about a stack."
        ]
    }

    private func question(explanation: String, version: Int) -> CheckpointQuestion {
        makeQuestion(
            goal: makeGoal(), index: 1, topic: "Stacks", prompt: "Which operation describes popping a stack?",
            expectedAnswer: correctChoice, choices: choices, explanation: explanation, verificationVersion: version
        )
    }

    private func assertCompiledLearnerFields(
        _ question: CheckpointQuestion, equal original: GeneratedQuestionPayload,
        context: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(Data(question.prompt.utf8), Data(original.prompt.utf8), context, file: file, line: line)
        XCTAssertEqual(Data(question.expectedAnswer.utf8), Data(original.expectedAnswer.utf8), context, file: file, line: line)
        XCTAssertEqual(Data(question.explanation.utf8), Data(original.explanation.utf8), context, file: file, line: line)
        XCTAssertEqual(Set(question.choices.map { Data($0.utf8) }), Set(original.choices.map { Data($0.utf8) }), context, file: file, line: line)
        XCTAssertEqual(Set(question.choiceExplanations.keys.map { Data($0.utf8) }), Set(original.choices.map { Data($0.utf8) }), context, file: file, line: line)
        for (choice, explanation) in original.choiceExplanations {
            XCTAssertEqual(question.choiceExplanations[choice].map { Data($0.utf8) }, Data(explanation.utf8), context, file: file, line: line)
        }
    }

    private func permutations(_ values: [String]) -> [[String]] {
        guard !values.isEmpty else { return [[]] }
        return values.indices.flatMap { index in
            var rest = values
            let first = rest.remove(at: index)
            return permutations(rest).map { [first] + $0 }
        }
    }
}
