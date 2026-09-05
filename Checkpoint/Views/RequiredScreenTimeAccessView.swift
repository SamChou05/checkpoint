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
    case continueAfterConnection
    case erase
    case none
}

enum ScreenTimeAccessState: Equatable {
    case permissionRequired
    case requesting
    case accessOff
    case requestFailed
    case unavailable
    case connected
    case eraseRecovery

    var status: String {
        switch self {
        case .permissionRequired:
            "Permission needed"
        case .requesting:
            "Requesting"
        case .accessOff:
            "Access off"
        case .requestFailed:
            "Request failed"
        case .unavailable:
            "iPhone required"
        case .connected:
            "Connected"
        case .eraseRecovery:
            "Recovery needed"
        }
    }

    var systemImage: String {
        switch self {
        case .permissionRequired:
            "checkmark.shield"
        case .requesting:
            "hourglass"
        case .accessOff:
            "exclamationmark.shield.fill"
        case .requestFailed:
            "arrow.clockwise"
        case .unavailable:
            "iphone.slash"
        case .connected:
            "checkmark.shield.fill"
        case .eraseRecovery:
            "trash"
        }
    }

    var tone: ScreenTimeAccessTone {
        switch self {
        case .permissionRequired:
            .informational
        case .requesting:
            .working
        case .accessOff, .eraseRecovery:
            .warning
        case .requestFailed:
            .failure
        case .unavailable:
            .warning
        case .connected:
            .success
        }
    }
}

enum ScreenTimeAccessTone: Equatable {
    case informational
    case working
    case warning
    case failure
    case success
}

enum ScreenTimeAccessMotionStyle: Equatable {
    case animated
    case identity
}

struct ScreenTimeAccessMotionPolicy {
    let style: ScreenTimeAccessMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var animation: Animation? {
        style == .animated ? CheckpointMotion.change : nil
    }

    var transition: AnyTransition {
        style == .animated
            ? .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
            : .identity
    }

    var permitsWorkingPulse: Bool {
        style == .animated
    }

    var permitsSuccessEffect: Bool {
        style == .animated
    }
}

struct ScreenTimeAccessFeedbackCoordinator: Equatable {
    private(set) var hasPresentedConnectedFeedback = false

    mutating func consumeConnectedTransition(
        state: ScreenTimeAccessState
    ) -> Bool {
        guard state == .connected else {
            hasPresentedConnectedFeedback = false
            return false
        }
        guard !hasPresentedConnectedFeedback else { return false }

        hasPresentedConnectedFeedback = true
        return true
    }
}

private enum ScreenTimeAccessPrivacyCopy {
    static let title = "Private by design"
    static let detail = "Checkpoint never reads or stores Screen Time activity."
}

enum ScreenTimeAccessLayoutElement: Hashable {
    case viewport
    case hero
    case statusMessage
    case actionBar
    case primaryAction
    case eraseLink
}

private enum ScreenTimeAccessFocusDestination: Hashable {
    case error
}

private let screenTimeAccessLayoutCoordinateSpaceName = "Checkpoint.ScreenTimeAccess.Layout"

private struct ScreenTimeAccessLayoutFrameReporter: ViewModifier {
    let element: ScreenTimeAccessLayoutElement
    let report: (@MainActor (ScreenTimeAccessLayoutElement, CGRect) -> Void)?

    func body(content: Content) -> some View {
        content.background {
            if let report {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(screenTimeAccessLayoutCoordinateSpaceName))

                    Color.clear
                        .onAppear {
                            report(element, frame)
                        }
                        .onChange(of: frame) { _, updatedFrame in
                            report(element, updatedFrame)
                        }
                }
            }
        }
    }
}

private extension View {
    func reportScreenTimeAccessLayoutFrame(
        _ element: ScreenTimeAccessLayoutElement,
        using report: (@MainActor (ScreenTimeAccessLayoutElement, CGRect) -> Void)?
    ) -> some View {
        modifier(ScreenTimeAccessLayoutFrameReporter(element: element, report: report))
    }
}

struct ScreenTimeAccessPresentation: Equatable {
    let state: ScreenTimeAccessState
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
    let showsPrivacyProofInHero: Bool

