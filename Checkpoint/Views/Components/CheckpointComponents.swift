import SwiftUI
import UIKit

struct CheckpointColorComponents: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

struct CheckpointAdaptiveColor: Equatable, Sendable {
    let light: CheckpointColorComponents
    let dark: CheckpointColorComponents

    var color: Color {
        Color(
            uiColor: UIColor { traits in
                (traits.userInterfaceStyle == .dark ? dark : light).uiColor
            }
        )
    }
}

/// Saddle & Ink: warm surfaces and restrained brand color, with independent status roles.
/// Fixed hero colors remain paired with fixed espresso; adaptive controls use actionText.
enum CheckpointPalette {
    static let ink = CheckpointColorComponents(hex: 0x29231E)
    static let paper = CheckpointColorComponents(hex: 0xFAF7F0)
    static let mint = CheckpointColorComponents(hex: 0xA9BA97)
    static let heroText = CheckpointColorComponents(hex: 0xEDE3D4)
    static let heroMuted = CheckpointColorComponents(hex: 0xB7A995)
    static let heroInfo = CheckpointColorComponents(hex: 0xA9BACA)
    static let heroWarning = CheckpointColorComponents(hex: 0xD7B575)
    static let heroDanger = CheckpointColorComponents(hex: 0xE6A18F)
    static let heroTrack = CheckpointColorComponents(hex: 0x8E7D6A)
    static let heroDivider = CheckpointColorComponents(hex: 0xEDE3D4, alpha: 0.16)
    static let heroSubtleFill = CheckpointColorComponents(hex: 0xEDE3D4, alpha: 0.07)
    static let selectionCountFill = CheckpointColorComponents(hex: 0x29231E, alpha: 0.10)

    static let backgroundBase = adaptive(0xF2EBDD, 0x191714)
    static let panel = adaptive(0xFAF7F0, 0x27221D)
    static let panelRaised = adaptive(0xF0E7D9, 0x332B23)
    static let hairline = adaptive(0xD8CDBD, 0x493F34)
    static let controlStroke = adaptive(0x8A7B68, 0x8E7D6A)
    static let text = adaptive(0x29231E, 0xEDE3D4)
    static let muted = adaptive(0x71675A, 0xB7A995)
    static let accent = adaptive(0x805A3B, 0xCBA678)
    static let actionFill = adaptive(0x29231E, 0xE3D2BA)
    static let actionText = adaptive(0xFAF7F0, 0x29231E)
    static let selectionFill = adaptive(0xE3D2BA, 0x393027)
    static let selectionText = text
    static let selectionBorder = accent
    static let destructiveFill = adaptive(0x893E32, 0x9C493D)
    static let success = adaptive(0x486147, 0xA9BA97)
    static let blue = adaptive(0x435A6B, 0xA9BACA)
    static let amber = adaptive(0x70501E, 0xD7B575)
    static let coral = adaptive(0x893E32, 0xE6A18F)

    // Compatibility names for semantic progress and older view call sites.
    static let teal = success
    static let actionTeal = actionFill
    static let actionDeep = actionFill
    static let actionBorder = actionFill
    static let backgroundGreen = backgroundBase
    static let backgroundWarm = backgroundBase
    static let heroBorder = adaptive(0x493F34, 0x493F34)
    static let shadowCard = CheckpointAdaptiveColor(
        light: .init(hex: 0x29231E, alpha: 0.03), dark: .init(hex: 0, alpha: 0.12)
    )
    static let shadowElevated = CheckpointAdaptiveColor(
        light: .init(hex: 0x29231E, alpha: 0.08), dark: .init(hex: 0, alpha: 0.20)
    )

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> CheckpointAdaptiveColor {
        CheckpointAdaptiveColor(light: .init(hex: light), dark: .init(hex: dark))
    }
}

