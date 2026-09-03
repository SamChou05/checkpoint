import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class CheckpointAttemptRenderingTests: XCTestCase {
    @MainActor
    func testResolutionPresentationLeadsWithCheckpointOutcomeWhenFinalAnswerDiffers() {
        let passAfterMiss = CheckpointResolutionPresentation(
            purpose: .temporaryUnlock,
            didMeetStandard: true,
            correctAnswerCount: 4,
            questionCount: 5,
            unlockMinutes: 30,
            failureProtectionOutcome: nil
        )

        XCTAssertEqual(passAfterMiss.title, "Checkpoint cleared")
        XCTAssertEqual(passAfterMiss.scoreText, "4 of 5 correct")
        XCTAssertEqual(passAfterMiss.detail, "Your 30-minute break is ready to begin.")
        XCTAssertEqual(passAfterMiss.systemImage, "checkmark.seal.fill")
        XCTAssertEqual(passAfterMiss.tone, .success)
        XCTAssertEqual(passAfterMiss.actionTitle, "Begin 30-minute break")
        XCTAssertEqual(passAfterMiss.actionSystemImage, "lock.open")

        let failureAfterCorrectAnswer = CheckpointResolutionPresentation(
            purpose: .temporaryUnlock,
            didMeetStandard: false,
            correctAnswerCount: 1,
            questionCount: 5,
            unlockMinutes: 30,
            failureProtectionOutcome: .protectionRemainsOn,
            cooldownDurationText: "5 minutes"
        )

        XCTAssertEqual(failureAfterCorrectAnswer.title, "Checkpoint not cleared")
        XCTAssertEqual(failureAfterCorrectAnswer.scoreText, "1 of 5 correct")
        XCTAssertEqual(
            failureAfterCorrectAnswer.detail,
            "Protection stays on. Try again in 5 minutes, and we'll revisit what you missed."
        )
        XCTAssertEqual(failureAfterCorrectAnswer.systemImage, "arrow.counterclockwise.circle.fill")
        XCTAssertEqual(failureAfterCorrectAnswer.tone, .needsPractice)
        XCTAssertEqual(failureAfterCorrectAnswer.actionTitle, "Return home")
        XCTAssertEqual(failureAfterCorrectAnswer.actionSystemImage, "house")
    }

    @MainActor
    func testResolutionPresentationExplainsPreviewAndUnavailableProtectionStates() {
        let preview = CheckpointResolutionPresentation(
            purpose: .preview,
            didMeetStandard: false,
            correctAnswerCount: 2,
            questionCount: 5,
            unlockMinutes: 30,
            failureProtectionOutcome: nil
        )

        XCTAssertEqual(preview.eyebrow, "PRACTICE RESULT")
        XCTAssertEqual(preview.title, "Practice complete")
        XCTAssertEqual(
            preview.detail,
            "You didn't meet the practice standard yet. App protection did not change."
        )
        XCTAssertEqual(preview.actionTitle, "Finish")
        XCTAssertEqual(preview.actionSystemImage, "checkmark.seal")

        let unavailable = CheckpointResolutionPresentation(
            purpose: .stopBlocking,
            didMeetStandard: false,
            correctAnswerCount: 1,
            questionCount: 5,
            unlockMinutes: 30,
            failureProtectionOutcome: .protectionTurnedOffForUnavailableCheckpoint
        )

        XCTAssertEqual(
            unavailable.detail,
            "Protection was turned off because another full checkpoint isn't ready. Prepare questions before starting it again."
        )
        XCTAssertEqual(unavailable.actionTitle, "Return home")

        let activeBreak = CheckpointResolutionPresentation(
            purpose: .stopBlocking,
            didMeetStandard: false,
            correctAnswerCount: 1,
            questionCount: 5,
            unlockMinutes: 30,
            failureProtectionOutcome: .activeBreakContinues
        )

        XCTAssertEqual(
            activeBreak.detail,
            "Your break continues. Check Home when it ends to confirm protection status."
        )

        let actionFailure = CheckpointProtectionActionFailurePresentation(
            purpose: .temporaryUnlock,
            detail: "The break could not start. Protection is still on; try again."
        )
        XCTAssertEqual(actionFailure.title, "Break didn't start")
        XCTAssertEqual(
            actionFailure.detail,
            "The break could not start. Protection is still on; try again."
        )

        let actionFailureResolution = CheckpointResolutionPresentation(
            purpose: .temporaryUnlock,
            didMeetStandard: true,
            correctAnswerCount: 4,
            questionCount: 5,
            unlockMinutes: 30,
            failureProtectionOutcome: nil,
            protectionActionFailed: true
        )
        XCTAssertEqual(
            actionFailureResolution.detail,
            "You met the standard, but the break didn't start."
        )
    }

    @MainActor
    func testResolutionMotionAndFocusPoliciesRespectTerminalStateAndReduceMotion() {
        let standard = CheckpointResolutionMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .choreographed)
        XCTAssertNotNil(standard.animation)

        let reduced = CheckpointResolutionMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)

        XCTAssertEqual(
            CheckpointFeedbackDestination.resolve(shouldFinish: false),
            .answerFeedback
        )
        XCTAssertEqual(
            CheckpointFeedbackDestination.resolve(shouldFinish: true),
            .resolution
        )
    }

    @MainActor
    func testContradictoryFinalAnswerStatesRenderAcrossCompactAndAccessibleLayouts() throws {
        let suiteName = "CheckpointAttemptRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let goal = makeGoal()
        let questions = (1...5).map { index in
            makeQuestion(
                goal: goal,
                index: index,
                topic: index == 5 ? "Failure recovery" : "State modeling",
                prompt: "Which choice preserves the system invariant in scenario \(index)?",
                expectedAnswer: "Validate the invariant before committing state",
                choices: [
                    "Validate the invariant before committing state",
                    "Commit dependent state before validation",
                    "Skip validation for this update",
                    "Reset every dependency"
                ],
                explanation: "The correct choice preserves the invariant before any dependent state is updated."
            )
        }
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = questions
        XCTAssertTrue(store.hasReadyCheckpointSet)

        let session = CheckpointSession(
            questions: questions,
            requiredCorrectAnswers: 4,
            purpose: .temporaryUnlock
        )
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: InertAttemptProtectionController()
        )
        let fixtures = [
            CheckpointAttemptRenderFixture(
                name: "attempt-pass-final-miss-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: session,
                        initialPresentation: .terminal(
                            questionIndex: 4,
                            correctAnswerCount: 4,
                            answer: questions[4].choices[1],
                            result: .incorrect,
                            didPass: true
                        ),
                        reduceMotionOverride: false
                    )
                )
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-pass-final-miss-full-light",
                width: 393,
                height: 1_400,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: session,
                        initialPresentation: .terminal(
                            questionIndex: 4,
                            correctAnswerCount: 4,
                            answer: questions[4].choices[1],
                            result: .incorrect,
                            didPass: true
                        ),
                        reduceMotionOverride: false
                    )
                )
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-pass-action-failure-compact-light",
                width: 320,
                height: 760,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: session,
                        initialPresentation: .terminal(
                            questionIndex: 4,
                            correctAnswerCount: 4,
                            answer: questions[4].choices[1],
                            result: .incorrect,
                            didPass: true,
                            actionErrorMessage: "The break could not start. Protection is still on; try again."
                        ),
                        reduceMotionOverride: false
                    )
                )
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-fail-final-correct-accessibility-dark-reduced",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: session,
                        initialPresentation: .terminal(
                            questionIndex: 2,
                            correctAnswerCount: 1,
                            answer: questions[2].expectedAnswer,
                            result: .correct,
                            didPass: false
                        ),
                        reduceMotionOverride: true
                    )
                )
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-fail-final-correct-full-dark",
                width: 393,
                height: 1_400,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: session,
                        initialPresentation: .terminal(
                            questionIndex: 2,
                            correctAnswerCount: 1,
                            answer: questions[2].expectedAnswer,
                            result: .correct,
                            didPass: false
                        ),
                        reduceMotionOverride: false
                    )
                )
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: fixture.content
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

private struct CheckpointAttemptRenderFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let content: AnyView
}

@MainActor
private final class InertAttemptProtectionController: AppProtectionControlling {
    let hasSelection = true
    var isShieldingEnabled = true
    var userFacingErrorMessage: String?

    func applyShield() {
        isShieldingEnabled = true
    }

    func clearShield() {
        isShieldingEnabled = false
    }

    func temporarilyUnshield(until expiration: Date) -> Bool {
        isShieldingEnabled = false
        return true
    }

    func reconcileShieldState(protectionShouldRemainActive: Bool?) {
        isShieldingEnabled = protectionShouldRemainActive == true
    }

    func refreshActiveShieldConfiguration() {}
}
