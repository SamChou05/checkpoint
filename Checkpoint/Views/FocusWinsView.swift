import SwiftUI

struct FocusWinsView: View {
    let store: CheckpointStore
    let goalID: Goal.ID
    let goalTitle: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isDraftFocused: Bool
    @AccessibilityFocusState private var focusedFailure: FocusWinsFailure?

    @State private var draft = ""
    @State private var confirmation: FocusWinsConfirmation?
    @State private var failure: FocusWinsFailure?
    @State private var successFeedbackTrigger = 0
    @State private var errorFeedbackTrigger = 0

    init(store: CheckpointStore, goalID: Goal.ID, goalTitle: String) {
        self.store = store
        self.goalID = goalID
        self.goalTitle = goalTitle
    }

    private var focusWins: [FocusWin] {
        store.focusWins(for: goalID)
    }

    private var dayGroups: [FocusWinsDayGroup] {
        let calendar = Calendar.current
        return Dictionary(grouping: focusWins) {
            calendar.startOfDay(for: $0.loggedAt)
        }
        .map { date, wins in
            FocusWinsDayGroup(
                date: date,
                wins: wins.sorted(by: FocusWinsView.winComesBefore)
            )
        }
        .sorted { $0.date > $1.date }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isOverCharacterLimit: Bool {
        draft.count > CheckpointStore.maximumFocusWinNoteLength
    }

    private var canLogDraft: Bool {
        !trimmedDraft.isEmpty && !isOverCharacterLimit
    }

    private var hasUnsavedDraft: Bool {
        !trimmedDraft.isEmpty
    }

    private var usesStackedLayout: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge ||
            dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    header
                    composer

                    if focusWins.isEmpty {
                        emptyState
                    } else {
                        ledger
                    }

                    storageFootnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
            .checkpointScreenBackground()
            .navigationTitle("Focus Wins")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: requestClose)
                        .foregroundStyle(CheckpointTheme.teal)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        isDraftFocused = false
                    }
                }
            }
            .alert(item: $confirmation, content: confirmationAlert)
            .animation(
                CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                value: focusWins.map(\.id)
            )
            .sensoryFeedback(.success, trigger: successFeedbackTrigger)
            .sensoryFeedback(.error, trigger: errorFeedbackTrigger)
        }
        .interactiveDismissDisabled(hasUnsavedDraft)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)

                Text("PRIVATE NOTES")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
            }
            .foregroundStyle(CheckpointTheme.teal)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Private notes")

            Text(goalTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Keep a private note of progress you noticed toward this goal.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            truthfulnessNote
                .padding(.top, 2)
        }
    }

    private var truthfulnessNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            Text("Focus Wins are logged by you. They don’t affect progress metrics, practice recommendations, questions, or app breaks.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.teal.opacity(0.08),
            in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                .stroke(CheckpointTheme.teal.opacity(0.22), lineWidth: 1)
        }
    }

    private var composer: some View {
        SectionPanel("Log a Focus Win") {
            VStack(alignment: .leading, spacing: 12) {
                Text("What moved forward?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Write it in your own words")
                            .font(.body)
                            .foregroundStyle(CheckpointTheme.muted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 17)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    TextEditor(text: $draft)
                        .font(.body)
                        .foregroundStyle(CheckpointTheme.text)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 156 : 124)
                        .focused($isDraftFocused)
                        .accessibilityLabel("What moved forward?")
                        .accessibilityHint("Write a private note in your own words")
                }
                .background(
                    CheckpointTheme.panelRaised,
                    in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                        .stroke(
                            isOverCharacterLimit ? CheckpointTheme.coral : CheckpointTheme.controlStroke,
                            lineWidth: isOverCharacterLimit ? 1.5 : 1
                        )
                }

                composerStatus

                PrimaryActionButton(title: "Log win", systemImage: "plus") {
                    logFocusWin()
                }
                .disabled(!canLogDraft)
                .accessibilityHint(logButtonAccessibilityHint)

                if failure == .save {
                    FocusWinsFailureMessage(
                        message: "This Focus Win couldn’t be saved. Your draft is still here."
                    )
                    .accessibilityFocused($focusedFailure, equals: .save)
                }
            }
        }
        .onChange(of: draft) { _, _ in
            if failure == .save {
                failure = nil
                focusedFailure = nil
            }
        }
    }

    @ViewBuilder
    private var composerStatus: some View {
        if usesStackedLayout {
            VStack(alignment: .leading, spacing: 5) {
                characterCount
                characterLimitMessage
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                characterLimitMessage

                Spacer(minLength: 8)

                characterCount
            }
        }
    }

    private var characterCount: some View {
        Text("\(draft.count)/\(CheckpointStore.maximumFocusWinNoteLength)")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(isOverCharacterLimit ? CheckpointTheme.coral : CheckpointTheme.muted)
            .accessibilityLabel(characterCountAccessibilityLabel)
    }

    @ViewBuilder
    private var characterLimitMessage: some View {
        if isOverCharacterLimit {
            Text("Use 280 characters or fewer.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.coral)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 52, height: 52)
                .background(CheckpointTheme.teal.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            Text("No Focus Wins yet")
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)
                .accessibilityAddTraits(.isHeader)

            Text("When you notice something move forward, log it here in your own words.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(
            CheckpointTheme.panel.opacity(0.82),
            in: RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        }
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if usesStackedLayout {
                    VStack(alignment: .leading, spacing: 8) {
                        ledgerTitle
                        ledgerCount
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        ledgerTitle

                        Spacer(minLength: 8)

                        ledgerCount
                    }
                }
            }

            if failure == .delete {
                FocusWinsFailureMessage(
                    message: "This Focus Win couldn’t be deleted. It is still in your ledger."
                )
                .accessibilityFocused($focusedFailure, equals: .delete)
            }

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(dayGroups) { group in
                    Text(dayTitle(for: group.date))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckpointTheme.muted)
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .padding(.top, group.id == dayGroups.first?.id ? 0 : 6)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(group.wins) { focusWin in
                        FocusWinRow(
                            focusWin: focusWin,
                            usesStackedLayout: usesStackedLayout
                        ) {
                            isDraftFocused = false
                            failure = nil
                            focusedFailure = nil
                            confirmation = .delete(focusWin)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    private var storageFootnote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "internaldrive")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            Text("Stored with this goal in your local Checkpoint data. Checkpoint keeps the 500 most recent Focus Wins for each goal.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var ledgerTitle: some View {
        Text("Your ledger")
            .font(.title3.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .accessibilityAddTraits(.isHeader)
    }

    private var ledgerCount: some View {
        StatusBadge(text: ledgerCountText, tint: CheckpointTheme.teal)
    }

    private var ledgerCountText: String {
        let count = focusWins.count
        return count == 1 ? "1 win" : "\(count) wins"
    }

    private var logButtonAccessibilityHint: String {
        if trimmedDraft.isEmpty {
            return "Enter a note before logging"
        }
        if isOverCharacterLimit {
            return "Use 280 characters or fewer"
        }
        return "Saves this note with the selected goal in your local Checkpoint data"
    }

    private var characterCountAccessibilityLabel: String {
        let difference = CheckpointStore.maximumFocusWinNoteLength - draft.count
        if difference == 0 {
            return "No characters remaining"
        }
        if difference == 1 {
            return "1 character remaining"
        }
        if difference > 1 {
            return "\(difference) characters remaining"
        }
        if difference == -1 {
            return "1 character over the limit"
        }
        return "\(-difference) characters over the limit"
    }

    private func logFocusWin() {
        guard canLogDraft else { return }

        let wasAtCapacity = focusWins.count >= CheckpointStore.maximumStoredFocusWinCountPerGoal
        let didSave = store.recordFocusWin(note: draft, goalID: goalID)
        guard didSave else {
            failure = .save
            focusedFailure = .save
            errorFeedbackTrigger += 1
            return
        }

        draft = ""
        failure = nil
        focusedFailure = nil
        isDraftFocused = false
        successFeedbackTrigger += 1

        let announcement = wasAtCapacity
            ? "Focus Win logged. Your oldest Focus Win was removed to keep the 500 most recent for this goal."
            : "Focus Win logged."
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func requestClose() {
        isDraftFocused = false
        if hasUnsavedDraft {
            confirmation = .discardDraft
        } else {
            dismiss()
        }
    }

    private func delete(_ focusWin: FocusWin) {
        let didDelete = store.deleteFocusWin(id: focusWin.id, goalID: goalID)
        guard didDelete else {
            failure = .delete
            focusedFailure = .delete
            errorFeedbackTrigger += 1
            return
        }

        failure = nil
        focusedFailure = nil
        successFeedbackTrigger += 1
        AccessibilityNotification.Announcement("Focus Win deleted.").post()
    }

    private func confirmationAlert(_ confirmation: FocusWinsConfirmation) -> Alert {
        switch confirmation {
        case .discardDraft:
            return Alert(
                title: Text("Discard this draft?"),
                message: Text("This Focus Win hasn’t been logged."),
                primaryButton: .destructive(Text("Discard")) {
                    draft = ""
                    failure = nil
                    focusedFailure = nil
                    dismiss()
                },
                secondaryButton: .cancel(Text("Keep writing"))
            )

        case let .delete(focusWin):
            return Alert(
                title: Text("Delete this Focus Win?"),
                message: Text("This removes the note from this goal. It can’t be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    delete(focusWin)
                },
                secondaryButton: .cancel(Text("Cancel"))
            )
        }
    }

    private func dayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    private static func winComesBefore(_ lhs: FocusWin, _ rhs: FocusWin) -> Bool {
        if lhs.loggedAt == rhs.loggedAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.loggedAt > rhs.loggedAt
    }
}

private enum FocusWinsConfirmation: Identifiable {
    case discardDraft
    case delete(FocusWin)

    var id: String {
        switch self {
        case .discardDraft:
            return "discard-draft"
        case let .delete(focusWin):
            return "delete-\(focusWin.id.uuidString)"
        }
    }
}

private enum FocusWinsFailure: Hashable {
    case save
    case delete
}

private struct FocusWinsDayGroup: Identifiable {
    var id: Date { date }
    var date: Date
    var wins: [FocusWin]
}

private struct FocusWinRow: View {
    var focusWin: FocusWin
    var usesStackedLayout: Bool
    var requestDeletion: () -> Void

    var body: some View {
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: 10) {
                    noteAndMetadata

                    HStack {
                        Spacer()
                        actionsMenu
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    noteAndMetadata

                    Spacer(minLength: 4)

                    actionsMenu
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panel.opacity(0.94),
            in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        }
    }

    private var noteAndMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(focusWin.note)
                .font(.body)
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("Logged by you · \(focusWin.loggedAt.formatted(.dateTime.hour().minute()))")
                .font(.caption)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var actionsMenu: some View {
        Menu {
            Button(role: .destructive, action: requestDeletion) {
                Label("Delete Focus Win", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CheckpointTheme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options for Focus Win logged \(fullDateText)")
        .accessibilityHint("Includes an option to delete this note")
    }

    private var rowAccessibilityLabel: String {
        "\(focusWin.note). Logged by you \(fullDateText)"
    }

    private var fullDateText: String {
        focusWin.loggedAt.formatted(
            .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
                .year()
                .hour()
                .minute()
        )
    }
}

private struct FocusWinsFailureMessage: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.coral)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.coral)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.coral.opacity(0.08),
            in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}
