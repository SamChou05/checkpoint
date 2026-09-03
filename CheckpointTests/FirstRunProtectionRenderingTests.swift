import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

#if canImport(FamilyControls)
import FamilyControls
#endif

final class FirstRunProtectionRenderingTests: XCTestCase {
    @MainActor
    func testFirstRunProtectionFlowKeepsFailureVisibleUntilExplicitRecovery() async {
        var startResults: [FirstRunProtectionStartResult] = [
            .failed(message: "Questions are still being prepared."),
            .failed(message: "Protection could not turn on.")
        ]
        var finishCount = 0
        var continueWithoutProtectionCount = 0
        let flow = FirstRunProtectionFlow(
            startProtection: {
                startResults.removeFirst()
            },
            finishProtectedSetup: {
                finishCount += 1
            },
            continueWithoutProtection: {
                continueWithoutProtectionCount += 1
            }
        )

        await flow.start(selectionSummary: "2 apps selected")

        XCTAssertEqual(
            flow.phase,
            .failed(
                selectionSummary: "2 apps selected",
                message: "Questions are still being prepared."
            )
        )
        XCTAssertEqual(finishCount, 0)
        XCTAssertEqual(continueWithoutProtectionCount, 0)
        XCTAssertFalse(flow.finishProtectedSetup())
        XCTAssertTrue(flow.editSelection())
        XCTAssertEqual(flow.phase, .selecting)
        XCTAssertFalse(flow.continueWithoutProtection())

        await flow.start(selectionSummary: "3 apps selected")

        XCTAssertEqual(
            flow.phase,
            .failed(
                selectionSummary: "3 apps selected",
                message: "Protection could not turn on."
            )
        )
        XCTAssertTrue(flow.continueWithoutProtection())
        XCTAssertEqual(continueWithoutProtectionCount, 1)
        XCTAssertFalse(flow.continueWithoutProtection())
        XCTAssertFalse(flow.editSelection())
    }

    @MainActor
    func testFirstRunProtectionFlowKeepsSuccessVisibleUntilExplicitFinish() async {
        var finishCount = 0
        var continueWithoutProtectionCount = 0
        let flow = FirstRunProtectionFlow(
            startProtection: {
                .protected(selectionSummary: "2 apps and 1 website selected")
            },
            finishProtectedSetup: {
                finishCount += 1
            },
            continueWithoutProtection: {
                continueWithoutProtectionCount += 1
            }
        )

        await flow.start(selectionSummary: "2 apps selected")

        XCTAssertEqual(
            flow.phase,
            .protected(selectionSummary: "2 apps and 1 website selected")
        )
        XCTAssertEqual(finishCount, 0)
        XCTAssertEqual(continueWithoutProtectionCount, 0)
        XCTAssertFalse(flow.continueWithoutProtection())
        XCTAssertFalse(flow.editSelection())
        XCTAssertTrue(flow.finishProtectedSetup())
        XCTAssertEqual(finishCount, 1)
        XCTAssertFalse(flow.finishProtectedSetup())
    }

    @MainActor
    func testFirstRunProtectionFlowRecoversWhenLiveProtectionDisappears() async {
        var unavailableCount = 0
        let flow = FirstRunProtectionFlow(
            startProtection: {
                .protected(selectionSummary: "2 apps selected")
            },
            finishProtectedSetup: {},
            continueWithoutProtection: {},
            protectionUnavailable: {
                unavailableCount += 1
            }
        )

        await flow.start(selectionSummary: "2 apps selected")

        XCTAssertTrue(
            flow.protectionDidBecomeUnavailable(
                message: "Protection turned off before setup finished."
            )
        )
        XCTAssertEqual(
            flow.phase,
            .failed(
                selectionSummary: "2 apps selected",
                message: "Protection turned off before setup finished."
            )
        )
        XCTAssertEqual(unavailableCount, 1)
        XCTAssertFalse(
            flow.protectionDidBecomeUnavailable(message: "Duplicate state change")
        )
        XCTAssertEqual(unavailableCount, 1)
    }

    @MainActor
    func testFirstRunProtectionFlowIgnoresDuplicateStartWhilePreparing() async {
        var startCount = 0
        let flow = FirstRunProtectionFlow(
            startProtection: {
                startCount += 1
                try? await Task.sleep(for: .milliseconds(50))
                return .protected(selectionSummary: "2 apps selected")
            },
            finishProtectedSetup: {},
            continueWithoutProtection: {}
        )

        let firstStart = Task { @MainActor in
            await flow.start(selectionSummary: "2 apps selected")
        }
        for _ in 0..<20 where !flow.phase.isPreparing {
            await Task.yield()
        }

        XCTAssertEqual(
            flow.phase,
            .preparing(selectionSummary: "2 apps selected")
        )
        await flow.start(selectionSummary: "Different selection")
        XCTAssertEqual(startCount, 1)

        await firstStart.value
        XCTAssertEqual(
            flow.phase,
            .protected(selectionSummary: "2 apps selected")
        )
    }

