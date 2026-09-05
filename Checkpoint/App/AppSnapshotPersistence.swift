import Foundation

struct AppSnapshotEnvelope: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var savedAt: Date
    var snapshot: AppSnapshot

    init(snapshot: AppSnapshot, savedAt: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.snapshot = snapshot
    }
}

enum AppSnapshotLoadResult {
    case empty
    case loaded(AppSnapshot)
    case recovered(AppSnapshot, message: String)
    case failed(message: String)
}

struct AppSnapshotPersistence {
    static let legacySnapshotKey = "checkpoint.snapshot.v1"
    static let primaryDefaultsKey = "checkpoint.snapshot.v2.primary"
    static let backupDefaultsKey = "checkpoint.snapshot.v2.backup"
    static let eraseIncompleteKey = "checkpoint.snapshot.eraseIncomplete.v1"
    static let primaryFileName = "app-state.json"
    static let backupFileName = "app-state.backup.json"

    private enum Storage {
        case files(URL)
        case defaults
    }

    private enum PersistenceError: LocalizedError {
        case verificationFailed

        var errorDescription: String? {
            "The saved app state could not be verified."
        }
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let storage: Storage

    var requiresEraseRecovery: Bool {
        defaults.bool(forKey: Self.eraseIncompleteKey)
    }

    init(
        defaults: UserDefaults,
        persistenceDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager

        if let persistenceDirectory {
            storage = .files(persistenceDirectory)
        } else if defaults === UserDefaults.standard {
            storage = .files(Self.defaultPersistenceDirectory(fileManager: fileManager))
        } else {
            // Unit tests inject an isolated defaults suite. Keeping their state in
            // that suite avoids cross-test file coordination while exercising the
            // same versioned primary/backup envelope.
            storage = .defaults
        }
    }

    func load() -> AppSnapshotLoadResult {
        if requiresEraseRecovery {
            do {
                try erase()
                return .empty
            } catch {
                return .failed(
                    message: "Checkpoint could not finish erasing its local backup. Retry data erasure before adding a new goal."
                )
            }
        }

        let primaryData = readPrimaryData()
        if let snapshot = decodedSnapshot(from: primaryData) {
            return .loaded(snapshot)
        }

        let backupData = readBackupData()
        if let backupData,
           let snapshot = decodedSnapshot(from: backupData) {
            try? restorePrimary(from: backupData)
            return .recovered(
                snapshot,
                message: "Checkpoint recovered your saved data from a backup because the newest local copy could not be read."
            )
        }

        if let legacyData = defaults.data(forKey: Self.legacySnapshotKey),
           let legacySnapshot = try? JSONDecoder().decode(AppSnapshot.self, from: legacyData) {
            do {
                try save(legacySnapshot)
                return .loaded(legacySnapshot)
            } catch {
                return .recovered(
                    legacySnapshot,
                    message: "Checkpoint opened your saved data, but could not finish upgrading its local storage. Your data remains available in the older copy."
                )
            }
        }

        let containedUnreadableData = primaryData != nil
            || backupData != nil
            || defaults.data(forKey: Self.legacySnapshotKey) != nil
        guard containedUnreadableData else { return .empty }

        return .failed(
            message: "Checkpoint could not read its saved data or backup. App protection will stay off until you create a new goal."
        )
    }

    func save(_ snapshot: AppSnapshot) throws {
        guard !requiresEraseRecovery else {
            throw PersistenceError.verificationFailed
        }

        let encoded = try JSONEncoder().encode(AppSnapshotEnvelope(snapshot: snapshot))

        switch storage {
        case .files(let directory):
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let primaryURL = directory.appendingPathComponent(Self.primaryFileName)
            let backupURL = directory.appendingPathComponent(Self.backupFileName)

            if let currentPrimary = try? Data(contentsOf: primaryURL),
               decodedSnapshot(from: currentPrimary) != nil {
                try currentPrimary.write(to: backupURL, options: [.atomic])
                applyFileProtection(to: backupURL)
            }

            try encoded.write(to: primaryURL, options: [.atomic])
            applyFileProtection(to: primaryURL)
            guard decodedSnapshot(from: try? Data(contentsOf: primaryURL)) != nil else {
                throw PersistenceError.verificationFailed
            }

            if decodedSnapshot(from: try? Data(contentsOf: backupURL)) == nil {
                do {
                    try encoded.write(to: backupURL, options: [.atomic])
                    applyFileProtection(to: backupURL)
                } catch {
                    // The verified primary is the committed source of truth.
                    // Failing to provision its first recovery copy must not make
                    // callers roll back memory and report a false save failure.
                }
            }

        case .defaults:
            if let currentPrimary = defaults.data(forKey: Self.primaryDefaultsKey),
               decodedSnapshot(from: currentPrimary) != nil {
                defaults.set(currentPrimary, forKey: Self.backupDefaultsKey)
            }

            defaults.set(encoded, forKey: Self.primaryDefaultsKey)
            guard decodedSnapshot(
                from: defaults.data(forKey: Self.primaryDefaultsKey)
            ) != nil else {
                throw PersistenceError.verificationFailed
            }

            if decodedSnapshot(from: defaults.data(forKey: Self.backupDefaultsKey)) == nil {
                defaults.set(encoded, forKey: Self.backupDefaultsKey)
            }
        }

        // Retain the legacy value until the new primary verifies successfully.
        defaults.removeObject(forKey: Self.legacySnapshotKey)
    }

