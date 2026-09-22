# Constructor worker trial: better yield, failed qualification

The actual worker returned **14/15** requested questions within its budgets, but
the trial failed. Both independent reviews found **13/15** sound learner items:
all fourteen keys are correct, while one Python main explanation gives a false
execution sequence. The separate constructor quota also failed. The numerical
job used ordinary prose for every item; only three mixed-job items used the
constructor. This configuration remains inactive.

| Job | Returned / planned | Sound learner items | Compiled returns | Calls | Seconds |
| --- | --- | --- | --- | --- | --- |
| Numerical | 5/5 | 5/5 | 0 | 3 | 53.436100 |
| Python | 5/5 | 4/5 | 0 | 3 | 61.407327 |
| Mixed | 4/5 | 4/5 | 3 | 5 | 92.328774 |

All eleven calls returned native-valid output and ended normally. Reported usage
was 33,973 input and 17,322 output tokens, with no missing usage. No retry, rescue,
model substitution or extra job occurred. The frozen denominator remains fifteen.

## What the constructor did

The model supplied four task-only numerical rows, all in the mixed job. Three
compiled and passed the immutable final audit. Their exact keys, four distinct
values, three worked main explanations and twelve choice-feedback statements
are independently correct. Rebuilding their original tasks reproduces the full
specifications and all five learner fields. No answer choices were supplied by
the author for these rows.

The fourth task was unsatisfiable: `(5 * 2 + x - 17) = 5` requires `x = 12`, outside
its declared integer domain `1..10`. The constructor correctly rejected it with
`no_answer`. This is an invalid authored task, distinct from the previous trial's
missing correct value in an author-supplied choice set. Code cannot repair that
task without changing its premises.

All five numerical-only questions instead used the permitted prose variant.
They are correct on independent review, but receive policy 7 and no compiler
guarantee. The native union allows either variant; the instructions say to use
the numerical variant only when it serves the objective, without enforcing
scope-based selection. Thus this run cannot qualify the constructor route:
zero numerical-job compiled returns miss the required four, and three total
compiled returns miss the required six. The mixed quotas of two compiled and
one English item did pass. Schema compliance and actual constructor use are
different measurements.

## Correct key, false teaching

`python:4` correctly answers `True` for `True or False and False`. Its main says
the right-hand conjunction evaluates first, then the `or` expression evaluates.
That is not Python's execution order: the left `True` makes `or` skip the entire
right-hand side. Operator precedence determines grouping; it does not override
short-circuit evaluation. See the [Python language reference](https://docs.python.org/3/reference/expressions.html#boolean-operations).

Both reviewers locked the correct answer from the stem before seeing this
explanation, then independently identified the false execution narrative. Root
also checked a handwritten expression with operand-visit markers; the independent
review checked its syntax tree and bytecode. These checks distinguish a correct
result from incorrect teaching. The immutable final auditor nevertheless marked
that explanation supported. No explanation was rewritten to rescue the result.

The other thirteen mains and all twelve compiled choice-feedback fields are
supported. All eleven prose solver dispositions, 44 choice judgments and 66 pair
judgments agree with the independently solved tasks. A garbled indexing
parenthesis in one private pair reason is recorded separately; it did not change
the correct distinct-value judgment. Private reasons are not learner teaching.

## Yield and review boundaries

There were seventeen raw author rows. Besides the unsatisfiable task, the mixed
job lost a pronoun item whose main referred to answer positions. Its top-up used
the same generic stem and was deduplicated. The job stopped with one provider
call remaining, below the existing three-call requirement for another author
pass. Neither discarded pronoun item earns content credit; rejection by a
structural guard does not prove its semantics were otherwise correct.

Socket-blocked replay reproduced all eleven requests, reservations, passes,
source bindings, verifier decisions and returned records. All 37 pins matched
through 31 actual plan checks. The same runtime limits and native contracts were
used at dispatch. Root separately checked 336 stored-key choice permutations;
the [client audit](../constructed-authoring-20260922/CLIENT_HIGHLIGHTING_REVIEW.md)
records actual Swift model/presentation tests and their UI limitations.

Both reviewers locked stems and rotated choices before opening keys, teaching,
provenance or model judgments. The numerical extrema stated in the prose rows
are mathematically complete over integers; no hidden bounds are needed to solve
them. That does not give those rows finite-domain compiler provenance.

- [Frozen plan](plan.json): `29ca1b56074a64c9af5306c6c3e14880a6c7d9ed53bb065c6e2d0dd22f81b87c`.
- [Capture](capture.json): `49833e414ec775090b3408ff6b73d5b967c401fd64b6b4294d7533f1ac8c2658`.
- [Root blind lock](root-blind-review.json) and [content review](root-content-review.json).
- [Independent blind lock](independent-blind-review.json) and [content review](independent-content-review.md).
- [Independent structural replay](independent-structural-review.md).

These are three fresh batches on repeated scopes, with no matched-item or
population-accuracy claim. The failed prose-task prompt addition was excluded.
No runtime default, policy floor, stored inventory or deployed service changed.
