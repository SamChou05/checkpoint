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
    @State private var actionErrorMessage: String?
    @AccessibilityFocusState private var isActionErrorFocused: Bool

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
                                .accessibilityLabel("Confirmation phrase")
                                .accessibilityHint("Type \(action.confirmationPhrase) to continue.")

                            Button(role: .destructive) {
                                performAction()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: action.systemImage)

                                    Text(action.buttonTitle)
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .padding(.horizontal, 12)
                                .background(
                                    CheckpointTheme.coral,
                                    in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                                )
                            }
                            .buttonStyle(CheckpointPressButtonStyle())
                            .disabled(!isConfirmed)
                            .opacity(isConfirmed ? 1 : 0.58)
                            .accessibilityLabel(action.buttonTitle)

                            if let actionErrorMessage {
                                Label(actionErrorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.coral)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityFocused($isActionErrorFocused)
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
        actionErrorMessage = nil

        switch action {
        case .resetData:
            screenTime.eraseAllData()
            store.eraseAllData()
        }

        let recoveryMessages = [
            screenTime.sharedDataEraseErrorMessage,
            store.persistenceRecoveryMessage
        ].compactMap { $0 }

        guard recoveryMessages.isEmpty else {
            let message = recoveryMessages.joined(separator: " ")
            actionErrorMessage = message
            Task { @MainActor in
                await Task.yield()
                isActionErrorFocused = true
            }
            return
        }

        AccessibilityNotification.Announcement("All Checkpoint data was erased.").post()
        dismiss()
    }
}

struct SettingsNavigationRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var trailingText: String
    var voiceOverValue: String? = nil
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemImage: systemImage)
                            titleLabel
                            Spacer(minLength: 8)
                            chevron
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            trailingLabel
                            detailLabel
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        SettingsRowIcon(systemImage: systemImage)

                        VStack(alignment: .leading, spacing: 4) {
                            titleLabel
                            detailLabel
                        }

                        Spacer(minLength: 0)
                        trailingLabel
                        chevron
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(voiceOverValue ?? detail)
        .accessibilityHint("Opens \(title).")
    }

    private var titleLabel: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var detailLabel: some View {
        Text(detail)
            .font(.footnote)
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var trailingLabel: some View {
        Text(trailingText)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.muted)
            .accessibilityHidden(true)
    }
}

struct LegalLinkRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var url: URL?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if let url {
            Link(destination: url) {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(detail)
            .accessibilityHint("Opens in your browser.")
        } else {
            rowContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(detail)
                .accessibilityHint("This URL is not configured in this build.")
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        SettingsRowIcon(systemImage: systemImage)
                        legalTitle
                    }

                    legalDetail
                    legalAccessory
                }
            } else {
                HStack(spacing: 12) {
                    SettingsRowIcon(systemImage: systemImage)

                    VStack(alignment: .leading, spacing: 4) {
                        legalTitle
                        legalDetail
                    }

                    Spacer(minLength: 8)
                    legalAccessory
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var legalTitle: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var legalDetail: some View {
        Text(detail)
            .font(.footnote)
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var legalAccessory: some View {
        if url == nil {
            StatusBadge(text: "Not configured", tint: CheckpointTheme.coral)
        } else {
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityHidden(true)
        }
    }
}

private struct SettingsRowIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 34, height: 34)
            .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}
