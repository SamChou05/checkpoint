# Slot-4 correlative agreement: blind content check

**Eight of eight displayed keys matched in both independent answer-blind
reviews, but the wording remains formulaic.** Source commit
`0d28a099b0aa8bafd1e815222907b8e0e82082cc` adds a closed either/or and
neither/nor family to English slot 4. The [preparation script](prepare.py)
compiled all four scenes in both clause orders, shuffled the choices and item
order, and locked the [answer-hidden worksheet](worksheet.json). Reviewers
received only that worksheet and wrote [review A](review-a.json) and
[review B](review-b.json) before the [private keys](private.json) were opened.
The [audit](audit.py) verifies hashes and all 16 reviewer key selections.
No model, worker, or bank call ran.

Both reviewers found one correct choice and four meaningfully distinct choices
in every item under standard written American English. This agrees with the
[Chicago Manual of Style's rule](https://www.chicagomanualofstyle.org/qanda/data/faq/topics/Usage/faq0420.html)
that an or/nor verb agrees with the last-named subject. Chicago also notes
that mixed singular/plural coordination can sound awkward. Reviewer A rated
naturalness 3/5 for four items and 4/5 for four; reviewer B rated all eight
3/5. Both identified four pairs that reuse the same clauses in reverse order.
One reviewer noted that “arrange the returns” in the library scene sounds
slightly unnatural.

The [offline capacity harness](../../MAPPED_BANK_CAPACITY_GATE.md) now reaches
85/85 unique exact stems and leaves seven unused slot-4 variants there. It
reports 35, 175, and 200 same-slot/family pairs at 40, 80, and 85 items,
respectively. These improvements do not establish that the items are
semantically different enough for a full learner bank: the order reversals
count as different exact stems, and the strict family-use gate still fails.
The route stays opt-in pending live provider, worker, and full-bank content
qualification.

SHA-256: worksheet `0a4d6417329fb1924d797dbd846bb0511478812f6bcbc58afe28aafc9d775ca6`;
private `3adfb9a6fbb4a31148a05750e99a9d9cf4cc1eabbcab22dcacee1ebb274e4571`;
review A `256d0ddfa3952aae84e83ed112551912b5d46f209ccffdfa976c9ab7fa2095f3`;
review B `cc42114c410d1b9acc3655778d8069cf466a187fc56912db1e457886c8d0797d`.
