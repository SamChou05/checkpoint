import Foundation
import Observation

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

#if os(iOS) && canImport(ManagedSettings)
import ManagedSettings
#endif

@MainActor
@Observable
final class ScreenTimeController {
    enum SetupState: String {
        case notStarted = "Not connected"
        case authorized = "Authorized"
        case shieldActive = "Shield active"
        case temporarilyUnlocked = "Temporarily unlocked"
        case failed = "Setup failed"
        case readyForSpike = "Ready for Screen Time spike"
        case unavailable = "Unavailable in this build"
    }

    var setupState: SetupState = .notStarted
    var restrictedAppsSummary = "No restricted apps selected"
    var lastErrorMessage: String?
    var isShieldingEnabled = false

    #if os(iOS) && canImport(FamilyControls)
    var selection = FamilyActivitySelection(includeEntireCategory: true) {
        didSet {
            persistSelection()
            updateSummary()
            if isShieldingEnabled {
                applyShield()
            }
        }
    }
    #endif

    #if os(iOS) && canImport(ManagedSettings)
    @ObservationIgnored private let managedStore = ManagedSettingsStore()
    #endif

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let selectionKey = "checkpoint.screenTime.selection.v1"
    @ObservationIgnored private var relockTask: Task<Void, Never>?

    init(defaults: UserDefaults = SharedAppGroup.defaults) {
        self.defaults = defaults
        restoreSelection()
        updateSummary()
        reconcileShieldState()
    }

    func requestAuthorization() async {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            setupState = .authorized
            lastErrorMessage = nil
            updateSummary()
        } catch {
            setupState = .failed
            lastErrorMessage = error.localizedDescription
        }
        #else
        setupState = .unavailable
        restrictedAppsSummary = "FamilyControls requires an iOS app target with Screen Time entitlements."
        #endif
    }

    func applyShield() {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        relockTask?.cancel()
        managedStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

        if selection.categoryTokens.isEmpty {
            managedStore.shield.applicationCategories = nil
        } else {
            managedStore.shield.applicationCategories = .specific(selection.categoryTokens, except: [])
        }

        isShieldingEnabled = hasSelection
        setupState = hasSelection ? .shieldActive : .authorized
        SharedAppGroup.publishDesiredShieldActive(isShieldingEnabled)
        SharedAppGroup.publishUnlockExpiration(nil)
        updateSummary()
        #else
        setupState = .unavailable
        restrictedAppsSummary = "Shielding requires FamilyControls and ManagedSettings on iOS."
        #endif
    }

    func clearShield() {
        #if os(iOS) && canImport(ManagedSettings)
        relockTask?.cancel()
        managedStore.clearAllSettings()
        #endif

        isShieldingEnabled = false
        setupState = .authorized
        SharedAppGroup.publishDesiredShieldActive(false)
        SharedAppGroup.publishUnlockExpiration(nil)
        updateSummary()
    }

    func temporarilyUnshield(minutes: Int) {
        guard minutes > 0 else { return }

        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        managedStore.clearAllSettings()
        isShieldingEnabled = false
        setupState = .temporarilyUnlocked
        SharedAppGroup.publishDesiredShieldActive(true)
        SharedAppGroup.publishUnlockExpiration(Calendar.current.date(byAdding: .minute, value: minutes, to: Date()))

        relockTask?.cancel()
        relockTask = Task { [weak self] in
            let seconds = UInt64(minutes * 60)
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.applyShield()
        }
        #else
        setupState = .unavailable
        #endif
    }

    func reconcileShieldState() {
        guard SharedAppGroup.desiredShieldActive else { return }

        if let unlockExpiration = SharedAppGroup.unlockExpiration, unlockExpiration > Date() {
            setupState = .temporarilyUnlocked
            return
        }

        applyShield()
    }

    #if os(iOS) && canImport(FamilyControls)
    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
    }

    func updateSelection(_ newSelection: FamilyActivitySelection) {
        selection = newSelection
    }
    #else
    var hasSelection: Bool { false }
    #endif

    private func updateSummary() {
        #if os(iOS) && canImport(FamilyControls)
        let appCount = selection.applicationTokens.count
        let categoryCount = selection.categoryTokens.count
        let webCount = selection.webDomainTokens.count

        if appCount + categoryCount + webCount == 0 {
            restrictedAppsSummary = "No restricted apps selected"
        } else {
            restrictedAppsSummary = "\(appCount) apps, \(categoryCount) categories, \(webCount) websites selected"
        }
        #else
        restrictedAppsSummary = "Screen Time APIs are unavailable in this build."
        #endif
    }

    private func persistSelection() {
        #if os(iOS) && canImport(FamilyControls)
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: selectionKey)
        #endif
    }

    private func restoreSelection() {
        #if os(iOS) && canImport(FamilyControls)
        guard
            let data = defaults.data(forKey: selectionKey),
            let restoredSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }

        selection = restoredSelection
        #endif
    }
}
