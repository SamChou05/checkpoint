import XCTest
@testable import Checkpoint

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

final class ScreenTimeCoordinationTests: CheckpointWorkflowTestCase {
    // MARK: - Screen Time and shield coordination

    @MainActor
    func testPendingShieldAttemptCreatesOneCheckpointSessionThenClears() throws {
        let store = makeSeededStore(questionCount: 6)

        SharedAppGroup.markPendingShieldAttempt()

        XCTAssertNotNil(SharedAppGroup.pendingShieldAttemptDate)
        let session = try XCTUnwrap(store.takePendingShieldSession())
        XCTAssertEqual(session.questions.count, 5)
        XCTAssertNil(SharedAppGroup.pendingShieldAttemptDate)
        XCTAssertNil(store.takePendingShieldSession())
    }

    @MainActor
    func testPendingSessionPreparationCannotConsumeReplacementShieldTap() throws {
        let store = makeSeededStore(questionCount: 6)
        SharedAppGroup.markPendingShieldAttempt()
        let firstAttemptID = try XCTUnwrap(SharedAppGroup.currentPendingShieldAttempt?.id)

        SharedAppGroup.markPendingShieldAttempt()
        let replacementAttemptID = try XCTUnwrap(SharedAppGroup.currentPendingShieldAttempt?.id)

        XCTAssertNotEqual(firstAttemptID, replacementAttemptID)
        XCTAssertNil(store.takePendingShieldSession(pendingAttemptID: firstAttemptID))
        XCTAssertEqual(SharedAppGroup.currentPendingShieldAttempt?.id, replacementAttemptID)

        let session = try XCTUnwrap(
            store.takePendingShieldSession(pendingAttemptID: replacementAttemptID)
        )
        XCTAssertEqual(session.questions.count, 5)
        XCTAssertNil(SharedAppGroup.currentPendingShieldAttempt)
    }

    @MainActor
    func testShieldConfigurationDiagnosticsAreRecorded() {
        XCTAssertEqual(SharedAppGroup.shieldConfigurationRenderCount, 0)
        XCTAssertNil(SharedAppGroup.shieldConfigurationRenderDate)

        SharedAppGroup.markShieldConfigurationRendered()

        XCTAssertEqual(SharedAppGroup.shieldConfigurationRenderCount, 1)
        XCTAssertNotNil(SharedAppGroup.shieldConfigurationRenderDate)
    }

