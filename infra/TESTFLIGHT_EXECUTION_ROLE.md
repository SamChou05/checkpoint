# TestFlight CloudFormation execution role (review only)

`testflight-cfn-execution-role.yaml` is a candidate for the **existing**
`checkpoint-question-service-testflight` backend stack. It creates one
CloudFormation service role and one managed permissions boundary for the three
SAM-generated Lambda roles. The service role trusts only
`cloudformation.amazonaws.com`. Its permissions cover the current SAM
transform: three Lambda functions and roles, two event source mappings, one
HTTP API and stage, two DynamoDB tables, three SQS queues, three log groups,
CloudWatch alarms, one SNS topic and optional email subscription, and an
optional Bedrock budget. The artifact read is limited to this stack's prefix
in the bucket created by `testflight-deploy-bootstrap.yaml`.

The backend SAM template now accepts `LambdaPermissionsBoundaryArn` and
attaches it to all three generated roles. The TestFlight deployment script
requires the matching `LAMBDA_PERMISSIONS_BOUNDARY_ARN` environment variable;
production and local deployments keep their existing default. The boundary
caps the roles to this stack's runtime logs, X-Ray, Bedrock model/profile and
guardrail resources, DynamoDB tables and stream, and SQS queues. The SAM role
policies remain narrower. In particular, the service role can edit those
roles' inline policies, but cannot remove their boundary or create a new
generated role without it.

## Review inputs and order

1. Read the current stack resource list and compare every physical name with
   the name prefixes in the template. The execution role intentionally does
   not include permission to manage arbitrary pre-existing resources.
2. Find `BackendApi`'s physical API ID and the active stage name. The
   read-only inventory currently shows API ID `6zhfbzrded` and stage
   `prod`. Pass both to the role template. This pins API Gateway changes to that API. An API
   replacement requires a separate role-policy update and change-set review.
3. Review the new role and boundary policy before creating anything. The
   role's fixed name gives its ARN the form
   `arn:aws:iam::<account>:role/checkpoint-question-service-testflight-cfn-execution`.
   That ARN can be supplied to the OIDC bootstrap before the role exists; IAM
   does not require a referenced `iam:PassRole` resource to exist when the
   policy is created. Create the OIDC bootstrap first to obtain its artifact
   bucket, then create this separate role stack with that bucket name and the
   API ID. The role stack requires `CAPABILITY_NAMED_IAM`.
4. **Before associating the service role with the existing stack**, an IAM
   administrator must attach the reviewed boundary to all three existing
   generated Lambda roles and verify `PermissionsBoundary.PermissionsBoundaryArn`
   on each with `iam:GetRole`. The live roles currently have no boundary.
   The first CloudFormation update cannot be relied on to attach the boundary
   before it can edit an inline role policy. This one-time IAM change may
   appear as drift until the SAM stack adds the matching boundary property.
5. Record `ExecutionRoleArn` and `LambdaPermissionsBoundaryArn` as the
   corresponding protected GitHub environment variables. Review a
   **nonexecuting** backend change set that adds the boundary property to the
   SAM roles and associates the service role with the stack. Association of a
   CloudFormation service role persists on future stack operations.

Read-only inventory examples:

```bash
aws cloudformation list-stack-resources \
  --region us-east-1 \
  --stack-name checkpoint-question-service-testflight \
  --query 'StackResourceSummaries[].[LogicalResourceId,ResourceType,PhysicalResourceId]'
aws cloudformation describe-stack-resource \
  --region us-east-1 \
  --stack-name checkpoint-question-service-testflight \
  --logical-resource-id BackendApi \
  --query 'StackResourceDetail.PhysicalResourceId' --output text
sam validate --lint --template-file infra/testflight-cfn-execution-role.yaml
sam validate --lint --template-file backend/bedrock-question-service/template.yaml
for role in \
  checkpoint-question-servi-CheckpointQuestionFunctio-mt7EPYsWN0xL \
  checkpoint-question-servi-QuestionBankWorkerFunctio-34CX62yjnFiS \
  checkpoint-question-servi-QuestionBankOutboxFunctio-ABdZuDngCdbU; do
  aws iam get-role --role-name "$role" \
    --query 'Role.[RoleName,PermissionsBoundary.PermissionsBoundaryArn]' \
    --output text
done
```

