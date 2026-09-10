# Prospective solver judgment/reason ordering diagnostic

Experiment: `solver-judgment-reason-order-v1`. This is preparation for a fixed
32-call diagnostic, with no inference result yet. At preparation time the sole
known live-access blocker is the expired AWS session. Local verification and
independent subject assessment must finish before the source/plan freeze and
one authorized execution; renewing access does not itself establish readiness.

## Question and intervention

The [stage attribution](QUESTION_STAGE_ATTRIBUTION_RESULTS.md) found four solver
judgment labels that conflict with their written reasons. This does not establish
that output order caused the conflicts. Test whether writing each reason before
its judgment improves both factual assessment and internal consistency while
retaining rejection of defective questions.

Both arms use the current complete-choice solver prompt and native output
contract. `judgment_first` retains the existing row order: choice, judgment,
reason. `reason_first` changes only that row's order in the prompt's JSON example
and the equivalent schema's `properties` to choice, reason, judgment. Every
property remains required; the required-member array, field constraints, question
text, offered-choice order, sources, model and other settings stay the same.
This is a combined prompt-example/schema-order intervention; it does not isolate
the contribution of either component or reveal the model's internal reasoning.

Anthropic documents that structured outputs retain schema property order, with
required properties before optional ones. All three fields here are required.
Record the actual emitted row order rather than presuming the manipulation took
effect. Schema order does not establish factual correctness.
[Official property-ordering documentation](https://platform.claude.com/docs/en/build-with-claude/structured-outputs#property-ordering)
(checked September 10, 2026).

## Fixed subjects and provenance

The [fixture](../backend/bedrock-question-service/evals/fixtures/question_solver_order.json)
contains eight batches, 22 distinct indexed items. Only `subject` enters the
provider input, rebuilt through current `build_solver_prompt` and checked for
exact equality. Keys, expected judgments, rationales and provenance remain local.
Historical batches preserve the entire original solver subject and choice order;
no candidate is extracted into a smaller replacement batch.

| Batch | Items | Selection |
| --- | ---: | --- |
| Historical solver call 1 | 5 | Two-step spreadsheet-copy label/reason conflict and all companions. |
| Historical solver call 4 | 2 | Unsupported third operand and multiple-correct-average companion. |
| Historical solver call 9 | 5 | Spreadsheet-variance label/reason conflict and all companions. |
| Historical solver call 12 | 1 | Original-map-distance label/reason conflict. |
| Historical solver call 27 | 3 | Plant-to-snail ratio label/reason conflict and all companions. |
| Fresh English agreement | 2 | One uniquely correct item and one with two correct choices. |
| Fresh fictional badge rules | 2 | One valid negative answer and one with no correct choice. |
| Fresh Python list operations | 2 | One uniquely correct output and one with the correct output omitted. |

Historical provenance binds the complete [delivery capture](evidence/delivery-feedback-20260909/capture.json),
actual solver-call indexes, source-bearing [trace](evidence/stage-attribution-20260910/trace.json),
raw occurrence identities and frozen assessor records by byte hashes. Expected
per-choice rows follow the exact provider choice order. The fresh subjects were
authored locally for this fixture; their origin path/hash is null and the frozen
fixture binds their literal content. Local Python execution confirms their
printed outputs. These are basic transfer controls, not calibrated advanced
questions or a claim that their broad domains have never been tested before.

Two historical companions remain materially ambiguous: call 1/index 3 asks about
numeric results without supplying cell values; call 27/index 0 leaves the shrimp
energy pathway unclear. Their expected choice judgments and expected eligibility
are null, not forced to `uncertain` or binary ground truth. Preserve the separate
conventional-reading caveats for pond transfer efficiency and spreadsheet variance.
Independent key-blind assessment precedes any response and may identify further
scope disagreements; reconcile or retain them explicitly before freezing.

The completed [independent control review](evidence/solver-order-preparation-20260910/control-review.json)
is bound to the [key-blind packet](evidence/solver-order-preparation-20260910/control-packet.json).
It agrees with every expected choice judgment on the 20 scored subjects: 14
uniquely valid, two with multiple answers, and four with no answer. The same two
ambiguous companions remain unscored. The runner checks that the packet, exact
subjects and independent assessments still agree before freezing or execution.
These assistant assessments are prospective controls, not expert ground truth
or new evidence of provider performance.

## Bounds and execution

Use `us.anthropic.claude-sonnet-4-6`, native Converse, disabled thinking, 6,000
output tokens and temperature 0.2. Freeze the current source and boto3/botocore
1.43.91 dependencies. Eight batches × two arms × two repetitions is exactly
32 single-attempt calls. Within each repetition, alternate which arm goes first
by batch; reverse that order in the second repetition. Repeated observations of
the same subjects are not independent subjects.

Each request is at most 32 KiB; the aggregate ceiling is 1 MiB. Reuse the existing
bounded observer: 240-second worker deadline, 75-second read timeout, three-second
connect timeout and one SDK attempt. Preserve exact requests before dispatch,
raw responses, usage and worker cleanup records. An execution claim prevents a
second run of the same frozen plan. No author, reviewer, repair, top-off,
replacement or extra diagnostic call is permitted. Completed schema/adaptation
or correlation failures remain content outcomes and later fixed jobs continue;
provider, unfinished-response, unknown-usage, cleanup, observer or persistence
failure stops subsequent jobs. Unattempted slots remain in the denominator.

## Assessment and interpretation

There are 88 planned item responses: 22 subjects × two arms × two repetitions.
Keep all 88 for availability; only 20 distinct subjects have frozen binary
expectations (80 planned scorable responses). Report historical and fresh items
separately, and show the four original conflict sentinels and extra-operand defect
individually. One subject's repeated responses are paired observations, not an
expanded sample of independent subjects.

Report native format/correlation, exact per-choice judgment agreement, actual
solver-gate eligibility, independently assessed rationale correctness, and
judgment/reason consistency separately. The unchanged `validate_batch` and
`rejection_reason` enforce existing coverage, uncertainty and key-agreement
rules. A consistent but false reason is still an error. A missing or malformed
response is unavailable, not evidence of a correct semantic rejection. Never
repair a declared judgment from its reason or bypass a solver veto.

Favorable evidence would reduce the original conflicts while producing correct
judgments on valid controls and preserving rejection of defective controls,
especially the unsupported third operand. Inspect any regression and do not
trade false acceptance for apparent recovery. This selected solver diagnostic
cannot establish production accuracy, delivered teaching quality, useful
difficulty, learning gains or an automatic production change. A favorable result
would still require a fresh full-workflow qualification.
