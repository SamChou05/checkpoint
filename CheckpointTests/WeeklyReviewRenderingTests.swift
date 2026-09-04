import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class WeeklyReviewRenderingTests: XCTestCase {
    @MainActor
    func testWeeklyReviewRendersGoalPulseAcrossKeyLayouts() throws {
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
        let fixtures = [
            WeeklyReviewRenderFixture(
                name: "weekly-review-goal-pulse-light",
                width: 393,
                height: 1_250,
                colorScheme: .light,
                dynamicTypeSize: .large,
                initialMetricsID: WeeklyMetricsSummary.allGoalsID,
                reduceMotion: false
            ),
            WeeklyReviewRenderFixture(
                name: "weekly-review-goal-pulse-compact-dark",
                width: 320,
                height: 1_200,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                initialMetricsID: WeeklyMetricsSummary.allGoalsID,
                reduceMotion: false
            ),
            WeeklyReviewRenderFixture(
                name: "weekly-review-goal-pulse-ax2-dark-reduced",
                width: 393,
                height: 1_850,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                initialMetricsID: WeeklyMetricsSummary.allGoalsID,
                reduceMotion: true
            ),
            WeeklyReviewRenderFixture(
                name: "weekly-review-selected-goal-light",
                width: 393,
                height: 1_200,
                colorScheme: .light,
                dynamicTypeSize: .large,
                initialMetricsID: fixture.otherGoalID.uuidString,
                reduceMotion: false
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
                    reduceMotionOverride: renderFixture.reduceMotion
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
            makeAttempt(goal: activeGoal, result: .incorrect, createdAt: priorWeek.addingTimeInterval(120))
        ]
        store.unlockEvents = [
            UnlockEvent(goalID: activeGoal.id, minutes: 30, createdAt: monday),
            UnlockEvent(goalID: activeGoal.id, minutes: 20, createdAt: tuesday),
            UnlockEvent(goalID: otherGoal.id, minutes: 15, createdAt: tuesday)
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
    let reduceMotion: Bool
}
