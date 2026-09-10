# Withholding solver reasoning did not fix reviewer correctness

The [prospective comparison](QUESTION_REVIEWER_INDEPENDENCE_PROTOCOL.md)
completed its ten calls. Both versions approved and would return the same
defective spreadsheet question. Withholding the solver records also produced
incorrect ecology feedback and a malformed final five-item review. It does not
meet the prospective criterion and is not qualified for production.

This was a distinct information-flow experiment, not another assumptions critic.
It does not establish that solver context never influences a reviewer. It shows
that removing that context did not resolve this selected failure, so neither
this removal nor a new wording of the same intervention should be promoted on
the present evidence. No runtime behavior, model default or deployment changed.

## Observed comparison

| Observation | Solver records supplied | Solver records withheld |
| --- | ---: | ---: |
| Fresh reviewer calls | 5 | 5 |
| Planned item occurrences | 12 | 12 |
| Correlated reviews available | 12 | 7 |
| Local simulated policy returns | 11 | 7 |
| Uncontested valid controls returned, of 7 | 7 | 5 |
| Clear defective spreadsheet item approved and returned | 1 | 1 |

The seven subjects with correlated reviews in both arms receive the same answer
in both. These include the defective spreadsheet item. The other five withheld
slots are unavailable due to a malformed response; they are not successful
rejections or evidence that the treatment caught their content defects.

The baseline's one policy exclusion is the ice-cream causation item, rated
difficulty 2 by the model against a request minimum of 3. It is not an
application-level factual catch. The baseline's feedback on that item remains
part of the content assessment even though the policy would not return it.

Both arms share the current native reviewer schema and a conditional instruction
about optional solver records. The older runtime subjects also receive the
current rejected-envelope instruction in both arms. Neither arm is an untouched
production baseline. The only difference within a pair is the presence of the
entire `independentSolutions` field; the solver veto itself remains enforced.

## Content findings

**The original extra-factor defect persists.** The spreadsheet stem requests
multiplying two values. Every offered formula adds a third cell operand, A3,
which belongs to the displayed quarter labels. Both fresh reviews choose the
same three-factor formula and teach an anchoring strategy for that added operand.
The actual acceptance rules return the question in both local replays. This is
not merely disagreement over whether an address's dollar signs imply an anchor;
the unrequested third factor is decisive under either reading.

**Correct keys still come with false teaching.** The withheld ecology review
chooses 75 correctly under the stated production-ratio interpretation, but its
37.5 explanation confuses multiplication by 1.25 with applying 25%, includes a
self-correction inside the sentence, and uses the wrong biomass base. Its 7.5
explanation calls a factor of 0.025 a 10% efficiency. These are distinct teaching
errors, not proof that the selected 75 is an arithmetic error. The baseline's
individual ecology distractor arithmetic is better, while its main overstates
that every distractor applies efficiency to a biomass value.

In the baseline's final batch, the Bayes question selects approximately 9%
correctly. Its 50% distractor explanation falsely says equal true and false
positives would imply approximately 50% prevalence. With sensitivity and
specificity both 99%, `0.99p = 0.01(1-p)` instead gives `p = 0.01`, or 1%.
The satisfaction-survey review turns a possible response bias into an asserted
direction and motivation: it says dissatisfied customers are systematically less
likely to respond. The supplied response counts establish neither that direction
nor actual bias. These exact teaching defects were independently identified.
Their treatment counterparts are unavailable, so they cannot support a paired
claim that withholding improved teaching on those subjects.

The independent assessor and root preserve different readings of some original
questions. The assessor requires additional assumptions for the hospital,
marble and ecology items and regards the specific ice-cream likelihood claim as
unsupported. Root's pre-response notes preserve conventional textbook readings
as plausible interpretations rather than established falsehoods. Root also
treats “tasks attempted” in an otherwise correct completion-rate explanation as
weaker wording, while the independent assessor flags it. These differences were
recorded before the final paired summary; no cases were relabeled to favor an arm.

Of the 19 correlated positive reviews, the independent assessment supports nine
complete keys/main explanations/four-choice feedback sets under its readings;
root supports eleven under its recorded readings. These are descriptive content
counts, not general accuracy, calibrated difficulty, delivery quality or learning
gain estimates. Both assessments agree on the decisive spreadsheet approvals
and the clear Bayes, ecology-arithmetic and survey-bias teaching defects.

## Format and operational evidence

All ten provider calls completed with `end_turn`, known usage and confirmed
worker/group cleanup. All ten responses satisfy the static native JSON schema;
nine pass native adaptation and exact item correlation. The final treatment
response supplies seven review records for five subjects, with indexes
`[0, 0, 1, 2, 3, 3, 4]`. A `valid:false` record also carries a meaningful answer
and feedback, which the native adapter rejects. The duplicate indexes separately
violate exact item coverage. No duplicate was selected, merged or repaired.

There are 26 raw review records, 24 planned item occurrences and 19 correlated
reviews. Preserve those denominators. The malformed five-item batch is exported
as five unavailable slots. Static schema success is narrower than a valid
application response, and the rejection is not output-token exhaustion.

Usage was 26,269 input and 6,491 output tokens. The largest response used 1,368
of its 6,000-token allowance. SDK intervals sum to 96.744330 seconds and worker
lifetimes to 104.829113 seconds; neither sum is an independently measured full
application latency. The ten requests total 105,595 serialized bytes, with a
largest request of 14,634 bytes. No retries, repairs, additional questions or
model-agreement changes occurred.

The frozen source is `040d0e53eef6e1dc516fa19bd92b7ac8cf3204ba`, with 67 bound
source files and the pinned SDK. The canonical plan hash is
`183b3a645c38cff16e8a945ad5bb66f01be4625402b2dcfb1c9cc7090520ea91`.
The terminal capture byte hash is
`49baaee19270e20afe6830881c7c06dd91266c332f7acd86d8aaad11e1e9c9ce`.
The original process handle 58234 exited zero; this run must not be restarted.

Preparation passed 82 targeted tests, including 23 new cases. An initial test
command named a nonexistent observer module; the corrected final suite passed.
One later synthetic stale-response fixture initially changed a field already
rejected by the adapter and was corrected to isolate response-hash binding.
These preparation errors involved no provider calls. Ruff and whitespace checks
passed. The independent plan audit completed after the reported launch and is
labeled accordingly; root's exact plan/source checks and tests preceded launch.
The terminal audit independently reproduced content outcomes, all nine policy
replays and the masked feedback export without provider calls or capture writes.

## Consequence for the next change

Do not remove solver evidence from the production reviewer based on this result.
Do not count the lost batch as an accuracy improvement, or repeat this same
ablation until it passes. The original stem/choices can still encourage a model
to supply the intended missing premise, and the reviewer can introduce fresh
errors while writing explanations.

The next distinct comparison should test stronger model capability using the
current complete-choice and teaching contracts before adding another LLM critique
layer. The existing Opus 5 plan is still a historical stem-only/legacy experiment;
it must be updated and bounded before treating it as that comparison. Its model
agreement remains unaccepted. Fresh generation across broader subjects and actual
normal-runtime delivery remain necessary before any promotion. The generalized
correctness objective is unresolved.

Raw captures, frozen assessments, both independent audits, reproduction helper
and the item-level paired summary are in the
[evidence directory](evidence/reviewer-independence-20260910/README.md).
