import SwiftUI

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
        }
        .buttonStyle(.plain)
    }
}

struct BreakRemainingStat: View {
    var expiresAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.amber)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Break remaining")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)

                    Text("Protection restarts automatically when this ends.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(valueText(at: context.date))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(12)
            .background(CheckpointTheme.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func valueText(at date: Date) -> String {
        guard let expiresAt else { return "Ending" }

        let minutesRemaining = max(0, Int(ceil(expiresAt.timeIntervalSince(date) / 60)))
        guard minutesRemaining > 0 else { return "Ending" }
        return "\(minutesRemaining)m"
    }
}
