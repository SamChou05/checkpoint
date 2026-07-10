# Production QA

Use this checklist before TestFlight and again before App Store submission. Mark items with the date, device/build, result, and any follow-up commit. The dated final validation log lives in `docs/FINAL_LAUNCH_TEST_LOG.md`.

## Latest Local Automated Validation

Run: July 10, 2026 EDT.

- [x] Complete Debug iOS simulator suite passed: 203 tests, 0 failures.
- [x] Release iOS simulator build succeeded, including all three Screen Time extensions.
- [x] Bedrock question service suite passed: 106 tests, 0 failures, including 22 server-reserve tests.
- [x] Python compilation, `ruff`, plist validation, `git diff --check`, and CloudFormation-aware YAML parsing passed.
- [x] Focused reserve tests cover opt-in, authentication recovery, stale revisions, durable save-before-ack and ACK retry across relaunch, duplicate delivery, partial-batch recovery, low-fresh pulls, fast shield delivery, background coalescing, downgrade purge, and interrupted-purge retry.
- [x] AWS SAM lint/build passed and `checkpoint-question-service-prod` deployed in `us-east-1`; authenticated generation plus register/sync/worker/pull/ack/purge/delete smoke tests passed.
- [x] Deployed DynamoDB TTL/SSE, SQS SSE/visibility/DLQ redrive, 15-minute recovery schedule, and zero-error Lambda smoke metrics were verified.
- [x] A physical-device Release archive `1.0 (2)` succeeded with all extensions and the live backend configuration embedded.
- [ ] App Store export is blocked: Xcode reports no signed-in account and no App Store distribution profiles for the app or its three extensions.
- [ ] CloudWatch notification alarms and an AWS Budget still need owner-selected destinations/thresholds; the worker-side generation quotas are active.
- [ ] The latest changes still require physical-device background-task, shield-loop, and StoreKit verification.

## Previous Device QA Run

Started: June 4, 2026 PDT.

- [x] Debug simulator tests passed: 101 passed, 0 failed.
- [x] Bedrock question service unit tests passed: 15 passed, 0 failed.
- [x] Release simulator build succeeded.
- [x] `Checkpoint/Config/Secrets.xcconfig` is ignored and not tracked.
- [x] Backend endpoint is configured locally and returned valid `questions` JSON for an authenticated LSAT request.
- [x] Backend endpoint returned 401 for the same request without the bearer token.
- [x] Release physical-device build succeeded on connected iPhone.
- [x] Debug physical-device build, install, and launch succeeded on connected iPhone after StoreKit membership flow changes.
- [x] Debug physical-device build and reinstall succeeded after launch-readiness changes.
- [ ] Latest physical-device launch after reinstall is retested while the iPhone is unlocked.
- [x] StoreKit local config contract tests verify product IDs, launch prices, and renewal periods.
- [ ] Real shield loop retested on physical iPhone.
- [ ] Local StoreKit purchase/expiration tested from the shared Xcode scheme.
- [ ] StoreKit sandbox/TestFlight purchase checked.

Findings:

- Release entitlement refresh now runs when the app returns to foreground, so expired or canceled Pro access can return to Free without requiring a full app restart.
- The backend now fails closed when no bearer token is configured unless `ALLOW_UNAUTHENTICATED_BACKEND=true` is explicitly set. Keep rate limits enabled, rotate the token before broader testing, and consider App Attest or a stronger backend gate before a public scale-up.

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
- [ ] `ALLOW_UNAUTHENTICATED_BACKEND` is not enabled on exposed Function URLs.
- [ ] Backend rate limits by install ID and source IP before calling Bedrock.
- [ ] Backend caps requested batch size.
- [ ] Backend rejects malformed, duplicate, off-target, and below-difficulty questions.
- [ ] App falls back gracefully when backend returns 401, 429, 502, or malformed data.
- [ ] Goal title, focus areas, derived learning target, difficulty, and weak topics are present in backend requests.

## Cloud Question Reserve

- [ ] The reserve remains off until a Pro user explicitly enables its Settings toggle.
- [ ] Registration sends a locally generated secret over HTTPS and DynamoDB stores only its SHA-256 hash.
- [ ] Repeating registration with the same install/secret succeeds; a different secret cannot rotate that install.
- [ ] A goal sync queues at most one 20-question deficit and does not generate again merely because time passes.
- [ ] Duplicate SQS messages and a simultaneous recovery sweep result in one Bedrock worker lease/provider operation.
- [ ] A delayed older sync cannot replace a newer goal revision.
- [ ] Editing the goal or syncing desired count zero while Bedrock runs prevents the stale result from committing.
- [ ] Pull returns the same stable delivery until acknowledgement.
- [ ] Questions are persisted locally before acknowledgement; save failure sends no acknowledgement.
- [ ] Relaunch after save-before-ack creates no duplicate questions and then acknowledges the delivery.
- [ ] Stale acknowledgement cannot clear a newer held delivery.
- [ ] Low never-asked inventory triggers a pull even when review questions keep total inventory above ten.
- [ ] Provider failures honor backoff, stop after the configured attempt cap, and do not bypass the four-batch daily worker quota.
- [ ] Downgrade syncs desired count zero; opt-out, goal deletion, and reset send authenticated deletion.
- [ ] DynamoDB TTL, SQS DLQ/visibility, EventBridge recovery, CloudWatch errors, and AWS budget alarms are verified in the deployed stack.
- [ ] Worst-case UTF-8 reserve state remains below its 360 KiB application cap and DynamoDB's 400 KiB item limit.
- [ ] App Store privacy labels and the hosted policy disclose the opt-in retained goal/question data and 30-day TTL.
- [ ] App Attest or an equivalent registration-abuse control is decided before unrestricted public scale.

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
