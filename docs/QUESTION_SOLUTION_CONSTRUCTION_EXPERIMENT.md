# Independently solved answer construction

Prospective protocol, September 8, 2026 UTC. This experiment changes who owns a
question's key. It does not add another compatibility judge or replace the
production generator. The previous goal turn made concrete progress through
policy freshness and literal answer-disagreement fixes; the remaining free-text
contradiction and shared-model errors remain open.

Pre-dispatch validation: 25 focused contract/runner checks pass, including key
replacement attempts, unknown solutions, duplicate alternatives, hidden metadata,
budget/order enforcement, persistence failures, and modified replay joins. The
complete 653-test backend suite completes without failures, with one existing
optional-runtime skip. Ruff and diff checks pass. These use scripted model
responses, not fresh correctness observations. Independent review verified the
reference summaries and exact historical stem; AWS's read-only identity check
also succeeded before preparation.

## Why test this change

The earlier author prompts already asked a model to solve before writing choices.
They nevertheless returned the task, key, distractors, and explanation together.
Later independent solutions could advise review, while the key remained the first
author's. The new sequence freezes the task, asks a separate call for a concise
answer, and builds the choices around that exact answer. A later author cannot
substitute a positive method for an independently supplied negative conclusion.

Separating distractor construction from an established question and answer is
consistent with [EDGE's question-and-answer-guided generation task](https://aclanthology.org/2020.coling-main.189/).
That study evaluated a different trained model and reading-comprehension data;
it does not demonstrate that this proposed pipeline works. Its useful design
distinction is between an alternative's incorrectness and its plausibility.

Our [complete-question solver experiment](QUESTION_COMPLETE_SOLVER_RESULTS.md)
already showed that both fresh solver configurations can give the same wrong
all-pairs answer. Exact answer ownership does not turn that answer into truth.
The [native artifact follow-up](QUESTION_ARTIFACT_NATIVE_FOLLOWUP.md) also showed
why a correctly bound key is insufficient when challenge or feedback is weak.

## Four candidates and at most fifteen calls

The [frozen-input fixture](../backend/bedrock-question-service/evals/fixtures/question_solution_construction.json)
specifies photography, English writing, lunar observations, and the exact
historical all-pairs task stem. The first three start from learning goals and
inspected reference summaries. They each receive one task-author, solver,
distractor-author, and reviewer call. The fixed stem omits task authorship and
receives the other three calls. Case order is fixed by the fixture. No old key,
old choices, assessment labels, or another case's output enters a provider call.

The model is `us.anthropic.claude-opus-4-6-v1` with adaptive thinking, high effort,
16,000 maximum output tokens, one SDK attempt, a three-second connection timeout,
and a 100-second read timeout. Limits are fifteen calls overall, four per case,
32,000 UTF-8 input-text bytes per call and 480,000 total. Bytes are not tokens or
a certified spend cap. The read timeout is not a hard whole-trial deadline.
Missing usage after a failed call remains unknown.

No repair, replacement, retry, top-up, native execution, automatic model change,
production write, or deployment belongs to this trial. Provider or malformed
response failures stop later dispatch. Well-formed unsupported content records a
case rejection and skips its remaining calls, without replacing the candidate.

## Construction boundary

1. The task author supplies a standalone stem and learning metadata, with no key
   or choices. All necessary passage, example, or comparison material must be
   displayed; a reference summary cannot replace a missing scenario premise.
2. The independent solver sees that exact task and references, without choices.
   It supplies `answerText` separately from support and missing assumptions.
   Uncertainty and invalid tasks cannot produce a candidate. Nonexistence or
   insufficient information may be substantive answers. An answered record with
   required extra assumptions is rejected.
3. The application keeps `answerText` unchanged. The distractor author may write
   three alternatives and proposed explanations, with no task/key editing fields.
   It cannot compress the answer or remove conditions to fit the interface.
4. An independent final review sees the exact task and shuffled choices, with
   the key, solution/support, and proposed feedback hidden. The application
   requires its selected answer to equal the frozen solver answer and validates
   the complete returned feedback. No production verification stamp is emitted.

Existing limits apply to complete fields: 320 stem characters, 140 per choice,
420 for the main explanation, and 280 per choice explanation. Text is retained
exactly, without repair, clipping, or whitespace changes. Distinctness checks
cannot establish semantic uniqueness; model verdicts cannot establish truth.

## Evidence and assessment

Before dispatch, freeze source revision, all relevant module hashes, prompts,
fixture, dependencies, settings, stage order, and budgets. Persist complete actual
requests before each call. Retain final response text, stop reason, usage and
reasoning-block count, without storing private reasoning text or credentials.
Record the exact task, solution, constructed choices and hashes between stages.
Replay must reconstruct requests and results from raw saved outputs and reject
changed joins, settings, or content.

An independent assessor first receives rendered stems and choices with goals and
sources, without proposed keys, feedback, or model difficulty. Freeze answers,
completeness, semantic uniqueness, distractor plausibility, objective fit and
difficulty before joining the solution and feedback. Then assess the raw solver
support, proposed teaching text, and all final main/choice explanations. Report
each defect and any disagreement between assessors. These are assistant
assessments, not educator consensus or empirical learning outcomes.

Full feasibility requires all four candidates to have a uniquely warranted key,
three plausible wrong alternatives, complete supported feedback and the relevant
goal fit; each fresh item must independently reach difficulty 3. Show component
counts and every rejection out of four. A changed all-pairs choice set with a
valid negative key is a new complete MCQ, not retroactive rejection of the old
positive-key fixture. A rejection due to formatting or excessive length is not
evidence that the system understood its factual error.

This is an unpaired feasibility trial. It cannot establish a causal accuracy gain,
production error rate, arbitrary-goal coverage, useful adaptation over time, or
deployment readiness. A partial success remains evidence about its specific
components. No old experiment criteria or results are rewritten.
