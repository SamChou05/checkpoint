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

The result shows that the compact typed author schema can work with the live
service and that the current constructor can make unambiguous candidate
choices from this response. It does **not** overturn the earlier
[full-worker failure](../mapped-agreement-full-worker-qualification-20260927/RESULTS.md)
or the [refill failure](../mapped-refill-qualification-20260927/RESULTS.md):
those required downstream model calls, which rejected two difficulty ratings
or timed out, respectively. Nor does one five-item call establish a reliable
40/80-item inventory. The mapped route remains opt-in and the deployed
TestFlight worker remains on the legacy path.
