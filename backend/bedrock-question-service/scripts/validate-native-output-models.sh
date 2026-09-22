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

validate_worker_read_timeout
validate_skill_map_override
validate_native_output_models
