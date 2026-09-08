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

| Requirement | Evidence to collect | Status |
| --- | --- | --- |
| Compact Progress entry; recommendation retained | `ProgressDashboardRenderingTests`: native first-fold and main-state renders, mounted dedicated-map handoff and membership continuation; 41 integration/onboarding/editor tests pass in `/tmp/CheckpointMapIntegration-4.xcresult` | Verified; final UI pass pending |
| Goal → skill → focus-point hierarchy and true lineage | Graph/layout tests; actual persisted map and screenshot | Pending |
| Pan, pinch, fit, branch expansion, selection, detail navigation | Native interaction/render verification | Pending |
| Meaningful status and preserved historical evidence | Focused evidence/history tests | Pending |
| Configurable skill and focus-point editor | `LearningMapEditorTests`: isolated drafts, retained IDs, replacement lineage, ordering, validation and native light/dark/large-text renders; foundation persistence tests | Automated checks verified; live editor walkthrough pending |
| Emphasis, challenge, and pause influence learning | Foundation selector/allocation tests; 29 final `BackendQuestionEngineContractTests`; backend configuration/allocation suites including full objective coverage under 99:1 weights | Local checks verified; configured-service rollout pending |
| Automatic, suggested, and manual growth | `LearningMapConfigurationTests`: persisted modes, entitlement, exact-revision acceptance/dismissal, live-checkpoint fencing and no repeated dismissed proposals | Verified; final error-message review pending |
| Legacy migration and safe substantive edits | 93 foundation tests across configuration, migration, skill-map and async-bank suites; archived replacements, retained question/answer lineage, stable default objective IDs, safe legacy review preference | Verified |
| Empty, building, suggested, repair, goal switch and missing target states | Native primary-state renders and first-run tests; mounted pending handoffs/goal changes; saved map remains reachable during generation and failure; explicit stale IDs cannot resolve to a different branch | Verified |
| Long labels, growing history, Dynamic Type, VoiceOver, Reduce Motion, list | Layout tests and representative native renders | Pending |
| Build, relevant suites, whitespace, committed milestones | Final command results and commit history | Pending |

## Work boundaries

The current checkout contains unrelated solver-evaluation work. Commit only files owned by the learning-map work. The app points at the TestFlight backend. The updated service and worker must be verified there before distributing the editor; release preparation must preserve existing providers, quotas, credentials, and data. The live service predates additional question-verification work already in this checkout, so the complete release delta must be reviewed explicitly.
