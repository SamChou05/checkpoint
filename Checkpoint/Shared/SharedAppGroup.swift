import Foundation

enum SharedAppGroup {
    static let identifier = "group.com.samchou.checkpoint"

    static let pendingShieldAttemptDateKey = "pendingShieldAttemptDate"
    static let shieldGoalTitleKey = "shieldGoalTitle"
    static let shieldPromptPreviewKey = "shieldPromptPreview"
    static let shieldAttemptCountKey = "shieldAttemptCount"
    static let lastUnlockExpirationKey = "lastUnlockExpiration"
    static let desiredShieldActiveKey = "desiredShieldActive"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static func markPendingShieldAttempt() {
        let defaults = defaults
        defaults.set(Date(), forKey: pendingShieldAttemptDateKey)
        defaults.set(defaults.integer(forKey: shieldAttemptCountKey) + 1, forKey: shieldAttemptCountKey)
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
        defaults.set(promptPreview ?? "Open Checkpoint and clear one checkpoint before you scroll.", forKey: shieldPromptPreviewKey)
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

    static var unlockExpiration: Date? {
        defaults.object(forKey: lastUnlockExpirationKey) as? Date
    }
}
