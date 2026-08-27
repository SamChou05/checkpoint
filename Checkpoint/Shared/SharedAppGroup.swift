import Foundation

#if os(iOS) && canImport(DeviceActivity)
@preconcurrency import DeviceActivity
#endif

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

enum SharedAppGroup {
    struct ShieldContext: Codable, Equatable {
        var goalTitle: String
        var promptPreview: String
        var revision: String
        var updatedAt: Date
    }

    struct ProtectionSnapshot: Codable, Equatable, Sendable {
        static let currentSchemaVersion = 3

        var schemaVersion: Int
        var desiredShieldActive: Bool
        var unlockExpiration: Date?
        var screenTimeSelectionData: Data?
        var screenTimeSelectionSemanticsVersion: Int
        var configurationRevision: String
        var revision: String
        var updatedAt: Date

        func acceptsPendingShieldAttempt(
            configurationRevision pendingConfigurationRevision: String?,
            hasSelection: Bool,
            now: Date = Date()
        ) -> Bool {
            guard desiredShieldActive, hasSelection else { return false }
            if let unlockExpiration, unlockExpiration > now { return false }

            return pendingConfigurationRevision == nil ||
                pendingConfigurationRevision == configurationRevision
        }
    }

    struct PendingShieldAttempt: Codable, Equatable, Sendable {
        var id: String
        var createdAt: Date
        var protectionConfigurationRevision: String?

        init(
            id: String = UUID().uuidString,
            createdAt: Date,
            protectionConfigurationRevision: String?
        ) {
            self.id = id
            self.createdAt = createdAt
            self.protectionConfigurationRevision = protectionConfigurationRevision
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case createdAt
            case protectionConfigurationRevision
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            protectionConfigurationRevision = try container.decodeIfPresent(
                String.self,
                forKey: .protectionConfigurationRevision
            )
            id = try container.decodeIfPresent(String.self, forKey: .id)
                ?? Self.legacyIdentifier(
                    createdAt: createdAt,
                    protectionConfigurationRevision: protectionConfigurationRevision
                )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(createdAt, forKey: .createdAt)
            try container.encodeIfPresent(
                protectionConfigurationRevision,
                forKey: .protectionConfigurationRevision
            )
        }

        static func legacyIdentifier(
            createdAt: Date,
            protectionConfigurationRevision: String?
        ) -> String {
            "legacy-\(createdAt.timeIntervalSinceReferenceDate)-\(protectionConfigurationRevision ?? "unbound")"
        }
    }

    static let identifier = "group.com.samchou.checkpoint"
    static let maximumShieldedApplicationCount = 50
    static let maximumShieldedWebDomainCount = 50

