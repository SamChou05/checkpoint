import SwiftUI

struct FeedbackDraftCopy {
    static let localOnlyDetail = "Saving stores a draft in Checkpoint’s local app data. Nothing is sent until you tap Share and choose a destination."
    static let savedDetail = "Draft saved in Checkpoint. Nothing was sent."
    static let emptyMessageDetail = "Describe what happened or what would help before saving."
    static let messageTooLongDetail = "Use 1,000 characters or fewer."
    static let persistenceFailureDetail = "This draft couldn’t be saved. Your text is still here."
    static let retentionDetail = "Checkpoint keeps your 100 most recent feedback drafts."
    static let discardTitle = "Discard this draft?"
    static let discardDetail = "This text hasn’t been saved or shared."
    static let deleteTitle = "Delete this draft?"
    static let deleteDetail = "Removes it from Saved drafts and current app data. A recovery backup may keep the previous copy until a later successful save or Erase all data. Already shared copies are unaffected."
}

enum FeedbackDraftNotice: Equatable {
    case saved
    case emptyMessage
    case messageTooLong
    case persistenceFailure

    init(result: IssueReportDraftSaveResult) {
        switch result {
        case .saved:
            self = .saved
        case .emptyMessage:
            self = .emptyMessage
        case .messageTooLong:
            self = .messageTooLong
        case .notRetained, .persistenceFailed:
            self = .persistenceFailure
        }
    }

    var detail: String {
        switch self {
        case .saved:
            FeedbackDraftCopy.savedDetail
        case .emptyMessage:
            FeedbackDraftCopy.emptyMessageDetail
        case .messageTooLong:
            FeedbackDraftCopy.messageTooLongDetail
        case .persistenceFailure:
            FeedbackDraftCopy.persistenceFailureDetail
        }
    }

    var systemImage: String {
        switch self {
        case .saved:
            "checkmark.circle.fill"
        case .emptyMessage, .messageTooLong:
            "exclamationmark.circle.fill"
        case .persistenceFailure:
            "externaldrive.badge.exclamationmark"
        }
    }

    var tone: FeedbackDraftNoticeTone {
        switch self {
        case .saved:
            .success
        case .emptyMessage, .messageTooLong:
            .warning
        case .persistenceFailure:
            .failure
        }
    }
}

enum FeedbackDraftNoticeTone: Equatable {
    case success
    case warning
    case failure
}

struct FeedbackDraftSettingsPresentation: Equatable {
    var detail: String
    var voiceOverValue: String

    init(count: Int) {
        switch count {
        case 0:
            detail = "Open support or save a local draft"
            voiceOverValue = "No feedback drafts saved in Checkpoint. Nothing is sent automatically."
        case 1:
            detail = "1 local draft"
            voiceOverValue = "1 feedback draft saved in Checkpoint. Nothing is sent automatically."
        default:
            detail = "\(count) local drafts"
            voiceOverValue = "\(count) feedback drafts saved in Checkpoint. Nothing is sent automatically."
        }
    }
}

struct FeedbackDraftComposerPresentation: Equatable {
    var trimmedMessage: String
    var characterCount: Int
    var isEmpty: Bool
    var isTooLong: Bool
    var hasUnsavedDraft: Bool

    init(message: String) {
        trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        characterCount = trimmedMessage.count
        isEmpty = trimmedMessage.isEmpty
        isTooLong = characterCount > CheckpointStore.maximumIssueReportMessageLength
        hasUnsavedDraft = !isEmpty
    }
}

struct FeedbackDraftEditingState: Equatable {
    private(set) var message: String
    private(set) var notice: FeedbackDraftNotice?

    init(message: String = "", notice: FeedbackDraftNotice? = nil) {
        self.message = message
        self.notice = notice
    }

    mutating func userEditedMessage(_ message: String) {
        self.message = message
        notice = nil
    }

    mutating func clearNotice() {
        notice = nil
    }

    mutating func applySaveResult(_ result: IssueReportDraftSaveResult) {
        if result == .saved {
            message = ""
        }
        notice = FeedbackDraftNotice(result: result)
    }
}

