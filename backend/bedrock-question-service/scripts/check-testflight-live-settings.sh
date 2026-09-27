#!/usr/bin/env bash
# Read only five nonsecret parameters that previously differed from workflow defaults.
set -euo pipefail

[[ "${DEPLOYMENT_ENVIRONMENT:-}" == testflight ]] || {
  echo 'This comparison is only for TestFlight.' >&2
  exit 1
}

query="Stacks[0].Parameters[?ParameterKey=='ReservedConcurrency'||ParameterKey=='QuestionBankWorkerReservedConcurrency'||ParameterKey=='QuestionBankMaxReceiveCount'||ParameterKey=='BedrockReasoningEffort'||ParameterKey=='MonthlyBedrockBudgetUSD'].[ParameterKey,ParameterValue]"
rows="$(aws cloudformation describe-stacks \
  --region "$AWS_REGION" \
  --stack-name "$SAM_STACK_NAME" \
  --query "$query" \
  --output text)"

declare -A live_values=()
while IFS=$'\t' read -r key value; do
  [[ -z "$key" ]] && continue
  live_values["$key"]="$value"
done <<< "$rows"

expected=(
  'ReservedConcurrency:RESERVED_CONCURRENCY'
  'QuestionBankWorkerReservedConcurrency:QUESTION_BANK_WORKER_RESERVED_CONCURRENCY'
  'QuestionBankMaxReceiveCount:QUESTION_BANK_MAX_RECEIVE_COUNT'
  'BedrockReasoningEffort:BEDROCK_REASONING_EFFORT'
  'MonthlyBedrockBudgetUSD:MONTHLY_BEDROCK_BUDGET_USD'
)
for pair in "${expected[@]}"; do
  key="${pair%%:*}"
  variable="${pair#*:}"
  if [[ -z "${live_values[$key]+present}" ]]; then
    echo "Live stack is missing $key; review the stack before deploying." >&2
    exit 1
  fi
  if [[ "${live_values[$key]}" != "${!variable:-}" ]]; then
    echo "$variable differs from the live stack; review and set the protected variable before deploying." >&2
    exit 1
  fi
done

echo 'TestFlight operational variables match the five checked live stack parameters.'
