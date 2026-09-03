import XCTest
@testable import Checkpoint

final class PracticeHistoryReviewPresentationTests: XCTestCase {
    func testAnswerResultPresentationUsesSharedStatusContract() {
        let expectations: [
            (AnswerResult, label: String, systemImage: String, tone: CheckpointAnswerResultTone)
        ] = [
            (.correct, "Correct", "checkmark.circle.fill", .success),
            (.partial, "Almost", "circle.lefthalf.filled", .warning),
            (.incorrect, "Not quite", "xmark.circle.fill", .failure),
            (.unclear, "Needs review", "questionmark.circle.fill", .warning)
        ]

        for (result, expectedLabel, expectedSystemImage, expectedTone) in expectations {
            let presentation = CheckpointAnswerResultPresentation(result: result)

            XCTAssertEqual(presentation.label, expectedLabel, result.rawValue)
            XCTAssertEqual(presentation.systemImage, expectedSystemImage, result.rawValue)
            XCTAssertEqual(presentation.tone, expectedTone, result.rawValue)
        }
    }

    func testPersistedSnapshotWinsAsWholeObjectOverConflictingRetainedQuestion() {
        let questionID = UUID()
        let goalID = UUID()
        let retainedQuestion = makeRetainedQuestion(
            id: questionID,
            goalID: goalID,
            topic: "Live question topic",
            expectedAnswer: "Live question answer",
            explanation: "Live question explanation",
            format: .multipleChoice
        )
        let attempt = makeAttempt(
            questionID: questionID,
            goalID: goalID,
            answer: "Learner answer",
            result: .incorrect,
            reviewSnapshot: CheckpointAttemptReviewSnapshot(
                topic: "Persisted skill",
                format: .reflection,
                referenceAnswer: "Persisted example response",
                explanation: "Persisted explanation"
            )
        )

        let presentation = PracticeHistoryReviewPresentation(
            attempt: attempt,
            retainedQuestion: retainedQuestion
        )

        XCTAssertEqual(presentation.topic, "Persisted skill")
        XCTAssertEqual(presentation.userAnswer, "Learner answer")
        XCTAssertEqual(presentation.referenceLabel, "Example response")
        XCTAssertEqual(presentation.referenceAnswer, "Persisted example response")
        XCTAssertEqual(presentation.explanation, "Persisted explanation")
    }

    func testPersistedSnapshotOmissionsDoNotBackfillFromRetainedQuestion() {
        let questionID = UUID()
        let goalID = UUID()
        let retainedQuestion = makeRetainedQuestion(
            id: questionID,
            goalID: goalID,
            topic: "Live question topic",
            expectedAnswer: "Live question answer",
            explanation: "Live question explanation",
            format: .multipleChoice
        )
        let attempt = makeAttempt(
            questionID: questionID,
            goalID: goalID,
            result: .incorrect,
            reviewSnapshot: CheckpointAttemptReviewSnapshot(
                topic: "  \n",
                format: .shortAnswer,
                referenceAnswer: nil,
                explanation: "\t"
            )
        )

        let presentation = PracticeHistoryReviewPresentation(
            attempt: attempt,
            retainedQuestion: retainedQuestion
        )

        XCTAssertNil(presentation.topic)
        XCTAssertNil(presentation.referenceLabel)
        XCTAssertNil(presentation.referenceAnswer)
        XCTAssertNil(presentation.explanation)
    }

    func testPersistedSnapshotUsesFormatSpecificReferenceLabels() {
        let expectations: [(QuestionFormat, String)] = [
            (.multipleChoice, "Correct answer"),
            (.shortAnswer, "Expected answer"),
            (.codeTrace, "Expected answer"),
            (.reflection, "Example response")
        ]

        for (format, expectedLabel) in expectations {
            let attempt = makeAttempt(
                result: .incorrect,
                reviewSnapshot: CheckpointAttemptReviewSnapshot(
                    topic: "Skill",
                    format: format,
                    referenceAnswer: "Reference for \(format.rawValue)",
                    explanation: "Explanation"
                )
            )

            let presentation = PracticeHistoryReviewPresentation(attempt: attempt)

            XCTAssertEqual(presentation.referenceLabel, expectedLabel, format.rawValue)
            XCTAssertEqual(
                presentation.referenceAnswer,
                "Reference for \(format.rawValue)",
                format.rawValue
            )
        }
    }

