import SwiftUI

enum CheckpointTheme {
    static let ink = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let panel = Color(red: 0.10, green: 0.12, blue: 0.15)
    static let panelRaised = Color(red: 0.14, green: 0.16, blue: 0.20)
    static let text = Color(red: 0.95, green: 0.96, blue: 0.94)
    static let muted = Color(red: 0.63, green: 0.67, blue: 0.70)
    static let teal = Color(red: 0.20, green: 0.78, blue: 0.68)
    static let amber = Color(red: 0.95, green: 0.68, blue: 0.30)
    static let coral = Color(red: 0.92, green: 0.35, blue: 0.32)

    static let background = LinearGradient(
        colors: [
            Color(red: 0.04, green: 0.05, blue: 0.07),
            Color(red: 0.08, green: 0.09, blue: 0.11),
            Color(red: 0.05, green: 0.08, blue: 0.08)
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
                .foregroundStyle(.black)
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
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
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
                .stroke(.white.opacity(0.08), lineWidth: 1)
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
