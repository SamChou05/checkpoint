# Authored worked explanations

## Status and purpose

Implemented behind the server environment setting `QUESTION_FEEDBACK_CONTRACT=authored_solution`; the default remains `reviewer_written`. A subsequent [fresh live trial](QUESTION_AUTHORED_SOLUTION_FRESH_RESULTS.md) returned two of six authored candidates and retained a misleading teaching claim. It did not qualify this path for default use, and no deployment occurred. The [reasoning comparison](QUESTION_REASONING_RECHECK.md) showed that the final reviewer could introduce incorrect teaching while approving correct keys. This change removes that unchecked content-writing step, without assuming that author text or model agreement is necessarily true.

## Runtime contract

1. The author creates the question, four choices, key and a complete main worked explanation. It must apply the stated facts and explain the decisive reasoning. The existing author prompt instructs a 320-character main limit; runtime validation permits up to 420 characters. This mode does not widen either bound. Choice explanations are not requested in this construction mode.
2. Sanitization rejects malformed or oversized main explanations instead of cleaning or clipping them. A model-supplied nonempty or malformed `choiceExplanations` value is a rejection, never permission to discard existing teaching. The mixed quantitative route separately admits only exact compiler-owned feedback bound by a revalidated private sidecar. Normal stem and choice sanitization still occurs before the candidate is frozen.
3. For ordinary prose, the existing complete-choice solver receives the exact candidate stem and choices without the author key, explanation or difficulty. Zero or multiple supported choices, uncertainty and exact key disagreement block final review. These are enforced declarations, not proof that each model judgment is true.
4. The final audit receives the frozen candidate and main explanation, plus goal, skill and supplied source context. It receives neither the explicit author key/difficulty nor solver judgments/reasons. Historical answers and teaching are omitted. The explanation may reveal the intended key, so this audit is not answer-blind.
5. A strict response contains only an indexed verdict, exact answer, assessed difficulty, explanation support and issues. Unsupported or uncertain teaching, any issue, disagreement, malformed output or insufficient difficulty blocks acceptance. Replacement text and verification metadata are forbidden response fields.
6. Acceptance preserves ordinary prose main text exactly and returns an empty choice-feedback map. Legacy transport assigns policy revision 3; native transport assigns revision 7 only after the complete pair/count gate and immutable-main audit both pass. The audit cannot write learner-facing content. The normal three-call generation path, deadline, quota and provider-call limits remain in force.

The iOS client already displays the main when choice-specific feedback is absent, and JSON bank storage retains the complete question. No storage migration or UI change is required for this opt-in shape.

## Provenance and limits

Revisions 3 and 7 identify the legacy and native forms of this contract; neither certifies semantic correctness. The default generation/request policy remains 4 and the current client floor remains 2. Explicit request/claim minimums through 8 are supported. Revisions are freshness thresholds, not cumulative capabilities: a minimum-6 request may return a revision-7 authored question, which does not mean it was produced by the revision-6 quantitative compiler. Existing eligible inventory and claim replays remain available, so enabling the environment flag alone does not guarantee that every delivered bank question used this path. Old content is never relabeled.

The application can enforce unchanged teaching and blocking review outcomes. It cannot establish that a model's `supported` label accurately describes its reasoning. Tests deliberately preserve an example where two falsely supportive model responses still admit incorrect teaching. Neither this path nor more output tokens replaces subject evidence or independent assessment.

The fresh prospective trial across non-math goals did not meet its criterion. Further qualification must inspect every raw candidate as well as returned content, measure usable yield and difficulty, and retain malformed output and rejected questions in the denominator. Passing a small trial would establish feasibility, not arbitrary-subject accuracy or full-bank release readiness.

## Native pair/count integration — September 22, 2026

With both `BEDROCK_STRUCTURED_OUTPUT_MODE=native` and
`QUESTION_FEEDBACK_CONTRACT=authored_solution`, the existing native author is
followed by `complete_choice_solver_v5_n{count}` and the new
`authored_solution_reviewer_v2_n{count}` audit. Trusted counts follow sanitized
solver inputs and dense solver survivors; the provider cannot supply indexes.
The audit uses shared schema references and preserves the original verdict,
exact-answer, difficulty, explanation-support and issues fields. It cannot emit
replacement teaching or provenance. All four choice judgments and six pair
relations must pass before the audit; equivalent or uncertain pairs veto the item.

The native audit receives each survivor's assigned topic/skill/objective, goal,
source context and the last 30 keyless history descriptors. Its instructions
require assignment fit and reject cosmetic repeats while allowing new
applications of the same objective. It receives neither explicit answer keys,
author difficulty nor solver judgments. Main text passes unchanged through
sanitization and admission; malformed, oversized or shuffle-position-dependent
teaching is rejected rather than repaired. The existing reviewer position guard
is shared with this route, including numeric-value and source-literal exceptions.

