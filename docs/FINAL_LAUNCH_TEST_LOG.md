# Final Launch Test Log

Use this as the source of truth for the final TestFlight and App Store readiness pass. Keep each entry dated, include the device/build, and link the follow-up commit when a test creates work.

Last updated: July 10, 2026 EDT.

## Latest Local Validation

| Date | Area | Build or Device | Result | Notes |
| --- | --- | --- | --- | --- |
| July 10, 2026 | Simulator XCTest suite | Xcode 26.4.1, iPhone 17 simulator | Pass | 211 passed, 0 failed after backend-consent, reserve deletion-ordering, legal-link, and release configuration changes. |
| July 10, 2026 | Bedrock question service | Python 3.12 unittest + Ruff + SAM CLI | Pass | 106 passed, 0 failed; SAM lint and build passed. |
| July 10, 2026 | AWS production deployment | `checkpoint-question-service-prod`, `us-east-1` | Pass | Authenticated generation and the complete reserve lifecycle passed against the live stack; unauthenticated requests returned 401. |
| July 10, 2026 | AWS production controls | DynamoDB, SQS, EventBridge, Lambda | Pass | TTL and encryption enabled; DLQ redrive/visibility and recovery schedule verified; smoke invocations reported zero Lambda errors. |
| July 10, 2026 | AWS production observability | CloudWatch Logs and alarms | Pass | Both Lambda functions use stack-managed 30-day log groups; endpoint 5xx, worker error, stale reserve queue, and DLQ alarms were deployed and reported `OK` after an authenticated one-question smoke test. |
| July 10, 2026 | Physical-device Release archive | Checkpoint 1.0 (2) | Pass | Archive contains the live backend endpoint, rotated Keychain-backed credential, and all three extensions. |
| July 10, 2026 | Release credential handling | Checkpoint 1.0 (2) | Pass | The exposed credential was rotated, the earlier archive was deleted, unauthenticated requests still return 401, and a fresh archive was rebuilt and verified against the replacement credential. |
| July 10, 2026 | App Store export | Checkpoint 1.0 (2) | Blocked | Xcode reported `No Accounts` and no App Store profiles for the app and three extensions. Sign in and verify Family Controls distribution access before retrying. |
| July 10, 2026 | Final release archive | Post-consent/legal-link candidate | Pending | Rebuild from the final commit after owner-approved Privacy and Support URLs are configured; the current development archive is retained only for technical validation. |
| June 4, 2026 | Simulator XCTest suite | XcodeBuildMCP, iPhone 17 simulator | Pass | 101 passed, 0 failed after StoreKit config checks were added. |
| June 4, 2026 | Simulator app launch | XcodeBuildMCP, iPhone 17 simulator | Pass | Debug app built, installed, and launched without diagnostics. |
| June 4, 2026 | Release simulator build | Xcode 26.4.1, iPhone 17 simulator | Pass | Release build completed successfully after launch-readiness changes. |
| June 4, 2026 | Physical iPhone Debug build | `Shampoo`, iOS device ID `00008110-00123D940E40401E` | Pass | Debug build signed with current development profile. |
| June 4, 2026 | Physical iPhone install and launch | `Shampoo`, devicectl ID `17FB15E3-533A-5CF5-B134-47ACFD5DDF91` | Pass | App installed and launched with bundle ID `com.samchou.checkpoint`. |
| June 4, 2026 | Physical iPhone reinstall after launch polish | `Shampoo`, devicectl ID `17FB15E3-533A-5CF5-B134-47ACFD5DDF91` | Partial | Updated app installed; launch retry was blocked because the iPhone was locked. |
| June 4, 2026 | StoreKit config contract | XCTest | Pass | Local StoreKit config product IDs, periods, and launch prices match app constants. |
| June 4, 2026 | Bedrock question service unit tests | Python unittest | Pass | 15 passed, 0 failed, including fail-closed backend auth and rate-limit coverage. |

## Final Tests Before TestFlight

These must pass before broader TestFlight testing.

