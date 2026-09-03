import Observation
import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

enum RestrictedAppsPresentationMode: Equatable {
    case management
    case firstRun
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
        guard !didConclude, case .failed = phase else { return false }
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
    let stage: String
    let eyebrow: String
    let title: String
    let detail: String
    let supportingTitle: String
    let supportingDetail: String
    let selectionSummary: String
    let systemImage: String
    let tone: FirstRunProtectionStatusTone

    init?(
        phase: FirstRunProtectionPhase,
        hasSelection: Bool = true
    ) {
        switch phase {
        case .selecting:
            return nil
        case let .preparing(selectionSummary):
            stage = "Turning on protection"
            eyebrow = "FINALIZING SETUP"
            title = "Preparing your first checkpoint"
            detail = "Checkpoint is making sure your first attempt is ready before protection turns on."
            supportingTitle = "Protection waits for a ready checkpoint"
            supportingDetail = "Enough questions must be ready before Checkpoint protects your apps."
            self.selectionSummary = selectionSummary
            systemImage = "hourglass"
            tone = .working
        case let .failed(capturedSelectionSummary, message):
            stage = "Needs attention"
            eyebrow = "SETUP NEEDS ATTENTION"
            title = "Protection didn't turn on"
            detail = message
            if hasSelection {
                supportingTitle = "Your app choices are saved"
                supportingDetail = "Try again, choose different apps, or finish setup without protection."
                selectionSummary = capturedSelectionSummary
            } else {
                supportingTitle = "Choose apps to continue"
                supportingDetail = "Select at least one app or website, then try turning protection on again."
                selectionSummary = "No protected apps selected"
            }
            systemImage = "exclamationmark.shield.fill"
            tone = .failure
        case let .protected(selectionSummary):
            stage = "Protection ready"
            eyebrow = "SETUP COMPLETE"
            title = "Protection is on"
            detail = "Opening a protected app now starts a checkpoint before a timed break."
            supportingTitle = "Your first checkpoint is ready"
            supportingDetail = "Open a protected app whenever you're ready. You can change your app choices later in Settings."
            self.selectionSummary = selectionSummary
            systemImage = "checkmark.shield.fill"
            tone = .success
        }
    }

