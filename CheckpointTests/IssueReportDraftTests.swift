import Foundation
import XCTest
@testable import Checkpoint

final class IssueReportDraftTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var persistenceDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "IssueReportDraftTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        persistenceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CheckpointIssueReportDraftTests-\(UUID().uuidString)", isDirectory: true)
        resetSharedAppGroupState()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: persistenceDirectory)
        resetSharedAppGroupState()
        defaults = nil
        suiteName = nil
        persistenceDirectory = nil
        super.tearDown()
    }

    @MainActor
    func testDraftMessageValidationTrimsAndAcceptsExactlyOneThousandCharacters() throws {
        XCTAssertEqual(CheckpointStore.maximumIssueReportMessageLength, 1_000)

        let goal = makeInterviewGoal(title: "Validation goal")
        let store = makeStore(goal: goal)

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .generalFeedback,
                message: "  \n\t  ",
                includesCurrentGoal: false,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            .emptyMessage
        )
        XCTAssertTrue(store.issueReportDrafts.isEmpty)

        let maximumLengthMessage = String(
            repeating: "x",
            count: CheckpointStore.maximumIssueReportMessageLength
        )
        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .questionIssue,
                message: " \(maximumLengthMessage) \n",
                includesCurrentGoal: false,
                createdAt: Date(timeIntervalSince1970: 200)
            ),
            .saved
        )
        XCTAssertEqual(try XCTUnwrap(store.issueReportDrafts.first).message, maximumLengthMessage)
        XCTAssertEqual(store.issueReportDrafts.first?.message.count, 1_000)

        let overLimitMessage = String(
            repeating: "y",
            count: CheckpointStore.maximumIssueReportMessageLength + 1
        )
        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .appBlocking,
                message: overLimitMessage,
                includesCurrentGoal: false,
                createdAt: Date(timeIntervalSince1970: 300)
            ),
            .messageTooLong
        )
        XCTAssertEqual(store.issueReportDrafts.count, 1)
        XCTAssertEqual(store.issueReportDrafts.first?.message, maximumLengthMessage)
    }

    @MainActor
    func testDraftOmitsCurrentGoalByDefaultAndIncludesItOnlyWhenRequested() throws {
        let goal = makeInterviewGoal(title: "Private goal context")
        let store = makeStore(goal: goal)

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .generalFeedback,
                message: "Keep this feedback independent of my goal.",
                includesCurrentGoal: false,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            .saved
        )
        let unscopedDraft = try XCTUnwrap(
            store.issueReportDrafts.first { $0.message.hasPrefix("Keep this") }
        )
        XCTAssertNil(unscopedDraft.goalID)
        XCTAssertEqual(unscopedDraft.goalTitle, "")
        XCTAssertEqual(unscopedDraft.includesGoalContext, false)
        XCTAssertEqual(unscopedDraft.contact, "")

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .goalSetup,
                message: "Include the current goal with this draft.",
                includesCurrentGoal: true,
                createdAt: Date(timeIntervalSince1970: 200)
            ),
            .saved
        )
        let scopedDraft = try XCTUnwrap(
            store.issueReportDrafts.first { $0.message.hasPrefix("Include the current") }
        )
        XCTAssertEqual(scopedDraft.goalID, goal.id)
        XCTAssertEqual(scopedDraft.goalTitle, goal.title)
        XCTAssertEqual(scopedDraft.includesGoalContext, true)
        XCTAssertEqual(scopedDraft.contact, "")
    }

    @MainActor
    func testDraftsRoundTripThroughFileBackedPersistence() throws {
        let goal = makeInterviewGoal(title: "Persist draft goal")
        let store = makeStore(goal: goal)

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .membership,
                message: "First persisted draft",
                includesCurrentGoal: false,
                createdAt: Date(timeIntervalSince1970: 1_000)
            ),
            .saved
        )
        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .questionIssue,
                message: "Second persisted draft",
                includesCurrentGoal: true,
                createdAt: Date(timeIntervalSince1970: 2_000)
            ),
            .saved
        )
        let expectedDrafts = store.issueReportDrafts

        let restoredStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )

        XCTAssertEqual(restoredStore.issueReportDrafts, expectedDrafts)
        XCTAssertEqual(restoredStore.issueReportCount, expectedDrafts.count)
        XCTAssertEqual(restoredStore.issueReportDrafts.map(\.message), [
            "Second persisted draft",
            "First persisted draft"
        ])
    }

    @MainActor
    func testLegacyDraftMigrationScrubsUnconsentedGoalContextFromPrimaryAndBackup() throws {
        let goal = makeInterviewGoal(title: "Legacy private goal")
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .generalFeedback,
                message: "Legacy draft",
                includesCurrentGoal: true,
                createdAt: Date(timeIntervalSince1970: 1_000)
            ),
            .saved
        )

        let primaryKey = AppSnapshotPersistence.primaryDefaultsKey
        let backupKey = AppSnapshotPersistence.backupDefaultsKey
        let encodedEnvelope = try XCTUnwrap(defaults.data(forKey: primaryKey))
        var envelopeObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedEnvelope) as? [String: Any]
        )
        var snapshotObject = try XCTUnwrap(envelopeObject["snapshot"] as? [String: Any])
        var reports = try XCTUnwrap(snapshotObject["issueReports"] as? [[String: Any]])
        XCTAssertNotNil(reports[0].removeValue(forKey: "includesGoalContext"))
        reports[0]["contact"] = "legacy@example.com"
        snapshotObject["issueReports"] = reports
        envelopeObject["snapshot"] = snapshotObject
        let legacyEnvelope = try JSONSerialization.data(withJSONObject: envelopeObject)
        defaults.set(legacyEnvelope, forKey: primaryKey)
        defaults.set(legacyEnvelope, forKey: backupKey)

        let restoredStore = CheckpointStore(defaults: defaults)
        let migratedDraft = try XCTUnwrap(restoredStore.issueReportDrafts.first)
        XCTAssertEqual(migratedDraft.includesGoalContext, false)
        XCTAssertNil(migratedDraft.goalID)
        XCTAssertEqual(migratedDraft.goalTitle, "")
        XCTAssertEqual(migratedDraft.contact, "")

        for key in [primaryKey, backupKey] {
            let data = try XCTUnwrap(defaults.data(forKey: key))
            let envelope = try JSONDecoder().decode(AppSnapshotEnvelope.self, from: data)
            let persistedDraft = try XCTUnwrap(envelope.snapshot.issueReports?.first)
            XCTAssertEqual(persistedDraft.includesGoalContext, false, key)
            XCTAssertNil(persistedDraft.goalID, key)
            XCTAssertEqual(persistedDraft.goalTitle, "", key)
            XCTAssertEqual(persistedDraft.contact, "", key)
        }
    }

    @MainActor
    func testInitialBackupProvisionFailureDoesNotReportCommittedPrimaryAsFailed() throws {
        let goal = makeInterviewGoal(title: "Primary commit goal")
        let store = makeStore(goal: goal)
        try FileManager.default.createDirectory(
            at: persistenceDirectory,
            withIntermediateDirectories: true
        )
        let blockedBackupURL = persistenceDirectory.appendingPathComponent(
            AppSnapshotPersistence.backupFileName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: blockedBackupURL,
            withIntermediateDirectories: false
        )

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .generalFeedback,
                message: "Committed without an initial recovery copy",
                includesCurrentGoal: false,
                createdAt: Date(timeIntervalSince1970: 1_000)
            ),
            .saved
        )
        XCTAssertEqual(store.issueReportDrafts.count, 1)

        let restoredStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        XCTAssertEqual(
            restoredStore.issueReportDrafts.map(\.message),
            ["Committed without an initial recovery copy"]
        )
    }

    @MainActor
    func testFailedDraftAddRestoresPreviousInMemoryDrafts() throws {
        try Data("not a directory".utf8).write(to: persistenceDirectory)
        let goal = makeInterviewGoal(title: "Failed add goal")
        let store = makeStore(goal: goal)
        let existingDraft = makeDraft(
            id: deterministicUUID(1),
            message: "Keep existing draft",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        store.issueReports = [existingDraft]

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .generalFeedback,
                message: "This write must roll back",
                includesCurrentGoal: true,
                createdAt: Date(timeIntervalSince1970: 200)
            ),
            .persistenceFailed
        )
        XCTAssertEqual(store.issueReports, [existingDraft])
        XCTAssertEqual(store.issueReportDrafts, [existingDraft])
        XCTAssertNotNil(store.persistenceRecoveryMessage)
    }

    @MainActor
    func testFailedDraftDeleteRestoresPreviousInMemoryDrafts() throws {
        try Data("not a directory".utf8).write(to: persistenceDirectory)
        let goal = makeInterviewGoal(title: "Failed delete goal")
        let store = makeStore(goal: goal)
        let olderDraft = makeDraft(
            id: deterministicUUID(1),
            message: "Older draft",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newerDraft = makeDraft(
            id: deterministicUUID(2),
            message: "Newer draft",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let originalDrafts = [olderDraft, newerDraft]
        store.issueReports = originalDrafts

        XCTAssertFalse(store.deleteIssueReportDraft(id: newerDraft.id))
        XCTAssertEqual(store.issueReports, originalDrafts)
        XCTAssertEqual(store.issueReportDrafts, [newerDraft, olderDraft])
        XCTAssertNotNil(store.persistenceRecoveryMessage)
    }

    @MainActor
    func testDraftDeletionPersistsAcrossRelaunch() throws {
        let goal = makeInterviewGoal(title: "Delete draft goal")
        let store = makeStore(goal: goal)
        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .generalFeedback,
                message: "Delete this draft",
                includesCurrentGoal: false,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            .saved
        )
        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .membership,
                message: "Keep this draft",
                includesCurrentGoal: false,
                createdAt: Date(timeIntervalSince1970: 200)
            ),
            .saved
        )
        let draftToDelete = try XCTUnwrap(
            store.issueReportDrafts.first { $0.message == "Delete this draft" }
        )

        XCTAssertTrue(store.deleteIssueReportDraft(id: draftToDelete.id))
        XCTAssertEqual(store.issueReportDrafts.map(\.message), ["Keep this draft"])

        let restoredStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        XCTAssertEqual(restoredStore.issueReportDrafts.map(\.message), ["Keep this draft"])
    }

    @MainActor
    func testDraftRetentionKeepsNewestOneHundredWithDeterministicUUIDTieBreaks() throws {
        XCTAssertEqual(CheckpointStore.maximumStoredIssueReportCount, 100)

        let goal = makeInterviewGoal(title: "Retention goal")
        let store = makeStore(goal: goal)
        let tiedDate = Date(timeIntervalSince1970: 10_000)
        let tiedDrafts = (1...CheckpointStore.maximumStoredIssueReportCount).map { index in
            makeDraft(
                id: deterministicUUID(index),
                message: "Tied draft \(index)",
                createdAt: tiedDate
            )
        }
        let originalReverseOrder = Array(tiedDrafts.reversed())
        store.issueReports = originalReverseOrder

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .generalFeedback,
                message: "Too old to retain",
                includesCurrentGoal: false,
                createdAt: tiedDate.addingTimeInterval(-1)
            ),
            .notRetained
        )
        XCTAssertEqual(store.issueReports, originalReverseOrder)

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .generalFeedback,
                message: "Newest retained draft",
                includesCurrentGoal: false,
                createdAt: tiedDate.addingTimeInterval(1)
            ),
            .saved
        )

        let retainedDrafts = store.issueReportDrafts
        XCTAssertEqual(retainedDrafts.count, CheckpointStore.maximumStoredIssueReportCount)
        XCTAssertEqual(retainedDrafts.first?.message, "Newest retained draft")
        XCTAssertFalse(retainedDrafts.contains { $0.id == deterministicUUID(100) })
        XCTAssertEqual(
            retainedDrafts.dropFirst().map(\.id),
            tiedDrafts.prefix(CheckpointStore.maximumStoredIssueReportCount - 1).map(\.id)
        )

        let restoredStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        XCTAssertEqual(restoredStore.issueReportDrafts, retainedDrafts)
    }

    @MainActor
    func testDraftLedgerRemainsGlobalAcrossActiveGoalSwitches() throws {
        let firstGoal = makeInterviewGoal(title: "First active goal")
        let secondGoal = makeInterviewGoal(title: "Second active goal")
        let unavailableEngine = HybridQuestionEngine(
            backendEngine: UnavailableQuestionEngine(provider: .backend),
            appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(
            questionEngine: unavailableEngine,
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        store.goal = firstGoal
        store.goalProfiles = [firstGoal, secondGoal]
        store.membershipTier = .member

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .goalSetup,
                message: "Draft attached to the first goal",
                includesCurrentGoal: true,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            .saved
        )
        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .generalFeedback,
                message: "Global draft with no goal context",
                includesCurrentGoal: false,
                createdAt: Date(timeIntervalSince1970: 200)
            ),
            .saved
        )
        let expectedDrafts = store.issueReportDrafts

        XCTAssertTrue(store.switchActiveGoal(to: secondGoal.id))
        XCTAssertEqual(store.goal?.id, secondGoal.id)
        XCTAssertEqual(store.issueReportDrafts, expectedDrafts)
        XCTAssertEqual(
            store.issueReportDrafts.first { $0.goalID != nil }?.goalID,
            firstGoal.id
        )

        XCTAssertTrue(store.switchActiveGoal(to: firstGoal.id))
        XCTAssertEqual(store.issueReportDrafts, expectedDrafts)
    }

    @MainActor
    func testEraseAllDataClearsDraftsInMemoryAndOnRelaunch() {
        let goal = makeInterviewGoal(title: "Erase drafts goal")
        let store = makeStore(goal: goal)
        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .appBlocking,
                message: "Erase this local draft",
                includesCurrentGoal: true,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            .saved
        )
        XCTAssertFalse(store.issueReportDrafts.isEmpty)

        store.eraseAllData(backendIdentityDefaults: defaults)

        XCTAssertTrue(store.issueReports.isEmpty)
        XCTAssertTrue(store.issueReportDrafts.isEmpty)
        XCTAssertTrue(store.hasNoPersistedAppData)

        let restoredStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        XCTAssertTrue(restoredStore.issueReportDrafts.isEmpty)
        XCTAssertTrue(restoredStore.hasNoPersistedAppData)
    }

    @MainActor
    private func makeStore(goal: Goal) -> CheckpointStore {
        let store = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        store.goal = goal
        store.goalProfiles = [goal]
        return store
    }

    private func makeDraft(
        id: UUID,
        message: String,
        createdAt: Date
    ) -> UserIssueReport {
        UserIssueReport(
            id: id,
            goalID: nil,
            goalTitle: "",
            includesGoalContext: false,
            category: .generalFeedback,
            message: message,
            contact: "",
            createdAt: createdAt
        )
    }

    private func deterministicUUID(_ value: Int) -> UUID {
        let suffix = String(format: "%012d", value)
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }
}
