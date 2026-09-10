# Exact replay separates draft defects, checker mistakes and format losses

An offline replay now traces every raw author occurrence in the completed
September 9 delivery comparison through the actual batch sanitizer, solver,
reviewer and returned content. All 29 recorded calls, deadline observations,
decisions and seven returns reproduce exactly under the frozen source and SDK.
No new inference, model upgrade, production prompt change or deployment occurred.

The new finding is not that all failures have one cause. Some drafts contain
defective choices or premises; the checker sometimes misses those defects, and
sometimes rejects a sound question despite explaining its answer correctly.
This gives the next experiment a specific interface hypothesis to test.

## A verdict can contradict the reason written immediately after it

Four admitted questions with independently supported author keys were rejected
because of solver labels that contradicted their own reasons. The exact
[records and field order](evidence/stage-attribution-20260910/declared-reason-conflicts.json)
are preserved:

| Question | Solver declaration | Its reason establishes | Actual code outcome |
| --- | --- | --- | --- |
| Copy `=$B$3+C$2` right two columns, then down two rows | Refutes `=$B$3+E$2` | That exact formula is correct. | Zero supported choices; reject. |
| Original 8 cm at 1:25,000 | Supports both 5 km and 2 km | 8 × 25,000 cm is 2 km; 5 km is refuted. | Multiple supported choices; reject. |
| Copy a variance formula across months and down regions | Supports an unanchored formula and the correctly anchored formula | The unanchored formula fails when copied across. | Multiple supported choices; reject. |
| Plants produce 8,000; snails produce 800 | Refutes 10% | 800 / 8,000 is 10%; that choice is supported. | Zero supported choices; reject. |

These four raw responses actually emitted each row in the order `choice`,
`judgment`, `reason`. The application correctly follows its explicit declared
judgments; interpreting arbitrary reason text to overwrite those judgments would
reintroduce a different trust gap. These observations show a label/reason
consistency failure, not proof that changing field order will solve it.

