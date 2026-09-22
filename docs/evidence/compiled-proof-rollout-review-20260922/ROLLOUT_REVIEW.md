# Conditional compiled-proof worker rollout review

**This is a read-only deployment review, not rollout qualification or approval.**
The full-worker trial has now **failed**: 10/15 returned and two defective English
items released. Its original prerequisite is unmet, so the candidate below must
remain inactive. See [the frozen result](../compiled-proof-worker-qualification-20260922/RESULTS.md).
No deployment, invocation,
model call, configuration write, inventory action, or package download was made.
The project instruction explicitly says that landing improvements on main
“does not authorize deployment or destructive history rewriting.”

The five AWS reads at **2026-09-22 13:09:17 UTC** found the same September 11
TestFlight deployment as the earlier reviewer-release snapshot. The refreshed
[selected configuration](deployment-current.json) records exact function names,
selected nonsecret parameters/environment, runtime, package hashes, and source
pins. It uses the existing credential helper with its 15-second/32,768-byte
in-memory bound. AWS reads used connect 3 seconds, read 20 seconds, and one SDK
attempt. Only two function configurations and their CloudFormation identities
were read; guardrail identifiers/version values were never retained.

| Identity | Observed value |
| --- | --- |
| Stack / region | `checkpoint-question-service-testflight` / `us-east-1` |
| Stack status / last update | `UPDATE_COMPLETE` / `2026-09-11T15:35:21.693000+00:00` |
| API function | `checkpoint-question-servi-CheckpointQuestionFuncti-GwrpPtUv4A7u` |
| Worker function | `checkpoint-question-servi-QuestionBankWorkerFuncti-EIEsbeyLC1WU` |
| API / worker runtime | Python 3.12, x86_64, 256 MB; both `Active`, last update `Successful` |
| API / worker timeout | 30 / 240 seconds |
| API package SHA-256 (base64) | `YaJGqVgADEWGbtv6j1b96SYBmt8pAkcWaiYzgngMW/Y=` |
| Worker package SHA-256 (base64) | `Hh0yKkR0RJy9t5K78eZTk6e05diWNWPV86fJSve7Hyo=` |

The two code hashes exactly equal the prior snapshot. This refresh did not
repeat its package download/module comparison. It therefore does not claim a
new whole-package source reconstruction or identify every deployed module.

## Smallest parameter changes

Deploying the **current candidate code and template** is required; changing an
environment flag on the old package does not install the compiler, native
contracts, immutable audit, or policy-8 proof path. Relative to the observed
stack, these are the only five behavior overrides needed for the proposed
worker configuration:

| CloudFormation parameter | Workflow/deploy-script variable | Observed | Conditional candidate | Config-only rollback on new code |
| --- | --- | --- | --- | --- |
| `QuestionBankWorkerStructuredOutputMode` | `QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE` | Absent; worker inherits global `legacy` | `native` | `inherit` |
| `QuestionBankWorkerAuthorMode` | `QUESTION_BANK_WORKER_AUTHOR_MODE` | Absent; packaged prose path | `mixed_quantitative` | `inherit` |
| `QuestionBankWorkerFeedbackContract` | `QUESTION_BANK_WORKER_FEEDBACK_CONTRACT` | Absent; packaged `reviewer_written` | `authored_solution` | `reviewer_written` |
| `QuestionBankWorkerClaudeThinking` | `QUESTION_BANK_WORKER_CLAUDE_THINKING` | Absent; global `disabled` | `adaptive` | `inherit` |
| `QuestionBankWorkerReadTimeoutSeconds` | `QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS` | `75` | `100` | `75` |

The new `QuestionAuthorMode` parameter stays at its default `prose`. The new
skill-map model/resource override pair stays empty, preserving inheritance from
the unchanged Kimi worker model. No model ARN, invoke-resource list, global
thinking switch, global token cap, API transport, public policy floor, or new
schema needs changing. Do not run `deploy-sam.sh` as a preview: it invokes
`sam deploy --no-confirm-changeset` with every configured parameter. A reviewable
change set must explicitly preserve unrelated existing parameters and secrets;
the five-row table is a delta, not a complete deploy-script environment.

