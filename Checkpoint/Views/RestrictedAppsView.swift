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
                .navigationTitle("Restricted Apps")
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
        .preferredColorScheme(.dark)
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

                    Text("Screen Time APIs unavailable")
                        .font(.title3.bold())
                        .foregroundStyle(CheckpointTheme.text)

                    Text("Open this project in Xcode with an iOS target and add the Family Controls capability to use app selection.")
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
                Text("Choose apps, categories, or websites to gate behind checkpoints.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Label("\(localSelection.applicationTokens.count) apps", systemImage: "app")
                    Spacer()
                    Label("\(localSelection.categoryTokens.count) categories", systemImage: "square.grid.2x2")
                    Spacer()
                    Label("\(localSelection.webDomainTokens.count) sites", systemImage: "globe")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
            }
            .padding(16)
            .background(CheckpointTheme.panel)

            FamilyActivityPicker(selection: $localSelection)
                .onChange(of: localSelection) { _, newSelection in
                    screenTime.updateSelection(newSelection)
                }
        }
    }
}
#endif

