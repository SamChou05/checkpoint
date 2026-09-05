import SwiftUI

enum ProtectionSettingsControlLayout: Equatable {
    case unavailable
    case requestingAuthorization
    case authorizationRequired
    case chooseApps
    case startAndEditApps
    case editApps
}

enum SettingsProtectionState: Equatable {
    case active
    case breakInProgress(relockReadiness: HomeActiveBreakRelockReadiness)
    case unavailable
    case requestingAuthorization
    case authorizationRequired
    case permissionRequired
    case chooseApps
    case startingProtection
    case preparingPractice
    case checkpointRequired
    case ready
}

enum SettingsProtectionTone: Equatable {
    case active
    case breakInProgress
    case unavailable
    case attention
    case setup
    case preparing

    var color: Color {
        switch self {
        case .active:
            CheckpointTheme.teal
        case .breakInProgress, .preparing:
            CheckpointTheme.amber
        case .unavailable:
            CheckpointTheme.muted
        case .attention:
            CheckpointTheme.coral
        case .setup:
            CheckpointTheme.blue
        }
    }
}

struct SettingsProtectionPresentation: Equatable {
    let state: SettingsProtectionState
    let restrictedAppsSummary: String

    init(
        setupState: ScreenTimeController.SetupState,
        isShieldingEnabled: Bool,
        authorizationState: ScreenTimeController.AuthorizationState,
        hasSelection: Bool,
        hasReadyCheckpointSet: Bool,
        isStartingProtection: Bool,
        isPreparingPractice: Bool,
        breakRelockReadiness: HomeActiveBreakRelockReadiness = .ready,
        restrictedAppsSummary: String
    ) {
        self.restrictedAppsSummary = restrictedAppsSummary

        if isShieldingEnabled {
            state = .active
        } else if setupState == .temporarilyUnlocked {
            state = .breakInProgress(relockReadiness: breakRelockReadiness)
        } else if setupState == .unavailable || authorizationState == .unavailable {
            state = .unavailable
        } else if authorizationState == .requesting {
            state = .requestingAuthorization
        } else if setupState == .failed
                    || authorizationState == .denied
                    || authorizationState == .failed {
            state = .permissionRequired
        } else if authorizationState == .unresolved
                    || authorizationState == .notDetermined {
            state = .authorizationRequired
        } else if !hasSelection {
            state = .chooseApps
        } else if isStartingProtection {
            state = .startingProtection
        } else if isPreparingPractice {
            state = .preparingPractice
        } else if hasReadyCheckpointSet {
            state = .ready
        } else {
            state = .checkpointRequired
        }
    }

    var controlLayout: ProtectionSettingsControlLayout {
        switch state {
        case .unavailable:
            .unavailable
        case .requestingAuthorization:
            .requestingAuthorization
        case .authorizationRequired, .permissionRequired:
            .authorizationRequired
        case .chooseApps:
            .chooseApps
        case .active, .breakInProgress:
            .editApps
        case .startingProtection, .preparingPractice, .checkpointRequired, .ready:
            .startAndEditApps
        }
    }

    var statusText: String {
        switch state {
        case .active:
            "On"
        case .breakInProgress:
            "Break in progress"
        case .unavailable:
            "iPhone only"
        case .requestingAuthorization:
            "Requesting access"
        case .authorizationRequired:
            "Not set up"
        case .permissionRequired:
            "Permission needed"
        case .chooseApps, .startingProtection, .preparingPractice, .checkpointRequired, .ready:
            "Off"
        }
    }