    static let pendingShieldAttemptDateKey = "pendingShieldAttemptDate"
    static let pendingShieldAttemptProtectionRevisionKey = "pendingShieldAttemptProtectionRevision"
    static let pendingShieldAttemptDataKey = "checkpoint.pendingShieldAttempt.v2"
    static let pendingShieldAttemptCurrentIDKey = "checkpoint.pendingShieldAttempt.currentID"
    private static let pendingShieldAttemptEventKeyPrefix = "checkpoint.pendingShieldAttempt.event."
    static let shieldGoalTitleKey = "shieldGoalTitle"
    static let shieldPromptPreviewKey = "shieldPromptPreview"
    static let shieldAttemptCountKey = "shieldAttemptCount"
    static let shieldConfigurationRenderDateKey = "shieldConfigurationRenderDate"
    static let shieldConfigurationRenderCountKey = "shieldConfigurationRenderCount"
    static let lastUnlockExpirationKey = "lastUnlockExpiration"
    static let desiredShieldActiveKey = "desiredShieldActive"
    static let checkpointReadyKey = "checkpoint.protection.checkpointReady"
    static let screenTimeSelectionKey = "checkpoint.screenTime.selection.v1"
    static let screenTimeSelectionSemanticsVersionKey = "checkpoint.screenTime.selectionSemanticsVersion"
    static let protectionConfigurationRevisionKey = "checkpoint.protection.configurationRevision"
    static let protectionRevisionKey = "checkpoint.protection.revision"
    static let protectionUpdatedAtKey = "checkpoint.protection.updatedAt"
    static let currentScreenTimeSelectionSemanticsVersion = 1
    static let unlockRelockMonitorScheduledAtKey = "unlockRelockMonitorScheduledAt"
    static let unlockRelockMonitorIntervalStartKey = "unlockRelockMonitorIntervalStart"
    static let unlockRelockMonitorExpectedEndKey = "unlockRelockMonitorExpectedEnd"
    static let unlockRelockExtensionIntervalStartCountKey = "unlockRelockExtensionIntervalStartCount"
    static let unlockRelockExtensionIntervalEndCountKey = "unlockRelockExtensionIntervalEndCount"
    static let unlockRelockExtensionLastEventDateKey = "unlockRelockExtensionLastEventDate"
    static let unlockRelockExtensionLastResultKey = "unlockRelockExtensionLastResult"
    private static let defaultShieldGoalTitle = "Checkpoint"
    private static let defaultShieldPromptPreview =
        "Open Checkpoint to complete a practice set for your current goal."
    private static let shieldContextFileName = "shield-context.json"
    private static let screenTimeSelectionFileName = "screen-time-selection.json"
    private static let protectionSnapshotFileName = "protection-snapshot.json"
    private static let knownDefaultsKeys = [
        pendingShieldAttemptDateKey,
        pendingShieldAttemptProtectionRevisionKey,
        pendingShieldAttemptDataKey,
        pendingShieldAttemptCurrentIDKey,
        shieldGoalTitleKey,
        shieldPromptPreviewKey,
        shieldAttemptCountKey,
        shieldConfigurationRenderDateKey,
        shieldConfigurationRenderCountKey,
        lastUnlockExpirationKey,
        desiredShieldActiveKey,
        checkpointReadyKey,
        screenTimeSelectionKey,
        screenTimeSelectionSemanticsVersionKey,
        protectionConfigurationRevisionKey,
        protectionRevisionKey,
        protectionUpdatedAtKey,
        unlockRelockMonitorScheduledAtKey,
        unlockRelockMonitorIntervalStartKey,
        unlockRelockMonitorExpectedEndKey,
        unlockRelockExtensionIntervalStartCountKey,
        unlockRelockExtensionIntervalEndCountKey,
        unlockRelockExtensionLastEventDateKey,
        unlockRelockExtensionLastResultKey
    ]

    private enum DataEraseError: LocalizedError {
        case incomplete

