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
            return CheckpointDataEraseCopy.warningMessage
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
            return "trash"
        }
    }
}

struct CheckpointDataEraseConsequence: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
}

enum CheckpointDataEraseCopy {
    static let removedItems = [
        CheckpointDataEraseConsequence(
            id: "learning-history",
            title: "Goals and learning history",
            detail: "Generated questions, answers, progress, Focus Wins, and local feedback drafts.",
            systemImage: "book.closed"
        ),
        CheckpointDataEraseConsequence(
            id: "protection-setup",
            title: "App protection setup",
            detail: "Protected app and website selections, unlock state, and local Screen Time coordination. Protection turns off.",
            systemImage: "shield.slash"
        ),
        CheckpointDataEraseConsequence(
            id: "service-records",
            title: "Local service records",
            detail: "Diagnostics, the anonymous backend install ID, and purchase-status reminders.",
            systemImage: "externaldrive"
        ),
    ]

    static let retainedItems = [
        CheckpointDataEraseConsequence(
            id: "app-store",
            title: "App Store activity",
            detail: "Your subscription and purchases already in progress are not canceled. Manage them with Apple.",
            systemImage: "apple.logo"
        ),
        CheckpointDataEraseConsequence(
            id: "screen-time-permission",
            title: "Screen Time permission",
            detail: "iOS keeps Checkpoint’s permission until you change it in Settings.",
            systemImage: "hand.raised"
        ),
        CheckpointDataEraseConsequence(
            id: "backend-retention",
            title: "Backend records age out",
            detail: "Question-bank, quota, stream, and queued-job records aren’t deleted immediately. They age out under their retention windows, and queued work may finish after reset.",
            systemImage: "cloud"
        ),
    ]

    static let irreversibleDetail = "This permanently removes Checkpoint’s local data from this iPhone and can’t be undone."

    static let warningMessage = "This erases goals, questions, answers, progress, Focus Wins, feedback drafts, protected-app and website selections, local diagnostics, the anonymous backend install ID, and local purchase-status reminders from this iPhone, then turns off app protection. Your App Store subscription and purchases in progress are not canceled. Your iOS Screen Time permission stays granted until you change it in Settings. Existing backend question-bank, quota, stream, and queued-job records are not deleted immediately; they age out under their retention windows, and queued work may finish after reset. This can't be undone."
}

enum AdvancedConfirmationInputState: Equatable {
    case empty
    case incomplete
    case ready
}

enum AdvancedConfirmationStatusTone: Equatable {
    case neutral
    case ready
}

struct AdvancedConfirmationPresentation: Equatable {
    let action: AdvancedSettingsAction
    let inputState: AdvancedConfirmationInputState
    let hasActionError: Bool
    let isErasing: Bool
    let didSucceed: Bool

    init(
        action: AdvancedSettingsAction,
        confirmationText: String,
        hasActionError: Bool,
        isErasing: Bool,
        didSucceed: Bool = false
    ) {
        self.action = action
        self.hasActionError = hasActionError
        self.isErasing = isErasing
        self.didSucceed = didSucceed

        let normalizedText = confirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if normalizedText.isEmpty {
            inputState = .empty
        } else if normalizedText == action.confirmationPhrase {
            inputState = .ready
        } else {
            inputState = .incomplete
        }
    }

    var isConfirmed: Bool {
        inputState == .ready
    }

    var isActionEnabled: Bool {
        (isConfirmed || didSucceed) && !isErasing
    }

    var actionTitle: String {
        if isErasing {
            return "Erasing…"
        }
        if didSucceed {
            return "Start fresh"
        }
        if hasActionError {
            return "Retry erasure"
        }
        return isConfirmed ? action.buttonTitle : "Type \(action.confirmationPhrase) to continue"
    }

    var actionSystemImage: String {
        if isErasing {
            return "hourglass"
        }
        if didSucceed {
            return "arrow.right"
        }
        return hasActionError ? "arrow.clockwise" : action.systemImage
    }

    var confirmationStatusText: String {
        switch inputState {
        case .empty:
            "Enter \(action.confirmationPhrase) to continue."
        case .incomplete:
            "The phrase must match \(action.confirmationPhrase)."
        case .ready:
            "Confirmation ready."
        }
    }

    var confirmationSystemImage: String {
        switch inputState {
        case .empty:
            "text.cursor"
        case .incomplete:
            "ellipsis.circle"
        case .ready:
            "checkmark.circle.fill"
        }
    }

    var confirmationTone: AdvancedConfirmationStatusTone {
        isConfirmed ? .ready : .neutral
    }

    var fieldAccessibilityHint: String {
        switch inputState {
        case .empty:
            "Type \(action.confirmationPhrase) to continue."
        case .incomplete:
            "The entry does not match \(action.confirmationPhrase). Type the phrase again to continue."
        case .ready:
            "Confirmation ready. The erase action is now available."
        }
    }

    var actionAccessibilityValue: String {
        if isErasing {
            return "Erasure in progress"
        }
        if didSucceed {
            return "Local data erased; ready to start fresh"
        }
        if isConfirmed {
            return hasActionError ? "Ready to retry" : "Ready"
        }
        return "Unavailable until \(action.confirmationPhrase) is entered"
    }
}

struct DataEraseOnboardingHandoff: Equatable {
    private(set) var isPending = false

    mutating func schedule() {
        isPending = true
    }

    mutating func consumeAfterConfirmationDismissal() -> Bool {
        guard isPending else { return false }
        isPending = false
        return true
    }
}

struct AdvancedConfirmationErrorDelivery: Equatable {
    private(set) var message: String?
    private(set) var revision = 0

    init(message: String? = nil) {
        self.message = message
    }

