# Monetization Plan

Checkpoint is currently planned as a paid/full-access app rather than a freemium app with a Pro tier.

## Recommendation

Launch as one paid product with all current features included:

- Multiple goal profiles with separate focus areas, question difficulty, practice sets, history, reports, and Skill Maps.
- Custom checkpoint rules, including question count, passing score, and 5/10/15/30 minute unlock windows.
- Larger cached question banks, automatic refill, and adaptive Study Assist.
- App blocking, temporary unlocks, emergency pass, history, reports, and diagnostics.

This avoids making the free version strong enough to undercut conversion, and it keeps the app simpler: users buy Checkpoint, then they get Checkpoint.

## Launch Pricing

The simplest launch path is paid app pricing in App Store Connect. The current candidate price remains $4.99, with no in-app Free/Pro gate in the code.

Before selling the app:

1. Make sure the Account Holder accepts the Paid Apps Agreement in App Store Connect.
2. Configure banking and tax information.
3. Set the app price under Pricing and Availability.
4. Re-run TestFlight validation after pricing, entitlement, backend, and real-device Screen Time work are complete.

If backend AI usage becomes expensive enough that one-time paid pricing is risky, revisit an app-wide subscription later. Do not revive a feature-level Free/Pro split unless user research clearly shows users understand and value that split.

## Cost Profile

- Local/offline question generation has no per-user AI cost.
- Apple Foundation Models generation has no server bill, but only works on supported devices.
- Backend AI generation can create variable cost. Keep it batch-based, quota-limited, cooldown-protected, and cached locally.
- Paid-only launch reduces free-user backend exposure, but does not remove the need for backend quotas.

## Current Implementation

- StoreKit purchase UI and Free/Pro gates have been removed from the app target.
- Runtime behavior grants the full feature set.
- Payment is expected to happen through App Store app pricing at launch, not an in-app feature paywall.

## References

- Apple App Store Connect Help: Set a price
  https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/
