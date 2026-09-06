# Checkpoint Development Status

Last updated: September 6, 2026

## Current Product Direction

Checkpoint is an iOS app that lets a user pick restricted apps, set a goal, and turn distraction attempts into goal-aligned multiple-choice checkpoint questions.

The App Store-safe workflow is:

1. The mascot welcomes the user and helps them describe a goal with optional context and study materials.
2. Checkpoint generates a Skill Map; the user reviews, optionally edits, and explicitly approves it.
3. Checkpoint explains Screen Time access, and the user explicitly grants Family Controls permission. Questions prepare in the background.
4. User optionally picks restricted apps inside Checkpoint, or finishes setup and chooses apps later.
5. Checkpoint shields those apps.
6. User opens a restricted app.
7. iOS shows a Checkpoint shield.
8. User opens Checkpoint and answers a short checkpoint set.
9. Correct multiple-choice answers across the full set grant a short unlock.
10. Checkpoint re-locks after the unlock window.

Important platform constraint:

- Apple's shield UI cannot host a full custom SwiftUI quiz.
- Apple's newer Managed Settings docs include a shield response for opening the parental-controls app, but this must be verified on a real device and OS version.
- The product should therefore treat the shield as the trigger and Checkpoint as the place where the actual question is answered.

## Built So Far

### App Shell

- SwiftUI iOS app project.
- Academic paper-inspired visual system.
- Home, Progress, and Settings tabs.
- Settings keeps user-facing controls focused on goals, app protection, and checkpoint rules; reset is collapsed under App data and diagnostics live in Debug-only Developer tools.
- The app is currently modeled as a starter-membership product: the first goal and core blocker loop are included before payment, while membership unlocks goal switching and ongoing fresh generation.
- Checkpoint history is accessible from Settings instead of occupying a primary tab.
- Feedback notes are accessible from Settings, saved locally, and shareable through the system share sheet.
- First-goal onboarding precedes Screen Time authorization. A persisted approval marker resumes saved goals at Skill Map review until approval, then at permission/app selection; denial or cancellation stays on a clear retry screen.
- Stopping blocking is intentionally harder than starting it: active blockers route through blocked-app checkpoint attempts, while full stop requires an 18-of-20 review from Settings.
- Settings places a compact Plan section below the core goal and app-protection controls.
- For members, question replenishment is abstracted away: Checkpoint quietly prepares fresh AI-generated questions when the current set can no longer fill the next checkpoint.
- Home does not preview upcoming questions; question selection stays inside the checkpoint moment.
- Study Assist adds next-topic guidance without exposing question-bank status.
- Mascot-guided, three-step onboarding: Goal, Skill Map, Protection. Initial entry requires only a goal; one collapsed optional row holds context and study materials. Timing and difficulty remain available in goal settings.
- Skill Map review shows a compact skill list with objectives available on tap, supports editing, and requires explicit durable approval before permission setup. Generation failures offer retry or goal edits; map availability is independent of question readiness.
- Natural-language goal profile onboarding with sensible defaults and optional topic/starting-level customization.
- Optional text and text-based PDF study materials can be attached to a goal. The app extracts and bounds their text locally, persists it with the profile, and uses it as untrusted grounding data for generation.
- Onboarding starts blank and rejects empty goal titles.
- The raw typed goal is authoritative. Legacy category is compatibility metadata only, and new goals default to `Custom` instead of being classified by subject keywords.
- Question generation extracts an internal learning target from natural-language goals, so `Study for the LSAT` becomes LSAT content rather than questions about studying.
- Existing profiles reopen prefilled for edits; users can create and switch multiple goal profiles.
- Home lets users switch the active goal profile, and each profile keeps its own question difficulty, practice set, history, reports, and Skill Map.
- Home focuses on the active profile and blocking state; the manual checkpoint preview is tucked into Debug-only Developer tools and does not unlock apps.

### Question System