- [x] Production backend credential was rotated after the July 10 archive-inspection exposure; the earlier archive was deleted and build 2 was rebuilt and verified.
- [ ] Fresh archive and exported IPA have a write-once manifest and verified SHA-256 checksums from `docs/RELEASE_ARTIFACTS.md`.
- [ ] Local StoreKit run from Xcode shared `Checkpoint` scheme loads Monthly and Annual products.
- [ ] Local StoreKit Monthly purchase switches Free to Pro.
- [ ] Local StoreKit Annual purchase switches Free to Pro.
- [ ] Local StoreKit expired or cleared subscription returns Pro to Free on foreground refresh.
- [ ] Restore purchases restores Pro only when a current local entitlement exists.
- [x] Release build uses the intended backend endpoint or intentionally falls back to Apple/local generation.
- [x] Exposed backend has `CHECKPOINT_BACKEND_TOKEN` configured and does not set `ALLOW_UNAUTHENTICATED_BACKEND=true`.
- [x] Backend endpoint rejects unauthenticated requests.
- [ ] Backend endpoint rate limits by install ID and IP before calling Bedrock.
- [ ] Backend question batch generation returns valid, unique, on-target choices for LSAT, technical interview, and school exam goals.
- [ ] Latest installed iPhone build is launched once while the iPhone is unlocked.
- [ ] Physical iPhone shield loop passes the full real-device plan below.

## Real Shield Loop

Run on a physical iPhone before TestFlight and again before App Store submission.

- [ ] Install a signed build.
- [ ] Create or select a goal.
- [ ] Confirm Screen Time authorization is granted.
- [ ] Choose at least one protected app and one category.
- [ ] Start protection and verify selected targets are blocked.
- [ ] Open a protected app and confirm the custom Checkpoint shield appears.
- [ ] Switch goals in Checkpoint and confirm the shield shows the new current goal.
- [ ] Tap the shield action and confirm Checkpoint opens.
- [ ] Confirm the protected-app checkpoint appears automatically.
- [ ] Fail a checkpoint and confirm protected apps remain locked.
- [ ] Retry and confirm missed questions are prioritized.
- [ ] Pass with the configured score and confirm protected apps unblock for the configured duration.
- [ ] Confirm protected apps re-lock when the break expires.
- [ ] Force quit and relaunch Checkpoint during an unlock window and after expiration.
- [ ] Restart the phone and confirm the intended protection state is recovered.

## TestFlight Purchase Pass

Run after App Store Connect products exist and a TestFlight build is available.

- [ ] App Store Connect subscription group exists: `Checkpoint Pro`.
- [ ] Monthly product exists: `checkpoint.membership.monthly`.
- [ ] Annual product exists: `checkpoint.membership.yearly`.
- [ ] Paid Apps Agreement, banking, and tax setup are complete.
- [ ] TestFlight app shows localized StoreKit prices.
- [ ] Sandbox Monthly purchase switches Free to Pro.
- [ ] Sandbox Annual purchase switches Free to Pro.
- [ ] Restore purchases switches Free to Pro only with an active entitlement.
- [ ] Subscription expiration/cancellation returns Pro to Free on foreground refresh.
- [ ] Free user can still complete the first-goal protected-app loop.
- [ ] Free user is prompted for Pro when trying to create or switch beyond the first goal.
- [ ] Free user is prompted for Pro when ongoing fresh generation is needed.
- [ ] Pro user can create and switch among up to 5 goals.

## App Store Submission Pass

Run after TestFlight purchase and shield-loop validation.

- [ ] Family Controls distribution entitlement is approved for shipping bundle IDs.
- [ ] App privacy labels match local storage, Screen Time state, backend generation, and StoreKit purchases.
- [ ] Hosted privacy policy URL is live.
- [ ] Support URL is live.
- [ ] App Store screenshots are captured from the current UI.
- [ ] App subtitle, description, keywords, and promotional text are final.
- [ ] App Review notes explain Family Controls, Managed Settings, Device Activity, App Groups, AI generation, and unlock/re-lock behavior.
- [ ] First in-app purchases are attached to the app version before review.
- [ ] Age rating and content rights are finalized.
- [ ] No secrets are tracked in git.