    /// Persists a transition whose recovery copy must agree with its committed
    /// primary. The backup is prepared first; the primary remains the commit
    /// marker, so an interrupted write continues loading the previous primary.
    func saveMirrored(_ snapshot: AppSnapshot) throws {
        guard !requiresEraseRecovery else {
            throw PersistenceError.verificationFailed
        }

        let encoded = try JSONEncoder().encode(AppSnapshotEnvelope(snapshot: snapshot))

        switch storage {
        case .files(let directory):
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let primaryURL = directory.appendingPathComponent(Self.primaryFileName)
            let backupURL = directory.appendingPathComponent(Self.backupFileName)

            try encoded.write(to: backupURL, options: [.atomic])
            applyFileProtection(to: backupURL)
            guard decodedSnapshot(from: try? Data(contentsOf: backupURL)) != nil else {
                throw PersistenceError.verificationFailed
            }

            try encoded.write(to: primaryURL, options: [.atomic])
            applyFileProtection(to: primaryURL)
            guard decodedSnapshot(from: try? Data(contentsOf: primaryURL)) != nil else {
                throw PersistenceError.verificationFailed
            }

        case .defaults:
            defaults.set(encoded, forKey: Self.backupDefaultsKey)
            guard decodedSnapshot(
                from: defaults.data(forKey: Self.backupDefaultsKey)
            ) != nil else {
                throw PersistenceError.verificationFailed
            }

            defaults.set(encoded, forKey: Self.primaryDefaultsKey)
            guard decodedSnapshot(
                from: defaults.data(forKey: Self.primaryDefaultsKey)
            ) != nil else {
                throw PersistenceError.verificationFailed
            }
        }

        defaults.removeObject(forKey: Self.legacySnapshotKey)
    }

    func erase() throws {
        defaults.set(true, forKey: Self.eraseIncompleteKey)
        defaults.synchronize()
        defaults.removeObject(forKey: Self.legacySnapshotKey)
        defaults.removeObject(forKey: Self.primaryDefaultsKey)
        defaults.removeObject(forKey: Self.backupDefaultsKey)

        if case .files(let directory) = storage,
           fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }

        guard readPrimaryData() == nil,
              readBackupData() == nil,
              defaults.data(forKey: Self.legacySnapshotKey) == nil else {
            throw PersistenceError.verificationFailed
        }

        defaults.removeObject(forKey: Self.eraseIncompleteKey)
        defaults.synchronize()
    }

    private func readPrimaryData() -> Data? {
        switch storage {
        case .files(let directory):
            return try? Data(contentsOf: directory.appendingPathComponent(Self.primaryFileName))
        case .defaults:
            return defaults.data(forKey: Self.primaryDefaultsKey)
        }
    }

    private func readBackupData() -> Data? {
        switch storage {
        case .files(let directory):
            return try? Data(contentsOf: directory.appendingPathComponent(Self.backupFileName))
        case .defaults:
            return defaults.data(forKey: Self.backupDefaultsKey)
        }
    }

    private func restorePrimary(from backupData: Data) throws {
        switch storage {
        case .files(let directory):
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try backupData.write(
                to: directory.appendingPathComponent(Self.primaryFileName),
                options: [.atomic]
            )
            applyFileProtection(
                to: directory.appendingPathComponent(Self.primaryFileName)
            )
        case .defaults:
            defaults.set(backupData, forKey: Self.primaryDefaultsKey)
        }
    }

    private func decodeEnvelope(_ data: Data) throws -> AppSnapshot {
        let envelope = try JSONDecoder().decode(AppSnapshotEnvelope.self, from: data)
        guard envelope.schemaVersion == AppSnapshotEnvelope.currentSchemaVersion else {
            throw PersistenceError.verificationFailed
        }
        return envelope.snapshot
    }

    private func decodedSnapshot(from data: Data?) -> AppSnapshot? {
        guard let data else { return nil }
        return try? decodeEnvelope(data)
    }

    private static func defaultPersistenceDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return applicationSupport.appendingPathComponent("Checkpoint", isDirectory: true)
    }

    private func applyFileProtection(to url: URL) {
        #if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
