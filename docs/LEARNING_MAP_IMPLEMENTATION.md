# Interactive learning map

**Release update:** The user approved deployment and needed model calls. The reviewed TestFlight update is deployed and its eight live contract checks pass. Direct generation exposed a deadline guard problem; that correction and real generation checks are in progress. The earlier preparation notes below describe the pre-deployment audit. See [the current release record](LEARNING_MAP_RELEASE.md) for authoritative live status.

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
| Pan, pinch, fit, branch expansion, selection, detail navigation | Native accessibility actions verified branch selection, zoom, fit, detail and editor handoff. Camera anchor/translation/zoom bounds and combined gesture lifecycle checked. Centering Simulator and bringing its windows forward restored coordinate taps and keyboard input. Native dragging remains a no-op on both the map and an ordinary iOS form, so that tool path cannot prove pan/pinch | Implemented; physical pan/pinch check remains unverified |
| Meaningful status and preserved historical evidence | Goal/skill/objective identity-scoped evidence tests, reported-question exclusion, archived mastery snapshots, earned vs replaced distinction; focus points use evidence dots rather than inherited mastery rings | Verified |
| Configurable skill and focus-point editor | Draft, validation, identity/lineage and persistence tests. Native picker → review → save → reopen preserved Focus more (`/tmp/CheckpointEditorLive.xcresult`). A second coordinate-tap and keyboard walkthrough renamed a skill, showed the keep-progress consequence, saved it, and passed a store-reload assertion (`/tmp/CheckpointMapPointerLive.xcresult`). Both temporary fixtures were removed | Verified |
| Emphasis, challenge, and pause influence learning | Selector/allocation tests; 29 backend-provider contract tests; backend configuration and skewed full-objective-coverage tests. Shared edit-impact calculation determines fresh-question entitlement and review copy. A refreshed package from `9ce484f` passes 80 contract tests loaded directly from its ZIP, including the current verification-policy contract | Local and packaged behavior verified; release decision and deployed smoke pending |
| Automatic, suggested, and manual growth | Persisted modes, entitlement gates, exact-revision acceptance/dismissal, active-checkpoint fencing, no repeated dismissed proposals, actionable acceptance error reasons | Verified |
| Legacy migration and safe substantive edits | Codable migration tests, retained IDs and answers, archived replacements, stable legacy objective IDs, safe older-app review-mode encoding, exact-revision saves | Verified |
| Empty, building, suggested, repair, goal switch and missing target states | First-run/state rendering regressions, goal-scoped pending handoffs, saved-map recovery access, authoritative explicit skill IDs | Verified |
| Long labels, growing history, Dynamic Type, VoiceOver, Reduce Motion, list | Native 320/393-point light/dark and accessibility-size renders inspected. Readable hit regions tested. Canvas bounds historical display; all earlier skills and archived focus-point evidence remain accessible through List | Verified in render/model checks; physical assistive-device walkthrough not claimed |
| Build, relevant suites, whitespace, committed milestones | The current complete signed native suite passed 985 tests in `/tmp/checkpoint-policy-ios-full-20260908.xcresult`, including all 161 map-related regression tests. The complete backend suite ran 628 tests without failures and with one optional-runtime skip. Real Release build stops at existing missing `CHECKPOINT_PRIVACY_POLICY_URL` gate; it was not bypassed | Debug and relevant checks verified; distribution configuration remains incomplete |

## Verification notes

- Final native regression: 29 provider-contract, 8 first-run, 24 configuration, 7 editor, 12 explorer, 26 Progress, 16 migration, and 39 skill-map tests: **161 passed**.
- Current compatibility audit: inspected the full native result bundle directly and confirmed **985 passed, zero failures or skips**. Its log includes every suite above and 22 asynchronous question-bank tests. The map views, graph, presentation, editor, and dedicated map tests are unchanged since `065bfa6`. The new policy changes passed checks for first-use admission, legacy bank migration, claim recovery, and retained history. The shared map-edit preflight uses the updated selector, so question availability observes the new policy without changing Starter edit entitlements.
- Current backend regression: `/tmp/checkpoint-exact-answer-backend-tests-20260908.log` records 628 tests, `OK (skipped=1)`. This is offline evidence, not deployed model behavior or proof of semantic question correctness.
- Native screenshots: `/tmp/CheckpointMapExplorerFinalRenders/manifest.json` and `/tmp/CheckpointMapIntegration-5-attachments/manifest.json`. Selected copies live under the task's `native-learning-map` visualization directory.
- Main implementation commits: `6d08f25`, `045fa9a`, `d66071c`, `d6b6e39`, `a34ccb3`, `a2b05cb`, `70a8afa`, `ff6ec52`, `03b4e5c`, `a4c06b9`, `f898652`.
- Live TestFlight source was inspected rather than assumed compatible. It predates edited descriptions and the newer verified-question pipeline. The unexecuted change set `learning-map-d6b6e39-review2-20260908` on `checkpoint-question-service-testflight` in `us-east-1` is superseded and must not be executed. The now-committed app requires `verificationPolicyRevision >= 1` and requests that minimum when claiming inventory; the old package emits no policy revision. A replacement runtime from `9ce484f` includes `verification_policy.py` and the compatible bank/reviewer changes. Its 80 packaged contract tests pass without calling a live provider. The updated smoke plan requires current policy provenance as well as edited scope and challenge behavior. Release and rollback evidence lives in `/tmp/checkpoint-learning-map-rollout-20260908/`, with the refreshed package in `candidate-9ce484f/`.
- The user has been asked whether to deploy that broader TestFlight update or finish with verified code and leave release to a separate task. No release or model smoke has been executed. This decision remains pending; elapsed time is not approval. Read-only continuation checks confirmed both live functions still match the captured September 3 rollback package and the superseded change set remains unexecuted.
- Final preparation: `learning-map-9ce484f-review-20260908` is `CREATE_COMPLETE` / `AVAILABLE`, unexecuted. The 93,827-byte package contains 18 tracked modules and hashes to `120dea9d0ffbf04b098dcd7d87bd5770b1c7a457fdfafd7b867b8bff62356769`. All 37 existing stack parameters are preserved; the same previously reviewed six additions remain. The expanded resource differences remain the two functions, their two roles, and queue visibility, with no resource additions/deletions. Both candidate and rollback artifacts were hash-checked. SAM build/lint and dry-run smoke passed. Relative to the superseded candidate, only the two function code locations change in the expanded template. See the committed [rollout review](../backend/bedrock-question-service/docs/learning-map-rollout.md) for the compatible release and smoke requirements.

## Work boundaries

Other tasks continue solver-evaluation work in this checkout. Commit only files owned by the learning-map work and package an exact committed runtime. The app points at the TestFlight backend. The updated service and worker must be verified there before distributing the editor; release preparation must preserve existing providers, quotas, credentials, and data. The live service predates additional question-verification work already in this checkout, so the complete release delta must be reviewed explicitly.

## Continuation verification

The implementation and native walkthrough turns made concrete progress. Coordinate taps and native typing were recovered through Simulator window placement; a real rename/save/reload walkthrough passed. Drag input was tested against both the map and an ordinary native form and remained ineffective, so no physical gesture success is claimed. The next continuation verified the committed question-policy work against the full 985-test result and prepared a compatible replacement backend package. No unrelated working changes were staged. The pending release decision is unchanged: local preparation does not authorize deploying the broader pipeline or invoking live models.
