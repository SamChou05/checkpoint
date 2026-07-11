import Foundation
import SwiftUI

enum AppResourceURL {
    static func configuredHTTPSValue(forInfoDictionaryKey key: String) -> URL? {
        validatedHTTPSValue(Bundle.main.object(forInfoDictionaryKey: key) as? String)
    }

    static func validatedHTTPSValue(_ rawValue: String?) -> URL? {
        guard
            let rawValue,
            !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let components = URLComponents(
                string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            components.scheme?.lowercased() == "https",
            let host = components.host,
            isPublicHost(host),
            components.user == nil,
            components.password == nil
        else {
            return nil
        }

        return components.url
    }

    private static func isPublicHost(_ host: String) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard normalized.contains("."),
              !["example.com", "example.net", "example.org"].contains(normalized),
              !normalized.hasSuffix(".example.com"),
              !normalized.hasSuffix(".example.net"),
              !normalized.hasSuffix(".example.org"),
              !normalized.hasSuffix(".example"),
              !normalized.hasSuffix(".invalid"),
              !normalized.hasSuffix(".local"),
              !normalized.hasSuffix(".localhost"),
              !normalized.hasSuffix(".test"),
              !normalized.hasSuffix(".internal"),
              !normalized.hasSuffix(".lan") else {
            return false
        }

        let octets = normalized.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) {
            let first = octets[0]
            let second = octets[1]
            return first != 0
                && first != 10
                && first != 127
                && first != 169
                && !(first == 172 && (16...31).contains(second))
                && !(first == 192 && second == 168)
                && !(first == 100 && (64...127).contains(second))
        }

        return !normalized.contains(":")
    }
}

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