    @MainActor
    func testDurableCompletionCanPrecedeExplicitSuccessFinish() async throws {
        let suiteName = "FirstRunProtectionRenderingTests.Durable.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        FirstRunSetupProgress.begin(defaults: defaults)
        var finishCount = 0
        let flow = FirstRunProtectionFlow(
            startProtection: {
                let didComplete = await FirstRunSetupProgress.completeAfterStartingProtection(
                    defaults: defaults,
                    startProtection: { true }
                )
                return didComplete
                    ? .protected(selectionSummary: "2 apps selected")
                    : .failed(message: "Protection could not turn on.")
            },
            finishProtectedSetup: {
                finishCount += 1
            },
            continueWithoutProtection: {}
        )

        await flow.start(selectionSummary: "2 apps selected")

        XCTAssertFalse(FirstRunSetupProgress.isPending(defaults: defaults))
        XCTAssertEqual(flow.phase, .protected(selectionSummary: "2 apps selected"))
        XCTAssertEqual(finishCount, 0)
        XCTAssertTrue(flow.finishProtectedSetup())
        XCTAssertEqual(finishCount, 1)
    }

    @MainActor
    func testFirstRunProtectionPresentationUsesTruthfulCopyForEveryPhase() throws {
        XCTAssertNil(FirstRunProtectionStatusPresentation(phase: .selecting))

        let preparing = try XCTUnwrap(
            FirstRunProtectionStatusPresentation(
                phase: .preparing(selectionSummary: "2 apps selected")
            )
        )
        XCTAssertEqual(preparing.stage, "Turning on protection")
        XCTAssertEqual(preparing.title, "Preparing your first checkpoint")
        XCTAssertEqual(
            preparing.detail,
            "Checkpoint is making sure your first attempt is ready before protection turns on."
        )
        XCTAssertEqual(preparing.systemImage, "hourglass")
        XCTAssertEqual(preparing.tone, .working)

        let failure = try XCTUnwrap(
            FirstRunProtectionStatusPresentation(
                phase: .failed(
                    selectionSummary: "2 apps selected",
                    message: "The first checkpoint is still being prepared."
                )
            )
        )
        XCTAssertEqual(failure.stage, "Needs attention")
        XCTAssertEqual(failure.title, "Protection didn't turn on")
        XCTAssertEqual(failure.detail, "The first checkpoint is still being prepared.")
        XCTAssertEqual(failure.supportingTitle, "Your app choices are saved")
        XCTAssertEqual(failure.tone, .failure)

        let failureWithoutSelection = try XCTUnwrap(
            FirstRunProtectionStatusPresentation(
                phase: .failed(
                    selectionSummary: "2 apps selected",
                    message: "Screen Time access changed."
                ),
                hasSelection: false
            )
        )
        XCTAssertEqual(failureWithoutSelection.supportingTitle, "Choose apps to continue")
        XCTAssertEqual(failureWithoutSelection.selectionSummary, "No protected apps selected")

        let protected = try XCTUnwrap(
            FirstRunProtectionStatusPresentation(
                phase: .protected(selectionSummary: "2 apps and 1 website selected")
            )
        )
        XCTAssertEqual(protected.stage, "Protection ready")
        XCTAssertEqual(protected.eyebrow, "SETUP COMPLETE")
        XCTAssertEqual(protected.title, "Protection is on")
        XCTAssertEqual(
            protected.detail,
            "Opening a protected app now starts a checkpoint before a timed break."
        )
        XCTAssertEqual(protected.supportingTitle, "Your first checkpoint is ready")
        XCTAssertEqual(protected.tone, .success)

        let emptySelection = FirstRunProtectionActionPresentation(
            phase: .selecting,
            hasSelection: false,
            hasCategoryOnlySelection: false
        )
        XCTAssertEqual(emptySelection.detail, "Select at least one app or website to continue.")
        XCTAssertFalse(emptySelection.isPrimaryEnabled)

        let categoryOnly = FirstRunProtectionActionPresentation(
            phase: .selecting,
            hasSelection: false,
            hasCategoryOnlySelection: true
        )
        XCTAssertEqual(
            categoryOnly.detail,
            "Keep at least one app selected inside the category to continue."
        )

        let failedAction = FirstRunProtectionActionPresentation(
            phase: .failed(selectionSummary: "2 apps selected", message: "Try again."),
            hasSelection: true,
            hasCategoryOnlySelection: false
        )
        XCTAssertEqual(failedAction.primaryTitle, "Try again")
        XCTAssertEqual(failedAction.secondaryTitle, "Continue without protection")
        XCTAssertTrue(failedAction.isPrimaryEnabled)
        XCTAssertNil(failedAction.detail)

        let failedWithoutSelection = FirstRunProtectionActionPresentation(
            phase: .failed(selectionSummary: "2 apps selected", message: "Try again."),
            hasSelection: false,
            hasCategoryOnlySelection: false
        )
        XCTAssertEqual(failedWithoutSelection.primaryTitle, "Choose apps")
        XCTAssertTrue(failedWithoutSelection.isPrimaryEnabled)
        XCTAssertEqual(failedWithoutSelection.primaryAction, .editSelection)

        let successAction = FirstRunProtectionActionPresentation(
            phase: .protected(selectionSummary: "2 apps selected"),
            hasSelection: true,
            hasCategoryOnlySelection: false
        )
        XCTAssertEqual(successAction.primaryTitle, "Go to Home")
        XCTAssertNil(successAction.secondaryTitle)
        XCTAssertNil(successAction.detail)
    }

