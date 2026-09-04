import Accessibility
import StoreKit
import SwiftUI

struct MembershipView: View {
    let feature: MembershipFeature
    let store: CheckpointStore
    let purchaseController: PurchaseController

    private let legalLinks = LegalLinks.current
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var purchasingProductID: String?
    @State private var selectedProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !store.isMember {
                        requestedFeatureBanner
                    }

                    proHero

                    if store.isMember {
                        memberManagement
                    } else {
                        planSelection
                    }

                    if let message = purchaseController.purchaseMessage {
                        purchaseMessage(message)
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
                if !store.isMember {
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
                purchaseController.startListeningForTransactions()
                await loadEntitlements()
                selectDefaultPlanIfNeeded()
            }
            .onChange(of: planOptions.map(\.id)) { _, _ in
                selectDefaultPlanIfNeeded()
            }
            .onChange(of: purchaseController.purchaseMessage) { _, message in
                guard let message else { return }
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    @ViewBuilder
    private var requestedFeatureBanner: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    requestedFeatureIcon
                    requestedFeatureCopy
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    requestedFeatureIcon
                    requestedFeatureCopy
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var requestedFeatureIcon: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 36, height: 36)
            .background(
                CheckpointTheme.teal.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var requestedFeatureCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("UNLOCK \(feature.title.uppercased())")
                .font(.caption2.weight(.bold))
                .tracking(0.75)
                .foregroundStyle(CheckpointTheme.teal)

            Text(feature.detail)
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var proHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            proHeroHeader

            VStack(alignment: .leading, spacing: 8) {
                Text(store.isMember ? "Your practice stays in motion." : "Keep every goal moving.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(proText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Fresh, adaptive checkpoints stay ready as your goals and skills evolve.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(proSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .overlay(CheckpointTheme.heroDivider)

            VStack(alignment: .leading, spacing: 14) {
                ProBenefitRow(
                    title: "Room for every priority",
                    detail: "Keep up to five goals separate and focused."
                )
                ProBenefitRow(
                    title: "Practice that stays fresh",
                    detail: "Keep receiving goal-aligned questions as you progress."
                )
                ProBenefitRow(
                    title: "Review that remembers",
                    detail: "Bring weak spots back into future checkpoints automatically."
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CheckpointTheme.ink)
                .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(CheckpointTheme.mint.opacity(0.09))
                        .frame(width: 190, height: 190)
                        .blur(radius: 14)
                        .offset(x: 82, y: -96)
                        .allowsHitTesting(false)
                }
        )
        .shadow(color: CheckpointTheme.shadowElevated, radius: 20, y: 10)
    }

    @ViewBuilder
    private var proHeroHeader: some View {
        if dynamicTypeSize.isAccessibilitySize && store.isMember {
            VStack(alignment: .leading, spacing: 10) {
                proEyebrow
                activePlanBadge
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                proEyebrow
                Spacer(minLength: 8)

                if store.isMember {
                    activePlanBadge
                } else {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(CheckpointTheme.mint)
                        .accessibilityHidden(true)
                }
            }
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
                            selectedProductID = option.id
                        }
                    }
                }
                .disabled(isPurchaseActionInProgress)
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

            SecondaryActionButton(title: "Try again", systemImage: "arrow.clockwise") {
                reloadProducts()
            }
            .disabled(isPurchaseActionInProgress)
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
        VStack(spacing: 0) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            PrimaryActionButton(
                title: purchaseButtonTitle,
                systemImage: purchaseButtonSystemImage,
                isLoading: purchasingProductID != nil
            ) {
                handlePurchaseButton()
            }
            .disabled(purchaseController.isLoadingProducts || isPurchaseActionInProgress)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
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

                Text(purchaseController.isRestoringPurchases ? "Restoring purchases" : "Restore purchases")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPurchaseActionInProgress)
    }

    private func purchaseMessage(_ message: String) -> some View {
        let isPending = message == "Purchase is pending approval."
        let tint = isPending ? CheckpointTheme.amber : CheckpointTheme.coral

        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: isPending ? "clock.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(message)
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
        catalogPresentation.planOptions
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
        if purchaseController.isLoadingProducts && planOptions.isEmpty {
            return "Loading plans"
        }
        guard let selectedOption else {
            return "Reload App Store plans"
        }
        if dynamicTypeSize.isAccessibilitySize {
            return "Subscribe — \(selectedOption.displayPrice)"
        }
        return "Subscribe — \(selectedOption.displayPrice) \(selectedOption.cadence)"
    }

    private var purchaseButtonSystemImage: String {
        selectedOption == nil ? "arrow.clockwise" : "sparkles"
    }

    private var subscriptionDisclosureText: String {
        "Payment is charged by Apple. Subscriptions renew automatically until canceled in App Store account settings."
    }

    private var isPurchaseActionInProgress: Bool {
        purchaseController.isRestoringPurchases || purchasingProductID != nil
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

        let defaultOptionID = catalogPresentation.resolvedSelection(currentID: selectedProductID)
        withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
            selectedProductID = defaultOptionID
        }
    }

    private func loadEntitlements() async {
        await purchaseController.loadProducts()
        let unlocked = await purchaseController.refreshEntitlements()
        store.updateMembershipTier(unlocked ? .member : .starter)
    }

    private func handlePurchaseButton() {
        guard let selectedProduct else {
            reloadProducts()
            return
        }
        purchase(selectedProduct)
    }

    private func reloadProducts() {
        Task {
            await purchaseController.loadProducts()
            selectDefaultPlanIfNeeded()
        }
    }

    private func purchase(_ product: Product) {
        purchasingProductID = product.id

        Task {
            let unlocked = await purchaseController.purchase(product)
            purchasingProductID = nil

            if unlocked {
                store.updateMembershipTier(.member)
                close()
            }
        }
    }

    private func restorePurchases() {
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
                Text(option.title)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(option.displayPrice)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)

                Text(option.cadence)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
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
            Text(option.title)
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)

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
        }
    }
}

private struct ProBenefitRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CheckpointTheme.ink)
                .frame(width: 24, height: 24)
                .background(CheckpointTheme.mint, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.heroText)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