struct FeedbackDraftRowPresentation: Equatable {
    var category: String
    var savedAt: String
    var message: String
    var goalContext: String?
    var shareText: String
    var shareAccessibilityLabel: String
    var deleteAccessibilityLabel: String

    init(report: UserIssueReport, position: Int? = nil) {
        category = report.category.rawValue
        savedAt = report.createdAt.formatted(date: .abbreviated, time: .shortened)
        message = report.message

        let trimmedGoalTitle = report.goalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let includesGoal = report.includesGoalContext == true
            && report.goalID != nil
            && !trimmedGoalTitle.isEmpty
            && trimmedGoalTitle != "No goal"
        goalContext = includesGoal ? "Goal: \(trimmedGoalTitle)" : nil

        var lines = [
            "Checkpoint feedback draft",
            "Category: \(report.category.rawValue)",
            "Saved: \(savedAt)"
        ]
        if let goalContext {
            lines.append(goalContext)
        }
        lines.append("")
        lines.append(report.message)
        shareText = lines.joined(separator: "\n")

        let draftIdentity = if let position {
            "feedback draft \(position), \(report.category.rawValue), saved \(savedAt)"
        } else {
            "\(report.category.rawValue) draft from \(savedAt)"
        }
        shareAccessibilityLabel = "Share \(draftIdentity)"
        deleteAccessibilityLabel = "Delete \(draftIdentity)"
    }
}

struct QuestionReportsView: View {
    let store: CheckpointStore
    let legalLinks: LegalLinks

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var category: IssueReportCategory
    @State private var editingState: FeedbackDraftEditingState
    @State private var includesCurrentGoal: Bool
    @State private var pendingDeleteReport: UserIssueReport?
    @State private var isDeleteConfirmationPresented = false
    @State private var isDiscardConfirmationPresented = false
    @State private var deletionFailureMessage: String?
    @State private var successFeedbackSequence = 0
    @AccessibilityFocusState private var isNoticeFocused: Bool

