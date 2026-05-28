import StoreKit
import SwiftUI

struct SettingsView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let purchaseController: PurchaseController

    @State private var isRestrictedAppsPresented = false
    @State private var isHistoryPresented = false
    @State private var isQuestionReportsPresented = false
    @State private var isAdvancedExpanded = false
    @State private var advancedAction: AdvancedSettingsAction?
    @State private var stopBlockingSession: CheckpointSession?
    @State private var stopBlockingMessage: String?
    @State private var isPreparingStopChallenge = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Settings")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Tune the blocker, your study goal, and the checkpoint rules.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    SectionPanel("Plan") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(store.isPro ? "Checkpoint Pro" : "Checkpoint Free")
                                        .font(.headline)
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text(planSubtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(CheckpointTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                StatusBadge(
                                    text: store.subscriptionTier.displayName,
                                    tint: store.isPro ? CheckpointTheme.amber : CheckpointTheme.teal
                                )
                            }

                            if !store.isPro {
                                SecondaryActionButton(title: "View Pro", systemImage: "sparkles") {
                                    store.requestUpgrade(for: .largerQuestionBanks)
                                }
                            }
                        }
                    }

                    SectionPanel("Goal") {
                        if let goal = store.goal {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(goal.title)
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("\(goal.category.rawValue) - \(goal.focusAreas)")
                                    .font(.subheadline)
                                    .foregroundStyle(CheckpointTheme.muted)
                            }
                        }

                        SecondaryActionButton(title: "Change active goal", systemImage: "pencil") {
                            store.isOnboardingPresented = true
                        }
                    }

                    SectionPanel("Activity") {
                        VStack(spacing: 14) {
                            SettingsNavigationRow(
                                title: "Checkpoint history",
                                detail: historyDetailText,
                                systemImage: "clock.arrow.circlepath",
                                trailingText: "\(store.attempts.count)"
                            ) {
                                isHistoryPresented = true
                            }

                            Divider()

                            SettingsNavigationRow(
                                title: "Question reports",
                                detail: questionReportsDetailText,
                                systemImage: "exclamationmark.bubble",
                                trailingText: "\(store.reportedQuestionCount)"
                            ) {
                                isQuestionReportsPresented = true
                            }
                        }
                    }

                    SectionPanel("App blocking") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Connection")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text(screenTime.setupState.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            Text(screenTime.restrictedAppsSummary)
                                .font(.footnote)
                                .foregroundStyle(CheckpointTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            if shouldShowScreenTimeAuthorizationButton {
                                SecondaryActionButton(title: "Allow Screen Time", systemImage: "shield") {
                                    Task {
                                        await screenTime.requestAuthorization()
                                    }
                                }
                            }

                            SecondaryActionButton(title: "Choose blocked apps", systemImage: "checklist") {
                                isRestrictedAppsPresented = true
                            }

                            if let message = screenTime.lastErrorMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.coral)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    SectionPanel("Checkpoint rules") {
                        VStack(alignment: .leading, spacing: 16) {
                            if !store.canUse(.advancedStrictness) {
                                ProLockedFeatureRow(feature: .advancedStrictness) {
                                    store.requestUpgrade(for: .advancedStrictness)
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Passing score")
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("\(store.unlockPolicy.requiredCorrectAnswers) of \(store.unlockPolicy.questionsPerSession) correct to unlock")
                                    .font(.subheadline)
                                    .foregroundStyle(CheckpointTheme.muted)

                                Stepper("Questions per checkpoint: \(store.unlockPolicy.questionsPerSession)", value: questionsPerSessionBinding, in: 1...10)
                                    .foregroundStyle(CheckpointTheme.text)
                                    .disabled(!store.canUse(.advancedStrictness))
                                    .opacity(store.canUse(.advancedStrictness) ? 1 : 0.48)

                                Stepper("Correct answers needed: \(store.unlockPolicy.requiredCorrectAnswers)", value: requiredCorrectAnswersBinding, in: 1...store.unlockPolicy.questionsPerSession)
                                    .foregroundStyle(CheckpointTheme.text)
                                    .disabled(!store.canUse(.advancedStrictness))
                                    .opacity(store.canUse(.advancedStrictness) ? 1 : 0.48)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Question difficulty")
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("Levels run 1 to 5. Start at \(difficultyLabel(for: store.unlockPolicy.minimumQuestionDifficulty)) or higher.")
                                    .font(.subheadline)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)

                                Stepper("Minimum: \(difficultyLabel(for: store.unlockPolicy.minimumQuestionDifficulty))", value: minimumQuestionDifficultyBinding, in: 1...5)
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Unlock time after passing")
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Picker("Unlock minutes", selection: unlockMinutesBinding) {
                                    ForEach(UnlockPolicy.correctAnswerUnlockMinuteOptions, id: \.self) { minutes in
                                        Text("\(minutes)m").tag(minutes)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Emergency pass")
                                        .font(.headline)
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text("\(store.emergencyPassesRemaining) remaining this week")
                                        .font(.subheadline)
                                        .foregroundStyle(CheckpointTheme.muted)

                                    if !screenTime.isShieldingEnabled {
                                        Text("Available while blocking is active")
                                            .font(.footnote)
                                            .foregroundStyle(CheckpointTheme.muted)
                                    }
                                }

                                Spacer()

                                Button {
                                    let unlockMinutes = store.useEmergencyPass()
                                    screenTime.temporarilyUnshield(minutes: unlockMinutes)
                                } label: {
                                    Image(systemName: "cross.case")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(CheckpointTheme.paper)
                                        .frame(width: 42, height: 42)
                                        .background(CheckpointTheme.amber, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(store.emergencyPassesRemaining == 0 || !screenTime.isShieldingEnabled)
                            }
                        }
                    }

                    SectionPanel("Advanced") {
                        DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Blocking diagnostics")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text(screenTime.shieldExtensionDiagnosticsText)
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Text("Stopping blocking is intentionally tucked away so app-open moments still point back to a checkpoint. To turn it off, clear a 10-question challenge with at least 9 correct.")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)

                                SecondaryActionButton(title: isPreparingStopChallenge ? "Preparing stop challenge" : "Stop blocking", systemImage: "hand.raised") {
                                    guard !isPreparingStopChallenge else { return }
                                    isPreparingStopChallenge = true

                                    Task {
                                        if let session = await store.prepareStopBlockingSession() {
                                            stopBlockingMessage = nil
                                            stopBlockingSession = session
                                        } else {
                                            stopBlockingMessage = store.checkpointNotice
                                        }
                                        isPreparingStopChallenge = false
                                    }
                                }
                                .disabled(!canStopBlocking || isPreparingStopChallenge)
                                .opacity(canStopBlocking ? 1 : 0.48)

                                if let stopBlockingMessage {
                                    Text(stopBlockingMessage)
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                SecondaryActionButton(title: "Reset app data", systemImage: "arrow.counterclockwise") {
                                    advancedAction = .resetData
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Text("Troubleshooting and reset")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                        }
                        .tint(CheckpointTheme.teal)
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $isRestrictedAppsPresented) {
                RestrictedAppsView(screenTime: screenTime)
            }
            .sheet(isPresented: $isHistoryPresented) {
                HistoryView(store: store)
            }
            .sheet(isPresented: $isQuestionReportsPresented) {
                QuestionReportsView(store: store)
            }
            .sheet(item: $advancedAction) { action in
                AdvancedConfirmationView(action: action, store: store, screenTime: screenTime)
            }
            .sheet(item: $stopBlockingSession) { session in
                CheckpointAttemptView(store: store, screenTime: screenTime, session: session)
            }
            .sheet(
                item: Binding(
                    get: { store.pendingPaywallFeature },
                    set: { feature in
                        if feature == nil {
                            store.dismissPaywall()
                        }
                    }
                )
            ) { feature in
                PaywallView(
                    feature: feature,
                    store: store,
                    purchaseController: purchaseController
                )
            }
        }
    }

    private var canStopBlocking: Bool {
        screenTime.isShieldingEnabled || screenTime.setupState == .temporarilyUnlocked
    }

    private var shouldShowScreenTimeAuthorizationButton: Bool {
        screenTime.setupState == .notStarted || screenTime.setupState == .failed
    }

    private var planSubtitle: String {
        if store.isPro {
            return "Extra question variety, adaptive guidance, and custom checkpoint rules are active."
        }

        return "Free keeps the blocker loop usable with one goal and automatic checkpoint preparation."
    }

    private var historyDetailText: String {
        if store.attempts.isEmpty {
            return "No checkpoint answers yet"
        }

        return "\(store.completedTodayCount) answered today"
    }

    private var questionReportsDetailText: String {
        if store.reportedQuestionCount == 0 {
            return "Flag confusing or incorrect questions"
        }

        return "\(store.reportedQuestionCount) submitted"
    }

    private var unlockMinutesBinding: Binding<Int> {
        Binding(
            get: { store.unlockPolicy.unlockMinutes },
            set: { store.updateUnlockMinutes($0) }
        )
    }

    private var questionsPerSessionBinding: Binding<Int> {
        Binding(
            get: { store.unlockPolicy.questionsPerSession },
            set: { store.updateQuestionsPerSession($0) }
        )
    }

    private var requiredCorrectAnswersBinding: Binding<Int> {
        Binding(
            get: { store.unlockPolicy.requiredCorrectAnswers },
            set: { store.updateRequiredCorrectAnswers($0) }
        )
    }

    private var minimumQuestionDifficultyBinding: Binding<Int> {
        Binding(
            get: { store.unlockPolicy.minimumQuestionDifficulty },
            set: { store.updateMinimumQuestionDifficulty($0) }
        )
    }

    private func difficultyLabel(for level: Int) -> String {
        switch level {
        case 1:
            return "Level 1 of 5 (Basics)"
        case 2:
            return "Level 2 of 5 (Easy)"
        case 3:
            return "Level 3 of 5 (Medium)"
        case 4:
            return "Level 4 of 5 (Hard)"
        default:
            return "Level 5 of 5 (Expert)"
        }
    }
}

