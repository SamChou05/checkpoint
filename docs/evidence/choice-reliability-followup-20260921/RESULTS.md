# Pairwise solver trial: useful detection, failed valid-item retention criterion

The stronger check caught all five selected duplicate-choice defects that the
existing solver admitted. It also rejected one of five predeclared-valid items.
The frozen acceptance criteria therefore failed; **this candidate is not promoted
to production**. No additional calls, retries, repairs, or relabeling followed.

Unlike the earlier reviewer wording experiment, this candidate requires six
explicit pair judgments in the existing solver response. Code computes the veto
from those judgments. A recognized duplicate can no longer be waived merely
because the model found exactly one correct answer. The remaining failure is in
the model's contextual equivalence judgment, rather than absent enforcement.

## Complete denominators

The [final plan](plan.json) froze ten new controls, five duplicate and five
distinct, all with unique keys. Each arm saw two batches of five, for four actual
provider calls. Both candidate calls used a real native `outputConfig` schema
named `complete_choice_solver_v2`; no production registry was changed.

| Observed outcome | Existing solver | Pairwise candidate |
| --- | ---: | ---: |
| Calls completed with valid schema and exact coverage | 2/2 | 2/2 |
| Unique authored key correctly established | 10/10 | 10/10 |
| Duplicate controls excluded by the solver gate | 0/5 | 5/5 |
| Predeclared-valid controls retained | 5/5 | 4/5 |
| Expected equivalent pairs correctly classified | Not assessed | 5/5 |
| Expected distinct pairs correctly classified | Not assessed | 52/55 |
| Uncertain pair judgments | Not assessed | 0/60 |

All 60 required candidate pairs were present exactly once with exact offered
choice text. No output was truncated or rejected for syntax, schema, coverage,
identity, or reason length. The baseline is not supposed to infer diversity from
its correctness declarations; these results expose the capability difference
rather than a counting bug.

The duplicate cases cover equal fraction/decimal values, converted durations,
paraphrased actions, equivalent negation, and commutative algebraic expressions.
The candidate retained the valid fraction-notation, internal-space, inequality,
and quantifier controls.

## The retained failure and its interpretation

The predeclared-valid failure asks: “Which exact written choice uses 'seconds' as
its unit word?” Choices are `2 minutes`, `60 seconds`, `1 minute`, and `3 minutes`.
The unique key remains correct. The candidate labels the three minute-valued
wrong choices equivalent, producing three pair errors and one item veto. Its
reason says both use minutes and neither matches the criterion.

Under the frozen rubric, the complete written choices propose different literal
durations and must not be equated simply because they fail the same condition.
This is the distinction the candidate prompt explicitly requested. There is
also a legitimate evaluation concern: varying the number while keeping the wrong
unit may provide weak distractors when the question tests only the unit word.
That pedagogical concern could motivate a different future control or rubric.
It does not authorize changing this trial's predeclared gold after seeing its
output. The result remains **4/5 retention and a failed frozen criterion**.

## Cost and call budget

| Actual usage across two calls per arm | Existing solver | Pairwise candidate |
| --- | ---: | ---: |
| Input tokens | 2,797 | 4,039 |
| Output tokens | 1,517 | 4,514 |
| Elapsed call time, total | 15.790 seconds | 42.480 seconds |

The four calls used 6,836 input and 6,031 output tokens in total. Both five-item
candidate batches ended normally under the unchanged 6,000-token and 75-second
read limits. These selected calls show increased output and latency; they are
not a population cost or performance estimate.

The proposed integration would still replace the existing solver call. A full
pass remains author → solver → reviewer, three calls, with at most two full
passes under six calls. No extra reviewer, author repair loop, or expanded call
budget was tested or proposed.

## Exact evidence and archived implementation

- [Capture](capture.json): every original provider response, usage, completion
  reason, latency and local validator result, including the unfavorable item.
- [Summary](summary.json): per-arm denominators and all three pair mismatches.
- [Runner](pair_solver_eval.py): native requests, strict schema/correlation
  validation, exact pair coverage, actual baseline admission and candidate veto.
- [Preflight plan](preflight-plan.json): undispatched initial preparation before
  aligning the candidate schema name and runtime transport suffix. It is not the
  executed plan and contains no provider outcomes.
- [Archived candidate](candidate_complete_question_solution.py): the temporary
  optional solver implementation copied byte-for-byte after the run. Its bytes
  must match the `complete_question_solution.py` hash in the executed plan.
- [Archived API replay](candidate-api-replay.json): both actual candidate
  responses passed the archived validator; all ten eligibility decisions match
  the original local scorer, including the unfavorable veto. The exact prompt
  match was also checked. This replay made no provider calls.

The production module is restored to HEAD after archival because the candidate
failed qualification. Replay of the candidate API must explicitly import the
archived module; do not interpret restored production code as the code used during
the trial. The exact tested prompt includes the normal native transport suffix
and matches the temporary candidate's prompt bytes. Both baseline requests were
checked unchanged against the preflight requests.

The evidence supports further work on contextual equivalence inside the existing
solver. It does not establish a production-ready fix, broad correctness, or
stability across repeated runs. All ten controls were selected and self-contained,
with one observation per item per arm; no fresh author generation was included.

The archived candidate's ten tests pass, including malformed pair coverage and
veto enforcement. All Python files in this evidence directory pass Ruff, and
`git diff --check` passes. The archive SHA-256 is
`9473291262cdf0aee9068a93138c1487e80252cbf9efbdce839840dc68b56d87`, matching the
frozen source hash; neither the executed plan nor capture changed after dispatch.