    @MainActor
    func testFirstRunProtectionMotionAndFocusPoliciesRespectReduceMotion() {
        let standard = FirstRunProtectionMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .choreographed)
        XCTAssertNotNil(standard.animation)

        let reduced = FirstRunProtectionMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)

        XCTAssertNil(FirstRunProtectionFocus.destination(for: .selecting))
        XCTAssertEqual(
            FirstRunProtectionFocus.destination(
                for: .preparing(selectionSummary: "2 apps selected")
            ),
            .preparing
        )
        XCTAssertEqual(
            FirstRunProtectionFocus.destination(
                for: .failed(selectionSummary: "2 apps selected", message: "Try again.")
            ),
            .failure
        )
        XCTAssertEqual(
            FirstRunProtectionFocus.destination(
                for: .protected(selectionSummary: "2 apps selected")
            ),
            .success
        )

        XCTAssertTrue(
            FirstRunProtectionLiveState(
                isAuthorized: true,
                hasSelection: true,
                hasActiveProtectionIntent: true
            ).isValid
        )
        XCTAssertFalse(
            FirstRunProtectionLiveState(
                isAuthorized: false,
                hasSelection: true,
                hasActiveProtectionIntent: true
            ).isValid
        )
        XCTAssertFalse(
            FirstRunProtectionLiveState(
                isAuthorized: true,
                hasSelection: false,
                hasActiveProtectionIntent: true
            ).isValid
        )
        XCTAssertFalse(
            FirstRunProtectionLiveState(
                isAuthorized: true,
                hasSelection: true,
                hasActiveProtectionIntent: false
            ).isValid
        )
    }

    @MainActor
    func testFirstRunProtectionStatesRenderAcrossKeyLayouts() {
        let failureMessage = "Checkpoint couldn't prepare enough questions for a reliable first attempt. Try again in a moment."
        let fixtures = [
            FirstRunProtectionRenderFixture(
                name: "first-run-selecting-empty-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                phase: .selecting,
                hasSelection: false,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-selecting-ready-standard-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                phase: .selecting,
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-selecting-ready-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                phase: .selecting,
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-selecting-category-only-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                phase: .selecting,
                hasSelection: false,
                categoryOnlySelection: true
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-selecting-ready-accessibility2-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                reduceMotion: false,
                phase: .selecting,
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-preparing-standard-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                reduceMotion: false,
                phase: .preparing(selectionSummary: "3 apps and 2 websites selected"),
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-preparing-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                phase: .preparing(selectionSummary: "3 apps and 2 websites selected"),
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-preparing-accessibility2-device-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                reduceMotion: false,
                phase: .preparing(selectionSummary: "3 apps and 2 websites selected"),
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-failure-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                phase: .failed(
                    selectionSummary: "3 apps and 2 websites selected",
                    message: failureMessage
                ),
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-failure-accessibility2-device-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                reduceMotion: false,
                phase: .failed(
                    selectionSummary: "3 apps and 2 websites selected",
                    message: failureMessage
                ),
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-failure-accessibility2-dark",
                width: 393,
                height: 1_400,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                reduceMotion: false,
                phase: .failed(
                    selectionSummary: "3 apps and 2 websites selected",
                    message: failureMessage
                ),
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-protected-standard-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                phase: .protected(selectionSummary: "3 apps and 2 websites selected"),
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-protected-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                phase: .protected(selectionSummary: "3 apps and 2 websites selected"),
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-protected-accessibility2-device-dark-reduced",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                reduceMotion: true,
                phase: .protected(selectionSummary: "3 apps and 2 websites selected"),
                hasSelection: true,
                categoryOnlySelection: false
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-protected-accessibility2-dark-reduced",
                width: 393,
                height: 1_400,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                reduceMotion: true,
                phase: .protected(selectionSummary: "3 apps and 2 websites selected"),
                hasSelection: true,
                categoryOnlySelection: false
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: FirstRunProtectionRenderScene(fixture: fixture)
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: fixture.reduceMotion ? 0.05 : 0.55,
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
    func testProductionFirstRunScreenRendersLiveControllerRecoveryStates() throws {
        let suiteName = "FirstRunProtectionRenderingTests.Production.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screenTime = ScreenTimeController(
            defaults: defaults,
            authorizer: FirstRunRenderScreenTimeAuthorizer()
        )

        #if canImport(FamilyControls)
        let previousSelection = screenTime.selection
        screenTime.selection = FamilyActivitySelection(includeEntireCategory: true)
        defer { screenTime.selection = previousSelection }
        #endif
        XCTAssertFalse(screenTime.hasSelection)

        let fixtures: [(String, FirstRunProtectionPhase, ColorScheme, DynamicTypeSize)] = [
            (
                "first-run-production-failure-missing-selection-light",
                .failed(
                    selectionSummary: "3 apps selected",
                    message: "Screen Time access changed before protection could turn on."
                ),
                .light,
                .large
            ),
            (
                "first-run-production-stale-success-recovers-dark",
                .protected(selectionSummary: "3 apps and 2 websites selected"),
                .dark,
                .large
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: RestrictedAppsView(
                    screenTime: screenTime,
                    onStartProtection: {
                        .failed(message: "This render fixture does not start protection.")
                    },
                    onFinishProtectedSetup: {},
                    onContinueWithoutProtection: {},
                    initialPhase: fixture.1,
                    reduceMotionOverride: true
                )
                .environment(\.colorScheme, fixture.2)
                .environment(\.dynamicTypeSize, fixture.3),
                width: 393,
                height: 852,
                colorScheme: fixture.2,
                settlingTime: 0.2,
                renderScale: 1
            )

            XCTAssertEqual(image.size.width, 393, accuracy: 0.5, fixture.0)
            XCTAssertEqual(image.size.height, 852, accuracy: 0.5, fixture.0)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.0
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

private struct FirstRunProtectionRenderFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let reduceMotion: Bool
    let phase: FirstRunProtectionPhase
    let hasSelection: Bool
    let categoryOnlySelection: Bool
}

private struct FirstRunProtectionRenderScene: View {
    let fixture: FirstRunProtectionRenderFixture

    var body: some View {
        NavigationStack {
            Group {
                if fixture.phase == .selecting {
                    selectionSurface
                } else {
                    FirstRunProtectionStatusView(
                        phase: fixture.phase,
                        reduceMotion: fixture.reduceMotion,
                        hasSelection: fixture.hasSelection,
                        editSelection: {}
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .checkpointScreenBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FirstRunProtectionActionBar(
                    presentation: FirstRunProtectionActionPresentation(
                        phase: fixture.phase,
                        hasSelection: fixture.hasSelection,
                        hasCategoryOnlySelection: fixture.categoryOnlySelection
                    ),
                    primaryAction: {},
                    secondaryAction: {}
                )
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var selectionSurface: some View {
        VStack(spacing: 0) {
            FirstRunAppSelectionHeader(
                selectionSummary: fixture.hasSelection
                    ? "3 apps and 2 websites selected"
                    : "Nothing selected yet",
                categorySelectionDetail: fixture.categoryOnlySelection
                    ? "Keep at least one app selected inside the category so Checkpoint has something to protect."
                    : nil,
                errorMessage: nil
            )
            .padding(16)
            .background(CheckpointTheme.panel)

            pickerSkeleton
        }
    }

    private var pickerSkeleton: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CheckpointTheme.panelRaised)
                            .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 7) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(CheckpointTheme.hairline)
                                .frame(width: index.isMultiple(of: 2) ? 132 : 104, height: 8)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(CheckpointTheme.panelRaised)
                                .frame(width: 76, height: 7)
                        }

                        Spacer()

                        Circle()
                            .stroke(CheckpointTheme.controlStroke, lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                    Divider()
                        .overlay(CheckpointTheme.hairline)
                        .padding(.leading, 68)
                }
            }
        }
        .scrollDisabled(true)
        .background(CheckpointTheme.panel.opacity(0.58))
        .accessibilityHidden(true)
    }
}

@MainActor
private final class FirstRunRenderScreenTimeAuthorizer: ScreenTimeAuthorizing {
    var authorizationStatus: ScreenTimeAuthorizationStatus { .approved }

    func requestAuthorization() async throws {}
}
