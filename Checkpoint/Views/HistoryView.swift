import SwiftUI

struct HistoryView: View {
    let store: CheckpointStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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

                Text("No practice yet")
                    .font(.title3.bold())
                    .foregroundStyle(CheckpointTheme.text)

                Text("Your answers will appear here after your first checkpoint.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
            }
        }
    }
}

private struct AttemptRow: View {
    var attempt: CheckpointAttempt
    @State private var isExpanded = false

    var body: some View {
        SectionPanel {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your answer")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckpointTheme.muted)

                    Text(attempt.answer)
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        StatusBadge(text: resultLabel, tint: tint)
                        Spacer()
                        Text(attempt.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    Text(attempt.prompt)
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.text)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(CheckpointTheme.teal)
        }
    }

    private var resultLabel: String {
        switch attempt.result {
        case .correct:
            return "Correct"
        case .partial:
            return "Almost"
        case .incorrect:
            return "Missed"
        case .unclear:
            return "Not sure"
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
