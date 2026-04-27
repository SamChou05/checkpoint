import Foundation

#if os(iOS)
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
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
        let defaults = SharedAppGroup.defaults
        let goalTitle = defaults.string(forKey: SharedAppGroup.shieldGoalTitleKey) ?? "Checkpoint"
        let prompt = defaults.string(forKey: SharedAppGroup.shieldPromptPreviewKey) ?? "Open Checkpoint and clear one checkpoint before you scroll."

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 0.96),
            icon: UIImage(systemName: "shield.lefthalf.filled"),
            title: ShieldConfiguration.Label(
                text: "Clear a checkpoint",
                color: UIColor(red: 0.95, green: 0.96, blue: 0.94, alpha: 1.0)
            ),
            subtitle: ShieldConfiguration.Label(
                text: "\(goalTitle)\n\(prompt)",
                color: UIColor(red: 0.72, green: 0.76, blue: 0.78, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Open Checkpoint",
                color: .black
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.20, green: 0.78, blue: 0.68, alpha: 1.0),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay locked",
                color: UIColor(red: 0.95, green: 0.96, blue: 0.94, alpha: 1.0)
            )
        )
    }
}
#endif

