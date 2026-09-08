# Independently solved answer construction: results

September 8, 2026 UTC. **Zero of four planned candidates produced an admissible
question.** Seven calls completed normally; six raw field-length violations
stopped the four cases before final review. Independent inspection of the
unchanged drafts also found the familiar incorrect all-pairs answer and an
underqualified photography diagnosis. The prototype is not being integrated
into production, and no deployment or model promotion occurred.

This closes the bounded trial in the [prospective protocol](QUESTION_SOLUTION_CONSTRUCTION_EXPERIMENT.md).
The original acceptance criteria, field limits, inputs and rejected outputs
remain unchanged. No repair, truncation, replacement, retry, further review call,
or native execution was performed. This is an unpaired feasibility observation,
not an accuracy comparison or a production error-rate estimate.

## Execution and length failures

The frozen plan used `us.anthropic.claude-opus-4-6-v1`, adaptive thinking with high
effort, 16,000 output tokens per call, one SDK attempt and a 100-second read
timeout. The maximum was fifteen calls: four for each fresh goal and three for
the fixed historical all-pairs stem. Actual dispatch was three task authors,
two solvers, two distractor authors and **zero reviewers**.

| Case | Calls made | Every raw field over its frozen limit | Result |
| --- | ---: | --- | --- |
| Photography and motion | 3 | Main explanation 423/420; correct-choice explanation 410/280 | Rejected before review |
| English modifier attribution | 1 | Stem 365/320; objective 149/140 | Rejected before solving |
| Lunar observations | 1 | Stem 721/320 | Rejected before solving |
| Historical all-pairs stem | 2 | Correct-choice explanation 307/280 | Rejected before review |

The operational audit measured all 29 bounded raw text fields, including fields
after each validator's first reported failure. These are character counts of
unchanged strings. The first rejection alone does not describe all defects.

All seven calls ended with `end_turn`. The largest output was 1,534 tokens,
well below the 16,000-token allowance. The observed rejection mechanism was
oversized individual fields, not exhaustion of the model's output-token budget.
Increasing that budget would not directly address these failures.

Known usage was 4,386 input and 5,936 output tokens, totaling 10,322. Requests
contained 19,024 UTF-8 input-text bytes. Recorded call intervals sum to 112.418
seconds; case intervals sum to 112.445 seconds, with the longest call at 25.720
seconds. Those are partial-pipeline observations, not production latency or a
separately timed end-to-end benchmark. Eight unused calls were not dispatched.
The capture's operational `completed` status does not mean construction succeeded.

## Independent inspection of the unchanged drafts

No question passed the constructor. To inspect the available content, two raw
MCQs were assembled solely for offline assessment from the unchanged task,
solver answer and three proposed distractors. Choice order was independently
shuffled. The other two cases supplied only their raw task; no choices, keys,
solutions or feedback were generated for them.

An independent assistant assessor received those displays, goals and sources
with keys, solver support, feedback and model difficulty hidden. Its assessment
was frozen before the feedback assessment began. It had prior familiarity with
the historical all-pairs stem; this is not a claim of a naive assessor or expert
consensus. The root assessor later read the capture and does not claim blindness.

| Case | Content finding | Challenge assessment |
| --- | --- | --- |
| Photography | Camera shake is the natural best-listed diagnosis, but the stem does not establish it as the primary cause or exclude changed focus/exposure. One air-vibration alternative is weak and expressly conflicts with the stationary-wall premise. | Level 2 for the intended interpretation; not a sound level-3 item |
| English writing, task only | The modifier attributes organization to the students, conflicting with the intended parent credit. The task has a substantive answer. This is a meaning mismatch, not necessarily a grammatically dangling modifier. | Provisional task estimate 2; final MCQ difficulty and alternatives unknown |
| Lunar observations, task only | Morning half-Moon evidence supports last quarter under the supplied approximate schedule. The blanket north/south left-right rule needs a viewing convention rather than treating disk orientation as invariant. | Provisional task estimate 2; final MCQ difficulty and alternatives unknown |
| All pairs | No offered choice supplies a warranted unconditional linear-time algorithm for explicitly enumerating all matching index pairs. The solver still chose the familiar hash-set answer. | Diagnosing the invalid question involves level-3 reasoning; this is not a usable question rating |

For the all-pairs counterexample, an array of `n` zeroes with target zero has
`n(n-1)/2` matching index pairs. Constant-time membership checks do not remove
the time needed to report that output. Recording one pair for each new zero
omits index pairs; enumerating every prior matching index incurs the output
cost. The stem also leaves index pairs versus distinct value pairs unspecified.
Substituting existence or distinct-value output changes the task. There was no
new negative-answer MCQ and no successful detection of this error by the pipeline.

