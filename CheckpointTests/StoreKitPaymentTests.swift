import XCTest
@testable import Checkpoint

final class StoreKitPaymentTests: XCTestCase {
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

    private func localSubscriptions() throws -> [StoreKitSubscription] {
        let url = try XCTUnwrap(
            Bundle(for: StoreKitPaymentTests.self).url(forResource: "CheckpointProducts", withExtension: "storekit")
        )
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(StoreKitConfiguration.self, from: data)

        return config.subscriptionGroups.flatMap(\.subscriptions)
    }
}

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
