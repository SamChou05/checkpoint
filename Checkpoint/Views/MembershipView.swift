import Accessibility
import StoreKit
import SwiftUI

struct MembershipViewRenderConfiguration {
    let planOptions: [MembershipPlanOption]
    let selectedPlanID: String?
    let legalLinks: LegalLinks
    let reduceMotion: Bool
    let purchaseAction: (String?) -> Void
    let reloadAction: () -> Void
    let restoreAction: () -> Void

    init(
        planOptions: [MembershipPlanOption],
        selectedPlanID: String?,
        legalLinks: LegalLinks,
        reduceMotion: Bool = false,
        purchaseAction: @escaping (String?) -> Void = { _ in },
        reloadAction: @escaping () -> Void = {},
        restoreAction: @escaping () -> Void = {}
    ) {
        self.planOptions = planOptions
        self.selectedPlanID = selectedPlanID
        self.legalLinks = legalLinks
        self.reduceMotion = reduceMotion
        self.purchaseAction = purchaseAction
        self.reloadAction = reloadAction
        self.restoreAction = restoreAction
    }
}

struct MembershipView: View {
    let feature: MembershipFeature
    let store: CheckpointStore
    let purchaseController: PurchaseController

    private let legalLinks: LegalLinks
    private let planOptionsOverride: [MembershipPlanOption]?
    private let performsStoreKitLoading: Bool
    private let reduceMotionOverride: Bool?
    private let renderPurchaseAction: ((String?) -> Void)?
    private let renderReloadAction: (() -> Void)?
    private let renderRestoreAction: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedProductID: String?
    @State private var selectionFeedbackSequence = 0