    var detail: String {
        switch state {
        case .active:
            "Selected apps pause at a goal-based checkpoint."
        case let .breakInProgress(relockReadiness):
            switch relockReadiness {
            case .ready:
                "Your timed break is active; protection restarts automatically."
            case .waitingForCheckpoint:
                "Your timed break is active. Protection turns back on only if another checkpoint is ready."
            case .needsAttention:
                "Your timed break is active. Protection needs attention before it can turn back on."
            }
        case .unavailable:
            "App protection is available on iPhone."
        case .requestingAuthorization:
            "Waiting for iPhone to confirm Screen Time access."
        case .authorizationRequired:
            "Allow Screen Time to set up private, on-device protection."
        case .permissionRequired:
            "Screen Time access is not approved, so app protection is off."
        case .chooseApps:
            "Choose the apps you want to use more intentionally."
        case .startingProtection:
            "Checkpoint is checking the practice set before protection starts."
        case .preparingPractice:
            "Checkpoint is preparing a full practice set. Start protection when it’s ready."
        case .checkpointRequired:
            "Your apps are selected; a full practice set is still needed."
        case .ready:
            "Your apps and practice set are ready to protect."
        }
    }

    var systemImage: String {
        switch state {
        case .active:
            "checkmark.shield.fill"
        case .breakInProgress:
            "timer"
        case .unavailable:
            "iphone.slash"
        case .permissionRequired:
            "exclamationmark.shield.fill"
        case .authorizationRequired:
            "shield.lefthalf.filled"
        case .chooseApps:
            "checklist"
        case .startingProtection, .preparingPractice:
            "clock.arrow.circlepath"
        case .requestingAuthorization, .checkpointRequired, .ready:
            "shield"
        }
    }

    var tone: SettingsProtectionTone {
        switch state {
        case .active:
            .active
        case .breakInProgress:
            .breakInProgress
        case .unavailable:
            .unavailable
        case .permissionRequired:
            .attention
        case .startingProtection, .preparingPractice, .checkpointRequired:
            .preparing
        case .requestingAuthorization, .authorizationRequired, .chooseApps, .ready:
            .setup
        }
    }

    var statusClass: SettingsProtectionStatusClass {
        Self.statusClass(for: state)
    }

    static func statusClass(
        for state: SettingsProtectionState
    ) -> SettingsProtectionStatusClass {
        switch state {
        case .active:
            .active
        case .breakInProgress:
            .breakInProgress
        case .unavailable:
            .unavailable
        case .permissionRequired:
            .permissionRequired
        case .requestingAuthorization,
             .authorizationRequired,
             .chooseApps,
             .startingProtection,
             .preparingPractice,
             .checkpointRequired,
             .ready:
            .off
        }
    }

    var canStopBlocking: Bool {
        switch state {
        case .active, .breakInProgress:
            true
        case .unavailable,
             .requestingAuthorization,
             .authorizationRequired,
             .permissionRequired,
             .chooseApps,
             .startingProtection,
             .preparingPractice,
             .checkpointRequired,
             .ready:
            false
        }
    }

    var showsProtectionStartProgress: Bool {
        state == .startingProtection
    }

    var disablesProtectionStart: Bool {
        state == .startingProtection || state == .preparingPractice
    }

    var visibleRestrictedAppsSummary: String? {
        let summary = restrictedAppsSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty,
              Self.comparableSentence(summary) != Self.comparableSentence(detail) else {
            return nil
        }
        return summary
    }

    var accessibilityValue: String {
        let summary = visibleRestrictedAppsSummary.map(Self.sentence)
        return ([Self.sentence(statusText), detail] + [summary].compactMap { $0 })
            .joined(separator: " ")
    }

    private static func comparableSentence(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
    }

    private static func sentence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last,
              !last.isPunctuation else {
            return trimmed
        }
        return "\(trimmed)."
    }
}

enum SettingsProtectionStatusClass: Equatable {
    case off
    case active
    case breakInProgress
    case permissionRequired
    case unavailable
}

struct SettingsProtectionTransitionPolicy {
    static func shouldClearActionMessage(
        from oldState: SettingsProtectionState,
        to newState: SettingsProtectionState
    ) -> Bool {
        guard oldState != newState else { return false }

        if newState == .ready {
            return true
        }

        if newState == .preparingPractice,
           oldState != .startingProtection {
            return true
        }

        return SettingsProtectionPresentation.statusClass(for: oldState)
            != SettingsProtectionPresentation.statusClass(for: newState)
    }

