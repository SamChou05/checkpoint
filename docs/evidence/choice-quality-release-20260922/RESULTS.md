# Reviewed twenty-case qualification: failed

All four native calls completed with valid strict JSON, native schema, exact choice
identity, complete four-choice/six-pair coverage, and normal completion. The
candidate rejected all ten defective items but retained only eight of ten valid
items. It therefore failed the criteria frozen before dispatch. No retry, repair,
replacement call, relabeling, or mutation of the frozen plan/capture occurred.

| Measure | Observed | Frozen requirement |
| --- | ---: | ---: |
| Structurally valid completed calls | 4/4 | 4/4 |
| Valid items retained | 8/10 | 10/10 |
| Defective items excluded | 10/10 | 10/10 |
| Defective items excluded for expected reason | 9/10 | 10/10 |
| Individual correctness judgments | 77/80 | 80/80 |
| Pair relation labels | 120/120 | 120/120 |
| Uncertain correctness/pair labels | 0/0 | 0/0 |
| Items matching every gold judgment and veto | 17/20 | 20/20 |

The two valid items falsely excluded were `membrane_water_direction` and
`essay_submission_fraction`. The defective `meeting_time_duplicate` was excluded
for zero supported choices instead of its correctly detected equivalent options.
All three errors were a typed correctness label that contradicted its own reason:

- `membrane_water_direction`: the correct A-to-B water flow was labeled `refuted`,
  while its reason worked through lower-to-higher salt concentration and ended
  “This is supported.” Its four labels produced `solver_zero_supported`.
- `meeting_time_duplicate`: the correct 9:45 a.m. was labeled `refuted`, while its
  reason explicitly computed 9:10 + 35 = 9:45 and ended “Supported.” The resulting
  `solver_zero_supported` took precedence over the duplicate-pair veto.
- `essay_submission_fraction`: the wrong 2/3 option was labeled `supported`, while
  its reason corrected itself to 18/24 = 3/4 and ended “Refuted.” With 3/4 also
  supported, this produced `solver_multiple_supported`.

These contradictions are directly visible in the unmodified raw responses and
expanded failed-item records in [summary.json](summary.json). The 120/120 pair
result measures relation labels, not every word of their explanations: one pair
reason incorrectly calls 2/3 correct while still correctly labeling the pair
as distinct.

## Serialization hypothesis for a separate prospective experiment

Every one of the 80 choice objects appeared in raw output order
`choice → judgment → reason`. Every one of the 120 pair objects appeared in order
`leftChoice → reason → relation → rightChoice`. The native schema's serialized
properties use that same alphabetic order. Thus all three incorrect correctness
labels preceded self-correcting reasoning, while pair reasons preceded relation
labels. This observation motivates a reason-before-judgment intervention; it is
not evidence that property ordering caused the errors or will repair them.

A separate paired plan will preserve the same prompt, reviewed gold, exact input
batches, model and settings, and alter only choice-row schema property/required
order. That experiment will record actual response ordering and cannot replace
these four calls in any denominator.

## Cost, provenance, and limits

| Call | Input tokens | Output tokens | Elapsed seconds | All-gold items |
| --- | ---: | ---: | ---: | ---: |
| 0 | 2,028 | 2,122 | 18.600 | 5/5 |
| 1 | 2,061 | 2,203 | 21.739 | 5/5 |
| 2 | 2,071 | 2,687 | 28.296 | 3/5 |
| 3 | 2,043 | 2,157 | 21.220 | 4/5 |
| Total | 8,203 | 9,169 | 89.855 | 17/20 |

Usage has no cache-read or cache-write tokens. Elapsed times are summed client
call durations, not a measured end-to-end application latency. No dollar price is
assumed. Model: `us.anthropic.claude-sonnet-4-6`, temperature 0.2, thinking disabled,
maximum 6,000 output tokens, 75-second read timeout, one SDK attempt. No output was
truncated. Gold keys were used only by local scoring, never sent to the model.

The independently reviewed packet SHA256 is
`d6263949701e1486036aa16a09c7348f478d180349a327c08fcd973485d4e305`.
The frozen plan file SHA256 is
`fb2b3538f1dea96d823397885cb3ac478c576dbbad067ace1b311a09bd1920c8`.
The capture file SHA256 is
`736b66c2e6407eea418c6c286c0f9fdf405c0f7399f91fdd74d549fcf1365f65`.
The archived candidate SHA256 is
`9473291262cdf0aee9068a93138c1487e80252cbf9efbdce839840dc68b56d87`.

This was one response per fixed five-item batch, not broad accuracy, repeated-run
stability, or live author-generation qualification. The earlier unit-word
control's failed result remains unchanged. This suite prospectively distinguishes
irrelevant wording changes from meaningful differences in the requested answer,
as documented in [the rubric](RUBRIC_AND_PLAN.md) and
[independent gold review](INDEPENDENT_GOLD_REVIEW.md).

Recompute counts without provider calls:

```sh
python docs/evidence/choice-quality-release-20260922/summarize_qualification.py
```
