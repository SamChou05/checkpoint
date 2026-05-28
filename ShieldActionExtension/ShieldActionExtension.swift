import Foundation

#if os(iOS)
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    private func handle(
        action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            SharedAppGroup.markPendingShieldAttempt()
            completionHandler(.openCheckpoint)
        case .secondaryButtonPressed,
             .firstSecondarySubmenuItemPressed,
             .secondSecondarySubmenuItemPressed,
             .thirdSecondarySubmenuItemPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }
}

private extension ShieldActionResponse {
    static var openCheckpoint: ShieldActionResponse {
        // Newer SDKs document .openParentalControlsApp. Until the Swift case is
        // exposed locally, .defer keeps the shield alive after recording the
        // pending attempt so Checkpoint can present it when opened.
        ShieldActionResponse(rawValue: 3) ?? .defer
    }
}
#endif
