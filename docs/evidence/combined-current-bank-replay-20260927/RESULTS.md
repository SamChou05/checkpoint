# Current combined-source bank replay

**The current code-owned route can construct 20, 40, and 80 distinct exact
stems, but larger banks still repeat reasoning and question formats.** This
offline replay pins the backend source at `1dc91bf` and reuses the five tasks
from an accepted native v9 author capture. It passes those tasks through the
current native adapter, actual mapped selector and compilers, a recent-30
prompt window, and the same full-bank variant-history projections used by the
worker. Each accepted row is added to an in-memory DynamoDB-shaped history.
There are no new model, worker, queue, AWS, or bank calls.

| Requested items | Compiled items | Unique exact stems | Code-owned one-key, four-distinct-choice checks | Same-family pairs within slots | Same numeric solve-signature pairs | Of those, pairs across different numeric family names | Same prompt-format pairs within slots |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 20 | 20 | 20 | 20 | 0 | 1 | 1 | 30 |
| 40 | 40 | 40 | 40 | 17 | 14 | 4 | 133 |
| 80 | 80 | 80 | 80 | 102 | 78 | 18 | 561 |

The solve signature comes from the compiled numeric graph using the existing
[offline signature probe](../solve-signature-gate-20260927/probe.py). It records
the operation tree for exact arithmetic or the relation, polynomial degree,
and variable-denominator status for bounded conditions. These are **structural
pair counts**, not 78 independent blind judgments of near-duplication. In the
first 20, `bounded_quadratic_equation` and `bounded_two_root_minimum` already
share a quadratic-equality kernel despite different family labels. By 40,
`bounded_linear_budget_maximum` and `bounded_solution_count` also share a
linear-upper-bound kernel. A family-name-only diversity gate misses both.

The new mechanisms are selected, but not uniformly early. The chronological
20-item replay selects the new slot-3 partitive family and slot-2 centered
square count. The new slot-1 quadratic-exclusion count, slot-2 linear-budget
maximum, and slot-4 full-sentence selection appear by 40. At 80, each numeric
slot-1 and slot-2 family is used three or four times; slot 3 uses each of its
four families four times. Slot 4 uses full-sentence selection **three times**,
while 13 of its 16 prompts still use the two-blank ordered-pair format. Slot 3
uses the two-blank format for all 16 prompts. The [machine report](summary.json)
contains the exact per-slot family, scene, graph-signature, and prompt-format
counts.

For a later answer-blind review, the [keyless 20-item worksheet](worksheet.json)
is a deterministic **stratified sample from the first 40 replayed items**, not
the chronological first 20. It takes the earliest occurrence of four selected
families per slot so the new quadratic-exclusion, linear-budget and
full-sentence-selection mechanisms, and both cross-family numeric solve
overlaps, are present. Its SHA-256 is
`265579e1a486435975e723e23b5364e4d72d9883ebd2ae3c87cb0f31bc4a48ed`.
The answer map is stored outside Git at
`/private/tmp/checkpoint-combined-current-bank-private-20260927/answer-map.json`
with file mode 600. The worksheet has no key or family metadata; review it
before opening the private map. No answer-blind review has yet been performed
on this new worksheet.

Run the [reproduction script](replay.py) from this repository root with the
backend test dependencies installed:

```sh
CHECKPOINT_PRIVATE_MAP_DIR=/private/tmp/checkpoint-combined-current-bank-private-20260927 \
  PYTHONPATH=backend/bedrock-question-service:backend/bedrock-question-service/tests \
  python -B docs/evidence/combined-current-bank-replay-20260927/replay.py
```

The script verifies that frozen public and private files remain byte-for-byte
identical on rerun. The source capture SHA-256 is
`17575d5a62b1fde235c3d43c7c9bc1d9e40385466e30b973fde1ca9cf1bbc9aa`.
This replay measures closed-constructor capacity only. It does not establish
live author selection, reviewer acceptance, age/grade difficulty, teaching
quality, or subjective bank diversity; those require the full worker and
independent blind review. In particular, 80 unique stems do not imply 80
different questions in the sense a student would experience.
