#!/usr/bin/env bash

set -e -o pipefail

endpoint="$(
  aws cloudformation describe-stacks \
    --stack-name "$SAM_STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='QuestionEndpoint'].OutputValue | [0]" \
    --output text
)"
if [[ "$endpoint" != https://* || "$endpoint" == None ]]; then
  echo "The deployed stack did not return a valid QuestionEndpoint." >&2
  exit 1
fi
echo "::add-mask::$endpoint"
CHECKPOINT_SMOKE_ENDPOINT="$endpoint" \
CHECKPOINT_SMOKE_TOKEN="$CHECKPOINT_BACKEND_TOKEN" \
  python smoke_test_backend.py \
    --case-id backyard_beekeeping_raw_goal \
    --target-count 1
