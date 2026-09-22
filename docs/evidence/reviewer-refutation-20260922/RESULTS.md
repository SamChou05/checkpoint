# The refutation paragraph was not qualified

The trial stopped after two of four planned calls. The baseline returned the six
familiar reviews with exact indexes. The candidate returned seven rows for those
same six items, duplicating index 0. Strict validation rejected that whole batch.
Both prospective-control calls remain unattempted, and the full planned denominator
remains 24 logical item reviews (twelve per arm). No retry, deduplication, reindexing,
replacement or extra call was performed. The candidate paragraph is not promoted.

Both returned responses were native-schema-valid and ended normally. This again
separates native JSON shape from exact request identity: v1 permits an array with
repeated integer indexes. The candidate's two index 0 objects are identical, but
that does not authorize dropping one. Its observable raw content can be audited
for diagnosis; it receives no successful stage or completed-trial semantic credit.
A separate count-bound contract fixes that structural class, but it was not part
of this intentionally one-paragraph comparison.

| Frozen call | Seconds | Input/output tokens | Observed outcome |
| --- | ---: | ---: | --- |
| Familiar baseline | 16.192 | 3,573/1,422 | Six rows, exact 0–5 coverage |
| Familiar candidate | 19.989 | 3,612/1,823 | Seven rows, indexes 0,0,1,2,3,4,5 |
| Prospective candidate | — | Not dispatched | Unattempted by stop rule |
| Prospective baseline | — | Not dispatched | Unattempted by stop rule |

Total observed usage was 7,185 input and 3,245 output tokens (10,430 total). Both
attempted responses returned usage, so there is no unknown usage from an attempted
call. Unattempted calls incurred no dispatch or reported usage. Total provider time
was 36.181 seconds. No timeout, truncation, SDK retry or reasoningContent block was
observed. The read limit remained 75 seconds and SDK total attempts remained one.

The candidate raw text still accepted both nonunique familiar items. It explicitly
acknowledged 26 rides meets the cheaper-pass condition, then claimed the unchanged
question asks for a minimum. Its grammar review again imposed the conventional
semicolon-before-however pattern as an exclusive rule. Its paint feedback still
claimed 15 liters blue and 9 liters white imply 3:3/equal parts, despite the correct
5:3 ratio. These observable defects prevent a semantic-success claim even aside
from the duplicated index. Its weighted-grade feedback also begins by attributing
82.4 to swapped weights, then computes 81.6 and acknowledges the mismatch. Correct
arithmetic later in that sentence does not make the opening explanation sound.

Independent output review inspected every original row and all sixty-five
main/choice explanation strings. The baseline had two full-content passes, three
failures and one uncertainty counted as failure. The candidate raw rows had one
content pass, five failures and one uncertainty, including the repeated bus row.
These candidate row-level observations are diagnostic only: they are not a repaired
six-item batch, valid-stage credit or a completed-trial semantic score.
No unattempted prospective case is counted as passed or failed on its content.
The new packet's synthetic solver fixtures were never sent. Its independently
approved gold and provenance remain frozen for any separately authorized future
experiment; this result supplies no held-out validation of the paragraph.

`plan.json` SHA256:
`39ed2eaf1cc1e543908bc3984d44142fc3d8dd9a044f527da1be57db22cd9f6a`.
`capture.json` SHA256:
`e6e47e32267709470196700d86d588f9b167a634ffaa8d952aba753bf0940ea2`.
`summary.json` separates raw row counts from strict batch/decision assessments.
`independent-output-audit.json` records the independent diagnostic content review.
The capture keeps its original stopped_after_failure status and bytes unchanged.

Ten no-network tests passed before dispatch. `replay-checks.json` records an exact
zero-network rebuild of the frozen plan, both requests, original native parsing,
baseline assessment and candidate duplicate-index stop. The other two calls stay
unattempted during replay. Archived validators prevent evolving production code
from changing these results; no main-source freeze or production edits were needed.
Ruff and diff checks passed. This selected, stopped comparison does not establish
that the paragraph caused the duplication, that it improves arbitrary content, or
that the unattempted six-item prospective batch would pass.
