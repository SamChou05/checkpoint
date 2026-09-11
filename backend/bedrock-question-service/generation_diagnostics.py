"""Bounded, content-free generation diagnostics shared by runtime and evals."""

from typing import Any

QUALITY_REASONS = {
    "sanitize": {
        "invalid_envelope",
        "invalid_allocation",
        "invalid_item",
        "invalid_skill",
        "skill_quota",
        "objective_quota",
        "prompt_length",
        "invalid_content",
        "invalid_complete_teaching",
        "duplicate_stem",
        "duplicate_answer",
        "invalid_choices",
        "duplicate_choices",
        "generic_content",
        "contradictory_explanation",
        "difficulty_floor",
        "difficulty_target",
        "accepted",
        "surplus",
    },
    "review": {
        "invalid_solution",
        "unsupported_solution",
        "solver_uncertain",
        "solver_zero_supported",
        "solver_multiple_supported",
        "solver_unresolved_limitations",
        "solver_outcome_mismatch",
        "invalid_choices",
        "invalid_json",
        "invalid_envelope",
        "invalid_index",
        "rejected_by_model",
        "answer_disagreement",
        "invalid_difficulty",
        "difficulty_floor",
        "difficulty_target",
        "invalid_feedback",
        "invalid_authored_review",
        "invalid_complete_teaching_review",
        "unsupported_authored_explanation",
        "uncertain_authored_explanation",
        "unsupported_main_explanation",
        "uncertain_main_explanation",
        "unsupported_choice_feedback",
        "uncertain_choice_feedback",
        "unsupported_feedback_display",
        "uncertain_feedback_display",
        "reported_issues",
        "answer_labels",
        "accepted",
    },
    "provider": {
        "output_truncated", "empty_output", "invalid_json", "request_failed",
        "native_incomplete", "native_contract_invalid", "native_request_invalid",
    },
}


def record_quality(
    metrics: dict[str, Any] | None, stage: str, reason: str, count: int = 1
) -> None:
    if metrics is None or count <= 0:
        return
    if reason not in QUALITY_REASONS.get(stage, set()):
        raise ValueError("Unknown quality diagnostic.")
    counts = metrics.setdefault("QuestionQuality", {}).setdefault(stage, {})
    counts[reason] = counts.get(reason, 0) + count


def quality_summary(metrics: dict[str, Any]) -> dict[str, dict[str, int]]:
    """Do not allow arbitrary provider strings or learner content into logs."""
    raw = metrics.get("QuestionQuality", {})
    if not isinstance(raw, dict):
        return {}
    return {
        stage: {
            reason: count
            for reason, count in raw_counts.items()
            if reason in reasons and type(count) is int and count > 0
        }
        for stage, reasons in QUALITY_REASONS.items()
        if isinstance(raw_counts := raw.get(stage), dict)
    }