## Deliberate limits

The policy has no `apigateway:POST` on the regional `/apis` collection, so
it cannot replace the API. API Gateway's API ID is random and has no stack
name, which is why it is a required exact input. API routes and integrations
are limited to that same API ID, including SAM's in-place API reimport.
Lambda event source mapping
UUIDs are also random; the mapping actions use the documented
`lambda:FunctionArn` condition to limit them to the worker and outbox
functions. `logs:DescribeLogGroups` and `dynamodb:ListStreams` are read-only
actions whose APIs need account/region-wide resource scope.

CloudFormation truncated the live Lambda function and role names to its
64-character limit, and truncated the outbox failure queue name to its queue
limit. The policy uses those observed, stack-specific prefixes; it does not
assume that the full logical IDs appear in the physical names. A read-only
comparison against all current physical IDs confirmed that each intended ARN
pattern matches. Recheck this if CloudFormation replaces a resource or the
SAM-generated naming scheme changes.

AWS Budget operations require account-level `aws-portal` billing actions in
addition to permission on the budget ARN. That broad grant is **off by
default**. If a reviewed change set needs to change the optional budget, set
`EnableBudgetManagement=true` on the role stack for that operation, then
remove the opt-in after the backend update. The budget action itself remains
limited to this stack's ARN. SNS subscription operations are scoped to the
stack's topic ARN.

This is a static policy review, not proof that a live change set will succeed.
CloudFormation may call additional read or tagging APIs as AWS handlers
evolve, and a future SAM template may add resources or policies. When a
scoped permission causes `AccessDenied`, identify that exact API call from
CloudTrail and review the required policy change; do not replace a resource
scope with `*` as a blanket repair. The boundary allows Bedrock model and
profile ARN families across regions because the deployed model ARNs are
environment settings; each generated Lambda role's inline policy still names
the exact approved invoke resources.

CloudFormation's [service-role guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-iam-servicerole.html)
documents a trust policy for the CloudFormation service principal, but not a
stack ARN condition for ordinary stacks. Access to use this role must
therefore be controlled through `iam:PassRole` and stack-scoped
CloudFormation permissions on every caller. A principal that can update the
stack after the role is associated can cause CloudFormation to use it.

The SAM source still lists `dynamodb:TransactWriteItems` in two inline role
policies. AWS's current [transaction authorization
reference](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis-iam.html)
maps that API to the underlying `PutItem`, `UpdateItem`,
`ConditionCheckItem`, and `DeleteItem` IAM actions; it is not a separate
IAM action. The boundary includes every underlying action actually granted
by the current SAM policies. A transaction that starts using `DeleteItem`
will require a separately reviewed source-policy and boundary change.

The service role cannot remove a Lambda role's permissions boundary. Deleting
the entire backend stack or deliberately removing a generated role may
therefore require a separately reviewed administrator-led teardown. This is
intentional: ordinary TestFlight deployments must not be able to discard the
boundary while retaining permission to edit inline role policies.

References: [CloudFormation service-role least privilege](https://docs.aws.amazon.com/prescriptive-guidance/latest/least-privilege-cloudformation/service-roles-for-cloudformation.html),
[IAM permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html),
[Lambda authorization actions and `lambda:FunctionArn`](https://docs.aws.amazon.com/service-authorization/latest/reference/list_lambda.html),
[API Gateway V2 resource ARNs](https://docs.aws.amazon.com/service-authorization/latest/reference/list_apigatewayv2.html),
[SNS authorization](https://docs.aws.amazon.com/service-authorization/latest/reference/list_sns.html), and
[Budget authorization](https://docs.aws.amazon.com/service-authorization/latest/reference/list_budgets.html).
