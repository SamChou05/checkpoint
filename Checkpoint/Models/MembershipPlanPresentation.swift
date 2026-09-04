import Foundation
import StoreKit

enum MembershipBillingPeriod: Equatable, Sendable {
    case month
    case year

    init?(_ period: Product.SubscriptionPeriod) {
        guard period.value == 1 else { return nil }

        switch period.unit {
        case .month:
            self = .month
        case .year:
            self = .year
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .month:
            "Monthly"
        case .year:
            "Annual"
        }
    }

    var cadence: String {
        switch self {
        case .month:
            "per month"
        case .year:
            "per year"
        }
    }
}

struct MembershipStoreProduct: Equatable, Sendable {
    let id: String
    let price: Decimal
    let displayPrice: String
    let priceFormatStyle: Decimal.FormatStyle.Currency
    let billingPeriod: MembershipBillingPeriod

    init?(product: Product) {
        guard MembershipProductID.all.contains(product.id),
              let subscriptionPeriod = product.subscription?.subscriptionPeriod,
              let billingPeriod = MembershipBillingPeriod(subscriptionPeriod) else {
            return nil
        }

        self.init(
            id: product.id,
            price: product.price,
            displayPrice: product.displayPrice,
            priceFormatStyle: product.priceFormatStyle,
            billingPeriod: billingPeriod
        )
    }

    init(
        id: String,
        price: Decimal,
        displayPrice: String,
        currencyCode: String,
        locale: Locale,
        billingPeriod: MembershipBillingPeriod
    ) {
        self.init(
            id: id,
            price: price,
            displayPrice: displayPrice,
            priceFormatStyle: Decimal.FormatStyle.Currency(code: currencyCode).locale(locale),
            billingPeriod: billingPeriod
        )
    }

    private init(
        id: String,
        price: Decimal,
        displayPrice: String,
        priceFormatStyle: Decimal.FormatStyle.Currency,
        billingPeriod: MembershipBillingPeriod
    ) {
        self.id = id
        self.price = price
        self.displayPrice = displayPrice
        self.priceFormatStyle = priceFormatStyle
        self.billingPeriod = billingPeriod
    }

    var isSupportedPlan: Bool {
        switch (id, billingPeriod) {
        case (MembershipProductID.monthly, .month),
             (MembershipProductID.yearly, .year):
            true
        default:
            false
        }
    }
}

struct MembershipPlanOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let displayPrice: String
    let cadence: String
    let detail: String
    let valueBadge: String?
    let isRecommended: Bool

    init(
        id: String,
        title: String,
        displayPrice: String,
        cadence: String,
        detail: String,
        valueBadge: String? = nil,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.title = title
        self.displayPrice = displayPrice
        self.cadence = cadence
        self.detail = detail
        self.valueBadge = valueBadge
        self.isRecommended = isRecommended
    }
}

enum MembershipPurchaseNotice: Equatable, Sendable {
    case pendingApproval
    case catalogUnavailable(String)
    case failure(String)
    case information(String)

    var message: String {
        switch self {
        case .pendingApproval:
            "Purchase is pending approval."
        case .catalogUnavailable(let message),
             .failure(let message),
             .information(let message):
            message
        }
    }

    var tone: MembershipPurchaseNoticeTone {
        switch self {
        case .pendingApproval:
            .pending
        case .catalogUnavailable, .failure:
            .failure
        case .information:
            .information
        }
    }

    var isPending: Bool {
        if case .pendingApproval = self {
            return true
        }
        return false
    }

    var shouldDisplayWithoutSelectedPlan: Bool {
        switch self {
        case .failure, .information:
            true
        case .pendingApproval, .catalogUnavailable:
            false
        }
    }

    static func resolvingCatalogLoad(
        current: MembershipPurchaseNotice?,
        catalogNotice: MembershipPurchaseNotice?
    ) -> MembershipPurchaseNotice? {
        current?.isPending == true ? current : catalogNotice
    }

    static func resolvingEntitlementRefresh(
        current: MembershipPurchaseNotice?,
        isUnlocked: Bool
    ) -> MembershipPurchaseNotice? {
        isUnlocked ? nil : current
    }
}

enum MembershipPurchaseNoticeTone: Equatable, Sendable {
    case pending
    case failure
    case information
}

struct MembershipCheckoutPresentation: Equatable, Sendable {
    let selectedPlan: MembershipPlanOption?
    let isLoadingPlans: Bool
    let isRestoringPurchases: Bool
    let isPurchasing: Bool
    let notice: MembershipPurchaseNotice?

    var isActionInProgress: Bool {
        isLoadingPlans || isRestoringPurchases || isPurchasing || notice?.isPending == true
    }

    var isPrimaryActionDisabled: Bool {
        isActionInProgress
    }

    var showsPrimaryProgress: Bool {
        isLoadingPlans || isPurchasing
    }

    var isRestoreActionDisabled: Bool {
        isLoadingPlans || isRestoringPurchases || isPurchasing
    }

