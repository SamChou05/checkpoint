import Foundation

#if os(iOS) && canImport(DeviceActivity)
@preconcurrency import DeviceActivity
#endif

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

enum SharedAppGroup {
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
        let defaults = defaults
        defaults.set(goalTitle ?? "Checkpoint", forKey: shieldGoalTitleKey)
        defaults.set(promptPreview ?? "Open Checkpoint to complete a practice set for your current goal.", forKey: shieldPromptPreviewKey)
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

#if os(iOS) && canImport(DeviceActivity)
extension DeviceActivityName {
    static var checkpointUnlockWindow: Self {
        Self("checkpoint.unlockWindow")
    }
}
#endif
