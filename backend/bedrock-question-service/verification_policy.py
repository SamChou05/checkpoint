"""Server policy provenance, separate from the existing client wire contract.

Revision 1 identifies the historical stem-only solver gate and final review.
Revision 2 requires complete-choice judgments, unique exact key agreement, and
final review. Neither certifies factual correctness. Missing revisions remain
legacy/unknown; reading or claiming inventory must never assign a new revision.
Revision 3 additionally identifies the opt-in authored worked-explanation audit;
the final reviewer cannot replace learner-facing teaching. It is not yet the
default generation contract or required claim minimum.
Revision 4 additionally identifies immutable complete teaching, including every
choice explanation and composed display. It is available only by explicit opt-in
and does not certify factual correctness.
"""

from typing import Any


VERIFICATION_VERSION = 1
LEGACY_VERIFICATION_POLICY_REVISION = 1
COMPLETE_CHOICE_VERIFICATION_POLICY_REVISION = 2
AUTHORED_SOLUTION_VERIFICATION_POLICY_REVISION = 3
COMPLETE_TEACHING_VERIFICATION_POLICY_REVISION = 4
MAX_SUPPORTED_VERIFICATION_POLICY_REVISION = COMPLETE_TEACHING_VERIFICATION_POLICY_REVISION
VERIFICATION_POLICY_REVISION = COMPLETE_CHOICE_VERIFICATION_POLICY_REVISION


def meets_verification_policy(question: dict[str, Any], minimum: int) -> bool:
    """Positive floors require typed provenance and complete-teaching continuity.

    Zero preserves legacy claims. Complete banks impose their own positive floor,
    so neither omitted claim settings nor damaged stored feedback bypass it.
    """
    if minimum == 0:
        return True
    wire_version = question.get("verificationVersion")
    revision = question.get("verificationPolicyRevision")
    if not (
        type(wire_version) is int
        and wire_version == VERIFICATION_VERSION
        and type(revision) is int
        and revision >= minimum
    ):
        return False
    if revision >= COMPLETE_TEACHING_VERIFICATION_POLICY_REVISION:
        # Match the complete client shape before ready/claim accounting. The
        # teaching freezer intentionally permits arbitrary non-content metadata.
        difficulty = question.get("difficulty")
        if (
            question.get("format") != "Multiple Choice"
            or type(difficulty) is not int
            or not 1 <= difficulty <= 5
        ):
            return False
        # Import at use time: the pure teaching contract shares request helpers,
        # which in turn import the bank facade. No trust is assigned by freezing.
        from complete_question_teaching import (
            CompleteTeachingFormatError,
            freeze_complete_question,
        )

        try:
            freeze_complete_question(question)
        except CompleteTeachingFormatError:
            return False
    return True