    mutating func publish(_ message: String?) {
        self.message = message
        revision &+= 1
    }

    mutating func clear() {
        message = nil
    }
}

enum AdvancedConfirmationMotionStyle: Equatable {
    case animated
    case tonalOnly
}

struct AdvancedConfirmationMotionPolicy {
    let style: AdvancedConfirmationMotionStyle
    let usesAssistiveNavigation: Bool

    init(
        reduceMotion: Bool,
        voiceOverEnabled: Bool,
        switchControlEnabled: Bool
    ) {
        usesAssistiveNavigation = voiceOverEnabled || switchControlEnabled
        style = reduceMotion || voiceOverEnabled || switchControlEnabled
            ? .tonalOnly
            : .animated
    }

    var animation: Animation? {
        style == .animated ? CheckpointMotion.change : nil
    }

    var animatesSymbolTransitions: Bool {
        style == .animated
    }

    var errorTransition: AnyTransition {
        style == .animated
            ? .opacity.combined(with: .move(edge: .bottom))
            : .identity
    }

    var animatesErrorInsertion: Bool {
        style == .animated
    }

    func shouldAnnounceReadyTransition(
        from oldState: AdvancedConfirmationInputState,
        to newState: AdvancedConfirmationInputState
    ) -> Bool {
        usesAssistiveNavigation && oldState != .ready && newState == .ready
    }
}

enum AdvancedConfirmationLayoutElement: Hashable {
    case viewport
    case hero
    case consequences
    case confirmation
    case actionBar
}

private enum AdvancedConfirmationScrollTarget: Hashable {
    case top
    case confirmation
}

private let advancedConfirmationLayoutCoordinateSpaceName = "advanced-confirmation-layout"

private struct AdvancedConfirmationLayoutFrameReporter: ViewModifier {
    let element: AdvancedConfirmationLayoutElement
    let report: (@MainActor (AdvancedConfirmationLayoutElement, CGRect) -> Void)?

    func body(content: Content) -> some View {
        if let report {
            content.background {
                GeometryReader { proxy in
                    let frame = proxy.frame(
                        in: .named(advancedConfirmationLayoutCoordinateSpaceName)
                    )

                    Color.clear
                        .onAppear {
                            report(element, frame)
                        }
                        .onChange(of: frame) { _, updatedFrame in
                            report(element, updatedFrame)
                        }
                }
            }
        } else {
            content
        }
    }
}

private extension View {
    func reportAdvancedConfirmationLayoutFrame(
        _ element: AdvancedConfirmationLayoutElement,
        using report: (@MainActor (AdvancedConfirmationLayoutElement, CGRect) -> Void)?
    ) -> some View {
        modifier(
            AdvancedConfirmationLayoutFrameReporter(
                element: element,
                report: report
            )
        )
    }
}

