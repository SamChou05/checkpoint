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

        let standardLayout = CheckpointChoiceLayoutPolicy(
            usesAccessibilityTextSize: false
        )
        XCTAssertEqual(standardLayout.style, .inline)
        XCTAssertEqual(standardLayout.availableTitleWidth(in: 248), 190)

        let accessibilityLayout = CheckpointChoiceLayoutPolicy(
            usesAccessibilityTextSize: true
        )
        XCTAssertEqual(accessibilityLayout.style, .stacked)
        XCTAssertGreaterThanOrEqual(accessibilityLayout.minimumControlHeight, 44)
        XCTAssertEqual(accessibilityLayout.answerGroupHorizontalExpansion, 12)
        XCTAssertEqual(accessibilityLayout.availableTitleWidth(in: 272), 256)
        XCTAssertGreaterThan(
            accessibilityLayout.availableTitleWidth(in: 272),
            standardLayout.availableTitleWidth(in: 248)
        )
    }

    @MainActor
    func testClearanceRunwayMapsEveryAnswerResultWithNonColorSemantics() {
        let presentation = CheckpointRunwayPresentation(
            questionCount: 5,
            currentQuestionIndex: 4,
            answerResults: [.correct, .partial, .incorrect, .unclear],
            requiredCorrectAnswerCount: 4
        )

        XCTAssertEqual(presentation.currentQuestionNumber, 5)
        XCTAssertEqual(presentation.answeredQuestionCount, 4)
        XCTAssertEqual(presentation.correctAnswerCount, 1)
        XCTAssertEqual(presentation.requiredCorrectAnswerCount, 4)
        XCTAssertEqual(
            presentation.nodes.map(\.state),
            [
                .answered(.correct),
                .answered(.partial),
                .answered(.incorrect),
                .answered(.unclear),
                .current,
            ]
        )
        XCTAssertEqual(
            presentation.nodes.map(\.systemImage),
            [
                "checkmark.circle.fill",
                "circle.lefthalf.filled",
                "xmark.circle.fill",
                "questionmark.circle.fill",
                "5.circle.fill",
            ]
        )
        XCTAssertEqual(
            presentation.nodes.map(\.tone),
            [.success, .warning, .failure, .warning, .current]
        )
        XCTAssertEqual(presentation.statusText, "3 more to clear")
        XCTAssertEqual(presentation.statusTone, .progress)
        XCTAssertEqual(
            presentation.accessibilityValue,
            "Question 5 of 5. 4 of 5 answered. 1 of 4 correct. 3 more to clear. "
                + "Answer history. Correct: question 1. Almost: question 2. "
                + "Incorrect: question 3. Needs review: question 4."
        )
    }

    @MainActor
    func testClearanceRunwayRecordsOneResultPerQuestionAndScalesToTwenty() {
        XCTAssertEqual(
            CheckpointRunwayPresentation.recording(
                .partial,
                for: 1,
                in: [.correct, .incorrect, .unclear],
                questionCount: 5
            ),
            [.correct, .partial]
        )
        XCTAssertEqual(
            CheckpointRunwayPresentation.recording(
                .correct,
                for: 0,
                in: [],
                questionCount: 0
            ),
            []
        )

        let results: [AnswerResult] = (0..<12).map { $0 == 4 ? .incorrect : .correct }
        let presentation = CheckpointRunwayPresentation(
            questionCount: 20,
            currentQuestionIndex: 12,
            answerResults: results,
            requiredCorrectAnswerCount: 18
        )

        XCTAssertEqual(presentation.nodes.count, 20)
        XCTAssertEqual(presentation.nodes[11].state, .answered(.correct))
        XCTAssertEqual(presentation.nodes[12].state, .current)
        XCTAssertEqual(presentation.nodes[19].state, .upcoming)
        XCTAssertEqual(presentation.nodes[19].systemImage, "20.circle")
        XCTAssertEqual(presentation.answeredQuestionCount, 12)
        XCTAssertEqual(presentation.correctAnswerCount, 11)
        XCTAssertEqual(presentation.statusText, "7 more to clear")
        XCTAssertEqual(
            presentation.accessibilityValue,
            "Question 13 of 20. 12 of 20 answered. 11 of 18 correct. 7 more to clear. "
                + "Answer history. Correct: questions 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12. "
                + "Incorrect: question 5."
        )
    }

    @MainActor
    func testClearanceRunwaySecuredCopyAndMotionRespectRemainingWorkAndReduceMotion() {
        let secured = CheckpointRunwayPresentation(
            questionCount: 5,
            currentQuestionIndex: 4,
            answerResults: [.correct, .correct, .correct, .correct],
            requiredCorrectAnswerCount: 4
        )
        XCTAssertEqual(secured.statusText, "Standard secured · Final question")
        XCTAssertEqual(secured.statusTone, .secured)

        let securedWithLongRunway = CheckpointRunwayPresentation(
            questionCount: 20,
            currentQuestionIndex: 1,
            answerResults: [.correct, .correct],
            requiredCorrectAnswerCount: 2
        )
        XCTAssertEqual(
            securedWithLongRunway.statusText,
            "Standard secured · 18 questions left"
        )
        XCTAssertEqual(securedWithLongRunway.statusTone, .secured)

        let standard = CheckpointRunwayMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .linked)
        XCTAssertTrue(standard.usesLinkedCurrentMarker)
        XCTAssertNotNil(standard.animation)

        let reduced = CheckpointRunwayMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertFalse(reduced.usesLinkedCurrentMarker)
        XCTAssertNil(reduced.animation)

        XCTAssertEqual(CheckpointAnswerFeedbackSensoryTone(result: .correct), .success)
        for result in [AnswerResult.partial, .incorrect, .unclear] {
            XCTAssertEqual(CheckpointAnswerFeedbackSensoryTone(result: result), .warning)
        }
    }

    @MainActor
    func testClearanceRunwayGeometryStaysContainedAtFiveSevenAndTwentyQuestions() throws {
        let sixQuestionLayout = CheckpointRunwayLayoutMetrics(questionCount: 6)
        XCTAssertFalse(sixQuestionLayout.usesCompactNodes)
        XCTAssertLessThanOrEqual(sixQuestionLayout.minimumRowWidth(nodeCount: 6), 280)

        let sevenQuestionLayout = CheckpointRunwayLayoutMetrics(questionCount: 7)
        XCTAssertTrue(sevenQuestionLayout.usesCompactNodes)
        XCTAssertLessThanOrEqual(sevenQuestionLayout.minimumRowWidth(nodeCount: 7), 280)

        let tenQuestionLayout = CheckpointRunwayLayoutMetrics(questionCount: 10)
        XCTAssertTrue(tenQuestionLayout.usesCompactNodes)
        XCTAssertLessThanOrEqual(tenQuestionLayout.minimumRowWidth(nodeCount: 10), 280)

        let fixtures = [
            CheckpointRunwayGeometryFixture(
                name: "clearance-runway-five-accessibility",
                width: 393,
                height: 852,
                dynamicTypeSize: .accessibility5,
                presentation: CheckpointRunwayPresentation(
                    questionCount: 5,
                    currentQuestionIndex: 2,
                    answerResults: [.correct, .incorrect],
                    requiredCorrectAnswerCount: 4
                ),
                expectedMinimumRunwayHeight: 38,
                expectedMaximumRunwayHeight: 46
            ),
            CheckpointRunwayGeometryFixture(
                name: "clearance-runway-seven-compact",
                width: 320,
                height: 568,
                dynamicTypeSize: .large,
                presentation: CheckpointRunwayPresentation(
                    questionCount: 7,
                    currentQuestionIndex: 3,
                    answerResults: [.correct, .incorrect, .correct],
                    requiredCorrectAnswerCount: 6
                ),
                expectedMinimumRunwayHeight: 26,
                expectedMaximumRunwayHeight: 34
            ),
            CheckpointRunwayGeometryFixture(
                name: "clearance-runway-twenty",
                width: 320,
                height: 568,
                dynamicTypeSize: .large,
                presentation: CheckpointRunwayPresentation(
                    questionCount: 20,
                    currentQuestionIndex: 12,
                    answerResults: (0..<12).map { $0 == 4 ? .incorrect : .correct },
                    requiredCorrectAnswerCount: 18
                ),
                expectedMinimumRunwayHeight: 60,
                expectedMaximumRunwayHeight: 90
            ),
        ]

        for fixture in fixtures {
            let capture = CheckpointRunwayGeometryCapture()
            let image = HostedViewRenderer.image(
                for: CheckpointRunwayGeometryScene(
                    presentation: fixture.presentation,
                    capture: capture
                )
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: .light,
                settlingTime: 0.15,
                renderScale: 1
            )

            let runwaySize = try XCTUnwrap(capture.runwaySize, fixture.name)
            XCTAssertEqual(runwaySize.width, fixture.width - 40, accuracy: 0.5, fixture.name)
            XCTAssertGreaterThanOrEqual(
                runwaySize.height,
                fixture.expectedMinimumRunwayHeight,
                fixture.name
            )
            XCTAssertLessThanOrEqual(
                runwaySize.height,
                fixture.expectedMaximumRunwayHeight,
                fixture.name
            )
            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
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
            let choiceLayoutCapture = CheckpointAttemptChoiceLayoutCapture()
            let image = HostedViewRenderer.image(
                for: CheckpointAttemptChoiceLayoutScene(
                    content: AnyView(
                        fixture.content
                            .environment(\.colorScheme, fixture.colorScheme)
                            .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)
                    ),
                    capture: choiceLayoutCapture
                ),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)

            switch fixture.name {
            case "attempt-selected-answer-full-light":
                try assertChoiceLayout(
                    choiceLayoutCapture,
                    titles: questions[0].choices,
                    style: .inline,
                    viewportWidth: fixture.width,
                    fixtureName: fixture.name
                )
            case "attempt-selected-answer-narrow-accessibility5-dark-reduced":
                try assertChoiceLayout(
                    choiceLayoutCapture,
                    titles: questions[0].choices,
                    style: .stacked,
                    viewportWidth: fixture.width,
                    fixtureName: fixture.name
                )
            default:
                break
            }

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func assertChoiceLayout(
        _ capture: CheckpointAttemptChoiceLayoutCapture,
        titles: [String],
        style: CheckpointChoiceLayoutStyle,
        viewportWidth: CGFloat,
        fixtureName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let frames = capture.frames
        let questionPanel = try XCTUnwrap(
            frames[.questionPanel],
            "\(fixtureName): missing question panel frame",
            file: file,
            line: line
        )
        let answerGroup = try XCTUnwrap(
            frames[.answerGroup],
            "\(fixtureName): missing answer group frame",
            file: file,
            line: line
        )
        let layout = CheckpointChoiceLayoutPolicy(
            usesAccessibilityTextSize: style == .stacked
        )
        let expectedControlWidth = viewportWidth - 72
            + layout.answerGroupHorizontalExpansion * 2
        let containmentTolerance: CGFloat = 0.75
        let expandedPanel = questionPanel.insetBy(
            dx: -containmentTolerance,
            dy: -containmentTolerance
        )
        let expandedGroup = answerGroup.insetBy(
            dx: -containmentTolerance,
            dy: -containmentTolerance
        )

        XCTAssertTrue(
            expandedPanel.contains(answerGroup),
            "\(fixtureName): answer group must remain inside its question panel",
            file: file,
            line: line
        )

        var controls: [CGRect] = []
        for title in titles {
            let control = try XCTUnwrap(
                frames[.control(title)],
                "\(fixtureName): missing control frame for \(title)",
                file: file,
                line: line
            )
            let indicator = try XCTUnwrap(
                frames[.indicator(title)],
                "\(fixtureName): missing indicator frame for \(title)",
                file: file,
                line: line
            )
            let titleFrame = try XCTUnwrap(
                frames[.title(title)],
                "\(fixtureName): missing title frame for \(title)",
                file: file,
                line: line
            )
            let expandedControl = control.insetBy(
                dx: -containmentTolerance,
                dy: -containmentTolerance
            )

            controls.append(control)
            XCTAssertTrue(
                expandedGroup.contains(control),
                "\(fixtureName): choice must remain inside the answer group",
                file: file,
                line: line
            )
            XCTAssertTrue(
                expandedControl.contains(indicator),
                "\(fixtureName): indicator must remain inside its control",
                file: file,
                line: line
            )
            XCTAssertTrue(
                expandedControl.contains(titleFrame),
                "\(fixtureName): title must remain inside its control",
                file: file,
                line: line
            )
            XCTAssertEqual(
                control.width,
                expectedControlWidth,
                accuracy: 1,
                "\(fixtureName): choices must fill the available panel width",
                file: file,
                line: line
            )
            XCTAssertGreaterThanOrEqual(
                control.height,
                layout.minimumControlHeight,
                "\(fixtureName): choices must preserve a 44-point-or-larger target",
                file: file,
                line: line
            )
            XCTAssertEqual(
                titleFrame.width,
                layout.availableTitleWidth(in: control.width),
                accuracy: 1,
                "\(fixtureName): title should receive its intended text column",
                file: file,
                line: line
            )

            switch style {
            case .inline:
                XCTAssertLessThanOrEqual(
                    indicator.maxX + layout.contentSpacing,
                    titleFrame.minX + containmentTolerance,
                    "\(fixtureName): regular layout keeps the title beside the indicator",
                    file: file,
                    line: line
                )
            case .stacked:
                XCTAssertLessThanOrEqual(
                    indicator.maxY + layout.contentSpacing,
                    titleFrame.minY + containmentTolerance,
                    "\(fixtureName): accessibility layout keeps the title below the indicator",
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    titleFrame.minX,
                    control.minX + layout.contentPadding,
                    accuracy: 1,
                    "\(fixtureName): accessibility title should align to the full-width inset",
                    file: file,
                    line: line
                )
            }
        }

        for (upper, lower) in zip(controls, controls.dropFirst()) {
            XCTAssertEqual(
                lower.minY - upper.maxY,
                10,
                accuracy: 1,
                "\(fixtureName): choices should keep consistent vertical separation",
                file: file,
                line: line
            )
        }

        guard style == .stacked else { return }

        let traits = UITraitCollection(
            preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        let pointSize = UIFont.preferredFont(
            forTextStyle: .footnote,
            compatibleWith: traits
        ).pointSize
        let titleFont = UIFont.systemFont(ofSize: pointSize, weight: .semibold)
        for title in titles {
            let titleFrame = try XCTUnwrap(frames[.title(title)], file: file, line: line)
            let widestWord = title
                .split(whereSeparator: \.isWhitespace)
                .map {
                    ceil(
                        (String($0) as NSString).size(
                            withAttributes: [.font: titleFont]
                        ).width
                    )
                }
                .max() ?? 0
            XCTAssertLessThanOrEqual(
                widestWord,
                titleFrame.width,
                "\(fixtureName): full words must fit without forced fragmentation",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    func testReviewedStatesAndHighCountRunwayRenderAcrossRealViewports() throws {
        let suiteName = "CheckpointAttemptReviewedRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let goal = makeGoal()
        let multipleChoiceQuestions = (1...5).map { index in
            makeQuestion(
                goal: goal,
                index: index,
                topic: "State modeling",
                prompt: "Which choice preserves the system invariant in scenario \(index)?",
                expectedAnswer: "Validate the invariant before committing state",
                choices: [
                    "Validate the invariant before committing state",
                    "Commit dependent state before validation",
                    "Skip validation for this update",
                    "Reset every dependency",
                ],
                explanation: "The correct choice preserves the invariant before any dependent state is updated."
            )
        }
        let reflectionQuestions = (1...5).map { index in
            makeReflectionAttemptQuestion(goal: goal, index: index)
        }
        let stopBlockingQuestions = (1...20).map { index in
            makeQuestion(
                goal: goal,
                index: index,
                topic: "Recovery sequence",
                prompt: "Choose the safest recovery step for scenario \(index)."
            )
        }
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = multipleChoiceQuestions

        let multipleChoiceSession = CheckpointSession(
            questions: multipleChoiceQuestions,
            requiredCorrectAnswers: 4,
            purpose: .temporaryUnlock
        )
        let reflectionSession = CheckpointSession(
            questions: reflectionQuestions,
            requiredCorrectAnswers: 4,
            purpose: .preview
        )
        let stopBlockingSession = CheckpointSession(
            questions: stopBlockingQuestions,
            requiredCorrectAnswers: StopBlockingPolicy.requiredCorrectAnswers,
            purpose: .stopBlocking
        )
        let longSecuredPreviewSession = CheckpointSession(
            questions: stopBlockingQuestions,
            requiredCorrectAnswers: 2,
            purpose: .preview
        )
        let workflow = CheckpointWorkflowCoordinator(
            store: store,
            protection: InertAttemptProtectionController()
        )
        let stopBlockingPreviousResults: [AnswerResult] = (0..<12).map {
            $0 == 4 ? .incorrect : .correct
        }
        let fixtures = [
            CheckpointAttemptRenderFixture(
                name: "attempt-reviewed-correct-full-light",
                width: 393,
                height: 1_400,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: multipleChoiceSession,
                        initialPresentation: .reviewed(
                            questionIndex: 1,
                            previousResults: [.incorrect],
                            answer: multipleChoiceQuestions[1].expectedAnswer,
                            result: .correct
                        ),
                        reduceMotionOverride: false
                    )
                )
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-reviewed-incorrect-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: multipleChoiceSession,
                        initialPresentation: .reviewed(
                            questionIndex: 1,
                            previousResults: [.correct],
                            answer: multipleChoiceQuestions[1].choices[1],
                            result: .incorrect
                        ),
                        reduceMotionOverride: false
                    )
                )
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-reviewed-partial-preview-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: reflectionSession,
                        initialPresentation: .reviewed(
                            questionIndex: 1,
                            previousResults: [.correct],
                            answer: "I identified the invariant but missed one dependency.",
                            result: .partial
                        ),
                        reduceMotionOverride: false
                    )
                )
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-reviewed-unclear-preview-accessibility2-dark-reduced",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: reflectionSession,
                        initialPresentation: .reviewed(
                            questionIndex: 1,
                            previousResults: [.correct],
                            answer: "I need to revisit how the recovery dependencies interact.",
                            result: .unclear
                        ),
                        reduceMotionOverride: true
                    )
                )
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-reviewed-stop-blocking-twenty-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: stopBlockingSession,
                        initialPresentation: .reviewed(
                            questionIndex: 12,
                            previousResults: stopBlockingPreviousResults,
                            answer: stopBlockingQuestions[12].choices[1],
                            result: .incorrect
                        ),
                        reduceMotionOverride: false
                    )
                )
            ),
            CheckpointAttemptRenderFixture(
                name: "attempt-standard-secured-long-accessibility5-dark-reduced",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    CheckpointAttemptView(
                        store: store,
                        workflow: workflow,
                        session: longSecuredPreviewSession,
                        initialPresentation: .reviewed(
                            questionIndex: 1,
                            previousResults: [.correct],
                            answer: stopBlockingQuestions[1].expectedAnswer,
                            result: .correct
                        ),
                        reduceMotionOverride: true
                    )
                )
            ),
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
private final class CheckpointAttemptChoiceLayoutCapture {
    var frames: [CheckpointChoiceLayoutElement: CGRect] = [:]

