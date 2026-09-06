# Adaptive learning contract

Pro practice uses the user's goal and source material as its scope. Each active skill has an independent question difficulty, recent evidence, and objectives needing follow-up. The manual level remains a minimum, not a requirement to accept each automatic increase.

## Evidence and progression

- Use the first answer to each distinct, verified question within the past 30 days. Reported questions and older unverified attempts remain in history but do not drive progression. Repeating a revealed answer does not demonstrate transfer or advance the curriculum.
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

Every newly generated question now requires a separate answer-blind AI review before it enters the bank. The reviewer receives the stem, rotated choices, goal, skill/objective, source scope, and recent question coverage. It does not receive the author's answer key, explanation, or difficulty label. The review must independently agree on the single best answer and actual difficulty and supply bounded explanations for all four choices. Missing, ambiguous, malformed, or disagreeing reviews reject the question; rejected stems are excluded from subsequent top-off attempts.

The reviewer uses the configured pinned model in a separate call, not a separate independently trained model. This reduces anchoring but cannot eliminate correlated model mistakes. Generation and review both count against the same provider-call budget, asynchronous quota, and deadline. No unverified output is returned when verification runs out of budget. The worker timeout is four minutes and the queue visibility is 24 minutes to accommodate the additional bounded calls. Public HTTP requests retain their existing timeout and may direct users toward asynchronous preparation when insufficient review time remains.

Automated tests exercise longitudinal improvement, independent skill levels, recovery, repeat-answer exclusion, history isolation, request validation, question allocation, and scheduler selection. They establish implementation behavior; they do not establish educational efficacy. Release evaluation must also examine real questions and repeated learner sessions for correctness, conceptual novelty, appropriate challenge, and retention.

## Teaching and rollout

Reviewed questions carry `verificationVersion: 1` and `choiceExplanations`, keyed by exact visible choice text. The quiz shows the selected choice's explanation plus the general reasoning after submission, and saves that feedback in the attempt snapshot for later review. Grading and answer review use the exact verified key; legacy answer-label and explanation heuristics cannot change it. The skill list shows the current adaptive practice level after evidence is available.

Pro preparation uses a new bank context and claims with `minimumVerificationVersion: 1`. Older cached questions are excluded from Pro selection; the backend discards old ready inventory and schedules replacements. Claim replay cannot bypass the verification requirement. Free legacy history and question decoding remain compatible.

Deploy and validate the backend before distributing the updated iOS client. Local test success is not a deployment, and enabling the client against an older backend leaves Pro waiting for verified inventory. Keep the live correctness evaluation as a release gate.
