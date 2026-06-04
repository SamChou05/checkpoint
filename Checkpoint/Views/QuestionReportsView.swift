import SwiftUI

struct QuestionReportsView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var category: IssueReportCategory = .generalFeedback
    @State private var message = ""
    @State private var contact = ""
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Report an issue")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Send feedback, question problems, or app issues from one place.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Issue") {
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

                            TextField("Email optional", text: $contact)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textFieldStyle(.plain)
                                .foregroundStyle(CheckpointTheme.text)
                                .padding(12)
                                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                            PrimaryActionButton(title: "Submit", systemImage: "paperplane") {
                                submitReport()
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

                    SectionPanel("Recent submissions") {
                        if store.issueReports.isEmpty {
                            EmptyIssueReportsState(
                                systemImage: "tray",
                                title: "No reports yet",
                                detail: "Submitted feedback will appear here."
                            )
                        } else {
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
            .navigationTitle("Report an issue")
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

    private func submitReport() {
        let didSubmit = store.submitIssueReport(
            category: category,
            message: message,
            contact: contact
        )

        guard didSubmit else {
            statusMessage = "Add a short note before submitting."
            return
        }

        message = ""
        contact = ""
        category = .generalFeedback
        statusMessage = "Submitted."
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
            }

            Text(report.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            if !report.goalTitle.isEmpty {
                Text("Goal: \(report.goalTitle)")
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyIssueReportsState: View {
    var systemImage: String
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(CheckpointTheme.amber)

            Text(title)
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
