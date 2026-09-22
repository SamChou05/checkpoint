# Bounded quantitative compiler and opt-in mixed authoring

`backend/bedrock-question-service/quantitative_task_compiler.py` is a pure compiler.
The separately configurable mixed author route can use it for supported numerical
tasks while keeping ordinary prose questions for all other subjects. The mode is
**off by default and not provider-qualified or deployed by this implementation**.
No client or global verification floor, transport, or model default changes.

`compile_question(spec)` either returns the five learner fields (`prompt`, four
`choices`, `expectedAnswer`, `explanation`, and four exact-keyed
`choiceExplanations`) or raises `QuantitativeTaskError` with a stable failure
code. The specification **is the complete problem**. It cannot carry an existing
stem, scenario, answer key, explanation, code, or other free prose. All learner
facts, the selection task, and teaching are rendered together from validated
data; this never silently repairs an old ambiguous question.

Two task shapes are supported:

```json
{"kind":"exact_value","unit":"m",
 "expression":{"op":"add","left":{"value":"0.1"},"right":{"value":"0.2"}},
 "choices":["0.3","0.2","0.4","0.5"]}
```

```json
{"kind":"scalar_condition","unit":"rides","selection":"minimum",
 "condition":{"left":{"op":"mul","left":{"value":"2.50"},"right":{"variable":"x"}},
              "relation":"gt","right":{"value":"60"}},
 "domain":{"kind":"integer_interval","lower":0,"upper":40},
 "choices":["23","24","25","26"]}
```

Expressions are closed trees of bounded exact number strings, `x` (conditions
only), and binary `add`, `sub`, `mul`, `div`. Comparisons are `lt`, `le`, `gt`,
`ge`, `eq`, `ne`, rendered as `<`, `<=`, `>`, `>=`, `=`, `!=`, respectively.
Equality and inequality are exact rational comparisons, without tolerances.
Selection is `any_satisfying`, `minimum`, or `maximum`; the domain is the
explicit inclusive integer interval or `{"kind":"offered"}`. Minimum/maximum
are taken over the **whole stated domain**, not silently over the offered subset.
`any_satisfying` asks which offered value satisfies the condition; it accepts only
when exactly one does, even if additional unoffered domain values also satisfy it.

The condition example renders an explicit minimum task and selects 25 rides.
Changing only its selection to `any_satisfying` rejects it because both 25 and 26
satisfy the strict comparison. Changing `gt` to `ge` makes the minimum 24. If 25
is absent, the integer-domain minimum task rejects the choices instead of
substituting 26. An explicitly offered-domain minimum can legitimately select 26.

Likewise, `x * x = 49` with both 7 and -7 offered in a signed integer domain
rejects an `any_satisfying` task. An explicitly nonnegative domain makes 7 the
sole supported option. A signed domain can also support an unambiguous offered
answer when only one root is listed: this task asks which offered value satisfies
the equation, not whether the equation has only one root in the entire domain.

All numerical operations use `fractions.Fraction`, never floating point. Input
decimal/fraction aliases are canonicalized before learner text exists; equivalent
choices are rejected even when both are wrong. Scalar extremum ties are equivalent
values and are rejected by the same check. No answer or multiple answers also
reject the task. All permitted domain values are evaluated; division by zero or
an arithmetic limit anywhere in that domain rejects the entire task. Out-of-domain
offered values are explicitly refuted by domain membership, without pretending
their numerical condition is false. Feedback states calculated results and stated
selection rules; it does not invent a learner's misconception.
The main explanation gives the selected value's actual substituted comparison.
For extrema it states the exhaustively checked smaller/larger-domain exclusion,
or that no such domain values exist. It does not assume the condition is monotonic.

Exact-value mains show a deterministic worked calculation, rather than only
stating the result. Inner operations appear first. Fraction addition/subtraction
shows a common denominator and converted numerators; multiplication shows the
numerator/denominator product and reduction; division shows multiplication by
the signed reciprocal, followed by the product and reduction. Negative operands
and fraction operands remain grouped, and zero is handled exactly. Every step
uses the same bounded `Fraction` arithmetic as the answer. A literal definition
is explained directly without inventing an operation. Scalar-condition teaching,
keys, prompts, choices and per-choice feedback are unchanged by this renderer.

