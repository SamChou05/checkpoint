import Foundation
import Observation
import StoreKit

enum MembershipStoreOperation: Equatable, Sendable {
    case loadingProducts
    case purchasing(productID: String)
    case restoringPurchases
    case checkingPurchaseStatus
}

enum MembershipPlanKind: Equatable, Sendable {
    case monthly
    case annual

    init?(productID: String) {
        switch productID {
        case MembershipProductID.monthly:
            self = .monthly
        case MembershipProductID.yearly:
            self = .annual
        default:
            return nil
        }
    }
}

enum MembershipPlanOwnership: Equatable, Sendable {
    case purchased
    case familyShared
    case unknown
}

enum MembershipRenewalDisposition: Equatable, Sendable {
    case active
    case renews
    case ends
    case changesTo(MembershipPlanKind)
    case gracePeriod(until: Date?)
}

struct MembershipEntitlementRecord: Equatable, Sendable {
    let transactionID: UInt64
    let productID: String
    let purchaseDate: Date
    let expirationDate: Date?
    let subscriptionGroupID: String?
    let isUpgraded: Bool
    let ownership: MembershipPlanOwnership
}

enum MembershipSubscriptionState: Equatable, Sendable {
    case subscribed
    case expired
    case inBillingRetryPeriod
    case inGracePeriod
    case revoked
    case unknown
}

struct MembershipRenewalRecord: Equatable, Sendable {
    let currentProductID: String
    let willAutoRenew: Bool
    let autoRenewPreference: String?
    let gracePeriodExpirationDate: Date?
}

struct MembershipSubscriptionStatusRecord: Equatable, Sendable {
    let transactionID: UInt64
    let productID: String
    let state: MembershipSubscriptionState
    let renewal: MembershipRenewalRecord?
}

struct MembershipActivePlanSnapshot: Equatable, Sendable {
    let transactionID: UInt64
    let productID: String
    let planKind: MembershipPlanKind
    let subscriptionGroupID: String?
    let purchaseDate: Date
    let currentPeriodEnd: Date?
    let renewalDisposition: MembershipRenewalDisposition
    let ownership: MembershipPlanOwnership
}

enum MembershipActivePlanResolver {
    static func supportedActiveEntitlements(
        _ entitlements: [MembershipEntitlementRecord]
    ) -> [MembershipEntitlementRecord] {
        entitlements.filter {
            MembershipPlanKind(productID: $0.productID) != nil && !$0.isUpgraded
        }
    }

    static func resolve(
        entitlements: [MembershipEntitlementRecord],
        statuses: [MembershipSubscriptionStatusRecord] = []
    ) -> MembershipActivePlanSnapshot? {
        guard let selected = supportedActiveEntitlements(entitlements)
            .sorted(by: isPreferred(_:over:))
            .first,
              let planKind = MembershipPlanKind(productID: selected.productID) else {
            return nil
        }

        let base = MembershipActivePlanSnapshot(
            transactionID: selected.transactionID,
            productID: selected.productID,
            planKind: planKind,
            subscriptionGroupID: selected.subscriptionGroupID,
            purchaseDate: selected.purchaseDate,
            currentPeriodEnd: selected.expirationDate,
            renewalDisposition: .active,
            ownership: selected.ownership
        )

        guard let status = statuses.first(where: {
            $0.transactionID == selected.transactionID && $0.productID == selected.productID
        }) else {
            return base
        }

        return MembershipActivePlanSnapshot(
            transactionID: base.transactionID,
            productID: base.productID,
            planKind: base.planKind,
            subscriptionGroupID: base.subscriptionGroupID,
            purchaseDate: base.purchaseDate,
            currentPeriodEnd: base.currentPeriodEnd,
            renewalDisposition: renewalDisposition(for: status, activePlan: base.planKind),
            ownership: base.ownership
        )
    }

    private static func isPreferred(
        _ lhs: MembershipEntitlementRecord,
        over rhs: MembershipEntitlementRecord
    ) -> Bool {
        if lhs.purchaseDate != rhs.purchaseDate {
            return lhs.purchaseDate > rhs.purchaseDate
        }
        if lhs.expirationDate != rhs.expirationDate {
            return (lhs.expirationDate ?? .distantPast) > (rhs.expirationDate ?? .distantPast)
        }

        let lhsRank = MembershipProductID.all.firstIndex(of: lhs.productID) ?? .max
        let rhsRank = MembershipProductID.all.firstIndex(of: rhs.productID) ?? .max
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.transactionID > rhs.transactionID
    }

