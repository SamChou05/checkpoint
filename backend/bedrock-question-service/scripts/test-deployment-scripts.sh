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
api_model=arn:aws:bedrock:us-east-1::foundation-model/moonshotai.kimi-k2.5
worker_model=arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-6
scope_hash=afad55f2475381992d1355945ef521da72d3170f06d6ea83670f07ee868c46f0
other_scope_hash=497824fdd8fd85389f03d435d44e44147260c9d600fca3538e0a515dacdb53e5
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
for checked_script in validate-deployment-config.sh deploy-sam.sh; do
  for timeout in 20 75 99.5 200; do
    rm -f "$sam_capture"
    env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" "QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS=$timeout" \
      "$script_dir/$checked_script"
    if [[ "$checked_script" == deploy-sam.sh ]]; then
      mapfile -d '' -t timeout_arguments < "$sam_capture"
      [[ " ${timeout_arguments[*]} " == *" QuestionBankWorkerReadTimeoutSeconds=$timeout "* ]] || \
        fail "worker read timeout $timeout was not forwarded exactly"
    fi
  done
  for timeout in 19.9 200.1 201 NaN inf -inf '' invalid; do
    rm -f "$sam_capture"
    if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" "QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS=$timeout" \
      "$script_dir/$checked_script" >"$test_directory/timeout-error" 2>&1; then
      fail "$checked_script accepted invalid worker read timeout $timeout"
    fi
    [[ ! -e "$sam_capture" ]] || fail "SAM ran for invalid worker read timeout"
    [[ "$(cat "$test_directory/timeout-error")" == *"QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS"* ]] || \
      fail "worker timeout rejection did not identify its setting"
  done
done

env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
  "${deployment_environment[@]}" \
  "$script_dir/deploy-sam.sh"
mapfile -d '' -t sam_arguments < "$sam_capture"
[[ "${#sam_arguments[@]}" -eq 71 ]] || \
  fail "SAM received ${#sam_arguments[@]} arguments instead of 71"
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
for setting in BedrockThinkingMaxTokens=16000 BedrockKimiThinking=disabled BedrockClaudeThinking=disabled QuestionBankWorkerClaudeThinking=inherit BedrockClaudeEffort=high BedrockStructuredOutputMode=legacy QuestionBankWorkerStructuredOutputMode=inherit QuestionAuthorMode=prose QuestionBankWorkerAuthorMode=inherit QuestionBankWorkerAuthorCardinalityContract=array QuestionBankWorkerFeedbackContract=reviewer_written QuestionBankWorkerTaskOnlyNumericalGoalSHA256= QuestionBankWorkerConstructedAuthorBatchSize=0 QuestionBankWorkerConstructedAuthorBatchGoalSHA256= QuestionBankWorkerMappedFixedFiveGoalSHA256= QuestionBankWorkerMappedFixedFiveScopeSHA256= QuestionBankWorkerMappedFixedFiveScopeMode=exact QuestionBankWorkerMappedAgreementTasks=disabled QuestionBankWorkerMappedQuantitativeFamilies=disabled; do
  [[ " ${sam_arguments[*]} " == *" $setting "* ]] || fail "reasoning setting $setting was not forwarded"
done

