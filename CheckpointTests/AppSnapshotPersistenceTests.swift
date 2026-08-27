import XCTest
@testable import Checkpoint

// MARK: - Snapshot persistence

final class AppSnapshotPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var persistenceDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "AppSnapshotPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        persistenceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CheckpointPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        UserDefaults.standard.removeObject(forKey: ScreenTimeController.sharedDataEraseIncompleteKey)
        resetSharedAppGroupState()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: persistenceDirectory)
        UserDefaults.standard.removeObject(forKey: ScreenTimeController.sharedDataEraseIncompleteKey)
        resetSharedAppGroupState()
        defaults = nil
        suiteName = nil
        persistenceDirectory = nil
        super.tearDown()
    }

    @MainActor
    func testFailedSnapshotWriteNeverPublishesVolatileQuestionReadiness() throws {
        try Data("not a directory".utf8).write(to: persistenceDirectory)
        let goal = makeGoal()
        let store = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0) }

        store.updateRequiredCorrectAnswers(4)

        XCTAssertTrue(store.hasReadyCheckpointSet)
        XCTAssertNotEqual(SharedAppGroup.checkpointReady, true)
        XCTAssertNotNil(store.persistenceRecoveryMessage)
    }

    @MainActor
    func testSuccessfulSnapshotLoadSeedsSharedQuestionReadiness() {
        let goal = makeGoal()
        let originalStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        originalStore.goal = goal
        originalStore.goalProfiles = [goal]
        originalStore.questions = (1...5).map { makeQuestion(goal: goal, index: $0) }
        originalStore.updateRequiredCorrectAnswers(4)
        SharedAppGroup.defaults.removeObject(forKey: SharedAppGroup.checkpointReadyKey)

        let restoredStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )

        XCTAssertTrue(restoredStore.hasReadyCheckpointSet)
        XCTAssertEqual(SharedAppGroup.checkpointReady, true)
    }

    @MainActor
    func testCorruptPrimaryRecoversFromAtomicBackup() throws {
        let goal = makeGoal()
        let store = makeFileBackedStore(goal: goal)
        let primaryURL = persistenceDirectory.appendingPathComponent(AppSnapshotPersistence.primaryFileName)
        let backupURL = persistenceDirectory.appendingPathComponent(AppSnapshotPersistence.backupFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        try Data("corrupt primary".utf8).write(to: primaryURL, options: [.atomic])

        let recoveredStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )

        XCTAssertEqual(recoveredStore.goal?.id, goal.id)
        XCTAssertNotNil(recoveredStore.persistenceRecoveryMessage)
        let restoredData = try Data(contentsOf: primaryURL)
        XCTAssertNoThrow(try JSONDecoder().decode(AppSnapshotEnvelope.self, from: restoredData))

        store.eraseAllData(backendIdentityDefaults: defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistenceDirectory.path))
    }

    @MainActor
    func testLegacyUserDefaultsSnapshotMigratesOnlyAfterVerifiedFileWrite() throws {
        let goal = makeGoal()
        let defaultsBackedStore = CheckpointStore(defaults: defaults)
        defaultsBackedStore.goal = goal
        defaultsBackedStore.goalProfiles = [goal]
        defaultsBackedStore.updateUnlockMinutes(10)
        let envelopeData = try XCTUnwrap(
            defaults.data(forKey: AppSnapshotPersistence.primaryDefaultsKey)
        )
        let envelope = try JSONDecoder().decode(AppSnapshotEnvelope.self, from: envelopeData)
        var oversizedLegacySnapshot = envelope.snapshot
        oversizedLegacySnapshot.questions = (0...CheckpointStore.maximumStoredQuestionCountPerGoal).map {
            makeQuestion(
                goal: goal,
                index: $0,
                status: .retired,
                timesAsked: 2,
                lastAskedAt: Date(timeIntervalSince1970: TimeInterval($0))
            )
        }
        oversizedLegacySnapshot.questionGenerationTraces = (
            0...CheckpointStore.maximumQuestionGenerationTraceCount
        ).map { makeGenerationTrace(goal: goal, index: $0) }
        defaults.removeObject(forKey: AppSnapshotPersistence.primaryDefaultsKey)
        defaults.removeObject(forKey: AppSnapshotPersistence.backupDefaultsKey)
        defaults.set(
            try JSONEncoder().encode(oversizedLegacySnapshot),
            forKey: AppSnapshotPersistence.legacySnapshotKey
        )

        let migratedStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )

        XCTAssertEqual(migratedStore.goal?.id, goal.id)
        XCTAssertNil(defaults.data(forKey: AppSnapshotPersistence.legacySnapshotKey))
        let primaryURL = persistenceDirectory
            .appendingPathComponent(AppSnapshotPersistence.primaryFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))
        let migratedEnvelope = try JSONDecoder().decode(
            AppSnapshotEnvelope.self,
            from: Data(contentsOf: primaryURL)
        )
        XCTAssertEqual(
            migratedEnvelope.snapshot.questions.count,
            CheckpointStore.maximumStoredQuestionCountPerGoal
        )
        XCTAssertEqual(
            migratedStore.questionGenerationTraces.count,
            CheckpointStore.maximumQuestionGenerationTraceCount
        )
        XCTAssertEqual(
            migratedEnvelope.snapshot.questionGenerationTraces?.count,
            CheckpointStore.maximumQuestionGenerationTraceCount
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: persistenceDirectory
                    .appendingPathComponent(AppSnapshotPersistence.backupFileName)
                    .path
            )
        )
    }

    @MainActor
    func testLegacySnapshotRemainsWhenMigrationWriteFails() throws {
        let goal = makeGoal()
        let defaultsBackedStore = CheckpointStore(defaults: defaults)
        defaultsBackedStore.goal = goal
        defaultsBackedStore.goalProfiles = [goal]
        defaultsBackedStore.updateUnlockMinutes(10)
        let envelopeData = try XCTUnwrap(
            defaults.data(forKey: AppSnapshotPersistence.primaryDefaultsKey)
        )
        let envelope = try JSONDecoder().decode(AppSnapshotEnvelope.self, from: envelopeData)
        defaults.removeObject(forKey: AppSnapshotPersistence.primaryDefaultsKey)
        defaults.removeObject(forKey: AppSnapshotPersistence.backupDefaultsKey)
        defaults.set(
            try JSONEncoder().encode(envelope.snapshot),
            forKey: AppSnapshotPersistence.legacySnapshotKey
        )

        // A regular file at the requested directory path forces createDirectory
        // and every subsequent atomic snapshot write to fail.
        try Data("not a directory".utf8).write(to: persistenceDirectory)
        let recoveredStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )

        XCTAssertEqual(recoveredStore.goal?.id, goal.id)
        XCTAssertNotNil(recoveredStore.persistenceRecoveryMessage)
        XCTAssertNotNil(defaults.data(forKey: AppSnapshotPersistence.legacySnapshotKey))
    }

    @MainActor
    func testCorruptPrimaryAndBackupShowsVisibleFailure() throws {
        try FileManager.default.createDirectory(
            at: persistenceDirectory,
            withIntermediateDirectories: true
        )
        try Data("corrupt primary".utf8).write(
            to: persistenceDirectory.appendingPathComponent(AppSnapshotPersistence.primaryFileName)
        )
        try Data("corrupt backup".utf8).write(
            to: persistenceDirectory.appendingPathComponent(AppSnapshotPersistence.backupFileName)
        )

        let store = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )

        XCTAssertNil(store.goal)
        XCTAssertTrue(store.isOnboardingPresented)
        XCTAssertTrue(store.persistenceRecoveryMessage?.contains("could not read") == true)
        XCTAssertEqual(store.checkpointNotice, store.persistenceRecoveryMessage)
    }

    @MainActor
    func testRetentionKeepsUsableQuestionsBeforeNewestRetiredQuestions() {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        let usableQuestions = (1...10).map {
            makeQuestion(goal: goal, index: $0, status: .new)
        }
        let retiredQuestions = (0..<500).map { index in
            makeQuestion(
                goal: goal,
                index: index + 100,
                status: .retired,
                timesAsked: 2,
                lastAskedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        store.questions = retiredQuestions + usableQuestions

        store.updateUnlockMinutes(10)

        XCTAssertEqual(store.questions.count, CheckpointStore.maximumStoredQuestionCountPerGoal)
        XCTAssertTrue(Set(usableQuestions.map(\.id)).isSubset(of: Set(store.questions.map(\.id))))
        let retainedRetiredDates = store.questions
            .filter { $0.status == .retired }
            .compactMap(\.lastAskedAt)
        XCTAssertEqual(retainedRetiredDates.count, 490)
        XCTAssertEqual(retainedRetiredDates.min(), Date(timeIntervalSince1970: 10))
    }

    @MainActor
    func testAttemptRetentionKeepsNewestRecordsPerGoal() {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        let attempts = (0...CheckpointStore.maximumStoredAttemptCountPerGoal).map { index in
            makeAttempt(
                goal: goal,
                result: .correct,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }.reversed()
        store.attempts = Array(attempts)

        store.updateUnlockMinutes(10)

        XCTAssertEqual(store.attempts.count, CheckpointStore.maximumStoredAttemptCountPerGoal)
        XCTAssertEqual(
            store.attempts.last?.createdAt,
            Date(timeIntervalSince1970: 1)
        )
    }

    @MainActor
    func testPostEraseReconciliationDoesNotRecreateLocalOrAppGroupState() {
        let goal = makeGoal()
        let store = makeFileBackedStore(goal: goal)
        store.startUnlockSession(minutes: 10)
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        SharedAppGroup.publishShieldContext(goalTitle: goal.title, promptPreview: nil)
        let screenTime = ScreenTimeController()

        XCTAssertTrue(FileManager.default.fileExists(atPath: persistenceDirectory.path))
        XCTAssertTrue(SharedAppGroup.hasPersistedData)

        screenTime.eraseAllData()
        store.eraseAllData(backendIdentityDefaults: defaults)

        // Equivalent to RootView's goal/selection reconciliation plus the
        // entitlement refresh that can arrive immediately after a reset.
        store.clearUnlockSession()
        screenTime.clearShield()
        store.updateMembershipTier(.member)

        XCTAssertTrue(store.hasNoPersistedAppData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistenceDirectory.path))
        XCTAssertFalse(SharedAppGroup.hasPersistedData)

        let reloadedStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        let reloadedScreenTime = ScreenTimeController()
        reloadedStore.clearUnlockSession()
        reloadedScreenTime.clearShield()

        XCTAssertTrue(reloadedStore.hasNoPersistedAppData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistenceDirectory.path))
        XCTAssertFalse(SharedAppGroup.hasPersistedData)
    }

    @MainActor
    func testScreenTimeEraseClearsKnownStandardDefaultsFallbackValues() {
        let standardDefaults = UserDefaults.standard
        let keys = [
            SharedAppGroup.shieldGoalTitleKey,
            SharedAppGroup.desiredShieldActiveKey,
            SharedAppGroup.screenTimeSelectionKey,
            SharedAppGroup.pendingShieldAttemptDateKey
        ]
        defer {
            for key in keys {
                standardDefaults.removeObject(forKey: key)
            }
        }

        standardDefaults.set("Fallback goal", forKey: SharedAppGroup.shieldGoalTitleKey)
        standardDefaults.set(true, forKey: SharedAppGroup.desiredShieldActiveKey)
        standardDefaults.set(Data("fallback selection".utf8), forKey: SharedAppGroup.screenTimeSelectionKey)
        standardDefaults.set(Date(), forKey: SharedAppGroup.pendingShieldAttemptDateKey)

        XCTAssertTrue(SharedAppGroup.hasPersistedData)

        let screenTime = ScreenTimeController()
        screenTime.eraseAllData()

        for key in keys {
            XCTAssertNil(standardDefaults.object(forKey: key))
        }
        XCTAssertNil(screenTime.sharedDataEraseErrorMessage)
        XCTAssertFalse(
            standardDefaults.bool(forKey: ScreenTimeController.sharedDataEraseIncompleteKey)
        )
        XCTAssertFalse(SharedAppGroup.hasPersistedData)
    }

    @MainActor
    func testIncompleteSharedEraseMarkerRetriesBeforeRestoringScreenTimeState() {
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        SharedAppGroup.publishShieldContext(goalTitle: "Sensitive old goal", promptPreview: nil)
        UserDefaults.standard.set(
            true,
            forKey: ScreenTimeController.sharedDataEraseIncompleteKey
        )

        XCTAssertTrue(SharedAppGroup.hasPersistedData)

        let screenTime = ScreenTimeController()

        XCTAssertNil(screenTime.sharedDataEraseErrorMessage)
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: ScreenTimeController.sharedDataEraseIncompleteKey)
        )
        XCTAssertFalse(SharedAppGroup.hasPersistedData)
        XCTAssertFalse(screenTime.isShieldingEnabled)
        XCTAssertFalse(screenTime.hasSelection)
    }

    @MainActor
    func testEraseDuringAutomaticRefillCannotRestartBackendWorkOrInstallIdentity() async throws {
        let goal = makeGoal()
        let backendEngine = DelayedInstallIdentityQuestionEngine(
            provider: .backend,
            delayNanoseconds: 200_000_000,
            identityDefaults: defaults
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        store.updateBackendEndpoint("https://example.com/ai")
        store.updateMembershipTier(.member)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = [makeQuestion(goal: goal, index: 1, status: .retired)]

        let refresh = Task { @MainActor in
            await store.refreshQuestionBatchIfNeeded()
        }
        for _ in 0..<20 where backendEngine.receivedRequests.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(backendEngine.receivedRequests.count, 1)
        XCTAssertNotNil(defaults.string(forKey: BackendClientIdentity.installIDKey))

        store.eraseAllData(backendIdentityDefaults: defaults)
        let didRefresh = await refresh.value
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertFalse(didRefresh)
        XCTAssertEqual(backendEngine.receivedRequests.count, 1)
        XCTAssertNil(defaults.string(forKey: BackendClientIdentity.installIDKey))
        XCTAssertNil(store.goal)
        XCTAssertTrue(store.hasNoPersistedAppData)
    }

    @MainActor
    func testEraseInvalidatesDelayedQuestionGenerationBeforeItCanRestoreData() async throws {
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: DelayedQuestionEngine(
                    provider: .backend,
                    delayNanoseconds: 200_000_000
                ),
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        let screenTime = ScreenTimeController()
        let creation = Task { @MainActor in
            await store.createGoal(
                title: "Study safely",
                deadline: Date().addingTimeInterval(86_400),
                category: .custom,
                currentLevel: "Beginner",
                focusAreas: "fundamentals",
                preferredQuestionStyle: .multipleChoice
            )
        }

        for _ in 0..<20 where store.goal == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(store.goal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistenceDirectory.path))

        screenTime.eraseAllData()
        store.eraseAllData(backendIdentityDefaults: defaults)
        await creation.value

        store.clearUnlockSession()
        screenTime.clearShield()

        XCTAssertNil(store.goal)
        XCTAssertTrue(store.questions.isEmpty)
        XCTAssertTrue(store.questionGenerationTraces.isEmpty)
        XCTAssertTrue(store.hasNoPersistedAppData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistenceDirectory.path))
        XCTAssertFalse(SharedAppGroup.hasPersistedData)
    }

    @MainActor
    func testFailedEraseMustPurgeOldSnapshotBeforeSavingNewGoal() throws {
        let fileManager = ToggleFailingFileManager()
        let oldGoal = makeGoal()
        let store = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory,
            fileManager: fileManager
        )
        store.goal = oldGoal
        store.goalProfiles = [oldGoal]
        store.updateUnlockMinutes(10)
        let primaryURL = persistenceDirectory
            .appendingPathComponent(AppSnapshotPersistence.primaryFileName)
        let backupURL = persistenceDirectory
            .appendingPathComponent(AppSnapshotPersistence.backupFileName)

        fileManager.shouldFailRemoval = true
        store.eraseAllData(backendIdentityDefaults: defaults)

        XCTAssertFalse(store.hasNoPersistedAppData)
        XCTAssertTrue(store.requiresPersistenceEraseRecovery)
        XCTAssertTrue(defaults.bool(forKey: AppSnapshotPersistence.eraseIncompleteKey))
        XCTAssertNotNil(store.persistenceRecoveryMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))

        let newGoal = Goal(
            title: "A new goal after reset",
            deadline: Date().addingTimeInterval(86_400),
            category: .custom,
            currentLevel: "Beginner",
            focusAreas: "new material",
            preferredQuestionStyle: .multipleChoice
        )
        store.goal = newGoal
        store.updateUnlockMinutes(15)

        let stillOldEnvelope = try JSONDecoder().decode(
            AppSnapshotEnvelope.self,
            from: Data(contentsOf: primaryURL)
        )
        XCTAssertEqual(stillOldEnvelope.snapshot.goal?.id, oldGoal.id)

        fileManager.shouldFailRemoval = false
        store.updateUnlockMinutes(30)

        let newPrimaryEnvelope = try JSONDecoder().decode(
            AppSnapshotEnvelope.self,
            from: Data(contentsOf: primaryURL)
        )
        let newBackupEnvelope = try JSONDecoder().decode(
            AppSnapshotEnvelope.self,
            from: Data(contentsOf: backupURL)
        )
        XCTAssertEqual(newPrimaryEnvelope.snapshot.goal?.id, newGoal.id)
        XCTAssertEqual(newBackupEnvelope.snapshot.goal?.id, newGoal.id)
        XCTAssertNotEqual(newBackupEnvelope.snapshot.goal?.id, oldGoal.id)
        XCTAssertFalse(store.requiresPersistenceEraseRecovery)
        XCTAssertFalse(defaults.bool(forKey: AppSnapshotPersistence.eraseIncompleteKey))
        XCTAssertNil(store.persistenceRecoveryMessage)
    }

    @MainActor
    func testFailedSnapshotEraseCannotRestoreOldGoalAfterRelaunch() throws {
        let fileManager = ToggleFailingFileManager()
        let oldGoal = makeGoal()
        let originalStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory,
            fileManager: fileManager
        )
        originalStore.goal = oldGoal
        originalStore.goalProfiles = [oldGoal]
        originalStore.updateUnlockMinutes(10)

        let primaryURL = persistenceDirectory
            .appendingPathComponent(AppSnapshotPersistence.primaryFileName)
        fileManager.shouldFailRemoval = true
        originalStore.eraseAllData(backendIdentityDefaults: defaults)

        let relaunchedStore = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory,
            fileManager: fileManager
        )

        XCTAssertNil(relaunchedStore.goal)
        XCTAssertFalse(relaunchedStore.isOnboardingPresented)
        XCTAssertTrue(relaunchedStore.requiresPersistenceEraseRecovery)
        XCTAssertNotNil(relaunchedStore.persistenceRecoveryMessage)
        XCTAssertTrue(defaults.bool(forKey: AppSnapshotPersistence.eraseIncompleteKey))

        let newGoal = Goal(
            title: "Goal created while cleanup is blocked",
            deadline: Date().addingTimeInterval(86_400),
            category: .custom,
            currentLevel: "Beginner",
            focusAreas: "new material",
            preferredQuestionStyle: .multipleChoice
        )
        relaunchedStore.goal = newGoal
        relaunchedStore.updateUnlockMinutes(15)

        let stillOldEnvelope = try JSONDecoder().decode(
            AppSnapshotEnvelope.self,
            from: Data(contentsOf: primaryURL)
        )
        XCTAssertEqual(stillOldEnvelope.snapshot.goal?.id, oldGoal.id)

        fileManager.shouldFailRemoval = false
        relaunchedStore.eraseAllData(backendIdentityDefaults: defaults)

        XCTAssertFalse(relaunchedStore.requiresPersistenceEraseRecovery)
        XCTAssertTrue(relaunchedStore.hasNoPersistedAppData)
        XCTAssertTrue(relaunchedStore.isOnboardingPresented)
        XCTAssertFalse(defaults.bool(forKey: AppSnapshotPersistence.eraseIncompleteKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistenceDirectory.path))

        let cleanRelaunch = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory,
            fileManager: fileManager
        )
        XCTAssertNil(cleanRelaunch.goal)
        XCTAssertTrue(cleanRelaunch.isOnboardingPresented)
        XCTAssertFalse(cleanRelaunch.requiresPersistenceEraseRecovery)
    }

    @MainActor
    private func makeGenerationTrace(goal: Goal, index: Int) -> QuestionGenerationTrace {
        QuestionGenerationTrace(
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            phase: "migration-\(index)",
            goalID: goal.id,
            goalTitle: goal.title,
            providerPreference: .backend,
            resolvedProvider: .backend,
            usedFallback: false,
            targetCount: 5,
            existingQuestionCount: 0,
            reportedQuestionCount: 0,
            competencyCount: 0,
            minimumDifficulty: 1,
            generatedQuestionCount: 5,
            addedQuestionCount: 5,
            retiredQuestionCount: 0,
            duration: 0.1,
            sourcePrompt: "migration trace \(index)",
            failure: nil,
            errorMessage: nil,
            questions: []
        )
    }

    @MainActor
    private func makeFileBackedStore(goal: Goal) -> CheckpointStore {
        let store = CheckpointStore(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory
        )
        store.goal = goal
        store.goalProfiles = [goal]
        store.updateUnlockMinutes(10)
        return store
    }
}

private final class DelayedInstallIdentityQuestionEngine: QuestionGenerating, @unchecked Sendable {
    let provider: AIProviderKind
    let delayNanoseconds: UInt64
    let identityDefaults: UserDefaults
    private(set) var receivedRequests: [QuestionGenerationRequest] = []

    init(
        provider: AIProviderKind,
        delayNanoseconds: UInt64,
        identityDefaults: UserDefaults
    ) {
        self.provider = provider
        self.delayNanoseconds = delayNanoseconds
        self.identityDefaults = identityDefaults
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        receivedRequests.append(request)
        _ = BackendClientIdentity.installID(defaults: identityDefaults)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return (1...request.targetCount).map { index in
            makeQuestion(
                goal: request.goal,
                index: receivedRequests.count * 1_000 + index,
                topic: "logical reasoning",
                prompt: "\(request.goal.title) delayed identity question \(receivedRequests.count)-\(index)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

private final class ToggleFailingFileManager: FileManager, @unchecked Sendable {
    var shouldFailRemoval = false

    override func removeItem(at URL: URL) throws {
        if shouldFailRemoval {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}
