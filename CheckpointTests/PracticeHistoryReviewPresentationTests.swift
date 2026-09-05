import SwiftUI
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

    func testArchiveDefaultsToAllGoalsAndKeepsMetricsScopedBeforeFiltering() {
        let fixture = makeArchiveFixture()

        let presentation = PracticeHistoryArchivePresentation(
            allAttempts: fixture.attempts,
            goalProfiles: [fixture.activeGoal, fixture.otherGoal, fixture.emptyGoal],
            activeGoalID: fixture.activeGoal.id,
            requestedScope: nil,
            filter: .review
        )

        XCTAssertEqual(presentation.scope, .all)
        XCTAssertEqual(
            presentation.goalOptions.map(\.id),
            [fixture.activeGoal.id, fixture.otherGoal.id, fixture.emptyGoal.id]
        )
        XCTAssertEqual(presentation.goalOptions.map(\.isCurrent), [true, false, false])
        XCTAssertEqual(
            presentation.scopedAttempts.map(\.prompt),
            [
                "Which launch constraint should be verified first?",
                "Choose the correct past-tense response.",
                "Which dependency creates the largest recovery risk?",
                "Translate the customer greeting."
            ]
        )
        XCTAssertEqual(
            presentation.filteredAttempts.map(\.prompt),
            [
                "Choose the correct past-tense response.",
                "Which dependency creates the largest recovery risk?"
            ]
        )
        XCTAssertEqual(presentation.correctCount, 2)
        XCTAssertEqual(presentation.reviewCount, 2)
        XCTAssertEqual(presentation.accuracyPercent, 50)
        XCTAssertEqual(presentation.scopeTitle, "All goals")
        XCTAssertEqual(presentation.summaryContext, "Across 2 goals")
        XCTAssertTrue(presentation.showsScopePicker)
        XCTAssertTrue(presentation.showsGoalIdentity)
        XCTAssertFalse(presentation.isGloballyEmpty)
        XCTAssertFalse(presentation.isScopeEmpty)
        XCTAssertEqual(presentation.filteredEmptyTitle, "Nothing to revisit")
        XCTAssertEqual(presentation.filteredEmptyDetail, "Every recorded answer is correct.")
    }

    func testArchivePerGoalScopeComposesWithFilterWithoutChangingSummaryMetrics() {
        let fixture = makeArchiveFixture()

        let presentation = PracticeHistoryArchivePresentation(
            allAttempts: fixture.attempts,
            goalProfiles: [fixture.activeGoal, fixture.otherGoal, fixture.emptyGoal],
            activeGoalID: fixture.activeGoal.id,
            requestedScope: .goal(fixture.otherGoal.id),
            filter: .correct
        )

        XCTAssertEqual(presentation.scope, .goal(fixture.otherGoal.id))
        XCTAssertEqual(
            presentation.scopedAttempts.map(\.prompt),
            ["Choose the correct past-tense response.", "Translate the customer greeting."]
        )
        XCTAssertEqual(
            presentation.filteredAttempts.map(\.prompt),
            ["Translate the customer greeting."]
        )
        XCTAssertEqual(presentation.correctCount, 1)
        XCTAssertEqual(presentation.reviewCount, 1)
        XCTAssertEqual(presentation.accuracyPercent, 50)
        XCTAssertEqual(presentation.scopeTitle, fixture.otherGoal.title)
        XCTAssertEqual(presentation.summaryContext, "For this goal")
        XCTAssertFalse(presentation.showsGoalIdentity)
        XCTAssertFalse(presentation.isScopeEmpty)
        XCTAssertTrue(presentation.supportingCopy.contains(fixture.otherGoal.title))
    }

    func testArchiveUsesDescendingUUIDAsDeterministicTieBreakerForSameDate() {
        let goal = makeArchiveGoal(
            id: fixedUUID("00000000-0000-0000-0000-000000000401"),
            title: "Practice deterministic ordering",
            deadline: fixedReferenceDate.addingTimeInterval(86_400 * 30),
            createdAt: fixedReferenceDate
        )
        let sharedDate = fixedReferenceDate.addingTimeInterval(-3_600)
        let low = makeArchiveAttempt(
            id: fixedUUID("00000000-0000-0000-0000-000000000001"),
            questionID: fixedUUID("00000000-0000-0000-0000-000000000411"),
            goalID: goal.id,
            prompt: "Low UUID",
            result: .correct,
            createdAt: sharedDate
        )
        let middle = makeArchiveAttempt(
            id: fixedUUID("00000000-0000-0000-0000-00000000000A"),
            questionID: fixedUUID("00000000-0000-0000-0000-000000000412"),
            goalID: goal.id,
            prompt: "Middle UUID",
            result: .correct,
            createdAt: sharedDate
        )
        let high = makeArchiveAttempt(
            id: fixedUUID("00000000-0000-0000-0000-00000000000F"),
            questionID: fixedUUID("00000000-0000-0000-0000-000000000413"),
            goalID: goal.id,
            prompt: "High UUID",
            result: .correct,
            createdAt: sharedDate
        )

        let presentation = PracticeHistoryArchivePresentation(
            allAttempts: [middle, low, high],
            goalProfiles: [goal],
            activeGoalID: goal.id,
            requestedScope: .goal(goal.id),
            filter: .all
        )

        XCTAssertEqual(presentation.scopedAttempts.map(\.id), [high.id, middle.id, low.id])
    }

    func testArchiveDisambiguatesEquivalentGoalTitlesWithDueDates() throws {
        let goals = makeDuplicateTitleGoals()

        let presentation = PracticeHistoryArchivePresentation(
            allAttempts: [],
            goalProfiles: [goals.first, goals.second],
            activeGoalID: goals.first.id,
            requestedScope: .all,
            filter: .all
        )

        let firstTitle = try XCTUnwrap(
            presentation.goalOptions.first { $0.id == goals.first.id }?.title
        )
        let secondTitle = try XCTUnwrap(
            presentation.goalOptions.first { $0.id == goals.second.id }?.title
        )
        XCTAssertTrue(firstTitle.hasPrefix("Résumé mastery · due "))
        XCTAssertTrue(secondTitle.hasPrefix("resume mastery · due "))
        XCTAssertNotEqual(firstTitle, secondTitle)
        XCTAssertEqual(presentation.goalTitle(for: goals.first.id), firstTitle)
        XCTAssertEqual(presentation.goalTitle(for: goals.second.id), secondTitle)
    }

    func testArchiveAddsStableProfileSuffixesWhenEquivalentTitlesShareADeadline() throws {
        let sharedDeadline = fixedReferenceDate.addingTimeInterval(86_400 * 30)
        let firstGoal = makeArchiveGoal(
            id: fixedUUID("00000000-0000-0000-0000-000000000703"),
            title: "Résumé mastery",
            deadline: sharedDeadline,
            createdAt: fixedReferenceDate.addingTimeInterval(-86_400)
        )
        let secondGoal = makeArchiveGoal(
            id: fixedUUID("00000000-0000-0000-0000-000000000704"),
            title: "resume mastery",
            deadline: sharedDeadline,
            createdAt: fixedReferenceDate.addingTimeInterval(-86_400 * 2)
        )
        let presentation = PracticeHistoryArchivePresentation(
            allAttempts: [],
            goalProfiles: [firstGoal, secondGoal],
            activeGoalID: firstGoal.id,
            requestedScope: .all,
            filter: .all
        )

        let firstTitle = try XCTUnwrap(
            presentation.goalOptions.first { $0.id == firstGoal.id }?.title
        )
        let secondTitle = try XCTUnwrap(
            presentation.goalOptions.first { $0.id == secondGoal.id }?.title
        )
        XCTAssertTrue(firstTitle.hasSuffix("profile 2"))
        XCTAssertTrue(secondTitle.hasSuffix("profile 1"))
    }

    func testArchiveGuaranteesUniqueLabelsForIdenticalNamesAndDeadlines() {
        let sharedDeadline = fixedReferenceDate.addingTimeInterval(86_400 * 30)
        let firstGoal = makeArchiveGoal(
            id: fixedUUID("00000000-0000-0000-0000-000000000731"),
            title: "Complete the launch review",
            deadline: sharedDeadline,
            createdAt: fixedReferenceDate.addingTimeInterval(-200)
        )
        let secondGoal = makeArchiveGoal(
            id: fixedUUID("00000000-0000-0000-0000-000000000732"),
            title: "Complete the launch review",
            deadline: sharedDeadline,
            createdAt: fixedReferenceDate.addingTimeInterval(-100)
        )

        let presentation = PracticeHistoryArchivePresentation(
            allAttempts: [],
            goalProfiles: [secondGoal, firstGoal],
            activeGoalID: secondGoal.id,
            requestedScope: .all,
            filter: .all
        )
        let titles = presentation.goalOptions.map(\.title)

        XCTAssertEqual(Set(titles).count, 2)
        XCTAssertTrue(titles.allSatisfy { $0.contains("· profile ") })
        XCTAssertEqual(presentation.goalTitle(for: firstGoal.id), titles[1])
        XCTAssertEqual(presentation.goalTitle(for: secondGoal.id), titles[0])
    }

    func testAllGoalsScopeKeepsRowIdentityWhenOnlyOneProfileHasAnswers() {
        let fixture = makeArchiveFixture()
        let singleAttempt = fixture.attempts[0]

        let presentation = PracticeHistoryArchivePresentation(
            allAttempts: [singleAttempt],
            goalProfiles: [fixture.activeGoal, fixture.otherGoal],
            activeGoalID: fixture.activeGoal.id,
            requestedScope: .all,
            filter: .all
        )

        XCTAssertEqual(presentation.summaryContext, "Across 1 goal")
        XCTAssertTrue(presentation.showsGoalIdentity)
        XCTAssertEqual(
            presentation.goalTitle(for: singleAttempt.goalID),
            fixture.activeGoal.title
        )
    }

    func testArchiveAttemptTimesRespectTheInjectedTimeZone() throws {
        let goal = makeArchiveGoal(
            id: fixedUUID("00000000-0000-0000-0000-000000000741"),
            title: "Verify localized history",
            deadline: fixedReferenceDate,
            createdAt: fixedReferenceDate
        )
        let attempt = makeArchiveAttempt(
            id: fixedUUID("00000000-0000-0000-0000-000000000742"),
            questionID: fixedUUID("00000000-0000-0000-0000-000000000743"),
            goalID: goal.id,
            prompt: "Which time should the archive display?",
            result: .correct,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone

        let presentation = PracticeHistoryArchivePresentation(
            allAttempts: [attempt],
            goalProfiles: [goal],
            activeGoalID: goal.id,
            requestedScope: .goal(goal.id),
            filter: .all,
            displayCalendar: calendar,
            displayLocale: locale,
            displayTimeZone: timeZone
        )

        XCTAssertEqual(
            presentation.timeText(for: attempt)
                .replacingOccurrences(of: "\u{202F}", with: " "),
            "12:00 AM"
        )
    }

    func testArchiveFallsBackFromMissingScopeAndLabelsUnavailableGoalHistory() {
        let fixture = makeArchiveFixture()
        let unavailableGoalID = fixedUUID("00000000-0000-0000-0000-000000000499")
        let unavailableAttempt = makeArchiveAttempt(
            id: fixedUUID("00000000-0000-0000-0000-000000000498"),
            questionID: fixedUUID("00000000-0000-0000-0000-000000000497"),
            goalID: unavailableGoalID,
            prompt: "Saved answer for an unavailable goal",
            result: .incorrect,
            createdAt: fixedReferenceDate.addingTimeInterval(60)
        )

        let presentation = PracticeHistoryArchivePresentation(
            allAttempts: fixture.attempts + [unavailableAttempt],
            goalProfiles: [fixture.activeGoal, fixture.otherGoal],
            activeGoalID: fixture.activeGoal.id,
            requestedScope: .goal(unavailableGoalID),
            filter: .all
        )

        XCTAssertEqual(presentation.scope, .all)
        XCTAssertEqual(presentation.scopeTitle, "All goals")
        XCTAssertEqual(presentation.goalTitle(for: unavailableGoalID), "Unavailable goal")
        XCTAssertTrue(presentation.scopedAttempts.contains { $0.goalID == unavailableGoalID })
        XCTAssertTrue(presentation.showsGoalIdentity)
    }

    func testArchiveKeepsASelectedKnownGoalWithNoAnswersAsAnEmptyScope() {
        let fixture = makeArchiveFixture()

        let presentation = PracticeHistoryArchivePresentation(
            allAttempts: fixture.attempts,
            goalProfiles: [fixture.activeGoal, fixture.otherGoal, fixture.emptyGoal],
            activeGoalID: fixture.activeGoal.id,
            requestedScope: .goal(fixture.emptyGoal.id),
            filter: .all
        )

        XCTAssertEqual(presentation.scope, .goal(fixture.emptyGoal.id))
        XCTAssertTrue(presentation.scopedAttempts.isEmpty)
        XCTAssertTrue(presentation.filteredAttempts.isEmpty)
        XCTAssertFalse(presentation.isGloballyEmpty)
        XCTAssertTrue(presentation.isScopeEmpty)
        XCTAssertEqual(presentation.correctCount, 0)
        XCTAssertEqual(presentation.reviewCount, 0)
        XCTAssertEqual(presentation.accuracyPercent, 0)
        XCTAssertEqual(presentation.scopeTitle, fixture.emptyGoal.title)
        XCTAssertEqual(presentation.scopeEmptyTitle, "No answers for this goal yet")
        XCTAssertEqual(
            presentation.scopeEmptyDetail,
            "Complete a checkpoint for \(fixture.emptyGoal.title) to start its history."
        )
    }

    func testHistoryLayoutPolicyCondensesShortAndExpandedTypeViewports() {
        let short = PracticeHistoryLayoutPolicy(
            viewportHeight: 568,
            usesExpandedTypeLayout: false
        )
        XCTAssertEqual(short.summaryDensity, .compact)
        XCTAssertFalse(short.showsSupportingCopy)
        XCTAssertFalse(short.usesMenuFilter)
        XCTAssertTrue(short.pinsFilter)

        let expandedType = PracticeHistoryLayoutPolicy(
            viewportHeight: 852,
            usesExpandedTypeLayout: true
        )
        XCTAssertEqual(expandedType.summaryDensity, .compact)
        XCTAssertTrue(expandedType.usesMenuFilter)
        XCTAssertFalse(expandedType.pinsFilter)
        XCTAssertFalse(expandedType.showsSupportingCopy)

        let roomy = PracticeHistoryLayoutPolicy(
            viewportHeight: 852,
            usesExpandedTypeLayout: false
        )
        XCTAssertEqual(roomy.summaryDensity, .expanded)
        XCTAssertTrue(roomy.showsSupportingCopy)
        XCTAssertFalse(roomy.usesMenuFilter)
        XCTAssertTrue(roomy.pinsFilter)
    }

    func testHistoryFilterLayoutUsesMenuForNarrowAndVeryHighCountArchives() {
        XCTAssertTrue(
            PracticeHistoryFilterLayoutPolicy.usesMenu(
                viewportWidth: 320,
                prefersExpandedTypeLayout: false,
                counts: [4, 2, 2]
            )
        )
        XCTAssertTrue(
            PracticeHistoryFilterLayoutPolicy.usesMenu(
                viewportWidth: 393,
                prefersExpandedTypeLayout: false,
                counts: [12_000, 9_999, 2_001]
            )
        )
        XCTAssertTrue(
            PracticeHistoryFilterLayoutPolicy.usesMenu(
                viewportWidth: 393,
                prefersExpandedTypeLayout: true,
                counts: [4, 2, 2]
            )
        )
        XCTAssertFalse(
            PracticeHistoryFilterLayoutPolicy.usesMenu(
                viewportWidth: 393,
                prefersExpandedTypeLayout: false,
                counts: [2_000, 1_200, 800]
            )
        )
    }

    func testHistoryResultStatusNamesFilterScopeCountAndMeaningfulOrdering() {
        let review = PracticeHistoryResultStatusPresentation(
            filter: .review,
            resultCount: 2,
            scopeTitle: "All goals"
        )
        XCTAssertEqual(review.title, "2 to revisit")
        XCTAssertEqual(review.orderingText, "Newest first")
        XCTAssertEqual(
            review.accessibilityLabel,
            "Showing 2 to revisit for All goals. Newest first."
        )

        let singular = PracticeHistoryResultStatusPresentation(
            filter: .correct,
            resultCount: 1,
            scopeTitle: "Launch reliability"
        )
        XCTAssertEqual(singular.title, "1 correct answer")

        let empty = PracticeHistoryResultStatusPresentation(
            filter: .all,
            resultCount: 0,
            scopeTitle: "Launch reliability"
        )
        XCTAssertEqual(empty.title, "0 answers")
        XCTAssertNil(empty.orderingText)
        XCTAssertEqual(
            empty.accessibilityLabel,
            "Showing 0 answers for Launch reliability."
        )
    }

    func testHistoryResultChangeDirectionFollowsTheOrderedFilters() {
        XCTAssertEqual(
            PracticeHistoryResultChange.filter(from: .all, to: .correct),
            .filterForward
        )
        XCTAssertEqual(
            PracticeHistoryResultChange.filter(from: .correct, to: .review),
            .filterForward
        )
        XCTAssertEqual(
            PracticeHistoryResultChange.filter(from: .review, to: .all),
            .filterBackward
        )
        XCTAssertEqual(
            PracticeHistoryResultChange.filter(from: .correct, to: .correct),
            .initial
        )
    }

    func testHistoryMotionPolicyUsesDirectionCrossfadeAndAccessibleFallbacks() {
        let standard = PracticeHistoryMotionPolicy(
            reduceMotion: false,
            assistiveNavigationEnabled: false
        )
        XCTAssertTrue(standard.usesMatchedGeometry)
        XCTAssertTrue(standard.usesRevealTransition)
        XCTAssertTrue(standard.animatesResultReset)
        XCTAssertNotNil(standard.resultAnimation)
        XCTAssertNotNil(standard.metricAnimation)
        XCTAssertEqual(standard.style(for: .initial), .identity)
        XCTAssertEqual(standard.style(for: .filterForward), .forward)
        XCTAssertEqual(standard.style(for: .filterBackward), .backward)
        XCTAssertEqual(standard.style(for: .scope), .opacity)

        let reduced = PracticeHistoryMotionPolicy(
            reduceMotion: true,
            assistiveNavigationEnabled: false
        )
        XCTAssertFalse(reduced.usesMatchedGeometry)
        XCTAssertFalse(reduced.usesRevealTransition)
        XCTAssertFalse(reduced.animatesResultReset)
        XCTAssertNil(reduced.resultAnimation)
        XCTAssertNil(reduced.metricAnimation)
        XCTAssertEqual(reduced.style(for: .filterForward), .identity)
        XCTAssertEqual(reduced.style(for: .scope), .identity)

        let assistive = PracticeHistoryMotionPolicy(
            reduceMotion: false,
            assistiveNavigationEnabled: true
        )
        XCTAssertFalse(assistive.usesMatchedGeometry)
        XCTAssertFalse(assistive.usesRevealTransition)
        XCTAssertFalse(assistive.animatesResultReset)
        XCTAssertNotNil(assistive.resultAnimation)
        XCTAssertNil(assistive.metricAnimation)
        XCTAssertEqual(assistive.style(for: .filterForward), .opacity)
        XCTAssertEqual(assistive.style(for: .scope), .opacity)
    }

    func testHistoryResultUpdateDeliveryDoesNotStealOrdinaryTouchFocus() {
        XCTAssertEqual(
            PracticeHistoryResultUpdateDeliveryPolicy.delivery(
                voiceOverEnabled: false,
                switchControlEnabled: false
            ),
            .none
        )
        XCTAssertEqual(
            PracticeHistoryResultUpdateDeliveryPolicy.delivery(
                voiceOverEnabled: true,
                switchControlEnabled: false
            ),
            .focusStatus
        )
        XCTAssertEqual(
            PracticeHistoryResultUpdateDeliveryPolicy.delivery(
                voiceOverEnabled: false,
                switchControlEnabled: true
            ),
            .announceStatus
        )
        XCTAssertEqual(
            PracticeHistoryResultUpdateDeliveryPolicy.delivery(
                voiceOverEnabled: true,
                switchControlEnabled: true
            ),
            .focusStatus
        )

        XCTAssertTrue(
            PracticeHistoryResultScrollPolicy.shouldReset(
                after: .scope,
                voiceOverEnabled: false,
                switchControlEnabled: false
            )
        )
        XCTAssertFalse(
            PracticeHistoryResultScrollPolicy.shouldReset(
                after: .scope,
                voiceOverEnabled: false,
                switchControlEnabled: true
            )
        )
        XCTAssertTrue(
            PracticeHistoryResultScrollPolicy.shouldReset(
                after: .filterForward,
                voiceOverEnabled: false,
                switchControlEnabled: true
            )
        )
        XCTAssertFalse(
            PracticeHistoryResultScrollPolicy.shouldReset(
                after: .initial,
                voiceOverEnabled: false,
                switchControlEnabled: false
            )
        )
    }

    @MainActor
    func testHistoryKeepsResultContextAndAnswerLogInTheFirstFold() throws {
        let fixtures = [
            PracticeHistoryFirstFoldFixture(
                name: "practice-history-first-fold-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                maximumSummaryHeight: 145,
                minimumVisibleFirstAttemptHeight: 44
            ),
            PracticeHistoryFirstFoldFixture(
                name: "practice-history-first-fold-accessibility5",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                maximumSummaryHeight: 270,
                minimumVisibleFirstAttemptHeight: 44
            ),
        ]

        for fixture in fixtures {
            let archiveFixture = makeArchiveFixture()
            let suiteName = "PracticeHistoryFirstFold.\(fixture.name).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = makeArchiveStore(
                defaults: defaults,
                fixture: archiveFixture
            )
            let capture = PracticeHistoryLayoutCapture()
            let configuration = HistoryViewRenderConfiguration(
                initialScope: .all,
                initialFilter: .review,
                reduceMotion: true,
                referenceDate: fixedReferenceDate,
                layoutReporter: { element, frame in
                    capture.frames[element] = frame
                }
            )
            let image = HostedViewRenderer.image(
                for: HistoryView(
                    store: store,
                    renderConfiguration: configuration
                )
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: 0.2,
                renderScale: 1
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)

            let viewport = try XCTUnwrap(capture.frames[.viewport], fixture.name)
            let header = try XCTUnwrap(capture.frames[.header], fixture.name)
            let summary = try XCTUnwrap(capture.frames[.summary], fixture.name)
            let filter = try XCTUnwrap(capture.frames[.filter], fixture.name)
            let resultStatus = try XCTUnwrap(
                capture.frames[.resultStatus],
                fixture.name
            )
            let timeline = try XCTUnwrap(capture.frames[.timeline], fixture.name)
            let firstAttempt = try XCTUnwrap(
                capture.frames[.firstAttempt],
                fixture.name
            )
            let semanticFrames = [
                header,
                summary,
                filter,
                resultStatus,
                timeline,
                firstAttempt,
            ]

            XCTAssertGreaterThan(viewport.width, 0, fixture.name)
            XCTAssertGreaterThan(viewport.height, 0, fixture.name)
            for frame in semanticFrames {
                XCTAssertFalse(frame.isNull, fixture.name)
                XCTAssertFalse(frame.isInfinite, fixture.name)
                XCTAssertGreaterThan(frame.width, 0, fixture.name)
                XCTAssertGreaterThan(frame.height, 0, fixture.name)
                XCTAssertGreaterThanOrEqual(
                    frame.minX,
                    viewport.minX - 0.5,
                    fixture.name
                )
                XCTAssertLessThanOrEqual(
                    frame.maxX,
                    viewport.maxX + 0.5,
                    fixture.name
                )
            }

            XCTAssertLessThanOrEqual(
                summary.height,
                fixture.maximumSummaryHeight,
                "\(fixture.name) allowed the practice summary to dominate the review"
            )
            XCTAssertLessThanOrEqual(header.maxY, summary.minY + 0.5, fixture.name)
            XCTAssertLessThanOrEqual(summary.maxY, filter.minY + 0.5, fixture.name)
            XCTAssertLessThanOrEqual(filter.maxY, timeline.minY + 0.5, fixture.name)
            XCTAssertTrue(
                filter.insetBy(dx: -0.5, dy: -0.5).contains(resultStatus),
                "\(fixture.name) separated the result count from its filter context"
            )
            XCTAssertTrue(
                viewport.insetBy(dx: -0.5, dy: -0.5).contains(resultStatus),
                "\(fixture.name) pushed the visible result count below the first fold"
            )
            XCTAssertTrue(
                timeline.insetBy(dx: -0.5, dy: -0.5).contains(firstAttempt),
                "\(fixture.name) placed the first answer outside the answer log"
            )

            let visibleFirstAttempt = firstAttempt.intersection(viewport)
            XCTAssertFalse(visibleFirstAttempt.isNull, fixture.name)
            XCTAssertGreaterThanOrEqual(
                visibleFirstAttempt.height,
                fixture.minimumVisibleFirstAttemptHeight,
                "\(fixture.name) left less than one meaningful answer row in the first fold"
            )

        }
    }

    @MainActor
    func testEmptyHistoryBranchesKeepAVisibleResultStatusTarget() throws {
        let cases: [(name: String, isGloballyEmpty: Bool)] = [
            ("practice-history-empty-scope-status", false),
            ("practice-history-global-empty-status", true),
        ]

        for testCase in cases {
            let archiveFixture = makeArchiveFixture()
            let suiteName = "PracticeHistoryEmptyStatus.\(testCase.name).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = makeArchiveStore(
                defaults: defaults,
                fixture: archiveFixture
            )
            if testCase.isGloballyEmpty {
                store.attempts = []
            }
            let capture = PracticeHistoryLayoutCapture()
            let configuration = HistoryViewRenderConfiguration(
                initialScope: testCase.isGloballyEmpty
                    ? .all
                    : .goal(archiveFixture.emptyGoal.id),
                reduceMotion: true,
                referenceDate: fixedReferenceDate,
                layoutReporter: { element, frame in
                    capture.frames[element] = frame
                }
            )
            let image = HostedViewRenderer.image(
                for: HistoryView(
                    store: store,
                    renderConfiguration: configuration
                ),
                width: 320,
                height: 568,
                colorScheme: .light,
                settlingTime: 0.15,
                renderScale: 1
            )

            let attachment = XCTAttachment(image: image)
            attachment.name = testCase.name
            attachment.lifetime = .keepAlways
            add(attachment)

            let viewport = try XCTUnwrap(capture.frames[.viewport], testCase.name)
            let filter = try XCTUnwrap(capture.frames[.filter], testCase.name)
            let status = try XCTUnwrap(capture.frames[.resultStatus], testCase.name)
            XCTAssertTrue(
                filter.insetBy(dx: -0.5, dy: -0.5).contains(status),
                "\(testCase.name) detached the empty result target from its log heading"
            )
            XCTAssertTrue(
                viewport.insetBy(dx: -0.5, dy: -0.5).contains(status),
                "\(testCase.name) left no visible result target for assistive focus"
            )
        }
    }

    @MainActor
    func testPracticeHistoryArchiveRendersAcrossScopeTypeAndMotionStates() throws {
        let archiveFixture = makeArchiveFixture()
        let duplicateGoals = makeDuplicateTitleGoals()
        let archiveSuiteName = "PracticeHistoryArchiveRenderingTests.Archive.\(UUID().uuidString)"
        let duplicateSuiteName = "PracticeHistoryArchiveRenderingTests.Duplicate.\(UUID().uuidString)"
        let archiveDefaults = try XCTUnwrap(UserDefaults(suiteName: archiveSuiteName))
        let duplicateDefaults = try XCTUnwrap(UserDefaults(suiteName: duplicateSuiteName))
        defer {
            archiveDefaults.removePersistentDomain(forName: archiveSuiteName)
            duplicateDefaults.removePersistentDomain(forName: duplicateSuiteName)
        }

        let archiveStore = makeArchiveStore(
            defaults: archiveDefaults,
            fixture: archiveFixture
        )
        let duplicateStore = makeDuplicateTitleStore(
            defaults: duplicateDefaults,
            goals: duplicateGoals
        )
        let expandedAttemptID = try XCTUnwrap(
            archiveFixture.attempts.first {
                $0.goalID == archiveFixture.otherGoal.id && $0.result == .partial
            }?.id
        )
        let fixtures = [
            PracticeHistoryRenderFixture(
                name: "practice-history-all-goals-light",
                store: archiveStore,
                configuration: HistoryViewRenderConfiguration(
                    initialScope: .all,
                    reduceMotion: false,
                    referenceDate: fixedReferenceDate
                ),
                width: 393,
                height: 1_500,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            PracticeHistoryRenderFixture(
                name: "practice-history-selected-revisit-expanded-dark",
                store: archiveStore,
                configuration: HistoryViewRenderConfiguration(
                    initialScope: .goal(archiveFixture.otherGoal.id),
                    initialFilter: .review,
                    initiallyExpandedAttemptIDs: [expandedAttemptID],
                    reduceMotion: false,
                    referenceDate: fixedReferenceDate
                ),
                width: 393,
                height: 1_500,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            PracticeHistoryRenderFixture(
                name: "practice-history-duplicate-title-compact",
                store: duplicateStore,
                configuration: HistoryViewRenderConfiguration(
                    initialScope: .goal(duplicateGoals.first.id),
                    reduceMotion: false,
                    referenceDate: fixedReferenceDate
                ),
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            PracticeHistoryRenderFixture(
                name: "practice-history-all-goals-accessibility2",
                store: archiveStore,
                configuration: HistoryViewRenderConfiguration(
                    initialScope: .all,
                    reduceMotion: false,
                    referenceDate: fixedReferenceDate
                ),
                width: 393,
                height: 2_000,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2
            ),
            PracticeHistoryRenderFixture(
                name: "practice-history-selected-empty-goal",
                store: archiveStore,
                configuration: HistoryViewRenderConfiguration(
                    initialScope: .goal(archiveFixture.emptyGoal.id),
                    reduceMotion: false,
                    referenceDate: fixedReferenceDate
                ),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            PracticeHistoryRenderFixture(
                name: "practice-history-reduce-motion-dark",
                store: archiveStore,
                configuration: HistoryViewRenderConfiguration(
                    initialScope: .all,
                    initialFilter: .correct,
                    reduceMotion: true,
                    referenceDate: fixedReferenceDate
                ),
                width: 393,
                height: 1_300,
                colorScheme: .dark,
                dynamicTypeSize: .large
            )
        ]
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone

        for fixture in fixtures {
            autoreleasepool {
                let view = HistoryView(
                    store: fixture.store,
                    renderConfiguration: fixture.configuration
                )
                .environment(\.calendar, calendar)
                .environment(\.locale, locale)
                .environment(\.timeZone, timeZone)
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)

                let image = HostedViewRenderer.image(
                    for: view,
                    width: fixture.width,
                    height: fixture.height,
                    colorScheme: fixture.colorScheme,
                    settlingTime: fixture.configuration.reduceMotion == true ? 0.05 : 0.55,
                    renderScale: 0.5
                )

                XCTAssertEqual(image.size.width, fixture.width, accuracy: 1, fixture.name)
                XCTAssertEqual(image.size.height, fixture.height, accuracy: 1, fixture.name)
                let attachment = XCTAttachment(image: image)
                attachment.name = fixture.name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
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

    func testSameQuestionIDDifferentGoalDoesNotProvideLegacyReviewFallback() {
        let sharedQuestionID = fixedUUID("00000000-0000-0000-0000-000000000501")
        let attemptGoalID = fixedUUID("00000000-0000-0000-0000-000000000502")
        let retainedQuestion = makeRetainedQuestion(
            id: sharedQuestionID,
            goalID: fixedUUID("00000000-0000-0000-0000-000000000503"),
            topic: "Wrong goal topic",
            expectedAnswer: "Wrong goal answer",
            explanation: "Wrong goal explanation",
            format: .reflection
        )
        let attempt = makeAttempt(
            questionID: sharedQuestionID,
            goalID: attemptGoalID,
            answer: "Recorded answer for the intended goal",
            result: .incorrect
        )

        let presentation = PracticeHistoryReviewPresentation(
            attempt: attempt,
            retainedQuestion: retainedQuestion
        )

        assertUserAnswerOnly(
            presentation,
            expectedAnswer: "Recorded answer for the intended goal"
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

    private var fixedReferenceDate: Date {
        Date(timeIntervalSince1970: 1_788_458_400)
    }

    private func fixedUUID(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid fixed test UUID: \(value)")
        }
        return id
    }

    private func makeArchiveFixture() -> PracticeHistoryArchiveFixture {
        let referenceDate = fixedReferenceDate
        let activeGoal = makeArchiveGoal(
            id: fixedUUID("00000000-0000-0000-0000-000000000601"),
            title: "Lead production architecture reviews",
            deadline: referenceDate.addingTimeInterval(86_400 * 45),
            createdAt: referenceDate.addingTimeInterval(-86_400 * 10)
        )
        let otherGoal = makeArchiveGoal(
            id: fixedUUID("00000000-0000-0000-0000-000000000602"),
            title: "Build fluent Spanish conversation",
            deadline: referenceDate.addingTimeInterval(86_400 * 75),
            createdAt: referenceDate.addingTimeInterval(-86_400 * 20)
        )
        let emptyGoal = makeArchiveGoal(
            id: fixedUUID("00000000-0000-0000-0000-000000000603"),
            title: "Prepare a product strategy portfolio",
            deadline: referenceDate.addingTimeInterval(86_400 * 100),
            createdAt: referenceDate.addingTimeInterval(-86_400 * 30)
        )
        let sharedQuestionID = fixedUUID("00000000-0000-0000-0000-000000000610")
        let activeQuestion = CheckpointQuestion(
            id: sharedQuestionID,
            goalID: activeGoal.id,
            prompt: "Which launch constraint should be verified first?",
            expectedAnswer: "Verify the irreversible dependency before committing rollout state.",
            explanation: "The highest-cost irreversible dependency should be validated before rollout.",
            topic: "Launch reliability",
            difficulty: 3,
            format: .shortAnswer,
            sourcePrompt: "fixed history fixture"
        )
        let otherQuestion = CheckpointQuestion(
            id: sharedQuestionID,
            goalID: otherGoal.id,
            prompt: "Choose the correct past-tense response.",
            expectedAnswer: "Ayer hablé con el cliente.",
            explanation: "Hablé is the first-person preterite form used for a completed action.",
            topic: "Past-tense conversation",
            difficulty: 2,
            format: .shortAnswer,
            sourcePrompt: "fixed history fixture"
        )
        let attempts = [
            makeArchiveAttempt(
                id: fixedUUID("00000000-0000-0000-0000-000000000621"),
                questionID: sharedQuestionID,
                goalID: activeGoal.id,
                prompt: activeQuestion.prompt,
                answer: activeQuestion.expectedAnswer,
                result: .correct,
                createdAt: referenceDate.addingTimeInterval(-600)
            ),
            makeArchiveAttempt(
                id: fixedUUID("00000000-0000-0000-0000-000000000622"),
                questionID: sharedQuestionID,
                goalID: otherGoal.id,
                prompt: otherQuestion.prompt,
                answer: "Ayer hablo con el cliente.",
                result: .partial,
                createdAt: referenceDate.addingTimeInterval(-1_800)
            ),
            makeArchiveAttempt(
                id: fixedUUID("00000000-0000-0000-0000-000000000623"),
                questionID: fixedUUID("00000000-0000-0000-0000-000000000613"),
                goalID: activeGoal.id,
                prompt: "Which dependency creates the largest recovery risk?",
                answer: "The easiest dependency to replace",
                result: .incorrect,
                createdAt: referenceDate.addingTimeInterval(-7_200),
                reviewSnapshot: CheckpointAttemptReviewSnapshot(
                    topic: "Failure recovery",
                    format: .shortAnswer,
                    referenceAnswer: "The dependency with irreversible external state.",
                    explanation: "Irreversible state makes rollback and recovery substantially harder."
                )
            ),
            makeArchiveAttempt(
                id: fixedUUID("00000000-0000-0000-0000-000000000624"),
                questionID: fixedUUID("00000000-0000-0000-0000-000000000614"),
                goalID: otherGoal.id,
                prompt: "Translate the customer greeting.",
                answer: "Buenos días, ¿cómo puedo ayudarle?",
                result: .correct,
                createdAt: referenceDate.addingTimeInterval(-86_400 - 1_800),
                reviewSnapshot: CheckpointAttemptReviewSnapshot(
                    topic: "Customer greetings",
                    format: .shortAnswer,
                    referenceAnswer: nil,
                    explanation: "The greeting and formal pronoun fit a customer conversation."
                )
            )
        ]
        return PracticeHistoryArchiveFixture(
            activeGoal: activeGoal,
            otherGoal: otherGoal,
            emptyGoal: emptyGoal,
            questions: [activeQuestion, otherQuestion],
            attempts: attempts
        )
    }

    private func makeDuplicateTitleGoals() -> (first: Goal, second: Goal) {
        (
            first: makeArchiveGoal(
                id: fixedUUID("00000000-0000-0000-0000-000000000701"),
                title: "Résumé mastery",
                deadline: fixedReferenceDate.addingTimeInterval(86_400 * 30),
                createdAt: fixedReferenceDate.addingTimeInterval(-86_400)
            ),
            second: makeArchiveGoal(
                id: fixedUUID("00000000-0000-0000-0000-000000000702"),
                title: "resume mastery",
                deadline: fixedReferenceDate.addingTimeInterval(86_400 * 60),
                createdAt: fixedReferenceDate.addingTimeInterval(-86_400 * 2)
            )
        )
    }

    private func makeArchiveGoal(
        id: Goal.ID,
        title: String,
        deadline: Date,
        createdAt: Date
    ) -> Goal {
        Goal(
            id: id,
            title: title,
            deadline: deadline,
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "A deterministic test focus",
            preferredQuestionStyle: .shortAnswer,
            createdAt: createdAt
        )
    }

    private func makeArchiveAttempt(
        id: CheckpointAttempt.ID,
        questionID: CheckpointQuestion.ID,
        goalID: Goal.ID,
        prompt: String,
        answer: String = "Recorded learner answer",
        result: AnswerResult,
        createdAt: Date,
        reviewSnapshot: CheckpointAttemptReviewSnapshot? = nil
    ) -> CheckpointAttempt {
        CheckpointAttempt(
            id: id,
            questionID: questionID,
            goalID: goalID,
            prompt: prompt,
            answer: answer,
            result: result,
            unlockMinutes: 0,
            reviewSnapshot: reviewSnapshot,
            createdAt: createdAt
        )
    }

    @MainActor
    private func makeArchiveStore(
        defaults: UserDefaults,
        fixture: PracticeHistoryArchiveFixture
    ) -> CheckpointStore {
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = .member
        store.goal = fixture.activeGoal
        store.goalProfiles = [fixture.activeGoal, fixture.otherGoal, fixture.emptyGoal]
        store.questions = fixture.questions
        store.attempts = fixture.attempts
        return store
    }

    @MainActor
    private func makeDuplicateTitleStore(
        defaults: UserDefaults,
        goals: (first: Goal, second: Goal)
    ) -> CheckpointStore {
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = .member
        store.goal = goals.first
        store.goalProfiles = [goals.first, goals.second]
        store.attempts = [
            makeArchiveAttempt(
                id: fixedUUID("00000000-0000-0000-0000-000000000711"),
                questionID: fixedUUID("00000000-0000-0000-0000-000000000712"),
                goalID: goals.first.id,
                prompt: "Which portfolio detail makes the outcome concrete?",
                result: .correct,
                createdAt: fixedReferenceDate.addingTimeInterval(-900)
            ),
            makeArchiveAttempt(
                id: fixedUUID("00000000-0000-0000-0000-000000000713"),
                questionID: fixedUUID("00000000-0000-0000-0000-000000000714"),
                goalID: goals.second.id,
                prompt: "Which revision best clarifies the impact?",
                result: .partial,
                createdAt: fixedReferenceDate.addingTimeInterval(-1_800)
            )
        ]
        return store
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

private struct PracticeHistoryArchiveFixture {
    let activeGoal: Goal
    let otherGoal: Goal
    let emptyGoal: Goal
    let questions: [CheckpointQuestion]
    let attempts: [CheckpointAttempt]
}

private struct PracticeHistoryFirstFoldFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let maximumSummaryHeight: CGFloat
    let minimumVisibleFirstAttemptHeight: CGFloat
}

@MainActor
private final class PracticeHistoryLayoutCapture {
    var frames: [PracticeHistoryLayoutElement: CGRect] = [:]
}

@MainActor
private struct PracticeHistoryRenderFixture {
    let name: String
    let store: CheckpointStore
    let configuration: HistoryViewRenderConfiguration
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
}
