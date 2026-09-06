import XCTest
@testable import Checkpoint

final class FirstRunSetupCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FirstRunSetupCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    func testPreparationTimeoutPreservesPendingSetupAndPresentation() async {
        let clock = FirstRunSetupTestClock()
        let coordinator = FirstRunSetupCoordinator(
            defaults: defaults,
            preparationTimeout: 2,
            now: { clock.now },
            sleep: { _ in clock.advance(by: 1) }
        )
        var startCount = 0
        coordinator.begin()
        coordinator.presentAppSelection()

        let result = await coordinator.startProtection(
            isPreparingQuestions: { true },
            startProtection: {
                startCount += 1
                return true
            },
            checkpointNotice: { nil },
            screenTimeErrorMessage: { nil },
            selectionSummary: { "2 apps selected" },
            currentGoalID: { UUID() }
        )

        XCTAssertEqual(
            result,
            .failed(
                message: "Your first checkpoint is still being prepared. Try again in a moment."
            )
        )
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(clock.advanceCount, 2)
        XCTAssertTrue(coordinator.isPending)
        XCTAssertTrue(coordinator.isAppSelectionPresented)
        XCTAssertTrue(FirstRunSetupProgress.isPending(defaults: defaults))
        XCTAssertNil(coordinator.suppressedSuggestedSkillMapGoalID)
    }

    @MainActor
    func testInterruptedPreparationPreservesPendingSetup() async {
        let coordinator = FirstRunSetupCoordinator(
            defaults: defaults,
            sleep: { _ in throw CancellationError() }
        )
        coordinator.begin()
        coordinator.presentAppSelection()

        let result = await coordinator.startProtection(
            isPreparingQuestions: { true },
            startProtection: { true },
            checkpointNotice: { nil },
            screenTimeErrorMessage: { nil },
            selectionSummary: { "2 apps selected" },
            currentGoalID: { UUID() }
        )

        XCTAssertEqual(
            result,
            .failed(message: "Setup was interrupted. Try turning protection on again.")
        )
        XCTAssertTrue(coordinator.isPending)
        XCTAssertTrue(coordinator.isAppSelectionPresented)
        XCTAssertTrue(FirstRunSetupProgress.isPending(defaults: defaults))
    }

    @MainActor
    func testGoalMismatchBeforeProtectionStartPreservesPendingSetup() async {
        let expectedGoalID = UUID()
        let currentGoalID = UUID()
        let coordinator = FirstRunSetupCoordinator(defaults: defaults)
        var startCount = 0
        coordinator.begin()
        coordinator.presentAppSelection()

        let result = await coordinator.startProtection(
            isPreparingQuestions: { false },
            startProtection: {
                startCount += 1
                return true
            },
            checkpointNotice: { nil },
            screenTimeErrorMessage: { nil },
            selectionSummary: { "2 apps selected" },
            currentGoalID: { currentGoalID },
            expectedGoalID: expectedGoalID
        )

        XCTAssertEqual(
            result,
            .failed(message: FirstRunSetupCoordinator.goalChangedMessage)
        )
        XCTAssertEqual(startCount, 0)
        XCTAssertTrue(coordinator.isPending)
        XCTAssertTrue(coordinator.isAppSelectionPresented)
        XCTAssertTrue(FirstRunSetupProgress.isPending(defaults: defaults))
        XCTAssertNil(coordinator.suppressedSuggestedSkillMapGoalID)
    }

    @MainActor
    func testGoalReplacementDuringProtectionStartDoesNotCompleteSetup() async {
        let expectedGoalID = UUID()
        let replacementGoalID = UUID()
        let coordinator = FirstRunSetupCoordinator(defaults: defaults)
        var currentGoalID = expectedGoalID
        coordinator.begin()
        coordinator.presentAppSelection()

        let result = await coordinator.startProtection(
            isPreparingQuestions: { false },
            startProtection: {
                currentGoalID = replacementGoalID
                return true
            },
            checkpointNotice: { nil },
            screenTimeErrorMessage: { nil },
            selectionSummary: { "2 apps selected" },
            currentGoalID: { currentGoalID },
            expectedGoalID: expectedGoalID
        )

        XCTAssertEqual(
            result,
            .failed(message: FirstRunSetupCoordinator.goalChangedMessage)
        )
        XCTAssertEqual(currentGoalID, replacementGoalID)
        XCTAssertTrue(coordinator.isPending)
        XCTAssertTrue(coordinator.isAppSelectionPresented)
        XCTAssertTrue(FirstRunSetupProgress.isPending(defaults: defaults))
        XCTAssertNil(coordinator.suppressedSuggestedSkillMapGoalID)
    }

    @MainActor
    func testCancellationAfterProtectionStartPreservesPendingSetup() async {
        let goalID = UUID()
        let coordinator = FirstRunSetupCoordinator(defaults: defaults)
        coordinator.begin()
        coordinator.presentAppSelection()

        let result = await coordinator.startProtection(
            isPreparingQuestions: { false },
            startProtection: {
                withUnsafeCurrentTask { task in
                    task?.cancel()
                }
                return true
            },
            checkpointNotice: { nil },
            screenTimeErrorMessage: { nil },
            selectionSummary: { "2 apps selected" },
            currentGoalID: { goalID },
            expectedGoalID: goalID
        )

        XCTAssertEqual(
            result,
            .failed(message: "Setup was interrupted. Try turning protection on again.")
        )
        XCTAssertTrue(coordinator.isPending)
        XCTAssertTrue(coordinator.isAppSelectionPresented)
        XCTAssertTrue(FirstRunSetupProgress.isPending(defaults: defaults))
        XCTAssertNil(coordinator.suppressedSuggestedSkillMapGoalID)
    }

    @MainActor
    func testWorkflowFailureUsesRealNoticeAndSkipExplicitlyStopsProtection() async {
        let goalID = UUID()
        let coordinator = FirstRunSetupCoordinator(defaults: defaults)
        var stopCount = 0
        coordinator.begin()
        coordinator.presentAppSelection()

        let result = await coordinator.startProtection(
            isPreparingQuestions: { false },
            startProtection: { false },
            checkpointNotice: { "A reviewed checkpoint is not ready yet." },
            screenTimeErrorMessage: { "Screen Time needs attention." },
            selectionSummary: { "2 apps selected" },
            currentGoalID: { goalID }
        )

        XCTAssertEqual(
            result,
            .failed(message: "A reviewed checkpoint is not ready yet.")
        )
        XCTAssertTrue(coordinator.isPending)
        XCTAssertTrue(coordinator.isAppSelectionPresented)
        XCTAssertTrue(FirstRunSetupProgress.isPending(defaults: defaults))

        coordinator.continueWithoutProtection(
            currentGoalID: goalID,
            stopProtection: { stopCount += 1 }
        )

        XCTAssertEqual(stopCount, 1)
        XCTAssertFalse(coordinator.isPending)
        XCTAssertFalse(coordinator.isAppSelectionPresented)
        XCTAssertFalse(FirstRunSetupProgress.isPending(defaults: defaults))
        XCTAssertEqual(coordinator.suppressedSuggestedSkillMapGoalID, goalID)
    }

    @MainActor
    func testSuccessfulStartClearsPendingButKeepsSuccessVisibleUntilFinish() async {
        let goalID = UUID()
        let coordinator = FirstRunSetupCoordinator(defaults: defaults)
        coordinator.begin()
        coordinator.presentAppSelection()
        let flow = FirstRunProtectionFlow(
            startProtection: {
                await coordinator.startProtection(
                    isPreparingQuestions: { false },
                    startProtection: { true },
                    checkpointNotice: { nil },
                    screenTimeErrorMessage: { nil },
                    selectionSummary: { "2 apps and 1 website selected" },
                    currentGoalID: { goalID }
                )
            },
            finishProtectedSetup: {
                coordinator.finishProtectedSetup()
            },
            continueWithoutProtection: {
                XCTFail("A protected flow cannot skip setup")
            }
        )

        await flow.start(selectionSummary: "2 apps selected")

        XCTAssertEqual(
            flow.phase,
            .protected(selectionSummary: "2 apps and 1 website selected")
        )
        XCTAssertFalse(coordinator.isPending)
        XCTAssertFalse(FirstRunSetupProgress.isPending(defaults: defaults))
        XCTAssertTrue(coordinator.isAppSelectionPresented)
        XCTAssertEqual(coordinator.suppressedSuggestedSkillMapGoalID, goalID)

        XCTAssertTrue(flow.finishProtectedSetup())
        XCTAssertFalse(coordinator.isAppSelectionPresented)
        XCTAssertEqual(
            flow.phase,
            .protected(selectionSummary: "2 apps and 1 website selected")
        )
    }

    @MainActor
    func testProtectionLossAfterSuccessRestoresDurablePendingSetup() async {
        let goalID = UUID()
        let coordinator = FirstRunSetupCoordinator(defaults: defaults)
        coordinator.begin()
        coordinator.presentAppSelection()
        let flow = FirstRunProtectionFlow(
            startProtection: {
                await coordinator.startProtection(
                    isPreparingQuestions: { false },
                    startProtection: { true },
                    checkpointNotice: { nil },
                    screenTimeErrorMessage: { nil },
                    selectionSummary: { "2 apps selected" },
                    currentGoalID: { goalID }
                )
            },
            finishProtectedSetup: {},
            continueWithoutProtection: {},
            protectionUnavailable: {
                coordinator.protectionDidBecomeUnavailable()
            }
        )
        await flow.start(selectionSummary: "2 apps selected")
        XCTAssertFalse(coordinator.isPending)
        XCTAssertFalse(FirstRunSetupProgress.isPending(defaults: defaults))

        XCTAssertTrue(
            flow.protectionDidBecomeUnavailable(
                message: "Protection turned off before setup finished. Try turning it on again."
            )
        )

        XCTAssertEqual(
            flow.phase,
            .failed(
                selectionSummary: "2 apps selected",
                message: "Protection turned off before setup finished. Try turning it on again."
            )
        )
        XCTAssertTrue(coordinator.isPending)
        XCTAssertTrue(coordinator.isAppSelectionPresented)
        XCTAssertTrue(FirstRunSetupProgress.isPending(defaults: defaults))
        XCTAssertNil(coordinator.suppressedSuggestedSkillMapGoalID)
    }
}

@MainActor
private final class FirstRunSetupTestClock {
    private(set) var now = Date(timeIntervalSinceReferenceDate: 10_000)
    private(set) var advanceCount = 0

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
        advanceCount += 1
    }
}
