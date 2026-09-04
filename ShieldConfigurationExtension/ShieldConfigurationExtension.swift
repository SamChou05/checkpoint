import Foundation

#if os(iOS)
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private enum Theme {
        static let background = adaptive(light: 0xF2F5ED, dark: 0x091512)
        static let title = adaptive(light: 0x0F241F, dark: 0xECF3EF)
        static let muted = adaptive(light: 0x596961, dark: 0xA8B7B0)
        static let accent = adaptive(light: 0x1C4F47, dark: 0x72D0B6)
        static let actionFill = adaptive(light: 0x1C4F47, dark: 0x2C7465)
        static let actionLabel = color(0xF2F5ED)

        private static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
            UIColor { traits in
                color(traits.userInterfaceStyle == .dark ? dark : light)
            }
        }

        private static func color(_ hex: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
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
        let handoffRoute = SharedAppGroup.currentShieldHandoffRoute
        let subtitle = handoffRoute == .automatic
            ? "Goal: \(context.goalTitle)"
            : "Tap below, then open Checkpoint from your Home Screen. Goal: \(context.goalTitle)"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: Theme.background,
            icon: checkpointIcon,
            title: ShieldConfiguration.Label(
                text: "Clear a checkpoint",
                color: Theme.title
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: Theme.muted
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: handoffRoute == .automatic ? "Open Checkpoint" : "Start checkpoint",
                color: Theme.actionLabel
            ),
            primaryButtonBackgroundColor: Theme.actionFill,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay locked",
                color: Theme.title
            )
        )
    }

    private var checkpointIcon: UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 72, weight: .semibold)
        return UIImage(systemName: "checkmark.shield.fill", withConfiguration: configuration)?
            .withTintColor(Theme.accent, renderingMode: .alwaysOriginal)
    }
}
#endif