# The closed agreement flag and both exact hashes are worker-only. Each entry
# point accepts the complete configuration shape, and rejects partial scopes, bad values,
# inherited prerequisites, and fallback before any SAM invocation.
for checked_script in validate-deployment-config.sh deploy-sam.sh; do
  mapped_settings=(
    QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=native
    QUESTION_BANK_WORKER_AUTHOR_MODE=constructed_quantitative
    QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT=array
    QUESTION_BANK_WORKER_FEEDBACK_CONTRACT=authored_solution
    "QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_GOAL_SHA256=$scope_hash"
    "QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_SHA256=$other_scope_hash"
    QUESTION_BANK_WORKER_MAPPED_AGREEMENT_TASKS=enabled
  )
  env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" "${mapped_settings[@]}" \
    "$script_dir/$checked_script"
  env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" "${mapped_settings[@]}" \
    QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_MODE=refill_history \
    "$script_dir/$checked_script"
  if [[ "$checked_script" == deploy-sam.sh ]]; then
    mapfile -d '' -t mapped_arguments < "$sam_capture"
    for setting in "QuestionBankWorkerMappedFixedFiveGoalSHA256=$scope_hash" \
      "QuestionBankWorkerMappedFixedFiveScopeSHA256=$other_scope_hash" \
      QuestionBankWorkerMappedFixedFiveScopeMode=refill_history \
      QuestionBankWorkerMappedAgreementTasks=enabled \
      BedrockStructuredOutputMode=legacy QuestionAuthorMode=prose; do
      [[ " ${mapped_arguments[*]} " == *" $setting "* ]] || \
        fail "mapped agreement setting $setting was not forwarded"
    done
  fi
  for case_name in invalid_mode empty_mode invalid_scope_mode disabled_refill_scope missing_goal missing_scope malformed_goal malformed_scope \
    orphan_goal orphan_scope inherited_native legacy_worker prose_worker count_bound \
    reviewer_feedback fallback_model; do
    case_settings=("${mapped_settings[@]}")
    case "$case_name" in
      invalid_mode) case_settings+=(QUESTION_BANK_WORKER_MAPPED_AGREEMENT_TASKS=ENABLED) ;;
      empty_mode) case_settings+=(QUESTION_BANK_WORKER_MAPPED_AGREEMENT_TASKS=) ;;
      invalid_scope_mode) case_settings+=(QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_MODE=other) ;;
      disabled_refill_scope) case_settings+=(QUESTION_BANK_WORKER_MAPPED_AGREEMENT_TASKS=disabled QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_GOAL_SHA256= QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_SHA256= QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_MODE=refill_history) ;;
      missing_goal) case_settings+=(QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_GOAL_SHA256=) ;;
      missing_scope) case_settings+=(QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_SHA256=) ;;
      malformed_goal) case_settings+=(QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_GOAL_SHA256=BAD) ;;
      malformed_scope) case_settings+=(QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_SHA256=BAD) ;;
      orphan_goal) case_settings+=(QUESTION_BANK_WORKER_MAPPED_AGREEMENT_TASKS=disabled QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_SHA256=) ;;
      orphan_scope) case_settings+=(QUESTION_BANK_WORKER_MAPPED_AGREEMENT_TASKS=disabled QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_GOAL_SHA256=) ;;
      inherited_native) case_settings+=(QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=inherit) ;;
      legacy_worker) case_settings+=(QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=legacy) ;;
      prose_worker) case_settings+=(QUESTION_BANK_WORKER_AUTHOR_MODE=prose) ;;
      count_bound) case_settings+=(QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT=count_bound) ;;
      reviewer_feedback) case_settings+=(QUESTION_BANK_WORKER_FEEDBACK_CONTRACT=reviewer_written) ;;
      fallback_model) case_settings+=("BEDROCK_FALLBACK_MODEL_ARN=$worker_model" "BEDROCK_INVOKE_RESOURCE_ARNS=$api_model,$worker_model") ;;
    esac
    rm -f "$sam_capture"
    if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" "${case_settings[@]}" \
      "$script_dir/$checked_script" >"$test_directory/mapped-error" 2>&1; then
      fail "$checked_script accepted invalid mapped agreement case $case_name"
    fi
    [[ ! -e "$sam_capture" ]] || fail "SAM ran for invalid mapped agreement case $case_name"
  done
  family_settings=("${mapped_settings[@]}" QUESTION_BANK_WORKER_MAPPED_QUANTITATIVE_FAMILIES=enabled)
  env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" "${family_settings[@]}" \
    "$script_dir/$checked_script"
  if [[ "$checked_script" == deploy-sam.sh ]]; then
    mapfile -d '' -t family_arguments < "$sam_capture"
    [[ " ${family_arguments[*]} " == *" QuestionBankWorkerMappedQuantitativeFamilies=enabled "* ]] || \
      fail "mapped quantitative family setting was not forwarded"
  fi
  for case_name in invalid_mode empty_mode missing_agreement; do
    case_settings=("${family_settings[@]}")
    case "$case_name" in
      invalid_mode) case_settings+=(QUESTION_BANK_WORKER_MAPPED_QUANTITATIVE_FAMILIES=ENABLED) ;;
      empty_mode) case_settings+=(QUESTION_BANK_WORKER_MAPPED_QUANTITATIVE_FAMILIES=) ;;
      missing_agreement)
        case_settings+=(QUESTION_BANK_WORKER_MAPPED_AGREEMENT_TASKS=disabled
          QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_GOAL_SHA256=
          QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_SHA256=)
        ;;
    esac
    rm -f "$sam_capture"
    if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" "${case_settings[@]}" \
      "$script_dir/$checked_script" >"$test_directory/family-error" 2>&1; then
      fail "$checked_script accepted invalid mapped quantitative family case $case_name"
    fi
    [[ ! -e "$sam_capture" ]] || fail "SAM ran for invalid mapped quantitative family case $case_name"
  done