    private static func renewalDisposition(
        for status: MembershipSubscriptionStatusRecord,
        activePlan: MembershipPlanKind
    ) -> MembershipRenewalDisposition {
        switch status.state {
        case .subscribed:
            guard let renewal = status.renewal,
                  renewal.currentProductID == status.productID else {
                return .active
            }
            if renewal.willAutoRenew,
               let preference = renewal.autoRenewPreference,
               let nextPlan = MembershipPlanKind(productID: preference),
               nextPlan != activePlan {
                return .changesTo(nextPlan)
            }
            return renewal.willAutoRenew ? .renews : .ends
        case .inGracePeriod:
            guard let renewal = status.renewal,
                  renewal.currentProductID == status.productID else {
                return .active
            }
            return .gracePeriod(until: renewal.gracePeriodExpirationDate)
        case .expired, .inBillingRetryPeriod, .revoked, .unknown:
            // A verified current entitlement remains the access authority. If
            // supplemental status metadata contradicts it, keep neutral copy.
            return .active
        }
    }
}

protocol MembershipStoreClient: Sendable {
    func currentMembershipEntitlements() async -> [MembershipEntitlementRecord]
    func subscriptionStatuses(
        for subscriptionGroupID: String
    ) async throws -> [MembershipSubscriptionStatusRecord]
    func synchronize() async throws
}

struct StoreKitMembershipStoreClient: MembershipStoreClient {
    func currentMembershipEntitlements() async -> [MembershipEntitlementRecord] {
        var records: [MembershipEntitlementRecord] = []

        if #available(iOS 18.4, *) {
            for productID in MembershipProductID.all {
                for await result in Transaction.currentEntitlements(for: productID) {
                    guard case .verified(let transaction) = result else { continue }
                    records.append(Self.entitlementRecord(from: transaction))
                }
            }
        } else {
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }
                records.append(Self.entitlementRecord(from: transaction))
            }
        }
        return records
    }

    func subscriptionStatuses(
        for subscriptionGroupID: String
    ) async throws -> [MembershipSubscriptionStatusRecord] {
        let statuses = try await Product.SubscriptionInfo.status(for: subscriptionGroupID)
        return statuses.compactMap(Self.statusRecord(from:))
    }

    func synchronize() async throws {
        try await AppStore.sync()
    }

    private static func entitlementRecord(from transaction: Transaction) -> MembershipEntitlementRecord {
        MembershipEntitlementRecord(
            transactionID: transaction.id,
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            subscriptionGroupID: transaction.subscriptionGroupID,
            isUpgraded: transaction.isUpgraded,
            ownership: ownership(from: transaction.ownershipType)
        )
    }

    private static func statusRecord(
        from status: Product.SubscriptionInfo.Status
    ) -> MembershipSubscriptionStatusRecord? {
        guard case .verified(let transaction) = status.transaction else { return nil }

        let renewal: MembershipRenewalRecord?
        switch status.renewalInfo {
        case .verified(let renewalInfo):
            renewal = MembershipRenewalRecord(
                currentProductID: renewalInfo.currentProductID,
                willAutoRenew: renewalInfo.willAutoRenew,
                autoRenewPreference: renewalInfo.autoRenewPreference,
                gracePeriodExpirationDate: renewalInfo.gracePeriodExpirationDate
            )
        case .unverified:
            renewal = nil
        }

        return MembershipSubscriptionStatusRecord(
            transactionID: transaction.id,
            productID: transaction.productID,
            state: subscriptionState(from: status.state),
            renewal: renewal
        )
    }

    private static func ownership(
        from ownershipType: Transaction.OwnershipType
    ) -> MembershipPlanOwnership {
        switch ownershipType {
        case .purchased:
            .purchased
        case .familyShared:
            .familyShared
        default:
            .unknown
        }
    }

    private static func subscriptionState(
        from renewalState: Product.SubscriptionInfo.RenewalState
    ) -> MembershipSubscriptionState {
        switch renewalState {
        case .subscribed:
            .subscribed
        case .expired:
            .expired
        case .inBillingRetryPeriod:
            .inBillingRetryPeriod
        case .inGracePeriod:
            .inGracePeriod
        case .revoked:
            .revoked
        default:
            .unknown
        }
    }
}

private struct MembershipEntitlementRefreshResult {
    let isUnlocked: Bool
    let isCurrent: Bool
}

enum MembershipPendingPurchaseLoadResult: Equatable, Sendable {
    case none
    case recent(MembershipPendingPurchaseRecord)
    case longRunning(MembershipPendingPurchaseRecord)
}

