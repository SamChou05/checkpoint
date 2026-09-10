# Normal-workflow comparison finds sparse delivery and a separate format bottleneck

The [prospective comparison](QUESTION_DELIVERED_QUALITY_PROTOCOL.md) completed on
September 9, 2026 (Pacific time). Six normal five-question operations returned
seven questions from 30 requested slots. Both teaching approaches produced one
returned question meeting every frozen joint content criterion, including the
requested cognitive difficulty. Neither filled a five-question request.

The six spreadsheet keys are supported by both independent assessments. The
remaining ecology key depends on a convention the assessors found unclear; it
is not a demonstrated arithmetic error. Four spreadsheet questions were
assessed at difficulty two despite being returned with difficulty three.
This selected run therefore establishes neither a
general correctness fix nor sufficient useful inventory at the requested level.

## Delivered quality and coverage

The reviewer-written mode authors new main and choice feedback during final
review. The authored-solution mode audits and preserves the author's main and
returns no choice-specific feedback. Both used the existing Kimi K2.5 author,
Sonnet 4.6 verification, disabled thinking, 6,000 output tokens, temperature 0.2,
normal repairs/top-offs and at most six calls per operation. These are different
fresh drafts under paired goal/source contexts, not the same drafts reviewed
twice. The three selected goals have appeared in earlier experiments.

| Observation | Reviewer-written | Authored solution |
| --- | ---: | ---: |
| Requested slots | 15 | 15 |
| Runtime returned, bank claimed, app retained | 4 | 3 |
| Supported key and premises, both assessors | 3/4 | 3/3 |
| Complete supported displayed teaching, both | 2/4 | 3/3 |
| Complete useful item at assessed difficulty ≥3, both | 1/4 | 1/3 |
| Jointly useful items per requested slots | 1/15 | 1/15 |
| Requests with five returned / five jointly useful | 0/3 / 0/3 | 0/3 / 0/3 |
| Provider calls | 15 | 14 |
| Known input / output tokens | 31,363 / 15,652 | 29,613 / 17,855 |
| Raw author occurrences across initial and top-off calls | 27 | 35 |

The supported-key row is a conservative joint-assessment count, not an observed
numerical-error rate. Assessor A supported complete teaching in 3/4 reviewer-written
returns; assessor B supported 2/4. Their disagreement concerns q06's wrong-choice
rationale. Both supported all three authored-solution explanations. The complete
useful-item counts agree because q06 is also below the requested difficulty.

| Goal and operation order | Reviewer-written returns / useful | Authored-solution returns / useful |
| --- | ---: | ---: |
| Spreadsheet references; reviewer-written first | 3/5 / 1 | 3/5 / 1 |
| Map scale/resizing; authored solution first | 0/5 / 0 | 0/5 / 0 |
| Food-web energy; reviewer-written first | 1/5 / 0 | 0/5 / 0 |

Precision is undefined for the empty returned sets. Their zero coverage does not
demonstrate perfect filtering. All six operations were attempted; there were no
unattempted operations or provider failures. With one jointly useful return per
arm, calls and known tokens per useful return equal the respective totals above.
This is not a production cost or latency estimate.

## Content findings and remaining uncertainty

| ID | Mode | Finding |
| --- | --- | --- |
| q01 | Authored solution | Correctly derives two mixed references from gradebook input relationships; complete main, plausible distractors, assessed difficulty 3. |
| q02 | Reviewer-written | Correctly anchors a commission rate column and sales row; complete main and all choice feedback, assessed difficulty 3. |
| q03 | Reviewer-written | Correct fixed-column budget reference and feedback; direct application of one rule, assessed difficulty 2. |
| q04 | Reviewer-written | Intended calculation 300 × 25% = 75 is correct under a biomass-production-ratio interpretation. Both assessors withheld unconditional support because the energy/biomass convention is unclear. One feedback string calls a grams-per-area-per-year quantity energy production. |
| q05 | Authored solution | Correct copied formula and full displacement explanation; direct rule application, assessed difficulty 2. |
| q06 | Reviewer-written | Correct copied formula and main. Assessors disagree whether the unanchored distractor's feedback makes an unstated counterfactual. Both assess difficulty 2. |
| q07 | Authored solution | Correct leftward copy and full displacement explanation; direct rule application, assessed difficulty 2. |

All seven are goal-relevant under both assessments, and none has a positional
reference that fails when choices are shuffled. The six spreadsheet distractor
sets are considered adequate by both assessors. Their disagreements and complete
reasoning remain in the [first and teaching assessments](evidence/delivery-feedback-20260909/README.md).

Root's [post-unmask coordinate calculations](evidence/delivery-feedback-20260909/root-calculations.json)
confirm the six spreadsheet transformations. For q06, removing anchors from the
original formula before copying would produce `=C4*D3`, whereas the offered
unanchored distractor is `=A4*D1`. The feedback's drift explanation can be read as
the former counterfactual, but does not state that timing clearly. This is a
preserved judgment disagreement, not an independently established wrong key.
These checks calculate simple A1 coordinates; they do not execute Excel.

