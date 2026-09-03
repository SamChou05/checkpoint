import SwiftUI

enum CheckpointTheme {
    static let ink = Color(red: 0.06, green: 0.14, blue: 0.12)
    static let paper = Color(red: 0.95, green: 0.96, blue: 0.93)
    static let panel = Color(red: 0.99, green: 0.98, blue: 0.95)
    static let panelRaised = Color(red: 0.90, green: 0.92, blue: 0.88)
    static let hairline = Color(red: 0.60, green: 0.65, blue: 0.59).opacity(0.38)
    static let text = ink
    static let muted = Color(red: 0.35, green: 0.41, blue: 0.38)
    static let teal = Color(red: 0.11, green: 0.31, blue: 0.28)
    static let blue = Color(red: 0.16, green: 0.31, blue: 0.47)
    static let amber = Color(red: 0.55, green: 0.40, blue: 0.15)
    static let coral = Color(red: 0.61, green: 0.29, blue: 0.24)
    static let mint = Color(red: 0.49, green: 0.91, blue: 0.78)

    static let compactCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 18

    static let background = LinearGradient(
        colors: [
            paper,
            Color(red: 0.90, green: 0.94, blue: 0.91),
            Color(red: 0.94, green: 0.92, blue: 0.86)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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
        Image(systemName: "checkmark.shield.fill")
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
            HStack(spacing: 8) {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(CheckpointTheme.paper)
                    } else {
                        Image(systemName: systemImage)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffectsRemoved(reduceMotion)
                    }
                }
                .frame(width: 20, height: 20)

                Text(title)
            }
                .font(.headline)
                .foregroundStyle(CheckpointTheme.paper)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [CheckpointTheme.teal, CheckpointTheme.ink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: CheckpointTheme.ink.opacity(0.14), radius: 10, y: 5)
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .opacity(isEnabled ? 1 : 0.58)
        .accessibilityLabel(isLoading ? "\(title), in progress" : title)
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
                        .stroke(CheckpointTheme.hairline, lineWidth: 1)
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
        .shadow(color: CheckpointTheme.ink.opacity(0.055), radius: 12, x: 0, y: 5)
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