Thus the blind assessment found zero fully sound items among the **two available
raw MCQs**. This is separate from the operational result of zero admissible
questions among **four planned cases**. The two task-only drafts cannot be scored
as correct or incorrect completed MCQs.

## Solver support and proposed teaching feedback

After the blind record froze, a second assistant reviewed both exact solver
answer/support records and all ten proposed feedback fields: two main
explanations, two correct-choice explanations and six distractor explanations.
The [field-by-field assessment](evidence/solution-construction-feedback-assessment-20260908.json)
preserves their exact text, source paths, hashes, limits and qualifications.
This was unblinded. The root's preliminary findings were shared before that
second record froze; it is not an independent replication or educator consensus.
The root agrees with the recorded conclusions, and no substantive disagreement
with the separately frozen blind assessment was recorded.

Neither solver supplied a fully supported answer/support record. Six of ten
proposed feedback fields contain clear material semantic defects; three have
supported cores with scope or detail qualifications, and one is supported without
qualification. These categories assess entire fields, not just whether their
associated choice is wrong. Three proposed feedback fields also exceed their
limits, overlapping the semantic findings rather than adding independent cases.

For photography, the solver and feedback assume unmentioned settings stayed
fixed and that removing the tripod actually caused shake. One distractor
explanation invents directional smearing and displaced detail that the stem
never reports, then uses those observations to exclude overexposure. The
stationary-wall observation rules out that wall's subject motion; it does not
establish every stronger causal claim in the feedback.

For all pairs, the key and main/correct-choice explanations repeat the false
output-inclusive linear-time claim. The nested-loop refutation is supported.
The comparison-sorting discussion needs its worst-case model and lower-bound
notation kept clear; the binary-search refutation is sound for the unsorted
input, but its hypothetical search-work bound must not be taught as a bound on
all index-pair output.

The other two cases have no proposed teaching text. **Final-review feedback is
unavailable for all four cases**; zero reviewed fields is not evidence of zero
reviewed errors. No proposed text was shortened, corrected or returned to a user.

## Interpretation and next work

Keeping an independently solved answer unchanged prevents a later distractor
author from replacing it. This run demonstrates why that guarantee is
insufficient: the solver itself supplied the wrong all-pairs answer and the
next call wrote an explanation defending it. The experiment does not establish
that another reviewer would accept or reject either draft, because none ran.

The two overlong stems contain avoidable introductory, instructional or repeated
background wording. Some lunar timing and orientation context matters, and any
shorter version would need its own checks. No shortened variant was generated
or counted. The photography and all-pairs stems already fit the limit, so their
semantic defects cannot be explained merely by those stems exceeding 320
characters. This trial does not establish that larger stems are either necessary
or sufficient for correctness.

The immediate decision is to retain this as an evaluation prototype. Do not
promote it, loosen the original criteria after observing the results, or treat
the length rejections as successful factual verification. A future candidate
needs both reliable bounded output and evidence that its answer follows from
the actual displayed task. Claims such as output complexity need explicit
counterexamples or computation where applicable; factual and causal claims need
adequate premises and inspected supporting evidence. Merely changing which
model call owns the key did not establish those properties here.

The separate production issue remains open: a solver can label a record
`resolved`, leave limitations empty and bury impossibility in its answer prose.
Existing typed-outcome, limitations and exact-rival-answer gates do not close
that semantic path. This trial supplies no release qualification for it, for
general question correctness, or for adaptive learning outcomes.

## Reproducibility

The [plan](evidence/solution-construction-plan-20260908.json) binds source
`9826a98d1355c898ee2c952bfbc4eb81b4f58c31`, Python 3.12.11 and boto3/botocore
1.43.89. Its canonical SHA-256 is
`b21c3b4981bcc86d53eb8e529ae183363b8c4506ef5d5cd7b799137f45a322f5`.
Execution used an isolated checkout of that exact source. Exact reconstruction
of the plan and dynamic requests passed; all 26 frozen source hashes matched.
The replay performs no provider or native call.

- [Exact terminal capture](evidence/solution-construction-capture-20260908.json)
- [Replayed results](evidence/solution-construction-replay-20260908.json)
- [Operational audit and every field measurement](evidence/solution-construction-operational-audit-20260908.json)
- [Blinded display packet](evidence/solution-construction-blind-packet-20260908.json)
- [Frozen independent content assessment](evidence/solution-construction-blind-assessment-20260908.json)
- [Subsequent unblinded support and feedback assessment](evidence/solution-construction-feedback-assessment-20260908.json)
- [Archive byte hashes](evidence/solution-construction-manifest-20260908.json)

Raw rejected values are preserved; no credentials or private reasoning text are
included. Replay and content hashes establish artifact consistency, not provider
authenticity, factual truth or learner outcomes.
