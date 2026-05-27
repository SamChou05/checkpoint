import SwiftUI

enum CheckpointTheme {
    static let ink = Color(red: 0.06, green: 0.14, blue: 0.12)
    static let paper = Color(red: 0.96, green: 0.96, blue: 0.92)
    static let panel = Color(red: 1.00, green: 0.99, blue: 0.96)
    static let panelRaised = Color(red: 0.92, green: 0.91, blue: 0.86)
    static let hairline = Color(red: 0.72, green: 0.70, blue: 0.63).opacity(0.42)
    static let text = ink
    static let muted = Color(red: 0.37, green: 0.42, blue: 0.40)
    static let teal = Color(red: 0.14, green: 0.36, blue: 0.32)
    static let blue = Color(red: 0.15, green: 0.36, blue: 0.58)
    static let amber = Color(red: 0.54, green: 0.35, blue: 0.09)
    static let coral = Color(red: 0.66, green: 0.31, blue: 0.26)

    static let background = LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.96, blue: 0.92),
            Color(red: 0.92, green: 0.95, blue: 0.90),
            Color(red: 0.95, green: 0.93, blue: 0.87)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct PrimaryActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(CheckpointTheme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(CheckpointTheme.teal, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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

struct MetricTile: View {
    var title: String
    var value: String
    var tint: Color
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(CheckpointTheme.text)
                .monospacedDigit()

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        )
    }
}

struct StatusBadge: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(tint)
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
