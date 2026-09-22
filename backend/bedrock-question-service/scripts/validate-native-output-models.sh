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

  local -a required_models=()
  [[ "$global_mode" != native ]] || required_models+=(BEDROCK_MODEL_ARN)
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

validate_native_output_models
