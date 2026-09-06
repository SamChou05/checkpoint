# Reported solver limitations cannot be waived by review

Commit `26feed4` blocks a `resolved` solver report whenever its normalized `limitations` string is nonempty. Previously, a solver could declare `resolved`, explain that the requested result was impossible in `limitations`, supply no required assumptions, and still have an approving reviewer pass the author's positive key. The new check runs before reviewer dispatch and records `solver_unresolved_limitations`.

The solver prompt now separates unresolved obstacles from conditions already justified by the question or sources. Supported conditions remain in the answer. Missing conditions must not be moved there to obtain acceptance. Whitespace-only limitations normalize to empty; text such as `none` is nonempty and blocks review. Canonical `no_solution`, `underdetermined`, and `inconsistent_premises` answers retain explanatory limitations and their existing answer contract. No provider call was added, model promoted, or deployment performed.

Evaluation treats the new outcome as abstention, not evidence of detecting a factual error. This is deliberately conservative: a harmless scope note in the wrong field also blocks an otherwise sound question.

## Exact scope and remaining failures

The [six-case offline replay](evidence/solver-limitations-replay-20260906.json) compares verifier `eb55433` with the source committed in `26feed4`, using frozen synthetic solver records and an intentionally approving reviewer. It preserves source hashes, exact cases, observed acceptance, reviewer dispatch counts, and runner source.

| Synthetic record | Before | After |
| --- | --- | --- |
| Impossible answer reported in nonempty limitations, despite `resolved` | Accepted | Blocked before review |
| Same impossibility only in answer, limitations empty | Accepted | Still accepted |
| Required but unstated speed only in answer, limitations empty | Accepted | Still accepted |
| Valid conditional answer with condition supplied in stem | Accepted | Accepted |
| Valid answer with a harmless scope note in limitations | Accepted | Abstained |
| Canonical negative answer with supporting limitations | Accepted | Accepted |

These callbacks prove control flow, not model accuracy. The new gate does not inspect the semantics of arbitrary answer prose. Empty limitations and agreement between models do not establish a correct answer, unique choices, or accurate teaching feedback.

## Impact on existing model responses

The [retrospective audit](evidence/solver-limitations-impact-20260906.json) inventories 16 solution records from eight actual calls in the source-authoring and solver-outcome experiments. It joins exact provider output to archived stems and prior independent assessments, without recounting duplicate archive representations as new calls. The [runner](evidence/solver-limitations-impact-20260906.py) is preserved separately. Root reran the original runner and reproduced the report byte-for-byte before archiving it.

Only one of the 16 records has nonempty limitations. It describes unseen alternatives for a Monstera question. Prior independent review supported that question's best-listed key, while finding a separate error in distractor feedback. The new gate would exclude the record because of its solver contract, not because it independently discovered that feedback error. This is neither a demonstrated clean factual catch nor a clean rejection of fully sound returned content.

The latest invalid all-pairs, RAW, and forms examples have empty limitations and remain unaffected by this field check. Three older records illustrate that limitations can contain decisive objections or useful caveats; they lack the current outcome field and cannot establish a current rejection rate. None of this replay measures behavior under the revised prompt, production inventory yield, or overall correctness.

The code milestone passed 486 backend tests with one existing skip, affected Ruff checks, `git diff --check`, and independent review. Seven new gate tests cover reported impossibility and missing conditions, conservative text handling, valid scoped answers and canonical negatives, diagnostic priority, and mixed-batch associations. Evaluator tests ensure an abstention earns no factual-correctness credit.

Archive SHA256 values:

- Synthetic replay: `74b7816bdc9e51e941edde62a8b0e768b94fb3411c519b55d2325bb531b7f564`
- Historical impact: `1dd94fe83756388aa5ecd923b08ffd233448aafe6a0aea9e5f03d424ed21b6a9`
- Historical runner: `d869f62d139ae54ac8fdc8a3d19742770b0262cc458c59cf7d55a9142c75d96b`
