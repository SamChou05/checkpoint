# Conditional Sonnet-constructor worker rollout review — draft

**FAILED / INACTIVE. The completed [full-worker trial](../constructed-sonnet-worker-qualification-20260922/RESULTS.md) returned 9/15 with zero numerical returns and failed its unchanged prospective criteria. This historical 100-second candidate cannot proceed. This document is neither deployment approval nor a change set.** No AWS reads/writes, provider calls, package downloads, deployment or inventory changes were performed for this review. `AGENTS.md` explicitly says landing improvements does not authorize deployment.

## Dated basis and source

The only AWS evidence used is the existing [selected snapshot](../compiled-proof-rollout-review-20260922/deployment-current.json), observed **2026-09-22 13:09:17 UTC**. It is not a fresh status check. Snapshot SHA-256: `f2db14f3aaf1d132f33f74314ea1f1d74388279df5181cbb694f601b9b4f3b79`.

- Stack/region: `checkpoint-question-service-testflight`, `us-east-1`; last observed `UPDATE_COMPLETE`, last updated September 11.
- API: `checkpoint-question-servi-CheckpointQuestionFuncti-GwrpPtUv4A7u`.
- Worker: `checkpoint-question-servi-QuestionBankWorkerFuncti-EIEsbeyLC1WU`.
- Observed API/worker: Python 3.12, x86_64, 256 MB, timeouts 30/240 seconds. These are dated observations, not current assertions.
- Candidate runtime: fixed source `0e4619f1696b848073f1a4d551c364ed3fbfbeb0`, present unchanged in integration main `7a38cc0`. The unsuccessful prose-task-explicitness addition is excluded.

## Exact conditional parameter delta

Install the candidate code/template as well as these overrides. Flags cannot add the new compiler/contracts to the old September package. The following **nine** values are the complete intended behavior/IAM delta relative to the selected snapshot; preserve all other existing parameters, secrets and resources. Every ARN below is copied verbatim from that snapshot, with Sonnet's existing verification resources reused for the author role.

```json
{
  "QuestionBankWorkerModelArn": "arn:aws:bedrock:us-east-1:239342516379:inference-profile/us.anthropic.claude-sonnet-4-6",
  "QuestionBankWorkerInvokeResourceArns": "arn:aws:bedrock:us-east-1:239342516379:inference-profile/us.anthropic.claude-sonnet-4-6,arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-6,arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-sonnet-4-6,arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-6",
  "SkillMapModelArn": "arn:aws:bedrock:us-east-1::foundation-model/moonshotai.kimi-k2.5",
  "SkillMapInvokeResourceArns": "arn:aws:bedrock:us-east-1::foundation-model/moonshotai.kimi-k2.5",
  "QuestionBankWorkerStructuredOutputMode": "native",
  "QuestionBankWorkerAuthorMode": "constructed_quantitative",
  "QuestionBankWorkerFeedbackContract": "authored_solution",
  "QuestionBankWorkerClaudeThinking": "adaptive",
  "QuestionBankWorkerReadTimeoutSeconds": "100"
}
```

| CloudFormation parameter | Deploy-script / GitHub environment variable | Previous effective value |
| --- | --- | --- |
| `QuestionBankWorkerModelArn` | `QUESTION_BANK_WORKER_MODEL_ARN` | Kimi foundation-model ARN above |
| `QuestionBankWorkerInvokeResourceArns` | `QUESTION_BANK_WORKER_INVOKE_RESOURCE_ARNS` | Exact Kimi resource above |
| `SkillMapModelArn` | `SKILL_MAP_MODEL_ARN` | Parameter absent; inherited worker Kimi |
| `SkillMapInvokeResourceArns` | `SKILL_MAP_INVOKE_RESOURCE_ARNS` | Parameter absent; inherited worker Kimi resources |
| `QuestionBankWorkerStructuredOutputMode` | `QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE` | `inherit`, effective global `legacy` |
| `QuestionBankWorkerAuthorMode` | `QUESTION_BANK_WORKER_AUTHOR_MODE` | `inherit`, effective `prose` |
| `QuestionBankWorkerFeedbackContract` | `QUESTION_BANK_WORKER_FEEDBACK_CONTRACT` | `reviewer_written` |
| `QuestionBankWorkerClaudeThinking` | `QUESTION_BANK_WORKER_CLAUDE_THINKING` | `inherit`, effective global `disabled` |
| `QuestionBankWorkerReadTimeoutSeconds` | `QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS` | `75` |