    static func shouldAnnounce(
        from oldState: SettingsProtectionState,
        to newState: SettingsProtectionState,
        hasConcreteError: Bool
    ) -> Bool {
        guard !hasConcreteError else { return false }

        if case .breakInProgress = oldState,
           case .breakInProgress = newState,
           oldState != newState {
            return true
        }

        if oldState == .startingProtection {
            return false
        }

        let oldStatusClass = SettingsProtectionPresentation.statusClass(for: oldState)
        let newStatusClass = SettingsProtectionPresentation.statusClass(for: newState)
        if oldStatusClass != newStatusClass {
            return true
        }

        guard oldStatusClass == .off else { return false }

        if newState == .requestingAuthorization
            || newState == .startingProtection {
            return false
        }

        return oldState != newState
    }
}

struct SettingsProtectionMotionPolicy: Equatable {
    let reduceMotion: Bool

    var animation: Animation? {
        CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)
    }

    var animatesActivationSymbol: Bool {
        !reduceMotion
    }

    func emphasizesTransition(
        from oldState: SettingsProtectionState,
        to newState: SettingsProtectionState
    ) -> Bool {
        animatesActivationSymbol
            && oldState != .active
            && newState == .active
    }
}

struct SettingsProtectionStatusHeader: View {
    let presentation: SettingsProtectionPresentation

    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activationSymbolSequence = 0

    init(
        presentation: SettingsProtectionPresentation,
        reduceMotionOverride: Bool? = nil
    ) {
        self.presentation = presentation
        self.reduceMotionOverride = reduceMotionOverride
    }

    var body: some View {
        headerLayout
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("App protection")
            .accessibilityValue(presentation.accessibilityValue)
            .animation(motionPolicy.animation, value: presentation.state)
            .onChange(of: presentation.state) { oldState, newState in
                guard motionPolicy.emphasizesTransition(
                    from: oldState,
                    to: newState
                ) else { return }
                activationSymbolSequence += 1
            }
    }

    @ViewBuilder
    private var headerLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                protectionIcon
                statusCopy
                statusBadge
            }
        } else if dynamicTypeSize > .large {
            VStack(alignment: .leading, spacing: 10) {
                regularIdentity
                statusBadge
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    inlineIdentity
                    Spacer(minLength: 8)
                    statusBadge
                }

                VStack(alignment: .leading, spacing: 10) {
                    regularIdentity
                    statusBadge
                }
            }
        }
    }

    private var inlineIdentity: some View {
        regularIdentity
            .frame(maxWidth: 220, alignment: .leading)
    }

    private var regularIdentity: some View {
        HStack(spacing: 12) {
            protectionIcon
            statusCopy
        }
    }

    private var protectionIcon: some View {
        Image(systemName: presentation.systemImage)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(presentation.tone.color)
            .frame(width: 42, height: 42)
            .background(
                presentation.tone.color.opacity(0.13),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, options: .nonRepeating, value: activationSymbolSequence)
            .symbolEffectsRemoved(!motionPolicy.animatesActivationSymbol)
            .accessibilityHidden(true)
    }

    private var statusCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("App protection")
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)

            Text(presentation.detail)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.interpolate)
        }
    }

    private var statusBadge: some View {
        StatusBadge(
            text: presentation.statusText,
            tint: presentation.tone.color
        )
        .contentTransition(.interpolate)
    }

    private var motionPolicy: SettingsProtectionMotionPolicy {
        SettingsProtectionMotionPolicy(
            reduceMotion: reduceMotionOverride ?? systemReduceMotion
        )
    }
}

