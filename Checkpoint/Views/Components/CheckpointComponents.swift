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

struct PrimaryActionButton: View {
    var title: String
    var systemImage: String
    var isLoading: Bool
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

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
                if isLoading {
                    ProgressView()
                        .tint(CheckpointTheme.paper)
                } else {
                    Image(systemName: systemImage)
                }

                Text(title)
            }
                .font(.headline)
                .foregroundStyle(CheckpointTheme.paper)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(CheckpointTheme.teal, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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
                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CheckpointTheme.panel.opacity(0.96))
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        )
        .shadow(color: CheckpointTheme.ink.opacity(0.04), radius: 8, x: 0, y: 3)
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
