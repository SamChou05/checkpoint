import Observation
import StoreKit

enum MembershipStoreOperation: Equatable, Sendable {
    case loadingProducts
    case purchasing(productID: String)
    case restoringPurchases
}

@MainActor
@Observable
final class PurchaseController {
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var purchaseNotice: MembershipPurchaseNotice?
    private(set) var storeOperation: MembershipStoreOperation?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored var onMembershipEntitlementChange: ((Bool) -> Void)?
    @ObservationIgnored private let grantsDebugTesterEntitlement: Bool

    init(
        grantsDebugTesterEntitlement: Bool = DebugMembershipEntitlement.isEnabled(),
        initialStoreOperation: MembershipStoreOperation? = nil
    ) {
        #if DEBUG
        self.grantsDebugTesterEntitlement = grantsDebugTesterEntitlement
        #else
        self.grantsDebugTesterEntitlement = false
        #endif
        storeOperation = initialStoreOperation
    }

    var isMembershipUnlocked: Bool {
        grantsDebugTesterEntitlement || purchasedProductIDs.contains(where: Self.isMembershipProduct)
    }

    var isLoadingProducts: Bool {
        storeOperation == .loadingProducts
    }

    var isRestoringPurchases: Bool {
        storeOperation == .restoringPurchases
    }

    var purchasingProductID: String? {
        guard case .purchasing(let productID) = storeOperation else { return nil }
        return productID
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
        let operation = MembershipStoreOperation.loadingProducts
        guard begin(operation) else { return }
        defer { finish(operation) }

        do {
            let loadedProducts = try await Product.products(for: MembershipProductID.all)
            products = MembershipProductID.all.compactMap { productID in
                loadedProducts.first { $0.id == productID }
            }
            let catalogNotice: MembershipPurchaseNotice? = products.isEmpty
                ? .catalogUnavailable(Self.productsUnavailableMessage)
                : nil
            purchaseNotice = .resolvingCatalogLoad(
                current: purchaseNotice,
                catalogNotice: catalogNotice
            )
        } catch {
            purchaseNotice = .resolvingCatalogLoad(
                current: purchaseNotice,
                catalogNotice: .catalogUnavailable("Could not load App Store plans yet.")
            )
        }
    }

    @discardableResult
    func refreshEntitlements() async -> Bool {
        if grantsDebugTesterEntitlement {
            purchasedProductIDs = [MembershipProductID.monthly]
            reconcilePurchaseNoticeWithEntitlement()
            publishMembershipEntitlement()
            return true
        }

        var activeProductIDs: Set<String> = []

        // StoreKit includes subscribed and billing-grace-period transactions here,
        // while excluding revoked or refunded products. Treat that sequence as the
        // entitlement authority instead of reinterpreting its expiration dates.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.isMembershipProduct(transaction.productID) else {
                continue
            }

            activeProductIDs.insert(transaction.productID)
        }

        purchasedProductIDs = activeProductIDs
        reconcilePurchaseNoticeWithEntitlement()
        publishMembershipEntitlement()
        return isMembershipUnlocked
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        let operation = MembershipStoreOperation.purchasing(productID: product.id)
        guard begin(operation) else { return false }
        defer { finish(operation) }

        purchaseNotice = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseNotice = .failure("The App Store could not verify this purchase.")
                    return false
                }

                await transaction.finish()
                purchaseNotice = nil
                return await refreshEntitlements()
            case .pending:
                purchaseNotice = .pendingApproval
                return false
            case .userCancelled:
                purchaseNotice = nil
                return false
            @unknown default:
                purchaseNotice = .failure("The App Store returned an unknown purchase state.")
                return false
            }
        } catch {
            purchaseNotice = .failure("Purchase failed. Try again from the App Store sheet.")
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        let operation = MembershipStoreOperation.restoringPurchases
        guard begin(operation) else { return false }
        defer { finish(operation) }

        purchaseNotice = nil

        do {
            try await AppStore.sync()
            let unlocked = await refreshEntitlements()
            if !unlocked {
                purchaseNotice = .information("No active Checkpoint Pro subscription was found.")
            }
            return unlocked
        } catch {
            purchaseNotice = .failure("Could not restore purchases yet.")
            return false
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult,
              Self.isMembershipProduct(transaction.productID) else {
            return
        }

        await transaction.finish()
        _ = await refreshEntitlements()
    }

    private static func isMembershipProduct(_ productID: String) -> Bool {
        MembershipProductID.all.contains(productID)
    }

    private func begin(_ operation: MembershipStoreOperation) -> Bool {
        guard storeOperation == nil else { return false }
        storeOperation = operation
        return true
    }

    private func finish(_ operation: MembershipStoreOperation) {
        guard storeOperation == operation else { return }
        storeOperation = nil
    }

    private func publishMembershipEntitlement() {
        onMembershipEntitlementChange?(isMembershipUnlocked)
    }

    private func reconcilePurchaseNoticeWithEntitlement() {
        purchaseNotice = .resolvingEntitlementRefresh(
            current: purchaseNotice,
            isUnlocked: isMembershipUnlocked
        )
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