    init(
        store: CheckpointStore,
        legalLinks: LegalLinks = .current,
        initialCategory: IssueReportCategory = .generalFeedback,
        initialMessage: String = "",
        initiallyIncludesCurrentGoal: Bool = false,
        initialNotice: FeedbackDraftNotice? = nil
    ) {
        self.store = store
        self.legalLinks = legalLinks
        _category = State(initialValue: initialCategory)
        _editingState = State(
            initialValue: FeedbackDraftEditingState(
                message: initialMessage,
                notice: initialNotice
            )
        )
        _includesCurrentGoal = State(initialValue: initiallyIncludesCurrentGoal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    supportPanel
                    composerPanel
                    savedDraftsPanel
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .checkpointScreenBackground()
            .navigationTitle("Support & Feedback")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        attemptClose()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
        }
        .interactiveDismissDisabled(hasUnsavedDraft)
        .alert(FeedbackDraftCopy.discardTitle, isPresented: $isDiscardConfirmationPresented) {
            Button("Discard", role: .destructive) {
                dismiss()
            }
            Button("Keep writing", role: .cancel) {}
        } message: {
            Text(FeedbackDraftCopy.discardDetail)
        }
        .confirmationDialog(
            FeedbackDraftCopy.deleteTitle,
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete draft", role: .destructive) {
                deletePendingDraft()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteReport = nil
            }
        } message: {
            Text(FeedbackDraftCopy.deleteDetail)
        }
        .alert("Couldn’t delete draft", isPresented: deletionFailureBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionFailureMessage ?? "Try again after checking available device storage.")
        }
        .sensoryFeedback(.success, trigger: successFeedbackSequence)
        .onChange(of: category) { _, _ in
            if hasUnsavedDraft {
                editingState.clearNotice()
            }
        }
        .onChange(of: includesCurrentGoal) { _, _ in
            if hasUnsavedDraft {
                editingState.clearNotice()
            }
        }
        .onChange(of: store.goal?.id) { oldGoalID, newGoalID in
            if oldGoalID != newGoalID {
                includesCurrentGoal = false
            }
        }
    }

    private var supportPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "lifepreserver.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.ink)
                    .frame(width: 46, height: 46)
                    .background(CheckpointTheme.mint, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Need help now?")
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.heroText)

                    Text("Open the Checkpoint support page for account, billing, or troubleshooting help.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let supportURL = legalLinks.supportURL {
                Button {
                    openURL(supportURL)
                } label: {
                    Label("Open support", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CheckpointTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            CheckpointTheme.mint,
                            in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius)
                        )
                }
                .buttonStyle(CheckpointPressButtonStyle())
                .accessibilityHint("Opens the configured support page")
            } else {
                Label("Support isn’t available in this build.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.heroWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
                .fill(CheckpointTheme.ink)
                .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
        )
        .shadow(color: CheckpointTheme.shadowCard, radius: 12, y: 5)
    }

    private var composerPanel: some View {
        SectionPanel("New feedback draft") {
            VStack(alignment: .leading, spacing: 14) {
                localOnlyDisclosure
                categoryPicker
                messageEditor

                if let goal = store.goal {
                    goalContextToggle(goal)
                }

                PrimaryActionButton(title: "Save draft", systemImage: "square.and.arrow.down") {
                    saveDraft()
                }
                .disabled(isMessageEmpty || isMessageTooLong)

                if let notice = editingState.notice {
                    noticeView(notice)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(
                CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                value: editingState.notice
            )
        }
    }

    private var localOnlyDisclosure: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lock.shield")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 34, height: 34)
                .background(CheckpointTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Local until you share")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                Text(FeedbackDraftCopy.localOnlyDetail)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("What is this about?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)

            Picker("What is this about?", selection: $category) {
                ForEach(IssueReportCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(CheckpointTheme.teal)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 12)
            .background(
                CheckpointTheme.panelRaised,
                in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius)
                    .stroke(CheckpointTheme.hairline, lineWidth: 1)
            }
            .accessibilityLabel("What is this about?")
            .accessibilityValue(category.rawValue)
        }
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField(
                "Describe what happened or what would help.",
                text: messageBinding,
                axis: .vertical
            )
            .lineLimit(5, reservesSpace: true)
            .textFieldStyle(.plain)
            .foregroundStyle(CheckpointTheme.text)
            .padding(12)
            .background(
                CheckpointTheme.panelRaised,
                in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius)
                    .stroke(
                        isMessageTooLong ? CheckpointTheme.coral : CheckpointTheme.hairline,
                        lineWidth: 1
                    )
            }
            .accessibilityHint("Checkpoint does not send this draft. Share opens the system share sheet")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if isMessageTooLong {
                    Label(FeedbackDraftCopy.messageTooLongDetail, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(CheckpointTheme.coral)
                        .accessibilityFocused($isNoticeFocused)
                } else {
                    Text("Drafts can be up to 1,000 characters.")
                        .foregroundStyle(CheckpointTheme.muted)
                }

                Spacer(minLength: 8)

                Text("\(trimmedMessageCount) / \(CheckpointStore.maximumIssueReportMessageLength)")
                    .foregroundStyle(isMessageTooLong ? CheckpointTheme.coral : CheckpointTheme.muted)
                    .monospacedDigit()
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func goalContextToggle(_ goal: Goal) -> some View {
        Toggle(isOn: $includesCurrentGoal) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Include current goal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                Text("Adds “\(goal.title)” to the saved and shared draft.")
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(CheckpointTheme.teal)
        .padding(12)
        .background(
            CheckpointTheme.panelRaised.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func noticeView(_ notice: FeedbackDraftNotice) -> some View {
        Label(notice.detail, systemImage: notice.systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(noticeTint(notice.tone))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityFocused($isNoticeFocused)
    }

    private var savedDraftsPanel: some View {
        SectionPanel("Saved drafts") {
            if store.issueReportDrafts.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                        .frame(width: 38, height: 38)
                        .background(CheckpointTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("No drafts yet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Drafts you save will appear here with Share and Delete controls.")
                            .font(.caption)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(store.issueReportDrafts.enumerated()), id: \.element.id) { index, report in
                        FeedbackDraftRow(report: report, position: index + 1) {
                            pendingDeleteReport = report
                            isDeleteConfirmationPresented = true
                        }
                        .transition(draftRowTransition)
                    }
                }

                Divider()
                    .overlay(CheckpointTheme.hairline)

                Label(FeedbackDraftCopy.retentionDetail, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var composerPresentation: FeedbackDraftComposerPresentation {
        FeedbackDraftComposerPresentation(message: editingState.message)
    }

    private var messageBinding: Binding<String> {
        Binding(
            get: { editingState.message },
            set: { editingState.userEditedMessage($0) }
        )
    }

    private var trimmedMessageCount: Int {
        composerPresentation.characterCount
    }

    private var isMessageEmpty: Bool {
        composerPresentation.isEmpty
    }

    private var isMessageTooLong: Bool {
        composerPresentation.isTooLong
    }

    private var hasUnsavedDraft: Bool {
        composerPresentation.hasUnsavedDraft
    }

    private var draftRowTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    private var deletionFailureBinding: Binding<Bool> {
        Binding(
            get: { deletionFailureMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deletionFailureMessage = nil
                }
            }
        )
    }

    private func noticeTint(_ tone: FeedbackDraftNoticeTone) -> Color {
        switch tone {
        case .success:
            CheckpointTheme.teal
        case .warning:
            CheckpointTheme.amber
        case .failure:
            CheckpointTheme.coral
        }
    }

    private func saveDraft() {
        let result = withAnimation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)
        ) {
            store.saveIssueReportDraft(
                category: category,
                message: editingState.message,
                includesCurrentGoal: includesCurrentGoal
            )
        }
        editingState.applySaveResult(result)

        if result == .saved {
            category = .generalFeedback
            includesCurrentGoal = false
            successFeedbackSequence += 1
        }
        focusNotice()
    }

    private func deletePendingDraft() {
        guard let pendingDeleteReport else { return }

        let didDelete = withAnimation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)
        ) {
            store.deleteIssueReportDraft(id: pendingDeleteReport.id)
        }
        self.pendingDeleteReport = nil

        if didDelete {
            successFeedbackSequence += 1
        } else {
            deletionFailureMessage = "This draft couldn’t be deleted. Check available device storage and try again."
        }
    }

    private func attemptClose() {
        if hasUnsavedDraft {
            isDiscardConfirmationPresented = true
        } else {
            dismiss()
        }
    }

    private func focusNotice() {
        Task { @MainActor in
            await Task.yield()
            isNoticeFocused = true
        }
    }
}