The ecology finding also needs qualification. The supplied OpenStax summary
describes a production ratio without specifying its measurement basis. The
underlying chapter discusses energy transfer and distinguishes energy from
standing biomass. [OpenStax, section 46.2](https://openstax.org/books/biology-2e/pages/46-2-energy-flow-through-ecosystems)
A research review explicitly allows production measurements in biomass, carbon
or energy units and discusses how the basis and food-web structure matter.
Thus biomass-based transfer efficiency is a legitimate convention; it is not
automatically invalid to use grams in such a problem.
[Mehner et al., 2022](https://link.springer.com/article/10.1007/s10021-022-00776-3)
Under a biomass-ratio convention q04 gives 75; under an energy-ratio convention,
the mass result also depends on relative energy contents per gram. This is our
inference from the definitions, not an empirical estimate of those contents.
The frozen conservative scores are unchanged, while the defensible intended
interpretation is preserved. This item cannot support a claim that the run
returned a definitely incorrect numerical answer.

## The format bottleneck is directly observed

All 13 author responses parsed, containing 62 raw question occurrences. The
runtime admitted 33 occurrences to verification; its other recorded author
rejections were 18 prompt-length failures, 10 invalid-content failures and one
duplicate-answer failure. These counters are structural/content-admission
categories, not independent factual judgments.

Seven of 16 completed downstream responses failed their strict JSON front end:
five solver responses, one reviewer response and one teaching-auditor response
(zero-based capture calls 5, 7, 14, 16, 18, 20 and 28). Each included explanatory
prose followed by fenced JSON. Existing parsing correctly preserved these as
format failures instead of treating them as a provider outage or silently
discarding surrounding statements. The exact responses and per-question
rejection metrics are retained in the [capture](evidence/delivery-feedback-20260909/capture.json)
and [operational audit](evidence/delivery-feedback-20260909/operational-audit.json).

None of the 29 calls exhausted its output budget: all ended with `end_turn`, and
the largest output was 2,201 of 6,000 tokens. No author JSON repair call occurred.
The complete run used 60,976 input and 33,507 output tokens. SDK intervals total
473.945472 seconds and isolated worker intervals total 491.233598 seconds;
these sums are recorded experiment intervals, not request latency percentiles.

The next useful comparison should qualify schema-constrained responses at every
model stage and then remeasure returned quality and coverage. That would address
the observed format failure directly. Bedrock documents schema-constrained
responses through Converse, while excluding string-length constraints from its
supported schema subset; local length and semantic checks therefore remain
necessary. [AWS structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
This experiment does not establish how
many additional questions would survive, or whether their content would be
correct. Recovering a JSON substring from arbitrary model prose is not a
correctness fix. Increasing the output limit is not supported by this run.
The separate native-output implementation in the shared checkout was excluded
from the frozen source; it was neither qualified nor deployed by this trial.

## Preservation, masking and reproducibility

Two fresh independent assistant assessors saw opaque shuffled IDs, original
goals/sources, stems and choices. Both first passes were frozen at
2026-09-10 04:51:25 UTC before either received feedback. Both teaching passes
were frozen at 04:54:25 UTC before arm/key unmasking. Teaching naturally reveals
an intended answer, so that phase is only partially masked. Neither assessment
is human expert calibration or evidence of learning gains. No root check
upgraded a disputed item into joint credit.

The [local delivery check](QUESTION_DELIVERY_LOCAL_CHECK.md) preserved all seven
returns through real bank preparation, atomic claim and idempotent replay using
test doubles, with no network or production storage. The original operation
batches then passed actual iOS decoding, whole-batch admission, Codable
persistence and feedback selection. All seven were retained; all 28 composed
selected-answer feedback displays matched the masked teaching packet exactly
despite choice reordering. A single targeted simulator test passed with no
failures or skips. This verifies local content delivery, not deployed scheduling,
UI layout, production bank state or learning outcomes.

The app fixture reconstructs the supported Goal fields from the original title,
current level, focus areas and sources. Its category uses the actual enum with
the test's custom-category fallback. Swift Goal has no separately assignable
`learningTarget`; the actual app derives that context from the reconstructed
goal. The raw backend fixture's explicit `learningTarget` is preserved in the
bank report but is not independently injected into the app. Thus the report's
shorthand "exact original goal/source context" must not be read as proof of
complete backend/client request-context equivalence. This qualifies that part
of the prospective delivery check; content preservation and the observed
seven-item app admission remain directly tested.

Preparation commit `6768a5a78bf3dfa4a322ce32760491d38ea08141` passed 1,007 backend
tests with no skips, focused Ruff, compilation and whitespace checks. Its 33
frozen source hashes match committed and current bytes. The separately committed
delivery helper (`1fd45a4`) passed four offline Python tests and two targeted
synthetic simulator controls before the exact-return test; its report binds
90 source files. No core runtime source changed between the frozen run and
exact replay, which passed with provider client creation forbidden.

All 29 calls have known usage, clean worker exits, confirmed cleanup and preserved
raw text. The plan's canonical SHA is
`bbebe7e13927aa06bc701bb3745ecc0d5beffea2c75d4b3f07261a9ccf090114`;
the capture's canonical SHA is
`0809bf2fe0e6b2e071845e487e008c6af2eb119d32311237bca3d58e746536e2`.
Byte hashes, complete artifacts and scope notes are in the
[evidence index](evidence/delivery-feedback-20260909/README.md).
No production default, deployment or adaptive-progression claim follows from
this selected comparison. The broader correctness and learning objective remains
unresolved.
