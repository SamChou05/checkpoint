# Solver output ordering improves a narrow failure, but does not establish correctness

The frozen September 10 comparison found fewer wrong choice verdicts when the
solver wrote each reason before its verdict. Among 30 scorable subject/repeat
pairs with validated responses in both arms, 22 were correct in both, six only
in `reason_first`, and two in neither. No available pair favored
`judgment_first`. The six improvements span four distinct subjects. Ten of the
40 planned pairs were unavailable: six had only a judgment-first response and
four had neither arm available. Both arms still
made a defective spreadsheet question eligible in both repetitions. This is
evidence for a useful ordering adjustment, not a complete correctness solution
or a production accuracy estimate.

## Execution and reproducibility

The [prospective protocol](QUESTION_SOLVER_ORDER_PROTOCOL.md),
[prepared plan](evidence/solver-order-preparation-20260910/prepared-plan.json),
subjects and independent control assessment were frozen before dispatch. The
plan's canonical SHA-256 is
`d2293b2ec2d290d3af72f6aa2459cd0cc866d8e35f5af816fbcd3a34add396e7`;
source revision is `41970660b089b1864f75ab6b62b3f17ce1567b05`.

AWS authentication was renewed. The single authorized execution produced 27
completed responses; request position 27 then hit `ReadTimeoutError` after
75.72 seconds. Its remote completion and usage remain unknown. Positions 28–31
were not attempted. Every local worker was reaped and its process-group cleanup
confirmed. There were no replacement calls, repairs, top-offs or reruns.

The raw [capture](evidence/solver-order-results-20260910/capture.json) preserves
all 32 planned requests, completed responses, the timeout and unattempted slots.
The offline [replay script](evidence/solver-order-results-20260910/replay.py)
reconstructs each dispatched request through the original provider adapter and
stage validator, forbids network connections, and reproduces every recorded
content observation exactly. It also checks source/plan binding and cleanup.
The original preparation document remains unchanged because its bytes are
bound to the plan; its old authentication status is superseded by this report.

Model/settings: `us.anthropic.claude-sonnet-4-6`, native Converse JSON schema,
thinking disabled, temperature 0.2, 6,000 maximum output tokens. Only the
choice-row order in the prompt example and corresponding schema properties
changed. This is a combined prompt/schema intervention; it does not isolate
their separate contributions or reveal internal reasoning.

All 27 completed responses ended with `end_turn`, using 316–1,792 output tokens.
Observed usage totals 49,330 input and 24,332 output tokens, excluding unknown
timeout usage. None of these completed semantic failures was caused by hitting
the 6,000-token output limit. That conclusion does not rule out a separate
benefit from enabling thinking, which this trial did not test.

## Availability and declared correctness

The subjects are 22 distinct questions: 20 scorable (14 uniquely valid, two with
multiple correct choices, four with none) and two materially ambiguous. Each arm
planned 44 item responses, of which 40 are scorable. Repetition does not create
additional independent subjects.

| Measure | Judgment first | Reason first |
| --- | ---: | ---: |
| Planned calls | 16 | 16 |
| Completed calls | 14 | 13 |
| Native/adaptation failures among completed calls | 0 | 0 |
| Batch-format failures among completed calls | 0 | 1 |
| Timeout with unknown remote completion | 0 | 1 |
| Unattempted calls | 2 | 2 |
| Validated item responses / planned | 40 / 44 | 33 / 44 |
| Validated scorable responses / planned | 36 / 40 | 30 / 40 |
| Exact four-choice agreement / planned scorable responses | 27 / 40 | 28 / 40 |
| Exact agreement / available scorable responses | 27 / 36 | 28 / 30 |
| Correct individual choice verdicts / available rows | 135 / 144 | 118 / 120 |

Position 16, reason-first repetition two of historical call 1, returned one
636-character reason against the application's 600-character limit. The
unchanged validator rejected all five items in that batch. This was valid JSON
and a complete response, not output-token exhaustion. The overlong reason also
contained a substantive spreadsheet mistake. Its batch remains unavailable;
neither readable companions nor the invalid rationale receive semantic credit.

