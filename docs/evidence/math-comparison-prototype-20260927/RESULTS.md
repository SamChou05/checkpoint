# Offline rational-comparison constructor prototype

This is a standalone code-owned prototype. No production selector, author
schema, provider call, or learner app imports it. It is a candidate way to add
the response format “which expression is larger, and by exactly how much?” to
the mapped level-2 exact-arithmetic objective.

`math_comparison_task_constructor.py` accepts only a closed family, one of eight
curated operand pairs, and a forward/reverse presentation order. It computes
both expression values and the exact margin with `Fraction`, then owns the
prompt, four literal choices, exact key, main explanation, and feedback keyed
to each literal choice. The two families compare crossed rational sums and
crossed rational products. The three wrong choices encode a reversed winner,
a partial-calculation margin, and both errors. For sums the partial margin
compares only the first fractions; for products it holds the second factor at
A's value. No model-supplied answer or explanatory claim is trusted.

The eight operand pairs were curated so their exact margins are distinct
across both families. With two families and two presentation orders, this
provides 32 distinct prompts and 32 distinct literal correct answers. Four
choice rotations yield 128 compiled variants, but rotations do not add
semantic variety. An earlier broader pair set contained mirrored answer
signatures and one cross-family margin collision; those pairs were removed
before this candidate was recorded.

The focused test independently parses each rendered expression, recomputes its
value, checks the winner and margin, reconstructs all four choice meanings,
checks all variants and rotations, and verifies bounds and closed-task
rejection. A five-item keyless sample is in `KEYLESS_WORKSHEET.md`, SHA-256
`870717a61bd366d6524ab5d0669fd4f2c0ea08c8e801c763735ea2d1419bb92f`.
Its intended answer map is outside Git at
`/private/tmp/checkpoint-math-comparison-prototype-20260927/answer-map.json`
with mode `0600`; do not show the map to answer-blind reviewers before their
reviews are locked.

This prototype does not establish learner difficulty or bank-level novelty.
Every item asks the same comparative relation and uses the same two-margin,
two-direction choice structure, so a longer bank may feel repetitive even
though operands and exact answers differ. The keyless sample needs independent
answer-blind review before any production wiring or live qualification.
