#!/usr/bin/env bash

set -e -o pipefail

parameters=(
  "BackendToken=$CHECKPOINT_BACKEND_TOKEN"
  "QuotaHashSecret=$QUOTA_HASH_SECRET"
  "AllowUnauthenticatedBackend=false"
  "BedrockModelArn=$BEDROCK_MODEL_ARN"
  "BedrockInvokeResourceArns=$BEDROCK_INVOKE_RESOURCE_ARNS"
  "QuestionBankWorkerModelArn=$QUESTION_BANK_WORKER_MODEL_ARN"
  "QuestionBankWorkerInvokeResourceArns=$QUESTION_BANK_WORKER_INVOKE_RESOURCE_ARNS"
  "BedrockVerificationModelArn=$BEDROCK_VERIFICATION_MODEL_ARN"
  "BedrockVerificationInvokeResourceArns=$BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS"
  "BedrockFallbackModelArn=$BEDROCK_FALLBACK_MODEL_ARN"
  "BedrockReasoningEffort=$BEDROCK_REASONING_EFFORT"
  "BedrockGuardrailIdentifier=$BEDROCK_GUARDRAIL_IDENTIFIER"
  "BedrockGuardrailVersion=$BEDROCK_GUARDRAIL_VERSION"
  "BedrockGuardrailArn=$BEDROCK_GUARDRAIL_ARN"
  "MaxQuestionsPerBatch=$MAX_QUESTIONS_PER_BATCH"
  "BedrockMaxTokens=$BEDROCK_MAX_TOKENS"
  "GenerationAttempts=$GENERATION_ATTEMPTS"
  "MaxProviderCallsPerRequest=$MAX_PROVIDER_CALLS_PER_REQUEST"
  "MaxRequestBodyBytes=$MAX_REQUEST_BODY_BYTES"
  "MaxRequestsPerInstallPerDay=$MAX_REQUESTS_PER_INSTALL_PER_DAY"
  "MaxRequestsPerIPPerDay=$MAX_REQUESTS_PER_IP_PER_DAY"
  "RateLimitTTLSeconds=$RATE_LIMIT_TTL_SECONDS"
  "QuestionBankTTLSeconds=$QUESTION_BANK_TTL_SECONDS"
  "QuestionBankMaxReceiveCount=$QUESTION_BANK_MAX_RECEIVE_COUNT"
  "QuestionBankMaxFailedGenerationJobs=$QUESTION_BANK_MAX_FAILED_GENERATION_JOBS"
  "DeploymentEnvironment=$DEPLOYMENT_ENVIRONMENT"
  "ServiceMode=$SERVICE_MODE"
  "ServiceRetryAfterSeconds=$SERVICE_RETRY_AFTER_SECONDS"
  "ApiStageName=$API_STAGE_NAME"
  "ApiThrottleRateLimit=$API_THROTTLE_RATE_LIMIT"
  "ApiThrottleBurstLimit=$API_THROTTLE_BURST_LIMIT"
  "ReservedConcurrency=$RESERVED_CONCURRENCY"
  "QuestionBankWorkerReservedConcurrency=$QUESTION_BANK_WORKER_RESERVED_CONCURRENCY"
  "QuestionBankWorkerReadTimeoutSeconds=$QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS"
  "QuestionBankGenerationChunkSize=$QUESTION_BANK_GENERATION_CHUNK_SIZE"
  "LogRetentionDays=$LOG_RETENTION_DAYS"
  "AlertEmail=$ALERT_EMAIL"
  "BudgetAlertEmail=$BUDGET_ALERT_EMAIL"
  "MonthlyBedrockBudgetUSD=$MONTHLY_BEDROCK_BUDGET_USD"
)

sam deploy \
  --stack-name "$SAM_STACK_NAME" \
  --region "$AWS_REGION" \
  --resolve-s3 \
  --capabilities CAPABILITY_IAM \
  --no-confirm-changeset \
  --no-fail-on-empty-changeset \
  --parameter-overrides "${parameters[@]}"