- Goal intake captures title, deadline, focus areas, and the profile-specific minimum question level; internal category and topic inference keep question generation aligned.
- The generation request derives a learning target, content topics, and a question directive before calling the configured cloud backend in production.
- If a goal has no usable focus areas or derived map, the app first asks the active provider for a structured Skill Map. Accepted question topics can still bootstrap a map if that planning call is unavailable.
- Provider prompts intentionally stay simple: user goal, derived learning target, content topics, requested count, difficulty floor, a concise difficulty rubric, and multiple-choice requirements.
- The MVP question format is limited to multiple choice for simpler grading and testing.
- Backend generation and an explicit internal Apple Foundation Models experiment are wired behind a shared interface.
- An AWS Bedrock Lambda backend is implemented in `backend/bedrock-question-service`; it matches the app contract, validates model output, and keeps provider credentials off-device.
- The August 2026 cross-domain capture for the evaluated TestFlight worker passed all 13 fixtures and all 43 generated questions after deterministic grading.
- AI generation should happen in batches and be cached locally, not live on every app-open attempt.
- Questions store prompt, expected answer, answer choices, explanation, topic, difficulty, format, status, ask count, correctness count, and next review date.
- Answer attempts are stored in history.
- Multiple-choice checkpoint answers are locally graded for the MVP before the final unlock.
- Multi-question checkpoint sessions ask 5 questions and require 4 correct answers by default before unlocking.
- Missed questions from a failed checkpoint set become due immediately and are prioritized in the next set.
- Each goal profile stores a 1-to-5 minimum question difficulty so users can skip material below their level for that subject.
- Raising the active goal's question level retires below-level questions and triggers member question-bank regeneration at the new level; lowering the level keeps existing harder questions usable.
- Revealing the expected answer before submission keeps the current attempt locked.
- Blocked-app launches with no available checkpoint questions now show a recovery notice instead of failing silently.
- Question batch state is tracked as idle, generating, ready, or failed.
- Checkpoint requires at least five validated questions before marking the first practice set ready. It does not substitute canned questions when AI output is missing or rejected.
- Starting protection is gated on a complete cached checkpoint. A blocked-app handoff never waits for network generation, and abandoned or force-quit checkpoint runs receive a persisted retry cooldown.
- The user sees pending generation and retryable service, connection, or quality failures, with goal-editing offered only when more specific subject context could help.
- Question refresh is abstracted away from users. Starter users get the first generated bank; membership keeps fresh questions flowing after that set runs low.
- Debug and Release builds both use StoreKit entitlements for Free/Pro access; local development uses `Checkpoint/Config/CheckpointProducts.storekit` through the shared Xcode scheme.
- Question generation now uses a provider router:
  - Automatic (production cloud backend)
  - Backend
  - Apple Foundation Models (explicit internal experiment)
- Production `Automatic` routes directly to the configured backend LLM.
- Apple Foundation Models is never selected by production `Automatic`; its availability, OS model version, and reasoning capability vary too much for it to be a production fallback or question source.
- Provider routing is internal so users do not need to choose a question source.
- The app stores the last provider used for diagnostics.
- Generated batches pass through a shared sanitizer before storage to remove blank, duplicate, reported, invalid, oversized, and off-target study-strategy questions.
- Provider prompts assign a distinct tested objective to every generated item, and checkpoint sessions spread fresh questions across available topics before repeating one.
- XCTest coverage verifies question-bank generation, session selection, unlock gating, shield-triggered sessions, provider policy, and sanitizer behavior.

### Adaptive Competency

- Topic competency model added.
- Each topic tracks estimated level, attempts, correct, partial, incorrect, streak, last result, and last practiced date.
- Correct answers increase estimated level.
- Partial answers remain in the model for future open-ended formats, but the MVP multiple-choice gate is binary.
- Incorrect or unclear answers lower level.
- Scheduler prioritizes:
  - missed questions due again
  - due review questions
  - new questions in weaker topics
  - questions near the user's estimated difficulty
- The scheduler respects the active profile's manually configured difficulty floor when enough questions are available.
- Initial topic levels start from the active question difficulty and inferred goal topics, then adjust by answer history.
- Strong recent accuracy surfaces an opt-in question-level increase that updates the goal difficulty and refills harder questions.
- Progress tab shows actionable per-topic progress, with detailed answer counts available on demand.

### Unlock Policy

- Correct-answer unlock duration is configurable with 5, 10, 15, and 30 minute options. The default is 30 minutes.
- Correct-answer count per unlock is configurable from Settings.
- Multiple-choice misses stay locked.
- Incorrect and unclear answers do not unlock.
- Revealed expected answers force the attempt to stay locked.
- Emergency Pass duration is tracked through the shared unlock policy.

### Screen Time / Blocking

