import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class WeeklyReviewRenderingTests: XCTestCase {
    func testCompactLayoutSignalsOverflowWithoutAWidthCliff() {
        let compact = WeeklyReviewResponsiveLayoutPolicy(
            viewportWidth: 320,
            dynamicTypeSize: .accessibility5
        )
        let justAboveCompact = WeeklyReviewResponsiveLayoutPolicy(
            viewportWidth: 321,
            dynamicTypeSize: .accessibility5
        )
        let transitionEnd = WeeklyReviewResponsiveLayoutPolicy(
            viewportWidth: 360,
            dynamicTypeSize: .accessibility5
        )
        let regular = WeeklyReviewResponsiveLayoutPolicy(
            viewportWidth: 393,
            dynamicTypeSize: .accessibility5
        )

        XCTAssertEqual(compact.screenHorizontalPadding, 12, accuracy: 0.01)
        XCTAssertEqual(compact.heroHorizontalPadding, 12, accuracy: 0.01)
        XCTAssertEqual(compact.dayDetailHorizontalPadding, 10, accuracy: 0.01)
        XCTAssertLessThan(
            abs(justAboveCompact.screenHorizontalPadding - compact.screenHorizontalPadding),
            0.25
        )
        XCTAssertLessThan(
            abs(justAboveCompact.dayDetailHorizontalPadding - compact.dayDetailHorizontalPadding),
            0.25
        )
        XCTAssertEqual(compact.dayDetailCopyAvailableWidth, 252, accuracy: 0.01)
        XCTAssertEqual(justAboveCompact.dayDetailCopyAvailableWidth, 252, accuracy: 0.01)
        XCTAssertEqual(transitionEnd.dayDetailCopyAvailableWidth, 252, accuracy: 0.01)

        XCTAssertEqual(WeeklyPracticeChartLayoutPolicy.minimumDayWidth, 44)
        XCTAssertEqual(
            WeeklyPracticeChartLayoutPolicy.overflowTreatment(
                availableWidth: compact.practiceChartAvailableWidth,
                dayCount: 7
            ),
            .horizontalScrollWithCue
        )
        XCTAssertEqual(
            WeeklyPracticeChartLayoutPolicy.overflowTreatment(
                availableWidth: regular.practiceChartAvailableWidth,
                dayCount: 7
            ),
            .fitted
        )
        XCTAssertGreaterThanOrEqual(
            regular.practiceChartAvailableWidth,
            WeeklyPracticeChartLayoutPolicy.minimumDayWidth * 7
        )
    }

    func testCompactAX5DetailMeasureCanKeepVisibleWordsWhole() {
        let policy = WeeklyReviewResponsiveLayoutPolicy(
            viewportWidth: 320,
            dynamicTypeSize: .accessibility5
        )
        let traits = UITraitCollection(
            preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        let preferredFont = UIFont.preferredFont(
            forTextStyle: .subheadline,
            compatibleWith: traits
        )
        let activityFont = UIFont.systemFont(
            ofSize: preferredFont.pointSize,
            weight: .semibold
        )
        let widestVisibleWord = ["questions", "answered"]
            .map {
                ($0 as NSString).size(withAttributes: [.font: activityFont]).width
            }
            .max() ?? 0

        XCTAssertGreaterThan(
            policy.dayDetailCopyAvailableWidth,
            ceil(widestVisibleWord) + 1
        )
    }

    @MainActor
    func testWeeklyReviewRendersDailyImpactAcrossKeyLayouts() throws {
        let suiteName = "WeeklyReviewRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))
        )
        let fixture = try makeWeeklyReviewStore(
            defaults: defaults,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: referenceDate))
        let monday = week.start
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        let wednesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: monday))
        let priorWeekStart = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -1, to: monday)
        )
        let priorSunday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 6, to: priorWeekStart)
        )
        let pastEmptyWeekStart = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -2, to: monday)
        )
        let pastEmptySunday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 6, to: pastEmptyWeekStart)
        )
        let fixtures = [
            WeeklyReviewRenderFixture(
                name: "weekly-review-daily-impact-light",
                width: 393,
                height: 1_250,
                colorScheme: .light,
                dynamicTypeSize: .large,
                initialMetricsID: WeeklyMetricsSummary.allGoalsID,
                initialWeekReferenceDate: referenceDate,
                initialSelectedPracticeDate: tuesday,
                reduceMotion: false
            ),
            WeeklyReviewRenderFixture(
                name: "weekly-review-daily-impact-compact-dark",
                width: 320,
                height: 1_200,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                initialMetricsID: WeeklyMetricsSummary.allGoalsID,
                initialWeekReferenceDate: referenceDate,
                initialSelectedPracticeDate: monday,
                reduceMotion: false
            ),
            WeeklyReviewRenderFixture(
                name: "weekly-review-daily-impact-ax5-dark-reduced",
                width: 393,
                height: 2_200,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                initialMetricsID: WeeklyMetricsSummary.allGoalsID,
                initialWeekReferenceDate: referenceDate,
                initialSelectedPracticeDate: wednesday,
                reduceMotion: true
            ),
            WeeklyReviewRenderFixture(
                name: "weekly-review-daily-impact-selected-goal-light",
                width: 393,
                height: 1_200,
                colorScheme: .light,
                dynamicTypeSize: .large,
                initialMetricsID: fixture.otherGoalID.uuidString,
                initialWeekReferenceDate: referenceDate,
                initialSelectedPracticeDate: tuesday,
                reduceMotion: false
            ),
            WeeklyReviewRenderFixture(
                name: "weekly-review-archive-active-sunday-compact-dark",
                width: 320,
                height: 1_350,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                initialMetricsID: WeeklyMetricsSummary.allGoalsID,
                initialWeekReferenceDate: priorSunday,
                initialSelectedPracticeDate: priorSunday,
                reduceMotion: false
            ),
            WeeklyReviewRenderFixture(
                name: "weekly-review-archive-empty-compact-ax5-dark-reduced",
                width: 320,
                height: 2_200,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                initialMetricsID: WeeklyMetricsSummary.allGoalsID,
                initialWeekReferenceDate: pastEmptySunday,
                initialSelectedPracticeDate: pastEmptySunday,
                reduceMotion: true
            )
        ]

        for renderFixture in fixtures {
            let image = HostedViewRenderer.image(
                for: WeeklyReviewView(
                    store: fixture.store,
                    initialMetricsID: renderFixture.initialMetricsID,
                    referenceDate: referenceDate,
                    displayCalendar: calendar,
                    displayLocale: Locale(identifier: "en_US"),
                    displayTimeZone: calendar.timeZone,
                    reduceMotionOverride: renderFixture.reduceMotion,
                    initialSelectedPracticeDate: renderFixture.initialSelectedPracticeDate,
                    initialWeekReferenceDate: renderFixture.initialWeekReferenceDate
                )
                .environment(\.colorScheme, renderFixture.colorScheme)
                .environment(\.dynamicTypeSize, renderFixture.dynamicTypeSize),
                width: renderFixture.width,
                height: renderFixture.height,
                colorScheme: renderFixture.colorScheme,
                settlingTime: renderFixture.reduceMotion ? 0.05 : 0.65,
                renderScale: 1
            )

            XCTAssertEqual(image.size.width, renderFixture.width, accuracy: 0.5)
            XCTAssertEqual(image.size.height, renderFixture.height, accuracy: 0.5)
            let attachment = XCTAttachment(image: image)
            attachment.name = renderFixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func makeWeeklyReviewStore(
        defaults: UserDefaults,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> (store: CheckpointStore, otherGoalID: Goal.ID) {
        let week = try XCTUnwrap(
            calendar.dateInterval(of: .weekOfYear, for: referenceDate)
        )
        let activeGoal = Goal(
            title: "Launch a senior product design portfolio",
            deadline: referenceDate.addingTimeInterval(86_400 * 28),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "storytelling, product rationale",
            preferredQuestionStyle: .reflection,
            createdAt: referenceDate.addingTimeInterval(-500)
        )
        let otherGoal = Goal(
            title: "Prepare for systems design interviews",
            deadline: referenceDate.addingTimeInterval(86_400 * 42),
            category: .codingInterview,
            currentLevel: "Advanced",
            focusAreas: "reliability, tradeoffs",
            preferredQuestionStyle: .shortAnswer,
            createdAt: referenceDate.addingTimeInterval(-400)
        )
        let quietGoal = Goal(
            title: "Build conversational Spanish",
            deadline: referenceDate.addingTimeInterval(86_400 * 90),
            category: .languageLearning,
            currentLevel: "Beginner",
            focusAreas: "speaking, listening",
            preferredQuestionStyle: .shortAnswer,
            createdAt: referenceDate.addingTimeInterval(-300)
        )
        let monday = week.start.addingTimeInterval(60 * 60 * 9)
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        let wednesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: monday))
        let priorWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: monday))
        let priorSunday = try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: priorWeek))
        let oldestSunday = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -2, to: priorSunday)
        )
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = .member
        store.goal = activeGoal
        store.goalProfiles = [activeGoal, otherGoal, quietGoal]
        store.attempts = [
            makeAttempt(goal: activeGoal, result: .correct, createdAt: monday),
            makeAttempt(goal: activeGoal, result: .correct, createdAt: monday.addingTimeInterval(120)),
            makeAttempt(goal: activeGoal, result: .incorrect, createdAt: tuesday),
            makeAttempt(goal: activeGoal, result: .correct, createdAt: tuesday.addingTimeInterval(120)),
            makeAttempt(goal: activeGoal, result: .partial, createdAt: wednesday),
            makeAttempt(goal: activeGoal, result: .correct, createdAt: wednesday.addingTimeInterval(120)),
            makeAttempt(goal: otherGoal, result: .correct, createdAt: monday),
            makeAttempt(goal: otherGoal, result: .correct, createdAt: tuesday),
            makeAttempt(goal: otherGoal, result: .incorrect, createdAt: tuesday.addingTimeInterval(120)),
            makeAttempt(goal: activeGoal, result: .correct, createdAt: priorWeek),
            makeAttempt(goal: activeGoal, result: .incorrect, createdAt: priorWeek.addingTimeInterval(120)),
            makeAttempt(goal: activeGoal, result: .correct, createdAt: priorSunday),
            makeAttempt(goal: otherGoal, result: .partial, createdAt: priorSunday.addingTimeInterval(120)),
            makeAttempt(goal: activeGoal, result: .correct, createdAt: oldestSunday)
        ]
        store.unlockEvents = [
            UnlockEvent(goalID: activeGoal.id, minutes: 30, createdAt: monday),
            UnlockEvent(goalID: activeGoal.id, minutes: 20, createdAt: tuesday),
            UnlockEvent(goalID: otherGoal.id, minutes: 15, createdAt: tuesday),
            UnlockEvent(goalID: activeGoal.id, minutes: 25, createdAt: priorSunday)
        ]

        var activeReview = TopicCompetency.initial(
            topic: "Portfolio narrative",
            goalID: activeGoal.id
        )
        activeReview.attempts = 5
        activeReview.correct = 2
        activeReview.incorrect = 3
        var activeStrong = TopicCompetency.initial(
            topic: "Product rationale",
            goalID: activeGoal.id
        )
        activeStrong.attempts = 5
        activeStrong.correct = 5
        var otherReview = TopicCompetency.initial(
            topic: "Failure recovery",
            goalID: otherGoal.id
        )
        otherReview.attempts = 4
        otherReview.correct = 1
        otherReview.incorrect = 3
        var otherStrong = TopicCompetency.initial(
            topic: "Capacity planning",
            goalID: otherGoal.id
        )
        otherStrong.attempts = 4
        otherStrong.correct = 4
        store.competencies = [
            activeReview,
            activeStrong,
            otherReview,
            otherStrong
        ]

        return (store, otherGoal.id)
    }
}

private struct WeeklyReviewRenderFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let initialMetricsID: String
    let initialWeekReferenceDate: Date
    let initialSelectedPracticeDate: Date?
    let reduceMotion: Bool
}
