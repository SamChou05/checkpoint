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
    func testFirstRunProtectionFlowReturnsToSelectionWhenStartTaskIsCancelled() async {
        let flow = FirstRunProtectionFlow(
            startProtection: {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    // The flow owns the visible cancellation state after its action unwinds.
                }
                return .protected(selectionSummary: "2 apps selected")
            },
            finishProtectedSetup: {},
            continueWithoutProtection: {}
        )

        let startTask = Task { @MainActor in
            await flow.start(selectionSummary: "2 apps selected")
        }
        for _ in 0..<20 where !flow.phase.isPreparing {
            await Task.yield()
        }
        XCTAssertEqual(
            flow.phase,
            .preparing(selectionSummary: "2 apps selected")
        )

        startTask.cancel()
        await startTask.value

        XCTAssertEqual(flow.phase, .selecting)
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
        let goalContext = FirstRunGoalContext(
            goalID: UUID(),
            title: "Lead a systems design interview"
        )
        XCTAssertNil(
            FirstRunProtectionStatusPresentation(
                phase: .selecting,
                goalContext: goalContext
            )
        )

        let preparing = try XCTUnwrap(
            FirstRunProtectionStatusPresentation(
                phase: .preparing(selectionSummary: "2 apps selected"),
                goalContext: goalContext
            )
        )
        XCTAssertEqual(preparing.stage, "Turning on protection")
        XCTAssertEqual(preparing.title, "Preparing your first checkpoint")
        XCTAssertEqual(
            preparing.detail,
            "Checkpoint is preparing a reliable first attempt for this goal before protection turns on."
        )
        XCTAssertEqual(preparing.goalContext, goalContext)
        XCTAssertEqual(
            preparing.operationalNote,
            "Keep Checkpoint open while your first checkpoint is prepared."
        )
        XCTAssertTrue(preparing.accessibilityLabel.contains(goalContext.title))
        XCTAssertEqual(preparing.systemImage, "hourglass")
        XCTAssertEqual(preparing.tone, .working)

        let failure = try XCTUnwrap(
            FirstRunProtectionStatusPresentation(
                phase: .failed(
                    selectionSummary: "2 apps selected",
                    message: "The first checkpoint is still being prepared."
                ),
                goalContext: goalContext
            )
        )
        XCTAssertEqual(failure.stage, "Needs attention")
        XCTAssertEqual(failure.title, "Protection isn't on yet")
        XCTAssertEqual(failure.detail, "The first checkpoint is still being prepared.")
        XCTAssertEqual(failure.supportingTitle, "Your goal and app choices are saved")
        XCTAssertTrue(failure.accessibilityLabel.contains(goalContext.title))
        XCTAssertEqual(failure.tone, .failure)

        let failureWithoutSelection = try XCTUnwrap(
            FirstRunProtectionStatusPresentation(
                phase: .failed(
                    selectionSummary: "2 apps selected",
                    message: "Screen Time access changed."
                ),
                goalContext: goalContext,
                hasSelection: false
            )
        )
        XCTAssertEqual(failureWithoutSelection.supportingTitle, "Choose apps for this goal")
        XCTAssertEqual(failureWithoutSelection.selectionSummary, "No protected apps selected")
        XCTAssertNil(failureWithoutSelection.operationalNote)

        let protected = try XCTUnwrap(
            FirstRunProtectionStatusPresentation(
                phase: .protected(selectionSummary: "2 apps and 1 website selected"),
                goalContext: goalContext
            )
        )
        XCTAssertEqual(protected.stage, "Protection ready")
        XCTAssertEqual(protected.eyebrow, "SETUP COMPLETE")
        XCTAssertEqual(protected.title, "Protection is on")
        XCTAssertEqual(
            protected.detail,
            "Opening a protected app now starts a checkpoint for this goal before a timed break."
        )
        XCTAssertEqual(protected.supportingTitle, "Your first checkpoint is ready")
        XCTAssertNil(protected.operationalNote)
        XCTAssertTrue(protected.accessibilityLabel.contains(goalContext.title))
        XCTAssertEqual(protected.tone, .success)

        let emptySelection = FirstRunProtectionActionPresentation(
            phase: .selecting,
            hasSelection: false,
            hasCategoryOnlySelection: false
        )
        XCTAssertEqual(emptySelection.detail, "Select at least one app or website to continue.")
        XCTAssertEqual(emptySelection.primaryTitle, "Choose apps first")
        XCTAssertTrue(emptySelection.hidesDetailAtAccessibilitySizes)
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
        XCTAssertFalse(failedAction.hidesDetailAtAccessibilitySizes)

        let preparingAction = FirstRunProtectionActionPresentation(
            phase: .preparing(selectionSummary: "2 apps selected"),
            hasSelection: true,
            hasCategoryOnlySelection: false
        )
        XCTAssertEqual(preparingAction.detail, preparing.operationalNote)
        XCTAssertTrue(preparingAction.hidesDetailAtAccessibilitySizes)

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
    func testProtectedAppsManagementPresentationExplainsEverySaveAndProtectionState() {
        XCTAssertNil(
            ProtectedAppsCategorySelectionPresentation(
                hasCategorySelection: false,
                hasProtectedItems: false,
                usesLegacyCategoryEnforcement: false
            ).detail
        )
        XCTAssertEqual(
            ProtectedAppsCategorySelectionPresentation(
                hasCategorySelection: true,
                hasProtectedItems: false,
                usesLegacyCategoryEnforcement: false
            ).detail,
            "Keep at least one app selected from the category, or choose a website, so Checkpoint has something to protect."
        )
        XCTAssertEqual(
            ProtectedAppsCategorySelectionPresentation(
                hasCategorySelection: true,
                hasProtectedItems: true,
                usesLegacyCategoryEnforcement: false
            ).detail,
            "Category shortcuts add their apps and websites to this list. Your individual changes take precedence."
        )
        XCTAssertEqual(
            ProtectedAppsCategorySelectionPresentation(
                hasCategorySelection: true,
                hasProtectedItems: true,
                usesLegacyCategoryEnforcement: true
            ).detail,
            "This older selection protects the whole category. Change a choice below to update it to the current app and website list."
        )

        XCTAssertEqual(
            ProtectedAppsManagementChrome(
                dynamicTypeSize: .large,
                availableHeight: 800
            ),
            .brandedHeader
        )
        XCTAssertEqual(
            ProtectedAppsManagementChrome(
                dynamicTypeSize: .large,
                availableHeight: 568
            ),
            .systemPickerCopy
        )
        XCTAssertEqual(
            ProtectedAppsManagementChrome(
                dynamicTypeSize: .xLarge,
                availableHeight: 800
            ),
            .systemPickerCopy
        )
        XCTAssertEqual(
            ProtectedAppsManagementChrome(
                dynamicTypeSize: .xxLarge,
                availableHeight: 800
            ),
            .systemPickerCopy
        )
        XCTAssertEqual(
            ProtectedAppsManagementChrome(
                dynamicTypeSize: .xxxLarge,
                availableHeight: 800
            ),
            .systemPickerCopy
        )
        XCTAssertEqual(
            ProtectedAppsManagementChrome(
                dynamicTypeSize: .accessibility1,
                availableHeight: 800
            ),
            .systemPickerCopy
        )

        let accessNeeded = ProtectedAppsManagementPresentation(
            selectionSummary: "No protected apps selected",
            hasSelection: false,
            hasRequiredScreenTimeAuthorization: false,
            isShieldingEnabled: false,
            isBreakInProgress: false,
            errorMessage: nil
        )
        XCTAssertEqual(accessNeeded.status, "ACCESS NEEDED")
        XCTAssertEqual(accessNeeded.title, "Screen Time access needed")
        XCTAssertEqual(accessNeeded.systemImage, "exclamationmark.shield.fill")
        XCTAssertEqual(accessNeeded.tone, .attention)
        XCTAssertEqual(
            accessNeeded.pickerHeaderText(isCondensed: true),
            "Screen Time access needed\nNo protected apps selected\n\nAllow Screen Time access to choose and protect apps."
        )

        let attention = ProtectedAppsManagementPresentation(
            selectionSummary: "3 apps selected",
            hasSelection: true,
            hasRequiredScreenTimeAuthorization: true,
            isShieldingEnabled: true,
            isBreakInProgress: false,
            errorMessage: "Choose fewer apps so iPhone can apply the full list."
        )
        XCTAssertEqual(attention.status, "NEEDS ATTENTION")
        XCTAssertEqual(attention.title, "Selection needs attention")
        XCTAssertEqual(
            attention.detail,
            "Choose fewer apps so iPhone can apply the full list."
        )
        XCTAssertEqual(attention.tone, .attention)
        XCTAssertEqual(
            attention.pickerHeaderText(isCondensed: true),
            "Needs attention\n3 apps selected\n\nChoose fewer apps so iPhone can apply the full list."
        )

        let empty = ProtectedAppsManagementPresentation(
            selectionSummary: "No protected apps selected",
            hasSelection: false,
            hasRequiredScreenTimeAuthorization: true,
            isShieldingEnabled: false,
            isBreakInProgress: false,
            errorMessage: nil
        )
        XCTAssertEqual(empty.status, "NOT SET")
        XCTAssertEqual(empty.title, "Choose your pause points")
        XCTAssertTrue(empty.detail.contains("Protection is off"))
        XCTAssertEqual(empty.tone, .empty)
        XCTAssertEqual(
            empty.pickerHeaderText(isCondensed: true),
            "Choose apps\nNo protected apps selected\n\nProtection is off. Choices save automatically."
        )

        let live = ProtectedAppsManagementPresentation(
            selectionSummary: "3 apps, 2 sites selected",
            hasSelection: true,
            hasRequiredScreenTimeAuthorization: true,
            isShieldingEnabled: true,
            isBreakInProgress: true,
            errorMessage: nil
        )
        XCTAssertEqual(live.status, "ACTIVE")
        XCTAssertEqual(live.title, "Protection list is live")
        XCTAssertEqual(
            live.detail,
            "Changes apply immediately. Turn protection off in Settings before clearing the list."
        )
        XCTAssertEqual(live.tone, .live)
        XCTAssertEqual(
            live.pickerHeaderText,
            "Active · Protection list is live\n3 apps, 2 sites selected\n\nChanges apply immediately. Turn protection off in Settings before clearing the list."
        )
        XCTAssertEqual(live.pickerHeaderText(isCondensed: false), live.pickerHeaderText)
        XCTAssertEqual(
            live.pickerHeaderText(isCondensed: true),
            "Protection active\n3 apps, 2 sites selected\n\nChanges apply immediately. Use Settings to turn protection off."
        )
        XCTAssertEqual(
            live.accessibilityLabel,
            "Protection list is live. ACTIVE. 3 apps, 2 sites selected. Changes apply immediately. Turn protection off in Settings before clearing the list."
        )

        let breakInProgress = ProtectedAppsManagementPresentation(
            selectionSummary: "3 apps, 2 sites selected",
            hasSelection: true,
            hasRequiredScreenTimeAuthorization: true,
            isShieldingEnabled: false,
            isBreakInProgress: true,
            errorMessage: nil
        )
        XCTAssertEqual(breakInProgress.status, "BREAK ACTIVE")
        XCTAssertEqual(breakInProgress.title, "Ready for the next lock")
        XCTAssertEqual(
            breakInProgress.detail,
            "Changes save now and apply when this break ends. Turn protection off in Settings before clearing the list."
        )
        XCTAssertEqual(breakInProgress.tone, .breakInProgress)
        XCTAssertEqual(
            breakInProgress.pickerHeaderText,
            "Break Active · Ready for the next lock\n3 apps, 2 sites selected\n\nChanges save now and apply when this break ends. Turn protection off in Settings before clearing the list."
        )
        XCTAssertEqual(
            breakInProgress.pickerHeaderText(isCondensed: true),
            "Break active\n3 apps, 2 sites selected\n\nChanges apply when the break ends. Use Settings to turn protection off."
        )

        let saved = ProtectedAppsManagementPresentation(
            selectionSummary: "3 apps, 2 sites selected",
            hasSelection: true,
            hasRequiredScreenTimeAuthorization: true,
            isShieldingEnabled: false,
            isBreakInProgress: false,
            errorMessage: nil
        )
        XCTAssertEqual(saved.status, "SAVED")
        XCTAssertEqual(saved.title, "Your list is ready")
        XCTAssertTrue(saved.detail.contains("save automatically"))
        XCTAssertEqual(saved.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(saved.tone, .ready)
        XCTAssertEqual(
            saved.pickerHeaderText,
            "Saved · Your list is ready\n3 apps, 2 sites selected\n\nYour choices save automatically. Start protection from Home or Settings when you're ready."
        )
        XCTAssertEqual(
            saved.pickerHeaderText(isCondensed: true),
            "List saved\n3 apps, 2 sites selected\n\nStart protection from Home or Settings."
        )
        XCTAssertEqual(
            saved.pickerFooterText(
                categorySelectionDetail: "Category shortcuts add apps and websites."
            ),
            "Category shortcuts add apps and websites."
        )
        XCTAssertNil(saved.pickerFooterText(categorySelectionDetail: nil))
        XCTAssertEqual(
            saved.accessibilityLabel,
            "Your list is ready. SAVED. 3 apps, 2 sites selected. Your choices save automatically. Start protection from Home or Settings when you're ready."
        )
    }

    @MainActor
    func testFirstRunProtectionMotionAndFocusPoliciesRespectAssistiveSettings() {
        XCTAssertTrue(
            RestrictedAppsErrorFeedbackPolicy.reportsScreenTimeError(
                presentationMode: .management,
                firstRunPhase: .protected(selectionSummary: "3 apps selected")
            )
        )
        XCTAssertTrue(
            RestrictedAppsErrorFeedbackPolicy.reportsScreenTimeError(
                presentationMode: .firstRun,
                firstRunPhase: .selecting
            )
        )
        XCTAssertFalse(
            RestrictedAppsErrorFeedbackPolicy.reportsScreenTimeError(
                presentationMode: .firstRun,
                firstRunPhase: .preparing(selectionSummary: "3 apps selected")
            )
        )
        XCTAssertFalse(
            RestrictedAppsErrorFeedbackPolicy.reportsScreenTimeError(
                presentationMode: .firstRun,
                firstRunPhase: .failed(
                    selectionSummary: "3 apps selected",
                    message: "Protection could not start."
                )
            )
        )

        let standard = FirstRunProtectionMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .choreographed)
        XCTAssertNotNil(standard.animation)

        let reduced = FirstRunProtectionMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
        XCTAssertEqual(
            FirstRunProtectionMotionPolicy(
                reduceMotion: false,
                voiceOverEnabled: true
            ).style,
            .identity
        )
        XCTAssertEqual(
            FirstRunProtectionMotionPolicy(
                reduceMotion: false,
                switchControlEnabled: true
            ).style,
            .identity
        )

        let standardHandoff = FirstGoalSuccessHandoffMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standardHandoff.style, .reveal)
        XCTAssertNotNil(standardHandoff.animation)

        let reducedHandoff = FirstGoalSuccessHandoffMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reducedHandoff.style, .identity)
        XCTAssertNil(reducedHandoff.animation)
        XCTAssertNil(
            FirstGoalSuccessHandoffMotionPolicy(
                reduceMotion: false,
                voiceOverEnabled: true
            ).animation
        )
        XCTAssertNil(
            FirstGoalSuccessHandoffMotionPolicy(
                reduceMotion: false,
                switchControlEnabled: true
            ).animation
        )

        let goalID = UUID()
        let goalContext = FirstRunGoalContext(
            goalID: goalID,
            title: "Prepare for the MCAT"
        )
        let handoff = FirstGoalSuccessHandoffToken(
            goalID: goalID,
            goalTitle: "Prepare for the MCAT"
        )
        let ordinaryHeader = FirstRunAppSelectionHeaderPresentation(
            goalContext: goalContext,
            didJustSaveGoal: false
        )
        XCTAssertFalse(ordinaryHeader.isSuccessHandoff)
        XCTAssertEqual(ordinaryHeader.stage, "Choose apps")
        XCTAssertEqual(ordinaryHeader.title, "Choose apps to protect")
        XCTAssertTrue(ordinaryHeader.detail.contains("skip this for now"))
        XCTAssertEqual(ordinaryHeader.systemImage, "checkmark.shield.fill")
        XCTAssertEqual(
            ordinaryHeader.pickerHeaderText(
                selectionSummary: "Nothing selected yet",
                errorMessage: nil,
                isCondensed: true,
                condensedSelectionSummary: "0 selected"
            ),
            "Step 3 of 3\nCheckpoint for: Prepare for the MCAT\n0 selected"
        )
        XCTAssertEqual(
            ordinaryHeader.pickerHeaderText(
                selectionSummary: "Nothing selected yet",
                errorMessage: "Choose at least one app.",
                isCondensed: true,
                condensedSelectionSummary: "0 selected"
            ),
            "Step 3 of 3\nCheckpoint for: Prepare for the MCAT\n0 selected\nNeeds attention: Choose at least one app."
        )
        XCTAssertEqual(
            ordinaryHeader.pickerFooterText(categorySelectionDetail: nil),
            ordinaryHeader.detail
        )

        let successHeader = FirstRunAppSelectionHeaderPresentation(
            goalContext: goalContext,
            didJustSaveGoal: true
        )
        XCTAssertTrue(successHeader.isSuccessHandoff)
        XCTAssertEqual(successHeader.stage, "Goal saved")
        XCTAssertEqual(successHeader.title, ordinaryHeader.title)
        XCTAssertEqual(successHeader.systemImage, "checkmark.circle.fill")
        XCTAssertTrue(successHeader.detail.hasPrefix("Select the apps"))
        XCTAssertTrue(successHeader.detail.contains("skip this for now"))
        XCTAssertEqual(
            successHeader.pickerHeaderText(
                selectionSummary: "Nothing selected yet",
                errorMessage: nil,
                isCondensed: true,
                condensedSelectionSummary: "0 selected"
            ),
            "Goal saved · Final\nCheckpoint for: Prepare for the MCAT\n0 selected"
        )
        XCTAssertEqual(
            successHeader.pickerFooterText(
                categorySelectionDetail: "Category shortcuts expand into apps and websites."
            ),
            "\(successHeader.detail)\n\nCategory shortcuts expand into apps and websites."
        )
        XCTAssertEqual(
            FirstRunAppSelectionChrome(dynamicTypeSize: .accessibility2),
            .brandedHeader
        )
        XCTAssertEqual(
            FirstRunAppSelectionChrome(dynamicTypeSize: .accessibility3),
            .systemPickerCopy
        )
        let deliveryTaskID = FirstGoalSuccessHandoffDeliveryTaskID(
            deliveryID: handoff.deliveryID,
            goalID: handoff.goalID,
            context: FirstGoalSuccessHandoffDeliveryContext(
                goalContext: goalContext,
                phase: .selecting,
                isAuthorized: true,
                errorMessage: nil,
                isExposed: true
            )
        )
        XCTAssertNotEqual(
            deliveryTaskID,
            FirstGoalSuccessHandoffDeliveryTaskID(
                deliveryID: handoff.deliveryID,
                goalID: handoff.goalID,
                context: FirstGoalSuccessHandoffDeliveryContext(
                    goalContext: goalContext,
                    phase: .selecting,
                    isAuthorized: true,
                    errorMessage: "Screen Time access changed.",
                    isExposed: true
                )
            ),
            "Clearing an error must re-key the deferred handoff delivery."
        )
        XCTAssertNotEqual(
            deliveryTaskID,
            FirstGoalSuccessHandoffDeliveryTaskID(
                deliveryID: handoff.deliveryID,
                goalID: handoff.goalID,
                context: FirstGoalSuccessHandoffDeliveryContext(
                    goalContext: goalContext,
                    phase: .selecting,
                    isAuthorized: true,
                    errorMessage: nil,
                    isExposed: false
                )
            ),
            "Uncovering the destination must re-key deferred delivery."
        )
        XCTAssertNotEqual(
            deliveryTaskID,
            FirstGoalSuccessHandoffDeliveryTaskID(
                deliveryID: UUID(),
                goalID: handoff.goalID,
                context: deliveryTaskID.context
            ),
            "A corrected delivery for the same goal must receive a fresh task identity."
        )
        XCTAssertNotEqual(
            deliveryTaskID.context,
            FirstGoalSuccessHandoffDeliveryContext(
                goalContext: FirstRunGoalContext(
                    goalID: goalID,
                    title: "Updated MCAT plan"
                ),
                phase: .selecting,
                isAuthorized: true,
                errorMessage: nil,
                isExposed: true
            ),
            "A current title change must re-key deferred delivery."
        )
        XCTAssertEqual(
            handoff.accessibilityAnnouncement,
            "Goal saved: Prepare for the MCAT. Step 3 of 3. Now choose the apps and websites that should pause for a checkpoint."
        )

        XCTAssertNil(FirstRunProtectionFocus.destination(for: .selecting))
        XCTAssertFalse(
            FirstRunProtectionFocus.movesProgrammatically(
                voiceOverEnabled: false,
                switchControlEnabled: false
            )
        )
        XCTAssertTrue(
            FirstRunProtectionFocus.movesProgrammatically(
                voiceOverEnabled: true,
                switchControlEnabled: false
            )
        )
        XCTAssertFalse(
            FirstRunProtectionFocus.movesProgrammatically(
                voiceOverEnabled: true,
                switchControlEnabled: true
            )
        )
        XCTAssertFalse(
            FirstRunAppSelectionLayoutPolicy.showsCategorySelectionDetail(
                dynamicTypeSize: .large,
                availableHeight: 568
            )
        )
        XCTAssertTrue(
            FirstRunAppSelectionLayoutPolicy.showsCategorySelectionDetail(
                dynamicTypeSize: .accessibility2,
                availableHeight: 568
            )
        )
        XCTAssertTrue(
            FirstRunAppSelectionLayoutPolicy.usesMinimalAccessibilityHeader(
                dynamicTypeSize: .accessibility2,
                availableHeight: 568
            )
        )
        XCTAssertFalse(
            FirstRunAppSelectionLayoutPolicy.usesMinimalAccessibilityHeader(
                dynamicTypeSize: .large,
                availableHeight: 568
            )
        )
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
    func testProtectedAppsManagementPreservesPickerSpaceAcrossCompactAndExpandedTextLayouts() {
        let categoryDetail =
            "Category shortcuts add their apps and websites to this list. Your individual changes take precedence."
        let fixtures = [
            ProtectedAppsManagementRenderFixture(
                name: "protected-apps-empty-short-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                presentation: ProtectedAppsManagementPresentation(
                    selectionSummary: "No protected apps selected",
                    hasSelection: false,
                    hasRequiredScreenTimeAuthorization: true,
                    isShieldingEnabled: false,
                    isBreakInProgress: false,
                    errorMessage: nil
                ),
                categorySelectionDetail: nil,
                minimumPickerHeight: 400
            ),
            ProtectedAppsManagementRenderFixture(
                name: "protected-apps-active-short-category-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                presentation: ProtectedAppsManagementPresentation(
                    selectionSummary: "12 apps, 3 sites selected",
                    hasSelection: true,
                    hasRequiredScreenTimeAuthorization: true,
                    isShieldingEnabled: true,
                    isBreakInProgress: false,
                    errorMessage: nil
                ),
                categorySelectionDetail: categoryDetail,
                minimumPickerHeight: 400
            ),
            ProtectedAppsManagementRenderFixture(
                name: "protected-apps-active-standard-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                reduceMotion: false,
                presentation: ProtectedAppsManagementPresentation(
                    selectionSummary: "3 apps, 2 sites selected",
                    hasSelection: true,
                    hasRequiredScreenTimeAuthorization: true,
                    isShieldingEnabled: true,
                    isBreakInProgress: false,
                    errorMessage: nil
                ),
                categorySelectionDetail: categoryDetail,
                minimumPickerHeight: 260
            ),
            ProtectedAppsManagementRenderFixture(
                name: "protected-apps-break-xlarge-dark-reduced",
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .xLarge,
                reduceMotion: true,
                presentation: ProtectedAppsManagementPresentation(
                    selectionSummary: "3 apps, 2 sites selected",
                    hasSelection: true,
                    hasRequiredScreenTimeAuthorization: true,
                    isShieldingEnabled: false,
                    isBreakInProgress: true,
                    errorMessage: nil
                ),
                categorySelectionDetail: categoryDetail,
                minimumPickerHeight: 400
            ),
            ProtectedAppsManagementRenderFixture(
                name: "protected-apps-attention-accessibility5-light-reduced",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                presentation: ProtectedAppsManagementPresentation(
                    selectionSummary: "3 apps selected",
                    hasSelection: true,
                    hasRequiredScreenTimeAuthorization: true,
                    isShieldingEnabled: true,
                    isBreakInProgress: false,
                    errorMessage: "Protection requires at least one app or website. Turn it off in Settings before clearing the list."
                ),
                categorySelectionDetail: nil,
                minimumPickerHeight: 600
            )
        ]

        for fixture in fixtures {
            let capture = ProtectedAppsPickerViewportCapture()
            let image = HostedViewRenderer.image(
                for: ProtectedAppsManagementRenderScene(
                    fixture: fixture,
                    viewportCapture: capture
                )
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: 0.15,
                renderScale: 1
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)
            XCTAssertGreaterThanOrEqual(
                capture.size.height,
                fixture.minimumPickerHeight,
                "\(fixture.name) left only \(capture.size.height) points for the picker"
            )
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
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
                name: "first-run-preparing-accessibility5-device-dark-reduced",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
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
                name: "first-run-failure-accessibility5-device-dark-reduced",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
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
            ),
            FirstRunProtectionRenderFixture(
                name: "first-run-protected-accessibility5-device-dark-reduced",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
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
    func testFirstGoalSuccessHandoffPreservesPickerSpaceAcrossKeyLayouts() {
        let handoff = FirstGoalSuccessHandoffToken(
            goalID: UUID(),
            goalTitle: "Lead a systems design interview"
        )
        let layouts = [
            FirstGoalHandoffLayoutFixture(
                name: "standard-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false
            ),
            FirstGoalHandoffLayoutFixture(
                name: "compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false
            ),
            FirstGoalHandoffLayoutFixture(
                name: "accessibility2-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                reduceMotion: false
            ),
            FirstGoalHandoffLayoutFixture(
                name: "accessibility5-dark-reduced",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true
            ),
            FirstGoalHandoffLayoutFixture(
                name: "compact-accessibility2-long-goal-dark-reduced",
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                reduceMotion: true,
                goalTitle: "Build a durable morning routine that makes time for exercise, focused writing, family breakfast, and planning the day's most important work"
            )
        ]

        for layout in layouts {
            autoreleasepool {
                let goalContext = FirstRunGoalContext(
                    goalID: handoff.goalID,
                    title: layout.goalTitle ?? handoff.goalTitle
                )
                let ordinaryCapture = ProtectedAppsPickerViewportCapture()
                _ = HostedViewRenderer.image(
                    for: FirstRunProtectionRenderScene(
                        fixture: layout.renderFixture,
                        goalContext: goalContext,
                        viewportCapture: ordinaryCapture
                    )
                    .environment(\.colorScheme, layout.colorScheme)
                    .environment(\.dynamicTypeSize, layout.dynamicTypeSize),
                    width: layout.width,
                    height: layout.height,
                    colorScheme: layout.colorScheme,
                    settlingTime: 0.1,
                    renderScale: 1
                )

                let successCapture = ProtectedAppsPickerViewportCapture()
                let image = HostedViewRenderer.image(
                    for: FirstRunProtectionRenderScene(
                        fixture: layout.renderFixture,
                        goalContext: goalContext,
                        firstGoalHandoff: handoff,
                        firstGoalHandoffRevealSequence: layout.reduceMotion ? 0 : 1,
                        viewportCapture: successCapture
                    )
                    .environment(\.colorScheme, layout.colorScheme)
                    .environment(\.dynamicTypeSize, layout.dynamicTypeSize),
                    width: layout.width,
                    height: layout.height,
                    colorScheme: layout.colorScheme,
                    settlingTime: layout.reduceMotion ? 0.05 : 0.45,
                    renderScale: 1
                )

                XCTAssertGreaterThan(ordinaryCapture.size.height, 0, layout.name)
                XCTAssertGreaterThanOrEqual(
                    successCapture.initialChoiceViewportHeight,
                    140,
                    "\(layout.name) left too little initial space for app choices"
                )
                XCTAssertEqual(
                    successCapture.initialChoiceViewportHeight,
                    ordinaryCapture.initialChoiceViewportHeight,
                    accuracy: 0.5,
                    "\(layout.name) success copy changed the picker viewport"
                )
                if layout.dynamicTypeSize >= .accessibility3 {
                    XCTAssertGreaterThan(successCapture.systemHeaderSize.height, 0, layout.name)
                }

                let attachment = XCTAttachment(image: image)
                attachment.name = "first-goal-handoff-\(layout.name)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testMountedFirstGoalSuccessHandoffDeliversOneEffectAfterRecovery() throws {
        let token = FirstGoalSuccessHandoffToken(
            goalID: UUID(),
            goalTitle: "An older MCAT plan"
        )
        let currentGoalTitle = "Prepare for the MCAT"

        for reduceMotion in [false, true] {
            let suiteName = "FirstRunProtectionRenderingTests.Handoff.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let screenTime = ScreenTimeController(
                defaults: defaults,
                authorizer: FirstRunRenderScreenTimeAuthorizer()
            )
            screenTime.setupState = .failed
            screenTime.lastErrorMessage = "Screen Time access changed."
            let capture = FirstGoalHandoffConsumptionCapture()

            _ = HostedViewRenderer.image(
                for: FirstGoalHandoffMountedScene(
                    screenTime: screenTime,
                    token: token,
                    capture: capture,
                    reduceMotion: reduceMotion,
                    activeGoalTitle: currentGoalTitle,
                    initiallyExposed: false
                )
                .environment(\.colorScheme, ColorScheme.light)
                .environment(\.dynamicTypeSize, DynamicTypeSize.large),
                width: 393,
                height: 852,
                colorScheme: .light,
                settlingTime: 0.55,
                renderScale: 1
            )

            XCTAssertEqual(capture.consumptionAttempts, [token])
            XCTAssertEqual(capture.exposureAtConsumption, [true])
            XCTAssertEqual(capture.deliveryEffects.count, 1)
            XCTAssertEqual(capture.deliveryEffects.first?.token, token)
            XCTAssertEqual(capture.deliveryEffects.first?.goalContext.title, currentGoalTitle)
            XCTAssertEqual(capture.deliveryEffects.first?.revealSequenceIncrement, 1)
            XCTAssertEqual(capture.deliveryEffects.first?.successFeedbackSequenceIncrement, 1)
            XCTAssertEqual(
                capture.deliveryEffects.first?.accessibilityAnnouncement,
                "Goal saved: \(currentGoalTitle). Step 3 of 3. Now choose the apps and websites that should pause for a checkpoint."
            )
        }
    }

    @MainActor
    func testMountedRejectedFirstGoalHandoffEmitsNoEffectOrRetry() throws {
        let suiteName = "FirstRunProtectionRenderingTests.RejectedHandoff.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let screenTime = ScreenTimeController(
            defaults: defaults,
            authorizer: FirstRunRenderScreenTimeAuthorizer()
        )
        let token = FirstGoalSuccessHandoffToken(
            goalID: UUID(),
            goalTitle: "Prepare for the MCAT"
        )
        let capture = FirstGoalHandoffConsumptionCapture()

        let image = HostedViewRenderer.image(
            for: FirstGoalHandoffMountedScene(
                screenTime: screenTime,
                token: token,
                capture: capture,
                reduceMotion: false,
                acceptsToken: false
            )
            .environment(\.colorScheme, ColorScheme.light)
            .environment(\.dynamicTypeSize, DynamicTypeSize.large),
            width: 393,
            height: 852,
            colorScheme: .light,
            settlingTime: 0.55,
            renderScale: 1
        )

        XCTAssertEqual(capture.consumptionAttempts, [token])
        XCTAssertEqual(capture.exposureAtConsumption, [true])
        XCTAssertTrue(capture.deliveryEffects.isEmpty)
        let attachment = XCTAttachment(image: image)
        attachment.name = "first-goal-handoff-authoritatively-rejected"
        attachment.lifetime = .keepAlways
        add(attachment)
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
                    reduceMotionOverride: true,
                    goalContext: FirstRunGoalContext(
                        goalID: UUID(),
                        title: "Lead a systems design interview"
                    )
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

    @MainActor
    func testMissingGoalRecoveryPinsItsOnlyActionAcrossKeyLayouts() throws {
        let fixtures: [(String, CGFloat, CGFloat, ColorScheme, DynamicTypeSize)] = [
            (
                "first-run-missing-goal-standard-light",
                393,
                852,
                .light,
                .large
            ),
            (
                "first-run-missing-goal-compact-accessibility5-dark",
                320,
                568,
                .dark,
                .accessibility5
            )
        ]

        for fixture in fixtures {
            let capture = FirstRunMissingGoalRecoveryLayoutCapture()
            let image = HostedViewRenderer.image(
                for: FirstRunMissingGoalRecoveryView(
                    recover: {},
                    layoutReporter: { element, frame in
                        capture.frames[element] = frame
                    }
                )
                .environment(\.colorScheme, fixture.3)
                .environment(\.dynamicTypeSize, fixture.4),
                width: fixture.1,
                height: fixture.2,
                colorScheme: fixture.3,
                settlingTime: 0.2,
                renderScale: 1
            )

            let viewport = try XCTUnwrap(capture.frames[.viewport], fixture.0)
            let actionBar = try XCTUnwrap(capture.frames[.actionBar], fixture.0)
            let primaryAction = try XCTUnwrap(
                capture.frames[.primaryAction],
                fixture.0
            )
            let canvas = CGRect(
                x: 0,
                y: 0,
                width: fixture.1,
                height: fixture.2
            )

            for frame in [viewport, actionBar, primaryAction] {
                XCTAssertFalse(frame.isNull, fixture.0)
                XCTAssertFalse(frame.isInfinite, fixture.0)
                XCTAssertGreaterThan(frame.width, 0, fixture.0)
                XCTAssertGreaterThan(frame.height, 0, fixture.0)
            }
            XCTAssertTrue(
                canvas.insetBy(dx: -0.5, dy: -0.5).contains(actionBar),
                "\(fixture.0) action bar escaped the rendered screen"
            )
            XCTAssertTrue(
                actionBar.insetBy(dx: -0.5, dy: -0.5).contains(primaryAction),
                "\(fixture.0) recovery action escaped its safe-area bar"
            )
            XCTAssertGreaterThanOrEqual(
                primaryAction.height,
                43.5,
                "\(fixture.0) recovery action is smaller than an accessible tap target"
            )

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.0
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

private struct ProtectedAppsManagementRenderFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let reduceMotion: Bool
    let presentation: ProtectedAppsManagementPresentation
    let categorySelectionDetail: String?
    let minimumPickerHeight: CGFloat

    var chrome: ProtectedAppsManagementChrome {
        ProtectedAppsManagementChrome(
            dynamicTypeSize: dynamicTypeSize,
            availableHeight: height
        )
    }
}

@MainActor
private final class ProtectedAppsPickerViewportCapture {
    var size = CGSize.zero
    var systemHeaderSize = CGSize.zero

    var initialChoiceViewportHeight: CGFloat {
        guard systemHeaderSize.height > 0 else { return size.height }
        return max(0, size.height - systemHeaderSize.height - 26)
    }
}

@MainActor
private final class FirstRunMissingGoalRecoveryLayoutCapture {
    var frames: [FirstRunMissingGoalRecoveryLayoutElement: CGRect] = [:]
}

private struct ProtectedAppsManagementRenderScene: View {
    let fixture: ProtectedAppsManagementRenderFixture
    let viewportCapture: ProtectedAppsPickerViewportCapture

    var body: some View {
        NavigationStack {
            Group {
                switch fixture.chrome {
                case .brandedHeader:
                    ProtectedAppsManagementShell(
                        presentation: fixture.presentation,
                        categorySelectionDetail: fixture.categorySelectionDetail,
                        changeSequence: 0,
                        reduceMotionOverride: fixture.reduceMotion
                    ) {
                        ProtectedAppsPickerSkeleton(
                            viewportCapture: viewportCapture
                        )
                    }
                case .systemPickerCopy:
                    ProtectedAppsSystemPickerSkeleton(
                        headerText: fixture.presentation.pickerHeaderText(
                            isCondensed: fixture.dynamicTypeSize.isAccessibilitySize
                        ),
                        footerText: fixture.presentation.pickerFooterText(
                            categorySelectionDetail: fixture.categorySelectionDetail
                        ),
                        viewportCapture: viewportCapture
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .checkpointScreenBackground()
            .navigationTitle("Protected Apps")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {}
                        .fontWeight(.semibold)
                        .foregroundStyle(CheckpointTheme.teal)
                }
            }
        }
    }
}

private struct ProtectedAppsSystemPickerSkeleton: View {
    let headerText: String
    let footerText: String?
    let viewportCapture: ProtectedAppsPickerViewportCapture?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(headerText)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .reportProtectedAppsSystemHeader(to: viewportCapture)

                ProtectedAppsPickerRows()

                if let footerText {
                    Text(footerText)
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                }
            }
            .padding(.vertical, 12)
        }
        .background(CheckpointTheme.panel.opacity(0.58))
        .reportProtectedAppsViewport(to: viewportCapture)
    }
}

private struct ProtectedAppsPickerSkeleton: View {
    var viewportCapture: ProtectedAppsPickerViewportCapture?

    init(viewportCapture: ProtectedAppsPickerViewportCapture? = nil) {
        self.viewportCapture = viewportCapture
    }

    var body: some View {
        ScrollView {
            ProtectedAppsPickerRows()
        }
        .scrollDisabled(true)
        .background(CheckpointTheme.panel.opacity(0.58))
        .reportProtectedAppsViewport(to: viewportCapture)
        .accessibilityHidden(true)
    }
}

private struct ProtectedAppsPickerRows: View {
    var body: some View {
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
}

private struct ProtectedAppsViewportReporter: ViewModifier {
    let capture: ProtectedAppsPickerViewportCapture?

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        capture?.size = proxy.size
                    }
                    .onChange(of: proxy.size) { _, size in
                        capture?.size = size
                    }
            }
        }
    }
}

