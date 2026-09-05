import SwiftUI

struct FocusWinsWeekDayPresentation: Identifiable, Equatable {
    let id: Date
    let label: String
    let winCount: Int
    let isToday: Bool
    let isFuture: Bool

    var hasWins: Bool {
        winCount > 0
    }
}

struct FocusWinsWeeklySnapshotPresentation: Equatable {
    let days: [FocusWinsWeekDayPresentation]
    let winCount: Int
    let activeDayCount: Int
    let headline: String
    let detail: String
    let badgeText: String
    let accessibilityValue: String

    var hasWins: Bool {
        winCount > 0
    }

    init(
        focusWins: [FocusWin],
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) {
        var calendar = calendar
        calendar.timeZone = timeZone
        let privacyBoundary = "Based only on private notes you log. Focus Wins never affect progress scores, practice recommendations, questions, or app breaks."
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let weekStart = calendar.dateInterval(
            of: .weekOfYear,
            for: referenceDate
        )?.start ?? referenceDay
        let weekEnd = calendar.date(
            byAdding: .day,
            value: 7,
            to: weekStart
        ) ?? weekStart.addingTimeInterval(7 * 86_400)
        let dateLabelFormatter = WeeklyReviewDateLabelFormatter(
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        let winsThisWeek = focusWins.filter { focusWin in
            let loggedDay = calendar.startOfDay(for: focusWin.loggedAt)
            return focusWin.loggedAt >= weekStart &&
                focusWin.loggedAt < weekEnd &&
                loggedDay <= referenceDay
        }
        let winsByDay = Dictionary(grouping: winsThisWeek) {
            calendar.startOfDay(for: $0.loggedAt)
        }

        days = (0..<7).map { offset in
            let date = calendar.date(
                byAdding: .day,
                value: offset,
                to: weekStart
            ) ?? weekStart.addingTimeInterval(Double(offset) * 86_400)
            let normalizedDate = calendar.startOfDay(for: date)
            return FocusWinsWeekDayPresentation(
                id: normalizedDate,
                label: dateLabelFormatter
                    .narrowWeekday(for: normalizedDate)
                    .uppercased(with: locale),
                winCount: winsByDay[normalizedDate]?.count ?? 0,
                isToday: normalizedDate == referenceDay,
                isFuture: normalizedDate > referenceDay
            )
        }

        winCount = winsThisWeek.count
        activeDayCount = winsByDay.count

        switch winCount {
        case 0:
            headline = "Your week is ready"
            detail = "Capture the small proof that your work is moving."
            badgeText = "PRIVATE"
            accessibilityValue = "No Focus Wins logged this week. \(privacyBoundary)"

        case 1:
            headline = "1 win this week"
            detail = "Captured on one day, in your own words."
            badgeText = "1 DAY"
            let activeDay = days.first(where: \.hasWins)
            let dayDetail = activeDay.map {
                dateLabelFormatter.wideWeekday(for: $0.id)
            } ?? "one day"
            accessibilityValue = "1 Focus Win logged this week on \(dayDetail). \(privacyBoundary)"

        default:
            headline = "\(winCount) wins this week"
            let dayNoun = activeDayCount == 1 ? "day" : "days"
            detail = "Captured across \(activeDayCount) \(dayNoun), in your own words."
            badgeText = "\(activeDayCount) \(dayNoun.uppercased())"
            let activeDayDetails = days.compactMap { day -> String? in
                guard day.hasWins else { return nil }
                let noun = day.winCount == 1 ? "win" : "wins"
                return "\(dateLabelFormatter.wideWeekday(for: day.id)), \(day.winCount) \(noun)"
            }
            accessibilityValue = "\(winCount) Focus Wins across \(activeDayCount) \(dayNoun) this week. "
                + activeDayDetails.joined(separator: "; ")
                + ". \(privacyBoundary)"
        }
    }
}

struct FocusWinsComposerPolicy {
    static func startsExpanded(
        focusWinCount: Int,
        override: Bool?
    ) -> Bool {
        override ?? (focusWinCount == 0)
    }
}

enum FocusWinsMutationMotionStyle: Equatable {
    case spatial
    case tonalOnly
}

struct FocusWinsMutationMotionPolicy {
    let style: FocusWinsMutationMotionStyle

