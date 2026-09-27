# TestFlight backend deploy bootstrap (review only)

The current TestFlight stack has no CloudFormation service role. On September 27,
2026, the account had no GitHub OIDC provider and the repository had no
`backend-testflight` environment. This repository contains a **candidate**
bootstrap template; nothing here creates an IAM role, GitHub environment, or
deployment by itself.

`testflight-deploy-bootstrap.yaml` creates a private, encrypted, versioned SAM
artifact bucket, the GitHub OIDC provider, and a deploy role whose trust subject
is exactly `repo:SamChou05/checkpoint:environment:backend-testflight`. Its
permissions cover the existing TestFlight stack, the SAM transform, the
artifact bucket's TestFlight prefix, and `iam:PassRole` for one supplied
CloudFormation execution role. It grants no direct Lambda, DynamoDB, Bedrock,
or IAM provisioning operations to the GitHub role. The provider is account-wide:
check for an existing provider before creating this stack, and import or reuse
it rather than creating a duplicate.

The separately reviewed **CloudFormation execution role** and Lambda
permissions boundary are defined in [TESTFLIGHT_EXECUTION_ROLE.md](TESTFLIGHT_EXECUTION_ROLE.md)
and `testflight-cfn-execution-role.yaml`. The role must exist in the same
account as the stack. The current stack has no service role; passing one with
`sam deploy --role-arn` attaches it to future stack operations. CloudFormation
does not support removing that association later, so review the execution-role
policy and this transition before applying it. The bootstrap does not create
the execution role automatically.

Read-only checks from this repository:

```bash
aws cloudformation validate-template \
  --region us-east-1 \
  --template-body file://infra/testflight-deploy-bootstrap.yaml \
  --query Description --output text
backend/bedrock-question-service/scripts/test-deployment-scripts.sh
```

Once an execution role has been reviewed, an operator can review the
CloudFormation change set for `testflight-deploy-bootstrap.yaml` with
`CAPABILITY_IAM`, create the bootstrap stack, and record its three outputs:
`DeployRoleArn`, `OidcProviderArn`, and `ArtifactBucketName`. This is an IAM and
S3 infrastructure change, separate from the backend release. Do not use the
backend `deploy-sam.sh` as a preview: it executes a change set automatically.

Create GitHub environment `backend-testflight` with **required reviewer(s)**,
**prevent self-review**, and a custom deployment branch policy allowing only
`main`. The reviewer ID is a deliberate owner choice. With an administrator's
GitHub CLI session, these commands show the intended API shape; inspect the
generated JSON and the resulting environment before adding credentials:

```bash
read -r -p 'GitHub required reviewer user ID: ' REVIEWER_ID
jq -n --argjson reviewer_id "$REVIEWER_ID" \
  '{wait_timer: 0, prevent_self_review: true,
    reviewers: [{type: "User", id: $reviewer_id}],
    deployment_branch_policy: {protected_branches: false,
                               custom_branch_policies: true}}' \
  | gh api --method PUT \
      repos/SamChou05/checkpoint/environments/backend-testflight --input -
gh api --method POST \
  repos/SamChou05/checkpoint/environments/backend-testflight/deployment-branch-policies \
  -f name=main -f type=branch
gh api repos/SamChou05/checkpoint/environments/backend-testflight
gh api repos/SamChou05/checkpoint/environments/backend-testflight/deployment-branch-policies
```

Use the GitHub environment settings UI or a secure secret-entry channel to set
`AWS_DEPLOY_ROLE_ARN` from the bootstrap output and the two private values
`CHECKPOINT_BACKEND_TOKEN` and `QUOTA_HASH_SECRET`. Do not store those values in
this repository, terminal history, workflow logs, or a parameter snapshot.
If rotating the app bearer, coordinate the TestFlight client configuration.

Set the environment variables `AWS_REGION=us-east-1`,
`SAM_STACK_NAME=checkpoint-question-service-testflight`,
`SAM_ARTIFACT_BUCKET` from the bootstrap output, and
`CLOUDFORMATION_EXECUTION_ROLE_ARN` to the reviewed service role, and
`LAMBDA_PERMISSIONS_BOUNDARY_ARN` to the role stack's boundary output. Copy the
three exact model/profile ARNs and their complete invoke-resource lists from
the current stack's **nonsecret** configuration:
`BEDROCK_MODEL_ARN`/`BEDROCK_INVOKE_RESOURCE_ARNS`,
`QUESTION_BANK_WORKER_MODEL_ARN`/`QUESTION_BANK_WORKER_INVOKE_RESOURCE_ARNS`,
and `BEDROCK_VERIFICATION_MODEL_ARN`/`BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS`.
Never use the workflow's worker-model fallback when preserving the deployed
worker model.

The five observed drift-prone values are `RESERVED_CONCURRENCY=2`,
`QUESTION_BANK_WORKER_RESERVED_CONCURRENCY=1`,
`QUESTION_BANK_MAX_RECEIVE_COUNT=5`, `BEDROCK_REASONING_EFFORT=none`, and
`MONTHLY_BEDROCK_BUDGET_USD=10`. The protected workflow now requires these
variables explicitly. After OIDC login, it compares them against only those
five live, nonsecret stack parameters and stops on a mismatch. The same check
can be run read-only from an authenticated shell:

```bash
DEPLOYMENT_ENVIRONMENT=testflight AWS_REGION=us-east-1 \
SAM_STACK_NAME=checkpoint-question-service-testflight \
RESERVED_CONCURRENCY=2 QUESTION_BANK_WORKER_RESERVED_CONCURRENCY=1 \
QUESTION_BANK_MAX_RECEIVE_COUNT=5 BEDROCK_REASONING_EFFORT=none \
MONTHLY_BEDROCK_BUDGET_USD=10 \
backend/bedrock-question-service/scripts/check-testflight-live-settings.sh
```

These five values were the known fallback differences on September 27, **not**
a complete parameter snapshot. Re-read all current nonsecret parameters and
review the full effective overrides and nonexecuting backend change set before
any release. Keep `BEDROCK_STRUCTURED_OUTPUT_MODE=legacy`, worker mode `inherit`
or `legacy`, prose authoring, array cardinality, reviewer-written feedback,
empty exact-goal hashes, and both mapped flags `disabled` until each route is
qualified. A completed identity bootstrap alone does not qualify quiz quality
or authorize a TestFlight rollout.

References: [AWS GitHub OIDC trust](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html),
[CloudFormation service-role persistence](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-iam-servicerole.html),
[CloudFormation SAM transform permissions](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/control-access-with-iam.html),
[GitHub environment protection](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments),
[GitHub environment API](https://docs.github.com/en/rest/deployments/environments), and
[deployment branch policies](https://docs.github.com/en/rest/deployments/branch-policies).
