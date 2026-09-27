# Mapped 40/80-item bank structural diversity simulation

**Result: exact stems stay unique, but the closed route repeats each reasoning
family heavily.** This deterministic offline run uses the `b86fc09` source,
the frozen [five-slot task seed](seed.json), and the same 3:2 mapped author
adapter, compiler, provenance, recent-30 prompt window, and private full-bank
variant projections used by the worker. It persists each compiled question in
an in-memory DynamoDB-shaped history, then refills from the identical source
tasks. It makes no provider call or real bank write.

| Five-item batches | Items | Unique exact stems | Uses of each of 10 slot-specific families | Same-slot/family item pairs |
| ---: | ---: | ---: | ---: | ---: |
| 8 | 40 | 40 | 4 | 60 |
| 16 | 80 | 80 | 8 | 280 |

The ten families are two per slot: fraction sum/scale and fraction quotient/add;
distributed linear and bounded quadratic equations; ratio minimum and quadratic
maximum; proximity and inverted-subject agreement; compound/`every` and
`a number`/`the number` agreement. For each slot, a family used eight times
creates `8 × 7 / 2 = 28` same-family pairs; the two families create 56 per
slot, or 280 across five slots. This is **structural reuse**, not 280
independently judged near-duplicate pairs. Distinct operands, scenes and stems
can affect difficulty and perceived similarity. Conversely, two differently
named families can still be semantically close, as the earlier
[answer-blind first-refill review](../mapped-refill-structure-preflight-20260927/RESULTS.md)
found for ratio-minimum versus quadratic-maximum thresholds. The simulation
does not replace that independent content review.

All 80 rows rechecked their code-owned proof, had four distinct choices, one
listed key, and feedback keyed to all four choices. Immediately after 80, the
next preparation records `agreement_novelty_exhausted` for both English slots:
their 16 exact stem variants per slot have been consumed. This matters for a
rolling 80-question bank or any failed/replacement items. The exact 40/80 stem
result is conditional on the frozen source tasks and all earlier items being
admitted; it is not a live worker yield or a universal bank-size guarantee.

The [reproduction script](run.py) compares its calculation byte-for-byte with
the [frozen summary](summary.json). The seed SHA-256 is
`42b775271ecb4a5b660f779f6d880ac989efd420225d14232e272443a78fe08d`;
the summary SHA-256 is
`5592d3f149f48a0cf5e3ab3857834abf04f250d7238aa22939e9cdc300bc33cc`.
Run from the repository root with the backend test dependencies available:

```sh
python -B docs/evidence/mapped-bank-diversity-simulation-20260927/run.py
```

This evidence rules out treating exact-stem deduplication or more lexical
scenes as a sufficient 40/80-item variety fix. A release design needs a
versioned, full-bank reasoning-mechanism ledger and a substantially broader
pool of distinct objectives and question formats with code-owned answers.
Where an objective cannot support the requested bank size, it should expose
that capacity rather than silently rephrase a few mechanisms. Any broadened
route still needs a repeated-bank worker run and independent, answer-blind
review of single-key correctness, choice quality, requested difficulty and
semantic overlap. This simulation alone does not qualify a rollout.

The frozen script reproduced `summary.json` byte-for-byte; the 26 focused
mapped-family/agreement backend tests, Ruff on the script, and `git diff
--check` passed. The full backend suite at baseline `b86fc09` ran 1,439 tests
with one unrelated infrastructure-template failure: its assertion expects the
old workflow default for `BEDROCK_REASONING_EFFORT`, while that baseline's new
deploy workflow uses the variable directly. No workflow or template files are
changed by this evidence commit.

During integration, commit `aad3f04` updated that stale assertion to the
explicit-variable contract; the full 1,439-test backend suite then passed.
The simulation's source-task seed and frozen counts were unchanged.