enum CheckpointTheme {
    static var ink: Color { CheckpointPalette.ink.color }
    static var paper: Color { CheckpointPalette.paper.color }
    static var accent: Color { CheckpointPalette.accent.color }
    static var success: Color { CheckpointPalette.success.color }
    static var actionFill: Color { CheckpointPalette.actionFill.color }
    static var actionText: Color { CheckpointPalette.actionText.color }
    static var actionTeal: Color { actionFill }
    static var actionDeep: Color { actionFill }
    static var actionBorder: Color { CheckpointPalette.actionBorder.color }
    static var destructiveFill: Color { CheckpointPalette.destructiveFill.color }
    static var selectionFill: Color { CheckpointPalette.selectionFill.color }
    static var selectionBorder: Color { CheckpointPalette.selectionBorder.color }
    static var heroText: Color { CheckpointPalette.heroText.color }
    static var heroMuted: Color { CheckpointPalette.heroMuted.color }
    static var heroSuccess: Color { CheckpointPalette.mint.color }
    static var heroInfo: Color { CheckpointPalette.heroInfo.color }
    static var heroWarning: Color { CheckpointPalette.heroWarning.color }
    static var heroDanger: Color { CheckpointPalette.heroDanger.color }
    static var heroTrack: Color { CheckpointPalette.heroTrack.color }
    static var heroDivider: Color { CheckpointPalette.heroDivider.color }
    static var heroSubtleFill: Color { CheckpointPalette.heroSubtleFill.color }
    static var selectionText: Color { CheckpointPalette.selectionText.color }
    static var selectionCountFill: Color { CheckpointPalette.selectionCountFill.color }
    static var heroBorder: Color { CheckpointPalette.heroBorder.color }
    static var shadowCard: Color { CheckpointPalette.shadowCard.color }
    static var shadowElevated: Color { CheckpointPalette.shadowElevated.color }
    static var panel: Color { CheckpointPalette.panel.color }
    static var panelRaised: Color { CheckpointPalette.panelRaised.color }
    static var hairline: Color { CheckpointPalette.hairline.color }
    static var controlStroke: Color { CheckpointPalette.controlStroke.color }
    static var text: Color { CheckpointPalette.text.color }
    static var muted: Color { CheckpointPalette.muted.color }
    static var teal: Color { success }
    static var blue: Color { CheckpointPalette.blue.color }
    static var amber: Color { CheckpointPalette.amber.color }
    static var coral: Color { CheckpointPalette.coral.color }
    static var mint: Color { CheckpointPalette.mint.color }

    static let compactCornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 12
    static var background: Color { CheckpointPalette.backgroundBase.color }
}

/// Native text styles retain Dynamic Type. Serif is reserved for editorial hierarchy;
/// questions, answers, form fields, and controls continue using the system sans face.
enum CheckpointTypography {
    static let screenTitle: Font = .system(.largeTitle, design: .serif)
    static let goalTitle: Font = .system(.title, design: .serif)
    static let sectionTitle: Font = .system(.title2, design: .serif)
    static let metric: Font = .system(.largeTitle, design: .serif)
    static let eyebrow: Font = .caption2.weight(.medium)
}

enum CheckpointMotion {
    static let press = Animation.snappy(duration: 0.16, extraBounce: 0)
    static let change = Animation.smooth(duration: 0.28)
    static let reveal = Animation.smooth(duration: 0.38)

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

struct GoalSelectionAction: Sendable {
    private let action: @MainActor @Sendable (Goal.ID) -> Void

    init(_ action: @escaping @MainActor @Sendable (Goal.ID) -> Void) {
        self.action = action
    }

    @MainActor
    func callAsFunction(_ goalID: Goal.ID) {
        action(goalID)
    }
}

private struct GoalSelectionActionKey: EnvironmentKey {
    static let defaultValue = GoalSelectionAction { _ in }
}

extension EnvironmentValues {
    var checkpointGoalSelection: GoalSelectionAction {
        get { self[GoalSelectionActionKey.self] }
        set { self[GoalSelectionActionKey.self] = newValue }
    }
}

enum GoalSwitchMenuOptionState: Equatable {
    case current
    case ready
    case preparing(selectableCount: Int, requiredCount: Int)
    case notReady(selectableCount: Int, requiredCount: Int)
    case locked
    case unavailable
}

struct GoalSwitchMenuOptionPresentation: Identifiable, Equatable {
    let id: Goal.ID
    let title: String
    let state: GoalSwitchMenuOptionState

