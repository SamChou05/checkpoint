# Learning map: simple, personal, and credible

## Task

Implement the next native learning-map refinement in Checkpoint. Keep the experience simple and powerful: a learner should immediately understand what they are building, how their practice is going, and what to do next. Make the map feel premium through clear hierarchy, thoughtful interaction, and trustworthy personal context.

This brief preserves the approved direction from a local design conversation so a cloud task can work independently. It requests implementation; the repository already contains an interactive map, and the work below is its next iteration. Inspect the current code before deciding what needs changing.

## Approved experience

- Keep the Progress page short, with a compact connected-map emblem and an explicit action to open the full map.
- In the explorer, show meaningful connections from the learner's goal to skills and their focus points/subskills. Retain stable positions and identities as the learner explores. The map should grow from real configured content and practice evidence.
- Preserve exploration, selection, zoom, branch focus, navigation, and the existing edit/review/save flow. Users should be able to configure skills and focus points without losing earned progress or history.
- Keep the overview quiet. Reveal context and evidence when a learner selects a node or asks for details. Avoid an always-visible dashboard of metrics, legends, instructions, or decorative badges.
- Make the selected-skill panel compact: a name, an honest progress status, at most one short sentence of personal context, and one primary next action. Keep Details and Edit secondary. Preserve at least today's usable canvas space on small phones.
- Base personalization on the actual learner goal, configured priorities, and available practice evidence. Every personalized claim and recommendation reason must be grounded in the learner's goal, settings, or practice evidence; factual progress claims must be traceable to stored data. When evidence is limited, say so plainly. Do not invent readiness, mastery, improvement, or exact progress percentages.
- In on-demand details, explain why the skill matters, what recent practice supports its status, and the recommended next step. Keep the first view concise, with deeper information optional.
- Connect the primary action to the existing practice flow for the selected skill. Preserve that selection through routing, membership checks, and availability checks. Use truthful labels and clear unavailable states; never silently substitute an unrelated skill.
- Use restrained depth, readable labels, generous touch targets, and motion tied to meaningful changes. Respect Reduce Motion and retain the accessible List alternative. Preserve current editing safeguards and learning behavior.

## Approved palette: graphite and soft iris

The user accepted this direction in a conceptual color comparison. The comparison was a design reference, not evidence that these colors are already implemented. Apply the direction consistently within the map and its compact entry, integrating with existing theme conventions. Avoid an unrelated app-wide redesign.

| Role | Light | Dark |
| --- | --- | --- |
| Background | `#F7F7FA` | `#111319` |
| Panel | `#FFFFFF` | `#1C2029` |
| Raised surface | `#ECEAF6` | `#292D3A` |
| Primary text | `#242534` | `#F2F1F8` |
| Secondary text | `#696878` | `#B9B9CA` |
| Selection / interactive accent | `#6255B2` | `#B1A0FF` |
| Strong progress | `#2A755E` | `#80D5B4` |
| Informational / unpracticed | `#596D8C` | `#B2BED2` |
| Building progress | `#826020` | `#EBCB88` |
| Border | `#D3D1E0` | `#3D4052` |
| Primary action | `#6255B2` | `#B1A0FF` |
| Text on primary action | `#FFFFFF` | `#201A37` |

Iris identifies interaction and selection. Green and amber retain their actual progress meanings. Color must not be the only way to communicate state. Check the actual foreground/background combinations in native views and adjust individual tokens if needed for legibility while retaining this direction.

## Start here

Read these existing sources and follow their dependencies into state, evidence, theme, and practice routing:

- [LearningMapView.swift](../Checkpoint/Views/LearningMapView.swift)
- [LearningMapGraph.swift](../Checkpoint/Views/LearningMapGraph.swift)
- [LearningMapNavigator.swift](../Checkpoint/Views/LearningMapNavigator.swift)
- [LearningMapVisuals.swift](../Checkpoint/Views/LearningMapVisuals.swift)
- [LearningMapPresentation.swift](../Checkpoint/Views/LearningMapPresentation.swift)
- [LearningMapEditorView.swift](../Checkpoint/Views/LearningMapEditorView.swift)

Existing checks include [explorer](../CheckpointTests/LearningMapExplorerTests.swift), [interaction](../CheckpointTests/LearningMapInteractionTests.swift), [visuals](../CheckpointTests/LearningMapVisualsTests.swift), [editor](../CheckpointTests/LearningMapEditorTests.swift), [configuration](../CheckpointTests/LearningMapConfigurationTests.swift), and [Progress rendering/routing](../CheckpointTests/ProgressDashboardRenderingTests.swift) tests.

[Premium exploration notes](LEARNING_MAP_PREMIUM_EXPLORATION.md) document the previous native refinement and its optional offline manual fixture. [Implementation notes](LEARNING_MAP_IMPLEMENTATION.md) provide additional history. Historical passing results are not verification of new changes. The previous conversation and local screenshot files are not available to this cloud task; use this brief and the checked-out repository as the handoff.

## Scope and working rules

- Work on a `codex/` branch and produce a reviewable draft pull request. Do not merge or deploy.
- Preserve stable skill identities, saved progress, practice history, membership behavior, and edit safeguards. Use existing data and services; this UI scope does not require production credentials, backend deployment, or live model calls.
- Follow applicable `AGENTS.md` instructions. Commit after each cohesive, verified milestone with a descriptive subject/body explaining the change and validation. Confirm the branch, run relevant available checks and `git diff --check`, stage only task-owned files, and push verified milestones to the task branch. Do not force-push or commit credentials, local configuration, or build artifacts.
- Make routine design and implementation decisions independently within this brief. Surface a blocker only when missing access, a consequential product decision, or an environment limitation actually prevents progress.

## Validation in the cloud

The app uses native SwiftUI/UIKit. Do not treat a source-only review or unrelated backend tests as proof that the native UI builds or behaves correctly.

The repository's [CI workflow](../.github/workflows/ci.yml) already runs iOS simulator tests, a Release simulator build, and static analysis on a hosted macOS runner. It uploads an XCTest result bundle when available. Use that workflow for native checks when this environment can publish the branch and inspect the run. Do not assume the coding container itself has Xcode or a simulator. If access is missing, state precisely what could not run.

At handoff, the base was `f55e5018a5a71db72c8864d9a79a44bd8ae41877`. Its [CI run](https://github.com/SamChou05/checkpoint/actions/runs/34419385973) was still in progress when inspected, with failures already reported in backend unit tests and the iOS simulator test step. Re-check the final results and compare failures before attributing them to this change. Do not expand into unrelated backend work or present a failing baseline as a passing one.

Validate relevant behavior and native layouts for compact phones, long labels, light/dark appearance, larger text, limited practice evidence, selection, editing, and the practice handoff. Add or update meaningful regression checks for behavior changes. Review actual native screenshots if the environment or CI artifacts make them available; a conceptual mockup is insufficient. Follow the existing fixture notes to produce captures where practical. Do not claim physical pan/pinch or assistive-device verification without performing it.

## Finish

Deliver the implementation in a draft pull request, with a concise explanation of what improved, the tests and CI results actually observed, and remaining limitations. Include native screenshots if captured and reviewed; otherwise explicitly leave native visual review for the user's Mac after the flight. Keep the work reviewable even if a tool or access limitation prevents the last validation step.

Success means the first view stays calm, the next action is obvious and works for the selected skill, and the learner can inspect credible reasons behind their progress without being overwhelmed.
