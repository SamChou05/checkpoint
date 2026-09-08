# Auditing the exact teaching item

Prospective protocol, September 8, 2026 UTC. This candidate changes what the
final call is allowed to do: it audits a complete question and its five existing
explanations, and cannot write replacement learner content. It is an evaluation
prototype, not a production change or another call added to the live pipeline.

The previous goal turn made progress by preserving and assessing the completed
[solution-owned construction trial](QUESTION_SOLUTION_CONSTRUCTION_RESULTS.md).
Its solver supplied the same wrong all-pairs answer, and subsequent feedback
invented or strengthened unsupported claims. That evidence rules out treating
an unchanged solver key as a sufficient correctness mechanism.

## Why this boundary

The production reviewer currently selects an answer and writes new main and
choice explanations in one response. Code checks their structure and lengths,
but no later step checks those newly written factual claims. The
[four-domain audit](QUESTION_FOUR_DOMAIN_EXPERIMENT.md) and
[full-pipeline audit](QUESTION_FULL_PIPELINE_EXPERIMENT.md) include concrete
errors introduced in this teaching feedback despite a supported selected key.

The proposed eventual three-call arrangement is complete-item authoring,
independent solving with existing application vetoes, and an audit of the frozen
complete item. Authoring all five explanations before the final audit moves
that text inside the checked boundary. It does not establish that the auditor
understands every claim. Production sanitization currently drops authored choice
feedback and clips the main explanation, so integration would also require
exact-content preservation through that path.

This is different from the earlier [claim audit](QUESTION_CHOICE_AUDIT_EXPERIMENT.md),
which assessed choices using newly generated justifications. Here the audited
explanations are exactly the proposed learner text. Research such as
[MCQG-SRefine](https://arxiv.org/abs/2410.13191) studies critique and correction
with expert assessment for medical question generation. That motivates assessing
question quality and difficulty empirically; its specialized setting and results
do not qualify this general Checkpoint contract or its model.

## Immutable acceptance contract

The [pure contract](../backend/bedrock-question-service/evals/question_immutable_review.py)
copies the complete stem, ordered choices, key, main explanation, exact-choice
explanations and learning metadata. It rejects invalid or oversized fields
without clipping, rewriting or inventing missing explanations. Limits are 320
characters for the stem, 140 per choice, 420 for the main explanation and 280
per choice explanation. No verification metadata is accepted as authority or
emitted as a production stamp.

The auditor sees the complete teaching item with choices rotated deterministically
from the exact stem. The explicit key, author difficulty, earlier questions and
solver output are omitted. **The explanations reveal the intended answer, so
this final audit is not answer-blind.** The existing independent solver would
remain a separate step in an eventual complete pipeline.

The response contains an overall validity judgment, an exact selected choice,
an assessed difficulty, five supported/unsupported/uncertain feedback judgments
and bounded issues. Every choice judgment binds by exact choice text. Any
unsupported or uncertain field, reported issue, wrong selected key, invalid
envelope or inadequate difficulty prevents acceptance. The auditor cannot
return a replacement explanation or revise the task. An accepted result keeps
all original teaching text and choice order; only assessed difficulty changes.
These code checks enforce reported judgments, not their semantic truth.

## Fixed six-call diagnostic

The [fixture](../backend/bedrock-question-service/evals/fixtures/question_immutable_review.json)
contains two feedback-only pairs plus two boundary controls. The
music pair uses a historical complete display and its erroneous returned
feedback, followed by a separately identified feedback correction. The photography
pair uses an explicitly identified controlled variant derived from a historical
error, with the same task and choices in its bad/sound feedback variants. The
all-pairs controls include an internally consistent wrong answer/explanation
and a separate well-posed negative-answer question; those two are not a
feedback-only pair. Exact origins and transformations stay in fixture provenance.

The six cases run in their frozen order, once each, with no source labels,
expected verdicts, pair IDs or provenance in the provider request. Both members
of each feedback pair receive identical context. Reference summaries are
manually inspected evidence, not automatic retrieval or guaranteed entailment.
The minimum difficulty is **1 solely to isolate factual feedback review**.
Retaining a sound easy control does not qualify level-3 generation or adaptation.

Freeze the exact fixture, source commit and module hashes, model settings,
dependencies and all six requests before dispatch. Use
`us.anthropic.claude-opus-4-6-v1`, adaptive thinking/high effort, a 16,000-token
output allowance, one SDK attempt, a three-second connection timeout and a
100-second read timeout. Caps are six calls total, one per case, 32,000 input-text
UTF-8 bytes per call and 192,000 total. These are not a monetary cap or a hard
whole-trial deadline.

The [runner](../backend/bedrock-question-service/evals/checkpoint_immutable_review_eval.py)
persists each exact request before dispatch and saves final response text,
usage, stop reason and reasoning-block count without private reasoning. A
provider, malformed-review, persistence or binding failure stops later calls.
No retries, repairs, replacements, resume, native artifact execution, author or
solver calls, production writes, model promotion or deployment belong to this
trial. A semantic rejection is an observed verdict, not an operational failure.

Pre-dispatch verification: 24 focused contract/runner tests pass, including
reviewer replacement attempts, exact choice joins, declared feedback vetoes,
normal completion, malformed output, usage preservation, persistence failures,
stopped-prefix replay, changed captures and no-resume behavior. The complete
686-test backend suite passes with one existing optional-runtime skip. Ruff and
diff checks pass. Independent code review cleared the dispatch/immutability
boundary after the three accounting fixes were tested. The six fixture items
fit every complete-field limit; both feedback pairs have identical task, choices,
key and context. Primary Canon, Yamaha and music-theory sources were inspected
before freeze, and the read-only AWS identity check succeeds. These are
preparation checks, not fresh semantic results.

The [exact frozen plan](evidence/immutable-review-plan-20260908.json) binds source
`976060f3068084deb87c24f3f545697ed142a3b7`, Python 3.12.11 and boto3/botocore
1.43.89. Its canonical SHA-256 is
`d65404c2f43007828de336095de74ae3bad0ca1e5cef97473cefb8da17d76b05`;
the archived file SHA-256 is
`4a0a378b9bf0a6629d79a9f0026cbcc4f035be35ac7b945f77c6770c859f349d`.
The requests use 5,522, 5,720, 5,394, 5,554, 4,870 and 5,135 input-text UTF-8
bytes respectively, totaling 32,195. Execution must use the isolated checkout
of this exact revision. Preparation dispatched no provider calls.

## Decision and limits

Report every verdict against its frozen expected outcome. For each bad-feedback
case, inspect whether the auditor identifies the actual defective field and
claim; an incidental format/difficulty rejection is not detection credit.
Require retention of the sound counterpart with exact original teaching text,
and separately report performance on the wrong-key and negative-answer controls.
Inspect issue text for newly invented objections and record uncertainty and
disagreements. A complete fixed-content feasibility pass requires all six
expected verdicts with warranted reasons, not merely six schema-valid responses.

Even a pass only qualifies a next full-authoring test. This run cannot prove that
an author can reliably supply all five explanations within limits, fill banks,
reach the learner's requested difficulty, meet production latency, or improve
arbitrary-goal learning. It does not close the existing answer-only solver
contradiction path or prove independence of shared model knowledge. Existing
release requirements and historical failed experiments remain unchanged.
