# Learning map TestFlight release

## Current state

The user approved the reviewed TestFlight deployment and the model calls needed for verification on September 8, 2026 UTC. The learning-map runtime and its deadline correction (`2a8d97c`) are deployed successfully. All eight live contract checks pass. A direct generation run now completes both full review passes within the HTTP deadline, but both drafts were rejected. The asynchronous path has demonstrated safe supersession after an edit; successful generation and claim remain unverified. The durable worker-budget correction (`e5818fc`) is verified and committed; its deployment is being prepared.

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

The edited job initially made three calls, its draft was rejected, and it remained queued with zero ready questions. Before the budget repair, a real SQS redelivery spent two more calls and terminally failed at five, still with zero ready questions. The current worker mistakenly couples the five-delivery SQS setting to the provider budget, leaving fewer than three calls for a complete retry. The terminal job will not be replayed or reset. The verified `e5818fc` correction uses the existing six-call request setting, seeds the local allowance from the leased durable counter, and terminates without doomed partial reviews. It preserves recovery after an ambiguous successful database commit. The full backend suite passed 697 tests with one optional skip; 48 focused regressions, lint, deployment-script checks, and independent review passed. Daily quotas and queue delivery limits remain unchanged.

Two separately archived, one-pass local diagnostics of the edited scope each made three calls and were rejected. With thinking disabled, the authored service-plan answer was $2 while the written values imply $14; with thinking enabled, the key was $3 while the values imply $4. Both omitted the correct option. Independent solving and review caught the defects. These are fresh local samples, not the unseen contents of the earlier live rejections, and provide no basis to promote a thinking-setting change or infer a population correctness rate.

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