private enum AdvancedSettingsAction: String, Identifiable {
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

private struct AdvancedConfirmationView: View {
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

private struct SettingsNavigationRow: View {
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

private struct ProLockedFeatureRow: View {
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

                Text("Free uses the default 4-of-5 checkpoint. Pro lets you tune the checkpoint length and passing score.")
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

private struct PaywallView: View {
    let feature: ProFeature
    let store: CheckpointStore
    let purchaseController: PurchaseController

    @Environment(\.dismiss) private var dismiss
    @State private var purchasingProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusBadge(text: feature.title, tint: CheckpointTheme.amber)

                        Text("Checkpoint Pro")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Keep the core blocker free. Upgrade when you want more control and less maintenance.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Included") {
                        VStack(alignment: .leading, spacing: 10) {
                            ProBenefitRow(title: feature.title, detail: feature.detail, isHighlighted: true)

                            ForEach(ProFeature.launchFeatures.filter { $0.id != feature.id }) { includedFeature in
                                ProBenefitRow(title: includedFeature.title, detail: includedFeature.detail)
                            }
                        }
                    }

                    SectionPanel("Price") {
                        VStack(alignment: .leading, spacing: 12) {
                            if purchaseController.isLoadingProducts {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Loading App Store prices")
                                        .font(.subheadline)
                                        .foregroundStyle(CheckpointTheme.muted)
                                }
                            } else if purchaseController.products.isEmpty {
                                FallbackPriceRow(title: "Monthly", price: "$4.99/mo")
                                FallbackPriceRow(title: "Annual", price: "$29.99/yr")

                                Text("App Store pricing appears here before purchase.")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(purchaseController.products, id: \.id) { product in
                                    Button {
                                        purchase(product)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(product.displayName)
                                                    .font(.headline)
                                                    .foregroundStyle(CheckpointTheme.text)

                                                Text(product.description)
                                                    .font(.footnote)
                                                    .foregroundStyle(CheckpointTheme.muted)
                                                    .lineLimit(2)
                                            }

                                            Spacer()

                                            if purchasingProductID == product.id {
                                                ProgressView()
                                            } else {
                                                Text(product.displayPrice)
                                                    .font(.subheadline.weight(.bold))
                                                    .foregroundStyle(CheckpointTheme.paper)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(CheckpointTheme.teal, in: RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                        .padding(12)
                                        .background(CheckpointTheme.panelRaised.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(purchasingProductID != nil)
                                }
                            }

                            if let message = purchaseController.purchaseMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.coral)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: 10) {
                                SecondaryActionButton(title: "Restore", systemImage: "arrow.clockwise.circle") {
                                    Task {
                                        let unlocked = await purchaseController.restorePurchases()
                                        if unlocked {
                                            store.updateSubscriptionTier(.pro)
                                            close()
                                        }
                                    }
                                }

                                SecondaryActionButton(title: "Keep Free", systemImage: "xmark") {
                                    close()
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Checkpoint Pro")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        close()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
            .task {
                await purchaseController.loadProducts()
                let unlocked = await purchaseController.refreshEntitlements()
                if unlocked {
                    store.updateSubscriptionTier(.pro)
                }
            }
        }
    }

    private func purchase(_ product: Product) {
        purchasingProductID = product.id

        Task {
            let unlocked = await purchaseController.purchase(product)
            purchasingProductID = nil

            if unlocked {
                store.updateSubscriptionTier(.pro)
                close()
            }
        }
    }

    private func close() {
        store.dismissPaywall()
        dismiss()
    }
}

private struct ProBenefitRow: View {
    var title: String
    var detail: String
    var isHighlighted = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isHighlighted ? "star.fill" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isHighlighted ? CheckpointTheme.amber : CheckpointTheme.teal)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FallbackPriceRow: View {
    var title: String
    var price: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)

            Spacer()

            Text(price)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
        }
        .padding(12)
        .background(CheckpointTheme.panelRaised.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
    }
}