done

# Both deployment entry points reject malformed or incompatible exact-goal
# settings before any SAM invocation; only the explicit worker route may opt in.
for checked_script in validate-deployment-config.sh deploy-sam.sh; do
  env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" \
    QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=native \
    QUESTION_BANK_WORKER_AUTHOR_MODE=constructed_quantitative \
    QUESTION_BANK_WORKER_FEEDBACK_CONTRACT=authored_solution \
    "QUESTION_BANK_WORKER_TASK_ONLY_NUMERICAL_GOAL_SHA256=$scope_hash" \
    QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_SIZE=3 \
    "QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_GOAL_SHA256=$scope_hash" \
    "$script_dir/$checked_script"
  if [[ "$checked_script" == deploy-sam.sh ]]; then
    mapfile -d '' -t scope_arguments < "$sam_capture"
    for setting in "QuestionBankWorkerTaskOnlyNumericalGoalSHA256=$scope_hash" \
      QuestionBankWorkerConstructedAuthorBatchSize=3 \
      "QuestionBankWorkerConstructedAuthorBatchGoalSHA256=$scope_hash" \
      BedrockStructuredOutputMode=legacy QuestionAuthorMode=prose; do
      [[ " ${scope_arguments[*]} " == *" $setting "* ]] || fail "worker scope setting $setting was not forwarded"
    done
  fi
  for case_name in malformed_task malformed_batch missing_batch_scope orphan_batch_scope mismatched_scope \
    inherited_native legacy_worker prose_worker reviewer_feedback count_bound noninteger_batch \
    unqualified_batch oversized_batch; do
    case_settings=(
      QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=native
      QUESTION_BANK_WORKER_AUTHOR_MODE=constructed_quantitative
      QUESTION_BANK_WORKER_FEEDBACK_CONTRACT=authored_solution
      "QUESTION_BANK_WORKER_TASK_ONLY_NUMERICAL_GOAL_SHA256=$scope_hash"
      QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_SIZE=3
      "QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_GOAL_SHA256=$scope_hash"
    )
    case "$case_name" in
      malformed_task) case_settings+=(QUESTION_BANK_WORKER_TASK_ONLY_NUMERICAL_GOAL_SHA256=BAD) ;;
      malformed_batch) case_settings+=(QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_GOAL_SHA256=BAD) ;;
      missing_batch_scope) case_settings+=(QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_GOAL_SHA256=) ;;
      orphan_batch_scope) case_settings+=(QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_SIZE=0) ;;
      mismatched_scope) case_settings+=("QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_GOAL_SHA256=$other_scope_hash") ;;
      inherited_native) case_settings+=(QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=inherit) ;;
      legacy_worker) case_settings+=(QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=legacy) ;;
      prose_worker) case_settings+=(QUESTION_BANK_WORKER_AUTHOR_MODE=prose) ;;
      reviewer_feedback) case_settings+=(QUESTION_BANK_WORKER_FEEDBACK_CONTRACT=reviewer_written) ;;
      count_bound) case_settings+=(QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT=count_bound) ;;
      noninteger_batch) case_settings+=(QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_SIZE=3.5) ;;
      unqualified_batch) case_settings+=(QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_SIZE=2) ;;
      oversized_batch) case_settings+=(QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_SIZE=6) ;;
    esac
    rm -f "$sam_capture"
    if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" "${case_settings[@]}" \
      "$script_dir/$checked_script" >"$test_directory/scope-error" 2>&1; then
      fail "$checked_script accepted invalid worker scope case $case_name"
    fi
    [[ ! -e "$sam_capture" ]] || fail "SAM ran for invalid worker scope case $case_name"
  done