struct AdvancedConfirmationView: View {
    let action: AdvancedSettingsAction
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let purchaseController: PurchaseController
    private let onLocalDataEraseCompleted: @MainActor () -> Void
    private let reduceMotionOverride: Bool?
    private let voiceOverOverride: Bool?
    private let switchControlOverride: Bool?
    private let layoutReporter: (@MainActor (AdvancedConfirmationLayoutElement, CGRect) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var systemVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var systemSwitchControlEnabled
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmationText: String
    @State private var actionErrorDelivery: AdvancedConfirmationErrorDelivery
    @State private var isErasing: Bool
    @State private var didEraseSuccessfully: Bool
    @AccessibilityFocusState private var isActionErrorFocused: Bool
    @FocusState private var isConfirmationFieldFocused: Bool

    init(
        action: AdvancedSettingsAction,
        store: CheckpointStore,
        screenTime: ScreenTimeController,
        purchaseController: PurchaseController,
        initialConfirmationText: String = "",
        initialActionErrorMessage: String? = nil,
        initiallyErasing: Bool = false,
        initiallySucceeded: Bool = false,
        reduceMotionOverride: Bool? = nil,
        voiceOverOverride: Bool? = nil,
        switchControlOverride: Bool? = nil,
        layoutReporter: (@MainActor (AdvancedConfirmationLayoutElement, CGRect) -> Void)? = nil,
        onLocalDataEraseCompleted: @escaping @MainActor () -> Void = {}
    ) {
        self.action = action
        self.store = store
        self.screenTime = screenTime
        self.purchaseController = purchaseController
        self.onLocalDataEraseCompleted = onLocalDataEraseCompleted
        self.reduceMotionOverride = reduceMotionOverride
        self.voiceOverOverride = voiceOverOverride
        self.switchControlOverride = switchControlOverride
        self.layoutReporter = layoutReporter
        _confirmationText = State(initialValue: initialConfirmationText)
        _actionErrorDelivery = State(
            initialValue: AdvancedConfirmationErrorDelivery(
                message: initialActionErrorMessage
            )
        )
        _isErasing = State(initialValue: initiallyErasing)
        _didEraseSuccessfully = State(initialValue: initiallySucceeded)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if didEraseSuccessfully {
                            erasureSuccessHero
                                .id(AdvancedConfirmationScrollTarget.top)
                                .reportAdvancedConfirmationLayoutFrame(.hero, using: layoutReporter)
                            erasureSuccessPanel
                                .reportAdvancedConfirmationLayoutFrame(.confirmation, using: layoutReporter)
                        } else {
                            eraseHero
                                .id(AdvancedConfirmationScrollTarget.top)
                                .reportAdvancedConfirmationLayoutFrame(.hero, using: layoutReporter)
                            consequencesPanel
                                .reportAdvancedConfirmationLayoutFrame(.consequences, using: layoutReporter)
                            confirmationPanel
                                .id(AdvancedConfirmationScrollTarget.confirmation)
                                .reportAdvancedConfirmationLayoutFrame(.confirmation, using: layoutReporter)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .reportAdvancedConfirmationLayoutFrame(.viewport, using: layoutReporter)
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(actionErrorDelivery.message == nil ? .top : .bottom)
                .checkpointScreenBackground()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actionBar
                        .reportAdvancedConfirmationLayoutFrame(.actionBar, using: layoutReporter)
                }
                .onAppear {
                    if actionErrorDelivery.message != nil {
                        revealConfirmation(using: proxy)
                    }
                }
                .onChange(of: actionErrorDelivery.message) { _, message in
                    if message == nil {
                        isActionErrorFocused = false
                    }
                }
                .onChange(of: actionErrorDelivery.revision) { _, _ in
                    guard actionErrorDelivery.message != nil else { return }
                    revealConfirmation(using: proxy)
                }
                .onChange(of: didEraseSuccessfully) { _, succeeded in
                    guard succeeded else { return }
                    revealSuccess(using: proxy)
                }
            }
            .navigationTitle(didEraseSuccessfully ? "Reset complete" : action.buttonTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didEraseSuccessfully ? "Close" : "Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                    .disabled(isErasing)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        isConfirmationFieldFocused = false
                    }
                }
            }
        }
        .coordinateSpace(name: advancedConfirmationLayoutCoordinateSpaceName)
        .interactiveDismissDisabled(isErasing)
        .animation(motionPolicy.animation, value: presentation)
        .onChange(of: presentation.inputState) { oldState, newState in
            announceReadyTransition(from: oldState, to: newState)
        }
    }

    private var presentation: AdvancedConfirmationPresentation {
        AdvancedConfirmationPresentation(
            action: action,
            confirmationText: confirmationText,
            hasActionError: actionErrorDelivery.message != nil,
            isErasing: isErasing,
            didSucceed: didEraseSuccessfully
        )
    }

    private var motionPolicy: AdvancedConfirmationMotionPolicy {
        AdvancedConfirmationMotionPolicy(
            reduceMotion: reduceMotionOverride ?? systemReduceMotion,
            voiceOverEnabled: voiceOverOverride ?? systemVoiceOverEnabled,
            switchControlEnabled: switchControlOverride ?? systemSwitchControlEnabled
        )
    }

    private var confirmationBinding: Binding<String> {
        Binding(
            get: { confirmationText },
            set: { updatedText in
                confirmationText = updatedText
            }
        )
    }

    private var eraseHero: some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.heroDanger,
            glowOpacity: 0.12,
            glowDiameter: 190,
            glowBlurRadius: 16,
            glowOffset: CGSize(width: 82, height: -92),
            contentPadding: dynamicTypeSize.isAccessibilitySize ? 18 : 20
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if dynamicTypeSize.isAccessibilitySize {
                    StatusBadge(text: "IRREVERSIBLE", tint: CheckpointTheme.heroDanger)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            heroEyebrow
                            Spacer(minLength: 8)
                            StatusBadge(text: "IRREVERSIBLE", tint: CheckpointTheme.heroDanger)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            heroEyebrow
                            StatusBadge(text: "IRREVERSIBLE", tint: CheckpointTheme.heroDanger)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(action.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(CheckpointTheme.heroText)
                        .fixedSize(horizontal: false, vertical: true)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Review what leaves this iPhone—and what remains outside this reset—before you confirm.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.heroMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()
                    .overlay(CheckpointTheme.heroDivider)

                irreversibleWarning
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.heroDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var heroEyebrow: some View {
        Label("DATA RESET", systemImage: "trash.fill")
            .font(.caption.weight(.bold))
            .tracking(0.75)
            .foregroundStyle(CheckpointTheme.heroDanger)
            .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private var irreversibleWarning: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)

                Text("Local data will be permanently erased. This can’t be undone.")
            }
            .accessibilityElement(children: .combine)
        } else {
            Label(
                CheckpointDataEraseCopy.irreversibleDetail,
                systemImage: "exclamationmark.triangle.fill"
            )
        }
    }

    private var consequencesPanel: some View {
        SectionPanel("Before you erase") {
            VStack(alignment: .leading, spacing: 16) {
                consequenceGroup(
                    title: "Removed from this iPhone",
                    systemImage: "minus.circle.fill",
                    tint: CheckpointTheme.coral,
                    items: CheckpointDataEraseCopy.removedItems
                )

                Divider()
                    .overlay(CheckpointTheme.hairline)

                consequenceGroup(
                    title: "Remains outside this reset",
                    systemImage: "checkmark.shield.fill",
                    tint: CheckpointTheme.teal,
                    items: CheckpointDataEraseCopy.retainedItems
                )
            }
        }
    }

    private var erasureSuccessHero: some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.heroSuccess,
            glowOpacity: 0.12,
            glowDiameter: 190,
            glowBlurRadius: 16,
            glowOffset: CGSize(width: 82, height: -92),
            contentPadding: dynamicTypeSize.isAccessibilitySize ? 18 : 20
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Label("RESET COMPLETE", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .tracking(0.75)
                    .foregroundStyle(CheckpointTheme.heroSuccess)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Ready for a fresh start")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(CheckpointTheme.heroText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Checkpoint’s data was removed from this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .overlay(CheckpointTheme.heroDivider)

                Label(
                    "Backend records disclosed before reset will continue aging out under their retention windows.",
                    systemImage: "cloud"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.heroMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var erasureSuccessPanel: some View {
        SectionPanel("What happens next") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up Checkpoint again")
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.text)

                    Text("Start fresh closes this confirmation and opens goal setup.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func consequenceGroup(
        title: String,
        systemImage: String,
        tint: Color,
        items: [CheckpointDataEraseConsequence]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)

            ForEach(items) { item in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(
                            tint.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)

                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var confirmationPanel: some View {
        SectionPanel("Confirm erasure") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Type \(action.confirmationPhrase) to enable the final action.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    TextField(action.confirmationPhrase, text: confirmationBinding)
                        .textFieldStyle(.plain)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(CheckpointTheme.text)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .disabled(isErasing)
                        .focused($isConfirmationFieldFocused)
                        .onSubmit {
                            isConfirmationFieldFocused = false
                        }
                        .accessibilityLabel("Confirmation phrase")
                        .accessibilityHint(presentation.fieldAccessibilityHint)

                    Image(systemName: presentation.confirmationSystemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(confirmationTint)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffectsRemoved(!motionPolicy.animatesSymbolTransitions)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 52)
                .background(
                    confirmationTint.opacity(presentation.isConfirmed ? 0.09 : 0.04),
                    in: RoundedRectangle(
                        cornerRadius: CheckpointTheme.compactCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: CheckpointTheme.compactCornerRadius,
                        style: .continuous
                    )
                    .stroke(
                        confirmationTint.opacity(presentation.isConfirmed ? 0.62 : 0.26),
                        lineWidth: presentation.isConfirmed ? 1.5 : 1
                    )
                }
                Label(
                    presentation.confirmationStatusText,
                    systemImage: presentation.confirmationSystemImage
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(confirmationTint)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.confirmationStatusText)

                if let actionErrorMessage = actionErrorDelivery.message {
                    Label(actionErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            CheckpointTheme.coral.opacity(0.08),
                            in: RoundedRectangle(
                                cornerRadius: CheckpointTheme.compactCornerRadius,
                                style: .continuous
                            )
                        )
                        .transition(motionPolicy.errorTransition)
                        .accessibilityFocused($isActionErrorFocused)
                        .id(actionErrorDelivery.revision)
                }
            }
        }
    }

    private var confirmationTint: Color {
        switch presentation.confirmationTone {
        case .neutral:
            CheckpointTheme.muted
        case .ready:
            CheckpointTheme.teal
        }
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            Button {
                performAction()
            } label: {
                actionLabel
                .font(.headline)
                .foregroundStyle(CheckpointTheme.paper)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 12)
                .background(
                    actionFill,
                    in: RoundedRectangle(
                        cornerRadius: CheckpointTheme.compactCornerRadius,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(CheckpointPressButtonStyle())
            .disabled(!presentation.isActionEnabled)
            .opacity(presentation.isActionEnabled ? 1 : 0.50)
            .accessibilityLabel(presentation.actionTitle)
            .accessibilityValue(presentation.actionAccessibilityValue)
            .accessibilityHint(actionAccessibilityHint)
            .accessibilityIdentifier("erase-all-data-confirm")
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var actionFill: Color {
        didEraseSuccessfully ? CheckpointTheme.teal : CheckpointTheme.destructiveFill
    }

    private var actionAccessibilityHint: String {
        if didEraseSuccessfully {
            return "Closes this confirmation and starts a fresh Checkpoint setup"
        }
        if presentation.isConfirmed {
            return "Permanently erases local Checkpoint data and turns off protection"
        }
        return "Enter \(action.confirmationPhrase) in the confirmation field first"
    }

    private var actionLabel: some View {
        HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 9) {
            if !dynamicTypeSize.isAccessibilitySize {
                actionIcon
            }
            Text(displayedActionTitle)
        }
    }

    private var displayedActionTitle: String {
        if dynamicTypeSize.isAccessibilitySize,
           !presentation.isConfirmed,
           !presentation.hasActionError,
           !didEraseSuccessfully {
            return "Enter \(action.confirmationPhrase)"
        }
        return presentation.actionTitle
    }

    @ViewBuilder
    private var actionIcon: some View {
        if isErasing {
            ProgressView()
                .tint(CheckpointTheme.paper)
                .accessibilityHidden(true)
        } else {
            Image(systemName: presentation.actionSystemImage)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffectsRemoved(!motionPolicy.animatesSymbolTransitions)
                .accessibilityHidden(true)
        }
    }

    private func performAction() {
        if didEraseSuccessfully {
            dismiss()
            return
        }

        guard presentation.isActionEnabled else { return }

        isActionErrorFocused = false
        isConfirmationFieldFocused = false
        isErasing = true

        Task { @MainActor in
            // Let the keyboard dismiss and the guarded working state render before
            // the synchronous persistence work begins.
            await Task.yield()
            guard isErasing, !didEraseSuccessfully else { return }

            let result: CheckpointDataEraseResult
            switch action {
            case .resetData:
                result = CheckpointDataEraseCoordinator.eraseAllData(
                    store: store,
                    screenTime: screenTime,
                    purchaseController: purchaseController,
                    presentsOnboardingAfterErase: false
                )
            }

            isErasing = false

            if result.didEraseLocalData {
                onLocalDataEraseCompleted()
            }

            guard result.succeeded else {
                actionErrorDelivery.publish(result.recoveryMessage)
                return
            }

            actionErrorDelivery.clear()
            didEraseSuccessfully = true
            AccessibilityNotification.Announcement(
                "Data was erased from this iPhone. Checkpoint is ready to start fresh."
            ).post()
        }
    }

    private func revealConfirmation(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(80))
            guard actionErrorDelivery.message != nil else { return }
            if let animation = motionPolicy.animation {
                withAnimation(animation) {
                    proxy.scrollTo(AdvancedConfirmationScrollTarget.confirmation, anchor: .bottom)
                }
            } else {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(AdvancedConfirmationScrollTarget.confirmation, anchor: .bottom)
                }
            }

            guard motionPolicy.usesAssistiveNavigation else { return }
            await Task.yield()
            guard actionErrorDelivery.message != nil else { return }
            isActionErrorFocused = true
        }
    }

    private func revealSuccess(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            if let animation = motionPolicy.animation {
                withAnimation(animation) {
                    proxy.scrollTo(AdvancedConfirmationScrollTarget.top, anchor: .top)
                }
            } else {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(AdvancedConfirmationScrollTarget.top, anchor: .top)
                }
            }
        }
    }

    private func announceReadyTransition(
        from oldState: AdvancedConfirmationInputState,
        to newState: AdvancedConfirmationInputState
    ) {
        guard motionPolicy.shouldAnnounceReadyTransition(
            from: oldState,
            to: newState
        ) else {
            return
        }

        AccessibilityNotification.Announcement(
            "Confirmation ready. \(action.buttonTitle) is available."
        ).post()
    }

}

