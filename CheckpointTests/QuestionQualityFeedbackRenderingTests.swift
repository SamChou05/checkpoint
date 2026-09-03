import SwiftUI
import XCTest
@testable import Checkpoint

final class QuestionQualityFeedbackRenderingTests: XCTestCase {
    func testQuestionQualityFeedbackCopyDescribesBehaviorAndDataUse() {
        let newPresentation = QuestionQualityFeedbackPresentation(existingReason: nil)
        let editPresentation = QuestionQualityFeedbackPresentation(existingReason: .confusing)

        XCTAssertEqual(newPresentation.title, "Remove this question?")
        XCTAssertEqual(newPresentation.actionTitle, "Remove from practice")
        XCTAssertEqual(newPresentation.successTitle, "Removed from future practice")
        XCTAssertEqual(editPresentation.title, "Update why it was removed")
        XCTAssertEqual(editPresentation.actionTitle, "Update reason")
        XCTAssertEqual(editPresentation.successTitle, "Reason updated")
        XCTAssertTrue(
            QuestionQualityFeedbackPresentation.supportsRemoval(in: .temporaryUnlock)
        )
        XCTAssertTrue(
            QuestionQualityFeedbackPresentation.supportsRemoval(in: .stopBlocking)
        )
        XCTAssertFalse(
            QuestionQualityFeedbackPresentation.supportsRemoval(in: .preview)
        )
        XCTAssertEqual(
            QuestionQualityFeedbackPresentation.successDetail,
            "Your saved answer and checkpoint result are unchanged."
        )
        XCTAssertEqual(
            QuestionQualityFeedbackPresentation.failureDetail,
            "Couldn’t save this change. Check available device storage and try again."
        )
        XCTAssertEqual(
            QuestionQualityFeedbackPresentation.historyBadgeTitle,
            "QUESTION REMOVED"
        )
        XCTAssertTrue(
            QuestionQualityFeedbackPresentation.dataUseDetail.contains("question’s text")
        )
        XCTAssertTrue(
            QuestionQualityFeedbackPresentation.dataUseDetail.contains("not your selected reason")
        )
        XCTAssertTrue(
            QuestionQualityFeedbackPresentation.dataUseDetail.contains("doesn’t create a support ticket")
        )
    }

    func testQuestionRemovalControlPresentsAvailableAndRemovedStates() {
        let available = QuestionRemovalControlPresentation(report: nil)
        XCTAssertEqual(available.title, "Question issue?")
        XCTAssertEqual(available.actionTitle, "Remove")

        let report = makeQuestionReport(for: makeQuestion(goal: makeGoal(), index: 1), note: "")
        let removed = QuestionRemovalControlPresentation(report: report)
        XCTAssertEqual(removed.title, "Removed from future practice")
        XCTAssertEqual(removed.detail, QuestionReportReason.confusing.rawValue)
        XCTAssertEqual(removed.actionTitle, "Edit")
        XCTAssertTrue(removed.accessibilityLabel.contains("Reason"))
    }

    func testQuestionReportReasonsHaveStableUserFacingOrderAndDetails() {
        XCTAssertEqual(
            QuestionReportReason.allCases,
            [.wrongAnswer, .confusing, .irrelevant, .tooEasy, .tooHard]
        )
        XCTAssertTrue(
            QuestionReportReason.allCases.allSatisfy {
                let presentation = QuestionReportReasonPresentation(reason: $0)
                return !presentation.title.isEmpty &&
                    !presentation.detail.isEmpty &&
                    !presentation.systemImage.isEmpty
            }
        )
    }

    @MainActor
    func testQuestionQualityFeedbackRendersAcrossKeyLayouts() {
        let fixtures = [
            QuestionQualityRenderFixture(
                name: "question-quality-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                existingReason: nil
            ),
            QuestionQualityRenderFixture(
                name: "question-quality-dark-selected",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                existingReason: .wrongAnswer
            ),
            QuestionQualityRenderFixture(
                name: "question-quality-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                existingReason: nil
            ),
            QuestionQualityRenderFixture(
                name: "question-quality-accessibility",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                existingReason: .irrelevant
            )
        ]

        for fixture in fixtures {
            let context = QuestionQualityFeedbackContext(
                questionID: UUID(),
                goalID: UUID(),
                prompt: "Which option best explains why a recursive call needs a clear base case?",
                existingReason: fixture.existingReason
            )
            let image = HostedViewRenderer.image(
                for: QuestionQualityFeedbackView(context: context, submit: { _ in true })
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme
            )

            XCTAssertEqual(image.size.width, fixture.width)
            XCTAssertEqual(image.size.height, fixture.height)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testQuestionRemovalControlsRenderInAvailableAndRemovedStates() {
        let goal = makeGoal()
        let question = makeQuestion(goal: goal, index: 1)
        let report = QuestionQualityReport(
            questionID: question.id,
            goalID: goal.id,
            prompt: question.prompt,
            reason: .wrongAnswer,
            note: ""
        )
        let surface = ScrollView {
            VStack(spacing: 14) {
                QuestionRemovalControl(report: nil, action: {})
                QuestionRemovalControl(report: report, action: {})
            }
            .padding(20)
        }
        .checkpointScreenBackground()
        let image = HostedViewRenderer.image(
            for: surface,
            width: 393,
            height: 300,
            colorScheme: .light
        )

        XCTAssertEqual(image.size, CGSize(width: 393, height: 300))
        let attachment = XCTAttachment(image: image)
        attachment.name = "question-removal-controls"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testQuestionQualitySuccessRendersWithPreservedResultCopy() {
        let context = QuestionQualityFeedbackContext(
            questionID: UUID(),
            goalID: UUID(),
            prompt: "Which prompt was removed?",
            existingReason: .wrongAnswer
        )
        let image = HostedViewRenderer.image(
            for: QuestionQualityFeedbackView(
                context: context,
                initiallySaved: true,
                submit: { _ in true }
            ),
            width: 393,
            height: 568,
            colorScheme: .light
        )

        XCTAssertEqual(image.size, CGSize(width: 393, height: 568))
        let attachment = XCTAttachment(image: image)
        attachment.name = "question-quality-success"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLongQuestionRendersInScrollableFeedbackSheet() {
        let context = QuestionQualityFeedbackContext(
            questionID: UUID(),
            goalID: UUID(),
            prompt: "A learner builds a recursive parser that handles nested expressions, optional whitespace, operator precedence, malformed input, and a maximum nesting depth. Which base cases are required to guarantee termination while still returning a useful error for incomplete input?",
            existingReason: nil
        )
        let image = HostedViewRenderer.image(
            for: QuestionQualityFeedbackView(context: context, submit: { _ in true }),
            width: 393,
            height: 852,
            colorScheme: .light
        )

        XCTAssertEqual(image.size, CGSize(width: 393, height: 852))
        let attachment = XCTAttachment(image: image)
        attachment.name = "question-quality-long-prompt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct QuestionQualityRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var existingReason: QuestionReportReason?
}
