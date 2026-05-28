import StoreKit
import SwiftUI

struct PaywallView: View {
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
                            priceContent

                            if let message = purchaseController.purchaseMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.coral)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: 10) {
                                SecondaryActionButton(title: "Restore", systemImage: "arrow.clockwise.circle") {
                                    restorePurchases()
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

    private func loadEntitlements() async {
        await purchaseController.loadProducts()
        let unlocked = await purchaseController.refreshEntitlements()
        if unlocked {
            store.updateSubscriptionTier(.pro)
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

    private func restorePurchases() {
        Task {
            let unlocked = await purchaseController.restorePurchases()
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

private struct ProductPurchaseRow: View {
    let product: Product
    let isPurchasing: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
