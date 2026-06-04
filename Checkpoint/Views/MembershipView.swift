import StoreKit
import SwiftUI

struct MembershipView: View {
    let feature: MembershipFeature
    let store: CheckpointStore
    let purchaseController: PurchaseController

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var purchasingProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose your plan")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Start with one focused goal. Switch to Pro when you want more goals, more variety, and steadier review over time.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    PlanCard(
                        title: "Free",
                        price: "$0",
                        cadence: "forever",
                        detail: freePlanDetailText,
                        statusText: store.isMember ? nil : "Current plan",
                        tint: CheckpointTheme.amber
                    ) {
                        PlanBenefitRow(title: "One goal to start", detail: "Build a focused checkpoint around the outcome that matters most right now.")
                        PlanBenefitRow(title: "Protected app flow", detail: "Clear a short practice set before opening the apps you chose to protect.")
                        PlanBenefitRow(title: "Weekly progress", detail: "See your questions answered, accuracy, skill progress, and screen-time patterns.")

                        if store.isMember {
                            PlanFootnote("To return to Free, manage your Pro plan in the App Store. Free resumes after the current billing period ends.")

                            SecondaryActionButton(title: "Return to Free", systemImage: "arrow.down.circle") {
                                openSubscriptionManagement()
                            }
                        } else {
                            DisabledPlanButton(title: "Current plan", systemImage: "checkmark")
                        }
                    }

                    PlanCard(
                        title: "Pro",
                        price: proPriceText,
                        cadence: proPriceCadenceText,
                        detail: proPlanDetailText,
                        statusText: store.isMember ? "Current plan" : nil,
                        tint: CheckpointTheme.teal
                    ) {
                        PlanBenefitRow(title: "Up to 5 goals", detail: "Keep school, exams, interviews, and personal goals organized separately.")
                        PlanBenefitRow(title: "Practice stays ready", detail: "Get new checkpoints as your priorities and progress change.")
                        PlanBenefitRow(title: "More variety", detail: "Work through a broader range of questions so practice stays useful.")
                        PlanBenefitRow(title: "Guided review", detail: "Missed ideas come back at the right time so weak spots do not disappear.")

                        if !store.isMember {
                            PlanFootnote("Choose a billing option to switch to Pro.")

                            Divider()

                            priceContent
                        } else {
                            DisabledPlanButton(title: "Current plan", systemImage: "checkmark")
                        }
                    }

                    if let message = purchaseController.purchaseMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        SecondaryActionButton(title: purchaseController.isRestoringPurchases ? "Restoring" : "Restore purchases", systemImage: "arrow.clockwise.circle") {
                            restorePurchases()
                        }
                        .disabled(purchaseController.isRestoringPurchases || purchasingProductID != nil)
                        .opacity(purchaseController.isRestoringPurchases || purchasingProductID != nil ? 0.64 : 1)

                        SecondaryActionButton(title: store.isMember ? "Done" : "Stay on Free", systemImage: "xmark") {
                            close()
                        }
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Choose your plan")
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
            FallbackPriceRow(title: "Monthly", price: "$4.99/mo")
            FallbackPriceRow(title: "Annual", price: "$29.99/yr")

            Text("App Store pricing appears here before purchase.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
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

    private var freePlanDetailText: String {
        if store.isMember {
            return "Free is always available if Pro is no longer the right fit."
        }

        return "A focused way to try the full Checkpoint habit with your first goal."
    }

    private var proPlanDetailText: String {
        if store.isMember {
            return "Your plan for multiple goals, varied practice, and steadier review."
        }

        return "For people working across more than one goal, or practicing often enough to need new checkpoints."
    }

    private var monthlyProduct: Product? {
        purchaseController.products.first { $0.id == MembershipProductID.monthly }
    }

    private var yearlyProduct: Product? {
        purchaseController.products.first { $0.id == MembershipProductID.yearly }
    }

    private var proPriceText: String {
        if let monthlyProduct {
            return monthlyProduct.displayPrice
        }

        if let yearlyProduct {
            return yearlyProduct.displayPrice
        }

        return "$4.99"
    }

    private var proPriceCadenceText: String {
        if monthlyProduct != nil {
            return "per month"
        }

        if yearlyProduct != nil {
            return "per year"
        }

        return "per month"
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
        product.id == MembershipProductID.yearly ? "Switch to Pro annually" : "Switch to Pro monthly"
    }

    private var detail: String {
        product.id == MembershipProductID.yearly ? "Best value for consistent practice." : "Flexible monthly access. Cancel anytime in the App Store."
    }
}

private struct PlanCard<Content: View>: View {
    var title: String
    var price: String
    var cadence: String
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

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(price)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(CheckpointTheme.text)

                        Text(cadence)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
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

private struct DisabledPlanButton: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CheckpointTheme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(CheckpointTheme.panelRaised.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
