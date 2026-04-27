# Checkpoint Development Status

Last updated: April 27, 2026

## Current Product Direction

Checkpoint is an iOS app that lets a user pick restricted apps, set a goal, and turn distraction attempts into goal-aligned multiple-choice checkpoint questions.

The App Store-safe workflow is:

1. User creates a goal in Checkpoint.
2. Checkpoint generates and stores a local multiple-choice question bank for that goal.
3. User grants Family Controls permission.
4. User picks restricted apps inside Checkpoint.
5. Checkpoint shields those apps.
6. User opens a restricted app.
7. iOS shows a Checkpoint shield.
8. User opens Checkpoint and answers a checkpoint question.
9. Correct multiple-choice answers grant a short unlock.
10. Checkpoint re-locks after the unlock window.

Important platform constraint:

- Apple's shield UI cannot host a full custom SwiftUI quiz.
- Apple's shield action extension cannot officially open the main app directly.
- The product should therefore treat the shield as the trigger and Checkpoint as the place where the actual question is answered.

## Built So Far

### App Shell

- SwiftUI iOS app project.
- Dark, modern visual system.
- Home, History, Skill, and Settings tabs.
- Goal onboarding flow.
- Simulated blocked-app attempt flow for previewing the checkpoint experience before real device testing.

### Question System

- Goal intake captures title, deadline, category, current level, and focus areas.
- The MVP question format is limited to multiple choice for simpler grading and testing.
- Local templates generate stored multiple-choice seed questions when AI providers are unavailable.
- Backend and Apple Foundation Models providers are wired behind a shared generation interface.
- AI generation should happen in batches and be cached locally, not live on every app-open attempt.
- Questions store prompt, expected answer, answer choices, explanation, topic, difficulty, format, status, ask count, correctness count, and next review date.
- Answer attempts are stored in history.
- Multiple-choice checkpoint answers are locally graded for the MVP before unlock.
- Revealing the expected answer before submission keeps the current attempt locked.
- Question batch state is tracked as idle, generating, ready, or failed.
- Settings includes a manual question batch refresh action.
- Users can report bad questions with a reason and optional note.
- Question generation now uses a provider router:
  - Automatic
  - Apple Foundation Models
  - Backend
  - Local Templates
- Automatic tries Apple Foundation Models first, then backend, then local templates.
- Backend generation is configured through a Settings endpoint URL.
- The app stores the last provider used and shows fallback messages when the preferred provider is unavailable.
- Generated batches pass through a shared sanitizer before storage to remove blank, duplicate, reported, invalid, and oversized questions.

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
- Initial topic levels are inferred from the user's typed current-level context, then adjusted by answer history.
- Skill tab shows average mastery and per-topic progress.

### Unlock Policy

- Correct-answer unlock duration is configurable.
- Multiple-choice misses stay locked.
- Incorrect and unclear answers do not unlock.
- Revealed expected answers force the attempt to stay locked.
- Emergency Pass duration is tracked through the shared unlock policy.

### Screen Time / Blocking

- Family Controls authorization request.
- FamilyActivityPicker-based restricted app/category/web selection.
- Selection persistence through shared App Group defaults.
- ManagedSettingsStore shielding.
- Temporary unshield after successful checkpoint.
- Re-lock timer.
- Re-lock reconciliation when the app becomes active.
- Family Controls and App Group entitlements.

### Screen Time Extensions

- Shield Configuration extension target.
- Shield Action extension target.
- Shield configuration shows Checkpoint-branded shield copy.
- Shield action records a pending checkpoint attempt in shared App Group state.
- Main app consumes pending shield attempts and opens the checkpoint answer flow.

## Current Technical Limits

- Full simulator/device build has not been run in this environment because full Xcode/simctl is not active.
- Real Screen Time behavior must be verified on a physical iPhone.
- Family Controls capability and App Groups must be enabled in Apple Developer/Xcode for the app and both extensions.
- Family Controls distribution requires Apple approval before App Store submission.
- The AI layer now has a provider interface with local templates, backend batch generation, and guarded Apple Foundation Models support.
- Storage is still prototype-level UserDefaults/App Group defaults, not SwiftData or SQLite.

## In-Progress Direction Before Device Setup

While Apple entitlement/device setup is pending, useful local work is:

- Replace prototype persistence with a production-ready local store.
- Add onboarding diagnostics for better initial competency estimates.
- Improve adaptive competency and diagnostic flows.
- Continue UI polish and error states.

## Current MVP Definition

The MVP is complete when:

- A user can create a goal.
- The app generates a question bank from the typed goal.
- The user can pick restricted apps inside Checkpoint.
- Those apps become shielded.
- Opening a restricted app shows Checkpoint's shield.
- The user can move from the shield to Checkpoint and answer a question.
- Correct answers temporarily unlock access.
- Incorrect or unclear answers keep access blocked.
- Missed questions return later.
- The Skill tab reflects topic-level competency.
- The app re-locks reliably after unlock expiration.

