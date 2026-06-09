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

    static let identifier = "group.com.samchou.checkpoint"

    static let pendingShieldAttemptDateKey = "pendingShieldAttemptDate"
    static let shieldGoalTitleKey = "shieldGoalTitle"
    static let shieldPromptPreviewKey = "shieldPromptPreview"
    static let shieldAttemptCountKey = "shieldAttemptCount"
    static let shieldConfigurationRenderDateKey = "shieldConfigurationRenderDate"
    static let shieldConfigurationRenderCountKey = "shieldConfigurationRenderCount"
    static let lastUnlockExpirationKey = "lastUnlockExpiration"
    static let desiredShieldActiveKey = "desiredShieldActive"
    static let screenTimeSelectionKey = "checkpoint.screenTime.selection.v1"
    static let unlockRelockMonitorScheduledAtKey = "unlockRelockMonitorScheduledAt"
    static let unlockRelockMonitorIntervalStartKey = "unlockRelockMonitorIntervalStart"
    static let unlockRelockMonitorExpectedEndKey = "unlockRelockMonitorExpectedEnd"
    static let unlockRelockExtensionIntervalStartCountKey = "unlockRelockExtensionIntervalStartCount"
    static let unlockRelockExtensionIntervalEndCountKey = "unlockRelockExtensionIntervalEndCount"
    static let unlockRelockExtensionLastEventDateKey = "unlockRelockExtensionLastEventDate"
    static let unlockRelockExtensionLastResultKey = "unlockRelockExtensionLastResult"
    private static let shieldContextFileName = "shield-context.json"
    private static let screenTimeSelectionFileName = "screen-time-selection.json"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static func markPendingShieldAttempt() {
        let defaults = defaults
        defaults.set(Date(), forKey: pendingShieldAttemptDateKey)
        defaults.set(defaults.integer(forKey: shieldAttemptCountKey) + 1, forKey: shieldAttemptCountKey)
    }

    static func markShieldConfigurationRendered() {
        let defaults = defaults
        defaults.set(Date(), forKey: shieldConfigurationRenderDateKey)
        defaults.set(defaults.integer(forKey: shieldConfigurationRenderCountKey) + 1, forKey: shieldConfigurationRenderCountKey)
    }

    static func consumePendingShieldAttempt() -> Date? {
        let defaults = defaults
        let date = defaults.object(forKey: pendingShieldAttemptDateKey) as? Date
        defaults.removeObject(forKey: pendingShieldAttemptDateKey)
        return date
    }

    static func publishShieldContext(goalTitle: String?, promptPreview: String?) {
        let context = ShieldContext(
            goalTitle: goalTitle ?? "Checkpoint",
            promptPreview: promptPreview ?? "Open Checkpoint to complete a practice set for your current goal.",
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
            goalTitle: defaults.string(forKey: shieldGoalTitleKey) ?? "Checkpoint",
            promptPreview: defaults.string(forKey: shieldPromptPreviewKey) ?? "Open Checkpoint to complete a practice set for your current goal.",
            revision: "legacy-defaults",
            updatedAt: .distantPast
        )
    }

    static func removeShieldContextFile() {
        guard let url = shieldContextURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func publishUnlockExpiration(_ date: Date?) {
        let defaults = defaults
        if let date {
            defaults.set(date, forKey: lastUnlockExpirationKey)
        } else {
            defaults.removeObject(forKey: lastUnlockExpirationKey)
        }
        defaults.synchronize()
    }

    static func publishDesiredShieldActive(_ isActive: Bool) {
        let defaults = defaults
        defaults.set(isActive, forKey: desiredShieldActiveKey)
        defaults.synchronize()
    }

    static func markUnlockRelockNeedsAppReconciliation() {
        publishDesiredShieldActive(true)
        publishUnlockExpiration(nil)
    }

    static var desiredShieldActive: Bool {
        defaults.bool(forKey: desiredShieldActiveKey)
    }

    static var pendingShieldAttemptDate: Date? {
        defaults.object(forKey: pendingShieldAttemptDateKey) as? Date
    }

    static var unlockExpiration: Date? {
        defaults.synchronize()
        return defaults.object(forKey: lastUnlockExpirationKey) as? Date
    }

    static func publishScreenTimeSelectionData(_ data: Data) {
        let defaults = defaults
        defaults.set(data, forKey: screenTimeSelectionKey)
        writeScreenTimeSelectionData(data)
        defaults.synchronize()
    }

    static func screenTimeSelectionData() -> Data? {
        let defaults = defaults
        defaults.synchronize()

        if let data = defaults.data(forKey: screenTimeSelectionKey) {
            return data
        }

        return readScreenTimeSelectionData()
    }

    static func removeScreenTimeSelectionFile() {
        guard let url = screenTimeSelectionURL else { return }
        try? FileManager.default.removeItem(at: url)
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

    private static var shieldContextURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent(shieldContextFileName)
    }

    private static var screenTimeSelectionURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent(screenTimeSelectionFileName)
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

    private static func writeScreenTimeSelectionData(_ data: Data) {
        guard let url = screenTimeSelectionURL else { return }
        try? data.write(to: url, options: [.atomic])
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
