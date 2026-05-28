# Monetization Plan

Checkpoint should start thinking about payment now, but should not block the core Screen Time loop behind a paywall until the real-device shield/unshield/re-lock workflow has passed TestFlight.

## Recommendation

Launch with a free core and one Pro subscription group.

- Free: one active goal, local/offline question generation, basic checkpoint history, default strictness, restricted app blocking.
- Pro: multiple goals, advanced difficulty controls, richer competency analytics, larger question banks, unlimited refreshes, stricter focus modes, and future import/sync features.
- Initial price test: yearly-first at about $29.99/year, with an optional monthly plan around $4.99/month.

This keeps the first release reviewable and useful while leaving room to monetize users who want deeper academic tracking.

## Product IDs

Use stable product IDs before creating App Store Connect products:

- Subscription group: `Checkpoint Pro`
- Monthly: `checkpoint.pro.monthly`
- Yearly: `checkpoint.pro.yearly`

## Implementation Order

1. Validate the real iPhone Screen Time loop.
2. Create the subscription group and auto-renewable subscription products in App Store Connect.
3. Add StoreKit 2 entitlement state in the app.
4. Add a local StoreKit configuration file for simulator purchase testing.
5. Gate only Pro features, not the user's ability to recover from a blocked app.
6. Add restore purchases, subscription management links, and App Review notes.

## App Review Notes

The core blocker should remain understandable without payment. If Pro is present, explain that payment unlocks advanced study and configuration features, while the base app remains usable for voluntary app blocking and checkpoint attempts.

## References

- Apple App Store Connect: Offer auto-renewable subscriptions  
  https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/
- Apple StoreKit current entitlements  
  https://developer.apple.com/documentation/storekit/transaction/currententitlements