| Preserved parameter or runtime setting | Effective candidate |
| --- | --- |
| `BedrockModelArn` / `BedrockStructuredOutputMode` | Nova Lite foundation model / `legacy` on synchronous API |
| `QuestionBankWorkerModelArn` and its invoke resources | Existing Kimi K2.5 foundation-model ARN and exact resource |
| `SkillMapModelArn` / `SkillMapInvokeResourceArns` | Empty new override pair; API continues using Kimi and its resources |
| `BedrockVerificationModelArn` / resources | Existing Sonnet 4.6 US profile ARN and existing destination model ARNs |
| `BedrockMaxTokens` / `BedrockKimiThinking` | `6000` / `disabled` |
| `BedrockClaudeThinking` / `BedrockClaudeEffort` | Global `disabled` / `high`; only worker Claude changes to adaptive |
| `BedrockThinkingMaxTokens` | `16000`; selected for worker Sonnet adaptive calls, not Kimi author calls |
| Temperature / connect timeout | Existing packaged defaults `0.2` / 3 seconds; adaptive Sonnet omits sampling parameters |
| API feedback / read timeout | Existing `reviewer_written` / 20-second packaged default |
| `MaxProviderCallsPerRequest` / `GenerationAttempts` | `6` / `3` |
| Worker timeout / chunk / maximum batch | 240 seconds / `5` / `20` |
| `QuestionBankMaxReceiveCount` | Observed `5`, preserved; this is the SQS delivery boundary |
| `QuestionBankMaxFailedGenerationJobs` | Observed `3`, preserved |
| API / worker reserved concurrency | Existing parameter values `2` / `1`, preserved |
| `ServiceMode` / environment / fallback | `enabled` / `testflight` / empty |

The current `question_bank_common._max_provider_calls()` reads
`MAX_PROVIDER_CALLS_PER_REQUEST`; it no longer derives the durable Converse
allowance from the SQS delivery count. Thus the observed receive count of 5 does
not require a sixth override to obtain the candidate's six-call budget. The
current template's receive-count description still mentions a shared threshold;
the actual runtime and regression tests establish the separate boundaries.
The worker subtracts prior durable attempts before passing the remaining
allowance into generation. The conservative three-call pre-author minimum stays
in force even when a returned all-compiled batch ultimately needs only two calls.

## Equivalence and qualification limits

Guardrail identifier/version presence is **false** for both functions; all three
CloudFormation guardrail parameter-presence checks are also **false**. The frozen
trial specifies empty guardrail values. This is an observed absence match, not
permission to disable anything if a future refresh differs. No guardrail policy,
account-level permission, IAM effective policy, or protection configuration was
read or changed.

The trial uses bare Kimi model and Sonnet profile IDs; the deployment retains
the corresponding full foundation-model/profile ARNs. The configured names,
region and existing invoke-resource targets line up, but request strings are not
byte-identical and the trial's user credentials are not the Lambda execution
role. The current native allowlist recognizes these ARN forms. IAM/resource
parameters were read; effective IAM authorization was not independently tested.

The trial uses actual runtime stages and SDK deadline shrinking with a simulated
240-second worker context and fake durable reservations. It does not measure
Lambda cold starts, deployed memory/CPU, SQS delivery, real DynamoDB transactions,
concurrency, quotas across requests, or a complete asynchronous bank fill. Its
frozen requirement is at least 14/15 released questions, at least 4 per job,
compiled quotas, and independently sound released learner content. Even a pass
would not establish universal model semantic correctness or justify altering
those criteria. The current read ceiling is 100 seconds, not a guarantee that
every call or full job completes within the remaining deadline.

## Conditional validation and rollback sequence

1. Require the frozen full-worker trial and independent learner-content audit to
   pass their original criteria. Keep any timeout, rejected item, content defect
   and missing assessment in its original denominator. Otherwise stop before
   deployment; this document grants no exception or fallback approval.
2. Bind the candidate commit and all 26 packaged runtime modules to the reviewed
   source; retain the exact previously deployed artifacts/template and prior
   parameter values for rollback. A package hash alone is not a deployable backup.
   Retain authentication and quota secrets in the approved secret mechanism,
   never in this review or a parameter artifact.
3. Produce and review a change set for the candidate template with only the five
   intended worker behavior overrides and required code updates. Preserve the
   API/skill-map models and IAM scope, existing guardrail values, ServiceMode,
   concurrency, delivery limits and quota values. If the template proposes
   unrelated replacements or parameter changes, resolve those before execution.
   The parent owns the separate explicit deployment authorization. GitHub's
   `confirm_deploy` input and protected environment are execution controls, not
   authorization inferred from this investigation.
