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

    private func permutations(_ values: [String]) -> [[String]] {
        guard !values.isEmpty else { return [[]] }
        return values.indices.flatMap { index in
            var rest = values
            let first = rest.remove(at: index)
            return permutations(rest).map { [first] + $0 }
        }
    }
}
