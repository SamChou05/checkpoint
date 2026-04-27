import SwiftUI

struct CompetencyView: View {
    let store: CheckpointStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Skill Map")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Checkpoint uses your answers to keep questions challenging without jumping too far ahead.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    summary

                    if store.sortedCompetencies.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.sortedCompetencies) { competency in
                            CompetencyRow(competency: competency)
                        }
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Skill")
            .toolbarTitleDisplayMode(.inline)
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(
                title: "Average mastery",
                value: store.averageMasteryText,
                tint: CheckpointTheme.teal,
                systemImage: "chart.line.uptrend.xyaxis"
            )

            MetricTile(
                title: "Tracked topics",
                value: "\(store.competencies.count)",
                tint: CheckpointTheme.amber,
                systemImage: "scope"
            )
        }
    }

    private var emptyState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.amber)

                Text("No skill data yet")
                    .font(.title3.bold())
                    .foregroundStyle(CheckpointTheme.text)

                Text("Create a goal and answer a few checkpoints. Missed topics will move toward the top.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CompetencyRow: View {
    var competency: TopicCompetency

    var body: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(competency.topic)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Level \(competency.displayLevel) - \(competency.attempts) attempts")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    Spacer()

                    StatusBadge(text: "\(competency.masteryPercent)%", tint: tint)
                }

                ProgressView(value: Double(competency.masteryPercent), total: 100)
                    .tint(tint)

                HStack {
                    Label("\(competency.correct)", systemImage: "checkmark.circle")
                    Spacer()
                    Label("\(competency.partial)", systemImage: "circle.lefthalf.filled")
                    Spacer()
                    Label("\(competency.incorrect)", systemImage: "xmark.circle")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
            }
        }
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

