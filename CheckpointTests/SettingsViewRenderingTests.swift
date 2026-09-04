import SwiftUI
import XCTest
@testable import Checkpoint

final class SettingsViewRenderingTests: XCTestCase {
    func testPracticeStandardPresentationKeepsExactContractPrimary() {
        let defaultPresentation = SettingsPracticeStandardPresentation(
            unlockPolicy: .default
        )

        XCTAssertEqual(defaultPresentation.questionCount, 5)
        XCTAssertEqual(defaultPresentation.requiredCorrectAnswers, 4)
        XCTAssertEqual(defaultPresentation.unlockMinutes, 30)
        XCTAssertEqual(defaultPresentation.passPercent, 80)
        XCTAssertEqual(defaultPresentation.headline, "Pass 4 of 5")
        XCTAssertEqual(
            defaultPresentation.detail,
            "When protection is on, passing opens protected apps for 30 minutes."
        )
        XCTAssertTrue(defaultPresentation.accessibilityValue.contains("5 questions"))
        XCTAssertTrue(defaultPresentation.accessibilityValue.contains("4 correct answers required"))
        XCTAssertTrue(defaultPresentation.accessibilityValue.contains("When protection is on"))
        XCTAssertTrue(defaultPresentation.accessibilityValue.contains("30 minutes"))
        XCTAssertTrue(defaultPresentation.accessibilityValue.contains("Applies to every goal"))

        let strict = SettingsPracticeStandardPresentation(
            unlockPolicy: policy(
                questions: 10,
                requiredCorrectAnswers: 10,
                unlockMinutes: 5
            )
        )
        XCTAssertEqual(strict.passPercent, 100)
        XCTAssertEqual(strict.headline, "Pass 10 of 10")
        XCTAssertEqual(
            strict.detail,
            "When protection is on, passing opens protected apps for 5 minutes."
        )

        let clamped = SettingsPracticeStandardPresentation(
            unlockPolicy: policy(
                questions: 5,
                requiredCorrectAnswers: 10,
                unlockMinutes: 15
            )
        )
        XCTAssertEqual(clamped.questionCount, 5)
        XCTAssertEqual(clamped.requiredCorrectAnswers, 5)
        XCTAssertEqual(clamped.passPercent, 100)
        XCTAssertEqual(clamped.headline, "Pass 5 of 5")
        XCTAssertEqual(
            clamped.detail,
            "When protection is on, passing opens protected apps for 15 minutes."
        )
    }

    func testPracticeStandardMotionPolicyHonorsReduceMotion() {
        XCTAssertNotNil(SettingsPracticeStandardMotionPolicy(reduceMotion: false).animation)
        XCTAssertNil(SettingsPracticeStandardMotionPolicy(reduceMotion: true).animation)
    }

    @MainActor
    func testLoweringQuestionCountClampsTheVisibleContractAtomically() throws {
        let suiteName = "SettingsViewRenderingTests.Clamp.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CheckpointStore(defaults: defaults)
        store.unlockPolicy = policy(
            questions: 10,
            requiredCorrectAnswers: 10,
            unlockMinutes: 15
        )

        store.updateQuestionsPerSession(5)

        let presentation = SettingsPracticeStandardPresentation(
            unlockPolicy: store.unlockPolicy
        )
        XCTAssertEqual(store.unlockPolicy.questionsPerSession, 5)
        XCTAssertEqual(store.unlockPolicy.requiredCorrectAnswers, 5)
        XCTAssertEqual(presentation.questionCount, 5)
        XCTAssertEqual(presentation.requiredCorrectAnswers, 5)
        XCTAssertEqual(presentation.headline, "Pass 5 of 5")
        XCTAssertEqual(
            presentation.detail,
            "When protection is on, passing opens protected apps for 15 minutes."
        )
    }

