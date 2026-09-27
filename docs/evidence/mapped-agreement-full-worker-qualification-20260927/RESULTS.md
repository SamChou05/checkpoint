# Closed agreement full-worker qualification: one-shot result

**Outcome: FAIL, 3/5 original slots returned.** The opt-in agreement author
schema was accepted by Bedrock, and code constructed five well-formed questions.
The final model teaching reviewer assigned difficulty **3** to both code-owned
English items, while the request and trusted constructor assigned difficulty
**2**. The exact-target verifier rejected original slots 3 and 4. No retry,
fallback, repair, or top-up was attempted. This is evidence of a difficulty
calibration disagreement, not a five-question worker success or a deployment
qualification.

The [frozen plan](plan.json) SHA-256 is
`361aa3aa99c456285309d31cdc7f60c058061a62dd2d89e32bbadefe3063cc6d`.
The [capture](capture.json) SHA-256 is
`2bcb9b577d165b508debe70cf6d42b2cf749f006c03922650b9d154eab8ca251`.
Source commit `0e70b33` kept the prior normalized request SHA
`212cea7d53ddefe17fbe8f2459705b46b871793e62e0e58b56cc11e3626e63ae`:
three exact arithmetic slots followed by two English slots. The only new route
flag was `QUESTION_MAPPED_AGREEMENT_TASKS=enabled`. The Sonnet 4.6 native/high
transport, no-fallback setting, six-call ceiling, and 240-second job deadline
were pinned. The new 2,701-byte schema SHA is
`2e2508e3c7944a0b51246e6fa5febcdd57b84c0003ae81315f36c1107cdbbb6c`.
The source and harness passed seven socket-free capture tests and 1,394 backend
tests; those checks did not exercise Bedrock grammar acceptance.

The single live job used three Converse calls: author (49.261 seconds),
answer-blind solver (38.845 seconds), and authored teaching reviewer (39.716
seconds). It finished in **128.485 seconds** and reported 10,450 input and
8,840 output tokens. All five original slots passed the local sanitizer. The
solver examined the two agreement items; the numeric keys came from local
proof. The final reviewer marked all five valid, supported and issue-free,
but rated the three numeric items 2 and the two agreement items 3. The final
quality counts were three accepted and two `review.difficulty_target`.

Two independent reviewers locked answer-blind reviews before the source slots,
keys, author teaching, and model difficulty ratings were revealed. The
prespecified [returned-output worksheet](returned-worksheet.json) SHA is
`3a99a17dc43296e4a9c857d4c19042fa891e79d487bccd059a6c7ad8241ccb84`;
it showed three readable questions and two explicit unavailable placeholders.
[Review A](returned-review-a.json) SHA
`144f4210d0eec20a5aaae3f5b6e4f8fbe9c67075ba3b70364b9c2125c231c43a`
and [review B](returned-review-b.json) SHA
`d3102ecb4b64b4c95c3b39ac44c4d4f6d4ee2ee2050c50fb803694180a04e76d`
both selected the explicit keys for the three readable rows, judged all six
choice pairs distinct in each, and rated each difficulty 2. This does not
change the official three-of-five denominator.

A separately labeled **post-hoc diagnostic** [worksheet](diagnostic-worksheet.json)
showed all five pre-review sanitized candidates, with new random IDs, order
and display-choice permutations, while hiding keys and model decisions. Its
SHA is `549796ba59e8593dfbd3db4d74862c46666771411c97caab2b52ee42d81c4b2c`.
[Diagnostic review A](diagnostic-review-a.json) SHA
`d38e61b4fbf937cc7b1997519554cbc835ed69a37d8f18bbd19bb4544423b4d1`
and [diagnostic review B](diagnostic-review-b.json) SHA
`4180ab667c8c41e0079fd63a118a292a798e19d6c553cafc5dc76cb533889b15`
both selected the code-owned answer for **all five**, found every item
self-contained, judged all six pairs distinct within each item, and rated
each item difficulty 2. The [private returned map](blind-private-returned_output.json)
and [private diagnostic map](blind-private-pre_review_diagnostic.json) were
opened only after all four reviews were locked.

| Original slot | Mechanism | Code-owned key | Model reviewer difficulty | Worker return | Both diagnostic reviewers |
| --- | --- | --- | --- | --- | --- |
| 0 | Exact fraction addition then multiplication | `38/3` | 2 | Returned | Key correct; level 2 |
| 1 | Exact fraction subtraction then division | `46` | 2 | Returned | Key correct; level 2 |
| 2 | Maximum integer satisfying a linear inequality | `9` | 2 | Returned | Key correct; level 2 |
| 3 | Singular and plural heads with intervening `near` phrases | `plans; prepare` | **3** | **Unfilled** | Key correct; level 2 |
| 4 | Distributive `Every guest` and compound `Maya and Theo` subjects | `receives; prepare` | **3** | **Unfilled** | Key correct; level 2 |

Independent local recompilation of the captured typed numeric specifications
and the two enumerated agreement tasks reproduced all five exact learner
fields: stem, four choices, literal key, main explanation and per-choice
feedback. The agreement explanations identify both head subjects and explain
why the tempting nearby noun does not control agreement; their feedback
checks each blank and is safe under choice shuffling. The numeric main
explanations and keys are sound. Exact-value distractor feedback is correct
but often only states that the selected number is not the computed answer.
No author explanation referred to a display answer label. The English items
fit the assigned subject-verb agreement objective and the numeric items fit
the assigned exact arithmetic or bounded-condition objective.

The blind reviewers also noted limited novelty within the two fraction
evaluation items and within the two two-blank agreement items. The English
items apply different agreement rules, but their shared answer format could
become predictable in a larger bank. The reviewers were not shown the
external objective, so their objective-fit judgments were limited to the
skills visible in the stems; the exact assignment was checked separately
against the frozen request and code-owned provenance.

The discrepancy supports investigating whether a final model difficulty
rating should veto a locally proven, closed level-2 task. That is a separate
source change requiring its own review and fresh qualification; this failed
trial does not authorize an override. The route remains opt-in and inactive in
the deployed worker. No additional provider call was made after this capture.

The archived harness pins candidate commit `0e70b33` by Git ancestry and
source hashes. Its seven socket-free tests pass on the isolated trial branch;
the ancestry guard intentionally fails on main, where the same source change
was cherry-picked under a different commit ID. This capture is historical
evidence, not a harness for current-source reruns.
