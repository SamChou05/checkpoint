# Current mapped 20-item offline bank sample: post-lock review

The current closed 3:2 mapped constructors compiled **20 of 20** items across
four five-question refills from one saved native author task object. Every
item has four literal-distinct choices, one listed key, feedback for every
choice, and a rechecked compiler proof. All 20 exact stems are unique under
the same recent-30 prompt window and full-bank numeric/English variant
projections used by the worker. This is an **offline constructor sample**;
there were no provider, solver, reviewer, queue, or durable-bank calls.

The [keyless worksheet](worksheet.json) SHA-256 is
`ab3d3ab1b73c0bf6268a6c4cd5cc13d753ba804c77a1ca1e8e3635edbd960ab4`.
The independent [rubric](RUBRIC.md) asks for each key, all six within-item
choice-pair judgments, difficulty 1–5 against the 2–3 target, and moderate or
strong reasoning-level near-duplicates across all 190 item pairs. The answer
map stayed outside the repository until the review file was locked. The
[review](review-a.json) SHA-256 is
`63c833dcf02aea88f4ee8343b308e9b1203a841744f467eec41ee9d9d8579c74`;
the now [archived answer map](post-lock-answer-map.json) SHA-256 is
`40be5690f5f5733a986f85c0a3bf87703466a225bedb728ac0f68c3582f303c2`.

**The reviewer selected 19 of the 20 code-owned keys.** The [post-lock
audit](post-lock-audit.json) checks every displayed prompt, choice, key, and
review selection against the frozen worksheet and map. On `Q08`, the reviewer
selected `D` (`keep; review`), but their own explanation identifies singular
“Every clerk” and plural “Ava and Ben.” The correct displayed choice is `C`
(`keeps; review`), which is also the compiler's key. The locked review remains
unchanged. This is a reviewer letter-selection error, not evidence that Q08
has two valid answers or an incorrect constructed key.

The reviewer judged all **120 within-item choice pairs** meaningfully
distinct and all 20 stems self-contained with clear objectives. They rated
`Q05`, the bounded two-root minimum item, difficulty **1**: its factors expose
both roots directly, below the target 2–3. They flagged weak distractors in
`Q02` and `Q19`, artificial wording in `Q17`, and thin context in `Q10`.
Distinct choices and a single correct key therefore do not settle distractor
quality or difficulty.

Across the 190 cross-item pairs, the reviewer recorded **one strong** and
**23 moderate** near-duplicates, leaving 166 unflagged. The strong pair
`Q01/Q04` is the same slot-3 proximity agreement decision in batches 2 and
4, with nouns and verbs changed. Seven of the moderate pairs cross the two
English slots, and two cross numeric slots 1 and 2. The audit verifies the
pair IDs, uniqueness, categories, and 190-pair arithmetic; it does not
independently reproduce the reviewer's semantic judgments. This one reviewer
and one offline sample cannot estimate live worker yield or general quality.

| Items | Numeric family use | Same-slot family pairs | Reused numeric operand pairs in a slot | Reused numeric operand pairs across slots |
| ---: | --- | ---: | ---: | ---: |
| 15 | Three different families in each numeric slot | 0 | 0 | 0 |
| 20 | All four current families once in each numeric slot | 1 (English proximity) | 0 | 0 |

At 15 items, this source produces one proximity × compound structural pair,
versus two flagged structural patterns in the archived [15-item
audit](../mapped-cross-slot-mechanism-audit-20260927/RESULTS.md). At 20, the
same three earlier warning formulas flag three pairs: two proximity ×
compound and one quadratic-maximum × linear-maximum. They are **candidate
overlaps**, not reviewed semantic-duplicate counts. The earlier independent
[15-item review](../mapped-combined-bank-blind-20260927/RESULTS.md) found four
strong near-duplicate pairs by consensus even while its same-slot family
counter was zero. That is why the present blind review must include cross-slot
and cross-family comparisons.

This first-20 structure benefits from having four numeric mechanisms per
slot, but it does not establish 40/80-item capacity or quality. The existing
[80-item capacity run](../slot4-gerund-capacity-20260927/RESULTS.md) still
records 29 same-slot family pairs at 40 and 153 at 80, and its strict
one-use-per-family gate fails. Different source-task seeds and item counts
make these descriptive comparisons, not a controlled causal estimate.

The [seed](seed.json) contains only the five typed tasks from the latest
accepted native author response, the base source commit
`0488e5239f63dcdc02c1926d5e8ecd270254953b`, and deterministic shuffle
seeds. Its SHA-256 is
`97311ad795e7936ffd0c79b338762770a27336d86d3200c24afc21bb0bad05f5`.
The source capture SHA-256 is
`17575d5a62b1fde235c3d43c7c9bc1d9e40385466e30b973fde1ca9cf1bbc9aa`.
The [summary](summary.json) freezes the source-file hashes, family counts,
and operand-reuse metrics without keys. The [preparation script](prepare.py)
checks that the source files still match the base commit and verifies output
bytes on rerun. Supply a private output directory when reproducing:

```sh
CHECKPOINT_PRIVATE_MAP_DIR=/path/only-the-preparer-can-open \
  PYTHONPATH=backend/bedrock-question-service \
  python -B docs/evidence/current-20-bank-blind-20260927/prepare.py
```

The keyless worksheet, review, answer map and [audit script](audit.py) are
frozen. Rerunning `audit.py` verifies the hashes and result byte-for-byte.
The semantic repeat and below-target difficulty mean this sample does not
qualify an 80-item bank or the full worker for release.