    var menuTitle: String {
        switch state {
        case .current:
            title
        case .ready:
            "\(title) · Ready"
        case .preparing:
            "\(title) · Preparing"
        case .notReady:
            "\(title) · Not ready"
        case .locked:
            "\(title) · Pro"
        case .unavailable:
            "\(title) · Unavailable"
        }
    }

    var systemImage: String {
        switch state {
        case .current:
            "checkmark.circle.fill"
        case .ready:
            "circle"
        case .preparing:
            "hourglass"
        case .notReady:
            "exclamationmark.circle"
        case .locked:
            "lock.fill"
        case .unavailable:
            "questionmark.circle"
        }
    }

    var isCurrent: Bool {
        state == .current
    }

    var accessibilityValue: String {
        switch state {
        case .current:
            "Current goal"
        case .ready:
            "Checkpoint ready"
        case let .preparing(selectableCount, requiredCount):
            "Preparing, \(selectableCount) of \(requiredCount) questions ready"
        case let .notReady(selectableCount, requiredCount):
            "Not ready, \(selectableCount) of \(requiredCount) questions ready"
        case .locked:
            "Requires Pro"
        case .unavailable:
            "Unavailable"
        }
    }
}

@MainActor
struct GoalSwitchMenuPresentation: Equatable {
    let options: [GoalSwitchMenuOptionPresentation]

    init(
        store: CheckpointStore,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let goals = store.availableGoalProfiles
        let resolver = GoalDisplayTitleResolver(
            goals: goals,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        options = goals.map { goal in
            let state: GoalSwitchMenuOptionState
            switch store.prepareGoalActivation(to: goal.id) {
            case let .eligible(plan):
                switch plan.readiness {
                case .ready:
                    state = .ready
                case let .preparing(selectableCount, requiredCount):
                    state = .preparing(
                        selectableCount: selectableCount,
                        requiredCount: requiredCount
                    )
                case let .incomplete(selectableCount, requiredCount):
                    state = .notReady(
                        selectableCount: selectableCount,
                        requiredCount: requiredCount
                    )
                }
            case .alreadyActive:
                state = .current
            case .membershipRequired:
                state = .locked
            case .targetNotFound:
                state = .unavailable
            }

            return GoalSwitchMenuOptionPresentation(
                id: goal.id,
                title: resolver.title(for: goal),
                state: state
            )
        }
    }
}

struct GoalSwitchConfirmationPresentation: Equatable {
    let sourceTitle: String?
    let targetTitle: String
    let title: String
    let message: String
    let confirmationButtonTitle: String
    let cancelButtonTitle = "Keep current goal"
    let readinessText: String

    init(
        confirmation: GoalSwitchConfirmation,
        goals: [Goal],
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let resolver = GoalDisplayTitleResolver(
            goals: goals,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        sourceTitle = confirmation.sourceGoalID.map {
            resolver.title(for: $0, fallback: confirmation.sourceTitle ?? "Current goal")
        }
        targetTitle = resolver.title(
            for: confirmation.targetGoalID,
            fallback: confirmation.targetTitle
        )

        let selectableCount = confirmation.readiness.selectableCount
        let requiredCount = confirmation.readiness.requiredCount
        let questionNoun = requiredCount == 1 ? "question" : "questions"
        readinessText = "\(selectableCount) of \(requiredCount) \(questionNoun) ready"

        switch confirmation.impact {
        case .turnsOffImmediately:
            title = "Switch goal and turn off protection?"
            message = "\(targetTitle) has \(readinessText). Switching now turns off app protection. Start protection again after a full checkpoint is ready."
            confirmationButtonTitle = "Switch and turn off"
        case .preventsRelockAfterBreak:
            title = "Switch goal before this break ends?"
            message = "Your break will continue, but protection won't return when it ends because \(targetTitle) has only \(readinessText). Start protection again after a full checkpoint is ready."
            confirmationButtonTitle = "Switch goal"
        }
    }
}

enum GoalIdentityMotionStyle: Equatable {
    case crossfade
    case identity
}

struct GoalIdentityMotionPolicy {
    let style: GoalIdentityMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .crossfade
    }

    var animation: Animation? {
        style == .crossfade ? CheckpointMotion.change : nil
    }

