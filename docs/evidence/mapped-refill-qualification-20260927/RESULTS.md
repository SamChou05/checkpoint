# Mapped closed-family refill: bounded qualification

**Outcome: FAIL.** The one authorized refill used all three reserved Converse
calls. Author and answer-blind solver responses arrived, but the final teaching
reviewer hit the frozen 70-second socket read timeout. The worker returned **zero
verified questions**. There was no retry, alternate job, top-up, deployment, or
production bank write. The five questions projected from the successful author
response are **unverified candidates**, not a worker return.

The candidate-only content evidence also fails the desired bank-variety bar:
two independent answer-blind reviewers identified the same **five strong
near-duplicate pairs across the ten-item worksheet**. Every pair joins one
previous bank item to the candidate in the same original slot. Changed numbers,
names, and exact stems preserved answers but repeated the substantive solve path.

## Frozen setup and call accounting

- Source: isolated checkout at `9105289100fdccec807a2d99c33878bfd276b6e0`.
  Its prior seed was the reviewed five-item capture from the earlier
  [one-shot mapped-family pass](../mapped-quant-families-qualification-20260927/RESULTS.md)
  (capture SHA-256 `f9e81f34f19e4829b49587c3919d77bae2595784064e063631d3515b61e009fa`).
  The prior pass used older source, so this is a synthetic bank refill, not a
  DynamoDB queue-and-claim run.
- The worker's own allocation and history functions produced the new request
  with five prior ready rows, five recent prompts and coverage rows, two
  full-bank English identities, a client-reported prior prompt, and two blocked
  v1 stem fingerprints. Desired count 11 and low watermark 0 preserved the
  exact 3 arithmetic : 2 English allocation and two one-objective counts.
  This small finite-bank setup was chosen because those static fields remain
  equal across the first two chunks; it does not model ordinary 40/80-item
  allocation sequences. The normalized goal and all assignment fields stayed
  pinned. The default full-request hash changed; the explicit `refill_history`
  scope digest matched both states.
- Frozen [plan](plan.json) SHA-256:
  `5681a27a407aebfad3f3b8e2ec6422859a912c28b7a77c7b972492aa0c5d44e2`.
  Static scope SHA-256:
  `e7ee04d1079161ba077043bd688a83958a102320c9d53a837cb96cd8039a3bdb`.
  Exact first author wire SHA-256:
  `d9869d3d7d7cff21625499c9b0211b1d2fe3f7a6ed617427cf3bd5c69fd8cd94`.
  The plan pins every service Python file and the [frozen harness](refill_probe.py).
  Offline route, JSON Schema, botocore Converse shape and focused backend tests
  passed before execution (31 tests, 41 subtests).
- The plan allowed one refill pass, at most **three new Converse calls**, one
  botocore attempt per call, one STS identity request, no fallback or top-up,
  and a 240-second overall execution deadline. STS confirmed the pinned
  account. Exactly three provider calls were reserved and dispatched in
  author, solver, reviewer order. The first two responses reported **7,457
  input and 2,947 output tokens** combined. Reviewer usage is unavailable
  after its read timeout; these are observed partial counts, not total use or
  a dollar estimate.
- The unmodified [partial capture](capture.json) SHA-256 is
  `f27a207c6039f54cd7ad3e640184e9cbbcb5b42940e23b683c08999635496ec5`.
  It records two responses, the reviewer `ReadTimeoutError`, all three
  dispatches, and zero returned questions. A separate [operational failure
  record](operational-failure.json) reconciles it. The frozen harness had an
  **offline finalization defect** after the timeout: its token sum dereferenced
  the reviewer's `null` response, leaving capture status at `setup`. This does
  not change the recorded provider failure or authorize a rerun. The raw
  capture and frozen harness are preserved for provenance. A future harness
  must sum `(call.get("response") or {}).get("usage", {})` and test timeout
  finalization before any new trial.

## Candidate-only proof and blind review

The author response adapted to the same five original slots. Offline
recompilation and sanitization produced five candidate questions with zero
compile failures. The [candidate audit](candidate-audit.json) matched the
three numeric private proofs, independently solved their exact keys, matched
the two English code-owned proofs, found a unique literal key among four
choices in each item, checked all 20 choice-keyed feedback entries, and
verified 120 choice-order permutations. All ten earlier-plus-candidate stem
identities were distinct. The five candidate explanations and feedback entries
were manually checked for factual support. The equation main verifies its key
rather than deriving it algebraically, a teaching limitation even though the
key and per-choice feedback are correct. None of the model-chosen numeric
operands or English tasks required a history-driven replacement; this trial
therefore does not test the replacement branch under live provider output.

The answer-hidden, shuffled [candidate worksheet](candidate-worksheet.json)
(SHA-256 `ff075ecd551b604ba84c8e57496733c69b7613102cb653c1d777a64dce90ae04`)
mixed five previously verified items with five **unverified** refill candidates.
The [private origin/key map](candidate-private.json) remained separate until
both independent reviews locked. The [first](review-codex-agreement-history.json)
and [second](blind-review-codex-independent.json) reviews have SHA-256 values
`32d34f5f8406327c131e0c2d528f6b9cd5c178544d847f61c598c450b61c3d33`
and `4f54cfdc3745f95d81e4c65425e937c74d97f3ee29ba7e588286e3966d49d255`,
respectively. Their answers were compared with the private map only after
both locks:

| Blind assessment | Reviewer 1 | Reviewer 2 |
| --- | ---: | ---: |
| Correct literal choice, all items | 10/10 | 10/10 |
| Correct literal choice, refill candidates | 5/5 | 5/5 |
| Self-contained, one supported choice, distinct choices | 10/10 | 10/10 |
| Difficulty at least level 2 | 10/10 | 10/10 |
| Strong cross-bank near-duplicate pairs | 5 | 5 |

The reviewers named the **same five pairs**. The [post-lock join](post-unblind.json)
shows that each pair occupies one original slot in the prior and candidate
batches: fraction evaluation, bounded equation, ratio-threshold minimum,
proximity agreement, and compound/distributive agreement. The two English
patterns have different rules from each other, but each was repeated across
the bank boundary. Literal stem deduplication did its limited job; it did not
supply meaningful variety.

This bounded attempt qualifies neither repeated-bank reliability nor a
40/80-item bank. The closed English library itself has at most eight variants
per slot. More importantly, this run returned no verified refill inventory,
and its candidate-only comparison shows a concrete diversity failure even
where exact key, choices, feedback and level-2 blind ratings were sound. The
mapped route remains opt-in and undeployed.
