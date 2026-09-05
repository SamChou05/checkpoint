import SwiftUI
import XCTest
@testable import Checkpoint

final class FocusWinsViewRenderingTests: XCTestCase {
    func testWeeklySnapshotCountsCurrentWeekThroughReferenceDay() throws {
        let calendar = fixedCalendar()
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try date(
            year: 2026,
            month: 9,
            day: 2,
            hour: 12,
            calendar: calendar
        )
        let goalID = UUID()
        let wins = [
            FocusWin(
                goalID: goalID,
                note: "Monday one",
                loggedAt: try date(year: 2026, month: 8, day: 31, hour: 9, calendar: calendar)
            ),
            FocusWin(
                goalID: goalID,
                note: "Monday two",
                loggedAt: try date(year: 2026, month: 8, day: 31, hour: 18, calendar: calendar)
            ),
            FocusWin(
                goalID: goalID,
                note: "Wednesday",
                loggedAt: try date(year: 2026, month: 9, day: 2, hour: 8, calendar: calendar)
            ),
            FocusWin(
                goalID: goalID,
                note: "Previous week",
                loggedAt: try date(year: 2026, month: 8, day: 30, hour: 8, calendar: calendar)
            ),
            FocusWin(
                goalID: goalID,
                note: "Future day",
                loggedAt: try date(year: 2026, month: 9, day: 3, hour: 8, calendar: calendar)
            )
        ]

        let presentation = FocusWinsWeeklySnapshotPresentation(
            focusWins: wins,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertEqual(presentation.days.count, 7)
        XCTAssertEqual(presentation.days.map(\.winCount), [2, 0, 1, 0, 0, 0, 0])
        XCTAssertEqual(presentation.days.map(\.isFuture), [false, false, false, true, true, true, true])
        XCTAssertEqual(presentation.winCount, 3)
        XCTAssertEqual(presentation.activeDayCount, 2)
        XCTAssertEqual(presentation.headline, "3 wins this week")
        XCTAssertEqual(presentation.detail, "Captured across 2 days, in your own words.")
        XCTAssertEqual(presentation.badgeText, "2 DAYS")
        XCTAssertTrue(presentation.accessibilityValue.contains("Monday, 2 wins"))
        XCTAssertTrue(presentation.accessibilityValue.contains("Wednesday, 1 win"))
        XCTAssertFalse(presentation.accessibilityValue.contains("Thursday, 1 win"))
    }

    func testWeeklySnapshotUsesTruthfulEmptyAndSingleWinCopy() throws {
        let calendar = fixedCalendar()
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try date(
            year: 2026,
            month: 9,
            day: 2,
            hour: 12,
            calendar: calendar
        )
        let goalID = UUID()

        let empty = FocusWinsWeeklySnapshotPresentation(
            focusWins: [],
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        XCTAssertEqual(empty.headline, "Your week is ready")
        XCTAssertEqual(empty.badgeText, "PRIVATE")
        XCTAssertTrue(empty.accessibilityValue.contains("Based only on private notes you log"))
        XCTAssertTrue(empty.accessibilityValue.contains("never affect progress scores"))
        XCTAssertTrue(empty.accessibilityValue.contains("practice recommendations"))
        XCTAssertTrue(empty.accessibilityValue.contains("app breaks"))

        let single = FocusWinsWeeklySnapshotPresentation(
            focusWins: [
                FocusWin(
                    goalID: goalID,
                    note: "A clear explanation",
                    loggedAt: try date(
                        year: 2026,
                        month: 9,
                        day: 2,
                        hour: 8,
                        calendar: calendar
                    )
                )
            ],
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        XCTAssertEqual(single.headline, "1 win this week")
        XCTAssertEqual(single.detail, "Captured on one day, in your own words.")
        XCTAssertTrue(single.accessibilityValue.contains("Wednesday"))
    }

    func testFocusWinsEntrySummarizesRecencyWithoutExposingNoteText() throws {
        let calendar = fixedCalendar()
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try date(
            year: 2026,
            month: 9,
            day: 2,
            hour: 12,
            calendar: calendar
        )
        let goalID = UUID()
        let secretNote = "Do not show this note in Progress"
        let presentation = FocusWinsEntryPresentation(
            focusWins: [
                FocusWin(
                    goalID: goalID,
                    note: secretNote,
                    loggedAt: try date(
                        year: 2026,
                        month: 9,
                        day: 2,
                        hour: 8,
                        calendar: calendar
                    )
                ),
                FocusWin(
                    goalID: goalID,
                    note: "Another private note",
                    loggedAt: try date(
                        year: 2026,
                        month: 8,
                        day: 31,
                        hour: 8,
                        calendar: calendar
                    )
                )
            ],
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertEqual(presentation.detail, "2 reflections this week · Latest today")
        XCTAssertEqual(presentation.trailingText, "2 total")
        XCTAssertTrue(presentation.accessibilityValue.contains("2 entries logged by you"))
        XCTAssertFalse(presentation.detail.contains(secretNote))
        XCTAssertFalse(presentation.accessibilityValue.contains(secretNote))
    }

    func testComposerStartsExpandedOnlyForEmptyOrExplicitlyRequestedStates() {
        XCTAssertTrue(FocusWinsComposerPolicy.startsExpanded(focusWinCount: 0, override: nil))
        XCTAssertFalse(FocusWinsComposerPolicy.startsExpanded(focusWinCount: 2, override: nil))
        XCTAssertTrue(FocusWinsComposerPolicy.startsExpanded(focusWinCount: 2, override: true))
        XCTAssertFalse(FocusWinsComposerPolicy.startsExpanded(focusWinCount: 0, override: false))
    }

    func testPostDeleteFocusAlwaysTargetsAPresentElement() {
        XCTAssertEqual(
            FocusWinsPostDeleteFocusPolicy.target(
                remainingWinCount: 2,
                isComposerExpanded: false
            ),
            .ledgerTitle
        )
        XCTAssertEqual(
            FocusWinsPostDeleteFocusPolicy.target(
                remainingWinCount: 0,
                isComposerExpanded: false
            ),
            .composerLauncher
        )
        XCTAssertEqual(
            FocusWinsPostDeleteFocusPolicy.target(
                remainingWinCount: 0,
                isComposerExpanded: true
            ),
            .composer
        )
    }

    @MainActor
    func testMutationMotionPolicyUsesSpatialFeedbackOnlyForStandardInteraction() {
        let standard = FocusWinsMutationMotionPolicy(
            reduceMotion: false,
            voiceOverEnabled: false,
            switchControlEnabled: false
        )

        XCTAssertEqual(standard.style, .spatial)
        XCTAssertNotNil(standard.mutationAnimation)
        XCTAssertNotNil(standard.confirmationDismissAnimation)
        XCTAssertTrue(standard.usesSpatialTransitions)
        XCTAssertTrue(standard.animatesSymbolEffects)
        XCTAssertFalse(standard.mutationTransaction.disablesAnimations)

        let suppressedPolicies = [
            (
                "Reduce Motion",
                FocusWinsMutationMotionPolicy(
                    reduceMotion: true,
                    voiceOverEnabled: false,
                    switchControlEnabled: false
                )
            ),
            (
                "VoiceOver",
                FocusWinsMutationMotionPolicy(
                    reduceMotion: false,
                    voiceOverEnabled: true,
                    switchControlEnabled: false
                )
            ),
            (
                "Switch Control",
                FocusWinsMutationMotionPolicy(
                    reduceMotion: false,
                    voiceOverEnabled: false,
                    switchControlEnabled: true
                )
            ),
            (
                "Combined",
                FocusWinsMutationMotionPolicy(
                    reduceMotion: true,
                    voiceOverEnabled: true,
                    switchControlEnabled: true
                )
            ),
        ]

        for (name, policy) in suppressedPolicies {
            XCTAssertEqual(policy.style, .tonalOnly, name)
            XCTAssertNil(policy.mutationAnimation, name)
            XCTAssertNil(policy.confirmationDismissAnimation, name)
            XCTAssertFalse(policy.usesSpatialTransitions, name)
            XCTAssertFalse(policy.animatesSymbolEffects, name)
            XCTAssertTrue(policy.mutationTransaction.disablesAnimations, name)
            XCTAssertTrue(policy.confirmationDismissTransaction.disablesAnimations, name)
        }
    }

    @MainActor
    func testMutationRevealScrollIsAlwaysDeterministicAndNonanimated() {
        let policies = [
            FocusWinsMutationMotionPolicy(
                reduceMotion: false,
                voiceOverEnabled: false,
                switchControlEnabled: false
            ),
            FocusWinsMutationMotionPolicy(
                reduceMotion: true,
                voiceOverEnabled: false,
                switchControlEnabled: false
            ),
            FocusWinsMutationMotionPolicy(
                reduceMotion: false,
                voiceOverEnabled: true,
                switchControlEnabled: false
            ),
            FocusWinsMutationMotionPolicy(
                reduceMotion: false,
                voiceOverEnabled: false,
                switchControlEnabled: true
            ),
        ]

        for policy in policies {
            XCTAssertNil(policy.scrollTransaction.animation)
            XCTAssertTrue(policy.scrollTransaction.disablesAnimations)
        }
    }

    @MainActor
    func testMutationConfirmationRemainsTonalAcrossAccessibilityModes() {
        let policies = [
            FocusWinsMutationMotionPolicy(
                reduceMotion: false,
                voiceOverEnabled: false,
                switchControlEnabled: false
            ),
            FocusWinsMutationMotionPolicy(
                reduceMotion: true,
                voiceOverEnabled: false,
                switchControlEnabled: false
            ),
            FocusWinsMutationMotionPolicy(
                reduceMotion: false,
                voiceOverEnabled: true,
                switchControlEnabled: false
            ),
            FocusWinsMutationMotionPolicy(
                reduceMotion: false,
                voiceOverEnabled: false,
                switchControlEnabled: true
            ),
        ]

        for policy in policies {
            XCTAssertTrue(policy.showsTonalConfirmation)
            XCTAssertGreaterThan(policy.celebrationBackgroundOpacity, 0)
            XCTAssertGreaterThan(policy.celebrationBorderOpacity, 0)
        }
        XCTAssertGreaterThan(policies[0].celebrationShadowOpacity, 0)
        for policy in policies.dropFirst() {
            XCTAssertEqual(policy.celebrationShadowOpacity, 0)
        }
    }

    @MainActor
    func testFocusWinsSurfacesRenderAcrossKeyLayouts() throws {
        let populatedSuiteName = "FocusWinsViewRenderingTests.populated.\(UUID().uuidString)"
        let emptySuiteName = "FocusWinsViewRenderingTests.empty.\(UUID().uuidString)"
        let populatedDefaults = try XCTUnwrap(UserDefaults(suiteName: populatedSuiteName))
        let emptyDefaults = try XCTUnwrap(UserDefaults(suiteName: emptySuiteName))
        defer {
            populatedDefaults.removePersistentDomain(forName: populatedSuiteName)
            emptyDefaults.removePersistentDomain(forName: emptySuiteName)
        }

        let calendar = fixedCalendar()
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try date(
            year: 2026,
            month: 9,
            day: 2,
            hour: 12,
            calendar: calendar
        )

        let goal = Goal(
            title: "Pass senior technical interviews",
            deadline: Date().addingTimeInterval(86_400 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays, system design, communication",
            preferredQuestionStyle: .multipleChoice
        )
        let populatedStore = CheckpointStore(defaults: populatedDefaults)
        populatedStore.goal = goal
        populatedStore.goalProfiles = [goal]
        populatedStore.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Explained the tradeoffs in my cache design without needing a hint.",
                loggedAt: try date(
                    year: 2026,
                    month: 9,
                    day: 2,
                    hour: 10,
                    calendar: calendar
                )
            ),
            FocusWin(
                goalID: goal.id,
                note: "Finished the recursion review and caught my own base-case error.",
                loggedAt: try date(
                    year: 2026,
                    month: 9,
                    day: 1,
                    hour: 17,
                    calendar: calendar
                )
            )
        ]
        let emptyStore = CheckpointStore(defaults: emptyDefaults)
        emptyStore.goal = goal
        emptyStore.goalProfiles = [goal]
        let celebratedWin = try XCTUnwrap(populatedStore.focusWins.first)
        let standardMotionPolicy = FocusWinsMutationMotionPolicy(
            reduceMotion: false,
            voiceOverEnabled: false,
            switchControlEnabled: false
        )
        let tonalOnlyMotionPolicy = FocusWinsMutationMotionPolicy(
            reduceMotion: true,
            voiceOverEnabled: false,
            switchControlEnabled: false
        )

        let fixtures = [
            RenderFixture(
                name: "focus-wins-populated-collapsed-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    FocusWinsView(
                        store: populatedStore,
                        goalID: goal.id,
                        goalTitle: goal.title,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone
                    )
                )
            ),
            RenderFixture(
                name: "focus-wins-populated-collapsed-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    FocusWinsView(
                        store: populatedStore,
                        goalID: goal.id,
                        goalTitle: goal.title,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone
                    )
                )
            ),
            RenderFixture(
                name: "focus-wins-compact-populated",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    FocusWinsView(
                        store: populatedStore,
                        goalID: goal.id,
                        goalTitle: goal.title,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone
                    )
                )
            ),
            RenderFixture(
                name: "focus-wins-empty-first-entry",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    FocusWinsView(
                        store: emptyStore,
                        goalID: goal.id,
                        goalTitle: goal.title,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone
                    )
                )
            ),
            RenderFixture(
                name: "focus-wins-empty-collapsed",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    FocusWinsView(
                        store: emptyStore,
                        goalID: goal.id,
                        goalTitle: goal.title,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone,
                        initiallyComposerExpanded: false
                    )
                )
            ),
            RenderFixture(
                name: "focus-wins-expanded-draft",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    FocusWinsView(
                        store: populatedStore,
                        goalID: goal.id,
                        goalTitle: goal.title,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone,
                        initialDraft: "Explained why the queue needs backpressure before writing any code.",
                        initiallyComposerExpanded: true
                    )
                )
            ),
            RenderFixture(
                name: "focus-wins-over-limit",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    FocusWinsView(
                        store: populatedStore,
                        goalID: goal.id,
                        goalTitle: goal.title,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone,
                        initialDraft: String(repeating: "W", count: 281),
                        initiallyComposerExpanded: true
                    )
                )
            ),
            RenderFixture(
                name: "focus-wins-accessibility5-collapsed-reduced-motion",
                width: 393,
                height: 2_100,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    FocusWinsView(
                        store: populatedStore,
                        goalID: goal.id,
                        goalTitle: goal.title,
                        reduceMotionOverride: true,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone
                    )
                )
            ),
            RenderFixture(
                name: "focus-win-row-celebrated-standard",
                width: 393,
                height: 220,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    FocusWinRow(
                        focusWin: celebratedWin,
                        usesStackedLayout: false,
                        isCelebrated: true,
                        celebrationSequence: 0,
                        accessibilityFocusRequestID: nil,
                        motionPolicy: standardMotionPolicy,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone,
                        consumeAccessibilityFocusRequest: { _ in },
                        requestDeletion: {}
                    )
                    .padding(20)
                    .checkpointScreenBackground()
                )
            ),
            RenderFixture(
                name: "focus-win-row-celebrated-accessibility5-tonal-only",
                width: 393,
                height: 720,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    FocusWinRow(
                        focusWin: celebratedWin,
                        usesStackedLayout: true,
                        isCelebrated: true,
                        celebrationSequence: 0,
                        accessibilityFocusRequestID: nil,
                        motionPolicy: tonalOnlyMotionPolicy,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone,
                        consumeAccessibilityFocusRequest: { _ in },
                        requestDeletion: {}
                    )
                    .padding(20)
                    .checkpointScreenBackground()
                )
            ),
            RenderFixture(
                name: "progress-focus-wins-entry",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(
                        store: populatedStore,
                        referenceDateOverride: referenceDate
                    )
                )
            )
        ]

        for fixture in fixtures {
            autoreleasepool {
                let image = HostedViewRenderer.image(
                    for: fixture.content
                        .environment(\.colorScheme, fixture.colorScheme)
                        .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                    width: fixture.width,
                    height: fixture.height,
                    colorScheme: fixture.colorScheme,
                    renderScale: 1
                )

                XCTAssertGreaterThan(image.size.width, 0)
                XCTAssertGreaterThan(image.size.height, 0)
                let attachment = XCTAttachment(image: image)
                attachment.name = fixture.name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour
                )
            )
        )
    }
}

private struct RenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var content: AnyView
}
