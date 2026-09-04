import Accessibility
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum ScreenTimeAccessContext: Equatable {
    case initialSetup
    case resumeSetup
    case restoreProtection
    case eraseRecovery

    static func resolve(
        requiresEraseRecovery: Bool,
        isFirstRunPending: Bool,
        hasGoal: Bool
    ) -> Self {
        if requiresEraseRecovery {
            return .eraseRecovery
        }
        if !hasGoal {
            return .initialSetup
        }
        if isFirstRunPending {
            return .resumeSetup
        }
        return .restoreProtection
    }
}

enum ScreenTimeAccessPrimaryAction: Equatable {
    case request
    case retry
    case openSettings
    case erase
    case unavailable
    case none
}

struct ScreenTimeAccessPresentation: Equatable {
    let stage: String
    let step: Int?
    let heading: String
    let detail: String
    let primaryAction: ScreenTimeAccessPrimaryAction
    let primaryTitle: String?
    let primarySystemImage: String?
    let isWorking: Bool
    let showsSetupSequence: Bool
    let recoveryTitle: String?
    let recoveryDetail: String?
    let recoverySystemImage: String?
    let statusMessage: String?

    init(
        context: ScreenTimeAccessContext,
        authorizationState: ScreenTimeController.AuthorizationState,
        requiresProtectedAppReselection: Bool
    ) {
        switch context {
        case .initialSetup:
            stage = "Screen Time"
            step = 1
            heading = "Practice before you scroll."
            detail = "Choose apps you want to use more intentionally. Clear a short, goal-based checkpoint to take a timed break."
            showsSetupSequence = true
            recoveryTitle = nil
            recoveryDetail = nil
            recoverySystemImage = nil
        case .resumeSetup:
            stage = "Resume setup"
            step = nil
            heading = "Reconnect Screen Time to finish setup"
            detail = "Your goal is saved. Restore access, then finish choosing the apps it will protect."
            showsSetupSequence = true
            recoveryTitle = nil
            recoveryDetail = nil
            recoverySystemImage = nil
        case .restoreProtection:
            stage = "Protection paused"
            step = nil
            heading = "Reconnect app protection"
            if requiresProtectedAppReselection {
                detail = "Screen Time access changed, so protection is off and your previous app choices must be selected again."
                recoveryDetail = "Your goals, answers, and progress stay saved. After access returns, Checkpoint opens your protection list so you can choose apps again."
            } else {
                detail = "Restore Screen Time access to keep using app protection."
                recoveryDetail = "Your goals, answers, and progress stay saved. Restoring access reconnects protection without changing your practice data."
            }
            showsSetupSequence = false
            recoveryTitle = "Your learning data is safe"
            recoverySystemImage = "lock.shield.fill"
        case .eraseRecovery:
            stage = "Data recovery"
            step = nil
            heading = "Finish erasing Checkpoint data"
            detail = "Checkpoint must verify that its local app and Screen Time data are removed before you can continue or create a new goal."
            showsSetupSequence = false
            recoveryTitle = nil
            recoveryDetail = nil
            recoverySystemImage = nil
        }

        isWorking = authorizationState == .requesting && context != .eraseRecovery

        if context == .eraseRecovery {
            primaryAction = .erase
            primaryTitle = "Retry data erasure"
            primarySystemImage = "trash"
            statusMessage = nil
            return
        }

        switch authorizationState {
        case .unresolved, .notDetermined:
            primaryAction = .request
            primaryTitle = "Allow Screen Time"
            primarySystemImage = "checkmark.shield"
            statusMessage = nil
        case .requesting:
            primaryAction = .request
            primaryTitle = "Requesting access"
            primarySystemImage = "checkmark.shield"
            statusMessage = nil
        case .denied:
            primaryAction = .openSettings
            primaryTitle = "Open iPhone Settings"
            primarySystemImage = "gear"
            statusMessage = "Screen Time access is off. Open iPhone Settings, allow access for Checkpoint, then return here."
        case .failed:
            primaryAction = .retry
            primaryTitle = "Try Screen Time access again"
            primarySystemImage = "arrow.clockwise"
            statusMessage = "Screen Time access wasn’t granted. Try again to continue."
        case .unavailable:
            primaryAction = .unavailable
            primaryTitle = nil
            primarySystemImage = nil
            statusMessage = nil
        case .approved, .approvedWithDataAccess:
            primaryAction = .none
            primaryTitle = nil
            primarySystemImage = nil
            statusMessage = nil
        }
    }
}

