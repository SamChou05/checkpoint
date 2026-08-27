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

enum ScreenTimeAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case approved
    case approvedWithDataAccess
    case unavailable
}

@MainActor
protocol ScreenTimeAuthorizing: AnyObject {
    var authorizationStatus: ScreenTimeAuthorizationStatus { get }

    func requestAuthorization() async throws
}

@MainActor
final class SystemScreenTimeAuthorizer: ScreenTimeAuthorizing {
    var authorizationStatus: ScreenTimeAuthorizationStatus {
        #if os(iOS) && canImport(FamilyControls)
        let status = AuthorizationCenter.shared.authorizationStatus

        if #available(iOS 26.4, *), status == .approvedWithDataAccess {
            return .approvedWithDataAccess
        }

        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .approved:
            return .approved
        default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    func requestAuthorization() async throws {
        #if os(iOS) && canImport(FamilyControls)
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        #else
        throw SystemScreenTimeAuthorizationError.unavailable
        #endif
    }
}

private enum SystemScreenTimeAuthorizationError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "App protection is available on iPhone."
    }
}

@MainActor
@Observable
final class ScreenTimeController {
    static let unlockRelockMonitorLeadIn: TimeInterval = 30
    static let minimumUnlockRelockMonitorDuration: TimeInterval = 15 * 60
    static let unlockRelockMonitorDurationSafetyMargin: TimeInterval = 1
    nonisolated static let sharedDataEraseIncompleteKey = "checkpoint.screenTime.eraseIncomplete.v1"

    private enum Message {
        static let screenTimeUnavailable = "App protection is available on iPhone."
        static let sharedDataEraseFailed =
            "Checkpoint could not remove all shared Screen Time data. Try Erase all data again."
        static let applicationLimitExceeded = "The selected apps exceed iPhone's protection limit."
        static let webDomainLimitExceeded = "The selected websites exceed iPhone's protection limit."
        static let authorizationRequired =
            "Screen Time access is not approved yet. Allow Screen Time access before starting app protection."
    }

    enum SetupState: String {
        case notStarted = "Not set up"
        case authorized = "Authorized"
        case shieldActive = "Protection active"
        case temporarilyUnlocked = "Break in progress"
        case failed = "Needs attention"
        case unavailable = "Unavailable in this build"
    }

    enum AuthorizationState: Equatable {
        case unresolved
        case requesting
        case notDetermined
        case denied
        case approved
        case approvedWithDataAccess
        case failed
        case unavailable
    }

    var setupState: SetupState = .notStarted
    private(set) var authorizationState: AuthorizationState = .unresolved
    var restrictedAppsSummary = "No protected apps selected"
    var lastErrorMessage: String?
    var sharedDataEraseErrorMessage: String?
    var isShieldingEnabled = false

    var hasRequiredScreenTimeAuthorization: Bool {
        authorizationState == .approved || authorizationState == .approvedWithDataAccess
    }

    var requiresScreenTimeAuthorization: Bool {
        !hasRequiredScreenTimeAuthorization
    }

    var isRequestingAuthorization: Bool {
        authorizationState == .requesting
    }

    var requiresSharedDataEraseRecovery: Bool {
        isSharedDataErasePending
    }

    var userFacingProtectionStatus: String {
        if isShieldingEnabled {
            return "On"
        }

        switch setupState {
        case .temporarilyUnlocked:
            return "Break in progress"
        case .failed:
            return "Permission needed"
        case .unavailable:
            return "iPhone only"
        case .notStarted, .authorized, .shieldActive:
            return "Off"
        }
    }

