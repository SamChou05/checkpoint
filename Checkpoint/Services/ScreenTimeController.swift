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
    static let unlockRelockMonitorLeadIn: TimeInterval = 30

    enum SetupState: String {
        case notStarted = "Not set up"
        case authorized = "Authorized"
        case shieldActive = "Protection active"
        case temporarilyUnlocked = "Break in progress"
        case failed = "Needs attention"
        case readyForSpike = "Ready"
        case unavailable = "Unavailable in this build"
    }

    var setupState: SetupState = .notStarted
    var restrictedAppsSummary = "No protected apps selected"
    var lastErrorMessage: String?
    var isShieldingEnabled = false

    var isReadyForShielding: Bool {
        setupState == .authorized ||
        setupState == .shieldActive ||
        setupState == .temporarilyUnlocked
    }

    var userFacingProtectionStatus: String {
        switch setupState {
        case .shieldActive:
            return "On"
        case .temporarilyUnlocked:
            return "Break in progress"
        case .failed:
            return "Permission needed"
        case .unavailable:
            return "iPhone only"
        case .notStarted, .authorized, .readyForSpike:
            return "Off"
        }
    }

    var userFacingErrorMessage: String? {
        guard lastErrorMessage != nil else { return nil }

        switch setupState {
        case .failed:
            return "Allow Screen Time so Checkpoint can protect the apps you choose."
        case .authorized where !hasSelection:
            return "Choose at least one app, category, or website to protect."
        default:
            return "App protection needs attention. Try again."
        }
    }

    var shieldExtensionDiagnosticsText: String {
        let renderCount = SharedAppGroup.shieldConfigurationRenderCount
        let actionCount = SharedAppGroup.shieldAttemptCount

        guard renderCount > 0 else {
            if actionCount > 0 {
                return "Open Checkpoint has been tapped \(actionCount)x, but the custom shield page has not reported yet. Reinstall the signed app and verify the Shield Configuration extension entitlements if the default Restricted page appears."
            }

            return "Custom shield has not reported yet. Open a protected app after starting protection; if the default Restricted page appears, verify the Shield Configuration extension provisioning."
        }

        let lastRendered = SharedAppGroup.shieldConfigurationRenderDate?.formatted(date: .abbreviated, time: .shortened) ?? "recently"
        return "Custom shield rendered \(renderCount)x, last \(lastRendered). Open Checkpoint tapped \(actionCount)x."
    }

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
    @ObservationIgnored private var relockTask: Task<Void, Never>?
    @ObservationIgnored private var shieldRefreshTask: Task<Void, Never>?
    @ObservationIgnored private let initialAuthorizationRequestKey = "checkpoint.screenTime.initialAuthorizationRequested"

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
            defaults.set(true, forKey: initialAuthorizationRequestKey)
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshAuthorizationStatus()
            updateSummary()
        } catch {
            setupState = .failed
            lastErrorMessage = error.localizedDescription
        }
        #else
        setupState = .unavailable
        restrictedAppsSummary = "App protection is available on iPhone."
        #endif
    }

    func requestInitialAuthorizationIfNeeded() async {
        guard setupState == .notStarted else { return }
        guard !defaults.bool(forKey: initialAuthorizationRequestKey) else { return }
        await requestAuthorization()
    }

    func refreshAuthorizationStatus() {
        #if os(iOS) && canImport(FamilyControls)
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined:
            setupState = .notStarted
            lastErrorMessage = nil
        case .denied:
            setupState = .failed
            lastErrorMessage = "Screen Time access is denied. Allow Screen Time access before starting app protection."
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
        restrictedAppsSummary = "App protection is available on iPhone."
        #endif
    }

    func applyShield() {
        applyShield(cancelPendingRefresh: true)
    }

    private func applyShield(cancelPendingRefresh: Bool) {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        if cancelPendingRefresh {
            shieldRefreshTask?.cancel()
            shieldRefreshTask = nil
        }
        relockTask?.cancel()
        stopUnlockRelockMonitor()

        guard hasSelection else {
            managedStore.clearAllSettings()
            isShieldingEnabled = false
            setupState = .authorized
            lastErrorMessage = "Choose at least one protected app, category, or website before starting app protection."
            SharedAppGroup.publishDesiredShieldActive(false)
            SharedAppGroup.publishUnlockExpiration(nil)
            updateSummary()
            return
        }

        guard isScreenTimeAuthorized else {
            isShieldingEnabled = false
            setupState = .failed
            lastErrorMessage = "Screen Time access is not approved yet. Allow Screen Time access before starting app protection."
            SharedAppGroup.publishDesiredShieldActive(false)
            SharedAppGroup.publishUnlockExpiration(nil)
            updateSummary()
            return
        }

        clearManagedShieldRestrictions()
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
        restrictedAppsSummary = "App protection is available on iPhone."
        #endif
    }

    func refreshActiveShieldConfiguration() {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        guard isShieldingEnabled else { return }
        shieldRefreshTask?.cancel()
        clearManagedShieldRestrictions()
        shieldRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            self?.finishActiveShieldConfigurationRefresh()
        }
        #endif
    }

    func clearShield() {
        shieldRefreshTask?.cancel()
        shieldRefreshTask = nil
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
        shieldRefreshTask?.cancel()
        shieldRefreshTask = nil

        guard hasSelection else {
            lastErrorMessage = "No protected apps are selected, so there is nothing to open."
            return
        }

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

    func reconcileShieldState(
        protectionShouldRemainActive: Bool? = nil,
        fallbackUnlockExpiration: Date? = nil
    ) {
        let shouldRemainActive = protectionShouldRemainActive ?? SharedAppGroup.desiredShieldActive
        guard shouldRemainActive else { return }

        let unlockExpiration = SharedAppGroup.unlockExpiration ?? fallbackUnlockExpiration
        if let unlockExpiration, unlockExpiration > Date() {
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
        selection = SharedAppGroup.categoryInclusiveSelection(newSelection)
        if hasSelection {
            lastErrorMessage = nil
        }
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
            restrictedAppsSummary = "No protected apps selected"
        } else {
            var parts: [String] = []
            if appCount > 0 {
                parts.append("\(appCount) \(appCount == 1 ? "app" : "apps")")
            }
            if categoryCount > 0 {
                parts.append("\(categoryCount) \(categoryCount == 1 ? "category" : "categories")")
            }
            if webCount > 0 {
                parts.append("\(webCount) \(webCount == 1 ? "site" : "sites")")
            }
            restrictedAppsSummary = parts.joined(separator: ", ") + " selected"
        }
        #else
        restrictedAppsSummary = "App protection is available on iPhone."
        #endif
    }

    private func persistSelection() {
        #if os(iOS) && canImport(FamilyControls)
        guard let data = try? JSONEncoder().encode(selection) else { return }
        SharedAppGroup.publishScreenTimeSelectionData(data)
        #endif
    }

    private func restoreSelection() {
        #if os(iOS) && canImport(FamilyControls)
        guard
            let data = SharedAppGroup.screenTimeSelectionData(),
            let restoredSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }

        selection = SharedAppGroup.categoryInclusiveSelection(restoredSelection)
        #endif
    }

    private var isScreenTimeAuthorized: Bool {
        #if os(iOS) && canImport(FamilyControls)
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined, .denied:
            return false
        default:
            return true
        }
        #else
        return false
        #endif
    }

    #if os(iOS) && canImport(ManagedSettings)
    private func clearManagedShieldRestrictions() {
        managedStore.shield.applications = nil
        managedStore.shield.applicationCategories = nil
        managedStore.shield.webDomains = nil
    }

    private func finishActiveShieldConfigurationRefresh() {
        guard isShieldingEnabled else { return }
        applyShield(cancelPendingRefresh: false)
        shieldRefreshTask = nil
    }
    #endif

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
        let intervalStart = Self.unlockRelockMonitorStart(for: start, expiration: expiration)
        let schedule = DeviceActivitySchedule(
            intervalStart: Self.dateComponents(for: intervalStart, calendar: calendar),
            intervalEnd: Self.dateComponents(for: expiration, calendar: calendar),
            repeats: false
        )

        do {
            stopUnlockRelockMonitor()
            try activityCenter.startMonitoring(.checkpointUnlockWindow, during: schedule)
            SharedAppGroup.markUnlockRelockMonitorScheduled(intervalStart: intervalStart, expectedEnd: expiration)
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

    static func unlockRelockMonitorStart(for start: Date, expiration: Date) -> Date {
        let latestSafeStart = expiration.addingTimeInterval(-1)
        let leadInStart = start.addingTimeInterval(-unlockRelockMonitorLeadIn)
        return min(leadInStart, latestSafeStart)
    }
}
