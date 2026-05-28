import SwiftUI

struct HistoryView: View {
    let store: CheckpointStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Checkpoint History")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Every checkpoint answer is stored so missed questions can return later.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    if store.activeAttempts.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.activeAttempts) { attempt in
                            AttemptRow(attempt: attempt)
                        }
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("History")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
        }
    }

    private var emptyState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.amber)

                Text("No checkpoints yet")
                    .font(.title3.bold())
                    .foregroundStyle(CheckpointTheme.text)

                Text("Blocked-app checkpoints appear here after the first rep.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
            }
        }
    }
}

private struct AttemptRow: View {
    var attempt: CheckpointAttempt

    var body: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StatusBadge(text: attempt.result.rawValue, tint: tint)
                    Spacer()
                    Text(attempt.createdAt, style: .time)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)
                }

                Text(attempt.prompt)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(attempt.answer)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Label("\(attempt.unlockMinutes)m unlock", systemImage: "timer")
                    Spacer()
                    Label("Stored", systemImage: "archivebox")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
            }
        }
    }

    private var tint: Color {
        switch attempt.result {
        case .correct:
            return CheckpointTheme.teal
        case .partial:
            return CheckpointTheme.amber
        case .incorrect, .unclear:
            return CheckpointTheme.coral
        }
    }
}
