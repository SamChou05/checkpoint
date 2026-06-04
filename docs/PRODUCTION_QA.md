# Production QA

Use this checklist before TestFlight and again before App Store submission. Mark items with the date, device/build, result, and any follow-up commit.

## Current QA Run

Started: June 4, 2026 PDT.

- [x] Debug simulator tests passed: 96 passed, 0 failed.
- [x] Bedrock question service unit tests passed: 13 passed, 0 failed.
- [x] Release simulator build succeeded.
- [x] `Checkpoint/Config/Secrets.xcconfig` is ignored and not tracked.
- [x] Backend endpoint is configured locally and returned valid `questions` JSON for an authenticated LSAT request.
- [x] Backend endpoint returned 401 for the same request without the bearer token.
- [x] Release physical-device build succeeded on connected iPhone.
- [ ] Real shield loop retested on physical iPhone.
- [ ] StoreKit sandbox/TestFlight purchase checked.

Findings:

- Release entitlement refresh now runs when the app returns to foreground, so expired or canceled Pro access can return to Free without requiring a full app restart.
- The backend still uses a static bearer token for local/TestFlight configuration. Keep rate limits enabled and rotate the token before broader testing; consider App Attest or a stronger backend gate before a public scale-up.

## Automated Baseline

- [ ] `xcodebuild` Debug simulator tests pass.
- [ ] Release simulator build succeeds.
- [ ] Release physical-device build succeeds with distribution-ready signing settings.
- [ ] Bedrock question service unit tests pass.
- [ ] No tracked secrets are present in the repo.
- [ ] Privacy manifests and entitlements are present for the app and Screen Time extensions.

## Payments And Plan Access

- [ ] App Store Connect has an auto-renewable subscription group.
- [ ] Monthly product ID exists: `checkpoint.membership.monthly`.
- [ ] Annual product ID exists: `checkpoint.membership.yearly`.
- [ ] Local StoreKit monthly and annual purchases switch the app to Pro in Debug.
- [ ] Local StoreKit cleared or expired subscriptions return the app to Free.
- [ ] Release builds start on Free when no current entitlement is present.
- [ ] StoreKit sandbox/TestFlight purchase switches the app to Pro.
- [ ] Restore purchases switches the app to Pro when an active entitlement exists.
- [ ] Cancellation or expired entitlement returns the app to Free on next entitlement refresh.
- [ ] Free users can complete the first-goal protected-app flow.
- [ ] Free users are gated when creating or switching beyond the first goal.
- [ ] Free users are gated when the first included practice set is exhausted.
- [ ] Pro users can create and switch up to 5 goals.

## AI Backend

- [ ] App build has a configured backend endpoint for TestFlight, or intentionally falls back to Apple/local generation.
- [ ] Backend endpoint returns the documented JSON response, not placeholder Lambda text.
- [ ] Backend enforces bearer auth or an equivalent production gate.
- [ ] Backend rate limits by install ID and source IP before calling Bedrock.
- [ ] Backend caps requested batch size.
- [ ] Backend rejects malformed, duplicate, off-target, and below-difficulty questions.
- [ ] App falls back gracefully when backend returns 401, 429, 502, or malformed data.
- [ ] Goal title, focus areas, derived learning target, difficulty, and weak topics are present in backend requests.

## Real Shield Loop

- [ ] Request Screen Time authorization on a physical iPhone.
- [ ] Select protected apps/categories/websites.
- [ ] Start protection and verify the selected targets are blocked.
- [ ] Open a protected app and confirm the custom Checkpoint shield appears.
- [ ] Confirm the shield shows the current goal after switching goals.
- [ ] Tap the shield action and confirm Checkpoint opens.
- [ ] Confirm a protected-app checkpoint appears without needing to manually start anything.
- [ ] Fail a checkpoint and confirm protected apps remain locked.
- [ ] Retake after failure and confirm missed questions are prioritized.
- [ ] Pass a checkpoint and confirm selected apps unblock for the configured break.
- [ ] Confirm apps re-lock when the break expires.
- [ ] Force quit and relaunch during a break and after a break to confirm reconciliation.
- [ ] Restart the phone and confirm protection state is recovered correctly.

## Core UX

- [ ] Onboarding creates the first goal and starts background practice preparation.
- [ ] Goal editing updates questions, Skill Map, and shield goal copy.
- [ ] Goal switching uses the selected goal's stored questions without unnecessary regeneration.
- [ ] Settings plan page clearly shows Free vs Pro and how to switch.
- [ ] Protected-app settings are understandable on small screens.
- [ ] Practice standard settings fit on small screens.
- [ ] Question explanations match the selected correct answer.
- [ ] Duplicate answer choices are rejected before storage.
- [ ] Correctly answered questions are not immediately repeated.
- [ ] Offline or failed generation states show calm recovery copy.

## App Store Assets

- [ ] Family Controls distribution access is approved for shipping bundle IDs.
- [ ] App privacy labels match local storage, Screen Time usage, and backend generation.
- [ ] Hosted privacy policy is live.
- [ ] Support URL is live.
- [ ] App Store screenshots are captured on current UI.
- [ ] App description and subtitle explain the consistency/checkpoint habit clearly.
- [ ] Review notes explain Family Controls, Managed Settings, Device Activity, App Groups, and unlock/re-lock behavior.
