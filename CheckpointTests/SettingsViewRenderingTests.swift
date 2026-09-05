import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

#if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
import ManagedSettings
#endif

final class SettingsViewRenderingTests: XCTestCase {
    func testDataEraseWarningNamesExternalStateThatContinues() {
        let warning = CheckpointDataEraseCopy.warningMessage

        XCTAssertEqual(AdvancedSettingsAction.resetData.detail, warning)
        XCTAssertTrue(warning.contains("local purchase-status reminders"))
        XCTAssertTrue(warning.contains("purchases in progress"))
        XCTAssertTrue(warning.contains("Screen Time permission"))
        XCTAssertTrue(warning.contains("not canceled"))
    }

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

    func testProtectionMotionPolicyEmphasizesOnlyActivation() {
        let standard = SettingsProtectionMotionPolicy(reduceMotion: false)
        XCTAssertNotNil(standard.animation)
        XCTAssertTrue(standard.animatesActivationSymbol)
        XCTAssertTrue(standard.emphasizesTransition(from: .ready, to: .active))
        XCTAssertFalse(standard.emphasizesTransition(from: .active, to: .active))
        XCTAssertFalse(standard.emphasizesTransition(from: .active, to: .ready))

        let reduced = SettingsProtectionMotionPolicy(reduceMotion: true)
        XCTAssertNil(reduced.animation)
        XCTAssertFalse(reduced.animatesActivationSymbol)
        XCTAssertFalse(reduced.emphasizesTransition(from: .ready, to: .active))
    }

    func testProtectionTransitionPolicySeparatesVisualProgressFromSideEffects() {
        XCTAssertFalse(
            SettingsProtectionTransitionPolicy.shouldClearActionMessage(
                from: .startingProtection,
                to: .checkpointRequired
            )
        )
        XCTAssertFalse(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .startingProtection,
                to: .checkpointRequired,
                hasConcreteError: false
            )
        )

