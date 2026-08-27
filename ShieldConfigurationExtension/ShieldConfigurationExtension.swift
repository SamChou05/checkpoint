import Foundation

#if os(iOS)
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private enum Theme {
        static let ink = UIColor(red: 0.06, green: 0.14, blue: 0.12, alpha: 1.0)
        static let paper = UIColor(red: 0.95, green: 0.96, blue: 0.93, alpha: 1.0)
        static let muted = UIColor(red: 0.35, green: 0.41, blue: 0.38, alpha: 1.0)
        static let teal = UIColor(red: 0.11, green: 0.31, blue: 0.28, alpha: 1.0)
    }

    override func configuration(shielding _: Application) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding _: Application, in _: ActivityCategory) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding _: WebDomain) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding _: WebDomain, in _: ActivityCategory) -> ShieldConfiguration {
        configuration()
    }

    private func configuration() -> ShieldConfiguration {
        SharedAppGroup.markShieldConfigurationRendered()

        let context = SharedAppGroup.currentShieldContext()
        let supportsAutomaticHandoff: Bool
        if #available(iOS 26.5, *) {
            supportsAutomaticHandoff = true
        } else {
            supportsAutomaticHandoff = false
        }
        let subtitle = supportsAutomaticHandoff
            ? "Goal: \(context.goalTitle)"
            : "Tap below, then open Checkpoint from your Home Screen. Goal: \(context.goalTitle)"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: Theme.paper,
            icon: mascotIcon,
            title: ShieldConfiguration.Label(
                text: "Clear a checkpoint",
                color: Theme.ink
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: Theme.muted
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: supportsAutomaticHandoff ? "Open Checkpoint" : "Start checkpoint",
                color: Theme.paper
            ),
            primaryButtonBackgroundColor: Theme.teal,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay locked",
                color: Theme.ink
            )
        )
    }

    private var mascotIcon: UIImage? {
        UIImage(named: "ShieldMascot", in: Bundle(for: Self.self), compatibleWith: nil) ??
            UIImage(systemName: "shield.lefthalf.filled")
    }
}
#endif
