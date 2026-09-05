import Foundation
import XCTest
@testable import Checkpoint

final class StoreKitPaymentTests: XCTestCase {
    // MARK: - Entitlement configuration

    @MainActor
    func testDebugMembershipEntitlementDefaultsOff() {
        let controller = PurchaseController(grantsDebugTesterEntitlement: false)

        XCTAssertFalse(controller.isMembershipUnlocked)
    }

    @MainActor
    func testDebugMembershipEntitlementCanBeExplicitlyEnabled() async {
        let controller = PurchaseController(grantsDebugTesterEntitlement: true)
        let isUnlocked = await controller.refreshEntitlements()

        XCTAssertTrue(isUnlocked)
        XCTAssertTrue(controller.isMembershipUnlocked)
        XCTAssertEqual(controller.purchasedProductIDs, [MembershipProductID.monthly])
    }

    func testDebugMembershipEnvironmentOptInIsExplicit() {
        XCTAssertFalse(DebugMembershipEntitlement.isEnabled(environment: [:]))
        XCTAssertFalse(
            DebugMembershipEntitlement.isEnabled(
                environment: [DebugMembershipEntitlement.environmentKey: "0"]
            )
        )

        #if DEBUG
        XCTAssertTrue(
            DebugMembershipEntitlement.isEnabled(
                environment: [DebugMembershipEntitlement.environmentKey: "true"]
            )
        )
        #endif
    }

    func testCompiledQAProBuildOptInIsExplicit() {
        #if DEBUG
        XCTAssertTrue(
            DebugMembershipEntitlement.isEnabled(
                environment: [:],
                compiledQABuild: true
            )
        )
        #endif
    }

    func testLegalLinksRejectMissingAndUnexpandedBuildSettings() {
        XCTAssertNil(LegalLinks.configuredURL(nil))
        XCTAssertNil(LegalLinks.configuredURL(""))
        XCTAssertNil(LegalLinks.configuredURL("$(CHECKPOINT_PRIVACY_POLICY_URL)"))
        XCTAssertNil(LegalLinks.configuredURL("not a URL"))
        XCTAssertNil(LegalLinks.configuredURL("http://checkpoint.example/privacy"))
        XCTAssertEqual(
            LegalLinks.configuredURL("https://checkpoint.example/privacy")?.absoluteString,
            "https://checkpoint.example/privacy"
        )
        XCTAssertEqual(LegalLinks.termsOfUseURL.scheme, "https")
    }

    // MARK: - StoreKit configuration

    func testLocalStoreKitConfigMatchesMembershipProductIDs() throws {
        let subscriptions = try localSubscriptions()

        XCTAssertEqual(subscriptions.map(\.productID), MembershipProductID.all)
    }

    func testLocalStoreKitConfigUsesLaunchPricingAndPeriods() throws {
        let subscriptions = try localSubscriptions()
        let monthly = try XCTUnwrap(subscriptions.first { $0.productID == MembershipProductID.monthly })
        let yearly = try XCTUnwrap(subscriptions.first { $0.productID == MembershipProductID.yearly })

        XCTAssertEqual(monthly.displayPrice, "4.99")
        XCTAssertEqual(monthly.recurringSubscriptionPeriod, "P1M")
        XCTAssertEqual(yearly.displayPrice, "29.99")
        XCTAssertEqual(yearly.recurringSubscriptionPeriod, "P1Y")
    }

    func testCatalogDerivesLocalizedAnnualValueAndRecommendsIt() throws {
        let presentation = MembershipCatalogPresentation(
            storeProducts: [
                makeStoreProduct(
                    id: MembershipProductID.monthly,
                    price: "4.99",
                    displayPrice: "$4.99",
                    billingPeriod: .month
                ),
                makeStoreProduct(
                    id: MembershipProductID.yearly,
                    price: "29.99",
                    displayPrice: "$29.99",
                    billingPeriod: .year
                )
            ]
        )

        XCTAssertEqual(presentation.planOptions.map(\.id), [
            MembershipProductID.yearly,
            MembershipProductID.monthly
        ])
        XCTAssertEqual(presentation.defaultPlanID, MembershipProductID.yearly)

        let annual = try XCTUnwrap(presentation.planOptions.first)
        XCTAssertEqual(annual.detail, "$2.50 per month when billed annually.")
        XCTAssertEqual(annual.valueBadge, "Save 49%")
        XCTAssertTrue(annual.isRecommended)
    }

