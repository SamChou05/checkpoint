import Foundation

#if os(iOS)
@preconcurrency import DeviceActivity
import FamilyControls
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let managedStore = ManagedSettingsStore()

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == .checkpointUnlockWindow else { return }
        reapplyShieldIfUnlockExpired()
    }

    private func reapplyShieldIfUnlockExpired() {
        guard SharedAppGroup.desiredShieldActive else { return }

        if let unlockExpiration = SharedAppGroup.unlockExpiration, unlockExpiration > Date() {
            return
        }

        guard let selection = restoredSelection, hasRestrictedItems(in: selection) else {
            managedStore.clearAllSettings()
            SharedAppGroup.publishDesiredShieldActive(false)
            SharedAppGroup.publishUnlockExpiration(nil)
            return
        }

        managedStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

        if selection.categoryTokens.isEmpty {
            managedStore.shield.applicationCategories = nil
        } else {
            managedStore.shield.applicationCategories = .specific(selection.categoryTokens, except: [])
        }

        SharedAppGroup.publishDesiredShieldActive(true)
        SharedAppGroup.publishUnlockExpiration(nil)
    }

    private var restoredSelection: FamilyActivitySelection? {
        guard
            let data = SharedAppGroup.defaults.data(forKey: SharedAppGroup.screenTimeSelectionKey),
            let decodedSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return nil }

        return SharedAppGroup.categoryInclusiveSelection(decodedSelection)
    }

    private func hasRestrictedItems(in selection: FamilyActivitySelection) -> Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
    }
}
#endif
