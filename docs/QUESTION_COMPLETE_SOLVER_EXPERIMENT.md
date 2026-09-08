# Complete-question first-solver comparison

Status: prospective, September 8, 2026 UTC. This isolated sixteen-call experiment has not run. It does not change runtime or qualify a replacement verifier.

The exact [dispatch plan](evidence/complete-solver-plan-20260908.json) is prepared from source `e0f8d86eda1e48a89333c6b8e61a5db4c2083a5b` with canonical SHA-256 `50b9018d13841bad53ff7d337e47cc228db5aa97519467daf5c62fc7a71640a6`. Its byte SHA-256 is `0579474d33c84fa8efc2b544e54a2e985a6c9cb7261fab5b354eb280648ca69a`. The sixteen requests total 68,179 UTF-8 input text bytes, with a largest request of 5,017 bytes. A detached checkout at that source and Python 3.12.11/boto3 1.43.89/botocore 1.43.89 bind execution independently of concurrent app work.

The current independent solver receives the stem, goal, skill metadata and supplied sources, but no choices. Some ordinary MCQs put necessary task information in their choices. Two versions of “Which sentence is not in the past tense?” can require different answers while producing identical solver requests. Local capture tests demonstrate the same information loss for comparisons among listed integers. This is an input limitation; it does not prove the final reviewer necessarily fails.

The candidate gives a fresh first solver the complete MCQ while hiding the author's key, feedback, difficulty, existing answer coverage and independent assessments. It also replaces the free solution/outcome contract with one answer-adequacy judgment per exact choice. These two changes are tested together; this is not a causal isolation of input exposure from output-contract changes.

## Why this comparison differs from previous work

The [evidence choice audit](QUESTION_CHOICE_AUDIT_EXPERIMENT.md) already showed that structured support/refutation labels and citations can contain bad reasoning. The [fixed-solver compatibility mapper](QUESTION_SOLUTION_COMPATIBILITY_RESULTS.md) added no supported veto and still accepted the invalid all-pairs key. Neither result supports adding another model call.

This candidate replaces the first solver's task. It receives no prior solver answer to map or defend. The experiment tests necessary input retention and direct unique-answer identification on matched choice-dependent controls, with the known invalid all-pairs item retained as a boundary. It does not assume that per-choice labels fix shared model mistakes.

## Frozen cases and observations

The [fixture](../backend/bedrock-question-service/evals/fixtures/question_complete_solver.json) contains eight fixed questions, not freshly generated questions:

- Four versions of the same grammar stem: unique present answer, unique future-directed non-past answer, no supported choice, and two supported choices.
- A valid no-real-solution question using an ordinary negative answer phrase.
- A valid Boolean pair-existence question with the necessary expected hash-operation conditions.
- The unchanged historical invalid all-pairs complexity question.
- A valid missing-flow-rate question with an ordinary cannot-determine answer phrase.

Independent warranted choice counts and concise reasons are recorded outside model inputs before dispatch. The all-pairs record copies the question and request, not any earlier solver answer. The valid negative answers are substantive conclusions established by the premises, not fallbacks for model uncertainty.

Both ordinary negative choices deliberately differ from the baseline's application-owned canonical wording. Any retention gain on those cases must be labeled a negative-answer contract gain, separately from choice-dependent grammar retention. Such a gain alone cannot establish that restoring choices caused the improvement. The four identical baseline grammar requests are independent samples; variation among their outputs cannot reflect the withheld choices.

Each case receives two fresh calls, in counterbalanced order: the unchanged runtime stem-only solver and the complete-MCQ candidate. The baseline request is captured verbatim from the actual `verify_questions` solve callback, stopping before any review. The candidate preserves that same subject data and restores the choices in the runtime reviewer's deterministic order. Only the system contract and offered choices differ. Neither arm receives the other arm's response. No author or final reviewer runs in this stage.

The baseline uses its current parser and `_solver_rejection_reason`; its observation is eligibility to reach review, not final acceptance. The candidate parser requires exactly one row for each unchanged offered choice. Its code derives the following dispositions:

- Two or more supported choices: multiple-answer veto, even if another row is uncertain.
- No supported choices and all four refuted: zero-answer veto.
- One supported choice and three refuted: eligible only if that exact choice equals the hidden authored key.
- Any other unresolved row: abstention.
- Malformed output: operational/format failure, never a semantic catch.

“Refuted” concerns adequacy as an answer to the task. A possible numerical value can be refuted as the uniquely justified answer without proving that value impossible. Conversely, an unanswered factual question does not justify the substantive conclusion that its answer is indeterminate.

## Predeclared decision criteria

Continue to a separately frozen final-review handoff comparison only if:

1. All five valid controls have the correct unique candidate mapping, with supported reasons for the key and every rival. At least one valid baseline pre-review exclusion gains a supported candidate mapping.
2. The zero- and multiple-answer grammar controls receive the correct dispositions for supported semantic reasons. Abstaining because choices were absent does not count as successful defect detection by the baseline.
3. The invalid all-pairs authored key is not candidate-eligible. A supported output-size contradiction or an accurately identified unresolved scope issue must explain the veto. A generic abstention, wrong calculation, erased qualification, or accidental format failure supplies no successful correctness evidence. Scope abstention remains separately labeled; it is not proof of four factual refutations.
4. All sixteen calls complete with valid records. Any missing or malformed case prevents meeting the full prospective criterion; it is retained in the denominator and is not replaced or retried.

All reasons require independent inspection against the unchanged questions and the fixture's assessments. A correct label with contradictory or unsupported reasoning fails that content assessment. A broader valid-retention or production-error-rate claim is prohibited by this small, deliberately selected suite.

First-stage success alone will not switch runtime. A follow-up must reuse these exact solver outputs, test the actual proposed final-review handoff on eligible items, and inspect all returned main and choice feedback. The handoff must accurately describe the complete-MCQ solver; it cannot relabel its output as a stem-only solution. Runtime integration also needs gate, batching/index, call-budget and answer-isolation checks. General generated-question quality, useful difficulty, distractor quality, arbitrary-goal coverage, adaptive learning and production latency remain separate requirements.

## Execution and evidence

The [runner](../backend/bedrock-question-service/evals/checkpoint_complete_solver_eval.py) is dry by default. It reuses the preceding experiment's unchanged request recorder, preserving complete requests before dispatch, response text, stop reasons, usage, elapsed intervals and a reasoning-block count. Hidden reasoning text and credentials are not saved.

Settings are `us.anthropic.claude-opus-4-6-v1`, adaptive thinking/high effort, at most 16,000 output tokens per call, three-second connect and 100-second read timeouts, and one SDK attempt. There are at most sixteen calls, two per case, with 32,000 UTF-8 input text bytes per call and 512,000 total. These byte/token ceilings are not a dollar cap or a guaranteed whole-run deadline. No authoring, retries, repairs, replacements or top-ups are allowed. A provider or required-format failure stops further dispatch.

Preparation freezes source revision and file hashes, Python/provider dependency versions, exact requests, case order and limits. Execution requires the exact canonical plan hash and an unchanged rebuild before creating the provider client. A fresh output directory is required. The committed plan above and detached source worktree are recorded before the first call.
