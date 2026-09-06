# Adaptive learning contract

Pro practice uses the user's goal and source material as its scope. Each active skill has an independent question difficulty, recent evidence, and objectives needing follow-up. The manual level remains a minimum, not a requirement to accept each automatic increase.

## Evidence and progression

- Use the first answer to each distinct question within the past 30 days. Repeating a revealed answer does not demonstrate transfer or advance the curriculum.
- Start at the goal's minimum level. Five distinct questions at the current level, at least four correct, and coverage of at least two available objectives advance that skill one level. The ceiling is level 5.
- Three misses in four questions at the current level step that skill back one level, respecting the chosen minimum.
- Recent results identify unresolved objectives and provide bounded question/selected-answer/reference-answer evidence to the AI. Focus Wins and other private notes are excluded.
- The scheduler prefers questions near the skill's target while preserving missed-question review and skill breadth. Replenishment measures coverage at the new target so a large old easy bank cannot prevent harder questions being prepared.
- Bank revisions change with difficulty, skill weights, and unresolved objectives, not on every answer. Requests persist across relaunch, and quizzes continue to use local inventory.
- Curriculum advancement uses recent distinct evidence across every objective, a correct streak, and hard-question evidence. Old lifetime mistakes remain in history without permanently preventing advancement.

## Generation contract

`adaptiveSkillPlans` is an optional array of at most six plans, each scoped to an active skill UUID. Plans carry `targetDifficulty`, recent accuracy/evidence count, up to five focus objective IDs, and up to three recent mistakes. The service validates skill/objective ownership and bounds every learner-provided string. These fields are untrusted evidence, never model instructions.

Generated questions must match their skill's target difficulty. The worker weights missed objectives more heavily while retaining coverage of the other objectives. Follow-up questions should test the same concept in a new scenario or representation, not reproduce a previously revealed answer.

## Validation boundary

Automated tests exercise longitudinal improvement, independent skill levels, recovery, repeat-answer exclusion, history isolation, request validation, question allocation, and scheduler selection. They establish implementation behavior; they do not establish educational efficacy. Release evaluation must also examine real questions and repeated learner sessions for correctness, conceptual novelty, appropriate challenge, and retention.