- Required launch-time Family Controls authorization with retry and foreground status reconciliation.
- FamilyActivityPicker-based blocked app/category/web selection.
- New installs start with an empty blocked-app selection.
- Selection persistence through shared App Group defaults.
- ManagedSettingsStore shielding.
- Starting blocking without a blocked-app selection surfaces an error instead of toggling an empty shield.
- Applying a shield before Screen Time approval surfaces an error.
- Temporary unshield after successful checkpoint.
- App-level fallback re-lock timer.
- Device Activity monitor scheduling so Screen Time can re-apply shields when the unlock window expires.
- Re-lock reconciliation when the app becomes active.
- Family Controls and App Group entitlements.
- Privacy manifests for the app and Screen Time extensions.

### Screen Time Extensions

- Shield Configuration extension target.
- Shield Action extension target.
- Device Activity Monitor extension target.
- Shield configuration shows Checkpoint-branded shield copy.
- Shield configuration writes render diagnostics to the shared App Group so Settings can confirm whether iOS loaded the custom shield page or fell back to the system Restricted page.
- Shield action records a pending checkpoint attempt in shared App Group state and, on iOS 26.5 or newer, asks iOS to open Checkpoint. Older systems retain the shield for manual handoff.
- Pending shield attempts are consumed at the app root, so the checkpoint sheet can appear even if Checkpoint opens on Settings or Progress.
- Device Activity monitor re-applies selected app/category/web shields after a temporary unlock expires.
- Main app consumes pending shield attempts on launch or foreground activation and opens the checkpoint answer flow.

## Current Technical Limits

- The full signed simulator XCTest suite passes with direct `xcodebuild` invocation.
- Real Screen Time behavior must be verified on a physical iPhone.
- Apple's public [`openParentalControlsApp`](https://developer.apple.com/documentation/managedsettings/shieldactionresponse/openparentalcontrolsapp) shield response is documented as available starting in iOS 26.5. The project still targets iOS 17 and currently compiles against an iOS 26.4 SDK, where it must fall back to recording the attempt and deferring. Automatic shield-to-app launch is therefore an explicit iOS-version and physical-device release gate; the UI must not promise an automatic handoff on older systems.
- Family Controls capability and App Groups must be enabled in Apple Developer/Xcode for the app and Screen Time extensions.
- Family Controls distribution requires Apple approval before App Store submission.
- Device Activity requires a 15-minute monitoring interval, so 5- and 10-minute breaks schedule their monitor far enough in the past to meet that minimum while still ending at the requested time; verify this behavior on a physical iPhone.
- App Store readiness steps are tracked in `docs/APP_STORE_READINESS.md`.
- The AI layer has production backend batch generation plus guarded Apple Foundation Models support for explicit internal experiments.
- Main app state uses a schema-versioned JSON envelope in Application Support with atomic primary and backup files, legacy UserDefaults migration, recovery reporting, file protection, and bounded history retention. App Group Screen Time coordination remains in its separate atomic snapshot/defaults store.
- Snapshot encoding and full-file primary/backup writes currently run synchronously on the main actor. Profile physical devices with near-retention-limit histories and move that I/O behind an asynchronous persistence boundary if Instruments shows launch or interaction stalls.
- Privacy Policy and Support links are read from `CHECKPOINT_PRIVACY_POLICY_URL` and `CHECKPOINT_SUPPORT_URL`. Configure real hosted URLs in ignored `Secrets.xcconfig` or through the corresponding `*_OVERRIDE` build settings; missing values are shown as diagnostics in Settings and the paywall.

## In-Progress Direction Before Device Setup

While Apple entitlement/device setup is pending, useful local work is:

- Exercise primary/backup recovery and legacy migration again from the previous physical-device build to the current candidate.
- Evaluate the one-question calibration and goal-classification flow described in `docs/QUESTION_CONTEXT_STRATEGY.md`.
- Improve adaptive competency and diagnostic flows.
- Continue UI polish and error states.

## Current MVP Definition

The MVP is complete when:

- A user can create a goal.
- The app generates a question bank from the typed goal.
- The user can pick restricted apps inside Checkpoint.
- Those apps become shielded.
- Opening a restricted app shows Checkpoint's shield.
- The user can move from the shield to Checkpoint and answer a checkpoint set.
- Completing the checkpoint set temporarily unlocks access.
- Incorrect or unclear answers keep access blocked.
- Missed questions return later, and failed checkpoint sets retest missed questions first on the next attempt.
- The Progress tab reflects topic-level competency.
- The app re-locks reliably after unlock expiration.

## Next Work

### P0