    func testCatalogOmitsSavingsWhenComparisonWouldMislead() throws {
        let mismatchedCurrency = MembershipCatalogPresentation(
            storeProducts: [
                makeStoreProduct(
                    id: MembershipProductID.monthly,
                    price: "4.99",
                    displayPrice: "$4.99",
                    billingPeriod: .month
                ),
                makeStoreProduct(
                    id: MembershipProductID.yearly,
                    price: "29.99",
                    displayPrice: "€29.99",
                    currencyCode: "EUR",
                    billingPeriod: .year
                )
            ]
        )
        let noDiscount = MembershipCatalogPresentation(
            storeProducts: [
                makeStoreProduct(
                    id: MembershipProductID.monthly,
                    price: "4.99",
                    displayPrice: "$4.99",
                    billingPeriod: .month
                ),
                makeStoreProduct(
                    id: MembershipProductID.yearly,
                    price: "59.88",
                    displayPrice: "$59.88",
                    billingPeriod: .year
                )
            ]
        )

        for presentation in [mismatchedCurrency, noDiscount] {
            XCTAssertEqual(presentation.defaultPlanID, MembershipProductID.monthly)
            let annual = try XCTUnwrap(
                presentation.planOptions.first { $0.id == MembershipProductID.yearly }
            )
            XCTAssertNil(annual.valueBadge)
            XCTAssertFalse(annual.isRecommended)
            XCTAssertEqual(
                annual.detail,
                "Billed annually through Apple for uninterrupted practice."
            )
        }
    }

    func testCatalogRejectsMislabeledPeriodsAndPreservesValidSelection() {
        let presentation = MembershipCatalogPresentation(
            storeProducts: [
                makeStoreProduct(
                    id: MembershipProductID.monthly,
                    price: "4.99",
                    displayPrice: "$4.99",
                    billingPeriod: .year
                ),
                makeStoreProduct(
                    id: MembershipProductID.yearly,
                    price: "29.99",
                    displayPrice: "$29.99",
                    billingPeriod: .year
                )
            ]
        )

        XCTAssertEqual(presentation.planOptions.map(\.id), [MembershipProductID.yearly])
        XCTAssertEqual(presentation.defaultPlanID, MembershipProductID.yearly)
        XCTAssertEqual(
            presentation.resolvedSelection(currentID: MembershipProductID.yearly),
            MembershipProductID.yearly
        )
        XCTAssertEqual(
            presentation.resolvedSelection(currentID: MembershipProductID.monthly),
            MembershipProductID.yearly
        )
    }

