# Source-supported solving and corrected recall assessment

> **Completion correction:** policy 6/7 also lost learned facts supplied in goal/skill prose. It is superseded by [subject-reference policy 8/9](QUESTION_SUBJECT_REFERENCE_POLICY_20260912.md). The final three-call control brings this phase to 48 calls; the 45-call counts below describe the earlier milestone.

This replaces the displayed-only proposal in PR #9. Checkpoint supports uploaded
study materials and private subjects. Recalling a learned fact does not require
printing that answer in the stem. The prior four source-hidden controls measured
source dependence; they did not prove four defective questions or false accepts.
The original traces are preserved, and those claims are withdrawn.

## Matched evidence

The [frozen controls](../backend/bedrock-question-service/evals/fixtures/source_recall_boundary.json)
contain four domains, each with two valid source-recall/application items, one
item missing essential case data, and one fully stated control. Both arms used
Sonnet, native output, unchanged author drafts and the existing final reviewer.
Only solver input and its source/case responsibility changed. All eight actual
solver/reviewer pairs were read, including rejected items and final feedback.

| Domain | Independent source/case assessment | Displayed returns | Source returns | Seconds displayed → source |
| --- | --- | --- | --- | --- |
| Luma arithmetic | Blue=3; 4 blue + 1 red = 14. Four unspecified-color tokens could total 8 through 12. | 1/4 | 3/4 | 11.436 → 15.389 |
| Rho programming | First index=1; 4 @ 3 = 2×4+3 = 11. An unspecified index into [7,12,19] has no unique element. | 1/4 | 3/4 | 13.486 → 14.747 |
| Zali language | Noun naro=river; forest=pali. Without grammatical context, naro could be river or flows. | 1/4 | 3/4 | 10.596 → 13.287 |
| Lumen handbook | Vale=Tuesday; Mira handles paper. An unidentified one of two museums does not fix its opening day. | 0/4 | 3/4 | 8.627 → 11.543 |

Source-supported solving retained **8/8 valid source items**, compared with **0/8**
in the displayed-only arm. Both blocked **4/4 missing-case items**. Fully stated
controls returned 4/4 versus 3/4; the Lumen reviewer gave no reason for its veto,
so its cause is unknown. These separate-subject controls also have a possible
scope interpretation; do not treat that extra return as a proven scope repair.
Each arm used eight calls, sixteen total. These are single draws, not a latency
or error-rate distribution.

The source arm returned 12 items, but not twelve flawless lessons. Its amber-token
distractor explanation falsely says no arithmetic using 2 and 7 yields 9, although
2+7=9. Source solver reasoning also remains fallible: the ambiguous Zali item has
one unjustifiably supported interpretation, while another uncertain choice blocks
admission; a Luma reason labels an impossible option uncertain. Keys, judgments,
and teaching quality must be assessed separately.

[Plan and exact trace inputs](evidence/correctness-continuation-20260912/source-recall/plan.json)
record the experimental source arm using historical revision 2, rather than
pretending it had already implemented the new production policy.

## Runtime contract and provenance

The independent solver receives exact topic, stem and choices, plus study sources.
It receives no author key/feedback, goal directives, skill-map or objective prose.
The tested system instruction distinguishes learned source facts from example-
specific data and prohibits borrowing another item's case. Author instructions
now distinguish learned recall from missing case data. Final review is unchanged.
No semantic filter, retry, model switch or extra call is added.

Policy 6 identifies successful source-supported complete-choice solving and final
review. Policy 7 adds the existing opt-in authored-teaching contract. Historical
reference and displayed paths retain 1/2/3 and 4/5 respectively. Wire version stays
1. The client requires 6 for fresh verified practice and preserves old attempts,
keys, content and stamps without regrading or relabeling them.

Release API claim support and every generating worker **before** an app requiring
6; otherwise the client cannot refill from older inventory. This investigation
has not deployed the branch or changed learner inventory. The separate native
verification setting remains opt-in after bounded qualification; it allows legacy Nova
authoring and native Sonnet verification in the same request.

All 1,068 backend tests and seven focused iOS policy/history tests pass.
Offline checks cover exact source and literal preservation, hidden-intent
exclusion, solver veto propagation, current/historical provenance, authored and
reviewer-written contracts, both transports, budgets, storage and client history.
Fresh qualification returned all four private-handbook recall items across both
authors. See the [final results](QUESTION_CORRECTNESS_CONTINUATION_RESULTS_20260912.md)
for broader failures and yield. Retaining the sources fixes the demonstrated false-rejection mechanism; it does not establish
general semantic correctness or solve false teaching.
