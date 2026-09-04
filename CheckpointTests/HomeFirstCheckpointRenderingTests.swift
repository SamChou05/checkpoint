import SwiftUI
import XCTest
@testable import Checkpoint

final class HomeFirstCheckpointRenderingTests: XCTestCase {
    @MainActor
    func testGoalSwitchMenuPresentationDescribesIdentityReadinessAndAccess() throws {
        let suiteName = "GoalSwitchMenuPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = fixedGoalSwitchCalendar
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = fixedGoalSwitchTimeZone
        let currentGoal = Goal(
            title: "Learn Swift",
            deadline: fixedGoalSwitchDate(month: 1, day: 10),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays",
            preferredQuestionStyle: .multipleChoice
        )
        let readyGoal = Goal(
            title: "Learn Swift",
            deadline: fixedGoalSwitchDate(month: 1, day: 20),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "concurrency",
            preferredQuestionStyle: .multipleChoice
        )
        let notReadyGoal = Goal(
            title: "Write clearly",
            deadline: fixedGoalSwitchDate(month: 2, day: 10),
            category: .writing,
            currentLevel: "Intermediate",
            focusAreas: "structure",
            preferredQuestionStyle: .shortAnswer
        )
        let preparingGoal = Goal(
            title: "Study calculus",
            deadline: fixedGoalSwitchDate(month: 3, day: 10),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "integrals",
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = .member
        store.goal = currentGoal
        store.goalProfiles = [currentGoal, readyGoal, notReadyGoal, preparingGoal]
        store.questions = (1...store.unlockPolicy.questionsPerSession).map {
            makeQuestion(goal: readyGoal, index: $0, topic: "concurrency")
        } + (101...102).map {
            makeQuestion(goal: notReadyGoal, index: $0, topic: "structure")
        } + [
            makeQuestion(goal: preparingGoal, index: 201, topic: "integrals")
        ]
        store.questionBankSyncIntents = [
            QuestionBankSyncIntent(
                goalID: preparingGoal.id,
                contextRevision: "pending-preparation",
                desiredCount: 10,
                lowWatermark: 5
            )
        ]

        let presentation = GoalSwitchMenuPresentation(
            store: store,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let current = try XCTUnwrap(presentation.options.first { $0.id == currentGoal.id })
        let ready = try XCTUnwrap(presentation.options.first { $0.id == readyGoal.id })
        let notReady = try XCTUnwrap(presentation.options.first { $0.id == notReadyGoal.id })
        let preparing = try XCTUnwrap(presentation.options.first { $0.id == preparingGoal.id })

        XCTAssertEqual(current.title, "Learn Swift · due Jan 10")
        XCTAssertEqual(ready.title, "Learn Swift · due Jan 20")
        XCTAssertNotEqual(current.title, ready.title)
        XCTAssertEqual(current.state, .current)
        XCTAssertEqual(current.menuTitle, "Learn Swift · due Jan 10")
        XCTAssertEqual(current.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(current.accessibilityValue, "Current goal")
        XCTAssertEqual(ready.state, .ready)
        XCTAssertEqual(ready.menuTitle, "Learn Swift · due Jan 20 · Ready")
        XCTAssertEqual(ready.systemImage, "circle")
        XCTAssertEqual(ready.accessibilityValue, "Checkpoint ready")
        XCTAssertEqual(notReady.state, .notReady(selectableCount: 2, requiredCount: 5))
        XCTAssertEqual(notReady.menuTitle, "Write clearly · Not ready")
        XCTAssertEqual(notReady.systemImage, "exclamationmark.circle")
        XCTAssertEqual(notReady.accessibilityValue, "Not ready, 2 of 5 questions ready")
        XCTAssertEqual(preparing.state, .preparing(selectableCount: 1, requiredCount: 5))
        XCTAssertEqual(preparing.menuTitle, "Study calculus · Preparing")
        XCTAssertEqual(preparing.systemImage, "hourglass")
        XCTAssertEqual(preparing.accessibilityValue, "Preparing, 1 of 5 questions ready")

        store.membershipTier = .starter
        let lockedPresentation = GoalSwitchMenuPresentation(
            store: store,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let locked = try XCTUnwrap(
            lockedPresentation.options.first { $0.id == readyGoal.id }
        )
        XCTAssertEqual(locked.state, .locked)
        XCTAssertEqual(locked.menuTitle, "Learn Swift · due Jan 20 · Pro")
        XCTAssertEqual(locked.systemImage, "lock.fill")
        XCTAssertEqual(locked.accessibilityValue, "Requires Pro")
    }

    @MainActor
    func testGoalSwitchConfirmationPresentationUsesExactProtectionCopy() {
        let calendar = fixedGoalSwitchCalendar
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = fixedGoalSwitchTimeZone
        let sourceGoal = Goal(
            title: "Learn Swift",
            deadline: fixedGoalSwitchDate(month: 1, day: 10),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays",
            preferredQuestionStyle: .multipleChoice
        )
        let targetGoal = Goal(
            title: "Learn Swift",
            deadline: fixedGoalSwitchDate(month: 1, day: 20),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "concurrency",
            preferredQuestionStyle: .multipleChoice
        )
        let immediate = GoalSwitchConfirmationPresentation(
            confirmation: GoalSwitchConfirmation(
                sourceGoalID: sourceGoal.id,
                sourceTitle: sourceGoal.title,
                targetGoalID: targetGoal.id,
                targetTitle: targetGoal.title,
                readiness: .incomplete(selectableCount: 2, requiredCount: 5),
                impact: .turnsOffImmediately
            ),
            goals: [sourceGoal, targetGoal],
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertEqual(immediate.sourceTitle, "Learn Swift · due Jan 10")
        XCTAssertEqual(immediate.targetTitle, "Learn Swift · due Jan 20")
        XCTAssertEqual(immediate.title, "Switch goal and turn off protection?")
        XCTAssertEqual(immediate.readinessText, "2 of 5 questions ready")
        XCTAssertEqual(
            immediate.message,
            "Learn Swift · due Jan 20 has 2 of 5 questions ready. Switching now turns off app protection. Start protection again after a full checkpoint is ready."
        )
        XCTAssertEqual(immediate.confirmationButtonTitle, "Switch and turn off")
        XCTAssertEqual(immediate.cancelButtonTitle, "Keep current goal")

        let activeBreak = GoalSwitchConfirmationPresentation(
            confirmation: GoalSwitchConfirmation(
                sourceGoalID: sourceGoal.id,
                sourceTitle: sourceGoal.title,
                targetGoalID: targetGoal.id,
                targetTitle: targetGoal.title,
                readiness: .preparing(selectableCount: 1, requiredCount: 5),
                impact: .preventsRelockAfterBreak
            ),
            goals: [sourceGoal, targetGoal],
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertEqual(activeBreak.title, "Switch goal before this break ends?")
        XCTAssertEqual(activeBreak.readinessText, "1 of 5 questions ready")
        XCTAssertEqual(
            activeBreak.message,
            "Your break will continue, but protection won't return when it ends because Learn Swift · due Jan 20 has only 1 of 5 questions ready. Start protection again after a full checkpoint is ready."
        )
        XCTAssertEqual(activeBreak.confirmationButtonTitle, "Switch goal")
        XCTAssertEqual(activeBreak.cancelButtonTitle, "Keep current goal")
    }

    @MainActor
    func testGoalIdentityMotionPolicyHonorsReduceMotion() {
        let standard = GoalIdentityMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .crossfade)
        XCTAssertNotNil(standard.animation)

        let reduced = GoalIdentityMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
    }

    @MainActor
    func testGoalSwitcherRendersAcrossKeyLayoutsAndStates() throws {
        let fixtures = [
            HomeGoalSwitchRenderFixture(
                name: "home-goal-switch-ready-light",
                width: 393,
                height: 1_000,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .ready
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-switch-ready-dark",
                width: 393,
                height: 1_000,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                state: .ready
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-switch-compact-long-duplicate",
                width: 320,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .ready
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-switch-preparing-accessibility5",
                width: 393,
                height: 1_800,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                state: .preparing
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-switch-failure-dark",
                width: 393,
                height: 1_150,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                state: .failed
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-switch-starter-locked-reduced-motion",
                width: 393,
                height: 1_000,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .starterLocked,
                reduceMotion: true
            )
        ]

        resetSharedAppGroupState()
        defer { resetSharedAppGroupState() }

        for fixture in fixtures {
            let storeSuiteName = "HomeGoalSwitchRenderingTests.Store.\(UUID().uuidString)"
            let screenTimeSuiteName = "HomeGoalSwitchRenderingTests.ScreenTime.\(UUID().uuidString)"
            let storeDefaults = try XCTUnwrap(UserDefaults(suiteName: storeSuiteName))
            let screenTimeDefaults = try XCTUnwrap(UserDefaults(suiteName: screenTimeSuiteName))
            defer {
                storeDefaults.removePersistentDomain(forName: storeSuiteName)
                screenTimeDefaults.removePersistentDomain(forName: screenTimeSuiteName)
            }

            let store = makeGoalSwitchRenderStore(
                defaults: storeDefaults,
                state: fixture.state
            )
            let screenTime = ScreenTimeController(
                defaults: screenTimeDefaults,
                authorizer: HomeRenderScreenTimeAuthorizer()
            )
            let workflow = CheckpointWorkflowCoordinator(
                store: store,
                protection: screenTime
            )
            let image = HostedViewRenderer.image(
                for: HomeView(
                    store: store,
                    screenTime: screenTime,
                    workflow: workflow,
                    refreshesQuestionsOnActivation: false,
                    reduceMotionOverride: fixture.reduceMotion
                )
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: fixture.reduceMotion ? 0.05 : 0.35,
                renderScale: 0.5
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 1, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 1, fixture.name)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = XCTAttachment.Lifetime.keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testFirstCheckpointLaunchpadRendersAcrossKeyLayouts() {
        let fixtures = [
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-accessibility",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: launchpadSurface
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                // Preserve point geometry while keeping the full render suite's retained attachments bounded.
                renderScale: 0.5
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 1)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testEarnedBreakCardRendersAcrossKeyLayouts() {
        let fixtures = [
            HomeBreakRenderFixture(
                name: "earned-break-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-dark-ending-soon",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                secondsRemaining: 46
            ),
            HomeBreakRenderFixture(
                name: "earned-break-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-accessibility-2",
                width: 393,
                height: 1_100,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-accessibility-5-dark",
                width: 393,
                height: 2_200,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-reduce-motion",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                secondsRemaining: 0,
                relockReadiness: .waitingForCheckpoint,
                areProtectedAppsAvailable: false,
                reduceMotion: true
            )
        ]

        for fixture in fixtures {
            let now = Date()
            let image = HostedViewRenderer.image(
                for: ScrollView {
                    HomeActiveBreakCard(
                        startedAt: now.addingTimeInterval(-12 * 60),
                        expiresAt: now.addingTimeInterval(TimeInterval(fixture.secondsRemaining)),
                        relockReadiness: fixture.relockReadiness,
                        areProtectedAppsAvailable: fixture.areProtectedAppsAvailable,
                        protectedAppsSummary: "3 apps, 1 category, 2 sites selected",
                        reduceMotionOverride: fixture.reduceMotion,
                        manageApps: {},
                        endBreakEarly: {}
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
                .checkpointScreenBackground()
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                // Preserve point geometry while keeping the full render suite's retained attachments bounded.
                renderScale: 0.5
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 1)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = XCTAttachment.Lifetime.keepAlways
            add(attachment)
        }
    }

    @MainActor
    private var launchpadSurface: some View {
        ScrollView {
            HomeFirstCheckpointLaunchpad(
                requiredCorrectAnswers: 4,
                questionCount: 5,
                unlockMinutes: 30,
                protectedAppsSummary: "3 apps and 2 websites selected",
                reviewApps: {}
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 36)
        }
        .checkpointScreenBackground()
    }

    @MainActor
    private func makeGoalSwitchRenderStore(
        defaults: UserDefaults,
        state: HomeGoalSwitchRenderState
    ) -> CheckpointStore {
        let firstGoal = Goal(
            title: "Build a polished, production-ready learning system",
            deadline: Date(timeIntervalSinceReferenceDate: 820_454_400),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "system design, reliability, communication",
            preferredQuestionStyle: .multipleChoice
        )
        let secondGoal = Goal(
            title: firstGoal.title,
            deadline: Date(timeIntervalSinceReferenceDate: 828_230_400),
            category: .writing,
            currentLevel: "Intermediate",
            focusAreas: "structure, editing, clarity",
            preferredQuestionStyle: .shortAnswer
        )
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = state == .starterLocked ? .starter : .member
        store.goal = firstGoal
        store.goalProfiles = [firstGoal, secondGoal]

        switch state {
        case .ready, .starterLocked:
            store.questions = (1...store.unlockPolicy.questionsPerSession).map {
                makeQuestion(goal: firstGoal, index: $0, topic: "system design")
            }
            store.questionBatchState = .ready
        case .preparing:
            store.questions = (1...2).map {
                makeQuestion(goal: firstGoal, index: $0, topic: "system design")
            }
            store.questionBatchState = .generating
        case .failed:
            store.questions = []
            store.questionBatchState = .failed
            store.lastQuestionGenerationFailure = .qualityRejected
        }

        return store
    }

    private var fixedGoalSwitchTimeZone: TimeZone {
        TimeZone(secondsFromGMT: 0)!
    }

    private var fixedGoalSwitchCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = fixedGoalSwitchTimeZone
        return calendar
    }

    private func fixedGoalSwitchDate(month: Int, day: Int) -> Date {
        fixedGoalSwitchCalendar.date(
            from: DateComponents(year: 2027, month: month, day: day, hour: 12)
        )!
    }
}

private struct HomeLaunchpadRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
}

private struct HomeBreakRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var secondsRemaining: Int
    var relockReadiness: HomeActiveBreakRelockReadiness = .ready
    var areProtectedAppsAvailable = true
    var reduceMotion = false
}

private struct HomeGoalSwitchRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var state: HomeGoalSwitchRenderState
    var reduceMotion = false
}

private enum HomeGoalSwitchRenderState {
    case ready
    case preparing
    case failed
    case starterLocked
}

@MainActor
private final class HomeRenderScreenTimeAuthorizer: ScreenTimeAuthorizing {
    var authorizationStatus: ScreenTimeAuthorizationStatus { .approved }

    func requestAuthorization() async throws {}
}