struct CheckpointDataEraseResult: Equatable {
    let didEraseLocalData: Bool
    let recoveryMessages: [String]

    var succeeded: Bool {
        didEraseLocalData && recoveryMessages.isEmpty
    }

    var recoveryMessage: String? {
        recoveryMessages.isEmpty ? nil : recoveryMessages.joined(separator: " ")
    }
}

@MainActor
enum CheckpointDataEraseCoordinator {
    @discardableResult
    static func eraseAllData(
        store: CheckpointStore,
        screenTime: ScreenTimeController,
        purchaseController: PurchaseController,
        presentsOnboardingAfterErase: Bool = true
    ) -> CheckpointDataEraseResult {
        screenTime.eraseAllData()
        store.eraseAllData(
            presentsOnboardingAfterErase: presentsOnboardingAfterErase
        )
        purchaseController.clearPendingPurchaseState()

        let recoveryMessages = [
            screenTime.sharedDataEraseErrorMessage,
            store.persistenceRecoveryMessage,
        ].compactMap { $0 }
            .reduce(into: [String]()) { messages, message in
                if !messages.contains(message) {
                    messages.append(message)
                }
            }
        return CheckpointDataEraseResult(
            didEraseLocalData: store.hasNoPersistedAppData,
            recoveryMessages: recoveryMessages
        )
    }
}