        XCTAssertTrue(
            SettingsProtectionTransitionPolicy.shouldClearActionMessage(
                from: .checkpointRequired,
                to: .ready
            )
        )
        XCTAssertTrue(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .checkpointRequired,
                to: .ready,
                hasConcreteError: false
            )
        )

        XCTAssertTrue(
            SettingsProtectionTransitionPolicy.shouldClearActionMessage(
                from: .requestingAuthorization,
                to: .permissionRequired
            )
        )
        XCTAssertFalse(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .requestingAuthorization,
                to: .permissionRequired,
                hasConcreteError: true
            )
        )

        XCTAssertTrue(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .ready,
                to: .active,
                hasConcreteError: false
            )
        )
        XCTAssertFalse(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .startingProtection,
                to: .active,
                hasConcreteError: false
            )
        )

        XCTAssertFalse(
            SettingsProtectionTransitionPolicy.shouldClearActionMessage(
                from: .breakInProgress(relockReadiness: .ready),
                to: .breakInProgress(relockReadiness: .waitingForCheckpoint)
            )
        )
        XCTAssertTrue(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .breakInProgress(relockReadiness: .ready),
                to: .breakInProgress(relockReadiness: .waitingForCheckpoint),
                hasConcreteError: false
            )
        )
        XCTAssertFalse(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .breakInProgress(relockReadiness: .ready),
                to: .breakInProgress(relockReadiness: .needsAttention),
                hasConcreteError: true
            )
        )

        XCTAssertTrue(
            SettingsProtectionTransitionPolicy.shouldClearActionMessage(
                from: .checkpointRequired,
                to: .preparingPractice
            )
        )
        XCTAssertTrue(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .checkpointRequired,
                to: .preparingPractice,
                hasConcreteError: false
            )
        )
        XCTAssertTrue(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .requestingAuthorization,
                to: .chooseApps,
                hasConcreteError: false
            )
        )
        XCTAssertFalse(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .authorizationRequired,
                to: .requestingAuthorization,
                hasConcreteError: false
            )
        )
        XCTAssertFalse(
            SettingsProtectionTransitionPolicy.shouldClearActionMessage(
                from: .startingProtection,
                to: .preparingPractice
            )
        )
        XCTAssertFalse(
            SettingsProtectionTransitionPolicy.shouldAnnounce(
                from: .startingProtection,
                to: .preparingPractice,
                hasConcreteError: false
            )
        )
    }

    func testTabContentAnnouncementsRequireTheVisibleUncoveredOwner() {
        XCTAssertTrue(
            TabContentAnnouncementOwnership.isActive(
                isVisible: true,
                isCoveredByParentPresentation: false,
                isCoveredByLocalPresentation: false
            )
        )
        XCTAssertFalse(
            TabContentAnnouncementOwnership.isActive(
                isVisible: false,
                isCoveredByParentPresentation: false,
                isCoveredByLocalPresentation: false
            )
        )
        XCTAssertFalse(
            TabContentAnnouncementOwnership.isActive(
                isVisible: true,
                isSceneActive: false,
                isCoveredByParentPresentation: false,
                isCoveredByLocalPresentation: false
            )
        )
        XCTAssertFalse(
            TabContentAnnouncementOwnership.isActive(
                isVisible: true,
                isCoveredByParentPresentation: true,
                isCoveredByLocalPresentation: false
            )
        )
        XCTAssertFalse(
            TabContentAnnouncementOwnership.isActive(
                isVisible: true,
                isCoveredByParentPresentation: false,
                isCoveredByLocalPresentation: true
            )
        )
    }

    func testAccessibilityAnnouncementQueueDeliversEachResultOnce() {
        var queue = AccessibilityAnnouncementDeliveryQueue()
        let errorRequest = AccessibilityAnnouncementRequest(
            message: "Screen Time needs attention.",
            context: .screenTimeError("Screen Time needs attention.")
        )
        let readinessRequest = AccessibilityAnnouncementRequest(
            message: "Questions are ready.",
            context: .goalReady(UUID())
        )

        XCTAssertNil(queue.submit(errorRequest, isOwner: false))
        XCTAssertEqual(queue.pendingRequest, errorRequest)
        XCTAssertNil(queue.takePending(isOwner: false))
        XCTAssertEqual(queue.takePending(isOwner: true), errorRequest)
        XCTAssertNil(queue.takePending(isOwner: true))

        XCTAssertEqual(
            queue.submit(readinessRequest, isOwner: true),
            readinessRequest
        )
        XCTAssertNil(queue.pendingRequest)

        let staleRequest = AccessibilityAnnouncementRequest(
            message: "Stale result",
            context: .settingsMessage("Stale result")
        )
        XCTAssertNil(queue.submit(staleRequest, isOwner: false))
        queue.discard()
        XCTAssertNil(queue.takePending(isOwner: true))
    }

    func testProtectionStartResultAnnouncementsRejectStaleOutcomes() {
        let success = ProtectionStartResultEvent(
            id: UUID(),
            goalID: UUID(),
            becameCheckpointReadyDuringStart: false,
            didStart: true,
            checkpointNotice: nil,
            protectionErrorMessage: nil
        )
        XCTAssertTrue(
            ProtectionStartResultAnnouncement.isCurrent(
                success,
                currentGoalID: success.goalID,
                isShieldingEnabled: true,
                protectionShouldRemainActive: true,
                checkpointNotice: nil,
                protectionErrorMessage: nil
            )
        )
        XCTAssertFalse(
            ProtectionStartResultAnnouncement.isCurrent(
                success,
                currentGoalID: UUID(),
                isShieldingEnabled: true,
                protectionShouldRemainActive: true,
                checkpointNotice: nil,
                protectionErrorMessage: nil
            )
        )
        XCTAssertFalse(
            ProtectionStartResultAnnouncement.isCurrent(
                success,
                currentGoalID: success.goalID,
                isShieldingEnabled: false,
                protectionShouldRemainActive: true,
                checkpointNotice: nil,
                protectionErrorMessage: nil
            )
        )

        let failed = ProtectionStartResultEvent(
            id: UUID(),
            goalID: UUID(),
            becameCheckpointReadyDuringStart: false,
            didStart: false,
            checkpointNotice: "A full checkpoint is still needed.",
            protectionErrorMessage: nil
        )
        XCTAssertTrue(
            ProtectionStartResultAnnouncement.isCurrent(
                failed,
                currentGoalID: failed.goalID,
                isShieldingEnabled: false,
                protectionShouldRemainActive: false,
                checkpointNotice: "A full checkpoint is still needed.",
                protectionErrorMessage: nil
            )
        )
        XCTAssertFalse(
            ProtectionStartResultAnnouncement.isCurrent(
                failed,
                currentGoalID: failed.goalID,
                isShieldingEnabled: false,
                protectionShouldRemainActive: false,
                checkpointNotice: "Questions are ready now.",
                protectionErrorMessage: nil
            )
        )
        XCTAssertFalse(
            ProtectionStartResultAnnouncement.isCurrent(
                failed,
                currentGoalID: failed.goalID,
                isShieldingEnabled: false,
                protectionShouldRemainActive: true,
                checkpointNotice: "A full checkpoint is still needed.",
                protectionErrorMessage: nil
            )
        )

        let error = ProtectionStartResultEvent(
            id: UUID(),
            goalID: UUID(),
            becameCheckpointReadyDuringStart: false,
            didStart: false,
            checkpointNotice: nil,
            protectionErrorMessage: "Screen Time access was denied."
        )
        XCTAssertTrue(
            ProtectionStartResultAnnouncement.isCurrent(
                error,
                currentGoalID: error.goalID,
                isShieldingEnabled: false,
                protectionShouldRemainActive: false,
                checkpointNotice: nil,
                protectionErrorMessage: "Screen Time access was denied."
            )
        )
        XCTAssertFalse(
            ProtectionStartResultAnnouncement.isCurrent(
                error,
                currentGoalID: error.goalID,
                isShieldingEnabled: false,
                protectionShouldRemainActive: false,
                checkpointNotice: nil,
                protectionErrorMessage: "Protected apps need to be selected."
            )
        )
    }

    func testProtectionStartReadinessSuppressesOnlyMatchingStartWork() {
        let goalID = UUID()
        let generatedResult = ProtectionStartResultEvent(
            id: UUID(),
            goalID: goalID,
            becameCheckpointReadyDuringStart: true,
            didStart: true,
            checkpointNotice: nil,
            protectionErrorMessage: nil
        )
        let unrelatedResult = ProtectionStartResultEvent(
            id: UUID(),
            goalID: goalID,
            becameCheckpointReadyDuringStart: false,
            didStart: false,
            checkpointNotice: "A full checkpoint is still needed.",
            protectionErrorMessage: nil
        )

        XCTAssertTrue(
            ProtectionStartReadinessAnnouncementPolicy.shouldSuppress(
                for: goalID,
                locallySuppressedGoalID: nil,
                parentPresentationOwnsReadiness: false,
                startingProtectionReadinessGoalID: nil,
                pendingResult: generatedResult
            )
        )
        XCTAssertTrue(
            ProtectionStartReadinessAnnouncementPolicy.shouldSuppress(
                for: goalID,
                locallySuppressedGoalID: nil,
                parentPresentationOwnsReadiness: false,
                startingProtectionReadinessGoalID: goalID,
                pendingResult: nil
            )
        )
        XCTAssertFalse(
            ProtectionStartReadinessAnnouncementPolicy.shouldSuppress(
                for: goalID,
                locallySuppressedGoalID: nil,
                parentPresentationOwnsReadiness: false,
                startingProtectionReadinessGoalID: nil,
                pendingResult: unrelatedResult
            )
        )
        XCTAssertFalse(
            ProtectionStartReadinessAnnouncementPolicy.shouldSuppress(
                for: UUID(),
                locallySuppressedGoalID: nil,
                parentPresentationOwnsReadiness: false,
                startingProtectionReadinessGoalID: nil,
                pendingResult: generatedResult
            )
        )
        XCTAssertTrue(
            ProtectionStartReadinessAnnouncementPolicy.shouldSuppress(
                for: goalID,
                locallySuppressedGoalID: nil,
                parentPresentationOwnsReadiness: true,
                startingProtectionReadinessGoalID: nil,
                pendingResult: nil
            )
        )
    }

    func testProtectionStartErrorFeedbackHandlesEitherObserverOrder() {
        let errorMessage = "Screen Time access was denied."
        let result = ProtectionStartResultEvent(
            id: UUID(),
            goalID: UUID(),
            becameCheckpointReadyDuringStart: false,
            didStart: false,
            checkpointNotice: nil,
            protectionErrorMessage: errorMessage
        )
        var feedback = ProtectionStartErrorFeedbackState()

        XCTAssertFalse(
            feedback.shouldDeliverPassiveError(
                errorMessage,
                isStartFeedbackPending: true
            )
        )
        feedback.recordDeliveredResult(result)
        XCTAssertFalse(
            feedback.shouldDeliverPassiveError(
                errorMessage,
                isStartFeedbackPending: false
            )
        )

        feedback.recordDeliveredResult(result)
        XCTAssertTrue(
            feedback.shouldDeliverPassiveError(
                "A different Screen Time error.",
                isStartFeedbackPending: false
            )
        )
        XCTAssertTrue(
            feedback.shouldDeliverPassiveError(
                errorMessage,
                isStartFeedbackPending: false
            )
        )
        XCTAssertFalse(
            feedback.shouldDeliverPassiveError(
                nil,
                isStartFeedbackPending: false
            )
        )
    }

    func testSettingsProtectionFeedbackHandlesEitherObserverOrder() {
        var feedback = SettingsProtectionAnnouncementState()

        XCTAssertFalse(
            feedback.shouldDeliverTransition(
                to: .active,
                isActionFeedbackPending: true
            )
        )
        feedback.recordExplicitState(.active)
        XCTAssertFalse(
            feedback.shouldDeliverTransition(
                to: .active,
                isActionFeedbackPending: false
            )
        )
        XCTAssertTrue(
            feedback.shouldDeliverTransition(
                to: .ready,
                isActionFeedbackPending: false
            )
        )

        feedback.recordExplicitState(.active)
        XCTAssertFalse(
            feedback.shouldDeliverTransition(
                to: .ready,
                isActionFeedbackPending: true
            )
        )
        XCTAssertTrue(
            feedback.shouldDeliverTransition(
                to: .active,
                isActionFeedbackPending: false
            )
        )
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
    func testProtectionStatusHeaderRendersTruthfulSemanticStates() {
        let fixtures = [
            SettingsProtectionHeaderRenderFixture(
                name: "settings-protection-not-set-up-light",
                width: 393,
                height: 340,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                presentation: protectionPresentation(
                    setupState: .notStarted,
                    authorizationState: .notDetermined,
                    hasSelection: false,
                    hasReadyCheckpointSet: false,
                    restrictedAppsSummary: "No protected apps selected"
                )
            ),
            SettingsProtectionHeaderRenderFixture(
                name: "settings-protection-stale-active-renders-off-light",
                width: 393,
                height: 340,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                presentation: protectionPresentation(
                    setupState: .shieldActive,
                    isShieldingEnabled: false,
                    hasSelection: true,
                    hasReadyCheckpointSet: true,
                    restrictedAppsSummary: "3 apps selected"
                )
            ),
            SettingsProtectionHeaderRenderFixture(
                name: "settings-protection-ready-xxxlarge-stacked-light",
                width: 393,
                height: 500,
                colorScheme: .light,
                dynamicTypeSize: .xxxLarge,
                reduceMotion: false,
                presentation: protectionPresentation(
                    setupState: .authorized,
                    isShieldingEnabled: false,
                    hasSelection: true,
                    hasReadyCheckpointSet: true,
                    restrictedAppsSummary: "3 apps selected"
                )
            ),
            SettingsProtectionHeaderRenderFixture(
                name: "settings-protection-active-dark",
                width: 393,
                height: 340,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                reduceMotion: false,
                presentation: protectionPresentation(
                    setupState: .shieldActive,
                    isShieldingEnabled: true,
                    hasSelection: true,
                    hasReadyCheckpointSet: true,
                    restrictedAppsSummary: "3 apps selected"
                )
            ),
            SettingsProtectionHeaderRenderFixture(
                name: "settings-protection-break-compact",
                width: 320,
                height: 430,
                colorScheme: .light,
                dynamicTypeSize: .large,
                reduceMotion: false,
                presentation: protectionPresentation(
                    setupState: .temporarilyUnlocked,
                    isShieldingEnabled: false,
                    hasSelection: true,
                    hasReadyCheckpointSet: false,
                    breakRelockReadiness: .waitingForCheckpoint,
                    restrictedAppsSummary: "2 apps and 1 website selected"
                )
            ),
            SettingsProtectionHeaderRenderFixture(
                name: "settings-protection-permission-accessibility5-reduced-motion",
                width: 393,
                height: 900,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                presentation: protectionPresentation(
                    setupState: .failed,
                    isShieldingEnabled: false,
                    authorizationState: .denied,
                    hasSelection: false,
                    hasReadyCheckpointSet: false,
                    restrictedAppsSummary: "No protected apps selected"
                )
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: SettingsProtectionHeaderRenderScene(fixture: fixture)
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
    func testSettingsViewRendersProtectionSetupControlStates() async throws {
        try await assertSettingsProtectionControlRenders([
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-requesting-access-light",
                state: .requestingAuthorization,
                colorScheme: .light
            ),
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-authorization-required-light",
                state: .authorizationRequired,
                colorScheme: .light
            ),
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-permission-error-accessibility3-light",
                state: .permissionRequired,
                colorScheme: .light,
                dynamicTypeSize: .accessibility3,
                height: 2_000
            ),
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-choose-apps-light",
                state: .chooseApps,
                colorScheme: .light
            )
        ])
    }

    @MainActor
    func testSettingsViewRendersProtectionReadinessControlStates() async throws {
        try await assertSettingsProtectionControlRenders([
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-checkpoint-required-light",
                state: .checkpointRequired,
                colorScheme: .light
            ),
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-background-preparation-light",
                state: .backgroundPreparation,
                colorScheme: .light
            ),
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-starting-accessibility2-light",
                state: .startingProtection,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                height: 1_800
            ),
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-ready-light",
                state: .ready,
                colorScheme: .light
            )
        ])
    }

    @MainActor
    func testSettingsViewRendersProtectionAppliedControlStates() async throws {
        try await assertSettingsProtectionControlRenders([
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-active-dark",
                state: .active,
                colorScheme: .dark
            ),
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-break-waiting-dark",
                state: .breakWaitingForCheckpoint,
                colorScheme: .dark
            ),
            SettingsProtectionControlRenderFixture(
                name: "settings-protection-controls-unavailable-light",
                state: .unavailable,
                colorScheme: .light
            )
        ])
    }

    @MainActor
    private func assertSettingsProtectionControlRenders(
        _ fixtures: [SettingsProtectionControlRenderFixture]
    ) async throws {
        for fixture in fixtures {
            let image = try await renderSettingsProtectionControls(fixture)
            XCTAssertEqual(image.size.width, 393, accuracy: 0.5, fixture.name)
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

        let focusSkill = SkillMapTopic(name: "Reliability and failure recovery")
        let goal = Goal(
            title: "Pass senior technical interviews",
            deadline: fixedDate(year: 2027, month: 2, day: 14),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "system design, reliability, communication",
            derivedSkillMap: GoalSkillMap(
                topics: [focusSkill],
                status: .reviewed,
                provenance: .userEdited
            ),
            preferredQuestionStyle: .multipleChoice
        )
        let secondGoal = Goal(
            title: "Write a product strategy brief",
            deadline: fixedDate(year: 2027, month: 3, day: 20),
            category: .writing,
            currentLevel: "Intermediate",
            focusAreas: "positioning, evidence, clarity",
            preferredQuestionStyle: .shortAnswer
        )
        let store = CheckpointStore(defaults: storeDefaults)
        store.goal = goal
        store.goalProfiles = [goal, secondGoal]
        store.membershipTier = .member
        store.questions = (1...store.unlockPolicy.questionsPerSession).map {
            makeQuestion(
                goal: goal,
                index: $0,
                topic: focusSkill.name,
                skillID: focusSkill.id
            )
        }
        store.questionBatchState = .ready
        store.isQuestionBankTopOffInProgress = true

        guard case let .recommendation(recommendation)? = store.studyFocusState else {
            return XCTFail("The assembled Pro settings fixture must expose a live Next Focus.")
        }
        XCTAssertEqual(recommendation.title, focusSkill.name)

        let screenTime = ScreenTimeController(
            defaults: screenTimeDefaults,
            authorizer: SettingsRenderScreenTimeAuthorizer()
        )
        await screenTime.bootstrapAuthorizationIfNeeded()
        let purchaseController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: nil
        )
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

        let layoutCapture = SettingsLayoutCapture()
        let firstFoldImage = HostedViewRenderer.image(
            for: SettingsView(
                store: store,
                screenTime: screenTime,
                purchaseController: purchaseController,
                workflow: workflow,
                presentCheckpoint: { _ in false },
                layoutReporter: { element, frame in
                    layoutCapture.frames[element] = frame
                }
            )
            .environment(\.colorScheme, ColorScheme.light)
            .environment(\.dynamicTypeSize, DynamicTypeSize.large)
            .environment(\.checkpointGoalSelection, GoalSelectionAction { _ in }),
            width: 393,
            height: 852,
            colorScheme: .light,
            settlingTime: 0.25,
            renderScale: 1
        )

        let viewport = try XCTUnwrap(layoutCapture.frames[.viewport])
        let protection = try XCTUnwrap(layoutCapture.frames[.protection])
        let goals = try XCTUnwrap(layoutCapture.frames[.goals])
        let practiceStandard = try XCTUnwrap(layoutCapture.frames[.practiceStandard])
        let plan = try XCTUnwrap(layoutCapture.frames[.plan])
        for frame in [protection, goals, practiceStandard, plan] {
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 0.5)
            XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 0.5)
        }
        XCTAssertLessThanOrEqual(protection.maxY, goals.minY + 0.5)
        XCTAssertLessThanOrEqual(goals.maxY, practiceStandard.minY + 0.5)
        XCTAssertLessThanOrEqual(practiceStandard.maxY, plan.minY + 0.5)
        XCTAssertTrue(
            viewport.insetBy(dx: -0.5, dy: -0.5).contains(goals),
            "Goal management must remain fully visible in the normal Settings first fold."
        )
        let visiblePracticeStandard = practiceStandard.intersection(viewport)
        XCTAssertFalse(visiblePracticeStandard.isNull)
        XCTAssertGreaterThanOrEqual(
            visiblePracticeStandard.height,
            44,
            "The checkpoint standard must begin with a meaningful affordance in the first fold."
        )

        XCTAssertEqual(firstFoldImage.size.width, 393, accuracy: 0.5)
        XCTAssertEqual(firstFoldImage.size.height, 852, accuracy: 0.5)
        let firstFoldAttachment = XCTAttachment(image: firstFoldImage)
        firstFoldAttachment.name = "settings-core-controls-first-fold-light"
        firstFoldAttachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(firstFoldAttachment)
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

    private func protectionPresentation(
        setupState: ScreenTimeController.SetupState = .authorized,
        isShieldingEnabled: Bool = false,
        authorizationState: ScreenTimeController.AuthorizationState = .approvedWithDataAccess,
        hasSelection: Bool = true,
        hasReadyCheckpointSet: Bool = true,
        isStartingProtection: Bool = false,
        isPreparingPractice: Bool = false,
        breakRelockReadiness: HomeActiveBreakRelockReadiness = .ready,
        restrictedAppsSummary: String = "1 app selected"
    ) -> SettingsProtectionPresentation {
        SettingsProtectionPresentation(
            setupState: setupState,
            isShieldingEnabled: isShieldingEnabled,
            authorizationState: authorizationState,
            hasSelection: hasSelection,
            hasReadyCheckpointSet: hasReadyCheckpointSet,
            isStartingProtection: isStartingProtection,
            isPreparingPractice: isPreparingPractice,
            breakRelockReadiness: breakRelockReadiness,
            restrictedAppsSummary: restrictedAppsSummary
        )
    }

    @MainActor
    private func renderSettingsProtectionControls(
        _ fixture: SettingsProtectionControlRenderFixture
    ) async throws -> UIImage {
        resetSharedAppGroupState()
        defer { resetSharedAppGroupState() }

        let storeSuiteName = "SettingsViewRenderingTests.Controls.Store.\(UUID().uuidString)"
        let screenTimeSuiteName = "SettingsViewRenderingTests.Controls.ScreenTime.\(UUID().uuidString)"
        let storeDefaults = try XCTUnwrap(UserDefaults(suiteName: storeSuiteName))
        let screenTimeDefaults = try XCTUnwrap(UserDefaults(suiteName: screenTimeSuiteName))
        defer {
            storeDefaults.removePersistentDomain(forName: storeSuiteName)
            screenTimeDefaults.removePersistentDomain(forName: screenTimeSuiteName)
        }

        let goal = Goal(
            title: "Finish a focused portfolio launch",
            deadline: fixedDate(year: 2027, month: 3, day: 10),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "planning, execution, communication",
            preferredQuestionStyle: .multipleChoice
        )
        let delayedQuestionEngine = SettingsRenderQuestionEngine(
            requestDelayNanoseconds: fixture.state.usesDelayedQuestionEngine
                ? 30_000_000_000
                : 0
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: delayedQuestionEngine,
                appleFoundationEngine: delayedQuestionEngine
            ),
            defaults: storeDefaults
        )
        store.goal = goal
        store.goalProfiles = [goal]
        store.membershipTier = .member

        let authorizer = SettingsRenderScreenTimeAuthorizer(
            authorizationStatus: fixture.state.authorizationStatus,
            suspendsAuthorizationRequest: fixture.state == .requestingAuthorization
        )
        let screenTime = ScreenTimeController(
            defaults: screenTimeDefaults,
            authorizer: authorizer
        )
        await screenTime.bootstrapAuthorizationIfNeeded()
        if fixture.state.requiresProtectedAppSelection {
            try configureProtectedAppSelection(screenTime)
        }

        let purchaseController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: nil
        )
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: screenTime)
        var authorizationRequestTask: Task<Void, Never>?
        var protectionStartTask: Task<Bool, Never>?

        switch fixture.state {
        case .requestingAuthorization:
            authorizationRequestTask = Task {
                await screenTime.requestAuthorization()
            }
            await Task.yield()
            XCTAssertTrue(screenTime.isRequestingAuthorization)
        case .authorizationRequired, .permissionRequired, .chooseApps:
            break
        case .checkpointRequired:
            screenTime.setupState = .authorized
            screenTime.isShieldingEnabled = false
        case .backgroundPreparation:
            screenTime.setupState = .authorized
            screenTime.isShieldingEnabled = false
            store.questionBatchState = .generating
        case .startingProtection:
            screenTime.setupState = .authorized
            screenTime.isShieldingEnabled = false
            protectionStartTask = Task {
                await workflow.startProtection()
            }
            await Task.yield()
            XCTAssertTrue(workflow.isStartingProtection)
        case .ready:
            screenTime.setupState = .authorized
            screenTime.isShieldingEnabled = false
            store.questions = (1...store.unlockPolicy.questionsPerSession).map {
                makeQuestion(goal: goal, index: $0, topic: "execution")
            }
            store.questionBatchState = .ready
        case .active:
            screenTime.setupState = .shieldActive
            screenTime.isShieldingEnabled = true
        case .breakWaitingForCheckpoint:
            SharedAppGroup.publishCheckpointReadiness(false)
            screenTime.setupState = .temporarilyUnlocked
            screenTime.isShieldingEnabled = false
        case .unavailable:
            screenTime.setupState = .unavailable
            screenTime.isShieldingEnabled = false
            screenTime.restrictedAppsSummary = "App protection is available on iPhone."
        }

        let image = HostedViewRenderer.image(
            for: SettingsView(
                store: store,
                screenTime: screenTime,
                purchaseController: purchaseController,
                workflow: workflow,
                presentCheckpoint: { _ in false }
            )
            .environment(\.colorScheme, fixture.colorScheme)
            .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)
            .environment(\.checkpointGoalSelection, GoalSelectionAction { _ in }),
            width: 393,
            height: fixture.height,
            colorScheme: fixture.colorScheme,
            settlingTime: 0.4,
            renderScale: 1
        )

        authorizationRequestTask?.cancel()
        protectionStartTask?.cancel()
        if let authorizationRequestTask {
            await authorizationRequestTask.value
        }
        if let protectionStartTask {
            _ = await protectionStartTask.value
        }
        return image
    }

    @MainActor
    private func configureProtectedAppSelection(
        _ screenTime: ScreenTimeController
    ) throws {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        let applicationToken = try JSONDecoder().decode(
            ManagedSettings.ApplicationToken.self,
            from: Data(#"{"data":"AQIDBA=="}"#.utf8)
        )
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        selection.applicationTokens = [applicationToken]
        XCTAssertTrue(screenTime.updateSelection(selection))
        XCTAssertTrue(screenTime.hasSelection)
        #else
        XCTFail("Protection control renders require FamilyControls and ManagedSettings")
        #endif
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

@MainActor
private final class SettingsLayoutCapture {
    var frames: [SettingsLayoutElement: CGRect] = [:]
}

private struct SettingsProtectionHeaderRenderFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let reduceMotion: Bool
    let presentation: SettingsProtectionPresentation
}

private struct SettingsProtectionControlRenderFixture {
    enum State: Equatable {
        case requestingAuthorization
        case authorizationRequired
        case permissionRequired
        case chooseApps
        case checkpointRequired
        case backgroundPreparation
        case startingProtection
        case ready
        case active
        case breakWaitingForCheckpoint
        case unavailable

        var authorizationStatus: ScreenTimeAuthorizationStatus {
            switch self {
            case .requestingAuthorization, .authorizationRequired:
                .notDetermined
            case .permissionRequired:
                .denied
            case .chooseApps,
                 .checkpointRequired,
                 .backgroundPreparation,
                 .startingProtection,
                 .ready,
                 .active,
                 .breakWaitingForCheckpoint,
                 .unavailable:
                .approved
            }
        }

        var requiresProtectedAppSelection: Bool {
            switch self {
            case .checkpointRequired,
                 .backgroundPreparation,
                 .startingProtection,
                 .ready,
                 .active,
                 .breakWaitingForCheckpoint:
                true
            case .requestingAuthorization,
                 .authorizationRequired,
                 .permissionRequired,
                 .chooseApps,
                 .unavailable:
                false
            }
        }

        var usesDelayedQuestionEngine: Bool {
            self == .startingProtection
        }
    }

    let name: String
    let state: State
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let height: CGFloat

    init(
        name: String,
        state: State,
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize = .large,
        height: CGFloat = 900
    ) {
        self.name = name
        self.state = state
        self.colorScheme = colorScheme
        self.dynamicTypeSize = dynamicTypeSize
        self.height = height
    }
}

private struct SettingsProtectionHeaderRenderScene: View {
    let fixture: SettingsProtectionHeaderRenderFixture

    var body: some View {
        ScrollView {
            SectionPanel("Protection") {
                SettingsProtectionStatusHeader(
                    presentation: fixture.presentation,
                    reduceMotionOverride: fixture.reduceMotion
                )

                if let selectionSummary = fixture.presentation.visibleRestrictedAppsSummary {
                    Text(selectionSummary)
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .padding(.bottom, 36)
        }
        .checkpointScreenBackground()
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
    let authorizationStatus: ScreenTimeAuthorizationStatus
    let suspendsAuthorizationRequest: Bool

    init(
        authorizationStatus: ScreenTimeAuthorizationStatus = .approved,
        suspendsAuthorizationRequest: Bool = false
    ) {
        self.authorizationStatus = authorizationStatus
        self.suspendsAuthorizationRequest = suspendsAuthorizationRequest
    }

    func requestAuthorization() async throws {
        guard suspendsAuthorizationRequest else { return }
        try await Task.sleep(nanoseconds: 30_000_000_000)
    }
}

private struct SettingsRenderQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind = .backend
    let requestDelayNanoseconds: UInt64

    func generateQuestions(
        for request: QuestionGenerationRequest
    ) async throws -> [CheckpointQuestion] {
        if requestDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: requestDelayNanoseconds)
        }

        return (1...request.targetCount).map {
            makeQuestion(goal: request.goal, index: $0, topic: "execution")
        }
    }
}
