# Current mapped native author schema: bounded one-call probe

**Outcome: author-only pass, not a worker or bank qualification.** One pinned
Sonnet 4.6 Converse call accepted the current native JSON schema, ended normally
in 30.521 seconds, and returned five typed tasks. Offline compilation and the
normal sanitizer produced five candidate questions with three quantitative
proofs, two agreement proofs, and no failures. No solver, teaching reviewer,
worker, queue, bank write, deployment, or client request ran in this trial.

The [frozen plan](plan.json) SHA-256 is
`abfb96c1dbb533d4b2da2882a7c5f222a7464c5441335cb97f575eb6795b02cd`;
the [capture](capture.json) SHA-256 is
`9eeb2e11045d02f60911eba29911da995cb3c8469a545a2737cc819874b32ca4`.
The [historical harness](probe.py) pins source commit `6ea0eaf`, the hash of
every service Python file, the prior synthetic refill input, the exact request
and wire, the model, and the schema. It validated the JSON Schema and SDK
Converse shape offline before dispatch, checked the AWS account via one STS
call, allowed one Converse attempt without retry or fallback, and retained only
the sanitized response. The call used 4,134 input and 495 output tokens and
reported `end_turn`. The archive is deliberately single-use; its source-commit
guard prevents treating a later checkout as the original probe.

The separate [offline audit](audit.py) locks both evidence files and the source
hashes. It reprojects all three historical numeric identities from the
previously verified five-item seed, compiles the captured tasks, and checks the
normal sanitizer. It finds ten distinct exact stems across seed and new
candidates; each new question has four distinct literal choices, one exact
key, feedback for all four choices, and a stable key/feedback association under
all 120 choice permutations. Independent arithmetic and grammar checks match
the five keys: `17/8`, `7`, `9`, `are; is`, `are; is`. The first three answers
follow respectively from `3/4 ÷ (4/6) + 1`, `(x + 5)(x + 1) = 96` for offered
integer `x`, and the maximum integer satisfying `x(x + 4) ≤ 117` on the given
domain. The English answers follow from inverted subject-verb agreement and
the distinct `a number of` / `the number of` forms. The two English candidates
share the same four answer strings despite different grammar rules; this
trial does not prove sustained format variety.

Two independent reviewers then received only an answer-hidden, shuffled
[ten-item worksheet](blind-worksheet.json) (SHA-256
`8505b8928be1df93284107ad369a6a21671bea3469774c05e1d0528db924728b`).
Five items came from the previously verified seed and five from this
author-only response; their origins, keys, and proofs were withheld. Both
[review A](blind-review-a.json) (SHA-256
`e7f1bc5d9dd7869d38f3055242be2b6cc831c4c74030e1fb30897aec6e780a3a`)
and [review B](blind-review-b.json) (SHA-256
`3e529fc7f4a4c5654361c94098226a1bff72d7554db67278247ddf9ea5914f57`)
locked before the [private mapping](blind-private.json) was opened. Both
selected the exact key on all ten questions and judged every item
self-contained with all four choices meaningfully distinct. The
[post-lock join](post-unblind.json) verifies their keys against the private
map and records pair origins.

Variety was less settled. Review A found five **moderate** near-duplicate
pairs and no strong pairs. Review B found nine overlapping pairs, including
three it rated **strong**: the seed and new inequality-cutoff items, the two
exact fraction-evaluation items, and two seed two-clause agreement items.
The reviewers agreed on those pairings but not on severity. The agreement
pair contains **two previous seed items**, so it is not a regression caused
by this author response. The new candidate and previous seed share a solve
pattern on the other two strong-rated pairs. This is direct evidence that a
schema, exact stem deduplication, and alternate algebraic frames do not by
themselves guarantee a bank of meaningfully different questions. It does
not establish that all three pairs are strong by consensus.

The result shows that the compact typed author schema can work with the live
service and that the current constructor can make unambiguous candidate
choices from this response. It does **not** overturn the earlier
[full-worker failure](../mapped-agreement-full-worker-qualification-20260927/RESULTS.md)
or the [refill failure](../mapped-refill-qualification-20260927/RESULTS.md):
those required downstream model calls, which rejected two difficulty ratings
or timed out, respectively. Nor does one five-item call establish a reliable
40/80-item inventory. The mapped route remains opt-in and the deployed
TestFlight worker remains on the legacy path.

The archived `audit.py` checks hashes against commit `6ea0eaf`; run it with
the evidence files in a checkout of that source snapshot. It intentionally
fails when service source changes. The live call cannot be replayed under its
frozen plan because its one-call allowance was consumed.