enum SettingsPlanState: Equatable, Sendable {
    case free
    case pendingPurchase
    case unconfirmedPurchase
    case pro
}

enum SettingsProActivityID: String, CaseIterable, Hashable, Sendable {
    case freshCheckpoints
    case nextFocus
    case goalLanes
}

enum SettingsProActivityTone: Equatable, Hashable, Sendable {
    case positive
    case informative
    case attention
    case neutral
}

struct SettingsProActivityItem: Identifiable, Equatable, Hashable, Sendable {
    let id: SettingsProActivityID
    let label: String
    let value: String
    let detail: String
    let systemImage: String
    let tone: SettingsProActivityTone

    var accessibilityValue: String {
        "\(label.capitalized): \(value). \(detail)"
    }
}

struct SettingsProActivityPresentation: Equatable, Hashable, Sendable {
    let headline: String
    let freshCheckpoints: SettingsProActivityItem
    let nextFocus: SettingsProActivityItem
    let goalLanes: SettingsProActivityItem

    init(
        hasGoal: Bool,
        hasReadyCheckpoint: Bool,
        isMaintainingFreshCheckpoints: Bool,
        isQuestionGenerationBlockingPractice: Bool,
        questionBankTargetCount: Int,
        studyFocusState: StudyFocusState?,
        skillMapStatus: SkillMapStatus?,
        hasPracticeHistory: Bool,
        goalCount: Int,
        goalLimit: Int
    ) {
        let targetCount = max(1, questionBankTargetCount)
        let normalizedGoalCount = max(0, goalCount)
        let normalizedGoalLimit = max(1, goalLimit)
        let targetDetail = "\(targetCount)-question practice target"

        if !hasGoal {
            headline = "Your Pro workspace is ready."
        } else if isQuestionGenerationBlockingPractice {
            headline = "Practice needs a little attention."
        } else {
            headline = "Pro is working in the background."
        }

        if !hasGoal {
            freshCheckpoints = SettingsProActivityItem(
                id: .freshCheckpoints,
                label: "FRESH CHECKPOINTS",
                value: "Ready for your first goal",
                detail: targetDetail,
                systemImage: "sparkles",
                tone: .neutral
            )
        } else if isQuestionGenerationBlockingPractice {
            freshCheckpoints = SettingsProActivityItem(
                id: .freshCheckpoints,
                label: "FRESH CHECKPOINTS",
                value: "Needs attention",
                detail: "Review Home to retry checkpoint setup",
                systemImage: "exclamationmark.triangle.fill",
                tone: .attention
            )
        } else if isMaintainingFreshCheckpoints {
            freshCheckpoints = SettingsProActivityItem(
                id: .freshCheckpoints,
                label: "FRESH CHECKPOINTS",
                value: hasReadyCheckpoint ? "Refreshing practice" : "Preparing checkpoint",
                detail: targetDetail,
                systemImage: "arrow.triangle.2.circlepath",
                tone: .informative
            )
        } else if hasReadyCheckpoint {
            freshCheckpoints = SettingsProActivityItem(
                id: .freshCheckpoints,
                label: "FRESH CHECKPOINTS",
                value: "Next checkpoint ready",
                detail: targetDetail,
                systemImage: "checkmark.circle.fill",
                tone: .positive
            )
        } else {
            freshCheckpoints = SettingsProActivityItem(
                id: .freshCheckpoints,
                label: "FRESH CHECKPOINTS",
                value: "Waiting to prepare",
                detail: targetDetail,
                systemImage: "clock",
                tone: .neutral
            )
        }

        switch studyFocusState {
        case let .recommendation(recommendation):
            nextFocus = SettingsProActivityItem(
                id: .nextFocus,
                label: "NEXT FOCUS",
                value: recommendation.title,
                detail: "Adaptive recommendation",
                systemImage: recommendation.systemImage,
                tone: .informative
            )
        case .caughtUp:
            nextFocus = SettingsProActivityItem(
                id: .nextFocus,
                label: "NEXT FOCUS",
                value: "Caught up for now",
                detail: "No review is due",
                systemImage: "checkmark.seal.fill",
                tone: .positive
            )
        case .awaitingQuestion:
            nextFocus = SettingsProActivityItem(
                id: .nextFocus,
                label: "NEXT FOCUS",
                value: "Waiting for practice",
                detail: "Appears when a question is ready",
                systemImage: "clock",
                tone: .neutral
            )
        case nil:
            let value: String
            let detail: String
            if !hasGoal {
                value = "Starts with your first goal"
                detail = "Adapts as you answer"
            } else if skillMapStatus == .suggested {
                value = "Skill map ready to review"
                detail = "Review it in Progress to unlock guidance"
            } else if !hasPracticeHistory {
                value = "Starts after your first checkpoint"
                detail = "Adapts from your answers"
            } else if skillMapStatus == nil {
                value = "Calibrating from your answers"
                detail = "Next Focus is not ready yet"
            } else {
                value = "Calibrating from your answers"
                detail = "Updates as practice becomes ready"
            }
            nextFocus = SettingsProActivityItem(
                id: .nextFocus,
                label: "NEXT FOCUS",
                value: value,
                detail: detail,
                systemImage: "scope",
                tone: .neutral
            )
        }

        goalLanes = SettingsProActivityItem(
            id: .goalLanes,
            label: "GOAL LANES",
            value: normalizedGoalCount == 0
                ? "Ready for your first goal"
                : "\(normalizedGoalCount) of \(normalizedGoalLimit) in use",
            detail: normalizedGoalCount == 0
                ? "\(normalizedGoalLimit) Pro goal lanes available"
                : "Each keeps its progress separate",
            systemImage: "square.stack.3d.up.fill",
            tone: .informative
        )
    }

