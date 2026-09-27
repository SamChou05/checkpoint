# TestFlight backend release readiness, September 27, 2026

This is a read-only release audit of `checkpoint-question-service-testflight` in
`us-east-1`, the GitHub deployment workflow, and repository revision `df03bfe`.
No stack, Lambda, IAM, GitHub environment, workflow run, or question inventory
was changed. No secret values or Lambda environment variables were retrieved for
this report.

## Observed state and release gap

- CloudFormation reported `UPDATE_COMPLETE`, last updated September 11 at
  15:35 UTC. The question API, bank worker, and outbox Lambda resources were
  last updated then. The worker code hash was
  `Hh0yKkR0RJy9t5K78eZTk6e05diWNWPV86fJSve7Hyo=`.
- The deployed global structured-output mode is `legacy`. The worker uses Kimi
  K2.5, the reviewer uses Sonnet 4.6, and the worker read ceiling is 75 seconds.
  The source improvements subsequently pushed to `main` are not in this package.
- [Deploy backend](../../../.github/workflows/deploy-backend.yml) is active but
  is triggered only by `workflow_dispatch`. The GitHub API reported zero runs of
  that workflow. A source push therefore cannot update TestFlight.
- With repository-admin access, the GitHub API reported zero repository
  environments, zero repository Actions secrets, and zero repository Actions
  variables. `backend-testflight` did not exist. The AWS account reported zero
  IAM OIDC providers, so the workflow's role-assumption step cannot yet work.
  A similarly named existing IAM role trusts Lambda, not GitHub Actions.

The protected environment needs these secrets: `AWS_DEPLOY_ROLE_ARN`,
`CHECKPOINT_BACKEND_TOKEN`, and `QUOTA_HASH_SECRET`. Its required variables are
`AWS_REGION`, `SAM_STACK_NAME`, `BEDROCK_MODEL_ARN`,
`BEDROCK_INVOKE_RESOURCE_ARNS`, `QUESTION_BANK_WORKER_MODEL_ARN`,
`QUESTION_BANK_WORKER_INVOKE_RESOURCE_ARNS`,
`BEDROCK_VERIFICATION_MODEL_ARN`, and
`BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS`. The workflow has fallbacks for the
worker model/resource variables, but taking them would move the worker from its
current independent model to the API model. Region, stack name, and the three
model/resource pairs can be derived from read-only stack metadata or parameters
without printing secret parameters. The OIDC deploy role and trust policy must
be created or independently identified; the Lambda execution role is not a
substitute. The app bearer and quota HMAC secrets must be supplied or rotated
through a secure channel. CloudFormation marks them `NoEcho`; the repository is
not a source for their values. Rotating the bearer requires coordinated client
configuration.

The deployment workflow also substitutes defaults for absent optional
variables. A comparison of every existing **nonsecret** stack parameter with
those defaults found five changes that a naive rollout would introduce:

| Variable | Live stack | Workflow fallback |
| --- | ---: | ---: |
| `RESERVED_CONCURRENCY` | 2 | 5 |
| `QUESTION_BANK_WORKER_RESERVED_CONCURRENCY` | 1 | 2 |
| `QUESTION_BANK_MAX_RECEIVE_COUNT` | 5 | 6 |
| `BEDROCK_REASONING_EFFORT` | `none` | `low` |
| `MONTHLY_BEDROCK_BUDGET_USD` | 10 | 25 |

Set these explicitly when preserving current behavior. Re-read the full
nonsecret parameter set immediately before staging; this snapshot is not a
complete parameter file. Existing model profiles and their destination-model
allowlists must be kept together. Never print secret parameters or a Lambda's
full environment while comparing configuration.

## Staged source release and verification

1. Pin one `main` commit and retain the deployed template, exact prior Lambda
   packages, complete parameter set, and private secret references for rollback.
   Compare the deployed artifacts with the candidate at the file-hash level;
   a Lambda code SHA alone is not a deployable backup.
2. Run the backend unit suite, Ruff, deployment-script tests, `sam validate
   --lint`, a container SAM build, and `scripts/validate-native-sdk.py` against
   each of the three built function directories. The local deployment-script
   suite passed in this audit; that alone does not verify the new package.
3. Configure a protected `backend-testflight` GitHub environment and an AWS
   OIDC provider plus a stack-scoped deployment role. Preserve the observed
   operational values above and keep unqualified settings disabled: global
   `legacy`, worker `inherit` or explicit `legacy`, prose authoring, array
   cardinality, reviewer-written feedback, empty exact-goal hashes, and both
   mapped flags `disabled`. This packages applicable general fixes but does not
   activate native structured output or establish semantic quiz reliability.
4. Stage a **nonexecuting** CloudFormation change set for that pinned artifact
   and exact parameter set. Review every code, IAM, configuration, and resource
   delta against the current stack; resolve unrelated drift before execution.
   `scripts/deploy-sam.sh` is not a preview command: it directly invokes
   `sam deploy --no-confirm-changeset`.
5. Once the required protected credentials and scoped role are in place,
   deploy through the protected workflow or a scoped manual role. Verify stack completion, all three Lambda code
   hashes and packaged modules, only selected nonsecret effective settings,
   model invoke permissions, and a bounded authenticated API and bank
   fill/claim smoke. Check the installed TestFlight client endpoint and policy
   floor before claiming a user-visible result. Monitor provider failures,
   content rejection, inventory fill, timeouts, and quota accounting.
6. If checks fail, restore the retained prior packages, template, and exact
   parameters; merely resetting feature flags on new code is not a software
   rollback. Verify the rollback's effective configuration and bank behavior.

The [deployment guide](../../../backend/bedrock-question-service/docs/DEPLOYMENT.md)
also documents manual `sam validate`, `sam build`, and `sam deploy --guided`, and
the repository provides `scripts/deploy-sam.sh` for an already configured
shell. No `samconfig.toml` exists. This is an alternative to the absent GitHub
environment, not a reason to skip the same package, parameter, changeset, and
smoke checks. The AWS CLI session used for this read-only audit identified as
the account root principal, so it is not an appropriate deployment identity.