    func record(_ updatedFrames: [CheckpointChoiceLayoutElement: CGRect]) {
        frames.merge(updatedFrames, uniquingKeysWith: { _, latest in latest })
    }
}

private struct CheckpointAttemptChoiceLayoutScene: View {
    let content: AnyView
    let capture: CheckpointAttemptChoiceLayoutCapture

    var body: some View {
        content
            .overlayPreferenceValue(CheckpointChoiceLayoutPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    let frames = anchors.mapValues { proxy[$0] }

                    Color.clear
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .onAppear {
                            capture.record(frames)
                        }
                        .onChange(of: frames) { _, updatedFrames in
                            capture.record(updatedFrames)
                        }
                }
            }
    }
}

private func makeReflectionAttemptQuestion(
    goal: Goal,
    index: Int
) -> CheckpointQuestion {
    CheckpointQuestion(
        goalID: goal.id,
        prompt: "Explain how you would preserve the recovery invariant in scenario \(index).",
        expectedAnswer: "Validate every dependency before committing the recovery state.",
        choices: [],
        explanation: "A safe recovery validates each dependency before it commits any related state.",
        topic: "Recovery reflection",
        difficulty: 3,
        format: .reflection,
        sourcePrompt: "test"
    )
}

private struct CheckpointRunwayGeometryFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let dynamicTypeSize: DynamicTypeSize
    let presentation: CheckpointRunwayPresentation
    let expectedMinimumRunwayHeight: CGFloat
    let expectedMaximumRunwayHeight: CGFloat
}

@MainActor
private final class CheckpointRunwayGeometryCapture {
    var runwaySize: CGSize?
}

private struct CheckpointRunwayGeometryScene: View {
    let presentation: CheckpointRunwayPresentation
    let capture: CheckpointRunwayGeometryCapture

    @Namespace private var currentMarkerNamespace

    var body: some View {
        VStack {
            CheckpointClearanceRunway(
                presentation: presentation,
                motionPolicy: CheckpointRunwayMotionPolicy(reduceMotion: true),
                currentMarkerNamespace: currentMarkerNamespace
            )
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            capture.runwaySize = proxy.size
                        }
                        .onChange(of: proxy.size) { _, size in
                            capture.runwaySize = size
                        }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .checkpointScreenBackground()
    }
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