    var accessibilityLabel: String {
        "\(title). \(selectionSummary). \(detail)"
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
            if hasSelection {
                detail = "Your choices are saved. Turn on protection when you're ready."
                detailTone = .standard
            } else if hasCategoryOnlySelection {
                detail = "Keep at least one app selected inside the category to continue."
                detailTone = .warning
            } else {
                detail = "Select at least one app or website to continue."
                detailTone = .warning
            }
            primaryTitle = "Turn on protection"
            primarySystemImage = "checkmark.shield"
            isPrimaryLoading = false
            isPrimaryEnabled = hasSelection
            primaryAction = hasSelection ? .startProtection : .none
            secondaryTitle = nil
        case .preparing:
            detail = "Keep Checkpoint open while your first checkpoint is prepared."
            detailTone = .standard
            primaryTitle = "Turning on protection"
            primarySystemImage = "checkmark.shield"
            isPrimaryLoading = true
            isPrimaryEnabled = false
            primaryAction = .none
            secondaryTitle = nil
        case .failed:
            detail = nil
            detailTone = .standard
            primaryTitle = hasSelection ? "Try again" : "Choose apps"
            primarySystemImage = hasSelection ? "arrow.clockwise" : "slider.horizontal.3"
            isPrimaryLoading = false
            isPrimaryEnabled = true
            primaryAction = hasSelection ? .startProtection : .editSelection
            secondaryTitle = "Continue without protection"
        case .protected:
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

    var style: FirstRunProtectionMotionStyle {
        reduceMotion ? .identity : .choreographed
    }

    var animation: Animation? {
        CheckpointMotion.animation(CheckpointMotion.reveal, reduceMotion: reduceMotion)
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
}

struct RestrictedAppsView: View {
    let screenTime: ScreenTimeController
    let presentationMode: RestrictedAppsPresentationMode
    private let reduceMotionOverride: Bool?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var firstRunFlow: FirstRunProtectionFlow
    @State private var successFeedbackSequence = 0
    @State private var errorFeedbackSequence = 0

    init(screenTime: ScreenTimeController) {
        self.screenTime = screenTime
        presentationMode = .management
        reduceMotionOverride = nil
        _firstRunFlow = State(
            initialValue: FirstRunProtectionFlow(
                startProtection: {
                    .failed(message: "First-run protection setup is unavailable.")
                },
                finishProtectedSetup: {},
                continueWithoutProtection: {}
            )
        )
    }

    init(
        screenTime: ScreenTimeController,
        onStartProtection: @escaping @MainActor () async -> FirstRunProtectionStartResult,
        onFinishProtectedSetup: @escaping @MainActor () -> Void,
        onContinueWithoutProtection: @escaping @MainActor () -> Void,
        onProtectionUnavailable: @escaping @MainActor () -> Void = {},
        initialPhase: FirstRunProtectionPhase = .selecting,
        reduceMotionOverride: Bool? = nil
    ) {
        self.screenTime = screenTime
        presentationMode = .firstRun
        self.reduceMotionOverride = reduceMotionOverride
        _firstRunFlow = State(
            initialValue: FirstRunProtectionFlow(
                initialPhase: initialPhase,
                startProtection: onStartProtection,
                finishProtectedSetup: onFinishProtectedSetup,
                continueWithoutProtection: onContinueWithoutProtection,
                protectionUnavailable: onProtectionUnavailable
            )
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
                            .foregroundStyle(CheckpointTheme.teal)
                        }
                    }
                }
        }
        .sensoryFeedback(.success, trigger: successFeedbackSequence)
        .sensoryFeedback(.error, trigger: errorFeedbackSequence)
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
        .task {
            if screenTime.setupState == .notStarted || screenTime.setupState == .failed {
                await screenTime.requestAuthorization()
            }
            reconcileLiveProtectionState()
        }
        .onChange(of: liveProtectionState) { _, state in
            guard !state.isValid else { return }
            reconcileLiveProtectionState()
        }
    }

    @ViewBuilder
    private var content: some View {
        if presentationMode == .firstRun,
           FirstRunProtectionStatusPresentation(phase: firstRunFlow.phase) != nil {
            FirstRunProtectionStatusView(
                phase: firstRunFlow.phase,
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
                presentationMode: presentationMode
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
            let selectionSummary = screenTime.restrictedAppsSummary
            Task { @MainActor in
                await firstRunFlow.start(selectionSummary: selectionSummary)
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

    private func reconcileLiveProtectionState() {
        guard presentationMode == .firstRun,
              !liveProtectionState.isValid else {
            return
        }
        _ = firstRunFlow.protectionDidBecomeUnavailable(
            message: "Protection turned off before setup finished. Try turning it on again."
        )
    }
}

struct FirstRunProtectionActionBar: View {
    let presentation: FirstRunProtectionActionPresentation
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            if let detail = presentation.detail {
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

struct FirstRunProtectionStatusView: View {
    let phase: FirstRunProtectionPhase
    let reduceMotion: Bool
    var hasSelection = true
    let editSelection: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                        compact: usesTightSpacing
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
        .opacity(reduceMotion || isRevealed ? 1 : 0)
        .scaleEffect(
            reduceMotion || isRevealed ? 1 : 0.98,
            anchor: .top
        )
        .onAppear {
            revealStatus()
        }
        .task(id: phase) {
            let destination = focusDestination
            let tone = presentation.tone
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedDestination = destination
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
            .symbolEffectsRemoved(reduceMotion || presentation.tone != .success)
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
        let motion = FirstRunProtectionMotionPolicy(reduceMotion: reduceMotion)
        withAnimation(motion.animation) {
            isRevealed = true
        }
    }
}

struct FirstRunAppSelectionHeader: View {
    let selectionSummary: String
    let categorySelectionDetail: String?
    let errorMessage: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CheckpointSetupMark(
                stage: "Choose apps",
                step: 3,
                compact: dynamicTypeSize.isAccessibilitySize
            )

            Text("Choose your pause points.")
                .font(dynamicTypeSize.isAccessibilitySize ? .title3.bold() : .title2.bold())
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Opening one of these apps will start a short, goal-based checkpoint before a timed break.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

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
}

#if os(iOS) && canImport(FamilyControls)
private struct FamilyPickerContent: View {
    let screenTime: ScreenTimeController
    let presentationMode: RestrictedAppsPresentationMode

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if presentationMode == .firstRun {
                    FirstRunAppSelectionHeader(
                        selectionSummary: selectionSummary,
                        categorySelectionDetail: screenTime.selection.categoryTokens.isEmpty
                            ? nil
                            : categorySelectionDetail,
                        errorMessage: screenTime.userFacingErrorMessage
                    )
                } else {
                    Text("Choose what Checkpoint should protect.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(selectionSummary, systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if !screenTime.selection.categoryTokens.isEmpty {
                        Text(categorySelectionDetail)
                            .font(.caption)
                            .foregroundStyle(CheckpointTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage = screenTime.userFacingErrorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .background(CheckpointTheme.panel)

            FamilyActivityPicker(selection: selectionBinding)
        }
    }

    private var selectionBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { screenTime.selection },
            set: { _ = screenTime.updateSelection($0) }
        )
    }

    private var selectionSummary: String {
        let parts = [
            selectionCountText(screenTime.selection.applicationTokens.count, singular: "app", plural: "apps"),
            selectionCountText(screenTime.selection.webDomainTokens.count, singular: "site", plural: "sites")
        ].compactMap { $0 }

        if parts.isEmpty, !screenTime.selection.categoryTokens.isEmpty {
            return "No individual apps selected yet"
        }
        guard !parts.isEmpty else { return "Nothing selected yet" }
        return parts.joined(separator: ", ") + " selected"
    }

    private var categorySelectionDetail: String {
        if screenTime.selection.applicationTokens.isEmpty {
            return "Keep at least one app selected inside the category so Checkpoint has something to protect."
        }
        return "Category shortcuts add their apps to this list. Your individual app changes take precedence."
    }

    private func selectionCountText(
        _ count: Int,
        singular: String,
        plural: String
    ) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? singular : plural)"
    }
}
#endif
