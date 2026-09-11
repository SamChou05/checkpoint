import Foundation

#if os(iOS)
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private enum Theme {
        static let background = adaptive(light: 0xF2EBDD, dark: 0x191714)
        static let title = adaptive(light: 0x29231E, dark: 0xEDE3D4)
        static let muted = adaptive(light: 0x71675A, dark: 0xB7A995)
        static let accent = adaptive(light: 0x805A3B, dark: 0xCBA678)
        static let actionFill = adaptive(light: 0x29231E, dark: 0xE3D2BA)
        static let actionLabel = adaptive(light: 0xFAF7F0, dark: 0x29231E)

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
            icon: mascotIcon,
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

    private var mascotIcon: UIImage? {
        UIImage(named: "ShieldMascot", in: Bundle(for: Self.self), compatibleWith: nil) ??
            checkpointIcon
    }

    private var checkpointIcon: UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 72, weight: .semibold)
        return UIImage(systemName: "checkmark.shield.fill", withConfiguration: configuration)?
            .withTintColor(Theme.accent, renderingMode: .alwaysOriginal)
    }
}
#endif
