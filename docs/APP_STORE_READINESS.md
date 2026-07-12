# App Store Readiness

Checkpoint is not App Store-ready yet, but the repo now has the core workflow, tests, entitlements files, and privacy manifests needed to move toward TestFlight.

## Current Status

- Core checkpoint flow is implemented.
- Default unlock policy asks 5 questions and requires 4 correct answers.
- Failed checkpoint sets make missed questions due immediately so the next attempt retests them first.
- AI generation is AI-only: production `Automatic` routes directly to the configured cloud backend, with no alternate production source or canned fallback.
- A practice set is not ready until at least five questions pass validation; pending generation and retryable service, connection, or quality states are visible.
- Live-backend smoke tests exercised LSAT, MCAT, Spanish, modern history, and a raw-goal beekeeping case. Full validated sets were observed across all five domains; a partial Spanish batch was correctly rejected by the stricter gate and succeeded on retry. Endpoint and token values live only in ignored local configuration and are not recorded in version control.
- Main app and Screen Time extensions include Family Controls and App Group entitlement files.
- Main app and Screen Time extensions include privacy manifests for `UserDefaults` access.
- Successful checkpoints temporarily unshield selected apps, then schedule a Device Activity monitor extension to re-apply shields after the unlock window.
- Settings includes shield-extension diagnostics to confirm whether the custom Checkpoint shield rendered or iOS fell back to the default Restricted page.
- New installs start with no restricted apps/categories selected, and empty shield attempts surface an in-app error.
- Blocked-app launches with no available checkpoint questions surface a recovery notice.
- The full simulator XCTest suite passes: 192 tests, 0 failures on July 12, 2026, using Xcode 26.4.1 with normal simulator signing and parallel testing disabled.
- The Bedrock question service suite passes: 88 tests, 0 failures on Python 3.12 on July 12, 2026.
- GitHub Actions definitions now cover backend tests, secret scanning, iOS simulator tests, a Release simulator build, and Xcode static analysis. A separate backend workflow is manual-only and environment-gated.
- Starter-membership product behavior is implemented. The first goal and blocker/checkpoint/unlock loop are usable before payment; membership unlocks goal switching, fresh ongoing generation, larger question banks, and adaptive Study Assist.

## Automated Repository Gates

The required branch checks should include the jobs in `.github/workflows/ci.yml`. They run on pushes and pull requests and can also be dispatched manually:

- Python 3.12 backend unit tests, bytecode compilation, Ruff linting, and linted SAM template validation.
- Gitleaks scanning against the complete checked-out git history.
- iOS simulator XCTest with simulator signing retained so App Group persistence paths are testable.
- A generic-simulator Release build using an ephemeral token plus explicitly allowed reserved `.invalid` backend, Privacy Policy, and Support URLs.
- Xcode static analysis.

The Release simulator job is a compile/link/configuration check only. Its explicit CI-placeholder opt-in is not permitted for a normal Release build, which now requires non-placeholder hosted HTTPS Privacy Policy and Support URLs. CI does not contain production credentials, produce a signed distribution archive, prove Family Controls distribution entitlement access, or upload anything to App Store Connect.

Backend deployment is intentionally isolated in `.github/workflows/deploy-backend.yml`. Validation is safe to run without credentials; deployment occurs only when a human checks the confirmation input and the protected GitHub Environment permits the job. Configure `backend-testflight` and `backend-production` environments, require reviewers for production, and provide:

- Required environment secrets: `AWS_DEPLOY_ROLE_ARN`, `CHECKPOINT_BACKEND_TOKEN`, `QUOTA_HASH_SECRET`. Both application secrets must contain at least 32 characters.
- Required environment variables: `AWS_REGION`, `SAM_STACK_NAME`, `BEDROCK_MODEL_ARN`, `BEDROCK_INVOKE_RESOURCE_ARNS`. The invoke-resource value is a comma-delimited, wildcard-free ARN allowlist containing the runtime profile/model ARN plus every destination foundation-model ARN needed for cross-region inference.
- Optional model and safety variables: `BEDROCK_FALLBACK_MODEL_ARN`, `BEDROCK_GUARDRAIL_IDENTIFIER`, `BEDROCK_GUARDRAIL_VERSION`, `BEDROCK_GUARDRAIL_ARN`. Guardrail values are all-three-or-none; production requires all three.
- Alerting variables: `ALERT_EMAIL`, `BUDGET_ALERT_EMAIL`, and optional `MONTHLY_BEDROCK_BUDGET_USD`. Both email values are required for production.
- Optional operational tuning variables mirror the remaining SAM parameters, including provider/request limits, quotas, throttles, reserved concurrency, retention, stage name, and service kill-switch mode.
- `GITLEAKS_LICENSE` as a repository or organization secret only if Gitleaks requires it for the repository owner type.