    init(
        context: ScreenTimeAccessContext,
        authorizationState: ScreenTimeController.AuthorizationState,
        requiresProtectedAppReselection: Bool,
        continuesOnboardingAfterDismissal: Bool = false
    ) {
        if context == .eraseRecovery {
            state = .eraseRecovery
        } else {
            switch authorizationState {
            case .unresolved, .notDetermined:
                state = .permissionRequired
            case .requesting:
                state = .requesting
            case .denied:
                state = .accessOff
            case .failed:
                state = .requestFailed
            case .unavailable:
                state = .unavailable
            case .approved, .approvedWithDataAccess:
                state = .connected
            }
        }
        showsPrivacyProofInHero = context == .initialSetup || context == .resumeSetup

        switch context {
        case .initialSetup:
            stage = "Screen Time"
            step = 1
            if state == .connected {
                heading = "Screen Time connected"
                detail = "Continue to create your goal, then choose the apps you want to protect."
                showsSetupSequence = false
            } else if authorizationState == .unavailable {
                heading = "Screen Time access needs an iPhone"
                detail = "Open Checkpoint on a supported iPhone to finish setup and choose the apps you want to protect."
                showsSetupSequence = false
            } else {
                heading = "Practice before you scroll."
                detail = "Choose apps. Clear a checkpoint for a timed break."
                showsSetupSequence = true
            }
            recoveryTitle = nil
            recoveryDetail = nil
            recoverySystemImage = nil
        case .resumeSetup:
            stage = "Resume setup"
            step = nil
            if state == .connected {
                heading = "Screen Time connected"
                detail = "Your goal is saved. Continue to choose the apps it will protect."
                showsSetupSequence = false
            } else if authorizationState == .unavailable {
                heading = "Finish setup on a supported iPhone"
                detail = "Your goal is saved. Open Checkpoint on an iPhone to reconnect Screen Time and choose protected apps."
                showsSetupSequence = false
            } else {
                heading = "Reconnect Screen Time to finish setup"
                detail = "Your goal is saved. Restore access, then finish choosing the apps it will protect."
                showsSetupSequence = true
            }
            recoveryTitle = nil
            recoveryDetail = nil
            recoverySystemImage = nil
        case .restoreProtection:
            stage = requiresProtectedAppReselection ? "Protection paused" : "Screen Time"
            step = nil
            if state == .connected, continuesOnboardingAfterDismissal {
                heading = "Screen Time connected"
                detail = requiresProtectedAppReselection
                    ? "Continue setup. Choose apps again after you finish your goal."
                    : "Continue your goal setup when you're ready."
                recoveryDetail = "Your goals, answers, and progress stayed saved while Screen Time access was off."
            } else if state == .connected, requiresProtectedAppReselection {
                heading = "Screen Time reconnected"
                detail = "Choose apps again to restore app protection."
                recoveryDetail = "Your goals, answers, and progress stayed saved while Screen Time access was off."
            } else if state == .connected {
                heading = "Screen Time connected"
                detail = "Return to Checkpoint when you're ready."
                recoveryDetail = "Your goals, answers, and progress stayed saved while Screen Time access was off."
            } else if authorizationState == .unavailable,
                      requiresProtectedAppReselection {
                heading = "App protection needs an iPhone"
                detail = "Open Checkpoint on a supported iPhone to reconnect Screen Time and restore app protection."
                recoveryDetail = "Your goals, answers, and progress stay saved until you can reconnect protection on an iPhone."
            } else if authorizationState == .unavailable {
                heading = "Screen Time access needs an iPhone"
                detail = "Open Checkpoint on a supported iPhone to restore Screen Time access."
                recoveryDetail = "Your goals, answers, and progress stay saved until you can reconnect on an iPhone."
            } else if requiresProtectedAppReselection {
                heading = "Reconnect app protection"
                detail = "Screen Time access changed, so protection is off and your previous app choices must be selected again."
                recoveryDetail = "Your goals, answers, and progress stay saved. After access returns, Checkpoint opens your protection list so you can choose apps again."
            } else {
                heading = "Reconnect Screen Time"
                detail = "Restore Screen Time access to continue using Checkpoint."
                recoveryDetail = "Your goals, answers, and progress stay saved while Screen Time access is off."
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
            statusMessage = "Checkpoint couldn’t complete the Screen Time request. Try again."
        case .unavailable:
            primaryAction = .none
            primaryTitle = nil
            primarySystemImage = nil
            statusMessage = nil
        case .approved, .approvedWithDataAccess:
            primaryAction = .continueAfterConnection
            switch context {
            case .initialSetup, .resumeSetup:
                primaryTitle = "Continue setup"
                primarySystemImage = "arrow.right"
            case .restoreProtection where continuesOnboardingAfterDismissal:
                primaryTitle = "Continue setup"
                primarySystemImage = "arrow.right"
            case .restoreProtection where requiresProtectedAppReselection:
                primaryTitle = "Choose apps again"
                primarySystemImage = "square.grid.2x2"
            case .restoreProtection:
                primaryTitle = "Return to Checkpoint"
                primarySystemImage = "arrow.right"
            case .eraseRecovery:
                primaryTitle = nil
                primarySystemImage = nil
            }
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
    let purchaseController: PurchaseController
    let context: ScreenTimeAccessContext
    private let reduceMotionOverride: Bool?
    private let layoutReporter: (@MainActor (ScreenTimeAccessLayoutElement, CGRect) -> Void)?
    private let onContinue: () -> Void
    private let continuesOnboardingAfterDismissal: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled
    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var focusedDestination: ScreenTimeAccessFocusDestination?
    @State private var isEraseConfirmationPresented = false
    @State private var connectedFeedbackSequence = 0
    @State private var feedbackCoordinator = ScreenTimeAccessFeedbackCoordinator()

    private let legalLinks = LegalLinks.current

    init(
        store: CheckpointStore,
        screenTime: ScreenTimeController,
        purchaseController: PurchaseController,
        context: ScreenTimeAccessContext = .initialSetup,
        onContinue: @escaping () -> Void = {},
        continuesOnboardingAfterDismissal: Bool = false,
        reduceMotionOverride: Bool? = nil,
        layoutReporter: (@MainActor (ScreenTimeAccessLayoutElement, CGRect) -> Void)? = nil
    ) {
        self.store = store
        self.screenTime = screenTime
        self.purchaseController = purchaseController
        self.context = context
        self.onContinue = onContinue
        self.continuesOnboardingAfterDismissal = continuesOnboardingAfterDismissal
        self.reduceMotionOverride = reduceMotionOverride
        self.layoutReporter = layoutReporter
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenTimeAccessHero(
                    presentation: accessPresentation,
                    reduceMotion: reduceMotion,
                    connectedFeedbackSequence: connectedFeedbackSequence
                )
                .reportScreenTimeAccessLayoutFrame(.hero, using: layoutReporter)

                if !accessPresentation.showsSetupSequence,
                   accessPresentation.recoveryTitle != nil {
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
                        .transition(accessMotionPolicy.transition)
                        .accessibilityFocused($focusedDestination, equals: .error)
                        .reportScreenTimeAccessLayoutFrame(.statusMessage, using: layoutReporter)
                        .id(message)
                }

                privacyFooter
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .reportScreenTimeAccessLayoutFrame(.viewport, using: layoutReporter)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if accessPresentation.primaryAction != .none {
                accessActionBar
                    .reportScreenTimeAccessLayoutFrame(.actionBar, using: layoutReporter)
            }
        }
        .checkpointScreenBackground()
        .coordinateSpace(name: screenTimeAccessLayoutCoordinateSpaceName)
        .sensoryFeedback(.success, trigger: connectedFeedbackSequence)
        .animation(
            accessMotionPolicy.animation,
            value: accessPresentation
        )
        .onAppear {
            focusAccessErrorIfNeeded()
            presentConnectedFeedbackIfNeeded()
        }
        .onChange(of: accessErrorMessage) { _, _ in
            focusAccessErrorIfNeeded()
        }
        .onChange(of: accessPresentation.state) { _, state in
            presentConnectedFeedbackIfNeeded(for: state)
        }
        .alert("Erase all Checkpoint data?", isPresented: $isEraseConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Erase all data", role: .destructive) {
                eraseAllData()
            }
        } message: {
            Text(CheckpointDataEraseCopy.warningMessage)
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
                case .openSettings:
                    PrimaryActionButton(
                        title: accessPresentation.primaryTitle ?? "Open iPhone Settings",
                        systemImage: accessPresentation.primarySystemImage ?? "gear"
                    ) {
                        openSystemSettings()
                    }
                case .continueAfterConnection:
                    PrimaryActionButton(
                        title: accessPresentation.primaryTitle ?? "Continue setup",
                        systemImage: accessPresentation.primarySystemImage ?? "arrow.right",
                        action: onContinue
                    )
                    .accessibilityIdentifier("screen-time-access-continue")
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
            .reportScreenTimeAccessLayoutFrame(.primaryAction, using: layoutReporter)
            .padding(.horizontal, 20)
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

    private var requiresDataEraseRecovery: Bool {
        screenTime.requiresSharedDataEraseRecovery
            || store.requiresPersistenceEraseRecovery
    }

    private var accessPresentation: ScreenTimeAccessPresentation {
        ScreenTimeAccessPresentation(
            context: requiresDataEraseRecovery ? .eraseRecovery : context,
            authorizationState: screenTime.authorizationState,
            requiresProtectedAppReselection: screenTime.requiresProtectedAppReselection,
            continuesOnboardingAfterDismissal: continuesOnboardingAfterDismissal
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
        if focusedDestination == .error {
            focusedDestination = nil
        }
        guard accessErrorMessage != nil,
              usesAssistiveNavigation else { return }

        Task { @MainActor in
            await Task.yield()
            guard accessErrorMessage != nil else { return }
            focusedDestination = .error
        }
    }

    private func presentConnectedFeedbackIfNeeded(
        for state: ScreenTimeAccessState? = nil
    ) {
        let state = state ?? accessPresentation.state
        guard feedbackCoordinator.consumeConnectedTransition(state: state) else { return }

        if accessMotionPolicy.permitsSuccessEffect {
            connectedFeedbackSequence += 1
        }

        guard usesAssistiveNavigation else { return }
        AccessibilityNotification.Announcement(
            "\(accessPresentation.heading). \(accessPresentation.detail)"
        ).post()
    }

    private var usesAssistiveNavigation: Bool {
        isVoiceOverEnabled || isSwitchControlEnabled
    }

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !accessPresentation.showsPrivacyProofInHero {
                Label(ScreenTimeAccessPrivacyCopy.title, systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                Text(ScreenTimeAccessPrivacyCopy.detail)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                .buttonStyle(CheckpointPressButtonStyle())
                .reportScreenTimeAccessLayoutFrame(.eraseLink, using: layoutReporter)
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
        CheckpointDataEraseCoordinator.eraseAllData(
            store: store,
            screenTime: screenTime,
            purchaseController: purchaseController
        )
    }

    private var accessMotionPolicy: ScreenTimeAccessMotionPolicy {
        ScreenTimeAccessMotionPolicy(reduceMotion: reduceMotion)
    }

}

struct ScreenTimeAccessHero: View {
    let presentation: ScreenTimeAccessPresentation
    let reduceMotion: Bool
    let connectedFeedbackSequence: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CheckpointHeroSurface(
            glowColor: accent,
            glowOpacity: presentation.state == .requesting ? 0.15 : 0.10,
            contentPadding: dynamicTypeSize.isAccessibilitySize ? 16 : 12
        ) {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 8) {
                heroIdentity

                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.heading)
                        .font(.title2.bold())
                        .foregroundStyle(CheckpointTheme.heroText)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .accessibilityAddTraits(.isHeader)

                    Text(presentation.detail)
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }

                if presentation.showsSetupSequence {
                    Divider()
                        .overlay(CheckpointTheme.heroDivider)

                    setupJourney
                }

                if presentation.showsPrivacyProofInHero {
                    Divider()
                        .overlay(CheckpointTheme.heroDivider)

                    privacyPromise
                }
            }
        }
        .animation(motionPolicy.animation, value: presentation.state)
    }

    @ViewBuilder
    private var heroIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                identity
                statusBadge
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    identity
                    Spacer(minLength: 6)
                    statusBadge
                }

