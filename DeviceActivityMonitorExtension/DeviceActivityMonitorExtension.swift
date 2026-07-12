import Foundation

#if os(iOS)
@preconcurrency import DeviceActivity
import FamilyControls
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let managedStore = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == .checkpointUnlockWindow else { return }
        SharedAppGroup.markUnlockRelockExtensionIntervalStarted()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == .checkpointUnlockWindow else { return }
        reapplyShieldIfUnlockExpired()
    }

    private func reapplyShieldIfUnlockExpired() {
        let initialSnapshot = SharedAppGroup.currentProtectionSnapshot()
        var result = reconcileManagedSettings(with: initialSnapshot)

        let latestSnapshot = SharedAppGroup.currentProtectionSnapshot()
        if latestSnapshot.revision != initialSnapshot.revision {
            result = reconcileManagedSettings(with: latestSnapshot)
            result = "converged: \(result)"
        }

        SharedAppGroup.markUnlockRelockExtensionIntervalEnded(result: result)
    }

    private func reconcileManagedSettings(
        with snapshot: SharedAppGroup.ProtectionSnapshot
    ) -> String {
        guard snapshot.desiredShieldActive else {
            managedStore.clearAllSettings()
            return "cleared: protection inactive"
        }

        if let unlockExpiration = snapshot.unlockExpiration,
           unlockExpiration > Date() {
            managedStore.clearAllSettings()
            return "cleared: break still active"
        }

        guard let selection = restoredSelection(from: snapshot),
              hasRestrictedItems(in: selection, snapshot: snapshot)
        else {
            managedStore.clearAllSettings()
            return "cleared: missing protected app selection"
        }

        guard selection.webDomainTokens.count <= SharedAppGroup.maximumShieldedWebDomainCount else {
            managedStore.clearAllSettings()
            return "cleared: protected website limit exceeded"
        }

        guard selection.applicationTokens.count <= SharedAppGroup.maximumShieldedApplicationCount else {
            managedStore.clearAllSettings()
            return "cleared: protected app limit exceeded"
        }

        managedStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

        if usesLegacyCategoryEnforcement(selection: selection, snapshot: snapshot) {
            managedStore.shield.applicationCategories = .specific(selection.categoryTokens, except: [])
        } else {
            // Once the user has edited the new expanded selection, app tokens
            // are authoritative so a category cannot add a removed app back.
            managedStore.shield.applicationCategories = nil
        }

        return "relocked"
    }

    private func restoredSelection(
        from snapshot: SharedAppGroup.ProtectionSnapshot
    ) -> FamilyActivitySelection? {
        guard
            let data = snapshot.screenTimeSelectionData,
            let decodedSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return nil }

        return SharedAppGroup.categoryInclusiveSelection(decodedSelection)
    }

    private func hasRestrictedItems(
        in selection: FamilyActivitySelection,
        snapshot: SharedAppGroup.ProtectionSnapshot
    ) -> Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty ||
        usesLegacyCategoryEnforcement(selection: selection, snapshot: snapshot)
    }

    private func usesLegacyCategoryEnforcement(
        selection: FamilyActivitySelection,
        snapshot: SharedAppGroup.ProtectionSnapshot
    ) -> Bool {
        SharedAppGroup.usesLegacyCategoryEnforcement(
            semanticsVersion: snapshot.screenTimeSelectionSemanticsVersion,
            applicationTokenCount: selection.applicationTokens.count,
            categoryTokenCount: selection.categoryTokens.count,
            webDomainTokenCount: selection.webDomainTokens.count
        )
    }
}
#endif
