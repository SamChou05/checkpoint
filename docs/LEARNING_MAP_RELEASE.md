# Learning map TestFlight release

## Current state

The user approved the reviewed TestFlight deployment and the model calls needed for verification on September 8, 2026 UTC. The `9ce484f` runtime was deployed successfully. The eight live contract checks passed, but direct question generation exposed a deadline problem that must be resolved before this release is considered functionally verified.

## Deployed milestone

- Stack: `checkpoint-question-service-testflight`, region `us-east-1`.
- Approved change set: `learning-map-9ce484f-review-20260908`.
- Execution token: `learning-map-9ce484f-approved-20260908`.
- Stack update began at `2026-09-08T05:19:55Z` and reached `UPDATE_COMPLETE`.
- HTTP and worker code match the reviewed 18-module, 93,827-byte package, SHA-256 `120dea9d0ffbf04b098dcd7d87bd5770b1c7a457fdfafd7b867b8bff62356769`.
- All 37 earlier parameters and six reviewed additions were preserved. The deployed outbox package and all resource identities remain unchanged. Both queue event mappings are enabled, and the worker mapping retains its original UUID.
- The final expanded template matches the reviewed template. The completed stack events carry the approved execution token and contain no failed deployment events.

The local `candidate-9ce484f/post-deployment-review.json` records the sanitized structural audit. The rollback package remains available. Deployment completion alone does not establish successful generation.

## Live checks and unresolved finding

All eight authenticated validation checks passed: description limits, challenge values/floor, one active branch, skewed coverage for thirty focus points, insufficient inventory rejection, paused-map identity, and manual growth rejection. These checks intentionally stop before provider calls or inventory writes.

Two direct synthetic generation attempts returned HTTP 502 after approximately 4.95 and 4.81 seconds. Both failures remain in separate reports; no successful result is claimed. Cloud records show two successful model invocations per attempt, with no third invocation. The runtime requires 26 seconds remaining before every provider call, while the HTTP Lambda has a 30-second deadline. After authoring and independent solving take more than four seconds, the guard prevents final review. The generic provider-failure response obscures that refusal.

An isolated reviewer availability probe succeeded (18 input and 5 output tokens). Both Lambda roles allow the reviewer profile and its three regional destination models. Those checks support the deadline diagnosis; they do not replace a successful endpoint test.

A separate background-path smoke is prepared with one synthetic install/goal, two paused skills, one active focus point, and a finite one-question bank. Its first invocation stopped in the helper before any ensure or claim request. Its original identities are retained for recovery. No background generation outcome has yet been established.

## Evidence location

The reviewed package, rollback evidence, and separate live reports are under `/tmp/checkpoint-learning-map-rollout-20260908/candidate-9ce484f/`:

- `smoke-validation-live.json`
- `smoke-question-live.json`
- `smoke-question-live-retry1.json`
- `post-deployment-review.json`
- `reviewer-permission-audit.json`
- `reviewer-cloudtrail-audit.json`
- `async-smoke-state.json`

These are bounded synthetic checks. They do not establish a population question-correctness rate or close the separate semantic-correctness workstream.