done
for argument in "${sam_arguments[@]:11}"; do
  [[ "$argument" == *=* && "$argument" != *'$'* ]] || \
    fail "unexpanded or malformed parameter override: $argument"
done

[[ " ${sam_arguments[*]} " == *" SkillMapModelArn= "* ]] || fail "skill-map model inheritance changed"
[[ " ${sam_arguments[*]} " == *" SkillMapInvokeResourceArns= "* ]] || fail "skill-map IAM inheritance changed"
skill_map_model=arn:aws:bedrock:us-east-1::foundation-model/moonshotai.kimi-k2.5
for checked_script in validate-deployment-config.sh deploy-sam.sh; do
  env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" "SKILL_MAP_MODEL_ARN=$skill_map_model" \
    "SKILL_MAP_INVOKE_RESOURCE_ARNS=$skill_map_model" "$script_dir/$checked_script"
  for invalid_pair in model_only resources_only missing_model wildcard question_wildcard model_wildcard empty_entry; do
    model="$skill_map_model" resources="$skill_map_model"
    case "$invalid_pair" in
      model_only) resources="" ;;
      resources_only) model="" ;;
      missing_model) resources="$worker_model" ;;
      wildcard) resources="$skill_map_model,*" ;;
      question_wildcard) resources="$skill_map_model,arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-?" ;;
      model_wildcard) model="arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-?"; resources="$model" ;;
      empty_entry) resources="$skill_map_model," ;;
    esac
    rm -f "$sam_capture"
    if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" "SKILL_MAP_MODEL_ARN=$model" \
      "SKILL_MAP_INVOKE_RESOURCE_ARNS=$resources" "$script_dir/$checked_script" >"$test_directory/skill-map-error" 2>&1; then
      fail "$checked_script accepted invalid skill-map configuration $invalid_pair"
    fi
    [[ ! -e "$sam_capture" ]] || fail "SAM ran for invalid skill-map configuration"
  done
  unsupported_skill=arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-lite-v1:0
  if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" BEDROCK_STRUCTURED_OUTPUT_MODE=native \
    "SKILL_MAP_MODEL_ARN=$unsupported_skill" "SKILL_MAP_INVOKE_RESOURCE_ARNS=$unsupported_skill" \
    "$script_dir/$checked_script" >"$test_directory/skill-map-native-error" 2>&1; then
    fail "$checked_script accepted unsupported native skill-map model"
  fi
  env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" "SKILL_MAP_MODEL_ARN=$skill_map_model" \
    "SKILL_MAP_INVOKE_RESOURCE_ARNS=$skill_map_model" "$script_dir/$checked_script"
  if [[ "$checked_script" == deploy-sam.sh ]]; then
    mapfile -d '' -t sam_arguments < "$sam_capture"
    [[ " ${sam_arguments[*]} " == *" SkillMapModelArn=$skill_map_model "* ]] || fail "skill-map model not forwarded"
    [[ " ${sam_arguments[*]} " == *" SkillMapInvokeResourceArns=$skill_map_model "* ]] || fail "skill-map IAM not forwarded"
    [[ " ${sam_arguments[*]} " == *" QuestionBankWorkerModelArn=$worker_model "* ]] || fail "skill-map override changed worker"
  fi