Use an AWS OIDC role scoped to the intended SAM stack; do not add long-lived AWS keys to GitHub. The deployment workflow maps its target directly to the template's `testflight` or `production` deployment environment. Its separate `run_smoke_test` input is off by default; explicitly enabling it after a confirmed deployment retrieves the stack output and spends one authenticated Bedrock request without printing endpoint or token values. A green CI run is necessary for release, but it cannot clear any gate below.

## Apple, Account, and Human Gates

These cannot be completed from the repo alone:

1. Confirm the Apple Developer Program team that will ship Checkpoint and register these bundle IDs:
   - `com.samchou.checkpoint`
   - `com.samchou.checkpoint.ShieldConfigurationExtension`
   - `com.samchou.checkpoint.ShieldActionExtension`
   - `com.samchou.checkpoint.DeviceActivityMonitorExtension`
2. Enable `group.com.samchou.checkpoint` for all four bundle IDs. Request Family Controls distribution access separately for the main app and each of the three extension bundle IDs; development entitlement success is not distribution approval.
3. After approval, create distribution profiles for all four targets. Produce a signed archive, export it, upload it, and confirm that App Store Connect finishes processing it. The CI simulator build does not satisfy this gate.
4. Accept the Paid Apps Agreement and complete banking and tax. Create the `Checkpoint Pro` subscription group plus `checkpoint.membership.monthly` and `checkpoint.membership.yearly`, add required localization/review information, attach the first subscriptions to the app version, and perform the full TestFlight sandbox purchase/restore/expiration/cancellation pass.
5. Finalize retention and deletion treatment for goals, prompts, install IDs, IP quota records, AWS/Bedrock processing, and iOS device-backup eligibility with appropriate legal review. Publish working Privacy Policy and Support URLs, expose the required legal links in the app, complete App Store privacy labels, and manually verify that Erase All Data removes backend and App Group/Screen Time state as promised.
6. Define the policy for arbitrary-goal harmful content, refusal behavior, and age suitability. Select and configure input/output controls or Bedrock Guardrails, have a human review adversarial results, and answer App Store age-rating and generative-content questions consistently with observed behavior.
7. Install build 4 on the physical test iPhone and run both build 3 → 4 migration and a full reset. Complete the entire physical shield matrix, including selection changes, protection off, every break duration, force quit, reboot, editing during a break, custom shield rendering, and selection limits.
8. Complete physical iOS 17 minimum-version, small-screen, VoiceOver, and large Dynamic Type validation. Simulator coverage is supporting evidence, not accessibility or Screen Time sign-off.
9. Finalize screenshots, store copy, content rights, export compliance, DSA status, support contact, and App Review notes. A human should review every screenshot and metadata answer against the exact uploaded build.
10. Deploy and approve the production backend, then configure the real HTTPS endpoint and token for the signed Release build through protected build settings. Do not treat a manual SAM deployment as public-production security approval until App Attest, server-side entitlement/quota enforcement, throttling, budgets, kill switch, metrics, and outage alerts are accepted.

## Latest Real-Device Validation Attempt

Last checked: July 11, 2026 EDT.

- Local entitlement files are present for the main app and all Screen Time extensions.
- A paired wired physical test iPhone was visible to `xcrun devicectl`; its identifier is recorded only in local operational notes.
- Device details now report `developerModeStatus: enabled`.
- Local signing/provisioning now finds the paid team `RF8739P5MC` (`Cicada Labs LLC`) and generated development profiles.
- Physical-device Debug build now succeeds using the project signing settings.
- Signed build 4 verifies and is installed in place over build 3 on the physical test iPhone with bundle ID `com.samchou.checkpoint`; the device reports version 1.0, build 4.
- Build 4 launches successfully after the physical test iPhone is unlocked.
- Next action: visually verify that build-3 progress and protection selection migrated, then complete the real shield/unshield/re-lock test plan below before any clean reset.