    func testPendingCheckoutDisablesRepeatPurchaseAndUsesAwaitingApprovalCTA() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: .pendingApproval
        )

        XCTAssertTrue(presentation.isActionInProgress)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
        XCTAssertFalse(presentation.showsPrimaryProgress)
        XCTAssertFalse(presentation.isSecondaryActionDisabled)
        XCTAssertTrue(presentation.shouldShowNoticeInPurchaseBar)
        XCTAssertEqual(presentation.buttonTitle(accessibilitySize: false), "Awaiting approval")
        XCTAssertEqual(presentation.buttonSystemImage, "clock.fill")
        XCTAssertEqual(presentation.secondaryAction, .checkPurchaseStatus)
        XCTAssertEqual(presentation.secondaryButtonTitle, "Check purchase status")
        XCTAssertEqual(presentation.secondaryButtonSystemImage, "clock.arrow.circlepath")
        XCTAssertEqual(
            presentation.secondaryButtonAccessibilityLabel,
            "Check App Store purchase status"
        )
        XCTAssertEqual(
            presentation.buttonAccessibilityLabel,
            "Purchase pending App Store approval"
        )
    }

    func testAccessibleCheckoutKeepsVisibleAndVoiceOverBillingComplete() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: nil
        )

        XCTAssertEqual(
            presentation.buttonTitle(accessibilitySize: true),
            "Subscribe — $29.99 per year"
        )
        XCTAssertEqual(
            presentation.buttonTitle(accessibilitySize: false, compact: true),
            "Subscribe — $29.99"
        )
        XCTAssertEqual(
            presentation.buttonAccessibilityLabel,
            "Subscribe to Checkpoint Pro, Annual plan, $29.99 per year"
        )
        XCTAssertFalse(presentation.isPrimaryActionDisabled)
    }

    func testCatalogRecoveryCTAHasOneClearStateWithoutInlineNotice() {
        let unavailable = MembershipCheckoutPresentation(
            selectedPlan: nil,
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: .catalogUnavailable("Could not load App Store plans yet.")
        )
        let loading = MembershipCheckoutPresentation(
            selectedPlan: nil,
            isLoadingPlans: true,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: nil
        )

        XCTAssertEqual(unavailable.buttonTitle(accessibilitySize: false), "Reload App Store plans")
        XCTAssertEqual(unavailable.buttonSystemImage, "arrow.clockwise")
        XCTAssertFalse(unavailable.isPrimaryActionDisabled)
        XCTAssertFalse(unavailable.shouldShowNoticeInPurchaseBar)

        XCTAssertEqual(loading.buttonTitle(accessibilitySize: false), "Loading plans")
        XCTAssertTrue(loading.isActionInProgress)
        XCTAssertTrue(loading.isPrimaryActionDisabled)
        XCTAssertTrue(loading.showsPrimaryProgress)
        XCTAssertTrue(loading.isSecondaryActionDisabled)
    }

    func testCatalogLoadingBlocksRestoreAndSelectionUntilItsNoticeResolutionFinishes() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            isLoadingPlans: true,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: nil
        )

        XCTAssertTrue(presentation.isActionInProgress)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
        XCTAssertTrue(presentation.showsPrimaryProgress)
        XCTAssertTrue(presentation.isSecondaryActionDisabled)
        XCTAssertEqual(presentation.buttonTitle(accessibilitySize: false), "Refreshing prices")
        XCTAssertEqual(
            presentation.buttonAccessibilityLabel,
            "Refreshing App Store prices, in progress"
        )
    }

    @MainActor
    func testPurchaseControllerRejectsOverlappingCatalogAndRestoreOperations() async {
        let loadingController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            initialStoreOperation: .loadingProducts
        )
        let restoreStarted = await loadingController.restorePurchases()

        XCTAssertFalse(restoreStarted)
        XCTAssertTrue(loadingController.isLoadingProducts)
        XCTAssertFalse(loadingController.isRestoringPurchases)

        let restoringController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            initialStoreOperation: .restoringPurchases
        )
        await restoringController.loadProducts()

        XCTAssertTrue(restoringController.isRestoringPurchases)
        XCTAssertFalse(restoringController.isLoadingProducts)

        let checkingController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            initialStoreOperation: .checkingPurchaseStatus
        )
        let overlappingRestoreStarted = await checkingController.restorePurchases()

        XCTAssertFalse(overlappingRestoreStarted)
        XCTAssertTrue(checkingController.isCheckingPurchaseStatus)
        XCTAssertFalse(checkingController.isRestoringPurchases)
    }

    func testCheckingPurchaseStatusPresentationOwnsSecondaryProgress() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isCheckingPurchaseStatus: true,
            isPurchasing: false,
            notice: .pendingApproval
        )

        XCTAssertEqual(presentation.secondaryAction, .checkPurchaseStatus)
        XCTAssertEqual(presentation.secondaryButtonTitle, "Checking purchase status")
        XCTAssertEqual(
            presentation.secondaryButtonAccessibilityLabel,
            "Checking App Store purchase status, in progress"
        )
        XCTAssertTrue(presentation.showsSecondaryProgress)
        XCTAssertTrue(presentation.isSecondaryActionDisabled)
    }

    func testActivePlanResolverIgnoresUnsupportedAndUpgradedEntitlements() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activeAnnual = makeEntitlement(
            transactionID: 10,
            productID: MembershipProductID.yearly,
            purchaseDate: now
        )
        let snapshot = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [
                    makeEntitlement(
                        transactionID: 12,
                        productID: "checkpoint.membership.unsupported",
                        purchaseDate: now.addingTimeInterval(200)
                    ),
                    makeEntitlement(
                        transactionID: 11,
                        productID: MembershipProductID.monthly,
                        purchaseDate: now.addingTimeInterval(100),
                        isUpgraded: true
                    ),
                    activeAnnual,
                ]
            )
        )

        XCTAssertEqual(snapshot.transactionID, 10)
        XCTAssertEqual(snapshot.planKind, .annual)
        XCTAssertEqual(snapshot.renewalDisposition, .active)
    }

    func testActivePlanResolverUsesNewestPurchaseDateThenStablePlanOrder() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let newest = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [
                    makeEntitlement(
                        transactionID: 1,
                        productID: MembershipProductID.monthly,
                        purchaseDate: now
                    ),
                    makeEntitlement(
                        transactionID: 2,
                        productID: MembershipProductID.yearly,
                        purchaseDate: now.addingTimeInterval(1)
                    ),
                ]
            )
        )
        let stableTie = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [
                    makeEntitlement(
                        transactionID: 3,
                        productID: MembershipProductID.yearly,
                        purchaseDate: now
                    ),
                    makeEntitlement(
                        transactionID: 4,
                        productID: MembershipProductID.monthly,
                        purchaseDate: now
                    ),
                ]
            )
        )

        XCTAssertEqual(newest.planKind, .annual)
        XCTAssertEqual(stableTie.planKind, .monthly)
    }

    func testActivePlanResolverUsesOnlyMatchingVerifiedRenewalMetadata() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entitlement = makeEntitlement(
            transactionID: 42,
            productID: MembershipProductID.yearly,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(86_400)
        )
        let matchingRenewal = MembershipRenewalRecord(
            currentProductID: MembershipProductID.yearly,
            willAutoRenew: true,
            autoRenewPreference: MembershipProductID.monthly,
            gracePeriodExpirationDate: nil
        )
        let scheduledChange = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [entitlement],
                statuses: [
                    MembershipSubscriptionStatusRecord(
                        transactionID: 42,
                        productID: MembershipProductID.yearly,
                        state: .subscribed,
                        renewal: matchingRenewal
                    )
                ]
            )
        )
        let stalePreference = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [entitlement],
                statuses: [
                    MembershipSubscriptionStatusRecord(
                        transactionID: 42,
                        productID: MembershipProductID.yearly,
                        state: .subscribed,
                        renewal: MembershipRenewalRecord(
                            currentProductID: MembershipProductID.yearly,
                            willAutoRenew: false,
                            autoRenewPreference: MembershipProductID.monthly,
                            gracePeriodExpirationDate: nil
                        )
                    )
                ]
            )
        )
        let mismatchedRenewal = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [entitlement],
                statuses: [
                    MembershipSubscriptionStatusRecord(
                        transactionID: 42,
                        productID: MembershipProductID.yearly,
                        state: .subscribed,
                        renewal: MembershipRenewalRecord(
                            currentProductID: MembershipProductID.monthly,
                            willAutoRenew: true,
                            autoRenewPreference: nil,
                            gracePeriodExpirationDate: nil
                        )
                    )
                ]
            )
        )

        XCTAssertEqual(scheduledChange.renewalDisposition, .changesTo(.monthly))
        XCTAssertEqual(stalePreference.renewalDisposition, .ends)
        XCTAssertEqual(mismatchedRenewal.renewalDisposition, .active)
    }

    func testActivePlanResolverCarriesGraceAndFamilySharingTruth() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let graceEnd = now.addingTimeInterval(86_400)
        let entitlement = makeEntitlement(
            transactionID: 48,
            productID: MembershipProductID.monthly,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(-60),
            ownership: .familyShared
        )
        let snapshot = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [entitlement],
                statuses: [
                    MembershipSubscriptionStatusRecord(
                        transactionID: 48,
                        productID: MembershipProductID.monthly,
                        state: .inGracePeriod,
                        renewal: MembershipRenewalRecord(
                            currentProductID: MembershipProductID.monthly,
                            willAutoRenew: true,
                            autoRenewPreference: nil,
                            gracePeriodExpirationDate: graceEnd
                        )
                    )
                ]
            )
        )

        XCTAssertEqual(snapshot.renewalDisposition, .gracePeriod(until: graceEnd))
        XCTAssertEqual(snapshot.ownership, .familyShared)
    }

    func testInactiveSubscriptionStatusCannotRevokeVerifiedCurrentEntitlement() throws {
        let entitlement = makeEntitlement(
            transactionID: 49,
            productID: MembershipProductID.monthly,
            purchaseDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        for state in [
            MembershipSubscriptionState.expired,
            .inBillingRetryPeriod,
            .revoked,
            .unknown,
        ] {
            let snapshot = try XCTUnwrap(
                MembershipActivePlanResolver.resolve(
                    entitlements: [entitlement],
                    statuses: [
                        MembershipSubscriptionStatusRecord(
                            transactionID: entitlement.transactionID,
                            productID: entitlement.productID,
                            state: state,
                            renewal: nil
                        )
                    ]
                )
            )

            XCTAssertEqual(snapshot.renewalDisposition, .active)
        }
    }

    @MainActor
    func testInitialPlanSnapshotIsPresentationOnlyAndDoesNotGrantAccess() {
        let snapshot = MembershipActivePlanSnapshot(
            transactionID: 1,
            productID: MembershipProductID.yearly,
            planKind: .annual,
            subscriptionGroupID: "checkpoint.pro",
            purchaseDate: Date(timeIntervalSince1970: 1_800_000_000),
            currentPeriodEnd: nil,
            renewalDisposition: .active,
            ownership: .purchased
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            initialActivePlanSnapshot: snapshot
        )

        XCTAssertFalse(controller.isMembershipUnlocked)
        XCTAssertTrue(controller.purchasedProductIDs.isEmpty)
        XCTAssertEqual(controller.activePlanSnapshot, snapshot)
    }

    @MainActor
    func testPendingStatusCheckReadsEntitlementsWithoutSynchronizingAndKeepsPendingNotice() async {
        let client = MembershipStoreClientSpy(entitlementResponses: [[]])
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client
        )
        controller.purchaseNotice = .pendingApproval

        let unlocked = await controller.checkPurchaseStatus()
        let events = await client.recordedEvents()

        XCTAssertFalse(unlocked)
        XCTAssertEqual(controller.purchaseNotice, .pendingApprovalChecked)
        XCTAssertFalse(controller.isCheckingPurchaseStatus)
        XCTAssertEqual(events, [.readEntitlements])
    }

    @MainActor
    func testPendingStatusCheckClearsPendingAndPublishesActiveAnnualSnapshot() async throws {
        let entitlement = makeEntitlement(
            transactionID: 77,
            productID: MembershipProductID.yearly,
            purchaseDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let client = MembershipStoreClientSpy(entitlementResponses: [[entitlement]])
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client
        )
        controller.purchaseNotice = .pendingApproval
        var publishedEntitlement = false
        controller.onMembershipEntitlementChange = { publishedEntitlement = $0 }

        let unlocked = await controller.checkPurchaseStatus()
        let events = await client.recordedEvents()

        XCTAssertTrue(unlocked)
        XCTAssertTrue(publishedEntitlement)
        XCTAssertNil(controller.purchaseNotice)
        XCTAssertEqual(controller.activePlanSnapshot?.planKind, .annual)
        XCTAssertEqual(events, [.readEntitlements])
    }

    @MainActor
    func testEntitlementRefreshEnrichesSnapshotWithoutChangingAccessAuthority() async {
        let groupID = "checkpoint.pro"
        let entitlement = makeEntitlement(
            transactionID: 78,
            productID: MembershipProductID.yearly,
            purchaseDate: Date(timeIntervalSince1970: 1_800_000_000),
            expirationDate: Date(timeIntervalSince1970: 1_900_000_000),
            subscriptionGroupID: groupID
        )
        let client = MembershipStoreClientSpy(
            entitlementResponses: [[entitlement]],
            statuses: [
                MembershipSubscriptionStatusRecord(
                    transactionID: entitlement.transactionID,
                    productID: entitlement.productID,
                    state: .subscribed,
                    renewal: MembershipRenewalRecord(
                        currentProductID: entitlement.productID,
                        willAutoRenew: true,
                        autoRenewPreference: nil,
                        gracePeriodExpirationDate: nil
                    )
                )
            ]
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client
        )

        let unlocked = await controller.refreshEntitlements()
        let events = await client.recordedEvents()

        XCTAssertTrue(unlocked)
        XCTAssertEqual(controller.activePlanSnapshot?.renewalDisposition, .renews)
        XCTAssertEqual(events, [.readEntitlements, .readStatuses(groupID)])
    }

    @MainActor
    func testStatusLookupFailurePreservesVerifiedBaseSnapshot() async {
        let groupID = "checkpoint.pro"
        let entitlement = makeEntitlement(
            transactionID: 79,
            productID: MembershipProductID.monthly,
            purchaseDate: Date(timeIntervalSince1970: 1_800_000_000),
            subscriptionGroupID: groupID
        )
        let client = MembershipStoreClientSpy(
            entitlementResponses: [[entitlement]],
            statusLookupFails: true
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client
        )

        let unlocked = await controller.refreshEntitlements()

        XCTAssertTrue(unlocked)
        XCTAssertEqual(controller.activePlanSnapshot?.transactionID, entitlement.transactionID)
        XCTAssertEqual(controller.activePlanSnapshot?.renewalDisposition, .active)
    }

    @MainActor
    func testRestoreSynchronizesBeforeReadingAndReportsNoSubscription() async {
        let client = MembershipStoreClientSpy(entitlementResponses: [[]])
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client
        )

        let unlocked = await controller.restorePurchases()
        let events = await client.recordedEvents()

        XCTAssertFalse(unlocked)
        XCTAssertEqual(
            controller.purchaseNotice,
            .information("No active Checkpoint Pro subscription was found.")
        )
        XCTAssertEqual(events, [.synchronize, .readEntitlements])
    }

    @MainActor
    func testRestoreDoesNotReadEntitlementsWhenSynchronizationFails() async {
        let client = MembershipStoreClientSpy(
            entitlementResponses: [[]],
            synchronizationFails: true
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client
        )

        let unlocked = await controller.restorePurchases()
        let events = await client.recordedEvents()

        XCTAssertFalse(unlocked)
        XCTAssertEqual(controller.purchaseNotice, .failure("Could not restore purchases yet."))
        XCTAssertEqual(events, [.synchronize])
    }

    @MainActor
    func testOlderEntitlementRefreshCannotOverwriteNewerSnapshot() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let annual = makeEntitlement(
            transactionID: 2,
            productID: MembershipProductID.yearly,
            purchaseDate: now
        )
        let client = GatedMembershipStoreClient()
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client
        )

        let olderRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        await client.waitForRequestCount(1)
        let newerRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        await client.waitForRequestCount(2)

        await client.resumeRequest(1, with: [annual])
        _ = await newerRefresh.value
        await client.resumeRequest(0, with: [])
        _ = await olderRefresh.value

        XCTAssertTrue(controller.isMembershipUnlocked)
        XCTAssertEqual(controller.activePlanSnapshot?.transactionID, annual.transactionID)
        XCTAssertEqual(controller.purchasedProductIDs, [MembershipProductID.yearly])
    }

    @MainActor
    func testOlderStatusLookupCannotOverwriteNewerSnapshot() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let annual = makeEntitlement(
            transactionID: 3,
            productID: MembershipProductID.yearly,
            purchaseDate: now,
            subscriptionGroupID: "checkpoint.pro"
        )
        let monthly = makeEntitlement(
            transactionID: 4,
            productID: MembershipProductID.monthly,
            purchaseDate: now.addingTimeInterval(60)
        )
        let client = GatedStatusMembershipStoreClient(
            entitlementResponses: [[annual], [monthly]]
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client
        )

        let olderRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        await client.waitForStatusRequest()
        let newerRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        _ = await newerRefresh.value

        await client.resumeStatusRequest(
            with: [
                MembershipSubscriptionStatusRecord(
                    transactionID: annual.transactionID,
                    productID: annual.productID,
                    state: .subscribed,
                    renewal: MembershipRenewalRecord(
                        currentProductID: annual.productID,
                        willAutoRenew: true,
                        autoRenewPreference: nil,
                        gracePeriodExpirationDate: nil
                    )
                )
            ]
        )
        _ = await olderRefresh.value

        XCTAssertEqual(controller.activePlanSnapshot?.transactionID, monthly.transactionID)
        XCTAssertEqual(controller.activePlanSnapshot?.planKind, .monthly)
        XCTAssertEqual(controller.activePlanSnapshot?.renewalDisposition, .active)
    }

    func testPendingApprovalSurvivesCatalogReloadUntilEntitlementUnlocks() {
        let afterSuccessfulCatalogLoad = MembershipPurchaseNotice.resolvingCatalogLoad(
            current: .pendingApproval,
            catalogNotice: nil
        )
        let afterFailedCatalogLoad = MembershipPurchaseNotice.resolvingCatalogLoad(
            current: afterSuccessfulCatalogLoad,
            catalogNotice: .catalogUnavailable("Could not load App Store plans yet.")
        )
        let whileStillLocked = MembershipPurchaseNotice.resolvingEntitlementRefresh(
            current: afterFailedCatalogLoad,
            isUnlocked: false
        )
        let afterApproval = MembershipPurchaseNotice.resolvingEntitlementRefresh(
            current: whileStillLocked,
            isUnlocked: true
        )

        XCTAssertEqual(afterSuccessfulCatalogLoad, .pendingApproval)
        XCTAssertEqual(afterFailedCatalogLoad, .pendingApproval)
        XCTAssertEqual(whileStillLocked, .pendingApproval)
        XCTAssertNil(afterApproval)
    }

    func testCatalogReloadReplacesNonpendingNoticeWithCurrentCatalogState() {
        let unavailable = MembershipPurchaseNotice.resolvingCatalogLoad(
            current: .failure("A previous purchase failed."),
            catalogNotice: .catalogUnavailable("Could not load App Store plans yet.")
        )
        let recovered = MembershipPurchaseNotice.resolvingCatalogLoad(
            current: unavailable,
            catalogNotice: nil
        )

        XCTAssertEqual(
            unavailable,
            .catalogUnavailable("Could not load App Store plans yet.")
        )
        XCTAssertNil(recovered)
    }

    func testOnlyActionableNoCatalogNoticesRenderSeparately() {
        XCTAssertFalse(MembershipPurchaseNotice.pendingApproval.shouldDisplayWithoutSelectedPlan)
        XCTAssertFalse(
            MembershipPurchaseNotice.pendingApprovalChecked.shouldDisplayWithoutSelectedPlan
        )
        XCTAssertFalse(
            MembershipPurchaseNotice.catalogUnavailable("Catalog unavailable.")
                .shouldDisplayWithoutSelectedPlan
        )
        XCTAssertTrue(
            MembershipPurchaseNotice.failure("Restore failed.")
                .shouldDisplayWithoutSelectedPlan
        )
        XCTAssertTrue(
            MembershipPurchaseNotice.information("No subscription found.")
                .shouldDisplayWithoutSelectedPlan
        )
    }

    private func localSubscriptions() throws -> [StoreKitSubscription] {
        let url = try XCTUnwrap(
            Bundle(for: StoreKitPaymentTests.self).url(forResource: "CheckpointProducts", withExtension: "storekit")
        )
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(StoreKitConfiguration.self, from: data)

        return config.subscriptionGroups.flatMap(\.subscriptions)
    }

    private func makeStoreProduct(
        id: String,
        price: String,
        displayPrice: String,
        currencyCode: String = "USD",
        billingPeriod: MembershipBillingPeriod
    ) -> MembershipStoreProduct {
        MembershipStoreProduct(
            id: id,
            price: Decimal(string: price)!,
            displayPrice: displayPrice,
            currencyCode: currencyCode,
            locale: Locale(identifier: "en_US"),
            billingPeriod: billingPeriod
        )
    }

    private func makeAnnualPlanOption() -> MembershipPlanOption {
        MembershipPlanOption(
            id: MembershipProductID.yearly,
            title: "Annual",
            displayPrice: "$29.99",
            cadence: "per year",
            detail: "$2.50 per month when billed annually.",
            valueBadge: "Save 49%",
            isRecommended: true
        )
    }

    private func makeEntitlement(
        transactionID: UInt64,
        productID: String,
        purchaseDate: Date,
        expirationDate: Date? = nil,
        subscriptionGroupID: String? = nil,
        isUpgraded: Bool = false,
        ownership: MembershipPlanOwnership = .purchased
    ) -> MembershipEntitlementRecord {
        MembershipEntitlementRecord(
            transactionID: transactionID,
            productID: productID,
            purchaseDate: purchaseDate,
            expirationDate: expirationDate,
            subscriptionGroupID: subscriptionGroupID,
            isUpgraded: isUpgraded,
            ownership: ownership
        )
    }
}

