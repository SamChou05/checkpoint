# Checkpoint

Checkpoint is a SwiftUI iOS app for goal-gated screen time. The app turns an attempted distraction into an AI-assisted multiple-choice checkpoint question, stores the answer history, and uses missed/due questions before generating new ones.

See `DEVELOPMENT.md` for the current build status, platform constraints, product decisions, and MVP roadmap.

## Current Build

- Native SwiftUI app shell.
- Natural-language goal profile onboarding flow, with one active Free goal and Pro support for multiple saved profiles.
- Goal category is inferred internally from the typed goal/context instead of shown as user-facing setup.
- Provider-based multiple-choice question generation extracts a learning target from typed goals, so phrases like `Study for the LSAT` produce LSAT questions rather than study-habit prompts.
- Automatic question generation with provider details abstracted away from the user-facing app.
- Multi-question checkpoint sessions that ask 5 questions and require 4 correct answers by default before an unlock.
- Per-profile 1-to-5 question difficulty floor so users can skip remedial prompts for goals they already know well.
- Correct-answer unlock windows use 15, 30, 45, or 60 minutes, with 30 minutes as the default.
- Stored checkpoint attempts with correctness and unlock state.
- Missed questions from a failed unlock attempt become due immediately so the next checkpoint retests them first.
- XCTest coverage for the core checkpoint, scheduler, unlock, sanitizer, and provider-cost workflows.
- Recovery states for blocked-app launches when no checkpoint questions are available.
- Academic paper-inspired UI for Home, Checkpoint, Skill, and Settings, with history available from Settings.
- Settings now keeps product controls up front: Plan, Goal profiles, App blocking, Checkpoint rules, and a collapsed Advanced troubleshooting area for diagnostics and reset.
- Question quality reporting lives in Settings instead of interrupting the checkpoint quiz.
- Home no longer offers one-tap pause or manual checkpoint entry while blocking is active; short breaks start from blocked-app attempts or emergency passes, while fully stopping blocking requires a 9-of-10 stop challenge in Advanced.
- Manual checkpoint preview lives in Advanced for testing and does not unlock apps.
- Checkpoint quietly prepares fresh local questions when the current set can no longer fill the next checkpoint, so users do not manage a question bank.
- Pro users can switch goal profiles from Home; each profile keeps its own goal context, question difficulty, practice set, history, reports, and Skill Map.
- StoreKit-ready Free/Pro plan state, paywall UI, restore hook, and Pro gating for goal profiles, custom checkpoint rules, extra question variety, and adaptive guidance.
- Privacy manifests for the app and Screen Time extensions.
- Screen Time controller for Family Controls authorization, app selection, shielding, temporary unlocks, and re-lock reconciliation.
- Shield Configuration extension target for branded Screen Time shield UI.
- Shield Action extension target that records a pending checkpoint and asks iOS to open Checkpoint when the shield primary button is tapped.
- Device Activity Monitor extension target that re-applies shields when a temporary unlock expires.
- Shared App Group state for passing the current goal/prompt and pending shield attempts between app and extensions.

## AI Question Generation

The MVP uses a hybrid provider approach:

- Automatic tries Apple Foundation Models when available, then a configured backend LLM, then Local Templates as the no-cost/offline fallback.
- Apple Foundation Models can provide on-device generation on Apple Intelligence-compatible devices.
- Backend LLM generation is batch-based and reserved for internal app configuration; the first AWS Bedrock Lambda service lives in `backend/bedrock-question-service`.
- Local Templates keep the app usable without network, backend, or supported on-device models.
- Provider prompts and payloads include a derived learning target, content topics, and a directive to test the subject matter instead of asking about study plans or app usage.
- Configure production backend URLs through `Checkpoint/Config/Secrets.xcconfig` or another internal build configuration, not user-facing Settings and never with AWS credentials in the app.
- Backend calls include an anonymous install ID and the Bedrock service can enforce DynamoDB-backed install/IP daily quotas before model invocation.
- The Bedrock service retries malformed model output and can fall back to Nova Micro if the cheapest primary model does not return valid JSON.

The backend request/response shape is documented in `docs/AI_BACKEND_CONTRACT.md`. The app intentionally generates and caches question batches instead of exposing model/source choices or calling AI on every blocked-app attempt.

## App Store Readiness

See `docs/APP_STORE_READINESS.md` for entitlement steps, physical-device testing, App Review notes, and remaining launch blockers.

See `docs/MONETIZATION.md` for the recommended free/Pro split, product IDs, and StoreKit setup order.

## Testing

Run the `Checkpoint` scheme tests in Xcode. The suite covers the 4-of-5 unlock gate, failed-session retesting, missed/due scheduling, shield-triggered session creation, no-question recovery states, no-cost local generation, provider fallback policy, unlock duration policy, emergency unlock session creation, empty Screen Time selection defaults, Free/Pro gating, Pro goal profile isolation, Pro Assist, and provider payload sanitization.

## Open

Open `Checkpoint.xcodeproj` in Xcode and run the `Checkpoint` target on an iPhone simulator or device. Simulator XCTest verification is passing locally; real Screen Time behavior still needs device testing.

## Preview While Building

Fastest options:

1. Open `Checkpoint.xcodeproj` in Xcode.
2. Select the `Checkpoint` scheme.
3. Run on an iPhone simulator to preview the whole app.
4. Use Settings -> Advanced -> `Preview checkpoint` only when you need to test the checkpoint flow manually.

For real Screen Time testing:

1. Use a real iPhone when possible.
2. In Xcode, add the Family Controls capability for the app target.
3. Confirm the bundle ID is available in your Apple Developer account.
4. Run the app and accept the first-run Screen Time prompt. If it was dismissed, open Settings -> `Allow Screen Time`.
5. Select apps/categories and tap `Start blocking` from Home.

The current code includes the FamilyControls picker, selection persistence, ManagedSettings shielding, temporary unshielding after a successful checkpoint, automatic re-shielding after the unlock timer, a Device Activity monitor extension for background re-locking, shield configuration/action extensions, and App Group state sharing.

## Real-Device Loop To Verify

1. Launch Checkpoint and create a goal.
2. Accept the first-run Screen Time prompt, or use Settings -> `Allow Screen Time` if needed.
3. Settings -> `Choose blocked apps`.
4. Home -> `Start blocking`.
5. Open a selected blocked app.
6. Confirm the Checkpoint shield appears with current goal/prompt copy.
7. Tap `Open Checkpoint` on the shield.
8. Confirm Checkpoint opens and shows the checkpoint answer sheet.
9. Answer the checkpoint set correctly.
10. Confirm the selected app is temporarily unshielded.
11. Confirm the app re-locks after the unlock expires or after Checkpoint returns active.

## Required Apple Setup

- Add Family Controls capability to the main app and Screen Time extensions.
- Add App Groups to the main app and Screen Time extensions.
- Use the same group ID: `group.com.samchou.checkpoint`.
- Configure the main app bundle ID: `com.samchou.checkpoint`.
- Configure extension bundle IDs:
  - `com.samchou.checkpoint.ShieldConfigurationExtension`
  - `com.samchou.checkpoint.ShieldActionExtension`
  - `com.samchou.checkpoint.DeviceActivityMonitorExtension`
- Family Controls distribution requires Apple approval before App Store submission.
