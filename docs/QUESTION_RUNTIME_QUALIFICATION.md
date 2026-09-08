# Policy-2 qualification with the worker's model settings

September 8, 2026. This prospective check uses the current runtime's complete-choice
solver and final reviewer, then requests one fresh five-question batch. Earlier
complete-choice experiments used single questions and Opus with adaptive thinking;
they do not qualify the deployed worker's Kimi/Sonnet settings or five-item output.

**Result:** the five fixed diagnostics received the intended admission decisions,
and a fresh five-question batch completed in one pass. Independent examination
nevertheless found a definite mathematical error in returned teaching, unsupported
claims and inflated difficulty ratings. Operational success did not establish
correctness or release readiness. No deployment followed.

The [read-only configuration check](evidence/runtime-worker-configuration-20260908.json)
confirmed Kimi K2.5 authoring, Sonnet 4.6 verification, disabled thinking, 6,000
output tokens, three generation attempts, a six-call allowance, a 75-second read
timeout and a 240-second worker limit. Temperature and connection timeout were
unset; the matching runtime defaults are 0.2 and three seconds. The experiment
uses the equivalent short model/profile IDs. Calls run locally against Bedrock,
without invoking the deployed API, queue or worker or modifying learner inventory.

## Frozen operations and assessment

1. Run the exact current `verify_questions(..., solver_contract="complete_choices")`
   on five predeclared questions. Two are valid: an observed-rate comparison and an
   ordinary insufficient-information answer. Three are invalid: an unsupported
   converse, inconsistent exhaustive counts and two independently correct choices.
   The solver receives all five; only runtime survivors reach final review. At
   most two calls are allowed. All-rejected output is not a successful full pipeline.
2. Run `_generate_sanitized_questions` on one fresh goal about probability and
   evidence in everyday decisions, requesting five questions at difficulty 3.
   Preserve normal runtime author repairs and top-offs within the six-call budget;
   do not substitute or resume the job after an operational failure.

The [fixture](../backend/bedrock-question-service/evals/fixtures/question_runtime_qualification.json)
contains exact diagnostic questions, predeclared per-choice grounds and the fresh
goal. Diagnostic answers and assessments are withheld from solver/reviewer input.
These simple controls test answer coverage and premise handling, not advanced
challenge or a production error rate. They contain no exam-specific instructions.
An [independent pre-call review](evidence/runtime-fixed-neutral-topic-assessment-20260908.json)
confirmed the answer counts. Before freezing, three topic labels were made neutral
so model-visible metadata would not announce the intended defect. The assessment
records those changes and its unchanged predecessor; no model response informed them.

The existing isolated observation worker provides exact request binding, sanitized
final response capture and bounded cleanup. Each operation has a 240-second local
inference window; each serialized request is capped at 32 KiB and one SDK attempt.
At most eight model calls can occur. Disk persistence and preflight are not hard
real-time, and local timeout does not establish remote cancellation or zero usage.
Exact dynamic requests are persisted before dispatch. A provider, capture or cleanup
failure stops later work even if the runtime preserves earlier accepted questions.
The injected transport retains a fixed 75-second read window. Its late-operation
admission is conservative: the deployed client factory can shorten that window
to fit remaining time. This is not an exact simulation of Lambda's final seconds.

Before examining the fresh author's keys or the runtime's verdicts, independently
assess every parseable raw candidate using its unchanged stem and choices. Then
assess retained main explanations and every choice explanation. Keep key accuracy,
distinct plausible distractors, factual teaching accuracy and actual difficulty
separate from valid JSON, output-token fit, response completion and inventory yield.
Execute or calculate exact self-contained examples where applicable. Model
agreement is not an external correctness certificate.

The result can establish a bounded operational observation and expose concrete
failures. It cannot establish release readiness, long-term adaptive learning,
production latency, or a general error-rate estimate. No release follows
automatically from a passing local run.

## Release boundary

The inspected TestFlight packages still use policy 1. The current client requires
policy 2 for fresh verified practice, so both backend functions and actual bank
claims must be qualified before that client ships. A synchronous release smoke
must assert policy metadata on every raw returned item before sanitization;
sanitization alone cannot prove that verification occurred. An asynchronous
ensure-to-claim release exercise remains separate work.

The observed daily allowance is 40 asynchronous model calls per install. Even at
perfect yield, filling the entire 80-question Pro target from empty takes at least
48 calls with five questions and three calls per pass. Initial practice can start
with a smaller batch. This quota observation must not be confused with model
incorrectness or treated as permission to raise spending limits.

## Recorded results

The frozen run at source `85b3e23cbbd90347eddae356e791a53825267d7a` made five
calls: two for the fixed batch, then author, solver and reviewer for the fresh
batch. All ended with `end_turn` and confirmed local cleanup. There were no
repairs, top-offs, retries or unknown usage. Total usage was **14,165 tokens**:
9,232 input and 4,933 output. The largest response used 1,234 of its 6,000 output
tokens. Individual SDK intervals ranged from 8.8 to 17.2 seconds. These are
observed call intervals, not a production latency guarantee.