@MainActor
struct MembershipPendingPurchasePersistence {
    static let storageKey = "checkpoint.membership.pendingPurchase.v1"
    /// Changes recovery wording only. StoreKit does not provide a matching
    /// timeout, so the marker remains until verification or explicit user action.
    static let defaultLongRunningInterval: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults?
    let longRunningInterval: TimeInterval

    init(
        defaults: UserDefaults? = .standard,
        longRunningInterval: TimeInterval = Self.defaultLongRunningInterval
    ) {
        self.defaults = defaults
        self.longRunningInterval = max(0, longRunningInterval)
    }

    func load(at date: Date) -> MembershipPendingPurchaseLoadResult {
        guard let defaults,
              let data = defaults.data(forKey: Self.storageKey) else {
            return .none
        }
        guard let record = try? JSONDecoder().decode(
            MembershipPendingPurchaseRecord.self,
            from: data
        ), MembershipProductID.all.contains(record.productID),
           record.initiatedAt <= date else {
            clear()
            return .none
        }
        guard !isLongRunning(record, at: date) else {
            return .longRunning(record)
        }
        return .recent(record)
    }

    func save(_ record: MembershipPendingPurchaseRecord) {
        guard MembershipProductID.all.contains(record.productID),
              let data = try? JSONEncoder().encode(record) else {
            clear()
            return
        }
        defaults?.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults?.removeObject(forKey: Self.storageKey)
    }

    func isLongRunning(_ record: MembershipPendingPurchaseRecord, at date: Date) -> Bool {
        date.timeIntervalSince(record.initiatedAt) >= longRunningInterval
    }
}

@MainActor
@Observable
final class PurchaseController {
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var purchaseNotice: MembershipPurchaseNotice?
    private(set) var storeOperation: MembershipStoreOperation?
    private(set) var activePlanSnapshot: MembershipActivePlanSnapshot?
    private(set) var pendingPurchaseRecord: MembershipPendingPurchaseRecord?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored var onMembershipEntitlementChange: ((Bool) -> Void)?
    @ObservationIgnored private let grantsDebugTesterEntitlement: Bool
    @ObservationIgnored private let storeClient: any MembershipStoreClient
    @ObservationIgnored private let pendingPurchasePersistence: MembershipPendingPurchasePersistence
    @ObservationIgnored private let currentDate: () -> Date
    @ObservationIgnored private var entitlementRequestRevision = 0

    init(
        grantsDebugTesterEntitlement: Bool = DebugMembershipEntitlement.isEnabled(),
        initialStoreOperation: MembershipStoreOperation? = nil,
        initialActivePlanSnapshot: MembershipActivePlanSnapshot? = nil,
        storeClient: any MembershipStoreClient = StoreKitMembershipStoreClient(),
        pendingPurchaseDefaults: UserDefaults? = .standard,
        pendingPurchaseLongRunningInterval: TimeInterval = MembershipPendingPurchasePersistence.defaultLongRunningInterval,
        currentDate: @escaping () -> Date = { Date() }
    ) {
        #if DEBUG
        self.grantsDebugTesterEntitlement = grantsDebugTesterEntitlement
        #else
        self.grantsDebugTesterEntitlement = false
        #endif
        self.storeClient = storeClient
        pendingPurchasePersistence = MembershipPendingPurchasePersistence(
            defaults: pendingPurchaseDefaults,
            longRunningInterval: pendingPurchaseLongRunningInterval
        )
        self.currentDate = currentDate
        storeOperation = initialStoreOperation
        activePlanSnapshot = initialActivePlanSnapshot

        switch pendingPurchasePersistence.load(at: currentDate()) {
        case .none:
            break
        case .recent(let record):
            pendingPurchaseRecord = record
            purchaseNotice = .pendingApproval
        case .longRunning(let record):
            pendingPurchaseRecord = record
            purchaseNotice = .previousPurchaseUnconfirmed
        }
    }

    var pendingPurchaseProductID: String? {
        pendingPurchaseRecord?.productID
    }

    var hasUnresolvedPurchase: Bool {
        pendingPurchaseRecord != nil
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

    var isCheckingPurchaseStatus: Bool {
        storeOperation == .checkingPurchaseStatus
    }

    var purchasingProductID: String? {
        guard case .purchasing(let productID) = storeOperation else { return nil }
        return productID
    }

    var isCheckoutActionInProgress: Bool {
        switch storeOperation {
        case .purchasing, .restoringPurchases, .checkingPurchaseStatus:
            true
        case .loadingProducts, nil:
            false
        }
    }

    var hasUnresolvedCheckout: Bool {
        hasUnresolvedPurchase || isCheckoutActionInProgress
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
            refreshPendingPurchasePresentationIfNeeded()
            let catalogNotice: MembershipPurchaseNotice? = products.isEmpty
                ? .catalogUnavailable(Self.productsUnavailableMessage)
                : nil
            purchaseNotice = .resolvingCatalogLoad(
                current: purchaseNotice,
                catalogNotice: catalogNotice
            )
        } catch {
            refreshPendingPurchasePresentationIfNeeded()
            purchaseNotice = .resolvingCatalogLoad(
                current: purchaseNotice,
                catalogNotice: .catalogUnavailable("Could not load App Store plans yet.")
            )
        }
    }

