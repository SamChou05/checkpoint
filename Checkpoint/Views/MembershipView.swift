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
    let context: MembershipPresentationContext
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
        context: MembershipPresentationContext,
        store: CheckpointStore,
        purchaseController: PurchaseController,
        renderConfiguration: MembershipViewRenderConfiguration? = nil
    ) {
        self.context = context
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
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(paywallPresentation.sectionOrder, id: \.self) { section in
                        paywallSection(section)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .checkpointScreenBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if paywallPresentation.checkoutPlacement == .sticky {
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

    @ViewBuilder
    private func paywallSection(_ section: MembershipPaywallSection) -> some View {
        switch section {
        case .hero:
            proHero
        case .offer:
            planSelection
        case .memberManagement:
            memberManagement
        case .valueProof:
            proValueProof
        case .benefits:
            proBenefitsPanel
        case .notice:
            if let notice = purchaseController.purchaseNotice,
               store.isMember || (planOptions.isEmpty && notice.shouldDisplayWithoutSelectedPlan) {
                purchaseNotice(notice)
            }
        case .restore:
            restoreButton
        case .legal:
            paywallLegalLinks
        }
    }

    private var proHero: some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.mint,
            glowDiameter: store.isMember ? 190 : 150,
            glowBlurRadius: store.isMember ? 14 : 11,
            glowOffset: CGSize(width: 72, height: -82),
            contentPadding: store.isMember ? 20 : 16
        ) {
            VStack(alignment: .leading, spacing: store.isMember ? 18 : 12) {
                proHeroHeader

                VStack(alignment: .leading, spacing: 7) {
                    Text(store.isMember ? "Your practice stays in motion." : context.membershipHeadline)
                        .font(
                            .system(
                                store.isMember && !dynamicTypeSize.isAccessibilitySize
                                    ? .largeTitle
                                    : .title2,
                                design: .rounded,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(proText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        store.isMember
                            ? "Fresh, adaptive checkpoints stay ready as your goals and skills evolve."
                            : context.offerDetail
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
        if !store.isMember {
            HStack(alignment: .center, spacing: 10) {
                Label(context.offerLabel, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.mint)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                Spacer(minLength: 6)

                if !dynamicTypeSize.isAccessibilitySize {
                    ProMomentumMark()
                }
            }
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                proEyebrow
                activePlanBadge
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                proEyebrow
                Spacer(minLength: 8)
                activePlanBadge
            }
        }
    }

    @ViewBuilder
    private var proBenefitGrid: some View {
        let benefits = [
            ProBenefit(
                title: "Up to \(ProductLimits.memberGoalProfileLimit) focused goals",
                systemImage: "square.stack.3d.up.fill"
            ),
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
        SectionPanel("Included with Pro") {
            proBenefitGrid
        }
    }

    private var proValueProof: some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.blue,
            glowOpacity: 0.07,
            glowDiameter: 125,
            glowBlurRadius: 10,
            glowOffset: CGSize(width: 64, height: -70),
            contentPadding: 12
        ) {
            MembershipValuePreview(
                presentation: MembershipValuePreviewPresentation(context: context),
                reduceMotion: reduceMotion
            )
        }
    }

    private var proEyebrow: some View {
        Text("Checkpoint Pro")
            .font(.caption.weight(.semibold))
            .foregroundStyle(proSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var activePlanBadge: some View {
        Label("Active", systemImage: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.mint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(CheckpointTheme.mint.opacity(0.10), in: Capsule())
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var planSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if paywallPresentation.checkoutPlacement == .afterPlanChoices {
                accessibilityOfferIntro
            }

            Text("Choose your plan")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
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

                if paywallPresentation.checkoutPlacement == .afterPlanChoices {
                    inlinePurchaseAction
                }
            } else if planOptions.isEmpty {
                unavailablePlans

                if paywallPresentation.checkoutPlacement == .afterPlanChoices {
                    inlinePurchaseAction
                }
            } else if paywallPresentation.laysOutPlansSideBySide {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(planOptions) { option in
                        MembershipPlanRow(
                            option: option,
                            isSelected: selectedProductID == option.id,
                            style: .compactCard
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

                if let selectedOption {
                    selectedOfferSupport(selectedOption)
                    subscriptionDisclosure
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(planOptions) { option in
                            MembershipPlanRow(
                                option: option,
                                isSelected: selectedProductID == option.id,
                                style: paywallPresentation.checkoutPlacement == .afterPlanChoices
                                    && selectedProductID != option.id
                                        ? .compactAlternativeRow
                                        : .expandedRow
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

                    if selectedOption != nil {
                        subscriptionDisclosure

                        if paywallPresentation.checkoutPlacement == .afterPlanChoices {
                            inlinePurchaseAction
                        }
                    }
                }
            }
        }
    }

    private var accessibilityOfferIntro: some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.mint,
            glowOpacity: 0.07,
            glowDiameter: 110,
            glowBlurRadius: 9,
            glowOffset: CGSize(width: 55, height: -62),
            contentPadding: 14
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Label(context.offerLabel, systemImage: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.mint)
                    .fixedSize(horizontal: false, vertical: true)

                Text(context.offerDetail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(proSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selectedOfferSupport(_ option: MembershipPlanOption) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .accessibilityHidden(true)

            Text(option.detail)
                .font(.footnote.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var subscriptionDisclosure: some View {
        Text(MembershipPaywallPresentation.subscriptionDisclosureText)
            .font(.caption)
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
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
            Text("Pro access is active")
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)

            Text("Billing and cancellation are managed by Apple.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            if let notice = purchaseController.purchaseNotice,
               checkoutPresentation.shouldShowNoticeInPurchaseBar {
                purchaseNotice(notice)
                    .padding(.horizontal, 20)
            }

            purchaseActionButton
                .padding(.horizontal, 20)
                .padding(.top, selectedOption == nil ? 2 : 0)

            if selectedOption != nil {
                purchaseTrustLine
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 9)
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

    private var purchaseTrustLine: some View {
        Label(MembershipPaywallPresentation.billingTrustText, systemImage: "lock.fill")
            .font(.caption2.weight(.medium))
            .foregroundStyle(CheckpointTheme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MembershipPaywallPresentation.billingTrustAccessibilityLabel)
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

    private var paywallPresentation: MembershipPaywallPresentation {
        MembershipPaywallPresentation(
            isMember: store.isMember,
            accessibilitySize: dynamicTypeSize.isAccessibilitySize,
            usesLargeText: dynamicTypeSize >= .xLarge
        )
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

enum MembershipValuePreviewMotionStyle: Equatable {
    case stagedReveal
    case identity
}

struct MembershipValuePreviewMotionPolicy: Equatable {
    let style: MembershipValuePreviewMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .stagedReveal
    }

    var animatesReveal: Bool { style == .stagedReveal }
    var animatesSymbol: Bool { style == .stagedReveal }
    var hiddenOpacity: Double { style == .stagedReveal ? 0 : 1 }
    var hiddenScale: CGFloat { style == .stagedReveal ? 0.92 : 1 }

    func nodeAnimation(at index: Int) -> Animation? {
        guard style == .stagedReveal else { return nil }
        return .smooth(duration: 0.34).delay(Double(index) * 0.09)
    }

    func connectorAnimation(after index: Int) -> Animation? {
        guard style == .stagedReveal else { return nil }
        return .smooth(duration: 0.3).delay(0.08 + (Double(index) * 0.09))
    }
}

struct MembershipValuePreview: View {
    let presentation: MembershipValuePreviewPresentation
    let reduceMotion: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isRevealed = false
    @State private var symbolRevealSequence = 0

    private var motionPolicy: MembershipValuePreviewMotionPolicy {
        MembershipValuePreviewMotionPolicy(reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("How Pro works")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.heroMuted)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                verticalWorkflow
            } else {
                ViewThatFits(in: .horizontal) {
                    standardWorkflow
                        .fixedSize(horizontal: true, vertical: false)

                    compactWorkflow
                }
            }

            Text(presentation.outcome)
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.heroSubtleFill,
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(CheckpointTheme.heroDivider, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .onAppear {
            reveal()
        }
    }

    private var standardWorkflow: some View {
        HStack(spacing: 5) {
            ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    horizontalConnector(after: index - 1)
                }

                VStack(spacing: 6) {
                    nodeMark(node)

                    Text(node.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(nodeTextColor(node))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 74)
                }
                .opacity(isRevealed ? 1 : motionPolicy.hiddenOpacity)
                .scaleEffect(isRevealed ? 1 : motionPolicy.hiddenScale)
                .animation(motionPolicy.nodeAnimation(at: index), value: isRevealed)
            }
        }
    }

    private var compactWorkflow: some View {
        ZStack(alignment: .top) {
            compactConnector
                .padding(.horizontal, 34)
                .padding(.top, 15)

            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                    VStack(spacing: 5) {
                        nodeMark(node)

                        Text(node.compactTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(nodeTextColor(node))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(isRevealed ? 1 : motionPolicy.hiddenOpacity)
                    .scaleEffect(isRevealed ? 1 : motionPolicy.hiddenScale)
                    .animation(motionPolicy.nodeAnimation(at: index), value: isRevealed)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var compactConnector: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(CheckpointTheme.heroDivider)

            Capsule()
                .fill(CheckpointTheme.mint.opacity(0.54))
                .scaleEffect(x: isRevealed ? 1 : 0, anchor: .leading)
                .animation(motionPolicy.connectorAnimation(after: 0), value: isRevealed)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var verticalWorkflow: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    verticalConnector(after: index - 1)
                }

                HStack(spacing: 11) {
                    nodeMark(node)

                    Text(node.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(nodeTextColor(node))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(isRevealed ? 1 : motionPolicy.hiddenOpacity)
                .scaleEffect(
                    isRevealed ? 1 : motionPolicy.hiddenScale,
                    anchor: .leading
                )
                .animation(motionPolicy.nodeAnimation(at: index), value: isRevealed)
            }
        }
    }

    private func nodeMark(_ node: MembershipValuePreviewNode) -> some View {
        let highlighted = isHighlighted(node)
        let animated = isAnimatedDestination(node)

        return Image(systemName: node.systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(highlighted ? CheckpointTheme.mint : CheckpointTheme.heroMuted)
            .frame(width: 32, height: 32)
            .background(
                highlighted
                    ? CheckpointTheme.mint.opacity(0.14)
                    : CheckpointTheme.heroSubtleFill,
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        highlighted
                            ? CheckpointTheme.mint.opacity(0.5)
                            : CheckpointTheme.heroDivider,
                        lineWidth: 1
                    )
            }
            .symbolEffect(.bounce, options: .nonRepeating, value: symbolRevealSequence)
            .symbolEffectsRemoved(!motionPolicy.animatesSymbol || !animated)
            .accessibilityHidden(true)
    }

    private func horizontalConnector(after index: Int) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(CheckpointTheme.heroDivider)

            Capsule()
                .fill(CheckpointTheme.mint.opacity(0.54))
                .scaleEffect(x: isRevealed ? 1 : 0, anchor: .leading)
                .animation(motionPolicy.connectorAnimation(after: index), value: isRevealed)
        }
        .frame(width: 14, height: 2)
        .accessibilityHidden(true)
    }

    private func verticalConnector(after index: Int) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(CheckpointTheme.heroDivider)

            Capsule()
                .fill(CheckpointTheme.mint.opacity(0.54))
                .scaleEffect(y: isRevealed ? 1 : 0, anchor: .top)
                .animation(motionPolicy.connectorAnimation(after: index), value: isRevealed)
        }
        .frame(width: 2, height: 12)
        .padding(.leading, 15)
        .accessibilityHidden(true)
    }

    private func isHighlighted(_ node: MembershipValuePreviewNode) -> Bool {
        presentation.highlightedNodeID == nil || presentation.highlightedNodeID == node.id
    }

    private func isAnimatedDestination(_ node: MembershipValuePreviewNode) -> Bool {
        if let highlightedNodeID = presentation.highlightedNodeID {
            return highlightedNodeID == node.id
        }
        return node.id == presentation.nodes.last?.id
    }

    private func nodeTextColor(_ node: MembershipValuePreviewNode) -> Color {
        isHighlighted(node) ? CheckpointTheme.heroText : CheckpointTheme.heroMuted
    }

    private func reveal() {
        isRevealed = true
        guard motionPolicy.animatesSymbol else { return }
        symbolRevealSequence += 1
    }
}

private enum MembershipPlanRowStyle: Equatable {
    case compactCard
    case compactAlternativeRow
    case expandedRow
}

private struct MembershipPlanRow: View {
    let option: MembershipPlanOption
    let isSelected: Bool
    let style: MembershipPlanRowStyle
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            planRowContent
                .padding(style == .compactCard ? 12 : 15)
                .frame(
                    maxWidth: .infinity,
                    minHeight: style == .compactCard ? 118 : nil,
                    alignment: .leading
                )
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Selects the \(option.title.lowercased()) plan")
    }

    @ViewBuilder
    private var planRowContent: some View {
        if style == .compactCard {
            compactCardContent
        } else if style == .compactAlternativeRow {
            compactAlternativeContent
        } else if dynamicTypeSize.isAccessibilitySize {
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

    private var compactAlternativeContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                selectionIcon
                optionTitleText
            }

            recommendedBadge

            Text("\(option.displayPrice) \(option.cadence)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            optionSavings
        }
    }

    private var compactCardContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 6) {
                selectionIcon
                Spacer(minLength: 4)
                recommendedBadge
            }

            optionTitleText

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(option.displayPrice)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 2)

                Text(option.cadence)
                    .font(.caption2)
                    .foregroundStyle(CheckpointTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            optionSavings
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
            Text("Best value")
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckpointTheme.selectionText)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(CheckpointTheme.actionTeal, in: Capsule())
        }
    }

    @ViewBuilder
    private var optionSavings: some View {
        if let valueBadge = option.valueBadge {
            Text(valueBadge)
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
        }
        .accessibilityHidden(true)
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
