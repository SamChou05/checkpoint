# Interactive learning map

## Goal and scope

Shorten Progress to a compact Learning map entry and keep Next Focus accessible. The destination is a native, interactive goal → skill → focus-point map, with evidence and earned history, safe configuration, and real effects on learning. This work follows the goal brief supplied on September 8, 2026 and the design discussion that prioritizes accumulated growth, relationships, and learner control.

## Product decisions

- Progress uses a general connected-nodes icon and a useful summary; the map owns exploration, history, and management.
- The explorer presents distinct goal, skill, and focus-point nodes, real membership/progression edges, stable branch focus, pan, zoom, fit, and an accessible list.
- Editing happens in an explicit draft, with a review of consequences before an exact-revision save.
- Retained IDs preserve learning continuity. A replacement receives a new ID, with the previous skill and evidence retained in history.
- Planned maps contain 3–6 skills, with at least one participating in practice. Each configured skill can have up to five focus points. Existing persisted maps must continue decoding safely.
- Skills have a description, practice emphasis (balanced, focus, maintain), challenge (adaptive, foundations, stretch), and pause state. Focus points have editable names and descriptions.
- Growth supports automatic advancement, reviewing suggestions, and manual management. Existing membership gates and evolution preferences are preserved.
- Focus-point details show available practice evidence rather than inventing independently calibrated mastery.

## Verification ledger

Completion requires direct evidence for every row below. Pending means unproven, not complete.

| Requirement | Evidence | Status |
| --- | --- | --- |
| Compact Progress entry; recommendation retained | Native Progress first-fold/main-state renders, mounted dedicated-map handoff, membership continuation, recovery entry during generation/failure | Verified |
| Goal → skill → focus-point hierarchy and true lineage | Graph identity/membership tests, selected branches and light/dark native renders; 50-stage history traversal draws only actual predecessor edges | Verified |
| Pan, pinch, fit, branch expansion, selection, detail navigation | Native accessibility actions verified branch selection, zoom, fit, detail and editor handoff. Camera anchor/translation/zoom bounds and combined gesture lifecycle checked. Physical pointer delivery fails in the Simulator automation surface (`windowNotFoundAtPosition`), independently reproduced by two agents | Implemented; physical pan/pinch check remains unverified |
| Meaningful status and preserved historical evidence | Goal/skill/objective identity-scoped evidence tests, reported-question exclusion, archived mastery snapshots, earned vs replaced distinction; focus points use evidence dots rather than inherited mastery rings | Verified |
| Configurable skill and focus-point editor | Draft, validation, identity/lineage and persistence tests. Native picker → review → save → reopen walkthrough preserved Focus more; a separate store reload assertion passed in `/tmp/CheckpointEditorLive.xcresult`. Temporary interactive fixture removed | Verified |
| Emphasis, challenge, and pause influence learning | Selector/allocation tests; 29 backend-provider contract tests; backend configuration and skewed full-objective-coverage tests. Shared edit-impact calculation determines fresh-question entitlement and review copy | Local behavior verified; configured-service rollout awaits user decision |
| Automatic, suggested, and manual growth | Persisted modes, entitlement gates, exact-revision acceptance/dismissal, active-checkpoint fencing, no repeated dismissed proposals, actionable acceptance error reasons | Verified |
| Legacy migration and safe substantive edits | Codable migration tests, retained IDs and answers, archived replacements, stable legacy objective IDs, safe older-app review-mode encoding, exact-revision saves | Verified |
| Empty, building, suggested, repair, goal switch and missing target states | First-run/state rendering regressions, goal-scoped pending handoffs, saved-map recovery access, authoritative explicit skill IDs | Verified |
| Long labels, growing history, Dynamic Type, VoiceOver, Reduce Motion, list | Native 320/393-point light/dark and accessibility-size renders inspected. Readable hit regions tested. Canvas bounds historical display; all earlier skills and archived focus-point evidence remain accessible through List | Verified in render/model checks; physical assistive-device walkthrough not claimed |
| Build, relevant suites, whitespace, committed milestones | 161 final signed native tests passed in `/tmp/CheckpointLearningMapFinal.xcresult`; final review-copy follow-up passed 7 editor tests. Backend agent reported 547-test run with Ruff/deployment checks; earlier async-bank suite passed 19 tests. Real Release build stops at existing missing `CHECKPOINT_PRIVACY_POLICY_URL` gate; it was not bypassed | Debug and relevant checks verified; distribution configuration remains incomplete |

## Verification notes

- Final native regression: 29 provider-contract, 8 first-run, 24 configuration, 7 editor, 12 explorer, 26 Progress, 16 migration, and 39 skill-map tests: **161 passed**.
- Native screenshots: `/tmp/CheckpointMapExplorerFinalRenders/manifest.json` and `/tmp/CheckpointMapIntegration-5-attachments/manifest.json`. Selected copies live under the task's `native-learning-map` visualization directory.
- Main implementation commits: `6d08f25`, `045fa9a`, `d66071c`, `d6b6e39`, `a34ccb3`, `a2b05cb`, `70a8afa`, `ff6ec52`, `03b4e5c`, `a4c06b9`, `f898652`.
- Live TestFlight source was inspected rather than assumed compatible. It predates edited descriptions and the newer verified-question pipeline. The reviewed, unexecuted change set is `learning-map-d6b6e39-review2-20260908` on `checkpoint-question-service-testflight` in `us-east-1`. All 37 existing parameters are retained; the candidate also adds the previously undeployed Claude reviewer. Exact release, bounded smoke, and rollback instructions are in `/tmp/checkpoint-learning-map-rollout-20260908/RELEASE_REVIEW.md`.
- The user has been asked whether to deploy that broader TestFlight update or finish with verified code and leave release to a separate task. No release or model smoke has been executed. This decision remains pending; elapsed time is not approval.

## Work boundaries

The current checkout contains unrelated solver-evaluation work. Commit only files owned by the learning-map work. The app points at the TestFlight backend. The updated service and worker must be verified there before distributing the editor; release preparation must preserve existing providers, quotas, credentials, and data. The live service predates additional question-verification work already in this checkout, so the complete release delta must be reviewed explicitly.