enum AdvancedSettingsAction: String, Identifiable {
    case resetData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resetData:
            return "Erase all data?"
        }
    }

    var detail: String {
        switch self {
        case .resetData:
            return "This erases goals, progress, protected-app selections, local diagnostics, and the anonymous backend install ID, then turns off app protection. Your App Store subscription and iOS Screen Time permission are not canceled. This can't be undone."
        }
    }

    var confirmationPhrase: String {
        switch self {
        case .resetData:
            return "RESET"
        }
    }

    var buttonTitle: String {
        switch self {
        case .resetData:
            return "Erase all data"
        }
    }

    var systemImage: String {
        switch self {
        case .resetData:
            return "arrow.counterclockwise"
        }
    }
}

struct AdvancedConfirmationView: View {
    let action: AdvancedSettingsAction
    let store: CheckpointStore
    let screenTime: ScreenTimeController

    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""
    @State private var actionErrorMessage: String?
    @AccessibilityFocusState private var isActionErrorFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(action.title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text(action.detail)
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Confirm") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Type \(action.confirmationPhrase) to continue.")
                                .font(.subheadline)
                                .foregroundStyle(CheckpointTheme.muted)

                            TextField(action.confirmationPhrase, text: $confirmationText)
                                .textFieldStyle(.plain)
                                .font(.headline)
                                .foregroundStyle(CheckpointTheme.text)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel("Confirmation phrase")
                                .accessibilityHint("Type \(action.confirmationPhrase) to continue.")

                            Button(role: .destructive) {
                                performAction()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: action.systemImage)

                                    Text(action.buttonTitle)
                                }
                                .font(.headline)
                                .foregroundStyle(CheckpointTheme.paper)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .padding(.horizontal, 12)
                                .background(
                                    CheckpointTheme.destructiveFill,
                                    in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                                )
                            }
                            .buttonStyle(CheckpointPressButtonStyle())
                            .disabled(!isConfirmed)
                            .opacity(isConfirmed ? 1 : 0.58)
                            .accessibilityLabel(action.buttonTitle)

                            if let actionErrorMessage {
                                Label(actionErrorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.coral)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityFocused($isActionErrorFocused)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle(action.buttonTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
        }
    }

    private var isConfirmed: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == action.confirmationPhrase
    }

    private func performAction() {
        actionErrorMessage = nil

        switch action {
        case .resetData:
            screenTime.eraseAllData()
            store.eraseAllData()
        }

        let recoveryMessages = [
            screenTime.sharedDataEraseErrorMessage,
            store.persistenceRecoveryMessage
        ].compactMap { $0 }

        guard recoveryMessages.isEmpty else {
            let message = recoveryMessages.joined(separator: " ")
            actionErrorMessage = message
            Task { @MainActor in
                await Task.yield()
                isActionErrorFocused = true
            }
            return
        }

        AccessibilityNotification.Announcement("All Checkpoint data was erased.").post()
        dismiss()
    }
}

enum SettingsPlanState: Equatable, Sendable {
    case free
    case pendingPurchase
    case pro
}

struct SettingsPlanPresentation: Equatable, Sendable {
    let state: SettingsPlanState

    init(
        membershipTier: MembershipTier,
        purchaseNotice: MembershipPurchaseNotice?
    ) {
        if membershipTier == .member {
            state = .pro
        } else if purchaseNotice?.isPending == true {
            state = .pendingPurchase
        } else {
            state = .free
        }
    }

    var planName: String {
        switch state {
        case .free:
            "Checkpoint Free"
        case .pendingPurchase, .pro:
            "Checkpoint Pro"
        }
    }

    var badgeText: String {
        switch state {
        case .free:
            "FREE"
        case .pendingPurchase:
            "PENDING"
        case .pro:
            "PRO ACTIVE"
        }
    }

    var headline: String {
        switch state {
        case .free:
            "Protection for one focused goal."
        case .pendingPurchase:
            "Your purchase is awaiting approval."
        case .pro:
            "Your practice stays in motion."
        }
    }

