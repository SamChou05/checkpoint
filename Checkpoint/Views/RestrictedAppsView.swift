import Accessibility
import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

enum RestrictedAppsPresentationMode: Equatable {
    case management
    case firstRun
}

struct RestrictedAppsView: View {
    let screenTime: ScreenTimeController
    let presentationMode: RestrictedAppsPresentationMode
    private let onStartProtection: (@MainActor () async -> String?)?
    private let onContinueWithoutProtection: (@MainActor () -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isStartingProtection = false
    @State private var firstRunCompletionError: String?

    init(
        screenTime: ScreenTimeController,
        presentationMode: RestrictedAppsPresentationMode = .management,
        onStartProtection: (@MainActor () async -> String?)? = nil,
        onContinueWithoutProtection: (@MainActor () -> Void)? = nil
    ) {
        self.screenTime = screenTime
        self.presentationMode = presentationMode
        self.onStartProtection = onStartProtection
        self.onContinueWithoutProtection = onContinueWithoutProtection
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .checkpointScreenBackground()
                .navigationTitle(presentationMode == .firstRun ? "Choose Apps" : "Protected Apps")
                .toolbarTitleDisplayMode(.inline)
                .toolbar(
                    presentationMode == .firstRun ? .hidden : .visible,
                    for: .navigationBar
                )
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if presentationMode == .firstRun {
                        firstRunActionBar
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        if presentationMode == .management {
                            Button("Done") {
                                dismiss()
                            }
                            .foregroundStyle(CheckpointTheme.teal)
                        }
                    }
                }
        }
        .task {
            if screenTime.setupState == .notStarted || screenTime.setupState == .failed {
                await screenTime.requestAuthorization()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS) && canImport(FamilyControls)
        FamilyPickerContent(
            screenTime: screenTime,
            presentationMode: presentationMode
        )
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

    private var firstRunActionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            if !dynamicTypeSize.isAccessibilitySize {
                Text(firstRunActionDetail)
                    .font(.caption)
                    .foregroundStyle(screenTime.hasSelection ? CheckpointTheme.muted : CheckpointTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }

            if let firstRunCompletionError {
                Label(firstRunCompletionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            PrimaryActionButton(
                title: isStartingProtection ? "Turning on protection" : "Turn on protection",
                systemImage: "checkmark.shield",
                isLoading: isStartingProtection
            ) {
                startProtectionAndFinish()
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .disabled(!screenTime.hasSelection || isStartingProtection)
            .padding(.horizontal, 20)

            if firstRunCompletionError != nil, let onContinueWithoutProtection {
                Button("Continue to Home") {
                    onContinueWithoutProtection()
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
            }

        }
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var firstRunActionDetail: String {
        if isStartingProtection {
            return "Preparing your first checkpoint and turning protection on."
        }
        if screenTime.hasSelection {
            return "Your choices are saved. Finish setup to turn protection on."
        }
        if hasCategoryOnlySelection {
            return "Keep at least one app selected inside the category to continue."
        }
        return "Select at least one app or website to continue."
    }

    private var hasCategoryOnlySelection: Bool {
        #if os(iOS) && canImport(FamilyControls)
        !screenTime.selection.categoryTokens.isEmpty && !screenTime.hasSelection
        #else
        false
        #endif
    }

    private func startProtectionAndFinish() {
        guard screenTime.hasSelection, !isStartingProtection else { return }

        Task { @MainActor in
            isStartingProtection = true
            firstRunCompletionError = nil
            let errorMessage = await onStartProtection?()
            isStartingProtection = false

            if let errorMessage {
                firstRunCompletionError = errorMessage
                AccessibilityNotification.Announcement(errorMessage).post()
                return
            }

            dismiss()
        }
    }
}

#if os(iOS) && canImport(FamilyControls)
private struct FamilyPickerContent: View {
    let screenTime: ScreenTimeController
    let presentationMode: RestrictedAppsPresentationMode

    @State private var localSelection: FamilyActivitySelection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        screenTime: ScreenTimeController,
        presentationMode: RestrictedAppsPresentationMode
    ) {
        self.screenTime = screenTime
        self.presentationMode = presentationMode
        _localSelection = State(initialValue: screenTime.selection)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if presentationMode == .firstRun {
                    CheckpointSetupMark(
                        stage: "Choose apps",
                        step: 3,
                        compact: dynamicTypeSize.isAccessibilitySize
                    )

                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Choose your pause points.")
                            .font(.title2.bold())
                            .foregroundStyle(CheckpointTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        Text("Opening one of these apps will start a short, goal-based checkpoint before a timed break.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Choose what Checkpoint should protect.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label(selectionSummary, systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if !localSelection.categoryTokens.isEmpty {
                    Text(categorySelectionDetail)
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
            selectionCountText(localSelection.webDomainTokens.count, singular: "site", plural: "sites")
        ].compactMap { $0 }

        if parts.isEmpty, !localSelection.categoryTokens.isEmpty {
            return "No individual apps selected yet"
        }
        guard !parts.isEmpty else { return "Nothing selected yet" }
        return parts.joined(separator: ", ") + " selected"
    }

    private var categorySelectionDetail: String {
        if localSelection.applicationTokens.isEmpty {
            return "Keep at least one app selected inside the category so Checkpoint has something to protect."
        }
        return "Category shortcuts add their apps to this list. Your individual app changes take precedence."
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