                HStack(alignment: .center, spacing: 8) {
                    compactIdentity
                    Spacer(minLength: 4)
                    statusBadge
                }

                VStack(alignment: .leading, spacing: 10) {
                    identity
                    statusBadge
                }
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 11) {
            Image(systemName: presentation.state.systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(
                    accent.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(
                    .bounce,
                    options: .nonRepeating,
                    value: connectedFeedbackSequence
                )
                .symbolEffect(
                    .pulse,
                    options: .repeating,
                    isActive: presentation.state == .requesting
                        && motionPolicy.permitsWorkingPulse
                )
                .symbolEffectsRemoved(reduceMotion)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("CHECKPOINT")
                    .font(.caption2.weight(.bold))
                    .tracking(1.05)
                    .foregroundStyle(CheckpointTheme.heroText)

                Text(stageText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityContext)
    }

    private var compactIdentity: some View {
        HStack(spacing: 9) {
            Image(systemName: presentation.state.systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(
                    accent.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(
                    .bounce,
                    options: .nonRepeating,
                    value: connectedFeedbackSequence
                )
                .symbolEffect(
                    .pulse,
                    options: .repeating,
                    isActive: presentation.state == .requesting
                        && motionPolicy.permitsWorkingPulse
                )
                .symbolEffectsRemoved(reduceMotion)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("CHECKPOINT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(CheckpointTheme.heroText)

                Text(compactStageText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityContext)
    }

    private var statusBadge: some View {
        StatusBadge(text: presentation.state.status, tint: accent)
            .contentTransition(.opacity)
            .accessibilityLabel("Status: \(presentation.state.status)")
    }

    private var privacyPromise: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                privacyIcon
                privacyCopy
            }

            VStack(alignment: .leading, spacing: 8) {
                privacyIcon
                privacyCopy
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var setupJourney: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW IT WORKS")
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(CheckpointTheme.heroMuted)
                .accessibilityAddTraits(.isHeader)

            if usesStackedJourneyLayout {
                VStack(alignment: .leading, spacing: 8) {
                    verticalJourneyStep(
                        title: "Choose apps",
                        systemImage: "square.grid.2x2"
                    )
                    verticalJourneyStep(
                        title: "Clear a checkpoint",
                        systemImage: "checkmark.circle"
                    )
                    verticalJourneyStep(
                        title: "Unlock a timed break",
                        systemImage: "timer"
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    journeyStep(title: "Choose apps", systemImage: "square.grid.2x2")
                    journeyArrow
                    journeyStep(title: "Checkpoint", systemImage: "checkmark.circle")
                    journeyArrow
                    journeyStep(title: "Timed break", systemImage: "timer")
                }
            }
        }
    }

    private func journeyStep(title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 32, height: 32)
                .background(
                    CheckpointTheme.heroSubtleFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullJourneyTitle(for: title))
    }

    private var journeyArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(CheckpointTheme.heroMuted)
            .padding(.top, 11)
            .accessibilityHidden(true)
    }

    private func verticalJourneyStep(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.heroText)
            .symbolRenderingMode(.hierarchical)
            .tint(accent)
            .frame(minHeight: 34)
    }

    private var usesStackedJourneyLayout: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge ||
            dynamicTypeSize.isAccessibilitySize
    }

    private func fullJourneyTitle(for compactTitle: String) -> String {
        switch compactTitle {
        case "Checkpoint":
            "Clear a checkpoint"
        case "Timed break":
            "Unlock a timed break"
        default:
            compactTitle
        }
    }

    private var privacyIcon: some View {
        Image(systemName: "hand.raised.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 30, height: 30)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }

    private var privacyCopy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ScreenTimeAccessPrivacyCopy.title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)

            Text(ScreenTimeAccessPrivacyCopy.detail)
                .font(.caption)
                .foregroundStyle(CheckpointTheme.heroMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stageText: String {
        guard let step = presentation.step else {
            return presentation.stage.uppercased()
        }
        return "\(presentation.stage.uppercased()) · STEP \(step) OF 3"
    }

    private var compactStageText: String {
        guard let step = presentation.step else {
            return presentation.stage.uppercased()
        }
        return "STEP \(step) OF 3"
    }

    private var accessibilityContext: String {
        guard let step = presentation.step else {
            return "Checkpoint, \(presentation.stage)"
        }
        return "Checkpoint setup, step \(step) of 3, \(presentation.stage)"
    }

    private var accent: Color {
        switch presentation.state.tone {
        case .informational:
            CheckpointTheme.heroInfo
        case .working:
            CheckpointTheme.heroInfo
        case .warning:
            CheckpointTheme.heroWarning
        case .failure:
            CheckpointTheme.heroDanger
        case .success:
            CheckpointTheme.heroSuccess
        }
    }

    private var motionPolicy: ScreenTimeAccessMotionPolicy {
        ScreenTimeAccessMotionPolicy(reduceMotion: reduceMotion)
    }
}
