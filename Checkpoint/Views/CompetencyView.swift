import SwiftUI

struct CompetencyView: View {
    let store: CheckpointStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if store.sortedCompetencies.isEmpty {
                        emptyState
                    } else {
                        Text("See what's strong and what to practice next. Topics needing attention appear first.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(store.sortedCompetencies) { competency in
                            CompetencyRow(competency: competency)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 56)
            }
            .padding(.bottom, 48)
            .checkpointScreenBackground()
            .navigationTitle("Progress")
            .toolbarTitleDisplayMode(.inline)
        }
    }

    private var emptyState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.amber)

                Text("No progress yet")
                    .font(.title3.bold())
                    .foregroundStyle(CheckpointTheme.text)

                Text("Complete a few practice questions to see what to review next.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CompetencyRow: View {
    var competency: TopicCompetency
    @State private var isExpanded = false

    var body: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(competency.topic)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)

                        Text(questionCountText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    Spacer()

                    StatusBadge(text: progressLabel, tint: tint)
                }

                ProgressView(value: Double(competency.masteryPercent), total: 100)
                    .tint(tint)
                    .accessibilityLabel("Progress")
                    .accessibilityValue(progressLabel)

                DisclosureGroup(isExpanded: $isExpanded) {
                    HStack {
                        detailCount(title: "Correct", value: competency.correct, systemImage: "checkmark.circle")
                        Spacer()
                        detailCount(title: "Almost", value: competency.partial, systemImage: "circle.lefthalf.filled")
                        Spacer()
                        detailCount(title: "Missed", value: competency.incorrect, systemImage: "xmark.circle")
                    }
                    .padding(.top, 10)
                } label: {
                    Text("Details")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                }
                .tint(CheckpointTheme.teal)
            }
        }
    }

    private var questionCountText: String {
        "\(competency.attempts) \(competency.attempts == 1 ? "question" : "questions") answered"
    }

    private var progressLabel: String {
        switch competency.masteryPercent {
        case 75...:
            return "Strong"
        case 40..<75:
            return "Building"
        default:
            return "Needs practice"
        }
    }

    private func detailCount(title: String, value: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("\(value)", systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }

    private var tint: Color {
        switch competency.masteryPercent {
        case 75...:
            return CheckpointTheme.teal
        case 40..<75:
            return CheckpointTheme.amber
        default:
            return CheckpointTheme.coral
        }
    }
}
