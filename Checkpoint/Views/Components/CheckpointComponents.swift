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
        Group {
            if isLoading {
                ProgressView()
                    .tint(CheckpointTheme.paper)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 24 : 17, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffectsRemoved(reduceMotion)
            }
        }
        .frame(
            width: dynamicTypeSize.isAccessibilitySize ? 28 : 20,
            height: dynamicTypeSize.isAccessibilitySize ? 28 : 20
        )
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

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

extension View {
    func checkpointScreenBackground() -> some View {
        background(CheckpointTheme.background.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }
}
