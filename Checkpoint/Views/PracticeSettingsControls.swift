import SwiftUI

struct PracticeStandardStepperRow: View {
    var title: String
    var value: Int
    var decrementDisabled: Bool
    var incrementDisabled: Bool
    var decrementAction: () -> Void
    var incrementAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 8)

            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CheckpointTheme.panelRaised.opacity(0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 30, height: 30)
                    .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("Break after passing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)

                Text("\(selectedMinutes) min")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CheckpointTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose how long protected apps open after passing a practice set.")
    }
}
