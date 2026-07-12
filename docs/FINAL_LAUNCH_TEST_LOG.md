# Final Launch Test Log

Use this as the source of truth for the final TestFlight and App Store readiness pass. Keep each entry dated, include the device/build, and link the follow-up commit when a test creates work.

Last updated: July 12, 2026 EDT.

## Latest Local Validation

| Date | Area | Build or Device | Result | Notes |
| --- | --- | --- | --- | --- |
| July 12, 2026 | Full simulator XCTest suite | Xcode 26.4.1, iPhone 17 simulator | Pass | 192 passed, 0 failed with normal simulator signing and parallel testing disabled, including explicit Screen Time authorization, approved-relaunch, failed-erasure write gates, and crash-safe snapshot-erasure recovery. |
| July 12, 2026 | Bedrock question service unit tests | Python 3.12 `unittest` | Pass | 88 passed, 0 failed; Ruff, Python compilation, and SAM lint validation also passed. |
| July 12, 2026 | Release simulator build, static analysis, and signed device compile | Xcode 26.4.1 | Pass | Release simulator build and analysis completed; the generic iPhone Debug bundle passed strict deep code-sign verification. |
| July 11, 2026 | Full simulator XCTest suite | Xcode 26.4.1, iPhone 17 simulator | Pass | 183 passed, 0 failed with normal simulator signing and parallel testing disabled. Simulator signing must remain enabled because App Group file-fallback tests exercise the simulated entitlement path. |
| July 11, 2026 | Bedrock question service unit tests | Python 3.12 `unittest` | Pass | 88 passed, 0 failed, including backend auth, HMAC quotas, Guardrail handling, deadline/call budgets, deployment-template contract, cross-domain prompt contract, and question-quality coverage. |
| July 11, 2026 | Release simulator build and static analysis | Xcode 26.4, generic iOS simulator | Pass | App and all three Screen Time extensions built successfully; `xcodebuild analyze` completed successfully. |
| July 11, 2026 | Physical build 3 → 4 upgrade install | Physical test iPhone (identifier recorded locally) | Pass | Signed Debug build 4 verified and installed directly over build 3 without uninstalling, preserving the data needed for migration inspection. Device reports version 1.0, build 4. |
| July 11, 2026 | Physical build 4 launch | Physical test iPhone (identifier recorded locally) | Pass | Build 4 launched successfully after the phone was unlocked. Visually confirm the migrated goal, progress, protection selection, and Free entitlement before any reset. |
| June 4, 2026 | Simulator XCTest suite | XcodeBuildMCP, iPhone 17 simulator | Pass | 101 passed, 0 failed after StoreKit config checks were added. |
| June 4, 2026 | Simulator app launch | XcodeBuildMCP, iPhone 17 simulator | Pass | Debug app built, installed, and launched without diagnostics. |
| June 4, 2026 | Release simulator build | Xcode 26.4.1, iPhone 17 simulator | Pass | Release build completed successfully after launch-readiness changes. |
| June 4, 2026 | Physical iPhone Debug build | Physical test iPhone (identifier recorded locally) | Pass | Debug build signed with current development profile. |
| June 4, 2026 | Physical iPhone install and launch | Physical test iPhone (identifier recorded locally) | Pass | App installed and launched with bundle ID `com.samchou.checkpoint`. |
| June 4, 2026 | Physical iPhone reinstall after launch polish | Physical test iPhone (identifier recorded locally) | Partial | Updated app installed; launch retry was blocked because the iPhone was locked. |
| June 4, 2026 | StoreKit config contract | XCTest | Pass | Local StoreKit config product IDs, periods, and launch prices match app constants. |
| June 4, 2026 | Bedrock question service unit tests | Python unittest | Pass | 15 passed, 0 failed, including fail-closed backend auth and rate-limit coverage. |

## Automated Repository Gates

`.github/workflows/ci.yml` runs on pushes, pull requests, and manual dispatches. It runs the backend unit suite and Python compilation, scans full tracked history with Gitleaks, runs the iOS simulator suite, builds Release for a generic simulator, and runs Xcode static analysis. The XCTest result bundle is retained as a workflow artifact for 14 days.

The CI Release build uses a generated token and explicitly permitted reserved `.invalid` backend, Privacy Policy, and Support URLs only to exercise Release configuration, compilation, and linking. Normal Release builds reject reserved legal-link placeholders. CI is not a signed distribution archive and cannot validate the production backend, hosted legal pages, or App Store processing.

`.github/workflows/deploy-backend.yml` is manual-only. Every run tests, validates, and builds the SAM application. Deployment additionally requires the explicit confirmation input, a protected `backend-testflight` or `backend-production` GitHub Environment, configured environment secrets/variables, and AWS OIDC role assumption. Nothing deploys on push.