## Physical Device Test Plan

Run this before TestFlight and again before App Store submission:

1. Install a signed build on a real iPhone.
2. Launch Checkpoint, review the required Screen Time explanation, tap Allow Screen Time, and approve the system request.
3. Create a goal. Confirm the app shows preparation until five validated questions are ready.
4. Choose at least one restricted app and one category.
5. Apply the shield from Home.
6. Open a restricted app and confirm the Checkpoint shield appears.
7. If the system default Restricted page appears, open Settings > Advanced > Troubleshooting and reset and confirm whether the custom shield render count is still zero before debugging UI copy.
8. Tap the primary shield button and confirm Checkpoint opens.
9. Confirm the checkpoint sheet appears from the pending shield attempt, including when Checkpoint was last left on Settings, Progress, or History.
10. Fail at least two questions and confirm the app stays locked.
11. Try again and confirm the missed questions appear first.
12. Pass with 4 of 5 correct and confirm the app temporarily unshields.
13. Wait for the unlock window to expire and confirm the app re-locks.
14. Force quit and relaunch Checkpoint during an unlock window and after expiration to verify reconciliation.
15. Restart the phone and verify the selected app remains shielded when it should be.
16. Exercise a backend connection failure and a rejected-quality batch, and confirm each state is visible and retryable without canned questions appearing.

## App Review Notes Draft

Use this as a starting point in App Store Connect review notes:

Checkpoint helps users reduce distracting app use by combining Apple's Screen Time APIs with goal-based learning checkpoints. Users choose a learning goal and select apps or categories they want to restrict. When a restricted app is opened, the Screen Time shield prompts the user to return to Checkpoint and complete a short multiple-choice checkpoint. Passing the checkpoint temporarily unblocks the selected apps; failing keeps them restricted and prioritizes missed questions on the next attempt.

The app uses Family Controls, Managed Settings, Managed Settings UI, Device Activity, App Groups, and Screen Time extensions. The App Group is used only to pass shield context, pending checkpoint state, unlock expiration, desired shield state, and selected Screen Time state between the app and extensions.

AI question generation is batch-based and cached. Production `Automatic` routes directly to the configured cloud backend. Apple Foundation Models remains code-supported only as an explicit internal experiment and is not a production fallback or question source because availability, OS model version, and reasoning capability vary. There is no canned question fallback, and a set is not ready until at least five questions pass validation. Pending generation and service, connection, or quality failures are visible and retryable. Backend generation is internal service wiring rather than a normal user-facing setting; it is not called on every blocked-app attempt.

## Privacy Notes

- The app stores goal, question, answer-history, competency, shield-state, and unlock-window data locally.
- The app and extensions use App Group `UserDefaults` to coordinate shield state.
- Unlock windows can be 5, 10, 15, or 30 minutes. Short windows rely on the app-level re-lock task and foreground reconciliation, with Device Activity as an additional background re-lock path.
- Backend generation, when explicitly configured, sends goal context, derived learning target/topics, competency progress, existing prompts, and reported prompts to the configured endpoint.
- The app does not use tracking domains.
- The current privacy manifests declare `UserDefaults` required-reason API access:
  - `CA92.1` for app-only defaults in the main app.
  - `1C8F.1` for App Group defaults shared by the app and extensions.

## Not Ready Until

- Family Controls distribution access is approved for all shipping bundle IDs.
- A real iPhone passes the shield/unshield/re-lock test plan.
- App Store privacy labels and a hosted privacy policy are finalized.
- Screenshots, description, support URL, age rating, and review notes are created in App Store Connect. Draft copy is tracked in `docs/APP_STORE_COPY.md`.
- A hosted privacy policy is published from the draft in `docs/PRIVACY_POLICY_DRAFT.md`.
- Persistence is accepted as MVP-local storage or replaced with a production store.
- The production backend is deployed, and the Release configuration resolves a valid HTTPS endpoint and nonempty token.
- Monetization scope is finalized, the Paid Apps Agreement is active, App Store Connect subscription products are configured, and starter/member launch assumptions are reviewed against backend AI cost.