    var items: [SettingsProActivityItem] {
        [freshCheckpoints, nextFocus, goalLanes]
    }

    var accessibilityValue: String {
        items.map(\.accessibilityValue).joined(separator: ". ")
    }
}

struct SettingsPlanPresentation: Equatable, Sendable {
    let state: SettingsPlanState
    let proActivity: SettingsProActivityPresentation?
    let activePlanKind: MembershipPlanKind?
    let activePlanPresentation: MembershipActivePlanPresentation?
    let upgradePlanOption: MembershipPlanOption?

    init(
        membershipTier: MembershipTier,
        purchaseNotice: MembershipPurchaseNotice?,
        hasUnresolvedPurchase: Bool = false,
        proActivity: SettingsProActivityPresentation? = nil,
        activePlanSnapshot: MembershipActivePlanSnapshot? = nil,
        upgradePlanOption: MembershipPlanOption? = nil,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        let resolvedState: SettingsPlanState
        if membershipTier == .member {
            resolvedState = .pro
        } else if hasUnresolvedPurchase,
                  purchaseNotice == .previousPurchaseUnconfirmed {
            resolvedState = .unconfirmedPurchase
        } else if hasUnresolvedPurchase || purchaseNotice?.isPending == true {
            resolvedState = .pendingPurchase
        } else {
            resolvedState = .free
        }
        state = resolvedState
        self.proActivity = resolvedState == .pro ? proActivity : nil
        activePlanKind = resolvedState == .pro ? activePlanSnapshot?.planKind : nil
        activePlanPresentation = resolvedState == .pro
            ? MembershipActivePlanPresentation(
                snapshot: activePlanSnapshot,
                now: now,
                locale: locale,
                calendar: calendar,
                timeZone: timeZone
            )
            : nil
        let isCatalogUnavailable: Bool
        switch purchaseNotice {
        case .catalogUnavailable:
            isCatalogUnavailable = true
        default:
            isCatalogUnavailable = false
        }
        self.upgradePlanOption = resolvedState == .free && !isCatalogUnavailable
            ? upgradePlanOption
            : nil
    }

    var planName: String {
        switch state {
        case .free:
            "Checkpoint Free"
        case .pendingPurchase:
            "Checkpoint Pro"
        case .unconfirmedPurchase:
            "Checkpoint Pro"
        case .pro:
            activePlanKind.map { "Checkpoint Pro · \($0.shortTitle)" } ?? "Checkpoint Pro"
        }
    }

    var badgeText: String {
        switch state {
        case .free:
            "FREE"
        case .pendingPurchase:
            "PENDING"
        case .unconfirmedPurchase:
            "UNCONFIRMED"
        case .pro:
            activePlanPresentation?.badgeText ?? "ACTIVE"
        }
    }

    var headline: String {
        switch state {
        case .free:
            "Protection for one focused goal."
        case .pendingPurchase:
            "The App Store is completing your purchase."
        case .unconfirmedPurchase:
            "The App Store hasn’t completed this purchase."
        case .pro:
            proActivity?.headline ?? "Pro is working in the background."
        }
    }