    var transition: AnyTransition {
        switch style {
        case .crossfade:
            .asymmetric(
                insertion: .opacity.combined(
                    with: .scale(scale: 0.99, anchor: .top)
                ),
                removal: .opacity
            )
        case .identity:
            .identity
        }
    }
}

struct GoalSwitcherCapsuleLabel: View {
    var title = "Current goal"

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(CheckpointTheme.accent)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 11)
        .frame(minHeight: 44)
        .background(CheckpointTheme.accent.opacity(0.10), in: Capsule())
        .contentShape(Capsule())
    }
}

enum PrimaryActionIconState: Equatable {
    case loading
    case symbol(String)

    init(systemImage: String, isLoading: Bool) {
        self = isLoading ? .loading : .symbol(systemImage)
    }
}

enum PrimaryActionIconMotionStyle: Equatable {
    case animated
    case identity
}

struct PrimaryActionIconMotionPolicy: Equatable {
    let style: PrimaryActionIconMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var animation: Animation? {
        style == .animated ? CheckpointMotion.change : nil
    }

    var transition: AnyTransition {
        style == .animated
            ? .opacity.combined(with: .scale(scale: 0.94))
            : .identity
    }
}

struct CheckpointSetupMark: View {
    let stage: String
    var step: Int?
    var stepCount = 3
    var systemImage = "checkmark.shield.fill"
    var isWorking = false
    var compact = false
    var symbolEffectSequence = 0
    var reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    @ViewBuilder
    var body: some View {
        if compact {
            HStack(spacing: 10) {
                markIcon
                markCopy
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    markIcon
                    markCopy
                }

                VStack(alignment: .leading, spacing: 10) {
                    markIcon
                    markCopy
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
        }
    }

    private var markIcon: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: compact ? 19 : 24, weight: .semibold))
            .foregroundStyle(CheckpointTheme.mint)
            .frame(width: compact ? 40 : 52, height: compact ? 40 : 52)
            .background(
                CheckpointTheme.ink,
                in: RoundedRectangle(
                    cornerRadius: compact ? 13 : 16,
                    style: .continuous
                )
            )
            .symbolEffect(
                .pulse,
                options: .repeating,
                isActive: isWorking && !reduceMotion
            )
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(
                .bounce,
                options: .nonRepeating,
                value: symbolEffectSequence
            )
            .symbolEffectsRemoved(reduceMotion)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var markCopy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CHECKPOINT")
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(CheckpointTheme.text)

            if compact, let step {
                Text("STEP \(step) OF \(stepCount) · \(stage.uppercased())")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)
                    .contentTransition(.opacity)
            } else {
                Text(stage.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)
                    .contentTransition(.opacity)

                if let step {
                    Text("STEP \(step) OF \(stepCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accessibilityDescription: String {
        guard let step else { return "Checkpoint setup, \(stage)" }
        return "Checkpoint setup, step \(step) of \(stepCount), \(stage)"
    }
}

enum CheckpointPressRole: Equatable, Sendable {
    case control
    case surface
}

enum CheckpointPressMotionStyle: Equatable, Sendable {
    case spatial
    case tonalOnly
}

struct CheckpointPressVisualEffect: Equatable, Sendable {
    let scale: CGFloat
    let offsetY: CGFloat
    let opacity: Double
}

struct CheckpointPressMotionPolicy: Equatable, Sendable {
    let role: CheckpointPressRole
    let style: CheckpointPressMotionStyle

    init(
        role: CheckpointPressRole = .control,
        reduceMotion: Bool,
        voiceOverEnabled: Bool,
        switchControlEnabled: Bool
    ) {
        self.role = role
        style = reduceMotion || voiceOverEnabled || switchControlEnabled
            ? .tonalOnly
            : .spatial
    }

    var animation: Animation? {
        style == .spatial ? CheckpointMotion.press : nil
    }

    func visualEffect(isPressed: Bool) -> CheckpointPressVisualEffect {
        guard isPressed else {
            return CheckpointPressVisualEffect(scale: 1, offsetY: 0, opacity: 1)
        }

        switch (style, role) {
        case (.spatial, .control):
            return CheckpointPressVisualEffect(scale: 0.985, offsetY: 0, opacity: 0.88)
        case (.spatial, .surface):
            return CheckpointPressVisualEffect(scale: 0.992, offsetY: 1, opacity: 0.92)
        case (.tonalOnly, .control):
            return CheckpointPressVisualEffect(scale: 1, offsetY: 0, opacity: 0.88)
        case (.tonalOnly, .surface):
            return CheckpointPressVisualEffect(scale: 1, offsetY: 0, opacity: 0.92)
        }
    }
}

struct CheckpointPressEffect: ViewModifier {
    let isPressed: Bool
    let policy: CheckpointPressMotionPolicy

    func body(content: Content) -> some View {
        let effect = policy.visualEffect(isPressed: isPressed)

        content
            .scaleEffect(effect.scale)
            .offset(y: effect.offsetY)
            .opacity(effect.opacity)
            .animation(policy.animation, value: isPressed)
    }
}

struct CheckpointPressButtonStyle: ButtonStyle {
    var role: CheckpointPressRole = .control

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(
            CheckpointPressEffect(
                isPressed: configuration.isPressed,
                policy: CheckpointPressMotionPolicy(
                    role: role,
                    reduceMotion: reduceMotion,
                    voiceOverEnabled: voiceOverEnabled,
                    switchControlEnabled: switchControlEnabled
                )
            )
        )
    }
}

