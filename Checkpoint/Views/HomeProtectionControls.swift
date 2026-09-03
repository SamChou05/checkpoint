import SwiftUI

struct BreakRemainingPresentation: Equatable {
    let minutesRemaining: Int?

    init(expiresAt: Date?, at date: Date) {
        guard let expiresAt else {
            minutesRemaining = nil
            return
        }

        let remaining = max(0, Int(ceil(expiresAt.timeIntervalSince(date) / 60)))
        minutesRemaining = remaining > 0 ? remaining : nil
    }

    var text: String {
        minutesRemaining.map { "\($0)m" } ?? "Ending"
    }

    var accessibilityValue: String {
        guard let minutesRemaining else { return "Ending" }
        return minutesRemaining == 1
            ? "1 minute"
            : "\(minutesRemaining) minutes"
    }
}

struct HomeProtectionActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 10)
            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CheckpointTheme.controlStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct BreakRemainingStat: View {
    var expiresAt: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let presentation = BreakRemainingPresentation(
                expiresAt: expiresAt,
                at: context.date
            )

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            timerIcon
                            breakTitle
                        }

                        timerValue(presentation)
                        breakDetail
                    }
                } else {
                    HStack(spacing: 12) {
                        timerIcon

                        VStack(alignment: .leading, spacing: 3) {
                            breakTitle
                            breakDetail
                        }

                        Spacer(minLength: 12)
                        timerValue(presentation)
                    }
                }
            }
            .padding(12)
            .background(CheckpointTheme.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Break remaining")
            .accessibilityValue(presentation.accessibilityValue)
            .accessibilityHint("Protection restarts automatically when this break ends.")
        }
    }

    private var timerIcon: some View {
        Image(systemName: "timer")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(CheckpointTheme.amber)
            .frame(width: 24)
            .accessibilityHidden(true)
    }

    private var breakTitle: some View {
        Text("Break remaining")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var breakDetail: some View {
        Text("Protection restarts automatically when this ends.")
            .font(.caption.weight(.medium))
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func timerValue(_ presentation: BreakRemainingPresentation) -> some View {
        Text(presentation.text)
            .font(.title3.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentTransition(
                presentation.minutesRemaining == nil
                    ? .opacity
                    : .numericText(countsDown: true)
            )
            .animation(
                CheckpointMotion.animation(
                    CheckpointMotion.change,
                    reduceMotion: reduceMotion
                ),
                value: presentation
            )
    }
}
