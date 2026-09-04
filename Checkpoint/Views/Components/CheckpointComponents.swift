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

enum CheckpointPalette {
    static let ink = CheckpointColorComponents(hex: 0x0F241F)
    static let paper = CheckpointColorComponents(hex: 0xF2F5ED)
    static let mint = CheckpointColorComponents(hex: 0x7DE8C7)
    static let heroText = CheckpointColorComponents(hex: 0xF0FAF5)
    static let heroMuted = CheckpointColorComponents(hex: 0xA8BFB5)
    static let heroInfo = CheckpointColorComponents(hex: 0x86BDEB)
    static let heroWarning = CheckpointColorComponents(hex: 0xF0C36B)
    static let heroDanger = CheckpointColorComponents(hex: 0xFF9587)
    static let heroTrack = CheckpointColorComponents(hex: 0x60776E)
    static let heroDivider = CheckpointColorComponents(hex: 0xFFFFFF, alpha: 0.11)
    static let heroSubtleFill = CheckpointColorComponents(hex: 0xFFFFFF, alpha: 0.07)
    static let selectionText = CheckpointColorComponents(hex: 0xFFFFFF)
    static let selectionCountFill = CheckpointColorComponents(hex: 0x0F241F, alpha: 0.24)

    static let actionTeal = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x1C4F47),
        dark: CheckpointColorComponents(hex: 0x2C7465)
    )
    static let actionDeep = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x0F241F),
        dark: CheckpointColorComponents(hex: 0x245E53)
    )
    static let actionBorder = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0xFFFFFF, alpha: 0.12),
        dark: CheckpointColorComponents(hex: 0x72D0B6, alpha: 0.55)
    )
    static let destructiveFill = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x9C4A3D),
        dark: CheckpointColorComponents(hex: 0xA94F45)
    )
    static let selectionFill = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x0F241F),
        dark: CheckpointColorComponents(hex: 0x328170)
    )
    static let heroBorder = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0xFFFFFF, alpha: 0),
        dark: CheckpointColorComponents(hex: 0x40534C)
    )
    static let shadowCard = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x0F241F, alpha: 0.055),
        dark: CheckpointColorComponents(hex: 0x000000, alpha: 0.25)
    )
    static let shadowElevated = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x0F241F, alpha: 0.14),
        dark: CheckpointColorComponents(hex: 0x000000, alpha: 0.38)
    )

    static let backgroundBase = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0xF2F5ED),
        dark: CheckpointColorComponents(hex: 0x091512)
    )
    static let backgroundGreen = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0xE6F0E8),
        dark: CheckpointColorComponents(hex: 0x10241F)
    )
    static let backgroundWarm = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0xF0EADB),
        dark: CheckpointColorComponents(hex: 0x211E18)
    )
    static let panel = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0xFCFAF2),
        dark: CheckpointColorComponents(hex: 0x14211E)
    )
    static let panelRaised = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0xE6EBE0),
        dark: CheckpointColorComponents(hex: 0x1C2C27)
    )
    static let hairline = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0xC9D0C7),
        dark: CheckpointColorComponents(hex: 0x40534C)
    )
    static let controlStroke = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x7C8A82),
        dark: CheckpointColorComponents(hex: 0x60786D)
    )
    static let text = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x0F241F),
        dark: CheckpointColorComponents(hex: 0xECF3EF)
    )
    static let muted = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x596961),
        dark: CheckpointColorComponents(hex: 0xA8B7B0)
    )
    static let teal = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x1C4F47),
        dark: CheckpointColorComponents(hex: 0x72D0B6)
    )
    static let blue = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x294F78),
        dark: CheckpointColorComponents(hex: 0x86BDEB)
    )
    static let amber = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x76500F),
        dark: CheckpointColorComponents(hex: 0xF0C36B)
    )
    static let coral = CheckpointAdaptiveColor(
        light: CheckpointColorComponents(hex: 0x904034),
        dark: CheckpointColorComponents(hex: 0xFF9587)
    )
}

enum CheckpointTheme {
    static var ink: Color { CheckpointPalette.ink.color }
    static var paper: Color { CheckpointPalette.paper.color }
    static var actionTeal: Color { CheckpointPalette.actionTeal.color }
    static var actionDeep: Color { CheckpointPalette.actionDeep.color }
    static var actionBorder: Color { CheckpointPalette.actionBorder.color }
    static var destructiveFill: Color { CheckpointPalette.destructiveFill.color }
    static var selectionFill: Color { CheckpointPalette.selectionFill.color }
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
    static var teal: Color { CheckpointPalette.teal.color }
    static var blue: Color { CheckpointPalette.blue.color }
    static var amber: Color { CheckpointPalette.amber.color }
    static var coral: Color { CheckpointPalette.coral.color }
    static var mint: Color { CheckpointPalette.mint.color }

    static let compactCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 18

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                CheckpointPalette.backgroundBase.color,
                CheckpointPalette.backgroundGreen.color,
                CheckpointPalette.backgroundWarm.color
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
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
        .font(.caption.weight(.bold))
        .foregroundStyle(CheckpointTheme.teal)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 11)
        .frame(minHeight: 44)
        .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            } else {
                Text(stage.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)

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

struct CheckpointPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                CheckpointMotion.animation(CheckpointMotion.press, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

struct PrimaryActionButton: View {
    var title: String
    var systemImage: String
    var isLoading: Bool
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        systemImage: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        actionIcon
                        actionTitle
                    }
                } else {
                    HStack(spacing: 8) {
                        actionIcon
                        actionTitle
                    }
                }
            }
                .foregroundStyle(CheckpointTheme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 18 : 15)
                .background(
                    LinearGradient(
                        colors: [CheckpointTheme.actionTeal, CheckpointTheme.actionDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                        .stroke(CheckpointTheme.actionBorder, lineWidth: 1)
                }
                .shadow(color: CheckpointTheme.shadowElevated, radius: 10, y: 5)
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
                    .tint(CheckpointTheme.paper)
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
            .font(.headline)
            .multilineTextAlignment(.center)
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

struct SectionPanel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)
                    .accessibilityAddTraits(.isHeader)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
                .fill(CheckpointTheme.panel.opacity(0.96))
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        )
        .shadow(color: CheckpointTheme.shadowCard, radius: 12, x: 0, y: 5)
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
        glowColor: Color,
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
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(CheckpointTheme.ink)
                    .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(glowColor.opacity(glowOpacity))
                            .frame(width: glowDiameter, height: glowDiameter)
                            .blur(radius: glowBlurRadius)
                            .offset(glowOffset)
                            .allowsHitTesting(false)
                    }
            )
            .shadow(color: CheckpointTheme.shadowElevated, radius: 16, y: 8)
    }
}

struct StatusBadge: View {
    var text: String
    var tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                tint.opacity(0.14),
                in: RoundedRectangle(
                    cornerRadius: dynamicTypeSize.isAccessibilitySize
                        ? CheckpointTheme.compactCornerRadius
                        : 100,
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