enum ScreenTimeAccessRecoveryRouting {
    static func shouldPresentProtectedApps(
        context: ScreenTimeAccessContext,
        authorizationBecameAvailable: Bool,
        requiresProtectedAppReselection: Bool
    ) -> Bool {
        context == .restoreProtection &&
            authorizationBecameAvailable &&
            requiresProtectedAppReselection
    }
}

struct RequiredScreenTimeAccessView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let context: ScreenTimeAccessContext
    private let reduceMotionOverride: Bool?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var isStatusFocused: Bool
    @State private var isEraseConfirmationPresented = false

    private let legalLinks = LegalLinks.current

    init(
        store: CheckpointStore,
        screenTime: ScreenTimeController,
        context: ScreenTimeAccessContext = .initialSetup,
        reduceMotionOverride: Bool? = nil
    ) {
        self.store = store
        self.screenTime = screenTime
        self.context = context
        self.reduceMotionOverride = reduceMotionOverride
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 20)

                CheckpointSetupMark(
                    stage: accessPresentation.stage,
                    step: accessPresentation.step,
                    isWorking: accessPresentation.isWorking
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(accessPresentation.heading)
                        .font(.largeTitle.bold())
                        .foregroundStyle(CheckpointTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(accessPresentation.detail)
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentTransition(.opacity)

                if accessPresentation.showsSetupSequence {
                    setupSequencePanel
                } else if accessPresentation.recoveryTitle != nil {
                    recoveryPanel
                }

                if let message = accessErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(
                            CheckpointTheme.coral.opacity(0.08),
                            in: RoundedRectangle(
                                cornerRadius: CheckpointTheme.compactCornerRadius,
                                style: .continuous
                            )
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .accessibilityFocused($isStatusFocused)
                        .id(message)
                }

                privacyFooter
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if accessPresentation.primaryAction != .none {
                accessActionBar
            }
        }
        .checkpointScreenBackground()
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: accessPresentation
        )
        .onAppear {
            focusAccessErrorIfNeeded()
        }
        .onChange(of: accessErrorMessage) { _, _ in
            focusAccessErrorIfNeeded()
        }
        .alert("Erase all Checkpoint data?", isPresented: $isEraseConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Erase all data", role: .destructive) {
                eraseAllData()
            }
        } message: {
            Text("This removes goals, progress, protected-app selections, diagnostics, and the anonymous backend install ID.")
        }
    }

    @ViewBuilder
    private var accessActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            Group {
                switch accessPresentation.primaryAction {
                case .erase:
                    PrimaryActionButton(
                        title: accessPresentation.primaryTitle ?? "Retry data erasure",
                        systemImage: accessPresentation.primarySystemImage ?? "trash"
                    ) {
                        eraseAllData()
                    }
                case .unavailable:
                    Label(
                        "Screen Time app protection requires a supported iPhone build.",
                        systemImage: "iphone.slash"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .openSettings:
                    PrimaryActionButton(
                        title: accessPresentation.primaryTitle ?? "Open iPhone Settings",
                        systemImage: accessPresentation.primarySystemImage ?? "gear"
                    ) {
                        openSystemSettings()
                    }
                case .request, .retry:
                    PrimaryActionButton(
                        title: accessPresentation.primaryTitle ?? "Allow Screen Time",
                        systemImage: accessPresentation.primarySystemImage ?? "checkmark.shield",
                        isLoading: accessPresentation.isWorking
                    ) {
                        Task {
                            await screenTime.requestAuthorization()
                        }
                    }
                    .disabled(accessPresentation.isWorking)
                case .none:
                    EmptyView()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var recoveryPanel: some View {
        SectionPanel {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: accessPresentation.recoverySystemImage ?? "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 42, height: 42)
                    .background(
                        CheckpointTheme.teal.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(accessPresentation.recoveryTitle ?? "Your learning data is safe")
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.text)

                    Text(accessPresentation.recoveryDetail ?? "")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
    }

    private var setupSequencePanel: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("HOW IT WORKS")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(CheckpointTheme.muted)
                    .accessibilityAddTraits(.isHeader)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        sequenceStep(title: "Choose apps", systemImage: "square.grid.2x2")
                        sequenceArrow
                        sequenceStep(title: "Clear a checkpoint", systemImage: "checkmark.circle")
                        sequenceArrow
                        sequenceStep(title: "Unlock a timed break", systemImage: "timer")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        verticalSequenceStep(title: "Choose apps", systemImage: "square.grid.2x2")
                        verticalSequenceStep(title: "Clear a checkpoint", systemImage: "checkmark.circle")
                        verticalSequenceStep(title: "Unlock a timed break", systemImage: "timer")
                    }
                }
            }
        }
    }

    private func sequenceStep(title: String, systemImage: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 36, height: 36)
                .background(
                    CheckpointTheme.teal.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var sequenceArrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(CheckpointTheme.muted.opacity(0.7))
            .padding(.top, 12)
            .accessibilityHidden(true)
    }

    private func verticalSequenceStep(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .symbolRenderingMode(.hierarchical)
            .tint(CheckpointTheme.teal)
            .frame(minHeight: 36)
    }

    private var requiresDataEraseRecovery: Bool {
        screenTime.requiresSharedDataEraseRecovery
            || store.requiresPersistenceEraseRecovery
    }

    private var accessPresentation: ScreenTimeAccessPresentation {
        ScreenTimeAccessPresentation(
            context: requiresDataEraseRecovery ? .eraseRecovery : context,
            authorizationState: screenTime.authorizationState,
            requiresProtectedAppReselection: screenTime.requiresProtectedAppReselection
        )
    }

    private var accessErrorMessage: String? {
        if requiresDataEraseRecovery {
            return store.persistenceRecoveryMessage
                ?? screenTime.sharedDataEraseErrorMessage
                ?? "Checkpoint could not finish erasing local data."
        }

        return accessPresentation.statusMessage ?? screenTime.userFacingErrorMessage
    }

    private func focusAccessErrorIfNeeded() {
        isStatusFocused = false
        guard accessErrorMessage != nil else { return }

        Task { @MainActor in
            await Task.yield()
            guard accessErrorMessage != nil else { return }
            isStatusFocused = true
        }
    }

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Uses Apple Screen Time", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)

            Text("You choose what to protect. Checkpoint does not read or store your Screen Time activity history.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    legalLinkItems
                }

                VStack(alignment: .leading, spacing: 0) {
                    legalLinkItems
                }
            }

            if store.isMember,
               let subscriptionURL = URL(string: "https://apps.apple.com/account/subscriptions") {
                compactAccessLink(title: "Manage subscription", url: subscriptionURL)
            }

            if shouldOfferDataErase {
                Divider()

                Button(role: .destructive) {
                    isEraseConfirmationPresented = true
                } label: {
                    Label("Erase all Checkpoint data", systemImage: "trash")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var legalLinkItems: some View {
        if let privacyPolicyURL = legalLinks.privacyPolicyURL {
            compactAccessLink(title: "Privacy", url: privacyPolicyURL)
        }
        compactAccessLink(title: "Terms", url: LegalLinks.termsOfUseURL)
        if let supportURL = legalLinks.supportURL {
            compactAccessLink(title: "Support", url: supportURL)
        }
    }

    private func compactAccessLink(title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private var shouldOfferDataErase: Bool {
        !requiresDataEraseRecovery
            && (!store.hasNoPersistedAppData || screenTime.hasSelection)
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }

    private func eraseAllData() {
        screenTime.eraseAllData()
        store.eraseAllData()
    }

}