    var detail: String {
        switch state {
        case .free:
            "Explore Pro for up to \(ProductLimits.memberGoalProfileLimit) goals, fresh checkpoints, and adaptive Next Focus."
        case .pendingPurchase:
            "Pro unlocks as soon as the App Store confirms it."
        case .pro:
            "Up to \(ProductLimits.memberGoalProfileLimit) focused goals, fresh checkpoints, and adaptive Next Focus are unlocked."
        }
    }

    var actionTitle: String {
        switch state {
        case .free:
            "Explore Checkpoint Pro"
        case .pendingPurchase:
            "Check purchase status"
        case .pro:
            "View plan & billing"
        }
    }

    var systemImage: String {
        switch state {
        case .free:
            "shield.lefthalf.filled"
        case .pendingPurchase:
            "clock.fill"
        case .pro:
            "sparkles"
        }
    }

    var actionSystemImage: String {
        switch state {
        case .free:
            "arrow.up.right"
        case .pendingPurchase:
            "clock.arrow.circlepath"
        case .pro:
            "creditcard"
        }
    }

    var accessibilityLabel: String {
        switch state {
        case .free:
            "Checkpoint Free"
        case .pendingPurchase:
            "Checkpoint Pro purchase"
        case .pro:
            "Checkpoint Pro"
        }
    }

    var accessibilityValue: String {
        switch state {
        case .free:
            "Current plan. App protection for one focused goal. Checkpoint Pro adds up to \(ProductLimits.memberGoalProfileLimit) goals, fresh checkpoints, and adaptive Next Focus."
        case .pendingPurchase:
            "Pending App Store approval. Pro unlocks after confirmation."
        case .pro:
            "Active access. Up to \(ProductLimits.memberGoalProfileLimit) focused goals, fresh checkpoints, and adaptive Next Focus are unlocked."
        }
    }

    var accessibilityHint: String {
        switch state {
        case .free:
            "Opens Checkpoint Pro plans."
        case .pendingPurchase:
            "Opens purchase status and plan options."
        case .pro:
            "Opens plan and billing."
        }
    }
}

enum SettingsPlanMotionStyle: Equatable {
    case animated
    case identity
}

struct SettingsPlanMotionPolicy: Equatable {
    let style: SettingsPlanMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var animation: Animation? {
        style == .animated ? CheckpointMotion.change : nil
    }

    var animatesSymbol: Bool {
        style == .animated
    }

    var pressedScale: CGFloat {
        style == .animated ? 0.99 : 1
    }
}

struct SettingsPlanCard: View {
    let presentation: SettingsPlanPresentation
    let action: () -> Void

    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var symbolEffectSequence = 0