done

for global_mode in legacy native; do
  for worker_mode in inherit legacy native; do
    env -i "PATH=$PATH" "${deployment_environment[@]}" \
      "BEDROCK_STRUCTURED_OUTPUT_MODE=$global_mode" \
      "QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=$worker_mode" \
      "$script_dir/validate-deployment-config.sh"
    env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" "BEDROCK_STRUCTURED_OUTPUT_MODE=$global_mode" \
      "QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=$worker_mode" \
      "$script_dir/deploy-sam.sh"
    mapfile -d '' -t sam_arguments < "$sam_capture"
    [[ " ${sam_arguments[*]} " == *" BedrockStructuredOutputMode=$global_mode "* ]] || \
      fail "global output mode $global_mode was not forwarded"
    [[ " ${sam_arguments[*]} " == *" QuestionBankWorkerStructuredOutputMode=$worker_mode "* ]] || \
      fail "worker output mode $worker_mode was not forwarded"
  done
done

for global_author in prose mixed_quantitative; do
  for worker_author in inherit prose mixed_quantitative constructed_quantitative; do
    env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" BEDROCK_STRUCTURED_OUTPUT_MODE=native \
      "QUESTION_AUTHOR_MODE=$global_author" "QUESTION_BANK_WORKER_AUTHOR_MODE=$worker_author" \
      QUESTION_BANK_WORKER_FEEDBACK_CONTRACT=authored_solution \
      "$script_dir/deploy-sam.sh"
    mapfile -d '' -t sam_arguments < "$sam_capture"
    [[ " ${sam_arguments[*]} " == *" QuestionAuthorMode=$global_author "* ]] || fail "global author mode not forwarded"
    [[ " ${sam_arguments[*]} " == *" QuestionBankWorkerAuthorMode=$worker_author "* ]] || fail "worker author mode not forwarded"
  done
done
for checked_script in validate-deployment-config.sh deploy-sam.sh; do
  for author_variable in QUESTION_AUTHOR_MODE QUESTION_BANK_WORKER_AUTHOR_MODE; do
    rm -f "$sam_capture"
    if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" "$author_variable=mixed_quantitative" \
      "$script_dir/$checked_script" >"$test_directory/author-error" 2>&1; then
      fail "$checked_script accepted mixed authoring with legacy transport"
    fi
    [[ ! -e "$sam_capture" ]] || fail "SAM ran for incompatible author mode"
  done
done

for checked_script in validate-deployment-config.sh deploy-sam.sh; do
  rm -f "$sam_capture"
  if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" QUESTION_BANK_WORKER_AUTHOR_MODE=constructed_quantitative \
    QUESTION_BANK_WORKER_FEEDBACK_CONTRACT=authored_solution \
    "$script_dir/$checked_script" >"$test_directory/constructed-legacy-error" 2>&1; then
    fail "$checked_script accepted constructed authoring with legacy transport"
  fi
  [[ ! -e "$sam_capture" ]] || fail "SAM ran for constructed legacy transport"
  for invalid_feedback in reviewer_written invalid; do
    rm -f "$sam_capture"
    if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" BEDROCK_STRUCTURED_OUTPUT_MODE=legacy \
      QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=native QUESTION_BANK_WORKER_AUTHOR_MODE=constructed_quantitative \
      "QUESTION_BANK_WORKER_FEEDBACK_CONTRACT=$invalid_feedback" \
      "$script_dir/$checked_script" >"$test_directory/constructed-error" 2>&1; then
      fail "$checked_script accepted constructed authoring without immutable feedback"
    fi
    [[ ! -e "$sam_capture" ]] || fail "SAM ran for incompatible constructed feedback"
  done
  env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" BEDROCK_STRUCTURED_OUTPUT_MODE=legacy QUESTION_AUTHOR_MODE=prose \
    QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=native QUESTION_BANK_WORKER_AUTHOR_MODE=constructed_quantitative \
    QUESTION_BANK_WORKER_FEEDBACK_CONTRACT=authored_solution "$script_dir/$checked_script"
  if [[ "$checked_script" == deploy-sam.sh ]]; then
    mapfile -d '' -t sam_arguments < "$sam_capture"
    [[ " ${sam_arguments[*]} " == *" QuestionBankWorkerAuthorMode=constructed_quantitative "* ]] || fail "constructed worker mode not forwarded"
    [[ " ${sam_arguments[*]} " == *" BedrockStructuredOutputMode=legacy "* ]] || fail "constructed worker changed API transport"
    [[ " ${sam_arguments[*]} " == *" QuestionAuthorMode=prose "* ]] || fail "constructed worker changed API author"
  fi
