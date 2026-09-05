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

    var accessibilityLabel: String {
        var parts = [
            "\(title) plan",
            "\(displayPrice) \(cadence)",
            detail.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        ]
        if let valueBadge {
            parts.append(valueBadge)
        }
        if isRecommended {
            parts.append("Best value")
        }
        return parts.joined(separator: ". ") + "."
    }
}

enum MembershipPurchaseNotice: Equatable, Sendable {
    case pendingApproval
    case pendingApprovalChecked
    case catalogUnavailable(String)
    case failure(String)
    case information(String)

    var message: String {
        switch self {
        case .pendingApproval:
            "Purchase is pending approval."
        case .pendingApprovalChecked:
            "Still awaiting App Store approval. Pro unlocks automatically when it’s confirmed."
        case .catalogUnavailable(let message),
             .failure(let message),
             .information(let message):
            message
        }
    }

    var tone: MembershipPurchaseNoticeTone {
        switch self {
        case .pendingApproval, .pendingApprovalChecked:
            .pending
        case .catalogUnavailable, .failure:
            .failure
        case .information:
            .information
        }
    }

    var isPending: Bool {
        switch self {
        case .pendingApproval, .pendingApprovalChecked:
            true
        case .catalogUnavailable, .failure, .information:
            false
        }
    }

