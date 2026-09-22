# Frozen reviewer-data omission comparison

**Both arms failed. Removing `independentSolutions` is not promoted.** Four calls
completed exactly as planned, with no retries or replacements. All four responses
passed native JSON/schema and index-coverage checks. All 19 positive reviews had
correct exact keys, complete bounded feedback, and difficulty 2–3.

| Measure | With solver records | Without solver records |
| --- | ---: | ---: |
| Valid questions retained | 10/10 | 9/10 |
| Correct keys among retained questions | 10/10 | 9/9 |
| Items with definite feedback errors | 2 | 2 |
| Additional feedback scope uncertainty | 0 | 1 |
| Complete-content passes under frozen uncertainty-fails rule | 8/10 | 6/10 |

The baseline repeated the false statement that 15 L blue and 9 L white form a
1:1 mixture; the actual ratio is 5:3. It also claimed the 17.4% distractor came
from dividing a 12,000 increase by either 12,000 or 92,000; these calculations
give 100% and approximately 13.04%, respectively.

Omitting solver records removed that particular paint sentence but generated a
new faulty explanation: it called the correct 2/3 factor inverted and introduced
an unexplained 3/3 factor before turning the result into 9 L. It also attributed
17.4% to a calculation that its own sentence correctly described as approximately
13%. The valid fuel-efficiency item was rejected: its raw negative row named
32 mpg while its feedback calculated 30 mpg. The native adapter safely discarded
that negative row's unused answer and feedback.

The omission arm additionally described Python `and` with an unqualified rule
about both operands being `True`. That rule is correct for this item's Boolean
comparisons but misleading as a general Python rule (`1 and True` returns the
Boolean `True`). The audit records this as scope uncertainty, separate from the
two definite arithmetic feedback errors. Even treating that wording favorably
would leave only 7/10 complete passes and would not change the failed outcome.

The known false-ratio repetition is consistent with anchoring. This comparison
also shows why copying alone does not explain all feedback defects: omitting
solver prose still produced errors and a false rejection. The unchanged prompt
asks to inspect the omitted records, so this is an omission experiment, not a
qualified redesigned review contract. The next candidate retains current reviewer
data; any alternative prompt or feedback architecture needs separate testing.

The exact plan, execution manifest, requests, responses, and earlier failed
pipeline evidence remain unchanged. Detailed per-item judgments and counterexamples
are in `reviewer-anchoring-audit.json`. The capture SHA-256 is
`2627bace50af8444fb88e538af609ad331f0c48daec604c53a45b3870fa3253d`.
No production source, deployment setting, or learner inventory changed in this
comparison.
