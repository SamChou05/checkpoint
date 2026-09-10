# Prospective reviewer context comparison

The current default reviewer sees the earlier solver's choice judgments and
reasons. The latest native-format probe showed that both calls can defend an
interpretation that changes the question. This experiment tests whether access
to the earlier answer advocacy affects the final review. It adds no new critic,
subject-specific detector, external source, computation or authoring strategy.

Earlier choice-claim, split-evidence and obstruction experiments already tested
declared assumptions, source support and separate teaching review. They did not
isolate this information flow in the current reviewer-written feedback contract.
The authored-solution path already withholds solver reasoning, but also changes
teaching ownership and the review contract; its failures remain relevant evidence
that withholding alone cannot guarantee correctness.

## Fixed comparison

The runner is
`backend/bedrock-question-service/evals/checkpoint_reviewer_independence_probe.py`.
It freezes five existing reviewer batches containing twelve distinct items:

| Archive | Call indexes | Items and coverage |
| --- | --- | --- |
| September 9 delivery comparison | 2, 5, 23 | Four spreadsheet items and one ecology item |
| September 8 runtime qualification | 1, 4 | Seven items covering observed proportions, insufficient survey information, probability, causal inference and survey bias |

These are every default reviewer call in those two fixed archives, preserving
the actual original batch boundaries. Selection uses existing requests rather
than rewritten questions or constructed solver advice. It includes the defective
spreadsheet item and valid controls, including a natural cannot-determine answer.
It contains no language/grammar items and is not a representative user-goal sample.
Do not generalize a positive result to all subjects or adaptive learning.

Each batch receives two fresh reviewer calls. `solver_context` includes the
entire historical `independentSolutions` field. `withheld_solver_context` omits
that field, including supported-choice labels as well as reasons. Questions,
choice order, sources, history, remaining context and provider settings are
identical within each pair. Order reverses on alternate pairs. Historical
reviewer outcomes are background evidence, not the fresh baseline.

Both arms share the same minimal conditional wording explaining that solver
records may be absent. Both use the current complete-review instructions and
native reviewer schema. The two older runtime batches predate the three-line
rejected-envelope instruction, which is restored in both arms. These common
changes mean neither arm is an untouched production baseline. The only
between-arm difference is presence of the solver records.

Use the already-accessible US Sonnet 4.6 profile, disabled thinking, temperature
0.2, 6,000 maximum output tokens, read timeout 75 seconds, connect timeout three
seconds, one SDK attempt and a 240-second disposable worker deadline. There are
exactly ten planned calls and at most 32 KiB of serialized request per call,
327,680 bytes total. Bytes are not a certified token or dollar cap. No model
agreement, model/default setting or production deployment changes.

The existing parent-owned observation and durable capture sequence is shared
with the native-stage probe. Provider, nonterminal response, missing observation,
worker cleanup and persistence failures stop the run. A usable completed textual
response failing schema, adaptation or item correlation is recorded as content
failure and does not cause a retry or replacement. A completed response with
unusable observed content still stops operationally. Do not resume a completed
or failed capture or repeat a trial until it passes.

## Application behavior and assessment

Before dispatch, replay the original generation prefixes or original fixed
question operation through the current code to recover the actual candidates,
normalized request and historical solver record. Every request must match its
archive, allowing only the documented shared envelope instruction migration.
Freeze those inputs in the plan. No replay stub can call a provider or storage.

After each usable adapted reviewer response, replay actual `verify_questions`
with the frozen candidates and solver, and that arm's exact fresh review. The
callback verifies the original user context before applying the prospective
reviewer-only intervention. The ordinary solver veto, authored-key comparison,
feedback checks and difficulty requirements remain enforced. Questions rejected
by the historical solver cannot be rescued. Report these as **local simulated
policy outcomes**, never as fresh full-pipeline generation or delivery.

Freeze an independent assessment of the unchanged twelve subjects before any
fresh responses. Its packet hides authored keys, prior solver records, teaching
and arm identities; the assessor may retain previous task context, so do not
claim a fully blinded fresh evaluator. Require literal per-choice judgments,
material defects/ambiguity, supported answer and assessed difficulty. Keep
reasonable interpretation disagreements visible instead of relabeling them to
favor an arm.

Then export the exact fresh reviews with opaque identifiers and no arm/solver
records. Independently assess validity, answer, main explanation and every
choice explanation against the frozen subjects. Freeze those judgments before
unmasking. Style or the response itself may reveal clues. Assessments by coding
agents are fallible, not expert ground truth or measured learning outcomes.

Report separately:

- Semantic approval of defective/ambiguous items and loss of supported controls.
- Correct key with fully sound main and all choice feedback.
- Schema/adaptation failures and independent difficulty requirements.
- Actual local policy returns, preserving every reviewed item in its denominator.
- Input/output usage, unknown usage, and worker/SDK timing with their proper scope.

Credit a rejection only when its substantive reasoning identifies the actual
defect. A bare `valid:false` has no reason in this contract and cannot alone prove
defect detection. Format or difficulty exclusion cannot be counted as a factual
catch. A correct key paired with misleading teaching is not a successful item.

The intervention is promising only if defective semantic approvals decrease
without a new rejection of a supported control or newly unsupported teaching.
Even then, evaluate fresh questions in the normal runtime before considering a
production change. A mixed or null result does not qualify removal or justify
another differently worded approval layer. The full generalized correctness goal
remains open regardless of this selected diagnostic's outcome.

## Preparation status

This document was frozen prospectively in `040d0e5`, before calls. The single
comparison is now complete; see [the results](QUESTION_REVIEWER_INDEPENDENCE_RESULTS.md).
The preparation required committing and verifying the runner, tests and protocol
before freezing the plan. Verify source
and dependency hashes, exact paired request deltas and the independent-assessment
freeze before dispatch. Record the final plan hash and one fresh capture path in
the result artifact. The experiment does not depend on the unactivated Opus 5
comparison, whose runner still uses the historical stem-only/legacy contract.