    var userFacingErrorMessage: String? {
        if let sharedDataEraseErrorMessage {
            return sharedDataEraseErrorMessage
        }

        guard lastErrorMessage != nil else { return nil }

        #if os(iOS) && canImport(FamilyControls)
        let selectionLimitError = Self.selectionLimitError(for: selection)
        if selectionLimitError == Message.applicationLimitExceeded ||
            lastErrorMessage == Message.applicationLimitExceeded {
            return "Choose no more than \(SharedAppGroup.maximumShieldedApplicationCount) apps so iPhone can apply the full protection list."
        }

        if selectionLimitError == Message.webDomainLimitExceeded ||
            lastErrorMessage == Message.webDomainLimitExceeded {
            return "Choose no more than \(SharedAppGroup.maximumShieldedWebDomainCount) websites so iPhone can apply the full protection list."
        }
        #endif

        if lastErrorMessage?.hasPrefix("The break could not start") == true {
            return "The break couldn't start, so protection stayed on. Try again."
        }

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
            guard !isRestoringSelection else { return }
            persistSelection()
            updateSummary()
            handleSelectionChange()
        }
    }
    #endif

    #if os(iOS) && canImport(ManagedSettings)
    @ObservationIgnored private let managedStore = ManagedSettingsStore()
    #endif

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authorizer: any ScreenTimeAuthorizing
    @ObservationIgnored private let sharedDataEraser: () throws -> Void
    @ObservationIgnored private var relockTask: Task<Void, Never>?
    @ObservationIgnored private var shieldRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var isRestoringSelection = false
    @ObservationIgnored private var selectionSemanticsVersion = 0
    @ObservationIgnored private var hasStartedAuthorizationBootstrap = false
    @ObservationIgnored private var shouldReconcileAfterAuthorization = false
    @ObservationIgnored private var hasErasedAllData = false

    #if os(iOS) && canImport(DeviceActivity)
    @ObservationIgnored private let activityCenter = DeviceActivityCenter()
    #endif

    init(
        defaults: UserDefaults = SharedAppGroup.defaults,
        authorizer: any ScreenTimeAuthorizing = SystemScreenTimeAuthorizer(),
        sharedDataEraser: @escaping () throws -> Void = { try SharedAppGroup.eraseAllData() }
    ) {
        self.defaults = defaults
        self.authorizer = authorizer
        self.sharedDataEraser = sharedDataEraser
        // The system status supersedes this legacy one-time authorization flag.
        defaults.removeObject(forKey: "checkpoint.screenTime.initialAuthorizationRequested")

        if UserDefaults.standard.bool(forKey: Self.sharedDataEraseIncompleteKey) {
            do {
                try sharedDataEraser()
                UserDefaults.standard.removeObject(forKey: Self.sharedDataEraseIncompleteKey)
                UserDefaults.standard.synchronize()
            } catch {
                hasErasedAllData = true
                sharedDataEraseErrorMessage = Message.sharedDataEraseFailed
                stopUnlockRelockMonitor()
                #if os(iOS) && canImport(ManagedSettings)
                managedStore.clearAllSettings()
                #endif
                updateSummary()
                refreshAuthorizationStatus()
                return
            }
        }

        let hadPersistedData = SharedAppGroup.hasPersistedData
        hasErasedAllData = !hadPersistedData
        restoreSelection()
        updateSummary()
        shouldReconcileAfterAuthorization = hadPersistedData
        refreshAuthorizationStatus()
        if shouldReconcileAfterAuthorization {
            reconcileShieldState()
        }
    }

    func requestAuthorization() async {
        guard !blockForPendingSharedDataErase() else { return }
        authorizationState = .requesting

        do {
            hasErasedAllData = false
            try await authorizer.requestAuthorization()
            refreshAuthorizationStatus()
            updateSummary()
        } catch {
            handleAuthorizationRequestFailure(error)
        }
    }

    func bootstrapAuthorizationIfNeeded() async {
        guard !hasStartedAuthorizationBootstrap else { return }
        hasStartedAuthorizationBootstrap = true
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        switch authorizer.authorizationStatus {
        case .notDetermined:
            authorizationState = .notDetermined
            setupState = .notStarted
            lastErrorMessage = nil
        case .denied:
            let shouldDeactivateProtection = isShieldingEnabled ||
                setupState == .shieldActive ||
                setupState == .temporarilyUnlocked ||
                SharedAppGroup.desiredShieldActive ||
                SharedAppGroup.currentPendingShieldAttempt != nil
            authorizationState = .denied
            shouldReconcileAfterAuthorization = false
            invalidateSelectionAfterAuthorizationLoss()
            if shouldDeactivateProtection &&
                (isShieldingEnabled || SharedAppGroup.desiredShieldActive ||
                 SharedAppGroup.currentPendingShieldAttempt != nil) {
                deactivateProtection(refreshAuthorization: false)
            }
            setupState = .failed
            lastErrorMessage = "Screen Time access is denied. Allow Screen Time access before starting app protection."
        case .approved:
            authorizationState = .approved
            if setupState != .shieldActive && setupState != .temporarilyUnlocked {
                setupState = .authorized
            }
            lastErrorMessage = nil
            reconcileAfterAuthorizationIfNeeded()
        case .approvedWithDataAccess:
            authorizationState = .approvedWithDataAccess
            if setupState != .shieldActive && setupState != .temporarilyUnlocked {
                setupState = .authorized
            }
            lastErrorMessage = nil
            reconcileAfterAuthorizationIfNeeded()
        case .unavailable:
            authorizationState = .unavailable
            setupState = .unavailable
            restrictedAppsSummary = Message.screenTimeUnavailable
        }
    }

    private func handleAuthorizationRequestFailure(_ error: any Error) {
        switch authorizer.authorizationStatus {
        case .denied, .approved, .approvedWithDataAccess:
            // The completed system status outranks an accompanying request error.
            refreshAuthorizationStatus()
        case .notDetermined:
            authorizationState = .failed
            setupState = .failed
            lastErrorMessage = error.localizedDescription
        case .unavailable:
            authorizationState = .unavailable
            setupState = .unavailable
            restrictedAppsSummary = Message.screenTimeUnavailable
            lastErrorMessage = error.localizedDescription
        }

        if authorizationState != .unavailable {
            updateSummary()
        }
    }

    private func reconcileAfterAuthorizationIfNeeded() {
        guard shouldReconcileAfterAuthorization else { return }
        guard hasRequiredScreenTimeAuthorization else { return }

        shouldReconcileAfterAuthorization = false
        reconcileShieldState()
    }

    func applyShield() {
        guard !blockForPendingSharedDataErase() else {
            isShieldingEnabled = false
            return
        }
        guard !hasErasedAllData || hasSelection else {
            isShieldingEnabled = false
            lastErrorMessage = "Choose at least one protected app, category, or website before starting app protection."
            updateSummary()
            return
        }
        hasErasedAllData = false
        applyShield(cancelPendingRefresh: true)
    }

    private func applyShield(cancelPendingRefresh: Bool) {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        if cancelPendingRefresh {
            shieldRefreshTask?.cancel()
            shieldRefreshTask = nil
        }
        relockTask?.cancel()

        guard SharedAppGroup.isAvailable else {
            deactivateProtection(
                errorMessage: "Checkpoint's shared Screen Time storage is unavailable. Reinstall the app before starting protection."
            )
            return
        }

        guard hasSelection else {
            deactivateProtection(
                errorMessage: "Choose at least one protected app, category, or website before starting app protection."
            )
            return
        }

        guard SharedAppGroup.checkpointReady != false else {
            deactivateProtection(
                errorMessage: "Prepare a full checkpoint before starting app protection."
            )
            return
        }

        if let selectionLimitError = Self.selectionLimitError(for: selection) {
            deactivateProtection(errorMessage: selectionLimitError)
            return
        }

        guard hasRequiredScreenTimeAuthorization else {
            if authorizationState == .denied {
                deactivateProtection(refreshAuthorization: false)
            }
            setupState = .failed
            lastErrorMessage = Message.authorizationRequired
            return
        }

        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        applyCurrentSelectionToManagedStore()
        stopUnlockRelockMonitor()

        isShieldingEnabled = true
        setupState = .shieldActive
        lastErrorMessage = nil
        updateSummary()
        scheduleManagedShieldReassertion()
        #else
        setupState = .unavailable
        restrictedAppsSummary = Message.screenTimeUnavailable
        #endif
    }

    func refreshActiveShieldConfiguration() {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        guard isShieldingEnabled else { return }
        applyShield()
        #endif
    }

    func clearShield() {
        guard !hasErasedAllData else { return }
        guard isShieldingEnabled ||
                setupState == .shieldActive ||
                setupState == .temporarilyUnlocked ||
                SharedAppGroup.desiredShieldActive ||
                SharedAppGroup.currentPendingShieldAttempt != nil else {
            return
        }
        deactivateProtection()
    }

    func eraseAllData() {
        // Persist a tombstone outside the App Group so launch can retry an interrupted erase.
        UserDefaults.standard.set(true, forKey: Self.sharedDataEraseIncompleteKey)
        UserDefaults.standard.synchronize()
        hasErasedAllData = true
        shouldReconcileAfterAuthorization = false
        deactivateProtection()

        #if os(iOS) && canImport(FamilyControls)
        isRestoringSelection = true
        selection = FamilyActivitySelection(includeEntireCategory: true)
        isRestoringSelection = false
        selectionSemanticsVersion = SharedAppGroup.currentScreenTimeSelectionSemanticsVersion
        #endif

        do {
            try sharedDataEraser()
            UserDefaults.standard.removeObject(forKey: Self.sharedDataEraseIncompleteKey)
            UserDefaults.standard.synchronize()
            sharedDataEraseErrorMessage = nil
        } catch {
            sharedDataEraseErrorMessage = Message.sharedDataEraseFailed
        }
        lastErrorMessage = nil
        isShieldingEnabled = false
        refreshAuthorizationStatus()
        updateSummary()
    }

    @discardableResult
    func temporarilyUnshield(until expiration: Date) -> Bool {
        guard !hasErasedAllData else { return false }
        guard expiration > Date() else { return false }

        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        shieldRefreshTask?.cancel()
        shieldRefreshTask = nil

        guard hasSelection else {
            deactivateProtection()
            lastErrorMessage = "No protected apps are selected, so there is nothing to open."
            return false
        }

        if let selectionLimitError = Self.selectionLimitError(for: selection) {
            deactivateProtection(errorMessage: selectionLimitError)
            return false
        }

        guard SharedAppGroup.desiredShieldActive || isShieldingEnabled else {
            lastErrorMessage = "Protection is already off."
            return false
        }

        let now = Date()
        guard scheduleUnlockRelockMonitor(from: now, until: expiration) else {
            let schedulingError = lastErrorMessage
            applyShield()
            lastErrorMessage = schedulingError
            return false
        }

        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: expiration)
        managedStore.clearAllSettings()
        scheduleManagedShieldClearReassertion(while: .temporarilyUnlocked)
        isShieldingEnabled = false
        setupState = .temporarilyUnlocked
        lastErrorMessage = nil

        scheduleForegroundRelock(until: expiration)
        return true
        #else
        setupState = .unavailable
        return false
        #endif
    }

    func reconcileShieldState(protectionShouldRemainActive: Bool? = nil) {
        guard !hasErasedAllData else { return }
        let shouldRemainActive = protectionShouldRemainActive ?? SharedAppGroup.desiredShieldActive
        guard shouldRemainActive else {
            deactivateProtection()
            return
        }

        guard hasSelection else {
            deactivateProtection()
            return
        }

        guard hasRequiredScreenTimeAuthorization else {
            switch authorizationState {
            case .denied:
                deactivateProtection(refreshAuthorization: false)
                setupState = .failed
                lastErrorMessage = Message.authorizationRequired
            case .unavailable:
                setupState = .unavailable
            case .unresolved, .requesting, .notDetermined, .failed:
                // Preserve the persisted intent and opaque selection until
                // the launch authorization request resolves conclusively.
                shouldReconcileAfterAuthorization = true
            case .approved, .approvedWithDataAccess:
                break
            }
            return
        }

        if let selectionLimitError = Self.selectionLimitError(for: selection) {
            deactivateProtection(errorMessage: selectionLimitError)
            return
        }

        let unlockExpiration = SharedAppGroup.unlockExpiration
        if let unlockExpiration, unlockExpiration > Date() {
            shieldRefreshTask?.cancel()
            shieldRefreshTask = nil
            relockTask?.cancel()
            guard scheduleUnlockRelockMonitor(from: Date(), until: unlockExpiration) else {
                let schedulingError = lastErrorMessage
                applyShield()
                lastErrorMessage = schedulingError
                return
            }

            SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: unlockExpiration)

            #if os(iOS) && canImport(ManagedSettings)
            managedStore.clearAllSettings()
            scheduleManagedShieldClearReassertion(while: .temporarilyUnlocked)
            #endif

            setupState = .temporarilyUnlocked
            isShieldingEnabled = false
            lastErrorMessage = nil
            scheduleForegroundRelock(until: unlockExpiration)
            return
        }

        applyShield()
    }

    #if os(iOS) && canImport(FamilyControls)
    private static func selectionLimitError(
        for selection: FamilyActivitySelection
    ) -> String? {
        if selection.applicationTokens.count > SharedAppGroup.maximumShieldedApplicationCount {
            return Message.applicationLimitExceeded
        }
        if selection.webDomainTokens.count > SharedAppGroup.maximumShieldedWebDomainCount {
            return Message.webDomainLimitExceeded
        }
        return nil
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty ||
        usesLegacyCategoryEnforcement
    }

    @discardableResult
    func updateSelection(_ newSelection: FamilyActivitySelection) -> Bool {
        guard !blockForPendingSharedDataErase() else { return false }
        let normalizedSelection = SharedAppGroup.categoryInclusiveSelection(newSelection)
        let applicationCountIsAllowed = SharedAppGroup.canAcceptShieldTokenCount(
            normalizedSelection.applicationTokens.count,
            currentCount: selection.applicationTokens.count,
            maximumCount: SharedAppGroup.maximumShieldedApplicationCount
        )
        guard applicationCountIsAllowed else {
            lastErrorMessage = Message.applicationLimitExceeded
            return false
        }

        let webDomainCountIsAllowed = SharedAppGroup.canAcceptShieldTokenCount(
            normalizedSelection.webDomainTokens.count,
            currentCount: selection.webDomainTokens.count,
            maximumCount: SharedAppGroup.maximumShieldedWebDomainCount
        )
        guard webDomainCountIsAllowed else {
            lastErrorMessage = Message.webDomainLimitExceeded
            return false
        }

        if let selectionLimitError = Self.selectionLimitError(for: normalizedSelection) {
            lastErrorMessage = selectionLimitError
        } else if lastErrorMessage == Message.applicationLimitExceeded ||
                    lastErrorMessage == Message.webDomainLimitExceeded {
            lastErrorMessage = nil
        } else if !normalizedSelection.applicationTokens.isEmpty ||
                    !normalizedSelection.webDomainTokens.isEmpty ||
                    !normalizedSelection.categoryTokens.isEmpty {
            lastErrorMessage = nil
        }

        guard normalizedSelection != selection else { return true }

        hasErasedAllData = false
        selection = normalizedSelection
        return true
    }
    #else
    var hasSelection: Bool { false }
    #endif

    private func updateSummary() {
        #if os(iOS) && canImport(FamilyControls)
        let appCount = selection.applicationTokens.count
        let categoryCount = selection.categoryTokens.count
        let webCount = selection.webDomainTokens.count

        if !hasSelection {
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
        restrictedAppsSummary = Message.screenTimeUnavailable
        #endif
    }

    private func invalidateSelectionAfterAuthorizationLoss() {
        #if os(iOS) && canImport(FamilyControls)
        guard !selection.applicationTokens.isEmpty ||
                !selection.categoryTokens.isEmpty ||
                !selection.webDomainTokens.isEmpty
        else { return }

        // Revoked authorization invalidates every opaque FamilyActivitySelection token.
        selection = FamilyActivitySelection(includeEntireCategory: true)
        #endif
    }

    private func persistSelection(
        semanticsVersion: Int = SharedAppGroup.currentScreenTimeSelectionSemanticsVersion
    ) {
        #if os(iOS) && canImport(FamilyControls)
        guard !isSharedDataErasePending else { return }
        guard let data = try? JSONEncoder().encode(selection) else { return }
        selectionSemanticsVersion = semanticsVersion
        SharedAppGroup.publishScreenTimeSelectionData(data, semanticsVersion: semanticsVersion)
        #endif
    }

    private func restoreSelection() {
        #if os(iOS) && canImport(FamilyControls)
        let protectionSnapshot = SharedAppGroup.currentProtectionSnapshot()
        guard
            let data = protectionSnapshot.screenTimeSelectionData,
            let restoredSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }

        let normalizedSelection = SharedAppGroup.categoryInclusiveSelection(restoredSelection)
        let restoredSemanticsVersion = SharedAppGroup.resolvedScreenTimeSelectionSemanticsVersion(
            storedVersion: protectionSnapshot.screenTimeSelectionSemanticsVersion,
            applicationTokenCount: normalizedSelection.applicationTokens.count,
            webDomainTokenCount: normalizedSelection.webDomainTokens.count
        )
        let shouldUpgradeConcreteLegacySelection =
            restoredSemanticsVersion != protectionSnapshot.screenTimeSelectionSemanticsVersion
        selectionSemanticsVersion = restoredSemanticsVersion
        isRestoringSelection = true
        selection = normalizedSelection
        isRestoringSelection = false

        if normalizedSelection != restoredSelection || shouldUpgradeConcreteLegacySelection {
            persistSelection(semanticsVersion: restoredSemanticsVersion)
        }
        #endif
    }

    private func handleSelectionChange() {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        guard !isSharedDataErasePending else { return }
        guard hasSelection else {
            if isShieldingEnabled || setupState == .temporarilyUnlocked || SharedAppGroup.desiredShieldActive {
                deactivateProtection()
            }
            return
        }

        if isShieldingEnabled {
            applyShield()
        }
        #endif
    }

    private var isSharedDataErasePending: Bool {
        UserDefaults.standard.bool(forKey: Self.sharedDataEraseIncompleteKey)
    }

    @discardableResult
    private func blockForPendingSharedDataErase() -> Bool {
        guard isSharedDataErasePending else { return false }
        sharedDataEraseErrorMessage = Message.sharedDataEraseFailed
        return true
    }

    private func deactivateProtection(
        errorMessage: String? = nil,
        refreshAuthorization: Bool = true
    ) {
        shieldRefreshTask?.cancel()
        shieldRefreshTask = nil
        relockTask?.cancel()
        relockTask = nil
        SharedAppGroup.publishProtectionState(isActive: false, unlockExpiration: nil)
        _ = SharedAppGroup.consumePendingShieldAttempt()

        #if os(iOS) && canImport(ManagedSettings)
        stopUnlockRelockMonitor()
        managedStore.clearAllSettings()
        scheduleManagedShieldClearReassertion(while: .off)
        #endif

        isShieldingEnabled = false
        setupState = .notStarted
        if refreshAuthorization {
            refreshAuthorizationStatus()
        }
        if let errorMessage {
            lastErrorMessage = errorMessage
        }
        updateSummary()
    }

    #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
    private var usesLegacyCategoryEnforcement: Bool {
        SharedAppGroup.usesLegacyCategoryEnforcement(
            semanticsVersion: selectionSemanticsVersion,
            applicationTokenCount: selection.applicationTokens.count,
            categoryTokenCount: selection.categoryTokens.count,
            webDomainTokenCount: selection.webDomainTokens.count
        )
    }

    private func applyCurrentSelectionToManagedStore() {
        managedStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        // Expanded category tokens must not re-protect apps removed from that expansion.
        if usesLegacyCategoryEnforcement {
            managedStore.shield.applicationCategories = .specific(selection.categoryTokens, except: [])
        } else {
            managedStore.shield.applicationCategories = nil
        }
    }

    private func scheduleManagedShieldReassertion() {
        shieldRefreshTask?.cancel()
        shieldRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            guard let self,
                  self.isShieldingEnabled,
                  SharedAppGroup.desiredShieldActive,
                  SharedAppGroup.checkpointReady != false,
                  SharedAppGroup.unlockExpiration == nil,
                  self.hasSelection else { return }

            self.applyCurrentSelectionToManagedStore()
            self.shieldRefreshTask = nil
        }
    }

    private enum ManagedShieldClearMode {
        case off
        case temporarilyUnlocked
    }

    private func scheduleManagedShieldClearReassertion(while mode: ManagedShieldClearMode) {
        shieldRefreshTask?.cancel()
        shieldRefreshTask = Task { [weak self] in
            for delay in [UInt64(250_000_000), UInt64(750_000_000)] {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let self else { return }

                let shouldStayClear: Bool
                switch mode {
                case .off:
                    shouldStayClear = !SharedAppGroup.desiredShieldActive
                case .temporarilyUnlocked:
                    shouldStayClear = SharedAppGroup.desiredShieldActive &&
                        (SharedAppGroup.unlockExpiration ?? .distantPast) > Date()
                }

                guard shouldStayClear else { return }
                self.managedStore.clearAllSettings()
            }

            self?.shieldRefreshTask = nil
        }
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

    @discardableResult
    private func scheduleUnlockRelockMonitor(from start: Date, until expiration: Date) -> Bool {
        #if os(iOS) && canImport(DeviceActivity)
        let calendar = Calendar.current
        let monitorEnd = Self.unlockRelockMonitorEnd(for: expiration)

        if activityCenter.activities.contains(.checkpointUnlockWindow),
           let existingSchedule = activityCenter.schedule(for: .checkpointUnlockWindow),
           let existingEnd = calendar.date(from: existingSchedule.intervalEnd),
           abs(existingEnd.timeIntervalSince(monitorEnd)) < 0.5 {
            return true
        }

        let intervalStart = Self.unlockRelockMonitorStart(for: start, expiration: expiration)
        let schedule = DeviceActivitySchedule(
            intervalStart: Self.dateComponents(for: intervalStart, calendar: calendar),
            intervalEnd: Self.dateComponents(for: monitorEnd, calendar: calendar),
            repeats: false
        )

        do {
            stopUnlockRelockMonitor()
            try activityCenter.startMonitoring(.checkpointUnlockWindow, during: schedule)
            SharedAppGroup.markUnlockRelockMonitorScheduled(intervalStart: intervalStart, expectedEnd: monitorEnd)
            return true
        } catch {
            lastErrorMessage = "The break could not start because the system re-lock timer was unavailable: \(error.localizedDescription)"
            return false
        }
        #else
        return false
        #endif
    }

    private func stopUnlockRelockMonitor() {
        #if os(iOS) && canImport(DeviceActivity)
        guard activityCenter.activities.contains(.checkpointUnlockWindow) else { return }
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
        let leadInStart = start.addingTimeInterval(-unlockRelockMonitorLeadIn)
        let minimumDurationStart = expiration.addingTimeInterval(
            -minimumUnlockRelockMonitorDuration - unlockRelockMonitorDurationSafetyMargin
        )
        return min(leadInStart, minimumDurationStart)
    }

    static func unlockRelockMonitorEnd(for expiration: Date) -> Date {
        Date(timeIntervalSince1970: ceil(expiration.timeIntervalSince1970))
    }
}
