#!/usr/bin/env bash
# Sourced by both deployment entry points. Keep this allowlist aligned with
# native_output_contracts.ensure_supported_model; unsupported models fail before
# CloudFormation can replace a working service with one that rejects requests.

validate_native_output_models() {
  local global_mode="${BEDROCK_STRUCTURED_OUTPUT_MODE:-legacy}"
  local worker_mode="${QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE:-inherit}"
  case "$global_mode" in
    legacy|native) ;;
    *) echo "BEDROCK_STRUCTURED_OUTPUT_MODE must be legacy or native." >&2; return 1 ;;
  esac
  case "$worker_mode" in
    inherit) worker_mode="$global_mode" ;;
    legacy|native) ;;
    *) echo "QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE must be inherit, legacy, or native." >&2; return 1 ;;
  esac

  case "${QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT:-array}" in
    array) ;;
    count_bound)
      if [[ "$worker_mode" != native ]]; then
        echo "QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT=count_bound requires native worker transport." >&2
        return 1
      fi
      ;;
    *) echo "QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT must be array or count_bound." >&2; return 1 ;;
  esac

  case "${QUESTION_BANK_WORKER_FEEDBACK_CONTRACT:-reviewer_written}" in
    reviewer_written|authored_solution) ;;
    *) echo "QUESTION_BANK_WORKER_FEEDBACK_CONTRACT must be reviewer_written or authored_solution." >&2; return 1 ;;
  esac

  local global_author="${QUESTION_AUTHOR_MODE:-prose}"
  local worker_author="${QUESTION_BANK_WORKER_AUTHOR_MODE:-inherit}"
  case "$global_author" in
    prose|mixed_quantitative) ;;
    *) echo "QUESTION_AUTHOR_MODE must be prose or mixed_quantitative." >&2; return 1 ;;
  esac
  case "$worker_author" in
    inherit) worker_author="$global_author" ;;
    prose|mixed_quantitative|constructed_quantitative) ;;
    *) echo "QUESTION_BANK_WORKER_AUTHOR_MODE must be inherit, prose, mixed_quantitative, or constructed_quantitative." >&2; return 1 ;;
  esac
  if [[ "$global_author" == mixed_quantitative && "$global_mode" != native ]] ||
     [[ "$worker_author" != prose && "$worker_mode" != native ]]; then
    echo "Mixed quantitative authoring requires native transport for each enabled function." >&2
    return 1
  fi

  if [[ "$worker_author" == constructed_quantitative && "${QUESTION_BANK_WORKER_FEEDBACK_CONTRACT:-reviewer_written}" != authored_solution ]]; then
    echo "Constructed quantitative authoring requires authored_solution worker feedback." >&2
    return 1
  fi

  # The API skill-map route has its own effective model, even when the worker
  # uses a different transport. Check that model whenever the API is native.
  local skill_map_model_variable=QUESTION_BANK_WORKER_MODEL_ARN
  [[ -z "${SKILL_MAP_MODEL_ARN:-}" ]] || skill_map_model_variable=SKILL_MAP_MODEL_ARN
  local -a required_models=()
  [[ "$global_mode" != native ]] || required_models+=(BEDROCK_MODEL_ARN "$skill_map_model_variable")
  [[ "$worker_mode" != native ]] || required_models+=(QUESTION_BANK_WORKER_MODEL_ARN)
  if [[ "$global_mode" == native || "$worker_mode" == native ]]; then
    required_models+=(BEDROCK_VERIFICATION_MODEL_ARN)
    [[ -z "${BEDROCK_FALLBACK_MODEL_ARN:-}" ]] || required_models+=(BEDROCK_FALLBACK_MODEL_ARN)
  fi
  local variable model
  for variable in "${required_models[@]}"; do
    model="${!variable}"
    case "${model,,}" in
      *moonshotai.kimi-k2.5*|*anthropic.claude-sonnet-4-6*) ;;
      *) echo "$variable is outside the native structured-output support allowlist." >&2; return 1 ;;
    esac
  done
}

