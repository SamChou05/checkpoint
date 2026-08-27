import StoreKit
import SwiftUI

struct MembershipView: View {
    let feature: MembershipFeature
    let store: CheckpointStore
    let purchaseController: PurchaseController
    private let legalLinks = LegalLinks.current

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var purchasingProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(headerDetailText)
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if !store.isMember {
                        SectionPanel("Current plan") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Free")
                                        .font(.headline)
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text("One goal with app protection")
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.muted)
                                }

                                Spacer()

                                StatusBadge(text: "Current", tint: CheckpointTheme.amber)
                            }
                        }
                    }

                    PlanCard(
                        title: "Pro",
                        price: store.isMember ? nil : proPriceText,
                        cadence: store.isMember ? nil : proPriceCadenceText,
                        detail: proPlanDetailText,
                        statusText: store.isMember ? "Current plan" : nil,
                        tint: CheckpointTheme.teal
                    ) {
                        PlanBenefitRow(title: "Up to 5 goals", detail: "Keep school, exams, interviews, and personal goals organized separately.")
                        PlanBenefitRow(title: "Fresh, varied practice", detail: "Keep getting useful checkpoints as you progress.")
                        PlanBenefitRow(title: "Review missed topics", detail: "Bring weak spots back into practice automatically.")

                        if !store.isMember {
                            Divider()

                            priceContent

                            PlanFootnote(subscriptionDisclosureText)
                        } else {
                            PlanFootnote("Billing and cancellation are managed by Apple.")

                            SecondaryActionButton(title: "Manage subscription", systemImage: "creditcard") {
                                openSubscriptionManagement()
                            }
                        }
                    }

                    if let message = purchaseController.purchaseMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !store.isMember {
                        SecondaryActionButton(title: purchaseController.isRestoringPurchases ? "Restoring" : "Restore purchases", systemImage: "arrow.clockwise.circle") {
                            restorePurchases()
                        }
                        .disabled(purchaseController.isRestoringPurchases || purchasingProductID != nil)
                        .opacity(purchaseController.isRestoringPurchases || purchasingProductID != nil ? 0.64 : 1)
                    }

                    paywallLegalLinks
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle(store.isMember ? "Your Plan" : "Choose Your Plan")
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
            }
        }
    }

    @ViewBuilder
    private var priceContent: some View {
        if purchaseController.isLoadingProducts {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading App Store prices")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
            }
        } else if purchaseController.products.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Plans are temporarily unavailable.")
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)

                SecondaryActionButton(title: "Try again", systemImage: "arrow.clockwise") {
                    Task {
                        await purchaseController.loadProducts()
                    }
                }
            }
        } else {
            ForEach(purchaseController.products, id: \.id) { product in
                ProductPurchaseRow(
                    product: product,
                    isPurchasing: purchasingProductID == product.id,
                    isDisabled: purchasingProductID != nil
                ) {
                    purchase(product)
                }
            }
        }
    }

    private var headerDetailText: String {
        if store.isMember {
            return "Pro is active. Manage your subscription or review what's included."
        }

        return feature.detail
    }

    private var proPlanDetailText: String {
        if store.isMember {
            return "Multiple goals, fresh practice, and guided review."
        }

        return "For more goals and practice that keeps adapting as you learn."
    }

    private var preferredProduct: Product? {
        purchaseController.products.first { $0.id == MembershipProductID.monthly }
            ?? purchaseController.products.first { $0.id == MembershipProductID.yearly }
    }

    private var proPriceText: String? {
        preferredProduct?.displayPrice
    }

    private var proPriceCadenceText: String? {
        guard let preferredProduct else { return nil }
        return preferredProduct.id == MembershipProductID.monthly ? "per month" : "per year"
    }

    private var subscriptionDisclosureText: String {
        "Billing is handled by Apple. Subscriptions renew automatically until canceled in App Store account settings."
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

    private func loadEntitlements() async {
        await purchaseController.loadProducts()
        let unlocked = await purchaseController.refreshEntitlements()
        store.updateMembershipTier(unlocked ? .member : .starter)
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
}

private struct CompactLegalLink: View {
    var title: String
    var url: URL?

    @ViewBuilder
    var body: some View {
        if let url {
            Link(title, destination: url)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.teal)
        } else {
            Text("\(title) — not configured")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.coral)
        }
    }
}

private struct ProductPurchaseRow: View {
    let product: Product
    let isPurchasing: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.text)

                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .lineLimit(2)
                }

                Spacer()

                if isPurchasing {
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
        .disabled(isDisabled)
    }

    private var title: String {
        product.id == MembershipProductID.yearly ? "Annual" : "Monthly"
    }

    private var detail: String {
        if product.id == MembershipProductID.yearly {
            return "Lower yearly price for steady practice. Cancel anytime in the App Store."
        }

        return "Flexible monthly access. Cancel anytime in the App Store."
    }
}

private struct PlanCard<Content: View>: View {
    var title: String
    var price: String?
    var cadence: String?
    var detail: String
    var statusText: String?
    var tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(CheckpointTheme.text)

                    if let price {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(price)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(CheckpointTheme.text)

                            if let cadence {
                                Text(cadence)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.muted)
                            }
                        }
                    }
                }

                Spacer()

                if let statusText {
                    StatusBadge(text: statusText, tint: tint)
                }
            }

            Text(detail)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CheckpointTheme.panel.opacity(0.96))
                .stroke(tint.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: CheckpointTheme.ink.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

private struct PlanBenefitRow: View {
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
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

private struct PlanFootnote: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