## Next Work

### P0

- Run the project in Xcode and fix real build issues.
- Enable Family Controls and App Groups for all targets.
- Test the shield loop on a real iPhone.
- Confirm Shield Configuration extension is invoked for app tokens and category tokens.
- Confirm Shield Action extension writes pending attempts.
- Confirm Checkpoint picks up pending attempts when opened.
- Replace prototype persistence with SwiftData or SQLite.
- Verify backend generation against a real endpoint.
- Verify Apple Foundation Models generation with the iOS SDK and supported hardware.

### P1

- Add a diagnostic quiz during onboarding.
- Explore open-ended AI grading after the multiple-choice MVP is stable.
- Add stricter repeat-attempt escalation.
- Add no-unlock Deep Focus windows.
- Add bad-question reporting.

### P2

- Multiple goals with per-app routing.
- User-provided materials such as notes, PDFs, links, or flashcards.
- Integrations with Anki, Quizlet, LeetCode, Notion, or Google Sheets.
- Server-side analytics and TestFlight instrumentation.
- Subscription/paywall experiments after retention is validated.

## Product Decisions

- Keep one active goal for the MVP.
- Keep AI generation batched and cached, not live on every app-open attempt.
- Do not ship API keys in the iOS app.
- Use the shield as the trigger, not as the full quiz surface.
- Track competence by topic so questions become challenging but doable.
- Keep the tone calm and progress-oriented, not punitive.

## AI Cost Strategy

The cheapest scalable architecture is hybrid:

1. Generate questions in batches.
2. Cache generated questions locally.
3. Track progress locally without AI.
4. Use deterministic scheduling for missed, due, and weak-area questions.
5. Use AI only when a goal is created, a question bank runs low, or the user explicitly asks for a refresh.

Avoid:

- Calling an AI API every time a user opens a blocked app.
- Using AI to grade every answer when multiple-choice answer keys can work.
- Shipping API keys inside the iOS app.

Recommended MVP path:

- Start with local templates and deterministic tracking.
- Add a backend endpoint for batch question generation.
- Generate 30 to 100 questions per goal or topic batch.
- Store expected answer, explanation, topic, difficulty, and quality flags.
- Use multiple choice for the MVP so grading is deterministic and cheap.
- Revisit open-ended prompts only after the core blocker loop is reliable.
- Add on-device generation later where available.

Cost options:

1. Template-only local generation
   - Lowest cost.
   - No per-prompt AI charges.
   - Weakest personalization.

2. Apple Foundation Models on-device
   - No per-prompt server bill.
   - Private and offline-capable.
   - Requires supported Apple Intelligence devices and Apple Intelligence enabled.
   - Smaller on-device model means prompts must be simpler and outputs need validation.

3. API batch generation
   - Best MVP quality-to-effort tradeoff.
   - Costs scale with batch refreshes, not every app-open attempt.
   - Requires backend for key security, quotas, and abuse control.

4. Self-hosted open-weight model
   - No vendor per-prompt fee.
   - Still has compute, hosting, maintenance, observability, and scaling costs.
   - Makes sense later if usage volume is high and predictable.

5. Bundled/local open-weight model in the app
   - Fixed server cost near zero.
   - Hard on iOS because models can be large, slower, battery-intensive, and quality varies.
   - Better as a later experiment than the first MVP path.

Current recommendation:

- MVP: template/local tracking plus backend batch generation.
- Add Apple Foundation Models as an on-device option for supported devices.
- Consider self-hosting only after usage data shows API spend is a real problem.

Apple Foundation Models device implication:

- Foundation Models works on Apple Intelligence-compatible devices when Apple Intelligence is enabled.
- Current iPhone support is iPhone 15 Pro models and iPhone 16 models or later.
- This excludes iPhone 15, iPhone 15 Plus, iPhone 14 series, iPhone 13 series, iPhone SE, and older devices.
- Because the likely early user base may include students with older iPhones, Foundation Models should not be the only MVP AI path.
- Best MVP architecture remains provider-based:
  - Use Apple Foundation Models on supported devices.
  - Use cached local templates when offline or unsupported.
  - Use backend batch generation as the universal fallback.

Implementation status:

- Provider enum and routing are implemented.
- Local template provider is implemented.
- Backend provider contract is implemented as a POST endpoint that returns question JSON.
- Apple Foundation Models provider is guarded behind iOS/FoundationModels availability and falls back automatically when unavailable.
- Provider output validation is implemented before questions enter the bank.
- Typed current-level context now seeds initial competency estimates.
- Settings exposes provider preference, backend endpoint, batch state, last provider, and quality report count.
- Backend request/response contract is documented in `docs/AI_BACKEND_CONTRACT.md`.
