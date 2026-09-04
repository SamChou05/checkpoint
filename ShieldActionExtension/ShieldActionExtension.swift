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
        // iOS 26.5 uses raw value 3 for openParentalControlsApp, which this SDK
        // predates. Older systems must never receive that availability-gated
        // response even when the enum accepts its raw value.
        guard SharedAppGroup.currentShieldHandoffRoute == .automatic else {
            return .defer
        }
        return ShieldActionResponse(rawValue: 3) ?? .defer
    }
}
#endif