- Confirm Family Controls and App Group provisioning for all four shipping bundle IDs.
- Test the shield loop on a real iPhone.
- Confirm Shield Configuration extension is invoked for app tokens and category tokens.
- If the default Restricted page appears in a Debug build, check Settings > Developer tools > Diagnostics and preview. A zero custom shield render count means the signed build did not load the Shield Configuration extension, usually due to extension provisioning, bundle ID, Family Controls, or App Group setup.
- Confirm Shield Action extension writes pending attempts.
- On iOS 26.5 or newer, confirm Checkpoint opens from the shield primary action; on older systems, confirm the manual-open path picks up the pending attempt.
- Confirm Device Activity monitor re-locks selected apps at unlock expiration while Checkpoint is backgrounded.
- Validate the versioned primary/backup persistence migration on the physical upgrade install and verify Erase all data removes both copies.
- Deploy and verify the intended TestFlight or production Bedrock stack against its real endpoint and model.
- Configure Release with an HTTPS backend endpoint and token through `Checkpoint/Config/Secrets.xcconfig` or the `CHECKPOINT_AI_BACKEND_ENDPOINT_OVERRIDE` and `CHECKPOINT_AI_BACKEND_TOKEN_OVERRIDE` build settings.
- Keep Apple Foundation Models validation separate as an internal experiment; it is not a release-readiness dependency.

### P1

- Add a diagnostic quiz during onboarding.
- Explore open-ended AI grading after the multiple-choice MVP is stable.
- Add stricter repeat-attempt escalation.
- Add no-unlock Deep Focus windows.
- Add bad-question reporting.

### P2

- Per-app routing to a chosen goal profile.
- Retrieval, citations, and server-side source versioning for material larger than the current five-file/24,000-character text bridge.
- Integrations with Anki, Quizlet, LeetCode, Notion, or Google Sheets.
- Server-side analytics and TestFlight instrumentation.
- Membership pricing experiments after retention is validated.
- Configure StoreKit subscription products in App Store Connect and verify purchase/restore in TestFlight before launch.

## Product Decisions

- Launch direction is starter-membership: let users complete the primary first-goal flow, then ask for membership when they need fresh ongoing generation or goal switching.
- Keep membership framed as continuity and flexibility, not as a punishment for using the starter flow.
- Keep AI generation batched and cached, not live on every app-open attempt.
- Do not ship API keys in the iOS app.
- Use the shield as the trigger, not as the full quiz surface.
- Track competence by topic so questions become challenging but doable.
- Keep the tone calm and progress-oriented, not punitive.

## AI Cost Strategy

The scalable AI-only architecture is:

1. Generate questions in batches.
2. Cache accepted questions on the device.
3. Track progress and schedule missed, due, and weak-area questions without another model call.
4. Use AI when a goal is created or the current set can no longer fill the next checkpoint.
5. Require a full validated 5-question set before marking practice ready.

Avoid:

- Calling an AI service every time a user opens a blocked app.
- Using AI to grade every answer when multiple-choice answer keys can work.
- Shipping provider credentials inside the iOS app.
- Substituting canned questions when AI generation fails or its output does not pass validation.

Current provider policy:

- Production `Automatic` routes directly to the configured cloud backend.
- Apple Foundation Models is code-supported only as an explicit internal experiment and is excluded from production cost and availability assumptions.
- Backend costs scale with batch creation and refreshes, so generation remains quota-limited, cooldown-protected, and cached.
- A Release build must include a valid HTTPS backend endpoint, a non-placeholder token of at least 32 characters, and hosted HTTPS Privacy Policy and Support URLs. The cloud backend is the canonical production question source.

Implementation status:

- Provider routing is implemented.
- Backend provider contract is implemented as a POST endpoint that returns question JSON.
- AWS Bedrock Lambda reference service is implemented under `backend/bedrock-question-service`.
- Apple Foundation Models support is guarded by platform and device availability and can be selected only for explicit internal experiments.
- Production `Automatic` routes directly to the configured backend; there is no alternate production source or canned question fallback.
- Provider and app validation run before questions enter the bank, and fewer than five accepted questions leaves the batch unready.
- Pending generation and service, connection, or quality failures are visible and retryable instead of silently replaced.
- Core workflow and provider policy are covered by the `CheckpointTests` XCTest target.
- Focus areas are optional user-facing study context; blank or placeholder focus text asks AI to infer a Skill Map from the exact learning target instead of inserting a canned topic map.
- Settings exposes strictness controls, global unlock rules, and off-flow history/report access; minimum question difficulty lives on each goal profile.
- Backend request/response contract is documented in `docs/AI_BACKEND_CONTRACT.md`.