    @discardableResult
    func refreshEntitlements() async -> Bool {
        if grantsDebugTesterEntitlement {
            entitlementRequestRevision &+= 1
            purchasedProductIDs = [MembershipProductID.monthly]
            activePlanSnapshot = nil
            reconcilePurchaseNoticeWithEntitlement()
            publishMembershipEntitlement()
            return true
        }
        let refresh = await readAndApplyEntitlements()
        return refresh.isCurrent && refresh.isUnlocked
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        let operation = MembershipStoreOperation.purchasing(productID: product.id)
        guard begin(operation) else { return false }
        defer { finish(operation) }

        guard prepareForPurchaseAttempt() else { return false }
        purchaseNotice = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    resolveUnsuccessfulPurchaseAttempt(
                        notice: .failure("The App Store could not verify this purchase.")
                    )
                    return false
                }

                await transaction.finish()
                clearPendingPurchaseMarker()
                purchaseNotice = nil
                return await refreshEntitlements()
            case .pending:
                if isMembershipUnlocked {
                    clearPendingPurchaseMarker()
                    purchaseNotice = nil
                    return true
                }
                recordPendingPurchase(productID: product.id, initiatedAt: currentDate())
                return false
            case .userCancelled:
                resolveUnsuccessfulPurchaseAttempt(notice: nil)
                return false
            @unknown default:
                resolveUnsuccessfulPurchaseAttempt(
                    notice: .failure("The App Store returned an unknown purchase state.")
                )
                return false
            }
        } catch {
            resolveUnsuccessfulPurchaseAttempt(
                notice: .failure("Purchase failed. Try again from the App Store sheet.")
            )
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        let operation = MembershipStoreOperation.restoringPurchases
        guard begin(operation) else { return false }
        defer { finish(operation) }

        if pendingPurchaseRecord == nil {
            purchaseNotice = nil
        }
        let startingEntitlementRevision = entitlementRequestRevision

        do {
            try await storeClient.synchronize()
            let refresh = await readAndApplyEntitlements()
            if refresh.isCurrent, !refresh.isUnlocked {
                if pendingPurchaseRecord != nil {
                    refreshPendingPurchasePresentationIfNeeded()
                } else if purchaseNotice != .previousPurchaseUnconfirmed {
                    purchaseNotice = .information("No active Checkpoint Pro subscription was found.")
                }
            }
            return refresh.isCurrent && refresh.isUnlocked
        } catch {
            guard startingEntitlementRevision == entitlementRequestRevision else {
                return false
            }
            refreshPendingPurchasePresentationIfNeeded()
            if pendingPurchaseRecord != nil {
                // The local marker is only recovery context. A synchronization
                // failure cannot prove the App Store request was rejected.
            } else if purchaseNotice != .previousPurchaseUnconfirmed {
                purchaseNotice = .failure("Could not restore purchases yet.")
            }
            return false
        }
    }

    @discardableResult
    func checkPurchaseStatus() async -> Bool {
        let operation = MembershipStoreOperation.checkingPurchaseStatus
        guard begin(operation) else { return false }
        defer { finish(operation) }

        let startingNotice = purchaseNotice
        let hadUnresolvedPurchase = pendingPurchaseRecord != nil
        let refresh = await readAndApplyEntitlements()
        if refresh.isCurrent,
           !refresh.isUnlocked,
           let pendingPurchaseRecord {
            if pendingPurchasePersistence.isLongRunning(
                pendingPurchaseRecord,
                at: currentDate()
            ) {
                purchaseNotice = .previousPurchaseUnconfirmed
            } else if hadUnresolvedPurchase || startingNotice?.isPending == true {
                purchaseNotice = .pendingApprovalChecked
            }
        } else if refresh.isCurrent,
                  !refresh.isUnlocked,
                  startingNotice?.isPending == true,
                  purchaseNotice?.isPending == true {
            purchaseNotice = .pendingApprovalChecked
        }
        return refresh.isCurrent && refresh.isUnlocked
    }

    func clearPendingPurchaseState() {
        clearPendingPurchaseMarker()
        switch purchaseNotice {
        case .pendingApproval, .pendingApprovalChecked, .previousPurchaseUnconfirmed:
            purchaseNotice = nil
        case .catalogUnavailable, .failure, .information, nil:
            break
        }
    }

    func recordPendingPurchase(productID: String, initiatedAt: Date) {
        guard MembershipProductID.all.contains(productID) else { return }
        let record = MembershipPendingPurchaseRecord(
            productID: productID,
            initiatedAt: initiatedAt
        )
        pendingPurchaseRecord = record
        pendingPurchasePersistence.save(record)
        purchaseNotice = .pendingApproval
    }

    @discardableResult
    func prepareForPurchaseAttempt() -> Bool {
        guard let pendingPurchaseRecord else { return true }
        guard pendingPurchasePersistence.isLongRunning(
            pendingPurchaseRecord,
            at: currentDate()
        ) else {
            refreshPendingPurchasePresentationIfNeeded()
            return false
        }
        refreshPendingPurchasePresentationIfNeeded()
        return true
    }

    func resolveUnsuccessfulPurchaseAttempt(
        notice: MembershipPurchaseNotice?
    ) {
        if pendingPurchaseRecord != nil {
            // A replacement attempt does not prove the earlier StoreKit request
            // ended. Keep its recovery record until StoreKit verifies access, a
            // newer attempt becomes pending, or the user erases local data.
            refreshPendingPurchasePresentationIfNeeded()
        } else {
            purchaseNotice = notice
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult,
              Self.isMembershipProduct(transaction.productID) else {
            return
        }

        await transaction.finish()
        _ = await readAndApplyEntitlements()
    }

    private func readAndApplyEntitlements() async -> MembershipEntitlementRefreshResult {
        entitlementRequestRevision &+= 1
        let requestRevision = entitlementRequestRevision
        let entitlements = await storeClient.currentMembershipEntitlements()
        let activeEntitlements = MembershipActivePlanResolver.supportedActiveEntitlements(
            entitlements
        )
        let verifiedUnlocked = !activeEntitlements.isEmpty

        guard requestRevision == entitlementRequestRevision else {
            return MembershipEntitlementRefreshResult(
                isUnlocked: verifiedUnlocked,
                isCurrent: false
            )
        }

        purchasedProductIDs = Set(activeEntitlements.map(\.productID))
        let baseSnapshot = MembershipActivePlanResolver.resolve(entitlements: entitlements)
        activePlanSnapshot = baseSnapshot
        reconcilePurchaseNoticeWithEntitlement()
        refreshPendingPurchasePresentationIfNeeded()
        publishMembershipEntitlement()

        guard let subscriptionGroupID = activePlanSnapshot?.subscriptionGroupID else {
            return MembershipEntitlementRefreshResult(
                isUnlocked: verifiedUnlocked,
                isCurrent: true
            )
        }

        do {
            let statuses = try await storeClient.subscriptionStatuses(
                for: subscriptionGroupID
            )
            guard requestRevision == entitlementRequestRevision,
                  activePlanSnapshot?.transactionID == baseSnapshot?.transactionID else {
                return MembershipEntitlementRefreshResult(
                    isUnlocked: verifiedUnlocked,
                    isCurrent: false
                )
            }
            activePlanSnapshot = MembershipActivePlanResolver.resolve(
                entitlements: entitlements,
                statuses: statuses
            )
        } catch {
            // Renewal metadata improves presentation only. Verified current
            // entitlements remain authoritative when this optional lookup fails.
        }
        return MembershipEntitlementRefreshResult(
            isUnlocked: verifiedUnlocked,
            isCurrent: requestRevision == entitlementRequestRevision
        )
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
        if isMembershipUnlocked {
            clearPendingPurchaseMarker()
        }
        purchaseNotice = .resolvingEntitlementRefresh(
            current: purchaseNotice,
            isUnlocked: isMembershipUnlocked
        )
    }

    private func refreshPendingPurchasePresentationIfNeeded() {
        guard let pendingPurchaseRecord else { return }
        if pendingPurchasePersistence.isLongRunning(
            pendingPurchaseRecord,
            at: currentDate()
        ) {
            purchaseNotice = .previousPurchaseUnconfirmed
        } else if purchaseNotice?.requiresPurchaseStatusCheck != true {
            purchaseNotice = .pendingApproval
        }
    }

    private func clearPendingPurchaseMarker() {
        pendingPurchaseRecord = nil
        pendingPurchasePersistence.clear()
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
