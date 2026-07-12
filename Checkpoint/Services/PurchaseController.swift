import Observation
import StoreKit

@MainActor
@Observable
final class PurchaseController {
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoadingProducts = false
    var isRestoringPurchases = false
    var purchaseMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored var onMembershipEntitlementChange: ((Bool) -> Void)?
    @ObservationIgnored private let grantsDebugTesterEntitlement: Bool

    init(
        grantsDebugTesterEntitlement: Bool = DebugMembershipEntitlement.isEnabled()
    ) {
        #if DEBUG
        self.grantsDebugTesterEntitlement = grantsDebugTesterEntitlement
        #else
        self.grantsDebugTesterEntitlement = false
        #endif
    }

    var isMembershipUnlocked: Bool {
        if grantsDebugTesterEntitlement {
            return true
        }

        return purchasedProductIDs.contains { MembershipProductID.all.contains($0) }
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
            let loadedProducts = try await Product.products(for: MembershipProductID.all)
            products = MembershipProductID.all.compactMap { productID in
                loadedProducts.first { $0.id == productID }
            }
            purchaseMessage = products.isEmpty ? Self.productsUnavailableMessage : nil
        } catch {
            purchaseMessage = "Could not load App Store plans yet."
        }
    }

    @discardableResult
    func refreshEntitlements() async -> Bool {
        if grantsDebugTesterEntitlement {
            purchasedProductIDs = [MembershipProductID.monthly]
            publishMembershipEntitlement()
            return true
        }

        var activeProductIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  MembershipProductID.all.contains(transaction.productID),
                  isActive(transaction) else {
                continue
            }

            activeProductIDs.insert(transaction.productID)
        }

        purchasedProductIDs = activeProductIDs
        publishMembershipEntitlement()
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
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

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

    private func isActive(_ transaction: Transaction) -> Bool {
        guard transaction.revocationDate == nil else { return false }

        if let expirationDate = transaction.expirationDate {
            return expirationDate > Date()
        }

        return true
    }

    private func publishMembershipEntitlement() {
        onMembershipEntitlementChange?(isMembershipUnlocked)
    }

    private static var productsUnavailableMessage: String {
        #if DEBUG
        "App Store plans are not available yet. Check StoreKit or App Store Connect setup, then try again."
        #else
        "App Store plans are not available yet. Try again soon."
        #endif
    }

}

enum DebugMembershipEntitlement {
    static let environmentKey = "CHECKPOINT_DEBUG_PRO_ENTITLEMENT"

    static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        compiledQABuild: Bool = isCompiledQABuild
    ) -> Bool {
        #if DEBUG
        if compiledQABuild {
            return true
        }

        guard let rawValue = environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }

        return ["1", "true", "yes", "on"].contains(rawValue)
        #else
        return false
        #endif
    }

    private static var isCompiledQABuild: Bool {
        #if DEBUG && CHECKPOINT_DEBUG_PRO_BUILD
        true
        #else
        false
        #endif
    }
}