    var shouldShowNoticeInPurchaseBar: Bool {
        selectedPlan != nil && notice != nil
    }

    func buttonTitle(accessibilitySize: Bool) -> String {
        if notice?.isPending == true {
            return "Awaiting approval"
        }
        if isLoadingPlans {
            return selectedPlan == nil ? "Loading plans" : "Refreshing prices"
        }
        guard let selectedPlan else {
            return "Reload App Store plans"
        }
        if accessibilitySize {
            return "Subscribe — \(selectedPlan.displayPrice)"
        }
        return "Subscribe — \(selectedPlan.displayPrice) \(selectedPlan.cadence)"
    }

    var buttonAccessibilityLabel: String {
        if notice?.isPending == true {
            return "Purchase pending App Store approval"
        }
        if isLoadingPlans {
            return selectedPlan == nil
                ? "Loading App Store plans, in progress"
                : "Refreshing App Store prices, in progress"
        }
        guard let selectedPlan else {
            return "Reload App Store plans"
        }

        let label = "Subscribe to Checkpoint Pro, \(selectedPlan.title) plan, \(selectedPlan.displayPrice) \(selectedPlan.cadence)"
        return isPurchasing ? "\(label), in progress" : label
    }

    var buttonSystemImage: String {
        if notice?.isPending == true {
            return "clock.fill"
        }
        return selectedPlan == nil ? "arrow.clockwise" : "sparkles"
    }

    var restoreButtonTitle: String {
        if isRestoringPurchases {
            return "Restoring purchases"
        }
        if notice?.isPending == true {
            return "Check purchase status"
        }
        return "Restore purchases"
    }
}

struct MembershipCatalogPresentation: Equatable, Sendable {
    let planOptions: [MembershipPlanOption]
    let defaultPlanID: String?

    init(products: [Product]) {
        self.init(storeProducts: products.compactMap(MembershipStoreProduct.init(product:)))
    }

    init(storeProducts: [MembershipStoreProduct]) {
        let supportedProducts = storeProducts.filter(\.isSupportedPlan)
        let monthlyProduct = supportedProducts.first { $0.id == MembershipProductID.monthly }
        let annualProduct = supportedProducts.first { $0.id == MembershipProductID.yearly }
        let annualValue = MembershipAnnualValue(
            monthlyProduct: monthlyProduct,
            annualProduct: annualProduct
        )

        let monthlyOption = monthlyProduct.map {
            MembershipPlanOption(
                id: $0.id,
                title: $0.billingPeriod.title,
                displayPrice: $0.displayPrice,
                cadence: $0.billingPeriod.cadence,
                detail: "Flexible access, billed monthly through Apple."
            )
        }
        let annualOption = annualProduct.map {
            MembershipPlanOption(
                id: $0.id,
                title: $0.billingPeriod.title,
                displayPrice: $0.displayPrice,
                cadence: $0.billingPeriod.cadence,
                detail: annualValue.map {
                    "\($0.monthlyEquivalentDisplayPrice) per month when billed annually."
                } ?? "Billed annually through Apple for uninterrupted practice.",
                valueBadge: annualValue.map { "Save \($0.savingsPercentage)%" },
                isRecommended: annualValue != nil
            )
        }

        if annualValue != nil {
            planOptions = [annualOption, monthlyOption].compactMap { $0 }
            defaultPlanID = annualOption?.id ?? monthlyOption?.id
        } else {
            planOptions = [monthlyOption, annualOption].compactMap { $0 }
            defaultPlanID = monthlyOption?.id ?? annualOption?.id
        }
    }

    func resolvedSelection(currentID: String?) -> String? {
        if planOptions.contains(where: { $0.id == currentID }) {
            return currentID
        }
        return defaultPlanID
    }
}

private struct MembershipAnnualValue {
    let monthlyEquivalentDisplayPrice: String
    let savingsPercentage: Int

    init?(
        monthlyProduct: MembershipStoreProduct?,
        annualProduct: MembershipStoreProduct?
    ) {
        guard let monthlyProduct,
              let annualProduct,
              monthlyProduct.billingPeriod == .month,
              annualProduct.billingPeriod == .year,
              monthlyProduct.priceFormatStyle.currencyCode
                == annualProduct.priceFormatStyle.currencyCode,
              monthlyProduct.price > 0,
              annualProduct.price > 0 else {
            return nil
        }

        let twelveMonthlyPayments = monthlyProduct.price * 12
        guard annualProduct.price < twelveMonthlyPayments else { return nil }

        let rawSavingsPercentage = NSDecimalNumber(
            decimal: ((twelveMonthlyPayments - annualProduct.price) / twelveMonthlyPayments) * 100
        ).doubleValue
        let savingsPercentage = Int(rawSavingsPercentage.rounded(.down))
        guard savingsPercentage > 0 else { return nil }

        monthlyEquivalentDisplayPrice = annualProduct.priceFormatStyle.format(
            annualProduct.price / 12
        )
        self.savingsPercentage = savingsPercentage
    }
}