The skill-map pair is essential. `template.yaml:392` otherwise assigns the worker model to API `SKILL_MAP_MODEL_ID`, and `template.yaml:464` assigns the worker's invoke resources to that API role statement. Setting only the worker model/resources would silently move API skill-map planning to Sonnet. Both explicit Kimi overrides preserve its model **and** matching exact IAM resource. Validation requires the override pair together, includes its model ARN in resources, and rejects wildcards. Worker author IAM (`template.yaml:564`) and existing verifier IAM (`:568`) can use the same already observed Sonnet profile plus its three destination-model ARNs; no new ARN or wildcard is invented here. Effective IAM/account authorization was not independently tested.

The new author uses Sonnet 4.6 adaptive/high with 16,000 shared tokens and no sampling, because of existing model-specific runtime behavior. Solver and immutable auditor already use those settings. Global `BedrockMaxTokens=6000`, `BedrockThinkingMaxTokens=16000`, `BedrockClaudeThinking=disabled`, `BedrockClaudeEffort=high`, `BedrockKimiThinking=disabled` and packaged temperature 0.2 remain unchanged. The worker override alone enables Claude adaptive mode; it does not change Kimi skill-map behavior.

## Preserved settings and deployment wiring

Preserve the synchronous API Nova Lite model/resource, `BedrockStructuredOutputMode=legacy`, global `QuestionAuthorMode=prose` and default API `reviewer_written` feedback. Preserve the existing Sonnet verification model/resources, empty fallback, `ServiceMode=enabled`, TestFlight environment, authentication/quota secrets and all unlisted parameters. Keep provider budget 6, generation attempts 3, worker timeout 240 seconds, chunk size 5, maximum batch 20, SQS receive limit 5, failed-job limit 3, and API/worker reserved concurrency 2/1. Preserve `BedrockReasoningEffort=none`. The snapshot omits some parameters; do not fill them with guessed values.

The source wiring exists in `backend/bedrock-question-service/scripts/deploy-sam.sh:16–28,37,56` and `.github/workflows/deploy-backend.yml:95–115,135`. The workflow takes these from the selected GitHub environment's variables. Its fallback defaults are **not** a preservation mechanism: reserved concurrency defaults to 5/2 rather than observed 2/1; receive limit defaults to 6 rather than 5; reasoning effort defaults to `low` rather than `none`. A future complete deployment configuration must explicitly preserve the live values. This delta document is not a complete environment file.

Do not run `deploy-sam.sh` as a preview: it executes `sam deploy --no-confirm-changeset`. Workflow `confirm_deploy` and protected environments are execution controls, not authorization provided by this investigation. No change set was created here.

The dated snapshot records guardrail identifier/version presence as false on both functions, and all three guardrail parameter-presence checks as false. That matches the trial's empty guardrail configuration only at the time observed. No guardrail policy was inspected. If any future authorized refresh differs, resolve equivalence before deployment; this review never authorizes disabling a guardrail.

## Existing package/test support

The [construction verification manifest](../constructed-authoring-20260922/VERIFICATION.json) pins all **27 runtime modules**, requirements and SDK validator across the API, worker and outbox SAM artifacts. All 29 source-file hashes in that manifest were rechecked locally for this review and match the current candidate; no tests/build were repeated. It records 1,309 passing backend tests, passing SAM lint/build and fake deployment-script tests, 171 unchanged historical contract families and 172 packaged SDK shapes per artifact (516 total). The manifest SHA-256 is `16777294606a931ca4ad0a2b2371ba203c16eb46edad5a2d8c427c436c8f3551`.

