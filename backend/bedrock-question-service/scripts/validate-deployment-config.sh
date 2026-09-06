#!/usr/bin/env bash

set -e -o pipefail

missing=()
[[ -n "$AWS_DEPLOY_ROLE_ARN" ]] || missing+=(AWS_DEPLOY_ROLE_ARN)
[[ -n "$AWS_REGION" ]] || missing+=(AWS_REGION)
[[ -n "$SAM_STACK_NAME" ]] || missing+=(SAM_STACK_NAME)
[[ -n "$CHECKPOINT_BACKEND_TOKEN" ]] || missing+=(CHECKPOINT_BACKEND_TOKEN)
[[ -n "$QUOTA_HASH_SECRET" ]] || missing+=(QUOTA_HASH_SECRET)
[[ -n "$BEDROCK_MODEL_ARN" ]] || missing+=(BEDROCK_MODEL_ARN)
[[ -n "$BEDROCK_INVOKE_RESOURCE_ARNS" ]] || missing+=(BEDROCK_INVOKE_RESOURCE_ARNS)
[[ -n "$QUESTION_BANK_WORKER_MODEL_ARN" ]] || missing+=(QUESTION_BANK_WORKER_MODEL_ARN)
[[ -n "$QUESTION_BANK_WORKER_INVOKE_RESOURCE_ARNS" ]] || missing+=(QUESTION_BANK_WORKER_INVOKE_RESOURCE_ARNS)
[[ -n "$BEDROCK_VERIFICATION_MODEL_ARN" ]] || missing+=(BEDROCK_VERIFICATION_MODEL_ARN)
[[ -n "$BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS" ]] || missing+=(BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS)
if (( ${#missing[@]} > 0 )); then
  printf 'Missing required environment secrets or variables: %s\n' "${missing[*]}" >&2
  exit 1
fi
if (( ${#CHECKPOINT_BACKEND_TOKEN} < 32 )); then
  echo "CHECKPOINT_BACKEND_TOKEN must contain at least 32 characters." >&2
  exit 1
fi
if (( ${#QUOTA_HASH_SECRET} < 32 )); then
  echo "QUOTA_HASH_SECRET must contain at least 32 characters." >&2
  exit 1
fi

validate_invoke_resources() {
  local resource_list="$1"
  local primary_model="$2"
  local check_fallback="${5:-true}"
  local resource_list_name="$3"
  local primary_model_name="$4"
  local primary_is_allowed=false
  local fallback_is_allowed=false
  local resource
  local -a resources

  IFS=',' read -r -a resources <<< "$resource_list"
  for resource in "${resources[@]}"; do
    resource="${resource#"${resource%%[![:space:]]*}"}"
    resource="${resource%"${resource##*[![:space:]]}"}"
    if [[ -z "$resource" || "$resource" == *'*'* || "$resource" != arn:*:bedrock:* ]]; then
      echo "Every $resource_list_name value must be a non-wildcard Bedrock ARN." >&2
      exit 1
    fi
    [[ "$resource" == "$primary_model" ]] && primary_is_allowed=true
    [[ -n "$BEDROCK_FALLBACK_MODEL_ARN" && "$resource" == "$BEDROCK_FALLBACK_MODEL_ARN" ]] && fallback_is_allowed=true
  done
  if [[ "$primary_is_allowed" != true ]]; then
    echo "$resource_list_name must include $primary_model_name." >&2
    exit 1
  fi
  if [[ "$check_fallback" == true && -n "$BEDROCK_FALLBACK_MODEL_ARN" && "$fallback_is_allowed" != true ]]; then
    echo "$resource_list_name must include BEDROCK_FALLBACK_MODEL_ARN." >&2
    exit 1
  fi
}

validate_invoke_resources \
  "$BEDROCK_INVOKE_RESOURCE_ARNS" \
  "$BEDROCK_MODEL_ARN" \
  BEDROCK_INVOKE_RESOURCE_ARNS \
  BEDROCK_MODEL_ARN
validate_invoke_resources \
  "$QUESTION_BANK_WORKER_INVOKE_RESOURCE_ARNS" \
  "$QUESTION_BANK_WORKER_MODEL_ARN" \
  QUESTION_BANK_WORKER_INVOKE_RESOURCE_ARNS \
  QUESTION_BANK_WORKER_MODEL_ARN
validate_invoke_resources \
  "$BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS" \
  "$BEDROCK_VERIFICATION_MODEL_ARN" \
  BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS \
  BEDROCK_VERIFICATION_MODEL_ARN false
case "$BEDROCK_REASONING_EFFORT" in
  none|low|medium|high|xhigh|max) ;;
  *)
    echo "BEDROCK_REASONING_EFFORT must be none, low, medium, high, xhigh, or max." >&2
    exit 1
    ;;
esac

guardrail_values=(
  "$BEDROCK_GUARDRAIL_IDENTIFIER"
  "$BEDROCK_GUARDRAIL_VERSION"
  "$BEDROCK_GUARDRAIL_ARN"
)
configured_guardrail_values=0
for value in "${guardrail_values[@]}"; do
  [[ -n "$value" ]] && ((configured_guardrail_values += 1))
done
if (( configured_guardrail_values != 0 && configured_guardrail_values != 3 )); then
  echo "Guardrail identifier, version, and ARN must be set together." >&2
  exit 1
fi
if [[ "$DEPLOYMENT_ENVIRONMENT" == production ]]; then
  if (( configured_guardrail_values != 3 )); then
    echo "Production requires a complete Bedrock Guardrail configuration." >&2
    exit 1
  fi
  [[ -n "$ALERT_EMAIL" ]] || missing+=(ALERT_EMAIL)
  [[ -n "$BUDGET_ALERT_EMAIL" ]] || missing+=(BUDGET_ALERT_EMAIL)
  [[ -n "$BEDROCK_VERIFICATION_MODEL_ARN" ]] || missing+=(BEDROCK_VERIFICATION_MODEL_ARN)
[[ -n "$BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS" ]] || missing+=(BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS)
if (( ${#missing[@]} > 0 )); then
    printf 'Production is missing required alert variables: %s\n' "${missing[*]}" >&2
    exit 1
  fi
fi
