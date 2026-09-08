# Learning map TestFlight release

## Current state

The native learning-map implementation and compatible TestFlight backend are verified. The user approved deployment and needed model calls. The final runtime (`601d273`) is deployed, all eight live contract checks pass, and a real asynchronous question generated from the edited map was manually reviewed and successfully claimed. Earlier failed generation trials are preserved below. This establishes the tested integration, not a general question-correctness rate.

## Initial deployed milestone

- Stack: `checkpoint-question-service-testflight`, region `us-east-1`.
- Approved change set: `learning-map-9ce484f-review-20260908`.
- Execution token: `learning-map-9ce484f-approved-20260908`.
- Stack update began at `2026-09-08T05:19:55Z` and reached `UPDATE_COMPLETE`.
- HTTP and worker code match the reviewed 18-module, 93,827-byte package, SHA-256 `120dea9d0ffbf04b098dcd7d87bd5770b1c7a457fdfafd7b867b8bff62356769`.
- All 37 earlier parameters and six reviewed additions were preserved. The deployed outbox package and all resource identities remain unchanged. Both queue event mappings are enabled, and the worker mapping retains its original UUID.
- The final expanded template matches the reviewed template. The completed stack events carry the approved execution token and contain no failed deployment events.

The local `candidate-9ce484f/post-deployment-review.json` records the sanitized structural audit. The rollback package remains available. Deployment completion alone does not establish successful generation.

## Initial live checks and deadline diagnosis

All eight authenticated validation checks passed: description limits, challenge values/floor, one active branch, skewed coverage for thirty focus points, insufficient inventory rejection, paused-map identity, and manual growth rejection. These checks intentionally stop before provider calls or inventory writes.

Two direct synthetic generation attempts returned HTTP 502 after approximately 4.95 and 4.81 seconds. Both failures remain in separate reports; no successful result is claimed. Cloud records show two successful model invocations per attempt, with no third invocation. The runtime requires 26 seconds remaining before every provider call, while the HTTP Lambda has a 30-second deadline. After authoring and independent solving take more than four seconds, the guard prevents final review. The generic provider-failure response obscures that refusal.

An isolated reviewer availability probe succeeded (18 input and 5 output tokens). Both Lambda roles allow the reviewer profile and its three regional destination models. Those checks support the deadline diagnosis; they do not replace a successful endpoint test.

## Deployed deadline correction

The code-only `2a8d97c` update reached `UPDATE_COMPLETE` on September 8 at 06:19 UTC, using execution token `learning-map-deadline-2a8d97c-approved-20260908`. Both functions match the reviewed 18-module, 94,803-byte ZIP, SHA-256 `43f01baf9214bed3b7c10384d5389f6958b6608a355e1b145c3c012b86f6a9c9`. All 43 parameters, providers, quotas, resource identities, and the outbox remain unchanged.

Provider transport timeouts now fit the remaining invocation time, while configured timeouts remain upper bounds. The guard rechecks the actual transport bounds before calling and reserves response time. Explicit deadline exhaustion has its own error and metric. HTTP timeout remains 30 seconds; review is unchanged. Verification included 662 backend tests with one optional skip, 111 tests against the exact packaged modules, focused deadline regressions, build/lint, and independent review.

All eight live validation checks passed again. The subsequent direct generation run made all six provider calls in 22.22 seconds (22.49 seconds at the client). Both full author/solver/reviewer passes completed, demonstrating the deadline repair. Both drafts were rejected by the reviewer and no question was returned. This is a quality failure, not successful end-to-end generation.

## Background edit and supersession checks

A synthetic install and goal use two paused skills, one active focus point, and finite one-question banks. An initial helper error occurred before any ensure or claim; recovery retained the original handles. The first actual job made three calls and returned no questions after answer disagreement.

A substantive map edit changed the active scope from shopping receipt totals to service-plan fees, included allowances, and overage. Skill and objective identities were retained. One normal ensure advanced the same goal to the edited bank. The older bank became superseded, and a later real worker delivery marked its job superseded with the provider counter unchanged at three. This establishes disposal without extra calls after the edit; it does not claim cancellation of already-issued calls.

The edited job initially made three calls, its draft was rejected, and it remained queued with zero ready questions. Before the budget repair, a real SQS redelivery spent two more calls and terminally failed at five, still with zero ready questions. The old worker mistakenly coupled the five-delivery SQS setting to the provider budget, leaving fewer than three calls for a complete retry. The terminal job will not be replayed or reset. The verified `e5818fc` correction uses the existing six-call request setting, seeds the local allowance from the leased durable counter, and terminates without doomed partial reviews. It preserves recovery after an ambiguous successful database commit. The full backend suite passed 697 tests with one optional skip; 48 focused regressions, lint, deployment-script checks, and independent review passed. Daily quotas and queue delivery limits remain unchanged.

Two separately archived, one-pass local diagnostics of the edited scope each made three calls and were rejected. With thinking disabled, the authored service-plan answer was $2 while the written values imply $14; with thinking enabled, the key was $3 while the values imply $4. Both omitted the correct option. Independent solving and review caught the defects. These are fresh local samples, not the unseen contents of the earlier live rejections, and provide no basis to promote a thinking-setting change or infer a population correctness rate.