    var shouldDisplayWithoutSelectedPlan: Bool {
        switch self {
        case .failure, .information:
            true
        case .pendingApproval, .pendingApprovalChecked, .catalogUnavailable:
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

enum MembershipSecondaryStoreAction: Equatable, Sendable {
    case restorePurchases
    case checkPurchaseStatus
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
    let isCheckingPurchaseStatus: Bool
    let isPurchasing: Bool
    let notice: MembershipPurchaseNotice?

    init(
        selectedPlan: MembershipPlanOption?,
        isLoadingPlans: Bool,
        isRestoringPurchases: Bool,
        isCheckingPurchaseStatus: Bool = false,
        isPurchasing: Bool,
        notice: MembershipPurchaseNotice?
    ) {
        self.selectedPlan = selectedPlan
        self.isLoadingPlans = isLoadingPlans
        self.isRestoringPurchases = isRestoringPurchases
        self.isCheckingPurchaseStatus = isCheckingPurchaseStatus
        self.isPurchasing = isPurchasing
        self.notice = notice
    }

    var isActionInProgress: Bool {
        isLoadingPlans
            || isRestoringPurchases
            || isCheckingPurchaseStatus
            || isPurchasing
            || notice?.isPending == true
    }

    var isPrimaryActionDisabled: Bool {
        isActionInProgress
    }

    var showsPrimaryProgress: Bool {
        isLoadingPlans || isPurchasing
    }

    var isSecondaryActionDisabled: Bool {
        isLoadingPlans || isRestoringPurchases || isCheckingPurchaseStatus || isPurchasing
    }

    var shouldShowNoticeInPurchaseBar: Bool {
        selectedPlan != nil && notice != nil
    }

    func buttonTitle(accessibilitySize _: Bool, compact: Bool = false) -> String {
        if notice?.isPending == true {
            return "Awaiting approval"
        }
        if isLoadingPlans {
            return selectedPlan == nil ? "Loading plans" : "Refreshing prices"
        }
        guard let selectedPlan else {
            return "Reload App Store plans"
        }
        if compact {
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

    var secondaryAction: MembershipSecondaryStoreAction {
        notice?.isPending == true ? .checkPurchaseStatus : .restorePurchases
    }

    var secondaryButtonTitle: String {
        if isRestoringPurchases {
            return "Restoring purchases"
        }
        if isCheckingPurchaseStatus {
            return "Checking purchase status"
        }
        if notice?.isPending == true {
            return "Check purchase status"
        }
        return "Restore purchases"
    }

    var secondaryButtonSystemImage: String {
        secondaryAction == .checkPurchaseStatus ? "clock.arrow.circlepath" : "arrow.clockwise"
    }

    var showsSecondaryProgress: Bool {
        isRestoringPurchases || isCheckingPurchaseStatus
    }

    var secondaryButtonAccessibilityLabel: String {
        switch secondaryAction {
        case .restorePurchases:
            isRestoringPurchases ? "Restoring App Store purchases, in progress" : "Restore App Store purchases"
        case .checkPurchaseStatus:
            isCheckingPurchaseStatus
                ? "Checking App Store purchase status, in progress"
                : "Check App Store purchase status"
        }
    }
}

enum MembershipActivePlanTone: Equatable, Sendable {
    case active
    case scheduled
    case attention
}

struct MembershipActivePlanVisualStateKey: Equatable, Sendable {
    let planTitle: String
    let badgeText: String
    let statusText: String
    let statusSystemImage: String
}

struct MembershipActivePlanPresentation: Equatable, Sendable {
    let planTitle: String
    let planSystemImage: String
    let badgeText: String
    let tone: MembershipActivePlanTone
    let statusText: String
    let supportText: String
    let statusSystemImage: String
    let managementTitle: String
    let managementAccessibilityHint: String
    let accessibilityLabel: String

    init(
        snapshot: MembershipActivePlanSnapshot?,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        guard let snapshot else {
            planTitle = "Checkpoint Pro"
            planSystemImage = "checkmark.seal.fill"
            badgeText = "ACTIVE"
            tone = .active
            statusText = "Pro access is active"
            supportText = "Open Apple subscriptions for plan and billing details."
            statusSystemImage = "checkmark.circle.fill"
            managementTitle = "View plan & billing"
            managementAccessibilityHint = "Opens Apple subscription management."
            accessibilityLabel = [planTitle, badgeText, statusText, supportText]
                .joined(separator: ". ")
            return
        }

        planTitle = snapshot.planKind.planTitle
        planSystemImage = snapshot.planKind.planSystemImage

        if snapshot.ownership == .familyShared {
            badgeText = "ACTIVE"
            tone = .active
            statusText = "Shared through Family Sharing"
            supportText = "The purchaser manages billing with Apple."
            statusSystemImage = "person.2.fill"
            managementTitle = "View Apple subscriptions"
            managementAccessibilityHint =
                "Shows subscriptions for this Apple Account. The purchaser manages the shared plan."
        } else {
            let periodEnd = Self.futureDateText(
                snapshot.currentPeriodEnd,
                now: now,
                locale: locale,
                calendar: calendar,
                timeZone: timeZone
            )

            switch snapshot.renewalDisposition {
            case .active:
                badgeText = "ACTIVE"
                tone = .active
                statusText = "Active access verified by Apple"
                supportText = "Billing and cancellation are managed by Apple."
                statusSystemImage = "checkmark.circle.fill"
            case .renews:
                badgeText = "ACTIVE"
                tone = .active
                statusText = periodEnd.map { "Renews \($0)" } ?? "Auto-renew is on"
                supportText = "Billing and cancellation are managed by Apple."
                statusSystemImage = "arrow.triangle.2.circlepath"
            case .ends:
                badgeText = "ACTIVE"
                tone = .active
                statusText = periodEnd.map { "Access through \($0)" } ?? "Renewal is off"
                supportText = "Your Pro benefits stay active through the current billing period."
                statusSystemImage = "calendar.badge.clock"
            case .changesTo(let nextPlan):
                badgeText = "SCHEDULED"
                tone = .scheduled
                statusText = periodEnd.map {
                    "Changes to \(nextPlan.shortTitle) on \($0)"
                } ?? "\(nextPlan.shortTitle) plan scheduled next"
                supportText = "Your current plan stays active until the switch."
                statusSystemImage = "arrow.triangle.swap"
            case .gracePeriod(let gracePeriodEnd):
                badgeText = "NEEDS ATTENTION"
                tone = .attention
                let graceEnd = Self.futureDateText(
                    gracePeriodEnd,
                    now: now,
                    locale: locale,
                    calendar: calendar,
                    timeZone: timeZone
                )
                statusText = graceEnd.map {
                    "Billing issue · Pro remains active through \($0)"
                } ?? "Billing issue · Pro remains active"
                supportText = "Update payment details with Apple to keep Pro active."
                statusSystemImage = "exclamationmark.circle.fill"
            }

            managementTitle = "Manage with Apple"
            managementAccessibilityHint = "Opens Apple subscription management."
        }

        accessibilityLabel = [planTitle, badgeText, statusText, supportText]
            .joined(separator: ". ")
    }

    var visualStateKey: MembershipActivePlanVisualStateKey {
        MembershipActivePlanVisualStateKey(
            planTitle: planTitle,
            badgeText: badgeText,
            statusText: statusText,
            statusSystemImage: statusSystemImage
        )
    }

    private static func futureDateText(
        _ date: Date?,
        now: Date,
        locale: Locale,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> String? {
        guard let date, date > now else { return nil }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

extension MembershipPlanKind {
    var planTitle: String {
        "\(shortTitle) plan"
    }

    var shortTitle: String {
        switch self {
        case .monthly:
            "Monthly"
        case .annual:
            "Annual"
        }
    }

    var planSystemImage: String {
        switch self {
        case .monthly:
            "calendar"
        case .annual:
            "calendar.badge.checkmark"
        }
    }
}

enum MembershipSubscriptionManagementScope: Equatable, Sendable {
    case allSubscriptions
    case subscriptionGroup(String)

    init(activePlanSnapshot: MembershipActivePlanSnapshot?) {
        guard activePlanSnapshot?.ownership != .familyShared else {
            self = .allSubscriptions
            return
        }
        self.init(subscriptionGroupID: activePlanSnapshot?.subscriptionGroupID)
    }

    init(subscriptionGroupID: String?) {
        guard let subscriptionGroupID = subscriptionGroupID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !subscriptionGroupID.isEmpty else {
            self = .allSubscriptions
            return
        }
        self = .subscriptionGroup(subscriptionGroupID)
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
