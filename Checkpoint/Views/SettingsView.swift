import StoreKit
import SwiftUI

struct SettingsView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let purchaseController: PurchaseController

    @State private var isRestrictedAppsPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Settings")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Keep the MVP strict, simple, and easy to test.")
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
                                    store.requestUpgrade(for: .unlimitedQuestionRefreshes)
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

                        SecondaryActionButton(title: "Edit goal setup", systemImage: "pencil") {
                            store.isOnboardingPresented = true
                        }
                    }

                    SectionPanel("Screen Time") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Status")
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

                            SecondaryActionButton(title: "Request setup", systemImage: "shield") {
                                Task {
                                    await screenTime.requestAuthorization()
                                }
                            }

                            SecondaryActionButton(title: "Choose restricted apps", systemImage: "checklist") {
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

                    SectionPanel("Launch readiness") {
                        VStack(alignment: .leading, spacing: 12) {
                            readinessRow(
                                title: "Goal",
                                detail: store.goal?.title ?? "Missing",
                                isReady: store.goal != nil
                            )

                            readinessRow(
                                title: "Questions",
                                detail: "\(store.questions.count) stored",
                                isReady: store.questions.count >= store.unlockPolicy.questionsPerSession
                            )

                            readinessRow(
                                title: "Screen Time",
                                detail: screenTime.setupState.rawValue,
                                isReady: screenTime.isReadyForShielding
                            )

                            readinessRow(
                                title: "Restricted apps",
                                detail: screenTime.restrictedAppsSummary,
                                isReady: screenTime.hasSelection
                            )

                            readinessRow(
                                title: "Unlock window",
                                detail: "\(store.unlockPolicy.unlockMinutes)m default",
                                isReady: store.unlockPolicy.unlockMinutes >= 15
                            )
                        }
                    }

                    SectionPanel("Strictness") {
                        VStack(alignment: .leading, spacing: 16) {
                            if !store.canUse(.advancedStrictness) {
                                ProLockedFeatureRow(feature: .advancedStrictness) {
                                    store.requestUpgrade(for: .advancedStrictness)
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Checkpoint threshold")
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("\(store.unlockPolicy.requiredCorrectAnswers) of \(store.unlockPolicy.questionsPerSession) correct to unlock")
                                    .font(.subheadline)
                                    .foregroundStyle(CheckpointTheme.muted)

                                Stepper("Questions in set: \(store.unlockPolicy.questionsPerSession)", value: questionsPerSessionBinding, in: 1...10)
                                    .foregroundStyle(CheckpointTheme.text)
                                    .disabled(!store.canUse(.advancedStrictness))
                                    .opacity(store.canUse(.advancedStrictness) ? 1 : 0.48)

                                Stepper("Correct needed: \(store.unlockPolicy.requiredCorrectAnswers)", value: requiredCorrectAnswersBinding, in: 1...store.unlockPolicy.questionsPerSession)
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
                                Text("Correct-answer unlock")
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
                                    Text("Emergency Pass")
                                        .font(.headline)
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text("\(store.emergencyPassesRemaining) remaining this week")
                                        .font(.subheadline)
                                        .foregroundStyle(CheckpointTheme.muted)

                                    if !screenTime.isShieldingEnabled {
                                        Text("Available while shields are active")
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

                    SectionPanel("Questions") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Status")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text(store.questionBatchState.rawValue.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            HStack {
                                Text("Reports")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text("\(store.reportedQuestionCount)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            HStack {
                                Text("Refreshes")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text(store.questionRefreshStatusText)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            SecondaryActionButton(
                                title: store.canRefreshQuestionBatch ? "Refresh question batch" : "Upgrade for more refreshes",
                                systemImage: store.canRefreshQuestionBatch ? "arrow.clockwise" : "lock"
                            ) {
                                if store.canRefreshQuestionBatch {
                                    Task {
                                        await store.refreshQuestionBatch()
                                    }
                                } else {
                                    store.requestUpgrade(for: .unlimitedQuestionRefreshes)
                                }
                            }
                        }
                    }

                    SectionPanel("Developer") {
                        SecondaryActionButton(title: "Reset local prototype data", systemImage: "arrow.counterclockwise") {
                            screenTime.clearShield()
                            store.resetDemoData()
                        }
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

    private var planSubtitle: String {
        if store.isPro {
            return "Unlimited refreshes, larger question banks, and advanced strictness are active."
        }

        return "Free keeps the blocker loop usable with one goal, local questions, and \(FreemiumLimits.freeQuestionRefreshLimit) refreshes per goal."
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

    private func readinessRow(title: String, detail: String, isReady: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isReady ? CheckpointTheme.teal : CheckpointTheme.amber)
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

            Spacer(minLength: 0)
        }
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

                Text("Free uses the default 4-of-5 checkpoint. Pro lets you tune the checkpoint length and pass threshold.")
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

                        Text("Keep the core blocker free. Pay for deeper study controls when Checkpoint becomes part of your routine.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Why Pro") {
                        VStack(alignment: .leading, spacing: 10) {
                            ProBenefitRow(title: feature.title, detail: feature.detail, isHighlighted: true)

                            ForEach(ProFeature.allCases.filter { $0.id != feature.id }) { includedFeature in
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

                                Text("These are the planned launch prices. Purchases will activate after the App Store Connect products are configured.")
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