## Deployed worker-budget correction

The code-only `e5818fc` update reached `UPDATE_COMPLETE`, with stack update timestamp `2026-09-08T06:48:05Z` and execution token `learning-map-async-budget-e5818fc-approved-20260908`. Both functions match the reviewed 18-module, 95,594-byte ZIP, SHA-256 `e19355d3f5092525df649b44f9d034a423b7b5adc0d8667f2caab19bb50c3022`. Independent audit verified both templates against the candidate, all 43 parameters, all 32 resource identities, unchanged function environments, unchanged model settings, and the unchanged outbox. No failed deployment or rollback event occurred.

All eight live contract checks passed again. Verification also includes 159 tests imported from the exact deployment ZIP, with zero failures or skips, in addition to the source-suite results above.

A separate version-9 edit retained all goal/skill/focus identities and narrowed the service-plan description to whole-unit usage without taxes, prorating, tiers, or rounding. This was an explicitly recorded new map-edit trial, not a reinterpretation of earlier failures. The normal ensure saved the new scope and target difficulty 3 and triggered one real SQS job. It completed six provider calls in 45.28 seconds, with two independently reviewed drafts rejected, zero questions returned, and immediate terminal failure. No 24-minute doomed retry was needed. Prior version-7 and version-8 call counters remain three and five. No terminal job or quota counter was reset.

At this milestone the map-to-generation contract and bounded failure behavior were verified, while successful generation and claim remained unverified. The subsequent results below close that integration check; the earlier rejections remain failures.

## Final prompt correction and successful live claim

A separate Foundations control trial changed only the active challenge, map version, and context revision. The server correctly selected target difficulty 2, preserving all descriptions and identities. Both reviewed drafts were rejected; the version-10 job terminalized at six calls with zero questions. Switching the author to Sonnet in a separate three-call local diagnostic also produced a wrong key and no valid option. Neither result justified changing deployed models or thinking settings.

A minimal local experiment changed only the author prompt's sample JSON field order: the finished explanation comes before the answer key and choices. The original Kimi author then produced a coherent question that passed the unchanged independent solver and reviewer. A manual check confirmed both plans cost $65. This fresh sample supported trying the concrete correction; it did not establish causality or a population accuracy improvement.

The exact one-line correction was committed and pushed as `601d27312753864282d2215bd54eec3070a58672`. The full backend suite ran 716 tests with zero failures and one optional skip; all 159 tests against the exact ZIP passed. The deployed 18-module, 95,594-byte ZIP hashes to `10b7e02a1d2c32e69c9bd7c526346e8122a09caff1fabcb44ad03b11652c1e8d`. Independent post-deployment review confirmed the approved execution token `learning-map-explanation-first-601d273-approved-20260908`, both function hashes, exact templates, all 43 parameters, all 32 physical resource identities, unchanged model and environment settings, and the unchanged outbox. All eight live contract checks passed again.

The version-11 smoke restored Stretch while preserving the same service-plan descriptions, goal, skill, and focus-point IDs. One normal ensure triggered a real SQS job. The first draft was rejected for difficulty; the second passed at the required difficulty 3. All six provider calls completed in 31.99 seconds, returning one question. The old version-7/8/9/10 counters stayed at 3/5/6/6. No counter was reset, no terminal job was replayed, and no extra inventory was requested.

The returned item compares a $40 unlimited gym plan, $5 day passes, and a $35 ten-visit bundle with $4 overage. At twelve visits the totals are $40, $60, and $43, giving exactly one correct choice. Root and a second agent independently confirmed the literal answer; the second agent assessed the stem and choices before seeing the key or feedback. All main calculations are correct. The $48 distractor explanation describes charging for included visits but does not explicitly name the additional omission of the fixed fee; both reviews found this a minor precision caveat, with the correct formula clearly provided elsewhere.

One claim request returned HTTP 200 and the exact manually reviewed question, with matching skill/focus IDs, difficulty 3, verification version 1, and policy revision 1. The durable receipt exists, the job is complete, generated inventory is exactly one, and ready inventory is zero after claim. This verifies the edited map's actual generation and retrieval path without weakening review.

The [committed synthetic evidence](evidence/learning-map-live-release-20260908.json) retains successful and failed trials, source hashes, provider counters, exact accepted content, and the manual assessments. Continued question-quality work remains separate; one successful integration example does not qualify general accuracy or future model output.

## Evidence location

The reviewed package, rollback evidence, and separate live reports are under `/tmp/checkpoint-learning-map-rollout-20260908/candidate-9ce484f/`:

- `smoke-validation-live.json`
- `smoke-question-live.json`
- `smoke-question-live-retry1.json`
- `post-deployment-review.json`
- `reviewer-permission-audit.json`
- `reviewer-cloudtrail-audit.json`
- `async-smoke-state.json`

The deadline package and its separate validation/generation reports are in the adjacent `candidate-deadline-fix/` directory. Original failures and both local diagnostic traces are retained, along with `async-both-trials-status-before-budget-release.json`.

These are bounded synthetic checks. They do not establish a population question-correctness rate or close the separate semantic-correctness workstream.

Final deployment and live-claim artifacts are in `candidate-explanation-first/` and `smoke-v11-prompt-order/` under the same rollout directory.
