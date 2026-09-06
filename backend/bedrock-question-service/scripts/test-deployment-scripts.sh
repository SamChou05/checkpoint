#!/usr/bin/env bash
# Generated stub scripts intentionally defer their variable expansion.
# shellcheck disable=SC2016

set -e -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/checkpoint-deploy-scripts.XXXXXX")"
test_bin="$test_directory/bin"
mkdir -p "$test_bin"
trap 'rm -rf "$test_directory"' EXIT

fail() {
  echo "deployment script test failed: $*" >&2
  exit 1
}

backend_token=checkpoint-backend-token-at-least-32-characters
quota_secret=checkpoint-quota-secret-at-least-32-characters
api_model=arn:aws:bedrock:us-east-1::foundation-model/test.api-model
worker_model=arn:aws:bedrock:us-east-1::foundation-model/test.worker-model
deployment_environment=(
  "AWS_DEPLOY_ROLE_ARN=arn:aws:iam::123456789012:role/checkpoint-deploy"
  "AWS_REGION=us-east-1"
  "SAM_STACK_NAME=checkpoint-test"
  "CHECKPOINT_BACKEND_TOKEN=$backend_token"
  "QUOTA_HASH_SECRET=$quota_secret"
  "BEDROCK_MODEL_ARN=$api_model"
  "BEDROCK_INVOKE_RESOURCE_ARNS=$api_model"
  "QUESTION_BANK_WORKER_MODEL_ARN=$worker_model"
  "QUESTION_BANK_WORKER_INVOKE_RESOURCE_ARNS=$worker_model"
  "BEDROCK_VERIFICATION_MODEL_ARN=$worker_model"
  "BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS=$worker_model"
  "BEDROCK_FALLBACK_MODEL_ARN="
  "BEDROCK_REASONING_EFFORT=low"
  "BEDROCK_GUARDRAIL_IDENTIFIER="
  "BEDROCK_GUARDRAIL_VERSION="
  "BEDROCK_GUARDRAIL_ARN="
  "BEDROCK_MAX_TOKENS=6000"
  "GENERATION_ATTEMPTS=3"
  "MAX_PROVIDER_CALLS_PER_REQUEST=6"
  "MAX_REQUEST_BODY_BYTES=131072"
  "MAX_QUESTIONS_PER_BATCH=20"
  "MAX_REQUESTS_PER_INSTALL_PER_DAY=40"
  "MAX_REQUESTS_PER_IP_PER_DAY=400"
  "RATE_LIMIT_TTL_SECONDS=172800"
  "QUESTION_BANK_TTL_SECONDS=2592000"
  "QUESTION_BANK_MAX_RECEIVE_COUNT=5"
  "QUESTION_BANK_MAX_FAILED_GENERATION_JOBS=3"
  "DEPLOYMENT_ENVIRONMENT=testflight"
  "SERVICE_MODE=enabled"
  "SERVICE_RETRY_AFTER_SECONDS=300"
  "API_STAGE_NAME=prod"
  "API_THROTTLE_RATE_LIMIT=5"
  "API_THROTTLE_BURST_LIMIT=10"
  "RESERVED_CONCURRENCY=5"
  "QUESTION_BANK_WORKER_RESERVED_CONCURRENCY=2"
  "QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS=75"
  "QUESTION_BANK_GENERATION_CHUNK_SIZE=5"
  "LOG_RETENTION_DAYS=14"
  "ALERT_EMAIL="
  "BUDGET_ALERT_EMAIL="
  "MONTHLY_BEDROCK_BUDGET_USD=25"
)

env -i "PATH=$PATH" "${deployment_environment[@]}" \
  "$script_dir/validate-deployment-config.sh"

if missing_output="$(
  env -i "PATH=$PATH" \
    "$script_dir/validate-deployment-config.sh" 2>&1
)"; then
  fail "configuration without required values was accepted"
fi
[[ "$missing_output" == *"Missing required environment secrets or variables"* ]] || \
  fail "missing configuration did not return its expected diagnostic"

if production_output="$(
  env -i "PATH=$PATH" "${deployment_environment[@]}" \
    DEPLOYMENT_ENVIRONMENT=production \
    "$script_dir/validate-deployment-config.sh" 2>&1
)"; then
  fail "production configuration without a guardrail was accepted"
