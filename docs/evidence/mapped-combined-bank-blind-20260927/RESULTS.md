# Combined mapped repertoire: answer-blind first-three-batch review

**Result: 15/15 correct displayed keys in two independent reviews, but four
strong near-duplicate pairs by consensus.** This is an offline sample from the
first three five-item refills of source `847584de1ea5c2b3b7147f181c52ec8cd83296ba`,
after the numeric and slot-3 English repertoire expansions. It uses the saved
five-task source seed, current code-owned compilers, recent-30 prompts, and
full-bank variant history. No model, worker, queue, or bank call ran.

The [preparation script](prepare.py) pins that source commit and checks the
recreated [answer-hidden worksheet](worksheet.json) against the archived
bytes. Displayed choices and item order were shuffled deterministically.
Reviewers A and B saw only the worksheet and locked [review A](review-a.json)
and [review B](review-b.json) before the [private mapping](private.json) was
opened. The [post-lock audit](audit.py) verifies file hashes, every displayed
key against the hidden code-owned answer, and the overlap judgments. Both
reviewers selected all 15 keys and found every item self-contained with
meaningfully distinct choices. Reviewer A rated three items difficulty 3,
and reviewer B rated eight items difficulty 3, against the worksheet's
requested level 2. Reviewer A found some fraction distractors less plausible
despite being distinct.

Both reviewers marked the same four pairs **strong** near-duplicates:
`B01/B07`, `B01/B12`, `B07/B12`, and `B10/B13`. The first three form a
paired-agreement cluster. `B07` is original English slot 3, while `B01` and
`B12` are slot 4; a per-slot family counter misses that cross-slot overlap.
The numeric `B10/B13` pair is the same bounded-maximum decision with different
expressions, showing that different code-owned family names can still ask
essentially the same question. `B01` and `B12` come from different batches;
`B10` and `B13` do too. Both reviewers also recorded moderate overlaps.

The structural [capacity gate](../../MAPPED_BANK_CAPACITY_GATE.md) is useful
for exposing finite inventories, but it cannot certify semantic distance.
This first-three-batch sample reinforces the need for a cross-slot and
cross-family mechanism review over the full bank before qualification. It
does not estimate a general model success rate: the source tasks are frozen,
the questions were compiled offline, and the actual author, solver, and
reviewer worker did not run. The mapped route remains opt-in.

SHA-256: worksheet `2150bc0f199789e7a6a9345ea44912fb8c1d9b843c688f904e8f4f3dc5bedf85`;
private mapping `d9e30f23237275b5ac1608110509c069d0e4cff8a1642588a0f0876c9980265c`;
review A `3171efc7ee3fa5a3e169016018b6438630a6e14f5272cdbf9b0329d2f0b999ef`;
review B `add45083dd8403c6c604d866e168b4032b6ad3d193891b4c331dadaa4d946525`.
