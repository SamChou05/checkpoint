# Candidate: require contextual pair judgments in the existing solver

The smallest defensible change is to extend the complete-choice solver's result,
not add another model call. The current four correctness judgments remain. Six
new rows cover every unordered pair of exact choices, with `equivalent`,
`distinct`, or `uncertain` and a short reason. Application code validates complete
pair coverage, then vetoes an equivalent or uncertain pair independently of
whether exactly one answer is correct. A reviewer cannot waive that veto.

This directly addresses the demonstrated failure: a model can recognize that
`Three` and `The number three` mean the same thing yet still approve a quiz because
only `Two` is correct. A declared equivalent pair would now deterministically
exclude that item. The model can still misjudge equivalence, so that narrower
invariant must be evaluated rather than described as a guarantee of semantics.

The [runner](pair_solver_eval.py) and [frozen plan](plan.json) are experimental
only. They do not change `native_output_contracts.py`, the production solver,
provider routing, or question banks. The plan contains exact provider-native
schemas and requests, source hashes, gold pair relations and input order.

## Fixed comparison

- Four provider calls maximum: two batches of five questions per arm. Arm order
  is baseline then candidate in batch 1, candidate then baseline in batch 2.
- Ten new self-contained controls, five with equivalent wrong distractors and
  five with genuinely distinct choices; all ten have exactly one correct key.
  None uses the previous eight reviewer-control stems.
- Duplicate families: fraction/decimal value, converted duration, paraphrased
  action, logically equivalent negation, and commutative algebraic expressions.
- Valid families: written unit notation, inequality boundaries, fraction versus
  decimal notation, meaningful internal spaces, and quantifier boundaries.
  The notation/value pairs deliberately reuse exact choices under different
  stems to expose context-insensitive normalization.
- Sonnet 4.6, disabled thinking, temperature 0.2, 6,000 output tokens, 75-second
  read timeout and one SDK attempt. No retries, repair, or additional calls.
- Stop on any transport, native syntax/schema, exact-content correlation,
  coverage, or bounded-reason failure. Preserve all raw results and mark remaining
  jobs unattempted. Do not remove failed cases from denominators.

The baseline uses the actual current solver schema and unchanged parser/gate.
The candidate uses a local schema extension in the native `outputConfig`, retains
the original correctness instructions, and explicitly separates meaning from
shared truth/falsity. Its local validator requires all six distinct unordered
pairs with exact offered strings. It projects the unchanged four correctness
rows into the real existing complete-solver validator and combines its veto
with the pair veto. There is no model-supplied overall validity flag to override.

## Frozen criteria and limitations

Report each layer separately: four completed/format-valid responses; ten correct
unique keys per arm; 60 candidate pair rows; five equivalent and 55 distinct
relations; five defective items excluded and all five valid controls retained;
uncertain declarations; and per-call latency, usage and truncation. Missing or
malformed rows are operational failures, not successful semantic rejections.

All figures are prospective exact-control targets, not statistical accuracy
thresholds. There is one observation per item per arm, with no repeated stability
measurement and no fresh author output. Passing would establish bounded
feasibility and justify an integration experiment, not arbitrary-subject
correctness or a production guarantee.

## Production budget if qualified

The candidate replaces one existing solver call. A full pass remains author →
solver → reviewer: three calls, allowing at most two full passes under the
existing six-call budget. Five items add 30 pair records, so output length and
latency could become the limiting cost even without another stage. This trial
keeps the current token and timeout ceilings unchanged to expose that risk.

Any later implementation would need a versioned solver schema/policy, exact
coverage validation, separate quality reasons for equivalence and uncertainty,
and preservation of all current correctness/identity gates. No automatic text
rewriting, loss of code symbols, substring inference, fourth stage, or increase
to the six-call budget is proposed.
