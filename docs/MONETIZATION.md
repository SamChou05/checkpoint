# Monetization Plan

Checkpoint should start thinking about payment now, but should not block the core Screen Time loop behind a paywall until the real-device shield/unshield/re-lock workflow has passed TestFlight.

## Recommendation

Launch with a free core and one Pro subscription group.

- Free: one active goal, local/offline question generation, basic checkpoint history, default strictness, restricted app blocking.
- Pro: advanced strictness controls, larger question banks, unlimited refreshes, richer competency analytics, multiple goals, and future import/sync features.
- Initial price test: $4.99/month and $29.99/year.

This keeps the first release reviewable and useful while leaving room to monetize users who want deeper academic tracking.

## Implemented Free/Pro Split

The current app has a StoreKit-ready freemium shell:

- Free keeps the core blocker loop usable: one active goal, local questions, the default 5-question session, 4 correct answers required, app blocking, and temporary unlock.
- Free gets 2 question-bank refreshes per goal.
- Pro unlocks advanced strictness tuning, unlimited refreshes, and larger provider target batches.
- The paywall uses StoreKit product IDs and restore hooks, but App Store Connect products and a local StoreKit configuration file still need to be created before real purchases can complete.
- The blocker recovery path is not paywalled.

## Cost Profile

The freemium gates do not create meaningful new infrastructure cost by themselves.

- StoreKit has no fixed monthly fee, but Apple takes its App Store commission on paid subscriptions.
- Local/offline question generation has no per-user AI cost.
- Apple Foundation Models generation has no server bill, but only works on supported devices.
- Backend AI generation can create variable cost. Keep it batch-based, quota-limited, and preferably tied to Pro refresh limits before using it broadly.
- The free refresh limit exists partly to control backend spend if backend generation becomes active.

## Product IDs

Use stable product IDs before creating App Store Connect products:

- Subscription group: `Checkpoint Pro`
- Monthly: `checkpoint.pro.monthly`
- Yearly: `checkpoint.pro.yearly`

## Implementation Order

1. Validate the real iPhone Screen Time loop.
2. Create the subscription group and auto-renewable subscription products in App Store Connect.
3. Add a local StoreKit configuration file for simulator purchase testing.
4. Verify StoreKit product loading, purchase, restore, and entitlement refresh in TestFlight.
5. Add subscription management links and final App Review notes.
6. Re-check that only Pro features are gated, not the user's ability to recover from a blocked app.

## App Review Notes

The core blocker should remain understandable without payment. If Pro is present, explain that payment unlocks advanced study and configuration features, while the base app remains usable for voluntary app blocking and checkpoint attempts.

## References

- Apple App Store Connect: Offer auto-renewable subscriptions  
  https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/
- Apple StoreKit current entitlements  
  https://developer.apple.com/documentation/storekit/transaction/currententitlements