All observed choice rows followed their intended order: 160
`choice/judgment/reason` rows and 152 `choice/reason/judgment` rows. Those counts
include the 20 raw rows in the rejected batch, before validation. Anthropic
documents that schema property order controls structured output order, with
required fields before optional fields.
[Official documentation](https://platform.claude.com/docs/en/build-with-claude/structured-outputs#property-ordering)
(checked September 10, 2026).

| Scored response group | Judgment first exact / available / planned | Reason first exact / available / planned |
| --- | ---: | ---: |
| Historical | 19 / 28 / 28 | 22 / 24 / 28 |
| Fresh transfer controls | 8 / 8 / 12 | 6 / 6 / 12 |

Fresh English agreement, fictional badge rules and Python list-operation
controls were correct wherever available. The missing fresh repetitions limit
that evidence. These are basic transfer controls, not calibrated advanced
questions or an estimate for arbitrary user goals.

## Solver gate outcomes and individual cases

| Scored question class | Judgment first | Reason first |
| --- | ---: | ---: |
| Valid: eligible / available / planned | 21 / 26 / 28 | 21 / 21 / 28 |
| Valid: unnecessary semantic veto | 5 | 0 |
| Defective: falsely eligible / available / planned | 4 / 10 / 12 | 2 / 9 / 12 |
| Defective: semantic veto | 6 | 7 |

Eligibility means the unchanged solver gate accepted declared uniqueness and
agreement with the locally held author key. No reviewer, delivery stage or
complete production acceptance ran. A format failure is never counted as a
successful factual catch.

| Original case | Judgment first, repetitions 1 / 2 | Reason first, repetitions 1 / 2 |
| --- | --- | --- |
| Call 1/index 2: two-step copied formula | Wrong veto / wrong veto | Correct / unavailable batch |
| Call 9/index 2: copied variance formula | Correct / correct | Correct / correct |
| Call 12/index 0: original map distance | Correct / correct | Correct / correct |
| Call 27/index 2: plant-to-snail ratio | Wrong veto / wrong veto | Correct / correct |
| Call 4/index 1: unsupported third operand | False eligibility / false eligibility | False eligibility / false eligibility |

The additional false eligibilities in judgment-first are call 4/index 0 in both
repetitions: the solver labels a second working average formula as refuted even
while its reason explains that it works. Reason-first correctly retains both
supported choices and vetoes that defective item. The remaining valid-item veto
in judgment-first is call 27/index 1 in repetition two, where the reason correctly
calculates 625 but the verdict rejects it.

The unsupported-third-operand question remains the decisive broader failure.
Both arms explain reference anchoring but accept multiplication by an unstated
third factor. Better ordering does not make that interpretation correct.

## Independent rationale assessment

Two fresh independent assistant assessors evaluated all 73 validated responses
in opaque packets without arm, repeat, author key or expected judgments. Each
subject's available responses stayed with one assessor. They assessed the
reasons first, saved that assessment, then received the declared verdicts in a
separate packet and assessed consistency. Canonical presentation concealed the
original field order. The [assessment join](evidence/solver-order-results-20260910/assessed-results.json)
binds the original packet and assessment bytes, checks exact coverage and choice
identity, and only then joins results to the arms. These are independent
assistant assessments, not human-expert ground truth.

| Scorable responses | Judgment first | Reason first |
| --- | ---: | ---: |
| All four rationales correct / available / planned | 32 / 36 / 40 | 26 / 30 / 40 |
| Verdict–reason consistency / available / planned | 29 / 36 / 40 | 30 / 30 / 40 |
| Correct verdicts, correct rationales and consistent / available / planned | 25 / 36 / 40 | 26 / 30 / 40 |

All seven inconsistent responses are in judgment-first. Their reasons explicitly
conclude support while the associated verdict says refuted. Correct verdicts
alone would nevertheless overstate performance: both arms' two responses to the
circular-budget question correctly refute every choice, but include erroneous
extra claims about inputs or required anchors. Both arms' two extra-operand
responses have substantively false rationales supporting the wrong formula.

For the joint correctness criterion, the 30 available paired observations split
20 both-correct, six reason-first-only, zero judgment-first-only and four
neither-correct. Across all 20 distinct scored subjects, both repetitions were
available for 16 judgment-first subjects and ten reason-first subjects. Both
repetitions were jointly correct for ten and eight subjects respectively.
Missingness prevents treating the better conditional result as an unconditional
availability improvement.

The fresh assessor calls the extra-operand stem ambiguous rather than assigning
the frozen no-answer classification. Their written assessment explicitly agrees
that none of the offered choices answers the literal stem and rejects the
three-input repair. Preserve that classification difference; do not rewrite the
predeclared expectations or count it as support for the keyed formula.

The two predeclared ambiguous subjects remain unscored. The price-matrix subject
has three available responses and one unavailable; one available response
contains a false argument supporting "Only row 2". The shrimp-food-web subject
has all four responses but unresolved pathway/production assumptions. Their
individual gate outcomes remain descriptive in the archived join, without
forcing an accuracy label.

## Implementation decision

Do not promote this diagnostic as proof that the generalized pipeline is fixed.
Reason-before-verdict is a supported candidate adjustment for internal
contradictions. A full-workflow qualification must still inspect the displayed
question, all choices, keyed answer and final learner feedback together.

The separate source-instruction consistency fix, commit `8d35e4c` on
`codex/source-evidence-contract`, was deliberately excluded from this trial.
It resolves conflicting permissions for substantive study facts; it does not
add factual verification. There were no production prompt, gate or deployment
changes in this results milestone.

The next implementation work should consolidate demonstrated context and
instruction fixes, treat output order as an intentional contract, and address
the remaining unsupported-premise failure with a materially different check.
Repeating equivalent critics or adding another generic "check your work"
instruction is not supported by these results. Preserve the defect as an
evaluation case rather than introducing a spreadsheet-specific acceptance rule.
