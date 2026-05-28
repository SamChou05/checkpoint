import SwiftUI

enum AdvancedSettingsAction: String, Identifiable {
    case resetData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resetData:
            return "Reset Checkpoint?"
        }
    }

    var detail: String {
        switch self {
        case .resetData:
            return "This clears your goal, questions, skill map, history, reports, and blocking state on this device."
        }
    }

    var confirmationPhrase: String {
        switch self {
        case .resetData:
            return "RESET"
        }
    }

    var buttonTitle: String {
        switch self {
        case .resetData:
            return "Reset app data"
        }
    }

    var systemImage: String {
        switch self {
        case .resetData:
            return "arrow.counterclockwise"
        }
    }
}

struct AdvancedConfirmationView: View {
    let action: AdvancedSettingsAction
    let store: CheckpointStore
    let screenTime: ScreenTimeController

    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(action.title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text(action.detail)
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Confirm") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Type \(action.confirmationPhrase) to continue.")
                                .font(.subheadline)
                                .foregroundStyle(CheckpointTheme.muted)

                            TextField(action.confirmationPhrase, text: $confirmationText)
                                .textFieldStyle(.plain)
                                .font(.headline)
                                .foregroundStyle(CheckpointTheme.text)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                            PrimaryActionButton(title: action.buttonTitle, systemImage: action.systemImage) {
                                performAction()
                                dismiss()
                            }
                            .disabled(!isConfirmed)

                            SecondaryActionButton(title: "Cancel", systemImage: "xmark") {
                                dismiss()
                            }
                        }
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle(action.buttonTitle)
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

    private var isConfirmed: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == action.confirmationPhrase
    }

    private func performAction() {
        switch action {
        case .resetData:
            screenTime.clearShield()
            store.resetDemoData()
        }
    }
}

struct SettingsNavigationRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var trailingText: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 34, height: 34)
                    .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)

                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                }

                Spacer(minLength: 0)

                Text(trailingText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ProLockedFeatureRow: View {
    var feature: ProFeature
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CheckpointTheme.amber)
                .frame(width: 26, height: 26)
                .background(CheckpointTheme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                Text(feature.detail)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Pro") {
                action()
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.paper)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(CheckpointTheme.teal, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .background(CheckpointTheme.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}
