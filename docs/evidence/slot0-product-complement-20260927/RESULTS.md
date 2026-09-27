# Slot-0 product-complement family: offline and blind result

The closed mapped numeric slot now has a fourth calculation: multiply two
proper fractions, then subtract their product from one. The author chooses only
the family and bounded operands `a,b` in `2..9`; code constructs the exact
expression, answer, four numeric choices, explanation, feedback, and proof.
This adds a product-and-complement decision to the existing sum-and-scale,
quotient-and-add, and reciprocal-of-sum decisions.

All 64 operand pairs have a key independently recomputed with `Fraction`, four
distinct rational choice values, complete proof-checked learner fields, and a
unique exact stem outside the preceding three slot-0 families. The isolated
80-item replay reduces slot-0 same-family pairs from 35 to 24, without losing
any exact stem. The combined current-source capacity replay, which also
includes the independent slot-2 count family, has 23/131/152 same-slot-family
pairs at 40/80/85 unique items. This structural measure is not a semantic
diversity score.

An independent reviewer saw only the locked [four-item keyless worksheet](worksheet.json)
(SHA-256 `6a93870d452fbb078d0c3e15a76da5a7ca985335f5df5f828da0cc863ddceb24`)
and [rubric](RUBRIC.md) (SHA-256
`e2a552aa28498263eb38bbef69a2548014a3f39a0e778ceec68e3e27386193d7`).
The [review](review.json) (SHA-256
`3d9b68c4cc390235447d14b416dc89b1ed1d09fdda45c6710ac96cc52abd58ed`)
selected B, C, A, B. Post-lock independent arithmetic confirms those are the
four exact keys. The reviewer judged every within-item choice pair distinct
and the items level 2 to easy level 3. It also called all six within-family
question pairs strong near-duplicates: the numbers change but the method does
not. The notation was clear but stiff and heavily parenthesized. This family
should count as one additional mechanism, not 64 different ideas.

After this family and the slot-2 count family were integrated, the combined
native schema became 2,156 bytes, SHA-256
`a6426dd4d8cdd26a7d6fb03bbd373c8d55ab1dd79c17eab48279e3a3120d201e`,
with transport name `question_author_constructed_mapped_families_v9_n5`.
That combined schema has not been sent to Bedrock. The mapped route remains
opt-in, and this offline result does not qualify an 80-item bank.
