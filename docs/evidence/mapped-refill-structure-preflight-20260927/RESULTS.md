# Combined mapped first-refill offline preflight

**Outcome: keys/choices pass; difficulty improves; variety fails.** A frozen
five-slot fake-author fixture was compiled twice, first against an empty bank
and then with the first five prompts in history. No Bedrock calls, production
bank writes, or worker return occurred. Each ten-item worksheet mixed the
initial and refill questions in random order, shuffled choices, and hid its
answer/origin map until two independent reviews were saved.

| Blind finding | Initial source `e505d47` | Refined source `f48440e` |
| --- | ---: | ---: |
| Reviewer A/B match to code-owned keys | 10/10; 10/10 | 10/10; 10/10 |
| One answer, four distinct meaningful choices, self-contained | 10/10; 10/10 | 10/10; 10/10 |
| Items rated at least difficulty 2 | 9/10; 9/10 | 10/10; 10/10 |
| Strong near-duplicate pairs in ten-item bank | 2; 1 | 3; 2 |
| Strong old/new pairs both reviewers named | 0 | 1 |

The original level-1 item was a two-step linear equation. The source change
made that family require distributing and collecting the variable on both sides.
It also changes the second operand when a refill switches numeric family, so
the earlier and later tasks do not preserve the identical domain and answer
boundary. These changes lifted the blind difficulty ratings in this small
fixture. They did **not** meet the zero-strong-overlap bank-variety gate: both
reviewers still treated the original ratio-minimum and refill quadratic-maximum
items as the same bounded threshold decision. Both also paired the two initial
English questions, despite their different grammar details. Reviewer A further
paired the two exact-fraction evaluations. A fixed 3:2 allocation with two
solve mechanisms per slot cannot supply fresh structure over a 40/80-item bank.

The initial [worksheet](initial-worksheet.json) SHA-256 is
`9920b8c37fce709d887253c44d7961034f4fba2dc396045973a93a66537bf525`.
Its separate [private map](initial-private.json) and locked
[review A](initial-review-a.json) / [review B](initial-review-b.json) are
preserved. The refined [worksheet](refined-worksheet.json) SHA-256 is
`578911da059e6312c5847f1e8a521ae88a3405d85d5325daee0f4b60c2546a81`.
The [private map](refined-private.json) and locked
[review A](refined-review-a.json) / [review B](refined-review-b.json) were joined
only after both reports were written. Both reviewers picked all ten keys in
both worksheets. [Reproduction script](make_refined_worksheet.py) checks the
exact refined worksheet and private bytes from source `f48440e`; the first
worksheet is retained as a frozen predecessor artifact.

The integrated backend suite passed 1,434 tests after refinement. One full
run had an unrelated local process-group-cleanup timing failure; that test
passed alone, and the complete suite passed when rerun on the stable tree.
Ruff and `git diff --check` passed. This preflight is only source and blind
content evidence. The prior [live refill](../mapped-refill-qualification-20260927/RESULTS.md)
timed out at the model reviewer and returned zero verified questions. The
mapped route remains disabled, and its new source has not passed a live
repeated-bank worker qualification.