    var detail: String {
        switch state {
        case .free:
            "Explore Pro for up to \(ProductLimits.memberGoalProfileLimit) goals, fresh checkpoints, and adaptive Next Focus."
        case .pendingPurchase:
            "Pro unlocks automatically when it finishes. You may need to take action in the App Store."
        case .unconfirmedPurchase:
            "It may still complete. Check its status before starting another purchase."
        case .pro:
            "Fresh checkpoints, adaptive guidance, and separate goal lanes stay ready as you practice."
        }
    }

    var actionTitle: String {
        switch state {
        case .free:
            "Explore Checkpoint Pro"
        case .pendingPurchase, .unconfirmedPurchase:
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
        case .unconfirmedPurchase:
            "questionmark.circle.fill"
        case .pro:
            activePlanPresentation?.planSystemImage ?? "checkmark.seal.fill"
        }
    }

    var actionSystemImage: String {
        switch state {
        case .free:
            "arrow.up.right"
        case .pendingPurchase, .unconfirmedPurchase:
            "clock.arrow.circlepath"
        case .pro:
            "creditcard"
        }
    }

    var accessibilityLabel: String {
        switch state {
        case .free:
            "Checkpoint Free"
        case .pendingPurchase, .unconfirmedPurchase:
            "Checkpoint Pro purchase"
        case .pro:
            planName
        }
    }

    var accessibilityValue: String {
        switch state {
        case .free:
            if let upgradePlanOption {
                "Current plan. App protection for one focused goal. Checkpoint Pro adds up to \(ProductLimits.memberGoalProfileLimit) goals, fresh checkpoints, and adaptive Next Focus. App Store price. \(upgradePlanOption.accessibilityLabel)"
            } else {
                "Current plan. App protection for one focused goal. Checkpoint Pro adds up to \(ProductLimits.memberGoalProfileLimit) goals, fresh checkpoints, and adaptive Next Focus."
            }
        case .pendingPurchase:
            "Waiting for the App Store to complete this purchase. Pro unlocks automatically when it finishes. You may need to take action in the App Store."
        case .unconfirmedPurchase:
            "Unconfirmed App Store purchase. It may still complete."
        case .pro:
            if let proActivity {
                "\(activePlanAccessibilityValue)\(proActivity.accessibilityValue)."
            } else {
                "\(activePlanAccessibilityValue)Fresh checkpoints, adaptive guidance, and separate goal lanes are unlocked."
            }
        }
    }

    var accessibilityHint: String {
        switch state {
        case .free:
            "Opens Checkpoint Pro plans."
        case .pendingPurchase, .unconfirmedPurchase:
            "Opens purchase status and plan options."
        case .pro:
            "Opens plan and billing."
        }
    }

    var visualStateKey: SettingsPlanVisualStateKey {
        SettingsPlanVisualStateKey(
            state: state,
            activePlanKind: activePlanKind,
            activePlan: activePlanPresentation?.visualStateKey
        )
    }

    private var activePlanAccessibilityValue: String {
        guard let activePlanPresentation else {
            return "Active access. "
        }

        return [
            activePlanPresentation.planTitle,
            activePlanPresentation.badgeText.capitalized,
            activePlanPresentation.statusText,
            activePlanPresentation.supportText,
        ]
        .joined(separator: ". ") + ". "
    }
}

struct SettingsPlanVisualStateKey: Equatable, Sendable {
    let state: SettingsPlanState
    let activePlanKind: MembershipPlanKind?
    let activePlan: MembershipActivePlanVisualStateKey?
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

    var activityTransition: AnyTransition {
        switch style {
        case .animated:
            .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
        case .identity:
            .identity
        }
    }

    var offerTransition: AnyTransition {
        style == .animated ? .opacity : .identity
    }
}

enum SettingsPlanLayoutElement: Hashable {
    case card
    case subscriptionStatus
    case proActivity
    case proActivityRow(SettingsProActivityID)
    case upgradeOffer
    case action
}

private let settingsPlanLayoutCoordinateSpaceName = "Checkpoint.Settings.Plan.Layout"

private struct SettingsPlanLayoutFrameReporter: ViewModifier {
    let element: SettingsPlanLayoutElement
    let report: (@MainActor (SettingsPlanLayoutElement, CGRect) -> Void)?