The new [Sonnet-author trial plan](../constructed-sonnet-worker-qualification-20260922/PLAN.md) retains the actual worker stages and prospective 15-item denominator: at least 14 returned, at least 4 per job, required compiled quotas and independently sound released content. Offline harness tests do not qualify model behavior. A future passing local trial still does not measure Lambda cold start/memory/CPU, actual role authorization, SQS delivery, DynamoDB/durable-quota operations or concurrency. Trial requests use the bare Sonnet US profile ID; deployment uses the observed full ARN, so the strings and caller principals are not identical.

## Conditional validation and rollback

1. Require the new frozen trial, unchanged yield/compiler quotas and independent literal-task plus all learner-teaching review to pass. Preserve failures and missing assessments. Otherwise leave this candidate inactive.
2. Before a separately authorized deployment, obtain a bounded fresh configuration check and bind the candidate package to the manifest. Retain the exact previous package/template/parameter set for rollback; a Lambda code hash alone is not a deployable backup. Preserve secrets outside this evidence. Review the code update plus nine deltas and resolve unrelated changes before execution.
3. After authorization and deployment, verify selected API/worker/skill-map environment, runtime, packaged modules and exact IAM parameter scope. Check API Nova Lite legacy plus Kimi skill maps separately from worker Sonnet native/constructed/authored. A successful CloudFormation update does not establish semantic or asynchronous-worker correctness.
4. If separately authorized, validate a bounded fresh asynchronous bank fill/claim: actual six-call durable limit, 240-second deadline, chunk 5, compiler uptake, exact compiled five fields/policy 8, exact prose main plus empty feedback/policy 7, assignment/difficulty/content quality and client key/highlight preservation. Include real transport/queue/storage overhead and report incomplete yield, not just accepted schemas.
5. Check synchronous questions as a **legacy floor-2 diagnostic**, not as native-worker evidence. `run-deployment-smoke-test.sh` calls the synchronous API without a minimum-policy override, while `smoke_test_backend.py` defaults to policy 4. Therefore the wrapper's automatic smoke is unsuitable for this split configuration; keep workflow `run_smoke_test=false` and, only when separately authorized, use an explicit `--minimum-policy-revision 2` with the existing one-item smoke case. API skill-map preservation also needs its own authorized check. None of these requests was made here.
6. For a configuration-only rollback on the new code, restore the saved Kimi worker model/resources, worker structured/author/thinking overrides to `inherit`, feedback to `reviewer_written`, and read timeout to 75. The explicit Kimi skill-map pair may remain to preserve behavior, or both may return to empty inheritance once the worker is Kimi again. Apply compatible changes together. This restores earlier effective configuration on **new code**, not the old package. Exact software rollback uses the retained prior package/template/parameters. Recheck settings and service status after any authorized rollback; never weaken content gates to regain yield.

## Client and inventory boundary

Current main still uses client freshness floor 2, so policy 7/8 outputs need no client schema/floor change. Existing policy-2 inventory also remains eligible; a backend deployment does not repair or replace it or update an installed app. The [client highlighting audit](../constructed-authoring-20260922/CLIENT_HIGHLIGHTING_REVIEW.md) documents explicit-key/shuffle/empty-feedback behavior and its limitations.

The separately staged future floor-4 client is not part of this delta. Do not ship it, retag/delete questions, reset bank pointers/claims, alter historic attempt snapshots or reopen consumed Starter allowance here. Freshness numbers are thresholds, not cumulative optional capabilities. Any later floor transition must follow backend operational qualification and its own inventory/rollback plan; returning to policy-2-only generation after a floor-4 app release could strand new practice. Member context may change with a future floor, while the stable Starter context intentionally protects its entitlement. No inventory action is proposed or performed by this review.
