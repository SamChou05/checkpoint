# Monetization Plan

Checkpoint is currently planned as a starter-membership app.

## Recommendation

Let users experience the complete primary loop before payment:

- Create the first goal.
- Generate a starter question set.
- Choose blocked apps.
- Clear checkpoints from blocked-app attempts.
- Temporarily unlock apps after passing.

Ask for membership when the app needs to become more powerful or ongoing:

- Changing or adding goal profiles.
- Keeping fresh generated checkpoints ready after the starter set runs low.
- Building the larger member question bank.
- Using adaptive Study Assist and level-up regeneration.

This gives users a real taste of the product while keeping backend AI exposure bounded by a finite starter bank.

## Launch Pricing

Current candidate pricing:

- Monthly membership: `$4.99/mo`
- Annual membership: `$29.99/yr`

StoreKit product IDs in the app:

- `checkpoint.membership.monthly`
- `checkpoint.membership.yearly`

Before selling membership:

1. Make sure the Account Holder accepts the Paid Apps Agreement in App Store Connect.
2. Configure banking and tax information.
3. Create matching auto-renewable subscription products in App Store Connect.
4. Add the products to a subscription group.
5. Verify StoreKit purchase and restore in TestFlight.
6. Re-run TestFlight validation after pricing, entitlement, backend, and real-device Screen Time work are complete.

## Cost Profile

- Local/offline question generation has no per-user AI cost.
- Apple Foundation Models generation has no server bill, but only works on supported devices.
- Backend AI generation can create variable cost. Keep it batch-based, quota-limited, cooldown-protected, and cached locally.
- The starter plan should cap free backend exposure to the first goal and starter question bank.
- Membership revenue should cover ongoing backend refreshes, larger banks, and goal switching.

## Current Implementation

- StoreKit membership UI is in the app target.
- A checked-in local StoreKit configuration supports Debug purchase and restore testing from the shared `Checkpoint` scheme.
- App Store Connect still needs matching subscription products before TestFlight purchase validation.
- Runtime behavior starts users on `Starter`.
- Starter users can create the first goal and use the core blocker/checkpoint/unlock flow.
- Starter users are prompted positively for membership when they try to change goals or when fresh generation is needed.
- Member users get goal profiles, larger question banks, automatic refresh, and adaptive Study Assist.

## References

- Apple In-App Purchase
  https://developer.apple.com/in-app-purchase/
- Apple App Store Review Guidelines
  https://developer.apple.com/app-store/review/guidelines/