    func body(content: Content) -> some View {
        content.background {
            if let report {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(settingsPlanLayoutCoordinateSpaceName))

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
    func reportSettingsPlanLayoutFrame(
        _ element: SettingsPlanLayoutElement,
        using report: (@MainActor (SettingsPlanLayoutElement, CGRect) -> Void)?
    ) -> some View {
        modifier(SettingsPlanLayoutFrameReporter(element: element, report: report))
    }
}

struct SettingsPlanCard: View {
    let presentation: SettingsPlanPresentation
    let action: () -> Void

    private let reduceMotionOverride: Bool?
    private let layoutReporter: (@MainActor (SettingsPlanLayoutElement, CGRect) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var symbolEffectSequence = 0

    init(
        presentation: SettingsPlanPresentation,
        reduceMotionOverride: Bool? = nil,
        layoutReporter: (@MainActor (SettingsPlanLayoutElement, CGRect) -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.reduceMotionOverride = reduceMotionOverride
        self.layoutReporter = layoutReporter
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

                    if let activePlanPresentation = presentation.activePlanPresentation {
                        activePlanStatus(activePlanPresentation)
                            .transition(motionPolicy.activityTransition)
                    }

                    planSummary

                    Divider()
                        .overlay(CheckpointTheme.heroBorder)
                        .accessibilityHidden(true)

                    planAction
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CheckpointPressButtonStyle(role: .surface))
        .reportSettingsPlanLayoutFrame(.card, using: layoutReporter)
        .coordinateSpace(name: settingsPlanLayoutCoordinateSpaceName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint(presentation.accessibilityHint)
        .animation(motionPolicy.animation, value: presentation.visualStateKey)
        .animation(motionPolicy.animation, value: presentation.proActivity)
        .animation(motionPolicy.animation, value: presentation.upgradePlanOption)
        .onAppear {
            triggerSymbolEffectIfNeeded()
        }
        .onChange(of: presentation.visualStateKey) { _, _ in
            triggerSymbolEffectIfNeeded()
        }
    }

    private func activePlanStatus(
        _ activePlan: MembershipActivePlanPresentation
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: activePlan.statusSystemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accentTint)
                .frame(width: 30, height: 30)
                .background(
                    accentTint.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .contentTransition(.symbolEffect(.replace))
                .symbolEffectsRemoved(!motionPolicy.animatesSymbol)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(activePlan.statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.heroText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)

                Text(activePlan.supportText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.heroSubtleFill,
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(accentTint.opacity(0.22), lineWidth: 1)
        }
        .reportSettingsPlanLayoutFrame(.subscriptionStatus, using: layoutReporter)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var planSummary: some View {
        VStack(alignment: .leading, spacing: presentation.proActivity == nil ? 7 : 13) {
            Text(presentation.headline)
                .font(.title3.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.interpolate)

            if let proActivity = presentation.proActivity {
                proActivityPanel(proActivity)
                    .transition(motionPolicy.activityTransition)
            } else {
                Text(presentation.detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)

                if let upgradePlanOption = presentation.upgradePlanOption {
                    upgradeOffer(upgradePlanOption)
                        .transition(motionPolicy.offerTransition)
                }
            }
        }
    }

    private func upgradeOffer(_ option: MembershipPlanOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    upgradeOfferLabel
                    Spacer(minLength: 8)
                    recommendedOfferBadge(option)
                }

                VStack(alignment: .leading, spacing: 6) {
                    upgradeOfferLabel
                    recommendedOfferBadge(option)
                }
            }

            upgradeOfferCharge(option)

            Text(option.detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.heroMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let valueBadge = option.valueBadge {
                Text(valueBadge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckpointTheme.mint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.heroSubtleFill,
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(CheckpointTheme.heroDivider, lineWidth: 1)
        }
        .reportSettingsPlanLayoutFrame(.upgradeOffer, using: layoutReporter)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func upgradeOfferCharge(_ option: MembershipPlanOption) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.subheadline.weight(.semibold))

                Text(option.displayPrice)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)

                Text(option.cadence)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CheckpointTheme.heroMuted)
            }
            .foregroundStyle(CheckpointTheme.heroText)
        } else {
            Text(option.chargeSummary)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var upgradeOfferLabel: some View {
        Text("APP STORE PRICE")
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(CheckpointTheme.heroMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func recommendedOfferBadge(_ option: MembershipPlanOption) -> some View {
        if option.isRecommended {
            Text("BEST VALUE")
                .font(.caption2.weight(.bold))
                .tracking(0.3)
                .foregroundStyle(CheckpointTheme.mint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(CheckpointTheme.mint.opacity(0.12), in: Capsule())
        }
    }

    private func proActivityPanel(
        _ proActivity: SettingsProActivityPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(proActivity.items) { item in
                proActivityRow(item)

                if item.id != .goalLanes {
                    Divider()
                        .overlay(CheckpointTheme.heroDivider)
                        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 41)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(
            CheckpointTheme.heroSubtleFill,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CheckpointTheme.heroDivider, lineWidth: 1)
        }
        .reportSettingsPlanLayoutFrame(.proActivity, using: layoutReporter)
    }

    private func proActivityRow(_ item: SettingsProActivityItem) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    proActivityIdentity(item)
                    proActivityCopy(item)
                }
            } else {
                HStack(alignment: .center, spacing: 11) {
                    proActivityIcon(item)
                    proActivityCopy(item)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reportSettingsPlanLayoutFrame(.proActivityRow(item.id), using: layoutReporter)
        .accessibilityHidden(true)
    }

    private func proActivityIdentity(_ item: SettingsProActivityItem) -> some View {
        Text(item.label)
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(proActivityTint(item.tone))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func proActivityIcon(_ item: SettingsProActivityItem) -> some View {
        Image(systemName: item.systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(proActivityTint(item.tone))
            .frame(width: 30, height: 30)
            .background(
                proActivityTint(item.tone).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, options: .nonRepeating, value: item)
            .symbolEffectsRemoved(!motionPolicy.animatesSymbol)
            .accessibilityHidden(true)
    }

    private func proActivityCopy(_ item: SettingsProActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !dynamicTypeSize.isAccessibilitySize {
                Text(item.label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(CheckpointTheme.heroMuted)
            }

            Text(item.value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(
                    item.id == .goalLanes ? .numericText() : .interpolate
                )

            Text(item.detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.heroMuted)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.interpolate)
        }
    }

    private func proActivityTint(_ tone: SettingsProActivityTone) -> Color {
        switch tone {
        case .positive:
            CheckpointTheme.heroSuccess
        case .informative:
            CheckpointTheme.heroInfo
        case .attention:
            CheckpointTheme.heroWarning
        case .neutral:
            CheckpointTheme.heroMuted
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
        Group {
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
        .frame(minHeight: 44, alignment: .leading)
        .reportSettingsPlanLayoutFrame(.action, using: layoutReporter)
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
        case .unconfirmedPurchase:
            CheckpointTheme.heroInfo
        case .pro:
            switch presentation.activePlanPresentation?.tone {
            case .scheduled:
                CheckpointTheme.heroInfo
            case .attention:
                CheckpointTheme.heroWarning
            case .active, nil:
                CheckpointTheme.mint
            }
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
        .buttonStyle(CheckpointPressButtonStyle(role: .surface))
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