done

for checked_script in validate-deployment-config.sh deploy-sam.sh; do
  for worker_mode in inherit legacy native; do
    rm -f "$sam_capture"
    if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" BEDROCK_STRUCTURED_OUTPUT_MODE=legacy \
      "QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=$worker_mode" \
      QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT=count_bound \
      "$script_dir/$checked_script" >"$test_directory/cardinality-error" 2>&1; then
      if [[ "$worker_mode" != native ]]; then
        fail "$checked_script accepted count-bound authoring with legacy worker transport"
      fi
    elif [[ "$worker_mode" == native ]]; then
      fail "$checked_script rejected count-bound authoring with native worker transport"
    fi
    if [[ "$worker_mode" != native ]]; then
      [[ ! -e "$sam_capture" ]] || fail "SAM ran for incompatible count-bound authoring"
      [[ "$(cat "$test_directory/cardinality-error")" == *"QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT"* ]] || \
        fail "count-bound rejection did not identify its setting"
    elif [[ "$checked_script" == deploy-sam.sh ]]; then
      mapfile -d '' -t cardinality_arguments < "$sam_capture"
      [[ " ${cardinality_arguments[*]} " == *" QuestionBankWorkerAuthorCardinalityContract=count_bound "* ]] || \
        fail "count-bound worker authoring was not forwarded"
      [[ " ${cardinality_arguments[*]} " == *" BedrockStructuredOutputMode=legacy "* ]] || \
        fail "count-bound worker authoring changed API transport"
    fi
  done
  env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" BEDROCK_STRUCTURED_OUTPUT_MODE=native \
    QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=inherit \
    QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT=count_bound \
    "$script_dir/$checked_script"
  for invalid_cardinality in invalid prose; do
    rm -f "$sam_capture"
    if env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=native \
      "QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT=$invalid_cardinality" \
      "$script_dir/$checked_script" >"$test_directory/cardinality-error" 2>&1; then
      fail "$checked_script accepted invalid worker author cardinality $invalid_cardinality"
    fi
    [[ ! -e "$sam_capture" ]] || fail "SAM ran for invalid worker author cardinality"
  done
done

for feedback in reviewer_written authored_solution; do
  for checked_script in validate-deployment-config.sh deploy-sam.sh; do
    env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" \
      BEDROCK_STRUCTURED_OUTPUT_MODE=legacy QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=native \
      QUESTION_AUTHOR_MODE=prose QUESTION_BANK_WORKER_AUTHOR_MODE=mixed_quantitative \
      QUESTION_BANK_WORKER_CLAUDE_THINKING=adaptive \
      "QUESTION_BANK_WORKER_FEEDBACK_CONTRACT=$feedback" "$script_dir/$checked_script"
  done
  mapfile -d '' -t sam_arguments < "$sam_capture"
  [[ " ${sam_arguments[*]} " == *" QuestionBankWorkerFeedbackContract=$feedback "* ]] || fail "worker feedback not forwarded"
  [[ " ${sam_arguments[*]} " == *" BedrockStructuredOutputMode=legacy "* ]] || fail "API transport changed"
  [[ " ${sam_arguments[*]} " == *" QuestionAuthorMode=prose "* ]] || fail "API author mode changed"
done

