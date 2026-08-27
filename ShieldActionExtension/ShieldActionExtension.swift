import Foundation

#if os(iOS)
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for _: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for _: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for _: ActivityCategoryToken,
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
        // Raw value 3 opens the parental-controls app in newer SDKs. Until this
        // SDK exposes that case, .defer keeps the shield up for a later app launch.
        ShieldActionResponse(rawValue: 3) ?? .defer
    }
}
#endif
