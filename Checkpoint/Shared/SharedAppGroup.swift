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
    private static let shieldContextFileName = "shield-context.json"

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
    }

    static func publishDesiredShieldActive(_ isActive: Bool) {
        defaults.set(isActive, forKey: desiredShieldActiveKey)
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
        defaults.object(forKey: lastUnlockExpirationKey) as? Date
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