    @MainActor
    func testUnlockRelockMonitorMeetsMinimumDurationForEveryBreakOption() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)

        for minutes in UnlockPolicy.correctAnswerUnlockMinuteOptions {
            let expiration = start.addingTimeInterval(TimeInterval(minutes * 60))
            let monitorStart = ScreenTimeController.unlockRelockMonitorStart(
                for: start,
                expiration: expiration
            )

            XCTAssertGreaterThanOrEqual(
                expiration.timeIntervalSince(monitorStart),
                ScreenTimeController.minimumUnlockRelockMonitorDuration +
                    ScreenTimeController.unlockRelockMonitorDurationSafetyMargin
            )
            XCTAssertLessThan(monitorStart, expiration)
        }
    }

    @MainActor
    func testUnlockRelockMonitorRoundsFractionalExpirationUp() {
        let expiration = Date(timeIntervalSince1970: 1_780_000_000.25)

        let monitorEnd = ScreenTimeController.unlockRelockMonitorEnd(for: expiration)

        XCTAssertEqual(monitorEnd.timeIntervalSince1970, 1_780_000_001, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(monitorEnd, expiration)
    }

    @MainActor
    func testSharedSelectionDataFallsBackToAppGroupFileForExtensions() {
        let data = Data("encoded protected app selection".utf8)

        SharedAppGroup.publishScreenTimeSelectionData(data)
        SharedAppGroup.removeProtectionSnapshotFile()
        SharedAppGroup.defaults.removeObject(forKey: SharedAppGroup.screenTimeSelectionKey)
        SharedAppGroup.defaults.synchronize()

        XCTAssertEqual(SharedAppGroup.screenTimeSelectionData(), data)
    }

    @MainActor
    func testCanonicalProtectionSnapshotWinsOverDivergentLegacySelection() {
        let currentSelection = Data("current protected app selection".utf8)
        let staleSelection = Data("stale protected app selection".utf8)

        SharedAppGroup.publishScreenTimeSelectionData(currentSelection)
        SharedAppGroup.defaults.set(staleSelection, forKey: SharedAppGroup.screenTimeSelectionKey)
        SharedAppGroup.defaults.synchronize()

        XCTAssertEqual(SharedAppGroup.screenTimeSelectionData(), currentSelection)
        XCTAssertEqual(
            SharedAppGroup.currentProtectionSnapshot().screenTimeSelectionData,
            currentSelection
        )
    }

    @MainActor
    func testLegacyMigrationPrefersNewerDefaultsSelectionOverStaleFile() {
        let staleFileSelection = Data("stale file selection".utf8)
        let newerDefaultsSelection = Data("newer defaults selection".utf8)

        SharedAppGroup.publishScreenTimeSelectionData(staleFileSelection)
        SharedAppGroup.removeProtectionSnapshotFile()
        SharedAppGroup.defaults.set(newerDefaultsSelection, forKey: SharedAppGroup.screenTimeSelectionKey)
        SharedAppGroup.defaults.synchronize()

        XCTAssertEqual(
            SharedAppGroup.currentProtectionSnapshot().screenTimeSelectionData,
            newerDefaultsSelection
        )
    }

    @MainActor
    func testLegacyFallbackPreservesAndAdvancesProtectionRevisions() {
        SharedAppGroup.publishScreenTimeSelectionData(Data("selection A".utf8))
        let persistedSnapshot = SharedAppGroup.currentProtectionSnapshot()
        SharedAppGroup.removeProtectionSnapshotFile()

        let fallbackSnapshot = SharedAppGroup.currentProtectionSnapshot()
        XCTAssertEqual(fallbackSnapshot.revision, persistedSnapshot.revision)
        XCTAssertEqual(
            fallbackSnapshot.configurationRevision,
            persistedSnapshot.configurationRevision
        )

        SharedAppGroup.publishScreenTimeSelectionData(Data("selection B".utf8))
        let updatedSnapshot = SharedAppGroup.currentProtectionSnapshot()
        XCTAssertNotEqual(updatedSnapshot.revision, fallbackSnapshot.revision)
        XCTAssertNotEqual(
            updatedSnapshot.configurationRevision,
            fallbackSnapshot.configurationRevision
        )
    }

    func testLegacyCategoryEnforcementOnlyAppliesWithoutConcreteTokens() {
        XCTAssertTrue(
            SharedAppGroup.usesLegacyCategoryEnforcement(
                semanticsVersion: 0,
                applicationTokenCount: 0,
                categoryTokenCount: 1,
                webDomainTokenCount: 0
            )
        )
        XCTAssertFalse(
            SharedAppGroup.usesLegacyCategoryEnforcement(
                semanticsVersion: 0,
                applicationTokenCount: 1,
                categoryTokenCount: 1,
                webDomainTokenCount: 0
            ),
            "Concrete legacy tokens must be authoritative so a category cannot restore a removed app."
        )
        XCTAssertEqual(
            SharedAppGroup.resolvedScreenTimeSelectionSemanticsVersion(
                storedVersion: 0,
                applicationTokenCount: 1,
                webDomainTokenCount: 0
            ),
            SharedAppGroup.currentScreenTimeSelectionSemanticsVersion
        )
        XCTAssertEqual(
            SharedAppGroup.resolvedScreenTimeSelectionSemanticsVersion(
                storedVersion: 0,
                applicationTokenCount: 0,
                webDomainTokenCount: 0
            ),
            0,
            "Truly category-only legacy data must remain protected until the user makes a concrete selection."
        )
    }

    func testOverLimitSelectionCanBeReducedButNotExpanded() {
        let limit = SharedAppGroup.maximumShieldedApplicationCount

        XCTAssertTrue(
            SharedAppGroup.canAcceptShieldTokenCount(
                limit - 1,
                currentCount: limit + 10,
                maximumCount: limit
            )
        )
        XCTAssertTrue(
            SharedAppGroup.canAcceptShieldTokenCount(
                limit + 9,
                currentCount: limit + 10,
                maximumCount: limit
            ),
            "An upgraded user must be able to remove an oversized list one item at a time."
        )
        XCTAssertFalse(
            SharedAppGroup.canAcceptShieldTokenCount(
                limit + 11,
                currentCount: limit + 10,
                maximumCount: limit
            )
        )
        XCTAssertFalse(
            SharedAppGroup.canAcceptShieldTokenCount(
                limit + 1,
                currentCount: limit,
                maximumCount: limit
            )
        )
    }

    @MainActor
    func testExactPendingAttemptConsumptionPreservesNewerShieldTap() {
        SharedAppGroup.publishScreenTimeSelectionData(Data("protected app selection".utf8))
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        SharedAppGroup.markPendingShieldAttempt()
        let firstAttempt = SharedAppGroup.currentPendingShieldAttempt

        SharedAppGroup.markPendingShieldAttempt()
        let newerAttempt = SharedAppGroup.currentPendingShieldAttempt

        guard let firstAttempt, let newerAttempt else {
            return XCTFail("Both pending shield attempts should be persisted.")
        }
        XCTAssertNotEqual(firstAttempt.id, newerAttempt.id)
        XCTAssertNil(
            SharedAppGroup.consumePendingShieldAttempt(matchingID: firstAttempt.id),
            "Finishing older async preparation must not consume a newer shield tap."
        )
        XCTAssertEqual(SharedAppGroup.currentPendingShieldAttempt?.id, newerAttempt.id)
        XCTAssertNotNil(SharedAppGroup.consumePendingShieldAttempt(matchingID: newerAttempt.id))
        XCTAssertNil(SharedAppGroup.currentPendingShieldAttempt)
    }

    @MainActor
    func testSelectionChangeInvalidatesPendingShieldAttemptConfiguration() {
        let initialSelection = Data("protected apps A and B".utf8)
        let updatedSelection = Data("protected app A".utf8)
        SharedAppGroup.publishScreenTimeSelectionData(initialSelection)
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        SharedAppGroup.markPendingShieldAttempt()
        let pendingRevision = SharedAppGroup.pendingShieldAttemptProtectionRevision

        SharedAppGroup.publishScreenTimeSelectionData(updatedSelection)

        let updatedSnapshot = SharedAppGroup.currentProtectionSnapshot()
        XCTAssertEqual(updatedSnapshot.screenTimeSelectionData, updatedSelection)
        XCTAssertNotEqual(pendingRevision, updatedSnapshot.configurationRevision)
    }

    @MainActor
    func testSelectionSemanticsUpgradeInvalidatesLegacyCategoryConfiguration() {
        let selection = Data("legacy category selection".utf8)
        SharedAppGroup.publishScreenTimeSelectionData(selection, semanticsVersion: 0)
        let legacyRevision = SharedAppGroup.currentProtectionSnapshot().configurationRevision

        SharedAppGroup.publishScreenTimeSelectionData(
            selection,
            semanticsVersion: SharedAppGroup.currentScreenTimeSelectionSemanticsVersion
        )

        let upgradedSnapshot = SharedAppGroup.currentProtectionSnapshot()
        XCTAssertEqual(
            upgradedSnapshot.screenTimeSelectionSemanticsVersion,
            SharedAppGroup.currentScreenTimeSelectionSemanticsVersion
        )
        XCTAssertNotEqual(upgradedSnapshot.configurationRevision, legacyRevision)
    }

    @MainActor
    func testProtectionIntentAndBreakExpirationPublishAsOneRevision() {
        let selection = Data("protected app selection".utf8)
        let expiration = Date().addingTimeInterval(300)
        SharedAppGroup.publishScreenTimeSelectionData(selection)

        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: expiration)

        let publishedSnapshot = SharedAppGroup.currentProtectionSnapshot()
        XCTAssertTrue(publishedSnapshot.desiredShieldActive)
        XCTAssertEqual(publishedSnapshot.unlockExpiration, expiration)
        XCTAssertEqual(publishedSnapshot.screenTimeSelectionData, selection)

        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: expiration)
        XCTAssertEqual(
            SharedAppGroup.currentProtectionSnapshot().revision,
            publishedSnapshot.revision,
            "Publishing the same state must not make an in-flight shield action stale."
        )
    }

    @MainActor
    func testPendingShieldAttemptIsBoundToProtectionRevision() {
        SharedAppGroup.publishScreenTimeSelectionData(Data("protected app selection".utf8))
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let activeRevision = SharedAppGroup.currentProtectionSnapshot().configurationRevision

        SharedAppGroup.markPendingShieldAttempt()

        XCTAssertEqual(SharedAppGroup.pendingShieldAttemptProtectionRevision, activeRevision)

        SharedAppGroup.publishUnlockExpiration(Date().addingTimeInterval(300))

        XCTAssertEqual(
            SharedAppGroup.pendingShieldAttemptProtectionRevision,
            SharedAppGroup.currentProtectionSnapshot().configurationRevision
        )
        XCTAssertNotEqual(
            SharedAppGroup.pendingShieldAttemptProtectionRevision,
            SharedAppGroup.currentProtectionSnapshot().revision
        )

        _ = SharedAppGroup.consumePendingShieldAttempt()
        XCTAssertNil(SharedAppGroup.pendingShieldAttemptProtectionRevision)
    }

    @MainActor
    func testExpiredBreakNormalizationKeepsPendingShieldAttemptCurrent() {
        SharedAppGroup.publishScreenTimeSelectionData(Data("protected app selection".utf8))
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: Date().addingTimeInterval(-1)
        )
        let expiredBreakRevision = SharedAppGroup.currentProtectionSnapshot().revision
        SharedAppGroup.markPendingShieldAttempt()

        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)

        let normalizedSnapshot = SharedAppGroup.currentProtectionSnapshot()
        XCTAssertNotEqual(normalizedSnapshot.revision, expiredBreakRevision)
        XCTAssertEqual(
            SharedAppGroup.pendingShieldAttemptProtectionRevision,
            normalizedSnapshot.configurationRevision
        )
    }

    @MainActor
    func testPendingShieldAttemptPredicateRejectsOffBreakAndChangedSelection() {
        let now = Date()
        SharedAppGroup.publishScreenTimeSelectionData(Data("selection A".utf8))
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        SharedAppGroup.markPendingShieldAttempt()
        let pendingRevision = SharedAppGroup.pendingShieldAttemptProtectionRevision

        let activeSnapshot = SharedAppGroup.currentProtectionSnapshot()
        XCTAssertTrue(
            activeSnapshot.acceptsPendingShieldAttempt(
                configurationRevision: pendingRevision,
                hasSelection: true,
                now: now
            )
        )

        SharedAppGroup.publishUnlockExpiration(now.addingTimeInterval(300))
        XCTAssertFalse(
            SharedAppGroup.currentProtectionSnapshot().acceptsPendingShieldAttempt(
                configurationRevision: pendingRevision,
                hasSelection: true,
                now: now
            )
        )

        SharedAppGroup.publishUnlockExpiration(now.addingTimeInterval(-1))
        XCTAssertTrue(
            SharedAppGroup.currentProtectionSnapshot().acceptsPendingShieldAttempt(
                configurationRevision: pendingRevision,
                hasSelection: true,
                now: now
            )
        )

        SharedAppGroup.publishScreenTimeSelectionData(Data("selection B".utf8))
        XCTAssertFalse(
            SharedAppGroup.currentProtectionSnapshot().acceptsPendingShieldAttempt(
                configurationRevision: pendingRevision,
                hasSelection: true,
                now: now
            )
        )

        SharedAppGroup.publishProtectionState(isActive: false, unlockExpiration: nil)
        XCTAssertFalse(
            SharedAppGroup.currentProtectionSnapshot().acceptsPendingShieldAttempt(
                configurationRevision: nil,
                hasSelection: true,
                now: now
            )
        )
    }

    @MainActor
    func testUnlockRelockExtensionDiagnosticsAreRecorded() {
        let intervalStart = Date().addingTimeInterval(-30)
        let expectedEnd = Date().addingTimeInterval(300)

        SharedAppGroup.markUnlockRelockMonitorScheduled(intervalStart: intervalStart, expectedEnd: expectedEnd)
        SharedAppGroup.markUnlockRelockExtensionIntervalStarted()
        SharedAppGroup.markUnlockRelockExtensionIntervalEnded(result: "relocked")

        let defaults = SharedAppGroup.defaults
        XCTAssertNotNil(defaults.object(forKey: SharedAppGroup.unlockRelockMonitorScheduledAtKey) as? Date)
        XCTAssertEqual(defaults.object(forKey: SharedAppGroup.unlockRelockMonitorIntervalStartKey) as? Date, intervalStart)
        XCTAssertEqual(defaults.object(forKey: SharedAppGroup.unlockRelockMonitorExpectedEndKey) as? Date, expectedEnd)
        XCTAssertEqual(defaults.integer(forKey: SharedAppGroup.unlockRelockExtensionIntervalStartCountKey), 1)
        XCTAssertEqual(defaults.integer(forKey: SharedAppGroup.unlockRelockExtensionIntervalEndCountKey), 1)
        XCTAssertEqual(defaults.string(forKey: SharedAppGroup.unlockRelockExtensionLastResultKey), "relocked")
        XCTAssertNotNil(defaults.object(forKey: SharedAppGroup.unlockRelockExtensionLastEventDateKey) as? Date)
    }

    @MainActor
    func testPendingShieldAttemptWithoutQuestionsShowsRecoveryNotice() {
        let store = CheckpointStore(defaults: defaults)
        store.goal = makeGoal()

        SharedAppGroup.markPendingShieldAttempt()

        XCTAssertNil(store.takePendingShieldSession())
        XCTAssertTrue(store.checkpointNotice?.contains("no questions are ready yet") ?? false)
        XCTAssertNil(store.pendingMembershipFeature)
        XCTAssertNil(store.takePendingShieldSession())
    }

    @MainActor
    func testManualCheckpointWithoutGoalShowsRecoveryNotice() {
        let store = CheckpointStore(defaults: defaults)

        XCTAssertNil(store.startManualCheckpointSession())
        XCTAssertEqual(store.checkpointNotice, "Create a goal before starting a practice set.")

        store.clearCheckpointNotice()
        XCTAssertNil(store.checkpointNotice)
    }

    @MainActor
    func testScreenTimeSelectionStartsEmpty() {
        let screenTime = ScreenTimeController(defaults: defaults)

        XCTAssertFalse(screenTime.hasSelection)
        XCTAssertEqual(screenTime.restrictedAppsSummary, "No protected apps selected")
    }

    func testProtectedAppsSelectionSummaryCountsOnlyEnforcedItems() {
        let currentSelection = ProtectedAppsSelectionSummary(
            applicationCount: 3,
            enforcedCategoryCount: 0,
            webDomainCount: 2
        )
        XCTAssertEqual(currentSelection.text, "3 apps, 2 sites selected")

        let legacySelection = ProtectedAppsSelectionSummary(
            applicationCount: 1,
            enforcedCategoryCount: 2,
            webDomainCount: 1
        )
        XCTAssertEqual(
            legacySelection.text,
            "1 app, 2 categories, 1 site selected"
        )

        let emptySelection = ProtectedAppsSelectionSummary(
            applicationCount: 0,
            enforcedCategoryCount: 0,
            webDomainCount: 0
        )
        XCTAssertEqual(emptySelection.text, "No protected apps selected")
    }

    @MainActor
    func testScreenTimeSummaryExcludesModernCategoryShortcutsButReportsLegacyEnforcement() throws {
        #if os(iOS) && canImport(FamilyControls)
        let applicationToken = try JSONDecoder().decode(
            ManagedSettings.ApplicationToken.self,
            from: Data(#"{"data":"AQIDBA=="}"#.utf8)
        )
        let categoryToken = try JSONDecoder().decode(
            ManagedSettings.ActivityCategoryToken.self,
            from: Data(#"{"data":"BQYHCA=="}"#.utf8)
        )
        let authorizer = FakeScreenTimeAuthorizer(authorizationStatus: .approved)
        let screenTime = ScreenTimeController(
            defaults: defaults,
            authorizer: authorizer
        )
        var currentSelection = FamilyActivitySelection(includeEntireCategory: true)
        currentSelection.applicationTokens = [applicationToken]
        currentSelection.categoryTokens = [categoryToken]

        XCTAssertTrue(screenTime.updateSelection(currentSelection))
        XCTAssertEqual(screenTime.restrictedAppsSummary, "1 app selected")
        XCTAssertFalse(screenTime.usesLegacyCategoryEnforcement)

        var legacySelection = FamilyActivitySelection(includeEntireCategory: true)
        legacySelection.categoryTokens = [categoryToken]
        SharedAppGroup.publishScreenTimeSelectionData(
            try JSONEncoder().encode(legacySelection),
            semanticsVersion: 0
        )
        let restoredLegacy = ScreenTimeController(
            defaults: defaults,
            authorizer: authorizer
        )
        XCTAssertTrue(restoredLegacy.hasSelection)
        XCTAssertTrue(restoredLegacy.usesLegacyCategoryEnforcement)
        XCTAssertEqual(restoredLegacy.restrictedAppsSummary, "1 category selected")
        #endif
    }

    func testProtectionSettingsControlsKeepEditorReachableAcrossStates() {
        let unavailable = ProtectionSettingsControlPresentation(
            isProtectionUnavailable: true,
            isRequestingAuthorization: false,
            requiresScreenTimeAuthorization: false,
            hasSelection: true,
            canStopBlocking: false
        )
        XCTAssertEqual(unavailable.layout, .unavailable)

        let requesting = ProtectionSettingsControlPresentation(
            isProtectionUnavailable: false,
            isRequestingAuthorization: true,
            requiresScreenTimeAuthorization: true,
            hasSelection: false,
            canStopBlocking: false
        )
        XCTAssertEqual(requesting.layout, .requestingAuthorization)

        let authorizationRequired = ProtectionSettingsControlPresentation(
            isProtectionUnavailable: false,
            isRequestingAuthorization: false,
            requiresScreenTimeAuthorization: true,
            hasSelection: true,
            canStopBlocking: false
        )
        XCTAssertEqual(authorizationRequired.layout, .authorizationRequired)

        let empty = ProtectionSettingsControlPresentation(
            isProtectionUnavailable: false,
            isRequestingAuthorization: false,
            requiresScreenTimeAuthorization: false,
            hasSelection: false,
            canStopBlocking: false
        )
        XCTAssertEqual(empty.layout, .chooseApps)

        let savedAndOff = ProtectionSettingsControlPresentation(
            isProtectionUnavailable: false,
            isRequestingAuthorization: false,
            requiresScreenTimeAuthorization: false,
            hasSelection: true,
            canStopBlocking: false
        )
        XCTAssertEqual(savedAndOff.layout, .startAndEditApps)

        let active = ProtectionSettingsControlPresentation(
            isProtectionUnavailable: false,
            isRequestingAuthorization: false,
            requiresScreenTimeAuthorization: false,
            hasSelection: true,
            canStopBlocking: true
        )
        XCTAssertEqual(active.layout, .editApps)
    }

    @MainActor
    func testProtectedAppsPickerCannotClearActiveProtectionIntent() throws {
        #if os(iOS) && canImport(FamilyControls)
        let screenTime = ScreenTimeController(defaults: defaults)
        let applicationToken = try JSONDecoder().decode(
            ManagedSettings.ApplicationToken.self,
            from: Data(#"{"data":"AQIDBA=="}"#.utf8)
        )
        var populatedSelection = FamilyActivitySelection(includeEntireCategory: true)
        populatedSelection.applicationTokens = [applicationToken]
        let emptySelection = FamilyActivitySelection(includeEntireCategory: true)
        let expectedMessage =
            "Protection requires at least one app or website. Turn it off in Settings before clearing the list."

        XCTAssertTrue(screenTime.updateSelection(populatedSelection))
        XCTAssertEqual(screenTime.selection, populatedSelection)
        XCTAssertEqual(screenTime.restrictedAppsSummary, "1 app selected")
        let persistedSelection = try XCTUnwrap(
            SharedAppGroup.screenTimeSelectionData()
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                FamilyActivitySelection.self,
                from: persistedSelection
            ),
            populatedSelection
        )

        screenTime.setupState = .shieldActive
        screenTime.isShieldingEnabled = true
        XCTAssertFalse(screenTime.updateSelection(emptySelection))
        XCTAssertTrue(screenTime.isShieldingEnabled)
        XCTAssertEqual(screenTime.selection, populatedSelection)
        XCTAssertEqual(screenTime.restrictedAppsSummary, "1 app selected")
        XCTAssertEqual(SharedAppGroup.screenTimeSelectionData(), persistedSelection)
        XCTAssertEqual(screenTime.lastErrorMessage, expectedMessage)
        XCTAssertEqual(screenTime.userFacingErrorMessage, expectedMessage)

        screenTime.lastErrorMessage = nil
        screenTime.setupState = .temporarilyUnlocked
        screenTime.isShieldingEnabled = false
        XCTAssertFalse(screenTime.updateSelection(emptySelection))
        XCTAssertEqual(screenTime.setupState, .temporarilyUnlocked)
        XCTAssertEqual(screenTime.selection, populatedSelection)
        XCTAssertEqual(SharedAppGroup.screenTimeSelectionData(), persistedSelection)
        XCTAssertEqual(screenTime.userFacingErrorMessage, expectedMessage)

        screenTime.lastErrorMessage = nil
        screenTime.setupState = .authorized
        XCTAssertTrue(screenTime.updateSelection(emptySelection))
        XCTAssertFalse(screenTime.hasSelection)
        XCTAssertEqual(screenTime.restrictedAppsSummary, "No protected apps selected")
        let clearedSelectionData = try XCTUnwrap(
            SharedAppGroup.screenTimeSelectionData()
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                FamilyActivitySelection.self,
                from: clearedSelectionData
            ),
            emptySelection
        )
        let restored = ScreenTimeController(
            defaults: defaults,
            authorizer: FakeScreenTimeAuthorizer(authorizationStatus: .approved)
        )
        XCTAssertFalse(restored.hasSelection)
        XCTAssertEqual(restored.restrictedAppsSummary, "No protected apps selected")
        #endif
    }

    @MainActor
    func testAuthorizationLossClearsSelectionAndPersistsProtectedAppReselectionRequirement() throws {
        #if os(iOS) && canImport(FamilyControls)
        let authorizer = FakeScreenTimeAuthorizer(authorizationStatus: .approved)
        let screenTime = ScreenTimeController(
            defaults: defaults,
            authorizer: authorizer
        )
        let validSelection = try makeValidProtectedAppSelection()

        XCTAssertTrue(screenTime.updateSelection(validSelection))
        XCTAssertTrue(screenTime.hasSelection)
        XCTAssertFalse(screenTime.requiresProtectedAppReselection)

        authorizer.authorizationStatus = .denied
        screenTime.refreshAuthorizationStatus()

        XCTAssertEqual(screenTime.authorizationState, .denied)
        XCTAssertFalse(screenTime.hasSelection)
        XCTAssertTrue(screenTime.selection.applicationTokens.isEmpty)
        XCTAssertTrue(screenTime.selection.categoryTokens.isEmpty)
        XCTAssertTrue(screenTime.selection.webDomainTokens.isEmpty)
        XCTAssertTrue(screenTime.requiresProtectedAppReselection)
        XCTAssertEqual(
            defaults.object(
                forKey: SharedAppGroup.screenTimeSelectionRecoveryRequiredKey
            ) as? Bool,
            true
        )

        let persistedSelectionData = try XCTUnwrap(
            SharedAppGroup.screenTimeSelectionData()
        )
        let persistedSelection = try JSONDecoder().decode(
            FamilyActivitySelection.self,
            from: persistedSelectionData
        )
        XCTAssertTrue(persistedSelection.applicationTokens.isEmpty)
        XCTAssertTrue(persistedSelection.categoryTokens.isEmpty)
        XCTAssertTrue(persistedSelection.webDomainTokens.isEmpty)
        #endif
    }

    @MainActor
    func testProtectedAppReselectionRequirementSurvivesControllerRecreation() throws {
        #if os(iOS) && canImport(FamilyControls)
        let screenTime = try makeControllerRequiringProtectedAppReselection()
        XCTAssertTrue(screenTime.requiresProtectedAppReselection)

        let recreated = ScreenTimeController(
            defaults: defaults,
            authorizer: FakeScreenTimeAuthorizer(authorizationStatus: .approved)
        )

        XCTAssertTrue(recreated.hasRequiredScreenTimeAuthorization)
        XCTAssertFalse(recreated.hasSelection)
        XCTAssertTrue(recreated.requiresProtectedAppReselection)
        XCTAssertEqual(
            defaults.object(
                forKey: SharedAppGroup.screenTimeSelectionRecoveryRequiredKey
            ) as? Bool,
            true
        )
        #endif
    }

    @MainActor
    func testPersistedRecoveryMarkerDiscardsAStaleSelectionAfterRelaunch() throws {
        #if os(iOS) && canImport(FamilyControls)
        let staleSelection = try makeValidProtectedAppSelection()
        SharedAppGroup.publishScreenTimeSelectionData(
            try JSONEncoder().encode(staleSelection)
        )
        defaults.set(
            true,
            forKey: SharedAppGroup.screenTimeSelectionRecoveryRequiredKey
        )

        let recreated = ScreenTimeController(
            defaults: defaults,
            authorizer: FakeScreenTimeAuthorizer(authorizationStatus: .approved)
        )

        XCTAssertTrue(recreated.hasRequiredScreenTimeAuthorization)
        XCTAssertFalse(recreated.hasSelection)
        XCTAssertTrue(recreated.requiresProtectedAppReselection)

        let persistedSelectionData = try XCTUnwrap(
            SharedAppGroup.screenTimeSelectionData()
        )
        let persistedSelection = try JSONDecoder().decode(
            FamilyActivitySelection.self,
            from: persistedSelectionData
        )
        XCTAssertTrue(persistedSelection.applicationTokens.isEmpty)
        XCTAssertTrue(persistedSelection.categoryTokens.isEmpty)
        XCTAssertTrue(persistedSelection.webDomainTokens.isEmpty)
        #endif
    }

    @MainActor
    func testChoosingValidSelectionClearsProtectedAppReselectionRequirement() throws {
        #if os(iOS) && canImport(FamilyControls)
        let screenTime = try makeControllerRequiringProtectedAppReselection()
        XCTAssertTrue(screenTime.requiresProtectedAppReselection)

        XCTAssertTrue(
            screenTime.updateSelection(try makeValidProtectedAppSelection())
        )

        XCTAssertTrue(screenTime.hasSelection)
        XCTAssertFalse(screenTime.requiresProtectedAppReselection)
        XCTAssertNil(
            defaults.object(
                forKey: SharedAppGroup.screenTimeSelectionRecoveryRequiredKey
            )
        )
        #endif
    }

    @MainActor
    func testEraseAllScreenTimeDataClearsProtectedAppReselectionRequirement() {
        defaults.set(
            true,
            forKey: SharedAppGroup.screenTimeSelectionRecoveryRequiredKey
        )
        var eraseCallCount = 0
        let screenTime = ScreenTimeController(
            defaults: defaults,
            authorizer: FakeScreenTimeAuthorizer(authorizationStatus: .approved),
            sharedDataEraser: { eraseCallCount += 1 }
        )
        XCTAssertTrue(screenTime.requiresProtectedAppReselection)

        screenTime.eraseAllData()

        XCTAssertEqual(eraseCallCount, 1)
        XCTAssertFalse(screenTime.requiresProtectedAppReselection)
        XCTAssertNil(
            defaults.object(
                forKey: SharedAppGroup.screenTimeSelectionRecoveryRequiredKey
            )
        )
    }

    @MainActor
    func testSuccessfulDeferredSharedEraseClearsLoadedProtectedAppReselectionRequirement() {
        UserDefaults.standard.set(
            true,
            forKey: ScreenTimeController.sharedDataEraseIncompleteKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: ScreenTimeController.sharedDataEraseIncompleteKey
            )
        }
        defaults.set(
            true,
            forKey: SharedAppGroup.screenTimeSelectionRecoveryRequiredKey
        )
        var eraseCallCount = 0

        let screenTime = ScreenTimeController(
            defaults: defaults,
            authorizer: FakeScreenTimeAuthorizer(authorizationStatus: .approved),
            sharedDataEraser: { eraseCallCount += 1 }
        )

        XCTAssertEqual(eraseCallCount, 1)
        XCTAssertFalse(screenTime.requiresSharedDataEraseRecovery)
        XCTAssertFalse(screenTime.requiresProtectedAppReselection)
        XCTAssertNil(
            defaults.object(
                forKey: SharedAppGroup.screenTimeSelectionRecoveryRequiredKey
            )
        )
        XCTAssertFalse(
            UserDefaults.standard.bool(
                forKey: ScreenTimeController.sharedDataEraseIncompleteKey
            )
        )
    }

    @MainActor
    func testScreenTimeAuthorizationBootstrapWaitsForExplicitRequest() async {
        let authorizer = FakeScreenTimeAuthorizer(
            authorizationStatus: .notDetermined,
            statusAfterRequest: .approved
        )
        let screenTime = ScreenTimeController(defaults: defaults, authorizer: authorizer)

        XCTAssertTrue(screenTime.requiresScreenTimeAuthorization)

        await screenTime.bootstrapAuthorizationIfNeeded()
        await screenTime.bootstrapAuthorizationIfNeeded()

        XCTAssertEqual(authorizer.requestCount, 0)
        XCTAssertTrue(screenTime.requiresScreenTimeAuthorization)
        XCTAssertEqual(screenTime.authorizationState, .notDetermined)

        await screenTime.requestAuthorization()

        XCTAssertEqual(authorizer.requestCount, 1)
        XCTAssertTrue(screenTime.hasRequiredScreenTimeAuthorization)
        XCTAssertFalse(screenTime.requiresScreenTimeAuthorization)
        XCTAssertEqual(screenTime.setupState, .authorized)
    }

    @MainActor
    func testApprovedScreenTimeAuthorizationSkipsBootstrapRequest() async {
        let authorizer = FakeScreenTimeAuthorizer(authorizationStatus: .approved)
        let screenTime = ScreenTimeController(defaults: defaults, authorizer: authorizer)

        XCTAssertTrue(screenTime.hasRequiredScreenTimeAuthorization)
        XCTAssertFalse(screenTime.requiresScreenTimeAuthorization)

        await screenTime.bootstrapAuthorizationIfNeeded()

        XCTAssertEqual(authorizer.requestCount, 0)
        XCTAssertEqual(screenTime.authorizationState, .approved)
        XCTAssertEqual(screenTime.setupState, .authorized)
    }

    @MainActor
    func testCanceledScreenTimeAuthorizationStaysGatedAndCanRetry() async {
        let authorizer = FakeScreenTimeAuthorizer(
            authorizationStatus: .notDetermined,
            statusAfterRequest: .approved,
            requestError: FakeScreenTimeAuthorizationError.canceled
        )
        let screenTime = ScreenTimeController(defaults: defaults, authorizer: authorizer)

        await screenTime.bootstrapAuthorizationIfNeeded()
        await screenTime.requestAuthorization()

        XCTAssertEqual(authorizer.requestCount, 1)
        XCTAssertTrue(screenTime.requiresScreenTimeAuthorization)
        XCTAssertEqual(screenTime.authorizationState, .failed)
        XCTAssertEqual(screenTime.setupState, .failed)

        authorizer.requestError = nil
        await screenTime.requestAuthorization()

        XCTAssertEqual(authorizer.requestCount, 2)
        XCTAssertTrue(screenTime.hasRequiredScreenTimeAuthorization)
        XCTAssertEqual(screenTime.setupState, .authorized)
    }

    @MainActor
    func testDeniedScreenTimeAuthorizationRemainsRequired() async {
        let authorizer = FakeScreenTimeAuthorizer(
            authorizationStatus: .notDetermined,
            statusAfterRequest: .denied
        )
        let screenTime = ScreenTimeController(defaults: defaults, authorizer: authorizer)

        await screenTime.bootstrapAuthorizationIfNeeded()
        await screenTime.requestAuthorization()

        XCTAssertEqual(authorizer.requestCount, 1)
        XCTAssertTrue(screenTime.requiresScreenTimeAuthorization)
        XCTAssertFalse(screenTime.hasRequiredScreenTimeAuthorization)
        XCTAssertEqual(screenTime.authorizationState, .denied)
        XCTAssertEqual(screenTime.setupState, .failed)
    }

    @MainActor
    func testScreenTimeApprovalWithDataAccessSatisfiesRequiredGate() async {
        let authorizer = FakeScreenTimeAuthorizer(
            authorizationStatus: .notDetermined,
            statusAfterRequest: .approvedWithDataAccess
        )
        let screenTime = ScreenTimeController(defaults: defaults, authorizer: authorizer)

        await screenTime.bootstrapAuthorizationIfNeeded()
        await screenTime.requestAuthorization()

        XCTAssertTrue(screenTime.hasRequiredScreenTimeAuthorization)
        XCTAssertFalse(screenTime.requiresScreenTimeAuthorization)
        XCTAssertEqual(screenTime.authorizationState, .approvedWithDataAccess)
        XCTAssertEqual(screenTime.setupState, .authorized)
    }

    @MainActor
    func testFailedSharedEraseBlocksAuthorizationSelectionAndProtectionWrites() async {
        UserDefaults.standard.set(
            true,
            forKey: ScreenTimeController.sharedDataEraseIncompleteKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: ScreenTimeController.sharedDataEraseIncompleteKey
            )
        }

        let authorizer = FakeScreenTimeAuthorizer(
            authorizationStatus: .approved
        )
        let screenTime = ScreenTimeController(
            defaults: defaults,
            authorizer: authorizer,
            sharedDataEraser: { throw FakeSharedDataEraseError.failed }
        )

        XCTAssertNotNil(screenTime.sharedDataEraseErrorMessage)
        XCTAssertTrue(screenTime.hasRequiredScreenTimeAuthorization)
        XCTAssertFalse(screenTime.requiresScreenTimeAuthorization)
        XCTAssertTrue(screenTime.requiresSharedDataEraseRecovery)

        await screenTime.requestAuthorization()
        screenTime.applyShield()

        XCTAssertEqual(authorizer.requestCount, 0)
        XCTAssertFalse(screenTime.isShieldingEnabled)
        XCTAssertTrue(
            UserDefaults.standard.bool(
                forKey: ScreenTimeController.sharedDataEraseIncompleteKey
            )
        )

        #if os(iOS) && canImport(FamilyControls)
        XCTAssertFalse(
            screenTime.updateSelection(
                FamilyActivitySelection(includeEntireCategory: true)
            )
        )
        #endif
    }

    @MainActor
    func testClearingShieldPreservesPersistedSelection() {
        let selectionData = Data("protected selection".utf8)
        SharedAppGroup.publishScreenTimeSelectionData(selectionData)
        let screenTime = ScreenTimeController(defaults: defaults)

        screenTime.clearShield()

        XCTAssertEqual(SharedAppGroup.screenTimeSelectionData(), selectionData)
    }

    @MainActor
    func testEraseAllScreenTimeDataClearsSelectionStateAndDiagnostics() {
        let selectionData = Data("protected selection".utf8)
        SharedAppGroup.publishScreenTimeSelectionData(selectionData)
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: Date().addingTimeInterval(300)
        )
        SharedAppGroup.markPendingShieldAttempt()
        SharedAppGroup.markShieldConfigurationRendered()
        SharedAppGroup.markUnlockRelockExtensionIntervalStarted()
        let screenTime = ScreenTimeController(defaults: defaults)

        screenTime.eraseAllData()

        XCTAssertFalse(screenTime.hasSelection)
        XCTAssertEqual(screenTime.restrictedAppsSummary, "No protected apps selected")
        XCTAssertNil(SharedAppGroup.screenTimeSelectionData())
        XCTAssertFalse(SharedAppGroup.desiredShieldActive)
        XCTAssertNil(SharedAppGroup.unlockExpiration)
        XCTAssertNil(SharedAppGroup.currentPendingShieldAttempt)
        XCTAssertEqual(SharedAppGroup.shieldConfigurationRenderCount, 0)
        XCTAssertEqual(SharedAppGroup.defaults.integer(forKey: SharedAppGroup.unlockRelockExtensionIntervalStartCountKey), 0)
    }

    @MainActor
    func testOffReconciliationClearsStaleBreakAndPendingAttempt() {
        SharedAppGroup.publishProtectionState(
            isActive: false,
            unlockExpiration: Date().addingTimeInterval(300)
        )
        SharedAppGroup.markPendingShieldAttempt()

        let screenTime = ScreenTimeController(defaults: defaults)

        XCTAssertFalse(screenTime.isShieldingEnabled)
        XCTAssertFalse(SharedAppGroup.desiredShieldActive)
        XCTAssertNil(SharedAppGroup.unlockExpiration)
        XCTAssertNil(SharedAppGroup.pendingShieldAttemptDate)
    }

    @MainActor
    func testMissingSelectionCannotKeepProtectionOrBreakIntentActive() {
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: Date().addingTimeInterval(300)
        )

        let screenTime = ScreenTimeController(defaults: defaults)

        XCTAssertFalse(screenTime.hasSelection)
        XCTAssertFalse(screenTime.isShieldingEnabled)
        XCTAssertNotEqual(screenTime.setupState, .temporarilyUnlocked)
        XCTAssertNotEqual(
            screenTime.lastErrorMessage,
            "Screen Time access is not approved yet. Allow Screen Time access before starting app protection."
        )
        XCTAssertFalse(SharedAppGroup.desiredShieldActive)
        XCTAssertNil(SharedAppGroup.unlockExpiration)
    }

    @MainActor
    func testProtectionStatusUsesAppliedControllerState() {
        let screenTime = ScreenTimeController(defaults: defaults)

        screenTime.setupState = .shieldActive
        screenTime.isShieldingEnabled = false
        XCTAssertEqual(screenTime.userFacingProtectionStatus, "Off")

        screenTime.isShieldingEnabled = true
        XCTAssertEqual(screenTime.userFacingProtectionStatus, "On")

        screenTime.isShieldingEnabled = false
        screenTime.setupState = .temporarilyUnlocked
        XCTAssertEqual(screenTime.userFacingProtectionStatus, "Break in progress")
    }

    @MainActor
    func testScreenTimeSelectionDefaultsToWholeCategoryMode() {
        #if os(iOS) && canImport(FamilyControls)
        let screenTime = ScreenTimeController(defaults: defaults)

        XCTAssertTrue(screenTime.selection.includeEntireCategory)
        #endif
    }

    @MainActor
    func testRestoredScreenTimeSelectionMigratesToWholeCategoryMode() {
        #if os(iOS) && canImport(FamilyControls)
        let legacySelection = FamilyActivitySelection()
        let data = try? JSONEncoder().encode(legacySelection)
        if let data {
            SharedAppGroup.publishScreenTimeSelectionData(data, semanticsVersion: 0)
        }

        let screenTime = ScreenTimeController(defaults: defaults)

        XCTAssertTrue(screenTime.selection.includeEntireCategory)
        #endif
    }

    @MainActor
    func testApplyShieldWithoutSelectionShowsError() {
        let screenTime = ScreenTimeController(defaults: defaults)

        screenTime.applyShield()

        XCTAssertFalse(screenTime.isShieldingEnabled)
        XCTAssertEqual(
            screenTime.lastErrorMessage,
            "Choose at least one protected app or website before starting app protection."
        )
        XCTAssertFalse(SharedAppGroup.desiredShieldActive)
    }

    @MainActor
    func testStarterAllowsAdvancedStrictnessChanges() {
        let store = CheckpointStore(defaults: defaults)

        store.updateQuestionsPerSession(8)
        store.updateRequiredCorrectAnswers(7)

        XCTAssertEqual(store.unlockPolicy.questionsPerSession, 8)
        XCTAssertEqual(store.unlockPolicy.requiredCorrectAnswers, 7)
    }

    #if os(iOS) && canImport(FamilyControls)
    @MainActor
    private func makeControllerRequiringProtectedAppReselection() throws -> ScreenTimeController {
        let authorizer = FakeScreenTimeAuthorizer(authorizationStatus: .approved)
        let screenTime = ScreenTimeController(
            defaults: defaults,
            authorizer: authorizer
        )
        XCTAssertTrue(
            screenTime.updateSelection(try makeValidProtectedAppSelection())
        )

        authorizer.authorizationStatus = .denied
        screenTime.refreshAuthorizationStatus()

        XCTAssertFalse(screenTime.hasSelection)
        return screenTime
    }

    private func makeValidProtectedAppSelection() throws -> FamilyActivitySelection {
        let applicationToken = try JSONDecoder().decode(
            ManagedSettings.ApplicationToken.self,
            from: Data(#"{"data":"AQIDBA=="}"#.utf8)
        )
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        selection.applicationTokens = [applicationToken]
        return selection
    }
    #endif

}

private enum FakeScreenTimeAuthorizationError: Error {
    case canceled
}

private enum FakeSharedDataEraseError: Error {
    case failed
}

@MainActor
private final class FakeScreenTimeAuthorizer: ScreenTimeAuthorizing {
    var authorizationStatus: ScreenTimeAuthorizationStatus
    var statusAfterRequest: ScreenTimeAuthorizationStatus?
    var requestError: (any Error)?
    private(set) var requestCount = 0

    init(
        authorizationStatus: ScreenTimeAuthorizationStatus,
        statusAfterRequest: ScreenTimeAuthorizationStatus? = nil,
        requestError: (any Error)? = nil
    ) {
        self.authorizationStatus = authorizationStatus
        self.statusAfterRequest = statusAfterRequest
        self.requestError = requestError
    }

    func requestAuthorization() async throws {
        requestCount += 1

        if let requestError {
            throw requestError
        }

        if let statusAfterRequest {
            authorizationStatus = statusAfterRequest
        }
    }
}