    init(
        presentation: SettingsPlanPresentation,
        reduceMotionOverride: Bool? = nil,
        action: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.reduceMotionOverride = reduceMotionOverride
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            CheckpointHeroSurface(
                glowColor: accentTint,
                glowOpacity: 0.11,
                glowDiameter: 132,
                glowBlurRadius: 12,
                glowOffset: CGSize(width: 58, height: -72),
                contentPadding: 17
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    planHeader

                    VStack(alignment: .leading, spacing: 7) {
                        Text(presentation.headline)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(CheckpointTheme.heroText)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.interpolate)

                        Text(presentation.detail)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(CheckpointTheme.heroMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.interpolate)
                    }

                    Divider()
                        .overlay(CheckpointTheme.heroBorder)
                        .accessibilityHidden(true)

                    planAction
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsPlanCardButtonStyle(motionPolicy: motionPolicy))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint(presentation.accessibilityHint)
        .animation(motionPolicy.animation, value: presentation.state)
        .onAppear {
            triggerSymbolEffectIfNeeded()
        }
        .onChange(of: presentation.state) { _, _ in
            triggerSymbolEffectIfNeeded()
        }
    }

    @ViewBuilder
    private var planHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                planIdentity
                planBadge
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    planIdentity
                    Spacer(minLength: 8)
                    planBadge
                }

                VStack(alignment: .leading, spacing: 10) {
                    planIdentity
                    planBadge
                }
            }
        }
    }

    private var planIdentity: some View {
        HStack(spacing: 11) {
            Image(systemName: presentation.systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accentTint)
                .frame(width: 40, height: 40)
                .background(
                    CheckpointTheme.heroSubtleFill,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .nonRepeating, value: symbolEffectSequence)
                .symbolEffectsRemoved(!motionPolicy.animatesSymbol)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR PLAN")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(CheckpointTheme.heroMuted)

                Text(presentation.planName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.heroText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
            }
        }
    }

    private var planBadge: some View {
        Text(presentation.badgeText)
            .font(.caption2.weight(.bold))
            .tracking(0.4)
            .foregroundStyle(accentTint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(accentTint.opacity(0.12), in: Capsule())
            .contentTransition(.interpolate)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var planAction: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                planActionTitle
                planActionIcon
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    planActionTitle
                    Spacer(minLength: 8)
                    planActionIcon
                }

                VStack(alignment: .leading, spacing: 8) {
                    planActionTitle
                    planActionIcon
                }
            }
        }
    }

    private var planActionTitle: some View {
        Text(presentation.actionTitle)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.mint)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.interpolate)
    }

    private var planActionIcon: some View {
        Image(systemName: presentation.actionSystemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.mint)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private var accentTint: Color {
        switch presentation.state {
        case .free:
            CheckpointTheme.heroInfo
        case .pendingPurchase:
            CheckpointTheme.amber
        case .pro:
            CheckpointTheme.mint
        }
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var motionPolicy: SettingsPlanMotionPolicy {
        SettingsPlanMotionPolicy(reduceMotion: reduceMotion)
    }

    private func triggerSymbolEffectIfNeeded() {
        guard motionPolicy.animatesSymbol else { return }
        symbolEffectSequence += 1
    }
}

private struct SettingsPlanCardButtonStyle: ButtonStyle {
    let motionPolicy: SettingsPlanMotionPolicy

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? motionPolicy.pressedScale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(motionPolicy.animation, value: configuration.isPressed)
    }
}

struct SettingsNavigationRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var trailingText: String
    var voiceOverValue: String? = nil
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemImage: systemImage)
                            titleLabel
                            Spacer(minLength: 8)
                            chevron
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            trailingLabel
                            detailLabel
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        SettingsRowIcon(systemImage: systemImage)

                        VStack(alignment: .leading, spacing: 4) {
                            titleLabel
                            detailLabel
                        }

                        Spacer(minLength: 0)
                        trailingLabel
                        chevron
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(voiceOverValue ?? detail)
        .accessibilityHint("Opens \(title).")
    }

    private var titleLabel: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var detailLabel: some View {
        Text(detail)
            .font(.footnote)
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var trailingLabel: some View {
        Text(trailingText)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.muted)
            .accessibilityHidden(true)
    }
}

struct LegalLinkRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var url: URL?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if let url {
            Link(destination: url) {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(detail)
            .accessibilityHint("Opens in your browser.")
        } else {
            rowContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(detail)
                .accessibilityHint("This URL is not configured in this build.")
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        SettingsRowIcon(systemImage: systemImage)
                        legalTitle
                    }

                    legalDetail
                    legalAccessory
                }
            } else {
                HStack(spacing: 12) {
                    SettingsRowIcon(systemImage: systemImage)

                    VStack(alignment: .leading, spacing: 4) {
                        legalTitle
                        legalDetail
                    }

                    Spacer(minLength: 8)
                    legalAccessory
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var legalTitle: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var legalDetail: some View {
        Text(detail)
            .font(.footnote)
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var legalAccessory: some View {
        if url == nil {
            StatusBadge(text: "Not configured", tint: CheckpointTheme.coral)
        } else {
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityHidden(true)
        }
    }
}

private struct SettingsRowIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 34, height: 34)
            .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}
