# Inactive quantitative task compiler

`backend/bedrock-question-service/quantitative_task_compiler.py` is a standalone,
pure prototype. Nothing imports it from generation, routing, or policy code. It
does not call a provider, stamp approval, change defaults, or deploy anything.

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

Units are one shared identifier from `unitless`, `m`, `cm`, `s`, `kg`, `g`, `L`,
`USD`, `rides`. Expressions operate on numerical measures in that declared unit;
this prototype does not derive physical equations, mix/convert units, preserve
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

This guarantees the bounded mathematical task and its generated teaching, subject
to implementation correctness. It does **not** certify distracting-error
plausibility, learning-objective fit, novelty, difficulty, or open language,
causal, scientific, and factual questions. Runtime integration and any wider
content guarantee remain separate work; the prototype is inactive.