The [exact capture](evidence/runtime-qualification-capture-20260908.json), SHA-256
`6b4e90c111164618d042fe7b920d15bf0bd878dbd4b1a397b8de694c95bb3c5d`, contains the
frozen fixture, actual requests, unmodified raw outputs, lifecycle observations
and runtime results. Plan SHA-256 is
`d29a5555e8b56ba2e79f8d32665ba46a3fd2de1b98160683d71f0d2c178916f4`.
[Independent replay and fixed-item audit](evidence/runtime-operational-fixed-audit-20260908.json)
confirmed the source/dependency bindings and reproduced every request and decision
with observer and provider creation disabled.

### Fixed questions

Both valid questions survived; the unsupported converse, contradictory counts
and two-answer question were excluded before final review. All 20 solver choice
judgments agreed with the predeclared answer-adequacy grounds. Final review saw
only the two legitimate survivors. This directly exercises five-item correlation,
vetoes and valid-negative retention under the worker's model settings.

Labels alone still hide qualifications. The jar's correctly refuted answer has
a reason ending in “uncertain” wording. Survey feedback calls an option directly
contradicted by the respondents' preferences, which additionally assumes those
respondents were eligible. The latter is a conditional overclaim, not a demonstrated
falsehood under ordinary survey conventions. Both retained keys and main
explanations were supported.

### Fresh questions and teaching

All five raw author candidates were assessed before their assessors saw authored
keys, feedback, model judgments or survival. Separate subsequent reviews assessed
all 25 final teaching fields without seeing the model's reviewer verdict or
difficulty labels. Stem and choice text survived unchanged; existing sanitization
reordered choices. These are independent assistant assessments, not a human panel
or calibrated psychometric study.

| Fresh item | Independent key assessment | Final teaching | Model / independent difficulty |
| --- | --- | --- | --- |
| Two hospitals and extreme birth proportions | Small hospital under a conventional common, independent sampling model; information-limit answer remains defensible without that unstated model | Overstates that no further information is needed | 3 / 2 |
| Rare-disease test | About 9%, confirmed by exact arithmetic | Wrong prevalence claim in the 50% distractor explanation; correct key and main calculation | 4 / 3 |
| Ice cream and drowning | Confounding is a plausible hypothesis; the offered “likely explains” conclusion is stronger than the stated association establishes | Treats possible confounding as a known explanation and asserts no direct causal link | 3 / 2 |
| Two marble draws | About 18%, confirmed by enumeration under ordinary independent uniform draws | All five fields sound under that conventional model | 4 / 3 |
| Customer satisfaction survey | Nonresponse is the best-listed concern about generalization, not proof the respondent statistic is wrong | Invents dissatisfied customers' lower response motivation and definite upward bias | 3 / 2 |

The clearest error is independent of disputed wording. With the test's 99%
sensitivity and 99% specificity, equal true and false positives require
`0.99p = 0.01(1-p)`, so prevalence must be **1%**. The solver said approximately
**50%**, and final review repeated that false statement in learner feedback.
At 50% prevalence the posterior would be 99%, not 50%. The original 1-in-1,000
question's correct answer remains approximately 9%.
[Exact arithmetic and stage records](evidence/runtime-fresh-feedback-calculation-20260908.json).
This was a shared reasoning mistake despite correct answer-key agreement.

The marble question alone had support for complete teaching at the requested
challenge, under its ordinary sampling convention. This does not establish a
one-in-five production success rate. The selected goal and familiar examples
do not represent arbitrary user goals, and novelty or actual learning gains were
not measured.

The evidence distinguishes missing qualifications from definite calculation
errors. More relevant premises could address the former; the latter already had
the necessary numbers. Output truncation held back none of these calls. This run
does **not** test whether enabling thinking would improve their correctness.
Further qualification must score every learner-facing explanation and preserve
possible-versus-established claims; model key agreement or complete inventory
alone cannot be the release criterion.

Evidence: [blind assessment A](evidence/runtime-fresh-blind-a-assessment-20260908.json),
[blind assessment B](evidence/runtime-fresh-blind-b-assessment-20260908.json),
[teaching assessment A](evidence/runtime-fresh-teaching-a-assessment-20260908.json),
[teaching assessment B](evidence/runtime-fresh-teaching-b-assessment-20260908.json),
and [independent native calculations](evidence/runtime-fresh-native-calculations-20260908.json).
Their exact input packets are archived alongside them. Full backend validation
passes **857 tests with no skips** in the live dependency environment. Source
provenance separately passes seven new iOS tests and 65 existing goal/bank tests.

Packet `content_sha256` binds compact, sorted UTF-8 JSON of the item ID, goal,
sources, exact stem and raw ordered choices. `teaching_sha256` binds the complete
`question` object in the teaching packet, including final choice order, key and
all feedback. These are recorded-content bindings, not proofs of factual truth.
