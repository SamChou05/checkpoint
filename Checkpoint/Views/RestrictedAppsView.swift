import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

struct RestrictedAppsView: View {
    let screenTime: ScreenTimeController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .checkpointScreenBackground()
                .navigationTitle("Protected Apps")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundStyle(CheckpointTheme.teal)
                    }
                }
        }
        .preferredColorScheme(.light)
        .task {
            if screenTime.setupState == .notStarted || screenTime.setupState == .failed {
                await screenTime.requestAuthorization()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS) && canImport(FamilyControls)
        FamilyPickerContent(screenTime: screenTime)
        #else
        ScrollView {
            SectionPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(CheckpointTheme.amber)

                    Text("App protection unavailable")
                        .font(.title3.bold())
                        .foregroundStyle(CheckpointTheme.text)

                    Text("App protection is available on iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        #endif
    }
}

#if os(iOS) && canImport(FamilyControls)
private struct FamilyPickerContent: View {
    let screenTime: ScreenTimeController

    @State private var localSelection: FamilyActivitySelection

    init(screenTime: ScreenTimeController) {
        self.screenTime = screenTime
        _localSelection = State(initialValue: screenTime.selection)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose what Checkpoint should protect.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Label(selectionSummary, systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                if !localSelection.categoryTokens.isEmpty {
                    Text("Category shortcuts add their apps to this list. Your individual app changes take precedence.")
                        .font(.caption)
                        .foregroundStyle(CheckpointTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage = screenTime.userFacingErrorMessage {
                    Text(errorMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(CheckpointTheme.panel)

            FamilyActivityPicker(selection: $localSelection)
                .onChange(of: localSelection) { _, newSelection in
                    if !screenTime.updateSelection(newSelection) {
                        localSelection = screenTime.selection
                    }
                }
        }
        .onChange(of: screenTime.selection) { _, newSelection in
            if localSelection != newSelection {
                localSelection = newSelection
            }
        }
        .onDisappear {
            _ = screenTime.updateSelection(localSelection)
        }
    }

    private var selectionSummary: String {
        let parts = [
            selectionCountText(localSelection.applicationTokens.count, singular: "app", plural: "apps"),
            selectionCountText(localSelection.categoryTokens.count, singular: "category", plural: "categories"),
            selectionCountText(localSelection.webDomainTokens.count, singular: "site", plural: "sites")
        ].compactMap { $0 }

        guard !parts.isEmpty else { return "Nothing selected yet" }
        return parts.joined(separator: ", ") + " selected"
    }

    private func selectionCountText(
        _ count: Int,
        singular: String,
        plural: String
    ) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? singular : plural)"
    }
}
#endif
