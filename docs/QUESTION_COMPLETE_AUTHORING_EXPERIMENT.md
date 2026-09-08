# Fresh complete authoring with immutable audit

Prospective protocol, September 8, 2026 UTC. The previous
[five-case fixed-content audit](QUESTION_IMMUTABLE_REVIEW_FOLLOWUP_RESULTS.md)
retained three sound controls and rejected two defective items. Its application
veto blocked an all-pairs question even though the model approved it while
reporting a decisive objection. It did not establish that new complete teaching
items can be authored and survive independent solving and review.

This trial tests that missing construction step. One generic author writes the
stem, four choices, key, main explanation and four choice explanations together.
The current option-blind solver receives only the stem, topic, goal and sources.
Its existing typed-outcome, assumptions, limitations and exact-rival gates apply.
An eligible item then reaches the immutable auditor, which checks every existing
explanation and cannot replace learner content. Its input excludes the solver
record to avoid anchoring it to that result. Any reported issue, unsupported or
uncertain feedback, answer disagreement, or assessed difficulty below three
blocks eligibility. The known answer-only solver contradiction remains possible;
this trial is not a claimed fix for that semantic classification problem.

## Fixed scope before inference

The [fixture](../backend/bedrock-question-service/evals/fixtures/question_complete_authoring.json)
contains four fresh goals, each requesting one question at minimum difficulty 3:

| Goal | Supplied grounding | Intended challenge to assess independently |
| --- | --- | --- |
| CSS Grid placement | Short summary of a dated W3C Grid specification | Apply interacting declarations to a concrete layout |
| Conditional probability | Short summary from Penn State STAT 500 | Choose a relevant conditional population and reason from counts |
| English conditions and quantifier scope | No supplied documents | Distinguish a warranted conclusion from converse or scope errors |
| Dissolved solute and concentration | No supplied documents | Apply conservation across explicitly stated process steps |

No question, answer, distractor or exemplar is prescribed. The same goal and
source text are available to all three roles. External assessment criteria and
source provenance stay outside model prompts. The sources were selected and
checked before the trial; there is no automatic search, calculator, code
execution or native observer in this pipeline. A source summary is not proof
that generated claims follow from it.

The generic author contract retains the current 320-character stem, 140-character
choices, 420-character main explanation and 280-character per-choice explanation
limits. It gives shorter writing targets, prohibits truncation and requests
complete necessary conditions. It shares the runtime canonical negative-answer
guidance so valid negative conclusions are not automatically excluded by a new
wording convention. Every item must contain complete exact-choice-keyed feedback.
The author may select a narrower substantive application that fits; it may not
drop necessary premises. Topic-specific question schemas are not introduced.

## Dispatch and artifact contract

- Opus 4.6 with adaptive thinking at high effort, 16,000 output tokens per call.
- Four cases, one sequence each, at most three calls per case and twelve total.
- One SDK attempt, three-second connection timeout and 100-second read timeout.
- At most 32,000 input-text UTF-8 bytes per call and 384,000 over the trial.
- No retries, repairs, top-ups, replacement cases or capture resumption.

These are resource allowances, not a monetary ceiling or a whole-trial deadline.
The frozen plan records source revision, source/dependency hashes, settings,
fixture and exact initial author requests. Solver and auditor requests depend
on fresh output; frozen code reconstructs them from the unchanged validated
question and context. Exact requests and content bindings are persisted before
each dispatch. The prior solution hash binds the audit sequence without putting
the solver's answer into the audit prompt. No private reasoning is saved.

Malformed or oversized model content rejects that case without repair. A derived
request beyond the byte allowance receives a separate budget rejection before
dispatch. Solver or auditor vetoes and insufficient assessed challenge likewise
end that case. Other fixed goals continue. Provider, correlation or persistence
failure stops all later dispatch. Raw returned text, known usage, stop reasons,
elapsed call intervals and explicit failure stages remain recorded. Unknown
usage or unattempted stages are not invented.

A shared deterministic state machine drives next requests and independently
replays saved decisions. Accepted learner fields must match the authored fields
exactly, except for the auditor's difficulty rating. No verification stamp,
production inventory write, deployment or runtime model promotion is produced.

## Predeclared assessment and next decision

Report all four planned cases, every attempted role, raw field-limit violations,
code eligibility and all rejection reasons. Review each available raw draft even
if its next stage was skipped. After capture is terminal, independently inspect
keys for a unique warranted answer, all five teaching-feedback fields, meaningful
and distinct distractors, scope and actual cognitive difficulty. Keep factual
validity, parser eligibility, source support and challenge judgments separate.
Assessor familiarity and visibility of authored keys must be disclosed.

The four-case feasibility target requires one fully supported, bounded, useful
item per goal at independently assessed difficulty at least 3, with exact final
content preserved. A merely eligible item or an easy item does not meet that
target. Any failed or unattempted case remains in the denominator. A pass would
justify broader fresh sampling and integration design; it would not establish
arbitrary-goal correctness, production throughput, adaptive learning gains or
release readiness. A failure should identify the mechanism actually observed,
including repeated length loss, false agreement, missed feedback defects or
unwarranted difficulty ratings, before choosing another change.

## Frozen plan and local verification

The [exact plan](evidence/complete-authoring-plan-20260908.json) was prepared from clean detached source `d06a7bfdf08853b8644a00c6df2e0a8aa46726c9` before inference.

- Canonical plan SHA-256: `5605a3b97b0ad407bee7cac1aa9466a16fc090e9e666824903fa5179ff93f2de`.
- Archived file SHA-256: `c15d48b270b9c710a96123ba4da334dd25aaf79c28fe05153beba3291bb5626a`.
- Initial author request UTF-8 bytes: 5687, 5644, 4937, 4964.
- Runtime dependencies: `{"boto3": "1.43.89", "botocore": "1.43.89", "python": "3.12.11"}`.

The19focused author/runner tests and716-test backend suite pass, with one existing optional-runtime skip. Independent reviews checked the fixture, context isolation, dynamic bindings, budget rejection and malformed-output classification. Ruff and diff checks pass. The original clean-source plan reconstructs exactly; no provider calls have occurred at this freeze point.
