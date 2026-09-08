# Fresh feedback error escaped immutable model review

September 8, 2026 UTC. The [predeclared two-item audit](QUESTION_FRESH_AUTHOR_IMMUTABLE_AUDIT.md)
completed both calls. It approved the CSS item's materially false explanation
without reporting an issue. It correctly rated the sound English item below the
original difficulty target. This does not qualify the auditor as a reliable
general correctness gate.

| Exact fresh item | Auditor judgment | Original minimum 3 | Independent finding |
| --- | --- | --- | --- |
| CSS Grid | Valid; all five fields supported; no issues; level 3 | Retained | False dense-packing explanation escaped |
| English conditions | Valid; all five fields supported; no issues; level 2 | Rejected for difficulty | Sound introductory item, correctly below target |

The existing factual-support run at minimum 1 retained both items. The separately
predeclared evaluation at minimum 3 retained only CSS. No complete, supported
item therefore survived at the original target. These are two selected cases,
not a production error-rate estimate. The CSS key itself is correct; the failure
is approval of false teaching content.

Both calls used Opus 4.6 with adaptive thinking, high effort and a 16,000-output-token
cap. They returned valid schemas and `end_turn`; usage was 2,848 input and 2,160
output tokens, totaling 5,008. Recorded call intervals were 16.978 and 15.602
seconds. Neither response exhausted its allowance. More tokens are not supported
as a fix for this observed failure.

## Independent execution confirms the error

After freezing the model results, a fixed local WebKit reproduction placed the
same three children with column spans two, two and one. Sparse placement produced
rows `[A, A, empty]` and `[B, B, C]`. Changing only the flow to dense produced
`[A, A, C]` and `[B, B, empty]`. Both have one empty cell. The claim that dense
packing would make “No cell is left empty” true is false.

This corroborates the prior manual deduction from the
[W3C placement algorithm](https://www.w3.org/TR/2025/CRD-css-grid-1-20250326/#auto-placement-algo).
The reproduction was written by the assistant, with fixed dimensions for measuring
cell coordinates, and executed once in local WebKit. It uses no remote content or
persistent website data. It demonstrates a useful external check for this case,
not automatic verification of arbitrary CSS questions. It does not inspect the
browser's internal placement cursor or verify the separate cursor-timing detail.

## Implication

Explicit solver and issue vetoes prevent the application from overruling declared
defects. They cannot catch a defect that every model labels supported. A stronger
model, thinking enabled, source context and full-field review still shared this
particular error. The next correctness work needs appropriate independent evidence
or execution and broader fresh-item evaluations; this result does not justify
promoting the immutable auditor alone or repeatedly tweaking its prompt against
this one example.

No content was repaired, no additional author/solver call was made, and nothing
was admitted to production. The original minimum-1 capture is unchanged; the
minimum-3 observation reuses the same responses without another call.

## Evidence

- [Exact terminal capture](evidence/fresh-author-immutable-capture-20260908.json)
- [Replay of original floor-1 decisions](evidence/fresh-author-immutable-replay-20260908.json)
- [Separate predeclared floor-3 decisions](evidence/fresh-author-immutable-floor3-20260908.json)
- [Independent bindings and semantic assessment](evidence/fresh-author-immutable-assessment-20260908.json)
- [Fixed local WebKit reproduction](evidence/css-feedback-native-check-20260908.swift)
- [Observed native cell coordinates](evidence/css-feedback-native-observed-20260908.json)
- [Native execution, derived occupancy and file hashes](evidence/css-feedback-native-execution-20260908.json)
- [Independent reproduction correspondence assessment](evidence/css-feedback-native-correspondence-20260908.json)

The capture byte SHA-256 is
`24370b8065b006f1779601ec058d5b9769e23400b808b237cb1c8bcd6929aced`.
Offline replay rebuilt the exact frozen plan and source/dependency bindings with
client creation prohibited. It checked exact request and question hashes, order,
and unchanged retained text. These checks establish recorded consistency, not
provider authenticity or correctness of its judgments.