private struct ProtectedAppsSystemHeaderReporter: ViewModifier {
    let capture: ProtectedAppsPickerViewportCapture?

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        capture?.systemHeaderSize = proxy.size
                    }
                    .onChange(of: proxy.size) { _, size in
                        capture?.systemHeaderSize = size
                    }
            }
        }
    }
}

private extension View {
    func reportProtectedAppsViewport(
        to capture: ProtectedAppsPickerViewportCapture?
    ) -> some View {
        modifier(ProtectedAppsViewportReporter(capture: capture))
    }

    func reportProtectedAppsSystemHeader(
        to capture: ProtectedAppsPickerViewportCapture?
    ) -> some View {
        modifier(ProtectedAppsSystemHeaderReporter(capture: capture))
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

private struct FirstGoalHandoffLayoutFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let reduceMotion: Bool
    var goalTitle: String? = nil

    var renderFixture: FirstRunProtectionRenderFixture {
        FirstRunProtectionRenderFixture(
            name: name,
            width: width,
            height: height,
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize,
            reduceMotion: reduceMotion,
            phase: .selecting,
            hasSelection: false,
            categoryOnlySelection: false
        )
    }
}

@MainActor
private final class FirstGoalHandoffConsumptionCapture {
    var consumptionAttempts: [FirstGoalSuccessHandoffToken] = []
    var exposureAtConsumption: [Bool] = []
    var deliveryEffects: [FirstGoalSuccessHandoffDeliveryEffect] = []
}

private struct FirstGoalHandoffMountedScene: View {
    let screenTime: ScreenTimeController
    let capture: FirstGoalHandoffConsumptionCapture
    let goalContext: FirstRunGoalContext
    let reduceMotion: Bool
    let acceptsToken: Bool
    let initiallyExposed: Bool
    @State private var handoff: FirstGoalSuccessHandoffToken?
    @State private var allowsDelivery: Bool

