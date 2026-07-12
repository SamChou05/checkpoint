# StoreKit Launch Setup

Checkpoint uses StoreKit auto-renewable subscriptions for the Free-to-Pro upgrade path.

## Product IDs

The app expects these exact product IDs:

- `checkpoint.membership.monthly`
- `checkpoint.membership.yearly`

The local Xcode test configuration lives at:

- `Checkpoint/Config/CheckpointProducts.storekit`

The shared `Checkpoint` scheme points its Run action to that file, so local Xcode runs can load test products before App Store Connect products exist.

Debug builds now start from the real StoreKit entitlement state. To preview Pro without making a StoreKit transaction, explicitly add the environment variable `CHECKPOINT_DEBUG_PRO_ENTITLEMENT=1` to the Run action. Keep it absent or disabled for Free-to-Pro purchase, restore, expiration, and cancellation testing. Release builds ignore this override.

For a persistent on-device QA build that remains Pro after a Home-screen relaunch, add `CHECKPOINT_DEBUG_PRO_BUILD` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` for that Debug build only. The condition is absent by default, and Release builds ignore it even if it is supplied.

## Local Xcode Testing

1. Open `Checkpoint.xcodeproj`.
2. Select the shared `Checkpoint` scheme.
3. Run the app on a simulator or development device.
4. Open Settings > Choose your plan.
5. Confirm the Pro card loads StoreKit prices.
6. Purchase the monthly or annual test product.
7. Confirm the app switches from Free to Pro.
8. Use Xcode's StoreKit transaction manager to expire, cancel, or clear the test subscription.
9. Return the app to foreground and confirm it falls back to Free when there is no active entitlement.
10. Use Restore purchases and confirm it restores Pro only when an active entitlement exists.

Local StoreKit data is only for Xcode testing. It does not upload to App Store Connect and will not be used by App Store-signed builds.

## App Store Connect Setup

Before TestFlight purchase testing:

1. Accept the Paid Apps Agreement.
2. Complete banking and tax setup.
3. Create one auto-renewable subscription group named `Checkpoint Pro`.
4. Add a monthly subscription with product ID `checkpoint.membership.monthly`.
5. Add an annual subscription with product ID `checkpoint.membership.yearly`.
6. Set launch pricing to `$4.99/mo` and `$29.99/yr`, unless pricing changes before launch.
7. Add English display names and descriptions that match the plan page.
8. Attach the first in-app purchases to the app version when submitting for review.
9. Test purchases and restore through TestFlight with a sandbox tester.
10. Re-test cancellation, expiration, and downgrade behavior before submission.

## Runtime Expectations

- New installs start on Free without an active StoreKit entitlement.
- A verified active monthly or annual entitlement switches the app to Pro.
- Revoked or expired transactions do not unlock Pro.
- Purchase and restore refresh entitlements immediately.
- Foreground refresh brings the app back to Free after a cancellation or expiration.
- The plan UI uses App Store product prices when StoreKit returns products.

## Launch Checklist

- [ ] Local StoreKit products load in Debug.
- [ ] Local StoreKit monthly purchase switches the app to Pro.
- [ ] Local StoreKit annual purchase switches the app to Pro.
- [ ] Local StoreKit cleared/expired subscription returns the app to Free.
- [ ] Restore purchases works with an active local entitlement.
- [ ] App Store Connect products exist with matching IDs.
- [ ] TestFlight sandbox purchase switches the app to Pro.
- [ ] TestFlight restore switches the app to Pro only with an active entitlement.
- [ ] TestFlight cancellation or expiration returns the app to Free on refresh.
