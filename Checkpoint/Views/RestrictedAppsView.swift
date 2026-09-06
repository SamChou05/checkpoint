import Observation
import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

enum RestrictedAppsPresentationMode: Equatable {
    case management
    case firstRun
}

enum RestrictedAppsErrorFeedbackPolicy {
    static func reportsScreenTimeError(
        presentationMode: RestrictedAppsPresentationMode,
        firstRunPhase: FirstRunProtectionPhase
    ) -> Bool {
        presentationMode == .management || firstRunPhase == .selecting
    }
}

enum ProtectedAppsManagementTone: Equatable {
    case live
    case breakInProgress
    case ready
    case empty
    case attention
}

enum ProtectedAppsManagementChrome: Equatable {
    case brandedHeader
    case systemPickerCopy

    init(dynamicTypeSize: DynamicTypeSize, availableHeight: CGFloat) {
        self = dynamicTypeSize >= .xLarge || availableHeight < 620
            ? .systemPickerCopy
            : .brandedHeader
    }
}

struct ProtectedAppsManagementPresentation: Equatable {
    let eyebrow: String
    let status: String
    let title: String
    let detail: String
    let selectionSummary: String
    let systemImage: String
    let tone: ProtectedAppsManagementTone

    init(
        selectionSummary: String,
        hasSelection: Bool,
        hasRequiredScreenTimeAuthorization: Bool,
        isShieldingEnabled: Bool,
        isBreakInProgress: Bool,
        errorMessage: String?
    ) {
        eyebrow = "PROTECTION LIST"
        self.selectionSummary = selectionSummary

        if !hasRequiredScreenTimeAuthorization {
            status = "ACCESS NEEDED"
            title = "Screen Time access needed"
            detail = errorMessage
                ?? "Allow Screen Time access to choose and protect apps."
            systemImage = "exclamationmark.shield.fill"
            tone = .attention
        } else if let errorMessage {
            status = "NEEDS ATTENTION"
            title = "Selection needs attention"
            detail = errorMessage
            systemImage = "exclamationmark.shield.fill"
            tone = .attention
        } else if !hasSelection {
            status = "NOT SET"
            title = "Choose your pause points"
            detail = "Protection is off because no apps or websites are selected. Choose at least one below; changes save automatically."
            systemImage = "shield.slash.fill"
            tone = .empty
        } else if isShieldingEnabled {
            status = "ACTIVE"
            title = "Protection list is live"
            detail = "Changes apply immediately. Turn protection off in Settings before clearing the list."
            systemImage = "checkmark.shield.fill"
            tone = .live
        } else if isBreakInProgress {
            status = "BREAK ACTIVE"
            title = "Ready for the next lock"
            detail = "Changes save now and apply when this break ends. Turn protection off in Settings before clearing the list."
            systemImage = "timer"
            tone = .breakInProgress
        } else {
            status = "SAVED"
            title = "Your list is ready"
            detail = "Your choices save automatically. Start protection from Home or Settings when you're ready."
            systemImage = "checkmark.circle.fill"
            tone = .ready
        }
    }

    var accessibilityLabel: String {
        "\(title). \(status). \(selectionSummary). \(detail)"
    }

    var pickerHeaderText: String {
        "\(status.capitalized) · \(title)\n\(selectionSummary)\n\n\(detail)"
    }

    func pickerHeaderText(isCondensed: Bool) -> String {
        guard isCondensed else { return pickerHeaderText }

        let condensedTitle: String
        let condensedDetail: String
        switch tone {
        case .live:
            condensedTitle = "Protection active"
            condensedDetail = "Changes apply immediately. Use Settings to turn protection off."
        case .breakInProgress:
            condensedTitle = "Break active"
            condensedDetail = "Changes apply when the break ends. Use Settings to turn protection off."
        case .ready:
            condensedTitle = "List saved"
            condensedDetail = "Start protection from Home or Settings."
        case .empty:
            condensedTitle = "Choose apps"
            condensedDetail = "Protection is off. Choices save automatically."
        case .attention:
            condensedTitle = status == "ACCESS NEEDED"
                ? "Screen Time access needed"
                : "Needs attention"
            condensedDetail = detail
        }

        return "\(condensedTitle)\n\(selectionSummary)\n\n\(condensedDetail)"
    }

    func pickerFooterText(categorySelectionDetail: String?) -> String? {
        categorySelectionDetail
    }
}

struct ProtectedAppsCategorySelectionPresentation: Equatable {
    let detail: String?

    init(
        hasCategorySelection: Bool,
        hasProtectedItems: Bool,
        usesLegacyCategoryEnforcement: Bool
    ) {
        guard hasCategorySelection else {
            detail = nil
            return
        }

        if usesLegacyCategoryEnforcement {
            detail = "This older selection protects the whole category. Change a choice below to update it to the current app and website list."
        } else if hasProtectedItems {
            detail = "Category shortcuts add their apps and websites to this list. Your individual changes take precedence."
        } else {
            detail = "Keep at least one app selected from the category, or choose a website, so Checkpoint has something to protect."
        }
    }
}

enum FirstRunProtectionPhase: Equatable, Hashable {
    case selecting
    case preparing(selectionSummary: String)
    case failed(selectionSummary: String, message: String)
    case protected(selectionSummary: String)

    var selectionSummary: String? {
        switch self {
        case .selecting:
            nil
        case let .preparing(selectionSummary),
             let .failed(selectionSummary, _),
             let .protected(selectionSummary):
            selectionSummary
        }
    }

    var isPreparing: Bool {
        if case .preparing = self { return true }
        return false
    }
}

@MainActor
@Observable
final class FirstRunProtectionFlow {
    private(set) var phase: FirstRunProtectionPhase

    @ObservationIgnored private let startProtectionAction: @MainActor () async -> FirstRunProtectionStartResult
    @ObservationIgnored private let finishProtectedSetupAction: @MainActor () -> Void
    @ObservationIgnored private let continueWithoutProtectionAction: @MainActor () -> Void
    @ObservationIgnored private let protectionUnavailableAction: @MainActor () -> Void
    @ObservationIgnored private var didConclude = false

    init(
        initialPhase: FirstRunProtectionPhase = .selecting,
        startProtection: @escaping @MainActor () async -> FirstRunProtectionStartResult,
        finishProtectedSetup: @escaping @MainActor () -> Void,
        continueWithoutProtection: @escaping @MainActor () -> Void,
        protectionUnavailable: @escaping @MainActor () -> Void = {}
    ) {
        phase = initialPhase
        startProtectionAction = startProtection
        finishProtectedSetupAction = finishProtectedSetup
        continueWithoutProtectionAction = continueWithoutProtection
        protectionUnavailableAction = protectionUnavailable
    }