    init(
        screenTime: ScreenTimeController,
        token: FirstGoalSuccessHandoffToken,
        capture: FirstGoalHandoffConsumptionCapture,
        reduceMotion: Bool,
        activeGoalTitle: String? = nil,
        acceptsToken: Bool = true,
        initiallyExposed: Bool = true
    ) {
        self.screenTime = screenTime
        self.capture = capture
        goalContext = FirstRunGoalContext(
            goalID: token.goalID,
            title: activeGoalTitle ?? token.goalTitle
        )
        self.reduceMotion = reduceMotion
        self.acceptsToken = acceptsToken
        self.initiallyExposed = initiallyExposed
        _handoff = State(initialValue: token)
        _allowsDelivery = State(initialValue: initiallyExposed)
    }

    var body: some View {
        RestrictedAppsView(
            screenTime: screenTime,
            onStartProtection: {
                .failed(message: "This fixture does not start protection.")
            },
            onFinishProtectedSetup: {},
            onContinueWithoutProtection: {},
            reduceMotionOverride: reduceMotion,
            goalContext: goalContext,
            allowsFirstGoalHandoffDelivery: allowsDelivery,
            firstGoalHandoff: handoff,
            onFirstGoalHandoffConsumed: { token in
                guard handoff == token else { return nil }
                capture.consumptionAttempts.append(token)
                capture.exposureAtConsumption.append(allowsDelivery)
                guard acceptsToken else { return nil }
                handoff = nil
                return goalContext
            },
            onFirstGoalHandoffDelivered: { effect in
                capture.deliveryEffects.append(effect)
            }
        )
        .task {
            guard !initiallyExposed else { return }
            await Task.yield()
            allowsDelivery = true
        }
    }
}

private struct FirstRunProtectionRenderScene: View {
    let fixture: FirstRunProtectionRenderFixture
    var goalContext = FirstRunGoalContext(
        goalID: UUID(uuidString: "FC309E90-D35E-4D2A-927D-36B809C904C0")!,
        title: "Lead a systems design interview"
    )
    var firstGoalHandoff: FirstGoalSuccessHandoffToken? = nil
    var firstGoalHandoffRevealSequence = 0
    var viewportCapture: ProtectedAppsPickerViewportCapture? = nil