    init(
        reduceMotion: Bool,
        voiceOverEnabled: Bool,
        switchControlEnabled: Bool
    ) {
        style = reduceMotion || voiceOverEnabled || switchControlEnabled
            ? .tonalOnly
            : .spatial
    }

    var mutationAnimation: Animation? {
        style == .spatial ? CheckpointMotion.reveal : nil
    }

    var confirmationDismissAnimation: Animation? {
        style == .spatial ? CheckpointMotion.change : nil
    }

    var mutationTransaction: Transaction {
        transaction(animation: mutationAnimation)
    }

    var confirmationDismissTransaction: Transaction {
        transaction(animation: confirmationDismissAnimation)
    }

    var scrollTransaction: Transaction {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        return transaction
    }

    var usesSpatialTransitions: Bool {
        style == .spatial
    }

    var animatesSymbolEffects: Bool {
        style == .spatial
    }

    var showsTonalConfirmation: Bool {
        celebrationBackgroundOpacity > 0 && celebrationBorderOpacity > 0
    }

    var celebrationBackgroundOpacity: Double {
        0.10
    }

    var celebrationBorderOpacity: Double {
        0.72
    }

    var celebrationShadowOpacity: Double {
        style == .spatial ? 0.13 : 0
    }

    var composerTransition: AnyTransition {
        style == .spatial
            ? .opacity.combined(with: .move(edge: .top))
            : .identity
    }

    var rowTransition: AnyTransition {
        switch style {
        case .spatial:
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            )
        case .tonalOnly:
            .identity
        }
    }

    private func transaction(animation: Animation?) -> Transaction {
        var transaction = Transaction(animation: animation)
        transaction.disablesAnimations = style == .tonalOnly
        return transaction
    }
}

enum FocusWinsPostDeleteFocusTarget: Equatable {
    case composer
    case composerLauncher
    case ledgerTitle
}

struct FocusWinsPostDeleteFocusPolicy {
    static func target(
        remainingWinCount: Int,
        isComposerExpanded: Bool
    ) -> FocusWinsPostDeleteFocusTarget {
        if remainingWinCount > 0 {
            return .ledgerTitle
        }
        return isComposerExpanded ? .composer : .composerLauncher
    }
}

struct FocusWinsEntryPresentation: Equatable {
    let detail: String
    let trailingText: String
    let accessibilityValue: String

