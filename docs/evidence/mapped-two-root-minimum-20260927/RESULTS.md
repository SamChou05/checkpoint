# Mapped quantitative two-root minimum: offline result

This change adds a fourth substantive mechanism to numeric slot 1 of the
opt-in mapped 3:2 route. The closed task is
`(x - b)(x - (b + a)) = 0`, on the explicit integer domain
`0..(b + a + 2)`, with `selection: minimum`. Its two solutions are `b` and
`b + a`; the latter is now always an offered distractor. The other two
offered wrong values fail the condition. The exact key, choice order,
individual feedback, and domain-wide minimum proof are code-owned.

The finite inventory adds 72 variants (8 values of `a`, 9 of `b`), bringing
the numeric total from 624 to 696. Every variant compiled with four distinct
choices, one exact key, and round-trippable provenance. A representative
`a=5, b=7` item asks for the minimum solution of
`(x - 7)(x - 12) = 0`; it offers both `7` and `12`, and explains that `12`
satisfies the equation but is not the minimum. This tests a different decision
from the slot's three unique-solution equations.

The existing offline full-history capacity harness, run on the same frozen
seed and current compilers, reports:

| Bank size | Before: same-slot-family pairs | After | Slot 1 after |
| ---: | ---: | ---: | ---: |
| 40 | 35 | 32 | 4 |
| 80 | 175 | 164 | 24 |
| 85 | 200 | 188 | 28 |

At 80 items, slot 1's family-pair count fell from 35 to 24. Exact stems
remain unique, and the strict one-use-per-family gate still fails at 40 and
80. These are structural counts, not independent judgments of semantic
novelty or requested difficulty. In particular, the two-root task has not
undergone answer-blind model review.

The mapped native schema grows from 2,013 to 2,040 bytes; its new SHA-256 is
`4cb4a9f845c5553f141bb684360f7a086529814b465271d55ca13900e9932d5e`.
The contract name and metadata revision advance to `v6` and `8`. The schema
passes local JSON Schema and Bedrock SDK shape validation, but this exact
revision has **not** been sent to Bedrock; provider acceptance is unproven.
There were no AWS calls or production writes in this experiment.

Reproduction from repository root:

```sh
PYTHONPATH=backend/bedrock-question-service:backend/bedrock-question-service/tests:$PYTHONPATH \
  python -m unittest discover -s backend/bedrock-question-service/tests -p 'test_*.py'
PYTHONPATH=backend/bedrock-question-service:backend/bedrock-question-service/tests:$PYTHONPATH \
  python backend/bedrock-question-service/tests/mapped_bank_capacity_harness.py \
  --items 40 80 85 --max-family-uses 100
```

The backend suite passed 1,450 tests. Ruff and `git diff --check` also passed.