for global_thinking in disabled adaptive; do
  for worker_thinking in inherit disabled adaptive; do
    env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
      "${deployment_environment[@]}" "BEDROCK_CLAUDE_THINKING=$global_thinking" \
      "QUESTION_BANK_WORKER_CLAUDE_THINKING=$worker_thinking" \
      "$script_dir/deploy-sam.sh"
    mapfile -d '' -t sam_arguments < "$sam_capture"
    [[ " ${sam_arguments[*]} " == *" BedrockClaudeThinking=$global_thinking "* ]] || \
      fail "global thinking $global_thinking was not forwarded"
    [[ " ${sam_arguments[*]} " == *" QuestionBankWorkerClaudeThinking=$worker_thinking "* ]] || \
      fail "worker thinking $worker_thinking was not forwarded"
  done
done

for mode_variable in BEDROCK_STRUCTURED_OUTPUT_MODE QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE QUESTION_AUTHOR_MODE QUESTION_BANK_WORKER_AUTHOR_MODE QUESTION_BANK_WORKER_FEEDBACK_CONTRACT; do
  for checked_script in validate-deployment-config.sh deploy-sam.sh; do
    rm -f "$sam_capture"
    if invalid_mode_output="$(
      env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
        "${deployment_environment[@]}" "$mode_variable=invalid" \
        "$script_dir/$checked_script" 2>&1
    )"; then
      fail "$checked_script accepted invalid $mode_variable"
    fi
    [[ "$invalid_mode_output" == *"$mode_variable must be "* ]] || \
      fail "$checked_script did not identify invalid $mode_variable"
    [[ ! -e "$sam_capture" ]] || fail "SAM ran for invalid $mode_variable"
  done
done

unsupported_model=arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-lite-v1:0
for checked_script in validate-deployment-config.sh deploy-sam.sh; do
  # A legacy Nova API may coexist with a native Kimi/Sonnet worker.
  env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
    "${deployment_environment[@]}" \
    "BEDROCK_MODEL_ARN=$unsupported_model" \
    "BEDROCK_INVOKE_RESOURCE_ARNS=$unsupported_model" \
    BEDROCK_STRUCTURED_OUTPUT_MODE=legacy \
    QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=native \
    "$script_dir/$checked_script"
  for model_variable in BEDROCK_MODEL_ARN QUESTION_BANK_WORKER_MODEL_ARN BEDROCK_VERIFICATION_MODEL_ARN BEDROCK_FALLBACK_MODEL_ARN; do
    rm -f "$sam_capture"
    if unsupported_output="$(
      env -i "PATH=$test_bin:$PATH" "SAM_CAPTURE=$sam_capture" \
        "${deployment_environment[@]}" \
        "BEDROCK_INVOKE_RESOURCE_ARNS=$api_model,$unsupported_model" \
        "QUESTION_BANK_WORKER_INVOKE_RESOURCE_ARNS=$worker_model,$unsupported_model" \
        "BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS=$worker_model,$unsupported_model" \
        BEDROCK_STRUCTURED_OUTPUT_MODE=native \
        QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=inherit \
        "$model_variable=$unsupported_model" \
        "$script_dir/$checked_script" 2>&1
    )"; then
      fail "$checked_script accepted an unsupported native $model_variable"
    fi
    [[ "$unsupported_output" == *"$model_variable is outside the native structured-output support allowlist"* ]] || \
      fail "$checked_script did not identify unsupported $model_variable"
    [[ ! -e "$sam_capture" ]] || fail "SAM ran for unsupported native $model_variable"
  done
done

if fallback_output="$(
  env -i "PATH=$PATH" "${deployment_environment[@]}" \
    QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE=native \
    BEDROCK_FALLBACK_MODEL_ARN=arn:aws:bedrock:us-east-1::foundation-model/test.fallback \
    "$script_dir/validate-deployment-config.sh" 2>&1
)"; then
  fail "worker output override bypassed the fallback invoke allowlist"
fi
[[ "$fallback_output" == *"must include BEDROCK_FALLBACK_MODEL_ARN"* ]] || \
  fail "fallback allowlist rejection did not return its expected diagnostic"

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
