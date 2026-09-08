# Policy-2 qualification with the worker's model settings

September 8, 2026. This prospective check uses the current runtime's complete-choice
solver and final reviewer, then requests one fresh five-question batch. Earlier
complete-choice experiments used single questions and Opus with adaptive thinking;
they do not qualify the deployed worker's Kimi/Sonnet settings or five-item output.

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