The default feedback mode, legacy schemas/prompts, reviewer-written contracts,
three-stage path and six-call budget remain unchanged. The client already uses
the explicit key for highlighting and falls back to the main explanation when
choice feedback is empty. This reduces individually generated wrong-choice
teaching; it does not make the main explanation or model verdicts infallible.
The native combination has offline regression coverage only and remains opt-in
and unqualified for live rollout. The failed September 8 live trial is unchanged.

Verification: all **1,235 backend tests** pass, including eleven new native
authored-pair groups covering every pair veto, dense survivor identities, scoped
keyless history, unchanged main bytes, forbidden replacement fields, six-call
accounting and all 40 count schemas. Explicit minimum-7 claim/replay and
minimum-6 acceptance of revision 7 preserve freshness semantics. Independent
review checked 32 survivor masks and confirmed the 91 preexisting
config/metadata/prompt families are byte-identical. Ruff and whitespace checks
pass. A noncontainer SAM build passes; all 26 service modules, requirements and
SDK verifier match source in all three artifacts. Artifact-isolated Python 3.12
`-I -S` validates 131 request shapes per artifact (**393 offline checks**) using
the packaged boto3/botocore 1.43.91. No model calls or deployment were made.

## Mixed quantitative compatibility

The native `mixed_quantitative` author can also use this immutable-main audit.
The current immutable-main audit uses the count-bound v3 issue-flag contract.
Ordinary rows retain the existing v5 solver, preserve exact main text, and return
empty choice feedback with policy 7. Only exact privately revalidated compiled
rows skip that model correctness/pair stage: code already proves the complete
bounded mathematical task, unique key and distinct values. All surviving rows
still enter the same final audit for key agreement, teaching support, assigned
scope, difficulty, novelty and distractor quality. Compiled rows retain all five
exact compiler-owned learner fields and receive policy 8 after that audit.
Reviewer-written mode keeps the historical solver and compiled policy 6. No
new schema, stage, model/default or policy floor is introduced. Nonempty feedback is
accepted only through the server-created `CompiledCandidate`, freshly recompiled
before freezing and release. The audit sees main text only; private provenance,
explicit keys, difficulty labels, solver judgments and choice feedback stay hidden.

Sanitization and every subsequent filter retain questions and private sidecars
together. Provider-supplied feedback or approval flags cannot create that trust.
The final auditor still vetoes wrong keys, unsupported/uncertain main teaching,
issues and inadequate difficulty for both variants. Partial top-ups use the same
six-call budget, preserve already verified work and propagate durable refusals.
This combination remains opt-in and has not received live qualification.

Historical compatibility verification before the compiler-proof simplification: **1,247 backend tests** pass, including twelve new
groups for interleaved sanitizer/freeze/solver/reviewer drops, all five compiler
field mutations, forged sidecars and provider feedback, exact deep copies, every
pair veto, main-audit vetoes, partial top-ups, deadline exhaustion and durable
reservation refusal. Independent review checked sixteen additional survivor
masks and swapped provenance. Schemas, compiler, policy constants, templates and
defaults are unchanged from the native authored-main milestone. Ruff and staged
whitespace/secret checks pass. SAM builds all three functions; all 26 modules
plus requirements and SDK verifier match source in each artifact, and the same
**393 artifact-isolated request checks** pass. No inference or deployment ran.

## Compiler-proof call reduction

With native mixed authorship and immutable main auditing, all-compiled passes use
an author call and a final audit call. Mixed passes add the unchanged prose-only
solver call. The final audit count includes compiler-proved rows and surviving
prose; its identities never come from matching model text. Private sidecars are
revalidated before any solver exclusion and again before release, so provider
feedback/flags cannot mint the new revision 8. The audit cannot replace teaching.
The six-call worker budget and three-call pre-author minimum remain unchanged:
before authoring, the service cannot know whether prose will require all stages.
Provider failures and durable quota refusal retain their existing behavior.
This is an opt-in deterministic runtime reduction, not live worker qualification.

Verification: **1,285 backend tests** pass, including **59 focused tests** across
compiler-proof verification, the actual mixed route, policy claim/replay and the
smoke selector. New coverage checks all 24 compiled choice orders, dense
prose/original/audit associations, keyless scoped history, private-sidecar and
five-field tampering, final vetoes, provider-error propagation and conservative
partial-pass budgeting. Independent review additionally ran eight mixed survivor
masks and compared pure compiled two-call policy 8 with unchanged three-call
reviewer-written policy 6. Ruff, compilation, whitespace and secret checks pass.
SAM validation/build passes; all 26 runtime modules, requirements and verifier
match all three artifacts. Each artifact passes 171 isolated SDK request shapes
(**513 offline checks**). No model call or deployment was made for this change.

## Historical verification — September 8, 2026

- Twelve pure contract tests and eight integration tests cover exact preservation, malformed and replacement feedback, answer/issue/support vetoes, solver prerequisites, configuration ownership, index reconciliation and policy provenance.
- The full backend suite passed **884 tests** with no skips on September 8 using the live-review Python environment; Ruff and `git diff --check` passed.
- Independent read-only review found no material integration blocker and confirmed that the default author, solver and reviewer prompts retain their archived bytes.
