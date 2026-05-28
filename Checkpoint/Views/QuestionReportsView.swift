import SwiftUI

struct QuestionReportsView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuestion: CheckpointQuestion?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Question Reports")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Flag confusing, incorrect, or mismatched questions away from the checkpoint flow.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Report a question") {
                        if reportableQuestions.isEmpty {
                            EmptyReportsState(
                                systemImage: "checkmark.seal",
                                title: "No active questions to review",
                                detail: "Answered questions that are still in the current set will appear here."
                            )
                        } else {
                            VStack(spacing: 12) {
                                ForEach(reportableQuestions) { question in
                                    ReportableQuestionRow(question: question) {
                                        selectedQuestion = question
                                    }
                                }
                            }
                        }
                    }

                    SectionPanel("Submitted") {
                        if store.activeQuestionReports.isEmpty {
                            EmptyReportsState(
                                systemImage: "tray",
                                title: "No reports yet",
                                detail: "Reported questions are retired from future checkpoints."
                            )
                        } else {
                            VStack(spacing: 12) {
                                ForEach(store.activeQuestionReports) { report in
                                    SubmittedQuestionReportRow(report: report)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Question Reports")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
            .sheet(item: $selectedQuestion) { question in
                QuestionReportComposerView(store: store, question: question)
            }
        }
    }

    private var reportableQuestions: [CheckpointQuestion] {
        let reportedQuestionIDs = Set(store.activeQuestionReports.map(\.questionID))
        let activeQuestions = store.activeQuestions.filter { question in
            question.status != .retired && !reportedQuestionIDs.contains(question.id)
        }
        let questionsByID = Dictionary(uniqueKeysWithValues: activeQuestions.map { ($0.id, $0) })
        var orderedQuestions: [CheckpointQuestion] = []
        var seenQuestionIDs = Set<CheckpointQuestion.ID>()

        for attempt in store.activeAttempts {
            guard let question = questionsByID[attempt.questionID],
                  !seenQuestionIDs.contains(question.id) else {
                continue
            }

            orderedQuestions.append(question)
            seenQuestionIDs.insert(question.id)
        }

        for question in activeQuestions where !seenQuestionIDs.contains(question.id) {
            orderedQuestions.append(question)
            seenQuestionIDs.insert(question.id)
        }

        return Array(orderedQuestions.prefix(20))
    }
}

private struct ReportableQuestionRow: View {
    var question: CheckpointQuestion
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(text: question.topic, tint: CheckpointTheme.teal)

                Spacer()

                Text("Level \(question.difficulty) of 5")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)
            }

            Text(question.prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryActionButton(title: "Report issue", systemImage: "exclamationmark.bubble") {
                action()
            }
        }
        .padding(12)
        .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SubmittedQuestionReportRow: View {
    var report: QuestionQualityReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(text: report.reason.rawValue, tint: CheckpointTheme.amber)

                Spacer()

                Text(report.createdAt, style: .date)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)
            }

            Text(report.prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            if !report.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(report.note)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyReportsState: View {
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

private struct QuestionReportComposerView: View {
    let store: CheckpointStore
    let question: CheckpointQuestion

    @Environment(\.dismiss) private var dismiss
    @State private var reportReason: QuestionReportReason = .confusing
    @State private var reportNote = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Report Question")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("This removes the question from future checkpoints and helps future batches avoid similar issues.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Question") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                StatusBadge(text: question.topic, tint: CheckpointTheme.teal)

                                Spacer()

                                Text("Level \(question.difficulty) of 5")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(CheckpointTheme.muted)
                            }

                            Text(question.prompt)
                                .font(.headline)
                                .foregroundStyle(CheckpointTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SectionPanel("Issue") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Problem", selection: $reportReason) {
                                ForEach(QuestionReportReason.allCases) { reason in
                                    Text(reason.rawValue).tag(reason)
                                }
                            }

                            TextField("Optional note", text: $reportNote, axis: .vertical)
                                .lineLimit(4, reservesSpace: true)
                                .textFieldStyle(.plain)
                                .foregroundStyle(CheckpointTheme.text)
                                .padding(12)
                                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                            PrimaryActionButton(title: "Submit report", systemImage: "paperplane") {
                                store.reportQuestion(question, reason: reportReason, note: reportNote)
                                dismiss()
                            }

                            SecondaryActionButton(title: "Cancel", systemImage: "xmark") {
                                dismiss()
                            }
                        }
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Report Question")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
        }
    }
}
