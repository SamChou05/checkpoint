import SwiftUI

enum CheckpointSetupStep: Int, CaseIterable {
    case goal = 1
    case skillMap
    case protection

    var title: String {
        switch self {
        case .goal: "Goal"
        case .skillMap: "Skill Map"
        case .protection: "Protection"
        }
    }

    var accessibilityLabel: String {
        "Setup, step \(rawValue) of \(Self.allCases.count), \(title)"
    }
}

/// A shared guide keeps the first-run conversation continuous across screens.
struct CheckpointSetupGuide: View {
    let step: CheckpointSetupStep
    let title: String
    let message: String
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasAppeared = false

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if step == .goal && dynamicTypeSize.isAccessibilitySize {
                compactGoalGreeting
            } else if dynamicTypeSize.isAccessibilitySize {
                progress
                VStack(alignment: .leading, spacing: 12) {
                    mascot
                    speech
                }
            } else {
                progress
                HStack(alignment: .top, spacing: 12) {
                    mascot
                        .padding(.top, 10)
                    speech
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panel,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckpointTheme.hairline.opacity(0.75), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: CheckpointTheme.shadowElevated, radius: 18, y: 8)
        .task(id: reduceMotion) {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.3)) {
                hasAppeared = true
            }
        }
    }

    private var compactGoalGreeting: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CheckpointMascotMark(size: 40, cornerRadius: 13)
                Text("Step 1 of 3 · Goal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(step.accessibilityLabel)

            Text("What will you learn?")
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(title). \(message)")
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Step \(step.rawValue) of 3 · \(step.title)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(CheckpointSetupStep.allCases, id: \.rawValue) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule()
                            .fill(item.rawValue <= step.rawValue
                                ? CheckpointTheme.teal
                                : CheckpointTheme.hairline)
                            .frame(height: 4)

                        if !dynamicTypeSize.isAccessibilitySize {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                if item.rawValue < step.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.bold))
                                } else {
                                    Text("\(item.rawValue)")
                                        .font(.caption.weight(.bold))
                                }
                                Text(item.title)
                                    .font(.caption.weight(item == step ? .bold : .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(item == step
                                ? CheckpointTheme.teal
                                : CheckpointTheme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.accessibilityLabel)
    }

    private var mascot: some View {
        CheckpointMascotMark(size: 64, cornerRadius: 20)
            .shadow(color: CheckpointTheme.shadowCard, radius: 8, y: 5)
            .rotationEffect(.degrees(hasAppeared || reduceMotion ? 0 : -5))
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.94)
            .accessibilityHidden(true)
    }

    private var speech: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.heroMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.ink,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(alignment: dynamicTypeSize.isAccessibilitySize ? .topLeading : .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(CheckpointTheme.ink)
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(45))
                .offset(
                    x: dynamicTypeSize.isAccessibilitySize ? 23 : -4,
                    y: dynamicTypeSize.isAccessibilitySize ? -4 : 0
                )
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}
