import StoreKit
import SwiftUI

struct MembershipView: View {
    let feature: MembershipFeature
    let store: CheckpointStore
    let purchaseController: PurchaseController

    @Environment(\.dismiss) private var dismiss
    @State private var purchasingProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose your plan")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Start with one focused goal. Upgrade when you want Checkpoint to keep fresh practice ready as your priorities evolve.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    PlanCard(
                        title: "Free",
                        price: "$0",
                        cadence: "forever",
                        detail: "Try the core Checkpoint loop with one goal.",
                        statusText: store.isMember ? nil : "Current plan",
                        tint: CheckpointTheme.amber
                    ) {
                        PlanBenefitRow(title: "One active goal", detail: "Set a goal, choose protected apps, and practice before app breaks.")
                        PlanBenefitRow(title: "Initial question bank", detail: "Enough practice to experience the primary flow before upgrading.")
                        PlanBenefitRow(title: "Skill Map and weekly stats", detail: "Track early progress without extra setup.")
                    }

                    PlanCard(
                        title: "Pro",
                        price: "$4.99",
                        cadence: "per month",
                        detail: proPlanDetailText,
                        statusText: store.isMember ? "Current plan" : nil,
                        tint: CheckpointTheme.teal
                    ) {
                        PlanBenefitRow(title: "Up to 5 goals", detail: "Keep separate question banks, levels, and Skill Maps for each goal.")
                        PlanBenefitRow(title: "Fresh AI practice", detail: "Generate new goal-aligned questions when your bank runs low.")
                        PlanBenefitRow(title: "Deeper question banks", detail: "Keep more ready questions cached so switching goals feels seamless.")
                        PlanBenefitRow(title: "Adaptive guidance", detail: "Use misses, mastery, and recent accuracy to guide what comes next.")

                        if !store.isMember {
                            Divider()

                            priceContent
                        }
                    }

                    if let message = purchaseController.purchaseMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        SecondaryActionButton(title: "Restore purchases", systemImage: "arrow.clockwise.circle") {
                            restorePurchases()
                        }

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

    private var proPlanDetailText: String {
        if store.isMember {
            return "Fresh practice and goal switching are active."
        }

        return "For multiple goals, fresh questions, and smoother long-term practice."
    }

    private func loadEntitlements() async {
        await purchaseController.loadProducts()
        let unlocked = await purchaseController.refreshEntitlements()
        if unlocked {
            store.updateMembershipTier(.member)
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
        product.id == MembershipProductID.yearly ? "Start annual" : "Start monthly"
    }

    private var detail: String {
        product.id == MembershipProductID.yearly ? "Best value for consistent practice." : "Flexible monthly access."
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
