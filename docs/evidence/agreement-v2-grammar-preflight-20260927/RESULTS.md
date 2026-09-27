# Closed agreement frames: keyless offline preflight

This is an **offline design check, not a worker qualification or rollout**. It
assesses the 16 grammar stems rendered by isolated candidate `8628911` (four
proximity scenes and four compound/`every` scenes, each in two clause orders).
The candidate was still under source review when these worksheets were made;
later fixes must be checked against the final source before a live trial.

The [worksheet](worksheet.json) hid the keys, scene identifiers, source slots
and teaching. It showed each stem with four deterministically shuffled choices
and a level-2 rubric. Its SHA-256 is
`7831c8ad623c89098692dd67c5c90c7c043aeb84fd1fa1ea7853a1224925c6c6`.
Two fresh independent reviewers received only that file and locked their JSON
reviews before the [private map](private-map.json) was opened. The map SHA-256
is `8e5ce9d854599f64fb0a95797ba1b66aeedc7248bf921faf0215ae7030fc6912`.

| Review | SHA-256 | Key matches | Standalone level 2 | Distinct within-item pairs |
| --- | --- | ---: | ---: | ---: |
| [A](review-a.json) | `d35ba5a09d05d3ed18bda9696911ba238bba394ad521b374a7334766120c5ba6` | 16/16 | 16/16 | 96/96 |
| [B](review-b.json) | `2e6f3bb31b24d177f79ed00b58338feec9a56c82a2780ef72a51d4a9cffc4c04` | 16/16 | 16/16 | 96/96 |

Both reviewers found a single defensible key in every item. A separate source
review found the clauses, agreement explanations and choice feedback sound, with
all bounds satisfied. This improves the case for the harder compound frames;
the prior live worker's simple compound/`every` stem was rated level 1 by both
blind reviewers. It does **not** prove that the model will emit the new schema,
that the full worker will return all assigned slots, or that students will
experience the same difficulty.

Both reviewers also flagged limited bank novelty. There are eight underlying
scenes and each appears twice with clause order reversed, all using nearby-noun
attractors. Repeated exposure can make later questions feel like recognition
even though each standalone stem was rated level 2. The isolated candidate's
history selector initially missed older bank items because the generation
request carries only the latest 30 prompts, whereas bank deduplication uses
all stored items. That bug blocks promotion until corrected and retested.