struct PrimaryActionButton: View {
    var title: String
    var systemImage: String
    var isLoading: Bool
    var compact: Bool
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        systemImage: String,
        isLoading: Bool = false,
        compact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        actionTitle
                        actionIcon
                    }
                } else {
                    HStack(spacing: 12) {
                        actionTitle
                        Spacer(minLength: 8)
                        actionIcon
                    }
                }
            }
                .foregroundStyle(CheckpointTheme.actionText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 18 : (compact ? 10 : 15))
                .frame(minHeight: compact ? 50 : 44)
                .background(
                    CheckpointTheme.actionFill,
                    in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                        .stroke(CheckpointTheme.actionBorder, lineWidth: 1)
                }
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .opacity(isEnabled || isLoading ? 1 : 0.58)
        .accessibilityLabel(isLoading ? "\(title), in progress" : title)
    }

    private var actionIcon: some View {
        ZStack {
            switch actionIconState {
            case .loading:
                ProgressView()
                    .tint(CheckpointTheme.actionText)
                    .transition(actionIconMotionPolicy.transition)
            case let .symbol(systemImage):
                Image(systemName: systemImage)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 24 : 17, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffectsRemoved(reduceMotion)
                    .transition(actionIconMotionPolicy.transition)
            }
        }
        .frame(
            width: dynamicTypeSize.isAccessibilitySize ? 28 : 20,
            height: dynamicTypeSize.isAccessibilitySize ? 28 : 20
        )
        .animation(actionIconMotionPolicy.animation, value: actionIconState)
        .accessibilityHidden(true)
    }

    private var actionIconState: PrimaryActionIconState {
        PrimaryActionIconState(systemImage: systemImage, isLoading: isLoading)
    }

    private var actionIconMotionPolicy: PrimaryActionIconMotionPolicy {
        PrimaryActionIconMotionPolicy(reduceMotion: reduceMotion)
    }

    private var actionTitle: some View {
        Text(title)
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.leading)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SecondaryActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    CheckpointTheme.panelRaised.opacity(0.82),
                    in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                        .stroke(CheckpointTheme.controlStroke, lineWidth: 1)
                }
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .opacity(isEnabled ? 1 : 0.58)
    }
}

enum SectionPanelStyle {
    case surface
    case editorial
}

struct SectionPanel<Content: View>: View {
    var title: String?
    var contentPadding: CGFloat
    var style: SectionPanelStyle
    @ViewBuilder var content: Content

    init(
        _ title: String? = nil,
        contentPadding: CGFloat = 16,
        style: SectionPanelStyle = .surface,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.contentPadding = contentPadding
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CheckpointTheme.muted)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(.vertical, contentPadding)
        .padding(.horizontal, style == .surface ? contentPadding : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if style == .surface {
                RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
                    .fill(CheckpointTheme.panel)
            }
        }
        .overlay(alignment: .top) {
            if style == .editorial {
                Rectangle().fill(CheckpointTheme.hairline).frame(height: 1)
            }
        }
    }
}