For example, `(5/6)/(5/9)` now teaches:
`Multiply by the reciprocal: (5/6) / (5/9) = (5/6) * (9/5) = 45/30 = 3/2.`
The final sentence attaches the declared unit to the answer. Repeated subtrees
are shown in dependency order; different calculations that happen to produce the
same value are never merged. The complete main must still fit **420 characters**.
Longer valid expressions fail with `learner_text_limit`: no clipped proof,
omitted operation or answer-only fallback is emitted. This can lower yield for
large or deeply nested expressions. It does not loosen the independent solver
or audit, and does not establish a difficulty or pedagogical-sufficiency guarantee
for every accepted expression. Historical specs, captures and stored learner
content are not rewritten.

Units are one shared identifier from `unitless`, `m`, `cm`, `s`, `kg`, `g`, `L`,
`USD`, `rides`. Expressions operate on numerical measures in that declared unit;
this compiler does not derive physical equations, mix/convert units, preserve
alternative written number formats, or infer dimensions from prose. Fraction
operands are parenthesized so rendering preserves the exact expression tree.

Limits: four choices; 24 characters per input number; numerator magnitude and
positive denominator at most 10^9; 96 bits per intermediate rational component;
31 expression nodes total and depth 6; at most 201 integers with endpoints within
±10^6. Closed fields, exact primitive types, bounded parsing/evaluation, and final
320/140/420/280 character limits reject excess without clipping. No `eval`,
generated code, arbitrary functions, source lookup, I/O, or network is used.

The tests include 3,780 small-domain cases against a separate integer oracle,
all choice permutations, strict/inclusive and global/offered boundaries, exact
decimal/fraction arithmetic, equivalent distractors, empty/multiple solutions,
undefined expressions, oversized/cyclic input, and rendering bounds. Run from
the backend directory with `python -m unittest discover -s tests -p
test_quantitative_task_compiler.py`.
Worked-proof tests independently parse every displayed equality with exact
arithmetic for 248 signed/zero binary cases and 64 nested operator combinations,
check source-operation order, reciprocal signs and reductions, and exercise the
complete 420/421-character boundary without mocking or truncating the renderer.

This guarantees the bounded mathematical task and its generated teaching, subject
to implementation correctness. It does **not** certify distracting-error
plausibility, learning-objective fit, novelty, difficulty, or open language,
causal, scientific, and factual questions. Any wider content guarantee remains separate; the ordinary prose path still
depends on fallible model judgments.


## Opt-in route and exact source binding

Set `QUESTION_AUTHOR_MODE=mixed_quantitative` only with native transport. Both
`QUESTION_FEEDBACK_CONTRACT=reviewer_written` and the opt-in `authored_solution`
main-only audit are supported; legacy transport fails before dispatch. `prose` remains the default and keeps the existing native-v3 or
legacy-v1 author contract. SAM exposes `QuestionAuthorMode` (default `prose`)
and `QuestionBankWorkerAuthorMode` (default `inherit`); the corresponding deploy
variables are `QUESTION_AUTHOR_MODE` and `QUESTION_BANK_WORKER_AUTHOR_MODE`.
A worker-only opt-in can leave the synchronous API unchanged. Roll back by
selecting `prose`, without changing stored questions or policy stamps.

`question_author_mixed_v1` returns a `questions` array of closed variants:

```json
{"kind":"prose","question":{"prompt":"...","choices":{"a":"...","b":"...","c":"...","d":"..."},"explanation":"...","correctChoice":"a","topic":"...","difficulty":2,"format":"Multiple Choice"}}
```

```json
{"kind":"quantitative","task":{"kind":"exact_value","unit":"unitless","nodes":[{"kind":"literal","value":"2"},{"kind":"binary","op":"add","left":0,"right":0}],"root":1,"choices":{"a":"3","b":"4","c":"5","d":"6"}},"topic":"Arithmetic","difficulty":2}
```