    var body: some View {
        NavigationStack {
            Group {
                if fixture.phase == .selecting {
                    selectionSurface
                } else {
                    FirstRunProtectionStatusView(
                        phase: fixture.phase,
                        goalContext: goalContext,
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

    @ViewBuilder
    private var selectionSurface: some View {
        switch FirstRunAppSelectionChrome(dynamicTypeSize: fixture.dynamicTypeSize) {
        case .brandedHeader:
            VStack(spacing: 0) {
                FirstRunAppSelectionHeader(
                    goalContext: goalContext,
                    selectionSummary: selectionSummary,
                    categorySelectionDetail: inlineCategorySelectionDetail,
                    errorMessage: nil,
                    didJustSaveGoal: firstGoalHandoff?.goalID == goalContext.goalID,
                    firstGoalHandoffRevealSequence: firstGoalHandoffRevealSequence,
                    reduceMotionOverride: fixture.reduceMotion,
                    usesMinimalAccessibilityLayout: FirstRunAppSelectionLayoutPolicy
                        .usesMinimalAccessibilityHeader(
                            dynamicTypeSize: fixture.dynamicTypeSize,
                            availableHeight: fixture.height
                        )
                )
                .padding(16)
                .background(CheckpointTheme.panel)

                pickerSkeleton
            }
        case .systemPickerCopy:
            let presentation = FirstRunAppSelectionHeaderPresentation(
                goalContext: goalContext,
                didJustSaveGoal: firstGoalHandoff?.goalID == goalContext.goalID
            )
            ProtectedAppsSystemPickerSkeleton(
                headerText: presentation.pickerHeaderText(
                    selectionSummary: selectionSummary,
                    errorMessage: nil,
                    isCondensed: true,
                    condensedSelectionSummary: fixture.hasSelection
                        ? selectionSummary
                        : "0 selected"
                ),
                footerText: presentation.pickerFooterText(
                    categorySelectionDetail: categorySelectionDetail
                ),
                viewportCapture: viewportCapture
            )
        }
    }

    private var selectionSummary: String {
        if fixture.categoryOnlySelection {
            return "Category selected · choose an app inside"
        }
        return fixture.hasSelection
            ? "3 apps and 2 websites selected"
            : "Nothing selected yet"
    }

    private var categorySelectionDetail: String? {
        fixture.categoryOnlySelection
            ? "Keep at least one app selected from the category, or choose a website, so Checkpoint has something to protect."
            : nil
    }

    private var inlineCategorySelectionDetail: String? {
        guard FirstRunAppSelectionLayoutPolicy.showsCategorySelectionDetail(
            dynamicTypeSize: fixture.dynamicTypeSize,
            availableHeight: fixture.height
        ) else {
            return nil
        }
        return categorySelectionDetail
    }

    private var pickerSkeleton: some View {
        ProtectedAppsPickerSkeleton(viewportCapture: viewportCapture)
    }
}

@MainActor
private final class FirstRunRenderScreenTimeAuthorizer: ScreenTimeAuthorizing {
    var authorizationStatus: ScreenTimeAuthorizationStatus { .approved }

    func requestAuthorization() async throws {}
}
