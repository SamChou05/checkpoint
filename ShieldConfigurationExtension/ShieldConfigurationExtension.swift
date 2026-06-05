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

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        configuration()
    }

    private func configuration() -> ShieldConfiguration {
        SharedAppGroup.markShieldConfigurationRendered()

        let context = SharedAppGroup.currentShieldContext()

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: Theme.paper,
            icon: mascotIcon,
            title: ShieldConfiguration.Label(
                text: "Clear a checkpoint",
                color: Theme.ink
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Goal: \(context.goalTitle)",
                color: Theme.muted
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Open Checkpoint",
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