    init(
        feature: MembershipFeature,
        store: CheckpointStore,
        purchaseController: PurchaseController,
        renderConfiguration: MembershipViewRenderConfiguration? = nil
    ) {
        self.feature = feature
        self.store = store
        self.purchaseController = purchaseController
        legalLinks = renderConfiguration?.legalLinks ?? .current
        planOptionsOverride = renderConfiguration?.planOptions
        performsStoreKitLoading = renderConfiguration == nil
        reduceMotionOverride = renderConfiguration?.reduceMotion
        renderPurchaseAction = renderConfiguration?.purchaseAction
        renderReloadAction = renderConfiguration?.reloadAction
        renderRestoreAction = renderConfiguration?.restoreAction
        _selectedProductID = State(initialValue: renderConfiguration?.selectedPlanID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    proHero

                    if store.isMember {
                        memberManagement
                    } else {
                        planSelection

                        if dynamicTypeSize.isAccessibilitySize {
                            inlinePurchaseAction
                        }
                    }

                    proBenefitsPanel

                    if let notice = purchaseController.purchaseNotice,
                       store.isMember || (planOptions.isEmpty && notice.shouldDisplayWithoutSelectedPlan) {
                        purchaseNotice(notice)
                    }

                    if !store.isMember {
                        restoreButton
                    }

                    paywallLegalLinks
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .checkpointScreenBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !store.isMember, !dynamicTypeSize.isAccessibilitySize {
                    purchaseBar
                }
            }
            .navigationTitle(store.isMember ? "Your Plan" : "Checkpoint Pro")
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
                guard performsStoreKitLoading else {
                    selectDefaultPlanIfNeeded()
                    return
                }
                purchaseController.startListeningForTransactions()
                await loadEntitlements()
                selectDefaultPlanIfNeeded()
            }
            .onChange(of: planOptions.map(\.id)) { _, _ in
                selectDefaultPlanIfNeeded()
            }
            .onChange(of: purchaseController.purchaseNotice) { _, notice in
                guard let notice else { return }
                AccessibilityNotification.Announcement(notice.message).post()
            }
            .sensoryFeedback(.selection, trigger: selectionFeedbackSequence)
        }
    }

    private var proHero: some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.mint,
            glowDiameter: 190,
            glowBlurRadius: 14,
            glowOffset: CGSize(width: 82, height: -96),
            contentPadding: 20
        ) {
            VStack(alignment: .leading, spacing: 18) {
                proHeroHeader

                VStack(alignment: .leading, spacing: 9) {
                    if !store.isMember {
                        Label("UNLOCK \(feature.title.uppercased())", systemImage: "sparkles")
                            .font(.caption2.weight(.bold))
                            .tracking(0.72)
                            .foregroundStyle(CheckpointTheme.mint)
                    }

                    Text(store.isMember ? "Your practice stays in motion." : feature.membershipHeadline)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(proText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        store.isMember
                            ? "Fresh, adaptive checkpoints stay ready as your goals and skills evolve."
                            : feature.detail
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(proSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

            }
        }
    }

    @ViewBuilder
    private var proHeroHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                proEyebrow
                if store.isMember {
                    activePlanBadge
                } else {
                    ProMomentumMark(reduceMotion: reduceMotion)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                proEyebrow
                Spacer(minLength: 8)

                if store.isMember {
                    activePlanBadge
                } else {
                    ProMomentumMark(reduceMotion: reduceMotion)
                }
            }
        }
    }

    @ViewBuilder
    private var proBenefitGrid: some View {
        let benefits = [
            ProBenefit(title: "Up to five focused goals", systemImage: "square.stack.3d.up.fill"),
            ProBenefit(title: "Fresh checkpoints", systemImage: "sparkles"),
            ProBenefit(title: "More question variety", systemImage: "rectangle.stack.badge.plus"),
            ProBenefit(title: "Adaptive Next Focus", systemImage: "scope")
        ]

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                ForEach(benefits) { benefit in
                    ProBenefitTile(benefit: benefit)
                }
            }
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(benefits) { benefit in
                    ProBenefitTile(benefit: benefit)
                }
            }
        }
    }

    private var proBenefitsPanel: some View {
        SectionPanel("Everything in Pro") {
            proBenefitGrid
        }
    }

    private var proEyebrow: some View {
        Text("CHECKPOINT PRO")
            .font(.caption2.weight(.bold))
            .tracking(1.0)
            .foregroundStyle(proSecondaryText)
    }

    private var activePlanBadge: some View {
        Label("ACTIVE", systemImage: "checkmark")
            .font(.caption2.weight(.bold))
            .foregroundStyle(CheckpointTheme.mint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(CheckpointTheme.mint.opacity(0.10), in: Capsule())
    }

    private var planSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHOOSE BILLING")
                .font(.caption2.weight(.bold))
                .tracking(0.85)
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityAddTraits(.isHeader)

            if purchaseController.isLoadingProducts && planOptions.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(CheckpointTheme.teal)
                    Text("Loading App Store plans")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
            } else if planOptions.isEmpty {
                unavailablePlans
            } else {
                VStack(spacing: 10) {
                    ForEach(planOptions) { option in
                        MembershipPlanRow(
                            option: option,
                            isSelected: selectedProductID == option.id
                        ) {
                            selectPlan(option.id)
                        }
                    }
                }
                .disabled(isPurchaseActionInProgress)
                .opacity(isPurchaseActionInProgress ? 0.72 : 1)
                .animation(
                    CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                    value: isPurchaseActionInProgress
                )
            }

            Text(subscriptionDisclosureText)
                .font(.caption)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unavailablePlans: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plans are temporarily unavailable.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)

            Text("Reconnect to the App Store and try loading prices again.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panel.opacity(0.86),
            in: RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        }
    }

    private var memberManagement: some View {
        SectionPanel("Subscription") {
            VStack(alignment: .leading, spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        memberPlanSummary
                        StatusBadge(text: "Current", tint: CheckpointTheme.teal)
                    }
                } else {
                    HStack {
                        memberPlanSummary
                        Spacer(minLength: 8)
                        StatusBadge(text: "Current", tint: CheckpointTheme.teal)
                    }
                }

                SecondaryActionButton(title: "Manage subscription", systemImage: "creditcard") {
                    openSubscriptionManagement()
                }
            }
        }
    }

    private var memberPlanSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Pro is active")
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)

            Text("Billing and cancellation are managed by Apple.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var purchaseBar: some View {
        VStack(spacing: 10) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            if let notice = purchaseController.purchaseNotice,
               checkoutPresentation.shouldShowNoticeInPurchaseBar {
                purchaseNotice(notice)
                    .padding(.horizontal, 20)
            }

            if let selectedOption, !dynamicTypeSize.isAccessibilitySize {
                selectedPlanSummary(selectedOption)
                    .padding(.horizontal, 20)
                    .accessibilityHidden(true)
            }

            purchaseActionButton
            .padding(.horizontal, 20)
            .padding(.top, selectedOption == nil ? 2 : 0)
            .padding(.bottom, 10)
        }
        .background(CheckpointTheme.panel)
        .shadow(color: CheckpointTheme.shadowCard, radius: 12, y: -4)
    }

    private var inlinePurchaseAction: some View {
        VStack(spacing: 10) {
            if let notice = purchaseController.purchaseNotice,
               checkoutPresentation.shouldShowNoticeInPurchaseBar {
                purchaseNotice(notice)
            }

            purchaseActionButton
        }
    }

    private var purchaseActionButton: some View {
        PrimaryActionButton(
            title: purchaseButtonTitle,
            systemImage: purchaseButtonSystemImage,
            isLoading: checkoutPresentation.showsPrimaryProgress
        ) {
            handlePurchaseButton()
        }
        .accessibilityLabel(checkoutPresentation.buttonAccessibilityLabel)
        .disabled(checkoutPresentation.isPrimaryActionDisabled)
    }

    private func selectedPlanSummary(_ option: MembershipPlanOption) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            selectedPlanIdentity(option)
            Spacer(minLength: 8)
            selectedPlanPrice(option)
        }
    }

    private func selectedPlanIdentity(_ option: MembershipPlanOption) -> some View {
        HStack(spacing: 7) {
            Text("\(option.title) plan")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)

            if let valueBadge = option.valueBadge {
                Text(valueBadge.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
            }
        }
    }

    private func selectedPlanPrice(_ option: MembershipPlanOption) -> some View {
        Text("\(option.displayPrice) \(option.cadence)")
            .font(.footnote.weight(.medium))
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var restoreButton: some View {
        Button {
            restorePurchases()
        } label: {
            HStack(spacing: 7) {
                if purchaseController.isRestoringPurchases {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }

                Text(checkoutPresentation.restoreButtonTitle)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(checkoutPresentation.isRestoreActionDisabled)
    }

    private func purchaseNotice(_ notice: MembershipPurchaseNotice) -> some View {
        let tint: Color
        let systemImage: String

        switch notice.tone {
        case .pending:
            tint = CheckpointTheme.amber
            systemImage = "clock.fill"
        case .failure:
            tint = CheckpointTheme.coral
            systemImage = "exclamationmark.circle.fill"
        case .information:
            tint = CheckpointTheme.blue
            systemImage = "info.circle.fill"
        }

        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(notice.message)
                .font(.footnote)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var planOptions: [MembershipPlanOption] {
        planOptionsOverride ?? catalogPresentation.planOptions
    }

    private var catalogPresentation: MembershipCatalogPresentation {
        MembershipCatalogPresentation(products: purchaseController.products)
    }

    private var selectedOption: MembershipPlanOption? {
        planOptions.first { $0.id == selectedProductID }
    }

    private var selectedProduct: Product? {
        purchaseController.products.first { $0.id == selectedProductID }
    }

    private var purchaseButtonTitle: String {
        checkoutPresentation.buttonTitle(accessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    private var purchaseButtonSystemImage: String {
        checkoutPresentation.buttonSystemImage
    }

    private var subscriptionDisclosureText: String {
        "Payment is charged by Apple. Subscriptions renew automatically until canceled in App Store account settings."
    }

    private var isPurchaseActionInProgress: Bool {
        checkoutPresentation.isActionInProgress
    }

    private var checkoutPresentation: MembershipCheckoutPresentation {
        MembershipCheckoutPresentation(
            selectedPlan: selectedOption,
            isLoadingPlans: purchaseController.isLoadingProducts,
            isRestoringPurchases: purchaseController.isRestoringPurchases,
            isPurchasing: purchaseController.purchasingProductID != nil,
            notice: purchaseController.purchaseNotice
        )
    }

    private var paywallLegalLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    paywallLegalLinkItems
                }

                VStack(alignment: .leading, spacing: 8) {
                    paywallLegalLinkItems
                }
            }

            if let missingMessage = legalLinks.missingConfigurationMessage {
                Text(missingMessage)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var paywallLegalLinkItems: some View {
        CompactLegalLink(title: "Privacy Policy", url: legalLinks.privacyPolicyURL)
        CompactLegalLink(title: "Support", url: legalLinks.supportURL)
        CompactLegalLink(title: "Terms of Use", url: LegalLinks.termsOfUseURL)
    }

    private func selectDefaultPlanIfNeeded() {
        guard !planOptions.isEmpty else {
            selectedProductID = nil
            return
        }
        guard !planOptions.contains(where: { $0.id == selectedProductID }) else { return }

        let defaultOptionID: String?
        if planOptionsOverride != nil {
            defaultOptionID = planOptions.first(where: \.isRecommended)?.id ?? planOptions.first?.id
        } else {
            defaultOptionID = catalogPresentation.resolvedSelection(currentID: selectedProductID)
        }
        withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
            selectedProductID = defaultOptionID
        }
    }

    private func selectPlan(_ productID: String) {
        guard selectedProductID != productID else { return }

        withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
            selectedProductID = productID
        }
        selectionFeedbackSequence += 1
    }

    private func loadEntitlements() async {
        await purchaseController.loadProducts()
        let unlocked = await purchaseController.refreshEntitlements()
        store.reconcileMembershipEntitlement(isUnlocked: unlocked)
    }

    private func handlePurchaseButton() {
        if let renderPurchaseAction {
            renderPurchaseAction(selectedProductID)
            return
        }

        guard let selectedProduct else {
            reloadProducts()
            return
        }
        purchase(selectedProduct)
    }

    private func reloadProducts() {
        if let renderReloadAction {
            renderReloadAction()
            return
        }

        Task {
            await purchaseController.loadProducts()
            selectDefaultPlanIfNeeded()
        }
    }

    private func purchase(_ product: Product) {
        Task {
            let unlocked = await purchaseController.purchase(product)

            if unlocked {
                store.updateMembershipTier(.member)
                close()
            }
        }
    }

    private func restorePurchases() {
        if let renderRestoreAction {
            renderRestoreAction()
            return
        }

        Task {
            let unlocked = await purchaseController.restorePurchases()
            if unlocked {
                store.updateMembershipTier(.member)
                close()
            }
        }
    }

    private func openSubscriptionManagement() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            openURL(url)
        }
    }

    private func close() {
        store.dismissMembershipPrompt()
        dismiss()
    }

    private var proText: Color { CheckpointTheme.heroText }
    private var proSecondaryText: Color { CheckpointTheme.heroMuted }
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
}

