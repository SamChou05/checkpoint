# Deterministic numerical option construction

This pure module is used by the optional `constructed_quantitative` author
route. The module itself does not select a runtime route, call a provider, create
verification metadata, or change existing author contracts. The route requires
native transport and `authored_solution`; defaults remain unchanged. `construct_quantitative_spec(spec_without_choices)` accepts a complete
nested compiler task without options and returns a separate full compiler spec
with four exact numerical choices. Rejection raises
`QuantitativeConstructionError`, with a stable `code` describing the failure.

The task must be an existing `exact_value` expression or a `scalar_condition`
with an explicit `integer_interval` domain. Unit, expression, number, domain and
rendered-text limits are the existing compiler's limits. Offered-set domains are
unsupported because construction must start from a task whose domain does not
depend on the generated options. Inputs cannot contain a proposed key, choice
list, learner prose, approval or provenance.

For exact arithmetic, the constructor evaluates the correct result with exact
fractions. Its finite wrong-value pool makes **one mistaken step** in the expression.
For fractional operands it first tries procedure errors: combining numerators and
denominators separately, changing denominators without scaling numerators,
misapplying reciprocal multiplication, or omitting a numerator or denominator.
The remaining bounded mechanisms include operator substitutions, omitted steps
and reversed operands. Whole-number operations retain their existing pool.
A change inside a nested expression is evaluated through unchanged ancestors.
The 31-node/depth-six compiler
limit permits at most 15 binary operations and 90 candidates before deduplication.
Undefined or oversized hypothetical calculations, equivalent values, and the
actual result are discarded. There is no generic numerical padding. Literal-only
tasks and degenerate arithmetic often fail for insufficient distractors.

These priorities address the old constructor's tendency to select three root
operator swaps before any fraction-specific or inner-step mistake. The error
families are informed by [IES Recommendation 3](https://ies.ed.gov/ncee/wwc/docs/practiceguide/fractions_pg_093010.pdf),
pages 31–32. The exact ordering and additional omission rules are engineering
hypotheses, not measured probabilities of learner errors. Final review still
judges plausibility; a rejected question is never rescued by this heuristic.

For scalar conditions, every integer in the stated domain is evaluated first,
including points that will not be offered. Undefined arithmetic anywhere rejects
the task. `any_satisfying` chooses one feasible number and three actually false
domain numbers. The deterministic first-feasible convention does not add a
minimum requirement to the question. A task may have many unoffered solutions.
An explicitly requested minimum/maximum uses the actual whole-domain extremum
and three other domain values, preferring nearest boundary competitors. Other
satisfying numbers are wrong only because this task explicitly requests the
extremum. No monotonicity, missing condition, out-of-domain premise, or hidden
selection rule is inferred.

All four numbers must satisfy the compiler's offered-number representation bounds
(24 characters, numerator/denominator components at most 10^9), not just its
96-bit intermediate arithmetic limit. Fractions establish numerical uniqueness.
Task and option bytes determine the final option order uniformly for every
option; callers cannot nominate a preferred key slot. The app may still shuffle.

The completed specification goes through `compile_question` before being returned.
That checks the exact answer count and renders the existing five learner fields,
including worked main teaching and all four choice explanations. No generated
trace is truncated to fit: a proof exceeding 420 characters fails closed. The
constructor supplies no invented account of how a particular learner made an
error. Existing compiler feedback compares each option with the actual task.

This guarantees answer inclusion, unique task-relative correctness and distinct
numerical values for admitted tasks in this closed subset. Transparent mistakes
and boundary competitors are a bounded pedagogical heuristic, not proof of
appropriate difficulty or convincing distractors for every curriculum. A final
reviewer still assesses those properties. Insufficient pools, malformed graphs in
the separate transport adapter, unsuitable topics and overly long proofs must
remain visible yield failures; none may be silently repaired or padded.

Tests use independent syntax-mutation, fraction-procedure and evaluation oracles, signed and nested
fractions, all six scalar relations and three selections, exhaustive small-domain
checks, seven historically observed missing-answer task shapes, exact type and
size attacks, undefined unoffered domain values, and deterministic deep-copy
behavior. Historical specifications and captures remain unchanged. Integration
must retain server-owned provenance and final recompilation; this module alone
does not authorize release or establish full-worker quality.