The typed row allows only its task, topic/difficulty and optional skill/objective
metadata. It accepts no authored key, stem, feedback, approval flag or digest.
Task-defining fields precede choices in the serialized schema; ordinary prose
retains the exact author-v3 property order. All historical schema bytes remain
unchanged. Internal `$defs` share the node, task and prose schemas without recursive
references or a depth-expanded provider grammar. SDK validation is not live
provider grammar qualification.

Flat node identity is its array position. Binary operands must reference earlier
exact integer positions; roots must exist and every node must be reachable.
Expanded size and depth are checked **before** tree materialization, counting
shared references again and summing both condition roots. A small DAG cannot
bypass the compiler's 31-node/depth-6 limits. The adapter then invokes the original
compiler with all its unchanged rational, domain, output and resource bounds.
Invalid specs leave rejected source positions; they never become prose or receive
a repaired key. Other valid rows remain eligible. Ordinary bounded top-up passes
may author fresh questions within the same existing provider budget.

Only successful local compilation creates a private `CompiledCandidate` with
immutable specification and learner snapshots. A trusted ordinal sidecar follows
source rows through sanitization, duplicate removal, immutable freezing, solver filtering and dense
review reindexing. No prompt, content digest, normalized answer or model identity
is used to join provenance. The sanitizer checks all five fields against a fresh
compilation and preserves exact choice order, main and per-choice feedback.
The existing answer-blind fixed-slot solver still vetoes incorrect/duplicate
choices; the reviewer still vetoes, agrees with the exact key and assesses
requested difficulty, scope and novelty. These stages may falsely reject sound
compiled questions. In reviewer-written mode, generated reviewer feedback is
structurally checked but discarded for compiled rows. In authored-solution mode,
the count-bound immutable-main audit receives the exact compiled or authored
main explanation, without keys, solver judgments or choice feedback. It cannot
produce replacement teaching. All four compiler-derived choice explanations
remain protected by exact local recompilation.

Immediately before release, the same trusted specification is recompiled and
all five learner fields must still match. Those exact compiler fields replace
any intermediate content; only this route assigns policy revision **6**. This
guarantee is exact compiler-owned content plus the existing independent gates,
not the unused model-written feedback. Ordinary native rows receive revision 4
with reviewer-written feedback, or revision 7 with an unchanged authored main
and empty choice feedback. Maximum explicitly requestable policy is 7, while
the current server default remains 4 and the client minimum remains 2.
Stored legacy inventory is never promoted or relabeled. Revision 6 identifies
this bounded mathematical guarantee plus existing model gates; it does not
certify that a generated item teaches a requested nonmathematical objective.

Only a real private `CompiledCandidate` whose freshly generated five fields
match may carry nonempty choice feedback through immutable freezing. Prose
feedback is rejected, including provider flags pretending it was compiled. The
question and its sidecar are filtered together; a rejected row cannot lend its
provenance to a following prose row. Ordinary main text is preserved rather than
normalized or clipped. The final audit can veto either type but cannot rewrite it.

One complete pass still has exactly three provider stages: mixed author, existing
v5 solver, and the selected count-bound reviewer or immutable-main audit. The worker still has six calls total and its existing
deadline. No new model, reviewer stage, fallback permission, quota or global
quality floor is introduced. Unsupported subjects use the prose variant; typed
spec failures do not authorize reuse of an invalid task's content as prose.

Focused tests exercise graph bounds and flat/tree equivalence, forbidden metadata,
all five content mutations, duplicate removal followed by solver filtering and
review reindexing, reviewer veto/key/difficulty checks, forged stamps, mixed
subjects, failed specs, three-call and six-call behavior, exact claim/replay
policy thresholds, worker/API configuration isolation and offline SDK request
shapes. Live native grammar, yield, difficulty/assignment fit and mixed-subject
quality require separate bounded qualification before rollout.