    func start(selectionSummary: String) async {
        guard !didConclude else { return }
        switch phase {
        case .selecting, .failed:
            break
        case .preparing, .protected:
            return
        }

        phase = .preparing(selectionSummary: selectionSummary)
        let result = await startProtectionAction()

        guard !Task.isCancelled else {
            if case .preparing = phase {
                phase = .selecting
            }
            return
        }
        guard !didConclude, case .preparing = phase else { return }
        switch result {
        case let .failed(message):
            phase = .failed(selectionSummary: selectionSummary, message: message)
        case let .protected(selectionSummary):
            phase = .protected(selectionSummary: selectionSummary)
        }
    }

    @discardableResult
    func editSelection() -> Bool {
        guard !didConclude, case .failed = phase else { return false }
        phase = .selecting
        return true
    }

    @discardableResult
    func finishProtectedSetup() -> Bool {
        guard !didConclude, case .protected = phase else { return false }
        didConclude = true
        finishProtectedSetupAction()
        return true
    }

    @discardableResult
    func continueWithoutProtection() -> Bool {
        guard !didConclude else { return false }
        switch phase {
        case .selecting, .failed:
            break
        case .preparing, .protected:
            return false
        }
        didConclude = true
        continueWithoutProtectionAction()
        return true
    }

    @discardableResult
    func protectionDidBecomeUnavailable(message: String) -> Bool {
        guard !didConclude,
              case let .protected(selectionSummary) = phase else {
            return false
        }
        phase = .failed(selectionSummary: selectionSummary, message: message)
        protectionUnavailableAction()
        return true
    }
}

enum FirstRunProtectionStatusTone: Equatable {
    case working
    case failure
    case success
}

struct FirstRunProtectionStatusPresentation: Equatable {
    let goalContext: FirstRunGoalContext
    let stage: String
    let eyebrow: String
    let title: String
    let detail: String
    let supportingTitle: String
    let supportingDetail: String
    let operationalNote: String?
    let selectionSummary: String
    let systemImage: String
    let tone: FirstRunProtectionStatusTone

    init?(
        phase: FirstRunProtectionPhase,
        goalContext: FirstRunGoalContext,
        hasSelection: Bool = true
    ) {
        self.goalContext = goalContext
        switch phase {
        case .selecting:
            return nil
        case let .preparing(selectionSummary):
            stage = "Turning on protection"
            eyebrow = "FINALIZING SETUP"
            title = "Preparing your first checkpoint"
            detail = "Checkpoint is preparing a reliable first attempt for this goal before protection turns on."
            supportingTitle = "Protection waits for a ready checkpoint"
            supportingDetail = "Enough questions must be ready before Checkpoint protects your apps."
            operationalNote = "Keep Checkpoint open while your first checkpoint is prepared."
            self.selectionSummary = selectionSummary
            systemImage = "hourglass"
            tone = .working
        case let .failed(capturedSelectionSummary, message):
            stage = "Needs attention"
            eyebrow = "SETUP NEEDS ATTENTION"
            title = "Protection isn't on yet"
            detail = message
            if hasSelection {
                supportingTitle = "Your goal and app choices are saved"
                supportingDetail = "Try again, choose different apps, or continue with this goal without protection."
                selectionSummary = capturedSelectionSummary
            } else {
                supportingTitle = "Choose apps for this goal"
                supportingDetail = "Select at least one app or website, then try turning protection on again."
                selectionSummary = "No protected apps selected"
            }
            operationalNote = nil
            systemImage = "exclamationmark.shield.fill"
            tone = .failure
        case let .protected(selectionSummary):
            stage = "Protection ready"
            eyebrow = "SETUP COMPLETE"
            title = "Protection is on"
            detail = "Opening a protected app now starts a checkpoint for this goal before a timed break."
            supportingTitle = "Your first checkpoint is ready"
            supportingDetail =
                "Open a protected app to practice this goal. "
                + "You can change your app choices later in Settings."
            operationalNote = nil
            self.selectionSummary = selectionSummary
            systemImage = "checkmark.shield.fill"
            tone = .success
        }
    }

    var accessibilityLabel: String {
        switch tone {
        case .working:
            "Preparing the first checkpoint for \(goalContext.title). "
                + "\(selectionSummary). Protection will turn on when enough questions are ready. "
                + (operationalNote ?? "")
        case .failure:
            "Protection is not on for \(goalContext.title). \(selectionSummary). \(detail)"
        case .success:
            "Protection is on for \(goalContext.title). \(selectionSummary). "
                + "Opening a protected app now starts a checkpoint before a timed break."
        }
    }
}

enum FirstRunProtectionActionDetailTone: Equatable {
    case standard
    case warning
}

enum FirstRunProtectionPrimaryAction: Equatable {
    case startProtection
    case editSelection
    case finishProtectedSetup
    case none
}

struct FirstRunProtectionActionPresentation: Equatable {
    let detail: String?
    let detailTone: FirstRunProtectionActionDetailTone
    let hidesDetailAtAccessibilitySizes: Bool
    let primaryTitle: String
    let primarySystemImage: String
    let isPrimaryLoading: Bool
    let isPrimaryEnabled: Bool
    let primaryAction: FirstRunProtectionPrimaryAction
    let secondaryTitle: String?

    init(
        phase: FirstRunProtectionPhase,
        hasSelection: Bool,
        hasCategoryOnlySelection: Bool
    ) {
        switch phase {
        case .selecting:
            hidesDetailAtAccessibilitySizes = true
            if hasSelection {
                detail = nil
                detailTone = .standard
            } else if hasCategoryOnlySelection {
                detail = "Select an app inside the category, or set this up later."
                detailTone = .warning
            } else {
                detail = nil
                detailTone = .standard
            }
            primaryTitle = hasSelection ? "Turn on protection" : "Choose apps first"
            primarySystemImage = "checkmark.shield"
            isPrimaryLoading = false
            isPrimaryEnabled = hasSelection
            primaryAction = hasSelection ? .startProtection : .none
            secondaryTitle = "Set up later"
        case .preparing:
            hidesDetailAtAccessibilitySizes = true
            detail = "Keep Checkpoint open while your first checkpoint is prepared."
            detailTone = .standard
            primaryTitle = "Turning on protection"
            primarySystemImage = "checkmark.shield"
            isPrimaryLoading = true
            isPrimaryEnabled = false
            primaryAction = .none
            secondaryTitle = nil
        case .failed:
            hidesDetailAtAccessibilitySizes = false
            detail = nil
            detailTone = .standard
            primaryTitle = hasSelection ? "Try again" : "Choose apps"
            primarySystemImage = hasSelection ? "arrow.clockwise" : "slider.horizontal.3"
            isPrimaryLoading = false
            isPrimaryEnabled = true
            primaryAction = hasSelection ? .startProtection : .editSelection
            secondaryTitle = "Continue without protection"
        case .protected:
            hidesDetailAtAccessibilitySizes = false
            detail = nil
            detailTone = .standard
            primaryTitle = "Go to Home"
            primarySystemImage = "house"
            isPrimaryLoading = false
            isPrimaryEnabled = true
            primaryAction = .finishProtectedSetup
            secondaryTitle = nil
        }
    }
}