4. After an authorized deployment, read the selected environment/runtime/settings
   again, verify exact deployed module hashes and packaged SDK compatibility,
   and ensure the API remains legacy with Nova Lite and Kimi skill maps. Inspect
   only bounded redacted operational status. Do not treat a successful stack
   update as a semantic or asynchronous-worker test.
5. If separately authorized, run a bounded fresh asynchronous bank request/claim
   through the real worker. Check exact compiled five-field content with policy
   8, prose main plus empty choice feedback with policy 7, all correct-answer
   highlights after shuffle, content quality and the six-call/240-second limits.
   Record cold-start and durable-operation overhead separately from the local
   trial. Also check the synchronous API as a **legacy policy-2** diagnostic.
   The existing `run-deployment-smoke-test.sh` invokes the synchronous API with
   the smoke tool's default policy floor 4, so its automatic smoke is unsuitable
   for this intentionally split configuration. Keep `run_smoke_test=false` for
   that wrapper; an authorized API smoke must explicitly select minimum policy
   2, while the worker requires a separate asynchronous test. This is a concrete
   validation limitation, not a reason to make Nova Lite native.
6. On deployment/configuration failure or failed authorized post-deploy checks,
   use the retained prior artifact/template/parameter set for an exact rollback.
   Reverting only the five worker overrides restores legacy configuration on
   **new code**, not the old package; it is a distinct config-only fallback and
   must be assessed as such. Preserve stored questions, attempts, bank pointers,
   claim records and consumed Starter allowance; never mass-delete or retag
   inventory. Do not weaken verifier gates to recover yield. Recheck selected
   settings and service status after any authorized rollback.

## Client floor and inventory sequencing

Current main still has `QuestionVerificationPolicy.currentRevision = 2`.
New compiled 8 and prose 7 pass that freshness threshold without a wire/schema
change. Existing policy-2 inventory also remains eligible; a backend deployment
alone does not replace it, repair old stored answers, or update an installed app.
The explicit-key grading/highlighting fix and empty-feedback fallback are already
in source, but this review does not identify the binary installed on a device.

The separate future policy-4 client candidate is staged work, not current main.
Its earlier simulator evidence is recorded in
[the structural milestone](../question-reliability-release-20260922/STRUCTURAL_MILESTONE.md).
Backend acceptance/support must precede raising that client floor: the new
worker emits 7/8, while an old policy-2 worker cannot satisfy it. Freshness
thresholds do not imply cumulative capabilities; a numeric minimum is not a
request for exclusively compiled content.

The existing selector requires current verification for members and Starter
users. Claim requests send that same floor, and higher-floor replays must meet
it. A future bump changes member bank context because it contains the policy
number; the Starter context intentionally remains `starter` to avoid resetting
its entitlement. Obsolete cached questions stay stored and out of new practice,
with historical attempt snapshots unchanged. An unused Starter allowance may
receive verified replacements without retiring/deleting old inventory. Existing
attempts, `timesAsked`, retired history, or an active unfinished Starter run
continue to protect the consumed allowance. The
[cached-inventory evidence](../question-reliability-release-20260922/CACHED_INVENTORY.md)
records that tested behavior.

A normal higher-floor server claim can discard stale ready rows from eligibility
and request refill while retaining their stored content; do not replace this
with bulk deletion, relabeling, or an entitlement reset. Once a floor-4 client is
actually shipped, a rollback to policy-2-only generation would strand new
practice unless sufficient eligible inventory remains. Keep the floor-2 client
until the new worker is operationally verified and a separate client release
and rollback plan has been approved.

## Artifact provenance

- Snapshot SHA-256: `f2db14f3aaf1d132f33f74314ea1f1d74388279df5181cbb694f601b9b4f3b79`.
- Prior selected deployment snapshot SHA-256: `cd67fdc18205d72427edaddb389e7949ad0320d6ae1ea35a5317839a08d8f849`.
- Candidate commit at observation: `bf112a36a2814cc9058cbc7ef96e22dd4c4b8bca`.
- [Read-only script](read_deployment.py) and configuration source hashes are
  pinned in the snapshot. The script creates its output exclusively and does
  not overwrite it; rerunning it is not part of this review.
