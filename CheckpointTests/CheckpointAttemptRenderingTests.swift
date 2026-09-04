import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class CheckpointAttemptRenderingTests: XCTestCase {
    @MainActor
    func testResolutionPresentationLeadsWithCheckpointOutcomeAndTruthfulScore() {
        let passAfterMiss = CheckpointResolutionPresentation(
            purpose: .temporaryUnlock,
            didMeetStandard: true,
            correctAnswerCount: 4,
            answeredQuestionCount: 5,
            questionCount: 5,
            requiredCorrectAnswerCount: 4,
            unlockMinutes: 30,
            failureProtectionOutcome: nil
        )

        XCTAssertEqual(passAfterMiss.title, "Checkpoint cleared")
        XCTAssertEqual(passAfterMiss.compactTitle, "Cleared")
        XCTAssertEqual(passAfterMiss.scoreText, "4 of 5 correct")
        XCTAssertEqual(passAfterMiss.scoreComponents, ["4 of 5 correct"])
        XCTAssertEqual(passAfterMiss.compactScoreComponents, ["Score 4 / 5"])
        XCTAssertEqual(passAfterMiss.detail, "Your 30-minute break is ready to begin.")
        XCTAssertEqual(passAfterMiss.systemImage, "checkmark.seal.fill")
        XCTAssertEqual(passAfterMiss.tone, .success)
        XCTAssertEqual(passAfterMiss.actionTitle, "Begin 30-minute break")
        XCTAssertEqual(passAfterMiss.actionSystemImage, "lock.open")

        let failureAfterCorrectAnswer = CheckpointResolutionPresentation(
            purpose: .temporaryUnlock,
            didMeetStandard: false,
            correctAnswerCount: 1,
            answeredQuestionCount: 3,
            questionCount: 5,
            requiredCorrectAnswerCount: 4,
            unlockMinutes: 30,
            failureProtectionOutcome: .protectionRemainsOn,
            cooldownDurationText: "5 minutes"
        )

        XCTAssertEqual(failureAfterCorrectAnswer.title, "Checkpoint not cleared")
        XCTAssertEqual(failureAfterCorrectAnswer.compactTitle, "Not cleared")
        XCTAssertEqual(failureAfterCorrectAnswer.scoreText, "1 correct · 3 of 5 answered")
        XCTAssertEqual(failureAfterCorrectAnswer.scoreComponents, ["1 correct", "3 of 5 answered"])
        XCTAssertEqual(
            failureAfterCorrectAnswer.compactScoreComponents,
            ["1 correct", "3 / 5 done"]
        )
        XCTAssertEqual(
            failureAfterCorrectAnswer.detail,
            "The 4-of-5 standard was no longer reachable. Protection stays on. Try again in 5 minutes, and we'll revisit what you missed."
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
            answeredQuestionCount: 5,
            questionCount: 5,
            requiredCorrectAnswerCount: 4,
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

        let earlyPreview = CheckpointResolutionPresentation(
            purpose: .preview,
            didMeetStandard: false,
            correctAnswerCount: 1,
            answeredQuestionCount: 3,
            questionCount: 5,
            requiredCorrectAnswerCount: 4,
            unlockMinutes: 30,
            failureProtectionOutcome: nil
        )
        XCTAssertEqual(earlyPreview.scoreText, "1 correct · 3 of 5 answered")
        XCTAssertEqual(
            earlyPreview.detail,
            "The 4-of-5 standard was no longer reachable. App protection did not change."
        )

        let unavailable = CheckpointResolutionPresentation(
            purpose: .stopBlocking,
            didMeetStandard: false,
            correctAnswerCount: 1,
            answeredQuestionCount: 5,
            questionCount: 5,
            requiredCorrectAnswerCount: 4,
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
            answeredQuestionCount: 5,
            questionCount: 5,
            requiredCorrectAnswerCount: 4,
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
            answeredQuestionCount: 5,
            questionCount: 5,
            requiredCorrectAnswerCount: 4,
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

        let activeChrome = CheckpointAttemptChromePresentation(
            isResolved: false,
            usesAccessibilityTextSize: false
        )
        XCTAssertTrue(activeChrome.showsProgressHeader)
        XCTAssertEqual(activeChrome.primaryActionPlacement, .pinned)

        let resolvedStandardChrome = CheckpointAttemptChromePresentation(
            isResolved: true,
            usesAccessibilityTextSize: false
        )
        XCTAssertFalse(resolvedStandardChrome.showsProgressHeader)
        XCTAssertEqual(resolvedStandardChrome.primaryActionPlacement, .pinned)

        let resolvedAccessibilityChrome = CheckpointAttemptChromePresentation(
            isResolved: true,
            usesAccessibilityTextSize: true
        )
        XCTAssertFalse(resolvedAccessibilityChrome.showsProgressHeader)
        XCTAssertEqual(resolvedAccessibilityChrome.primaryActionPlacement, .inline)

        let activeAccessibilityChrome = CheckpointAttemptChromePresentation(
            isResolved: false,
            usesAccessibilityTextSize: true
        )
        XCTAssertTrue(activeAccessibilityChrome.showsProgressHeader)
        XCTAssertEqual(activeAccessibilityChrome.primaryActionPlacement, .inline)
    }

    @MainActor
    func testChoiceSelectionOnlyChangesUnlockedAnswersAndRespectsReduceMotion() {
        let standard = CheckpointChoiceSelectionPolicy(reduceMotion: false)
        XCTAssertTrue(standard.usesLinkedSelectionPlate)
        XCTAssertNotNil(standard.animation)

        let reduced = CheckpointChoiceSelectionPolicy(reduceMotion: true)
        XCTAssertFalse(reduced.usesLinkedSelectionPlate)
        XCTAssertNil(reduced.animation)

        XCTAssertEqual(
            CheckpointChoiceSelectionPolicy.decision(
                currentAnswer: "First",
                requestedAnswer: "Second",
                isLocked: false
            ),
            CheckpointChoiceSelectionDecision(
                answer: "Second",
                reportsSelectionFeedback: true
            )
        )
        XCTAssertNil(
            CheckpointChoiceSelectionPolicy.decision(
                currentAnswer: "First",
                requestedAnswer: "First",
                isLocked: false
            )
        )
        XCTAssertNil(
            CheckpointChoiceSelectionPolicy.decision(
                currentAnswer: "First",
                requestedAnswer: "Second",
                isLocked: true
            )
        )
    }

    @MainActor
    func testAnswerProgressionEndsImpossibleAttemptsButCompletesPassingQuestionSet() {
        let goal = makeGoal()
        let questions = (1...5).map { makeQuestion(goal: goal, index: $0) }
        let session = CheckpointSession(
            questions: questions,
            requiredCorrectAnswers: 4,
            purpose: .temporaryUnlock
        )

        let earlyFailure = CheckpointAnswerProgression(
            session: session,
            correctAnswerCount: 1,
            answeredQuestionCount: 3
        )
        XCTAssertTrue(earlyFailure.shouldFinish)
        XCTAssertFalse(earlyFailure.shouldPass)

        let standardMetBeforeFinalQuestion = CheckpointAnswerProgression(
            session: session,
            correctAnswerCount: 4,
            answeredQuestionCount: 4
        )
        XCTAssertFalse(standardMetBeforeFinalQuestion.shouldFinish)
        XCTAssertFalse(standardMetBeforeFinalQuestion.shouldPass)

        let completedPass = CheckpointAnswerProgression(
            session: session,
            correctAnswerCount: 4,
            answeredQuestionCount: 5
        )
        XCTAssertTrue(completedPass.shouldFinish)
        XCTAssertTrue(completedPass.shouldPass)
    }

    @MainActor
    func testAttemptsRenderAcrossSelectionResolutionAndAccessibleLayouts() throws {
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
                name: "attempt-selected-answer-full-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: session,
                        initialPresentation: .selected(
                            questionIndex: 0,
                            answer: questions[0].choices[1]
                        ),
                        reduceMotionOverride: false
                    )
                )
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-selected-answer-narrow-accessibility5-dark-reduced",
                width: 320,
                height: 1_800,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: session,
                        initialPresentation: .selected(
                            questionIndex: 0,
                            answer: questions[0].choices[1]
                        ),
                        reduceMotionOverride: true
                    )
                )
            ),
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
                name: "attempt-fail-early-resolution-standard-dark",
                width: 393,
                height: 852,
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
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-fail-early-resolution-accessibility-dark-reduced",
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
                name: "attempt-fail-early-resolution-narrow-accessibility5-dark-reduced",
                width: 320,
                height: 1_800,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
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
                name: "attempt-fail-early-resolution-accessibility-full-dark-reduced",
                width: 393,
                height: 2_200,
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
                name: "attempt-fail-early-resolution-full-dark",
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