    @MainActor
    func testPracticeStandardCardRendersAcrossKeyLayouts() {
        let fixtures = [
            SettingsPracticeStandardRenderFixture(
                name: "settings-standard-default-collapsed-light",
                width: 393,
                height: 620,
                colorScheme: .light,
                dynamicTypeSize: .large,
                policy: .default,
                isExpanded: false,
                reduceMotion: false
            ),
            SettingsPracticeStandardRenderFixture(
                name: "settings-standard-strict-expanded-compact-dark",
                width: 320,
                height: 1_050,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                policy: policy(
                    questions: 10,
                    requiredCorrectAnswers: 10,
                    unlockMinutes: 5
                ),
                isExpanded: true,
                reduceMotion: false
            ),
            SettingsPracticeStandardRenderFixture(
                name: "settings-standard-expanded-accessibility5-reduced-motion",
                width: 393,
                height: 2_600,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                policy: .default,
                isExpanded: true,
                reduceMotion: true
            ),
            SettingsPracticeStandardRenderFixture(
                name: "settings-standard-clamped-five-of-five",
                width: 393,
                height: 620,
                colorScheme: .light,
                dynamicTypeSize: .large,
                policy: policy(
                    questions: 5,
                    requiredCorrectAnswers: 10,
                    unlockMinutes: 15
                ),
                isExpanded: false,
                reduceMotion: true
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: SettingsPracticeStandardRenderScene(fixture: fixture)
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: fixture.reduceMotion ? 0.05 : 0.35,
                renderScale: 1
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
    func testSettingsViewRendersTheAssembledControlCenter() async throws {
        resetSharedAppGroupState()
        defer { resetSharedAppGroupState() }

        let storeSuiteName = "SettingsViewRenderingTests.Store.\(UUID().uuidString)"
        let screenTimeSuiteName = "SettingsViewRenderingTests.ScreenTime.\(UUID().uuidString)"
        let storeDefaults = try XCTUnwrap(UserDefaults(suiteName: storeSuiteName))
        let screenTimeDefaults = try XCTUnwrap(UserDefaults(suiteName: screenTimeSuiteName))
        defer {
            storeDefaults.removePersistentDomain(forName: storeSuiteName)
            screenTimeDefaults.removePersistentDomain(forName: screenTimeSuiteName)
        }

        let goal = Goal(
            title: "Pass senior technical interviews",
            deadline: fixedDate(year: 2027, month: 2, day: 14),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "system design, reliability, communication",
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: storeDefaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.membershipTier = .member

        let screenTime = ScreenTimeController(
            defaults: screenTimeDefaults,
            authorizer: SettingsRenderScreenTimeAuthorizer()
        )
        await screenTime.bootstrapAuthorizationIfNeeded()
        let purchaseController = PurchaseController(grantsDebugTesterEntitlement: false)
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: screenTime)

        let image = HostedViewRenderer.image(
            for: SettingsView(
                store: store,
                screenTime: screenTime,
                purchaseController: purchaseController,
                workflow: workflow,
                presentCheckpoint: { _ in false }
            )
            .environment(\.colorScheme, ColorScheme.light)
            .environment(\.dynamicTypeSize, DynamicTypeSize.large)
            .environment(\.checkpointGoalSelection, GoalSelectionAction { _ in }),
            width: 393,
            height: 2_400,
            colorScheme: .light,
            settlingTime: 0.45,
            renderScale: 0.5
        )

        XCTAssertEqual(image.size.width, 393, accuracy: 1)
        XCTAssertEqual(image.size.height, 2_400, accuracy: 1)
        let attachment = XCTAttachment(image: image)
        attachment.name = "settings-control-center-assembled-light"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func policy(
        questions: Int,
        requiredCorrectAnswers: Int,
        unlockMinutes: Int
    ) -> UnlockPolicy {
        UnlockPolicy(
            unlockMinutes: unlockMinutes,
            partialUnlockMinutes: 15,
            unlockOnPartial: true,
            questionsPerSession: questions,
            requiredCorrectAnswers: requiredCorrectAnswers,
            minimumQuestionDifficulty: 1
        )
    }

    private func fixedDate(
        year: Int,
        month: Int,
        day: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )!
    }
}

private struct SettingsPracticeStandardRenderFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let policy: UnlockPolicy
    let isExpanded: Bool
    let reduceMotion: Bool
}

private struct SettingsPracticeStandardRenderScene: View {
    let fixture: SettingsPracticeStandardRenderFixture
    @State private var isExpanded: Bool

    init(fixture: SettingsPracticeStandardRenderFixture) {
        self.fixture = fixture
        _isExpanded = State(initialValue: fixture.isExpanded)
    }

    var body: some View {
        ScrollView {
            SettingsPracticeStandardCard(
                presentation: SettingsPracticeStandardPresentation(
                    unlockPolicy: fixture.policy
                ),
                isExpanded: $isExpanded,
                reduceMotionOverride: fixture.reduceMotion
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    PracticeStandardStepperRow(
                        title: "Questions per checkpoint",
                        value: fixture.policy.questionsPerSession,
                        decrementDisabled: fixture.policy.questionsPerSession <= UnlockPolicy.minimumQuestionsPerSession,
                        incrementDisabled: fixture.policy.questionsPerSession >= UnlockPolicy.maximumQuestionsPerSession,
                        decrementAction: {},
                        incrementAction: {}
                    )

                    PracticeStandardStepperRow(
                        title: "Correct answers needed",
                        value: fixture.policy.requiredCorrectAnswers,
                        decrementDisabled: fixture.policy.requiredCorrectAnswers <= UnlockPolicy.minimumRequiredCorrectAnswers,
                        incrementDisabled: fixture.policy.requiredCorrectAnswers >= fixture.policy.questionsPerSession,
                        decrementAction: {},
                        incrementAction: {}
                    )

                    BreakDurationMenu(
                        selectedMinutes: fixture.policy.unlockMinutes,
                        options: UnlockPolicy.correctAnswerUnlockMinuteOptions,
                        selectMinutes: { _ in }
                    )
                }
            }
            .padding(20)
            .padding(.bottom, 36)
        }
        .checkpointScreenBackground()
    }
}

@MainActor
private final class SettingsRenderScreenTimeAuthorizer: ScreenTimeAuthorizing {
    var authorizationStatus: ScreenTimeAuthorizationStatus { .approved }

    func requestAuthorization() async throws {}
}