private actor MembershipStoreClientSpy: MembershipStoreClient {
    enum Event: Equatable, Sendable {
        case synchronize
        case readEntitlements
        case readStatuses(String)
    }

    enum Failure: Error {
        case synchronization
        case status
    }

    private var entitlementResponses: [[MembershipEntitlementRecord]]
    private let statuses: [MembershipSubscriptionStatusRecord]
    private let synchronizationFails: Bool
    private let statusLookupFails: Bool
    private var events: [Event] = []

    init(
        entitlementResponses: [[MembershipEntitlementRecord]],
        statuses: [MembershipSubscriptionStatusRecord] = [],
        synchronizationFails: Bool = false,
        statusLookupFails: Bool = false
    ) {
        self.entitlementResponses = entitlementResponses
        self.statuses = statuses
        self.synchronizationFails = synchronizationFails
        self.statusLookupFails = statusLookupFails
    }

    func currentMembershipEntitlements() async -> [MembershipEntitlementRecord] {
        events.append(.readEntitlements)
        guard !entitlementResponses.isEmpty else { return [] }
        return entitlementResponses.removeFirst()
    }

    func subscriptionStatuses(
        for subscriptionGroupID: String
    ) async throws -> [MembershipSubscriptionStatusRecord] {
        events.append(.readStatuses(subscriptionGroupID))
        if statusLookupFails {
            throw Failure.status
        }
        return statuses
    }

    func synchronize() async throws {
        events.append(.synchronize)
        if synchronizationFails {
            throw Failure.synchronization
        }
    }

    func recordedEvents() -> [Event] {
        events
    }
}