A green workflow is necessary but does not clear Apple or human gates. CI cannot grant Family Controls distribution access, create profiles, exercise Screen Time on a real device, validate sandbox purchases, approve legal/privacy answers, judge arbitrary-goal AI safety, or archive/upload/process a distribution build.

## Final Tests Before TestFlight

These must pass before broader TestFlight testing.

- [ ] CI is green on the exact commit selected for the TestFlight build.
- [ ] Local StoreKit run from Xcode shared `Checkpoint` scheme loads Monthly and Annual products.
- [ ] Local StoreKit Monthly purchase switches Free to Pro.
- [ ] Local StoreKit Annual purchase switches Free to Pro.
- [ ] Local StoreKit expired or cleared subscription returns Pro to Free on foreground refresh.
- [ ] Restore purchases restores Pro only when a current local entitlement exists.
- [ ] Release build uses the intended backend endpoint; production Automatic has no Apple/local or canned fallback.
- [ ] Internal/TestFlight backend has a rotated shared bearer configured and does not set `ALLOW_UNAUTHENTICATED_BACKEND=true`; the shared bearer is not accepted as public-production identity.
- [ ] Backend endpoint rejects unauthenticated requests.
- [ ] Backend endpoint rate limits by install ID and IP before calling Bedrock.
- [ ] A human-approved backend deployment is active in the intended GitHub Environment; no deployment was inferred from a simulator Release build.
- [ ] Backend question batch generation returns valid, unique, on-target choices across exam, language, technical, humanities, and uncommon raw-goal cases.
- [ ] Latest installed iPhone build is launched once while the iPhone is unlocked.
- [ ] Physical iPhone shield loop passes the full real-device plan below.

## Real Shield Loop

Run on a physical iPhone before TestFlight and again before App Store submission.

- [ ] Install a signed build.
- [ ] Review the required Screen Time explanation, tap Allow Screen Time, and approve the system request.
- [ ] Create or select a goal.
- [ ] Choose at least one protected app and one category.
- [ ] Start protection and verify selected targets are blocked.
- [ ] Remove one protected app while protection stays on; confirm that app opens and the remaining targets stay blocked.
- [ ] Remove an app that was added through a category; confirm the category does not add it back.
- [ ] Confirm a newly installed app from a selected category stays unprotected until the selection is refreshed.
- [ ] Confirm a selection over 50 websites fails visibly without partially enabling protection.
- [ ] Confirm a selection over 50 apps fails visibly without partially enabling protection.
- [ ] Remove the last protected app; confirm protection and any active break both end.
- [ ] Turn protection off, force-quit/relaunch, and confirm all targets remain unblocked.
- [ ] Open a protected app and confirm the custom Checkpoint shield appears.
- [ ] Switch goals in Checkpoint and confirm the shield shows the new current goal.
- [ ] Tap the shield action and confirm Checkpoint opens.
- [ ] Confirm the protected-app checkpoint appears automatically.
- [ ] Fail a checkpoint and confirm protected apps remain locked.
- [ ] Retry and confirm missed questions are prioritized.
- [ ] Pass with the configured score and confirm protected apps unblock for the configured duration.
- [ ] Confirm protected apps re-lock when the break expires.
- [ ] Edit the protected list during a break and confirm only the newest list re-locks.
- [ ] Force-quit immediately after starting each 5/10/15/30-minute break and confirm re-lock at expiration.
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
- [ ] Distribution provisioning profiles exist for the main app and all three Screen Time extensions.
- [ ] A signed distribution archive exports, uploads, and finishes processing in App Store Connect.
- [ ] App privacy labels match local storage, Screen Time state, backend generation, and StoreKit purchases.
- [ ] Hosted privacy policy URL is live.
- [ ] Support URL is live.
- [ ] Public backend requests use App Attest challenges/assertions with replay protection and server-held key state; the embedded shared bearer and caller-supplied install UUID are no longer trusted as identity.
- [ ] The server verifies current StoreKit subscription entitlement before assigning paid quotas or Pro-only backend access.
- [ ] Server quotas, API throttling, reserved concurrency, Guardrails, kill switch, structured metrics, alarms, and budget notifications are deployed and operationally verified.
- [ ] App Store screenshots are captured from the current UI.
- [ ] App subtitle, description, keywords, and promotional text are final.
- [ ] App Review notes explain Family Controls, Managed Settings, Device Activity, App Groups, AI generation, and unlock/re-lock behavior.
- [ ] First in-app purchases are attached to the app version before review.
- [ ] Age rating and content rights are finalized.
- [ ] Arbitrary-goal harmful-content/refusal behavior and the generative-content age-rating strategy receive human sign-off.
- [ ] iOS 17 minimum-version, small-screen, VoiceOver, and large Dynamic Type passes are complete on physical devices where applicable.
- [ ] No secrets are tracked in git.
