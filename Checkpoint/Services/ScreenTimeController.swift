import Foundation
import Observation

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

#if os(iOS) && canImport(DeviceActivity)
@preconcurrency import DeviceActivity
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

    var isReadyForShielding: Bool {
        setupState == .authorized ||
        setupState == .shieldActive ||
        setupState == .temporarilyUnlocked
    }

    #if os(iOS) && canImport(FamilyControls)
    var selection = FamilyActivitySelection() {
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
    @ObservationIgnored private var relockTask: Task<Void, Never>?

    #if os(iOS) && canImport(DeviceActivity)
    @ObservationIgnored private let activityCenter = DeviceActivityCenter()
    #endif

    init(defaults: UserDefaults = SharedAppGroup.defaults) {
        self.defaults = defaults
        restoreSelection()
        updateSummary()
        refreshAuthorizationStatus()
        reconcileShieldState()
    }

    func requestAuthorization() async {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshAuthorizationStatus()
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

    func refreshAuthorizationStatus() {
        #if os(iOS) && canImport(FamilyControls)
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined:
            setupState = .notStarted
            lastErrorMessage = nil
        case .denied:
            setupState = .failed
            lastErrorMessage = "Screen Time access is denied. Enable Family Controls permission before applying shields."
        case .approved:
            if setupState != .shieldActive && setupState != .temporarilyUnlocked {
                setupState = .authorized
            }
            lastErrorMessage = nil
        default:
            if setupState != .shieldActive && setupState != .temporarilyUnlocked {
                setupState = .authorized
            }
            lastErrorMessage = nil
        }
        #else
        setupState = .unavailable
        restrictedAppsSummary = "FamilyControls requires an iOS app target with Screen Time entitlements."
        #endif
    }

    func applyShield() {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        relockTask?.cancel()
        stopUnlockRelockMonitor()

        guard hasSelection else {
            managedStore.clearAllSettings()
            isShieldingEnabled = false
            setupState = .authorized
            lastErrorMessage = "Choose at least one restricted app, category, or website before applying the shield."
            SharedAppGroup.publishDesiredShieldActive(false)
            SharedAppGroup.publishUnlockExpiration(nil)
            updateSummary()
            return
        }

        managedStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

        if selection.categoryTokens.isEmpty {
            managedStore.shield.applicationCategories = nil
        } else {
            managedStore.shield.applicationCategories = .specific(selection.categoryTokens, except: [])
        }

        isShieldingEnabled = hasSelection
        setupState = hasSelection ? .shieldActive : .authorized
        lastErrorMessage = nil
        SharedAppGroup.publishDesiredShieldActive(isShieldingEnabled)
        SharedAppGroup.publishUnlockExpiration(nil)
        updateSummary()
        #else
        setupState = .unavailable
        restrictedAppsSummary = "Shielding requires FamilyControls and ManagedSettings on iOS."
        #endif
    }

    func clearShield() {
        relockTask?.cancel()
        isShieldingEnabled = false
        setupState = .authorized
        lastErrorMessage = nil
        SharedAppGroup.publishDesiredShieldActive(false)
        SharedAppGroup.publishUnlockExpiration(nil)

        #if os(iOS) && canImport(ManagedSettings)
        stopUnlockRelockMonitor()
        managedStore.clearAllSettings()
        #endif

        updateSummary()
    }

    func temporarilyUnshield(minutes: Int) {
        guard minutes > 0 else { return }

        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        let now = Date()
        let expiration = Calendar.current.date(byAdding: .minute, value: minutes, to: now) ?? now

        managedStore.clearAllSettings()
        isShieldingEnabled = false
        setupState = .temporarilyUnlocked
        lastErrorMessage = nil
        SharedAppGroup.publishDesiredShieldActive(true)
        SharedAppGroup.publishUnlockExpiration(expiration)

        scheduleForegroundRelock(until: expiration)
        scheduleUnlockRelockMonitor(from: now, until: expiration)
        #else
        setupState = .unavailable
        #endif
    }

    func reconcileShieldState() {
        guard SharedAppGroup.desiredShieldActive else { return }

        if let unlockExpiration = SharedAppGroup.unlockExpiration, unlockExpiration > Date() {
            setupState = .temporarilyUnlocked
            isShieldingEnabled = false
            scheduleForegroundRelock(until: unlockExpiration)
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
        defaults.set(data, forKey: SharedAppGroup.screenTimeSelectionKey)
        #endif
    }

    private func restoreSelection() {
        #if os(iOS) && canImport(FamilyControls)
        guard
            let data = defaults.data(forKey: SharedAppGroup.screenTimeSelectionKey),
            let restoredSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }

        selection = restoredSelection
        #endif
    }

    private func scheduleForegroundRelock(until expiration: Date) {
        relockTask?.cancel()

        let remainingSeconds = max(1, expiration.timeIntervalSinceNow)
        relockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remainingSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.applyShield()
        }
    }

    private func scheduleUnlockRelockMonitor(from start: Date, until expiration: Date) {
        #if os(iOS) && canImport(DeviceActivity)
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: Self.dateComponents(for: start, calendar: calendar),
            intervalEnd: Self.dateComponents(for: expiration, calendar: calendar),
            repeats: false
        )

        do {
            try activityCenter.startMonitoring(.checkpointUnlockWindow, during: schedule)
        } catch {
            lastErrorMessage = "System re-lock timer could not start: \(error.localizedDescription). Checkpoint will re-lock when the app is active."
        }
        #endif
    }

    private func stopUnlockRelockMonitor() {
        #if os(iOS) && canImport(DeviceActivity)
        activityCenter.stopMonitoring([.checkpointUnlockWindow])
        #endif
    }

    private static func dateComponents(for date: Date, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }
}
