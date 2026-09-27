# Current native transport schema: one bounded author call

**Outcome: author-only pass.** At source commit
`811ec0af4759c40731750165c3c5f0043a034e70`, one pinned Claude Sonnet
4.6 Bedrock Converse call accepted the mapped five-slot native JSON schema and
returned five typed tasks. Offline compilation and the normal sanitizer produced
five candidate questions: three numeric proofs and two English agreement proofs,
with no compiler failures. The response reported `end_turn`. No solver, teaching
reviewer, full worker, bank write, queue, deployment, GitHub write, or client
request ran.

The [frozen plan](plan.json) SHA-256 is
`794c1626bcefc30dbc3fc6b8db2013c4e11291e7bfed6b8789df99017e4f0926`;
the [sanitized capture](capture.json) SHA-256 is
`88bba102fd848d96e782334a1ca0fc5fe3a0d9059f85d72897445fc348e5f819`.
The [single-use harness](probe.py) pins the source commit and service source
hashes, the prior synthetic 3:2 seed/refill input, request hash, exact wire
hash, model and endpoint, and a one-call limit. It validates JSON Schema
Draft 2020-12 and the SDK Converse input shape offline, verifies AWS account
`239342516379` via one STS call, disables retries and fallback, and captures
only safe response fields. The configured Bedrock read timeout was 70 seconds;
the total deadline was 120 seconds. The completed call took 27.598 seconds,
with provider latency 26,191 ms. Usage was 4,329 input tokens and 953 output
tokens (5,282 total); cache-read and cache-write input tokens were both zero.

The JSON schema sent on the wire was **2,013 bytes**, SHA-256
`be8391e81587d8dca861f46cfdb0f1a89e18d88ad19a3417105affab016f2d99`,
with stable transport name
`question_author_constructed_mapped_families_v5_n5`. The prompt kept its
assignment-specific author-contract identity. This single call confirms that
the current wire declaration was accepted; it does not establish a cache hit or
predict future schema compilation time.

The [offline audit](audit.py) locks the plan, capture, harness, and service
source hashes. It replays the captured tasks through the normal compiler and
sanitizer and verifies all five candidates have four distinct literal choices,
one exact key, feedback for each choice, and stable answer/feedback association
under all 120 possible choice-order permutations. It finds ten distinct exact
stems across the historical five-question seed and these five new candidates.
Manual independent checks agree with the keys: `20/31`, `8`, `7`,
`carries; check`, and `is; are`. The first follows from the reciprocal of
`4/5 + 6/8`; the second solves `(x+5)/(x+1)=13/9` in the stated domain; the
third takes the maximum integer satisfying `3(x+2)+x≤34`; the English answers
follow subject-verb agreement in the supplied sentences.

This is evidence for **schema acceptance and candidate construction only**.
It does not overturn prior full-worker failures or qualify sustained bank
variety. Exact-stem and literal-choice checks do not rule out semantically
similar questions; these five have not passed an answer-blind diversity review.
The mapped route remains opt-in, and the deployed TestFlight worker remains on
the legacy path. The harness cannot issue a second call because the capture
already exists, and its source-commit guard prevents treating later source as
this historical probe.
