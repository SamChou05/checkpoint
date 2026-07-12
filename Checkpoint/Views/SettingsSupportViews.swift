import SwiftUI

enum AdvancedSettingsAction: String, Identifiable {
    case resetData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resetData:
            return "Erase all data?"
        }
    }

    var detail: String {
        switch self {
        case .resetData:
            return "This erases goals, progress, protected-app selections, local diagnostics, and the anonymous backend install ID, then turns off app protection. Your App Store subscription and iOS Screen Time permission are not canceled. This can't be undone."
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
            return "Erase all data"
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
            screenTime.eraseAllData()
            store.eraseAllData()
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

struct LegalLinkRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var url: URL?

    @ViewBuilder
    var body: some View {
        if let url {
            Link(destination: url) {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
                .accessibilityHint("This URL is not configured in this build.")
        }
    }

    private var rowContent: some View {
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if url == nil {
                StatusBadge(text: "Not configured", tint: CheckpointTheme.coral)
            } else {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
