import SwiftUI

struct PracticeStandardStepperRow: View {
    var title: String
    var value: Int
    var decrementDisabled: Bool
    var incrementDisabled: Bool
    var decrementAction: () -> Void
    var incrementAction: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    titleLabel

                    HStack(spacing: 12) {
                        valueLabel
                        Spacer(minLength: 8)
                        adjustmentControls
                    }
                }
            } else {
                HStack(spacing: 10) {
                    titleLabel
                    Spacer(minLength: 8)
                    valueLabel
                    adjustmentControls
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(CheckpointTheme.panelRaised.opacity(0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityHint("Swipe up or down to adjust.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where !incrementDisabled:
                incrementAction()
            case .decrement where !decrementDisabled:
                decrementAction()
            default:
                break
            }
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueLabel: some View {
        Text("\(value)")
            .font(.title3.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private var adjustmentControls: some View {
        HStack(spacing: 1) {
            adjustmentButton(
                systemImage: "minus",
                accessibilityLabel: "Decrease \(title)",
                isDisabled: decrementDisabled,
                action: decrementAction
            )

            adjustmentButton(
                systemImage: "plus",
                accessibilityLabel: "Increase \(title)",
                isDisabled: incrementDisabled,
                action: incrementAction
            )
        }
        .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        )
    }

    private func adjustmentButton(
        systemImage: String,
        accessibilityLabel: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isDisabled ? CheckpointTheme.muted.opacity(0.45) : CheckpointTheme.teal)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct BreakDurationMenu: View {
    var selectedMinutes: Int
    var options: [Int]
    var selectMinutes: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { minutes in
                Button {
                    selectMinutes(minutes)
                } label: {
                    Label("\(minutes) minutes", systemImage: minutes == selectedMinutes ? "checkmark" : "timer")
                }
            }
        } label: {
            menuLabel
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CheckpointTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Break after passing")
        .accessibilityValue("\(selectedMinutes) minutes")
        .accessibilityHint("Choose how long protected apps open after passing a practice set.")
    }

    @ViewBuilder
    private var menuLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    menuIcon
                    menuTitle
                }

                HStack(spacing: 8) {
                    menuValue
                    Spacer(minLength: 8)
                    menuChevron
                }
            }
        } else {
            HStack(spacing: 12) {
                menuIcon
                menuTitle
                Spacer(minLength: 8)
                menuValue
                menuChevron
            }
        }
    }

    private var menuIcon: some View {
        Image(systemName: "timer")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 30, height: 30)
            .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private var menuTitle: some View {
        Text("Break after passing")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var menuValue: some View {
        Text("\(selectedMinutes) min")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private var menuChevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.muted)
            .accessibilityHidden(true)
    }
}
