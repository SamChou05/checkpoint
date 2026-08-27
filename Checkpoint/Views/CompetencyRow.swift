import SwiftUI

struct CompetencyRow: View {
    var competency: TopicCompetency
    @State private var isExpanded = false

    var body: some View {
        let progress = progressPresentation

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

                    StatusBadge(text: progress.label, tint: progress.tint)
                }

                ProgressView(value: Double(competency.masteryPercent), total: 100)
                    .tint(progress.tint)
                    .accessibilityLabel("Progress")
                    .accessibilityValue(progress.label)

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
                    Text("Details for \(competency.topic)")
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

    private var progressPresentation: (label: String, tint: Color) {
        if competency.attempts == 0 {
            return ("Not started", CheckpointTheme.blue)
        }

        switch competency.masteryPercent {
        case 75...:
            return ("Strong", CheckpointTheme.teal)
        case 40..<75:
            return ("Building", CheckpointTheme.amber)
        default:
            return ("Needs practice", CheckpointTheme.coral)
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
}