fi
[[ "$production_output" == *"Production requires a complete Bedrock Guardrail configuration"* ]] || \
  fail "production guardrail rejection did not return its expected diagnostic"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\0'\'' "$@" > "$SAM_CAPTURE"' \
  > "$test_bin/sam"
chmod 0755 "$test_bin/sam"

sam_capture="$test_directory/sam-arguments"
env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
  "${deployment_environment[@]}" \
  "$script_dir/deploy-sam.sh"
mapfile -d '' -t sam_arguments < "$sam_capture"
[[ "${#sam_arguments[@]}" -eq 50 ]] || \
  fail "SAM received ${#sam_arguments[@]} arguments instead of 50"
expected_prefix=(
  deploy
  --stack-name checkpoint-test
  --region us-east-1
  --resolve-s3
  --capabilities CAPABILITY_IAM
  --no-confirm-changeset
  --no-fail-on-empty-changeset
  --parameter-overrides
)
for index in "${!expected_prefix[@]}"; do
  [[ "${sam_arguments[$index]}" == "${expected_prefix[$index]}" ]] || \
    fail "unexpected SAM argument $index: ${sam_arguments[$index]}"
done
[[ " ${sam_arguments[*]} " == *" BackendToken=$backend_token "* ]] || \
  fail "backend token override was not forwarded"
[[ " ${sam_arguments[*]} " == *" BedrockModelArn=$api_model "* ]] || \
  fail "API model override was not forwarded"
[[ " ${sam_arguments[*]} " == *" QuestionBankWorkerModelArn=$worker_model "* ]] || \
  fail "worker model override was not forwarded"
[[ " ${sam_arguments[*]} " == *" QuestionBankMaxFailedGenerationJobs=3 "* ]] || \
  fail "bank failed-job ceiling override was not forwarded"
for argument in "${sam_arguments[@]:11}"; do
  [[ "$argument" == *=* && "$argument" != *'$'* ]] || \
    fail "unexpanded or malformed parameter override: $argument"
done

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "$AWS_STUB_OUTPUT"' \
  > "$test_bin/aws"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''endpoint=%s\ntoken=%s\n'\'' "$CHECKPOINT_SMOKE_ENDPOINT" "$CHECKPOINT_SMOKE_TOKEN" > "$PYTHON_CAPTURE"' \
  'printf '\''%s\0'\'' "$@" >> "$PYTHON_CAPTURE"' \
  > "$test_bin/python"
chmod 0755 "$test_bin/aws" "$test_bin/python"

python_capture="$test_directory/python-call"
smoke_output="$(
  env -i "PATH=$test_bin:$PATH" \
    "AWS_STUB_OUTPUT=https://checkpoint.example/v1/questions" \
    "PYTHON_CAPTURE=$python_capture" \
    "SAM_STACK_NAME=checkpoint-test" \
    "AWS_REGION=us-east-1" \
    "CHECKPOINT_BACKEND_TOKEN=$backend_token" \
    "$script_dir/run-deployment-smoke-test.sh"
)"
[[ "$smoke_output" == "::add-mask::https://checkpoint.example/v1/questions" ]] || \
  fail "smoke endpoint was not masked"
grep -Fqx 'endpoint=https://checkpoint.example/v1/questions' "$python_capture" || \
  fail "smoke endpoint was not passed to the checker"
grep -Fqx "token=$backend_token" "$python_capture" || \
  fail "smoke token was not passed to the checker"
grep -Fq 'smoke_test_backend.py' "$python_capture" || \
  fail "smoke checker was not invoked"

rm -f "$python_capture"
if invalid_endpoint_output="$(
  env -i "PATH=$test_bin:$PATH" \
    "AWS_STUB_OUTPUT=None" \
    "PYTHON_CAPTURE=$python_capture" \
    "SAM_STACK_NAME=checkpoint-test" \
    "AWS_REGION=us-east-1" \
    "CHECKPOINT_BACKEND_TOKEN=$backend_token" \
    "$script_dir/run-deployment-smoke-test.sh" 2>&1
)"; then
  fail "invalid CloudFormation endpoint was accepted"
fi
[[ "$invalid_endpoint_output" == *"did not return a valid QuestionEndpoint"* ]] || \
  fail "invalid endpoint did not return its expected diagnostic"
[[ ! -e "$python_capture" ]] || fail "smoke checker ran for an invalid endpoint"

echo "deployment script tests passed"