enum FirstRunProtectionMotionStyle: Equatable {
    case choreographed
    case identity
}

struct FirstRunProtectionMotionPolicy {
    let reduceMotion: Bool
    let voiceOverEnabled: Bool
    let switchControlEnabled: Bool

    init(
        reduceMotion: Bool,
        voiceOverEnabled: Bool = false,
        switchControlEnabled: Bool = false
    ) {
        self.reduceMotion = reduceMotion
        self.voiceOverEnabled = voiceOverEnabled
        self.switchControlEnabled = switchControlEnabled
    }

    var style: FirstRunProtectionMotionStyle {
        reduceMotion || voiceOverEnabled || switchControlEnabled
            ? .identity
            : .choreographed
    }

    var animation: Animation? {
        style == .identity ? nil : CheckpointMotion.reveal
    }
}

enum FirstGoalSuccessHandoffMotionStyle: Equatable {
    case reveal
    case identity
}

struct FirstGoalSuccessHandoffMotionPolicy {
    let reduceMotion: Bool
    let voiceOverEnabled: Bool
    let switchControlEnabled: Bool

    init(
        reduceMotion: Bool,
        voiceOverEnabled: Bool = false,
        switchControlEnabled: Bool = false
    ) {
        self.reduceMotion = reduceMotion
        self.voiceOverEnabled = voiceOverEnabled
        self.switchControlEnabled = switchControlEnabled
    }

    var style: FirstGoalSuccessHandoffMotionStyle {
        reduceMotion || voiceOverEnabled || switchControlEnabled
            ? .identity
            : .reveal
    }

    var animation: Animation? {
        style == .identity ? nil : CheckpointMotion.reveal
    }
}

struct FirstGoalSuccessHandoffDeliveryTaskID: Hashable {
    let deliveryID: UUID?
    let goalID: UUID?
    let context: FirstGoalSuccessHandoffDeliveryContext
}

struct FirstRunAppSelectionHeaderPresentation: Equatable {
    let goalContext: FirstRunGoalContext
    let isSuccessHandoff: Bool
    let stage: String
    let title: String
    let systemImage: String
    let detail: String

    init(
        goalContext: FirstRunGoalContext,
        didJustSaveGoal: Bool
    ) {
        self.goalContext = goalContext
        isSuccessHandoff = didJustSaveGoal
        if !isSuccessHandoff {
            stage = "Choose apps"
            title = "Choose apps to protect"
            systemImage = "checkmark.shield.fill"
            detail = "Pause distracting apps until you clear a checkpoint. This is optional."
        } else {
            stage = "Goal saved"
            title = "Choose apps to protect"
            systemImage = "checkmark.circle.fill"
            detail = "Pause distracting apps until you clear a checkpoint. This is optional."
        }
    }

    func pickerHeaderText(
        selectionSummary: String,
        errorMessage: String?,
        isCondensed: Bool = false,
        condensedSelectionSummary: String? = nil
    ) -> String {
        if isCondensed {
            var lines = [
                isSuccessHandoff ? "Goal saved · Final" : "Step 3 of 3",
                "Checkpoint for: \(goalContext.title)",
                condensedSelectionSummary ?? selectionSummary,
            ]
            if let errorMessage {
                lines.append("Needs attention: \(errorMessage)")
            }
            return lines.joined(separator: "\n")
        }

        var sections = [
            "\(stage) · Step 3 of 3",
            "\(title)\nCheckpoint for: \(goalContext.title)\n\(selectionSummary)",
            detail,
        ]
        if let errorMessage {
            sections.append("Needs attention: \(errorMessage)")
        }
        return sections.joined(separator: "\n\n")
    }

    func pickerFooterText(categorySelectionDetail: String?) -> String {
        [detail, categorySelectionDetail]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }
}

enum FirstRunAppSelectionChrome: Equatable {
    case brandedHeader
    case systemPickerCopy

    init(dynamicTypeSize: DynamicTypeSize) {
        self = dynamicTypeSize >= .accessibility3
            ? .systemPickerCopy
            : .brandedHeader
    }
}

enum FirstRunAppSelectionLayoutPolicy {
    static func showsCategorySelectionDetail(
        dynamicTypeSize: DynamicTypeSize,
        availableHeight: CGFloat
    ) -> Bool {
        dynamicTypeSize.isAccessibilitySize || availableHeight >= 700
    }

    static func usesMinimalAccessibilityHeader(
        dynamicTypeSize: DynamicTypeSize,
        availableHeight: CGFloat
    ) -> Bool {
        dynamicTypeSize.isAccessibilitySize && availableHeight < 700
    }
}

struct FirstRunProtectionLiveState: Equatable {
    let isAuthorized: Bool
    let hasSelection: Bool
    let hasActiveProtectionIntent: Bool

    var isValid: Bool {
        isAuthorized && hasSelection && hasActiveProtectionIntent
    }
}

enum FirstRunProtectionFocus: Hashable {
    case preparing
    case failure
    case success

    static func destination(for phase: FirstRunProtectionPhase) -> Self? {
        switch phase {
        case .selecting:
            nil
        case .preparing:
            .preparing
        case .failed:
            .failure
        case .protected:
            .success
        }
    }

    static func movesProgrammatically(
        voiceOverEnabled: Bool,
        switchControlEnabled: Bool
    ) -> Bool {
        voiceOverEnabled && !switchControlEnabled
    }
}

struct RestrictedAppsView: View {
    let screenTime: ScreenTimeController
    let presentationMode: RestrictedAppsPresentationMode
    private let reduceMotionOverride: Bool?
    private let goalContext: FirstRunGoalContext?
    private let allowsFirstGoalHandoffDelivery: Bool
    private let firstGoalHandoff: FirstGoalSuccessHandoffToken?
    private let onFirstGoalHandoffConsumed: @MainActor (FirstGoalSuccessHandoffToken) -> FirstRunGoalContext?
    private let onFirstGoalHandoffDelivered: @MainActor (FirstGoalSuccessHandoffDeliveryEffect) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var firstRunFlow: FirstRunProtectionFlow
    @State private var firstGoalHandoffDelivery: FirstGoalSuccessHandoffDeliveryState
    @State private var firstGoalHandoffRevealSequence = 0
    @State private var successFeedbackSequence = 0
    @State private var errorFeedbackSequence = 0
    @State private var protectionStartTask: Task<Void, Never>? = nil