enum StudyFocusCardStyle: Equatable {
    case compact
    case panel
}

struct StudyFocusCard: View {
    let state: StudyFocusState
    let style: StudyFocusCardStyle
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if state.isRecommendation {
                Button(action: action) {
                    surface
                }
                .buttonStyle(CheckpointPressButtonStyle(role: .surface))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Next Focus. \(state.title). \(state.detail)")
                .accessibilityHint("Shows this skill's answer breakdown and latest signal.")
            } else {
                surface
                    .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var surface: some View {
        switch style {
        case .compact:
            cardContent
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    CheckpointTheme.panelRaised.opacity(0.62),
                    in: RoundedRectangle(
                        cornerRadius: CheckpointTheme.cardCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: CheckpointTheme.cardCornerRadius,
                        style: .continuous
                    )
                    .stroke(accent.opacity(0.16), lineWidth: 1)
                }
        case .panel:
            SectionPanel(style: .editorial) {
                cardContent
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                focusIcon

                focusCopy

                if state.isRecommendation {
                    accessoryLabel
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    focusIcon
                    focusCopy
                    Spacer(minLength: 4)

                    if state.isRecommendation {
                        accessoryLabel
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        focusIcon
                        focusCopy
                    }

                    if state.isRecommendation {
                        accessoryLabel
                    }
                }
            }
        }
    }

    private var focusIcon: some View {
        Image(systemName: state.systemImage)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(accent)
            .frame(width: 44, height: 44)
            .background(
                accent.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var focusCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NEXT FOCUS")
                .font(CheckpointTypography.eyebrow)
                .tracking(0.85)
                .foregroundStyle(accent)
                .accessibilityAddTraits(.isHeader)

            Text(state.title)
                .font(CheckpointTypography.sectionTitle)
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(state.detail)
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessoryLabel: some View {
        HStack(spacing: 6) {
            Text("View skill")
                .font(.caption.weight(.bold))
                .fixedSize(horizontal: true, vertical: true)

            accessoryIcon
        }
        .foregroundStyle(CheckpointTheme.accent)
        .frame(minHeight: 44)
        .accessibilityHidden(true)
    }

    private var accessoryIcon: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.accent)
            .accessibilityHidden(true)
    }

    private var accent: Color {
        state.isRecommendation ? CheckpointTheme.accent : CheckpointTheme.teal
    }
}

struct CheckpointHeroSurface<Content: View>: View {
    var glowColor: Color
    var glowOpacity: Double = 0.09
    var glowDiameter: CGFloat = 150
    var glowBlurRadius: CGFloat = 11
    var glowOffset = CGSize(width: 64, height: -82)
    var contentPadding: CGFloat = 18
    @ViewBuilder var content: Content

    init(
        glowColor: Color = .clear,
        glowOpacity: Double = 0.09,
        glowDiameter: CGFloat = 150,
        glowBlurRadius: CGFloat = 11,
        glowOffset: CGSize = CGSize(width: 64, height: -82),
        contentPadding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.glowColor = glowColor
        self.glowOpacity = glowOpacity
        self.glowDiameter = glowDiameter
        self.glowBlurRadius = glowBlurRadius
        self.glowOffset = glowOffset
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
                    .fill(CheckpointTheme.ink)
                    .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
            )
    }
}

struct CheckpointMascotMark: View {
    static let assetName = "ShieldMascot"
    static let image = UIImage(
        named: assetName,
        in: .main,
        compatibleWith: nil
    )

    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        resolvedImage
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CheckpointTheme.heroDivider, lineWidth: 1)
            }
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var resolvedImage: Image {
        if let image = Self.image {
            Image(uiImage: image)
        } else {
            Image(systemName: "checkmark.shield.fill")
        }
    }
}

struct StatusBadge: View {
    var text: String
    var tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                tint.opacity(0.07),
                in: RoundedRectangle(
                    cornerRadius: CheckpointTheme.compactCornerRadius,
                    style: .continuous
                )
            )
    }
}

extension View {
    func checkpointScreenBackground() -> some View {
        background(CheckpointTheme.background.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }
}
