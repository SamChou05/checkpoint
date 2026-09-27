# Slot-2 typed solution-count candidate

The candidate adds one genuinely different decision to mapped numeric slot 2:
**count** the integers satisfying a distributed inequality in an explicit
eight-integer domain. The author still supplies only a closed family name and
two bounded operands. The code owns the inequality, domain, four numeric
choices, key, complete per-choice feedback, and an explanation that evaluates
every domain integer. It never treats a count as an `x` value. Existing generic
model-authored quantitative schemas retain their original three selections;
only the closed mapped family route may use `count_satisfying`.

The new family has 72 parameter variants (`a` from 2 through 9, `b` from 3
through 11). All 72 compile with exactly four distinct offered counts, one
listed correct count, complete feedback, and text within the compiler limits.
The correct count varies from 2 through 6. The mapped schema changes to 2,126
bytes, SHA-256 `c1622557c089257b648b57b65cc843b7e1766e57a8f8db0ebffadbbe3b76d769`,
with transport name `question_author_constructed_mapped_families_v8_n5`.
The general author schemas and prompt instructions remain unchanged.

In the offline full-history 3:2 capacity replay, exact stems remain unique
through 85 items. At 80, slot 2 uses each of four families four times; its
same-family pair count falls from 35 to 24. Across all slots, the 40/80/85
counts fall from 29/153/176 to **26/142/164**. This is a structural measure,
not an observed count of independently judged semantic duplicates. The strict
one-use-per-family capacity gate still fails.

Two independently locked answer-blind reviews assessed content. The
[six-count worksheet](worksheet.json) SHA-256 is
`73415d0a33dd50412a7cc2d112cd4251e1c3502cb42292cd00bd7615e531b021`.
Its [review](review.json) selected all six code-owned keys, found each item
self-contained, each choice set distinct, and each difficulty near 2/5. It
also judged **all 15 count-to-count pairs strong near-duplicates**: each
question uses the same cancellation and inclusive-count procedure. A second
[mixed slot-2 worksheet](cross-worksheet.json) SHA-256 is
`94c6cedbd4d7e877fad16b6ca8012ff2b4a76ef0a7287a65438474c5d96aec6a`.
That [review](cross-review.json) selected all five keys, found the two count
questions strongly similar to each other, and found only moderate or weak
overlap between count and the three existing max/min decisions. It also
independently called the two existing maximum families a strong pair. The
[post-lock audit](audit.py) joins both reviews with their private keys and
checks the worksheet hashes.

The count family is a repertoire improvement, not a complete bank-variety
fix. An 80-item bank still uses this exact count mechanism four times and
the two English slots retain other near-duplicate risks. The provider has not
been asked to emit the changed native schema, and no live repeated-bank worker
qualification or rollout is claimed from these offline checks.

The figures above are frozen to this candidate's isolated base without the
independent slot-0 product-complement family. After integration of both changes,
the combined native schema is 2,156 bytes with SHA-256
`a6426dd4d8cdd26a7d6fb03bbd373c8d55ab1dd79c17eab48279e3a3120d201e`
and transport name `question_author_constructed_mapped_families_v9_n5`.
The current-source capacity replay reports 23/131/152 same-slot/family pairs
at 40/80/85 unique stems. This combined schema has not had a live Bedrock call.