    init(
        focusWins: [FocusWin],
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) {
        var calendar = calendar
        calendar.timeZone = timeZone
        let weeklySnapshot = FocusWinsWeeklySnapshotPresentation(
            focusWins: focusWins,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let totalCount = focusWins.count

        guard let latestWin = focusWins.max(by: { $0.loggedAt < $1.loggedAt }) else {
            detail = "Start a private record of progress you noticed."
            trailingText = "No notes"
            accessibilityValue = "No entries logged by you. Opens a private reflection ledger."
            return
        }

        let latestText = Self.recencyText(
            for: latestWin.loggedAt,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        if weeklySnapshot.winCount == 0 {
            detail = "Your private reflection ledger · Latest \(latestText)"
        } else {
            let noun = weeklySnapshot.winCount == 1 ? "reflection" : "reflections"
            detail = "\(weeklySnapshot.winCount) \(noun) this week · Latest \(latestText)"
        }
        trailingText = totalCount == 1 ? "1 total" : "\(totalCount) total"

        let entryNoun = totalCount == 1 ? "entry" : "entries"
        let weeklyNoun = weeklySnapshot.winCount == 1 ? "entry" : "entries"
        accessibilityValue = "\(totalCount) \(entryNoun) logged by you. "
            + "\(weeklySnapshot.winCount) \(weeklyNoun) this week. "
            + "Latest logged \(latestText)."
    }

    private static func recencyText(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let dateDay = calendar.startOfDay(for: date)
        if dateDay == referenceDay {
            return "today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDay),
           dateDay == calendar.startOfDay(for: yesterday) {
            return "yesterday"
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        let includesYear = calendar.component(.year, from: date)
            != calendar.component(.year, from: referenceDate)
        formatter.setLocalizedDateFormatFromTemplate(includesYear ? "MMMdyyyy" : "MMMd")
        return formatter.string(from: date)
    }
}

struct FocusWinsView: View {
    let store: CheckpointStore
    let goalID: Goal.ID
    let goalTitle: String
    private let reduceMotionOverride: Bool?
    private let referenceDateOverride: Date?
    private let calendar: Calendar
    private let locale: Locale
    private let timeZone: TimeZone

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isDraftFocused: Bool
    @AccessibilityFocusState(for: [.voiceOver, .switchControl])
    private var isComposerAccessibilityFocused: Bool
    @AccessibilityFocusState(for: [.voiceOver, .switchControl])
    private var postMutationAccessibilityFocus: FocusWinsPostMutationAccessibilityFocus?
    @AccessibilityFocusState private var focusedFailure: FocusWinsFailure?

    @State private var draft: String
    @State private var isComposerExpanded: Bool
    @State private var confirmation: FocusWinsConfirmation?
    @State private var failure: FocusWinsFailure?
    @State private var successFeedbackTrigger = 0
    @State private var celebrationFeedbackSequence = 0
    @State private var deletionFeedbackTrigger = 0
    @State private var errorFeedbackTrigger = 0
    @State private var celebratedWinID: FocusWin.ID?
    @State private var celebrationRequestID: UUID?
    @State private var celebrationDismissalReadyID: UUID?
    @State private var celebrationTask: Task<Void, Never>?
    @State private var revealRequest: FocusWinRevealRequest?
    @State private var focusedWinID: FocusWin.ID?
    @State private var winAccessibilityFocusRequestID: UUID?

    init(
        store: CheckpointStore,
        goalID: Goal.ID,
        goalTitle: String,
        reduceMotionOverride: Bool? = nil,
        referenceDate: Date? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        initialDraft: String = "",
        initiallyComposerExpanded: Bool? = nil
    ) {
        self.store = store
        self.goalID = goalID
        self.goalTitle = goalTitle
        self.reduceMotionOverride = reduceMotionOverride
        referenceDateOverride = referenceDate
        var resolvedCalendar = calendar
        resolvedCalendar.timeZone = timeZone
        self.calendar = resolvedCalendar
        self.locale = locale
        self.timeZone = timeZone
        _draft = State(initialValue: initialDraft)
        _isComposerExpanded = State(
            initialValue: FocusWinsComposerPolicy.startsExpanded(
                focusWinCount: store.focusWins(for: goalID).count,
                override: initiallyComposerExpanded
            )
        )
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var mutationMotionPolicy: FocusWinsMutationMotionPolicy {
        FocusWinsMutationMotionPolicy(
            reduceMotion: reduceMotion,
            voiceOverEnabled: voiceOverEnabled,
            switchControlEnabled: switchControlEnabled
        )
    }

    private var referenceDate: Date {
        referenceDateOverride ?? Date()
    }

    private var focusWins: [FocusWin] {
        store.focusWins(for: goalID)
    }

    private var dayGroups: [FocusWinsDayGroup] {
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

    private var weeklySnapshotPresentation: FocusWinsWeeklySnapshotPresentation {
        FocusWinsWeeklySnapshotPresentation(
            focusWins: focusWins,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                        weeklySnapshot

                        if isComposerExpanded {
                            composer
                                .transition(mutationMotionPolicy.composerTransition)
                        } else {
                            composerLauncher
                                .transition(mutationMotionPolicy.composerTransition)
                        }

                        if !focusWins.isEmpty {
                            ledger
                        }

                        storageFootnote
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: revealRequest) { _, request in
                    reveal(request, with: proxy)
                }
            }
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
            .sensoryFeedback(.success, trigger: successFeedbackTrigger)
            .sensoryFeedback(.success, trigger: deletionFeedbackTrigger)
            .sensoryFeedback(.error, trigger: errorFeedbackTrigger)
        }
        .interactiveDismissDisabled(hasUnsavedDraft)
        .onChange(of: celebrationDismissalReadyID) { _, requestID in
            completeCelebrationDismissal(requestID)
        }
        .onDisappear {
            celebrationTask?.cancel()
            celebrationTask = nil
            celebrationRequestID = nil
            celebrationDismissalReadyID = nil
            revealRequest = nil
        }
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
        }
    }

    private var weeklySnapshot: some View {
        FocusWinsWeeklySnapshotCard(
            presentation: weeklySnapshotPresentation,
            motionPolicy: mutationMotionPolicy
        )
    }

    private var composer: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LOG A FOCUS WIN")
                            .font(.caption2.weight(.bold))
                            .tracking(0.9)
                            .foregroundStyle(CheckpointTheme.teal)

                        Text("What moved forward?")
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                    }
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 8)

                    Button(action: requestComposerCollapse) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CheckpointTheme.muted)
                            .frame(width: 44, height: 44)
                            .background(
                                CheckpointTheme.panelRaised,
                                in: Circle()
                            )
                    }
                    .buttonStyle(CheckpointPressButtonStyle())
                    .accessibilityLabel("Close win composer")
                    .accessibilityHint(
                        hasUnsavedDraft
                            ? "Asks before discarding your draft"
                            : "Returns to your Focus Wins"
                    )
                }

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
                        .accessibilityFocused($isComposerAccessibilityFocused)
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

    private var composerLauncher: some View {
        Button(action: expandComposer) {
            SectionPanel {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        composerLauncherIcon
                        composerLauncherCopy
                        composerLauncherAccessory
                    }
                } else {
                    HStack(spacing: 14) {
                        composerLauncherIcon
                        composerLauncherCopy
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CheckpointTheme.teal)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(CheckpointPressButtonStyle(role: .surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(composerLauncherAccessibilityLabel)
        .accessibilityHint("Opens a private note editor")
        .accessibilityFocused(
            $postMutationAccessibilityFocus,
            equals: .composerLauncher
        )
    }

    private var composerLauncherIcon: some View {
        Image(systemName: "plus")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(CheckpointTheme.heroText)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(
                    colors: [CheckpointTheme.actionTeal, CheckpointTheme.actionDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var composerLauncherCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(
                focusWins.isEmpty
                    ? "Capture your first win"
                    : "Capture another win"
            )
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)

            Text(
                focusWins.isEmpty
                    ? "Start your private reflection ledger."
                    : "Add the moment while it’s fresh."
            )
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composerLauncherAccessibilityLabel: String {
        focusWins.isEmpty
            ? "Log your first Focus Win"
            : "Log another Focus Win"
    }

    private var composerLauncherAccessory: some View {
        HStack(spacing: 5) {
            Text("Write")
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(CheckpointTheme.teal)
        .accessibilityHidden(true)
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
                            usesStackedLayout: usesStackedLayout,
                            isCelebrated: focusWin.id == celebratedWinID,
                            celebrationSequence: celebrationFeedbackSequence,
                            accessibilityFocusRequestID: focusedWinID == focusWin.id
                                ? winAccessibilityFocusRequestID
                                : nil,
                            motionPolicy: mutationMotionPolicy,
                            calendar: calendar,
                            locale: locale,
                            timeZone: timeZone,
                            consumeAccessibilityFocusRequest: { requestID in
                                consumeAccessibilityFocusRequest(
                                    requestID,
                                    for: focusWin.id
                                )
                            },
                            requestDeletion: {
                                isDraftFocused = false
                                failure = nil
                                focusedFailure = nil
                                confirmation = .delete(focusWin)
                            }
                        )
                        .id(focusWin.id)
                        .transition(mutationMotionPolicy.rowTransition)
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
            .accessibilityFocused(
                $postMutationAccessibilityFocus,
                equals: .ledgerTitle
            )
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

        let previousWinIDs = Set(focusWins.map(\.id))
        let wasAtCapacity = focusWins.count >= CheckpointStore.maximumStoredFocusWinCountPerGoal
        var loggedWin: FocusWin?
        let didSave = withTransaction(mutationMotionPolicy.mutationTransaction) {
            guard store.recordFocusWin(note: draft, goalID: goalID) else {
                return false
            }

            loggedWin = focusWins.first(where: { !previousWinIDs.contains($0.id) })
                ?? focusWins.first
            draft = ""
            failure = nil
            focusedFailure = nil
            isDraftFocused = false
            isComposerAccessibilityFocused = false
            postMutationAccessibilityFocus = nil
            isComposerExpanded = false
            celebratedWinID = loggedWin?.id
            return true
        }
        guard didSave else {
            failure = .save
            focusedFailure = .save
            errorFeedbackTrigger += 1
            return
        }

        successFeedbackTrigger += 1
        if let loggedWin {
            requestReveal(of: loggedWin.id)
            scheduleCelebrationDismissal(for: loggedWin.id)
        }

        let announcement = wasAtCapacity
            ? "Focus Win logged. Your oldest Focus Win was removed to keep the 500 most recent for this goal."
            : "Focus Win logged."
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func requestClose() {
        isDraftFocused = false
        if hasUnsavedDraft {
            confirmation = .discardDraftAndDismiss
        } else {
            dismiss()
        }
    }

    private func expandComposer() {
        withTransaction(mutationMotionPolicy.mutationTransaction) {
            failure = nil
            focusedFailure = nil
            postMutationAccessibilityFocus = nil
            isComposerExpanded = true
        }

        Task { @MainActor in
            await Task.yield()
            guard isComposerExpanded else { return }
            isDraftFocused = true
            isComposerAccessibilityFocused = true
        }
    }

    private func requestComposerCollapse() {
        isDraftFocused = false
        isComposerAccessibilityFocused = false
        if hasUnsavedDraft {
            confirmation = .discardDraftAndCollapse
        } else {
            collapseComposer()
        }
    }

    private func collapseComposer() {
        withTransaction(mutationMotionPolicy.mutationTransaction) {
            failure = nil
            focusedFailure = nil
            isComposerExpanded = false
        }
    }

    private func requestReveal(of focusWinID: FocusWin.ID) {
        focusedWinID = nil
        winAccessibilityFocusRequestID = nil
        revealRequest = FocusWinRevealRequest(focusWinID: focusWinID)
    }

    private func consumeAccessibilityFocusRequest(
        _ requestID: UUID,
        for focusWinID: FocusWin.ID
    ) {
        guard focusedWinID == focusWinID,
              winAccessibilityFocusRequestID == requestID else { return }

        focusedWinID = nil
        winAccessibilityFocusRequestID = nil
    }

    private func reveal(
        _ request: FocusWinRevealRequest?,
        with proxy: ScrollViewProxy
    ) {
        guard let request else { return }

        Task { @MainActor in
            await Task.yield()
            guard revealRequest == request else { return }

            withTransaction(mutationMotionPolicy.scrollTransaction) {
                proxy.scrollTo(request.focusWinID, anchor: .center)
            }

            guard revealRequest == request else { return }
            if voiceOverEnabled || switchControlEnabled {
                focusedWinID = request.focusWinID
                winAccessibilityFocusRequestID = UUID()
            }
            if mutationMotionPolicy.animatesSymbolEffects,
               celebratedWinID == request.focusWinID {
                celebrationFeedbackSequence += 1
            }
            revealRequest = nil
        }
    }

    private func scheduleCelebrationDismissal(for focusWinID: FocusWin.ID) {
        celebrationTask?.cancel()
        let requestID = UUID()
        celebrationRequestID = requestID
        celebrationDismissalReadyID = nil

        celebrationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled,
                  celebrationRequestID == requestID,
                  celebratedWinID == focusWinID else { return }
            celebrationDismissalReadyID = requestID
        }
    }

    private func completeCelebrationDismissal(_ requestID: UUID?) {
        guard let requestID,
              celebrationRequestID == requestID else { return }

        withTransaction(mutationMotionPolicy.confirmationDismissTransaction) {
            celebratedWinID = nil
        }
        guard celebrationRequestID == requestID else { return }
        celebrationRequestID = nil
        celebrationDismissalReadyID = nil
        celebrationTask = nil
    }

    private func delete(_ focusWin: FocusWin) {
        let didDelete = withTransaction(mutationMotionPolicy.mutationTransaction) {
            guard store.deleteFocusWin(id: focusWin.id, goalID: goalID) else {
                return false
            }

            failure = nil
            focusedFailure = nil
            if celebratedWinID == focusWin.id {
                celebrationTask?.cancel()
                celebrationTask = nil
                celebrationRequestID = nil
                celebrationDismissalReadyID = nil
                celebratedWinID = nil
            }
            if focusedWinID == focusWin.id {
                focusedWinID = nil
                winAccessibilityFocusRequestID = nil
            }
            return true
        }
        guard didDelete else {
            failure = .delete
            focusedFailure = .delete
            errorFeedbackTrigger += 1
            return
        }

        deletionFeedbackTrigger += 1
        AccessibilityNotification.Announcement("Focus Win deleted.").post()
        Task { @MainActor in
            await Task.yield()
            switch FocusWinsPostDeleteFocusPolicy.target(
                remainingWinCount: focusWins.count,
                isComposerExpanded: isComposerExpanded
            ) {
            case .composer:
                isComposerAccessibilityFocused = true
                postMutationAccessibilityFocus = nil
            case .composerLauncher:
                postMutationAccessibilityFocus = .composerLauncher
            case .ledgerTitle:
                postMutationAccessibilityFocus = .ledgerTitle
            }
        }
    }

    private func confirmationAlert(_ confirmation: FocusWinsConfirmation) -> Alert {
        switch confirmation {
        case .discardDraftAndDismiss:
            return Alert(
                title: Text("Discard this draft?"),
                message: Text("This Focus Win hasn’t been logged."),
                primaryButton: .destructive(Text("Discard")) {
                    draft = ""
                    failure = nil
                    focusedFailure = nil
                    dismiss()
                },
                secondaryButton: .cancel(Text("Keep writing")) {
                    Task { @MainActor in
                        await Task.yield()
                        guard isComposerExpanded else { return }
                        isDraftFocused = true
                        isComposerAccessibilityFocused = true
                    }
                }
            )

        case .discardDraftAndCollapse:
            return Alert(
                title: Text("Discard this draft?"),
                message: Text("This Focus Win hasn’t been logged."),
                primaryButton: .destructive(Text("Discard")) {
                    draft = ""
                    failure = nil
                    focusedFailure = nil
                    collapseComposer()
                },
                secondaryButton: .cancel(Text("Keep writing")) {
                    Task { @MainActor in
                        await Task.yield()
                        guard isComposerExpanded else { return }
                        isDraftFocused = true
                        isComposerAccessibilityFocused = true
                    }
                }
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
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let dateDay = calendar.startOfDay(for: date)
        if dateDay == referenceDay {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDay),
           dateDay == calendar.startOfDay(for: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        let includesYear = calendar.component(.year, from: date)
            != calendar.component(.year, from: referenceDate)
        formatter.setLocalizedDateFormatFromTemplate(includesYear ? "EEEEMMMdy" : "EEEEMMMd")
        return formatter.string(from: date)
    }

    private static func winComesBefore(_ lhs: FocusWin, _ rhs: FocusWin) -> Bool {
        if lhs.loggedAt == rhs.loggedAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.loggedAt > rhs.loggedAt
    }
}

private struct FocusWinsWeeklySnapshotCard: View {
    let presentation: FocusWinsWeeklySnapshotPresentation
    let motionPolicy: FocusWinsMutationMotionPolicy

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            snapshotHeader
            weekRail

            Divider()
                .overlay(CheckpointTheme.heroDivider)

            privacyBoundary
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CheckpointTheme.ink)
                .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(CheckpointTheme.heroSuccess.opacity(0.09))
                        .frame(width: 160, height: 160)
                        .blur(radius: 12)
                        .offset(x: 72, y: -92)
                        .allowsHitTesting(false)
                }
        )
        .shadow(color: CheckpointTheme.shadowElevated, radius: 18, y: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your Focus Wins this week")
        .accessibilityValue(presentation.accessibilityValue)
    }

    @ViewBuilder
    private var snapshotHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                snapshotIcon
                snapshotCopy
                snapshotBadge
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    snapshotIdentity
                    Spacer(minLength: 8)
                    snapshotBadge
                }
                .frame(minWidth: 300, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        snapshotIcon
                        Spacer(minLength: 8)
                        snapshotBadge
                    }

                    snapshotCopy
                }
            }
        }
    }

    private var snapshotIdentity: some View {
        HStack(alignment: .top, spacing: 12) {
            snapshotIcon
            snapshotCopy
        }
    }

    private var snapshotIcon: some View {
        Image(systemName: presentation.hasWins ? "checkmark.seal.fill" : "sparkles")
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 21, weight: .bold))
            .foregroundStyle(CheckpointTheme.heroSuccess)
            .frame(width: 44, height: 44)
            .background(CheckpointTheme.heroSubtleFill, in: RoundedRectangle(cornerRadius: 13))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffectsRemoved(!motionPolicy.animatesSymbolEffects)
            .accessibilityHidden(true)
    }

    private var snapshotCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR WEEK")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(CheckpointTheme.heroMuted)

            Text(presentation.headline)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())

            Text(presentation.detail)
                .font(.footnote.weight(.medium))
                .foregroundStyle(CheckpointTheme.heroMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var snapshotBadge: some View {
        Text(presentation.badgeText)
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(CheckpointTheme.heroSuccess)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(CheckpointTheme.heroSuccess.opacity(0.11), in: Capsule())
            .contentTransition(.numericText())
    }

    private var weekRail: some View {
        HStack(spacing: 6) {
            ForEach(presentation.days) { day in
                FocusWinsWeekDayMark(day: day)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var privacyBoundary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 9) {
                privacyIcon
                privacyCopy
            }
        } else {
            HStack(alignment: .top, spacing: 9) {
                privacyIcon
                privacyCopy
            }
        }
    }

    private var privacyIcon: some View {
        Image(systemName: "lock.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.heroSuccess)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    private var privacyCopy: some View {
        Text("Logged by you. Never used for progress scores, recommendations, questions, or app breaks.")
            .font(.footnote)
            .foregroundStyle(CheckpointTheme.heroMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FocusWinsWeekDayMark: View {
    let day: FocusWinsWeekDayPresentation

    var body: some View {
        VStack(spacing: 6) {
            Text(day.label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(markFill)

                if day.winCount == 1 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(CheckpointTheme.ink)
                } else if day.winCount > 1 {
                    Text("\(day.winCount)")
                        .font(.caption2.monospacedDigit().weight(.black))
                        .foregroundStyle(CheckpointTheme.ink)
                        .contentTransition(.numericText())
                } else if day.isToday {
                    Circle()
                        .fill(CheckpointTheme.heroMuted)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 31)
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(CheckpointTheme.heroSuccess.opacity(0.66), lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(day.isFuture ? 0.42 : 1)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private var labelColor: Color {
        day.hasWins
            ? CheckpointTheme.heroText
            : CheckpointTheme.heroMuted
    }

    private var markFill: Color {
        day.hasWins
            ? CheckpointTheme.heroSuccess
            : CheckpointTheme.heroSubtleFill
    }
}

private enum FocusWinsConfirmation: Identifiable {
    case discardDraftAndDismiss
    case discardDraftAndCollapse
    case delete(FocusWin)

    var id: String {
        switch self {
        case .discardDraftAndDismiss:
            return "discard-draft-and-dismiss"
        case .discardDraftAndCollapse:
            return "discard-draft-and-collapse"
        case let .delete(focusWin):
            return "delete-\(focusWin.id.uuidString)"
        }
    }
}

private struct FocusWinRevealRequest: Equatable {
    let id = UUID()
    let focusWinID: FocusWin.ID
}

private enum FocusWinsFailure: Hashable {
    case save
    case delete
}

private enum FocusWinsPostMutationAccessibilityFocus: Hashable {
    case composerLauncher
    case ledgerTitle
}

private struct FocusWinsDayGroup: Identifiable {
    var id: Date { date }
    var date: Date
    var wins: [FocusWin]
}

struct FocusWinRow: View {
    var focusWin: FocusWin
    var usesStackedLayout: Bool
    var isCelebrated: Bool
    var celebrationSequence: Int
    var accessibilityFocusRequestID: UUID?
    var motionPolicy: FocusWinsMutationMotionPolicy
    var calendar: Calendar
    var locale: Locale
    var timeZone: TimeZone
    var consumeAccessibilityFocusRequest: (UUID) -> Void
    var requestDeletion: () -> Void

    @AccessibilityFocusState(for: [.voiceOver, .switchControl])
    private var isAccessibilityFocused: Bool

    init(
        focusWin: FocusWin,
        usesStackedLayout: Bool,
        isCelebrated: Bool,
        celebrationSequence: Int,
        accessibilityFocusRequestID: UUID?,
        motionPolicy: FocusWinsMutationMotionPolicy,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone,
        consumeAccessibilityFocusRequest: @escaping (UUID) -> Void,
        requestDeletion: @escaping () -> Void
    ) {
        self.focusWin = focusWin
        self.usesStackedLayout = usesStackedLayout
        self.isCelebrated = isCelebrated
        self.celebrationSequence = celebrationSequence
        self.accessibilityFocusRequestID = accessibilityFocusRequestID
        self.motionPolicy = motionPolicy
        self.calendar = calendar
        self.locale = locale
        self.timeZone = timeZone
        self.consumeAccessibilityFocusRequest = consumeAccessibilityFocusRequest
        self.requestDeletion = requestDeletion
    }

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
            rowBackground,
            in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                .stroke(
                    isCelebrated
                        ? CheckpointTheme.teal.opacity(
                            motionPolicy.celebrationBorderOpacity
                        )
                        : CheckpointTheme.hairline,
                    lineWidth: isCelebrated ? 1.5 : 1
                )
        }
        .shadow(
            color: isCelebrated
                ? CheckpointTheme.teal.opacity(motionPolicy.celebrationShadowOpacity)
                : .clear,
            radius: 10,
            y: 4
        )
        .task(id: accessibilityFocusRequestID) {
            guard let requestID = accessibilityFocusRequestID else { return }
            await Task.yield()
            guard !Task.isCancelled,
                  accessibilityFocusRequestID == requestID else { return }
            isAccessibilityFocused = true
            consumeAccessibilityFocusRequest(requestID)
        }
    }

    private var noteAndMetadata: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isCelebrated ? "sparkles" : "quote.bubble.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 22, height: 22)
                .symbolEffect(.bounce, options: .nonRepeating, value: celebrationSequence)
                .symbolEffectsRemoved(
                    !motionPolicy.animatesSymbolEffects || !isCelebrated
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(focusWin.note)
                    .font(.body)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Logged by you · \(loggedTimeText)")
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityFocused($isAccessibilityFocused)
    }

    private var rowBackground: Color {
        isCelebrated
            ? CheckpointTheme.teal.opacity(motionPolicy.celebrationBackgroundOpacity)
            : CheckpointTheme.panel.opacity(0.94)
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

    private var loggedTimeText: String {
        formattedDate(template: "jm")
    }

    private var fullDateText: String {
        formattedDate(template: "EEEEMMMMdyjm")
    }

    private func formattedDate(template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: focusWin.loggedAt)
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