        var errorDescription: String? {
            "Checkpoint could not remove all shared Screen Time data."
        }
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static var isAvailable: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) != nil
    }

    static func canAcceptShieldTokenCount(
        _ proposedCount: Int,
        currentCount: Int,
        maximumCount: Int
    ) -> Bool {
        proposedCount <= maximumCount ||
            (currentCount > maximumCount && proposedCount <= currentCount)
    }

    static func resolvedScreenTimeSelectionSemanticsVersion(
        storedVersion: Int,
        applicationTokenCount: Int,
        webDomainTokenCount: Int
    ) -> Int {
        guard storedVersion < currentScreenTimeSelectionSemanticsVersion,
              applicationTokenCount > 0 || webDomainTokenCount > 0 else {
            return storedVersion
        }

        return currentScreenTimeSelectionSemanticsVersion
    }

    static func usesLegacyCategoryEnforcement(
        semanticsVersion: Int,
        applicationTokenCount: Int,
        categoryTokenCount: Int,
        webDomainTokenCount: Int
    ) -> Bool {
        semanticsVersion < currentScreenTimeSelectionSemanticsVersion &&
            categoryTokenCount > 0 &&
            applicationTokenCount == 0 &&
            webDomainTokenCount == 0
    }

    static func markPendingShieldAttempt() {
        let defaults = defaults
        let attempt = PendingShieldAttempt(
            createdAt: Date(),
            protectionConfigurationRevision: currentProtectionSnapshot().configurationRevision
        )
        if let data = try? JSONEncoder().encode(attempt) {
            let previousAttemptID = defaults.string(forKey: pendingShieldAttemptCurrentIDKey)
            defaults.set(data, forKey: pendingShieldAttemptEventKey(for: attempt.id))
            defaults.set(attempt.id, forKey: pendingShieldAttemptCurrentIDKey)
            if let previousAttemptID, previousAttemptID != attempt.id {
                defaults.removeObject(forKey: pendingShieldAttemptEventKey(for: previousAttemptID))
            }
        }
        defaults.removeObject(forKey: pendingShieldAttemptDataKey)
        defaults.removeObject(forKey: pendingShieldAttemptDateKey)
        defaults.removeObject(forKey: pendingShieldAttemptProtectionRevisionKey)
        defaults.set(defaults.integer(forKey: shieldAttemptCountKey) + 1, forKey: shieldAttemptCountKey)
        defaults.synchronize()
    }

    static func markShieldConfigurationRendered() {
        let defaults = defaults
        defaults.set(Date(), forKey: shieldConfigurationRenderDateKey)
        defaults.set(defaults.integer(forKey: shieldConfigurationRenderCountKey) + 1, forKey: shieldConfigurationRenderCountKey)
    }

    static func consumePendingShieldAttempt(matchingID: String? = nil) -> Date? {
        let defaults = defaults
        guard let attempt = currentPendingShieldAttempt else { return nil }
        if let matchingID, attempt.id != matchingID {
            return nil
        }

        let latestCurrentID = defaults.string(forKey: pendingShieldAttemptCurrentIDKey)
        if let latestCurrentID, latestCurrentID != attempt.id {
            return nil
        }

        defaults.removeObject(forKey: pendingShieldAttemptEventKey(for: attempt.id))
        defaults.removeObject(forKey: pendingShieldAttemptDataKey)
        defaults.removeObject(forKey: pendingShieldAttemptDateKey)
        defaults.removeObject(forKey: pendingShieldAttemptProtectionRevisionKey)
        defaults.synchronize()
        return attempt.createdAt
    }

    static func removeAllPendingShieldAttempts() {
        let defaults = defaults
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(pendingShieldAttemptEventKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: pendingShieldAttemptCurrentIDKey)
        defaults.removeObject(forKey: pendingShieldAttemptDataKey)
        defaults.removeObject(forKey: pendingShieldAttemptDateKey)
        defaults.removeObject(forKey: pendingShieldAttemptProtectionRevisionKey)
        defaults.synchronize()
    }

    static func publishShieldContext(goalTitle: String?, promptPreview: String?) {
        let context = ShieldContext(
            goalTitle: goalTitle ?? defaultShieldGoalTitle,
            promptPreview: promptPreview ?? defaultShieldPromptPreview,
            revision: UUID().uuidString,
            updatedAt: Date()
        )
        let previousContext = currentShieldContext()
        let defaults = defaults
        defaults.set(context.goalTitle, forKey: shieldGoalTitleKey)
        defaults.set(context.promptPreview, forKey: shieldPromptPreviewKey)
        writeShieldContext(context)
        defaults.synchronize()

        if previousContext.goalTitle != context.goalTitle ||
            previousContext.promptPreview != context.promptPreview {
            NotificationCenter.default.post(name: .checkpointShieldContextDidChange, object: nil)
        }
    }

    static func currentShieldContext() -> ShieldContext {
        if let context = readShieldContext() {
            return context
        }

        let defaults = defaults
        defaults.synchronize()
        return ShieldContext(
            goalTitle: defaults.string(forKey: shieldGoalTitleKey) ?? defaultShieldGoalTitle,
            promptPreview: defaults.string(forKey: shieldPromptPreviewKey) ?? defaultShieldPromptPreview,
            revision: "legacy-defaults",
            updatedAt: .distantPast
        )
    }

    static func removeShieldContextFile() {
        guard let url = shieldContextURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func publishProtectionState(isActive: Bool, unlockExpiration: Date?) {
        updateProtectionSnapshot { snapshot in
            snapshot.desiredShieldActive = isActive
            snapshot.unlockExpiration = unlockExpiration
        }
    }

    static func publishUnlockExpiration(_ date: Date?) {
        updateProtectionSnapshot { snapshot in
            snapshot.unlockExpiration = date
        }
    }

    static func publishCheckpointReadiness(_ isReady: Bool) {
        let defaults = defaults
        guard defaults.object(forKey: checkpointReadyKey) as? Bool != isReady else { return }
        defaults.set(isReady, forKey: checkpointReadyKey)
        defaults.synchronize()
    }

    static func publishDesiredShieldActive(_ isActive: Bool) {
        updateProtectionSnapshot { snapshot in
            snapshot.desiredShieldActive = isActive
        }
    }

    static var desiredShieldActive: Bool {
        currentProtectionSnapshot().desiredShieldActive
    }

    static var pendingShieldAttemptDate: Date? {
        currentPendingShieldAttempt?.createdAt
    }

    static var pendingShieldAttemptProtectionRevision: String? {
        currentPendingShieldAttempt?.protectionConfigurationRevision
    }

    static var unlockExpiration: Date? {
        currentProtectionSnapshot().unlockExpiration
    }

    static var checkpointReady: Bool? {
        defaults.object(forKey: checkpointReadyKey) as? Bool
    }

    static func publishScreenTimeSelectionData(
        _ data: Data,
        semanticsVersion: Int = currentScreenTimeSelectionSemanticsVersion
    ) {
        updateProtectionSnapshot { snapshot in
            snapshot.screenTimeSelectionData = data
            snapshot.screenTimeSelectionSemanticsVersion = semanticsVersion
        }
    }

    static func screenTimeSelectionData() -> Data? {
        currentProtectionSnapshot().screenTimeSelectionData
    }

    static func removeScreenTimeSelectionFile() {
        guard let url = screenTimeSelectionURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func removeProtectionSnapshotFile() {
        guard let url = protectionSnapshotURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static var hasPersistedData: Bool {
        if let domain = defaults.persistentDomain(forName: identifier), !domain.isEmpty {
            return true
        }

        if containsKnownValues(in: defaults) || containsKnownValues(in: .standard) {
            return true
        }

        return persistedFileURLs.contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    static func eraseAllData() throws {
        let sharedDefaults = defaults
        sharedDefaults.removePersistentDomain(forName: identifier)
        removeKnownValues(from: sharedDefaults)
        sharedDefaults.synchronize()

        // Clear scoped fallback keys used by legacy or entitlement-misconfigured builds.
        removeKnownValues(from: .standard)
        UserDefaults.standard.synchronize()

        var fileDeletionFailed = false
        for url in persistedFileURLs
        where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                fileDeletionFailed = true
            }
        }

        guard !fileDeletionFailed, !hasPersistedData else {
            throw DataEraseError.incomplete
        }
    }

    private static func removeKnownValues(from defaults: UserDefaults) {
        for key in knownDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(pendingShieldAttemptEventKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func containsKnownValues(in defaults: UserDefaults) -> Bool {
        defaults.dictionaryRepresentation().keys.contains { key in
            knownDefaultsKeys.contains(key) || key.hasPrefix(pendingShieldAttemptEventKeyPrefix)
        }
    }

    static func markUnlockRelockMonitorScheduled(intervalStart: Date, expectedEnd: Date) {
        let defaults = defaults
        defaults.set(Date(), forKey: unlockRelockMonitorScheduledAtKey)
        defaults.set(intervalStart, forKey: unlockRelockMonitorIntervalStartKey)
        defaults.set(expectedEnd, forKey: unlockRelockMonitorExpectedEndKey)
        defaults.removeObject(forKey: unlockRelockExtensionLastResultKey)
        defaults.synchronize()
    }

    static func markUnlockRelockExtensionIntervalStarted() {
        let defaults = defaults
        defaults.set(defaults.integer(forKey: unlockRelockExtensionIntervalStartCountKey) + 1, forKey: unlockRelockExtensionIntervalStartCountKey)
        defaults.set(Date(), forKey: unlockRelockExtensionLastEventDateKey)
        defaults.set("started", forKey: unlockRelockExtensionLastResultKey)
        defaults.synchronize()
    }

    static func markUnlockRelockExtensionIntervalEnded(result: String) {
        let defaults = defaults
        defaults.set(defaults.integer(forKey: unlockRelockExtensionIntervalEndCountKey) + 1, forKey: unlockRelockExtensionIntervalEndCountKey)
        defaults.set(Date(), forKey: unlockRelockExtensionLastEventDateKey)
        defaults.set(result, forKey: unlockRelockExtensionLastResultKey)
        defaults.synchronize()
    }

    static var shieldConfigurationRenderDate: Date? {
        defaults.object(forKey: shieldConfigurationRenderDateKey) as? Date
    }

    static var shieldConfigurationRenderCount: Int {
        defaults.integer(forKey: shieldConfigurationRenderCountKey)
    }

    static var shieldAttemptCount: Int {
        defaults.integer(forKey: shieldAttemptCountKey)
    }

    static func currentProtectionSnapshot() -> ProtectionSnapshot {
        readProtectionSnapshot() ?? legacyProtectionSnapshot()
    }

    static var currentPendingShieldAttempt: PendingShieldAttempt? {
        let defaults = defaults
        if let currentID = defaults.string(forKey: pendingShieldAttemptCurrentIDKey) {
            guard let data = defaults.data(forKey: pendingShieldAttemptEventKey(for: currentID)),
                  let attempt = try? JSONDecoder().decode(PendingShieldAttempt.self, from: data),
                  attempt.id == currentID else {
                return nil
            }
            return attempt
        }

        if let data = defaults.data(forKey: pendingShieldAttemptDataKey),
           let attempt = try? JSONDecoder().decode(PendingShieldAttempt.self, from: data) {
            return attempt
        }

        guard let createdAt = defaults.object(forKey: pendingShieldAttemptDateKey) as? Date else {
            return nil
        }
        let protectionConfigurationRevision = defaults.string(
            forKey: pendingShieldAttemptProtectionRevisionKey
        )
        return PendingShieldAttempt(
            id: PendingShieldAttempt.legacyIdentifier(
                createdAt: createdAt,
                protectionConfigurationRevision: protectionConfigurationRevision
            ),
            createdAt: createdAt,
            protectionConfigurationRevision: protectionConfigurationRevision
        )
    }

    private static func pendingShieldAttemptEventKey(for id: String) -> String {
        pendingShieldAttemptEventKeyPrefix + id
    }

    private static var shieldContextURL: URL? {
        sharedFileURL(named: shieldContextFileName)
    }

    private static var screenTimeSelectionURL: URL? {
        sharedFileURL(named: screenTimeSelectionFileName)
    }

    private static var protectionSnapshotURL: URL? {
        sharedFileURL(named: protectionSnapshotFileName)
    }

    private static var persistedFileURLs: [URL] {
        [shieldContextURL, screenTimeSelectionURL, protectionSnapshotURL].compactMap { $0 }
    }

    private static func sharedFileURL(named fileName: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent(fileName)
    }

    private static func readShieldContext() -> ShieldContext? {
        guard let url = shieldContextURL,
              let data = try? Data(contentsOf: url) else { return nil }

        return try? JSONDecoder().decode(ShieldContext.self, from: data)
    }

    private static func writeShieldContext(_ context: ShieldContext) {
        guard let url = shieldContextURL,
              let data = try? JSONEncoder().encode(context) else { return }

        try? data.write(to: url, options: [.atomic])
    }

    private static func readScreenTimeSelectionData() -> Data? {
        guard let url = screenTimeSelectionURL else { return nil }
        return try? Data(contentsOf: url)
    }

    @discardableResult
    private static func writeScreenTimeSelectionData(_ data: Data) -> Bool {
        guard let url = screenTimeSelectionURL else { return false }

        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private static func readProtectionSnapshot() -> ProtectionSnapshot? {
        guard let url = protectionSnapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ProtectionSnapshot.self, from: data),
              snapshot.schemaVersion > 0
        else { return nil }

        return snapshot
    }

    private static func legacyProtectionSnapshot() -> ProtectionSnapshot {
        let defaults = defaults
        defaults.synchronize()

        return ProtectionSnapshot(
            schemaVersion: ProtectionSnapshot.currentSchemaVersion,
            desiredShieldActive: defaults.bool(forKey: desiredShieldActiveKey),
            unlockExpiration: defaults.object(forKey: lastUnlockExpirationKey) as? Date,
            screenTimeSelectionData: defaults.data(forKey: screenTimeSelectionKey) ?? readScreenTimeSelectionData(),
            screenTimeSelectionSemanticsVersion: defaults.integer(forKey: screenTimeSelectionSemanticsVersionKey),
            configurationRevision: defaults.string(forKey: protectionConfigurationRevisionKey)
                ?? "legacy-protection-configuration",
            revision: defaults.string(forKey: protectionRevisionKey)
                ?? "legacy-protection-state",
            updatedAt: defaults.object(forKey: protectionUpdatedAtKey) as? Date ?? .distantPast
        )
    }

    private static func updateProtectionSnapshot(
        _ update: (inout ProtectionSnapshot) -> Void
    ) {
        let persistedSnapshot = readProtectionSnapshot()
        let previousSnapshot = persistedSnapshot ?? legacyProtectionSnapshot()
        var snapshot = previousSnapshot
        update(&snapshot)

        let payloadChanged =
            snapshot.desiredShieldActive != previousSnapshot.desiredShieldActive ||
            snapshot.unlockExpiration != previousSnapshot.unlockExpiration ||
            snapshot.screenTimeSelectionData != previousSnapshot.screenTimeSelectionData ||
            snapshot.screenTimeSelectionSemanticsVersion != previousSnapshot.screenTimeSelectionSemanticsVersion

        let configurationChanged =
            snapshot.desiredShieldActive != previousSnapshot.desiredShieldActive ||
            snapshot.screenTimeSelectionData != previousSnapshot.screenTimeSelectionData ||
            snapshot.screenTimeSelectionSemanticsVersion != previousSnapshot.screenTimeSelectionSemanticsVersion

        guard payloadChanged else {
            if persistedSnapshot == nil {
                _ = writeProtectionSnapshot(snapshot)
            }
            mirrorLegacyProtectionState(snapshot)
            return
        }

        snapshot.schemaVersion = ProtectionSnapshot.currentSchemaVersion
        if configurationChanged {
            snapshot.configurationRevision = UUID().uuidString
        }
        snapshot.revision = UUID().uuidString
        snapshot.updatedAt = Date()

        let snapshotWasWritten = writeProtectionSnapshot(snapshot)
        mirrorLegacyProtectionState(snapshot)
        if !snapshotWasWritten {
            // Prevent a stale canonical file from outranking the freshly mirrored fallback.
            removeProtectionSnapshotFile()
        }
    }

    @discardableResult
    private static func writeProtectionSnapshot(_ snapshot: ProtectionSnapshot) -> Bool {
        guard let url = protectionSnapshotURL,
              let data = try? JSONEncoder().encode(snapshot)
        else { return false }

        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private static func mirrorLegacyProtectionState(_ snapshot: ProtectionSnapshot) {
        let defaults = defaults
        defaults.set(snapshot.desiredShieldActive, forKey: desiredShieldActiveKey)
        defaults.set(snapshot.configurationRevision, forKey: protectionConfigurationRevisionKey)
        defaults.set(snapshot.revision, forKey: protectionRevisionKey)
        defaults.set(snapshot.updatedAt, forKey: protectionUpdatedAtKey)

        if let unlockExpiration = snapshot.unlockExpiration {
            defaults.set(unlockExpiration, forKey: lastUnlockExpirationKey)
        } else {
            defaults.removeObject(forKey: lastUnlockExpirationKey)
        }

        if let selectionData = snapshot.screenTimeSelectionData {
            defaults.set(selectionData, forKey: screenTimeSelectionKey)
            defaults.set(
                snapshot.screenTimeSelectionSemanticsVersion,
                forKey: screenTimeSelectionSemanticsVersionKey
            )
            if !writeScreenTimeSelectionData(selectionData) {
                removeScreenTimeSelectionFile()
            }
        } else {
            defaults.removeObject(forKey: screenTimeSelectionKey)
            defaults.removeObject(forKey: screenTimeSelectionSemanticsVersionKey)
            removeScreenTimeSelectionFile()
        }

        defaults.synchronize()
    }

    #if os(iOS) && canImport(FamilyControls)
    static func categoryInclusiveSelection(_ selection: FamilyActivitySelection) -> FamilyActivitySelection {
        guard !selection.includeEntireCategory else { return selection }

        var inclusiveSelection = FamilyActivitySelection(includeEntireCategory: true)
        inclusiveSelection.applicationTokens = selection.applicationTokens
        inclusiveSelection.categoryTokens = selection.categoryTokens
        inclusiveSelection.webDomainTokens = selection.webDomainTokens
        return inclusiveSelection
    }
    #endif
}

extension Notification.Name {
    static let checkpointShieldContextDidChange = Notification.Name("checkpoint.shieldContextDidChange")
}

#if os(iOS) && canImport(DeviceActivity)
extension DeviceActivityName {
    static var checkpointUnlockWindow: Self {
        Self("checkpoint.unlockWindow")
    }
}
#endif
