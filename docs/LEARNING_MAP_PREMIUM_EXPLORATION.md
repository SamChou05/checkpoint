# Learning map: visual depth and closer exploration

The September 8 refinement makes the existing native map visibly explorable and editable. Progress keeps its compact entry card, now with a small connected goal–skill–focus emblem and an explicit Explore map action.

## Experience

- Layered node surfaces, evidence rings, a subtle dot field, and light moving along selected connections give the map depth without moving its tap targets or inventing progress. An inspected focus point highlights only its actual parent path.
- Selecting a skill unfolds its focus points. Selecting a focus point enlarges its marker and centers its complete target and label at closer zoom. Existing graph identities and world positions remain stable.
- Zoom controls show magnification relative to the fitted branch. Fit restores the complete branch; All skills returns to the overview. A small navigator appears after zooming or panning and lets the learner reposition the same camera without changing selection or magnification.
- Edit is visible in the toolbar and selection preview. Node context menus also expose details, closer inspection, editing, and overview navigation. Existing draft/review/save behavior retains skill identity and earned progress.
- Motion stops for Reduce Motion, VoiceOver, Switch Control, an inactive scene, or the explicit Pause map motion action. Ambient effects also stop while gesturing, viewing List, inspecting details, or using the editor. List remains the default for assistive navigation and larger text sizes.
- A brief exploration hint sits beside the controls so it cannot cover the topmost node on a small phone. Breadcrumb buttons have individual 44-point touch regions.

This refinement changes native presentation and camera behavior. It requires no backend deployment or live model requests.

## Verification

There are **77 passing automated checks** across the final implementation: 14 interaction/camera/policy tests, 12 explorer tests, 7 editor tests, 8 visual tests, 26 Progress rendering/routing tests, and 10 theme tests. The optional manual walkthrough fixture skips during ordinary runs and was separately executed successfully with offline services.

- `/tmp/CheckpointPremiumMap-4.xcresult` verifies the final application views and the interaction, explorer, editor, Progress, and theme suites. Three new visual tests initially failed because their tiny hosting windows introduced a safe-area offset into pixel-region comparisons. No production visual change was needed.
- `/tmp/CheckpointPremiumMap-5.xcresult` passes all eight visual tests using native ImageRenderer with explicit dimensions, traits, and animation dates. Exact pixel assertions verify active versus suppressed motion, unchanged node centers, honest focus-point evidence dots, independent skill progress, unclipped halos, and light/dark contrast. The evidence spring remains bounded and monotonic.
- `/tmp/CheckpointPremiumMap-Live2.xcresult` hosts the actual map container and editor in a real simulator window with six skills and five focus points per skill, mixed progress, an earned earlier branch, and local service doubles. Native pointer/keyboard actions opened a branch, focused its last focus point, repositioned through the navigator, changed zoom from 311% to 389%, fitted the branch to 100%, paused and resumed motion, inspected details, opened the correct editor, renamed a skill, reviewed and saved the edit, returned to all skills, and opened List. The renamed branch retained its Strong status and 18 answers. A subsequent practiced focus point correctly showed two linked answers at closer zoom. The fixture's final record confirms the map changed while retaining six skills.
- Native 320- and 393-point light/dark renders and accessibility-size List/entry/editor renders were visually reviewed. Preview copies are in the task's `premium-learning-map` visualization directory.

Physical pan/pinch success is not claimed. The computer-use drag operation produced no movement in the simulator, consistent with the previously documented input-tool limitation. The real SwiftUI drag/magnify gesture remains connected to the tested anchor-preserving camera operations; direct zoom controls, navigator movement, fit, and branch navigation were verified live. Physical-device gesture and assistive-device sign-off remain separate from these simulator and rendering checks.

## Repeatable manual fixture

`LearningMapInteractionTests/testOptInNativeInteractionWalkthrough` is opt-in with `CHECKPOINT_MAP_INTERACTION_QA=1`. It uses isolated temporary storage and offline question services, restores the previous window, and cleans up its temporary store. Set the test target's environment in a temporary `.xctestrun` file; shell `SIMCTL_CHILD_` variables were not forwarded by this Xcode test runner. Optional controls are `CHECKPOINT_MAP_INTERACTION_QA_SECONDS` (10–600), `CHECKPOINT_MAP_INTERACTION_QA_OUTPUT`, `CHECKPOINT_MAP_INTERACTION_QA_APPEARANCE` (light/dark), and `CHECKPOINT_MAP_INTERACTION_QA_ACCESSIBILITY_TEXT=1`. Writing the output directory's `finish` file ends the fixture early. It produces initial/final captures and state records; pointer success still requires explicit observation.
