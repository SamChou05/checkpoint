import Observation
import StoreKit

@MainActor
@Observable
final class PurchaseController {
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoadingProducts = false
    var purchaseMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    var isMembershipUnlocked: Bool {
        purchasedProductIDs.contains { MembershipProductID.all.contains($0) }
    }

    func startListeningForTransactions() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            products = try await Product.products(for: MembershipProductID.all)
                .sorted { $0.price < $1.price }
            purchaseMessage = nil
        } catch {
            purchaseMessage = "Could not load App Store membership yet."
        }
    }

    @discardableResult
    func refreshEntitlements() async -> Bool {
        var activeProductIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  MembershipProductID.all.contains(transaction.productID) else {
                continue
            }

            activeProductIDs.insert(transaction.productID)
        }

        purchasedProductIDs = activeProductIDs
        return isMembershipUnlocked
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseMessage = "The App Store could not verify this purchase."
                    return false
                }

                await transaction.finish()
                purchaseMessage = nil
                return await refreshEntitlements()
            case .pending:
                purchaseMessage = "Purchase is pending approval."
                return false
            case .userCancelled:
                purchaseMessage = nil
                return false
            @unknown default:
                purchaseMessage = "The App Store returned an unknown purchase state."
                return false
            }
        } catch {
            purchaseMessage = "Purchase failed. Try again from the App Store sheet."
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            purchaseMessage = nil
            return await refreshEntitlements()
        } catch {
            purchaseMessage = "Could not restore purchases yet."
            return false
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult,
              MembershipProductID.all.contains(transaction.productID) else {
            return
        }

        await transaction.finish()
        _ = await refreshEntitlements()
    }
}
