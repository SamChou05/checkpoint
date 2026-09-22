# Draft production-generation qualification harness

No plan is frozen and no provider calls have been made by this draft. Root must
review the final scoped audit, component evidence, source hashes, and proposed
bounds before freezing and executing. `--preflight` runs fake clients only;
`--freeze --candidate TEXT` creates an exclusive plan, and `--execute PLAN_SHA256`
requires its exact hash and an unused capture path. `--plan PATH` selects the plan.
Import never freezes, obtains credentials, or dispatches.

The selected service root is explicitly `/tmp/checkpoint-authored-feedback-scope`,
including all 26 service modules. Running this file from another directory cannot
silently select a different service. The six unchanged requests and gold rules
come from `../question-reliability-release-20260922/pipeline-plan-v2.json`: five
fresh questions each in arithmetic, Python, English usage, quantitative evidence,
fictional access rules, and physical quantities. Requests and history are copied
without changing their task or difficulty requirements.

Proposed stages are the actual production `authored_feedback` route: Kimi K2.5
author v2, thinking disabled, 6,000 tokens, temperature 0.2; Sonnet 4.6 solver v5,
adaptive/high, 16,000 tokens and no temperature; and the scoped Sonnet full audit v3,
using its exact runtime prompt/schema/settings, also adaptive/high at 16,000.
The shared schema registry covers counts 1–40; these requests use counts 1–5 as
the real sanitizer, solver, and ordinary top-ups reduce each current batch.
Freeze includes the complete original domain-source plan and its gold/adjudication
rules, unchanged six requests, all 120 exact stage schemas and system prompts,
initial author prompts, all 26 module hashes, requirements and SDK verifier,
harness/test/plan-document hashes, dependency versions, settings, budgets and
prospective criteria. Historical source criteria remain provenance; this plan's
prospective criteria explicitly separate raw-attempt failures from learner quality.

The proposed read ceiling is **100 seconds**, changed prospectively from the
older 75-second draft. Connect remains 3 seconds, SDK attempts 1, job context
240 seconds, local/durable-call-interface allowance 6 per job, and total ceiling
36. Every reservation is saved locally before dispatch through the runtime's
`DurableProviderCallReservation` interface. This evidence journal does not test
the deployed DynamoDB ledger, leases, SQS delivery, worker handler, or inventory
writes. The real client factory still shrinks timeouts and rechecks deadline
admission. Source defaults and production configuration are not changed.

The harness observes exact runtime prompts and all three schemas, including
trusted current author count, dense solver inputs, dense post-solver audit maps,
sanitized skill/objective assignments, and bounded keyless recent question
descriptors. Source IDs and exact five-field learner-content digests bind each
author item to its exact solver subject, audit input and any returned admission.
When identical authored teaching appears twice, pure sanitizer-prefix checks
identify which original row the real sanitizer admitted without rejecting the job.
The audit can reject
but cannot replace teaching. Every returned item must retain policy 5, the audit's
difficulty, and every learner string. Raw visible attempts and all untouched
author rows remain in evidence; private reasoning blocks, signatures, raw headers
and unrecognized provider metadata do not. Only whitelisted bounded numeric
usage/latency and safe request/status metadata are retained.

Execute exports credentials once using the AWS CLI process format, with a
15-second deadline and 32-KiB output cap, and supplies them directly to an in-memory
SDK session. No credential files or credential environment variables are written.
Exact exported credential values are redacted before provider error fields are
truncated or persisted. Credential/setup failures abort globally. The actual
client must use the pinned us-east-1 Bedrock endpoint and total SDK attempts 1.
Plan, runtime, harness, domain input, contracts, and configuration are rechecked
before and after dispatch and at completion. Drift aborts globally and makes the
capture ineligible for qualification credit. Capture creation is exclusive, so
the same plan cannot accidentally run twice into the same evidence file.

Provider timeouts, non-`end_turn` responses, and malformed model outputs are
recorded without imposing an extra harness stop: the actual production route
owns its budgeted retries, top-ups, partial returns, and termination within that
job. Then the next untouched fixed domain runs. Routine per-job deadline,
six-call exhaustion, and durable-quota refusal are per-job outcomes. Global abort
is reserved for source/hash/request configuration integrity, credential/SDK setup,
or an actual dispatch/account-budget violation. No harness retry or rescue is
added. This prospective policy replaces only the older unfrozen draft's stop
policy; it does not change criteria or results of earlier trials.

Previously audited partial work is counted only if the real runtime returns it;
an exception never manufactures an accepted result. Failed/unattempted jobs
remain in the thirty-item denominator. Empty or failed runs cannot pass the
all-attempts diagnostic. Every raw provider/output failure is reported separately
from returned learner quality: a handled failed top-up does not corrupt an
earlier untouched, fully verified admission. Provider errors retain bounded
error code/message, HTTP status, and request ID so compilation failures keep
their cause.

Primary criteria remain at least **3 admitted per domain and 27 of 30 overall**,
with independent correct adjudication of every admitted key, unique answer,
choice distinction, task/assignment fit, novelty, difficulty, main explanation,
and all four choice explanations. Uncertainty fails. Solver/audit reason-label
accuracy is a separate diagnostic and cannot substitute for learner correctness.
Structural checks never mark release qualification successful.

Offline preflight (fake clients only):

```bash
/tmp/checkpoint-reliability-20260921-venv/bin/python -B \
  docs/evidence/authored-feedback-worker-20260922/worker_pipeline_probe.py --preflight
```

The test fixtures intentionally synthesize approvals; they prove boundary and
accounting behavior, not educational accuracy. Freeze/execute interfaces are
present for root review; no real plan or capture has been created by this draft.
No deployment or learner-bank write interface is exposed.
