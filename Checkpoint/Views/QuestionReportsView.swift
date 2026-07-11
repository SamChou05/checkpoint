import SwiftUI

struct QuestionReportsView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var category: IssueReportCategory = .generalFeedback
    @State private var message = ""
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Save the details, then share the note through your preferred support channel.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    SectionPanel("Feedback note") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Type", selection: $category) {
                                ForEach(IssueReportCategory.allCases) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            .pickerStyle(.menu)

                            TextField("What happened?", text: $message, axis: .vertical)
                                .lineLimit(5, reservesSpace: true)
                                .textFieldStyle(.plain)
                                .foregroundStyle(CheckpointTheme.text)
                                .padding(12)
                                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                            PrimaryActionButton(title: "Save note", systemImage: "square.and.arrow.down") {
                                saveNote()
                            }
                            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)

                            if let statusMessage {
                                Text(statusMessage)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.teal)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if !store.issueReports.isEmpty {
                        SectionPanel("Saved notes") {
                            VStack(spacing: 12) {
                                ForEach(Array(store.issueReports.prefix(10))) { report in
                                    SubmittedIssueReportRow(report: report)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Help & Feedback")
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

    private func saveNote() {
        let didSubmit = store.submitIssueReport(
            category: category,
            message: message,
            contact: ""
        )

        guard didSubmit else {
            statusMessage = "Add a short note before saving."
            return
        }

        message = ""
        category = .generalFeedback
        statusMessage = "Saved on this device. Use Share on the note when you're ready to send it."
    }
}

private struct SubmittedIssueReportRow: View {
    var report: UserIssueReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(text: report.category.rawValue, tint: CheckpointTheme.amber)

                Spacer()

                Text(report.createdAt, style: .date)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)

                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Share feedback note")
            }

            Text(report.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

        }
        .padding(12)
        .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
    }

    private var shareText: String {
        var lines = [
            "Checkpoint feedback",
            "Type: \(report.category.rawValue)",
            report.message
        ]

        if !report.goalTitle.isEmpty, report.goalTitle != "No goal" {
            lines.append("Goal: \(report.goalTitle)")
        }

        return lines.joined(separator: "\n")
    }
}