private struct MembershipPlanRow: View {
    let option: MembershipPlanOption
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            planRowContent
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? CheckpointTheme.teal.opacity(0.10)
                    : CheckpointTheme.panel.opacity(0.84),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? CheckpointTheme.teal.opacity(0.72) : CheckpointTheme.controlStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: isSelected
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Selects the \(option.title.lowercased()) plan")
    }

    @ViewBuilder
    private var planRowContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            expandedContent
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    selectionIcon
                    optionDescription
                    Spacer(minLength: 8)
                    optionPrice
                }

                expandedContent
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                selectionIcon
                optionTitle
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(option.displayPrice)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)

                Text(option.cadence)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)

                optionSavings
            }
            .padding(.leading, 32)

            Text(option.detail)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 32)
        }
    }

    private var selectionIcon: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(isSelected ? CheckpointTheme.teal : CheckpointTheme.muted)
            .frame(width: 22)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private var optionDescription: some View {
        VStack(alignment: .leading, spacing: 3) {
            optionTitle

            Text(option.detail)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var optionPrice: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(option.displayPrice)
                .font(.headline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)

            Text(option.cadence)
                .font(.caption)
                .foregroundStyle(CheckpointTheme.muted)

            optionSavings
        }
    }

    private var optionTitle: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    optionTitleText
                    recommendedBadge
                }
            } else {
                HStack(spacing: 7) {
                    optionTitleText
                    recommendedBadge
                }
            }
        }
    }

    private var optionTitleText: some View {
        Text(option.title)
            .font(.headline)
            .foregroundStyle(CheckpointTheme.text)
    }

    @ViewBuilder
    private var recommendedBadge: some View {
        if option.isRecommended {
            Text("BEST VALUE")
                .font(.caption2.weight(.bold))
                .tracking(0.45)
                .foregroundStyle(CheckpointTheme.selectionText)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(CheckpointTheme.actionTeal, in: Capsule())
        }
    }

    @ViewBuilder
    private var optionSavings: some View {
        if let valueBadge = option.valueBadge {
            Text(valueBadge.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckpointTheme.teal)
                .padding(.top, 2)
        }
    }
}

private struct ProBenefit: Identifiable {
    let title: String
    let systemImage: String

    var id: String { title }
}

private struct ProBenefitTile: View {
    let benefit: ProBenefit

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: benefit.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 27, height: 27)
                .background(
                    CheckpointTheme.teal.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityHidden(true)

            Text(benefit.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ProMomentumMark: View {
    let reduceMotion: Bool
    @State private var revealSequence = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(CheckpointTheme.mint.opacity(0.28), lineWidth: 1)
                .frame(width: 40, height: 40)

            Circle()
                .fill(CheckpointTheme.heroSubtleFill)
                .frame(width: 32, height: 32)

            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CheckpointTheme.mint)
                .symbolEffect(.bounce, options: .nonRepeating, value: revealSequence)
                .symbolEffectsRemoved(reduceMotion)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            revealSequence += 1
        }
    }
}

private struct CompactLegalLink: View {
    let title: String
    let url: URL?

    @ViewBuilder
    var body: some View {
        if let url {
            Link(destination: url) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        } else {
            Text("\(title) — not configured")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.coral)
                .frame(minHeight: 44, alignment: .leading)
        }
    }
}