The next focused hypothesis is to place the concise decisive reason before the
final judgment, preserving model settings, exact subjects and all admission
rules. The current native schema serializer uses `sort_keys=True`, so simply
reordering Python dictionary entries would not change the transmitted property
order. Anthropic documents schema property order as relevant to emitted order,
with required fields first. Actual order must still be recorded for the tested
Bedrock requests. [Anthropic structured-output ordering](https://platform.claude.com/docs/en/build-with-claude/structured-outputs#property-ordering)

This comparison has not run. Earlier split-evidence prototypes already placed
reasons before statuses in a different task and still made semantic errors;
there is no basis for treating this as a general cure. A useful trial must retain
valid questions **and** reject defective controls, including the extra-operand
case below. It must measure reason/label consistency separately from factual
support and must not silently repair a contradictory response.

## Draft quality and actual paths

Two new independent assistant assessors each received 31 shuffled raw occurrences
with the original goal, sources, stem and choices. Author keys, explanations,
teaching mode and downstream outcomes were withheld. Both passes were frozen
before joining their answers to authored keys. Each occurrence has one assessor;
these are retrospective assistant judgments on selected subjects, not expert
ground truth or an estimate of production accuracy.

| First-pass assessment relative to authored key | Raw occurrences | Admitted to checking | Returned |
| --- | ---: | ---: | ---: |
| One supported choice, matches author key | 46 | 26 | 7 |
| One supported choice, differs from author key | 2 | 0 | 0 |
| No supported choice | 6 | 2 | 0 |
| Multiple supported choices | 2 | 1 | 0 |
| Material interpretation ambiguity | 6 | 4 | 0 |
| Total | 62 | 33 | 7 |

The seven newly supported returned keys do not supersede the original two-assessor
result: six jointly supported keys and one ecology convention ambiguity. That
disagreement remains recorded in [the original results](QUESTION_DELIVERED_QUALITY_RESULTS.md).
This new pass did not reassess every teaching field, distractor quality or
difficulty. It cannot turn seven returns into seven fully qualified questions.

Concrete paths include:

- A gradebook item offers both `AVERAGE(B2:F2)` and `AVERAGE($B2:$F2)` when only
  filling downward is required. The independent assessment and actual solver
  both find two valid choices. The multiple-choice gate rejects it.
- All four options for a formula to enter in B2 refer back to B2. The independent
  assessment identifies the circular-reference defect; the solver rejects all
  options and the gate blocks it.
- A sales-summary item specifies multiplication of two cells but offers only
  formulas with a third operand, a quarter label. The solver invents a numeric
  quarter factor and declares one option supported. The original reviewer then
  discusses an anchor ambiguity and emits a rejection inside fenced JSON after
  prose. The application excludes it for **invalid JSON**, not a parsed factual
  veto. Later native rechecks already documented false approvals of this same
  subject; their results remain separate from this historical replay.
- Two ecology drafts have a different uniquely supported key in the new
  assessment. Both are excluded for stem length before any solver sees them.
  Their absence from returns is not evidence that a checker found the errors.

For all 33 admissions, the sanitizer preserved stem text, keyed-answer text and
the set of exact choice texts. Eleven choice lists were reordered. One default-mode
authored main explanation was clipped; that question never reached final review.
Thus sanitizer rewriting did not create the admitted stem/key defects in this
capture. Four returned mains were newly written by the reviewer; the other three
were preserved by the authored-teaching contract. Earlier complete-teaching
assessments remain the evidence for their quality.

There are 17 validated per-question solver decisions. Sixteen other candidates
belong to malformed solver batches and have no validated solver decision. Their
batch diagnostics are retained separately, never assigned as individual factual
catches. The complete joins, raw records and counted exclusions are in
[the attribution artifact](evidence/stage-attribution-20260910/attribution.json).

## Current context findings have separate scope

The previously committed goal-text and objective-label fixes restore information
lost before checking. They do not explain every defect above. The current default
reviewer also says sources are only for subject/scope, while the author says to
use substantive sources as evidence; that wording conflict remains unmodified.

Automatic source shortening can retain a general rule and discard its exception.
An [offline probe](evidence/stage-attribution-20260910/source-context-audit.json)
reproduces that with a 30,000-character synthetic document, while correctly
retaining `truncated:true`. The app may already have shortened imported text, and
its persisted source record does not keep the original full text or file handle.
Increasing output tokens cannot recover absent input. The historical run used
short, manually selected summaries already flagged truncated; its backend did
not apply this length-driven omission to them. Their completeness is unproven.

Source-derived knowledge can legitimately be tested from memory. A fictional
rule is not automatically a missing premise merely because it appears only in
study material. An absent case-specific table explicitly referenced by the stem
is a different issue. Any future source-use correction must preserve that
distinction instead of requiring every learned fact to be repeated in the quiz.

## Replay and verification

The [observer](../backend/bedrock-question-service/evals/checkpoint_stage_trace.py)
uses eval-only profiling of exact function code objects. It reads actual
sequential sanitizer events and preserves object identities through solver
filtering, reviewer reindexing and return. It does not sanitize questions
individually, match them by stem, modify prompts or duplicate admission policy.
SDK client creation and network connections are blocked; the previous profile
function is restored even on failure. Changed source bytes, mixed cached modules
and changed replay requests/results are refused.

The frozen source is `6768a5a78bf3dfa4a322ce32760491d38ea08141`, with Python
3.12.11 and boto3/botocore 1.43.89. This is deliberately separate from the current
implementation checkout. All 33 bound source hashes match. The final trace
reproduces 13 author batches, 62 raw occurrences, 33 sanitizer admissions,
29 calls and seven returns.

Ten new observer regressions and the full 1,121-test backend suite passed. Tests
cover batch deduplication and surplus, dense indexes, author repair, malformed
cohorts, transport exceptions, undispatched top-offs, profile restoration and
source/capture tampering. Independent review rebuilt the attribution artifact
exactly and found no actionable issue. No fresh question-quality measurement,
deployed behavior or learning gain is claimed. The broader correctness goal
remains incomplete.
