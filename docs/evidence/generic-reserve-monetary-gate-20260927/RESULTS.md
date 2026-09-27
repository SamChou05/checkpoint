# Narrow reserve-only expected-money diversity gate

The opt-in generic reserve now applies a code-owned signature **after** both
answer-blind solver and reviewer chunks. It recognizes only a direct request
for an expected monetary value in a chance scenario with four bare dollar
choices. It retains the earliest verified question with that signature and
then applies the existing five-survivor, all-or-nothing return rule. Default,
mapped, and source-bound routes do not use this gate.

Offline replay of the frozen [Trial 04 capture](../generic-reserve-seven-probe-v4-20260927/capture.json)
found six verified source ordinals `1,2,3,4,5,6`. The signature matched
ordinals `3` (expected net gain) and `5` (expected winnings), and retained
`1,2,3,4,6`. This excludes the pair both locked blind reviews called a
strong repeat. It does **not** qualify the retained five for content: ordinal
`6` was verified by the live worker but was outside Trial 04's five-item
blind worksheet, and the replay did not make a new provider call.

The separate [first pairwise model probe](../generic-reserve-pairwise-diversity-probe-20260927/RESULTS.md)
found that expected-money pair, while the [second blind pairwise
probe](../generic-pairwise-second-blind-probe-20260927/RESULTS.md) also found
its batch's expected-money pair but falsely grouped a two-roll probability
and a one-draw complement. The code-owned guard leaves those fraction-answer
questions alone. Independent code review identified three additional false
positive patterns, now covered by negative regressions: an expected attendance
given before a deterministic profit question, a supplied expected ticket
value followed by total payout, and an inverse ticket-price problem with an
expected-gain condition.

The rule intentionally misses different wording or currency formats and may
still group two substantively different expected-dollar tasks. It is a narrow
quality improvement, not a general semantic novelty guarantee. The generic
reserve remains disabled by default pending a full-worker run and independent
content review on this source. Validation: **1,502** backend tests, Ruff on
changed Python files, and `git diff --check`.