    func testCorrectAttemptSuppressesPersistedReferenceAnswer() {
        let attempt = makeAttempt(
            result: .correct,
            reviewSnapshot: CheckpointAttemptReviewSnapshot(
                topic: "Canonical skill",
                format: .multipleChoice,
                referenceAnswer: "A reference that should stay hidden",
                explanation: "The explanation remains useful after a correct answer."
            )
        )

        let presentation = PracticeHistoryReviewPresentation(attempt: attempt)

        XCTAssertEqual(presentation.topic, "Canonical skill")
        XCTAssertNil(presentation.referenceLabel)
        XCTAssertNil(presentation.referenceAnswer)
        XCTAssertEqual(
            presentation.explanation,
            "The explanation remains useful after a correct answer."
        )
    }

    func testWhitespaceOnlyUserAnswerUsesRecordedAnswerFallback() {
        let attempt = makeAttempt(answer: " \n\t ", result: .unclear)

        let presentation = PracticeHistoryReviewPresentation(attempt: attempt)

        XCTAssertEqual(presentation.userAnswer, "No answer recorded")
    }

    func testMatchingRetainedQuestionProvidesLegacyReviewFallback() {
        let questionID = UUID()
        let goalID = UUID()
        let retainedQuestion = makeRetainedQuestion(
            id: questionID,
            goalID: goalID,
            topic: "Legacy topic",
            expectedAnswer: "A stack removes the most recently added item.",
            explanation: "Stacks use last-in, first-out ordering.",
            format: .shortAnswer
        )
        let attempt = makeAttempt(
            questionID: questionID,
            goalID: goalID,
            answer: "The oldest item",
            result: .partial
        )

        let presentation = PracticeHistoryReviewPresentation(
            attempt: attempt,
            retainedQuestion: retainedQuestion
        )

        XCTAssertEqual(presentation.topic, "Legacy topic")
        XCTAssertEqual(presentation.userAnswer, "The oldest item")
        XCTAssertEqual(presentation.referenceLabel, "Expected answer")
        XCTAssertEqual(
            presentation.referenceAnswer,
            "A stack removes the most recently added item."
        )
        XCTAssertEqual(
            presentation.explanation,
            "Stacks use last-in, first-out ordering."
        )
    }

    func testMismatchedRetainedQuestionLeavesLegacyAttemptAtUserAnswerOnly() {
        let attempt = makeAttempt(answer: "Recorded learner answer", result: .incorrect)
        let retainedQuestion = makeRetainedQuestion(
            id: UUID(),
            goalID: attempt.goalID,
            topic: "Unrelated topic",
            expectedAnswer: "Unrelated answer",
            explanation: "Unrelated explanation",
            format: .reflection
        )

        let presentation = PracticeHistoryReviewPresentation(
            attempt: attempt,
            retainedQuestion: retainedQuestion
        )

        assertUserAnswerOnly(presentation, expectedAnswer: "Recorded learner answer")
    }

    func testOrphanedLegacyAttemptWithoutRetainedQuestionShowsUserAnswerOnly() {
        let attempt = makeAttempt(answer: "Orphaned learner answer", result: .incorrect)

        let presentation = PracticeHistoryReviewPresentation(attempt: attempt)

        assertUserAnswerOnly(presentation, expectedAnswer: "Orphaned learner answer")
    }

    private func makeAttempt(
        questionID: CheckpointQuestion.ID = UUID(),
        goalID: Goal.ID = UUID(),
        answer: String = "Learner answer",
        result: AnswerResult,
        reviewSnapshot: CheckpointAttemptReviewSnapshot? = nil
    ) -> CheckpointAttempt {
        CheckpointAttempt(
            questionID: questionID,
            goalID: goalID,
            prompt: "What should the learner know?",
            answer: answer,
            result: result,
            unlockMinutes: 0,
            reviewSnapshot: reviewSnapshot
        )
    }

    private func makeRetainedQuestion(
        id: CheckpointQuestion.ID,
        goalID: Goal.ID,
        topic: String,
        expectedAnswer: String,
        explanation: String,
        format: QuestionFormat
    ) -> CheckpointQuestion {
        CheckpointQuestion(
            id: id,
            goalID: goalID,
            prompt: "Retained question",
            expectedAnswer: expectedAnswer,
            choices: format == .multipleChoice
                ? [expectedAnswer, "Distractor one", "Distractor two", "Distractor three"]
                : [],
            explanation: explanation,
            topic: topic,
            difficulty: 2,
            format: format,
            sourcePrompt: "test"
        )
    }

    private func assertUserAnswerOnly(
        _ presentation: PracticeHistoryReviewPresentation,
        expectedAnswer: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(presentation.userAnswer, expectedAnswer, file: file, line: line)
        XCTAssertNil(presentation.topic, file: file, line: line)
        XCTAssertNil(presentation.referenceLabel, file: file, line: line)
        XCTAssertNil(presentation.referenceAnswer, file: file, line: line)
        XCTAssertNil(presentation.explanation, file: file, line: line)
    }
}
