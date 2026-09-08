# Two fresh author responses: correct keys, incomplete teaching quality

September 8, 2026 UTC. The [separate author-only diagnostic](QUESTION_AUTHOR_LATENCY_PROBE.md)
completed both preselected requests. Both keys were independently judged correct,
but the CSS item's feedback contains a false counterfactual and the English item
is easier than the requested minimum. Neither is qualified inventory: no solver
or immutable auditor ran in this diagnostic.

| Exact request | SDK interval | Input / output tokens | Independent content finding |
| --- | ---: | ---: | --- |
| CSS Grid placement | 37.37 s | 1,233 / 2,415 | Unique correct key; materially false distractor feedback; difficulty 3 |
| English conditions and scope | 25.61 s | 1,084 / 1,413 | Unique correct key and supported feedback; difficulty 2, below the requested 3 |

The two calls used 6,145 observed tokens in total. Both stopped with `end_turn`,
returned the complete author schema, and met all current stem, choice and feedback
limits. There was no observed token exhaustion or field overflow. Worker lifetimes,
including startup and client creation, were 38.29 and 26.56 seconds; both workers
and their process groups were cleaned up normally.

## What the timing establishes

The model, high effort, adaptive thinking, 16,000-output-token cap and exact
request bodies were unchanged. Only the offline read window increased from
100 to 300 seconds, with an added process deadline. Both observed SDK intervals
were below 100 seconds. The original timeout remains unexplained; these calls
do not demonstrate a latency benefit from the larger window or recover the
original request's unknown content and usage. SDK elapsed time is distinct from
socket read inactivity. The CSS call repeats a previously attempted request in
a new diagnostic; it is not an independent accuracy sample or a resumed trial.

## Correct answer keys do not establish correct teaching

Two assistant assessors first received the exact stems and choices with authored
keys, difficulty labels and feedback withheld. Their written judgments were
frozen before those fields were opened. Both selected the same unique keys and
rated CSS at level 3 and English at level 2. They knew the experiment and its
requested challenge; this was not a naive human panel or calibrated difficulty
study. Distractor plausibility is qualitative, not measured learner behavior.

The CSS item correctly keys “Row 1, column 3” for sparse placement of three
children spanning two, two and one columns in a three-column grid. However,
the feedback for “No cell is left empty” claims that answer would become true
with dense packing. Applying the published placement algorithm gives these rows:

| Placement mode | First row | Second row |
| --- | --- | --- |
| Stated sparse mode | A, A, empty | B, B, C |
| Feedback's dense counterfactual | A, A, C | B, B, empty |

Dense packing moves the gap; it does not eliminate it. This is a manual deduction
from the [W3C placement algorithm](https://www.w3.org/TR/2025/CRD-css-grid-1-20250326/#auto-placement-algo),
not a native browser execution. A separate feedback field also compresses the
cursor timing imprecisely while giving the correct final placement. The assessment
records that lesser issue separately from the material false claim.

The English item correctly distinguishes a necessary condition from a sufficient
one and preserves the weekend restriction's scope. All five teaching fields are
supported under the stated permission-rule interpretation. It directly applies
one familiar condition, however, so both assessors rated it level 2 despite the
author's level-3 label. It is useful introductory practice, but does not demonstrate
the requested increase in challenge.

Across ten teaching fields, the field-level assessment records eight supported,
one qualified and one materially unsupported. One of two complete items is
supported; zero satisfy both complete content support and the requested minimum
level 3. These are observations about these two exact outputs, not a production
error rate or evidence about learning gains.

## Consequence for the next change

Increasing output allowance is not supported by these observations: both outputs
finished within their allowance. The concrete gaps are feedback correctness and
challenge assessment. Test the immutable auditor against these unchanged fresh
items before counting its earlier stress-test results as general success.

Separately, the complete-choice solver adapter now requires an explicit judgment
for every option and derives zero-answer, multiple-answer, uncertainty and key
disagreement vetoes in code. That addresses the old free-prose-to-key handoff;
it cannot establish that a confident model judgment or its explanation is true.
It is not yet connected to generation. No production model, timeout, deployment
or verification policy was changed by this diagnostic.

## Preserved evidence

- [Frozen two-call plan](evidence/author-latency-plan-20260908.json)
- [Unchanged terminal capture](evidence/author-latency-capture-20260908.json)
- [Independent request, timing and cleanup audit](evidence/author-latency-binding-audit-20260908.json)
- [Key-hidden assessment input](evidence/author-latency-blind-input-20260908.json)
- [Root's frozen first assessment](evidence/author-latency-root-blind-assessment-20260908.json)
- [Second assessor's frozen first assessment](evidence/author-latency-blind-assessment-20260908.json)
- [Exact-text feedback assessment](evidence/author-latency-feedback-assessment-20260908.json)
- [Byte hashes and original artifact locations](evidence/author-latency-artifacts-20260908.json)

The operational audit rebuilt the frozen plan from source
`7e6b7ed348884f90dfa58c566b5ae884ce272340`, verified 28 source hashes and the live
dependency versions, and checked exact request/response bindings and content
observations. Those checks establish recorded execution consistency, not provider
authenticity or subject accuracy. All six assessment/capture files are archived
byte-for-byte; paths inside them retain their original assessment-time locations.
