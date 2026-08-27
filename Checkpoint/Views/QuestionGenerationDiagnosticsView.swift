import SwiftUI

struct QuestionGenerationDiagnosticsView: View {
    let store: CheckpointStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Generation Diagnostics")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Recent prompts, providers, and generated question previews.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Recent runs") {
                        if store.questionGenerationTraces.isEmpty {
                            EmptyGenerationDiagnosticsState()
                        } else {
                            VStack(spacing: 12) {
                                ForEach(store.questionGenerationTraces) { trace in
                                    GenerationTraceRow(trace: trace)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 32)
            }
            .checkpointScreenBackground()
            .navigationTitle("Generation")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }

                if !store.questionGenerationTraces.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        ShareLink(item: store.questionGenerationDiagnosticsExportText) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(CheckpointTheme.teal)

                        Button("Clear", role: .destructive) {
                            store.clearQuestionGenerationDiagnostics()
                        }
                    }
                }
            }
        }
    }
}

private struct GenerationTraceRow: View {
    var trace: QuestionGenerationTrace
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                DiagnosticsKeyValueGrid(rows: [
                    ("Goal", trace.goalTitle),
                    ("Preference", trace.providerPreference.rawValue),
                    ("Provider", trace.resolvedProvider.rawValue),
                    ("Target", "\(trace.targetCount)"),
                    ("Existing", "\(trace.existingQuestionCount)"),
                    ("Generated", "\(trace.generatedQuestionCount)"),
                    ("Added", "\(trace.addedQuestionCount)"),
                    ("Retired", "\(trace.retiredQuestionCount)"),
                    ("Minimum level", "\(trace.minimumDifficulty)"),
                    ("Duration", formattedDuration(trace.duration))
                ])

                if let errorMessage = trace.errorMessage {
                    DiagnosticsTextBlock(title: "Message", text: errorMessage)
                }

                DiagnosticsTextBlock(title: "Prompt", text: trace.sourcePrompt)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Questions")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckpointTheme.muted)

                    if trace.questions.isEmpty {
                        Text("No question previews recorded.")
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                    } else {
                        ForEach(Array(trace.questions.enumerated()), id: \.element.id) { index, question in
                            GenerationQuestionPreviewRow(index: index + 1, question: question)
                        }
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trace.phase)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)

                        Text(trace.createdAt, style: .time)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    Spacer()

                    StatusBadge(
                        text: trace.usedFallback ? "Fallback" : trace.resolvedProvider.rawValue,
                        tint: trace.usedFallback ? CheckpointTheme.amber : CheckpointTheme.teal
                    )
                }

                HStack(spacing: 12) {
                    Label("\(trace.generatedQuestionCount) generated", systemImage: "sparkles")
                    Label("\(trace.addedQuestionCount) added", systemImage: "plus.circle")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
            }
        }
        .tint(CheckpointTheme.teal)
        .padding(12)
        .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "under 1s"
        }

        return "\(Int(duration.rounded()))s"
    }
}

private struct DiagnosticsKeyValueGrid: View {
    var rows: [(String, String)]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)

                    Spacer(minLength: 12)

                    Text(row.1)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct DiagnosticsTextBlock: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.muted)

            Text(text)
                .font(.caption)
                .foregroundStyle(CheckpointTheme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct GenerationQuestionPreviewRow: View {
    var index: Int
    var question: QuestionGenerationQuestionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(text: question.topic, tint: CheckpointTheme.teal)

                Spacer()

                Text("Level \(question.difficulty)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)
            }

            Text("\(index). \(question.prompt)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Choices: \(question.choices.joined(separator: " | "))")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Answer: \(question.expectedAnswer)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(question.explanation)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptyGenerationDiagnosticsState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(CheckpointTheme.amber)

            Text("No generation runs yet")
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)

            Text("Create or refresh a goal to record the next prompt and question batch.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