private actor GatedMembershipStoreClient: MembershipStoreClient {
    private var issuedRequestCount = 0
    private var continuations: [Int: CheckedContinuation<[MembershipEntitlementRecord], Never>] = [:]

    func currentMembershipEntitlements() async -> [MembershipEntitlementRecord] {
        let requestIndex = issuedRequestCount
        issuedRequestCount += 1
        return await withCheckedContinuation { continuation in
            continuations[requestIndex] = continuation
        }
    }

    func subscriptionStatuses(
        for _: String
    ) async throws -> [MembershipSubscriptionStatusRecord] {
        []
    }

    func synchronize() async throws {}

    func waitForRequestCount(_ count: Int) async {
        while issuedRequestCount < count {
            await Task.yield()
        }
    }

    func resumeRequest(
        _ index: Int,
        with entitlements: [MembershipEntitlementRecord]
    ) {
        continuations.removeValue(forKey: index)?.resume(returning: entitlements)
    }
}

private actor GatedStatusMembershipStoreClient: MembershipStoreClient {
    private var entitlementResponses: [[MembershipEntitlementRecord]]
    private var statusRequestWasIssued = false
    private var statusContinuation: CheckedContinuation<
        [MembershipSubscriptionStatusRecord],
        Never
    >?

    init(entitlementResponses: [[MembershipEntitlementRecord]]) {
        self.entitlementResponses = entitlementResponses
    }

    func currentMembershipEntitlements() async -> [MembershipEntitlementRecord] {
        guard !entitlementResponses.isEmpty else { return [] }
        return entitlementResponses.removeFirst()
    }

    func subscriptionStatuses(
        for _: String
    ) async throws -> [MembershipSubscriptionStatusRecord] {
        statusRequestWasIssued = true
        return await withCheckedContinuation { continuation in
            statusContinuation = continuation
        }
    }

    func synchronize() async throws {}

    func waitForStatusRequest() async {
        while !statusRequestWasIssued {
            await Task.yield()
        }
    }

    func resumeStatusRequest(with statuses: [MembershipSubscriptionStatusRecord]) {
        statusContinuation?.resume(returning: statuses)
        statusContinuation = nil
    }
}

// MARK: - StoreKit decoding fixtures

private struct StoreKitConfiguration: Decodable {
    var subscriptionGroups: [StoreKitSubscriptionGroup]
}

private struct StoreKitSubscriptionGroup: Decodable {
    var subscriptions: [StoreKitSubscription]
}

private struct StoreKitSubscription: Decodable {
    var productID: String
    var displayPrice: String
    var recurringSubscriptionPeriod: String
}