    init(screenTime: ScreenTimeController) {
        self.screenTime = screenTime
        presentationMode = .management
        reduceMotionOverride = nil
        goalContext = nil
        allowsFirstGoalHandoffDelivery = false
        firstGoalHandoff = nil
        onFirstGoalHandoffConsumed = { _ in nil }
        onFirstGoalHandoffDelivered = { _ in }
        _firstRunFlow = State(
            initialValue: FirstRunProtectionFlow(
                startProtection: {
                    .failed(message: "First-run protection setup is unavailable.")
                },
                finishProtectedSetup: {},
                continueWithoutProtection: {}
            )
        )
        _firstGoalHandoffDelivery = State(
            initialValue: FirstGoalSuccessHandoffDeliveryState()
        )
    }

    init(
        screenTime: ScreenTimeController,
        onStartProtection: @escaping @MainActor () async -> FirstRunProtectionStartResult,
        onFinishProtectedSetup: @escaping @MainActor () -> Void,
        onContinueWithoutProtection: @escaping @MainActor () -> Void,
        onProtectionUnavailable: @escaping @MainActor () -> Void = {},
        initialPhase: FirstRunProtectionPhase = .selecting,
        reduceMotionOverride: Bool? = nil,
        goalContext: FirstRunGoalContext,
        allowsFirstGoalHandoffDelivery: Bool = true,
        firstGoalHandoff: FirstGoalSuccessHandoffToken? = nil,
        onFirstGoalHandoffConsumed: @escaping @MainActor
            (FirstGoalSuccessHandoffToken) -> FirstRunGoalContext? = { _ in nil },
        onFirstGoalHandoffDelivered: @escaping @MainActor (FirstGoalSuccessHandoffDeliveryEffect) -> Void = { _ in }
    ) {
        self.screenTime = screenTime
        presentationMode = .firstRun
        self.reduceMotionOverride = reduceMotionOverride
        self.goalContext = goalContext
        self.allowsFirstGoalHandoffDelivery = allowsFirstGoalHandoffDelivery
        self.firstGoalHandoff = firstGoalHandoff
        self.onFirstGoalHandoffConsumed = onFirstGoalHandoffConsumed
        self.onFirstGoalHandoffDelivered = onFirstGoalHandoffDelivered
        _firstRunFlow = State(
            initialValue: FirstRunProtectionFlow(
                initialPhase: initialPhase,
                startProtection: onStartProtection,
                finishProtectedSetup: onFinishProtectedSetup,
                continueWithoutProtection: onContinueWithoutProtection,
                protectionUnavailable: onProtectionUnavailable
            )
        )
        _firstGoalHandoffDelivery = State(
            initialValue: FirstGoalSuccessHandoffDeliveryState(token: firstGoalHandoff)
        )
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .checkpointScreenBackground()
                .navigationTitle(navigationTitle)
                .toolbarTitleDisplayMode(.inline)
                .toolbar(
                    presentationMode == .firstRun ? .hidden : .visible,
                    for: .navigationBar
                )
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if presentationMode == .firstRun {
                        firstRunActionBar
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        if presentationMode == .management {
                            Button("Done") {
                                dismiss()
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(CheckpointTheme.teal)
                            .accessibilityHint("Your protected-app choices are saved automatically.")
                        }
                    }
                }
        }
        .sensoryFeedback(.success, trigger: successFeedbackSequence)
        .sensoryFeedback(.error, trigger: errorFeedbackSequence)
        .onChange(of: firstGoalHandoff) { _, token in
            firstGoalHandoffDelivery.receive(token)
        }
        .onChange(of: goalContext?.goalID) { _, goalID in
            protectionStartTask?.cancel()
            protectionStartTask = nil
            firstGoalHandoffDelivery.invalidate(unless: goalID)
        }
        .onChange(of: firstRunFlow.phase) { _, phase in
            switch phase {
            case .failed:
                errorFeedbackSequence += 1
            case .protected:
                guard liveProtectionState.isValid else {
                    reconcileLiveProtectionState()
                    return
                }
                successFeedbackSequence += 1
            case .selecting, .preparing:
                break
            }
        }
        .onChange(of: screenTime.userFacingErrorMessage) { _, message in
            guard RestrictedAppsErrorFeedbackPolicy.reportsScreenTimeError(
                presentationMode: presentationMode,
                firstRunPhase: firstRunFlow.phase
            ),
                  let message else { return }
            errorFeedbackSequence += 1
            AccessibilityNotification.Announcement(message).post()
        }
        .task {
            if screenTime.setupState == .notStarted || screenTime.setupState == .failed {
                await screenTime.requestAuthorization()
            }
            reconcileLiveProtectionState()
        }
        .task(id: firstGoalHandoffDeliveryTaskID) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            deliverFirstGoalHandoffIfNeeded()
        }
        .onChange(of: liveProtectionState) { _, state in
            guard !state.isValid else { return }
            reconcileLiveProtectionState()
        }
        .onDisappear {
            protectionStartTask?.cancel()
            protectionStartTask = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if presentationMode == .firstRun,
           FirstRunProtectionStatusPresentation(
               phase: firstRunFlow.phase,
               goalContext: firstRunGoalContext
           ) != nil {
            FirstRunProtectionStatusView(
                phase: firstRunFlow.phase,
                goalContext: firstRunGoalContext,
                reduceMotion: reduceMotion,
                hasSelection: screenTime.hasSelection,
                editSelection: {
                    _ = firstRunFlow.editSelection()
                }
            )
            .id(firstRunFlow.phase)
        } else {
        #if os(iOS) && canImport(FamilyControls)
            FamilyPickerContent(
                screenTime: screenTime,
                presentationMode: presentationMode,
                goalContext: goalContext,
                didJustSaveGoal: presentedFirstGoalHandoff != nil,
                firstGoalHandoffRevealSequence: firstGoalHandoffRevealSequence,
                reduceMotion: reduceMotion
            )
        #else
            ScrollView {
                SectionPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(CheckpointTheme.amber)

                        Text("App protection unavailable")
                            .font(.title3.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("App protection is available on iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
        #endif
        }
    }

    private var firstRunActionBar: some View {
        FirstRunProtectionActionBar(
            presentation: firstRunActionPresentation,
            primaryAction: handleFirstRunPrimaryAction,
            secondaryAction: {
                _ = firstRunFlow.continueWithoutProtection()
            }
        )
    }

    private var firstRunActionPresentation: FirstRunProtectionActionPresentation {
        FirstRunProtectionActionPresentation(
            phase: firstRunFlow.phase,
            hasSelection: screenTime.hasSelection,
            hasCategoryOnlySelection: hasCategoryOnlySelection
        )
    }

    private var navigationTitle: String {
        guard presentationMode == .firstRun else { return "Protected Apps" }
        switch firstRunFlow.phase {
        case .selecting:
            return "Choose Apps"
        case .preparing:
            return "Starting Protection"
        case .failed:
            return "Protection Setup"
        case .protected:
            return "Setup Complete"
        }
    }

    private var hasCategoryOnlySelection: Bool {
        #if os(iOS) && canImport(FamilyControls)
        !screenTime.selection.categoryTokens.isEmpty && !screenTime.hasSelection
        #else
        false
        #endif
    }

    private func handleFirstRunPrimaryAction() {
        switch firstRunActionPresentation.primaryAction {
        case .startProtection:
            guard protectionStartTask == nil else { return }
            let selectionSummary = screenTime.restrictedAppsSummary
            let flow = firstRunFlow
            protectionStartTask = Task { @MainActor in
                defer { protectionStartTask = nil }
                await flow.start(selectionSummary: selectionSummary)
            }
        case .editSelection:
            _ = firstRunFlow.editSelection()
        case .finishProtectedSetup:
            guard liveProtectionState.isValid else {
                reconcileLiveProtectionState()
                return
            }
            _ = firstRunFlow.finishProtectedSetup()
        case .none:
            break
        }
    }

    private var liveProtectionState: FirstRunProtectionLiveState {
        FirstRunProtectionLiveState(
            isAuthorized: screenTime.hasRequiredScreenTimeAuthorization,
            hasSelection: screenTime.hasSelection,
            hasActiveProtectionIntent: screenTime.isShieldingEnabled
                || screenTime.setupState == .temporarilyUnlocked
                || SharedAppGroup.desiredShieldActive
        )
    }

    private var firstGoalHandoffDeliveryTaskID: FirstGoalSuccessHandoffDeliveryTaskID {
        FirstGoalSuccessHandoffDeliveryTaskID(
            deliveryID: firstGoalHandoffDelivery.candidateForDelivery?.deliveryID,
            goalID: firstGoalHandoffDelivery.candidateForDelivery?.goalID,
            context: firstGoalHandoffDeliveryContext
        )
    }

    private var firstGoalHandoffDeliveryContext: FirstGoalSuccessHandoffDeliveryContext {
        FirstGoalSuccessHandoffDeliveryContext(
            goalContext: goalContext,
            phase: firstRunFlow.phase,
            isAuthorized: screenTime.hasRequiredScreenTimeAuthorization,
            errorMessage: screenTime.userFacingErrorMessage,
            isExposed: allowsFirstGoalHandoffDelivery
        )
    }

    private func reconcileLiveProtectionState() {
        guard presentationMode == .firstRun,
              !liveProtectionState.isValid else {
            return
        }
        _ = firstRunFlow.protectionDidBecomeUnavailable(
            message: "Protection turned off before setup finished. Try turning it on again."
        )
    }

    private func deliverFirstGoalHandoffIfNeeded() {
        guard presentationMode == .firstRun else { return }
        guard let effect = firstGoalHandoffDelivery.attemptDelivery(
            in: firstGoalHandoffDeliveryContext,
            authoritativeConsumeAndResolveContext: onFirstGoalHandoffConsumed
        ) else { return }

        firstGoalHandoffRevealSequence += effect.revealSequenceIncrement
        successFeedbackSequence += effect.successFeedbackSequenceIncrement
        AccessibilityNotification.Announcement(effect.accessibilityAnnouncement).post()
        onFirstGoalHandoffDelivered(effect)
    }

    private var firstRunGoalContext: FirstRunGoalContext {
        guard let goalContext else {
            preconditionFailure("First-run app selection requires a current goal")
        }
        return goalContext
    }

    private var presentedFirstGoalHandoff: FirstGoalSuccessHandoffToken? {
        guard firstGoalHandoffDelivery.presentedToken?.goalID == goalContext?.goalID else {
            return nil
        }
        return firstGoalHandoffDelivery.presentedToken
    }
}

struct FirstRunProtectionActionBar: View {
    let presentation: FirstRunProtectionActionPresentation
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            if let detail = presentation.detail,
               !(presentation.hidesDetailAtAccessibilitySizes && dynamicTypeSize.isAccessibilitySize) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }

            PrimaryActionButton(
                title: presentation.primaryTitle,
                systemImage: presentation.primarySystemImage,
                isLoading: presentation.isPrimaryLoading,
                action: primaryAction
            )
            .disabled(!presentation.isPrimaryEnabled)
            .accessibilityHint(presentation.detail ?? "")
            .padding(.horizontal, 20)

            if let secondaryTitle = presentation.secondaryTitle {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(CheckpointPressButtonStyle())
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var detailColor: Color {
        switch presentation.detailTone {
        case .standard:
            CheckpointTheme.muted
        case .warning:
            CheckpointTheme.amber
        }
    }
}

struct FirstRunGoalContextStrip: View {
    let goalContext: FirstRunGoalContext
    var compactsTitleForPicker = false
    var compactPickerLineLimit = 3

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "scope")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 28, height: 28)
                .background(
                    CheckpointTheme.teal.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .fixedSize()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("CHECKPOINT FOR")
                    .font(.caption2.weight(.bold))
                    .tracking(0.75)
                    .foregroundStyle(CheckpointTheme.teal)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                Text(goalContext.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .dynamicTypeSize(...titleMaximumDynamicTypeSize)
                    .lineLimit(
                        compactsTitleForPicker && dynamicTypeSize.isAccessibilitySize
                            ? compactPickerLineLimit
                            : (dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised,
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
            .stroke(CheckpointTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goalContext.accessibilityLabel)
    }

    private var titleMaximumDynamicTypeSize: DynamicTypeSize {
        compactsTitleForPicker ? .accessibility2 : .accessibility5
    }
}

struct FirstRunProtectionStatusView: View {
    let phase: FirstRunProtectionPhase
    let goalContext: FirstRunGoalContext
    let reduceMotion: Bool
    var hasSelection = true
    let editSelection: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @AccessibilityFocusState private var focusedDestination: FirstRunProtectionFocus?
    @State private var isRevealed = false
    @State private var successSymbolSequence = 0

    var body: some View {
        GeometryReader { proxy in
            let usesTightSpacing = dynamicTypeSize.isAccessibilitySize || proxy.size.height < 640

            ScrollView {
                VStack(alignment: .leading, spacing: usesTightSpacing ? 14 : 20) {
                    CheckpointSetupMark(
                        stage: presentation.stage,
                        step: 3,
                        systemImage: setupSystemImage,
                        compact: usesTightSpacing,
                        reduceMotionOverride: motionPolicy.style == .identity
                    )

                    FirstRunGoalContextStrip(
                        goalContext: goalContext
                    )
                    statusHero(usesTightSpacing: usesTightSpacing)
                    supportingPanel
                }
                .padding(.horizontal, 20)
                .padding(.top, usesTightSpacing ? 16 : 24)
                .padding(.bottom, usesTightSpacing ? 28 : 36)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .opacity(motionPolicy.style == .identity || isRevealed ? 1 : 0)
        .onAppear {
            revealStatus()
        }
        .task(id: phase) {
            let destination = focusDestination
            let tone = presentation.tone
            await Task.yield()
            guard !Task.isCancelled else { return }
            if FirstRunProtectionFocus.movesProgrammatically(
                voiceOverEnabled: voiceOverEnabled,
                switchControlEnabled: switchControlEnabled
            ) {
                focusedDestination = destination
            }
            if tone == .success {
                successSymbolSequence += 1
            }
        }
    }

    private func statusHero(usesTightSpacing: Bool) -> some View {
        CheckpointHeroSurface(
            glowColor: accent,
            glowOpacity: presentation.tone == .success ? 0.12 : 0.09,
            contentPadding: usesTightSpacing ? 14 : 18
        ) {
            VStack(alignment: .leading, spacing: usesTightSpacing ? 14 : 18) {
                statusIdentity(usesTightSpacing: usesTightSpacing)

                Text(presentation.detail)
                    .font(
                        usesTightSpacing && !dynamicTypeSize.isAccessibilitySize
                            ? .footnote.weight(.medium)
                            : .subheadline.weight(.medium)
                    )
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if dynamicTypeSize.isAccessibilitySize,
                   let operationalNote = presentation.operationalNote {
                    Label(operationalNote, systemImage: "iphone")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.heroText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            CheckpointTheme.heroSubtleFill,
                            in: RoundedRectangle(
                                cornerRadius: CheckpointTheme.compactCornerRadius,
                                style: .continuous
                            )
                        )
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Label(presentation.selectionSummary, systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.heroText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(CheckpointTheme.heroSubtleFill, in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($focusedDestination, equals: focusDestination)
    }

    @ViewBuilder
    private func statusIdentity(usesTightSpacing: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: usesTightSpacing ? 10 : 12) {
                statusIcon(usesTightSpacing: usesTightSpacing)
                statusTitle(usesTightSpacing: usesTightSpacing)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 13) {
                    statusIcon(usesTightSpacing: usesTightSpacing)
                    statusTitle(usesTightSpacing: usesTightSpacing)
                }

                VStack(alignment: .leading, spacing: usesTightSpacing ? 10 : 12) {
                    statusIcon(usesTightSpacing: usesTightSpacing)
                    statusTitle(usesTightSpacing: usesTightSpacing)
                }
            }
        }
    }

    private func statusIcon(usesTightSpacing: Bool) -> some View {
        let size: CGFloat = usesTightSpacing ? 48 : 56
        return Image(systemName: presentation.systemImage)
            .font(.system(size: usesTightSpacing ? 20 : 23, weight: .bold))
            .foregroundStyle(CheckpointTheme.ink)
            .frame(width: size, height: size)
            .background(
                accent,
                in: RoundedRectangle(
                    cornerRadius: usesTightSpacing ? 15 : 17,
                    style: .continuous
                )
            )
            .symbolEffect(.bounce, options: .nonRepeating, value: successSymbolSequence)
            .symbolEffectsRemoved(
                motionPolicy.style == .identity || presentation.tone != .success
            )
            .fixedSize()
            .accessibilityHidden(true)
    }

    private func statusTitle(usesTightSpacing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(0.85)
                .foregroundStyle(accent)

            Text(presentation.title)
                .font(
                    usesTightSpacing && !dynamicTypeSize.isAccessibilitySize
                        ? .title3.weight(.bold)
                        : .title2.weight(.bold)
                )
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var supportingPanel: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                supportingIdentity

                if dynamicTypeSize.isAccessibilitySize {
                    Label(presentation.selectionSummary, systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            CheckpointTheme.panelRaised,
                            in: RoundedRectangle(
                                cornerRadius: CheckpointTheme.compactCornerRadius,
                                style: .continuous
                            )
                        )
                        .accessibilityHidden(true)
                }

                if presentation.tone == .failure, hasSelection {
                    Button(action: editSelection) {
                        Label("Choose different apps", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.teal)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CheckpointPressButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var supportingIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                supportingIcon
                supportingCopy
            }
        } else {
            HStack(alignment: .top, spacing: 11) {
                supportingIcon
                supportingCopy
            }
        }
    }

    private var supportingIcon: some View {
        Image(systemName: supportingSystemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(supportingAccent)
            .frame(width: 34, height: 34)
            .background(
                supportingAccent.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var supportingCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.supportingTitle)
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(presentation.supportingDetail)
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var presentation: FirstRunProtectionStatusPresentation {
        guard let presentation = FirstRunProtectionStatusPresentation(
            phase: phase,
            goalContext: goalContext,
            hasSelection: hasSelection
        ) else {
            preconditionFailure("A selecting phase does not have a status presentation")
        }
        return presentation
    }

    private var focusDestination: FirstRunProtectionFocus {
        guard let destination = FirstRunProtectionFocus.destination(for: phase) else {
            preconditionFailure("A selecting phase does not have a focus destination")
        }
        return destination
    }

    private var accent: Color {
        switch presentation.tone {
        case .working:
            CheckpointTheme.heroInfo
        case .failure:
            CheckpointTheme.heroDanger
        case .success:
            CheckpointTheme.heroSuccess
        }
    }

    private var supportingAccent: Color {
        switch presentation.tone {
        case .working:
            CheckpointTheme.blue
        case .failure:
            CheckpointTheme.coral
        case .success:
            CheckpointTheme.teal
        }
    }

    private var supportingSystemImage: String {
        switch presentation.tone {
        case .working:
            "checklist"
        case .failure:
            "arrow.clockwise"
        case .success:
            "flag.checkered"
        }
    }

    private var setupSystemImage: String {
        switch presentation.tone {
        case .working:
            "hourglass"
        case .failure:
            "exclamationmark.shield.fill"
        case .success:
            "checkmark.shield.fill"
        }
    }

    private func revealStatus() {
        withAnimation(motionPolicy.animation) {
            isRevealed = true
        }
    }

    private var motionPolicy: FirstRunProtectionMotionPolicy {
        FirstRunProtectionMotionPolicy(
            reduceMotion: reduceMotion,
            voiceOverEnabled: voiceOverEnabled,
            switchControlEnabled: switchControlEnabled
        )
    }
}

struct ProtectedAppsManagementHeader: View {
    let presentation: ProtectedAppsManagementPresentation
    let categorySelectionDetail: String?
    var changeSequence = 0
    var compact = false
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            CheckpointHeroSurface(
                glowColor: accent,
                glowOpacity: presentation.tone == .live ? 0.13 : 0.09,
                contentPadding: compact ? 10 : (dynamicTypeSize.isAccessibilitySize ? 14 : 16)
            ) {
                VStack(alignment: .leading, spacing: compact ? 8 : (dynamicTypeSize.isAccessibilitySize ? 14 : 12)) {
                    identity

                    Text(presentation.detail)
                        .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()
                        .overlay(CheckpointTheme.heroDivider)

                    Label {
                        Text(presentation.selectionSummary)
                            .contentTransition(.numericText())
                    } icon: {
                        Image(systemName: "checklist")
                    }
                    .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.heroText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 11)
                    .padding(.vertical, compact ? 6 : 8)
                    .background(
                        CheckpointTheme.heroSubtleFill,
                        in: RoundedRectangle(
                            cornerRadius: dynamicTypeSize.isAccessibilitySize
                                ? CheckpointTheme.compactCornerRadius
                                : 100,
                            style: .continuous
                        )
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityAddTraits(.isHeader)

            if let categorySelectionDetail {
                Label(categorySelectionDetail, systemImage: "square.stack.3d.up.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CheckpointTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(compact ? 8 : 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        CheckpointTheme.amber.opacity(0.08),
                        in: RoundedRectangle(
                            cornerRadius: CheckpointTheme.compactCornerRadius,
                            style: .continuous
                        )
                    )
            }
        }
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: presentation
        )
    }

    @ViewBuilder
    private var identity: some View {
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    managementIcon
                    Spacer(minLength: 8)
                    statusBadge
                }
                identityCopy
            }
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                managementIcon
                identityCopy
                statusBadge
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 13) {
                    managementIcon
                    identityCopy
                    Spacer(minLength: 8)
                    statusBadge
                }

                VStack(alignment: .leading, spacing: 10) {
                    managementIcon
                    identityCopy
                    statusBadge
                }
            }
        }
    }

    private var managementIcon: some View {
        Image(systemName: presentation.systemImage)
            .font(.system(size: compact ? 17 : (dynamicTypeSize.isAccessibilitySize ? 20 : 21), weight: .bold))
            .foregroundStyle(CheckpointTheme.ink)
            .frame(
                width: compact ? 40 : (dynamicTypeSize.isAccessibilitySize ? 48 : 50),
                height: compact ? 40 : (dynamicTypeSize.isAccessibilitySize ? 48 : 50)
            )
            .background(
                accent,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, options: .nonRepeating, value: changeSequence)
            .symbolEffectsRemoved(reduceMotion)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var identityCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(presentation.eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(0.85)
                .foregroundStyle(accent)

            Text(presentation.title)
                .font(compact ? .headline : (dynamicTypeSize.isAccessibilitySize ? .title3.bold() : .title2.bold()))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusBadge: some View {
        Text(presentation.status)
            .font(.caption2.weight(.bold))
            .tracking(0.65)
            .foregroundStyle(accent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                accent.opacity(0.14),
                in: RoundedRectangle(
                    cornerRadius: dynamicTypeSize.isAccessibilitySize
                        ? CheckpointTheme.compactCornerRadius
                        : 100,
                    style: .continuous
                )
            )
    }

    private var accent: Color {
        switch presentation.tone {
        case .live:
            CheckpointTheme.heroSuccess
        case .breakInProgress:
            CheckpointTheme.heroInfo
        case .ready:
            CheckpointTheme.heroSuccess
        case .empty:
            CheckpointTheme.heroWarning
        case .attention:
            CheckpointTheme.heroDanger
        }
    }
}

struct ProtectedAppsManagementShell<PickerContent: View>: View {
    let presentation: ProtectedAppsManagementPresentation
    let categorySelectionDetail: String?
    let changeSequence: Int
    let reduceMotionOverride: Bool?
    let pickerContent: PickerContent

    init(
        presentation: ProtectedAppsManagementPresentation,
        categorySelectionDetail: String?,
        changeSequence: Int,
        reduceMotionOverride: Bool? = nil,
        @ViewBuilder pickerContent: () -> PickerContent
    ) {
        self.presentation = presentation
        self.categorySelectionDetail = categorySelectionDetail
        self.changeSequence = changeSequence
        self.reduceMotionOverride = reduceMotionOverride
        self.pickerContent = pickerContent()
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ProtectedAppsManagementHeader(
                    presentation: presentation,
                    categorySelectionDetail: categorySelectionDetail,
                    changeSequence: changeSequence,
                    compact: proxy.size.height < 700,
                    reduceMotionOverride: reduceMotionOverride
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .background(CheckpointTheme.background)

                pickerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }
        }
    }
}

struct FirstRunAppSelectionHeader: View {
    let goalContext: FirstRunGoalContext
    let selectionSummary: String
    let categorySelectionDetail: String?
    let errorMessage: String?
    var didJustSaveGoal = false
    var firstGoalHandoffRevealSequence = 0
    var reduceMotionOverride: Bool?
    var usesMinimalAccessibilityLayout = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var presentation: FirstRunAppSelectionHeaderPresentation {
        FirstRunAppSelectionHeaderPresentation(
            goalContext: goalContext,
            didJustSaveGoal: didJustSaveGoal
        )
    }

    private var handoffMotionPolicy: FirstGoalSuccessHandoffMotionPolicy {
        FirstGoalSuccessHandoffMotionPolicy(
            reduceMotion: reduceMotion,
            voiceOverEnabled: voiceOverEnabled,
            switchControlEnabled: switchControlEnabled
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !usesMinimalAccessibilityLayout {
                mascotIdentity
                    .animation(
                        handoffMotionPolicy.animation,
                        value: presentation.stage
                    )
            }

            Text("For: \(goalContext.title)")
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)
                .lineLimit(2)
                .accessibilityLabel(goalContext.accessibilityLabel)

            if !dynamicTypeSize.isAccessibilitySize {
                Text(presentation.detail)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(selectionSummary, systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            if let categorySelectionDetail {
                Text(categorySelectionDetail)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(
                        CheckpointTheme.coral.opacity(0.08),
                        in: RoundedRectangle(
                            cornerRadius: CheckpointTheme.compactCornerRadius,
                            style: .continuous
                        )
                    )
            }
        }
    }

    private var mascotIdentity: some View {
        HStack(spacing: 10) {
            CheckpointMascotMark(
                size: dynamicTypeSize.isAccessibilitySize ? 40 : 52,
                cornerRadius: dynamicTypeSize.isAccessibilitySize ? 13 : 16
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("STEP 3 OF 3 · OPTIONAL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)

                Text(presentation.title)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checkpoint setup, step 3 of 3, \(presentation.stage). App selection is optional.")
    }
}

#if os(iOS) && canImport(FamilyControls)
private struct FamilyPickerContent: View {
    let screenTime: ScreenTimeController
    let presentationMode: RestrictedAppsPresentationMode
    let goalContext: FirstRunGoalContext?
    let didJustSaveGoal: Bool
    let firstGoalHandoffRevealSequence: Int
    let reduceMotion: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectionFeedbackSequence = 0
    @State private var selectionRejectionFeedbackSequence = 0

    @ViewBuilder
    var body: some View {
        Group {
            if presentationMode == .firstRun {
                GeometryReader { proxy in
                    firstRunPicker(availableHeight: proxy.size.height)
                }
            } else {
                GeometryReader { proxy in
                    managementPicker(
                        chrome: ProtectedAppsManagementChrome(
                            dynamicTypeSize: dynamicTypeSize,
                            availableHeight: proxy.size.height
                        )
                    )
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectionFeedbackSequence)
        .sensoryFeedback(.error, trigger: selectionRejectionFeedbackSequence)
    }

    @ViewBuilder
    private func firstRunPicker(availableHeight: CGFloat) -> some View {
        switch FirstRunAppSelectionChrome(dynamicTypeSize: dynamicTypeSize) {
        case .brandedHeader:
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    FirstRunAppSelectionHeader(
                        goalContext: firstRunGoalContext,
                        selectionSummary: firstRunSelectionSummary,
                        categorySelectionDetail: inlineCategorySelectionDetail(
                            availableHeight: availableHeight
                        ),
                        errorMessage: screenTime.userFacingErrorMessage,
                        didJustSaveGoal: didJustSaveGoal,
                        firstGoalHandoffRevealSequence: firstGoalHandoffRevealSequence,
                        reduceMotionOverride: reduceMotion,
                        usesMinimalAccessibilityLayout: FirstRunAppSelectionLayoutPolicy
                            .usesMinimalAccessibilityHeader(
                                dynamicTypeSize: dynamicTypeSize,
                                availableHeight: availableHeight
                            )
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(CheckpointTheme.panel)

                FamilyActivityPicker(selection: selectionBinding)
            }
        case .systemPickerCopy:
            FamilyActivityPicker(
                headerText: firstRunHeaderPresentation.pickerHeaderText(
                    selectionSummary: firstRunSelectionSummary,
                    errorMessage: screenTime.userFacingErrorMessage,
                    isCondensed: true,
                    condensedSelectionSummary: firstRunCondensedSelectionSummary
                ),
                footerText: firstRunHeaderPresentation.pickerFooterText(
                    categorySelectionDetail: categorySelectionDetail
                ),
                selection: selectionBinding
            )
        }
    }

    @ViewBuilder
    private func managementPicker(
        chrome: ProtectedAppsManagementChrome
    ) -> some View {
        switch chrome {
        case .brandedHeader:
            ProtectedAppsManagementShell(
                presentation: managementPresentation,
                categorySelectionDetail: categorySelectionDetail,
                changeSequence: selectionFeedbackSequence
            ) {
                FamilyActivityPicker(selection: selectionBinding)
            }
        case .systemPickerCopy:
            FamilyActivityPicker(
                headerText: managementPresentation.pickerHeaderText(
                    isCondensed: dynamicTypeSize.isAccessibilitySize
                ),
                footerText: managementPresentation.pickerFooterText(
                    categorySelectionDetail: categorySelectionDetail
                ),
                selection: selectionBinding
            )
        }
    }

    private var selectionBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { screenTime.selection },
            set: { selection in
                let previousSelection = screenTime.selection
                let previousError = screenTime.userFacingErrorMessage
                if screenTime.updateSelection(selection) {
                    if presentationMode == .management,
                       screenTime.selection != previousSelection {
                        selectionFeedbackSequence += 1
                    }
                    return
                }
                guard let currentError = screenTime.userFacingErrorMessage,
                      currentError == previousError else { return }
                selectionRejectionFeedbackSequence += 1
                AccessibilityNotification.Announcement(currentError).post()
            }
        )
    }

    private var selectionSummary: String {
        screenTime.restrictedAppsSummary
    }

    private var firstRunSelectionSummary: String {
        hasCategoryOnlySelection
            ? "Category selected · choose an app inside"
            : selectionSummary
    }

    private var firstRunCondensedSelectionSummary: String {
        if hasCategoryOnlySelection {
            return firstRunSelectionSummary
        }
        return screenTime.hasSelection ? selectionSummary : "0 selected"
    }

    private var firstRunHeaderPresentation: FirstRunAppSelectionHeaderPresentation {
        FirstRunAppSelectionHeaderPresentation(
            goalContext: firstRunGoalContext,
            didJustSaveGoal: didJustSaveGoal
        )
    }

    private var firstRunGoalContext: FirstRunGoalContext {
        guard let goalContext else {
            preconditionFailure("First-run app selection requires a current goal")
        }
        return goalContext
    }

    private var managementPresentation: ProtectedAppsManagementPresentation {
        ProtectedAppsManagementPresentation(
            selectionSummary: selectionSummary,
            hasSelection: screenTime.hasSelection,
            hasRequiredScreenTimeAuthorization: screenTime.hasRequiredScreenTimeAuthorization,
            isShieldingEnabled: screenTime.isShieldingEnabled,
            isBreakInProgress: screenTime.setupState == .temporarilyUnlocked,
            errorMessage: screenTime.userFacingErrorMessage
        )
    }

    private var categorySelectionDetail: String? {
        ProtectedAppsCategorySelectionPresentation(
            hasCategorySelection: !screenTime.selection.categoryTokens.isEmpty,
            hasProtectedItems: screenTime.hasSelection,
            usesLegacyCategoryEnforcement: screenTime.usesLegacyCategoryEnforcement
        ).detail
    }

    private var hasCategoryOnlySelection: Bool {
        !screenTime.selection.categoryTokens.isEmpty && !screenTime.hasSelection
    }

    private func inlineCategorySelectionDetail(availableHeight: CGFloat) -> String? {
        guard FirstRunAppSelectionLayoutPolicy.showsCategorySelectionDetail(
            dynamicTypeSize: dynamicTypeSize,
            availableHeight: availableHeight
        ) else {
            return nil
        }
        return categorySelectionDetail
    }

}
#endif