private struct FeedbackDraftRow: View {
    var report: UserIssueReport
    var position: Int
    var delete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let presentation = FeedbackDraftRowPresentation(report: report, position: position)

        VStack(alignment: .leading, spacing: 11) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 7) {
                        StatusBadge(text: presentation.category, tint: CheckpointTheme.amber)
                        savedAtLabel(presentation.savedAt)
                    }
                } else {
                    HStack(spacing: 8) {
                        StatusBadge(text: presentation.category, tint: CheckpointTheme.amber)
                        Spacer(minLength: 8)
                        savedAtLabel(presentation.savedAt)
                    }
                }
            }

            if let goalContext = presentation.goalContext {
                Label(goalContext, systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(presentation.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(CheckpointTheme.hairline)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        shareControl(presentation)
                        deleteControl(presentation)
                    }
                } else {
                    HStack(spacing: 8) {
                        shareControl(presentation)
                        deleteControl(presentation)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        }
    }

    private func savedAtLabel(_ savedAt: String) -> some View {
        Label(savedAt, systemImage: "clock")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shareControl(_ presentation: FeedbackDraftRowPresentation) -> some View {
        ShareLink(item: presentation.shareText) {
            draftActionLabel(
                title: "Share",
                systemImage: "square.and.arrow.up",
                tint: CheckpointTheme.teal
            )
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .accessibilityLabel(presentation.shareAccessibilityLabel)
        .accessibilityHint("Opens the system share sheet. Nothing is sent until you choose a destination")
    }

    private func deleteControl(_ presentation: FeedbackDraftRowPresentation) -> some View {
        Button(role: .destructive, action: delete) {
            draftActionLabel(
                title: "Delete",
                systemImage: "trash",
                tint: CheckpointTheme.coral
            )
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .accessibilityLabel(presentation.deleteAccessibilityLabel)
    }

    private func draftActionLabel(
        title: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                CheckpointTheme.panel.opacity(0.70),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
    }
}