validate_skill_map_override() {
  local model="${SKILL_MAP_MODEL_ARN:-}" resources="${SKILL_MAP_INVOKE_RESOURCE_ARNS:-}"
  [[ -n "$model" || -n "$resources" ]] || return 0
  if [[ -z "$model" || -z "$resources" || "$model" != arn:*:bedrock:* || "$model" == *'*'* || "$model" == *'?'* ]]; then
    echo "SKILL_MAP_MODEL_ARN and SKILL_MAP_INVOKE_RESOURCE_ARNS must be supplied together with an exact Bedrock model ARN." >&2
    return 1
  fi
  local resource matched=false
  local -a entries
  IFS=',' read -r -a entries <<< "$resources"
  if [[ "$resources" == ,* || "$resources" == *, || "$resources" == *,,* ]]; then
    echo "SKILL_MAP_INVOKE_RESOURCE_ARNS must contain nonempty exact Bedrock ARNs." >&2
    return 1
  fi
  for resource in "${entries[@]}"; do
    resource="${resource#"${resource%%[![:space:]]*}"}"
    resource="${resource%"${resource##*[![:space:]]}"}"
    if [[ -z "$resource" || "$resource" == *'*'* || "$resource" == *'?'* || "$resource" != arn:*:bedrock:* ]]; then
      echo "SKILL_MAP_INVOKE_RESOURCE_ARNS must contain nonempty exact Bedrock ARNs." >&2
      return 1
    fi
    [[ "$resource" != "$model" ]] || matched=true
  done
  if [[ "$matched" != true ]]; then
    echo "SKILL_MAP_INVOKE_RESOURCE_ARNS must include SKILL_MAP_MODEL_ARN." >&2
    return 1
  fi
}

validate_worker_read_timeout() {
  local timeout="${QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS-75}"
  # SAM Number and the runtime both accept fractional seconds. Reject nonfinite
  # and malformed values before either entry point can invoke SAM.
  if [[ ! "$timeout" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
     ! awk -v timeout="$timeout" 'BEGIN { exit !(timeout >= 20 && timeout <= 200) }'; then
    echo "QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS must be a finite number from 20 through 200." >&2
    return 1
  fi
}

validate_worker_exact_goal_scopes() {
  local task_goal="${QUESTION_BANK_WORKER_TASK_ONLY_NUMERICAL_GOAL_SHA256:-}"
  local batch_size="${QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_SIZE:-0}"
  local batch_goal="${QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_GOAL_SHA256:-}"
  local name digest
  for name in QUESTION_BANK_WORKER_TASK_ONLY_NUMERICAL_GOAL_SHA256 QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_GOAL_SHA256; do
    digest="${!name:-}"
    if [[ -n "$digest" && ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
      echo "$name must be an exact lowercase 64-character SHA-256 digest." >&2
      return 1
    fi
  done
  if [[ ! "$batch_size" =~ ^(0|3)$ ]]; then
    echo "QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_SIZE must be 0 or the trialed three-item cap 3." >&2
    return 1
  fi
  if [[ "$batch_size" == 0 && -n "$batch_goal" ]] ||
     [[ "$batch_size" != 0 && -z "$batch_goal" ]]; then
    echo "QUESTION_BANK_WORKER_CONSTRUCTED_AUTHOR_BATCH_SIZE and its exact GOAL_SHA256 must be enabled together." >&2
    return 1
  fi
  if [[ -n "$task_goal" || "$batch_size" != 0 ]]; then
    if [[ "${QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE:-inherit}" != native ||
          "${QUESTION_BANK_WORKER_AUTHOR_MODE:-inherit}" != constructed_quantitative ||
          "${QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT:-array}" != array ||
          "${QUESTION_BANK_WORKER_FEEDBACK_CONTRACT:-reviewer_written}" != authored_solution ]]; then
      echo "Worker exact-goal authoring requires explicit native constructed_quantitative array mode and authored_solution feedback." >&2
      return 1
    fi
  fi
  if [[ -n "$task_goal" && -n "$batch_goal" && "$task_goal" != "$batch_goal" ]]; then
    echo "Task-only and constructed-author batch goal SHA-256 values must match." >&2
    return 1
  fi
}

validate_worker_mapped_agreement() {
  local mode="${QUESTION_BANK_WORKER_MAPPED_AGREEMENT_TASKS-disabled}"
  local goal="${QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_GOAL_SHA256:-}"
  local scope="${QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_SHA256:-}"
  local scope_mode="${QUESTION_BANK_WORKER_MAPPED_FIXED_FIVE_SCOPE_MODE:-exact}"
  if [[ "$scope_mode" != exact && "$scope_mode" != refill_history ]]; then
    echo "Mapped agreement scope mode must be exact or refill_history." >&2
    return 1
  fi
  case "$mode" in
    disabled)
      if [[ -n "$goal" || -n "$scope" || "$scope_mode" != exact ]]; then
        echo "Disabled mapped agreement requires empty worker hashes and exact scope mode." >&2
        return 1
      fi
      ;;
    enabled)
      if [[ ! "$goal" =~ ^[0-9a-f]{64}$ || ! "$scope" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Mapped agreement requires exact lowercase worker goal and scope SHA-256 values." >&2
        return 1
      fi
      if [[ "${QUESTION_BANK_WORKER_STRUCTURED_OUTPUT_MODE:-inherit}" != native ||
            "${QUESTION_BANK_WORKER_AUTHOR_MODE:-inherit}" != constructed_quantitative ||
            "${QUESTION_BANK_WORKER_AUTHOR_CARDINALITY_CONTRACT:-array}" != array ||
            "${QUESTION_BANK_WORKER_FEEDBACK_CONTRACT:-reviewer_written}" != authored_solution ||
            -n "${BEDROCK_FALLBACK_MODEL_ARN:-}" ]]; then
        echo "Mapped agreement requires explicit native constructed_quantitative array worker mode, authored_solution feedback, and no fallback model." >&2
        return 1
      fi
      ;;
    *)
      echo "QUESTION_BANK_WORKER_MAPPED_AGREEMENT_TASKS must be enabled or disabled." >&2
      return 1
      ;;
  esac
}

validate_worker_mapped_quantitative_families() {
  local mode="${QUESTION_BANK_WORKER_MAPPED_QUANTITATIVE_FAMILIES-disabled}"
  case "$mode" in
    disabled) ;;
    enabled)
      if [[ "${QUESTION_BANK_WORKER_MAPPED_AGREEMENT_TASKS-disabled}" != enabled ]]; then
        echo "Mapped quantitative families require enabled worker mapped agreement." >&2
        return 1
      fi
      ;;
    *)
      echo "QUESTION_BANK_WORKER_MAPPED_QUANTITATIVE_FAMILIES must be enabled or disabled." >&2
      return 1
      ;;
  esac
}

validate_worker_read_timeout
validate_skill_map_override
validate_native_output_models
validate_worker_exact_goal_scopes
validate_worker_mapped_agreement
validate_worker_mapped_quantitative_families
